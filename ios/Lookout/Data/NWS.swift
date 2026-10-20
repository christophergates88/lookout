import Foundation
import CoreLocation

// MARK: - Models (only the fields Lookout uses; everything optional so one odd value can't break a load)

struct NWSPoint: Decodable {
    struct Props: Decodable {
        let forecast: String?
        let forecastHourly: String?
        let timeZone: String?
        let relativeLocation: RelLoc?
    }
    struct RelLoc: Decodable {
        struct P: Decodable { let city: String?; let state: String? }
        let properties: P?
    }
    let properties: Props
}

struct NWSPeriod: Decodable, Identifiable, Sendable {
    struct Quantity: Decodable, Sendable { let value: Double? }
    let number: Int
    let name: String?
    let startTime: String?
    let endTime: String?
    let isDaytime: Bool?
    let temperature: FlexNumber?
    let temperatureUnit: String?
    let windSpeed: String?
    let windDirection: String?
    let shortForecast: String?
    let detailedForecast: String?
    let probabilityOfPrecipitation: Quantity?

    var id: Int { number }
    var start: Date? { DateParse.iso(startTime) }
    var rainChance: Int? { probabilityOfPrecipitation?.value.map { Int($0.rounded()) } }
    var tempF: Int? {
        guard let t = temperature?.value else { return nil }
        return Int((temperatureUnit == "C" ? t * 9 / 5 + 32 : t).rounded())
    }
    var symbol: String { WeatherSymbol.name(for: shortForecast ?? "", day: isDaytime ?? true) }
}

/// A number that the API may send either plain (72) or as {"unitCode": ..., "value": 72}.
struct FlexNumber: Decodable, Sendable {
    let value: Double?
    private struct Wrapped: Decodable { let value: Double? }
    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let d = try? c.decode(Double.self) {
            value = d
        } else if let w = try? c.decode(Wrapped.self) {
            value = w.value
        } else {
            value = nil
        }
    }
}

struct NWSForecast: Decodable {
    struct Props: Decodable { let periods: [NWSPeriod]? }
    let properties: Props
}

struct NWSAlert: Identifiable, Sendable, Hashable {
    let id: String
    let event: String
    let headline: String
    let severity: String
    let urgency: String
    let description: String
    let instruction: String
    let areaDesc: String
    let sender: String
    let ends: Date?
    let shape: GeoShape?

    static func == (a: NWSAlert, b: NWSAlert) -> Bool { a.id == b.id }
    func hash(into h: inout Hasher) { h.combine(id) }

    /// Warnings and Severe/Extreme alerts are the ones worth waking someone for.
    var isSerious: Bool {
        severity == "Extreme" || severity == "Severe" || event.localizedCaseInsensitiveContains("warning")
    }

    var rank: Int {
        switch severity {
        case "Extreme": return 0
        case "Severe": return 1
        case "Moderate": return 2
        case "Minor": return 3
        default: return 4
        }
    }
}

private struct NWSAlertCollection: Decodable {
    struct Feature: Decodable {
        struct P: Decodable {
            let id: String?
            let event: String?
            let headline: String?
            let severity: String?
            let urgency: String?
            let description: String?
            let instruction: String?
            let areaDesc: String?
            let senderName: String?
            let ends: String?
            let expires: String?
        }
        let id: String?
        let geometry: GeoShape?
        let properties: P
    }
    let features: [Feature]?
}

// MARK: - Client

/// National Weather Service (api.weather.gov). Free, public domain, United States only.
enum NWS {
    enum Failure: LocalizedError {
        case outsideUS, http(Int)
        var errorDescription: String? {
            switch self {
            case .outsideUS: return "Forecasts come from the U.S. National Weather Service, so Lookout covers the United States."
            case .http(let code): return "The National Weather Service didn't answer (error \(code)). Pull down to try again."
            }
        }
    }

