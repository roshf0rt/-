import Foundation

/// Права, с которыми программа установки на самом деле подписала приложение и виджет.
/// Они лежат в подписи исполняемого файла открытым plist, поэтому их можно прочитать
/// и найти общую для приложения и виджета папку или группу Keychain.
enum Entitlements {
    /// Права этого процесса (приложения или виджета).
    static let own: [String: Any] = read(executable: Bundle.main.executableURL)

    /// Права второй половины: виджета, если мы приложение, и наоборот.
    static let partner: [String: Any] = {
        let bundle = Bundle.main.bundleURL
        if bundle.pathExtension == "appex" {
            // …/UrFUSchedule.app/PlugIns/ScheduleWidget.appex
            let app = bundle.deletingLastPathComponent().deletingLastPathComponent()
            return read(executable: Bundle(url: app)?.executableURL)
        }
        let widget = Bundle.main.builtInPlugInsURL?.appendingPathComponent("ScheduleWidget.appex")
        return read(executable: widget.flatMap { Bundle(url: $0)?.executableURL })
    }()

    static var partnerKnown: Bool { !partner.isEmpty }

    static func appGroups(_ entitlements: [String: Any]) -> [String] {
        entitlements["com.apple.security.application-groups"] as? [String] ?? []
    }

    static func keychainGroups(_ entitlements: [String: Any]) -> [String] {
        entitlements["keychain-access-groups"] as? [String] ?? []
    }

    /// App Group, выданная и приложению, и виджету.
    static var sharedAppGroup: String? {
        appGroups(own).first { appGroups(partner).contains($0) }
    }

    /// Группа Keychain, доступная и приложению, и виджету.
    static var sharedKeychainGroup: String? {
        let partnerGroups = keychainGroups(partner)
        for group in keychainGroups(own) {
            if group.hasSuffix("*") {
                let prefix = String(group.dropLast())
                let candidate = prefix + "ru.roshfort.urfu.shared"
                if allows(partnerGroups, candidate) { return candidate }
                if let explicit = partnerGroups.first(where: { $0.hasPrefix(prefix) && !$0.hasSuffix("*") }) {
                    return explicit
                }
            } else if allows(partnerGroups, group) {
                return group
            }
        }
        return nil
    }

    private static func allows(_ groups: [String], _ group: String) -> Bool {
        groups.contains { $0 == group || ($0.hasSuffix("*") && group.hasPrefix(String($0.dropLast()))) }
    }

    private static func read(executable url: URL?) -> [String: Any] {
        guard let url, let data = try? Data(contentsOf: url, options: .alwaysMapped) else { return [:] }
        let open = Data("<?xml".utf8)
        let close = Data("</plist>".utf8)
        var searchFrom = data.startIndex
        while let start = data.range(of: open, in: searchFrom..<data.endIndex),
              let end = data.range(of: close, in: start.upperBound..<data.endIndex) {
            if let plist = try? PropertyListSerialization.propertyList(
                   from: data.subdata(in: start.lowerBound..<end.upperBound), format: nil
               ) as? [String: Any],
               plist["application-identifier"] != nil || plist["keychain-access-groups"] != nil {
                return plist
            }
            searchFrom = start.upperBound
        }
        return [:]
    }
}
