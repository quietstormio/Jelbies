//
//  MoveLog.swift
//  avoid-r1, phase 0 (2026-11-21). The "awkward moments" logger: how often does a body move in a way that reads as a reaction instead of an avoidance. LOGGING ONLY, no behaviour.
//  Off unless launched with `-MoveLog 1` (DevArgs builds; remembered in UserDefaults key "MoveLog" until `-MoveLog 0`). The headless harness sets `MoveLog.on = true` directly: same code, same numbers.
//  Counts per minute of game time, all bodies together (a body is sampled once per brain tick):
//    push     walk steps the floor rules / the peer spring moved by more than 1 cm (`planWalkStep`: the resolve of the planned step differs from the plan)
//    hard     hard stops: the speed over 0.2 s fell by more than 70 % against the 0.2 s before, mid-walk (> 0.5 u from the goal)
//    back     backward travel: velocity > 120 deg off the facing at > 0.3 u/s for more than 0.2 s (one event per episode)
//    side     sideways travel: velocity 60...120 deg off the facing at > 0.3 u/s for more than 0.2 s (one event per episode)
//    overlap  two non-paired bodies whose drawn skins overlap (ContactField gap < 0; the centre distance below 0.5 of the gap where no profile exists): one event per overlap
//    pinned   walks that ended by the stuck rules: no root progress (stuckT), the walk timeout, the 3 s stall re-pick, the steering give-up
//  and the 3x3 floor coverage grid (rows back .. front, columns left .. right of the roaming floor): the share of body time and of emote time (an idle move or a social) in each cell.
//  Lines go to Documents/movelog.txt (copy off the phone like micbench.log:
//    devicectl device copy from --domain-type appDataContainer --domain-identifier io.mgsllc.BobV1 --source Documents/movelog.txt --destination <path>)
//  and as `[melon] movelog ...` to the console. `pace` = game seconds per wall second of the window (the real-app check: >= 25 / 30 = 0.83, else the run is starved).
//

import Foundation
import QuartzCore
import simd

@MainActor
final class MoveLog {
    nonisolated(unsafe) static var on = false
    nonisolated(unsafe) static var writeFile = true
    static let shared = MoveLog()
    nonisolated deinit {}
    /// Free text put in every line (the harness / the take: "home happy", "park").
    var tag = ""
    var url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("movelog.txt")

    enum Kind: Int { case push, hard, back, side, overlap, pinned }
    static let names = ["push", "hard", "back", "side", "overlap", "pinned"]

    struct Totals {
        var n = [Int](repeating: 0, count: 6)
        var bodySec = [Float](repeating: 0, count: 9), emoteSec = [Float](repeating: 0, count: 9)
        var walkSec: Float = 0, gameSec: Float = 0
    }
    private(set) var total = Totals()
    private var window = Totals()
    private var windowWall = CACurrentMediaTime()
    private var minute = 0

    private struct Body {
        var clock: Float = 0
        var hist: [SIMD2<Float>] = []
        var sideT: Float = 0, backT: Float = 0, sideDone = false, backDone = false, hardCool: Float = 0
        var overlapping: Set<Int> = []
    }
    private var bodies: [Int: Body] = [:]
    private var clock: Float = 0, lastFlush: Float = 0

    static func configure(defaults: UserDefaults = .standard, devArgs: Bool = DevArgs.enabled) {
        guard devArgs else { on = false; return }
        let v = defaults.object(forKey: "MoveLog") != nil && defaults.bool(forKey: "MoveLog")
        defaults.set(v, forKey: "MoveLog")
        on = v
        if v { shared.reset(); shared.line("start") }
    }

    func reset() { total = Totals(); window = Totals(); bodies = [:]; clock = 0; lastFlush = 0; minute = 0; windowWall = CACurrentMediaTime() }

    /// A counted moment from the walk code (a push, a pinned walk).
    static func note(_ k: Kind) { guard on else { return }; shared.total.n[k.rawValue] += 1; shared.window.n[k.rawValue] += 1 }

    private func cell(_ p: SIMD2<Float>) -> Int {
        var lo = SIMD2<Float>(-3, -3), hi = SIMD2<Float>(3, 3)
        if let f = GameCamera.roamFloor { let b = f.bounds; lo = b.min; hi = b.max }
        let cx = min(2, max(0, Int((p.x - lo.x) / max(hi.x - lo.x, 0.1) * 3))), cz = min(2, max(0, Int((p.y - lo.y) / max(hi.y - lo.y, 0.1) * 3)))
        return cz * 3 + cx
    }

