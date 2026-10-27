import Foundation

/// Источник расписания с сайта УрФУ.
///
/// ВНИМАНИЕ: адреса и формат ответов взяты из обсуждения 2020 года и ещё не проверены.
/// Проверьте их в браузере перед использованием: откройте адрес
/// `https://urfu.ru/api/schedule/groups/suggest/?query=ИЭФ-412` и посмотрите JSON.
/// Пока в `ScheduleService` подключён `MockScheduleRepository`.
struct RemoteScheduleRepository: ScheduleRepository {
    private let base = URL(string: "https://urfu.ru")!

    func lessons(forGroup group: String, from start: Date, to end: Date) async throws -> [Lesson] {
        let groupId = try await groupId(for: group)
        let url = base.appending(path: "api/schedule/groups/lessons/\(groupId)/\(dayString(start))/")
        let (data, _) = try await URLSession.shared.data(from: url)
        // Формат занятий ещё не проверен. Разбор добавим, когда увидим реальный JSON.
        throw ScheduleError.unknownFormat(String(decoding: data.prefix(300), as: UTF8.self))
    }

    /// Переводит номер группы во внутренний id, который нужен для запроса расписания.
    private func groupId(for group: String) async throws -> String {
        var components = URLComponents(
            url: base.appending(path: "api/schedule/groups/suggest/"),
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = [URLQueryItem(name: "query", value: group)]
        guard let url = components?.url else { throw ScheduleError.badURL }

        let (data, _) = try await URLSession.shared.data(from: url)
        let suggestions = try JSONDecoder().decode([GroupSuggestion].self, from: data)
        guard let match = suggestions.first(where: { $0.value.caseInsensitiveCompare(group) == .orderedSame }) else {
            throw ScheduleError.groupNotFound(group)
        }
        return match.id
    }

    private func dayString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd"
        return formatter.string(from: date)
    }

    private struct GroupSuggestion: Decodable {
        let value: String
        let id: String

        enum CodingKeys: String, CodingKey {
            case value
            case id = "data"
        }
    }
}

enum ScheduleError: LocalizedError {
    case badURL
    case groupNotFound(String)
    case unknownFormat(String)

    var errorDescription: String? {
        switch self {
        case .badURL: "Не удалось собрать адрес запроса"
        case .groupNotFound(let group): "Группа \(group) не найдена"
        case .unknownFormat(let sample): "Неизвестный формат ответа: \(sample)"
        }
    }
}
