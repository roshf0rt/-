import SwiftUI

/// Что изменилось в расписании: отмена, перенос или новая пара. Висит наверху, пока её не закроют.
struct ChangesCard: View {
    let changes: [ScheduleChange]
    let now: Date
    let onDismiss: () -> Void

    var body: some View {
        if !changes.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Label("Расписание изменилось", systemImage: "exclamationmark.triangle.fill")
                    .font(.headline)
                    .foregroundStyle(.orange)

                ForEach(changes) { change in
                    Label {
                        Text(change.text(now: now))
                            .font(.subheadline)
                            .fixedSize(horizontal: false, vertical: true)
                    } icon: {
                        Image(systemName: symbol(for: change.kind))
                            .foregroundStyle(color(for: change.kind))
                    }
                }

                Button("Понятно", action: onDismiss)
                    .buttonStyle(.bordered)
                    .tint(.orange)
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
        }
    }

    private func symbol(for kind: ScheduleChange.Kind) -> String {
        switch kind {
        case .cancelled: return "xmark.circle.fill"
        case .added: return "plus.circle.fill"
        case .changed: return "arrow.triangle.2.circlepath.circle.fill"
        }
    }

    private func color(for kind: ScheduleChange.Kind) -> Color {
        switch kind {
        case .cancelled: return .red
        case .added: return .green
        case .changed: return .orange
        }
    }
}
