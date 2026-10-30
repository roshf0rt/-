import AppIntents
import Foundation

/// Команды для Siri, приложения «Команды» и кнопки Action. Берут то же расписание, что и виджеты.

struct NextLessonIntent: AppIntent {
    static var title: LocalizedStringResource = "Следующая пара"
    static var description: IntentDescription = IntentDescription("Какая пара будет дальше по расписанию группы.")

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let answer = await ScheduleAnswer.next()
        return .result(dialog: IntentDialog(stringLiteral: answer))
    }
}

struct NextRoomIntent: AppIntent {
    static var title: LocalizedStringResource = "Кабинет следующей пары"
    static var description: IntentDescription = IntentDescription("В какой кабинет и по какому адресу идти на следующую пару.")

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let answer = await ScheduleAnswer.room()
        return .result(dialog: IntentDialog(stringLiteral: answer))
    }
}

struct TomorrowLessonsIntent: AppIntent {
    static var title: LocalizedStringResource = "Пары завтра"
    static var description: IntentDescription = IntentDescription("Во сколько и где пары завтра.")

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let answer = await ScheduleAnswer.tomorrow()
        return .result(dialog: IntentDialog(stringLiteral: answer))
    }
}

/// Фразы для Siri. Название приложения обязательно: Siri привязывает фразу к приложению.
struct UrFUShortcuts: AppShortcutsProvider {
    @AppShortcutsBuilder
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: NextLessonIntent(),
            phrases: [
                "Какая следующая пара в \(.applicationName)",
                "Следующая пара в \(.applicationName)",
                "Когда следующая пара в \(.applicationName)",
                "Что дальше в \(.applicationName)",
            ],
            shortTitle: "Следующая пара",
            systemImageName: "calendar.badge.clock"
        )
        AppShortcut(
            intent: NextRoomIntent(),
            phrases: [
                "В какой кабинет идти в \(.applicationName)",
                "Какой кабинет в \(.applicationName)",
                "Куда идти на пару в \(.applicationName)",
                "Где следующая пара в \(.applicationName)",
            ],
            shortTitle: "Кабинет",
            systemImageName: "door.left.hand.open"
        )
        AppShortcut(
            intent: TomorrowLessonsIntent(),
            phrases: [
                "Во сколько пары завтра в \(.applicationName)",
                "Какие пары завтра в \(.applicationName)",
                "Расписание на завтра в \(.applicationName)",
            ],
            shortTitle: "Пары завтра",
            systemImageName: "calendar"
        )
    }
}

/// Текст ответов. Отдельно от intent, чтобы его было легко поменять и проверить.
enum ScheduleAnswer {
    private static let noGroup = "Сначала выберите группу в приложении «Расписание УрФУ»."
    private static let noLessons = "В ближайшие две недели пар нет."

    static func next(now: Date = .now) async -> String {
        guard let lessons = await visibleLessons(now: now) else { return noGroup }
        var parts: [String] = []
        if let current = lessons.current(at: now) {
            parts.append("Сейчас идёт «\(current.subject)» до \(RU.time(current.endsAt)).")
        }
        guard let next = lessons.next(after: now) else {
            return parts.isEmpty ? noLessons : (parts + ["Больше пар нет."]).joined(separator: " ")
        }
        let room = next.room.isEmpty ? "" : ", кабинет \(next.roomTitle)"
        parts.append("Следующая пара — «\(next.subject)», \(RU.startsIn(next, now: now))\(room).")
        return parts.joined(separator: " ")
    }

    static func room(now: Date = .now) async -> String {
        guard let lessons = await visibleLessons(now: now) else { return noGroup }
        let current = lessons.current(at: now)
        guard let next = lessons.next(after: now) else {
            if let current { return "Сейчас идёт «\(current.subject)», кабинет \(current.roomTitle). Больше пар нет." }
            return noLessons
        }
        let place = [next.room.isEmpty ? nil : "кабинет \(next.roomTitle)", next.shortAddress.isEmpty ? nil : next.shortAddress]
            .compactMap { $0 }
            .joined(separator: ", ")
        let head = current.map { "Сейчас идёт «\($0.subject)». " } ?? ""
        return "\(head)Идти на «\(next.subject)», \(RU.startsIn(next, now: now)): \(place.isEmpty ? "аудитория не указана" : place)."
    }

    static func tomorrow(now: Date = .now) async -> String {
        guard let lessons = await visibleLessons(now: now) else { return noGroup }
        let calendar = Calendar.current
        guard let day = calendar.date(byAdding: .day, value: 1, to: now) else { return noLessons }
        let tomorrow = lessons.filter { !$0.isTimeUnspecified && calendar.isDate($0.startsAt, inSameDayAs: day) }
        if tomorrow.isEmpty { return "Завтра пар нет." }
        let items = tomorrow.prefix(8).map { lesson -> String in
            let room = lesson.room.isEmpty ? "" : ", кабинет \(lesson.roomTitle)"
            return "\(RU.timeRange(lesson)) «\(lesson.subject)»\(room)"
        }
        let rest = tomorrow.count > 8 ? " И ещё \(tomorrow.count - 8)." : ""
        return "Завтра: " + items.joined(separator: "; ") + "." + rest
    }

    /// Расписание группы с учётом подгруппы; nil — группа не выбрана.
    private static func visibleLessons(now: Date) async -> [Lesson]? {
        guard let group = ScheduleStore.loadGroup() else { return nil }
        return await freshLessons(for: group, now: now).visible(forSubgroup: ScheduleStore.subgroup)
    }

    /// Снимок из общего хранилища. Если он старше получаса, пробуем обновить; без сети берём сохранённый.
    private static func freshLessons(for group: ScheduleGroup, now: Date) async -> [Lesson] {
        let saved = ScheduleStore.snapshot(for: group.id)
        if let saved, now.timeIntervalSince(saved.updatedAt) < 30 * 60 {
            return saved.lessons
        }
        do {
            let lessons = try await ScheduleAPI(timeout: 8).fetchSchedule(for: group)
            ScheduleStore.save(ScheduleSnapshot(group: group, lessons: lessons, updatedAt: now))
            return lessons
        } catch {
            return saved?.lessons ?? []
        }
    }
}
