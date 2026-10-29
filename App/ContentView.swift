import SwiftUI
import WidgetKit

@MainActor
final class ScheduleViewModel: ObservableObject {
    @Published private(set) var group = ScheduleStore.loadGroup()
    @Published private(set) var snapshot: ScheduleSnapshot?
    @Published private(set) var loading = false
    @Published private(set) var error: String?
    @Published var subgroup = ScheduleStore.subgroup {
        didSet {
            ScheduleStore.subgroup = subgroup
            shareWithWidget()
            updateReminders()
        }
    }
    /// За сколько минут напоминать о паре; 0 — не напоминать.
    @Published var reminderMinutes = LessonReminders.minutesBefore {
        didSet {
            LessonReminders.minutesBefore = reminderMinutes
            updateReminders()
        }
    }
    @Published private(set) var notificationsDenied = false
    /// Сообщение, когда пары закончились, и о каникулах.
    @Published var moodNotifications = LessonReminders.moodsEnabled {
        didSet {
            LessonReminders.moodsEnabled = moodNotifications
            updateReminders()
        }
    }
    @Published var useLocation = ScheduleStore.useLocation {
        didSet {
            ScheduleStore.useLocation = useLocation
            shareWithWidget()
        }
    }
    @Published var theme = AppTheme.current {
        didSet {
            AppTheme.current = theme
            ScheduleStore.theme = theme.rawValue
            shareWithWidget()
        }
    }
    /// Живая карточка пары на экране блокировки и на часах.
    @Published var liveActivity = LiveActivities.enabled {
        didSet {
            LiveActivities.enabled = liveActivity
            syncCompanions()
        }
    }
    @Published var liveActivityInIsland = LiveActivities.showsInIsland {
        didSet {
            LiveActivities.showsInIsland = liveActivityInIsland
            syncCompanions()
        }
    }
    private let api = ScheduleAPI()
    private var refreshID = UUID()

    init() {
        if let group { snapshot = ScheduleStore.snapshot(for: group.id) }
        shareWithWidget()
    }

    /// Whether the widget can see these settings.
    var widgetLinkWorks: Bool {
        SharedSettings.load() == sharedValues || (AppGroup.isShared && Entitlements.partnerKnown)
    }

    private func updateReminders() {
        let lessons = self.lessons
        let minutes = reminderMinutes
        Task {
            await LessonReminders.reschedule(lessons, minutesBefore: minutes)
            await LessonReminders.rescheduleMoods(lessons, enabled: moodNotifications)
            if minutes > 0 { notificationsDenied = !(await LessonReminders.requestAuthorization()) }
        }
    }

    private var sharedValues: SharedSettings.Values {
        SharedSettings.Values(group: group, subgroup: subgroup, theme: theme.rawValue, useLocation: useLocation)
    }

    private func shareWithWidget() {
        SharedSettings.save(sharedValues)
        WidgetCenter.shared.reloadAllTimelines()
        syncCompanions()
    }

    /// The Live Activity and the watch app follow the same group, subgroup and colour.
    func syncCompanions() {
        let lessons = self.lessons
        let theme = self.theme
        WatchLink.shared.send(group: group, subgroup: subgroup, theme: theme.rawValue, lessons: lessons)
        guard let name = group?.name else { return }
        Task { await LiveActivities.sync(lessons: lessons, groupName: name, theme: theme, canStart: true) }
    }

    var lessons: [Lesson] { (snapshot?.lessons ?? []).visible(forSubgroup: subgroup) }

    var hasSubgroups: Bool { snapshot?.lessons.contains { $0.subgroup != nil } ?? false }

