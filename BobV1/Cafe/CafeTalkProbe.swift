//
//  CafeTalkProbe.swift
//  Dev log for the café table after the meal (`-CafeTalkLog 1`, dev builds only): once per game second per body, "[cafetalk]" with the distance from its stand,
//  the yaw error against the facing it should keep (+ the body twist), what it is doing; and a count of the chirp requests by source. Capture / test aid only.
//

import Foundation
import simd

@MainActor
final class CafeTalkProbe {
    static let shared = CafeTalkProbe()
    static var on: Bool { DevArgs.enabled && UserDefaults.standard.integer(forKey: "CafeTalkLog") != 0 }
    var clock: Float = 0
    var next: Float = 0
    var started = false
    var chirps: [String: Int] = [:]

    func reset() { clock = 0; next = 0; started = false; chirps = [:] }

    func tick(_ care: GameCare, _ actors: [JellyActor], dt: Float) {
        guard Self.on else { return }
        let ph = care.cafe.phase
        guard ph == .cheer || ph == .lounge || ph == .done else { if ph != .eating { reset() }; return }
        if !started {
            started = true
            AudioHub.requestSrcTap = { what, jelly in
                guard what.hasPrefix("chirp:") else { return }
                let src = String(what.split(separator: "@").last ?? "?")
                Task { @MainActor in CafeTalkProbe.shared.chirps[src, default: 0] += 1 }
            }
        }
        clock += dt
        guard clock >= next else { return }
        next += 1
        for a in actors {
            guard let b = a.brain, let st = care.cafeBook.stands[a.id] else { continue }
            let want = care.cafeBook.chatYaw[a.id] ?? b.faceCameraYaw()
            let d = simd_distance(GameCare.floorPos(b, a.sim), st)
            let e = abs(GameCare.wrapAngle(b.yaw + b.twist - want))
            NSLog("[cafetalk] t=%.1f phase=%@ id=%d dist=%.3f yawErr=%.3f act=%@ idle=%@ feet=%d chirps=%@", clock, "\(ph)", a.id, d, e, "\(b.activity)", b.idleState.kind?.rawValue ?? "-", b.feet.active ? 1 : 0, "\(chirps.sorted { $0.key < $1.key })")
        }
    }
}
