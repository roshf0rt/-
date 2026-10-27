import Foundation

/// Короткий журнал запусков виджета. Приложение показывает его в настройках,
/// чтобы было видно, работает ли виджет и где он спотыкается.
enum WidgetLog {
    private static let key = "widget.log.v1"
    private static let limit = 30

    static func add(_ message: String) {
        let stamp = Date().formatted(.dateTime.day().month(.twoDigits).hour().minute().second().locale(RU.locale))
        var lines = entries()
        lines.append("\(stamp)  \(message)")
        lines = Array(lines.suffix(limit))
        if let data = try? JSONEncoder().encode(lines), SharedSettings.saveData(data, account: key) { return }
        AppGroup.defaults.set(lines, forKey: key)
    }

    static func entries() -> [String] {
        if let data = SharedSettings.loadData(account: key),
           let lines = try? JSONDecoder().decode([String].self, from: data) {
            return lines
        }
        return AppGroup.defaults.stringArray(forKey: key) ?? []
    }
}

struct DeadlineExceeded: LocalizedError {
    var errorDescription: String? { "Сайт не ответил вовремя" }
}

/// Runs `operation`, giving up after `seconds`; widgets are killed if they take too long.
func withDeadline<T: Sendable>(_ seconds: Double, _ operation: @escaping @Sendable () async throws -> T) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask { try await operation() }
        group.addTask {
            try await Task.sleep(for: .seconds(seconds))
            throw DeadlineExceeded()
        }
        defer { group.cancelAll() }
        guard let result = try await group.next() else { throw DeadlineExceeded() }
        return result
    }
}
