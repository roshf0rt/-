import Foundation

/// Одно занятие. Общая модель для приложения и виджета.
struct Lesson: Codable, Identifiable, Hashable {
    let subject: String
    let room: String?
    let teacher: String?
    let start: Date
    let end: Date

    var id: String { "\(start.timeIntervalSince1970)-\(subject)" }
}
