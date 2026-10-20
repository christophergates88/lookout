import SwiftUI
import StoreKit

/// Apple's subscription sheet with Lookout's pitch on top. Shows prices, trial, terms and restore.
struct PaywallView: View {
    @Environment(ProStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        SubscriptionStoreView(productIDs: AppConfig.proProductIDs) {
            VStack(spacing: 8) {
                LogoMark(size: 48)
                Text("Lookout Pro")
                    .font(.largeTitle.bold())
                    .foregroundStyle(Color.lkText)
                Text("See what's coming before you're in it.")
                    .font(.headline)
                    .foregroundStyle(Color.lkMuted)
                VStack(alignment: .leading, spacing: 8) {
                    ProFeatureRow(symbol: "steeringwheel", title: "Drive mode", text: "Big, glanceable screen with alerts read aloud and cameras ahead on your route.")
                    ProFeatureRow(symbol: "cloud.rain", title: "Live radar", text: "NEXRAD radar over your map, with warning areas drawn on top.")
                    ProFeatureRow(symbol: "bell.badge", title: "Background alerts", text: "A notification when a new warning covers you or a saved place.")
                    ProFeatureRow(symbol: "mappin.and.ellipse", title: "Watch \(AppConfig.proSavedPlaces) places", text: "Home, work, daycare, the lake: alerts and conditions at a glance.")
                    ProFeatureRow(symbol: "video", title: "Every nearby camera", text: "All public cameras around you, closest first, not just the nearest \(AppConfig.freeCameraCount).")
                    ProFeatureRow(symbol: "exclamationmark.triangle", title: "Storm risk", text: "Today's Storm Prediction Center severe-weather risk where you are.")
                }
                .padding(.top, 4)
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
        }
        .modifier(CompactPlanPicker())
        .storeButton(.visible, for: .restorePurchases)
        .subscriptionStorePolicyDestination(url: AppConfig.termsURL, for: .termsOfService)
        .subscriptionStorePolicyDestination(url: AppConfig.privacyURL, for: .privacyPolicy)
        .onInAppPurchaseCompletion { _, _ in
            await store.refreshEntitlement()
        }
        .onChange(of: store.isPro) { _, isPro in
            if isPro { dismiss() }
        }
        .background(Color.lkGround)
    }
}

/// Shows the monthly and yearly plans side by side so both are visible without scrolling.
private struct CompactPlanPicker: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 18.0, *) {
            content.subscriptionStoreControlStyle(.compactPicker)
        } else {
            content.subscriptionStoreControlStyle(.picker)
        }
    }
}

private struct ProFeatureRow: View {
    let symbol: String
    let title: String
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .font(.title3)
                .foregroundStyle(Color.lkAmber)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.bold()).foregroundStyle(Color.lkText)
                Text(text).font(.footnote).foregroundStyle(Color.lkMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// Wraps a Pro feature: shows it to Pro users, otherwise a short pitch and an unlock button.
struct ProLocked<Content: View>: View {
    @Environment(ProStore.self) private var store
    let title: String
    let pitch: String
    let symbol: String
    @ViewBuilder var content: () -> Content
    @State private var showPaywall = false

    var body: some View {
        if store.isPro {
            content()
        } else {
            VStack(spacing: 14) {
                Image(systemName: symbol)
                    .font(.system(size: 40))
                    .foregroundStyle(Color.lkAmber)
                Text(title).font(.title3.bold()).foregroundStyle(Color.lkText)
                Text(pitch)
                    .font(.subheadline)
                    .foregroundStyle(Color.lkMuted)
                    .multilineTextAlignment(.center)
                Button {
                    showPaywall = true
                } label: {
                    Text("Try Lookout Pro free").bold().frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .foregroundStyle(Color.lkAmberInk)
                .controlSize(.large)
            }
            .padding(24)
            .panel()
            .sheet(isPresented: $showPaywall) { PaywallView() }
        }
    }
}

/// A small "PRO" button that opens the paywall.
struct ProBadgeButton: View {
    @State private var showPaywall = false

    var body: some View {
        Button { showPaywall = true } label: { Pill(text: "PRO") }
            .sheet(isPresented: $showPaywall) { PaywallView() }
    }
}
