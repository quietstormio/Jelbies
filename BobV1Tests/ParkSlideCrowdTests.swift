//
//  ParkSlideCrowdTests.swift
//  park-crowd-r2: the pile at the slide's foot, staged. One rider is commanded to the slide (the game's own call, `startCommandedDecor`), two standers stand in the pocket at the
//  landing on the path side (S1: idle and held by the quiet lab; S2: in a standing pair social, restarted when it ends). Everything is measured and printed, nothing is asserted
//  on the numbers: the same test runs on the base and on the head.
//

import XCTest
import simd
@testable import BobV1

@MainActor
final class ParkSlideCrowdTests: XCTestCase {
    nonisolated(unsafe) static var keep: [AnyObject] = []

    override func setUp() {
        DecorField.shared.clear(); DecorField.shared.toys = ToyBook(); ToyTuning.settle = 0
    }
    override func tearDown() {
        DecorField.shared.clear(); ToyTuning.settle = 5
        GameCamera.endPark(count: 3); _ = GameCamera.camera(aspect: 440.0 / 956.0)
        GameCamera.configureRoom(count: 1); GameCamera.clearRoam(); RoomLayout.apply(RoomCatalog.home)
    }

    func parkLab(seed: UInt64) -> SocialTests.Lab {
        DecorField.shared.clear(); DecorField.shared.toys = ToyBook(); ToyTuning.settle = 0
        for (uid, ps) in HopscotchLine.shared.lines { for pl in ps { HopscotchLine.shared.remove(uid, pl.id) } }
        RoomLayout.apply(RoomCatalog.park); GameCamera.configurePark(); _ = GameCamera.refreshRoam(aspect: 440.0 / 956.0)
        let lab = SocialTests.Lab(n: 3, positions: [SIMD2(-2.1, -1.6), SIMD2(-0.6, 0.5), SIMD2(0.6, -0.8)], quiet: true, seed: seed)
        for r in lab.rigs { r.sim.arenaCenter = GameCamera.arenaCenter; r.sim.arenaRadius = GameCamera.arenaRadius; r.brain.anticsEnabled = true; r.brain.idleMood = .happy; r.brain.outingPlay = true }
        DecorField.shared.set(ParkToys.placed)
        DecorField.shared.toys.news.removeAll()
        return lab
    }

    func place(_ r: MotionRig, _ p: SIMD2<Float>) {
        r.brain.abortScript(r.sim, r.skinner)
        r.sim.teleport(toXZ: p)
        for _ in 0..<120 { r.sim.step() }
        r.brain.currentPose(r.sim)
    }

    struct Result {
        var v: String, start: String, seed: UInt64
        var t1: Float?, t4: Float?, t5: Float?, t6: Float?, tEnd: Float?
        var endNote = ""
        var inBox: Float = 0, pathRatio: Float = 0, march: Float = 0
        var maxSteerWait: Float = 0, maxStuck: Float = 0, maxStall: Float = 0
        var p10: Float = 0, p08: Float = 0, p07: Float = 0, minD: Float = .infinity, minDT: Float = 0
        var platform2: Float = 0, pushedWithBody = false, minAfter: Float = .infinity
        var move1: Float = 0, move2: Float = 0, minStanders: Float = .infinity
        var startedOK = true
        var rode: Bool { t5 != nil && t6 != nil }
    }

    func f(_ x: Float?) -> String { x.map { String(format: "%.1f", $0) } ?? "-" }

