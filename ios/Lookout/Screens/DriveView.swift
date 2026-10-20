import SwiftUI
import AVFoundation
import CoreLocation

/// Lookout Pro: a big, glanceable screen for the car. Keeps the screen on, reads new alerts aloud,
/// and shows the nearest camera ahead in the direction you're heading.
struct DriveView: View {
    @Environment(LookoutModel.self) private var model
    @Environment(LocationManager.self) private var location
    @Environment(\.dismiss) private var dismiss
    @AppStorage("driveSpeak") private var speakAlerts = true
    @State private var spokenIDs: Set<String> = []
    @State private var speaker = AlertSpeaker()
    @State private var openCamera: Camera?

    var body: some View {
        VStack(spacing: 16) {
            topBar
            alertBanner
            HStack(alignment: .top, spacing: 16) {
                speedBlock
                weatherBlock
            }
            cameraAhead
            Spacer(minLength: 0)
            Text("Glance only. Keep your eyes on the road.")
                .font(.caption).foregroundStyle(Color.lkMuted)
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
        .onAppear {
            UIApplication.shared.isIdleTimerDisabled = true
            location.beginTracking()
            // Don't announce alerts that were already showing when Drive mode opened.
            spokenIDs = Set(model.alerts.map(\.id))
        }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
            location.endTracking()
            speaker.stop()
        }
        .onChange(of: model.alerts.map(\.id)) { _, _ in announceNewAlerts() }
        .sheet(item: $openCamera) { CameraDetailView(camera: $0) }
        .statusBarHidden()
    }

    // MARK: Pieces

    private var topBar: some View {
        HStack {
            Text(model.place.isEmpty ? "Drive mode" : model.place)
                .font(.title3.bold()).foregroundStyle(Color.lkText).lineLimit(1)
            Spacer()
            Button {
                speakAlerts.toggle()
            } label: {
                Image(systemName: speakAlerts ? "speaker.wave.2.fill" : "speaker.slash.fill")
                    .font(.title2).frame(width: 52, height: 52)
                    .background(Color.lkPanel, in: Circle())
            }
            .accessibilityLabel(speakAlerts ? "Mute spoken alerts" : "Speak alerts")
            Button { dismiss() } label: {
                Image(systemName: "xmark").font(.title2.bold()).frame(width: 52, height: 52)
                    .background(Color.lkPanel, in: Circle())
            }
            .accessibilityLabel("Close drive mode")
        }
        .foregroundStyle(Color.lkText)
    }

    @ViewBuilder private var alertBanner: some View {
        if let top = model.alerts.first {
            VStack(alignment: .leading, spacing: 4) {
                Text(top.event.uppercased())
                    .font(.system(size: 30, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                    .minimumScaleFactor(0.6)
                    .lineLimit(2)
                if model.alerts.count > 1 {
                    Text("+\(model.alerts.count - 1) more alert\(model.alerts.count > 2 ? "s" : "")")
                        .font(.headline).foregroundStyle(.white.opacity(0.85))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(18)
            .background(top.isSerious ? Color.lkBad : Color.lkAmber.opacity(0.8),
                        in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        } else {
            Label("No weather alerts here", systemImage: "checkmark.shield.fill")
                .font(.title3.bold())
                .foregroundStyle(Color.lkOK)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(18)
                .background(Color.lkPanel, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
    }

    private var speedBlock: some View {
        let mph = max(0, (location.location?.speed ?? 0) * 2.23694)
        let course = location.location?.course ?? -1
        return VStack(spacing: 2) {
            Text("\(Int(mph.rounded()))")
                .font(.system(size: 76, weight: .bold, design: .rounded))
                .foregroundStyle(Color.lkText)
                .monospacedDigit()
            Text("MPH").font(.headline).foregroundStyle(Color.lkMuted)
            Text(course >= 0 ? "Heading " + Units.compass(course) : " ")
                .font(.headline).foregroundStyle(Color.lkAmber)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(Color.lkPanel, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private var weatherBlock: some View {
        VStack(spacing: 6) {
            if let now = model.now {
                Image(systemName: now.symbol).symbolRenderingMode(.multicolor).font(.system(size: 44))
                Text(now.tempF.map { "\($0)°" } ?? "--")
                    .font(.system(size: 48, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.lkText)
                Text(nextRain).font(.subheadline.bold()).foregroundStyle(Color.lkInfo)
                    .multilineTextAlignment(.center)
            } else {
                ProgressView()
            }
        }
        .frame(maxWidth: .infinity, minHeight: 170)
        .padding(.vertical, 8)
        .background(Color.lkPanel, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    /// "Rain likely by 4 PM" from the hourly forecast.
    private var nextRain: String {
        for p in model.hourly.prefix(6) {
            if let chance = p.rainChance, chance >= 50, let t = p.start {
                return "Rain likely by " + t.formatted(.dateTime.hour())
            }
        }
        return "Dry next 6 hrs"
    }

    @ViewBuilder private var cameraAhead: some View {
        if let cam = aheadCamera {
            Button { openCamera = cam } label: {
                HStack(spacing: 14) {
                    AsyncImage(url: cam.imageURL) { phase in
                        if case .success(let img) = phase { img.resizable().scaledToFill() } else { Color.lkPanel2 }
                    }
                    .frame(width: 150, height: 96)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    VStack(alignment: .leading, spacing: 4) {
                        Text("CAMERA AHEAD").font(.caption.bold()).tracking(1).foregroundStyle(Color.lkAmber)
                        Text(cam.title).font(.headline).foregroundStyle(Color.lkText).lineLimit(2)
                        Text(Units.miles(currentKm(cam))).font(.subheadline).foregroundStyle(Color.lkMuted)
                    }
                    Spacer()
                }
                .padding(12)
                .background(Color.lkPanel, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            }
            .buttonStyle(.plain)
        }
    }

    /// Nearest camera within 40 degrees of the direction of travel and under ~30 miles.
    /// When stopped (no heading), simply the nearest camera.
    private var aheadCamera: Camera? {
        guard let here = location.coordinate else { return model.cameras.first }
        let course = location.location?.course ?? -1
        let candidates = model.cameras.filter { Geo.km(here, $0.coordinate) < 48 }
        if course < 0 { return candidates.min { Geo.km(here, $0.coordinate) < Geo.km(here, $1.coordinate) } }
        return candidates
            .filter { Geo.angleBetween(Geo.bearing(here, $0.coordinate), course) <= 40 }
            .min { Geo.km(here, $0.coordinate) < Geo.km(here, $1.coordinate) }
    }

    private func currentKm(_ cam: Camera) -> Double {
        guard let here = location.coordinate else { return cam.km }
        return Geo.km(here, cam.coordinate)
    }

    private func announceNewAlerts() {
        let fresh = model.alerts.filter { !spokenIDs.contains($0.id) }
        guard !fresh.isEmpty else { return }
        fresh.forEach { spokenIDs.insert($0.id) }
        Haptics.warn()
        guard speakAlerts else { return }
        let names = fresh.map(\.event).joined(separator: ". ")
        speaker.say("Lookout. New alert: \(names).")
    }
}

/// Speaks over the car audio, ducking music.
@MainActor
final class AlertSpeaker {
    private let synth = AVSpeechSynthesizer()

    func say(_ text: String) {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .voicePrompt, options: [.duckOthers, .interruptSpokenAudioAndMixWithOthers])
        try? session.setActive(true)
        let u = AVSpeechUtterance(string: text)
        u.rate = AVSpeechUtteranceDefaultSpeechRate
        synth.speak(u)
    }

    func stop() {
        synth.stopSpeaking(at: .immediate)
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}
