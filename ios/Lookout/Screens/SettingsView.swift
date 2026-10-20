import SwiftUI
import StoreKit

struct SettingsView: View {
    @Environment(ProStore.self) private var store
    @AppStorage(AlertWatcher.enabledKey) private var backgroundAlerts = false
    @State private var showPaywall = false
    @State private var showManage = false
    @State private var notificationsDenied = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    if store.isPro {
                        Label("Lookout Pro is active", systemImage: "checkmark.seal.fill")
                            .foregroundStyle(Color.lkOK)
                        Button("Manage subscription") { showManage = true }
                    } else {
                        Button {
                            showPaywall = true
                        } label: {
                            HStack {
                                LogoMark(size: 40)
                                VStack(alignment: .leading) {
                                    Text("Try Lookout Pro free").bold().foregroundStyle(Color.lkText)
                                    Text("Drive mode, live radar, background alerts and more")
                                        .font(.caption).foregroundStyle(Color.lkMuted)
                                }
                                Spacer()
                                Pill(text: "PRO")
                            }
                        }
                    }
                    Button("Restore purchases") { Task { await store.restore() } }
                }
                .listRowBackground(Color.lkPanel)

                Section {
                    NavigationLink {
                        PlacesView()
                    } label: {
                        Label("Saved places", systemImage: "mappin.and.ellipse")
                    }
                } footer: {
                    Text("Home, work, school or anywhere else you want to keep an eye on.")
                }
                .listRowBackground(Color.lkPanel)

                Section {
                    Toggle(isOn: Binding(
                        get: { backgroundAlerts && store.isPro },
                        set: { on in setBackgroundAlerts(on) }
                    )) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Background warning alerts")
                            Text("Checks your last location and saved places about every 15 minutes or more, as iOS allows.")
                                .font(.caption).foregroundStyle(Color.lkMuted)
                        }
                    }
                    if notificationsDenied {
                        Text("Notifications are off for Lookout. Turn them on in Settings > Notifications > Lookout.")
                            .font(.caption).foregroundStyle(Color.lkBad)
                    }
                } header: {
                    Text("Alerts")
                } footer: {
                    Text("Lookout is a helper, not an official warning system. Keep Emergency Alerts turned on in your iPhone's Settings and follow your local officials.")
                }
                .listRowBackground(Color.lkPanel)

                Section("About") {
                    Link("Support", destination: AppConfig.supportURL)
                    Link("Privacy policy", destination: AppConfig.privacyURL)
                    Link("Terms of use", destination: AppConfig.termsURL)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Data sources").font(.subheadline.bold())
                        Text("Forecasts and alerts: National Weather Service. Radar: NOAA NEXRAD via Iowa Environmental Mesonet. Storm risk: NOAA Storm Prediction Center. Webcams provided by windy.com. Aircraft: adsb.lol (ODbL). Earthquakes: U.S. Geological Survey. Headlines: the GDELT Project. Scanner audio: Broadcastify and OpenMHz. Driver reports: Waze. Maps and traffic: Apple.")
                            .font(.caption).foregroundStyle(Color.lkMuted)
                    }
                    Text("Version \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0")")
                        .font(.caption).foregroundStyle(Color.lkMuted)
                }
                .listRowBackground(Color.lkPanel)

                #if DEBUG
                Section("Testing (Xcode builds only)") {
                    Toggle("Pretend I have Pro", isOn: Binding(get: { store.debugPro }, set: { store.setDebugPro($0) }))
                    StoreProductsCheck()
                }
                .listRowBackground(Color.lkPanel)
                #endif
            }
            .scrollContentBackground(.hidden)
            .background(Color.lkGround)
            .navigationTitle("More")
            .sheet(isPresented: $showPaywall) { PaywallView() }
            .manageSubscriptionsSheet(isPresented: $showManage)
            .alert("Lookout Pro", isPresented: Binding(get: { store.message != nil }, set: { if !$0 { store.message = nil } })) {
                Button("OK") { store.message = nil }
            } message: {
                Text(store.message ?? "")
            }
        }
    }

    private func setBackgroundAlerts(_ on: Bool) {
        guard store.isPro else { showPaywall = true; return }
        if on {
            Task {
                let granted = await AlertWatcher.requestPermission()
                notificationsDenied = !granted
                backgroundAlerts = granted
                if granted { AlertWatcher.schedule() }
            }
        } else {
            backgroundAlerts = false
            AlertWatcher.cancel()
        }
    }
}

#if DEBUG
/// Xcode builds only: shows which Lookout Pro products the App Store returns.
private struct StoreProductsCheck: View {
    @State private var result = "Checking App Store products…"
    var body: some View {
        Text(result).font(.caption).foregroundStyle(Color.lkMuted)
            .task {
                do {
                    let products = try await Product.products(for: AppConfig.proProductIDs)
                    let found = products.map { "\($0.id) \($0.displayPrice) intro:\($0.subscription?.introductoryOffer?.paymentMode.rawValue ?? "none")" }
                    let missing = AppConfig.proProductIDs.filter { id in !products.contains { $0.id == id } }
                    result = "Found: " + (found.isEmpty ? "none" : found.joined(separator: "; ")) + "\nMissing: " + (missing.isEmpty ? "none" : missing.joined(separator: ", "))
                } catch {
                    result = "Error: \(error)"
                }
            }
    }
}
#endif