    func scene(variant: String, start: Int, seed: UInt64) -> (Result, String) {
        let lab = parkLab(seed: seed)
        let sl = DecorField.shared.foot(ParkToys.slideUID)!
        let gap = MelonController.jellyGap
        let landing = sl.centre + sl.turned(SIMD2(0, BlobBrain.slideAt(BlobBrain.slideLength).z))
        let half = sl.quarter & 1 == 0 ? sl.spec.half : SIMD2(sl.spec.half.y, sl.spec.half.x)
        let climb = sl.centre + sl.turned(SIMD2(0, -DecorKind.slideApproach))
        let rider = lab.rigs[0], b0 = rider.brain
        let st = [lab.rigs[1], lab.rigs[2]]
        let want1 = landing + SIMD2(-0.8 * b0.peerGap, 0)
        let want2 = want1 + SIMD2(-0.7, 0.7) * gap
        let sp1 = b0.fixed(want1), sp2 = b0.fixed(want2)
        let mid = (sp1 + sp2) / 2
        let dirC = simd_normalize(mid - climb)
        let starts: [(String, SIMD2<Float>)] = [("F1", landing + SIMD2(0, 1.2)),
                                                ("F2", mid + dirC * 1.6),
                                                ("F3", SIMD2(sl.centre.x - half.x - 1.2, sl.centre.y))]
        let startWant = starts[start].1
        let startPos = b0.fixed(startWant)
        var geo = String(format: "stander spots (%.2f,%.2f) moved by fixed %.2f, (%.2f,%.2f) moved %.2f; landing (%.2f,%.2f); start %@ wanted (%.2f,%.2f) got (%.2f,%.2f) = %.2f from the landing, %.2f from the standers' mid", sp1.x, sp1.y, simd_distance(sp1, want1), sp2.x, sp2.y, simd_distance(sp2, want2), landing.x, landing.y, starts[start].0, startWant.x, startWant.y, startPos.x, startPos.y, simd_distance(startPos, landing), simd_distance(startPos, mid))
        var res = Result(v: variant, start: starts[start].0, seed: seed)
        place(st[0], sp1); place(st[1], sp2); place(rider, startPos)
        for k in 0..<2 { st[k].brain.socialBook.cooldown = 1e6 }
        // S2 helper: the longest standing friendly pair social
        let pairKind = SocialKind.cuddleLean
        for _ in 0..<5 { lab.tick(watching: false) }
        let spots = [sp1, sp2]
        var t: Float = 0
        var started = false, sawStage6 = false
        var hist: [SIMD2<Float>] = []
        var prev = rider.root, straightFrom = rider.root, lastRoot = rider.root, pathLen: Float = 0
        var firstHopPos: SIMD2<Float>?
        var after6: Float? = nil
        var pairStarts = 0
        while t < 45 {
            if !started, t >= 1 {
                started = b0.startCommandedDecor(.decorSlide, only: .slide, rider.sim, rider.skinner)
                if !started { res.startedOK = false; res.endNote = "command refused"; break }
                straightFrom = rider.root; prev = rider.root; lastRoot = rider.root; res.t1 = nil
                hist = []
            }
            if variant == "S2", st[0].brain.socialFree, st[1].brain.socialFree, !st[0].brain.isSocial, !st[1].brain.isSocial {
                if st[0].brain.socialStart(pairKind, with: st[1].brain, st[0].sim) { pairStarts += 1 }
            }
            lab.tick(watching: false); DecorField.shared.tick(dt: 1.0 / 60); t += 1.0 / 60
            let tc = t - 1
            let rr = rider.root
            let s = b0.idleState
            // standers
            for k in 0..<2 {
                let d = simd_distance(st[k].root, spots[k]); if k == 0 { res.move1 = max(res.move1, d) } else { res.move2 = max(res.move2, d) }
            }
            res.minStanders = min(res.minStanders, simd_distance(st[0].root, st[1].root))
            guard started else { continue }
            let onSlide = s.kind == .decorSlide
            // stage timeline
            if onSlide {
                if s.slideStage >= 1, res.t1 == nil { res.t1 = tc; firstHopPos = rr }
                if s.slideStage == 4, res.t4 == nil { res.t4 = tc }
                if s.slideStage == 5, res.t5 == nil {
                    res.t5 = tc
                    res.pushedWithBody = st.contains { simd_distance($0.root, landing) < b0.peerGap }
                }
                if s.slideStage == 6, res.t6 == nil { res.t6 = tc; sawStage6 = true; after6 = 0 }
                if s.slideStage == 4, s.phase == 2 { res.platform2 += 1.0 / 60 }
            }
            if res.t1 == nil {
                // approach
                pathLen += simd_distance(rr, lastRoot); lastRoot = rr
                if sl.distance(rr) < 0 { res.inBox += 1.0 / 60 }
                hist.append(rr); if hist.count > 15 { hist.removeFirst() }
                var walk = false; if case .walk = b0.script { walk = true }
                if walk, hist.count == 15, simd_distance(hist[0], rr) < 0.05 { res.march += 1.0 / 60 }
                res.maxSteerWait = max(res.maxSteerWait, b0.steerWait); res.maxStuck = max(res.maxStuck, b0.stuckT); res.maxStall = max(res.maxStall, b0.walkStallT)
                for k in 0..<2 {
                    let d = simd_distance(rr, st[k].root)
                    if d < 1.0 * gap { res.p10 += 1.0 / 60 }; if d < 0.8 * gap { res.p08 += 1.0 / 60 }; if d < 0.7 * gap { res.p07 += 1.0 / 60 }
                    if d < res.minD { res.minD = d; res.minDT = tc }
                }
            }
            if let a = after6, a <= 1.5 { for k in 0..<2 { res.minAfter = min(res.minAfter, simd_distance(rr, st[k].root)) }; after6 = a + 1.0 / 60 }
            if sawStage6, s.kind == nil, res.tEnd == nil { res.tEnd = tc }
            if let e = res.tEnd, tc >= e + 3 { break }
            if !onSlide, res.t5 == nil, tc > 3, s.kind == nil { res.endNote = "behaviour ended without a ride at \(f(tc)) s, stood at (\(String(format: "%.2f,%.2f", rr.x, rr.y))), \(String(format: "%.2f", sl.distance(rr))) from the slide edge"; break }
            prev = rr
        }
        _ = prev
        if !res.rode, res.endNote.isEmpty { res.endNote = "no ride in 45 s: stage \(b0.idleState.slideStage), kind \(String(describing: b0.idleState.kind)), at (\(String(format: "%.2f,%.2f", rider.root.x, rider.root.y)))" }
        if let h = firstHopPos { res.pathRatio = pathLen / max(simd_distance(straightFrom, h), 0.01) }
        if res.start == "F1", variant == "S1", seed == 1 || true { geo += "" }
        let line = "[scene] v=\(variant) start=\(res.start) seed=\(seed) | t_hop=\(f(res.t1)) t_platform=\(f(res.t4)) t_push=\(f(res.t5)) t_floor=\(f(res.t6)) t_end=\(f(res.tEnd)) | approach: inBox=\(String(format: "%.1f", res.inBox))s pathRatio=\(String(format: "%.2f", res.pathRatio)) march=\(String(format: "%.1f", res.march))s maxSteerWait=\(String(format: "%.1f", res.maxSteerWait)) maxStuckT=\(String(format: "%.1f", res.maxStuck)) maxWalkStallT=\(String(format: "%.1f", res.maxStall)) | press<1.0=\(String(format: "%.1f", res.p10)) <0.8=\(String(format: "%.1f", res.p08)) <0.7=\(String(format: "%.1f", res.p07)) minD=\(String(format: "%.2f", res.minD))@\(String(format: "%.1f", res.minDT)) | platformPh2=\(String(format: "%.1f", res.platform2))s pushedWithBodyInPeerGap=\(res.pushedWithBody ? "yes" : "no") minD1.5sAfterFloor=\(String(format: "%.2f", res.minAfter)) | standersMoved=\(String(format: "%.2f", res.move1))/\(String(format: "%.2f", res.move2)) minBetweenStanders=\(String(format: "%.2f", res.minStanders)) pairStarts=\(pairStarts) | \(res.endNote)"
        return (res, line + "\n   " + geo)
    }

