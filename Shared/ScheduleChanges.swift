import CryptoKit
import Foundation
import UserNotifications

/// Что поменялось в расписании: пару отменили, добавили, перенесли или сменили кабинет.
struct ScheduleChange: Codable, Identifiable, Equatable {
    enum Kind: String, Codable { case cancelled, added, changed }

    var id: UUID
    var kind: Kind
    var subject: String
    var startsAt: Date
    var endsAt: Date
    var room: String
    /// Для переноса и смены кабинета: как было.
    var previousStartsAt: Date?
    var previousRoom: String?
    var detectedAt: Date
    /// Уведомление об этом изменении уже отправлено.
    var notified: Bool

    func text(now: Date = .now) -> String {
        func when(_ date: Date) -> String {
            "\(RU.shortDay(date, now: now).lowercased(with: RU.locale)) в \(RU.time(date))"
        }
        let place = room.isEmpty ? "" : ", кабинет \(room)"
        switch kind {
        case .cancelled:
            return "Отменена: «\(subject)», \(when(startsAt))\(place)"
        case .added:
            return "Добавлена: «\(subject)», \(when(startsAt))\(place)"
        case .changed:
            var details: [String] = []
            if let before = previousStartsAt, before != startsAt {
                details.append("было \(when(before)), стало \(when(startsAt))")
            }
            if let before = previousRoom, before != room {
                details.append("кабинет \(before.isEmpty ? "—" : before) → \(room.isEmpty ? "—" : room)")
            }
            return "Изменена: «\(subject)»" + (details.isEmpty ? "" : " — " + details.joined(separator: "; "))
        }
    }
}

enum ScheduleDiff {
    /// Сколько дней вперёд сравниваем. Окно расписания скользит: дальний край каждый день «добавляет» пары.
    static let horizonDays = 13
    /// Отменённую и добавленную пару с тем же названием считаем переносом, если они не дальше друг от друга.
    static let moveWindow: TimeInterval = 7 * 24 * 60 * 60

    /// Похоже ли новое расписание на настоящее, а не на сбой сайта. Пустой ответ при непустом
    /// старом и резкая потеря пар подозрительны: такое изменение принимаем после повторной проверки.
    static func isPlausible(from old: [Lesson], to new: [Lesson], now: Date) -> Bool {
        let before = old.filter { !$0.isTimeUnspecified && $0.endsAt > now }.count
        let after = new.filter { !$0.isTimeUnspecified && $0.endsAt > now }.count
        if before > 0 && after == 0 { return false }
        return before - after <= 3 || after * 10 >= before * 7
    }

