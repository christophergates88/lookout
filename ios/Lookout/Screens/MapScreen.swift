import SwiftUI
import MapKit

struct MapScreen: View {
    @Environment(LookoutModel.self) private var model
    @Environment(LocationManager.self) private var location
    @Environment(ProStore.self) private var store
    @AppStorage("mapRadar") private var radarOn = true
    @AppStorage("mapTraffic") private var trafficOn = true
    @AppStorage("mapPlanes") private var planesOn = true
    @AppStorage("mapQuakes") private var quakesOn = true
    @State private var web: WebLink?
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
                    aircraft: planesOn ? model.aircraft : [],
                    quakes: quakesOn ? model.quakes : [],
                    recenter: recenter,
                    onCamera: { openCamera = $0 },
                    onAlert: { openAlert = $0 },
                    onLink: { web = WebLink(url: $0) }
                )
                .ignoresSafeArea(edges: .top)

                HStack(spacing: 10) {
                    ScrollView(.horizontal, showsIndicators: false) {
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
                            Button {
                                planesOn.toggle()
                            } label: {
                                Label("Planes", systemImage: "airplane")
                                    .padding(.horizontal, 12).padding(.vertical, 8)
                                    .background(planesOn ? Color.lkAmber : Color.lkPanel, in: Capsule())
                                    .foregroundStyle(planesOn ? Color.lkAmberInk : Color.lkText)
                            }
                            Button {
                                quakesOn.toggle()
                            } label: {
                                Label("Quakes", systemImage: "waveform.path.ecg")
                                    .padding(.horizontal, 12).padding(.vertical, 8)
                                    .background(quakesOn ? Color.lkAmber : Color.lkPanel, in: Capsule())
                                    .foregroundStyle(quakesOn ? Color.lkAmberInk : Color.lkText)
                            }
                        }
                        .padding(.top, 10)
                        .padding(.trailing, 6)
                    }
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
            .task(id: planesOn) {
                // Planes move fast: refresh them every 30 seconds while the map is open.
                while planesOn && !Task.isCancelled {
                    await model.refreshAircraft(for: location.coordinate)
                    try? await Task.sleep(for: .seconds(location.coordinate == nil ? 5 : 30))
                }
            }
            .sheet(item: $web) { SafariView(url: $0.url).ignoresSafeArea() }
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

final class PlanePin: NSObject, MKAnnotation {
    var plane: Aircraft
    @objc dynamic var coordinate: CLLocationCoordinate2D
    var title: String? { plane.callsign }
    var subtitle: String? { plane.summary }
    init(_ plane: Aircraft) { self.plane = plane; coordinate = plane.coordinate }
}

final class QuakePin: NSObject, MKAnnotation {
    let quake: Quake
    var coordinate: CLLocationCoordinate2D { quake.coordinate }
    var title: String? { String(format: "Magnitude %.1f earthquake", quake.magnitude) }
    var subtitle: String? { quake.place + ", " + quake.time.formatted(.relative(presentation: .named)) }
    init(_ quake: Quake) { self.quake = quake }
}

/// A small airplane that points the way it's flying.
final class PlaneView: MKAnnotationView {
    private let icon = UIImageView(image: UIImage(systemName: "airplane"))

    override init(annotation: MKAnnotation?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        frame = CGRect(x: 0, y: 0, width: 26, height: 26)
        icon.frame = bounds
        icon.contentMode = .scaleAspectFit
        icon.tintColor = UIColor(red: 0.92, green: 0.95, blue: 0.98, alpha: 1)
        icon.layer.shadowColor = UIColor.black.cgColor
        icon.layer.shadowOpacity = 0.9
        icon.layer.shadowRadius = 2
        icon.layer.shadowOffset = .zero
        addSubview(icon)
        canShowCallout = true
        rightCalloutAccessoryView = UIButton(type: .detailDisclosure)
        displayPriority = .defaultHigh
    }

    required init?(coder: NSCoder) { fatalError() }

