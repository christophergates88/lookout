# Roomprint for iPhone (App Store shell)

A Capacitor app whose WebView loads the live Roomprint site, so customers get the same walkthrough
with a native app icon, splash screen and camera access, and updates never need a resubmission.

## Build on the Mac (one-time toolchain, then two commands)
1. Install Xcode from the Mac App Store and open it once to accept the license.
2. Install Node (https://nodejs.org, LTS) if `node -v` fails in Terminal.
3. In Terminal:
   ```
   git clone https://github.com/christophergates88/roomprint-app.git ~/Roomprint
   cd ~/Roomprint/ios-shell
   npm install
   npx cap add ios --packagemanager SPM
   npx cap sync ios
   npx cap open ios
   ```
4. In Xcode: select the "App" target → Signing & Capabilities → Team: your Apple ID (Apple Developer
   Program membership required for the App Store). Bundle identifier `com.roomprint.app`.
5. Add the camera usage text: App → Info → add `NSCameraUsageDescription` = "Roomprint uses the camera
   to record each room of your home for your contents record." and `NSPhotoLibraryUsageDescription` =
   "Roomprint lets you add photos and videos from your library to your record."
6. Plug in the iPhone, pick it as the run target, press Run to test. Then Product → Archive →
   Distribute App → App Store Connect → Upload.

Before step 3, set `server.url` in `capacitor.config.json` to the live Worker URL.

## App Store Connect listing
- Name: Roomprint — Home Inventory Record
- Subtitle: Walk your home, get a claim-ready list
- Category: Utilities (secondary: Lifestyle)
- Age rating: 4+
- Privacy policy URL: https://<worker>/privacy  ·  Support URL: https://<worker>/
- Description: see `listing.md`
- Screenshots: 6.7" (1290×2796) and 6.1" (1179×2556), generated from the live app.
- Review notes: "Roomprint is a service: homeowners record their home with the phone camera inside the
  app, and a human-reviewed contents record is delivered by email. Payment for the record happens on the
  web; nothing is sold inside the app."
