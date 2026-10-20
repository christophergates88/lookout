import Foundation
import CoreLocation

/// Town, county and state for where you are, from Apple's reverse geocoder.
struct LocalArea: Sendable, Equatable {
    var city: String?
    /// For example "Putnam County".
    var county: String?
    /// Two-letter U.S. state code, for example "GA". Nil outside the United States.
    var stateCode: String?

    var stateName: String? { stateCode.flatMap { USStates.names[$0] } }

    /// "Eatonton, GA"
    var place: String { [city ?? county, stateCode].compactMap { $0 }.joined(separator: ", ") }

    /// "Putnam County, GA", or the town when the county is unknown.
    var countyOrPlace: String {
        if let county { return [county, stateCode].compactMap { $0 }.joined(separator: ", ") }
        return place
    }

    static func lookup(_ c: CLLocationCoordinate2D) async -> LocalArea? {
        let geocoder = CLGeocoder()
        let loc = CLLocation(latitude: c.latitude, longitude: c.longitude)
        guard let p = try? await geocoder.reverseGeocodeLocation(loc).first else { return nil }
        guard p.isoCountryCode == "US" else {
            return LocalArea(city: p.locality, county: p.subAdministrativeArea, stateCode: nil)
        }
        var code = p.administrativeArea
        if let a = code, a.count > 2 { code = USStates.names.first { $0.value == a }?.key }
        return LocalArea(city: p.locality, county: p.subAdministrativeArea, stateCode: code)
    }
}

/// U.S. states and territories: names, FIPS codes (Broadcastify uses them for its state pages)
/// and each state's official 511 traveler site.
enum USStates {
    static let names: [String: String] = [
        "AL": "Alabama", "AK": "Alaska", "AZ": "Arizona", "AR": "Arkansas", "CA": "California",
        "CO": "Colorado", "CT": "Connecticut", "DE": "Delaware", "DC": "District of Columbia",
        "FL": "Florida", "GA": "Georgia", "HI": "Hawaii", "ID": "Idaho", "IL": "Illinois",
        "IN": "Indiana", "IA": "Iowa", "KS": "Kansas", "KY": "Kentucky", "LA": "Louisiana",
        "ME": "Maine", "MD": "Maryland", "MA": "Massachusetts", "MI": "Michigan", "MN": "Minnesota",
        "MS": "Mississippi", "MO": "Missouri", "MT": "Montana", "NE": "Nebraska", "NV": "Nevada",
        "NH": "New Hampshire", "NJ": "New Jersey", "NM": "New Mexico", "NY": "New York",
        "NC": "North Carolina", "ND": "North Dakota", "OH": "Ohio", "OK": "Oklahoma", "OR": "Oregon",
        "PA": "Pennsylvania", "RI": "Rhode Island", "SC": "South Carolina", "SD": "South Dakota",
        "TN": "Tennessee", "TX": "Texas", "UT": "Utah", "VT": "Vermont", "VA": "Virginia",
        "WA": "Washington", "WV": "West Virginia", "WI": "Wisconsin", "WY": "Wyoming",
        "PR": "Puerto Rico"
    ]

    static let fips: [String: Int] = [
        "AL": 1, "AK": 2, "AZ": 4, "AR": 5, "CA": 6, "CO": 8, "CT": 9, "DE": 10, "DC": 11, "FL": 12,
        "GA": 13, "HI": 15, "ID": 16, "IL": 17, "IN": 18, "IA": 19, "KS": 20, "KY": 21, "LA": 22,
        "ME": 23, "MD": 24, "MA": 25, "MI": 26, "MN": 27, "MS": 28, "MO": 29, "MT": 30, "NE": 31,
        "NV": 32, "NH": 33, "NJ": 34, "NM": 35, "NY": 36, "NC": 37, "ND": 38, "OH": 39, "OK": 40,
        "OR": 41, "PA": 42, "RI": 44, "SC": 45, "SD": 46, "TN": 47, "TX": 48, "UT": 49, "VT": 50,
        "VA": 51, "WA": 53, "WV": 54, "WI": 55, "WY": 56, "PR": 72
    ]

    static let traveler511: [String: String] = [
        "AL": "https://algotraffic.com", "AK": "https://511.alaska.gov", "AZ": "https://az511.gov",
        "AR": "https://idrivearkansas.com", "CA": "https://quickmap.dot.ca.gov", "CO": "https://maps.cotrip.org",
        "CT": "https://ctroads.org", "DE": "https://deldot.gov/map", "FL": "https://fl511.com",
        "GA": "https://511ga.org", "HI": "https://goakamai.org", "ID": "https://511.idaho.gov",
        "IL": "https://www.gettingaroundillinois.com", "IN": "https://511in.org", "IA": "https://511ia.org",
        "KS": "https://kandrive.gov", "KY": "https://goky.ky.gov", "LA": "https://511la.org",
        "ME": "https://newengland511.org", "MD": "https://chart.maryland.gov", "MA": "https://mass511.com",
        "MI": "https://mdotjboss.state.mi.us/MiDrive/map", "MN": "https://511mn.org", "MS": "https://mdottraffic.com",
        "MO": "https://traveler.modot.org/map", "MT": "https://www.511mt.net", "NE": "https://new.511.nebraska.gov",
        "NV": "https://nvroads.com", "NH": "https://newengland511.org", "NJ": "https://511nj.org",
        "NM": "https://nmroads.com", "NY": "https://511ny.org", "NC": "https://drivenc.gov",
        "ND": "https://travelfiles.dot.nd.gov", "OH": "https://ohgo.com", "OK": "https://oktraffic.org",
        "OR": "https://tripcheck.com", "PA": "https://511pa.com", "RI": "https://www.dot.ri.gov/travel",
        "SC": "https://511sc.org", "SD": "https://sd511.org", "TN": "https://smartway.tn.gov",
        "TX": "https://drivetexas.org", "UT": "https://udottraffic.utah.gov", "VT": "https://newengland511.org",
        "VA": "https://511.vdot.virginia.gov", "WA": "https://wsdot.com/travel/real-time/map",
        "WV": "https://wv511.org", "WI": "https://511wi.gov", "WY": "https://map.wyoroad.info",
        "DC": "https://ddot.dc.gov"
    ]
}
