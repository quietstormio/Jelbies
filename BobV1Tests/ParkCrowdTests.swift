//
//  ParkCrowdTests.swift
//  The park crowd (park-crowd-r1): five autonomous Jelbies on the park lawn, wired like the real stage (SocialTests.Lab: the same keepApart wall, the same makeRoom).
//  `CrowdProbe` measures who presses / stands inside whom (and why), who gets stuck walking, and how the group socials gather.
//

import XCTest
import simd
@testable import BobV1

@MainActor
final class ParkCrowdTests: XCTestCase {
    nonisolated(unsafe) static var keep: [AnyObject] = []

    override func setUp() {
        DecorField.shared.clear(); DecorField.shared.toys = ToyBook(); ToyTuning.settle = 0
    }
    override func tearDown() {
        DecorField.shared.clear(); ToyTuning.settle = 5
        GameCamera.endPark(count: 3); _ = GameCamera.camera(aspect: 440.0 / 956.0)
        GameCamera.configureRoom(count: 1); GameCamera.clearRoam(); RoomLayout.apply(RoomCatalog.home)
    }

    static let starts5: [SIMD2<Float>] = [SIMD2(-2.1, -1.6), SIMD2(-0.6, 0.5), SIMD2(0.6, -0.8), SIMD2(1.0, 2.7), SIMD2(-0.5, 3.3)]

    /// The park the way HopscotchTests.parkLab sets it up (copied, that file is not edited), five bodies, autonomy on (quiet false), outingPlay on every brain as a park visit sets it.
    func parkLab(n: Int = 5, seed: UInt64) -> SocialTests.Lab {
        RoomLayout.apply(RoomCatalog.park); GameCamera.configurePark(); _ = GameCamera.refreshRoam(aspect: 440.0 / 956.0)
        let lab = SocialTests.Lab(n: n, positions: Array(Self.starts5.prefix(n)), quiet: false, seed: seed)
        for r in lab.rigs { r.sim.arenaCenter = GameCamera.arenaCenter; r.sim.arenaRadius = GameCamera.arenaRadius; r.brain.anticsEnabled = true; r.brain.idleMood = .happy; r.brain.outingPlay = true }
        DecorField.shared.set(ParkToys.placed)
        DecorField.shared.toys.news.removeAll()
        return lab
    }

    // MARK: the probe

    final class Rec {
        let s: SocialSession, kind: SocialKind, t0: Float
        var gather: Float = 0, pressed0: Float = 0, inside0: Float = 0, pressedL: Float = 0, insideL: Float = 0
        var minSolid: Float = .infinity, minLanding: Float = .infinity
        var members = 0
        init(_ s: SocialSession, t0: Float) { self.s = s; kind = s.kind; self.t0 = t0 }
    }
    struct Episode { var seed: UInt64, body: Int, t: Float, dur: Float, at: SIMD2<Float>, near: String, solid: Float, doing: String }

    final class Probe {
        let lab: SocialTests.Lab
        let gap = MelonController.jellyGap
        var pressedSec: [String: Float] = [:], insideSec: [String: Float] = [:]
        var recs: [ObjectIdentifier: Rec] = [:], order: [Rec] = []
        var hist: [[SIMD2<Float>]]
        var stuckSince: [Float?]
        var episodes: [Episode] = []
        var t: Float = 0
        let seed: UInt64
        var insideRun: [Int: Float] = [:], worstInsideRun: Float = 0, worstInsideRunPhase0: Float = 0
        var pressedTotal: Float = 0, insideTotal: Float = 0
        init(lab: SocialTests.Lab, seed: UInt64) { self.lab = lab; self.seed = seed; hist = Array(repeating: [], count: lab.rigs.count); stuckSince = Array(repeating: nil, count: lab.rigs.count) }

        func doing(_ i: Int) -> String {
            let b = lab.rigs[i].brain
            if let s = b.social { return "social:\(s.kind.rawValue)/p\(s.phase)" }
            if let k = b.idleState.kind { return "idle:\(k)" }
            return "script:\(b.scriptKindName)"
        }
        func isWalk(_ i: Int) -> Bool { if case .walk = lab.rigs[i].brain.script { return true }; return false }
        func solidDist(_ p: SIMD2<Float>) -> Float { DecorField.shared.feet.filter { $0.spec.solid }.map { $0.distance(p) }.min() ?? 9 }

