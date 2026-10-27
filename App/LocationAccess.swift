import CoreLocation
import SwiftUI

/// Разрешение на геолокацию. Само приложение место не использует — его берёт виджет,
/// но спросить разрешение может только приложение.
@MainActor
final class LocationAccess: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published private(set) var status: CLAuthorizationStatus
    private let manager: CLLocationManager

    override init() {
        let manager = CLLocationManager()
        self.manager = manager
        status = manager.authorizationStatus
        super.init()
        manager.delegate = self
    }

    func request() {
        manager.requestWhenInUseAuthorization()
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in self.status = status }
    }
}

struct LocationSection: View {
    @StateObject private var access = LocationAccess()

    var body: some View {
        Section {
            switch access.status {
            case .notDetermined:
                Button {
                    access.request()
                } label: {
                    Label("Разрешить геолокацию", systemImage: "location")
                }
            case .authorizedWhenInUse, .authorizedAlways:
                Label("Геолокация разрешена", systemImage: "location.fill")
                    .foregroundStyle(.green)
            default:
                Button {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                } label: {
                    Label("Геолокация запрещена — открыть настройки", systemImage: "location.slash")
                }
            }
        } header: {
            Text("Геолокация")
        } footer: {
            Text("Виджет считает, сколько ехать до корпуса пары. В универе он спокоен, а если вы далеко — краснеет заранее и пишет «ВЫХОДИ». При запросе выберите «При использовании приложения или виджетов».")
        }
    }
}
