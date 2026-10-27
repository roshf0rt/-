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

struct ScheduleProvider: AppIntentTimelineProvider {
    private let staleAfter: TimeInterval = 60 * 60

    func placeholder(in context: Context) -> ScheduleEntry { .preview }

    func snapshot(for configuration: ScheduleConfigurationIntent, in context: Context) async -> ScheduleEntry {
        if context.isPreview { return .preview }
        return await entries(for: configuration, now: Date(), allowNetwork: false).first ?? .preview
    }

    func timeline(for configuration: ScheduleConfigurationIntent, in context: Context) async -> Timeline<ScheduleEntry> {
        let now = Date()
        let entries = await entries(for: configuration, now: now, allowNetwork: true)
        let hasData = entries.first?.status == .ready
        return Timeline(entries: entries, policy: .after(now.addingTimeInterval(hasData ? staleAfter : 15 * 60)))
    }

    private func entries(for configuration: ScheduleConfigurationIntent, now: Date, allowNetwork: Bool) async -> [ScheduleEntry] {
        guard let group = configuration.group?.group ?? ScheduleStore.loadGroup() else {
            return [ScheduleEntry(date: now, status: .noGroup, groupName: "", lessons: [])]
        }

        // The widget fetches by itself, so it works even when the App Group is not shared.
        var snapshot = ScheduleStore.snapshot(for: group.id)
        if allowNetwork, snapshot.map({ now.timeIntervalSince($0.updatedAt) > staleAfter }) ?? true,
           let lessons = try? await ScheduleAPI().fetchSchedule(for: group) {
            let fresh = ScheduleSnapshot(group: group, lessons: lessons, updatedAt: now)
            ScheduleStore.save(fresh)
            snapshot = fresh
        }
        guard let snapshot else {
            return [ScheduleEntry(date: now, status: .noData, groupName: group.name, lessons: [])]
        }

        let lessons = snapshot.lessons.visible(forSubgroup: configuration.subgroup.resolved)
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
        return ScheduleEntry(date: now, status: .ready, groupName: "УГИ-433510", lessons: [
            lesson("Бренд-менеджмент", "практические занятия", room: "339", startsIn: -30 * 60),
            lesson("Событийный маркетинг", "лекции", room: "425", startsIn: 70 * 60),
            lesson("Корпоративный PR", "лекции", room: "339", startsIn: 170 * 60, subgroup: 1)
        ])
    }
}
