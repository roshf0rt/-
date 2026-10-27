import CoreLocation
import SwiftUI

/// Насколько далеко корпус пары и когда пора выходить. Без геолокации ведёт себя
/// как раньше: краснеет за 15 минут до начала.
struct HurryInfo {
    /// Расстояние в метрах до корпуса, по адресу пары.
    var distances: [String: Double] = [:]

    /// Ближе этого считаем, что вы уже в универе.
    static let campusRadius: Double = 500

    func distance(to lesson: Lesson) -> Double? { distances[lesson.shortAddress] }

    func isAtCampus(for lesson: Lesson) -> Bool {
        (distance(to: lesson) ?? .infinity) <= Self.campusRadius
    }

    /// За сколько до начала пора выходить: дорога (≈4 мин на км, от двери до двери) плюс запас.
    func lead(for lesson: Lesson) -> TimeInterval {
        guard let distance = distance(to: lesson) else { return TimeInterval(Hurry.minutes * 60) }
        if distance <= Self.campusRadius { return 0 }
        let travel = distance / 1000 * 4 + 5
        // Location is only checked in the hour before a pair, so the lead never exceeds it.
        return max(Double(Hurry.minutes), min(travel + 5, 60)) * 60
    }

    func isSoon(_ lesson: Lesson, at date: Date) -> Bool {
        let lead = lead(for: lesson)
        return lead > 0 && !lesson.isTimeUnspecified && lesson.startsAt > date
            && lesson.startsAt.timeIntervalSince(date) <= lead
    }

    /// В универе, и пара скоро начнётся.
    func isSettled(_ lesson: Lesson, at date: Date) -> Bool {
        isAtCampus(for: lesson) && lesson.startsAt > date && lesson.startsAt.timeIntervalSince(date) <= 30 * 60
    }

    func accent(_ lesson: Lesson, at date: Date) -> Color {
        isSoon(lesson, at: date) ? .red : lesson.tint
    }

    func statusColor(_ lesson: Lesson, at date: Date) -> Color {
        isSettled(lesson, at: date) ? .green : accent(lesson, at: date)
    }

    /// «3,2 км», если вы не в универе.
    func distanceText(for lesson: Lesson) -> String? {
        guard let distance = distance(to: lesson), distance > Self.campusRadius else { return nil }
        return (distance / 1000).formatted(.number.precision(.fractionLength(1)).locale(RU.locale)) + " км"
    }
}

private struct HurryKey: EnvironmentKey {
    static let defaultValue = HurryInfo()
}

extension EnvironmentValues {
    var hurry: HurryInfo {
        get { self[HurryKey.self] }
        set { self[HurryKey.self] = newValue }
    }
}

struct Coordinate: Codable, Sendable {
    let latitude: Double
    let longitude: Double

    init(_ location: CLLocation) {
        latitude = location.coordinate.latitude
        longitude = location.coordinate.longitude
    }

    var location: CLLocation { CLLocation(latitude: latitude, longitude: longitude) }
}

/// Текущее место для виджета. Работает, если в приложении разрешили геолокацию
/// «При использовании приложения или виджетов».
@MainActor
final class WidgetLocator: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var continuation: CheckedContinuation<Coordinate?, Never>?

    func current() async -> Coordinate? {
        guard manager.isAuthorizedForWidgetUpdates else { return nil }
        if let location = manager.location, location.timestamp.timeIntervalSinceNow > -10 * 60 {
            return Coordinate(location)
        }
        return await withCheckedContinuation { continuation in
            self.continuation = continuation
            manager.delegate = self
            manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
            manager.requestLocation()
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let coordinate = locations.last.map { Coordinate($0) }
        Task { @MainActor in self.finish(coordinate) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in self.finish(nil) }
    }

    private func finish(_ coordinate: Coordinate?) {
        continuation?.resume(returning: coordinate)
        continuation = nil
    }
}

/// Координаты корпусов по адресу, с кэшем: адреса не меняются.
enum CampusGeocoder {
    private static let key = "geocoder.cache.v1"

    static func coordinate(for address: String) async -> Coordinate? {
        var cache = UserDefaults.standard.data(forKey: key)
            .flatMap { try? JSONDecoder().decode([String: Coordinate].self, from: $0) } ?? [:]
        if let cached = cache[address] { return cached }
        let query = "Екатеринбург, \(address)"
        let found = try? await withDeadline(4) {
            try await CLGeocoder().geocodeAddressString(query).first?.location.map { Coordinate($0) }
        }
        guard let coordinate = found ?? nil else { return nil }
        cache[address] = coordinate
        if let data = try? JSONEncoder().encode(cache) { UserDefaults.standard.set(data, forKey: key) }
        return coordinate
    }
}
