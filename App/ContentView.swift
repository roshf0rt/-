import SwiftUI
import WidgetKit

struct ContentView: View {
    private let store = ScheduleStore()
    private let service = ScheduleService()

    @State private var group = ScheduleStore().selectedGroup ?? ""
    @State private var lessons = ScheduleStore().loadLessons()
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Группа") {
                    TextField("Например, ИЭФ-412", text: $group)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                    Button("Сохранить и обновить") {
                        Task { await save() }
                    }
                }

                Section("Сегодня") {
                    if lessons.today().isEmpty {
                        Text("Занятий нет")
                    } else {
                        ForEach(lessons.today()) { lesson in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(lesson.subject).font(.headline)
                                Text("\(time(lesson.start))–\(time(lesson.end))  \(lesson.room ?? "")")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage).foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Расписание УрФУ")
            .task {
                if !group.isEmpty { await save() }
            }
        }
    }

    private func save() async {
        let trimmed = group.trimmingCharacters(in: .whitespaces)
        store.selectedGroup = trimmed.isEmpty ? nil : trimmed
        do {
            try await service.refresh()
            lessons = store.loadLessons()
            errorMessage = nil
            WidgetCenter.shared.reloadAllTimelines()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func time(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
    }
}
