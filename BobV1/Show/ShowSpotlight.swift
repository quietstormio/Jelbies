//
//  ShowSpotlight.swift
//  The Jelly Show's spotlight (2026-11-19, the owner: "Do like a spotlight when it's the Jelmikos turn and they're centered").
//  While one contestant performs (his pick, his trick, an entrant's turn, the Dance round) a soft pool of light sits on the stage floor under him, a faint cone
//  falls from above, and the rest of the picture (the floor, the curtains, the waiting entrants) dims.
//  Drawn as ONE SwiftUI Canvas between the 3D view and the chrome (no extra render pass): a black layer with a soft elliptical hole round his projected body, a pale
//  pool on the floor with his body cut out of it. The hole is clear over the whole body, so his own colours are never touched; the chrome is above it all.
//

import SwiftUI
import simd
import QuartzCore

/// Which body is lit and how much: it fades out (0.4 s) before it moves to another body, then fades in (0.4 s).
nonisolated struct ShowSpotlightState: Equatable {
    /// The actor id the rules want lit now (nil = nobody) and the one actually lit.
    var target: Int?
    var shown: Int?
    /// 0...1 (the dim / the light's strength).
    var level: Float = 0
    /// The light is showing or fading (the layer draws only then).
    var isOn: Bool { level > 0 || target != nil }
    /// Where the light sits (his centroid while he performs; frozen while it fades out, so it never follows him as he walks off).
    var anchor: SIMD3<Float>?
    static let fadeSeconds: Float = 0.4
    mutating func step(target t: Int?, dt: Float) {
        target = t
        if t != shown {
            level = max(0, level - dt / Self.fadeSeconds)
            if level <= 0 { shown = t }
        } else if t != nil {
            level = min(1, level + dt / Self.fadeSeconds)
        } else { level = 0 }
    }
}

/// The picture of the light: pure numbers from the body's projected box, so a test can check it.
nonisolated struct ShowSpotlightShape {
    /// The share the picture is darkened by outside the light, at full level (the owner's "roughly 35-45%").
    static let dim: Double = 0.40
    /// The Dance round's light is gentler.
    static let danceScale: Double = 0.75
    /// Where the body is on screen: its middle, half width, half height (points), and the floor point under it.
    var centre: CGPoint, halfW: CGFloat, halfH: CGFloat, floor: CGPoint
    /// The clear (fully lit) ellipse: the whole body with room for its wobble; the light then fades out to `outer`.
    var inner: CGSize { CGSize(width: halfW * 1.5, height: halfH * 1.45) }
    var outer: CGSize { CGSize(width: halfW * 3.3, height: halfH * 2.7) }
    var pool: CGSize { CGSize(width: halfW * 2.6, height: halfW * 0.8) }
}

