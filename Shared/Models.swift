import Foundation

struct ScheduleGroup: Identifiable, Codable, Hashable {
    var id: String
    var name: String
}

struct Lesson: Identifiable, Codable, Hashable {
    var id: String
    var title: String
    var startsAt: Date
    var endsAt: Date
    var location: String
    var teacher: String
    var isTimeUnspecified: Bool = false
}

struct ScheduleSnapshot: Codable {
    var groupName: String
    var lessons: [Lesson]
    var updatedAt: Date?

    static let empty = ScheduleSnapshot(groupName: "", lessons: [], updatedAt: nil)
}

enum ScheduleStore {
    // This must match the App Group entitlement of both targets.
    static let appGroup = "group.ru.roshfort.urfu.schedule"
    private static let snapshotKey = "schedule.snapshot.v1"
    private static let groupKey = "schedule.group.v1"
    private static var defaults: UserDefaults? { UserDefaults(suiteName: appGroup) }

    static func load() -> ScheduleSnapshot {
        guard let data = defaults?.data(forKey: snapshotKey),
              let snapshot = try? JSONDecoder().decode(ScheduleSnapshot.self, from: data) else { return .empty }
        return snapshot
    }

    static func save(_ snapshot: ScheduleSnapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        defaults?.set(data, forKey: snapshotKey)
    }

    static func loadGroup() -> ScheduleGroup? {
        guard let data = defaults?.data(forKey: groupKey) else { return nil }
        return try? JSONDecoder().decode(ScheduleGroup.self, from: data)
    }

    static func saveGroup(_ group: ScheduleGroup) {
        guard let data = try? JSONEncoder().encode(group) else { return }
        defaults?.set(data, forKey: groupKey)
    }
}
