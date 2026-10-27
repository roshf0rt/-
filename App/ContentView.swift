import SwiftUI
import WidgetKit

struct ContentView: View {
    private let store = ScheduleStore()

    @State private var weekly = ScheduleStore().load()
    @State private var isAdding = false

    var body: some View {
        NavigationStack {
            List {
                Section("Сегодня") {
                    let today = weekly.lessons()
                    if today.isEmpty {
                        Text("Сегодня занятий нет")
                    } else {
                        ForEach(today) { lesson in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(lesson.subject).font(.headline)
                                Text("\(time(lesson.start))–\(time(lesson.end))  \(lesson.room)")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                Section("Всё расписание") {
                    ForEach(weekly) { item in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.subject).font(.headline)
                            Text("\(weekdayName(item.weekday)), \(minutesText(item.startMinute))–\(minutesText(item.endMinute))  \(item.room)")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .onDelete(perform: delete)
                }
            }
            .navigationTitle("Расписание")
            .toolbar {
                Button {
                    isAdding = true
                } label: {
                    Image(systemName: "plus")
                }
            }
            .sheet(isPresented: $isAdding) {
                AddLessonView { lesson in
                    add(lesson)
                }
            }
        }
    }

    private func add(_ lesson: WeeklyLesson) {
        weekly.append(lesson)
        weekly.sort { ($0.weekday, $0.startMinute) < ($1.weekday, $1.startMinute) }
        saveAndRefresh()
    }

    private func delete(at offsets: IndexSet) {
        weekly.remove(atOffsets: offsets)
        saveAndRefresh()
    }

    private func saveAndRefresh() {
        store.save(weekly)
        WidgetCenter.shared.reloadAllTimelines()
    }

    private func time(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
    }

    private func weekdayName(_ weekday: Int) -> String {
        Calendar.current.weekdaySymbols[weekday - 1].capitalized
    }

    private func minutesText(_ minutes: Int) -> String {
        String(format: "%02d:%02d", minutes / 60, minutes % 60)
    }
}

struct AddLessonView: View {
    @Environment(\.dismiss) private var dismiss
    let onSave: (WeeklyLesson) -> Void

    @State private var subject = ""
    @State private var room = ""
    @State private var weekday = 2
    @State private var start = Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: .now) ?? .now
    @State private var end = Calendar.current.date(bySettingHour: 10, minute: 30, second: 0, of: .now) ?? .now

    /// Порядок дней: понедельник первым, воскресенье последним.
    private let weekdays = [2, 3, 4, 5, 6, 7, 1]

    var body: some View {
        NavigationStack {
            Form {
                TextField("Предмет", text: $subject)
                TextField("Аудитория", text: $room)
                Picker("День недели", selection: $weekday) {
                    ForEach(weekdays, id: \.self) { day in
                        Text(Calendar.current.weekdaySymbols[day - 1].capitalized).tag(day)
                    }
                }
                DatePicker("Начало", selection: $start, displayedComponents: .hourAndMinute)
                DatePicker("Конец", selection: $end, displayedComponents: .hourAndMinute)
            }
            .navigationTitle("Новое занятие")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Сохранить") {
                        onSave(makeLesson())
                        dismiss()
                    }
                    .disabled(subject.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    private func makeLesson() -> WeeklyLesson {
        let calendar = Calendar.current
        func minutes(_ date: Date) -> Int {
            calendar.component(.hour, from: date) * 60 + calendar.component(.minute, from: date)
        }
        return WeeklyLesson(
            subject: subject.trimmingCharacters(in: .whitespaces),
            room: room.trimmingCharacters(in: .whitespaces),
            weekday: weekday,
            startMinute: minutes(start),
            endMinute: minutes(end)
        )
    }
}
