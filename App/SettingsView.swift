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
                         ? "Пары другой подгруппы скрываются в приложении и в виджетах."
                         : "В загруженном расписании номера подгрупп не найдены. Если на сайте они есть, откройте «Ответ сервера» ниже и пришлите текст разработчику.")
                }

                Section("Оформление") {
                    Picker("Цвет", selection: $model.theme) {
                        ForEach(AppTheme.allCases) { theme in
                            Label {
                                Text(theme.title)
                            } icon: {
                                Image(systemName: theme == .byKind ? "circle.hexagongrid.fill" : "circle.fill")
                                    .foregroundStyle(theme.color)
                            }
                            .tag(theme)
                        }
                    }
                    .pickerStyle(.navigationLink)
                }

                LocationSection()

                Section {
                    Picker("Напомнить о паре", selection: $model.reminderMinutes) {
                        Text("Не напоминать").tag(0)
                        ForEach(LessonReminders.choices, id: \.self) { minutes in
                            Text("За \(minutes) мин").tag(minutes)
                        }
                    }
                } header: {
                    Text("Напоминания")
                } footer: {
                    if model.notificationsDenied {
                        Text("Уведомления запрещены. Разрешите их: Настройки iOS → Уведомления → Расписание УрФУ.")
                            .foregroundStyle(.red)
                    } else {
                        Text("Напоминания ставятся на две недели вперёд и обновляются, когда вы открываете приложение. Учитывается выбранная подгруппа.")
                    }
                }

                Section {
                    if model.widgetLinkWorks {
                        Label("Связь с виджетом работает: виджеты берут группу и подгруппу из этих настроек.",
                              systemImage: "checkmark.circle")
                    } else {
                        Label("Связь с виджетом не работает (код \(SharedSettings.lastStatus.map { "\($0)" } ?? "—")). В виджетах: \(WidgetDefaults.groupName), \(WidgetDefaults.subgroup.map { "\($0) подгруппа" } ?? "все пары").",
                              systemImage: "exclamationmark.triangle")
                    }
                    Label("Экран блокировки: зажмите его → «Настроить» → «Экран блокировки» → поле под часами → «Расписание УрФУ». Круглый «Кабинет» во время пары показывает кольцо до её конца.",
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
                    EntitlementRow(title: "Папки приложения", values: Entitlements.appGroups(Entitlements.own))
                    EntitlementRow(title: "Папки виджета", values: Entitlements.appGroups(Entitlements.partner))
                    EntitlementRow(title: "Keychain приложения", values: Entitlements.keychainGroups(Entitlements.own))
                    EntitlementRow(title: "Keychain виджета", values: Entitlements.keychainGroups(Entitlements.partner))
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

/// Строка диагностики со списком прав подписи.
private struct EntitlementRow: View {
    let title: String
    let values: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.footnote)
            Text(values.isEmpty ? "нет" : values.joined(separator: "\n"))
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        }
    }
}
