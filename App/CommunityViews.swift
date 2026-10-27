import SwiftUI

/// Настройки общего ДЗ: ник, группы потока и чьи записи показывать.
struct CommunitySection: View {
    @ObservedObject var community: CommunityStore
    let group: ScheduleGroup?
    @State private var nickname = ""
    @State private var addingGroup = false
    @State private var saving = false

    private var trimmed: String { nickname.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        Section {
            HStack {
                TextField("Ваш ник", text: $nickname)
                    .autocorrectionDisabled()
                Button(community.hasProfile ? "Сохранить" : "Готово") {
                    guard let group else { return }
                    Task {
                        saving = true
                        await community.saveProfile(nickname: trimmed, group: group)
                        await community.refresh(group: group)
                        saving = false
                    }
                }
                .disabled(trimmed.count < 2 || group == nil || saving || trimmed == community.user?.nickname)
            }
            if let user = community.user {
                Text("Вы: \(user.nickname) · \(user.group.name)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Общее ДЗ")
        } footer: {
            Text("Ник видят одногруппники рядом с вашими записями. Группа берётся из приложения.")
        }
        .onAppear { if nickname.isEmpty { nickname = community.user?.nickname ?? "" } }

        Section {
            if let group {
                Label("\(group.name) — ваша", systemImage: "person.3")
            }
            ForEach(community.stream) { item in
                Text(item.name)
            }
            .onDelete { community.stream.remove(atOffsets: $0) }
            Button {
                addingGroup = true
            } label: {
                Label("Добавить группу потока", systemImage: "plus")
            }
        } header: {
            Text("Мой поток")
        } footer: {
            Text("ДЗ с пометкой «Потоку» увидят все эти группы. Потоковая пара узнаётся по предмету и времени начала.")
        }
        .sheet(isPresented: $addingGroup) {
            GroupPicker { picked in
                if picked.id != group?.id && !community.stream.contains(picked) {
                    community.stream.append(picked)
                }
            }
        }

        Section {
            Toggle("Только от выбранных авторов", isOn: $community.onlySelectedAuthors)
            if community.onlySelectedAuthors {
                if community.authors.isEmpty {
                    Text("Пока никто ничего не публиковал")
                        .foregroundStyle(.secondary)
                }
                ForEach(community.authors, id: \.id) { author in
                    Button {
                        if community.selectedAuthors.contains(author.id) {
                            community.selectedAuthors.remove(author.id)
                        } else {
                            community.selectedAuthors.insert(author.id)
                        }
                    } label: {
                        HStack {
                            Text("\(author.nickname) · \(author.groupName)")
                                .foregroundStyle(.primary)
                            Spacer()
                            if community.selectedAuthors.contains(author.id) {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            }
            if let error = community.error {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
        } header: {
            Text("Чьё ДЗ показывать")
        } footer: {
            Text("Свои записи видны всегда. Если кто-то пишет ерунду, включите фильтр и оставьте только нужных людей.")
        }
    }
}

/// ДЗ других людей к одной паре — в редакторе заметки.
struct SharedHomeworkList: View {
    @ObservedObject var community: CommunityStore
    let items: [SharedHomework]
    let onCopy: (SharedHomework) -> Void

    var body: some View {
        ForEach(items) { item in
            VStack(alignment: .leading, spacing: 6) {
                Text(item.text)
                HStack {
                    Text("\(item.author.nickname) · \(item.author.groupName)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    if item.mine {
                        Button("Удалить", role: .destructive) {
                            Task { await community.delete(item) }
                        }
                    } else {
                        Button("Взять себе") { onCopy(item) }
                    }
                }
                .font(.caption.weight(.semibold))
                .buttonStyle(.borderless)
            }
        }
    }
}
