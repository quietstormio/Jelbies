//
//  FormationTests.swift
//  FORMATION (the walk-up before an emote): a seeded soak over random layouts. For each kind the initiator starts the emote through its normal start API
//  from a random spot (pair distance 0.8 - 4.8 m, random facings, half of the layouts with a third Jelbie in the way or beside the pair) and the test
//  records the seconds from the start to phase 1 (the walk-up is over), to the emote proper (phase 2; the squabble's face-off is its phase 1), the outcome
//  (arrived / aborted / timed out / refused at start) and, for the touching kinds, the skin gap when the emote proper begins.
//  One table line per kind, prefixed FORMATION (MotionLog). Groups: groupHug, groupCheer, circleDance, ringDance with 3, 4 and 5 members, one of them ~5 m away.
//

import XCTest
import simd
@testable import BobV1

struct FormationRNG {
    var s: UInt64
    init(_ seed: UInt64) {          // (the seed goes through the mixer first: consecutive seeds would otherwise be the same stream shifted by one draw)
        var z = seed &* 0x9E3779B97F4A7C15
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        s = z ^ (z >> 31)
    }
    mutating func next() -> UInt64 {
        s &+= 0x9E3779B97F4A7C15
        var z = s
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
    mutating func unit() -> Float { Float(next() >> 40) / Float(1 << 24) }
    mutating func range(_ a: Float, _ b: Float) -> Float { a + (b - a) * unit() }
}

@MainActor
final class FormationTests: XCTestCase {
    enum Outcome { case arrived, aborted, timedOut, refused }
    struct Rec { var outcome: Outcome; var t1: Float?; var t2: Float?; var gap: Float?; var cf: Float?; var nilCF = false; var note = "" }

    override func setUp() { RoomLayout.dynamicBoxes = []; SocialTuning.pickChance = 0.12 }
    override func tearDown() { RoomLayout.dynamicBoxes = [] }

    static let floorMin = SIMD2<Float>(-2.0, -2.0), floorMax = SIMD2<Float>(2.0, 2.9)
    static let maxSeconds: Float = 25

    /// Pair kinds measured: (kind, the phase that is the emote proper, touching).
    static let pairKinds: [(SocialKind, Int, Bool)] = [
        (.chestBump, 2, true), (.squabble, 1, true), (.highFive, 2, true), (.nuzzle, 2, true), (.swayHug, 2, true),
        (.cheekSquish, 2, true), (.sneak, 2, true), (.tag, 2, true), (.leapfrog, 2, false), (.spinHug, 2, true), (.cuddleLean, 2, true), (.boop, 2, true),
    ]
    static let groupKinds: [(SocialKind, Bool)] = [(.groupHug, true), (.groupCheer, false), (.circleDance, false), (.ringDance, false)]

    // MARK: layouts

    static func inFloor(_ p: SIMD2<Float>) -> Bool { p.x >= floorMin.x && p.x <= floorMax.x && p.y >= floorMin.y && p.y <= floorMax.y }
    static func randomPoint(_ r: inout FormationRNG) -> SIMD2<Float> { SIMD2(r.range(floorMin.x, floorMax.x), r.range(floorMin.y, floorMax.y)) }

    /// The floor is the arena circle (GameCamera: centre (0, 0.5), radius 3.3): spots outside it are pushed in and the start API refuses them. Layouts stay inside r < 2.8.
    static let arenaC = SIMD2<Float>(0, 0.5), arenaR: Float = 2.8
    static func inArena(_ p: SIMD2<Float>) -> Bool { simd_distance(p, arenaC) < arenaR }
    static func arenaPoint(_ r: inout FormationRNG) -> SIMD2<Float> {
        for _ in 0..<200 { let p = randomPoint(&r); if inArena(p) { return p } }
        return arenaC
    }

    /// A pair (initiator `a` = rig 0, partner `b` = rig 1; distance 0.8 ... 4.8 m, random bearing, both inside the arena) and a third (rig 2): between / beside the walk for odd layouts, far off for even ones.
    static func pairLayout(_ i: Int) -> (pos: [SIMD2<Float>], yaw: [Float]) {
        var r = FormationRNG(UInt64(1000 + i))
        var a = SIMD2<Float>.zero, b = SIMD2<Float>.zero
        for _ in 0..<600 {
            b = arenaPoint(&r)
            let d = r.range(0.8, 4.8), ang = r.range(0, 2 * .pi)
            a = b + SIMD2(sinf(ang), cosf(ang)) * d
            if inArena(a) { break }
        }
        let u = simd_normalize(a - b + SIMD2(1e-6, 0)), lat = SIMD2(-u.y, u.x)
        let spotNear = b + u * 1.5          // (where the initiator is going to stand, roughly)
        var c = arenaC
        if i % 2 == 1 {
            let between = (i / 2) % 2 == 0
            var cands: [SIMD2<Float>] = []
            for _ in 0..<40 {
                let t = r.range(0.3, 0.6), side = r.range(between ? -0.25 : 0.9, between ? 0.25 : 1.4) * (r.unit() < 0.5 ? 1 : -1)
                cands.append(b + (a - b) * t + lat * side)
            }
            c = cands.first { inArena($0) && simd_distance($0, spotNear) > 1.35 && simd_distance($0, b) > 1.1 && simd_distance($0, a) > 1.1 } ?? cands[0]
        } else {
            var best = arenaC, bestD: Float = -1
            for _ in 0..<80 { let p = arenaPoint(&r); let dd = min(simd_distance(p, a), simd_distance(p, b)); if dd > bestD { bestD = dd; best = p } }
            c = best
        }
        return ([a, b, c], [r.range(-.pi, .pi), r.range(-.pi, .pi), r.range(-.pi, .pi)])
    }

