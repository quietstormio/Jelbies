//
//  SmoothDraw.swift
//  smooth-motion-r1 (owner 2026-11-22, ball play: "ensure it's quality use all Apple documentation to make it look smooth").
//
//  DRAWING ONLY. The physics is a fixed 1/60 s step and does not change by one bit; what changes is what is drawn and how many steps a slow frame may run:
//    1. the thrown ball is drawn EVERY frame at a position / rotation interpolated between the last two steps by how far the frame is into the step
//       (on a 120 Hz screen every second frame used to run no step and showed the same pose twice: motion was 60 per second);
//    2. close to a Jelmiko the ball's drawn state leans to the newest step (the bodies are drawn at the newest step: no ball inside a foot or a head);
//    3. a steady 30 / 24 fps frame may run as many steps as the frame interval needs (it ran 2 at most: about 0.8x speed at 24, 0.5x at 30 after a slow frame);
//       a single long hitch is guarded exactly as before.
//  One switch: `-SmoothDraw 0` (or env SMOOTHDRAW_OFF=1) = the game draws and steps exactly as commit 91bcdd4f.
//  Dev aids: `-SmoothLog 1` (a `[smooth]` line once a second, on the phone too), `-SmoothForceFPS n` (pin the display rate; no governor changes),
//  `-SmoothVirtualClock 1` (frames advance a synthetic 1 / rate seconds each: scripted 120 / 60 / 30 / 24 fps runs in the 60 Hz simulator).
//

import Foundation
import QuartzCore
import simd

enum SmoothDraw {
    // MARK: switches
    static var on: Bool = {
        if ProcessInfo.processInfo.environment["SMOOTHDRAW_OFF"] == "1" { return false }
        let d = UserDefaults.standard
        return d.object(forKey: "SmoothDraw") == nil || d.integer(forKey: "SmoothDraw") != 0
    }()
    static let log: Bool = UserDefaults.standard.integer(forKey: "SmoothLog") != 0
    static let forceFPS: Int? = { let n = UserDefaults.standard.integer(forKey: "SmoothForceFPS"); return n > 0 ? n : nil }()
    static let trace: Bool = UserDefaults.standard.integer(forKey: "SmoothTrace") != 0
    static let virtualClock: Bool = UserDefaults.standard.integer(forKey: "SmoothVirtualClock") != 0

    // MARK: the ball: the last two physics steps
    struct Snap { var pos: SIMD3<Float>; var rot: simd_quatf }
    private(set) static var prev: Snap?
    private(set) static var cur: Snap?
    private static var prevPhase: PlayToss.Phase = .off
    private static var curPhase: PlayToss.Phase = .off
    /// How far this frame is into the step after the newest one ran (0...1), set by the stage after its step loop.
    static var alpha: Float = 1
    /// What the last ball mesh was built at (the measuring stick: unchanged between two frames while flying = a repeated pose).
    private(set) static var lastDrawn = SIMD3<Float>(repeating: .nan)

    /// Largest distance the ball may move in one step and still be one continuous path (a throw's start, a header's lift are far less; a teleport is more).
    static let teleport: Float = 1.0
    /// Distance (3D, ball centre to the Jelmiko's upright axis, floor to crown) inside which the ball leans to the newest step. Tight: the kick reach is 1.15 u.
    static let nearFull: Float = 1.2, nearNone: Float = 1.8
    private(set) static var lastWeight: Float = 0

    /// After every fixed step (the stage calls it after `hopTick`): remember the ball's state.
    static func recordStep(_ p: PlayToss) { record(pos: p.ball.pos, rot: p.ball.rot, phase: p.phase) }
    static func record(pos: SIMD3<Float>, rot: simd_quatf, phase: PlayToss.Phase) {
        let s = Snap(pos: pos, rot: rot)
        prev = cur ?? s; prevPhase = curPhase
        cur = s; curPhase = phase
        if let pr = prev, simd_distance(pr.pos, s.pos) > teleport { prev = s }
    }
    /// The ball's speed (u/s) going INTO the step now running (from the last two recorded states); 0 when unknown. The event of a hit is sent after the hit has set the
    /// outgoing velocity, so an impact's strength is read from here.
    static var incomingSpeed: Float {
        guard let p = prev, let c = cur else { return 0 }
        return simd_distance(p.pos, c.pos) * 60
    }
    static func reset() { prev = nil; cur = nil; prevPhase = .off; curPhase = .off; alpha = 1; lastDrawn = SIMD3(repeating: .nan) }

    private static func smooth(_ t: Float) -> Float { let x = min(max(t, 0), 1); return x * x * (3 - 2 * x) }

    /// How much the drawn state leans to the newest step near a Jelmiko (1 = the newest step, 0 = the plain interpolation).
    static func nearWeight(ball: SIMD3<Float>, jellies: [(pos: SIMD2<Float>, top: Float)]) -> Float {
        var w: Float = 0
        for j in jellies {
            let dxz = simd_distance(SIMD2(ball.x, ball.z), j.pos)
            let dy = max(ball.y - j.top, 0)          // above the crown: the distance up to it
            w = max(w, smooth((nearNone - (dxz * dxz + dy * dy).squareRoot()) / (nearNone - nearFull)))
        }
        return w
    }

    /// Pure: the drawn state between two steps. `a` = how far into the step (0 = the older step, 1 = the newest).
    static func blend(_ p: Snap, _ c: Snap, a: Float) -> Snap {
        Snap(pos: p.pos + (c.pos - p.pos) * a, rot: simd_slerp(p.rot, c.rot, a))
    }

