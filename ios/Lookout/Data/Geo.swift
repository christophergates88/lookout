import Foundation
import CoreLocation

enum Geo {
    /// Great-circle distance in kilometres.
    static func km(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D) -> Double {
        let r = 6371.0
        let dLat = (b.latitude - a.latitude) * .pi / 180
        let dLon = (b.longitude - a.longitude) * .pi / 180
        let x = sin(dLat / 2) * sin(dLat / 2)
            + cos(a.latitude * .pi / 180) * cos(b.latitude * .pi / 180) * sin(dLon / 2) * sin(dLon / 2)
        return 2 * r * asin(min(1, sqrt(x)))
    }

    /// Initial bearing from a to b, 0–360 degrees.
    static func bearing(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D) -> Double {
        let lat1 = a.latitude * .pi / 180, lat2 = b.latitude * .pi / 180
        let dLon = (b.longitude - a.longitude) * .pi / 180
        let y = sin(dLon) * cos(lat2)
        let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon)
        let deg = atan2(y, x) * 180 / .pi
        return (deg + 360).truncatingRemainder(dividingBy: 360)
    }

    /// Smallest angle between two headings, 0–180.
    static func angleBetween(_ a: Double, _ b: Double) -> Double {
        let d = abs(a - b).truncatingRemainder(dividingBy: 360)
        return d > 180 ? 360 - d : d
    }

    /// Ray-casting point-in-polygon. `ring` is [[lon, lat], ...] as in GeoJSON.
    static func contains(ring: [[Double]], point: CLLocationCoordinate2D) -> Bool {
        var inside = false
        let x = point.longitude, y = point.latitude
        var j = ring.count - 1
        for i in 0..<ring.count {
            guard ring[i].count >= 2, ring[j].count >= 2 else { j = i; continue }
            let xi = ring[i][0], yi = ring[i][1], xj = ring[j][0], yj = ring[j][1]
            if (yi > y) != (yj > y), x < (xj - xi) * (y - yi) / ((yj - yi) == 0 ? 1e-12 : (yj - yi)) + xi {
                inside.toggle()
            }
            j = i
        }
        return inside
    }
}

/// A GeoJSON Polygon or MultiPolygon. Anything else decodes as empty.
struct GeoShape: Decodable, Sendable {
    /// Polygons; each is a list of rings; each ring is [[lon, lat]].
    var polygons: [[[[Double]]]] = []

    private enum CodingKeys: String, CodingKey { case type, coordinates }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let type = (try? c.decode(String.self, forKey: .type)) ?? ""
        switch type {
        case "Polygon":
            if let p = try? c.decode([[[Double]]].self, forKey: .coordinates) { polygons = [p] }
        case "MultiPolygon":
            if let mp = try? c.decode([[[[Double]]]].self, forKey: .coordinates) { polygons = mp }
        default:
            polygons = []
        }
    }

    init(polygons: [[[[Double]]]]) { self.polygons = polygons }

    /// True when the point is inside the outer ring of any polygon and not inside one of its holes.
    func contains(_ point: CLLocationCoordinate2D) -> Bool {
        for poly in polygons {
            guard let outer = poly.first, Geo.contains(ring: outer, point: point) else { continue }
            let inHole = poly.dropFirst().contains { Geo.contains(ring: $0, point: point) }
            if !inHole { return true }
        }
        return false
    }

    /// Outer rings as coordinates, for drawing on the map.
    var outerRings: [[CLLocationCoordinate2D]] {
        polygons.compactMap { poly in
            poly.first?.compactMap { pair in
                pair.count >= 2 ? CLLocationCoordinate2D(latitude: pair[1], longitude: pair[0]) : nil
            }
        }
    }
}

enum DateParse {
    private static let plain: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()
    private static let fractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    static func iso(_ s: String?) -> Date? {
        guard let s, !s.isEmpty else { return nil }
        return plain.date(from: s) ?? fractional.date(from: s)
    }
}