    func apply(_ plane: Aircraft) {
        // The symbol points east; turn it to the plane's track.
        let deg = (plane.track ?? 90) - 90
        icon.transform = CGAffineTransform(rotationAngle: CGFloat(deg * .pi / 180))
        icon.alpha = plane.onGround ? 0.5 : 1
    }
}

/// A dot sized by magnitude.
final class QuakeView: MKAnnotationView {
    override init(annotation: MKAnnotation?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        canShowCallout = true
        rightCalloutAccessoryView = UIButton(type: .detailDisclosure)
        displayPriority = .defaultHigh
    }

    required init?(coder: NSCoder) { fatalError() }

    func apply(_ q: Quake) {
        let d = CGFloat(10 + max(0, q.magnitude) * 5)
        frame = CGRect(x: 0, y: 0, width: d, height: d)
        layer.cornerRadius = d / 2
        let strong = q.magnitude >= 3
        backgroundColor = (strong ? UIColor(red: 1, green: 0.38, blue: 0.38, alpha: 1) : UIColor(red: 0.96, green: 0.6, blue: 0.2, alpha: 1)).withAlphaComponent(0.75)
        layer.borderColor = UIColor.white.withAlphaComponent(0.9).cgColor
        layer.borderWidth = 1.5
    }
}

struct LookoutMap: UIViewRepresentable {
    var center: CLLocationCoordinate2D?
    var cameras: [Camera]
    var alerts: [NWSAlert]
    var radar: Bool
    var traffic: Bool
    var aircraft: [Aircraft]
    var quakes: [Quake]
    var recenter: Int
    var onCamera: (Camera) -> Void
    var onAlert: (NWSAlert) -> Void
    var onLink: (URL) -> Void

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

        // Planes: move the ones still in view, add new ones, drop the rest.
        var stillHere = Set<String>()
        for plane in aircraft {
            stillHere.insert(plane.id)
            if let pin = c.planes[plane.id] {
                pin.plane = plane
                pin.coordinate = plane.coordinate
                (map.view(for: pin) as? PlaneView)?.apply(plane)
            } else {
                let pin = PlanePin(plane)
                c.planes[plane.id] = pin
                map.addAnnotation(pin)
            }
        }
        for (id, pin) in c.planes where !stillHere.contains(id) {
            map.removeAnnotation(pin)
            c.planes[id] = nil
        }

        // Earthquakes
        let quakeIDs = quakes.map(\.id)
        if quakeIDs != c.quakeIDs {
            c.quakeIDs = quakeIDs
            map.removeAnnotations(map.annotations.filter { $0 is QuakePin })
            map.addAnnotations(quakes.map(QuakePin.init))
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
        var planes: [String: PlanePin] = [:]
        var quakeIDs: [String] = []

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
            if let pin = annotation as? PlanePin {
                let view = (mapView.dequeueReusableAnnotationView(withIdentifier: "plane") as? PlaneView)
                    ?? PlaneView(annotation: pin, reuseIdentifier: "plane")
                view.annotation = pin
                view.apply(pin.plane)
                return view
            }
            if let pin = annotation as? QuakePin {
                let view = (mapView.dequeueReusableAnnotationView(withIdentifier: "quake") as? QuakeView)
                    ?? QuakeView(annotation: pin, reuseIdentifier: "quake")
                view.annotation = pin
                view.apply(pin.quake)
                return view
            }
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
            // Planes and quakes show a callout; cameras open their own screen.
            guard let pin = view.annotation as? CameraPin else { return }
            parent?.onCamera(pin.camera)
            mapView.deselectAnnotation(pin, animated: false)
        }

        func mapView(_ mapView: MKMapView, annotationView view: MKAnnotationView, calloutAccessoryControlTapped control: UIControl) {
            if let pin = view.annotation as? PlanePin, let url = pin.plane.trackURL {
                parent?.onLink(url)
            } else if let pin = view.annotation as? QuakePin, let url = pin.quake.url {
                parent?.onLink(url)
            }
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
