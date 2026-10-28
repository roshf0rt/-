import Foundation

/// What the phone sends to the watch app: the group, the chosen subgroup and the pairs
/// already filtered for it, so the watch works without searching on its own.
struct WatchPayload: Codable {
    static let key = "payload"

    var group: ScheduleGroup?
    var subgroup: Int?
    var theme: String
    var lessons: [Lesson]
    var sentAt: Date
}
