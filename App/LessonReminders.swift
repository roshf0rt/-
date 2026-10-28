import UIKit
import UserNotifications

/// Локальные напоминания перед парами. Сервер не нужен: приложение ставит их
/// заранее на две недели вперёд и пересоздаёт при каждом обновлении расписания.
enum LessonReminders {
    static let choices = [5, 10, 15, 20, 30]
    private static let key = "reminders.minutesBefore.v1"
    /// iOS keeps at most 64 pending notifications per app; leave room for homework.
    private static let limit = 50

    private static let moodKey = "reminders.moods.v1"

    /// Сообщать, когда пары на день закончились, и о каникулах. По умолчанию выключено.
    static var moodsEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: moodKey) }
        set { UserDefaults.standard.set(newValue, forKey: moodKey) }
    }

    /// 0 — напоминания выключены.
    static var minutesBefore: Int {
        get { UserDefaults.standard.integer(forKey: key) }
        set { UserDefaults.standard.set(newValue, forKey: key) }
    }

    static func requestAuthorization() async -> Bool {
        let center = UNUserNotificationCenter.current()
        let status = await center.notificationSettings().authorizationStatus
        if status == .notDetermined {
            return (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
        }
        return status == .authorized || status == .provisional
    }

    static func reschedule(_ lessons: [Lesson], minutesBefore: Int) async {
        let center = UNUserNotificationCenter.current()
        // Only this kind: homework reminders are scheduled separately.
        let pending = await center.pendingNotificationRequests()
        center.removePendingNotificationRequests(withIdentifiers: pending.map(\.identifier).filter { $0.hasPrefix("lesson-") })
        guard minutesBefore > 0, await requestAuthorization() else { return }

        let lead = TimeInterval(minutesBefore * 60)
        let now = Date()
        let upcoming = lessons.filter { !$0.isTimeUnspecified && $0.startsAt.addingTimeInterval(-lead) > now }
        for lesson in upcoming.prefix(limit) {
            let content = UNMutableNotificationContent()
            content.title = "Через \(minutesBefore) мин: \(lesson.subject)"
            content.body = ["Кабинет \(lesson.roomTitle)", lesson.shortAddress, RU.timeRange(lesson)]
                .filter { !$0.isEmpty }
                .joined(separator: " · ")
            content.sound = .default
            let fireDate = lesson.startsAt.addingTimeInterval(-lead)
            let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: fireDate)
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            let request = UNNotificationRequest(identifier: "lesson-\(lesson.id)", content: content, trigger: trigger)
            try? await center.add(request)
        }
    }
}

extension LessonReminders {
    /// One notification at the end of each day's last pair; before a break it becomes the holiday message.
    static func rescheduleMoods(_ lessons: [Lesson], enabled: Bool) async {
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests()
        center.removePendingNotificationRequests(withIdentifiers: pending.map(\.identifier).filter {
            $0.hasPrefix("dayend-") || $0.hasPrefix("vacation-")
        })
        guard enabled, await requestAuthorization() else { return }

        let calendar = Calendar.current
        let now = Date()
        let real = lessons.filter { !$0.isTimeUnspecified }
        let days = Dictionary(grouping: real) { calendar.startOfDay(for: $0.startsAt) }
        for (day, items) in days.sorted(by: { $0.key < $1.key }).prefix(14) {
            guard let end = items.map(\.endsAt).max(), end > now else { continue }
            let content = UNMutableNotificationContent()
            content.sound = .default
            let identifier: String
            if let next = real.filter({ $0.startsAt > end }).map(\.startsAt).min(),
               next.timeIntervalSince(end) >= Mood.vacationGap {
                let dayCount = calendar.dateComponents([.day], from: end, to: next).day ?? 0
                content.title = Mood.line(Mood.vacationLines, on: end)
                content.body = "До первой пары \(dayCount) дн. Отдыхайте по полной"
                identifier = "vacation-\(Int(day.timeIntervalSince1970))"
            } else {
                content.title = Mood.line(Mood.dayDoneLines, on: end)
                content.body = "Последняя пара — \(items.first { $0.endsAt == end }?.subject ?? "на сегодня всё")"
                identifier = "dayend-\(Int(day.timeIntervalSince1970))"
            }
            let components = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: end)
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            try? await center.add(UNNotificationRequest(identifier: identifier, content: content, trigger: trigger))
        }
    }
}

/// Показывает напоминание баннером, даже если приложение открыто.
final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        LiveActivities.registerBackgroundRefresh()
        WatchLink.shared.activate()
        return true
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }
}
