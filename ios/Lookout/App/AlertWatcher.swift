import Foundation
import BackgroundTasks
import UserNotifications
import CoreLocation

/// Lookout Pro: checks for new serious NWS alerts in the background (your last location and saved
/// places) and posts a notification. iOS decides exactly when background checks run, so this is
/// a helper, not a replacement for the Wireless Emergency Alerts built into the phone.
enum AlertWatcher {
    private static let seenKey = "seenAlertIDs"
    static let enabledKey = "backgroundAlertsOn"

    static var isEnabled: Bool { UserDefaults.standard.bool(forKey: enabledKey) }

    /// Ask iOS to wake Lookout in about 15 minutes.
    static func schedule() {
        guard isEnabled else { return }
        let req = BGAppRefreshTaskRequest(identifier: AppConfig.alertRefreshTaskID)
        req.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)
        try? BGTaskScheduler.shared.submit(req)
    }

    static func cancel() {
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: AppConfig.alertRefreshTaskID)
    }

    static func requestPermission() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    /// Alerts already shown on screen shouldn't also arrive as notifications.
    static func rememberSeen(_ alerts: [NWSAlert]) {
        var seen = UserDefaults.standard.stringArray(forKey: seenKey) ?? []
        for a in alerts where !seen.contains(a.id) { seen.append(a.id) }
        // Keep the newest 400; alert ids are unique so old ones never come back.
        UserDefaults.standard.set(Array(seen.suffix(400)), forKey: seenKey)
    }

    /// The background job: look up alerts for each watched spot, notify about new serious ones.
    static func runCheck() async {
        defer { schedule() }
        guard isEnabled, UserDefaults.standard.bool(forKey: ProStore.cachedProKey) else { return }

        var spots: [(String, CLLocationCoordinate2D)] = []
        if let here = LocationManager.lastSaved { spots.append(("Your location", here)) }
        for p in PlacesStore.load() { spots.append((p.name, p.coordinate)) }

        var seen = UserDefaults.standard.stringArray(forKey: seenKey) ?? []
        for (name, coord) in spots.prefix(AppConfig.proSavedPlaces + 1) {
            guard let alerts = try? await NWS.alerts(at: coord) else { continue }
            for alert in alerts where alert.isSerious && !seen.contains(alert.id) {
                seen.append(alert.id)
                await notify(alert, place: name)
            }
        }
        UserDefaults.standard.set(Array(seen.suffix(400)), forKey: seenKey)
    }

    private static func notify(_ alert: NWSAlert, place: String) async {
        let content = UNMutableNotificationContent()
        content.title = "\(alert.event) · \(place)"
        content.body = alert.headline.isEmpty ? alert.areaDesc : alert.headline
        content.sound = .default
        let req = UNNotificationRequest(identifier: alert.id, content: content, trigger: nil)
        try? await UNUserNotificationCenter.current().add(req)
    }
}