    /// n members: n - 1 in a loose cluster (all inside the arena) and the last one 4.0 ... 4.8 m from the cluster's centre.
    static func groupLayout(_ n: Int, _ i: Int) -> (pos: [SIMD2<Float>], yaw: [Float]) {
        var r = FormationRNG(UInt64(5000 + 31 * n + i))
        var pts: [SIMD2<Float>] = []
        for _ in 0..<2000 {
            pts = []
            let far = arenaPoint(&r), ang = r.range(0, 2 * .pi), dist = r.range(4.0, 4.8)
            let cc = far + SIMD2(sinf(ang), cosf(ang)) * dist
            guard simd_distance(cc, arenaC) < 1.7 else { continue }
            for _ in 0..<(n - 1) {
                for _ in 0..<60 {
                    let p = cc + SIMD2(r.range(-1.0, 1.0), r.range(-1.0, 1.0))
                    if inArena(p), pts.allSatisfy({ simd_distance($0, p) > 1.0 }) { pts.append(p); break }
                }
            }
            if pts.count == n - 1 { pts.append(far); break }
        }
        if pts.count != n { pts = (0..<n).map { SIMD2(-1.8 + Float($0) * 0.9, 0.5 + 1.2 * Float($0 % 2)) } }
        return (pts, (0..<n).map { _ in r.range(-.pi, .pi) })
    }

    // MARK: running

    func arrange(_ d: FeatureClipTests.Duo, _ pos: [SIMD2<Float>], _ yaw: [Float]) {
        d.place(pos)
        for (i, r) in d.lab.rigs.enumerated() { r.brain.yaw = yaw[i]; r.brain.stepYaw0 = yaw[i] }
        d.lab.aside = [Float](repeating: 0, count: d.lab.aside.count)          // (the room's step-aside runs as in the game)
        for r in d.lab.rigs {          // (a session's end sets short cooldowns; nobody picks a social of his own during the soak)
            r.brain.socialBook.cooldown = 1e6; r.brain.socialBook.pair = [:]; r.brain.socialBook.groupIdle = 0; r.brain.socialBook.groupCool = 1e6
            r.brain.idleState.cooldown = 1e6; r.brain.restTimer = 1e6
        }
        for _ in 0..<20 { d.tick() }
        for _ in 0..<150 where !d.lab.rigs.allSatisfy({ $0.brain.socialFree }) { d.tick() }          // (a start refused only because the last session left somebody busy would be noise)
    }

    func stopAll(_ d: FeatureClipTests.Duo) {
        for r in d.lab.rigs { r.brain.socialBook.stopAll = true }
        for _ in 0..<90 { d.tick(); if d.lab.rigs.allSatisfy({ $0.brain.social == nil }) { break } }
    }

    func minPairGap(_ d: FeatureClipTests.Duo, _ idx: [Int]) -> Float {
        let S = d.contactSurfaces()
        var g = Float.infinity
        for x in idx { var nearest = Float.infinity; for y in idx where y != x { nearest = min(nearest, BruteForceContactMetric.skinGap(S[x], S[y])) }; g = min(g, nearest) }
        return g
    }

