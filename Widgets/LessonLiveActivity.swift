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
                    VStack(alignment: .leading, spacing: 0) {
                        Text("каб.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text(card.room)
                            .font(.title2.weight(.bold))
                            .foregroundStyle(card.tint)
                            .lineLimit(1)
                            .minimumScaleFactor(0.5)
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    VStack(alignment: .trailing, spacing: 0) {
                        Text(card.timerCaption)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        card.timer
                            .font(.title3.weight(.semibold))
                            .monospacedDigit()
                            .multilineTextAlignment(.trailing)
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(card.title)
                            .font(.headline)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                        card.progress
                    }
                }
            } compactLeading: {
                if card.state.showsInIsland {
                    Text(card.room)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(card.tint)
                        .lineLimit(1)
                }
            } compactTrailing: {
                if card.state.showsInIsland {
                    card.timer
                        .font(.caption.weight(.semibold))
                        .monospacedDigit()
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: 48)
                }
            } minimal: {
                if card.state.showsInIsland {
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

/// What the card shows at the moment it is drawn. The system redraws it at the start and
/// at the end of the pair (the stale date), so the phase follows the clock without updates.
private struct ActivityCard {
    enum Phase { case before, during, after }

    let state: LessonActivityAttributes.ContentState
    let now = Date()

    var phase: Phase {
        if now < state.startsAt { return .before }
        if now < state.endsAt { return .during }
        return .after
    }

    var tint: Color {
        let theme = AppTheme(rawValue: state.theme) ?? .byKind
        if phase == .before && state.startsAt.timeIntervalSince(now) <= TimeInterval(Hurry.minutes * 60) { return .red }
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
        switch phase {
        case .before: return "Начало в \(RU.time(state.startsAt))"
        case .during: return "Идёт до \(RU.time(state.endsAt))"
        case .after: return state.nextStartsAt.map { "Далее в \(RU.time($0))" } ?? "Свободны до завтра"
        }
    }

    var timerCaption: String {
        phase == .during ? "до конца" : "до начала"
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
                        Text(card.timerCaption)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: 90, alignment: .trailing)
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
                Text([card.status, card.phase == .after ? nil : state.address]
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
