import SwiftUI
import WidgetKit

@main
struct ScheduleWidgetBundle: WidgetBundle {
    var body: some Widget {
        NextLessonWidget()
        RoomWidget()
        DayWidget()
    }
}

struct NextLessonWidget: Widget {
    var body: some WidgetConfiguration {
        // The kind is kept from the first version so widgets already on screen keep working.
        AppIntentConfiguration(kind: "UrFUScheduleWidget", intent: ScheduleConfigurationIntent.self,
                               provider: ScheduleProvider()) { entry in
            NextLessonView(entry: entry)
        }
        .configurationDisplayName("Ближайшая пара")
        .description("Текущая или следующая пара: время, предмет и кабинет.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular, .accessoryInline])
    }
}

struct RoomWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "UrFURoomWidget", intent: ScheduleConfigurationIntent.self,
                               provider: ScheduleProvider()) { entry in
            RoomView(entry: entry)
        }
        .configurationDisplayName("Кабинет")
        .description("Крупный номер аудитории текущей или следующей пары.")
        .supportedFamilies([.systemSmall, .accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

struct DayWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "UrFUDayWidget", intent: ScheduleConfigurationIntent.self,
                               provider: ScheduleProvider()) { entry in
            DayView(entry: entry)
        }
        .configurationDisplayName("Пары на день")
        .description("Оставшиеся пары на сегодня, а вечером — на следующий учебный день.")
        .supportedFamilies([.systemMedium, .systemLarge, .accessoryRectangular])
    }
}