    func med(_ a: [Float]) -> Float { let s = a.sorted(); return s.isEmpty ? 0 : s[s.count / 2] }

    func testMeasureSlideScene() {
        let seeds = Int(ProcessInfo.processInfo.environment["CROWD_SEEDS"] ?? "") ?? 4
        var lines: [String] = [], all: [Result] = []
        for v in ["S1", "S2"] { for st in 0..<3 { for k in 0..<seeds {
            let (r, line) = scene(variant: v, start: st, seed: 5 + UInt64(k) * 13)
            all.append(r); lines.append(line); MotionLog.write(line)
        } } }
        var o = "# slide scene (park-crowd-r2), \(seeds) seeds per cell, gap \(MelonController.jellyGap)\n\n## per-run lines\n" + lines.joined(separator: "\n") + "\n\n## table (median / worst)\n"
        o += "| variant | start | rode | t_hop med/worst | inBox s | pathRatio | march s | press<0.8 s | press<0.7 s | minD worst | platform ph2 s | pushed with body | minD 1.5 s after floor (worst) | standers moved max |\n|---|---|---|---|---|---|---|---|---|---|---|---|---|---|\n"
        for v in ["S1", "S2"] { for s in ["F1", "F2", "F3"] {
            let c = all.filter { $0.v == v && $0.start == s }
            let h = c.compactMap { $0.t1 }
            o += "| \(v) | \(s) | \(c.filter { $0.rode }.count)/\(c.count) | \(f(med(h))) / \(f(h.max())) | \(f(med(c.map { $0.inBox }))) / \(f(c.map { $0.inBox }.max())) | \(String(format: "%.2f", med(c.map { $0.pathRatio }))) / \(String(format: "%.2f", c.map { $0.pathRatio }.max() ?? 0)) | \(f(med(c.map { $0.march }))) / \(f(c.map { $0.march }.max())) | \(f(med(c.map { $0.p08 }))) / \(f(c.map { $0.p08 }.max())) | \(f(med(c.map { $0.p07 }))) / \(f(c.map { $0.p07 }.max())) | \(String(format: "%.2f", c.map { $0.minD }.min() ?? 0)) | \(f(med(c.map { $0.platform2 }))) / \(f(c.map { $0.platform2 }.max())) | \(c.filter { $0.pushedWithBody }.count)/\(c.count) | \(String(format: "%.2f", c.map { $0.minAfter }.min() ?? 0)) | \(String(format: "%.2f", c.map { max($0.move1, $0.move2) }.max() ?? 0)) |\n"
        } }
        MotionLog.write(o)
        if let dir = ProcessInfo.processInfo.environment["CROWD_OUT"] { try? o.write(toFile: dir + "/slide_scene_raw.md", atomically: true, encoding: .utf8) }
        XCTAssertEqual(all.count, 6 * seeds)
    }
}
