import Foundation

/// Занятие, которое повторяется каждую неделю. Вводится вручную в приложении.
struct WeeklyLesson: Codable, Identifiable, Hashable {
    var id = UUID()
    var subject: String
    var room: String
    /// День недели по Calendar: 1 — воскресенье, 2 — понедельник, … 7 — суббота.
    var weekday: Int
    /// Минуты от полуночи: 9:30 — это 570.
    var startMinute: Int
    var endMinute: Int
}

/// Занятие на конкретную дату. Его показывают список и виджеты.
struct Lesson: Identifiable, Hashable {
    let subject: String
    let room: String
    let start: Date
    let end: Date

    var id: String { "\(start.timeIntervalSince1970)-\(subject)" }
}

extension Array where Element == WeeklyLesson {
    /// Занятия на указанный день, по времени начала.
    func lessons(on date: Date = .now) -> [Lesson] {
        let calendar = Calendar.current
        let weekday = calendar.component(.weekday, from: date)
        let day = calendar.startOfDay(for: date)
        return filter { $0.weekday == weekday }
            .sorted { $0.startMinute < $1.startMinute }
            .compactMap { item in
                guard let start = calendar.date(byAdding: .minute, value: item.startMinute, to: day),
                      let end = calendar.date(byAdding: .minute, value: item.endMinute, to: day) else { return nil }
                return Lesson(subject: item.subject, room: item.room, start: start, end: end)
            }
    }
}

extension Array where Element == Lesson {
    /// Занятие, которое идёт прямо сейчас.
    func current(at now: Date = .now) -> Lesson? {
        first { $0.start <= now && now < $0.end }
    }

    /// Ближайшее занятие, которое ещё не началось.
    func next(after now: Date = .now) -> Lesson? {
        first { $0.start > now }
    }

    /// Моменты начала и конца занятий: в эти моменты виджет меняет содержимое.
    func transitionDates(after now: Date = .now) -> [Date] {
        flatMap { [$0.start, $0.end] }.filter { $0 > now }
    }
}