    func select(_ group: ScheduleGroup) async {
        self.group = group
        ScheduleStore.saveGroup(group)
        snapshot = ScheduleStore.snapshot(for: group.id)
        shareWithWidget()
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
            // A separate task, so the request survives when SwiftUI cancels the calling task
            // (pull to refresh, the launch task and returning to the app can overlap).
            let api = self.api
            let lessons = try await Task { try await api.fetchSchedule(for: group) }.value
            // Ignore a response if the user selected another group in the meantime.
            guard self.group == group, refreshID == requestID else { return }
            let fresh = ScheduleSnapshot(group: group, lessons: lessons, updatedAt: Date())
            snapshot = fresh
            ScheduleStore.save(fresh)
            WidgetCenter.shared.reloadAllTimelines()
            updateReminders()
            syncCompanions()
        } catch {
            guard refreshID == requestID else { return }
            if error is CancellationError || (error as? URLError)?.code == .cancelled { return }
            self.error = error.localizedDescription
        }
    }
}

struct ContentView: View {
    @StateObject private var model = ScheduleViewModel()
    @StateObject private var notes = NotesStore()
    @StateObject private var community = CommunityStore()
    @State private var choosingGroup = false
    @State private var showingSettings = false
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        NavigationStack {
            Group {
                if model.group == nil {
                    ScrollView {
                        VStack(spacing: 16) {
                            WelcomeCard()
                            ContentUnavailableView {
                                Label("Выберите группу", systemImage: "calendar.badge.clock")
                            } description: {
                                Text("Найдите свою группу, чтобы видеть пары в приложении и в виджетах.")
                            } actions: {
                                Button("Найти группу") { choosingGroup = true }
                                    .buttonStyle(.borderedProminent)
                            }
                            CreditFooter()
                        }
                        .padding(16)
                    }
                } else {
                    ScheduleList(model: model, notes: notes, community: community)
                }
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle(model.group?.name ?? "Расписание")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingSettings = true
                    } label: {
                        Image(systemName: "slider.horizontal.3")
                    }
                    .accessibilityLabel("Настройки")
                }
            }
            .sheet(isPresented: $choosingGroup) {
                GroupPicker { group in Task { await model.select(group) } }
            }
            .sheet(isPresented: $showingSettings) {
                SettingsView(model: model, community: community)
            }
            .task {
                await model.refresh()
                await community.refresh(group: model.group)
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active {
                    model.syncCompanions()
                    Task {
                        await model.refresh()
                        await community.refresh(group: model.group)
                    }
                }
            }
        }
        .environment(\.locale, RU.locale)
    }
}

/// Пары кончились или каникулы — вместо пустого места.
private struct MoodCard: View {
    let lessons: [Lesson]
    let now: Date

    var body: some View {
        if let days = Mood.vacationDays(lessons, now: now) {
            card(Mood.line(Mood.vacationLines, on: now), detail: "До первой пары \(days) дн.", icon: Mood.vacationEmoji)
        } else if Mood.dayDone(lessons, now: now) {
            card(Mood.line(Mood.dayDoneLines, on: now), detail: "Свободны до завтра", icon: "🎉")
        }
    }

    private func card(_ title: String, detail: String, icon: String) -> some View {
        HStack(spacing: 12) {
            Text(icon)
                .font(.largeTitle)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(detail).font(.footnote).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
    }
}

private struct ScheduleList: View {
    @ObservedObject var model: ScheduleViewModel
    @ObservedObject var notes: NotesStore
    @ObservedObject var community: CommunityStore
    @State private var editing: Lesson?