    private static func flightLike(_ ph: PlayToss.Phase) -> Bool { ph == .flying || ph == .loose }

    /// The ball as it is DRAWN this frame (the mesh rebuild calls this). Off, or not between two steps of one continuous flight: the physics state itself.
    static func ball(_ p: PlayToss) -> (pos: SIMD3<Float>, rot: simd_quatf) {
        drawn(pos: p.ball.pos, rot: p.ball.rot, jellies: p.jellies.map { (pos: $0.pos, top: $0.headTop) })
    }
    static func drawn(pos: SIMD3<Float>, rot: simd_quatf, jellies: [(pos: SIMD2<Float>, top: Float)]) -> (pos: SIMD3<Float>, rot: simd_quatf) {
        var out = Snap(pos: pos, rot: rot)
        lastWeight = 0
        if on, let pr = prev, let cu = cur, cu.pos == pos, cu.rot == rot, flightLike(prevPhase), flightLike(curPhase), alpha < 1 {
            let w = nearWeight(ball: pos, jellies: jellies); lastWeight = w
            out = blend(pr, cu, a: alpha + (1 - alpha) * w)
        }
        lastDrawn = out.pos
        return (out.pos, out.rot)
    }

    /// True when a frame that ran no step still has to rebuild the ball (it is between two different steps).
    static func wantsBallFrame(_ p: PlayToss) -> Bool {
        guard on, p.ballGame, flightLike(p.phase), let pr = prev, let cu = cur else { return false }
        return pr.pos != cu.pos || pr.rot.vector != cu.rot.vector
    }

    // MARK: steps per frame

    /// How many fixed steps a frame may run. `base` = today's rule (2, or 1 after a frame over 12 ms of CPU). A STEADY low-rate frame (30 / 24 fps, its dt one display
    /// interval, its CPU time well inside the interval) may run what the interval needs (2 at 30, 3 at 24), so the game keeps real speed; a hitch (a dt well over the
    /// interval) or a frame that already costs most of its interval keeps the old cap.
    static func maxSteps(base: Int, dt: Float, fps: Int, stepDt: Float, cpuMs: Double) -> Int {
        guard on, fps >= 20 else { return base }
        let interval = 1 / Float(fps)
        guard dt <= interval * 1.35, cpuMs < Double(interval) * 600 else { return base }
        let need = Int((interval / stepDt - 1e-3).rounded(.up))
        return max(base, min(need, 4))
    }

    // MARK: -SmoothTrace 1: the physics per step (same-seed comparison, switch on against off)
    private static var traceN = 0
    /// One line per fixed step: the ball's physics state and a bit-exact checksum of every body's particles.
    static func traceStep(play p: PlayToss?, bodies: [SoftBody]) {
        traceN += 1
        var sum: UInt64 = 0
        for b in bodies { for v in b.x { sum = sum &* 1099511628211 &+ UInt64(v.bitPattern) } }
        let b = p?.ball
        NSLog("[smoothtrace] %d ball %@ bodies %016llx", traceN, b.map { String(format: "%a %a %a", Double($0.pos.x), Double($0.pos.y), Double($0.pos.z)) } ?? "-", sum)
    }

    // MARK: the `[smooth]` line
    private static var frames = 0, steps = 0, s0 = 0, s1 = 0, s2 = 0, s3 = 0
    private static var flyFrames = 0, sameFrames = 0, leanFrames = 0, sameOutside = 0, outside = 0
    private static var prevFrameDrawn = SIMD3<Float>(repeating: .nan)
    private static var winStart = 0.0

    /// Once per drawn frame, after the step loop and the mesh rebuilds.
    static func frame(steps n: Int, play p: PlayToss?, now: Double, fps: Int, measuredFPS: Double?, stepDt: Float) {
        guard log else { return }
        frames += 1; steps += n
        switch n { case 0: s0 += 1; case 1: s1 += 1; case 2: s2 += 1; default: s3 += 1 }
        if let p, p.ballGame, p.phase == .flying {
            flyFrames += 1
            let same = lastDrawn == prevFrameDrawn
            if same { sameFrames += 1 }
            if lastWeight > 0.02 { leanFrames += 1 } else { outside += 1; if same { sameOutside += 1 } }
        }
        prevFrameDrawn = lastDrawn
        if winStart == 0 { winStart = now }
        let el = now - winStart
        if el >= 1 {
            NSLog("%@", String(format: "[smooth] on %d rate %d (measured %.1f) frames %d steps %d (0/1/2/3+: %d/%d/%d/%d) ball-flying frames %d same-pos %d (%.0f%%; %.0f%% of the %d frames away from every Jelmiko; %d frames leaning to the newest step) game-rate %.3f",
                               on ? 1 : 0, fps, measuredFPS ?? Double(frames) / el, frames, steps, s0, s1, s2, s3, flyFrames, sameFrames,
                               flyFrames > 0 ? Double(sameFrames) / Double(flyFrames) * 100 : 0, outside > 0 ? Double(sameOutside) / Double(outside) * 100 : 0, outside, leanFrames, Double(steps) * Double(stepDt) / el))
            frames = 0; steps = 0; s0 = 0; s1 = 0; s2 = 0; s3 = 0; flyFrames = 0; sameFrames = 0; leanFrames = 0; sameOutside = 0; outside = 0; winStart = now
        }
    }
}
