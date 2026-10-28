import Foundation

/// Что написать, когда пары на сегодня кончились или начались каникулы.
/// Фразы меняются от дня к дню, чтобы не приедались.
enum Mood {
    /// Перерыв длиннее этого — уже каникулы, а не выходные.
    static let vacationGap: TimeInterval = 10 * 24 * 60 * 60

    static let dayDoneLines = [
        "Ура, пары закончились! 🎉",
        "Всё, учёба на сегодня окончена 🥳",
        "Свободны! Мозг просит перерыв 🧠",
        "Пары кончились, можно выдохнуть 😌",
        "Отбой по парам. Гуляйте 🚶",
        "Газ домой! 🏠",
    ]

    /// Перемена между парами: без спешки.
    static let breakLines = [
        "Перемена! Выдохни ☕",
        "Перемена: вода, мемы, жизнь 📱",
        "Перемена, можно не торопиться 🛋️",
    ]

    /// Только за 15 минут до пары, не раньше.
    static let goLines = [
        "Газ на пару! 🚀",
        "Газ на пару, без опозданий 🏃",
    ]

    /// Каникулы отмечает жест 🤙, он же на виджете и в приложении.
    static let vacationEmoji = "🤙"

    static let vacationLines = [
        "Каникулы! Пары отдыхают 🏖️",
        "Расписание в отпуске. Вы тоже 🌴",
        "Каникулы — это не миф, это вы 😎",
    ]

    static func line(_ lines: [String], on date: Date) -> String {
        let day = Calendar.current.ordinality(of: .day, in: .era, for: date) ?? 0
        return lines[day % lines.count]
    }

    /// Сегодня были пары и все уже прошли.
    static func dayDone(_ lessons: [Lesson], now: Date) -> Bool {
        let today = lessons.filter { !$0.isTimeUnspecified && Calendar.current.isDate($0.startsAt, inSameDayAs: now) }
        guard let last = today.map(\.endsAt).max() else { return false }
        return now >= last
    }

    /// Сколько дней до первой пары, если впереди каникулы; иначе nil.
    static func vacationDays(_ lessons: [Lesson], now: Date) -> Int? {
        let future = lessons.filter { !$0.isTimeUnspecified && $0.startsAt > now }.map(\.startsAt).min()
        guard let next = future, next.timeIntervalSince(now) >= vacationGap else { return nil }
        return Calendar.current.dateComponents([.day], from: now, to: next).day
    }
}
