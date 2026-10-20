import Foundation
import CoreLocation

/// A plane overhead, from the adsb.lol open flight-tracking network.
struct Aircraft: Identifiable, Sendable, Hashable {
    let id: String
    let callsign: String
    let type: String?
    /// Feet. Nil when on the ground or unknown.
    let altitudeFt: Int?
    let onGround: Bool
    let speedKt: Int?
    /// Degrees from north.
    let track: Double?
    let coordinate: CLLocationCoordinate2D

    static func == (a: Aircraft, b: Aircraft) -> Bool { a.id == b.id }
    func hash(into h: inout Hasher) { h.combine(id) }

    var summary: String {
        var parts: [String] = []
        if let type { parts.append(type) }
        if onGround { parts.append("On the ground") }
        else if let altitudeFt { parts.append("\(altitudeFt.formatted()) ft") }
        if let speedKt { parts.append("\(speedKt) kt") }
        return parts.joined(separator: ", ")
    }

    var trackURL: URL? { URL(string: "https://globe.adsb.lol/?icao=\(id)") }
}

/// A recent earthquake nearby, from the U.S. Geological Survey.
struct Quake: Identifiable, Sendable, Hashable {
    let id: String
    let magnitude: Double
    let place: String
    let time: Date
    let coordinate: CLLocationCoordinate2D
    let url: URL?

    static func == (a: Quake, b: Quake) -> Bool { a.id == b.id }
    func hash(into h: inout Hasher) { h.combine(id) }
}

enum Sky {
    private static let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: config)
    }()

    /// Aircraft within about 25 nautical miles.
    static func aircraft(near c: CLLocationCoordinate2D) async throws -> [Aircraft] {
        let url = URL(string: String(format: "https://api.adsb.lol/v2/point/%.4f/%.4f/25", c.latitude, c.longitude))!
        let (data, resp) = try await session.data(from: url)
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let list = root["ac"] as? [[String: Any]] else { return [] }
        return list.compactMap { a in
            guard let hex = a["hex"] as? String,
                  let lat = a["lat"] as? Double, let lon = a["lon"] as? Double else { return nil }
            let flight = (a["flight"] as? String)?.trimmingCharacters(in: .whitespaces)
            let reg = a["r"] as? String
            let alt = a["alt_baro"]
            let ground = (alt as? String) == "ground"
            return Aircraft(
                id: hex,
                callsign: [flight, reg].compactMap { $0 }.first { !$0.isEmpty } ?? hex.uppercased(),
                type: a["t"] as? String,
                altitudeFt: (alt as? NSNumber)?.intValue,
                onGround: ground,
                speedKt: (a["gs"] as? NSNumber).map { Int($0.doubleValue.rounded()) },
                track: (a["track"] as? NSNumber)?.doubleValue ?? (a["calc_track"] as? NSNumber)?.doubleValue,
                coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon)
            )
        }
    }

    /// Earthquakes of magnitude 1 or more within about 190 miles in the past week.
    static func quakes(near c: CLLocationCoordinate2D) async throws -> [Quake] {
        let start = Date().addingTimeInterval(-7 * 86_400)
        let day = ISO8601DateFormatter.string(from: start, timeZone: TimeZone(identifier: "UTC")!, formatOptions: [.withFullDate])
        var comps = URLComponents(string: "https://earthquake.usgs.gov/fdsnws/event/1/query")!
        comps.queryItems = [
            URLQueryItem(name: "format", value: "geojson"),
            URLQueryItem(name: "latitude", value: String(format: "%.3f", c.latitude)),
            URLQueryItem(name: "longitude", value: String(format: "%.3f", c.longitude)),
            URLQueryItem(name: "maxradiuskm", value: "300"),
            URLQueryItem(name: "starttime", value: day),
            URLQueryItem(name: "minmagnitude", value: "1"),
            URLQueryItem(name: "orderby", value: "time"),
            URLQueryItem(name: "limit", value: "100")
        ]
        let (data, resp) = try await session.data(from: comps.url!)
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let feats = root["features"] as? [[String: Any]] else { return [] }
        return feats.compactMap { f in
            guard let id = f["id"] as? String,
                  let p = f["properties"] as? [String: Any],
                  let g = f["geometry"] as? [String: Any],
                  let xy = g["coordinates"] as? [Double], xy.count >= 2,
                  let mag = (p["mag"] as? NSNumber)?.doubleValue,
                  let ms = (p["time"] as? NSNumber)?.doubleValue else { return nil }
            return Quake(
                id: id,
                magnitude: mag,
                place: p["place"] as? String ?? "Earthquake",
                time: Date(timeIntervalSince1970: ms / 1000),
                coordinate: CLLocationCoordinate2D(latitude: xy[1], longitude: xy[0]),
                url: (p["url"] as? String).flatMap(URL.init(string:))
            )
        }
    }
}
