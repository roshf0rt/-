import Foundation

/// Загружает расписание выбранной группы и сохраняет его в App Group.
struct ScheduleService {
    var repository: ScheduleRepository = MockScheduleRepository()
    let store = ScheduleStore()

    func refresh() async throws {
        guard let group = store.selectedGroup else { return }
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: .now)
        let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start
        let lessons = try await repository.lessons(forGroup: group, from: start, to: end)
        store.saveLessons(lessons)
    }
}

extension Array where Element == Lesson {
    /// Занятия на указанный день, по времени начала.
    func today(_ now: Date = .now) -> [Lesson] {
        filter { Calendar.current.isDate($0.start, inSameDayAs: now) }
            .sorted { $0.start < $1.start }
    }

    /// Занятие, которое идёт прямо сейчас.
    func current(at now: Date = .now) -> Lesson? {
        today(now).first { $0.start <= now && now < $0.end }
    }

    /// Ближайшее занятие, которое ещё не началось.
    func next(after now: Date = .now) -> Lesson? {
        today(now).first { $0.start > now }
    }

    /// Моменты начала и конца занятий сегодня: в эти моменты виджет меняет содержимое.
    func transitionDates(after now: Date = .now) -> [Date] {
        today(now).flatMap { [$0.start, $0.end] }.filter { $0 > now }
    }
}
