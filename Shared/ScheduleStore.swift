import Foundation

enum AppGroup {
    /// Должен совпадать с App Group в настройках обоих таргетов (project.yml).
    static let id = "group.ru.urfu.schedule"
}

/// Хранилище в App Group: приложение пишет, виджет читает.
struct ScheduleStore {
    private let defaults = UserDefaults(suiteName: AppGroup.id) ?? .standard
    private let groupKey = "selectedGroup"
    private let lessonsKey = "lessons"

    var selectedGroup: String? {
        get { defaults.string(forKey: groupKey) }
        nonmutating set { defaults.set(newValue, forKey: groupKey) }
    }

    func saveLessons(_ lessons: [Lesson]) {
        guard let data = try? JSONEncoder().encode(lessons) else { return }
        defaults.set(data, forKey: lessonsKey)
    }

    func loadLessons() -> [Lesson] {
        guard let data = defaults.data(forKey: lessonsKey),
              let lessons = try? JSONDecoder().decode([Lesson].self, from: data) else { return [] }
        return lessons
    }
}
