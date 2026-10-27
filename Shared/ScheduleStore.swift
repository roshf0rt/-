import Foundation

enum AppGroup {
    /// Должен совпадать с App Group в настройках обоих таргетов (project.yml).
    static let id = "group.ru.urfu.schedule"
}

/// Хранилище в App Group: приложение пишет, виджет читает.
struct ScheduleStore {
    private let defaults = UserDefaults(suiteName: AppGroup.id) ?? .standard
    private let key = "weeklyLessons"

    func save(_ lessons: [WeeklyLesson]) {
        guard let data = try? JSONEncoder().encode(lessons) else { return }
        defaults.set(data, forKey: key)
    }

    func load() -> [WeeklyLesson] {
        guard let data = defaults.data(forKey: key),
              let lessons = try? JSONDecoder().decode([WeeklyLesson].self, from: data) else { return [] }
        return lessons
    }
}
