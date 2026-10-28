import Foundation
import UserNotifications

/// Общее ДЗ: сервер на `CommunityAPI.baseURL` хранит записи по группам.
struct CommunityAPI {
    static let baseURL = URL(string: "https://2-26-99-200.sslip.io/v1/")!

    struct GroupRef: Codable, Hashable {
        let id: String
        let name: String
    }

    struct User: Codable, Equatable {
        let id: Int
        var nickname: String
        var group: GroupRef
    }

    struct Draft: Encodable {
        let subject: String
        let lessonStart: Date
        let text: String
        let audience: [GroupRef]
    }

    private struct Registration: Decodable {
        let token: String
        let user: User
    }

    private struct ProfileBody: Encodable {
        let nickname: String
        let group: GroupRef
    }

    private struct ServerError: Decodable {
        let detail: Detail
        enum Detail: Decodable {
            case text(String), list([Item])
            struct Item: Decodable { let msg: String }
            init(from decoder: Decoder) throws {
                let container = try decoder.singleValueContainer()
                if let text = try? container.decode(String.self) { self = .text(text) }
                else { self = .list(try container.decode([Item].self)) }
            }
            var message: String {
                switch self {
                case .text(let text): return text
                case .list(let items): return items.map(\.msg).joined(separator: "; ")
                }
            }
        }
    }

    enum Failure: LocalizedError {
        case server(String)
        var errorDescription: String? {
            switch self { case .server(let message): return message }
        }
    }

    func register(nickname: String, group: GroupRef) async throws -> (token: String, user: User) {
        let result: Registration = try await send("users", method: "POST", body: ProfileBody(nickname: nickname, group: group))
        return (result.token, result.user)
    }

    func updateProfile(token: String, nickname: String, group: GroupRef) async throws -> User {
        try await send("users/me", method: "PUT", token: token, body: ProfileBody(nickname: nickname, group: group))
    }

    func homework(token: String, groups: [String]) async throws -> [SharedHomework] {
        var components = URLComponents(url: Self.baseURL.appendingPathComponent("homework"), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "groups", value: groups.joined(separator: ","))]
        return try await send(url: components.url!, method: "GET", token: token, body: Optional<Draft>.none)
    }

    func create(token: String, draft: Draft) async throws -> SharedHomework {
        try await send("homework", method: "POST", token: token, body: draft)
    }

    func delete(token: String, id: Int) async throws {
        struct Ok: Decodable { let ok: Bool }
        let _: Ok = try await send("homework/\(id)", method: "DELETE", token: token, body: Optional<Draft>.none)
    }

    private func send<Body: Encodable, Result: Decodable>(_ path: String, method: String, token: String? = nil,
                                                          body: Body?) async throws -> Result {
        try await send(url: Self.baseURL.appendingPathComponent(path), method: method, token: token, body: body)
    }

    private func send<Body: Encodable, Result: Decodable>(url: URL, method: String, token: String?,
                                                          body: Body?) async throws -> Result {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 20
        if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            let encoder = JSONEncoder()
            encoder.keyEncodingStrategy = .convertToSnakeCase
            encoder.dateEncodingStrategy = .iso8601
            request.httpBody = try encoder.encode(body)
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .iso8601
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let message = (try? decoder.decode(ServerError.self, from: data))?.detail.message
            throw Failure.server(message ?? "Сервер общего ДЗ недоступен")
        }
        return try decoder.decode(Result.self, from: data)
    }
}

struct SharedHomework: Codable, Identifiable, Equatable {
    struct Author: Codable, Hashable {
        let id: Int
        let nickname: String
        let groupName: String
    }

    let id: Int
    let author: Author
    let subject: String
    let lessonStart: Date
    let text: String
    let audience: [CommunityAPI.GroupRef]
    let createdAt: Date
    let mine: Bool

    var lessonKey: String { Lesson.shareKey(subject: subject, start: lessonStart) }
}

extension Lesson {
    /// Пара узнаётся по предмету и времени начала: у потоковой пары они одинаковы во всех группах.
    static func shareKey(subject: String, start: Date) -> String {
        "\(subject.lowercased())|\(Int(start.timeIntervalSince1970 / 60))"
    }

    var shareKey: String { Self.shareKey(subject: subject, start: startsAt) }
}

/// Кому показать ДЗ.
enum ShareScope: String, CaseIterable, Identifiable {
    case none, group, stream

    var id: String { rawValue }

    var title: String {
        switch self {
        case .none: return "Не делиться"
        case .group: return "Моей группе"
        case .stream: return "Потоку"
        }
    }
}

@MainActor
final class CommunityStore: ObservableObject {
    @Published private(set) var user: CommunityAPI.User?
    @Published private(set) var items: [SharedHomework] = []
    @Published private(set) var error: String?
    /// Другие группы потока; своя группа добавляется сама.
    @Published var stream: [ScheduleGroup] { didSet { save(stream, key: Keys.stream) } }
    @Published var onlySelectedAuthors: Bool { didSet { defaults.set(onlySelectedAuthors, forKey: Keys.onlySelected) } }
    @Published var selectedAuthors: Set<Int> { didSet { defaults.set(Array(selectedAuthors), forKey: Keys.authors) } }

