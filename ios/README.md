# Lookout for iPhone

Weather, warnings, radar and live public cameras for exactly where you are. Native SwiftUI app (iOS 17+, iPhone, portrait).
The web version of Lookout (the `index.html` one folder up) is separate and unchanged.

**Business model:** free app with a **Lookout Pro** subscription: **$2.99 a month** or **$19.99 a year**, with a **1-week free trial**.

| | Free | Lookout Pro |
| --- | --- | --- |
| Current conditions, 12-hour and 7-day forecast (NWS) | ✓ | ✓ |
| Active NWS alerts for your spot, warning areas on the map | ✓ | ✓ |
| Map with Apple traffic | ✓ | ✓ |
| Nearest public cameras | 3 | All nearby (up to 50) |
| Saved places with alerts and temperature | 1 | 20 |
| Live NEXRAD radar on the map | | ✓ |
| Drive mode: big screen, speed and heading, alerts read aloud, "camera ahead" | | ✓ |
| Background warning notifications (your location and saved places) | | ✓ |
| Today's storm risk (Storm Prediction Center) | | ✓ |

Running costs: none. Every data source is free: National Weather Service, NOAA Storm Prediction Center, NOAA radar via the
Iowa Environmental Mesonet, Apple Maps, and Windy's free webcam tier (which requires a link and credit to windy.com on
every camera, which the app does). There is no server.

---

## 1. Get the project onto the Mac (5 minutes)

1. On the Mac, open **Terminal**: press **⌘ Space**, type `Terminal`, press **Return**.
2. Paste this line and press **Return**:
   `cd ~/Downloads && git clone https://github.com/christophergates88/lookout.git lookout-ios-project`
3. Open **Finder** → **Downloads** → **lookout-ios-project** → **ios**. You'll see **Lookout.xcodeproj**.
   (Later, to get updates: in Terminal, `cd ~/Downloads/lookout-ios-project && git pull`.)

## 2. Add the camera key (2 minutes)

1. Go to **api.windy.com/keys**, sign in, click **Create API key**, choose **Webcams API**, and name it "Lookout iOS app".
   Use a new key, not the one in your phone's web app.
2. In Xcode (next step), open `Lookout/App/AppConfig.swift` and paste the key between the quotes on the `windyKey` line.
   Leave it empty and the camera features hide themselves.

## 3. Run it on your iPhone (10 minutes)

1. Double-click **Lookout.xcodeproj**. Xcode opens. If it shows a yellow **"Update to recommended settings"** notice,
   ignore it (don't click Perform Changes). Those new settings change how the code is checked and can cause errors.
2. In the left sidebar, click the blue **Lookout** icon at the top, then **Lookout** under TARGETS, then the
   **Signing & Capabilities** tab. **Team** should already show your developer account. If it says the bundle ID is
   unavailable, change `com.christophergates.lookout` to something unique like `com.christophergates.lookoutwx`, and
   also change the two product IDs in `AppConfig.swift` to match.
3. Plug in your iPhone, choose it in the device menu at the top middle of Xcode, and press **▶ Run**.
4. To try Pro features without paying: in the app, tap **More**, scroll down, turn on **Pretend I have Pro**
   (only exists in builds from Xcode, never in the App Store version).

If Xcode shows a red error, double-click **Build Lookout.command** in the `ios` folder. It writes `build.log`;
send that file (or the red error text) to Claude. These are usually one-line fixes.

## 4. Create the app and subscriptions in App Store Connect (20 minutes)

1. **appstoreconnect.apple.com** → **Apps** → **+** → **New App**.
   - Platform iOS, Name: see "App name" below, Language English (U.S.), Bundle ID `com.christophergates.lookout`, SKU `lookout-ios`.
2. In the new app: **Monetization → Subscriptions** → **Create** a subscription group named **Lookout Pro**.
3. Inside the group, **Create** two subscriptions:
   - Reference name **Pro Monthly**, Product ID `com.christophergates.lookout.pro.monthly`, duration **1 month**, price **$2.99**.
   - Reference name **Pro Yearly**, Product ID `com.christophergates.lookout.pro.yearly`, duration **1 year**, price **$19.99**.
   - For each: add a display name ("Lookout Pro Monthly" / "Lookout Pro Yearly"), a description ("Radar, Drive mode, background alerts, all cameras"),
     and a review screenshot of the Pro screen.
   - For each: **Introductory Offers → +** → **Free**, **1 week**, all countries.
4. In the subscription group, add a group display name "Lookout Pro".
5. To test buying without paying: in Xcode **File → New → File from Template → StoreKit Configuration File**, check
   **Sync this file with an app in App Store Connect**, then **Product → Scheme → Edit Scheme → Run → Options → StoreKit Configuration**, pick it.

## 5. Submit

1. In Xcode set the device to **Any iOS Device (arm64)**, then **Product → Archive**.
2. In the Organizer window: **Distribute App → App Store Connect → Upload**.
3. In App Store Connect fill in (copy from `app-store-listing.md`): description, keywords, support URL, privacy URL,
   screenshots (6.9-inch: run on the iPhone 16 Pro Max simulator or take them on your phone), category **Weather**,
   age rating 4+.
4. **App Privacy:** Data type **Precise Location**, used for **App Functionality**, **not linked** to the user, **not used for tracking**.
5. Attach both subscriptions to the version (**In-App Purchases and Subscriptions** section), then **Add for Review → Submit**.
6. In **App Review Information → Notes** paste: *"Lookout Pro can be tested with the sandbox account. Background
   alerts use BGAppRefreshTask to check NWS alerts for the user's last location and saved places and post local
   notifications. Location is When In Use only."*

## App name

"Lookout" may already be taken on the App Store, and Lookout, Inc. (the phone-security company) uses the name.
App Store Connect tells you immediately if a name is taken. Good options that keep the brand:
**"Lookout: Storm & Road Cams"**, **"Lookout Weather & Cams"**, or a fresh name like **"Watchpost"**.
The name under the icon on the phone (`CFBundleDisplayName`) can stay "Lookout".

## Files

- `Lookout/App`: app entry, settings you may change (`AppConfig.swift`), location, data model, Pro subscription, background alerts, colors and logo
- `Lookout/Data`: National Weather Service, Windy cameras, storm risk, saved places, map geometry
- `Lookout/Screens`: Now, Map, Cameras, Places, More, Drive mode, Pro paywall, welcome screens
- `Support/Info.plist`: background-refresh settings Xcode can't generate
- `Lookout/PrivacyInfo.xcprivacy`: Apple's required privacy manifest
- Privacy and support pages: `../privacy.html` and `../support.html`, served by GitHub Pages at
  christophergates88.github.io/lookout/privacy.html and /support.html
