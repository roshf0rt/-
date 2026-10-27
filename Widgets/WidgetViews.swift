import SwiftUI
import WidgetKit

// MARK: - Ближайшая пара

struct NextLessonView: View {
    @Environment(\.widgetFamily) private var family
    let entry: ScheduleEntry

    var body: some View {
        content
            .containerBackground(for: .widget) { WidgetBackdrop(color: entry.focus?.lessonKind.color ?? .blue) }
            .environment(\.locale, RU.locale)
    }

    @ViewBuilder private var content: some View {
        if entry.status == .ready, let lesson = entry.focus {
            switch family {
            case .accessoryInline:
                Text("\(RU.time(lesson.startsAt)) · \(lesson.roomTitle) · \(lesson.subject)")
            case .accessoryRectangular:
                VStack(alignment: .leading, spacing: 1) {
                    Text("\(StatusLine.title(for: lesson, at: entry.date)) · \(RU.timeRange(lesson))")
                        .font(.caption2.weight(.semibold))
                        .widgetAccentable()
                    Text(lesson.subject)
                        .font(.headline)
                        .lineLimit(1)
                    Text("Кабинет \(lesson.roomTitle)")
                        .font(.caption)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            case .systemMedium:
                medium(lesson)
            default:
                small(lesson)
            }
        } else {
            WidgetMessage(entry: entry)
        }
    }

    private func small(_ lesson: Lesson) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            StatusLine(lesson: lesson, date: entry.date)
            Spacer(minLength: 0)
            Text(lesson.subject)
                .font(.headline)
                .lineLimit(3)
                .minimumScaleFactor(0.8)
            Text(RU.timeRange(lesson))
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .monospacedDigit()
            HStack(spacing: 4) {
                Image(systemName: "door.left.hand.open")
                Text(lesson.roomTitle).fontWeight(.bold)
            }
            .font(.subheadline)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func medium(_ lesson: Lesson) -> some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text("КАБИНЕТ")
                    .font(.caption2.weight(.heavy))
                    .foregroundStyle(.secondary)
                Text(lesson.roomTitle)
                    .font(.system(size: 42, weight: .heavy, design: .rounded))
                    .foregroundStyle(lesson.lessonKind.color)
                    .lineLimit(1)
                    .minimumScaleFactor(0.4)
                Text(lesson.shortAddress)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                Spacer(minLength: 0)
            }
            .frame(width: 104, alignment: .leading)

