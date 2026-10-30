import AppIntents
import Foundation

/// «Какая следующая пара» для Siri, приложения «Команды» и кнопки Action.
/// Берёт то же расписание, что и виджеты, поэтому работает и на экране блокировки.
struct NextLessonIntent: AppIntent {
    static var title: LocalizedStringResource = "Следующая пара"
    static var description: IntentDescription = IntentDescription("Расскажет, какая пара будет дальше по расписанию группы.")

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let answer = await NextLessonAnswer.make()
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
            ],
            shortTitle: "Следующая пара",
            systemImageName: "calendar.badge.clock"
        )
    }
}

/// Текст ответа. Отдельно от intent, чтобы его было легко поменять и проверить.
enum NextLessonAnswer {
    static func make(now: Date = .now) async -> String {
        guard let group = ScheduleStore.loadGroup() else {
            return "Сначала выберите группу в приложении «Расписание УрФУ»."
        }
        let lessons = await freshLessons(for: group, now: now).visible(forSubgroup: ScheduleStore.subgroup)

        var parts: [String] = []
        if let current = lessons.current(at: now) {
            parts.append("Сейчас идёт «\(current.subject)» до \(RU.time(current.endsAt)).")
        }
        guard let next = lessons.next(after: now) else {
            return parts.isEmpty ? "В ближайшие две недели пар нет." : (parts + ["Больше пар нет."]).joined(separator: " ")
        }
        let room = next.room.isEmpty ? "" : ", кабинет \(next.room)"
        parts.append("Следующая пара — «\(next.subject)», \(RU.startsIn(next, now: now))\(room).")
        return parts.joined(separator: " ")
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
