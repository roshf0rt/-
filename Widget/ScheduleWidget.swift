import SwiftUI
import WidgetKit

struct ScheduleEntry: TimelineEntry {
    let date: Date
    let lessons: [Lesson]
    let hasSchedule: Bool
}

struct ScheduleProvider: TimelineProvider {
    func placeholder(in context: Context) -> ScheduleEntry {
        ScheduleEntry(date: .now, lessons: [], hasSchedule: true)
    }

    func getSnapshot(in context: Context, completion: @escaping (ScheduleEntry) -> Void) {
        completion(makeEntry(date: .now, weekly: ScheduleStore().load()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<ScheduleEntry>) -> Void) {
        let now = Date.now
        let weekly = ScheduleStore().load()
        let dates = Set([now] + weekly.lessons(on: now).transitionDates(after: now)).sorted()
        let entries = dates.map { makeEntry(date: $0, weekly: weekly) }
        // Новый таймлайн на следующий день. Виджет данные не загружает: всё лежит локально.
        let calendar = Calendar.current
        let nextMidnight = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now))
            ?? now.addingTimeInterval(86_400)
        completion(Timeline(entries: entries, policy: .after(nextMidnight)))
    }

    private func makeEntry(date: Date, weekly: [WeeklyLesson]) -> ScheduleEntry {
        ScheduleEntry(date: date, lessons: weekly.lessons(on: date), hasSchedule: !weekly.isEmpty)
    }
}

struct ScheduleWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: ScheduleEntry

    var body: some View {
        if entry.hasSchedule {
            content
        } else {
            Text("Добавьте занятия в приложении")
                .font(.caption)
        }
    }

    @ViewBuilder
    private var content: some View {
        let lessons = entry.lessons
        let focus = lessons.current(at: entry.date) ?? lessons.next(after: entry.date)

        switch family {
        case .accessoryInline:
            if let focus {
                Text("\(time(focus.start)) \(focus.subject)")
            } else {
                Text("Занятий нет")
            }

        case .accessoryCircular:
            VStack(spacing: 0) {
                Text("\(lessons.count)")
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
                    Text("\(time(focus.start))–\(time(focus.end))  \(focus.room)")
                        .font(.caption)
                }
            }

        case .systemSmall:
            VStack(alignment: .leading, spacing: 4) {
                Text("Сегодня").font(.caption).foregroundStyle(.secondary)
                if let focus {
                    Text(focus.subject).font(.headline).lineLimit(2)
                    Text("\(time(focus.start))  \(focus.room)").font(.caption)
                } else {
                    Text("Занятий нет")
                }
                Spacer()
            }

        default:
            VStack(alignment: .leading, spacing: 6) {
                Text("Сегодня").font(.caption).foregroundStyle(.secondary)
                if lessons.isEmpty {
                    Text("Занятий нет")
                } else {
                    ForEach(lessons) { lesson in
                        HStack(alignment: .firstTextBaseline) {
                            Text(time(lesson.start))
                                .font(.caption.monospacedDigit())
                                .frame(width: 44, alignment: .leading)
                            Text(lesson.subject)
                                .font(.subheadline)
                                .lineLimit(1)
                            Spacer()
                            Text(lesson.room)
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
