import SwiftUI
import SafariServices

/// Police, fire and EMS radio, live traffic reports, public-safety tools and local news for where you are.
struct ScannerView: View {
    @Environment(LookoutModel.self) private var model
    @Environment(LocationManager.self) private var location
    @State private var web: WebLink?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(area?.countyOrPlace.isEmpty == false ? area!.countyOrPlace : "Your area")
                            .font(.title3.bold()).foregroundStyle(Color.lkText)
                        Text("Live radio, reports and news for where you are. Links open right here in Lookout.")
                            .font(.subheadline).foregroundStyle(Color.lkMuted)
                    }
                    .padding(.vertical, 4)
                }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 0, leading: 4, bottom: 0, trailing: 4))

                Section {
                    if let state = area?.stateCode, let id = USStates.fips[state] {
                        row("antenna.radiowaves.left.and.right",
                            "Scanner feeds in \(area?.stateName ?? state)",
                            area?.county.map { "Live police, fire and EMS audio. Pick \($0)." } ?? "Live police, fire and EMS audio by county",
                            "https://www.broadcastify.com/listen/stid/\(id)")
                    } else {
                        row("antenna.radiowaves.left.and.right", "Scanner feeds", "Live police, fire and EMS audio",
                            "https://www.broadcastify.com/listen/")
                    }
                    row("waveform", "Recent dispatch calls", "Recorded radio calls you can replay, from OpenMHz",
                        "https://openmhz.com/systems")
                    if let q = searchPlace {
                        row("magnifyingglass", "Find more scanner feeds", q, google(q + " police scanner live"))
                    }
                } header: {
                    Text("Police, fire and EMS radio")
                } footer: {
                    Text("Scanner audio comes from volunteer feeds on Broadcastify and OpenMHz. Some counties have no public feed.")
                }
                .listRowBackground(Color.lkPanel)

                Section {
                    if let c = location.coordinate {
                        row("car.fill", "Crashes, police and hazards",
                            "Reported by drivers on Waze, around you",
                            String(format: "https://www.waze.com/live-map/directions?latlng=%.5f%%2C%.5f", c.latitude, c.longitude))
                    }
                    if let state = area?.stateCode, let dot = USStates.traveler511[state] {
                        row("road.lanes", "\(state) 511 road conditions",
                            "Official state road cameras, closures and incidents", dot)
                    }
                } header: {
                    Text("Live traffic reports")
                }
                .listRowBackground(Color.lkPanel)

                Section {
                    row("shield.lefthalf.filled", "Citizen", "Real-time 911 incident reports, in larger metro areas",
                        "https://citizen.com/explore")
                    if let place = area?.place, !place.isEmpty {
                        row("map", "Recent crime map", "Where local agencies share reports",
                            "https://www.crimemapping.com/map/location/" + (place.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? ""))
                    }
                    if let name = area?.stateName {
                        row("bolt.fill", "Power outages", "By county across \(name)",
                            "https://poweroutage.us/area/state/" + name.lowercased().replacingOccurrences(of: " ", with: "-"))
                    }
                    row("flame.fill", "Wildfires", "Active incidents from InciWeb", "https://inciweb.wildfire.gov/")
                    if let county = area?.countyOrPlace, !county.isEmpty {
                        row("megaphone.fill", "Emergency management", county, google(county + " emergency management alerts"))
                    }
                } header: {
                    Text("Incidents and public safety")
                }
                .listRowBackground(Color.lkPanel)

                Section {
                    NavigationLink {
                        NewsView()
                    } label: {
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Local news").foregroundStyle(Color.lkText)
                                Text(newsSubtitle).font(.caption).foregroundStyle(Color.lkMuted)
                            }
                        } icon: {
                            Image(systemName: "newspaper.fill").foregroundStyle(Color.lkAmber)
                        }
                    }
                } header: {
                    Text("News")
                }
                .listRowBackground(Color.lkPanel)
            }
            .scrollContentBackground(.hidden)
            .background(Color.lkGround)
            .navigationTitle("Scanner")
            .refreshable { await model.refresh(for: location.coordinate) }
            .sheet(item: $web) { SafariView(url: $0.url).ignoresSafeArea() }
        }
    }

    private var area: LocalArea? { model.area }

    private var searchPlace: String? {
        let s = area?.countyOrPlace ?? ""
        return s.isEmpty ? nil : s
    }

    private var newsSubtitle: String {
        if !model.news.isEmpty { return "\(model.news.count) stories from the last 3 days" }
        return area?.place.isEmpty == false ? "Headlines for \(area!.place)" : "Headlines for your area"
    }

    private func google(_ q: String) -> String {
        "https://www.google.com/search?q=" + (q.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")
    }

    private func row(_ symbol: String, _ title: String, _ subtitle: String, _ link: String) -> some View {
        Button {
            if let u = URL(string: link) { web = WebLink(url: u) }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: symbol)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Color.lkAmber)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).foregroundStyle(Color.lkText)
                    Text(subtitle).font(.caption).foregroundStyle(Color.lkMuted).lineLimit(2)
                }
                Spacer(minLength: 8)
                Image(systemName: "arrow.up.right").font(.caption.bold()).foregroundStyle(Color.lkMuted)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// A link to open in the in-app browser.
struct WebLink: Identifiable {
    let url: URL
    var id: String { url.absoluteString }
}

/// Safari, inside Lookout.
struct SafariView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        let config = SFSafariViewController.Configuration()
        config.entersReaderIfAvailable = false
        let vc = SFSafariViewController(url: url, configuration: config)
        vc.preferredControlTintColor = UIColor(red: 245 / 255, green: 182 / 255, blue: 63 / 255, alpha: 1)
        vc.preferredBarTintColor = UIColor(red: 11 / 255, green: 15 / 255, blue: 22 / 255, alpha: 1)
        vc.dismissButtonStyle = .done
        return vc
    }

    func updateUIViewController(_ vc: SFSafariViewController, context: Context) {}
}
