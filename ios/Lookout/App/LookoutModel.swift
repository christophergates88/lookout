import Foundation
import CoreLocation
import Observation

/// Everything Lookout shows for where you are right now. Reloads when you move or it gets stale.
@MainActor
@Observable
final class LookoutModel {
    private(set) var place = ""
    private(set) var hourly: [NWSPeriod] = []
    private(set) var daily: [NWSPeriod] = []
    private(set) var alerts: [NWSAlert] = []
    private(set) var cameras: [Camera] = []
    private(set) var risk: StormRisk?
    /// Town, county and state, for the scanner, safety and news links.
    private(set) var area: LocalArea?
    private(set) var news: [NewsStory] = []
    private(set) var newsLoading = false
    private(set) var newsFailed = false
    private(set) var aircraft: [Aircraft] = []
    private(set) var aircraftUpdatedAt: Date?
    private(set) var quakes: [Quake] = []
    private(set) var weatherError: String?
    private(set) var cameraError: String?
    private(set) var loading = false
    private(set) var updatedAt: Date?

    /// Where the loaded data is for.
    private(set) var loadedFor: CLLocationCoordinate2D?

    var now: NWSPeriod? { hourly.first }
    var today: NWSPeriod? { daily.first }

    /// Reload if we have nothing, moved more than ~3 km, or the data is over 10 minutes old.
    func refreshIfNeeded(for c: CLLocationCoordinate2D?) async {
        guard let c else { return }
        if let last = loadedFor, let t = updatedAt,
           Geo.km(last, c) < 3, Date().timeIntervalSince(t) < 600 { return }
        await refresh(for: c)
    }

    func refresh(for c: CLLocationCoordinate2D?) async {
        guard let c, !loading else { return }
        loading = true
        defer { loading = false }

        async let forecastTask = attempt { try await NWS.forecast(at: c) }
        async let alertsTask = attempt { try await NWS.alerts(at: c) }
        async let camsTask = attempt { try await Windy.nearby(c) }
        async let riskTask = attempt { try await SPC.day1Risk(at: c) }
        async let areaTask = LocalArea.lookup(c)
        async let quakesTask = attempt { try await Sky.quakes(near: c) }
        let (f, a, cams, r) = await (forecastTask, alertsTask, camsTask, riskTask)
        let (foundArea, q) = await (areaTask, quakesTask)

        switch f {
        case .success(let fc):
            place = fc.place
            hourly = fc.hourly
            daily = fc.daily
            weatherError = (fc.hourly.isEmpty && fc.daily.isEmpty) ? "The forecast is temporarily unavailable." : nil
        case .failure(let e):
            weatherError = e.localizedDescription
        }
        if case .success(let list) = a {
            alerts = list
            AlertWatcher.rememberSeen(list)
        }
        switch cams {
        case .success(let list):
            cameras = list
            cameraError = nil
        case .failure:
            cameraError = "Cameras didn't load. Pull down to try again."
        }
        if case .success(let rk) = r { risk = rk }
        if case .success(let list) = q { quakes = list }
        if let foundArea { area = foundArea }

        loadedFor = c
        updatedAt = Date()

        Task { await refreshNews() }
    }

    private var lastNewsRequest: Date?

    /// Local headlines for the current town and county.
    func refreshNews() async {
        guard let area, !newsLoading else { return }
        newsLoading = true
        defer { newsLoading = false }
        for attemptNumber in 0..<2 {
            // GDELT answers one request every 5 seconds per device, so space them out and retry once.
            if let last = lastNewsRequest {
                let wait = 6 - Date().timeIntervalSince(last)
                if wait > 0 { try? await Task.sleep(for: .seconds(wait)) }
            }
            lastNewsRequest = Date()
            do {
                news = try await LocalNews.stories(for: area)
                newsFailed = false
                return
            } catch {
                // Keep any stories we already have; the screens offer Google News links either way.
                if attemptNumber == 1 { newsFailed = news.isEmpty }
            }
        }
    }

    /// Planes overhead. Called by the map every 30 seconds while the layer is on.
    func refreshAircraft(for c: CLLocationCoordinate2D?) async {
        guard let c else { return }
        if let t = aircraftUpdatedAt, Date().timeIntervalSince(t) < 20 { return }
        aircraftUpdatedAt = Date()
        if let list = try? await Sky.aircraft(near: c) { aircraft = list }
    }
}

/// Runs an async call and keeps its error, so several calls can run side by side without
/// one failure cancelling the others.
func attempt<T>(_ body: () async throws -> T) async -> Result<T, Error> {
    do { return .success(try await body()) } catch { return .failure(error) }
}
