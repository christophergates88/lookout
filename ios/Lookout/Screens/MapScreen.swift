import SwiftUI
import MapKit

struct MapScreen: View {
    @Environment(LookoutModel.self) private var model
    @Environment(LocationManager.self) private var location
    @Environment(ProStore.self) private var store
    @AppStorage("mapRadar") private var radarOn = true
    @AppStorage("mapTraffic") private var trafficOn = true
    @State private var openCamera: Camera?
    @State private var openAlert: NWSAlert?
    @State private var showPaywall = false
    @State private var recenter = 0

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                LookoutMap(
                    center: location.coordinate,
                    cameras: store.isPro ? model.cameras : Array(model.cameras.prefix(AppConfig.freeCameraCount)),
                    alerts: model.alerts,
                    radar: store.isPro && radarOn,
                    traffic: trafficOn,
                    recenter: recenter,
                    onCamera: { openCamera = $0 },
                    onAlert: { openAlert = $0 }
                )
                .ignoresSafeArea(edges: .top)

                HStack(spacing: 10) {
                    Button {
                        if store.isPro { radarOn.toggle() } else { showPaywall = true }
                    } label: {
                        Label("Radar", systemImage: "cloud.rain")
                            .padding(.horizontal, 12).padding(.vertical, 8)
                            .background(store.isPro && radarOn ? Color.lkAmber : Color.lkPanel, in: Capsule())
                            .foregroundStyle(store.isPro && radarOn ? Color.lkAmberInk : Color.lkText)
                            .overlay(alignment: .topTrailing) {
                                if !store.isPro { Pill(text: "PRO").offset(x: 10, y: -10) }
                            }
                    }
                    Button {
                        trafficOn.toggle()
                    } label: {
                        Label("Traffic", systemImage: "car.fill")
                            .padding(.horizontal, 12).padding(.vertical, 8)
                            .background(trafficOn ? Color.lkAmber : Color.lkPanel, in: Capsule())
                            .foregroundStyle(trafficOn ? Color.lkAmberInk : Color.lkText)
                    }
                    Spacer()
                    Button {
                        recenter += 1
                    } label: {
                        Image(systemName: "location.fill")
                            .padding(10)
                            .background(Color.lkPanel, in: Circle())
                    }
                    .accessibilityLabel("Center on me")
                }
                .font(.subheadline.bold())
                .padding(.horizontal, 16)
                .padding(.bottom, 14)
            }
            .toolbar(.hidden, for: .navigationBar)
            .sheet(item: $openCamera) { CameraDetailView(camera: $0) }
            .sheet(item: $openAlert) { AlertDetailView(alert: $0) }
            .sheet(isPresented: $showPaywall) { PaywallView() }
        }
    }
}

// MARK: - MKMapView wrapper (SwiftUI's Map can't show radar tiles)

final class CameraPin: NSObject, MKAnnotation {
    let camera: Camera
    var coordinate: CLLocationCoordinate2D { camera.coordinate }
    var title: String? { camera.title }
    init(_ camera: Camera) { self.camera = camera }
}

final class AlertShape: MKPolygon {
    var alert: NWSAlert?
}

