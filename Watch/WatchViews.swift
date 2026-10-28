import SwiftUI

struct WatchHome: View {
    @ObservedObject var store: WatchStore

    var body: some View {
        NavigationStack {
            Group {
                if store.group == nil {
                    ContentUnavailableView {
                        Label("Нет группы", systemImage: "iphone")
                    } description: {
                        Text("Откройте «Расписание УрФУ» на iPhone и выберите группу.")
                    }
                } else {
                    TimelineView(.periodic(from: .now, by: 30)) { context in
                        ScheduleList(store: store, now: context.date)
                    }
                }
            }
            .navigationTitle(store.group?.name ?? "УрФУ")
        }
        .task {
            if store.isStale { await store.refresh() }
        }
    }
}

private struct ScheduleList: View {
    @ObservedObject var store: WatchStore
    let now: Date

    var body: some View {
        let days = store.lessons.upcomingDays(at: now, maxLessons: 30)
        List {
            if let focus = store.lessons.focus(at: now) {
                FocusCell(lesson: focus, now: now)
                    .listRowBackground(RoundedRectangle(cornerRadius: 12).fill(focus.accent(at: now).opacity(0.25)))
            }
            ForEach(Array(days.enumerated()), id: \.offset) { _, day in
                Section(RU.shortDay(day.day, now: now)) {
                    ForEach(day.lessons) { lesson in
                        LessonCell(lesson: lesson, now: now)
                    }
                }
            }
            if days.isEmpty {
                Text("Пар не найдено")
                    .foregroundStyle(.secondary)
            }
            Section {
                Button {
                    Task { await store.refresh() }
                } label: {
                    Label(store.loading ? "Обновляю…" : "Обновить", systemImage: "arrow.clockwise")
                }
                .disabled(store.loading)
            } footer: {
                if store.failed {
                    Text("Не удалось загрузить. Показано сохранённое.")
                } else if let updatedAt = store.updatedAt {
                    Text("Обновлено \(RU.shortDay(updatedAt, now: now).lowercased(with: RU.locale)) в \(RU.time(updatedAt))")
                }
            }
        }
    }
}

/// Текущая или ближайшая пара: крупно кабинет и живой отсчёт.
private struct FocusCell: View {
    let lesson: Lesson
    let now: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(lesson.isOngoing(at: now) ? "СЕЙЧАС" : (lesson.isSoon(at: now) ? "ПОРА ИДТИ" : "ДАЛЕЕ"))
                .font(.caption2.weight(.heavy))
                .foregroundStyle(lesson.accent(at: now))
            Text("каб. \(lesson.roomTitle)")
                .font(.title2.weight(.bold))
                .lineLimit(1)
                .minimumScaleFactor(0.5)
            Text(lesson.subject)
                .font(.headline)
                .lineLimit(2)
                .minimumScaleFactor(0.7)
            if lesson.isOngoing(at: now) {
                ProgressView(timerInterval: lesson.startsAt...lesson.endsAt, countsDown: true) {
                    EmptyView()
                } currentValueLabel: {
                    EmptyView()
                }
                .tint(lesson.tint)
                HStack(spacing: 3) {
                    Text("ещё")
                    Text(timerInterval: lesson.startsAt...lesson.endsAt, countsDown: true)
                        .monospacedDigit()
                }
                .font(.caption)
            } else if Calendar.current.isDate(lesson.startsAt, inSameDayAs: now) {
                HStack(spacing: 3) {
                    Text("через")
                    Text(timerInterval: now...lesson.startsAt, countsDown: true)
                        .monospacedDigit()
                }
                .font(.caption.weight(.semibold))
            } else {
                Text(RU.startsIn(lesson, now: now))
                    .font(.caption)
            }
            if !lesson.shortAddress.isEmpty {
                Text(lesson.shortAddress)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 4)
    }
}

private struct LessonCell: View {
    let lesson: Lesson
    let now: Date

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            RoundedRectangle(cornerRadius: 2)
                .fill(lesson.tint)
                .frame(width: 4)
            VStack(alignment: .leading, spacing: 2) {
                Text(lesson.subject)
                    .font(.footnote.weight(.semibold))
                    .lineLimit(2)
                Text("\(RU.timeRange(lesson)) · каб. \(lesson.roomTitle)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
        .opacity(lesson.endsAt < now ? 0.5 : 1)
    }
}
