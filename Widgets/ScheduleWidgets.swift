import SwiftUI
import WidgetKit

@main
struct ScheduleWidgetBundle: WidgetBundle {
    var body: some Widget {
        NextLessonWidget()
        RoomWidget()
        DayWidget()
        LessonLiveActivity()
    }
}

struct NextLessonWidget: Widget {
    var body: some WidgetConfiguration {
        // The kind is kept from the first version so widgets already on screen keep working.
        StaticConfiguration(kind: "UrFUScheduleWidget", provider: ScheduleProvider()) { entry in
            NextLessonView(entry: entry)
        }
        .configurationDisplayName("Ближайшая пара")
        .description("Текущая или следующая пара: время, предмет и кабинет.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular, .accessoryInline])
    }
}

struct RoomWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "UrFURoomWidget", provider: ScheduleProvider()) { entry in
            RoomView(entry: entry)
        }
        .configurationDisplayName("Кабинет")
        .description("Крупный номер аудитории текущей или следующей пары.")
        .supportedFamilies([.systemSmall, .accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

struct DayWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "UrFUDayWidget", provider: ScheduleProvider()) { entry in
            DayView(entry: entry)
        }
        .configurationDisplayName("Пары на день")
        .description("Средний — пары на сегодня или следующий учебный день. Большой — на несколько дней вперёд.")
        .supportedFamilies([.systemMedium, .systemLarge, .accessoryRectangular])
    }
}