extension GameCare {
    /// How a performer is held in the light: `dance` the whole dance; `holdAtCentre` switched on once his walk to the middle has ended there; `holdWherever` switched on once he stands still
    /// (the turn's wait for a late walker ran out: the light goes to HIM, wherever he is); `afterTrick` his score beat: kept only while he is still on the spot, off once he walks away.
    private enum SpotMode { case dance, holdAtCentre, holdWherever, afterTrick }
    /// The light is a spotlight, not a decoration: ON once the performer has arrived and stands still, kept through his trick AND his score beat (also when a hop / moonwalk carries him
    /// off the middle), OFF (0.4 s fade) when he walks off. Never on an empty middle, on someone still walking in, or sliding across the floor to catch him; off in Look, Results and the wide walk-on.
    var showSpotTarget: Int? {
        guard show.active, show.onStage, let s = show.sim, let (id, mode) = showSpotCandidate(s), let a = showSpotBody(id) else { return nil }
        let c = a.sim.centroid()          // (the body's own position: a borrowed entrant's `floor` is her far-off home spot)
        let d = simd_distance(SIMD2(c.x, c.z), ShowStage.playerSpot)
        let latched = showBook.spot.target == id && showBook.spot.shown == id
        switch mode {
        case .dance: return id
        case .afterTrick: return latched && d < Self.spotHold ? id : nil
        case .holdAtCentre: return latched || (!showSpotWalking(a) && d < Self.spotArrive) ? id : nil
        case .holdWherever: return latched || !showSpotWalking(a) ? id : nil
        }
    }
    /// Arrival (the flow's own arrival radius), and how far he may drift from the middle in his score beat before the light lets go.
    static let spotArrive: Float = 0.6, spotHold: Float = 0.45
    /// Is this body still walking (stepping to a goal, or a walk asked for)? The turn to the camera after the walk does not count (it can take seconds and the trick cuts it short). Test seam too.
    func showSpotWalking(_ a: JellyActor) -> Bool {
        guard let b = a.brain else { return false }
        if b.pending != nil { return true }
        if case .walk = b.script { return true }
        return false
    }
    private func showSpotBody(_ id: Int) -> JellyActor? { showBook.actors.first { $0.id == id } ?? showBook.extra.first { $0.id == id } }
    private func showSpotCandidate(_ s: ShowSim) -> (Int, SpotMode)? {
        let player = showBook.performers.first
        switch show.round {
        case .look: return nil
        case .dance: return show.beat == .dancing ? player.map { ($0, .dance) } : nil          // (on while the dance runs, off when it ends)
        case .trick, .results:
            if show.round == .trick && show.trickEntering { return nil }
            switch show.trickStage {
            case .pick: return (show.round == .trick && !s.tricksDone) ? player.map { ($0, .holdWherever) } : nil
            case .performing: return player.map { ($0, .holdWherever) }
            case .rivals:
                let rival = show.rivalTurn.flatMap { showBook.rivalBody[$0] }
                switch show.rivalStep {
                case .walkIn: return rival.map { ($0, .holdAtCentre) }
                case .perform: return rival.map { ($0, .holdWherever) }
                case .walkOut: return rival.map { ($0, .afterTrick) }          // (her score beat: lit while she still stands there, off as she steps away)
                case .playerAway: return player.map { ($0, .afterTrick) }          // (his score beat)
                case .playerBack: return nil
                }
            }
        }
    }
    /// The lit body (nil when none) and its centroid, for the light and the tests.
    var showSpotActor: JellyActor? {
        guard let id = showBook.spot.shown else { return nil }
        return showBook.actors.first { $0.id == id } ?? showBook.extra.first { $0.id == id }
    }
    func showSpotStep(dt: Float) {
        var t = showSpotTarget
        if DevArgs.enabled && UserDefaults.standard.object(forKey: "ShowSpotlight") != nil && UserDefaults.standard.integer(forKey: "ShowSpotlight") == 0 { t = nil }
        let before = showBook.spot.target, wasOn = showBook.spot.isOn
        showBook.spot.step(target: t, dt: dt)
        if wasOn != showBook.spot.isOn { show.nudge() }          // (the layer appears / goes clear; it does not redraw while the light is off)
        #if targetEnvironment(simulator)
        if DevArgs.enabled, before != showBook.spot.target {          // (capture aid: one line per light on / off, with where he stands)
            if let id = showBook.spot.target, let a = showBook.actors.first(where: { $0.id == id }) ?? showBook.extra.first(where: { $0.id == id }) {
                let c = a.sim.centroid()
                print(String(format: "[spotlight] ON actor %d round %@ turn %@ at (%.2f, %.2f), %.2f from the middle, t=%.2f", id, "\(show.round)", "\(show.trickTurnNow.map(String.init) ?? "-")", c.x, c.z, simd_distance(SIMD2(c.x, c.z), ShowStage.playerSpot), CACurrentMediaTime()))
            } else { print(String(format: "[spotlight] OFF t=%.2f", CACurrentMediaTime())) }
        }
        #endif
        if showBook.spot.target == showBook.spot.shown, showBook.spot.shown != nil, let a = showSpotActor { showBook.spot.anchor = a.sim.centroid() }
    }
    /// The projected box of the body (nil when none is lit). One camera for all five points (this runs every frame the light is on).
    func showSpotShape(size: CGSize) -> ShowSpotlightShape? {
        guard let f = showFrame, let a = showSpotActor else { return nil }
        let c = showBook.spot.anchor ?? a.sim.centroid()
        let H = BobShape.H, R = BobShape.R
        let vp = GameCamera.camera(aspect: Float(size.width / max(size.height, 1)), show: 1, showFrame: f).viewProj
        @inline(__always) func pt(_ x: Float, _ y: Float) -> CGPoint {
            let q = vp * SIMD4<Float>(x, y, c.z, 1)
            guard q.w > 1e-4 else { return CGPoint(x: size.width / 2, y: size.height / 2) }
            return CGPoint(x: CGFloat(q.x / q.w * 0.5 + 0.5) * size.width, y: CGFloat(1 - (q.y / q.w * 0.5 + 0.5)) * size.height)
        }
        let mid = pt(c.x, c.y), top = pt(c.x, c.y + H * 0.5), bot = pt(c.x, c.y - H * 0.5), side = pt(c.x + R, c.y), floor = pt(c.x, 0)
        return ShowSpotlightShape(centre: mid, halfW: abs(side.x - mid.x), halfH: max(abs(bot.y - top.y) / 2, 8), floor: floor)
    }
}

