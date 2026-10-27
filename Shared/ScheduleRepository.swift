import Foundation

/// Источник расписания. Реализация может быть любой: сайт, API, ICS-файл.
protocol ScheduleRepository {
    func lessons(forGroup group: String, from start: Date, to end: Date) async throws -> [Lesson]
}

/// Тестовые данные, пока не подключён реальный источник.
/// Когда будет известен адрес API, создайте RemoteScheduleRepository
/// с тем же протоколом и замените здесь MockScheduleRepository.
struct MockScheduleRepository: ScheduleRepository {
    func lessons(forGroup group: String, from start: Date, to end: Date) async throws -> [Lesson] {
        let calendar = Calendar.current
        let day = calendar.startOfDay(for: .now)
        func time(_ hour: Int, _ minute: Int) -> Date {
            calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day) ?? day
        }
        let all = [
            Lesson(subject: "Математический анализ", room: "Л-301", teacher: "Иванов И.И.",
                   start: time(9, 0), end: time(10, 30)),
            Lesson(subject: "Программирование", room: "ИЭФ-412", teacher: "Петров П.П.",
                   start: time(10, 45), end: time(12, 15)),
            Lesson(subject: "Английский язык", room: "Г-205", teacher: nil,
                   start: time(13, 0), end: time(14, 30)),
        ]
        return all.filter { $0.start >= start && $0.start < end }
    }
}
