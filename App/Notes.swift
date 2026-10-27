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
    @ObservedObject var community: CommunityStore
    @Environment(\.dismiss) private var dismiss
    @State private var note: LessonNote
    @State private var shareScope: ShareScope
    @State private var nickname = ""
    private let group: ScheduleGroup?
    /// Занятие, к которому относится ДЗ.
    @State private var targetID: String
    private let isNew: Bool
    /// Эта пара, если она ещё не началась, и следующие занятия по тому же предмету.
    private let candidates: [Lesson]

    init(lesson: Lesson, schedule: [Lesson], store: NotesStore, community: CommunityStore, group: ScheduleGroup?) {
        self.store = store
        self.community = community
        self.group = group
        let existing = store.note(for: lesson)
        isNew = existing == nil
        // New notes share like last time; re-saving an old note does not post it again.
        let lastScope = UserDefaults.standard.string(forKey: Self.lastScopeKey).flatMap(ShareScope.init(rawValue:))
        _shareScope = State(initialValue: existing == nil ? (lastScope ?? .none) : .none)
        _note = State(initialValue: existing ?? LessonNote(lesson: lesson, text: "", isHomework: false,
                                                           isDone: false, reminder: .none))
        let later = schedule.filter {
            $0.subject == lesson.subject && $0.startsAt > lesson.startsAt && $0.id != lesson.id
        }
        candidates = (lesson.startsAt > Date() ? [lesson] : []) + later.prefix(6)
        // Homework given at a pair that has already started is due next time by default.
        _targetID = State(initialValue: candidates.first?.id ?? lesson.id)
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

                let shared = community.sharedHomework(for: note.lesson)
                if !shared.isEmpty {
                    Section("ДЗ от одногруппников") {
                        SharedHomeworkList(community: community, items: shared) { item in
                            note.text = note.text.isEmpty ? item.text : note.text + "\n" + item.text
                            note.isHomework = true
                        }
                    }
                }

                Section {
                    Toggle("Домашнее задание", isOn: $note.isHomework)
                    if note.isHomework {
                        if !candidates.isEmpty {
                            Picker("К занятию", selection: $targetID) {
                                ForEach(candidates) { lesson in
                                    Text(candidateTitle(lesson)).tag(lesson.id)
                                }
                            }
                        }
                        Toggle("Выполнено", isOn: $note.isDone)
                    }
                    Picker("Напомнить", selection: $note.reminder) {
                        ForEach(NoteReminder.allCases) { reminder in
                            Text(reminder.title).tag(reminder)
                        }
                    }
                } footer: {
                    if note.isHomework && candidates.isEmpty {
                        Text("Следующего занятия по этому предмету в ближайшие две недели нет, ДЗ останется у этой пары.")
                    } else if note.isHomework {
                        Text("ДЗ появится у выбранного занятия, и напоминание сработает относительно него.")
                    }
                }

                if note.isHomework {
                    Section {
                        Picker("Поделиться", selection: $shareScope) {
                            ForEach(ShareScope.allCases) { scope in
                                Text(scope.title).tag(scope)
                            }
                        }
                        if shareScope != .none && !community.hasProfile {
                            TextField("Ваш ник для общего ДЗ", text: $nickname)
                                .autocorrectionDisabled()
                        }
                    } header: {
                        Text("Общее ДЗ")
                    } footer: {
                        if shareScope == .stream && community.stream.isEmpty {
                            Text("Группы потока не выбраны — добавьте их в настройках. Пока ДЗ увидит только ваша группа.")
                        } else if shareScope != .none {
                            Text("Запись увидят с вашим ником; удалить её можно здесь же.")
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
                        save()
                        dismiss()
                    }
                }
            }
        }
        .environment(\.locale, RU.locale)
    }

    private func candidateTitle(_ lesson: Lesson) -> String {
        let label = lesson.id == note.lesson.id ? "эта пара" : RU.shortDay(lesson.startsAt)
        return "\(label), \(RU.time(lesson.startsAt)) · \(lesson.lessonKind.title.lowercased(with: RU.locale))"
    }

    private static let lastScopeKey = "community.lastScope.v1"

    private func save() {
        let text = note.text.trimmingCharacters(in: .whitespacesAndNewlines)
        let lesson = saveLocally()
        guard note.isHomework, shareScope != .none, !text.isEmpty else { return }
        UserDefaults.standard.set(shareScope.rawValue, forKey: Self.lastScopeKey)
        let scope = shareScope
        let name = nickname.trimmingCharacters(in: .whitespacesAndNewlines)
        let group = self.group
        let community = self.community
        Task {
            if !community.hasProfile, let group, name.count >= 2 {
                await community.saveProfile(nickname: name, group: group)
            }
            await community.share(text: text, lesson: lesson, scope: scope, group: group)
        }
    }

    /// Saves the note and returns the pair it ended up attached to.
    private func saveLocally() -> Lesson {
        guard note.isHomework,
              let target = candidates.first(where: { $0.id == targetID }),
              target.id != note.lesson.id else {
            store.save(note)
            return note.lesson
        }
        var moved = note
        moved.lesson = target
        // Keep homework already written for that pair.
        if let existing = store.note(for: target), !existing.text.isEmpty {
            moved.text = existing.text + "\n" + note.text
        }
        if !isNew { store.delete(note) }
        store.save(moved)
        return target
    }
}

/// Список невыполненного ДЗ над расписанием.
struct HomeworkSection: View {
    @ObservedObject var store: NotesStore
    @ObservedObject var community: CommunityStore
    let lessons: [Lesson]
    let onOpen: (Lesson) -> Void

    var body: some View {
        let homework = store.openHomework
        let recent = Date().addingTimeInterval(-2 * 60 * 60)
        let shared = Array(community.visibleItems.filter { !$0.mine && $0.lessonStart > recent }.prefix(5))
        if !homework.isEmpty || !shared.isEmpty {
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
                if !shared.isEmpty {
                    Label("От одногруппников", systemImage: "person.2")
                        .font(.subheadline.weight(.semibold))
                        .padding(.top, 4)
                    ForEach(shared) { item in
                        Button {
                            if let lesson = lessons.first(where: { $0.shareKey == item.lessonKey }) { onOpen(lesson) }
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.text)
                                    .font(.subheadline.weight(.semibold))
                                    .lineLimit(2)
                                    .multilineTextAlignment(.leading)
                                Text("\(item.subject) · \(RU.shortDay(item.lessonStart)) \(RU.time(item.lessonStart)) · \(item.author.nickname)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(14)
            .background(Color(uiColor: .secondarySystemGroupedBackground),
                        in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
    }
}
