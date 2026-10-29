import ActivityKit
import SwiftUI
import WidgetKit

/// Живая карточка пары: экран блокировки, Dynamic Island и Smart Stack на Apple Watch.
struct LessonLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: LessonActivityAttributes.self) { context in
            LessonActivityView(state: context.state)
                .padding(14)
                .activityBackgroundTint(Color.black.opacity(0.35))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            let card = ActivityCard(state: context.state)
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    if card.state.showsInIsland && card.islandVisible {
                        Text(card.room)
                            .font(.title2.weight(.bold))
                            .foregroundStyle(card.tint)
                            .lineLimit(1)
                            .minimumScaleFactor(0.5)
                            .padding(.leading, 6)
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    if card.state.showsInIsland && card.islandVisible {
                        VStack(alignment: .trailing, spacing: 0) {
                            Text(card.islandCountdown)
                                .font(.title3.weight(.semibold))
                                .monospacedDigit()
                                .multilineTextAlignment(.trailing)
                                .lineLimit(1)
                                .minimumScaleFactor(0.6)
                            Text(card.timerCaption)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.6)
                        }
                        .padding(.trailing, 6)
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    if card.state.showsInIsland && card.islandVisible {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(card.title)
                                .font(.headline)
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                            card.progress
                        }
                        .padding(.horizontal, 6)
                    }
                }
            } compactLeading: {
                if card.state.showsInIsland && card.islandVisible {
                    Text(card.room)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(card.tint)
                        .lineLimit(1)
                }
            } compactTrailing: {
                if card.state.showsInIsland && card.islandVisible {
                    Text(card.islandCountdown)
                        .font(.caption2.weight(.semibold))
                        .monospacedDigit()
                        .multilineTextAlignment(.trailing)
                        .lineLimit(1)
                        .frame(maxWidth: 58)
                }
            } minimal: {
                if card.state.showsInIsland && card.islandVisible {
                    Text(card.room)
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(card.tint)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                }
            }
            .keylineTint(card.tint)
        }
    }
}

/// What the card shows at the moment it is drawn. The system redraws it at each boundary
/// (the stale date), so the phase follows the clock without push updates.
private struct ActivityCard {
    enum Phase { case before, during, after }

    let state: LessonActivityAttributes.ContentState
    let now = Date()

    var phase: Phase {
        if now < state.startsAt { return .before }
        if now < state.endsAt { return .during }
        return .after
    }

    /// Between two pairs: the last one is over and the next one has not started.
    var isBreak: Bool {
        switch phase {
        case .before: return state.previousEndsAt.map { now >= $0 } ?? false
        case .after: return state.nextStartsAt != nil
        case .during: return false
        }
    }

    /// The pair this card is counting down to, when it has not started yet.
    var upcomingStart: Date? {
        switch phase {
        case .before: return state.startsAt
        case .after: return state.nextStartsAt
        case .during: return nil
        }
    }

    /// Time to go: 15 minutes before the first pair of the day, 90 seconds before any other pair.
    var hurrying: Bool {
        guard let start = upcomingStart, start > now else { return false }
        let firstOfDay = phase == .before && state.previousEndsAt == nil
        let lead = firstOfDay ? TimeInterval(Hurry.minutes * 60) : TimeInterval(Hurry.breakSeconds)
        return start.timeIntervalSince(now) <= lead
    }

    var tint: Color {
        let theme = AppTheme(rawValue: state.theme) ?? .byKind
        if hurrying { return .red }
        return theme == .byKind ? LessonKind(state.kind).color : theme.color
    }

    /// After the pair the card points to the next one, if there is one today.
    var room: String {
        let room = phase == .after ? (state.nextRoom ?? "") : state.room
        return room.isEmpty ? "—" : room
    }

    var title: String {
        phase == .after ? (state.nextSubject ?? Mood.line(Mood.dayDoneLines, on: now)) : state.subject
    }

    var status: String {
        if let start = upcomingStart {
            if hurrying { return "\(Mood.line(Mood.goLines, on: now)) · \(RU.time(start))" }
            if phase == .before && !isBreak { return "Первая пара в \(RU.time(start))" }
            return "\(Mood.line(Mood.breakLines, on: now)) · \(RU.time(start))"
        }
        return phase == .during ? "Идёт до \(RU.time(state.endsAt))" : "Свободны до завтра"
    }

    var timerCaption: String {
        switch phase {
        case .before: return isBreak ? "до пары" : "до начала"
        case .during: return "до конца"
        case .after: return "до пары"
        }
    }

    private var timerEnd: Date? {
        switch phase {
        case .before: return state.startsAt
        case .during: return state.endsAt
        case .after: return state.nextStartsAt.flatMap { $0 > now ? $0 : nil }
        }
    }

    @ViewBuilder var timer: some View {
        if let end = timerEnd {
            Text(timerInterval: now...end, countsDown: true)
        } else {
            Text("✓")
        }
    }

    /// Minutes only, for the Dynamic Island: the system timer always shows seconds.
    /// The Dynamic Island shows the island only in the last hour before a pair, or during it.
    var islandVisible: Bool {
        guard let end = timerEnd, end > now else { return false }
        return phase == .during || end.timeIntervalSince(now) <= 60 * 60
    }

    /// Bare minutes without a unit under an hour, hours and minutes above it.
    var islandCountdown: String {
        guard let end = timerEnd else { return "✓" }
        let minutes = max(Int((end.timeIntervalSince(now) / 60).rounded(.up)), 0)
        return minutes < 60 ? "\(minutes)" : "\(minutes / 60) ч \(String(format: "%02d", minutes % 60))"
    }

    @ViewBuilder var progress: some View {
        if phase == .during {
            ProgressView(timerInterval: state.startsAt...state.endsAt, countsDown: true) {
                EmptyView()
            } currentValueLabel: {
                EmptyView()
            }
            .progressViewStyle(.linear)
            .tint(tint)
        } else {
            Text(status)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }
}

private struct LessonActivityView: View {
    let state: LessonActivityAttributes.ContentState

    var body: some View {
        let card = ActivityCard(state: state)
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("каб. \(card.room)")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(card.tint)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Spacer(minLength: 8)
                if card.phase != .after || state.nextStartsAt != nil {
                    VStack(alignment: .trailing, spacing: 0) {
                        card.timer
                            .font(.title3.weight(.semibold))
                            .monospacedDigit()
                            .multilineTextAlignment(.trailing)
                            .lineLimit(1)
                        Text(card.timerCaption)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: 110, alignment: .trailing)
                }
            }
            Text(card.title)
                .font(.headline)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            if card.phase == .during {
                card.progress
                Text(card.status)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text([card.status, card.phase == .after || card.isBreak ? nil : state.address]
                    .compactMap { $0?.isEmpty == false ? $0 : nil }
                    .joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .foregroundStyle(.white)
    }
}
