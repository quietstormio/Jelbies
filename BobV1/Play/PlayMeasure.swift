//
//  PlayMeasure.swift
//  Capture aid (play-spread-r3, simulator logs only, `-PlayLog 1` or `-PlayDemo 1`): whether the Jelmiko keep their faces to the camera while a ball is live, and from where each touch's ball came relative to the toucher's facing.
//    [camface]  every 0.5 s: phase, bout flag, each Jelmiko's angle between his visible heading and the line to the camera (0 = facing me, 180 = back to me)
//    [ballfrom] every touch: the angle between the toucher's visible heading and the direction the ball came from (where it was 0.35 s before); 0 when it came straight down
//  Read-only: no state of the game is touched.
//

import Foundation
import simd

@MainActor
enum PlayMeasure {
    static var on: Bool { DevArgs.enabled && (UserDefaults.standard.integer(forKey: "PlayLog") > 0 || UserDefaults.standard.integer(forKey: "PlayDemo") > 0) }
    private static var hist: [(t: Float, p: SIMD2<Float>)] = []
    private static var lastLog: Float = -9

    /// The heading the eye sees (in a jump the body's heading is the hop's attractor).
    static func heading(_ j: PlayJelly) -> Float {
        if j.brain.idleState.kind == .tossHeader { let af = j.sim.attractor.rotation.act(SIMD3<Float>(0, 0, 1)); return atan2f(af.x, af.z) }
        return j.brain.yaw
    }
    static func angle(_ a: Float, _ b: Float) -> Float { abs(wrapAngle(a - b)) * 180 / .pi }

    private static var wasWalking: [Int: Bool] = [:]
    static func tick(_ p: PlayToss, dt: Float) {
        guard on else { return }
        for j in p.jellies {          // (beach-aim-r1: every start of a walk, whoever sent it)
            var w = false; if case .walk = j.brain.script { w = true }
            if w, wasWalking[j.id] != true { NSLog("[walkstart] clock=%.3f id=%d phase=%@ bout=%d kind=%@ act=%@ script=%@ pos=(%.2f,%.2f)", p.clock, j.id, String(describing: p.phase), p.bout.active ? 1 : 0, String(describing: j.brain.idleState.kind), String(describing: j.brain.activity), String(String(describing: j.brain.script).prefix(60)), j.pos.x, j.pos.y) }
            wasWalking[j.id] = w
        }
        hist.append((p.clock, SIMD2(p.ball.pos.x, p.ball.pos.z)))
        if hist.count > 40 { hist.removeFirst(hist.count - 40) }
        guard p.phase == .flying || p.phase == .loose, p.clock - lastLog >= 0.5 else { return }
        lastLog = p.clock
        let cam = p.playerPoint()
        let angs = p.jellies.map { j -> String in
            let d = cam - j.pos
            var walking = false; if case .walk = j.brain.script { walking = true }          // (beach-aim-r1: a letter w = he is on a walk goal)
            return String(format: "%d:%.0f%@%@", j.id, angle(heading(j), atan2f(d.x, d.y)), walking ? "w" : "", j.free ? "f" : "")
        }
        NSLog("[camface] clock=%.2f phase=%@ bout=%d n=%d angs=%@", p.clock, p.phase == .flying ? "flying" : "loose", p.bout.active ? 1 : 0, p.jellies.count, angs.joined(separator: ","))
    }

    static func touch(_ p: PlayToss, _ kind: String, _ j: PlayJelly) {
        guard on else { return }
        let from = hist.last(where: { $0.t <= p.clock - 0.35 })?.p ?? SIMD2(p.ball.pos.x, p.ball.pos.z)
        let off = from - j.pos
        let a: Float = simd_length(off) < 0.4 ? 0 : angle(heading(j), atan2f(off.x, off.y))
        let camV = p.playerPoint() - j.pos
        let camA: Float = simd_length(camV) > 1e-3 ? angle(heading(j), atan2f(camV.x, camV.y)) : 0
        NSLog("[bodycam] clock=%.3f kind=%@ id=%d free=%d ang=%.1f", p.clock, kind, j.id, j.free ? 1 : 0, camA)
        NSLog("[ballfrom] clock=%.3f kind=%@ id=%d n=%d free=%d bout=%d ang=%.1f", p.clock, kind, j.id, p.jellies.filter { !$0.free }.count, j.free ? 1 : 0, p.bout.active ? 1 : 0, a)
    }
}