            VStack(alignment: .leading, spacing: 4) {
                StatusLine(lesson: lesson, date: entry.date)
                Text(lesson.subject)
                    .font(.headline)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
                    .fixedSize(horizontal: false, vertical: true)
                Text(RU.timeRange(lesson))
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                HStack(spacing: 4) {
                    Chip(lesson.lessonKind.title, color: lesson.lessonKind.color)
                    if let subgroup = lesson.subgroup {
                        Chip("\(subgroup) подгр.", color: .mint)
                    }
                }
                Spacer(minLength: 0)
                if let next = entry.following {
                    Text("Затем: \(WidgetText.when(next, at: lesson.startsAt)) · \(next.roomTitle) · \(next.subject)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

// MARK: - Кабинет

struct RoomView: View {
    @Environment(\.widgetFamily) private var family
    let entry: ScheduleEntry

    var body: some View {
        content
            .containerBackground(for: .widget) { WidgetBackdrop(color: entry.focus?.lessonKind.color ?? .blue) }
            .environment(\.locale, RU.locale)
    }

    @ViewBuilder private var content: some View {
        if entry.status == .ready, let lesson = entry.focus {
            switch family {
            case .accessoryCircular:
                ZStack {
                    AccessoryWidgetBackground()
                    VStack(spacing: -1) {
                        Text("каб.")
                            .font(.system(size: 10, weight: .semibold))
                        Text(lesson.roomTitle)
                            .font(.system(size: 22, weight: .heavy, design: .rounded))
                            .lineLimit(1)
                            .minimumScaleFactor(0.4)
                            .widgetAccentable()
                        Text(RU.time(lesson.startsAt))
                            .font(.system(size: 9, weight: .medium))
                    }
                    .padding(.horizontal, 5)
                }
            case .accessoryRectangular:
                HStack(spacing: 8) {
                    Text(lesson.roomTitle)
                        .font(.system(size: 38, weight: .heavy, design: .rounded))
                        .lineLimit(1)
                        .minimumScaleFactor(0.4)
                        .widgetAccentable()
                    VStack(alignment: .leading, spacing: 0) {
                        Text(RU.timeRange(lesson))
                            .font(.caption.weight(.semibold))
                        Text(lesson.subject)
                            .font(.caption2)
                            .lineLimit(2)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            case .accessoryInline:
                Text("Каб. \(lesson.roomTitle) · \(RU.time(lesson.startsAt))")
            default:
                VStack(alignment: .leading, spacing: 0) {
                    StatusLine(lesson: lesson, date: entry.date)
                    Spacer(minLength: 0)
                    Text("кабинет")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(lesson.roomTitle)
                        .font(.system(size: 62, weight: .heavy, design: .rounded))
                        .foregroundStyle(lesson.lessonKind.color)
                        .lineLimit(1)
                        .minimumScaleFactor(0.3)
                    if !lesson.shortAddress.isEmpty {
                        Text(lesson.shortAddress)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Text("\(RU.time(lesson.startsAt)) · \(lesson.subject)")
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                        .padding(.top, 3)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        } else {
            WidgetMessage(entry: entry)
        }
    }
}

// MARK: - Пары на день

struct DayView: View {
    @Environment(\.widgetFamily) private var family
    let entry: ScheduleEntry

    private var maxRows: Int { family == .systemLarge ? 7 : 3 }

    var body: some View {
        content
            .containerBackground(for: .widget) { WidgetBackdrop(color: .blue) }
            .environment(\.locale, RU.locale)
    }

    @ViewBuilder private var content: some View {
        if entry.status == .ready, let agenda = entry.agenda {
            if family == .accessoryRectangular {
                VStack(alignment: .leading, spacing: 1) {
                    ForEach(Array(agenda.lessons.prefix(3))) { lesson in
                        HStack(spacing: 4) {
                            Text(RU.time(lesson.startsAt)).fontWeight(.semibold).monospacedDigit()
                            Text(lesson.roomTitle).fontWeight(.heavy).widgetAccentable()
                            Text(lesson.subject).lineLimit(1)
                        }
                        .font(.caption2)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                VStack(alignment: .leading, spacing: 5) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(RU.shortDay(agenda.day, now: entry.date))
                            .font(.headline)
                        Spacer()
                        Text(entry.groupName)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    ForEach(Array(agenda.lessons.prefix(maxRows))) { lesson in
                        DayRow(lesson: lesson, date: entry.date)
                    }
                    if agenda.lessons.count > maxRows {
                        Text("и ещё \(agenda.lessons.count - maxRows)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        } else {
            WidgetMessage(entry: entry)
        }
    }
}

private struct DayRow: View {
    let lesson: Lesson
    let date: Date

    var body: some View {
        let kind = lesson.lessonKind
        HStack(spacing: 8) {
            Capsule()
                .fill(kind.color)
                .frame(width: 3, height: 26)
            VStack(alignment: .leading, spacing: 0) {
                Text(lesson.isTimeUnspecified ? "—" : RU.time(lesson.startsAt))
                    .font(.caption.weight(.bold))
                if !lesson.isTimeUnspecified {
                    Text(RU.time(lesson.endsAt))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .monospacedDigit()
            .lineLimit(1)
            .fixedSize()
            .frame(width: 46, alignment: .leading)
            VStack(alignment: .leading, spacing: 0) {
                Text(lesson.subject)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Text(lesson.subgroup.map { "\(kind.title) · \($0) подгр." } ?? kind.title)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            Text(lesson.roomTitle)
                .font(.system(.title3, design: .rounded, weight: .heavy))
                .lineLimit(1)
                .minimumScaleFactor(0.5)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(lesson.isOngoing(at: date) ? kind.color.opacity(0.2) : Color.clear,
                    in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

// MARK: - Общие элементы

struct StatusLine: View {
    let lesson: Lesson
    let date: Date

    static func title(for lesson: Lesson, at date: Date) -> String {
        if lesson.isOngoing(at: date) { return "СЕЙЧАС" }
        if Calendar.current.isDate(lesson.startsAt, inSameDayAs: date) { return "ДАЛЕЕ" }
        return RU.shortDay(lesson.startsAt, now: date).uppercased(with: RU.locale)
    }

    var body: some View {
        let color = lesson.lessonKind.color
        HStack(spacing: 5) {
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
            Text(Self.title(for: lesson, at: date))
                .font(.caption2.weight(.heavy))
                .foregroundStyle(color)
                .lineLimit(1)
            Spacer(minLength: 4)
            if lesson.isOngoing(at: date) {
                // Live countdown to the end of the pair; the system redraws it every second.
                Text(timerInterval: lesson.startsAt...lesson.endsAt, countsDown: true)
                    .font(.caption2.weight(.semibold))
                    .monospacedDigit()
                    .multilineTextAlignment(.trailing)
                    .frame(width: 58, alignment: .trailing)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

enum WidgetText {
    static func when(_ lesson: Lesson, at date: Date) -> String {
        if Calendar.current.isDate(lesson.startsAt, inSameDayAs: date) { return RU.time(lesson.startsAt) }
        return "\(RU.shortDay(lesson.startsAt, now: date).lowercased(with: RU.locale)) \(RU.time(lesson.startsAt))"
    }
}

struct WidgetMessage: View {
    @Environment(\.widgetFamily) private var family
    let entry: ScheduleEntry

    private var text: String {
        switch entry.status {
        case .noGroup: return "Не удалось найти группу. Проверьте интернет — виджет попробует снова"
        case .noData: return "Нет данных. Проверьте интернет или откройте приложение"
        case .ready: return "Ближайших пар нет"
        }
    }

    private var shortText: String {
        switch entry.status {
        case .noGroup: return "Выберите группу"
        case .noData: return "Нет данных"
        case .ready: return "Пар нет"
        }
    }

    var body: some View {
        switch family {
        case .accessoryInline:
            Text(shortText)
        case .accessoryCircular:
            ZStack {
                AccessoryWidgetBackground()
                Image(systemName: entry.status == .ready ? "cup.and.saucer" : "calendar")
            }
        case .accessoryRectangular:
            Text(shortText).font(.headline)
        default:
            VStack(alignment: .leading, spacing: 6) {
                Image(systemName: entry.status == .ready ? "cup.and.saucer.fill" : "calendar.badge.exclamationmark")
                    .font(.title2)
                    .foregroundStyle(.blue)
                Spacer(minLength: 0)
                if !entry.groupName.isEmpty {
                    Text(entry.groupName)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                Text(text)
                    .font(.subheadline.weight(.semibold))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }
}

struct WidgetBackdrop: View {
    let color: Color

    var body: some View {
        ZStack {
            Color(uiColor: .systemBackground)
            LinearGradient(colors: [color.opacity(0.3), color.opacity(0.04)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
        }
    }
}