    var body: some View {
        // The scroll view stays outside the timeline: rebuilding it every 30 seconds
        // left the pull-to-refresh indicator stuck with an empty gap above the title.
        ScrollView {
            TimelineView(.periodic(from: .now, by: 30)) { context in
                let now = context.date
                let upcoming = model.lessons.filter { $0.endsAt > now }
                let days = Dictionary(grouping: upcoming) { Calendar.current.startOfDay(for: $0.startsAt) }

                VStack(alignment: .leading, spacing: 12) {
                    WelcomeCard()

                    if let error = model.error {
                        Label(error, systemImage: "wifi.exclamationmark")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 4)
                    }

                    if model.hasSubgroups {
                        SubgroupPicker(selection: $model.subgroup)
                    }

                    if let focus = upcoming.focus(at: now) {
                        FocusCard(lesson: focus, now: now)
                    } else {
                        MoodCard(lessons: model.lessons, now: now)
                    }

                    HomeworkSection(store: notes, community: community, lessons: model.lessons) { editing = $0 }

                    if model.loading && model.snapshot == nil {
                        ProgressView("Загружаем расписание")
                            .frame(maxWidth: .infinity)
                            .padding(.top, 40)
                    } else if upcoming.isEmpty {
                        ContentUnavailableView("Пар нет", systemImage: "cup.and.saucer",
                                               description: Text("В ближайшие две недели занятий не найдено."))
                    }

                    ForEach(days.keys.sorted(), id: \.self) { day in
                        Text(RU.dayTitle(day, now: now))
                            .font(.title3.weight(.bold))
                            .padding(.top, 12)
                            .padding(.horizontal, 4)
                        ForEach(days[day] ?? []) { lesson in
                            LessonCard(lesson: lesson, now: now, note: notes.note(for: lesson),
                                       sharedCount: community.sharedHomework(for: lesson).filter { !$0.mine }.count)
                                .contentShape(Rectangle())
                                .onTapGesture { editing = lesson }
                        }
                    }

                    if let updated = model.snapshot?.updatedAt {
                        Text("Обновлено \(RU.shortDay(updated, now: now).lowercased(with: RU.locale)) в \(RU.time(updated))")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                    }

                    CreditFooter()
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
            }
        }
        .refreshable {
            // A refresh that ends almost at once can leave the indicator stuck.
            let started = Date()
            await model.refresh()
            await community.refresh(group: model.group)
            let remaining = 0.7 - Date().timeIntervalSince(started)
            if remaining > 0 { try? await Task.sleep(for: .seconds(remaining)) }
        }
        .sheet(item: $editing) { lesson in
            NoteEditor(lesson: lesson, schedule: model.lessons, store: notes, community: community, group: model.group)
        }
    }
}

struct SubgroupPicker: View {
    @Binding var selection: Int?

    var body: some View {
        Picker("Подгруппа", selection: $selection) {
            Text("Все пары").tag(Int?.none)
            Text("1 подгруппа").tag(Int?.some(1))
            Text("2 подгруппа").tag(Int?.some(2))
        }
        .pickerStyle(.segmented)
    }
}

/// Текущая или ближайшая пара с крупным номером кабинета.
private struct FocusCard: View {
    let lesson: Lesson
    let now: Date

    private var isCurrent: Bool { lesson.isOngoing(at: now) }
    private var color: Color { lesson.tint }

    private var details: String {
        var parts = [lesson.lessonKind.title]
        if let subgroup = lesson.subgroup { parts.append("\(subgroup) подгруппа") }
        if !lesson.shortAddress.isEmpty { parts.append(lesson.shortAddress) }
        if lesson.isHybrid { parts.append("гибрид") }
        return parts.joined(separator: " · ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(isCurrent ? "СЕЙЧАС" : "СЛЕДУЮЩАЯ ПАРА")
                    .font(.caption.weight(.heavy))
                    .tracking(0.6)
                Spacer()
                Text(isCurrent ? RU.minutesLeft(until: lesson.endsAt, now: now) : RU.startsIn(lesson, now: now))
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(.white.opacity(0.2), in: Capsule())
            }

            HStack(alignment: .lastTextBaseline) {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Кабинет")
                        .font(.caption.weight(.medium))
                        .opacity(0.8)
                    Text(lesson.roomTitle)
                        .font(.system(size: 52, weight: .heavy, design: .rounded))
                        .lineLimit(1)
                        .minimumScaleFactor(0.4)
                }
                Spacer(minLength: 12)
                VStack(alignment: .trailing, spacing: 0) {
                    Text(RU.time(lesson.startsAt))
                        .font(.title2.weight(.bold))
                    Text(RU.time(lesson.endsAt))
                        .font(.subheadline)
                        .opacity(0.8)
                }
                .monospacedDigit()
                .lineLimit(1)
                .fixedSize()
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(lesson.subject)
                    .font(.headline)
                    .lineLimit(2)
                Text(details)
                    .font(.subheadline)
                    .opacity(0.85)
                    .lineLimit(2)
            }

