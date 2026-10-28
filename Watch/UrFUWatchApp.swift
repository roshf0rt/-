import SwiftUI

@main
struct UrFUWatchApp: App {
    @StateObject private var store = WatchStore()

    var body: some Scene {
        WindowGroup {
            WatchHome(store: store)
                .environment(\.locale, RU.locale)
        }
    }
}