    func session(_ d: FeatureClipTests.Duo, kind: SocialKind, proper: Int) -> Rec {
        let a = d.lab.rigs[0]
        let others = d.lab.rigs.dropFirst().map { $0.brain }
        guard a.brain.socialStart(kind, with: others[0], a.sim), let s = a.brain.social else { return Rec(outcome: .refused, t1: nil, t2: nil, gap: nil) }
        var rec = Rec(outcome: .timedOut, t1: nil, t2: nil, gap: nil)
        let p0 = a.brain.position
        var moved: Float = 0
        for tick in 1...Int(Self.maxSeconds * 60) {
            d.tick()
            moved = max(moved, simd_distance(a.brain.position, p0))
            let t = Float(tick) / 60
            if s.phase >= 1, rec.t1 == nil { rec.t1 = t }
            if s.phase >= proper {
                rec.t2 = t; if rec.t1 == nil { rec.t1 = t }
                let members = s.crewIDs.isEmpty ? [0, 1] : s.crewIDs
                rec.gap = members.count == 2 ? { let S = d.contactSurfaces(); return BruteForceContactMetric.skinGap(S[members[0]], S[members[1]]) }() : minPairGap(d, members)
                if members.count == 2 { if let g = ContactField.gap(0, 1, features: true) { rec.cf = g } else { rec.nilCF = true } }          // (the stance's own metric at the same moment: nil = no profile gap)
                rec.outcome = .arrived
                break
            }
            if let e = s.end { rec.outcome = (e == .aborted || e == .stopped) ? .aborted : .arrived; break }
        }
        if rec.outcome != .arrived {
            let gap = ContactField.gap(0, 1, features: true).map { String(format: "%.2f", $0) } ?? "nil"
            rec.note = String(format: "start (%.1f,%.1f) moved %.2f end %@ t %.1f phase %d rewalks %d dist %.2f gap %@ script %@ initiator@(%.1f,%.1f) partner@(%.1f,%.1f) third@(%.1f,%.1f)", p0.x, p0.y, moved, s.end.map { "\($0)" } ?? "none", s.t, s.phase, s.rewalks, simd_distance(a.brain.position, others[0].position), gap, a.brain.scriptIsNone ? "none" : "walk",
                                  a.brain.position.x, a.brain.position.y, others[0].position.x, others[0].position.y, d.lab.rigs.last!.brain.position.x, d.lab.rigs.last!.brain.position.y)
        }
        stopAll(d)
        return rec
    }

    static func pct(_ v: [Float], _ q: Float) -> Float { v.isEmpty ? .nan : v.sorted()[min(v.count - 1, Int(q * Float(v.count)))] }
    func line(_ tag: String, _ recs: [Rec], touching: Bool) -> String {
        let t1 = recs.compactMap(\.t1), t2 = recs.compactMap(\.t2)
        let n = { (o: Outcome) in recs.filter { $0.outcome == o }.count }
        let gaps = recs.compactMap(\.gap)
        let worst = gaps.map { abs($0) }.max() ?? .nan
        let cfs = recs.compactMap(\.cf), nils = recs.filter { $0.nilCF }.count
        return String(format: "FORMATION %@ n=%d arrived=%d aborted=%d timeout=%d refused=%d | to-phase1 med %.1f p90 %.1f max %.1f | to-emote med %.1f p90 %.1f max %.1f | gap(cm) min %.1f max %.1f worst|.| %.1f | stance-gap max %.1f nil %d%@",
                      tag, recs.count, n(.arrived), n(.aborted), n(.timedOut), n(.refused),
                      Self.pct(t1, 0.5), Self.pct(t1, 0.9), t1.max() ?? .nan, Self.pct(t2, 0.5), Self.pct(t2, 0.9), t2.max() ?? .nan,
                      (gaps.min() ?? .nan) * 100, (gaps.max() ?? .nan) * 100, worst * 100, (cfs.max() ?? .nan) * 100, nils, touching ? " (touching)" : "")
    }

    static let layouts = 16

    func testPairFormation() {
        let d = FeatureClipTests.Duo(positions: [SIMD2(-1.5, 0.6), SIMD2(1.35, 0.9), SIMD2(0, 2.4)], features: [.none, .none, .none], seed: 77)
        d.live = true
        for _ in 0..<3 { d.tick() }
        var total = 0
        for (kind, proper, touching) in Self.pairKinds {
            var recs: [Rec] = []
            for i in 0..<Self.layouts {
                let l = Self.pairLayout(i)
                arrange(d, l.pos, l.yaw)
                recs.append(session(d, kind: kind, proper: proper))
            }
            MotionLog.write(line(kind.rawValue, recs, touching: touching))
            for (i, r) in recs.enumerated() where r.outcome == .aborted || r.outcome == .timedOut { MotionLog.write("FORMATION-DETAIL \(kind.rawValue) layout \(i): \(r.note)") }
            total += recs.count
        }
        XCTAssertEqual(total, Self.pairKinds.count * Self.layouts, "every session ran")
    }

    func testGroupFormation() {
        var total = 0
        for n in [3, 4, 5] {
            let d = FeatureClipTests.Duo(positions: (0..<n).map { SIMD2(-1.8 + Float($0) * 0.8, 0.5 + 1.2 * Float($0 % 2)) }, features: [JellyFeature](repeating: .none, count: n), seed: 88 + UInt64(n))
            d.live = true
            for _ in 0..<3 { d.tick() }
            for (kind, touching) in Self.groupKinds {
                var recs: [Rec] = []
                for i in 0..<8 {
                    let l = Self.groupLayout(n, i)
                    arrange(d, l.pos, l.yaw)
                    recs.append(session(d, kind: kind, proper: 2))
                }
                MotionLog.write(line("\(kind.rawValue)/\(n)", recs, touching: touching))
                total += recs.count
            }
        }
        XCTAssertEqual(total, 3 * Self.groupKinds.count * 8, "every session ran")
    }
}
