import SwiftUI
import WidgetKit

@MainActor
final class ScheduleViewModel: ObservableObject {
    @Published var group = ScheduleStore.loadGroup()
    @Published var snapshot = ScheduleStore.load()
    @Published var loading = false
    @Published var error: String?
    private let api = ScheduleAPI()
    private var refreshID = UUID()

    func select(_ group: ScheduleGroup) async {
        self.group = group
        ScheduleStore.saveGroup(group)
        // Avoid showing the previous group's classes under the new group name.
        snapshot = ScheduleSnapshot(groupName: group.name, lessons: [], updatedAt: nil)
        ScheduleStore.save(snapshot)
        WidgetCenter.shared.reloadAllTimelines()
        await refresh()
    }

    func refresh() async {
        guard let group else { return }
        let requestID = UUID()
        refreshID = requestID
        loading = true
        error = nil
        defer { if refreshID == requestID { loading = false } }
        do {
            let lessons = try await api.fetchSchedule(for: group).sorted { $0.startsAt < $1.startsAt }
            // Ignore a response if the user selected another group in the meantime.
            guard self.group == group, refreshID == requestID else { return }
            snapshot = ScheduleSnapshot(groupName: group.name, lessons: lessons, updatedAt: Date())
            ScheduleStore.save(snapshot)
            WidgetCenter.shared.reloadAllTimelines()
        } catch {
            guard refreshID == requestID else { return }
            self.error = error.localizedDescription
        }
    }
}

struct ContentView: View {
    @StateObject private var model = ScheduleViewModel()
    @State private var choosingGroup = false
    @Environment(\.scenePhase) private var scenePhase
    private var upcoming: [Lesson] { model.snapshot.lessons.filter { $0.endsAt >= Date() } }
    private var days: [Date] {
        Array(Set(upcoming.map { Calendar.current.startOfDay(for: $0.startsAt) })).sorted()
    }

    var body: some View {
        NavigationStack {
            Group {
                if model.group == nil {
                    ContentUnavailableView {
                        Label("Выберите группу", systemImage: "calendar.badge.clock")
                    } description: {
                        Text("Найдите свою группу, чтобы увидеть занятия и добавить виджет на экран.")
                    } actions: {
                        Button("Найти группу") { choosingGroup = true }.buttonStyle(.borderedProminent)
                    }
                } else {
                    List {
                        if let error = model.error {
                            Section { Label(error, systemImage: "wifi.exclamationmark").foregroundStyle(.secondary) }
                        }
                        if model.loading && model.snapshot.updatedAt == nil {
                            ProgressView("Загружаем расписание")
                        } else if upcoming.isEmpty {
                            Section { Text("Предстоящих занятий нет").foregroundStyle(.secondary) }
                        }
                        ForEach(days, id: \.self) { day in
                            Section(day.formatted(.dateTime.weekday(.wide).day().month())) {
                                ForEach(upcoming.filter { Calendar.current.isDate($0.startsAt, inSameDayAs: day) }) { lesson in
                                    LessonRow(lesson: lesson)
                                }
                            }
                        }
                        if let updated = model.snapshot.updatedAt {
                            Section { Text("Обновлено: \(updated.formatted(date: .abbreviated, time: .shortened))").font(.footnote).foregroundStyle(.secondary) }
                        }
                    }
                    .refreshable { await model.refresh() }
                }
            }
            .navigationTitle("Расписание")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(model.group?.name ?? "Группа") { choosingGroup = true }
                }
            }
            .sheet(isPresented: $choosingGroup) { GroupPicker { group in Task { await model.select(group) } } }
            .task { if model.group != nil { await model.refresh() } }
            .onChange(of: scenePhase) { _, phase in if phase == .active { Task { await model.refresh() } } }
        }
    }
}

struct LessonRow: View {
    let lesson: Lesson
    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                if lesson.isTimeUnspecified {
                    Text("Время не указано").font(.caption).foregroundStyle(.secondary)
                } else {
                    Text(lesson.startsAt, style: .time).font(.headline)
                    Text(lesson.endsAt, style: .time).font(.caption).foregroundStyle(.secondary)
                }
            }.frame(width: 52, alignment: .leading)
            VStack(alignment: .leading, spacing: 5) {
                Text(lesson.title).font(.headline)
                if !lesson.location.isEmpty { Label(lesson.location, systemImage: "mappin.and.ellipse").font(.subheadline).foregroundStyle(.secondary) }
                if !lesson.teacher.isEmpty { Text(lesson.teacher).font(.subheadline).foregroundStyle(.secondary) }
            }
        }.padding(.vertical, 4)
    }
}

struct GroupPicker: View {
    let onSelect: (ScheduleGroup) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var groups: [ScheduleGroup] = []
    @State private var loading = false
    @State private var error = false
    private let api = ScheduleAPI()

    var body: some View {
        NavigationStack {
            Group {
                if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    ContentUnavailableView.search(text: "Введите название группы")
                } else if loading {
                    ProgressView("Ищем группы")
                } else if error {
                    ContentUnavailableView("Не удалось найти группы", systemImage: "wifi.exclamationmark", description: Text("Проверьте подключение и попробуйте снова."))
                } else if groups.isEmpty {
                    ContentUnavailableView.search(text: query)
                } else {
                    List(groups) { group in
                        Button(group.name) { onSelect(group); dismiss() }
                    }
                }
            }
            .navigationTitle("Группа")
            .searchable(text: $query, prompt: "Например, РИ-230001")
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Готово") { dismiss() } } }
            .task(id: query) {
                let search = query.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !search.isEmpty else { groups = []; loading = false; error = false; return }
                loading = true; error = false
                do {
                    try await Task.sleep(for: .milliseconds(350))
                    let found = try await api.searchGroups(query: search)
                    guard !Task.isCancelled else { return }
                    groups = found; loading = false
                } catch {
                    guard !Task.isCancelled else { return }
                    groups = []; loading = false; self.error = true
                }
            }
        }
    }
}
