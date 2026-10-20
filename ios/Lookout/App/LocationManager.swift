import Foundation
import CoreLocation

/// Where the phone is. Uses "While Using the App" permission only.
@MainActor
@Observable
final class LocationManager: NSObject, CLLocationManagerDelegate {
    private(set) var location: CLLocation?
    private(set) var authorization: CLAuthorizationStatus = .notDetermined
    /// Driving mode wants continuous, precise updates; the rest of the app is happy with coarse ones.
    private(set) var isTracking = false

    private let manager = CLLocationManager()

    /// The last known spot, kept so background alert checks know where to look.
    nonisolated static let lastLatKey = "lastLat"
    nonisolated static let lastLonKey = "lastLon"

    nonisolated static var lastSaved: CLLocationCoordinate2D? {
        let d = UserDefaults.standard
        guard d.object(forKey: lastLatKey) != nil else { return nil }
        return CLLocationCoordinate2D(latitude: d.double(forKey: lastLatKey), longitude: d.double(forKey: lastLonKey))
    }

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        manager.distanceFilter = 300
        authorization = manager.authorizationStatus
    }

    var coordinate: CLLocationCoordinate2D? { location?.coordinate }

    var isDenied: Bool { authorization == .denied || authorization == .restricted }

    func start() {
        if manager.authorizationStatus == .notDetermined {
            manager.requestWhenInUseAuthorization()
        }
        manager.startUpdatingLocation()
    }

    /// Precise, frequent updates (driving mode). Call `endTracking()` when done.
    func beginTracking() {
        isTracking = true
        manager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        manager.distanceFilter = 15
        manager.activityType = .automotiveNavigation
        manager.startUpdatingLocation()
    }

    func endTracking() {
        isTracking = false
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        manager.distanceFilter = 300
        manager.activityType = .other
    }

    // MARK: CLLocationManagerDelegate (called on the main thread because the manager was made there)

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let last = locations.last else { return }
        Task { @MainActor in
            self.location = last
            let d = UserDefaults.standard
            d.set(last.coordinate.latitude, forKey: Self.lastLatKey)
            d.set(last.coordinate.longitude, forKey: Self.lastLonKey)
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            self.authorization = status
            if status == .authorizedWhenInUse || status == .authorizedAlways {
                self.manager.startUpdatingLocation()
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {}
}
