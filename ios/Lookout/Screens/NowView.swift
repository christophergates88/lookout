import SwiftUI

struct NowView: View {
    @Environment(LookoutModel.self) private var model
    @Environment(LocationManager.self) private var location
    @Environment(ProStore.self) private var store
    @State private var openAlert: NWSAlert?
    @State private var openCamera: Camera?
    @State private var showDrive = false
    @State private var showPaywall = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    header
                    if location.isDenied {
                        LocationDeniedCard()
                    } else if location.coordinate == nil {
                        ProgressView("Finding you…").padding(40)
                    } else {
                        alertsSection
                        conditionsCard
                        riskCard
                        hourlyStrip
                        camerasSection
                        weekCard
                        credits
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
            .background(Color.lkGround)
            .refreshable { await model.refresh(for: location.coordinate) }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    HStack(spacing: 8) {
                        LogoMark(size: 26)
                        Text("Lookout").font(.headline).foregroundStyle(Color.lkText)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        if store.isPro { showDrive = true } else { showPaywall = true }
                    } label: {
                        Label("Drive", systemImage: "steeringwheel")
                            .labelStyle(.titleAndIcon)
                            .font(.subheadline.bold())
                    }
                }
            }
            .toolbarBackground(Color.lkGround, for: .navigationBar)
            .sheet(item: $openAlert) { AlertDetailView(alert: $0) }
            .sheet(item: $openCamera) { CameraDetailView(camera: $0) }
            .sheet(isPresented: $showPaywall) { PaywallView() }
            .fullScreenCover(isPresented: $showDrive) { DriveView() }
        }
    }

    // MARK: Sections

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(model.place.isEmpty ? "Your location" : model.place)
                    .font(.title2.bold())
                    .foregroundStyle(Color.lkText)
                HStack(spacing: 6) {
                    Circle().fill(model.loading ? Color.lkAmber : Color.lkOK).frame(width: 7, height: 7)
                    Text(statusText).font(.caption).foregroundStyle(Color.lkMuted)
                }
            }
            Spacer()
        }
        .padding(.top, 8)
    }

    private var statusText: String {
        if model.loading { return "Updating…" }
        guard let t = model.updatedAt else { return "Live" }
        return "Updated " + t.formatted(date: .omitted, time: .shortened)
    }

    @ViewBuilder private var alertsSection: some View {
        if model.alerts.isEmpty {
            HStack(spacing: 10) {
                Image(systemName: "checkmark.shield.fill").foregroundStyle(Color.lkOK)
                Text("No active weather alerts here").font(.subheadline).foregroundStyle(Color.lkText)
                Spacer()
            }
            .panel()
        } else {
            VStack(spacing: 8) {
                ForEach(model.alerts) { alert in
                    Button { openAlert = alert } label: { AlertRow(alert: alert) }
                        .buttonStyle(.plain)
                }
            }
        }
    }

    @ViewBuilder private var conditionsCard: some View {
        if let now = model.now {
            HStack(alignment: .center, spacing: 16) {
                Image(systemName: now.symbol)
                    .symbolRenderingMode(.multicolor)
                    .font(.system(size: 52))
                VStack(alignment: .leading, spacing: 4) {
                    Text(now.tempF.map { "\($0)°" } ?? "--")
                        .font(.system(size: 52, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.lkText)
                    Text(now.shortForecast ?? "")
                        .font(.headline)
                        .foregroundStyle(Color.lkText)
                    HStack(spacing: 12) {
                        if let w = now.windSpeed {
                            Label("\(now.windDirection ?? "") \(w)", systemImage: "wind")
                        }
                        if let r = now.rainChance {
                            Label("\(r)%", systemImage: "drop.fill")
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(Color.lkMuted)
                }
                Spacer()
            }
            .panel()
        } else if let err = model.weatherError {
            Text(err).font(.subheadline).foregroundStyle(Color.lkMuted).panel()
        } else {
            ProgressView().frame(maxWidth: .infinity).panel()
        }
    }

    @ViewBuilder private var riskCard: some View {
        if store.isPro {
            if let risk = model.risk {
                HStack(spacing: 12) {
                    RoundedRectangle(cornerRadius: 4).fill(risk.color).frame(width: 8, height: 44)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("STORM RISK TODAY").font(.caption2.bold()).tracking(1).foregroundStyle(Color.lkMuted)
                        Text(risk.title).font(.subheadline.bold()).foregroundStyle(Color.lkText)
                        Text(risk.detail).font(.caption).foregroundStyle(Color.lkMuted)
                    }
                    Spacer()
                }
                .panel()
            }
        } else {
            Button { showPaywall = true } label: {
                HStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Color.lkAmber)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Today's storm risk").font(.subheadline.bold()).foregroundStyle(Color.lkText)
                        Text("See the Storm Prediction Center's severe-weather risk for here.")
                            .font(.caption).foregroundStyle(Color.lkMuted)
                    }
                    Spacer()
                    Pill(text: "PRO")
                }
                .panel()
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder private var hourlyStrip: some View {
        if !model.hourly.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                SectionLabel(text: "Next 12 hours")
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 14) {
                        ForEach(model.hourly.prefix(12)) { p in
                            VStack(spacing: 6) {
                                Text(p.start.map { $0.formatted(.dateTime.hour()) } ?? "")
                                    .font(.caption2).foregroundStyle(Color.lkMuted)
                                Image(systemName: p.symbol).symbolRenderingMode(.multicolor).font(.title3)
                                Text(p.tempF.map { "\($0)°" } ?? "").font(.subheadline.bold()).foregroundStyle(Color.lkText)
                                Text(p.rainChance.map { $0 > 0 ? "\($0)%" : " " } ?? " ")
                                    .font(.caption2).foregroundStyle(Color.lkInfo)
                            }
                            .frame(minWidth: 40)
                        }
                    }
                }
            }
            .panel()
        }
    }

    @ViewBuilder private var camerasSection: some View {
        if Windy.isConfigured {
            let shown = store.isPro ? Array(model.cameras.prefix(12)) : Array(model.cameras.prefix(AppConfig.freeCameraCount))
            VStack(alignment: .leading, spacing: 10) {
                SectionLabel(text: "Nearest cameras", trailing: model.cameras.isEmpty ? nil : "\(model.cameras.count) nearby")
                if shown.isEmpty {
                    Text(model.cameraError ?? "No public cameras found nearby.")
                        .font(.subheadline).foregroundStyle(Color.lkMuted)
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(shown) { cam in
                                Button { openCamera = cam } label: { CameraTile(camera: cam, width: 200) }
                                    .buttonStyle(.plain)
                            }
                        }
                    }
                    if !store.isPro && model.cameras.count > shown.count {
                        Button { showPaywall = true } label: {
                            Label("See all \(model.cameras.count) cameras with Pro", systemImage: "lock.fill")
                                .font(.footnote.bold())
                        }
                    }
                }
            }
            .panel()
        }
    }

    @ViewBuilder private var weekCard: some View {
        if !model.daily.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                SectionLabel(text: "7-day forecast")
                ForEach(model.daily.prefix(14)) { p in
                    HStack(spacing: 12) {
                        Text(p.name ?? "").font(.subheadline).foregroundStyle(Color.lkText)
                            .frame(width: 120, alignment: .leading)
                            .lineLimit(1)
                        Image(systemName: p.symbol).symbolRenderingMode(.multicolor).frame(width: 26)
                        Text(p.shortForecast ?? "").font(.caption).foregroundStyle(Color.lkMuted).lineLimit(1)
                        Spacer()
                        Text(p.tempF.map { "\($0)°" } ?? "").font(.subheadline.bold()).foregroundStyle(Color.lkText)
                    }
                    if p.id != model.daily.prefix(14).last?.id { Divider().overlay(Color.lkLine) }
                }
            }
            .panel()
        }
    }

    private var credits: some View {
        Text("Forecasts and alerts: National Weather Service. Storm risk: NOAA Storm Prediction Center. Webcams provided by windy.com.")
            .font(.caption2)
            .foregroundStyle(Color.lkMuted)
            .multilineTextAlignment(.center)
            .padding(.top, 4)
    }
}

