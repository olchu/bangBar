import CoreLocation
import Combine
import Foundation
import MapKit

@MainActor
final class MoonLocationService: NSObject, ObservableObject, CLLocationManagerDelegate {
    static let shared = MoonLocationService()

    @Published private(set) var authorizationStatus: CLAuthorizationStatus
    @Published private(set) var isSearching = false
    @Published private(set) var searchError: String?

    private let manager = CLLocationManager()

    override private init() {
        authorizationStatus = manager.authorizationStatus
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
    }

    func requestCurrentLocation() {
        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .authorizedAlways:
            manager.requestLocation()
        default:
            break
        }
    }

    func resolveCity(_ city: String) async -> Bool {
        let query = city.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return false }

        isSearching = true
        searchError = nil
        defer { isSearching = false }

        do {
            guard let request = MKGeocodingRequest(addressString: query),
                  let mapItem = try await request.mapItems.first else {
                searchError = "City not found"
                return false
            }
            saveCity(
                location: mapItem.location,
                name: mapItem.addressRepresentations?.cityName ?? mapItem.name ?? query
            )
            return true
        } catch {
            searchError = "City not found"
            return false
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorizationStatus = manager.authorizationStatus
        if manager.authorizationStatus == .authorizedAlways {
            manager.requestLocation()
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        let defaults = UserDefaults.standard
        defaults.set(location.coordinate.latitude, forKey: BangBarSettings.Key.moonCurrentLatitude)
        defaults.set(location.coordinate.longitude, forKey: BangBarSettings.Key.moonCurrentLongitude)
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        searchError = error.localizedDescription
    }

    private func saveCity(location: CLLocation, name: String) {
        let defaults = UserDefaults.standard
        defaults.set(location.coordinate.latitude, forKey: BangBarSettings.Key.moonLatitude)
        defaults.set(location.coordinate.longitude, forKey: BangBarSettings.Key.moonLongitude)
        defaults.set(name, forKey: BangBarSettings.Key.moonLocationName)
    }
}