    static func changes(from old: [Lesson], to new: [Lesson], now: Date, takenAt: Date) -> [ScheduleChange] {
        let calendar = Calendar.current
        let horizon = calendar.date(byAdding: .day, value: horizonDays, to: calendar.startOfDay(for: min(takenAt, now))) ?? now
        let oldByID = Dictionary(old.filter { !$0.isTimeUnspecified }.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let newByID = Dictionary(new.filter { !$0.isTimeUnspecified }.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

        var cancelled = oldByID.values.filter { newByID[$0.id] == nil && $0.endsAt > now && $0.startsAt < horizon }
        var added = newByID.values.filter { oldByID[$0.id] == nil && $0.startsAt > now && $0.startsAt < horizon }
        var result: [ScheduleChange] = []

        for lesson in newByID.values {
            guard let before = oldByID[lesson.id], lesson.endsAt > now, lesson.startsAt < horizon else { continue }
            let differs = before.startsAt != lesson.startsAt || before.endsAt != lesson.endsAt
                || before.room != lesson.room || before.subject != lesson.subject
            if differs { result.append(change(.changed, lesson, before: before, now: now)) }
        }

        // Перенос: у новой пары другой идентификатор, но то же название и тип занятия.
        for gone in cancelled {
            guard let index = added.firstIndex(where: {
                $0.subject == gone.subject && $0.kind == gone.kind && abs($0.startsAt.timeIntervalSince(gone.startsAt)) <= moveWindow
            }) else { continue }
            let match = added.remove(at: index)
            cancelled.removeAll { $0.id == gone.id }
            result.append(change(.changed, match, before: gone, now: now))
        }

        result += cancelled.map { change(.cancelled, $0, before: nil, now: now) }
        result += added.map { change(.added, $0, before: nil, now: now) }
        return result.sorted { $0.startsAt < $1.startsAt }
    }

    private static func change(_ kind: ScheduleChange.Kind, _ lesson: Lesson, before: Lesson?, now: Date) -> ScheduleChange {
        ScheduleChange(id: UUID(), kind: kind, subject: lesson.subject, startsAt: lesson.startsAt, endsAt: lesson.endsAt,
                       room: lesson.room, previousStartsAt: before?.startsAt, previousRoom: before?.room,
                       detectedAt: now, notified: false)
    }
}

/// Журнал изменений в общей памяти приложения и виджета. Сравнение идёт при каждом сохранении
/// расписания (в приложении, в фоне, в виджете), поэтому изменение не проходит незамеченным,
/// даже если расписание первым загрузил виджет.
enum ScheduleChangeLog {
    private static let entriesKey = "schedule.changes.v1"
    private static let enabledKey = "schedule.changes.enabled.v1"
    /// Подозрительное расписание подтверждается повторной проверкой не раньше чем через столько секунд.
    private static let confirmGap: TimeInterval = 180
    private static let limit = 30
    private static var defaults: UserDefaults { AppGroup.defaults }

    private struct Candidate: Codable {
        var signature: String
        var seenAt: Date
    }

    static var enabled: Bool {
        get { defaults.object(forKey: enabledKey) as? Bool ?? true }
        set { defaults.set(newValue, forKey: enabledKey) }
    }

    /// Вызывается после каждого сохранения свежего расписания.
    static func observe(_ fresh: ScheduleSnapshot, now: Date = .now) {
        let groupID = fresh.group.id
        guard let baseline = baseline(groupID) else {
            saveBaseline(fresh)
            return
        }
        let signature = Self.signature(fresh.lessons)
        guard signature != Self.signature(baseline.lessons) else {
            defaults.removeObject(forKey: candidateKey(groupID))
            return
        }

        let subgroup = ScheduleStore.subgroup
        let old = baseline.lessons.visible(forSubgroup: subgroup)
        let new = fresh.lessons.visible(forSubgroup: subgroup)
        if !ScheduleDiff.isPlausible(from: old, to: new, now: now) {
            // Подозрительная потеря пар (сбой сайта?): ждём второго такого же ответа.
            guard let candidate = candidate(groupID), candidate.signature == signature else {
                saveCandidate(Candidate(signature: signature, seenAt: now), groupID)
                return
            }
            guard now.timeIntervalSince(candidate.seenAt) >= confirmGap else { return }
        }

        defaults.removeObject(forKey: candidateKey(groupID))
        saveBaseline(fresh)
        guard enabled else { return }
        let found = ScheduleDiff.changes(from: old, to: new, now: now, takenAt: baseline.updatedAt)
        if !found.isEmpty { save(Array((load() + found).suffix(limit))) }
    }

    /// Изменения, которые ещё стоит показать: свежие и не про давно прошедшие пары.
    static func active(now: Date = .now) -> [ScheduleChange] {
        load().filter {
            $0.endsAt > now.addingTimeInterval(-6 * 60 * 60) && $0.detectedAt > now.addingTimeInterval(-3 * 24 * 60 * 60)
        }
    }

    static func dismiss() {
        save([])
    }

    /// Одно уведомление обо всех ещё не объявленных изменениях. Разрешение на уведомления не запрашивает:
    /// это делает приложение.
    static func notifyPending(now: Date = .now) async {
        var list = load()
        let pending = list.filter { !$0.notified && $0.endsAt > now }
        guard !pending.isEmpty else { return }
        // Отмечаем сразу, чтобы приложение и виджет не прислали одно и то же дважды.
        for index in list.indices { list[index].notified = true }
        save(list)
        guard enabled else { return }

        let center = UNUserNotificationCenter.current()
        let status = await center.notificationSettings().authorizationStatus
        guard status == .authorized || status == .provisional else { return }
        let content = UNMutableNotificationContent()
        content.title = pending.count == 1 ? "Расписание изменилось" : "Расписание изменилось (\(pending.count))"
        let lines = pending.prefix(4).map { $0.text(now: now) }
        content.body = (lines + (pending.count > 4 ? ["И ещё \(pending.count - 4)"] : [])).joined(separator: "\n")
        content.sound = .default
        try? await center.add(UNNotificationRequest(identifier: "change-\(Int(now.timeIntervalSince1970))",
                                                    content: content, trigger: nil))
    }

    // MARK: - Хранение

    private static func load() -> [ScheduleChange] {
        defaults.data(forKey: entriesKey).flatMap { try? JSONDecoder().decode([ScheduleChange].self, from: $0) } ?? []
    }

    private static func save(_ list: [ScheduleChange]) {
        if let data = try? JSONEncoder().encode(list) { defaults.set(data, forKey: entriesKey) }
    }

    private static func baselineKey(_ groupID: String) -> String { "schedule.baseline.v1.\(groupID)" }
    private static func candidateKey(_ groupID: String) -> String { "schedule.candidate.v1.\(groupID)" }

    private static func baseline(_ groupID: String) -> ScheduleSnapshot? {
        defaults.data(forKey: baselineKey(groupID)).flatMap { try? JSONDecoder().decode(ScheduleSnapshot.self, from: $0) }
    }

    private static func saveBaseline(_ snapshot: ScheduleSnapshot) {
        if let data = try? JSONEncoder().encode(snapshot) { defaults.set(data, forKey: baselineKey(snapshot.group.id)) }
    }

    private static func candidate(_ groupID: String) -> Candidate? {
        defaults.data(forKey: candidateKey(groupID)).flatMap { try? JSONDecoder().decode(Candidate.self, from: $0) }
    }

    private static func saveCandidate(_ candidate: Candidate, _ groupID: String) {
        if let data = try? JSONEncoder().encode(candidate) { defaults.set(data, forKey: candidateKey(groupID)) }
    }

    /// Отпечаток расписания: одинаковый набор пар даёт одинаковый отпечаток.
    private static func signature(_ lessons: [Lesson]) -> String {
        let rows = lessons.map {
            "\($0.id)|\($0.startsAt.timeIntervalSince1970)|\($0.endsAt.timeIntervalSince1970)|\($0.subject)|\($0.kind)|\($0.room)|\($0.address)|\($0.teacher)|\($0.subgroup ?? 0)"
        }.sorted()
        let digest = SHA256.hash(data: Data(rows.joined(separator: "\n").utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
