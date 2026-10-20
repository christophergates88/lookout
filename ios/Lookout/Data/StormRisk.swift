import Foundation
import CoreLocation
import SwiftUI

/// Today's severe thunderstorm risk at a point, from the Storm Prediction Center's day 1 outlook.
struct StormRisk: Sendable {
    /// SPC category: TSTM, MRGL, SLGT, ENH, MDT, HIGH, or NONE.
    let code: String

    var level: Int {
        ["NONE", "TSTM", "MRGL", "SLGT", "ENH", "MDT", "HIGH"].firstIndex(of: code) ?? 0
    }

    var title: String {
        switch code {
        case "TSTM": return "General thunderstorms"
        case "MRGL": return "Marginal risk (1 of 5)"
        case "SLGT": return "Slight risk (2 of 5)"
        case "ENH": return "Enhanced risk (3 of 5)"
        case "MDT": return "Moderate risk (4 of 5)"
        case "HIGH": return "High risk (5 of 5)"
        default: return "No severe storms expected"
        }
    }

    var detail: String {
        switch code {
        case "TSTM": return "Thunderstorms possible, not expected to be severe."
        case "MRGL": return "Isolated severe storms possible."
        case "SLGT": return "Scattered severe storms possible."
        case "ENH": return "Numerous severe storms possible."
        case "MDT": return "Widespread severe storms likely."
        case "HIGH": return "Widespread severe storms expected. Have a plan."
        default: return "The Storm Prediction Center has no severe risk here today."
        }
    }

    var color: Color {
        switch code {
        case "TSTM": return Color(red: 0.6, green: 0.85, blue: 0.6)
        case "MRGL": return Color(red: 0.3, green: 0.75, blue: 0.4)
        case "SLGT": return Color(red: 0.98, green: 0.85, blue: 0.3)
        case "ENH": return Color(red: 1.0, green: 0.6, blue: 0.2)
        case "MDT": return Color(red: 0.95, green: 0.3, blue: 0.3)
        case "HIGH": return Color(red: 0.85, green: 0.3, blue: 0.85)
        default: return .lkOK
        }
    }
}

private struct SPCCollection: Decodable {
    struct Feature: Decodable {
        struct P: Decodable { let LABEL: String? }
        let geometry: GeoShape?
        let properties: P?
    }
    let features: [Feature]?
}

enum SPC {
    static func day1Risk(at c: CLLocationCoordinate2D) async throws -> StormRisk {
        var req = URLRequest(url: AppConfig.spcDay1URL)
        req.setValue(AppConfig.nwsUserAgent, forHTTPHeaderField: "User-Agent")
        req.timeoutInterval = 20
        let (data, _) = try await URLSession.shared.data(for: req)
        let col = try JSONDecoder().decode(SPCCollection.self, from: data)
        var best = StormRisk(code: "NONE")
        for f in col.features ?? [] {
            guard let label = f.properties?.LABEL, let shape = f.geometry, shape.contains(c) else { continue }
            let risk = StormRisk(code: label)
            if risk.level > best.level { best = risk }
        }
        return best
    }
}