    /// Once per brain tick (the end of `BlobBrain.tick`).
    func sample(_ b: BlobBrain, dt: Float) {
        guard b.enabled, !b.held else { return }
        var s = bodies[b.steerID] ?? Body()
        s.clock += dt
        if s.clock > clock { let adv = s.clock - clock; clock = s.clock; total.gameSec += adv; window.gameSec += adv }
        let p = b.position, c = cell(p)
        total.bodySec[c] += dt; window.bodySec[c] += dt
        if (b.idleState.kind != nil && b.idleState.kind != .sleep) || b.social != nil { total.emoteSec[c] += dt; window.emoteSec[c] += dt }
        var goal: SIMD2<Float>?
        if case .walk(let g, _) = b.script, b.activity == .walking || b.activity == .coming, b.social == nil { goal = g }
        if let g = goal {
            total.walkSec += dt; window.walkSec += dt
            s.hist.append(p); if s.hist.count > 25 { s.hist.removeFirst() }
            let h = s.hist, yawDir = SIMD2<Float>(sinf(b.yaw), cosf(b.yaw))
            var sideNow = false, backNow = false
            if h.count >= 7 {
                let v = (h[h.count - 1] - h[h.count - 7]) / 0.1, sp = simd_length(v)
                if sp > 0.3 {
                    let ang = acosf(max(-1, min(1, simd_dot(v / sp, yawDir)))) * 180 / .pi
                    sideNow = ang >= 60 && ang <= 120; backNow = ang > 120
                }
            }
            if sideNow { s.sideT += dt; if s.sideT > 0.2, !s.sideDone { s.sideDone = true; Self.note(.side) } } else { s.sideT = 0; s.sideDone = false }
            if backNow { s.backT += dt; if s.backT > 0.2, !s.backDone { s.backDone = true; Self.note(.back) } } else { s.backT = 0; s.backDone = false }
            s.hardCool -= dt
            if h.count >= 25, s.hardCool <= 0, simd_distance(p, g) > 0.5 {
                let v1 = simd_distance(h[24], h[12]) / 0.2, v0 = simd_distance(h[12], h[0]) / 0.2
                if v0 > 0.5, v1 < 0.3 * v0 { Self.note(.hard); s.hardCool = 0.5 }
            }
        } else { s.hist.removeAll(keepingCapacity: true); s.sideT = 0; s.backT = 0; s.sideDone = false; s.backDone = false }
        // overlaps: this body against the higher ids (each pair once)
        for o in b.socialOthers() where o !== b && o.steerID > b.steerID && o.enabled {
            if b.social != nil && b.social === o.social { s.overlapping.remove(o.steerID); continue }
            if b.isPerched || o.isPerched { s.overlapping.remove(o.steerID); continue }
            let g: Float = ContactField.gap(b.steerID, o.steerID, features: false) ?? (simd_distance(b.position, o.position) - 0.5 * b.peerGap)
            if g < 0 { if s.overlapping.insert(o.steerID).inserted { Self.note(.overlap) } } else { s.overlapping.remove(o.steerID) }
        }
        bodies[b.steerID] = s
        if clock - lastFlush >= 60 { flush() }
    }

    private func rates(_ t: Totals, minutes: Float) -> String {
        zip(Self.names, t.n).map { "\($0) \(String(format: "%.1f", Float($1) / max(minutes, 0.01)))" }.joined(separator: " ")
    }
    private func gridText(_ t: Totals) -> String {
        func g(_ v: [Float]) -> String {
            let sum = max(v.reduce(0, +), 0.001)
            return (0..<3).map { r in (0..<3).map { String(format: "%2.0f", v[r * 3 + $0] / sum * 100) }.joined(separator: " ") }.joined(separator: " / ")
        }
        return "body% [\(g(t.bodySec))] emote% [\(g(t.emoteSec))]"
    }

    /// The report of the whole run so far, per minute of game time.
    var summary: String { "movelog \(tag) \(String(format: "%.1f", total.gameSec / 60)) min | \(rates(total, minutes: total.gameSec / 60)) | walk \(String(format: "%.0f", total.walkSec)) s | \(gridText(total))" }

    private func flush() {
        minute += 1
        let wall = Float(CACurrentMediaTime() - windowWall)
        line("min \(minute) | \(rates(window, minutes: window.gameSec / 60)) | walk \(String(format: "%.0f", window.walkSec)) s | pace \(String(format: "%.2f", window.gameSec / max(wall, 0.01))) | \(gridText(window))")
        window = Totals(); windowWall = CACurrentMediaTime(); lastFlush = clock
    }

    func line(_ s: String) {
        let text = "\(tag.isEmpty ? "" : tag + " | ")\(s)"
        print("[melon] movelog \(text)")
        guard Self.writeFile, let d = (text + "\n").data(using: .utf8) else { return }
        if let h = try? FileHandle(forWritingTo: url) { h.seekToEndOfFile(); h.write(d); try? h.close() } else { try? d.write(to: url) }
    }
}
