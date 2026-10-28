import Foundation
import WatchConnectivity

/// Sends the group, subgroup and pairs to the watch app.
final class WatchLink: NSObject, WCSessionDelegate {
    static let shared = WatchLink()
    private var pending: Data?

    func activate() {
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    func send(group: ScheduleGroup?, subgroup: Int?, theme: String, lessons: [Lesson]) {
        guard WCSession.isSupported() else { return }
        let start = Calendar.current.startOfDay(for: .now)
        let payload = WatchPayload(group: group, subgroup: subgroup, theme: theme,
                                   lessons: Array(lessons.filter { $0.endsAt > start }.prefix(80)), sentAt: .now)
        guard let data = try? JSONEncoder().encode(payload) else { return }
        DispatchQueue.main.async {
            self.pending = data
            self.flush()
        }
    }

    private func flush() {
        let session = WCSession.default
        guard let data = pending, session.activationState == .activated,
              session.isPaired, session.isWatchAppInstalled else { return }
        do {
            try session.updateApplicationContext([WatchPayload.key: data])
            pending = nil
        } catch {
            print("Watch: \(error)")
        }
    }

    func session(_ session: WCSession, activationDidCompleteWith state: WCSessionActivationState, error: Error?) {
        DispatchQueue.main.async { self.flush() }
    }

    func sessionWatchStateDidChange(_ session: WCSession) {
        DispatchQueue.main.async { self.flush() }
    }

    func sessionDidBecomeInactive(_ session: WCSession) {}

    func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }

    /// The watch asks for the data when it has none yet.
    func session(_ session: WCSession, didReceiveMessage message: [String: Any],
                 replyHandler: @escaping ([String: Any]) -> Void) {
        DispatchQueue.main.async {
            replyHandler(self.lastData.map { [WatchPayload.key: $0] } ?? [:])
        }
    }

    private var lastData: Data? {
        pending ?? WCSession.default.applicationContext[WatchPayload.key] as? Data
    }
}