            if isCurrent {
                ProgressView(value: now.timeIntervalSince(lesson.startsAt),
                             total: lesson.endsAt.timeIntervalSince(lesson.startsAt))
                    .tint(.white)
            }
        }
        .foregroundStyle(.white)
        .padding(18)
        .background(
            LinearGradient(colors: [color, color.opacity(0.65)], startPoint: .topLeading, endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: 26, style: .continuous)
        )
        .padding(.top, 4)
    }
}

private struct LessonCard: View {
    let lesson: Lesson
    let now: Date

    var note: LessonNote?
    var sharedCount = 0

    private var isCurrent: Bool { lesson.isOngoing(at: now) }
    private var kind: LessonKind { lesson.lessonKind }

    /// The larger iPhones (Plus and Pro Max) have room for a slightly bigger time.
    private static var isWideScreen: Bool { UIScreen.main.bounds.width >= 430 }
    private static var startFont: Font { isWideScreen ? .title2.weight(.semibold) : .title3.weight(.semibold) }
    private static var endFont: Font { isWideScreen ? .body : .subheadline }

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                if lesson.isTimeUnspecified {
                    Text("—").font(.title3.weight(.semibold))
                } else {
                    Text(RU.time(lesson.startsAt)).font(Self.startFont)
                    Text(RU.time(lesson.endsAt)).font(Self.endFont).foregroundStyle(.secondary)
                }
            }
            .monospacedDigit()
            // A time like 10:00 must never wrap onto a second line, even on the narrow Pro screens.
            .lineLimit(1)
            .fixedSize()
            .frame(minWidth: 58, alignment: .leading)

            VStack(alignment: .leading, spacing: 7) {
                Text(lesson.subject)
                    .font(.headline)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 6) {
                    Chip(kind.title, color: lesson.tint)
                    if let subgroup = lesson.subgroup {
                        Chip("\(subgroup) подгруппа", color: .mint)
                    }
                    if lesson.isHybrid {
                        Chip("Гибрид", color: .indigo)
                    }
                    if isCurrent {
                        Chip("Идёт сейчас", color: .green)
                    }
                    if let note, note.isHomework {
                        Chip(note.isDone ? "ДЗ готово" : "ДЗ", color: note.isDone ? .green : .red)
                    }
                    if sharedCount > 0 {
                        Chip("ДЗ группы: \(sharedCount)", color: .purple)
                    }
                }

                if !lesson.room.isEmpty || !lesson.shortAddress.isEmpty {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Image(systemName: "door.left.hand.open")
                            .foregroundStyle(.secondary)
                        Text(lesson.roomTitle).fontWeight(.bold)
                        if !lesson.shortAddress.isEmpty {
                            Text(lesson.shortAddress).foregroundStyle(.secondary)
                        }
                    }
                    .font(.subheadline)
                }

                if !lesson.teacher.isEmpty {
                    Label(lesson.teacher, systemImage: "person")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                if let note {
                    Label(note.text, systemImage: note.isHomework ? "book.closed" : "note.text")
                        .font(.subheadline)
                        .foregroundStyle(note.isHomework && !note.isDone ? lesson.tint : .secondary)
                        .lineLimit(2)
                }
            }
            .padding(.leading, 12)
            .overlay(alignment: .leading) {
                Capsule().fill(lesson.tint).frame(width: 4)
            }

            Spacer(minLength: 0)
        }
        .padding(14)
        .background(Color(uiColor: .secondarySystemGroupedBackground),
                    in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(isCurrent ? Color.green.opacity(0.7) : .clear, lineWidth: 1.5)
        }
    }
}
