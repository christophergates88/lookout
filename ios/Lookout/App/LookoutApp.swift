import SwiftUI
import CoreLocation

@main
struct LookoutApp: App {
    @State private var store = ProStore()
    @State private var location = LocationManager()
    @State private var model = LookoutModel()
    @State private var places = PlacesStore()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .environment(location)
                .environment(model)
                .environment(places)
                .preferredColorScheme(.dark)
                .tint(.lkAmber)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { AlertWatcher.schedule() }
        }
        .backgroundTask(.appRefresh(AppConfig.alertRefreshTaskID)) {
            await AlertWatcher.runCheck()
        }
    }
}

/// Onboarding the first time, then the tabs.
struct RootView: View {
    @AppStorage("didOnboard") private var didOnboard = false

    var body: some View {
        if didOnboard {
            MainTabs()
        } else {
            OnboardingView { didOnboard = true }
        }
    }
}

struct MainTabs: View {
    @Environment(LocationManager.self) private var location
    @Environment(LookoutModel.self) private var model
    @State private var tab = 0

    var body: some View {
        TabView(selection: $tab) {
            NowView()
                .tabItem { Label("Now", systemImage: "dot.radiowaves.left.and.right") }
                .tag(0)
            MapScreen()
                .tabItem { Label("Map", systemImage: "map") }
                .tag(1)
            CamerasView()
                .tabItem { Label("Cams", systemImage: "video") }
                .tag(2)
            ScannerView()
                .tabItem { Label("Scanner", systemImage: "antenna.radiowaves.left.and.right") }
                .tag(3)
            SettingsView()
                .tabItem { Label("More", systemImage: "ellipsis.circle") }
                .tag(4)
        }
        .onAppear { location.start() }
        .task(id: LocationKey(location.coordinate)) {
            await model.refreshIfNeeded(for: location.coordinate)
        }
        .task {
            // Keep things fresh while the app is open; refreshIfNeeded skips data under 10 minutes old.
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(120))
                await model.refreshIfNeeded(for: location.coordinate)
            }
        }
    }
}

/// Rounds a coordinate so small GPS jitter doesn't trigger reloads.
struct LocationKey: Hashable {
    let lat: Int
    let lon: Int
    init(_ c: CLLocationCoordinate2D?) {
        lat = Int(((c?.latitude ?? 0) * 50).rounded())
        lon = Int(((c?.longitude ?? 0) * 50).rounded())
    }
}
