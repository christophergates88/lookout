import SwiftUI
import CoreLocation

/// Places to watch besides where you are: alerts and temperature for each.
struct PlacesView: View {
    @Environment(PlacesStore.self) private var places
    @Environment(ProStore.self) private var store
    @Environment(LocationManager.self) private var location
    @State private var showAdd = false
    @State private var showPaywall = false

    private var limit: Int { store.isPro ? AppConfig.proSavedPlaces : AppConfig.freeSavedPlaces }

    var body: some View {
        NavigationStack {
            List {
                if places.places.isEmpty {
                    Section {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Watch the places that matter").font(.headline).foregroundStyle(Color.lkText)
                            Text("Add home, work, daycare or anywhere else to see their alerts and conditions at a glance.")
                                .font(.subheadline).foregroundStyle(Color.lkMuted)
                        }
                        .padding(.vertical, 6)
                    }
                    .listRowBackground(Color.lkPanel)
                }
                Section {
                    ForEach(places.places) { place in
                        PlaceRow(place: place)
                    }
                    .onDelete { places.remove(at: $0) }
                    .onMove { places.move(from: $0, to: $1) }
                } footer: {
                    if store.isPro {
                        Text("Lookout Pro checks these for new warnings in the background when it's turned on in More.")
                    } else {
                        Text("Free: \(AppConfig.freeSavedPlaces) place. Lookout Pro: up to \(AppConfig.proSavedPlaces), with background warning alerts.")
                    }
                }
                .listRowBackground(Color.lkPanel)
            }
            .scrollContentBackground(.hidden)
            .background(Color.lkGround)
            .navigationTitle("Places")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        if places.places.count < limit { showAdd = true } else { showPaywall = !store.isPro }
                    } label: { Image(systemName: "plus") }
                    .accessibilityLabel("Add a place")
                }
                if !places.places.isEmpty {
                    ToolbarItem(placement: .topBarLeading) { EditButton() }
                }
            }
            .sheet(isPresented: $showAdd) { AddPlaceView() }
            .sheet(isPresented: $showPaywall) { PaywallView() }
        }
    }
}

private struct PlaceRow: View {
    let place: SavedPlace
    @State private var temp: Int?
    @State private var alerts: [NWSAlert] = []
    @State private var openAlert: NWSAlert?
    @State private var loaded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(place.name).font(.headline).foregroundStyle(Color.lkText)
                Spacer()
                if let temp { Text("\(temp)°").font(.title3.bold()).foregroundStyle(Color.lkText) }
                else if !loaded { ProgressView() }
            }
            if alerts.isEmpty {
                Text(loaded ? "No active alerts" : " ").font(.caption).foregroundStyle(Color.lkOK)
            } else {
                ForEach(alerts) { a in
                    Button { openAlert = a } label: {
                        Label(a.event, systemImage: "exclamationmark.triangle.fill")
                            .font(.caption.bold())
                            .foregroundStyle(a.isSerious ? Color.lkBad : Color.lkAmber)
                    }
                    .buttonStyle(.borderless)
                }
            }
        }
        .padding(.vertical, 4)
        .task(id: place.id) { await load() }
        .sheet(item: $openAlert) { AlertDetailView(alert: $0) }
    }

    private func load() async {
        async let fc = attempt { try await NWS.forecast(at: place.coordinate) }
        async let al = attempt { try await NWS.alerts(at: place.coordinate) }
        let (f, a) = await (fc, al)
        if case .success(let forecast) = f { temp = forecast.hourly.first?.tempF }
        if case .success(let list) = a { alerts = list }
        loaded = true
    }
}

private struct AddPlaceView: View {
    @Environment(PlacesStore.self) private var places
    @Environment(LocationManager.self) private var location
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var address = ""
    @State private var searching = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Name") {
                    TextField("Home, Work, Daycare…", text: $name)
                }
                Section {
                    TextField("Street address or town", text: $address)
                        .textContentType(.fullStreetAddress)
                    Button {
                        Task { await addFromAddress() }
                    } label: {
                        if searching { ProgressView() } else { Text("Find and add") }
                    }
                    .disabled(address.trimmingCharacters(in: .whitespaces).isEmpty || searching)
                } header: {
                    Text("Address")
                }
                if let here = location.coordinate {
                    Section {
                        Button("Use where I am now") { add(name.isEmpty ? "Saved spot" : name, here) }
                    }
                }
                if let error {
                    Text(error).foregroundStyle(Color.lkBad)
                }
            }
            .navigationTitle("Add a place")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
    }

    private func addFromAddress() async {
        searching = true
        defer { searching = false }
        do {
            if let found = try await PlaceSearch.find(address) {
                add(name.isEmpty ? found.name : name, found.coordinate)
            } else {
                error = "Couldn't find that address."
            }
        } catch {
            self.error = "Couldn't find that address. Check the spelling and try again."
        }
    }

    private func add(_ n: String, _ c: CLLocationCoordinate2D) {
        places.add(SavedPlace(name: n, latitude: c.latitude, longitude: c.longitude))
        dismiss()
    }
}
