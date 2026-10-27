import Foundation
import Security

/// Группа и подгруппа, которые приложение передаёт виджету через Keychain.
/// Программы установки часто вырезают App Group, но профили с «TEAMID.*»
/// оставляют общий доступ к Keychain внутри одной подписи.
enum SharedSettings {
    struct Values: Codable, Equatable {
        var group: ScheduleGroup?
        var subgroup: Int?
    }

    private static let service = "ru.roshfort.urfu.settings"
    private static let account = "settings"

    static var accessGroup: String? {
        ProvisioningProfile.teamPrefix.map { "\($0).ru.roshfort.urfu.shared" }
    }

    /// Результат последней записи — для экрана диагностики.
    private(set) static var lastStatus: OSStatus?

    @discardableResult
    static func save(_ values: Values) -> Bool {
        guard var query = baseQuery(), let data = try? JSONEncoder().encode(values) else { return false }
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            // The widget refreshes while the phone is locked.
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]
        var status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            query.merge(attributes) { $1 }
            status = SecItemAdd(query as CFDictionary, nil)
        }
        lastStatus = status
        return status == errSecSuccess
    }

    static func load() -> Values? {
        guard var query = baseQuery() else { return nil }
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return try? JSONDecoder().decode(Values.self, from: data)
    }

    private static func baseQuery() -> [String: Any]? {
        guard let accessGroup else { return nil }
        return [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrAccessGroup as String: accessGroup
        ]
    }
}
