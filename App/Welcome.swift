import SwiftUI

/// Приветствие с коротким разбором функций. Показывается сверху, пока его не скроют.
struct WelcomeCard: View {
    @AppStorage("welcome.dismissed.v1") private var dismissed = false

    var body: some View {
        if !dismissed {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top) {
                    Text("Привет! 👋")
                        .font(.title3.weight(.bold))
                    Spacer(minLength: 0)
                    Button {
                        dismissed = true
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title3)
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Скрыть приветствие")
                }

                Text("Вот что здесь есть:")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                ForEach(Self.features) { feature in
                    Label {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(feature.title)
                                .font(.subheadline.weight(.semibold))
                            Text(feature.detail)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    } icon: {
                        Image(systemName: feature.icon)
                            .foregroundStyle(.tint)
                            .frame(width: 24)
                    }
                    .labelStyle(.titleAndIcon)
                }

                Text("Made by roshfort")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .padding()
            .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
        }
    }

    private struct Feature: Identifiable {
        let icon: String
        let title: String
        let detail: String
        var id: String { title }
    }

    private static let features: [Feature] = [
        Feature(icon: "calendar", title: "Расписание группы",
                detail: "Пары на сегодня и две недели вперёд, с подгруппами и кабинетами."),
        Feature(icon: "square.grid.2x2", title: "Виджеты",
                detail: "На главный экран и экран блокировки: ближайшая пара одним взглядом."),
        Feature(icon: "timer", title: "Живая карточка",
                detail: "Текущая или следующая пара на экране блокировки и в Dynamic Island. Включается в настройках."),
        Feature(icon: "applewatch", title: "Apple Watch",
                detail: "Расписание на часах. Данные берутся с телефона."),
        Feature(icon: "note.text", title: "Заметки и ДЗ",
                detail: "Заметки к парам. Поделиться домашкой с группой можно по желанию, без этого всё остаётся на телефоне."),
        Feature(icon: "bell", title: "Уведомления",
                detail: "Напоминания о парах и весёлые сообщения, когда пары кончились или начались каникулы. Всё отключается.")
    ]
}

/// Подпись внизу списка.
struct CreditFooter: View {
    var body: some View {
        Text("Made by roshfort")
            .font(.footnote.weight(.medium))
            .foregroundStyle(.tertiary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
    }
}
