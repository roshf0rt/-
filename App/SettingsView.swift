import SwiftUI

struct SettingsView: View {
    @ObservedObject var model: ScheduleViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var choosingGroup = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Группа") {
                    Button {
                        choosingGroup = true
                    } label: {
                        LabeledContent("Группа", value: model.group?.name ?? "Не выбрана")
                    }
                }

                Section {
                    SubgroupPicker(selection: $model.subgroup)
                } header: {
                    Text("Подгруппа")
                } footer: {
                    Text(model.hasSubgroups
                         ? "Пары другой подгруппы скрываются в приложении и в виджетах, где подгруппа стоит «Как в приложении»."
                         : "В загруженном расписании номера подгрупп не найдены. Если на сайте они есть, откройте «Ответ сервера» ниже и пришлите текст разработчику.")
                }

                Section {
                    Label("Зажмите виджет и выберите «Изменить виджет», чтобы указать группу и подгруппу именно для него.",
                          systemImage: "square.text.square")
                    Label("Виджеты: «Ближайшая пара», «Кабинет» и «Пары на день». Есть версии для экрана блокировки.",
                          systemImage: "lock.iphone")
                } header: {
                    Text("Виджеты")
                }
                .font(.subheadline)

                Section("Диагностика") {
                    if let group = model.group {
                        NavigationLink("Ответ сервера") { DiagnosticsView(group: group) }
                    }
                    LabeledContent("App Group", value: AppGroup.id)
                        .font(.footnote)
                    Text("Группа взята \(AppGroup.source)")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section {
                    let log = WidgetLog.entries()
                    if log.isEmpty {
                        Text("Записей нет. Значит, виджет ещё не запускался или не видит общие данные приложения.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(Array(log.reversed().enumerated()), id: \.offset) { _, line in
                            Text(line)
                                .font(.caption.monospaced())
                                .textSelection(.enabled)
                        }
                    }
                } header: {
                    Text("Журнал виджета")
                } footer: {
                    if !WidgetLog.entries().isEmpty {
                        ShareLink("Поделиться журналом", item: WidgetLog.entries().joined(separator: "\n"))
                    }
                }
            }
            .navigationTitle("Настройки")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Готово") { dismiss() } }
            }
            .sheet(isPresented: $choosingGroup) {
                GroupPicker { group in Task { await model.select(group) } }
            }
        }
        .environment(\.locale, RU.locale)
    }
}

/// Показывает несколько событий из ответа сайта, чтобы было видно, как устроены данные.
private struct DiagnosticsView: View {
    let group: ScheduleGroup
    @State private var text = ""
    @State private var failed = false

    var body: some View {
        ScrollView {
            if text.isEmpty && !failed {
                ProgressView().padding(.top, 40)
            } else {
                Text(failed ? "Не удалось загрузить ответ сервера." : text)
                    .font(.caption.monospaced())
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
            }
        }
        .navigationTitle("Ответ сервера")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !text.isEmpty {
                ShareLink(item: text)
            }
        }
        .task {
            do { text = try await ScheduleAPI().rawSample(for: group) }
            catch { failed = true }
        }
    }
}
