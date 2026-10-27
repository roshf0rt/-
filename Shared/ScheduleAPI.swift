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
        let data = try await request(try scheduleURL(for: group))
        let response: ScheduleResponse
        do { response = try JSONDecoder().decode(ScheduleResponse.self, from: data) }
        catch { throw ScheduleError.unexpectedResponse }

        // A single malformed event should not hide the rest of the schedule.
        let lessons = response.events.enumerated().compactMap { index, event in
            lesson(from: event, index: index, groupID: group.id)
        }
        return lessons.sorted { $0.startsAt < $1.startsAt }
    }

    /// Несколько событий из ответа сервера как есть — для экрана диагностики.
    /// Сначала идут события, где упоминается подгруппа.
    func rawSample(for group: ScheduleGroup) async throws -> String {
        let data = try await request(try scheduleURL(for: group))
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let events = object["events"] as? [[String: Any]] else {
            return String(decoding: data.prefix(4000), as: UTF8.self)
        }
        let mentionsSubgroup: ([String: Any]) -> Bool = { event in
            event.values.contains { ($0 as? String)?.localizedCaseInsensitiveContains("подгрупп") == true }
                || event.keys.contains { $0.localizedCaseInsensitiveContains("subgroup") }
        }
        let sample = Array((events.filter(mentionsSubgroup) + events.filter { !mentionsSubgroup($0) }).prefix(3))
        let pretty = try JSONSerialization.data(withJSONObject: sample, options: [.prettyPrinted, .sortedKeys])
        return String(decoding: pretty, as: UTF8.self)
    }

    private func scheduleURL(for group: ScheduleGroup) throws -> URL {
        // IDs from this endpoint are numeric; never allow a path supplied by the UI.
        guard !group.id.isEmpty, group.id.allSatisfy(\.isNumber) else {
            throw ScheduleError.unexpectedResponse
        }
        let url = baseURL.appendingPathComponent(group.id).appendingPathComponent("schedule", isDirectory: true)
        let start = calendar.startOfDay(for: Date())
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
        return components.url!
    }

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar
    }

    private func lesson(from event: [String: JSONValue], index: Int, groupID: String) -> Lesson? {
        func text(_ key: String) -> String {
            event[key]?.string?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        }
        let date = text("date"), timeBegin = text("timeBegin"), timeEnd = text("timeEnd")
        let midnight = ["00:00:00", "00:00"]
        let unspecified = (event["pairNumber"]?.int ?? 0) == 0 && midnight.contains(timeBegin) && midnight.contains(timeEnd)
        guard let starts = parseDate(date, time: timeBegin),
              let parsedEnd = parseDate(date, time: timeEnd),
              unspecified || parsedEnd > starts else { return nil }
        // Untimed events remain visible for their calendar day.
        let ends = unspecified ? calendar.date(byAdding: .day, value: 1, to: starts)! : parsedEnd

        let subgroup = Self.subgroup(in: event)
        var subject = text("title")
        if subgroup != nil {
            // The number is shown as a badge, so the generic marker is redundant.
            subject = subject.replacingOccurrences(of: "(подгруппа)", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return Lesson(
            id: event["id"]?.string ?? "\(groupID)-\(date)-\(timeBegin)-\(index)",
            subject: subject.isEmpty ? "Занятие" : subject,
            kind: text("loadType"),
            startsAt: starts,
            endsAt: ends,
            room: text("auditoryTitle"),
            address: text("auditoryLocation"),
            teacher: text("teacherName"),
            subgroup: subgroup,
            isTimeUnspecified: unspecified
        )
    }

    /// The subgroup field is undocumented, so look for it by name and in text like «1 подгруппа».
    static func subgroup(in event: [String: JSONValue]) -> Int? {
        for (key, value) in event where key.localizedCaseInsensitiveContains("subgroup") {
            if let number = value.int, (1...9).contains(number) { return number }
            if let text = value.string, let number = subgroupNumber(in: text) ?? Int(text), (1...9).contains(number) {
                return number
            }
            if case .object(let nested) = value, let number = subgroup(in: nested) { return number }
        }
        for value in event.values {
            if let text = value.string, let number = subgroupNumber(in: text) { return number }
        }
        return nil
    }

    static func subgroupNumber(in text: String) -> Int? {
        let patterns = [
            #"(\d)\s*(?:-?\s*я\s*)?подгрупп"#,
            #"подгрупп[аы]?\s*(?:№\s*)?(\d)"#,
            #"(\d)\s*п/г"#
        ]
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
                  let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
                  let range = Range(match.range(at: 1), in: text),
                  let number = Int(text[range]), number > 0 else { continue }
            return number
        }
        return nil
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

/// Any JSON value, so events can be read without knowing every field in advance.
enum JSONValue: Decodable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case object([String: JSONValue])
    case array([JSONValue])
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() { self = .null }
        else if let value = try? container.decode(Double.self) { self = .number(value) }
        else if let value = try? container.decode(Bool.self) { self = .bool(value) }
        else if let value = try? container.decode(String.self) { self = .string(value) }
        else if let value = try? container.decode([JSONValue].self) { self = .array(value) }
        else { self = .object(try container.decode([String: JSONValue].self)) }
    }

    var string: String? {
        switch self {
        case .string(let value): return value
        case .number(let value): return value == value.rounded() ? String(Int(value)) : String(value)
        default: return nil
        }
    }

    var int: Int? {
        switch self {
        case .number(let value): return Int(value)
        case .string(let value): return Int(value.trimmingCharacters(in: .whitespaces))
        default: return nil
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
private struct ScheduleResponse: Decodable { let events: [[String: JSONValue]] }
