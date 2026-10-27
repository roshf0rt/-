import SwiftUI
import WidgetKit

struct ScheduleEntry: TimelineEntry {
    let date: Date
    let group: String?
    let lessons: [Lesson]
}

struct ScheduleProvider: TimelineProvider {
    func placeholder(in context: Context) -> ScheduleEntry {
        ScheduleEntry(date: .now, group: "ИЭФ-412", lessons: [])
    }

    func getSnapshot(in context: Context, completion: @escaping (ScheduleEntry) -> Void) {
        completion(makeEntry(date: .now))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<ScheduleEntry>) -> Void) {
        let now = Date.now
        let lessons = ScheduleStore().loadLessons()
        let dates = Set([now] + lessons.transitionDates(after: now)).sorted()
        let entries = dates.map { makeEntry(date: $0) }
        // Перезапрос в начале следующего дня. Сеть из виджета не ходит:
        // данные обновляет приложение.
        let tomorrow = Calendar.current.startOfDay(for: now).addingTimeInterval(86_400 + 60)
        completion(Timeline(entries: entries, policy: .after(tomorrow)))
    }

    private func makeEntry(date: Date) -> ScheduleEntry {
        let store = ScheduleStore()
        return ScheduleEntry(date: date, group: store.selectedGroup, lessons: store.loadLessons())
    }
}

struct ScheduleWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: ScheduleEntry

    var body: some View {
        if entry.group == nil {
            Text("Выберите группу в приложении")
                .font(.caption)
        } else {
            content
        }
    }

    @ViewBuilder
    private var content: some View {
        let today = entry.lessons.today(entry.date)
        let focus = entry.lessons.current(at: entry.date) ?? entry.lessons.next(after: entry.date)

        switch family {
        case .accessoryInline:
            if let focus {
                Text("\(time(focus.start)) \(focus.subject)")
            } else {
                Text("Занятий нет")
            }

        case .accessoryCircular:
            VStack(spacing: 0) {
                Text("\(today.count)")
                    .font(.title2.bold())
                Text("пар")
                    .font(.caption2)
            }

        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 2) {
                Text(focus?.subject ?? "Занятий нет")
                    .font(.headline)
                    .lineLimit(1)
                if let focus {
                    Text("\(time(focus.start))–\(time(focus.end))  \(focus.room ?? "")")
                        .font(.caption)
                }
            }

        case .systemSmall:
            VStack(alignment: .leading, spacing: 4) {
                Text("Сегодня").font(.caption).foregroundStyle(.secondary)
                if let focus {
                    Text(focus.subject).font(.headline).lineLimit(2)
                    Text("\(time(focus.start))  \(focus.room ?? "")").font(.caption)
                } else {
                    Text("Занятий нет")
                }
                Spacer()
            }

        default:
            VStack(alignment: .leading, spacing: 6) {
                Text("Сегодня").font(.caption).foregroundStyle(.secondary)
                if today.isEmpty {
                    Text("Занятий нет")
                } else {
                    ForEach(today) { lesson in
                        HStack(alignment: .firstTextBaseline) {
                            Text(time(lesson.start))
                                .font(.caption.monospacedDigit())
                                .frame(width: 44, alignment: .leading)
                            Text(lesson.subject)
                                .font(.subheadline)
                                .lineLimit(1)
                            Spacer()
                            Text(lesson.room ?? "")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                Spacer()
            }
        }
    }

    private func time(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
    }
}

struct UrfuScheduleWidget: Widget {
    let kind = "UrfuScheduleWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: ScheduleProvider()) { entry in
            ScheduleWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Расписание")
        .description("Занятия на сегодня")
        .supportedFamilies([
            .accessoryInline, .accessoryCircular, .accessoryRectangular,
            .systemSmall, .systemMedium, .systemLarge
        ])
    }
}