struct LookoutMap: UIViewRepresentable {
    var center: CLLocationCoordinate2D?
    var cameras: [Camera]
    var alerts: [NWSAlert]
    var radar: Bool
    var traffic: Bool
    var recenter: Int
    var onCamera: (Camera) -> Void
    var onAlert: (NWSAlert) -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView()
        map.delegate = context.coordinator
        map.showsUserLocation = true
        map.overrideUserInterfaceStyle = .dark
        map.pointOfInterestFilter = .excludingAll
        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.tapped(_:)))
        tap.cancelsTouchesInView = false
        map.addGestureRecognizer(tap)
        return map
    }

    func updateUIView(_ map: MKMapView, context: Context) {
        let c = context.coordinator
        c.parent = self
        map.showsTraffic = traffic

        // First fix, or the user asked to recenter.
        if let center, (!c.didCenter || c.lastRecenter != recenter) {
            c.didCenter = true
            c.lastRecenter = recenter
            map.setRegion(MKCoordinateRegion(center: center, latitudinalMeters: 90_000, longitudinalMeters: 90_000), animated: true)
        }

        // Cameras
        let camIDs = cameras.map(\.id)
        if camIDs != c.cameraIDs {
            c.cameraIDs = camIDs
            map.removeAnnotations(map.annotations.filter { $0 is CameraPin })
            map.addAnnotations(cameras.map(CameraPin.init))
        }

        // Alert areas
        let alertIDs = alerts.map(\.id)
        if alertIDs != c.alertIDs {
            c.alertIDs = alertIDs
            map.removeOverlays(map.overlays.filter { $0 is AlertShape })
            for alert in alerts {
                for ring in alert.shape?.outerRings ?? [] where ring.count > 2 {
                    let poly = AlertShape(coordinates: ring, count: ring.count)
                    poly.alert = alert
                    map.addOverlay(poly, level: .aboveRoads)
                }
            }
        }

        // Radar: refresh the tiles every 5 minutes while it's on.
        let radarStamp = radar ? Int(Date().timeIntervalSince1970 / 300) : 0
        if radarStamp != c.radarStamp {
            c.radarStamp = radarStamp
            if let old = c.radarOverlay { map.removeOverlay(old) }
            c.radarOverlay = nil
            if radar {
                let tiles = MKTileOverlay(urlTemplate: AppConfig.radarTileTemplate + "?t=\(radarStamp)")
                tiles.canReplaceMapContent = false
                // Under the warning areas, so they stay visible on top of the radar.
                map.insertOverlay(tiles, at: 0, level: .aboveRoads)
                c.radarOverlay = tiles
            }
        }
    }

    final class Coordinator: NSObject, MKMapViewDelegate {
        var parent: LookoutMap?
        var didCenter = false
        var lastRecenter = 0
        var cameraIDs: [String] = []
        var alertIDs: [String] = []
        var radarStamp = 0
        var radarOverlay: MKTileOverlay?

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let tiles = overlay as? MKTileOverlay {
                let r = MKTileOverlayRenderer(tileOverlay: tiles)
                r.alpha = 0.65
                return r
            }
            if let shape = overlay as? AlertShape {
                let r = MKPolygonRenderer(polygon: shape)
                let severe = shape.alert?.severity == "Extreme" || shape.alert?.severity == "Severe"
                let color: UIColor = severe ? UIColor(red: 1, green: 0.38, blue: 0.38, alpha: 1) : UIColor(red: 0.96, green: 0.71, blue: 0.25, alpha: 1)
                r.fillColor = color.withAlphaComponent(0.18)
                r.strokeColor = color
                r.lineWidth = 2
                return r
            }
            return MKOverlayRenderer(overlay: overlay)
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            guard annotation is CameraPin else { return nil }
            let id = "cam"
            let view = (mapView.dequeueReusableAnnotationView(withIdentifier: id) as? MKMarkerAnnotationView)
                ?? MKMarkerAnnotationView(annotation: annotation, reuseIdentifier: id)
            view.annotation = annotation
            view.glyphImage = UIImage(systemName: "video.fill")
            view.markerTintColor = UIColor(red: 0.36, green: 0.70, blue: 1, alpha: 1)
            view.canShowCallout = false
            view.displayPriority = .required
            return view
        }

        func mapView(_ mapView: MKMapView, didSelect view: MKAnnotationView) {
            if let pin = view.annotation as? CameraPin {
                parent?.onCamera(pin.camera)
            }
            mapView.deselectAnnotation(view.annotation, animated: false)
        }

        /// Tapping inside a warning area opens it.
        @objc func tapped(_ g: UITapGestureRecognizer) {
            guard let map = g.view as? MKMapView else { return }
            let point = g.location(in: map)
            // Ignore taps on pins.
            if map.annotations.contains(where: { a in
                guard let v = map.view(for: a) else { return false }
                return v.frame.insetBy(dx: -8, dy: -8).contains(point)
            }) { return }
            let coord = map.convert(point, toCoordinateFrom: map)
            let mapPoint = MKMapPoint(coord)
            for case let shape as AlertShape in map.overlays {
                let r = MKPolygonRenderer(polygon: shape)
                r.createPath()
                let p = r.point(for: mapPoint)
                if r.path?.contains(p) == true, let alert = shape.alert {
                    parent?.onAlert(alert)
                    return
                }
            }
        }
    }
}
