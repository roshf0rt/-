#if os(iOS)
import ActivityKit
import Foundation

/// Живая карточка пары: экран блокировки, Dynamic Island и Smart Stack на часах.
struct LessonActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var subject: String
        var kind: String
        var room: String
        var address: String
        var startsAt: Date
        var endsAt: Date
        var nextSubject: String?
        var nextRoom: String?
        var nextStartsAt: Date?
        var theme: String
        /// Off: the Dynamic Island stays empty and only the lock screen card shows the pair.
        var showsInIsland: Bool
    }

    var groupName: String
}
#endif
