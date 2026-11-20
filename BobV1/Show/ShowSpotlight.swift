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
    /// The body the spotlight wants lit right now (an actor id): only inside a performer's own window (his pick + trick at the middle, an entrant's trick at the middle, the dance), never while anyone walks; nil between turns and in the rounds that have no light (Look, Results, the wide walk-on).
    var showSpotTarget: Int? {
        guard show.active, show.onStage, let s = show.sim else { return nil }
        guard let id = showSpotCandidate(s), let a = showBook.actors.first(where: { $0.id == id }) ?? showBook.extra.first(where: { $0.id == id }) else { return nil }
        // never a light on an empty middle or on someone still walking to it: the performer must stand at the centre
        let c = a.sim.centroid()          // (the body's own position: a borrowed entrant's `floor` is her far-off home spot)
        // the gate is for switching ON only: once lit he keeps it for his whole window, even when his trick carries him off the middle (a hop, a moonwalk)
        let alreadyLit = showBook.spot.target == id && showBook.spot.shown == id
        if show.round != .dance, !alreadyLit, simd_distance(SIMD2(c.x, c.z), ShowStage.playerSpot) > Self.spotArrive { return nil }
        return id
    }
    static let spotArrive: Float = 0.7
    private func showSpotCandidate(_ s: ShowSim) -> Int? {
        switch show.round {
        case .look: return nil
        case .dance: return show.beat == .dancing ? showBook.performers.first : nil          // (on while the dance runs, off when it ends)
        case .trick, .results:
            if show.round == .trick && show.trickEntering { return nil }
            switch show.trickStage {
            case .pick: return (show.round == .trick && !s.tricksDone) ? showBook.performers.first : nil
            case .performing: return showBook.performers.first
            case .rivals:
                switch show.rivalStep {
                case .perform: return show.rivalTurn.flatMap { showBook.rivalBody[$0] }          // (the light is a per-turn event: on only while the entrant stands at the middle doing her trick)
                case .walkIn, .playerBack, .playerAway, .walkOut: return nil
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
        let before = showBook.spot.target
        showBook.spot.step(target: t, dt: dt)
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
    /// The projected box of the body (nil when none is lit).
    func showSpotShape(size: CGSize) -> ShowSpotlightShape? {
        guard let f = showFrame, let a = showSpotActor else { return nil }
        let c = showBook.spot.anchor ?? a.sim.centroid()
        let H = BobShape.H, R = BobShape.R
        let mid = StageProject.point(SIMD2(c.x, c.z), y: c.y, frame: f, size: size)
        let top = StageProject.point(SIMD2(c.x, c.z), y: c.y + H * 0.5, frame: f, size: size)
        let bot = StageProject.point(SIMD2(c.x, c.z), y: c.y - H * 0.5, frame: f, size: size)
        let side = StageProject.point(SIMD2(c.x + R, c.z), y: c.y, frame: f, size: size)
        let floor = StageProject.point(SIMD2(c.x, c.z), y: 0, frame: f, size: size)
        return ShowSpotlightShape(centre: mid, halfW: abs(side.x - mid.x), halfH: max(abs(bot.y - top.y) / 2, 8), floor: floor)
    }
}

/// The light layer. It never takes touches and sits under the chrome.
struct ShowSpotlightLayer: View {
    let care: GameCare
    var body: some View {
        return GeometryReader { g in
            TimelineView(.animation(minimumInterval: nil, paused: false)) { _ in
                let st = care.showBook.spot
                let level = Double(st.level)
                let scale = care.show.round == .dance ? ShowSpotlightShape.danceScale : 1
                Canvas { ctx, size in
                    guard level > 0.001, let sh = care.showSpotShape(size: size) else { return }
                    let a = level * scale
                    let full = CGRect(origin: .zero, size: size)
                    // 1. the dim: black over everything, a soft elliptical hole round the body (clear over the whole body), and a faint cone of less dim from above
                    ctx.drawLayer { l in
                        l.fill(Path(full), with: .color(.black.opacity(ShowSpotlightShape.dim * a)))
                        l.blendMode = .destinationOut
                        // the cone: narrow at the top of the picture, as wide as the light's hole at the body
                        let topY: CGFloat = -20
                        let cone = Path { p in
                            p.move(to: CGPoint(x: sh.centre.x - sh.outer.width * 0.30, y: topY))
                            p.addLine(to: CGPoint(x: sh.centre.x + sh.outer.width * 0.30, y: topY))
                            p.addLine(to: CGPoint(x: sh.centre.x + sh.outer.width * 0.62, y: sh.centre.y))
                            p.addLine(to: CGPoint(x: sh.centre.x - sh.outer.width * 0.62, y: sh.centre.y))
                            p.closeSubpath()
                        }
                        l.fill(cone, with: .linearGradient(Gradient(colors: [.white.opacity(0.0), .white.opacity(0.30)]),
                                                            startPoint: CGPoint(x: sh.centre.x, y: topY), endPoint: CGPoint(x: sh.centre.x, y: sh.centre.y)))
                        // the hole: a circle gradient squashed into the body's ellipse
                        var h = l
                        h.translateBy(x: sh.centre.x, y: sh.centre.y)
                        h.scaleBy(x: sh.outer.width, y: sh.outer.height)
                        let k = Double(sh.inner.width / sh.outer.width)
                        h.fill(Path(ellipseIn: CGRect(x: -1, y: -1, width: 2, height: 2)),
                               with: .radialGradient(Gradient(stops: [.init(color: .white, location: 0), .init(color: .white, location: k),
                                                                      .init(color: .white.opacity(0.35), location: k + (1 - k) * 0.45), .init(color: .white.opacity(0), location: 1)]),
                                                     center: .zero, startRadius: 0, endRadius: 1))
                    }
                    // 2. the pool of light on the floor under him (a pale ring-shaped ellipse that stays on the floor when he hops: clear over his body and feet, strongest just
                    //    outside them), and his body + feet cut out of it with a soft edge, so his own colours are not lightened and no dark disc shows round him
                    ctx.drawLayer { l in
                        let warm = Color(red: 1, green: 0.95, blue: 0.78)
                        var p = l
                        p.translateBy(x: sh.floor.x, y: sh.floor.y)
                        p.scaleBy(x: sh.pool.width, y: sh.pool.height)
                        p.blendMode = .plusLighter
                        p.fill(Path(ellipseIn: CGRect(x: -1, y: -1, width: 2, height: 2)),
                               with: .radialGradient(Gradient(stops: [.init(color: warm.opacity(0), location: 0), .init(color: warm.opacity(0), location: 0.5),
                                                                      .init(color: warm.opacity(0.32 * a), location: 0.72), .init(color: warm.opacity(0), location: 1)]),
                                                     center: .zero, startRadius: 0, endRadius: 1))
                        var b = l
                        b.blendMode = .destinationOut
                        let topY = sh.centre.y - sh.halfH * 1.06, botY = max(sh.floor.y + sh.halfW * 0.22, sh.centre.y + sh.halfH * 1.06)
                        b.translateBy(x: sh.centre.x, y: (topY + botY) / 2)
                        b.scaleBy(x: sh.halfW * 1.25, y: (botY - topY) / 2 * 1.08)
                        b.fill(Path(ellipseIn: CGRect(x: -1, y: -1, width: 2, height: 2)),
                               with: .radialGradient(Gradient(stops: [.init(color: .white, location: 0), .init(color: .white, location: 0.8), .init(color: .white.opacity(0), location: 1)]),
                                                     center: .zero, startRadius: 0, endRadius: 1))
                    }
                }
                .drawingGroup(opaque: false)
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
