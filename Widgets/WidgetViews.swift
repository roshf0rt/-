import SwiftUI
import WidgetKit

// MARK: - Ближайшая пара

struct NextLessonView: View {
    @Environment(\.hurry) private var hurry
    @Environment(\.widgetFamily) private var family
    let entry: ScheduleEntry

    var body: some View {
        content
            .containerBackground(for: .widget) { WidgetBackdrop(entry: entry) }
            .environment(\.locale, RU.locale)
            .environment(\.hurry, entry.hurry)
    }

    @ViewBuilder private var content: some View {
        if entry.status == .ready, let lesson = entry.focus {
            switch family {
            case .accessoryInline:
                Text("\(RU.time(lesson.startsAt)) · \(lesson.roomTitle) · \(lesson.subject)")
            case .accessoryRectangular:
                LockScreenLesson(lesson: lesson, date: entry.date)
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
        VStack(alignment: .leading, spacing: 3) {
            StatusLine(lesson: lesson, date: entry.date, compact: true)
            Spacer(minLength: 0)
            Text(lesson.subject)
                .font(.headline)
                .lineLimit(3)
                .minimumScaleFactor(0.7)
            TimingLine(lesson: lesson, date: entry.date)
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
                    .foregroundStyle(hurry.accent(lesson, at: entry.date))
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
                    Chip(lesson.lessonKind.title, color: lesson.tint)
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
                        .minimumScaleFactor(0.8)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

// MARK: - Кабинет

struct RoomView: View {
    @Environment(\.hurry) private var hurry
    @Environment(\.widgetFamily) private var family
    let entry: ScheduleEntry

    var body: some View {
        content
            .containerBackground(for: .widget) { WidgetBackdrop(entry: entry) }
            .environment(\.locale, RU.locale)
            .environment(\.hurry, entry.hurry)
    }

    @ViewBuilder private var content: some View {
        if entry.status == .ready, let lesson = entry.focus {
            switch family {
            case .accessoryCircular:
                RoomGauge(lesson: lesson, date: entry.date)
            case .accessoryRectangular:
                HStack(spacing: 8) {
                    Text(lesson.roomTitle)
                        .font(.system(size: 38, weight: .heavy, design: .rounded))
                        .lineLimit(1)
                        .minimumScaleFactor(0.4)
                        .widgetAccentable()
                    LockScreenTiming(lesson: lesson, date: entry.date)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            case .accessoryInline:
                Text("Каб. \(lesson.roomTitle) · \(RU.time(lesson.startsAt))")
            default:
                VStack(alignment: .leading, spacing: 1) {
                    StatusLine(lesson: lesson, date: entry.date, compact: true)
                    Spacer(minLength: 0)
                    Text(lesson.roomTitle)
                        .font(.system(size: 58, weight: .heavy, design: .rounded))
                        .foregroundStyle(hurry.accent(lesson, at: entry.date))
                        .lineLimit(1)
                        .minimumScaleFactor(0.3)
                    if !lesson.shortAddress.isEmpty {
                        Text(lesson.shortAddress)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Text(lesson.subject)
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    TimingLine(lesson: lesson, date: entry.date)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        } else {
            WidgetMessage(entry: entry)
        }
    }
}

/// Круглый виджет экрана блокировки: номер кабинета, а во время пары — живое кольцо до её конца.
private struct RoomGauge: View {
    let lesson: Lesson
    let date: Date

    var body: some View {
        if lesson.isOngoing(at: date) {
            ProgressView(timerInterval: lesson.startsAt...lesson.endsAt, countsDown: true) {
                EmptyView()
            } currentValueLabel: {
                roomLabel(caption: "до \(RU.time(lesson.endsAt))")
            }
            .progressViewStyle(.circular)
            .widgetAccentable()
        } else {
            ZStack {
                AccessoryWidgetBackground()
                roomLabel(caption: RU.time(lesson.startsAt))
            }
        }
    }

    private func roomLabel(caption: String) -> some View {
        VStack(spacing: -1) {
            Text(lesson.roomTitle)
                .font(.system(size: 20, weight: .heavy, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.4)
            Text(caption)
                .font(.system(size: 9, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .padding(.horizontal, 6)
    }
}

// MARK: - Пары на день

struct DayView: View {
    @Environment(\.hurry) private var hurry
    @Environment(\.widgetFamily) private var family
    let entry: ScheduleEntry

    private let maxRows = 3

    var body: some View {
        content
            .containerBackground(for: .widget) { WidgetBackdrop(entry: entry) }
            .environment(\.locale, RU.locale)
            .environment(\.hurry, entry.hurry)
    }

    @ViewBuilder private var content: some View {
        if entry.status == .ready, let agenda = entry.agenda {
            if family == .accessoryRectangular {
                VStack(alignment: .leading, spacing: 1) {
                    ForEach(Array(agenda.lessons.prefix(3))) { lesson in
                        HStack(spacing: 4) {
                            Text(RU.time(lesson.startsAt)).fontWeight(.semibold).monospacedDigit()
                            Text(lesson.roomTitle).fontWeight(.heavy).widgetAccentable()
                            Text(lesson.subject).lineLimit(1).minimumScaleFactor(0.7)
                        }
                        .font(.caption2)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else if family == .systemLarge {
                week
            } else {
                VStack(alignment: .leading, spacing: 5) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(RU.shortDay(agenda.day, now: entry.date))
                            .font(.headline)
                        if let soon = entry.focus, hurry.isSoon(soon, at: entry.date) {
                            Text("пора идти")
                                .font(.caption.weight(.heavy))
                                .foregroundStyle(.red)
                        }
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

extension DayView {
    /// Большой виджет: ближайшие пары на несколько дней вперёд.
    fileprivate var week: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline) {
                Text("Расписание")
                    .font(.headline)
                if let soon = entry.focus, hurry.isSoon(soon, at: entry.date) {
                    Text("пора идти")
                        .font(.caption.weight(.heavy))
                        .foregroundStyle(.red)
                }
                Spacer()
                Text(entry.groupName)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            ForEach(Array(entry.lessons.upcomingDays(at: entry.date, maxLessons: 7).enumerated()), id: \.offset) { _, day in
                Text(RU.shortDay(day.day, now: entry.date).uppercased(with: RU.locale))
                    .font(.caption2.weight(.heavy))
                    .foregroundStyle(.secondary)
                    .padding(.top, 2)
                ForEach(day.lessons) { lesson in
                    DayRow(lesson: lesson, date: entry.date, compact: true)
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

private struct DayRow: View {
    @Environment(\.hurry) private var hurry
    let lesson: Lesson
    let date: Date
    /// Плотнее — для большого виджета на несколько дней.
    var compact = false

    var body: some View {
        let kind = lesson.lessonKind
        let accent = hurry.accent(lesson, at: date)
        let highlighted = lesson.isOngoing(at: date) || hurry.isSoon(lesson, at: date)
        HStack(spacing: 8) {
            Capsule()
                .fill(accent)
                .frame(width: 3, height: compact ? 22 : 26)
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
                    .font(compact ? .caption.weight(.semibold) : .subheadline.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                Text(lesson.subgroup.map { "\(kind.title) · \($0) подгр." } ?? kind.title)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            Text(lesson.roomTitle)
                .font(.system(compact ? .headline : .title3, design: .rounded, weight: .heavy))
                .lineLimit(1)
                .minimumScaleFactor(0.5)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, compact ? 1 : 3)
        .background(highlighted ? accent.opacity(0.22) : Color.clear,
                    in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

// MARK: - Экран блокировки

/// Прямоугольный виджет экрана блокировки: что за пара и сколько осталось.
private struct LockScreenLesson: View {
    @Environment(\.hurry) private var hurry
    let lesson: Lesson
    let date: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            // The room comes first and never gives way; the status is cut instead.
            HStack(spacing: 0) {
                Text("каб. \(lesson.roomTitle)")
                    .layoutPriority(1)
                Text(" · \(StatusLine.title(for: lesson, at: date, hurry: hurry))")
            }
            .font(.caption2.weight(.semibold))
            .lineLimit(1)
            .widgetAccentable()
            Text(lesson.subject)
                .font(.headline)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            LockScreenTiming(lesson: lesson, date: date)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Время пары, а во время неё — живая полоса прогресса; перед парой — живой отсчёт.
private struct LockScreenTiming: View {
    @Environment(\.hurry) private var hurry
    let lesson: Lesson
    let date: Date

    var body: some View {
        if lesson.isOngoing(at: date) {
            ProgressView(timerInterval: lesson.startsAt...lesson.endsAt, countsDown: true) {
                EmptyView()
            } currentValueLabel: {
                EmptyView()
            }
            .progressViewStyle(.linear)
            .widgetAccentable()
        } else if hurry.isSoon(lesson, at: date) {
            HStack(spacing: 3) {
                Text("через")
                Text(timerInterval: date...lesson.startsAt, countsDown: true)
                    .monospacedDigit()
            }
            .font(.caption.weight(.semibold))
        } else {
            Text(RU.timeRange(lesson))
                .font(.caption)
        }
    }
}

// MARK: - Общие элементы

struct StatusLine: View {
    @Environment(\.hurry) private var hurry
    let lesson: Lesson
    let date: Date
    /// Без отсчёта справа — для маленьких виджетов, где он не помещается.
    var compact = false

    static func title(for lesson: Lesson, at date: Date, hurry: HurryInfo) -> String {
        if lesson.isOngoing(at: date) { return "СЕЙЧАС" }
        if hurry.isSoon(lesson, at: date) { return hurry.distance(to: lesson) == nil ? "ПОРА ИДТИ" : "ВЫХОДИ" }
        if hurry.isSettled(lesson, at: date) { return "НА МЕСТЕ" }
        if Calendar.current.isDate(lesson.startsAt, inSameDayAs: date) { return "ДАЛЕЕ" }
        return RU.shortDay(lesson.startsAt, now: date).uppercased(with: RU.locale)
    }

    var body: some View {
        let color = hurry.statusColor(lesson, at: date)
        HStack(spacing: 5) {
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
            Text(Self.title(for: lesson, at: date, hurry: hurry))
                .font(.caption2.weight(.heavy))
                .foregroundStyle(color)
                .lineLimit(1)
            Spacer(minLength: 4)
            // Live countdowns: the system redraws them every second.
            if compact {
                EmptyView()
            } else if lesson.isOngoing(at: date) {
                Text(timerInterval: lesson.startsAt...lesson.endsAt, countsDown: true)
                    .font(.caption2.weight(.semibold))
                    .monospacedDigit()
                    .multilineTextAlignment(.trailing)
                    .frame(width: 58, alignment: .trailing)
                    .foregroundStyle(.secondary)
            } else if hurry.isSoon(lesson, at: date) {
                Text(timerInterval: date...lesson.startsAt, countsDown: true)
                    .font(.caption.weight(.heavy))
                    .monospacedDigit()
                    .multilineTextAlignment(.trailing)
                    .frame(width: 52, alignment: .trailing)
                    .foregroundStyle(.red)
            }
        }
    }
}

/// Время пары для маленьких виджетов: живой отсчёт до конца или до начала, иначе время.
struct TimingLine: View {
    @Environment(\.hurry) private var hurry
    let lesson: Lesson
    let date: Date

    var body: some View {
        if lesson.isOngoing(at: date) {
            HStack(spacing: 3) {
                Text("ещё")
                Text(timerInterval: lesson.startsAt...lesson.endsAt, countsDown: true)
                    .monospacedDigit()
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
        } else if hurry.isSoon(lesson, at: date) {
            HStack(spacing: 3) {
                Text("через")
                Text(timerInterval: date...lesson.startsAt, countsDown: true)
                    .monospacedDigit()
                if let distance = hurry.distanceText(for: lesson) {
                    Text("· \(distance)")
                }
            }
            .font(.caption.weight(.heavy))
            .foregroundStyle(.red)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
        } else {
            Text(RU.timeRange(lesson))
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .monospacedDigit()
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
        case .noGroup: return "Откройте приложение и выберите группу"
        case .noData: return "Нет данных. Проверьте интернет или откройте приложение"
        case .ready:
            if let days = Mood.vacationDays(entry.lessons, now: entry.date) { return "Каникулы! До пар \(days) дн." }
            if Mood.dayDone(entry.lessons, now: entry.date) { return Mood.line(Mood.dayDoneLines, on: entry.date) }
            return "Ближайших пар нет"
        }
    }

    private var symbol: String {
        guard entry.status == .ready else { return "calendar.badge.exclamationmark" }
        if Mood.vacationDays(entry.lessons, now: entry.date) != nil { return "beach.umbrella.fill" }
        if Mood.dayDone(entry.lessons, now: entry.date) { return "party.popper.fill" }
        return "cup.and.saucer.fill"
    }

    private var shortText: String {
        switch entry.status {
        case .noGroup: return "Выберите группу"
        case .noData: return "Нет данных"
        case .ready:
            if Mood.vacationDays(entry.lessons, now: entry.date) != nil { return "Каникулы" }
            if Mood.dayDone(entry.lessons, now: entry.date) { return "Пары кончились" }
            return "Пар нет"
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
                Image(systemName: symbol)
                    .font(.title2)
                    .foregroundStyle(.orange)
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

/// Фон виджета. За 15 минут до пары он краснеет, а во время пары по краю идёт кольцо,
/// которое укорачивается к её концу (обновляется раз в пару минут).
struct WidgetBackdrop: View {
    let entry: ScheduleEntry

    var body: some View {
        let lesson = entry.status == .ready ? entry.focus : nil
        let soon = lesson.map { entry.hurry.isSoon($0, at: entry.date) } ?? false
        let color = lesson.map { entry.hurry.accent($0, at: entry.date) } ?? .blue
        ZStack {
            Color(uiColor: .systemBackground)
            LinearGradient(colors: [color.opacity(soon ? 0.75 : 0.3), color.opacity(soon ? 0.35 : 0.04)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            if let lesson, lesson.isOngoing(at: entry.date) {
                ContainerRelativeShape()
                    .inset(by: 3)
                    .stroke(color.opacity(0.18), lineWidth: 5)
                ContainerRelativeShape()
                    .inset(by: 3)
                    .trim(from: 0, to: lesson.remainingFraction(at: entry.date))
                    .stroke(color, style: StrokeStyle(lineWidth: 5, lineCap: .round))
            }
        }
    }
}
