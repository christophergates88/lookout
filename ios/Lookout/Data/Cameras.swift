import Foundation
import CoreLocation

/// A public webcam near the user.
struct Camera: Identifiable, Sendable, Hashable {
    let id: String
    let title: String
    let city: String
    let coordinate: CLLocationCoordinate2D
    /// Preview image. On Windy's free tier these links expire after about 10 minutes, so they are
    /// refreshed with every load and never stored.
    let imageURL: URL?
    let pageURL: URL
    let live: Bool
    var km: Double = 0

    static func == (a: Camera, b: Camera) -> Bool { a.id == b.id }
    func hash(into h: inout Hasher) { h.combine(id) }
}

private struct WindyResponse: Decodable {
    struct Webcam: Decodable {
        struct Images: Decodable {
            struct ImageSet: Decodable { let preview: String?; let thumbnail: String? }
            let current: ImageSet?
        }
        struct Location: Decodable {
            let latitude: Double?
            let longitude: Double?
            let city: String?
            let region: String?
        }
        struct URLs: Decodable { let detail: String? }
        /// Only whether a live stream exists matters; the shape of each entry varies, so it isn't decoded.
        struct Player: Decodable {
            let hasLive: Bool
            private enum K: String, CodingKey { case live }
            init(from decoder: Decoder) throws {
                let c = try decoder.container(keyedBy: K.self)
                hasLive = c.contains(.live) && !((try? c.decodeNil(forKey: .live)) ?? true)
            }
        }
        let webcamId: FlexID
        let title: String?
        let status: String?
        let images: Images?
        let location: Location?
        let urls: URLs?
        let player: Player?
    }
    let webcams: [Webcam]?
}

/// Windy sends webcam ids as numbers; accept strings too.
private struct FlexID: Decodable {
    let text: String
    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let i = try? c.decode(Int64.self) { text = String(i) }
        else { text = (try? c.decode(String.self)) ?? UUID().uuidString }
    }
}

/// Windy Webcams API (free tier: images must link back to windy.com and credit Windy).
enum Windy {
    static var isConfigured: Bool { !AppConfig.windyKey.trimmingCharacters(in: .whitespaces).isEmpty }

    static func nearby(_ c: CLLocationCoordinate2D) async throws -> [Camera] {
        guard isConfigured else { return [] }
        var comps = URLComponents(string: "https://api.windy.com/webcams/api/v3/webcams")!
        comps.queryItems = [
            URLQueryItem(name: "nearby", value: String(format: "%.4f,%.4f,%d", c.latitude, c.longitude, AppConfig.cameraRadiusKm)),
            URLQueryItem(name: "limit", value: "50"),
            URLQueryItem(name: "include", value: "images,location,player,urls"),
            URLQueryItem(name: "lang", value: "en")
        ]
        var req = URLRequest(url: comps.url!)
        req.setValue(AppConfig.windyKey, forHTTPHeaderField: "x-windy-api-key")
        req.timeoutInterval = 20
        let (data, resp) = try await URLSession.shared.data(for: req)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(code) else { throw NWS.Failure.http(code) }
        let decoded = try JSONDecoder().decode(WindyResponse.self, from: data)
        let cams: [Camera] = (decoded.webcams ?? []).compactMap { w in
            guard let lat = w.location?.latitude, let lon = w.location?.longitude else { return nil }
            if let s = w.status, s != "active" { return nil }
            let coord = CLLocationCoordinate2D(latitude: lat, longitude: lon)
            let page = w.urls?.detail.flatMap(URL.init(string:))
                ?? URL(string: "https://www.windy.com/webcams/\(w.webcamId.text)")!
            let img = (w.images?.current?.preview ?? w.images?.current?.thumbnail).flatMap(URL.init(string:))
            var cam = Camera(
                id: "w" + w.webcamId.text,
                title: w.title ?? "Webcam",
                city: [w.location?.city, w.location?.region].compactMap { $0 }.joined(separator: ", "),
                coordinate: coord,
                imageURL: img,
                pageURL: page,
                live: w.player?.hasLive ?? false
            )
            cam.km = Geo.km(c, coord)
            return cam
        }
        return cams.sorted { $0.km < $1.km }
    }
}