    static let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 20
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: config)
    }()

    static func get<T: Decodable>(_ url: URL, as type: T.Type) async throws -> T {
        var req = URLRequest(url: url)
        req.setValue(AppConfig.nwsUserAgent, forHTTPHeaderField: "User-Agent")
        req.setValue("application/geo+json", forHTTPHeaderField: "Accept")
        let (data, resp) = try await session.data(for: req)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        if code == 404 { throw Failure.outsideUS }
        guard (200..<300).contains(code) else { throw Failure.http(code) }
        return try JSONDecoder().decode(T.self, from: data)
    }

    private static func fmt(_ v: Double) -> String { String(format: "%.4f", v) }

    struct Forecast: Sendable {
        var place: String
        var hourly: [NWSPeriod]
        var daily: [NWSPeriod]
    }

    /// Place name, hourly and 7-day forecast for a point.
    static func forecast(at c: CLLocationCoordinate2D) async throws -> Forecast {
        let pointURL = URL(string: "https://api.weather.gov/points/\(fmt(c.latitude)),\(fmt(c.longitude))")!
        let point = try await get(pointURL, as: NWSPoint.self)
        let rel = point.properties.relativeLocation?.properties
        let place = [rel?.city, rel?.state].compactMap { $0 }.joined(separator: ", ")

        async let hourly = periods(point.properties.forecastHourly)
        async let daily = periods(point.properties.forecast)
        let (h, d) = await (hourly, daily)
        return Forecast(place: place, hourly: h, daily: d)
    }

    private static func periods(_ link: String?) async -> [NWSPeriod] {
        guard let link, let url = URL(string: link) else { return [] }
        return (try? await get(url, as: NWSForecast.self).properties.periods) ?? []
    }

    /// Active alerts covering a point, most severe first.
    static func alerts(at c: CLLocationCoordinate2D) async throws -> [NWSAlert] {
        let url = URL(string: "https://api.weather.gov/alerts/active?point=\(fmt(c.latitude)),\(fmt(c.longitude))")!
        let col = try await get(url, as: NWSAlertCollection.self)
        let list: [NWSAlert] = (col.features ?? []).compactMap { f in
            let p = f.properties
            guard let id = p.id ?? f.id else { return nil }
            return NWSAlert(
                id: id,
                event: p.event ?? "Weather alert",
                headline: p.headline ?? "",
                severity: p.severity ?? "Unknown",
                urgency: p.urgency ?? "",
                description: p.description ?? "",
                instruction: p.instruction ?? "",
                areaDesc: p.areaDesc ?? "",
                sender: p.senderName ?? "National Weather Service",
                ends: DateParse.iso(p.ends) ?? DateParse.iso(p.expires),
                shape: (f.geometry?.polygons.isEmpty == false) ? f.geometry : nil
            )
        }
        return list.sorted { $0.rank < $1.rank }
    }
}

/// Maps NWS short forecast text to an SF Symbol.
enum WeatherSymbol {
    static func name(for text: String, day: Bool) -> String {
        let t = text.lowercased()
        if t.contains("thunder") || t.contains("t-storm") { return "cloud.bolt.rain.fill" }
        if t.contains("tornado") { return "tornado" }
        if t.contains("hurricane") || t.contains("tropical storm") { return "hurricane" }
        if t.contains("snow") || t.contains("flurr") { return "cloud.snow.fill" }
        if t.contains("sleet") || t.contains("freezing") || t.contains("ice") { return "cloud.sleet.fill" }
        if t.contains("shower") || t.contains("drizzle") { return day ? "cloud.sun.rain.fill" : "cloud.moon.rain.fill" }
        if t.contains("rain") { return "cloud.rain.fill" }
        if t.contains("fog") || t.contains("haze") || t.contains("smoke") { return "cloud.fog.fill" }
        if t.contains("wind") || t.contains("breezy") || t.contains("blustery") { return "wind" }
        if t.contains("partly") || t.contains("mostly sunny") || t.contains("mostly clear") {
            return day ? "cloud.sun.fill" : "cloud.moon.fill"
        }
        if t.contains("cloud") || t.contains("overcast") { return "cloud.fill" }
        if t.contains("sunny") || t.contains("clear") { return day ? "sun.max.fill" : "moon.stars.fill" }
        return day ? "cloud.sun.fill" : "cloud.moon.fill"
    }
}
