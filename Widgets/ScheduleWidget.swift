import SwiftUI
import WidgetKit

private struct ScheduleEntry: TimelineEntry {
    let date: Date
    let snapshot: ScheduleSnapshot

    var upcoming: [Lesson] {
        snapshot.lessons
            .filter { $0.endsAt > date }
            .sorted { lhs, rhs in
                if lhs.isTimeUnspecified != rhs.isTimeUnspecified { return !lhs.isTimeUnspecified }
                return lhs.startsAt < rhs.startsAt
            }
    }
}

private struct ScheduleProvider: TimelineProvider {
    func placeholder(in context: Context) -> ScheduleEntry {
        ScheduleEntry(date: Date(), snapshot: ScheduleStore.load())
    }

    func getSnapshot(in context: Context, completion: @escaping (ScheduleEntry) -> Void) {
        completion(ScheduleEntry(date: Date(), snapshot: ScheduleStore.load()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<ScheduleEntry>) -> Void) {
        Task {
            let now = Date()
            var snapshot = ScheduleStore.load()
            if let group = ScheduleStore.loadGroup(),
               snapshot.updatedAt.map({ now.timeIntervalSince($0) >= 30 * 60 }) ?? true {
                if let lessons = try? await ScheduleAPI().fetchSchedule(for: group),
                   ScheduleStore.loadGroup() == group {
                    snapshot = ScheduleSnapshot(groupName: group.name, lessons: lessons, updatedAt: Date())
                    ScheduleStore.save(snapshot)
                } else {
                    snapshot = ScheduleStore.load()
                }
            }
            // Boundary entries change the display even between network updates.
            let boundaries = snapshot.lessons.flatMap { [$0.startsAt, $0.endsAt] }
                .filter { $0 > now && $0 < now.addingTimeInterval(24 * 60 * 60) }
            let dates = Array(Set([now] + boundaries)).sorted()
            let entries = dates.map { ScheduleEntry(date: $0, snapshot: snapshot) }
            completion(Timeline(entries: entries, policy: .after(now.addingTimeInterval(30 * 60))))
        }
    }
}

private struct ScheduleWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: ScheduleEntry

    private var next: Lesson? { entry.upcoming.first }
    private var group: String { entry.snapshot.groupName.isEmpty ? "Укажите группу" : entry.snapshot.groupName }

    var body: some View {
        Group {
            switch family {
            case .accessoryInline:
                if let lesson = next {
                    Text(lesson.isTimeUnspecified ? "Время не указано · \(lesson.title)" : "\(time(lesson.startsAt)) · \(lesson.title)")
                } else {
                    Text(entry.snapshot.updatedAt == nil ? "Откройте приложение" : "Расписание: нет ближайших занятий")
                }
            case .accessoryCircular:
                if let lesson = next {
                    VStack(spacing: 1) {
                        Image(systemName: "book.fill")
                        Text(lesson.isTimeUnspecified ? "—" : time(lesson.startsAt)).font(.system(size: 12, weight: .bold))
                    }
                } else {
                    Image(systemName: "calendar")
                }
            case .accessoryRectangular:
                if let lesson = next {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(lesson.isTimeUnspecified ? "\(day(lesson.startsAt)) · время не указано" : "\(day(lesson.startsAt)) · \(time(lesson.startsAt))")
                            .font(.caption2.weight(.semibold))
                        Text(lesson.title).font(.caption.weight(.semibold)).lineLimit(2)
                        if !lesson.location.isEmpty {
                            Text(lesson.location).font(.caption2).lineLimit(1)
                        }
                    }
                } else {
                    VStack(alignment: .leading) {
                        Text(group).font(.caption.weight(.semibold))
                        Text(entry.snapshot.updatedAt == nil ? "Откройте приложение" : "Нет ближайших занятий").font(.caption2)
                    }
                }
            default:
                homeView
            }
        }
        .widgetBackground()
    }

    private var homeView: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("УРФУ", systemImage: "calendar")
                    .font(.caption.weight(.bold))
                Spacer(minLength: 0)
                Text(group).font(.caption2.weight(.medium)).lineLimit(1)
            }
            .foregroundStyle(.secondary)
            if let lesson = next {
                Text(!lesson.isTimeUnspecified && lesson.startsAt <= entry.date ? "СЕЙЧАС" : "БЛИЖАЙШАЯ ПАРА")
                    .font(.caption2.weight(.bold)).foregroundStyle(.blue)
                Text(lesson.title)
                    .font(.headline).lineLimit(family == .systemSmall ? 3 : 2)
                Spacer(minLength: 0)
                Text(lesson.isTimeUnspecified ? "\(day(lesson.startsAt)) · время не указано" : "\(day(lesson.startsAt)) · \(time(lesson.startsAt))–\(time(lesson.endsAt))")
                    .font(.caption.weight(.semibold)).lineLimit(1)
                if !lesson.location.isEmpty {
                    Label(lesson.location, systemImage: "mappin")
                        .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                }
            } else {
                Spacer(minLength: 0)
                Text(entry.snapshot.updatedAt == nil ? "Нет данных" : "Нет ближайших занятий").font(.headline)
                Text(entry.snapshot.groupName.isEmpty ? "Откройте приложение и выберите группу" : "Откройте приложение, чтобы обновить расписание")
                    .font(.caption).foregroundStyle(.secondary).lineLimit(2)
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private func time(_ date: Date) -> String {
        date.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits))
    }

    private func day(_ date: Date) -> String {
        if Calendar.current.isDateInToday(date) { return "Сегодня" }
        if Calendar.current.isDateInTomorrow(date) { return "Завтра" }
        return date.formatted(.dateTime.day().month(.abbreviated))
    }
}

private extension View {
    @ViewBuilder func widgetBackground() -> some View {
        if #available(iOS 17.0, *) {
            containerBackground(.background, for: .widget)
        } else {
            padding()
            background(Color(uiColor: .systemBackground))
        }
    }
}

@main
struct ScheduleWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "UrFUScheduleWidget", provider: ScheduleProvider()) { entry in
            ScheduleWidgetView(entry: entry)
        }
        .configurationDisplayName("Расписание УрФУ")
        .description("Ближайшая пара выбранной группы.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryInline, .accessoryRectangular, .accessoryCircular])
    }
}
