import Foundation

enum AppGroup {
    /// Идентификатор из project.yml. Его же подставляет scripts/configure-signing.py.
    static let configuredID = "group.ru.roshfort.urfu.schedule"

    /// Программы для установки IPA при переподписи часто меняют App Group.
    /// Тогда заданный в коде идентификатор не разрешён, и приложение с виджетом
    /// получают разные хранилища. Поэтому берём группу из профиля подписи.
    static let id: String = {
        let groups = provisionedGroups()
        return groups.first { $0.localizedCaseInsensitiveContains("urfu") } ?? groups.first ?? configuredID
    }()

    /// Есть ли у приложения и виджета общая папка. Без профиля с App Group её нет.
    static let isShared = !provisionedGroups().isEmpty

    /// Откуда взят идентификатор — для экрана диагностики.
    static var source: String {
        isShared ? "из профиля подписи" : "из кода (в профиле подписи групп нет)"
    }

    static var defaults: UserDefaults {
        UserDefaults(suiteName: id) ?? .standard
    }

    private static func provisionedGroups() -> [String] {
        guard let url = Bundle.main.url(forResource: "embedded", withExtension: "mobileprovision"),
              let data = try? Data(contentsOf: url),
              let start = data.range(of: Data("<?xml".utf8)),
              let end = data.range(of: Data("</plist>".utf8), in: start.lowerBound..<data.endIndex),
              let plist = try? PropertyListSerialization.propertyList(
                  from: data.subdata(in: start.lowerBound..<end.upperBound), format: nil
              ) as? [String: Any],
              let entitlements = plist["Entitlements"] as? [String: Any],
              let groups = entitlements["com.apple.security.application-groups"] as? [String]
        else { return [] }
        return groups.filter { !$0.contains("*") }
    }
}

enum ScheduleStore {
    private static let groupKey = "schedule.group.v1"
    private static let subgroupKey = "schedule.subgroup.v1"
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

    static func snapshot(for groupID: String) -> ScheduleSnapshot? {
        guard let data = defaults.data(forKey: snapshotKey(groupID)) else { return nil }
        return try? JSONDecoder().decode(ScheduleSnapshot.self, from: data)
    }

    static func save(_ snapshot: ScheduleSnapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        defaults.set(data, forKey: snapshotKey(snapshot.group.id))
    }
}
