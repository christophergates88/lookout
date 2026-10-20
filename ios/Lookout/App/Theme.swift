import SwiftUI
import UIKit

extension Color {
    /// Night-sky background and panels, matching the Lookout web app.
    static let lkGround = Color(red: 11 / 255, green: 15 / 255, blue: 22 / 255)
    static let lkPanel = Color(red: 20 / 255, green: 27 / 255, blue: 38 / 255)
    static let lkPanel2 = Color(red: 30 / 255, green: 40 / 255, blue: 54 / 255)
    static let lkLine = Color(red: 40 / 255, green: 50 / 255, blue: 63 / 255)
    static let lkText = Color(red: 234 / 255, green: 241 / 255, blue: 248 / 255)
    static let lkMuted = Color(red: 144 / 255, green: 160 / 255, blue: 178 / 255)
    /// Amber beacon accent.
    static let lkAmber = Color(red: 245 / 255, green: 182 / 255, blue: 63 / 255)
    static let lkAmberInk = Color(red: 26 / 255, green: 18 / 255, blue: 4 / 255)
    static let lkOK = Color(red: 67 / 255, green: 204 / 255, blue: 138 / 255)
    static let lkBad = Color(red: 255 / 255, green: 96 / 255, blue: 96 / 255)
    static let lkInfo = Color(red: 92 / 255, green: 179 / 255, blue: 255 / 255)
}

struct PanelStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.lkPanel, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(Color.lkLine, lineWidth: 1))
    }
}

extension View {
    func panel() -> some View { modifier(PanelStyle()) }
}

/// Small uppercase section label, e.g. "NEAREST CAMERAS".
struct SectionLabel: View {
    let text: String
    var trailing: String? = nil

    var body: some View {
        HStack {
            Text(text.uppercased())
                .font(.caption.weight(.bold))
                .tracking(1.2)
                .foregroundStyle(Color.lkMuted)
            Spacer()
            if let trailing {
                Text(trailing)
                    .font(.caption)
                    .foregroundStyle(Color.lkMuted)
            }
        }
    }
}

/// Small pill label, e.g. "PRO" or "LIVE".
struct Pill: View {
    let text: String
    var color: Color = .lkAmber
    var ink: Color = .lkAmberInk

    var body: some View {
        Text(text)
            .font(.caption2.weight(.heavy))
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .foregroundStyle(ink)
            .background(color, in: Capsule())
    }
}

/// The Lookout mark: a beacon dot inside sweep rings.
struct LogoMark: View {
    var size: CGFloat = 64

    var body: some View {
        Canvas { context, canvasSize in
            let w = canvasSize.width
            let bg = Path(roundedRect: CGRect(origin: .zero, size: canvasSize), cornerRadius: w * 0.22, style: .continuous)
            context.fill(bg, with: .color(.lkGround))
            let c = CGPoint(x: w / 2, y: w / 2)
            for (i, r) in [0.36, 0.25].enumerated() {
                let rr = w * r
                let ring = Path(ellipseIn: CGRect(x: c.x - rr, y: c.y - rr, width: rr * 2, height: rr * 2))
                context.stroke(ring, with: .color(Color.lkAmber.opacity(i == 0 ? 0.45 : 0.8)), lineWidth: w * 0.045)
            }
            let d = w * 0.11
            context.fill(Path(ellipseIn: CGRect(x: c.x - d, y: c.y - d, width: d * 2, height: d * 2)), with: .color(.lkAmber))
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

enum Units {
    static func miles(_ km: Double) -> String {
        let mi = km * 0.621371
        return mi < 10 ? String(format: "%.1f mi", mi) : String(format: "%.0f mi", mi)
    }

    /// 8 compass points from a bearing in degrees.
    static func compass(_ degrees: Double) -> String {
        let points = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
        let i = Int((degrees.truncatingRemainder(dividingBy: 360) + 360 + 22.5) / 45) % 8
        return points[i]
    }
}

@MainActor
enum Haptics {
    static func tap() { UIImpactFeedbackGenerator(style: .medium).impactOccurred() }
    static func warn() { UINotificationFeedbackGenerator().notificationOccurred(.warning) }
}
