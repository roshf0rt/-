import ActivityKit
import BackgroundTasks
import Foundation

/// Живая карточка текущей или следующей пары сегодня.
///
/// Without push updates only the app can start it (in the foreground) and move it to the
/// next pair. The card itself switches from "before" to "during" to "after" on its own:
/// its stale date is the next boundary, and the system redraws it then.
@MainActor
enum LiveActivities {
    static let refreshTaskID = "ru.roshfort.urfu.refresh"
    private static let enabledKey = "liveActivityEnabled"
    private static let islandKey = "liveActivityInIsland"
    /// A card is started only for a pair that begins within this time.
    private static let startWindow: TimeInterval = 6 * 60 * 60

    static var enabled: Bool {
        get { UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: enabledKey) }
    }

    static var showsInIsland: Bool {
        get { UserDefaults.standard.object(forKey: islandKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: islandKey) }
    }

    static var systemAllows: Bool { ActivityAuthorizationInfo().areActivitiesEnabled }

    static func sync(lessons: [Lesson], groupName: String, theme: AppTheme, canStart: Bool, now: Date = .now) async {
        let running = Activity<LessonActivityAttributes>.activities
        guard enabled, let state = state(lessons: lessons, theme: theme, now: now) else {
            for activity in running { await activity.end(nil, dismissalPolicy: .immediate) }
            return
        }
        let content = ActivityContent(state: state, staleDate: boundary(after: now, in: state), relevanceScore: 100)
        var current: Activity<LessonActivityAttributes>?
        for activity in running {
            if current == nil && activity.attributes.groupName == groupName {
                current = activity
            } else {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
        }
        if let current {
            await current.update(content)
        } else if canStart && systemAllows {
            do {
                _ = try Activity.request(attributes: LessonActivityAttributes(groupName: groupName),
                                         content: content, pushType: nil)
            } catch {
                print("Live Activity: \(error)")
            }
        }
        // Move on to the next pair when this one ends, if iOS grants the app the time.
        scheduleRefresh(at: state.endsAt)
    }

    /// Called from a background refresh: move the card on to the next pair or remove it.
    static func backgroundRefresh() async {
        guard let group = ScheduleStore.loadGroup(), let snapshot = ScheduleStore.snapshot(for: group.id) else { return }
        let lessons = snapshot.lessons.visible(forSubgroup: ScheduleStore.subgroup)
        await sync(lessons: lessons, groupName: group.name, theme: AppTheme.stored, canStart: false)
    }

    static func registerBackgroundRefresh() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: refreshTaskID, using: nil) { task in
            let work = Task { @MainActor in
                await backgroundRefresh()
                task.setTaskCompleted(success: true)
            }
            task.expirationHandler = { work.cancel() }
        }
    }

    private static func scheduleRefresh(at date: Date) {
        let request = BGAppRefreshTaskRequest(identifier: refreshTaskID)
        request.earliestBeginDate = date
        try? BGTaskScheduler.shared.submit(request)
    }

    /// The pair that is on now, or the next one today.
    private static func state(lessons: [Lesson], theme: AppTheme, now: Date) -> LessonActivityAttributes.ContentState? {
        let calendar = Calendar.current
        let today = lessons.filter { !$0.isTimeUnspecified && calendar.isDate($0.startsAt, inSameDayAs: now) }
        guard let focus = today.focus(at: now), focus.startsAt.timeIntervalSince(now) < startWindow else { return nil }
        let next = today.next(after: focus.startsAt)
        let previousEnd = today.filter { $0.endsAt <= focus.startsAt }.map(\.endsAt).max()
        return LessonActivityAttributes.ContentState(
            subject: focus.subject, kind: focus.kind, room: focus.room, address: focus.shortAddress,
            startsAt: focus.startsAt, endsAt: focus.endsAt,
            nextSubject: next?.subject, nextRoom: next?.room, nextStartsAt: next?.startsAt,
            previousEndsAt: previousEnd, theme: theme.rawValue, showsInIsland: showsInIsland)
    }

    /// The next moment the card changes: a break starts or ends, the 15-minute hurry begins, or a pair starts or ends.
    private static func boundary(after now: Date, in state: LessonActivityAttributes.ContentState) -> Date? {
        let hurry = state.startsAt.addingTimeInterval(-TimeInterval(Hurry.minutes * 60))
        return [state.previousEndsAt, hurry, state.startsAt, state.endsAt].compactMap { $0 }.filter { $0 > now }.min()
    }
}
