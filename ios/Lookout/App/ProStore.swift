import Foundation
import StoreKit

/// Lookout Pro: auto-renewable subscription (monthly or yearly) using StoreKit 2. No server needed.
@MainActor
@Observable
final class ProStore {
    private(set) var isPro = false
    var message: String?

    /// Lets you try Pro features in Xcode builds without buying. The switch for it only exists in
    /// debug builds (see Settings), so App Store builds always leave this off.
    private(set) var debugPro = false

    func setDebugPro(_ on: Bool) {
        debugPro = on
        Task { await refreshEntitlement() }
    }

    @ObservationIgnored private var updatesTask: Task<Void, Never>?

    /// Background tasks read this instead of StoreKit.
    nonisolated static let cachedProKey = "isProCached"

    init() {
        isPro = UserDefaults.standard.bool(forKey: Self.cachedProKey)
        updatesTask = Task { [weak self] in
            for await result in StoreKit.Transaction.updates {
                if case .verified(let transaction) = result {
                    await transaction.finish()
                    await self?.refreshEntitlement()
                }
            }
        }
        Task { [weak self] in await self?.refreshEntitlement() }
    }

    func refreshEntitlement() async {
        var active = false
        for await result in StoreKit.Transaction.currentEntitlements {
            guard case .verified(let t) = result,
                  AppConfig.proProductIDs.contains(t.productID),
                  t.revocationDate == nil else { continue }
            if let exp = t.expirationDate, exp < Date() { continue }
            active = true
        }
        if debugPro { active = true }
        isPro = active
        UserDefaults.standard.set(active, forKey: Self.cachedProKey)
    }

    func restore() async {
        do {
            try await AppStore.sync()
        } catch {
            message = "Couldn't reach the App Store. Check your connection and try again."
        }
        await refreshEntitlement()
        if !isPro && message == nil {
            message = "No active Lookout Pro subscription was found for this Apple ID."
        }
    }
}
