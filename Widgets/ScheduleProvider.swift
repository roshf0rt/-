import WidgetKit

struct ScheduleEntry: TimelineEntry {
    enum Status { case ready, noGroup, noData }

    let date: Date
    let status: Status
    let groupName: String
    /// Уже отфильтрованы по подгруппе и отсортированы.
    let lessons: [Lesson]
    /// Насколько далеко корпуса — по геолокации, если она разрешена.
    var hurry = HurryInfo()

    var focus: Lesson? { lessons.focus(at: date) }
    var agenda: (day: Date, lessons: [Lesson])? { lessons.agenda(at: date) }

    /// Пара, которая идёт после текущей или ближайшей.
    var following: Lesson? {
        guard let focus else { return nil }
        return lessons.next(after: focus.startsAt)
    }
}

/// A static provider: configurable (App Intents) widgets stay blank when the IPA is
/// re-signed without App Groups, while static ones render.
struct ScheduleProvider: TimelineProvider {
    private static let staleAfter: TimeInterval = 60 * 60
    private static let ringStep: TimeInterval = 2 * 60
    private static let ringHorizon: TimeInterval = 3 * 60 * 60

    func placeholder(in context: Context) -> ScheduleEntry { .preview }

    func getSnapshot(in context: Context, completion: @escaping (ScheduleEntry) -> Void) {
        if context.isPreview {
            completion(.preview)
            return
        }
        Task {
            completion(await Self.entries(now: Date(), allowNetwork: false).first ?? .preview)
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<ScheduleEntry>) -> Void) {
        Task {
            let now = Date()
            let entries = await Self.entries(now: now, allowNetwork: true)
            let hasData = entries.first?.status == .ready
            // Reload before the ring entries run out, at the latest after the cache goes stale.
            // With location on, refresh often before a pair so the distance stays current.
            let pairSoon = entries.first.map { entry in
                entry.lessons.contains { $0.startsAt > now && $0.startsAt.timeIntervalSince(now) < 60 * 60 }
            } ?? false
            let tracking = !(entries.first?.hurry.distances.isEmpty ?? true)
            let reload = !hasData ? 15 * 60 : (tracking && pairSoon ? 15 * 60 : min(Self.staleAfter, Self.ringHorizon))
            completion(Timeline(entries: entries, policy: .after(now.addingTimeInterval(reload))))
        }
    }

