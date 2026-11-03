import MapKit
import SwiftUI
import StraightBussingKit

/// The live map (web/js/map; docs/DESIGN-SPEC.md section 11): Apple's standard map, flat and muted, with points of
/// interest off; route lines in route colors stacked by draw order, each on a casing that flips to the opposite edge
/// when the route color is too close to the default one (computed from the color); two emphasis levels (network /
/// focused: a route page, a trip, a custom route); stops as small circles in their route's color from zoom 14; live
/// buses as route-colored markers with a heading notch; the user's position; a started or selected trip (bus legs on
/// the road shape, walking dots, the destination pin, "Board here" / "Get off" callouts). During a started trip (Kit
/// `TripYou`, web ui/tripmap.js) you are drawn where the trip says: on the bus you ride (a ring and "You" on its
/// marker; the GPS dot steps back), the boarding stop as a guess ("You (est.)") without GPS, else the normal GPS dot.
///
/// Cheap to re-evaluate on purpose: lines and stops come from `AppModel.mapLayers` (cached per visibility, appearance
/// and zoom step), bus staleness is computed at poll time, the camera lives in its own observable, the real user
/// location is MapKit's `UserAnnotation` (no redraw per location update) and the bottom inset is applied by the
/// caller, so this body only re-runs when buses, the trip/plan, the visible routes or the zoom step change.
///
/// Building and place names (owner 2026-10-13, web map/landmarks.js): text annotations under everything else, placed
/// by the Kit (`Landmarks.place`) when the camera stops moving (`layoutLabels`), kept in `AppModel.mapLabels`; Apple's
/// own points of interest stay off (they would name places twice).
struct MapScreen: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.colorScheme) private var scheme

    /// The trip drawn on the map: the started one, else the selected Directions option.
    var plan: TripOption? {
        if let t = model.activeTrip { return t.option }
        if model.page == .directions, let r = model.dir.result, r.options.indices.contains(model.dir.selected) { return r.options[model.dir.selected] }
        return nil
    }

    /// Directions with no shuttle option: the walk the whole way (sidewalk route once refined), like the web.
    var walkOnly: [LatLon]? {
        guard model.activeTrip == nil, model.page == .directions, let r = model.dir.result, r.options.isEmpty,
              let f = model.dir.from?.coord, let t = model.dir.to?.coord else { return nil }
        return r.walkOnlyCoords ?? [f, t]
    }

    /// Walking path: round 4 pt dots in `tintFill` (Apple Maps style, spec 11.4).
    static let walkStroke = StrokeStyle(lineWidth: 4, lineCap: .round, dash: [0.01, 8])

    var body: some View {
        @Bindable var camera = model.mapCamera
        let zoom = camera.zoom
        let layers = model.mapLayers(dark: scheme == .dark, zoom: zoom)
        let buses = model.mapBuses.filter { !layers.hidden.contains($0.rid) }
        let drawn = plan, ring = ringed   // once per body, not once per stop
        let openStop: String? = { if case .stop(let id)? = model.page { return id }; return nil }()
        // you on the started trip (Kit TripYou, the same evaluation as the card, the alerts and the Live Activity)
        let you = model.activeTrip != nil ? model.tripYou : nil
        let youBus: String? = you.flatMap { $0.onBus && $0.point != nil ? $0.vehicleId : nil }
        let youOnDrawnBus = youBus != nil && buses.contains { $0.id == youBus }
        let labels = you?.stopLabels ?? []
        // a marker of its own: the boarding stop as a guess (no GPS), or the bus you ride when its marker is not drawn
        let youMark: (at: LatLon, guess: Bool)? = you.flatMap { y in
            guard let p = y.point else { return nil }
            if y.source == .stop { return (p, true) }
            if y.onBus && !youOnDrawnBus { return (p, false) }
            return nil
        }
        let hideDot = you?.onBus == true   // on the bus: the GPS dot steps back (same place, or worse)
        // the heading cone (owner 2026-10-14): only `active` is read here (it flips rarely); the dot reads the rotation
        let heading = model.location.heading
        let coned = heading.active
        let walk = walkOnly
        // stops from zoom 14 (spec 11.4); favorites and highlighted stops always
        let showStops = zoom >= 14
        let bigStops = zoom >= 16
        let stops = layers.stops.filter { showStops || $0.isFav || ring.contains($0.id) }
        let legW = AppModel.lineWidth(zoom) + 2
        // the map labels: drawn from the last layout; laid out again on camera end or when what they avoid changes
        let placed = model.mapLabels.placed
        let labelScale = MapLabelModel.scale(typeSize)
        let labelSig = labelSignature(layers, ring: ring, tripLabels: labels, youGuess: youMark.flatMap { $0.guess ? $0.at : nil },
                                      plan: drawn, walkEnd: walk?.last)
        MapReader { proxy in
        Map(position: $camera.position) {
            // building and place names first: stops, buses, the trip and you are drawn over them, and they never take a tap
            ForEach(placed, id: \.drawKey) { p in
                Annotation("", coordinate: p.landmark.coord.cl, anchor: p.anchor.unitPoint) {
                    LandmarkLabel(label: p).equatable()
                }
                .annotationTitles(.hidden)
            }
            ForEach(layers.lines) { l in
                MapPolyline(coordinates: l.coords)
                    .stroke(l.color, style: StrokeStyle(lineWidth: l.width, lineCap: .round, lineJoin: .round))
            }
            if let o = drawn {
                // bus legs along the route's road shape between the stops (Kit Geometry.alongShape), cached, on a casing
                ForEach(Array(o.busLegs.enumerated()), id: \.offset) { item in
                    let path = model.roadPath(item.element).map(\.cl)
                    MapPolyline(coordinates: path)
                        .stroke(Palette.busRing, style: StrokeStyle(lineWidth: legW + 3, lineCap: .round, lineJoin: .round))
                    MapPolyline(coordinates: path)
                        .stroke(Color(hex: model.route(item.element.rid)?.color), style: StrokeStyle(lineWidth: legW, lineCap: .round, lineJoin: .round))
                }
                ForEach(Array(o.walkLegs.enumerated()), id: \.offset) { item in
                    MapPolyline(coordinates: (item.element.coords ?? [item.element.from.coord, item.element.to.coord]).map(\.cl))
                        .stroke(Palette.tintFill, style: Self.walkStroke)
                }
                if let last = o.legs.last {
                    let end = last.walk?.to.coord ?? last.bus?.alight.coord ?? LatLon(lat: 0, lon: 0)
                    Marker("Destination", systemImage: "mappin", coordinate: end.cl).tint(Palette.dangerFill)
                }
            }
            if let w = walk, let end = w.last {
                MapPolyline(coordinates: w.map(\.cl))
                    .stroke(Palette.tintFill, style: Self.walkStroke)
                Marker("Destination", systemImage: "mappin", coordinate: end.cl).tint(Palette.dangerFill)
            }
            // direction-of-travel chevrons along 1-3 focused routes (decorative, never intercept taps)
            ForEach(layers.chevrons) { c in
                Annotation("", coordinate: c.coord, anchor: .center) {
                    Image(systemName: "chevron.up")
                        .font(.system(size: 8, weight: .black))
                        .foregroundStyle(.white)
                        .padding(2)
                        .background(c.color, in: Circle())
                        .rotationEffect(.degrees(c.bearing))
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
                .annotationTitles(.hidden)
            }
            ForEach(stops) { s in
                Annotation(s.stop.name, coordinate: s.stop.coord.cl, anchor: .center) {
                    StopDot(id: s.id, isFav: s.isFav, faded: drawn != nil, ring: ring.contains(s.id), big: bigStops, color: s.color,
                            name: s.id == openStop ? s.stop.name : nil) { model.stopTapped(s.id) }
                        .equatable()
                        .accessibilityLabel(s.isFav ? "Favorite stop \(s.stop.name)" : "Stop \(s.stop.name)")
                }
                .annotationTitles(.hidden)
            }
            // the trip's stops: "Board here" and the get-off count (the card's and the alerts' numbers) under their
            // stops, as on the web (the destination marker and the You pill sit above their points); never in the way of a tap
            ForEach(labels, id: \.self) { l in
                Annotation("", coordinate: l.point.cl, anchor: UnitPoint.top) {
                    TripStopLabel(text: l.text)
                        .padding(.top, 10)
                        .allowsHitTesting(false)
                        .accessibilityLabel("\(l.text), \(l.stopName)")
                }
                .annotationTitles(.hidden)
            }
            if let m = youMark, let y = you {
                Annotation("", coordinate: m.at.cl, anchor: .center) {
                    YouMarker(guess: m.guess)
                        .allowsHitTesting(false)
                        .accessibilityLabel(y.text)
                }
                .annotationTitles(.hidden)
            }
            ForEach(buses) { b in
                let isYou = youOnDrawnBus && b.id == youBus
                Annotation(b.label, coordinate: b.coord.cl, anchor: .center) {
                    Button { model.busTapped(b.rid, vehicleId: b.id) } label: {
                        BusMarker(route: model.route(b.rid), bearing: b.bearing, stale: b.stale, youText: isYou ? you?.text : nil,
                                  number: b.number, picked: model.selectedBus == SelectedBus(rid: b.rid, vehicleId: b.id))
                            .frame(minWidth: 44, minHeight: 44)
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint(b.number != nil ? "Opens the route with this bus's times" : "Opens the route")
                }
                .annotationTitles(.hidden)
            }
            // Demo mode: a fixed simulated position (no cone: the compass would point a place you are not). Real
            // location: MapKit's own user dot, or, while the compass reads and the fix is good (`UserHeading`), the same
            // dot drawn by the app with the heading cone, still placed by MapKit (its own fine fixes, not the 30 m
            // filtered `model.user`). Both step back while you are drawn on the bus.
            if model.config.demo, !hideDot, let u = model.user {
                Annotation("My location", coordinate: u.cl, anchor: .center) { UserDot() }
                    .annotationTitles(.hidden)
            }
            if !model.config.demo && !hideDot && !coned {
                UserAnnotation()
            }
            if !model.config.demo && !hideDot && coned {
                UserAnnotation(anchor: .center) { _ in UserDot(heading: heading) }
            }
        }
        .mapStyle(.standard(elevation: .flat, emphasis: .muted, pointsOfInterest: .excludingAll))
        .mapControls { MapCompass() }
        // the names are laid out when the camera stops, not on every frame of a pan or zoom: each frame only notes the
        // time, the layout runs once the camera has been still for 0.3 s (with .onEnd alone, the names stayed where an
        // earlier camera had put them after the app's own camera glides in the CI simulator)
        .onMapCameraChange(frequency: .continuous) { ctx in
            heading.mapTurned(ctx.camera.heading)   // the cone keeps pointing the real way on a rotated map
            model.mapLabels.cameraMoved { layoutLabels(proxy, scale: labelScale) }
        }
        // a tap on a route line opens the line drawn on top (owner 2026-10-27; not while a trip or walk is drawn), a tap
        // on empty map lowers the sheet to peek (web onMapTap). Simultaneous, so it never blocks the stop / bus buttons;
        // `mapTapped` ignores a tap that also hit one of them. A pointer shortcut only: VoiceOver uses the Routes list.
        .simultaneousGesture(SpatialTapGesture(coordinateSpace: .global).onEnded { v in
            model.mapTapped(line: drawn == nil && walk == nil ? lineHit(v.location, proxy, layers) : nil)
        })
        .accessibilityLabel("Shuttle map")
        // follow camera (AppModel+Follow.swift), watched by a child view so this body does not re-run on a pan or a
        // settled sheet
        .background { FollowWatcher(camera: model.mapCamera, you: you) { followCheck(proxy) } }
        .background {
            LabelWatcher(camera: model.mapCamera, labels: model.mapLabels, signature: labelSig, scale: labelScale) {
                layoutLabels(proxy, scale: labelScale)
            }
        }
        }
    }

    /// The route line under a tap (web map.js + map/geometry.js lineAt, Kit `LineTap`): only lines whose box comes near
    /// the tap are projected; the topmost within `LineTap.reach` points plus half its width wins. Hidden routes are not
    /// in `layers.lines`, so they are never tapped; casings are skipped (their line has the same route).
    func lineHit(_ at: CGPoint, _ proxy: MapProxy, _ layers: MapLayers) -> String? {
        let r = CGFloat(LineTap.reach + 6)
        let corners = [CGPoint(x: at.x - r, y: at.y - r), CGPoint(x: at.x + r, y: at.y - r),
                       CGPoint(x: at.x - r, y: at.y + r), CGPoint(x: at.x + r, y: at.y + r)]
        let c = corners.compactMap { proxy.convert($0, from: .global) }
        guard c.count == 4, let lat0 = c.map(\.latitude).min(), let lat1 = c.map(\.latitude).max(),
              let lon0 = c.map(\.longitude).min(), let lon1 = c.map(\.longitude).max() else { return nil }
        var lines: [LineTap.Line] = []
        for l in layers.lines where !l.casing && l.maxLat >= lat0 && l.minLat <= lat1 && l.maxLon >= lon0 && l.minLon <= lon1 {
            let px = l.coords.compactMap { proxy.convert($0, to: .global) }.map { SIMD2(Double($0.x), Double($0.y)) }
            lines.append(LineTap.Line(rid: l.rid, px: px, width: Double(l.width)))
        }
        return LineTap.lineAt(SIMD2(Double(at.x), Double(at.y)), lines: lines)
    }

    /// Is every point of the trip's frame inside the visible map (above the sheet, below the chrome)? Then nothing
    /// moves; else the model frames it (and on a phase or leg change).
    func followCheck(_ proxy: MapProxy) {
        let cam = model.mapCamera
        guard cam.follow, model.activeTrip != nil, let y = model.tripYou else { return }
        let r = cam.visibleRect.insetBy(dx: -2, dy: -2)
        let out = y.frame.contains { p in
            guard let pt = proxy.convert(p.cl, to: .global) else { return true }
            return !r.contains(pt)
        }
        model.followTrip(y, outOfView: out)
    }

    /// Stops with a ring: the Routes to station candidates, else the open stop (web highlightStops / setSelectedStop).
    var ringed: Set<String> {
        if !model.pickHighlights.isEmpty { return Set(model.pickHighlights) }
        if case .stop(let id)? = model.page { return [id] }
        return []
    }
}

// MARK: Map labels (building and place names)

extension MapScreen {
    /// Lay the names out for the camera now (web map/landmarks.js refresh): the zoom from the ground scale at the center
    /// of the visible map (the web's zoom; a rotated map keeps it), the names shown at that zoom inside the visible box,
    /// projected by MapKit, then the Kit's placement inside the visible map (below the floating chrome, above the
    /// sheet). Called on camera end, a resized visible map, new obstacles, new landmarks or a new text size; it reads
    /// the model outside any view body, so only a changed result redraws the map. The zoom also sets the line widths
    /// and stop sizes (`MapCameraModel.setZoom`, written only when its 0.5 step changes).
    func layoutLabels(_ proxy: MapProxy, scale: Double) {
        let labels = model.mapLabels
        let view = model.mapCamera.visibleRect
        // the expanded sheet covers the map: no names under it
        guard view.width >= 80, view.height >= 60 else { labels.show([]); return }
        let mid = CGPoint(x: view.midX, y: view.midY)
        guard let a = proxy.convert(CGPoint(x: mid.x - 50, y: mid.y), from: .global),
              let b = proxy.convert(CGPoint(x: mid.x + 50, y: mid.y), from: .global) else { return }
        let la = LatLon(lat: a.latitude, lon: a.longitude), lb = LatLon(lat: b.latitude, lon: b.longitude)
        guard la.isValid, lb.isValid else { return }
        let zoom = Landmarks.zoom(metersPerPoint: Geo.hav(la, lb) / 100, latitude: (la.lat + lb.lat) / 2)
        model.mapCamera.setZoom(zoom)
        guard !labels.landmarks.isEmpty else { labels.show([]); return }
        let corners = [CGPoint(x: view.minX, y: view.minY), CGPoint(x: view.maxX, y: view.minY),
                       CGPoint(x: view.minX, y: view.maxY), CGPoint(x: view.maxX, y: view.maxY)]
        let geo = corners.compactMap { proxy.convert($0, from: .global) }.map { LatLon(lat: $0.latitude, lon: $0.longitude) }
        guard geo.count >= 2, let box = GeoBox(geo) else { return }
        var cands: [Landmarks.Candidate] = []
        for m in Landmarks.visible(labels.landmarks, zoom: zoom, in: box) {
            if let p = proxy.convert(m.coord.cl, to: .global) { cands.append(.init(landmark: m, x: Double(p.x), y: Double(p.y))) }
        }
        let placed = cands.isEmpty ? [] : Landmarks.place(cands, zoom: zoom, scale: scale, viewport: LabelRect(view),
                                                          obstacles: labelObstacles(proxy, view: view))
        labels.show(placed)
    }

    /// Screen boxes no name may cover: every stop (the web's 13 pt square; favorite stars and rings larger) and, on the
    /// iPhone also, the trip's stop labels, you at the boarding stop, the destination marker, your location and the
    /// locate button. Buses are left out on purpose, as on the web: they move every poll, so names would blink in and
    /// out as buses pass (and the CI screenshots would depend on where the simulated buses happen to be); buses are
    /// drawn over the names.
    func labelObstacles(_ proxy: MapProxy, view: CGRect) -> [LabelRect] {
        var out: [LabelRect] = []
        let area = view.insetBy(dx: -40, dy: -40)
        func at(_ p: LatLon, _ w: Double, _ h: Double, dy: Double = 0) {
            guard p.isValid, let s = proxy.convert(p.cl, to: .global), area.contains(s) else { return }
            out.append(LabelRect(centerX: Double(s.x), centerY: Double(s.y) + dy, width: w, height: h))
        }
        let ring = ringed
        for s in model.mapLayers.stops {
            // StopDot: ring 22 + its 3 pt stroke, star 20, dot 10 + its border (the web's stop circle: 2 x LABEL.STOP_R)
            let d: Double = ring.contains(s.id) ? 26 : s.isFav ? 22 : 2 * Landmarks.stopR
            at(s.stop.coord, d, d)
        }
        if model.activeTrip != nil, let y = model.tripYou {
            // "Board here" / the get-off count: a 24 pt callout 10 pt under its stop (TripStopLabel)
            for l in y.stopLabels { at(l.point, Landmarks.textWidth(l.text, size: 13) + 24, 30, dy: 10 + 15) }
            // "You (est.)" at the boarding stop: the 44 pt marker with its pill above
            if let p = y.point, y.source == .stop { at(p, 90, 70, dy: -12) }
        }
        // the destination balloon above its point, with its title under it
        if let o = plan, let last = o.legs.last, let end = last.walk?.to.coord ?? last.bus?.alight.coord { at(end, 84, 64, dy: -12) }
        if let w = walkOnly, let end = w.last { at(end, 84, 64, dy: -12) }
        if let u = model.user { at(u, 30, 30) }
        if model.detent != .full {   // the locate button, right under the floating chrome (RootView)
            out.append(LabelRect(minX: Double(view.maxX) - 52, minY: Double(view.minY) - 4, maxX: Double(view.maxX) + 8, maxY: Double(view.minY) + 48))
        }
        return out
    }

    /// What the names avoid besides the camera, as one value for `LabelWatcher`: a change lays them out again (a route
    /// shown or hidden, a favorite, a ring, the trip's stop labels, you at the boarding stop, a plan's destination).
    func labelSignature(_ layers: MapLayers, ring: Set<String>, tripLabels: [TripYou.StopLabel], youGuess: LatLon?,
                        plan: TripOption?, walkEnd: LatLon?) -> Int {
        var h = Hasher()
        h.combine(layers.stops.count)
        for s in layers.stops { h.combine(s.id); h.combine(s.isFav) }
        h.combine(ring)
        h.combine(tripLabels)
        h.combine(youGuess)
        if let last = plan?.legs.last { h.combine(last.walk?.to.coord ?? last.bus?.alight.coord) }
        h.combine(walkEnd)
        return h.finalize()
    }
}

/// The map labels' triggers besides the camera's end: a camera moved by the app (fit, fly to, the follow frame), a
/// resized visible map (the sheet settled, the chrome changed), new landmarks, what they avoid, the text size; each
/// lays out now and once the move has settled (`MapLabelModel.layoutSoon`). Its own view, so only this empty view
/// re-runs when they change.
struct LabelWatcher: View {
    let camera: MapCameraModel
    let labels: MapLabelModel
    let signature: Int
    let scale: Double
    let layout: () -> Void
    var body: some View {
        Color.clear
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .onAppear { labels.layoutSoon(layout) }
            .onChange(of: camera.position) { _, _ in labels.layoutSoon(now: false, layout) }
            .onChange(of: camera.visibleRect) { _, _ in labels.layoutSoon(layout) }
            .onChange(of: labels.version) { _, _ in labels.layoutSoon(layout) }
            .onChange(of: signature) { _, _ in labels.layoutSoon(layout) }
            .onChange(of: scale) { _, _ in labels.layoutSoon(layout) }
    }
}

/// A building or place name on the map (spec 11.5, web .sb-lm): `mapLandmark` Semibold in a quiet slate, with a 1.5 pt
/// halo in the land color (four offset copies: SwiftUI has no text stroke), no plate, in exactly the line breaks and
/// the box the Kit placed (each line 1.12 em tall), padded on the side facing its building by the placement's gap.
/// Decorative: never takes a tap and hidden from VoiceOver (stops and buses keep their own labels). Equatable, so a
/// map redraw for a bus move does not redraw the names.
struct LandmarkLabel: View, Equatable {
    let label: PlacedLandmark

    static let haloOffsets: [CGSize] = [CGSize(width: Landmarks.halo, height: 0), CGSize(width: -Landmarks.halo, height: 0),
                                        CGSize(width: 0, height: Landmarks.halo), CGSize(width: 0, height: -Landmarks.halo)]

    var body: some View {
        let size = CGFloat(label.size), lineH = CGFloat(label.size * Landmarks.lineHeightEm)
        let lines = VStack(spacing: 0) {
            ForEach(Array(label.lines.enumerated()), id: \.offset) { item in
                Text(item.element).font(.system(size: size, weight: .semibold)).lineLimit(1).fixedSize().frame(height: lineH)
            }
        }
        ZStack {
            ForEach(0..<Self.haloOffsets.count, id: \.self) { i in
                lines.foregroundStyle(Palette.mapLabelHalo).offset(Self.haloOffsets[i])
            }
            lines.foregroundStyle(Palette.mapLabel)
        }
        .frame(width: CGFloat(label.plateWidth), height: CGFloat(label.plateHeight))
        .padding(.top, CGFloat(label.padTop))
        .padding(.bottom, CGFloat(label.padBottom))
        .padding(.leading, CGFloat(label.padLeading))
        .padding(.trailing, CGFloat(label.padTrailing))
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// The follow camera's triggers: the rider dragging or zooming the map turns it off (`positionedByUser`); a new you,
/// a resized visible map or the follow switch turning on runs the check. Its own view, so only this empty view
/// re-runs when the camera or the sheet moves.
struct FollowWatcher: View {
    let camera: MapCameraModel
    let you: TripYou?
    let check: () -> Void
    var body: some View {
        Color.clear
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .onChange(of: camera.position.positionedByUser) { _, byUser in
                if byUser && camera.follow { camera.follow = false }
            }
            .onChange(of: camera.visibleRect) { _, _ in check() }
            .onChange(of: camera.follow) { _, on in if on { check() } }
            .onChange(of: you) { _, _ in check() }
    }
}

/// A stop (spec 11.4): a `bgCard` circle with its route's color as the stroke (neutral where several routes stop), 8 pt
/// up to zoom 15 and 10 pt from zoom 16; the open or highlighted stop is 16 pt with a 3 pt `tint` ring and, when open,
/// its name; favorites are a white star on a gold disc. 44 pt hit area. Equatable on what it shows (the tap closure is
/// new on every map body, so without this SwiftUI would redraw all stops whenever buses move). Annotation content must
/// not read the model from the environment: MapKit hosts it outside the normal view tree.
struct StopDot: View, Equatable {
    var id: String
    var isFav: Bool
    /// A plan is drawn: favorite stars step back (web map/favorites.js).
    var faded = false
    /// Highlighted (Routes to station candidate or the open stop).
    var ring = false
    /// Zoom 16 and closer: the larger circle.
    var big = false
    var color: Color = Palette.label2
    /// The open stop's name under it (`mapCallout`).
    var name: String? = nil
    var action: () -> Void

    static func == (a: StopDot, b: StopDot) -> Bool {
        a.id == b.id && a.isFav == b.isFav && a.faded == b.faded && a.ring == b.ring && a.big == b.big && a.color == b.color
            && a.name == b.name
    }

    var body: some View {
        Button(action: action) {
            ZStack {
                if isFav {
                    Image(systemName: "star.circle.fill").font(.system(size: 20)).foregroundStyle(.white, Palette.starBadge)
                        .overlay { if ring { Circle().strokeBorder(Palette.tint, lineWidth: 3).frame(width: 26, height: 26) } }
                        .opacity(faded && !ring ? 0.45 : 1)
                } else if ring {
                    Circle().fill(Palette.bgCard).frame(width: 16, height: 16)
                        .overlay(Circle().strokeBorder(Palette.tint, lineWidth: 3))
                        .shadow(color: Palette.shadow.opacity(0.3), radius: 1.5, y: 1)
                } else {
                    Circle().fill(Palette.bgCard).frame(width: big ? 10 : 8, height: big ? 10 : 8)
                        .overlay(Circle().strokeBorder(color, lineWidth: big ? 2.5 : 2))
                }
                if let name {
                    StopNameLabel(text: name).offset(y: 24)
                }
            }
            .frame(width: 44, height: 44)   // 44 pt tap target (web: 44 px halo)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// The open stop's name on the map: `mapCallout` with a land-colored halo.
struct StopNameLabel: View {
    let text: String
    var body: some View {
        let t = Text(text).font(Typo.mapCallout).lineLimit(1).fixedSize()
        ZStack {
            ForEach(0..<LandmarkLabel.haloOffsets.count, id: \.self) { i in
                t.foregroundStyle(Palette.mapLabelHalo).offset(LandmarkLabel.haloOffsets[i])
            }
            t.foregroundStyle(Palette.label)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// A bus on the map (spec 11.4): a 26 pt rounded rectangle in the route color with the short name (never cut; 10 pt
/// over 5 characters), a 2 pt ring (white, near-black in dark mode), a soft shadow, and a notch in the route color on
/// the ring edge turning with the bearing. Numbered buses carry their number inside after a thin divider ("AP/DX │ 2",
/// owner 2026-10-30), never as an overlapping disc. The picked bus has a 3 pt `tint` outline; the bus you ride on a
/// started trip (`youText`) a `tintFill` ring and a "You" pill; a stale bus is drawn at 50%. VoiceOver reads the trip
/// sentence ("You are on Bus 101. Get off in 2 stops: X").
struct BusMarker: View {
    let route: Route?
    let bearing: Double?
    var stale = false
    var youText: String? = nil
    /// "Bus 2": its number when the route shows two or more buses (Kit `BusNumbers`, owner 2026-10-30).
    var number: Int? = nil
    /// The bus picked on its route page (its own times are shown there).
    var picked = false

    var body: some View {
        let text = route?.chipText ?? "Bus"
        let long = text.count > 5
        let fg = Color.badgeText(hex: route?.color)
        // the marker's width (estimated from the text, for the notch's distance from the center)
        let w = max(32, CGFloat(text.count) * (long ? 6.4 : 7.2) + 14 + (number != nil ? 16 : 0))
        let shape = RoundedRectangle(cornerRadius: Radius.busMarker, style: .continuous)
        ZStack {
            if let bearing {
                let rad = bearing * .pi / 180
                let reach = 19 + max(0, w / 2 - 15) * CGFloat(abs(sin(rad)))
                Image(systemName: "triangle.fill")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(Color(hex: route?.color))
                    .offset(y: -reach)
                    .rotationEffect(.degrees(bearing))
            }
            HStack(spacing: 4) {
                Text(text).font(long ? Typo.mapBadgeLong : Typo.mapBadge).lineLimit(1).fixedSize()
                if let number {
                    Rectangle().fill(fg.opacity(0.4)).frame(width: 1, height: 12)
                    Text("\(number)").font(Typo.mapBadge).monospacedDigit().fixedSize()
                }
            }
            .foregroundStyle(fg)
            .padding(.horizontal, 7)
            .frame(minWidth: 32, minHeight: 26)
            .background(Color(hex: route?.color), in: shape)
            // the 2 pt ring outside the badge
            .padding(2)
            .background(Palette.busRing, in: RoundedRectangle(cornerRadius: Radius.busMarker + 2, style: .continuous))
            .overlay {
                if youText != nil {
                    RoundedRectangle(cornerRadius: Radius.busMarker + 6, style: .continuous)
                        .strokeBorder(Palette.tintFill, lineWidth: 3).padding(-4)
                } else if picked {
                    RoundedRectangle(cornerRadius: Radius.busMarker + 6, style: .continuous)
                        .strokeBorder(Palette.tint, lineWidth: 3).padding(-4)
                }
            }
            .shadow(color: Palette.shadow.opacity(0.3), radius: 1.5, y: 1)
            if youText != nil {
                YouPill(text: "You").offset(y: -32)
            }
        }
        .opacity(stale ? 0.5 : 1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel((youText ?? (number.map { "Bus \($0), \(route?.displayName ?? "Shuttle")" } ?? "\(route?.displayName ?? "Shuttle") bus"))
                            + (picked ? ", showing its times" : "") + (stale ? ", location may be old" : ""))
    }
}

/// The small "You" pill (`tintFill`, white text 4.7:1; the word carries the meaning, not the color).
struct YouPill: View {
    let text: String
    var body: some View {
        Text(text)
            .font(Typo.mapBadge)
            .lineLimit(1)
            .fixedSize()
            .foregroundStyle(Palette.onFill)
            .padding(.horizontal, 7).frame(minHeight: 18)
            .background(Palette.tintFill, in: Capsule())
            .overlay(Capsule().strokeBorder(.white, lineWidth: 1.5))
            .shadow(color: Palette.shadow.opacity(0.25), radius: 1.5, y: 1)
    }
}

/// You on a started trip as a marker of its own (web map.js renderYou): the boarding stop as a guess (no GPS: a dashed
/// hollow ring, pill "You (est.)"), or the bus you ride while its marker is not drawn (a filled dot, pill "You").
struct YouMarker: View {
    let guess: Bool
    var body: some View {
        ZStack {
            if guess {
                Circle().fill(Palette.bgCard).frame(width: 22, height: 22)
                    .overlay(Circle().stroke(Palette.tintFill, style: StrokeStyle(lineWidth: 3, dash: [4, 3])))
            } else {
                Circle().fill(Palette.tintFill).frame(width: 18, height: 18).overlay(Circle().strokeBorder(.white, lineWidth: 3))
            }
            YouPill(text: guess ? "You (est.)" : "You").offset(y: -24)
        }
        .frame(width: 44, height: 44)
        .shadow(color: Palette.shadow.opacity(0.25), radius: 1.5, y: 1)
    }
}

/// A trip callout under one of the trip's stops ("Board here", "Get off in 2 stops"; spec 11.4): a 24 pt `tintFill`
/// capsule with `onFill` text and a 6 pt pointer up to its stop.
struct TripStopLabel: View {
    let text: String
    var body: some View {
        VStack(spacing: 0) {
            CalloutPointer().fill(Palette.tintFill).frame(width: 12, height: 6)
            Text(text)
                .font(Typo.mapCallout)
                .lineLimit(1)
                .fixedSize()
                .foregroundStyle(Palette.onFill)
                .padding(.horizontal, 10)
                .frame(height: 24)
                .background(Palette.tintFill, in: Capsule())
        }
        .shadow(color: Palette.shadow.opacity(0.25), radius: 1.5, y: 1)
        .dynamicTypeSize(...DynamicTypeSize.xxLarge)
    }
}

/// The callout's pointer: a small triangle pointing up.
struct CalloutPointer: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.midX, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX, y: r.maxY))
        p.closeSubpath()
        return p
    }
}

/// Your location (spec 11.4): an 18 pt `tintFill` dot with a 3 pt white ring and an accuracy halo; with `heading` (the
/// real location while the compass reads), the heading cone behind it (web css .sb-mecone): a `tintFill` wedge fading
/// outward, `UserHeading.spread` wide, pointing the way the phone faces. Annotations stay upright on a rotated map, so
/// the cone turns by the compass minus the map's rotation; the turn animates the short way (Kit `HeadingCone.unwrap`),
/// not at all under Reduce Motion.
struct UserDot: View {
    var heading: UserHeading? = nil
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            if let h = heading, h.active {
                HeadingWedge(spread: h.spread)
                    .fill(RadialGradient(colors: [Palette.tintFill.opacity(0.35), Palette.tintFill.opacity(0.15), Palette.tintFill.opacity(0)],
                                         center: .center, startRadius: 6, endRadius: 46))
                    .frame(width: 92, height: 92)
                    .rotationEffect(.degrees(h.turn - h.mapTurn))
                    .animation(reduceMotion ? nil : .linear(duration: 0.15), value: h.turn - h.mapTurn)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
            Circle().fill(Palette.tintFill.opacity(0.10)).frame(width: 40, height: 40)
                .overlay(Circle().strokeBorder(Palette.tintFill.opacity(0.25), lineWidth: 1))
            Circle().fill(Palette.tintFill).frame(width: 18, height: 18)
                .overlay(Circle().strokeBorder(.white, lineWidth: 3))
                .shadow(color: Palette.shadow.opacity(0.3), radius: 1.5, y: 1)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("My location")
    }
}

/// A wedge from the center to the edge, `spread` degrees wide, pointing up (north on an unrotated map). Built from
/// points (not `addArc`, whose clockwise flag reads backwards in SwiftUI's flipped coordinates).
struct HeadingWedge: Shape {
    var spread: Double

    func path(in rect: CGRect) -> Path {
        let c = CGPoint(x: rect.midX, y: rect.midY), r = min(rect.width, rect.height) / 2
        var p = Path()
        p.move(to: c)
        let steps = 24
        for i in 0...steps {
            let a = (-spread / 2 + spread * Double(i) / Double(steps)) * .pi / 180   // 0 = up, clockwise
            p.addLine(to: CGPoint(x: c.x + r * sin(a), y: c.y - r * cos(a)))
        }
        p.closeSubpath()
        return p
    }
}
