import SwiftUI

struct CamerasView: View {
    @Environment(LookoutModel.self) private var model
    @Environment(LocationManager.self) private var location
    @Environment(ProStore.self) private var store
    @State private var openCamera: Camera?
    @State private var showPaywall = false

    private let columns = [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if !Windy.isConfigured {
                        Text("Cameras are turned off in this build.")
                            .foregroundStyle(Color.lkMuted).panel()
                    } else if model.cameras.isEmpty {
                        Text(model.cameraError ?? (model.loading ? "Looking for cameras…" : "No public cameras found within about \(AppConfig.cameraRadiusKm * 62 / 100) miles."))
                            .foregroundStyle(Color.lkMuted).panel()
                    } else {
                        SectionLabel(text: "Closest first", trailing: "\(model.cameras.count) cameras")
                        LazyVGrid(columns: columns, spacing: 10) {
                            ForEach(visible) { cam in
                                Button { openCamera = cam } label: { CameraTile(camera: cam, width: nil) }
                                    .buttonStyle(.plain)
                            }
                        }
                        if !store.isPro && model.cameras.count > visible.count {
                            ProLocked(title: "\(model.cameras.count - visible.count) more cameras nearby",
                                      pitch: "Lookout Pro shows every public camera around you, closest first, and the ones ahead of you in Drive mode.",
                                      symbol: "video.fill") { EmptyView() }
                        }
                    }
                    Text("Webcams provided by windy.com. Tap a camera, then its picture, to open it on Windy.")
                        .font(.caption2).foregroundStyle(Color.lkMuted)
                }
                .padding(16)
            }
            .background(Color.lkGround)
            .refreshable { await model.refresh(for: location.coordinate) }
            .navigationTitle("Cameras")
            .sheet(item: $openCamera) { CameraDetailView(camera: $0) }
        }
    }

    private var visible: [Camera] {
        store.isPro ? model.cameras : Array(model.cameras.prefix(AppConfig.freeCameraCount))
    }
}

struct CameraTile: View {
    let camera: Camera
    var width: CGFloat?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack(alignment: .topLeading) {
                AsyncImage(url: camera.imageURL) { phase in
                    switch phase {
                    case .success(let img): img.resizable().scaledToFill()
                    default: Color.lkPanel2.overlay(Image(systemName: "video").foregroundStyle(Color.lkMuted))
                    }
                }
                .frame(width: width, height: 112)
                .frame(maxWidth: width == nil ? CGFloat.infinity : nil)
                .clipped()
                if camera.live { Pill(text: "LIVE", color: .lkBad, ink: .white).padding(6) }
            }
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            Text(camera.title).font(.caption.bold()).foregroundStyle(Color.lkText).lineLimit(1)
            Text(Units.miles(camera.km)).font(.caption2).foregroundStyle(Color.lkMuted)
        }
        .frame(width: width)
    }
}

struct CameraDetailView: View {
    let camera: Camera
    @Environment(LocationManager.self) private var location
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 14) {
                Link(destination: camera.pageURL) {
                    AsyncImage(url: camera.imageURL) { phase in
                        switch phase {
                        case .success(let img): img.resizable().scaledToFit()
                        case .failure: Color.lkPanel2.frame(height: 220).overlay(Text("Picture unavailable").foregroundStyle(Color.lkMuted))
                        default: Color.lkPanel2.frame(height: 220).overlay(ProgressView())
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                Text(camera.title).font(.title3.bold()).foregroundStyle(Color.lkText)
                HStack {
                    Text(Units.miles(camera.km))
                    if let here = location.coordinate {
                        Text(Units.compass(Geo.bearing(here, camera.coordinate)))
                    }
                    if !camera.city.isEmpty { Text("· " + camera.city) }
                }
                .font(.subheadline).foregroundStyle(Color.lkMuted)
                Link(destination: camera.pageURL) {
                    Label(camera.live ? "Watch live on windy.com" : "Open on windy.com", systemImage: "arrow.up.right.square")
                        .bold().frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .foregroundStyle(Color.lkAmberInk)
                .controlSize(.large)
                Text("Webcam provided by windy.com").font(.caption2).foregroundStyle(Color.lkMuted)
                Spacer()
            }
            .padding(16)
            .background(Color.lkGround)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .presentationDetents([.large])
    }
}
