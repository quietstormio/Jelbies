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
    /// Seconds of game time per window line (60; `-MoveLogSeconds n` shortens it for a starved host, the rates stay per minute).
    nonisolated(unsafe) static var windowSeconds: Float = 60
    var url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("movelog.txt")

    enum Kind: Int { case push, hard, back, side, overlap, pinned }
    static let names = ["push", "hard", "back", "side", "overlap", "pinned"]

    struct Totals {
        var n = [Int](repeating: 0, count: 6)
        var bodySec = [Float](repeating: 0, count: 9), emoteSec = [Float](repeating: 0, count: 9)
        var walkSec: Float = 0, gameSec: Float = 0
        var arrN = 0; var arrSec: Float = 0, arrDist: Float = 0          // (walks that ended within 0.5 u of their goal: their seconds and straight-line metres)
        /// Activity budget seconds: 0 roam leg, 1 walk to an emote / job, 2 plain stand, 3 solo emote, 4 pair emote, 5 group emote, 6 toy / play, 7 lying / sitting / sleeping, 8 waiting (held, stood on a walk), 9 other (eating, touched ...)
        var act = [Float](repeating: 0, count: 11)
        var walkTimes: [Float] = []          // seconds of each walk that arrived
        var stands: [Float] = []          // plain stand episodes (s)
        var bump = [Int](repeating: 0, count: 3)          // body-body contacts of two bodies not in one session: both standing / one walking / both walking
        var pairN = 0, groupN = 0; var pairSec: Float = 0, groupSec: Float = 0          // finished sessions
        var idleSum3 = [Float](repeating: 0, count: 9), idleSum6 = [Float](repeating: 0, count: 36)          // integral of "seconds since a body was last in this cell"
        var idleMax3: Float = 0, idleMax6: Float = 0
        var idleCells3 = 9, idleCells6 = 36
        var quietSec: Float = 0, huddleSec: Float = 0, chainMax: Float = 0          // (move-mix-r1: seconds with nobody in any emote, with every body within 2.5 u of every other, the longest run of pair emotes of the same two (gaps <= 6 s))
        var kindSec: [String: Float] = [:]          // seconds of body time per emote kind (idle kind, or social kind)
        var kinds = Set<String>(), kindCounts: [Int] = []          // (the different emote kinds seen: this run's set; the sizes of the runs folded in)
        var emoteN = 0, walkN = 0          // (move-b-r1: emote starts (an idle move or a social) and walks to a new goal; walkSec / walkN = mean walk time to a goal)
    }
    /// Fold another run's totals in (the harness: several seeds into one table).
    static func add(_ a: inout Totals, _ o: Totals) {
        for k in 0..<a.n.count { a.n[k] += o.n[k] }
        for c in 0..<9 { a.bodySec[c] += o.bodySec[c]; a.emoteSec[c] += o.emoteSec[c]; a.idleSum3[c] += o.idleSum3[c] }
        for c in 0..<36 { a.idleSum6[c] += o.idleSum6[c] }
        for c in 0..<10 { a.act[c] += o.act[c] }
        for c in 0..<3 { a.bump[c] += o.bump[c] }
        for (k, v) in o.kindSec { a.kindSec[k, default: 0] += v }; a.kinds.formUnion(o.kinds); a.quietSec += o.quietSec; a.huddleSec += o.huddleSec; a.chainMax = max(a.chainMax, o.chainMax); a.kindCounts += o.kindCounts.isEmpty ? [o.kinds.count] : o.kindCounts
        a.walkSec += o.walkSec; a.gameSec += o.gameSec; a.emoteN += o.emoteN; a.walkN += o.walkN
        a.arrN += o.arrN; a.arrSec += o.arrSec; a.arrDist += o.arrDist
        a.stands += o.stands; a.walkTimes += o.walkTimes; a.pairN += o.pairN; a.groupN += o.groupN; a.pairSec += o.pairSec; a.groupSec += o.groupSec
        a.idleMax3 = max(a.idleMax3, o.idleMax3); a.idleMax6 = max(a.idleMax6, o.idleMax6)
        a.idleCells3 = o.idleCells3; a.idleCells6 = o.idleCells6
    }
    private(set) var total = Totals()
    /// Seconds per activity of each body (cumulative; the per-body view of the budget).
    private(set) var actBody: [Int: [Float]] = [:]
    /// Seconds per 3 x 3 cell of each body (round 2: every Jelmiko should use the whole floor).
    private(set) var cellBody: [Int: [Float]] = [:]
    private var sess: [ObjectIdentifier: (first: Float, last: Float, group: Bool, pair: Int)] = [:]
    private var chains: [Int: (start: Float, end: Float)] = [:]
    private var lastVisit3 = [Float](repeating: 0, count: 9), lastVisit6 = [Float](repeating: 0, count: 36)
    private var valid3 = [Bool](repeating: true, count: 9), valid6 = [Bool](repeating: true, count: 36), maskKey = ""

    private var window = Totals()
    private var windowWall = CACurrentMediaTime()
    private var minute = 0

    private struct Body {
        var clock: Float = 0
        var hist: [SIMD2<Float>] = []
        var sideT: Float = 0, backT: Float = 0, sideDone = false, backDone = false, hardCool: Float = 0
        var overlapping: Set<Int> = []
        var prevP = SIMD2<Float>.zero, speed: Float = 0, slowT: Float = 0, cat = -1, catT: Float = 0, touching: Set<Int> = []
        var inPlace = false, emoting = false, lastGoal: SIMD2<Float>?, walkStart = SIMD2<Float>.zero, walkT: Float = 0, lastP = SIMD2<Float>.zero
    }
    private var bodies: [Int: Body] = [:]
    private var clock: Float = 0, lastFlush: Float = 0, mixTickClock: Float = -1

    static func configure(defaults: UserDefaults = .standard, devArgs: Bool = DevArgs.enabled) {
        guard devArgs else { on = false; return }
        let v = defaults.object(forKey: "MoveLog") != nil && defaults.bool(forKey: "MoveLog")
        defaults.set(v, forKey: "MoveLog")
        on = v
        if v, defaults.object(forKey: "MoveLogSeconds") != nil { windowSeconds = max(5, Float(defaults.double(forKey: "MoveLogSeconds"))) }
        if v { shared.reset(); shared.line("start \(RoomTraffic.switchesText)") }
    }

    func reset() { total = Totals(); window = Totals(); bodies = [:]; actBody = [:]; cellBody = [:]; sess = [:]; chains = [:]; lastVisit3 = [Float](repeating: 0, count: 9); lastVisit6 = [Float](repeating: 0, count: 36); maskKey = ""; clock = 0; lastFlush = 0; minute = 0; windowWall = CACurrentMediaTime() }

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
        guard b.enabled else { return }
        if b.held { total.act[8] += dt; window.act[8] += dt; actBody[b.steerID, default: [Float](repeating: 0, count: 11)][8] += dt; return }
        var s = bodies[b.steerID] ?? Body()
        s.clock += dt
        let p = b.position, c = cell(p)
        if s.clock > clock { let adv = s.clock - clock; clock = s.clock; total.gameSec += adv; window.gameSec += adv; idleTick(adv) }
        visit(p)
        s.speed = s.clock > dt * 1.5 ? simd_distance(p, s.prevP) / max(dt, 1e-4) : 0; s.prevP = p
        activity(b, &s, dt)
        total.bodySec[c] += dt; window.bodySec[c] += dt
        cellBody[b.steerID, default: [Float](repeating: 0, count: 9)][c] += dt
        let emoteNow = (b.idleState.kind != nil && b.idleState.kind != .sleep) || b.social != nil
        var inPlaceNow = b.social != nil          // (round 2: an IN-PLACE emote or a pair / group: not travel, not a flourish on a walk, not a lying / sitting rest)
        if let k = b.idleState.kind, k != .sleep, !BlobBrain.travelKinds.contains(k), !b.isWalkScript { inPlaceNow = true }
        s.inPlace = inPlaceNow
        if emoteNow { total.emoteSec[c] += dt; window.emoteSec[c] += dt; if !s.emoting { total.emoteN += 1; window.emoteN += 1; if let n = b.social?.kind.rawValue ?? b.idleState.kind?.rawValue { total.kinds.insert(n); window.kinds.insert(n) } } }
        s.emoting = emoteNow
        if emoteNow, let n = b.social?.kind.rawValue ?? b.idleState.kind?.rawValue { total.kindSec[n, default: 0] += dt }
        var goal: SIMD2<Float>?
        if case .walk(let g, _) = b.script, b.activity == .walking || b.activity == .coming, b.social == nil { goal = g }
        if goal == nil || s.lastGoal.map({ simd_distance($0, goal!) > 0.01 }) == true { endWalk(&s) }
        if let g = goal {
            if s.lastGoal == nil { total.walkN += 1; window.walkN += 1; s.walkStart = p; s.walkT = 0 }
            s.lastGoal = g; s.walkT += dt; s.lastP = p
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
            if g <= 0, !(b.social != nil && b.social === o.social) {          // (bumps: bodies NOT in one session)
                if s.touching.insert(o.steerID).inserted {
                    let me = s.speed > 0.15, he = (bodies[o.steerID]?.speed ?? 0) > 0.15
                    let k = (me ? 1 : 0) + (he ? 1 : 0)
                    total.bump[k] += 1; window.bump[k] += 1
                }
            } else if g > 0.03 { s.touching.remove(o.steerID) }
        }
        bodies[b.steerID] = s
        if s.clock >= clock - 1e-6, bodies.count > 1, mixTickClock != clock {          // (once per game tick)
            mixTickClock = clock
            let any = bodies.values.contains { $0.inPlace }
            if !any { total.quietSec += dt; window.quietSec += dt }
            let ps = bodies.values.map { $0.prevP }
            var tight = ps.count >= 3
            for i in ps.indices { for j in ps.indices where j > i && simd_distance(ps[i], ps[j]) > 2.5 { tight = false } }
            if tight { total.huddleSec += dt; window.huddleSec += dt }
        }
        foldSessions()
        if clock - lastFlush >= Self.windowSeconds { flush() }
    }

    /// A walk ended (no goal now, or another goal): an arrival counts when the last sample was within 0.5 u of the goal.
    private func endWalk(_ s: inout Body) {
        defer { s.lastGoal = nil }
        guard let g = s.lastGoal, simd_distance(s.lastP, g) < 0.5 else { return }
        let d = simd_distance(s.walkStart, g)
        guard d > 0.3 else { return }
        total.walkTimes.append(s.walkT); total.arrN += 1; total.arrSec += s.walkT; total.arrDist += d; window.arrN += 1; window.arrSec += s.walkT; window.arrDist += d
    }

    // MARK: move-b-r1: activity budget, stands, sessions, floor idleness (logging only)

    private func activity(_ b: BlobBrain, _ s: inout Body, _ dt: Float) {
        let k = b.idleState.kind
        let walkingAct = b.activity == .walking || b.activity == .coming
        var isWalkScript = false
        if case .walk = b.script { isWalkScript = true }
        if walkingAct, isWalkScript, b.social == nil { s.slowT = s.speed < 0.1 ? s.slowT + dt : 0 } else { s.slowT = 0 }
        var cat = 9
        if let sn = b.social { cat = (sn.crew.count >= 3 || sn.idC >= 0) ? 5 : 4 }
        else if let k, BlobBrain.travelKinds.contains(k) { cat = 10 }          // (round 2: run / trot / zoomies / slide ... are TRAVEL: a "moving" class of its own, not a solo emote)
        else if k == .sleep || k == .sit || k == .slump || k == .flop { cat = 7 }
        else if walkingAct && isWalkScript {
            if s.slowT > 0.25 { cat = 8 }
            else if b.job != nil || b.pending != nil || b.commanded { cat = 1 }
            else if let k, k != .wander, k != .run { cat = 1 }
            else { cat = 0 }
        }
        else if b.activity == .playing || b.toy.waitUID >= 0 || b.toy.chaseSpot != nil { cat = 6 }
        else if b.activity == .eating || b.activity == .drinking || b.activity == .touched || b.activity == .recovering { cat = 9 }
        else if let k { cat = (k == .wander || k == .run) ? 0 : 3 }
        else { cat = 2 }
        if cat != s.cat {
            if s.cat == 2, s.catT > 0.2 { total.stands.append(s.catT); window.stands.append(s.catT) }
            s.cat = cat; s.catT = 0
        }
        s.catT += dt
        total.act[cat] += dt; window.act[cat] += dt
        actBody[b.steerID, default: [Float](repeating: 0, count: 11)][cat] += dt
        if let sn = b.social {
            let id = ObjectIdentifier(sn), group = sn.crew.count >= 3 || sn.idC >= 0
            sess[id] = (sess[id]?.first ?? clock, clock, group, min(sn.idA, sn.idB) * 100 + max(sn.idA, sn.idB))
        }
    }

    /// Sessions not seen for 2 s are over: counted with the length they were seen for.
    private func foldSessions() {
        for (id, v) in sess where clock - v.last > 2 {
            let len = v.last - v.first
            if v.group { total.groupN += 1; total.groupSec += len; window.groupN += 1; window.groupSec += len }
            else {
                total.pairN += 1; total.pairSec += len; window.pairN += 1; window.pairSec += len
                var ch = chains[v.pair] ?? (v.first, v.last)
                if v.first - ch.end > 6 { ch = (v.first, v.last) } else { ch.end = v.last }
                chains[v.pair] = ch
                total.chainMax = max(total.chainMax, ch.end - ch.start); window.chainMax = max(window.chainMax, ch.end - ch.start)
            }
            sess[id] = nil
        }
    }

    private func cellIndex(_ p: SIMD2<Float>, _ n: Int) -> Int {
        var lo = SIMD2<Float>(-3, -3), hi = SIMD2<Float>(3, 3)
        if let f = GameCamera.roamFloor { let b = f.bounds; lo = b.min; hi = b.max }
        let cx = min(n - 1, max(0, Int((p.x - lo.x) / max(hi.x - lo.x, 0.1) * Float(n)))), cz = min(n - 1, max(0, Int((p.y - lo.y) / max(hi.y - lo.y, 0.1) * Float(n))))
        return cz * n + cx
    }
    private func refreshMask() {
        guard let f = GameCamera.roamFloor else { return }
        let b = f.bounds, key = "\(b.min) \(b.max) \(f.zs.count)"
        guard key != maskKey else { return }
        maskKey = key
        func mask(_ n: Int) -> [Bool] {
            (0..<(n * n)).map { i in
                let cx = i % n, cz = i / n
                return f.contains(SIMD2(b.min.x + (Float(cx) + 0.5) / Float(n) * (b.max.x - b.min.x), b.min.y + (Float(cz) + 0.5) / Float(n) * (b.max.y - b.min.y)))
            }
        }
        valid3 = mask(3); valid6 = mask(6)
        if !valid3.contains(true) { valid3 = [Bool](repeating: true, count: 9) }
        if !valid6.contains(true) { valid6 = [Bool](repeating: true, count: 36) }
        total.idleCells3 = valid3.filter { $0 }.count; total.idleCells6 = valid6.filter { $0 }.count
        window.idleCells3 = total.idleCells3; window.idleCells6 = total.idleCells6
    }
    private func visit(_ p: SIMD2<Float>) { lastVisit3[cellIndex(p, 3)] = clock; lastVisit6[cellIndex(p, 6)] = clock }
    /// Once per game tick: the integral of the seconds since a body was last in each (floor) cell.
    private func idleTick(_ adv: Float) {
        refreshMask()
        for i in 0..<9 where valid3[i] {
            let since = clock - lastVisit3[i]
            total.idleSum3[i] += since * adv; window.idleSum3[i] += since * adv
            total.idleMax3 = max(total.idleMax3, since); window.idleMax3 = max(window.idleMax3, since)
        }
        for i in 0..<36 where valid6[i] {
            let since = clock - lastVisit6[i]
            total.idleSum6[i] += since * adv; window.idleSum6[i] += since * adv
            total.idleMax6 = max(total.idleMax6, since); window.idleMax6 = max(window.idleMax6, since)
        }
    }

    static let actNames = ["roam", "toTask", "stand", "solo", "pair", "group", "play", "lie", "wait", "other", "moving"]
    static func actText(_ a: [Float]) -> String {
        let sum = max(a.reduce(0, +), 0.001)
        return zip(actNames, a).map { "\($0) \(String(format: "%.0f", $1 / sum * 100))" }.joined(separator: " ")
    }
    static func pct(_ v: [Float], _ q: Float) -> Float { v.isEmpty ? 0 : v.sorted()[min(v.count - 1, Int(Float(v.count) * q))] }
    /// All the move-b-r1 numbers of a totals block as text lines.
    static func extra(_ t: Totals) -> String {
        let mins = max(t.gameSec / 60, 0.01)
        let st = t.stands
        var s = "act% [\(actText(t.act))]"
        s += String(format: " | stands %.1f/min med %.1f p90 %.1f max %.1f s, >5s %.1f/min >10s %.1f/min", Float(st.count) / mins, pct(st, 0.5), pct(st, 0.9), st.max() ?? 0, Float(st.filter { $0 > 5 }.count) / mins, Float(st.filter { $0 > 10 }.count) / mins)
        s += String(format: " | bumps/min stand-stand %.1f one-walking %.1f both-walking %.1f", Float(t.bump[0]) / mins, Float(t.bump[1]) / mins, Float(t.bump[2]) / mins)
        s += String(format: " | walk-to-goal median %.1f s p90 %.1f s (%d arrivals)", pct(t.walkTimes, 0.5), pct(t.walkTimes, 0.9), t.arrN)
        s += String(format: " | pairs %.1f/h len %.1f s, groups %.1f/h len %.1f s", Float(t.pairN) / mins * 60, t.pairSec / Float(max(t.pairN, 1)), Float(t.groupN) / mins * 60, t.groupSec / Float(max(t.groupN, 1)))
        let g = max(t.gameSec, 0.01)
        s += String(format: " | nobody-emoting %.0f%% huddle(all within 2.5 u) %.0f%% longest same-pair chain %.0f s kinds/run %@", t.quietSec / max(t.gameSec, 0.01) * 100, t.huddleSec / max(t.gameSec, 0.01) * 100, t.chainMax, (t.kindCounts.isEmpty ? [t.kinds.count] : t.kindCounts).map(String.init).joined(separator: "/"))
        s += String(format: " | idleness 3x3 mean %.1f max %.1f s, 6x6 mean %.1f max %.1f s", t.idleSum3.reduce(0, +) / g / Float(max(t.idleCells3, 1)), t.idleMax3, t.idleSum6.reduce(0, +) / g / Float(max(t.idleCells6, 1)), t.idleMax6)
        let bs = max(t.bodySec.reduce(0, +), 0.001)
        s += " | 3x3 body% (back..front rows) " + (0..<3).map { r in (0..<3).map { String(format: "%.0f", t.bodySec[r * 3 + $0] / bs * 100) }.joined(separator: " ") }.joined(separator: " / ")
        let ks = t.kindSec.sorted { $0.value > $1.value }.prefix(16).map { "\($0.key) \(String(format: "%.1f", $0.value / max(t.gameSec, 0.01) / 3 * 100))" }
        s += " | emote kinds % of body time (3 bodies): " + ks.joined(separator: ", ")
        s += " | KINDS(" + String(t.kinds.count) + ") " + t.kinds.sorted().joined(separator: ",")
        return s
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
    var summary: String {
        let t = total
        let body = actBody.keys.sorted().map { "b\($0) [\(Self.actText(actBody[$0]!))]" }.joined(separator: " ")
        let thirds = cellBody.keys.sorted().map { id -> String in
            let v = cellBody[id]!, tot = max(v.reduce(0, +), 0.001)
            let z = (0..<3).map { r in (0..<3).map { v[r * 3 + $0] }.reduce(0, +) / tot * 100 }, x = (0..<3).map { c in (0..<3).map { v[$0 * 3 + c] }.reduce(0, +) / tot * 100 }
            return "b\(id) back/mid/front " + z.map { String(format: "%.0f", $0) }.joined(separator: "/") + " left/ctr/right " + x.map { String(format: "%.0f", $0) }.joined(separator: "/") + " cells>0: \(v.filter { $0 > 0 }.count)"
        }.joined(separator: "; ")
        return "movelog \(tag) \(String(format: "%.1f", t.gameSec / 60)) min | \(rates(t, minutes: t.gameSec / 60)) | walk \(String(format: "%.0f", t.walkSec)) s / \(t.walkN) walks, \(t.arrN) arrivals \(String(format: "%.2f", t.arrSec / max(t.arrDist, 0.01))) s per u | emotes \(t.emoteN) | \(gridText(t)) | \(Self.extra(t)) | per body act% \(body) | THIRDS \(thirds)"
    }

    private func flush() {
        minute += 1
        let wall = Float(CACurrentMediaTime() - windowWall)
        line("min \(minute) | \(rates(window, minutes: window.gameSec / 60)) | walk \(String(format: "%.0f", window.walkSec)) s | pace \(String(format: "%.2f", window.gameSec / max(wall, 0.01))) | \(gridText(window)) | \(Self.extra(window))")
        window = Totals(); window.idleCells3 = total.idleCells3; window.idleCells6 = total.idleCells6; windowWall = CACurrentMediaTime(); lastFlush = clock
    }

    func line(_ s: String) {
        let text = "\(tag.isEmpty ? "" : tag + " | ")\(s)"
        print("[melon] movelog \(text)")
        guard Self.writeFile, let d = (text + "\n").data(using: .utf8) else { return }
        if let h = try? FileHandle(forWritingTo: url) { h.seekToEndOfFile(); h.write(d); try? h.close() } else { try? d.write(to: url) }
    }
}
