import Combine
import CoreLocation
import Foundation
import MapKit

struct WeatherInfo {
    let temperature: Double
    let weatherCode: Int
    let locationTitle: String?

    var temperatureString: String {
        let value = Int(temperature.rounded())
        return value > 0 ? "+\(value)°" : "\(value)°"
    }

    var symbolName: String {
        switch weatherCode {
        case 0:
            return "sun.max.fill"
        case 1...3:
            return "cloud.sun.fill"
        case 45...48:
            return "cloud.fog.fill"
        case 51...67:
            return "cloud.rain.fill"
        case 71...77:
            return "cloud.snow.fill"
        case 80...82:
            return "cloud.heavyrain.fill"
        case 95...99:
            return "cloud.bolt.rain.fill"
        default:
            return "cloud.fill"
        }
    }

    var conditionTitle: String {
        let isRussian = Locale.autoupdatingCurrent.language.languageCode?.identifier == "ru"

        switch weatherCode {
        case 0:
            return isRussian ? "Ясно" : "Clear"
        case 1...3:
            return isRussian ? "Облачно" : "Cloudy"
        case 45...48:
            return isRussian ? "Туман" : "Fog"
        case 51...67, 80...82:
            return isRussian ? "Дождь" : "Rain"
        case 71...77:
            return isRussian ? "Снег" : "Snow"
        case 95...99:
            return isRussian ? "Гроза" : "Storm"
        default:
            return isRussian ? "Погода" : "Weather"
        }
    }
}

final class WeatherService: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published private(set) var info: WeatherInfo?

    private let locationManager = CLLocationManager()
    private var refreshTimer: Timer?
    private var lastCoordinate: CLLocationCoordinate2D?
    private var locationTitle: String?

    override init() {
        super.init()

        locationManager.delegate = self
        refresh()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 30 * 60, repeats: true) { [weak self] _ in
            self?.refresh()
        }
    }

    func refresh() {
        requestLocationIfNeeded()

        if let coordinate = lastCoordinate ?? locationManager.location?.coordinate {
            fetchWeather(for: coordinate)
        }
    }

    private func requestLocationIfNeeded() {
        switch locationManager.authorizationStatus {
        case .notDetermined:
            locationManager.requestWhenInUseAuthorization()
        case .authorizedAlways, .authorizedWhenInUse:
            locationManager.requestLocation()
        case .denied, .restricted:
            info = nil
        @unknown default:
            info = nil
        }
    }

    private func fetchWeather(for coordinate: CLLocationCoordinate2D) {
        var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")
        components?.queryItems = [
            URLQueryItem(name: "latitude", value: String(format: "%.4f", coordinate.latitude)),
            URLQueryItem(name: "longitude", value: String(format: "%.4f", coordinate.longitude)),
            URLQueryItem(name: "current", value: "temperature_2m,weather_code"),
            URLQueryItem(name: "temperature_unit", value: "celsius")
        ]

        guard let url = components?.url else { return }

        URLSession.shared.dataTask(with: url) { [weak self] data, response, _ in
            guard
                let data,
                let httpResponse = response as? HTTPURLResponse,
                (200..<300).contains(httpResponse.statusCode)
            else {
                DispatchQueue.main.async {
                    self?.info = nil
                }
                return
            }

            DispatchQueue.main.async {
                guard let response = try? JSONDecoder().decode(OpenMeteoResponse.self, from: data) else {
                    self?.info = nil
                    return
                }
                self?.info = WeatherInfo(
                    temperature: response.current.temperature,
                    weatherCode: response.current.weatherCode,
                    locationTitle: self?.locationTitle
                )
            }
        }
        .resume()
    }

    private func updateLocationTitle(for location: CLLocation) {
        Task { [weak self] in
            guard let request = MKReverseGeocodingRequest(location: location) else { return }
            let mapItems = try? await request.mapItems
            let title = mapItems?.first.flatMap { item in
                item.address?.shortAddress ?? item.name
            }

            self?.locationTitle = title

            if let info = self?.info {
                self?.info = WeatherInfo(
                    temperature: info.temperature,
                    weatherCode: info.weatherCode,
                    locationTitle: title
                )
            }
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        requestLocationIfNeeded()
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        let coordinate = location.coordinate
        lastCoordinate = coordinate
        updateLocationTitle(for: location)
        fetchWeather(for: coordinate)
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        info = nil
    }
}

private struct OpenMeteoResponse: Decodable {
    let current: Current

    struct Current: Decodable {
        let temperature: Double
        let weatherCode: Int

        enum CodingKeys: String, CodingKey {
            case temperature = "temperature_2m"
            case weatherCode = "weather_code"
        }
    }
}
