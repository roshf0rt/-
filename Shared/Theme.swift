import SwiftUI

/// Цвет оформления. «По типу пары» красит лекции, практики и лабораторные по-разному,
/// остальные варианты красят всё одним цветом.
enum AppTheme: String, CaseIterable, Identifiable {
    case byKind, blue, indigo, purple, pink, green, teal, graphite

    var id: String { rawValue }

    var title: String {
        switch self {
        case .byKind: return "По типу пары"
        case .blue: return "Синий"
        case .indigo: return "Индиго"
        case .purple: return "Фиолетовый"
        case .pink: return "Розовый"
        case .green: return "Зелёный"
        case .teal: return "Бирюзовый"
        case .graphite: return "Графит"
        }
    }

    /// Один цвет темы; для «По типу пары» — образец для списка.
    var color: Color {
        switch self {
        case .byKind: return .orange
        case .blue: return .blue
        case .indigo: return .indigo
        case .purple: return .purple
        case .pink: return .pink
        case .green: return .green
        case .teal: return .teal
        case .graphite: return .gray
        }
    }

    /// Текущая тема. Приложение меняет её из настроек, виджет перечитывает при каждом обновлении.
    static var current: AppTheme = stored

    /// The app keeps the theme in its own store; the widget reads what the app shared.
    static var stored: AppTheme {
        // Installers may give the app and the widget different App Groups, so the widget
        // trusts what the app put in the keychain first.
        let isWidget = Bundle.main.bundlePath.hasSuffix(".appex")
        let raw = isWidget ? (SharedSettings.load()?.theme ?? ScheduleStore.theme) : ScheduleStore.theme
        return raw.flatMap(AppTheme.init(rawValue:)) ?? .byKind
    }
}

extension Lesson {
    /// Цвет пары с учётом выбранной темы.
    var tint: Color {
        AppTheme.current == .byKind ? lessonKind.color : AppTheme.current.color
    }
}