        func step() {
            lab.tick(watching: false)
            let dt: Float = 1.0 / 60
            t += dt
            let n = lab.rigs.count
            let roots = lab.rigs.map { $0.root }
            // group sessions
            for r in lab.rigs { if let s = r.brain.social, s.kind.isGroup, recs[ObjectIdentifier(s)] == nil {
                let rec = Rec(s, t0: t); rec.members = s.crewIDs.count
                let sf = DecorField.shared.foot(ParkToys.slideUID)
                let landing = sf.map { $0.centre + $0.turned(SIMD2(0, BlobBrain.slideAt(BlobBrain.slideLength).z)) }
                for (_, p) in s.slotSpot { rec.minSolid = min(rec.minSolid, solidDist(p)); if let l = landing { rec.minLanding = min(rec.minLanding, simd_distance(p, l)) } }
                recs[ObjectIdentifier(s)] = rec; order.append(rec)
            } }
            for rec in order where rec.s.end == nil && lab.rigs.contains(where: { $0.brain.social === rec.s }) && rec.s.phase == 0 { rec.gather += dt }
            // pairs
            for i in 0..<n { for j in (i + 1)..<n {
                let d = simd_distance(roots[i], roots[j])
                let bi = lab.rigs[i].brain, bj = lab.rigs[j].brain
                let same = bi.social != nil && bi.social === bj.social
                var inside = false
                if d < 0.8 * gap {
                    inside = d < 0.7 * gap
                    let pass = bi.socialBook.passThrough || bj.socialBook.passThrough
                    let soc = same ? "\(bi.social!.kind.rawValue)/p\(bi.social!.phase)" : (bi.social != nil || bj.social != nil ? "other-social" : "-")
                    let scr = [bi.scriptKindName, bj.scriptKindName].sorted().joined(separator: "+")
                    let dec = [bi, bj].contains { b in b.idleState.kind.map { BlobBrain.decorKinds.contains($0) || $0 == .hopscotch } ?? false } ? "decor" : "free"
                    let key = "soc=\(soc) pass=\(pass ? 1 : 0) scr=\(scr) \(dec)"
                    pressedSec[key, default: 0] += dt; pressedTotal += dt
                    if inside { insideSec[key, default: 0] += dt; insideTotal += dt }
                    if same, let rec = recs[ObjectIdentifier(bi.social!)] {
                        if bi.social!.phase == 0 { rec.pressed0 += dt; if inside { rec.inside0 += dt } } else { rec.pressedL += dt; if inside { rec.insideL += dt } }
                    }
                }
                let k = i * 8 + j
                let isPhase0 = same && bi.social!.phase == 0 && bi.social!.kind.isGroup
                if inside && isPhase0 { insideRun[k, default: 0] += dt; worstInsideRunPhase0 = max(worstInsideRunPhase0, insideRun[k]!) }
                else if inside { insideRun[k, default: 0] += dt } else { insideRun[k] = 0 }
                worstInsideRun = max(worstInsideRun, insideRun[k] ?? 0)
            } }
            // stuck walkers
            for i in 0..<n {
                hist[i].append(roots[i]); if hist[i].count > 181 { hist[i].removeFirst() }
                let stuck = hist[i].count > 180 && isWalk(i) && simd_distance(hist[i][0], roots[i]) < 0.25
                if stuck, stuckSince[i] == nil {
                    stuckSince[i] = t - 3
                    var near: [String] = []
                    for j in 0..<n where j != i && simd_distance(roots[i], roots[j]) < 1.3 * gap { near.append("#\(j) d=\(String(format: "%.2f", simd_distance(roots[i], roots[j]) / gap)) \(doing(j))") }
                    episodes.append(Episode(seed: seed, body: i, t: t - 3, dur: 3, at: roots[i], near: near.joined(separator: "; "), solid: solidDist(roots[i]), doing: doing(i)))
                } else if stuck, let s0 = stuckSince[i] { episodes[episodes.lastIndex { $0.body == i }!].dur = t - s0 }
                else if !stuck { stuckSince[i] = nil }
            }
        }
    }

    /// Run one seed for `seconds` and return the probe.
    func runProbe(seed: UInt64, seconds: Float = 120) -> Probe {
        let lab = parkLab(seed: seed)
        let p = Probe(lab: lab, seed: seed)
        for _ in 0..<Int(seconds * 60) { p.step() }
        return p
    }

    static func fmt(_ x: Float) -> String { String(format: "%.1f", x) }