    private let api = CommunityAPI()
    private let defaults = UserDefaults.standard
    private enum Keys {
        static let token = "community.token.v1"
        static let user = "community.user.v1"
        static let stream = "community.stream.v1"
        static let onlySelected = "community.onlySelected.v1"
        static let authors = "community.authors.v1"
        static let seen = "community.seen.v1"
    }

    private var token: String? {
        get { defaults.string(forKey: Keys.token) }
        set { defaults.set(newValue, forKey: Keys.token) }
    }

    init() {
        user = Self.load(CommunityAPI.User.self, key: Keys.user)
        stream = Self.load([ScheduleGroup].self, key: Keys.stream) ?? []
        onlySelectedAuthors = UserDefaults.standard.bool(forKey: Keys.onlySelected)
        selectedAuthors = Set(UserDefaults.standard.array(forKey: Keys.authors) as? [Int] ?? [])
    }

    var hasProfile: Bool { user != nil && token != nil }

    /// Записи других людей, которые проходят фильтр по авторам, и свои.
    var visibleItems: [SharedHomework] {
        items.filter { $0.mine || !onlySelectedAuthors || selectedAuthors.contains($0.author.id) }
    }

    func sharedHomework(for lesson: Lesson) -> [SharedHomework] {
        visibleItems.filter { $0.lessonKey == lesson.shareKey }
    }

    /// Авторы, которые уже что-то писали, кроме вас.
    var authors: [SharedHomework.Author] {
        Array(Set(items.filter { !$0.mine }.map(\.author))).sorted { $0.nickname < $1.nickname }
    }

    func saveProfile(nickname: String, group: ScheduleGroup) async {
        let ref = CommunityAPI.GroupRef(id: group.id, name: group.name)
        do {
            if let token {
                user = try await api.updateProfile(token: token, nickname: nickname, group: ref)
            } else {
                let result = try await api.register(nickname: nickname, group: ref)
                token = result.token
                user = result.user
            }
            save(user, key: Keys.user)
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    func refresh(group: ScheduleGroup?) async {
        guard let token, let group else { return }
        // Keep the profile's group in step with the group chosen in the app.
        if let user, user.group.id != group.id {
            await saveProfile(nickname: user.nickname, group: group)
        }
        do {
            // Its own task: pull to refresh and returning to the app cancel the view's task,
            // and a cancelled request must not show up as "отменено".
            let api = self.api
            let fresh = try await Task { try await api.homework(token: token, groups: [group.id]) }.value
            notifyAboutNew(in: fresh)
            items = fresh
            error = nil
        } catch {
            if error is CancellationError || (error as? URLError)?.code == .cancelled { return }
            self.error = error.localizedDescription
        }
    }

    func share(text: String, lesson: Lesson, scope: ShareScope, group: ScheduleGroup?) async {
        guard scope != .none, let token, let group else { return }
        var audience = [CommunityAPI.GroupRef(id: group.id, name: group.name)]
        if scope == .stream {
            audience += stream.filter { $0.id != group.id }.map { CommunityAPI.GroupRef(id: $0.id, name: $0.name) }
        }
        let draft = CommunityAPI.Draft(subject: lesson.subject, lessonStart: lesson.startsAt, text: text, audience: audience)
        do {
            let created = try await api.create(token: token, draft: draft)
            items.append(created)
            error = nil
        } catch {
            self.error = "Не удалось поделиться ДЗ: \(error.localizedDescription)"
        }
    }

    func delete(_ item: SharedHomework) async {
        guard let token else { return }
        do {
            try await api.delete(token: token, id: item.id)
            items.removeAll { $0.id == item.id }
        } catch {
            self.error = error.localizedDescription
        }
    }

    /// Notifies about homework from others that appeared since the last check.
    private func notifyAboutNew(in fresh: [SharedHomework]) {
        let seenBefore = defaults.array(forKey: Keys.seen) as? [Int]
        defaults.set(fresh.map(\.id), forKey: Keys.seen)
        // The first load after setup is not news.
        guard let seenBefore else { return }
        let known = Set(seenBefore)
        let new = fresh.filter {
            !$0.mine && !known.contains($0.id)
                && (!onlySelectedAuthors || selectedAuthors.contains($0.author.id))
        }
        guard !new.isEmpty else { return }
        Task {
            let center = UNUserNotificationCenter.current()
            guard await center.notificationSettings().authorizationStatus == .authorized else { return }
            for item in new.prefix(3) {
                let content = UNMutableNotificationContent()
                content.title = "Новое ДЗ: \(item.subject)"
                content.body = "\(item.author.nickname): \(item.text)"
                content.sound = .default
                try? await center.add(UNNotificationRequest(identifier: "shared-\(item.id)", content: content, trigger: nil))
            }
        }
    }

    private func save<T: Encodable>(_ value: T?, key: String) {
        defaults.set(value.flatMap { try? JSONEncoder().encode($0) }, forKey: key)
    }

    private static func load<T: Decodable>(_ type: T.Type, key: String) -> T? {
        UserDefaults.standard.data(forKey: key).flatMap { try? JSONDecoder().decode(type, from: $0) }
    }
}
