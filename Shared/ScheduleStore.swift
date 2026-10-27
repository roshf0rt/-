import Foundation

enum AppGroup {
    /// Идентификатор из project.yml. Его же подставляет scripts/configure-signing.py.
    static let configuredID = "group.ru.roshfort.urfu.schedule"

    /// Программы для установки IPA при переподписи часто меняют App Group.
    /// Тогда заданный в коде идентификатор не разрешён, и приложение с виджетом
    /// получают разные хранилища. Поэтому берём группу из профиля подписи.
    static let id: String = {
        if let shared = Entitlements.sharedAppGroup { return shared }
        let groups = provisionedGroups()
        return groups.first { $0.localizedCaseInsensitiveContains("urfu") } ?? groups.first ?? configuredID
    }()

    /// Есть ли у приложения и виджета общая папка. Программа установки может выдать
    /// им разные группы, поэтому сверяем права обоих, если их удалось прочитать.
    static let isShared: Bool = Entitlements.partnerKnown
        ? Entitlements.sharedAppGroup != nil
        : !provisionedGroups().isEmpty

    /// Откуда взят идентификатор — для экрана диагностики.
    static var source: String {
        if Entitlements.sharedAppGroup != nil { return "общая с виджетом" }
        if Entitlements.partnerKnown { return "у виджета другая или нет — общей папки нет" }
        return isShared ? "из профиля подписи" : "из кода (в профиле подписи групп нет)"
    }

    static var defaults: UserDefaults {
        UserDefaults(suiteName: id) ?? .standard
    }

    private static func provisionedGroups() -> [String] {
        let groups = ProvisioningProfile.entitlements["com.apple.security.application-groups"] as? [String] ?? []
        return groups.filter { !$0.contains("*") }
    }
}

/// The embedded provisioning profile, which tells what the installed build may share.
enum ProvisioningProfile {
    static let contents: [String: Any] = {
        guard let url = Bundle.main.url(forResource: "embedded", withExtension: "mobileprovision"),
              let data = try? Data(contentsOf: url),
              let start = data.range(of: Data("<?xml".utf8)),
              let end = data.range(of: Data("</plist>".utf8), in: start.lowerBound..<data.endIndex),
              let plist = try? PropertyListSerialization.propertyList(
                  from: data.subdata(in: start.lowerBound..<end.upperBound), format: nil
              ) as? [String: Any]
        else { return [:] }
        return plist
    }()

    static var entitlements: [String: Any] {
        contents["Entitlements"] as? [String: Any] ?? [:]
    }

    /// Team ID prefix used in keychain access groups, e.g. "ABCDE12345".
    static var teamPrefix: String? {
        if let prefix = (contents["ApplicationIdentifierPrefix"] as? [String])?.first { return prefix }
        if let team = (contents["TeamIdentifier"] as? [String])?.first { return team }
        if let appID = entitlements["application-identifier"] as? String, let dot = appID.firstIndex(of: ".") {
            return String(appID[..<dot])
        }
        return nil
    }
}

enum ScheduleStore {
    private static let groupKey = "schedule.group.v1"
    private static let subgroupKey = "schedule.subgroup.v1"
    private static let themeKey = "schedule.theme.v1"
    private static let locationKey = "schedule.useLocation.v1"
    private static var defaults: UserDefaults { AppGroup.defaults }

    private static func snapshotKey(_ groupID: String) -> String {
        "schedule.snapshot.v2.\(groupID)"
    }

    static func loadGroup() -> ScheduleGroup? {
        guard let data = defaults.data(forKey: groupKey) else { return nil }
        return try? JSONDecoder().decode(ScheduleGroup.self, from: data)
    }

    static func saveGroup(_ group: ScheduleGroup) {
        guard let data = try? JSONEncoder().encode(group) else { return }
        defaults.set(data, forKey: groupKey)
    }

    /// Выбранная подгруппа; nil — показывать все.
    static var subgroup: Int? {
        get {
            let value = defaults.integer(forKey: subgroupKey)
            return value > 0 ? value : nil
        }
        set { defaults.set(newValue ?? 0, forKey: subgroupKey) }
    }

    /// Учитывать ли геолокацию в виджете; по умолчанию да.
    static var useLocation: Bool {
        get { defaults.object(forKey: locationKey) as? Bool ?? true }
        set { defaults.set(newValue, forKey: locationKey) }
    }

    static var theme: String? {
        get { defaults.string(forKey: themeKey) }
        set { defaults.set(newValue, forKey: themeKey) }
    }

    static func snapshot(for groupID: String) -> ScheduleSnapshot? {
        guard let data = defaults.data(forKey: snapshotKey(groupID)) else { return nil }
        return try? JSONDecoder().decode(ScheduleSnapshot.self, from: data)
    }

    static func save(_ snapshot: ScheduleSnapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        defaults.set(data, forKey: snapshotKey(snapshot.group.id))
    }
}
