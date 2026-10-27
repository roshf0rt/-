import AppIntents
import WidgetKit

/// Настройки, которые открываются по «Изменить виджет».
struct ScheduleConfigurationIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Расписание"
    static var description = IntentDescription("Группа и подгруппа для этого виджета. Без группы виджет берёт её из приложения.")

    @Parameter(title: "Группа")
    var group: GroupEntity?

    @Parameter(title: "Подгруппа", default: .app)
    var subgroup: SubgroupOption
}

struct GroupEntity: AppEntity {
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Группа"
    static var defaultQuery = GroupQuery()

    /// "<id>|<name>": the widget needs the name, and the API cannot look a group up by ID.
    let id: String

    init(id: String) { self.id = id }
    init(_ group: ScheduleGroup) { id = "\(group.id)|\(group.name)" }

    var group: ScheduleGroup? {
        let parts = id.split(separator: "|", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { return nil }
        return ScheduleGroup(id: parts[0], name: parts[1])
    }

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(group?.name ?? id)")
    }
}

struct GroupQuery: EntityStringQuery {
    func entities(for identifiers: [String]) async throws -> [GroupEntity] {
        identifiers.map { GroupEntity(id: $0) }
    }

    func entities(matching string: String) async throws -> [GroupEntity] {
        try await ScheduleAPI().searchGroups(query: string).map { GroupEntity($0) }
    }

    func suggestedEntities() async throws -> [GroupEntity] {
        ScheduleStore.loadGroup().map { [GroupEntity($0)] } ?? []
    }
}

enum SubgroupOption: String, AppEnum {
    case app, all, first, second

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Подгруппа"
    static var caseDisplayRepresentations: [SubgroupOption: DisplayRepresentation] = [
        .app: "Как в приложении",
        .all: "Все пары",
        .first: "1 подгруппа",
        .second: "2 подгруппа"
    ]

    var resolved: Int? {
        switch self {
        case .app: return ScheduleStore.subgroup
        case .all: return nil
        case .first: return 1
        case .second: return 2
        }
    }
}
