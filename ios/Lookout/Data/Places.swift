import Foundation
import CoreLocation

/// A place the user wants to watch (home, work, daycare, the lake house...).
struct SavedPlace: Codable, Identifiable, Hashable, Sendable {
    var id = UUID()
    var name: String
    var latitude: Double
    var longitude: Double

    var coordinate: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: latitude, longitude: longitude) }
}

/// Saved places live on the phone only (UserDefaults).
@MainActor
@Observable
final class PlacesStore {
    private(set) var places: [SavedPlace] = []
    nonisolated private static let key = "savedPlaces.v1"

    init() { places = Self.load() }

    nonisolated static func load() -> [SavedPlace] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let list = try? JSONDecoder().decode([SavedPlace].self, from: data) else { return [] }
        return list
    }

    private func save() {
        if let data = try? JSONEncoder().encode(places) {
            UserDefaults.standard.set(data, forKey: Self.key)
        }
    }

    func add(_ place: SavedPlace) { places.append(place); save() }

    func remove(at offsets: IndexSet) {
        for i in offsets.sorted(by: >) where places.indices.contains(i) { places.remove(at: i) }
        save()
    }

    func move(from source: IndexSet, to destination: Int) {
        places.move(fromOffsets: source, toOffset: destination)
        save()
    }

    func rename(_ id: UUID, to name: String) {
        guard let i = places.firstIndex(where: { $0.id == id }) else { return }
        places[i].name = name
        save()
    }
}

/// Turns typed text ("123 Main St, Eatonton GA") into a coordinate.
enum PlaceSearch {
    static func find(_ text: String) async throws -> (name: String, coordinate: CLLocationCoordinate2D)? {
        let marks = try await CLGeocoder().geocodeAddressString(text)
        guard let m = marks.first, let loc = m.location else { return nil }
        let name = [m.name, m.locality, m.administrativeArea].compactMap { $0 }.first ?? text
        return (name, loc.coordinate)
    }
}
