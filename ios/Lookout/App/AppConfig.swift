import Foundation

/// Everything you may need to change before release lives here.
enum AppConfig {
    /// Shown in the app. The App Store name can be different (it must be unique on the store).
    static let appName = "Lookout"

    // MARK: Lookout Pro (auto-renewable subscriptions in one group)

    /// Must match the subscription product IDs you create in App Store Connect.
    static let proMonthlyID = "com.christophergates.lookout.pro.monthly"
    static let proYearlyID = "com.christophergates.lookout.pro.yearly"
    static let proProductIDs = [proMonthlyID, proYearlyID]

    /// Free tier limits. Pro removes them.
    static let freeCameraCount = 3
    static let freeSavedPlaces = 1
    static let proSavedPlaces = 20

    // MARK: Data sources

    /// The National Weather Service asks every app to identify itself with a contact.
    static let nwsUserAgent = "LookoutApp/1.0 (christophergates88.github.io/lookout/support.html)"

    /// Windy Webcams API key for the app (free tier). Make a NEW key just for the app at
    /// api.windy.com/keys ("Webcams API") and paste it between the quotes. Leave it empty and the
    /// camera features hide themselves.
    static let windyKey = ""
    /// How far to look for cameras, in kilometres (Windy allows up to 250).
    static let cameraRadiusKm = 120

    /// NEXRAD radar tiles (NOAA data served by the Iowa Environmental Mesonet).
    static let radarTileTemplate = "https://mesonet.agron.iastate.edu/cache/tile.py/1.0.0/nexrad-n0q-900913/{z}/{x}/{y}.png"

    /// Storm Prediction Center day 1 outlook (categorical), GeoJSON.
    static let spcDay1URL = URL(string: "https://www.spc.noaa.gov/products/outlook/day1otlk_cat.nolyr.geojson")!

    // MARK: Background alerts

    /// Must match BGTaskSchedulerPermittedIdentifiers in Support/Info.plist.
    static let alertRefreshTaskID = "com.christophergates.lookout.alerts"

    // MARK: Links

    static let supportURL = URL(string: "https://christophergates88.github.io/lookout/support.html")!
    /// Apple requires this to be a working public page before review.
    static let privacyURL = URL(string: "https://christophergates88.github.io/lookout/privacy.html")!
    /// Apple's standard end-user license agreement, shown on the paywall.
    static let termsURL = URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!
}