// MARK: - Pieces shared by several screens

struct AlertRow: View {
    let alert: NWSAlert

    var color: Color {
        switch alert.severity {
        case "Extreme", "Severe": return .lkBad
        case "Moderate": return .lkAmber
        default: return .lkInfo
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 3).fill(color).frame(width: 6)
            VStack(alignment: .leading, spacing: 3) {
                Text(alert.event).font(.headline).foregroundStyle(Color.lkText)
                if let ends = alert.ends {
                    Text("Until " + ends.formatted(.dateTime.weekday(.abbreviated).hour().minute()))
                        .font(.caption).foregroundStyle(Color.lkMuted)
                }
            }
            Spacer()
            Image(systemName: "chevron.right").font(.caption).foregroundStyle(Color.lkMuted)
        }
        .padding(12)
        .background(color.opacity(0.14), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(color.opacity(0.5), lineWidth: 1))
    }
}

struct AlertDetailView: View {
    let alert: NWSAlert
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    AlertRow(alert: alert)
                    if !alert.headline.isEmpty {
                        Text(alert.headline).font(.headline).foregroundStyle(Color.lkText)
                    }
                    if !alert.instruction.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            SectionLabel(text: "What to do")
                            Text(alert.instruction).foregroundStyle(Color.lkText)
                        }
                        .panel()
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        SectionLabel(text: "Details")
                        Text(alert.description).foregroundStyle(Color.lkText)
                    }
                    .panel()
                    Text("Areas: \(alert.areaDesc)").font(.caption).foregroundStyle(Color.lkMuted)
                    Text("Issued by \(alert.sender)").font(.caption).foregroundStyle(Color.lkMuted)
                }
                .padding(16)
            }
            .background(Color.lkGround)
            .navigationTitle(alert.event)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}

struct LocationDeniedCard: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "location.slash").font(.largeTitle).foregroundStyle(Color.lkAmber)
            Text("Lookout needs your location").font(.headline).foregroundStyle(Color.lkText)
            Text("Weather, alerts and cameras are all for where you are. Turn on location for Lookout in Settings.")
                .font(.subheadline).foregroundStyle(Color.lkMuted).multilineTextAlignment(.center)
            if let url = URL(string: UIApplication.openSettingsURLString) {
                Link("Open Settings", destination: url).bold()
            }
        }
        .padding(24)
        .panel()
    }
}
