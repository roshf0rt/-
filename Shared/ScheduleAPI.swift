import Foundation

/// The university's public schedule endpoints are undocumented and may change.
struct ScheduleAPI {
    private let baseURL = URL(string: "https://urfu.ru/api/v2/schedule/groups/")!
    private let timeZone = TimeZone(identifier: "Asia/Yekaterinburg")!

    func searchGroups(query: String) async throws -> [ScheduleGroup] {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return [] }
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "search", value: query)]
        let data = try await request(components.url!)
        do {
            return try JSONDecoder().decode([RemoteGroup].self, from: data).map {
                ScheduleGroup(id: $0.id.value, name: $0.title)
            }
        } catch {
            throw ScheduleError.unexpectedResponse
        }
    }

    func fetchSchedule(for group: ScheduleGroup) async throws -> [Lesson] {
        // IDs from this endpoint are numeric; never allow a path supplied by the UI.
        guard !group.id.isEmpty, group.id.allSatisfy(\.isNumber) else {
            throw ScheduleError.unexpectedResponse
        }
        let url = baseURL.appendingPathComponent(group.id).appendingPathComponent("schedule", isDirectory: true)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let now = Date()
        let start = calendar.startOfDay(for: now)
        let end = calendar.date(byAdding: .day, value: 14, to: start)!
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "date_gte", value: formatter.string(from: start)),
            URLQueryItem(name: "date_lte", value: formatter.string(from: end))
        ]
        let data = try await request(components.url!)
        let response: ScheduleResponse
        do { response = try JSONDecoder().decode(ScheduleResponse.self, from: data) }
        catch { throw ScheduleError.unexpectedResponse }

        let lessons = try response.events.enumerated().map { index, event -> Lesson in
            let unspecified = event.pairNumber == 0 && ["00:00:00", "00:00"].contains(event.timeBegin) && ["00:00:00", "00:00"].contains(event.timeEnd)
            guard let starts = parseDate(event.date, time: event.timeBegin),
                  let parsedEnd = parseDate(event.date, time: event.timeEnd),
                  unspecified || parsedEnd > starts else {
                throw ScheduleError.unexpectedResponse
            }
            // Untimed events remain visible for their calendar day.
            let ends = unspecified ? calendar.date(byAdding: .day, value: 1, to: starts)! : parsedEnd
            let title = [event.title, event.loadType].compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }.joined(separator: " · ")
            let location = [event.auditoryTitle, event.auditoryLocation].compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }.joined(separator: ", ")
            return Lesson(id: event.id ?? "\(group.id)-\(event.date)-\(event.timeBegin)-\(index)", title: title.isEmpty ? "Занятие" : title,
                          startsAt: starts, endsAt: ends, location: location, teacher: event.teacherName ?? "", isTimeUnspecified: unspecified)
        }
        return lessons.sorted { $0.startsAt < $1.startsAt }
    }

    private func parseDate(_ day: String, time: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.isLenient = false
        for format in ["yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd HH:mm"] {
            formatter.dateFormat = format
            if let date = formatter.date(from: "\(day) \(time)") { return date }
        }
        return nil
    }

    private func request(_ url: URL) async throws -> Data {
        var request = URLRequest(url: url)
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw ScheduleError.unexpectedResponse }
        guard (200..<300).contains(response.statusCode) else { throw ScheduleError.http(response.statusCode) }
        guard response.mimeType?.lowercased().contains("json") == true else { throw ScheduleError.unexpectedResponse }
        return data
    }
}

enum ScheduleError: LocalizedError {
    case http(Int)
    case unexpectedResponse

    var errorDescription: String? {
        switch self {
        case .http(let status): return "Сервер УрФУ вернул ошибку \(status). Попробуйте позже."
        case .unexpectedResponse: return "Не удалось прочитать ответ УрФУ. Сайт мог изменить формат данных или заблокировать запрос."
        }
    }
}

private struct RemoteID: Decodable {
    let value: String
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let number = try? container.decode(Int.self) { value = String(number) }
        else { value = try container.decode(String.self) }
    }
}
private struct RemoteGroup: Decodable { let id: RemoteID; let title: String }
private struct ScheduleResponse: Decodable { let events: [RemoteEvent] }
private struct RemoteEvent: Decodable {
    let id: String?
    let pairNumber: Int?
    let title: String?
    let loadType: String?
    let date: String
    let timeBegin: String
    let timeEnd: String
    let auditoryTitle: String?
    let auditoryLocation: String?
    let teacherName: String?
}