    /// The full table (markdown) for a set of seeds.
    func report(_ probes: [Probe], seconds: Float) -> String {
        var o = "# park crowd, \(probes.count) seeds x \(Int(seconds)) s, 5 bodies, gap \(MelonController.jellyGap)\n"
        let total = Float(probes.count) * seconds
        o += "\n## (a) pair-seconds pressed (<0.80 gap) / inside (<0.70 gap), all seeds: pressed \(Self.fmt(probes.reduce(0) { $0 + $1.pressedTotal })) s, inside \(Self.fmt(probes.reduce(0) { $0 + $1.insideTotal })) s of \(Int(total)) sim-s\n"
        var pr: [String: Float] = [:], ins: [String: Float] = [:]
        for p in probes { for (k, v) in p.pressedSec { pr[k, default: 0] += v }; for (k, v) in p.insideSec { ins[k, default: 0] += v } }
        for (k, v) in pr.sorted(by: { $0.value > $1.value }).prefix(25) { o += "- pressed \(Self.fmt(v)) inside \(Self.fmt(ins[k] ?? 0))  \(k)\n" }
        o += "\n## (b) stuck walkers (walk script, moved < 0.25 m in 3 s)\n"
        let eps = probes.flatMap { $0.episodes }
        o += "episodes \(eps.count), total \(Self.fmt(eps.reduce(0) { $0 + $1.dur })) s, longest \(Self.fmt(eps.map { $0.dur }.max() ?? 0)) s, stuckRepicks total \(probes.reduce(0) { $0 + $1.lab.rigs.reduce(0) { $0 + $1.brain.stuckRepicks } })\n"
        var byDoing: [String: (Int, Float)] = [:]
        for e in eps { let k = e.doing; byDoing[k] = ((byDoing[k]?.0 ?? 0) + 1, (byDoing[k]?.1 ?? 0) + e.dur) }
        for (k, v) in byDoing.sorted(by: { $0.value.1 > $1.value.1 }) { o += "- stuck walker doing \(k): \(v.0) episodes, \(Self.fmt(v.1)) s\n" }
        for e in eps.sorted(by: { $0.dur > $1.dur }).prefix(14) { o += "  seed \(e.seed) t=\(Self.fmt(e.t)) body \(e.body) dur \(Self.fmt(e.dur)) at (\(Self.fmt(e.at.x)),\(Self.fmt(e.at.y))) solid \(String(format: "%.2f", e.solid)) doing \(e.doing) near[\(e.near)]\n" }
        o += "\n## (c) group socials\n"
        let recs = probes.flatMap { $0.order }
        for k in [SocialKind.groupHug, .groupCheer, .conga, .circleDance, .congaLine, .ringDance] {
            let rs = recs.filter { $0.kind == k }
            if rs.isEmpty { continue }
            let done = rs.filter { $0.s.end == .done }.count, ab = rs.filter { $0.s.end == .aborted }.count
            let g = rs.map { $0.gather }
            o += "- \(k.rawValue): started \(rs.count), done \(done), aborted \(ab), other/unfinished \(rs.count - done - ab); gather mean \(Self.fmt(g.reduce(0, +) / Float(g.count))) s max \(Self.fmt(g.max() ?? 0)) s; pressed ph0 \(Self.fmt(rs.reduce(0) { $0 + $1.pressed0 })) later \(Self.fmt(rs.reduce(0) { $0 + $1.pressedL })), inside ph0 \(Self.fmt(rs.reduce(0) { $0 + $1.inside0 })) later \(Self.fmt(rs.reduce(0) { $0 + $1.insideL }))\n"
        }
        let rings = recs.filter { $0.kind == .groupHug || $0.kind == .circleDance || $0.kind == .groupCheer }
        for r in rings { o += "  ring \(r.kind.rawValue) n=\(r.members) t0=\(Self.fmt(r.t0)) minSolidDist \(String(format: "%.2f", r.minSolid)) minLandingDist \(String(format: "%.2f", r.minLanding)) gather \(Self.fmt(r.gather)) end \(String(describing: r.s.end)) inside ph0 \(Self.fmt(r.inside0))\n" }
        o += "  rings with a place < 0.35 of a solid piece: \(rings.filter { $0.minSolid < 0.35 }.count) of \(rings.count); places < peerGap (\(MelonController.jellyGap)) from the slide landing: \(rings.filter { $0.minLanding < MelonController.jellyGap }.count)\n"
        o += "  worst continuous inside-run (any pair) \(Self.fmt(probes.map { $0.worstInsideRun }.max() ?? 0)) s; during a group gather (phase 0) \(Self.fmt(probes.map { $0.worstInsideRunPhase0 }.max() ?? 0)) s\n"
        let hc = recs.filter { ($0.kind == .groupHug || $0.kind == .circleDance) && $0.s.end == .done }.count
        o += "\n## (d) completed hugs + circle dances: \(hc) in \(Int(total)) sim-s = \(String(format: "%.3f", Float(hc) / (total / 60))) per minute\n"
        return o
    }

    func writeOut(_ text: String, name: String) {
        MotionLog.write(text)
        if let dir = ProcessInfo.processInfo.environment["CROWD_OUT"] { try? text.write(toFile: dir + "/" + name, atomically: true, encoding: .utf8) }
    }

    // MARK: measurement (no assertion on the numbers: commit 1 is the BEFORE picture)

    func testMeasureParkCrowd() {
        let seeds = Int(ProcessInfo.processInfo.environment["CROWD_SEEDS"] ?? "") ?? 3
        let secs = Float(ProcessInfo.processInfo.environment["CROWD_SECS"] ?? "") ?? 120
        let t0 = Date()
        var probes: [Probe] = []
        for k in 0..<seeds { probes.append(runProbe(seed: 5 + UInt64(k) * 13, seconds: secs)); MotionLog.write("seed \(k) done, \(Date().timeIntervalSince(t0)) s wall") }
        writeOut(report(probes, seconds: secs), name: "crowd_report.md")
        XCTAssertEqual(probes.count, seeds)
    }
}
