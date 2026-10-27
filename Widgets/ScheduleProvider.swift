import WidgetKit

struct ScheduleEntry: TimelineEntry {
    enum Status { case ready, noGroup, noData }

    let date: Date
    let status: Status
    let groupName: String
    /// Уже отфильтрованы по подгруппе и отсортированы.
    let lessons: [Lesson]

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
            completion(Timeline(entries: entries, policy: .after(now.addingTimeInterval(hasData ? Self.staleAfter : 15 * 60))))
        }
    }

    private static func entries(now: Date, allowNetwork: Bool) async -> [ScheduleEntry] {
        guard let group = await resolveGroup(allowNetwork: allowNetwork) else {
            return [ScheduleEntry(date: now, status: .noGroup, groupName: "", lessons: [])]
        }

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

        let subgroup = AppGroup.isShared ? ScheduleStore.subgroup : WidgetDefaults.subgroup
        let lessons = snapshot.lessons.visible(forSubgroup: subgroup)
        // Redraw at every start and end of a pair, and at midnight for the day view.
        let calendar = Calendar.current
        let horizon = now.addingTimeInterval(24 * 60 * 60)
        var dates: Set<Date> = [now]
        for lesson in lessons where !lesson.isTimeUnspecified {
            for date in [lesson.startsAt, lesson.endsAt] where date > now && date < horizon {
                dates.insert(date)
            }
        }
        if let midnight = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) {
            dates.insert(midnight)
        }
        return dates.sorted().map {
            ScheduleEntry(date: $0, status: .ready, groupName: group.name, lessons: lessons)
        }
    }

    /// The app's group when the App Group is shared; otherwise the build-time default,
    /// looked up once on the site and then cached in the widget's own storage.
    private static func resolveGroup(allowNetwork: Bool) async -> ScheduleGroup? {
        if let group = ScheduleStore.loadGroup() { return group }
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
