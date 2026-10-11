import CoreLocation
import MapKit
import Observation

/// Place lookups (Apple Maps), one-off GPS readings and distances for the "near me" filter.
/// A student's area stays on the phone; only listing addresses and their coordinates go to the server.
enum Geo {
    struct Problem: LocalizedError {
        let errorDescription: String?
    }

    /// A ZIP code or "Town, State" typed by a student.
    static func find(_ text: String) async throws -> CLLocation {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = text
        request.resultTypes = .address
        guard let item = try? await MKLocalSearch(request: request).start().mapItems.first, let location = location(of: item)
        else { throw Problem(errorDescription: "Couldn't find that place. Check the spelling, or try a ZIP code.") }
        return location
    }

    /// The full address and map position of an Apple Maps suggestion an organization picked.
    static func resolve(_ suggestion: MKLocalSearchCompletion) async throws -> (address: String, location: CLLocation) {
        guard let item = try? await MKLocalSearch(request: MKLocalSearch.Request(completion: suggestion)).start().mapItems.first,
              let location = location(of: item)
        else { throw Problem(errorDescription: "Couldn't look up that address. Check your connection and try again.") }
        let address = [suggestion.title, suggestion.subtitle].filter { !$0.isEmpty }.joined(separator: ", ")
        return (address, location)
    }

    /// One GPS reading. Asks for permission the first time.
    @MainActor
    static func currentLocation() async throws -> CLLocation {
        try await OneShotLocation().get()
    }

    static func miles(_ a: CLLocation, _ b: CLLocation) -> Double { a.distance(from: b) / 1609.344 }

    private static func location(of item: MKMapItem) -> CLLocation? {
        if #available(iOS 26, *) { return item.location }
        return item.placemark.location
    }
}

/// Where the student's "near me" area is saved. On this phone only; cleared on sign-out.
enum AreaKey {
    static let name = "areaName"
    static let lat = "areaLat"
    static let lng = "areaLng"
    static let radius = "radiusMiles"
    static let all = [name, lat, lng, radius]
}

/// Apple Maps address suggestions while an organization types a listing's address.
@Observable
final class AddressCompleter: NSObject, MKLocalSearchCompleterDelegate {
    private(set) var suggestions: [MKLocalSearchCompletion] = []
    @ObservationIgnored private let completer = MKLocalSearchCompleter()

    override init() {
        super.init()
        completer.delegate = self
        completer.resultTypes = .address
    }

    func search(_ text: String) {
        if text.trimmed.isEmpty {
            completer.cancel()
            suggestions = []
        } else {
            completer.queryFragment = text
        }
    }

    func clear() {
        completer.cancel()
        suggestions = []
    }

    func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        suggestions = Array(completer.results.prefix(5))
    }

    func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        suggestions = []
    }
}

/// Turns CLLocationManager's delegate callbacks into one async call.
private final class OneShotLocation: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var continuation: CheckedContinuation<CLLocation, Error>?

    func get() async throws -> CLLocation {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            manager.delegate = self
            manager.desiredAccuracy = kCLLocationAccuracyKilometer // a town-level fix is plenty, and faster
            locationManagerDidChangeAuthorization(manager)
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization() // answers arrive back here
        case .authorizedWhenInUse, .authorizedAlways:
            manager.requestLocation()
        default:
            finish(.failure(Geo.Problem(errorDescription:
                "Location is off for Letterman. Turn it on in Settings > Privacy & Security > Location Services, or type a ZIP code instead.")))
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        if let location = locations.last { finish(.success(location)) }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        finish(.failure(Geo.Problem(errorDescription: "Couldn't get your location. Try again, or type a ZIP code instead.")))
    }

    // Callbacks can repeat (e.g. permission granted, then the location); only the first answer counts.
    private func finish(_ result: Result<CLLocation, Error>) {
        continuation?.resume(with: result)
        continuation = nil
    }
}
