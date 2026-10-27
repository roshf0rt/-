import SwiftUI
import UserNotifications

/// Когда напомнить о заметке или домашнем задании.
enum NoteReminder: String, Codable, CaseIterable, Identifiable {
    case none, eveningBefore, morning, hourBefore

    var id: String { rawValue }

    var title: String {
        switch self {
        case .none: return "Не напоминать"
        case .eveningBefore: return "Накануне в 20:00"
        case .morning: return "В день пары в 8:00"
        case .hourBefore: return "За час до пары"
        }
    }

    func fireDate(for lesson: Lesson) -> Date? {
        let calendar = Calendar.current
        let day = calendar.startOfDay(for: lesson.startsAt)
        switch self {
        case .none:
            return nil
        case .eveningBefore:
            guard let previous = calendar.date(byAdding: .day, value: -1, to: day) else { return nil }
            return calendar.date(bySettingHour: 20, minute: 0, second: 0, of: previous)
        case .morning:
            return calendar.date(bySettingHour: 8, minute: 0, second: 0, of: day)
        case .hourBefore:
            return lesson.startsAt.addingTimeInterval(-60 * 60)
        }
    }
}

/// Заметка к конкретной паре. Пара хранится целиком, чтобы заметка не пропала,
/// когда пара уйдёт из загруженного расписания.
struct LessonNote: Codable, Identifiable, Equatable {
    var lesson: Lesson
    var text: String
    var isHomework: Bool
    var isDone: Bool
    var reminder: NoteReminder

    var id: String { lesson.id }
}

@MainActor
final class NotesStore: ObservableObject {
    @Published private(set) var notes: [String: LessonNote] = [:]
    private let key = "lesson.notes.v1"

    init() {
        if let data = UserDefaults.standard.data(forKey: key),
           let saved = try? JSONDecoder().decode([String: LessonNote].self, from: data) {
            notes = saved
        }
    }

    func note(for lesson: Lesson) -> LessonNote? { notes[lesson.id] }

    /// Невыполненное ДЗ, начиная с ближайшего; прошедшее больше недели назад не показываем.
    var openHomework: [LessonNote] {
        let cutoff = Date().addingTimeInterval(-7 * 24 * 60 * 60)
        return notes.values
            .filter { $0.isHomework && !$0.isDone && $0.lesson.startsAt > cutoff }
            .sorted { $0.lesson.startsAt < $1.lesson.startsAt }
    }

    func save(_ note: LessonNote) {
        if note.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            notes[note.id] = nil
        } else {
            notes[note.id] = note
        }
        persist()
    }

    func delete(_ note: LessonNote) {
        notes[note.id] = nil
        persist()
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(notes) {
            UserDefaults.standard.set(data, forKey: key)
        }
        let snapshot = Array(notes.values)
        Task { await Self.reschedule(snapshot) }
    }

    private static let prefix = "note-"

    static func reschedule(_ notes: [LessonNote]) async {
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests()
        center.removePendingNotificationRequests(withIdentifiers: pending.map(\.identifier).filter { $0.hasPrefix(prefix) })

        let now = Date()
        let due = notes.compactMap { note -> (LessonNote, Date)? in
            guard !note.isDone, let date = note.reminder.fireDate(for: note.lesson), date > now else { return nil }
            return (note, date)
        }
        guard !due.isEmpty, await LessonReminders.requestAuthorization() else { return }
        for (note, date) in due {
            let content = UNMutableNotificationContent()
            content.title = note.isHomework ? "ДЗ: \(note.lesson.subject)" : "Заметка: \(note.lesson.subject)"
            content.body = "\(note.text)\n\(RU.shortDay(note.lesson.startsAt)) в \(RU.time(note.lesson.startsAt)), каб. \(note.lesson.roomTitle)"
            content.sound = .default
            let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date)
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            try? await center.add(UNNotificationRequest(identifier: prefix + note.id, content: content, trigger: trigger))
        }
    }
}

struct NoteEditor: View {
    @ObservedObject var store: NotesStore
    @Environment(\.dismiss) private var dismiss
    @State private var note: LessonNote
    private let isNew: Bool

    init(lesson: Lesson, store: NotesStore) {
        self.store = store
        let existing = store.note(for: lesson)
        isNew = existing == nil
        _note = State(initialValue: existing ?? LessonNote(lesson: lesson, text: "", isHomework: false,
                                                           isDone: false, reminder: .none))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(note.lesson.subject).font(.headline)
                        Text("\(RU.dayTitle(note.lesson.startsAt)) · \(RU.timeRange(note.lesson)) · каб. \(note.lesson.roomTitle)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Текст") {
                    TextField("Что задали, что взять с собой…", text: $note.text, axis: .vertical)
                        .lineLimit(4...12)
                }

                Section {
                    Toggle("Домашнее задание", isOn: $note.isHomework)
                    if note.isHomework {
                        Toggle("Выполнено", isOn: $note.isDone)
                    }
                    Picker("Напомнить", selection: $note.reminder) {
                        ForEach(NoteReminder.allCases) { reminder in
                            Text(reminder.title).tag(reminder)
                        }
                    }
                }

                if !isNew {
                    Section {
                        Button("Удалить заметку", role: .destructive) {
                            store.delete(note)
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle(isNew ? "Новая заметка" : "Заметка")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Отмена") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Сохранить") {
                        store.save(note)
                        dismiss()
                    }
                }
            }
        }
        .environment(\.locale, RU.locale)
    }
}

/// Список невыполненного ДЗ над расписанием.
struct HomeworkSection: View {
    @ObservedObject var store: NotesStore
    let onOpen: (Lesson) -> Void

    var body: some View {
        let homework = store.openHomework
        if !homework.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Label("Домашние задания", systemImage: "checklist")
                    .font(.headline)
                ForEach(homework) { note in
                    Button {
                        onOpen(note.lesson)
                    } label: {
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: "circle")
                                .foregroundStyle(note.lesson.tint)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(note.text)
                                    .font(.subheadline.weight(.semibold))
                                    .lineLimit(2)
                                    .multilineTextAlignment(.leading)
                                Text("\(note.lesson.subject) · \(RU.shortDay(note.lesson.startsAt)) \(RU.time(note.lesson.startsAt))")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            Spacer(minLength: 0)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(14)
            .background(Color(uiColor: .secondarySystemGroupedBackground),
                        in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
    }
}
