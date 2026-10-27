import SwiftUI

enum LessonKind {
    case lecture, practice, lab, exam, other

    init(_ text: String) {
        let text = text.lowercased()
        if text.contains("лекц") { self = .lecture }
        else if text.contains("лаб") { self = .lab }
        else if text.contains("практ") || text.contains("семинар") { self = .practice }
        else if text.contains("экзам") || text.contains("зач") || text.contains("консульт") { self = .exam }
        else { self = .other }
    }

    var title: String {
        switch self {
        case .lecture: return "Лекция"
        case .practice: return "Практика"
        case .lab: return "Лабораторная"
        case .exam: return "Аттестация"
        case .other: return "Занятие"
        }
    }

    var color: Color {
        switch self {
        case .lecture: return .blue
        case .practice: return .orange
        case .lab: return .purple
        case .exam: return .red
        case .other: return .teal
        }
    }
}

extension Lesson {
    var lessonKind: LessonKind { LessonKind(kind) }
    var roomTitle: String { room.isEmpty ? "—" : room }

    /// Адрес без пометок в скобках: «(гибридный формат) Ленина, 51» → «Ленина, 51».
    var shortAddress: String {
        address.replacingOccurrences(of: #"\([^)]*\)"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\s{2,}"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: " ,").union(.whitespacesAndNewlines))
    }

    var isHybrid: Bool { "\(room) \(address)".localizedCaseInsensitiveContains("гибрид") }
}

/// Даты и время по-русски независимо от языка, выбранного для приложения.
enum RU {
    static let locale = Locale(identifier: "ru_RU")

    static func time(_ date: Date) -> String {
        date.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits).locale(locale))
    }

    static func timeRange(_ lesson: Lesson) -> String {
        lesson.isTimeUnspecified ? "Время не указано" : "\(time(lesson.startsAt))–\(time(lesson.endsAt))"
    }

    /// «Сегодня, 27 октября», «Завтра, 28 октября», «Четверг, 29 октября».
    static func dayTitle(_ day: Date, now: Date = .now) -> String {
        let date = day.formatted(.dateTime.day().month(.wide).locale(locale))
        if let relative = relativeDay(day, now: now) { return "\(relative), \(date)" }
        let weekday = day.formatted(.dateTime.weekday(.wide).locale(locale))
        return "\(weekday.capitalized(with: locale)), \(date)"
    }

    /// «Сегодня», «Завтра» или «Чт, 29 окт.».
    static func shortDay(_ day: Date, now: Date = .now) -> String {
        relativeDay(day, now: now) ?? day.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).locale(locale))
    }

    /// Когда начнётся пара: «через 25 мин», «завтра в 09:00».
    static func startsIn(_ lesson: Lesson, now: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDate(lesson.startsAt, inSameDayAs: now) {
            let minutes = Int((lesson.startsAt.timeIntervalSince(now) / 60).rounded(.up))
            if minutes < 60 { return "через \(max(minutes, 1)) мин" }
            return "в \(time(lesson.startsAt))"
        }
        return "\(shortDay(lesson.startsAt, now: now).lowercased(with: locale)) в \(time(lesson.startsAt))"
    }

    static func minutesLeft(until date: Date, now: Date) -> String {
        let minutes = Int((date.timeIntervalSince(now) / 60).rounded(.up))
        if minutes < 60 { return "ещё \(max(minutes, 1)) мин" }
        return "ещё \(minutes / 60) ч \(minutes % 60) мин"
    }

    private static func relativeDay(_ day: Date, now: Date) -> String? {
        let calendar = Calendar.current
        if calendar.isDate(day, inSameDayAs: now) { return "Сегодня" }
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now), calendar.isDate(day, inSameDayAs: tomorrow) {
            return "Завтра"
        }
        return nil
    }
}

struct Chip: View {
    let text: String
    let color: Color

    init(_ text: String, color: Color) {
        self.text = text
        self.color = color
    }

    var body: some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .foregroundStyle(color)
            .background(color.opacity(0.16), in: Capsule())
    }
}
