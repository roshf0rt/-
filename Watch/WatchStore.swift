import Foundation
import WatchConnectivity

/// Расписание на часах: что прислал iPhone, а если его нет рядом — загрузка с сайта.
@MainActor
final class WatchStore: NSObject, ObservableObject {
    @Published private(set) var group: ScheduleGroup?
    @Published private(set) var lessons: [Lesson] = []
    @Published private(set) var updatedAt: Date?
    @Published private(set) var loading = false
    @Published private(set) var failed = false
    private var subgroup: Int?
    private static let storageKey = "watchPayload"

    override init() {
        super.init()
        if let data = UserDefaults.standard.data(forKey: Self.storageKey) { apply(data) }
        if WCSession.isSupported() {
            WCSession.default.delegate = self
            WCSession.default.activate()
        }
    }

    var isStale: Bool {
        updatedAt.map { Date().timeIntervalSince($0) > 60 * 60 } ?? true
    }

    func apply(_ data: Data) {
        guard let payload = try? JSONDecoder().decode(WatchPayload.self, from: data) else { return }
        group = payload.group
        subgroup = payload.subgroup
        lessons = payload.lessons.sorted { $0.startsAt < $1.startsAt }
        updatedAt = payload.sentAt
        AppTheme.current = AppTheme(rawValue: payload.theme) ?? .byKind
        UserDefaults.standard.set(payload.theme, forKey: "theme")
        UserDefaults.standard.set(data, forKey: Self.storageKey)
    }

    /// Loads the schedule from the site directly; without a group, asks the phone.
    func refresh() async {
        guard let group else {
            askPhone()
            return
        }
        loading = true
        failed = false
        defer { loading = false }
        do {
            let fresh = try await ScheduleAPI(timeout: 20).fetchSchedule(for: group)
            let payload = WatchPayload(group: group, subgroup: subgroup, theme: AppTheme.current.rawValue,
                                       lessons: fresh.visible(forSubgroup: subgroup), sentAt: .now)
            if let data = try? JSONEncoder().encode(payload) { apply(data) }
        } catch {
            failed = true
        }
    }

    func askPhone() {
        let session = WCSession.default
        guard WCSession.isSupported(), session.activationState == .activated, session.isReachable else { return }
        session.sendMessage(["request": WatchPayload.key], replyHandler: { reply in
            guard let data = reply[WatchPayload.key] as? Data else { return }
            Task { @MainActor in self.apply(data) }
        }, errorHandler: nil)
    }
}

extension WatchStore: WCSessionDelegate {
    nonisolated func session(_ session: WCSession, activationDidCompleteWith state: WCSessionActivationState, error: Error?) {
        let data = session.receivedApplicationContext[WatchPayload.key] as? Data
        Task { @MainActor in
            if let data {
                self.apply(data)
            } else if self.group == nil {
                self.askPhone()
            }
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        guard let data = applicationContext[WatchPayload.key] as? Data else { return }
        Task { @MainActor in self.apply(data) }
    }
}
