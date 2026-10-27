import SwiftUI

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
                    ContentUnavailableView("Найдите группу", systemImage: "magnifyingglass",
                                           description: Text("Введите номер группы, например УГИ-433510."))
                } else if loading {
                    ProgressView("Ищем группы")
                } else if error {
                    ContentUnavailableView("Не удалось найти группы", systemImage: "wifi.exclamationmark",
                                           description: Text("Проверьте подключение и попробуйте снова."))
                } else if groups.isEmpty {
                    ContentUnavailableView.search(text: query)
                } else {
                    List(groups) { group in
                        Button(group.name) { onSelect(group); dismiss() }
                    }
                }
            }
            .navigationTitle("Группа")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Номер группы")
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