/// The drawing, pure (a test renders it): nothing at level 0; the dim with its hole; the cone; the floor pool. All gradients and paths are built once.
nonisolated enum ShowSpotlightPainter {
    nonisolated(unsafe) private static let unitEllipse = Path(ellipseIn: CGRect(x: -1, y: -1, width: 2, height: 2))
    /// The cone in unit space: x -0.30 ... 0.30 at the top (y -1), -0.62 ... 0.62 at the body (y 0); scaled by (hole width, height of the picture above the body).
    nonisolated(unsafe) private static let unitCone: Path = {
        var p = Path(); p.move(to: CGPoint(x: -0.30, y: -1)); p.addLine(to: CGPoint(x: 0.30, y: -1)); p.addLine(to: CGPoint(x: 0.62, y: 0)); p.addLine(to: CGPoint(x: -0.62, y: 0)); p.closeSubpath(); return p
    }()
    nonisolated(unsafe) private static let coneFill = GraphicsContext.Shading.linearGradient(Gradient(colors: [.white.opacity(0), .white.opacity(0.30)]), startPoint: CGPoint(x: 0, y: -1), endPoint: .zero)
    nonisolated(unsafe) private static let holeFill: GraphicsContext.Shading = {
        let k = Double(1.5 / 3.3)          // (inner / outer: `ShowSpotlightShape.inner` / `.outer`)
        return .radialGradient(Gradient(stops: [.init(color: .white, location: 0), .init(color: .white, location: k), .init(color: .white.opacity(0.35), location: k + (1 - k) * 0.45), .init(color: .white.opacity(0), location: 1)]),
                               center: .zero, startRadius: 0, endRadius: 1)
    }()
    nonisolated(unsafe) private static let warm = Color(red: 1, green: 0.95, blue: 0.78)
    nonisolated(unsafe) private static let poolFill = GraphicsContext.Shading.radialGradient(Gradient(stops: [.init(color: warm.opacity(0), location: 0), .init(color: warm.opacity(0), location: 0.5), .init(color: warm.opacity(0.32), location: 0.72), .init(color: warm.opacity(0), location: 1)]),
                                                                       center: .zero, startRadius: 0, endRadius: 1)
    nonisolated(unsafe) private static let cutFill = GraphicsContext.Shading.radialGradient(Gradient(stops: [.init(color: .white, location: 0), .init(color: .white, location: 0.8), .init(color: .white.opacity(0), location: 1)]),
                                                                      center: .zero, startRadius: 0, endRadius: 1)

    static func paint(_ ctx: inout GraphicsContext, size: CGSize, shape sh: ShowSpotlightShape, level: Double, scale: Double) {
        guard level > 0.001 else { return }          // (fully off: nothing is drawn, not even a transparent layer)
        let a = level * scale
        // 1. the dim: black over everything, a soft elliptical hole round the body (clear over the whole body), and a faint cone of less dim from above
        ctx.drawLayer { l in
            l.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.black.opacity(ShowSpotlightShape.dim * a)))
            l.blendMode = .destinationOut
            var c = l
            c.translateBy(x: sh.centre.x, y: sh.centre.y); c.scaleBy(x: sh.outer.width, y: sh.centre.y + 20)
            c.fill(unitCone, with: coneFill)
            var h = l
            h.translateBy(x: sh.centre.x, y: sh.centre.y); h.scaleBy(x: sh.outer.width, y: sh.outer.height)
            h.fill(unitEllipse, with: holeFill)
        }
        // 2. the pool of light on the floor under him (a pale ring-shaped ellipse that stays on the floor when he hops: clear over his body and feet, strongest just outside them),
        //    and his body + feet cut out of it with a soft edge, so his own colours are not lightened and no dark disc shows round him
        ctx.drawLayer { l in
            var p = l
            p.opacity = a
            p.translateBy(x: sh.floor.x, y: sh.floor.y); p.scaleBy(x: sh.pool.width, y: sh.pool.height)
            p.blendMode = .plusLighter
            p.fill(unitEllipse, with: poolFill)
            var b = l
            b.blendMode = .destinationOut
            let topY = sh.centre.y - sh.halfH * 1.06, botY = max(sh.floor.y + sh.halfW * 0.22, sh.centre.y + sh.halfH * 1.06)
            b.translateBy(x: sh.centre.x, y: (topY + botY) / 2); b.scaleBy(x: sh.halfW * 1.25, y: (botY - topY) / 2 * 1.08)
            b.fill(unitEllipse, with: cutFill)
        }
    }

    // dev only: the layer's draw time while it is on, printed every 120 frames (CPU time to record the drawing; the compositing is on the GPU and shows in the usual perf line)
    nonisolated(unsafe) private static var perfSum = 0.0, perfN = 0
    static func perf(_ dt: Double, level: Double) {
        perfSum += dt; perfN += 1
        if perfN >= 120 { print(String(format: "[melon] spotlight layer: %d draws, %.3f ms avg (CPU record), level %.2f", perfN, perfSum / Double(perfN) * 1000, level)); perfSum = 0; perfN = 0 }
    }
}

/// The light layer. It never takes touches and sits under the chrome. Fully off it is a clear view: no TimelineView, no Canvas, no frames (the show's `revision` is nudged when the light
/// switches on and when its fade ends, and the layer subscribes to it).
struct ShowSpotlightLayer: View {
    let care: GameCare
    var body: some View {
        let _ = care.show.revision
        if care.showBook.spot.isOn {
            GeometryReader { g in
                TimelineView(.animation) { _ in
                    let level = Double(care.showBook.spot.level)
                    let scale = care.show.round == .dance ? ShowSpotlightShape.danceScale : 1
                    Canvas { ctx, size in
                        let t0 = DevArgs.enabled ? CACurrentMediaTime() : 0
                        guard let sh = care.showSpotShape(size: size) else { return }
                        ShowSpotlightPainter.paint(&ctx, size: size, shape: sh, level: level, scale: scale)
                        if DevArgs.enabled { ShowSpotlightPainter.perf(CACurrentMediaTime() - t0, level: level) }
                    }
                    .drawingGroup(opaque: false)
                }
            }
            .ignoresSafeArea()
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        } else {
            Color.clear.allowsHitTesting(false).accessibilityHidden(true)
        }
    }
}