    private static func entries(now: Date, allowNetwork: Bool) async -> [ScheduleEntry] {
        // The theme may have changed in the app since the extension was launched.
        AppTheme.current = AppTheme.stored
        guard let settings = await resolveSettings(allowNetwork: allowNetwork) else {
            return [ScheduleEntry(date: now, status: .noGroup, groupName: "", lessons: [])]
        }
        let (group, subgroup) = settings

        var snapshot = ScheduleStore.snapshot(for: group.id)
        if allowNetwork, snapshot.map({ now.timeIntervalSince($0.updatedAt) > staleAfter }) ?? true {
            WidgetLog.add("\(group.name): загрузка (кэш \(snapshot == nil ? "пуст" : "устарел"))")
            do {
                // Widgets get only a few seconds; a slow site must not leave a blank placeholder.
                let lessons = try await withDeadline(8) { try await ScheduleAPI(timeout: 7).fetchSchedule(for: group) }
                let fresh = ScheduleSnapshot(group: group, lessons: lessons, updatedAt: now)
                ScheduleStore.save(fresh)
                snapshot = fresh
                WidgetLog.add("\(group.name): загружено пар \(lessons.count)")
            } catch {
                WidgetLog.add("\(group.name): ошибка — \(error.localizedDescription)")
            }
        }
        guard let snapshot else {
            return [ScheduleEntry(date: now, status: .noData, groupName: group.name, lessons: [])]
        }

        let lessons = snapshot.lessons.visible(forSubgroup: subgroup)
        var hurry = allowNetwork ? await travelInfo(for: lessons, now: now) : HurryInfo()
        hurry.leads = hurryLeads(for: lessons)
        // Redraw at every start and end of a pair, when it is time to go, and at midnight
        // for the day view. During a pair, every 2 minutes so the ring shrinks; that is
        // limited to the next hours, after which the timeline is reloaded.
        let calendar = Calendar.current
        let horizon = now.addingTimeInterval(24 * 60 * 60)
        var dates: Set<Date> = [now]
        for lesson in lessons where !lesson.isTimeUnspecified {
            let leave = lesson.startsAt.addingTimeInterval(-hurry.lead(for: lesson))
            let settle = lesson.startsAt.addingTimeInterval(-30 * 60)
            for date in [leave, settle, lesson.startsAt, lesson.endsAt] where date > now && date < horizon {
                dates.insert(date)
            }
            var tick = max(lesson.startsAt, now).addingTimeInterval(ringStep)
            while tick < lesson.endsAt && tick < now.addingTimeInterval(ringHorizon) {
                dates.insert(tick)
                tick = tick.addingTimeInterval(ringStep)
            }
        }
        if let midnight = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) {
            dates.insert(midnight)
        }
        return dates.sorted().map {
            ScheduleEntry(date: $0, status: .ready, groupName: group.name, lessons: lessons, hurry: hurry)
        }
    }

    /// Only the first pair of a day and a pair after a break are urgent; other pairs are not.
    private static func hurryLeads(for lessons: [Lesson]) -> [String: TimeInterval] {
        let calendar = Calendar.current
        var leads: [String: TimeInterval] = [:]
        var previous: Lesson?
        for lesson in lessons.filter({ !$0.isTimeUnspecified }).sorted(by: { $0.startsAt < $1.startsAt }) {
            if let before = previous, calendar.isDate(before.startsAt, inSameDayAs: lesson.startsAt) {
                if before.endsAt <= lesson.startsAt { leads[lesson.id] = TimeInterval(Hurry.breakSeconds) }
            } else {
                leads[lesson.id] = TimeInterval(Hurry.minutes * 60)
            }
            previous = lesson
        }
        return leads
    }

    /// Distances from where you are to the buildings of the next day's pairs.
    private static func travelInfo(for lessons: [Lesson], now: Date) async -> HurryInfo {
        // Save battery: only if allowed in the app, never during a pair (you are already
        // there), and only in the hour before one.
        let enabled = SharedSettings.load()?.useLocation ?? (AppGroup.isShared ? ScheduleStore.useLocation : true)
        guard enabled, !lessons.contains(where: { $0.isOngoing(at: now) }) else { return HurryInfo() }
        let addresses = Set(lessons
            .filter { !$0.isTimeUnspecified && $0.startsAt > now && $0.startsAt.timeIntervalSince(now) < 60 * 60 }
            .map(\.shortAddress)
            .filter { !$0.isEmpty })
        guard !addresses.isEmpty else { return HurryInfo() }
        let locator = await MainActor.run { WidgetLocator() }
        guard let here = (try? await withDeadline(5) { await locator.current() }) ?? nil else {
            return HurryInfo()
        }
        var info = HurryInfo()
        for address in addresses.prefix(4) {
            if let building = await CampusGeocoder.coordinate(for: address) {
                info.distances[address] = here.location.distance(from: building.location)
            }
        }
        WidgetLog.add("геолокация: \(info.distances.map { "\($0.key) \(Int($0.value)) м" }.joined(separator: ", "))")
        return info
    }

    /// Where the group comes from, in order: the shared App Group, the keychain (the app
    /// writes it there, and it survives re-signing), then the build-time default.
    private static func resolveSettings(allowNetwork: Bool) async -> (ScheduleGroup, Int?)? {
        if let shared = SharedSettings.load(), let group = shared.group {
            return (group, shared.subgroup)
        }
        if AppGroup.isShared, let group = ScheduleStore.loadGroup() {
            return (group, ScheduleStore.subgroup)
        }
        // With a working link the app decides; the build-time group is only for installs
        // where the app cannot reach the widget at all.
        guard Entitlements.sharedAppGroup == nil, Entitlements.sharedKeychainGroup == nil,
              let group = await defaultGroup(allowNetwork: allowNetwork) else { return nil }
        return (group, WidgetDefaults.subgroup)
    }

    /// The build-time default, looked up once on the site and cached in the widget's own storage.
    private static func defaultGroup(allowNetwork: Bool) async -> ScheduleGroup? {
        if let group = ScheduleStore.loadGroup(), group.name == WidgetDefaults.groupName { return group }
        guard allowNetwork else { return nil }
        let name = WidgetDefaults.groupName
        do {
            let found = try await withDeadline(6) { try await ScheduleAPI(timeout: 5).searchGroups(query: name) }
            guard let group = found.first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) ?? found.first else {
                WidgetLog.add("группа \(name) не найдена")
                return nil
            }
            ScheduleStore.saveGroup(group)
            return group
        } catch {
            WidgetLog.add("поиск группы \(name): ошибка — \(error.localizedDescription)")
            return nil
        }
    }
}

extension ScheduleEntry {
    static var preview: ScheduleEntry {
        let now = Date()
        func lesson(_ subject: String, _ kind: String, room: String, startsIn offset: TimeInterval, subgroup: Int? = nil) -> Lesson {
            Lesson(id: "\(subject)-\(offset)", subject: subject, kind: kind,
                   startsAt: now.addingTimeInterval(offset), endsAt: now.addingTimeInterval(offset + 90 * 60),
                   room: room, address: "Ленина, 51", teacher: "Поспелова Т.Х.",
                   subgroup: subgroup, isTimeUnspecified: false)
        }
        return ScheduleEntry(date: now, status: .ready, groupName: WidgetDefaults.groupName, lessons: [
            lesson("Бренд-менеджмент", "практические занятия", room: "339", startsIn: -30 * 60),
            lesson("Событийный маркетинг", "лекции", room: "425", startsIn: 70 * 60),
            lesson("Корпоративный PR", "лекции", room: "339", startsIn: 170 * 60, subgroup: 1)
        ])
    }
}
