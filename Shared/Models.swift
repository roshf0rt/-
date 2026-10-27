import Foundation

struct ScheduleGroup: Identifiable, Codable, Hashable {
    var id: String
    var name: String
}

struct Lesson: Identifiable, Codable, Hashable {
    var id: String
    var subject: String
    /// Тип занятия как его пишет УрФУ: «лекции», «практические занятия»…
    var kind: String
    var startsAt: Date
    var endsAt: Date
    var room: String
    var address: String
    var teacher: String
    /// Номер подгруппы; nil — занятие для всей группы.
    var subgroup: Int?
    var isTimeUnspecified: Bool
}

struct ScheduleSnapshot: Codable {
    var group: ScheduleGroup
    var lessons: [Lesson]
    var updatedAt: Date
}

extension Lesson {
    func isVisible(forSubgroup subgroup: Int?) -> Bool {
        guard let subgroup, let own = self.subgroup else { return true }
        return own == subgroup
    }

    func isOngoing(at date: Date) -> Bool {
        !isTimeUnspecified && startsAt <= date && date < endsAt
    }
}

extension Array where Element == Lesson {
    func visible(forSubgroup subgroup: Int?) -> [Lesson] {
        filter { $0.isVisible(forSubgroup: subgroup) }.sorted { $0.startsAt < $1.startsAt }
    }

    func current(at date: Date) -> Lesson? {
        first { $0.isOngoing(at: date) }
    }

    func next(after date: Date) -> Lesson? {
        first { !$0.isTimeUnspecified && $0.startsAt > date }
    }

    /// Текущая пара, а если её нет — ближайшая.
    func focus(at date: Date) -> Lesson? {
        current(at: date) ?? next(after: date)
    }

    /// Ближайшие пары, сгруппированные по дням, не больше `maxLessons`.
    func upcomingDays(at date: Date, maxLessons: Int) -> [(day: Date, lessons: [Lesson])] {
        let calendar = Calendar.current
        var result: [(day: Date, lessons: [Lesson])] = []
        for lesson in filter({ $0.endsAt > date }).prefix(maxLessons) {
            let day = calendar.startOfDay(for: lesson.startsAt)
            if let last = result.last, calendar.isDate(last.day, inSameDayAs: day) {
                result[result.count - 1].lessons.append(lesson)
            } else {
                result.append((day, [lesson]))
            }
        }
        return result
    }

    /// Оставшиеся пары сегодня, а если их нет — пары ближайшего учебного дня.
    func agenda(at date: Date) -> (day: Date, lessons: [Lesson])? {
        let calendar = Calendar.current
        let upcoming = filter { $0.endsAt > date }
        guard let first = upcoming.first else { return nil }
        let day = calendar.startOfDay(for: first.startsAt)
        return (day, upcoming.filter { calendar.isDate($0.startsAt, inSameDayAs: day) })
    }
}
