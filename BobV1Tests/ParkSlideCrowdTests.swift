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

    func parkLab(seed: UInt64, n: Int = 3) -> SocialTests.Lab {
        DecorField.shared.clear(); DecorField.shared.toys = ToyBook(); ToyTuning.settle = 0
        for (uid, ps) in HopscotchLine.shared.lines { for pl in ps { HopscotchLine.shared.remove(uid, pl.id) } }
        RoomLayout.apply(RoomCatalog.park); GameCamera.configurePark(); _ = GameCamera.refreshRoam(aspect: 440.0 / 956.0)
        let lab = SocialTests.Lab(n: n, positions: Array([SIMD2<Float>(-2.1, -1.6), SIMD2(-0.6, 0.5), SIMD2(0.6, -0.8), SIMD2(1.0, 2.7), SIMD2(-0.5, 3.3)].prefix(n)), quiet: true, seed: seed)
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
        let want2 = want1 + SIMD2(-1.0 * gap, 0.3)          // (one gap toward the path; the floor's front edge (z 4.28) leaves no room to go much further to the front)
        let sp1 = b0.fixed(want1), sp2 = b0.fixed(want2)
        let mid = (sp1 + sp2) / 2
        let dirC = simd_normalize(mid - climb)
        let starts: [(String, SIMD2<Float>)] = [("F1", landing + SIMD2(0, 1.2)),
                                                ("F2", mid + dirC * 0.9),
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

    // MARK: r3 - the foot stays free

    /// T1: the three out spots (slide frame) are on open lawn, clear of the landing and the court, one gap apart.
    func testSlideOutSpotsAreOnOpenLawn() {
        let want: [SIMD2<Float>] = [SIMD2(-0.35, 3.5), SIMD2(-0.5, 2.1), SIMD2(-0.5, 0.65)]
        for (name, aspect) in [("portrait", Float(440.0 / 956.0)), ("landscape", Float(956.0 / 440.0))] {
            let lab = parkLab(seed: 5)
            _ = GameCamera.refreshRoam(aspect: aspect)
            let b = lab.rigs[0].brain
            let sl = DecorField.shared.foot(ParkToys.slideUID)!, court = DecorField.shared.foot(ParkToys.hopscotchUID)!
            let landing = b.slideLanding(sl)
            let pts = BlobBrain.slideOutSpots.map { sl.centre + sl.turned($0) }
            let solids = DecorField.shared.feet.filter { $0.spec.solid }
            for (k, q) in pts.enumerated() {
                let c = GameCamera.constrain(SIMD3(q.x, 0, q.y), radius: b.footprint)
                let moved = simd_distance(SIMD2(c.x, c.z), q)
                let sq = HopscotchCourt.squares.map { simd_distance(q, court.centre + court.turned($0)) }.min() ?? 99
                let sd = solids.map { $0.distance(q) }.min() ?? 99
                let others = pts.enumerated().filter { $0.offset != k }.map { simd_distance(q, $0.element) }
                print(String(format: "[spots] %@ #%d world (%.2f,%.2f) onFloor=%@ (moved %.2f) toLanding %.2f nearestSquare %.2f nearestSolid %.2f toOthers %.2f/%.2f", name, k, q.x, q.y, moved < 0.03 ? "yes" : "no", moved, simd_distance(q, landing), sq, sd, others[0], others[1]))
                if name == "portrait" {
                    XCTAssertLessThan(simd_distance(q, want[k]), 0.05, "spot \(k) world point \(q)")
                    XCTAssertGreaterThanOrEqual(simd_distance(q, landing), b.peerGap + 0.3, "spot \(k) to the landing")
                    XCTAssertGreaterThanOrEqual(sq, 1.15, "spot \(k) to the nearest square")
                    XCTAssertGreaterThanOrEqual(others.min() ?? 9, 1.4, "spot \(k) pairwise")
                    XCTAssertLessThan(moved, 0.03, "spot \(k) is on the floor")
                }
            }
        }
    }

    struct FootRide { var started = false, ph2: Float = 0, hold: Float = 0, pushed = false, t6: Float?, exit: SIMD2<Float>?, min5: Float = .infinity }

    /// T2: A rides, then B is commanded to the slide; the standers are free. The foot must be clear for B.
    func foot(seed: UInt64) -> String {
        let lab = parkLab(seed: seed)
        let sl = DecorField.shared.foot(ParkToys.slideUID)!
        let rigs = lab.rigs
        let landing = rigs[0].brain.slideLanding(sl)
        let gap = MelonController.jellyGap
        let peer = rigs[0].brain.peerGap
        let half = sl.quarter & 1 == 0 ? sl.spec.half : SIMD2(sl.spec.half.y, sl.spec.half.x)
        let sp1 = rigs[0].brain.fixed(landing + SIMD2(-0.8 * peer, 0))
        let sp2 = rigs[0].brain.fixed(sp1 + SIMD2(-1.0 * gap, 0.3))
        place(rigs[1], sp1); place(rigs[2], sp2); place(rigs[0], rigs[0].brain.fixed(SIMD2(sl.centre.x - half.x - 1.2, sl.centre.y)))
        for _ in 0..<5 { lab.tick(watching: false) }
        var t: Float = 0
        var R = [FootRide(), FootRide()]
        var aDone = false, lastTry: Float = -1, tries = 0
        var endAt: Float?
        var leftB: Float?, leftC: Float?
        var minPair = Float.infinity, minPairAt = ""
        var pushSeen = [false, false]
        while t < 120 {
            if t >= 1, !R[0].started { R[0].started = rigs[0].brain.startCommandedDecor(.decorSlide, only: .slide, rigs[0].sim, rigs[0].skinner) }
            if aDone, !R[1].started, tries < 21, t - lastTry >= 0.5 {
                lastTry = t; tries += 1
                R[1].started = rigs[1].brain.startCommandedDecor(.decorSlide, only: .slide, rigs[1].sim, rigs[1].skinner)
            }
            lab.tick(watching: false); DecorField.shared.tick(dt: 1.0 / 60); t += 1.0 / 60
            for i in 0..<2 {
                let s = rigs[i].brain.idleState
                let others = i == 0 ? [1, 2] : [0, 2]
                if s.kind == .decorSlide {
                    if s.slideStage == 4, s.phase == 2 { R[i].ph2 += 1.0 / 60; R[i].hold = s.hold }
                    if s.slideStage == 5, !pushSeen[i] { pushSeen[i] = true; R[i].pushed = others.contains { simd_distance(rigs[$0].root, landing) < peer } }
                    if s.slideStage == 6, R[i].t6 == nil { R[i].t6 = t }
                }
                if let s6 = R[i].t6, t - s6 <= 5 {
                    R[i].min5 = min(R[i].min5, others.map { simd_distance(rigs[i].root, rigs[$0].root) }.min()!)
                    if t - s6 > 4.98 { R[i].exit = rigs[i].root }
                }
            }
            if leftB == nil, simd_distance(rigs[1].root, landing) > peer { leftB = t }
            if leftC == nil, simd_distance(rigs[2].root, landing) > peer { leftC = t }
            for a in 0..<3 { for c in (a + 1)..<3 { let d = simd_distance(rigs[a].root, rigs[c].root); if d < minPair { minPair = d; minPairAt = "t=\(String(format: "%.1f", t)) ids \(a),\(c)" } } }
            if !aDone, R[0].t6 != nil, rigs[0].brain.idleState.kind == nil, DecorField.shared.occupant[ParkToys.slideUID] == nil { aDone = true }
            if R[1].t6 != nil, rigs[1].brain.idleState.kind == nil, endAt == nil { endAt = t + 5 }
            if let e = endAt, t >= e { break }
        }
        let A = R[0], B = R[1]
        let court = DecorField.shared.foot(ParkToys.hopscotchUID)!
        let standing = rigs.map { $0.root }
        let sqEnd = standing.map { p in HopscotchCourt.squares.map { simd_distance(p, court.centre + court.turned($0)) }.min() ?? 99 }.min() ?? 99
        func p(_ v: SIMD2<Float>?) -> String { v.map { String(format: "(%.2f,%.2f)", $0.x, $0.y) } ?? "-" }
        func d(_ v: SIMD2<Float>?) -> String { v.map { String(format: "%.2f", simd_distance($0, landing)) } ?? "-" }
        func ft(_ x: Float?) -> String { x.map { String(format: "%.1f", $0) } ?? "-" }
        let line = "[foot] seed=\(seed) | A: platformPh2=\(String(format: "%.1f", A.ph2))s (hold \(String(format: "%.1f", A.hold))) pushedWithBody=\(A.pushed ? "yes" : "no") exit=\(p(A.exit)) exitToLanding=\(d(A.exit)) minD5sAfterFloor=\(String(format: "%.2f", A.min5)) | standers: B leftFootAt=\(ft(leftB))s C leftFootAt=\(ft(leftC))s endB=\(p(standing[1])) endC=\(p(standing[2])) | B: started=\(B.started ? "yes" : "no") (tries \(tries)) platformPh2=\(String(format: "%.1f", B.ph2))s (hold \(String(format: "%.1f", B.hold))) pushedWithBody=\(B.pushed ? "yes" : "no") exit=\(p(B.exit)) exitToLanding=\(d(B.exit)) minD5sAfterFloor=\(String(format: "%.2f", B.min5)) | minPairDistanceWholeRun=\(String(format: "%.2f", minPair))@\(minPairAt) | nearestSquareOfAnyStandingBodyAtEnd=\(String(format: "%.2f", sqEnd)) | end t=\(String(format: "%.1f", t))"
        print(line)
        XCTAssertTrue(A.started && B.started, "seed \(seed): both rode. \(line)")
        for (n, r) in [("A", A), ("B", B)] {
            XCTAssertLessThanOrEqual(r.ph2, r.hold + 1.5, "seed \(seed) \(n) platformPh2. \(line)")
            XCTAssertFalse(r.pushed, "seed \(seed) \(n) pushed with a body inside peerGap. \(line)")
            if let e = r.exit { XCTAssertGreaterThanOrEqual(simd_distance(e, landing), peer + 0.2, "seed \(seed) \(n) exit. \(line)") }
            XCTAssertGreaterThanOrEqual(r.min5, 0.98, "seed \(seed) \(n) minD5sAfterFloor. \(line)")
        }
        XCTAssertGreaterThanOrEqual(minPair, 0.90, "seed \(seed) whole-run minimum pair distance. \(line)")
        return line
    }

    func testFootClearsForTheNextRider() {
        var lines: [String] = []
        for seed in UInt64(1)...4 { lines.append(foot(seed: seed)) }
        if let dir = ProcessInfo.processInfo.environment["CROWD_OUT"] { try? lines.joined(separator: "\n").write(toFile: dir + "/foot_lines.txt", atomically: true, encoding: .utf8) }
    }

    // MARK: r4 - a stander inside the slide's zone steps off

    func bState(_ b: BlobBrain, _ f: DecorFoot, _ landing: SIMD2<Float>, _ t: Float) -> String {
        "[stepoff-t] t=\(String(format: "%.2f", t)) script=\(b.scriptKindName) act=\(b.activity) pending=\(String(describing: b.pending)) interrupt=\(b.interruptScript) pos=(\(String(format: "%.2f,%.2f", b.position.x, b.position.y))) yaw=\(String(format: "%.2f", b.yaw)) feetActive=\(b.feet.active) steerWait=\(String(format: "%.2f", b.steerWait)) walkStallT=\(String(format: "%.2f", b.walkStallT)) scriptT=\(String(format: "%.2f", b.scriptT)) decorIgnore=\(String(describing: b.decorIgnore)) insideDecorT=\(String(format: "%.2f", b.insideDecorT)) insideStuckT=\(String(format: "%.2f", b.insideStuckT)) dLanding=\(String(format: "%.2f", simd_distance(b.position, landing))) dBox=\(String(format: "%.2f", f.distance(b.position))) walkOutFrom=\(String(describing: b.walkOutFrom))"
    }

    func stepoff(variant: String, seed: UInt64, spotB: SIMD2<Float>, spotC: SIMD2<Float>) -> String {
        let lab = parkLab(seed: seed)
        let sl = DecorField.shared.foot(ParkToys.slideUID)!
        let rigs = lab.rigs
        let landing = rigs[0].brain.slideLanding(sl)
        let peer = rigs[0].brain.peerGap
        place(rigs[1], spotB); place(rigs[2], spotC); place(rigs[0], rigs[0].brain.fixed(SIMD2(-1.6, 4.3)))
        for _ in 0..<5 { lab.tick(watching: false) }
        let b = rigs[1].brain
        var t: Float = 0, tCmd: Float = -1
        var started = false, walkStarts = 0, walkStartsWin = 0, prevNone = true
        var leftAt: Float?
        var minBox = sl.distance(b.position); let startBox = minBox
        var stuckRun: Float = 0, stuckMax: Float = 0, lastPos = b.position, lastChk: Float = 0
        var ph2: Float = 0, hold: Float = 0, t6: Float?, minD: Float = .infinity, endAt: Float?
        while t < 60 {
            if t >= 1, !started { started = rigs[0].brain.startCommandedDecor(.decorSlide, only: .slide, rigs[0].sim, rigs[0].skinner); tCmd = t }
            lab.tick(watching: false); DecorField.shared.tick(dt: 1.0 / 60); t += 1.0 / 60
            var isNone = true; if case .none = b.script { isNone = true } else { isNone = false }
            if prevNone, case .walk = b.script { walkStarts += 1; if started, t - tCmd <= (leftAt ?? 1e9) + 3 { walkStartsWin += 1 } }          // (walkStartsWin: from the command until 3 s after he is off the foot; walkStarts also counts his later own walks)
            prevNone = isNone
            if started, leftAt == nil, simd_distance(b.position, landing) >= peer { leftAt = t - tCmd }
            minBox = min(minBox, sl.distance(b.position))
            if t - lastChk >= 0.5 {
                var walking = false; if case .walk = b.script { walking = true }
                if walking, simd_distance(b.position, lastPos) < 0.05 { stuckRun += 0.5; stuckMax = max(stuckMax, stuckRun) } else { stuckRun = 0 }
                lastPos = b.position; lastChk = t
            }
            if Int(t * 60) % 15 == 0 { print(bState(b, sl, landing, t)) }
            let s = rigs[0].brain.idleState
            if s.kind == .decorSlide {
                if s.slideStage == 4, s.phase == 2 { ph2 += 1.0 / 60; hold = s.hold }
                if s.slideStage == 6, t6 == nil { t6 = t }
            }
            if let s6 = t6, t - s6 <= 1.5 { minD = min(minD, [1, 2].map { simd_distance(rigs[0].root, rigs[$0].root) }.min()!) }
            if t6 != nil, rigs[0].brain.idleState.kind == nil, endAt == nil { endAt = t + 3 }
            if let e = endAt, t >= e { break }
        }
        func ft(_ x: Float?) -> String { x.map { String(format: "%.1f", $0) } ?? "-" }
        let line = "[stepoff] v=\(variant) seed=\(seed) walkStartsWin=\(walkStartsWin) walkStartsAll=\(walkStarts) leftFootAt=\(ft(leftAt))s stuckMax=\(String(format: "%.1f", stuckMax))s minBox=\(String(format: "%.2f", minBox)) (start \(String(format: "%.2f", startBox))) A: platformPh2=\(String(format: "%.1f", ph2))s (hold \(String(format: "%.1f", hold))) minD1.5sAfterFloor=\(String(format: "%.2f", minD)) rode=\(t6 != nil) end t=\(String(format: "%.1f", t))"
        print(line)
        XCTAssertNotNil(leftAt, "\(line)")
        if let l = leftAt { XCTAssertLessThanOrEqual(l, 8, "leftFootAt. \(line)") }
        XCTAssertLessThanOrEqual(walkStartsWin, 2, "walkStartsWin. \(line)")
        XCTAssertLessThanOrEqual(stuckMax, 3, "stuckMax. \(line)")
        XCTAssertGreaterThanOrEqual(minBox, min(startBox, 0.15) - 0.05, "minBox. \(line)")
        XCTAssertLessThanOrEqual(ph2, hold + 1.5, "A platformPh2. \(line)")
        XCTAssertGreaterThanOrEqual(minD, 0.98, "A minD. \(line)")
        return line
    }

    func testStanderInsideTheSlideZoneStepsOff() {
        for seed in UInt64(1)...4 {
            _ = stepoff(variant: "V1", seed: seed, spotB: SIMD2(2.3, 2.9), spotC: SIMD2(1.58, 2.73))
            _ = stepoff(variant: "V2", seed: seed, spotB: SIMD2(1.76, 3.23), spotC: SIMD2(0.38, 3.49))
        }
    }

    /// Measurement only: the generic walk-out of `decorExitCheck` (no slide ride at all).
    func testMeasureGenericWalkOut() {
        for (name, withFriend) in [("alone", false), ("friend", true)] { for seed in UInt64(1)...2 {
            let lab = parkLab(seed: seed)
            let sl = DecorField.shared.foot(ParkToys.slideUID)!
            let rigs = lab.rigs, b = rigs[1].brain
            place(rigs[0], rigs[0].brain.fixed(SIMD2(-2.6, -1.0))); place(rigs[2], withFriend ? SIMD2(1.58, 2.73) : rigs[0].brain.fixed(SIMD2(-3.0, 0.5))); place(rigs[1], SIMD2(2.3, 2.9))
            for _ in 0..<5 { lab.tick(watching: false) }
            let landing = b.slideLanding(sl)
            var t: Float = 0, walkStarts = 0, prevNone = true
            var outAt: Float?
            while t < 20 {
                lab.tick(watching: false); DecorField.shared.tick(dt: 1.0 / 60); t += 1.0 / 60
                var isNone = true; if case .none = b.script { isNone = true } else { isNone = false }
                if prevNone, case .walk = b.script { walkStarts += 1 }
                prevNone = isNone
                if outAt == nil, sl.distance(b.position) >= b.footprint * sl.spec.reach + 0.05 { outAt = t }
                if Int(t * 60) % 15 == 0 { print(bState(b, sl, landing, t)) }
            }
            print("[walkout] case=\(name) seed=\(seed) walkStarts=\(walkStarts) outOfZoneAt=\(outAt.map { String(format: "%.1f", $0) } ?? "-")s")
        } }
    }

    // MARK: r5 - the ex-rider leaves when the lawn spots are taken

    /// The ex-rider (A, from F3) with a friend parked on each of the three out spots (5 bodies): `slideWalkOut` has nothing from the spots. He must still be off the landing within 6 s of touching the floor, never inside the box, with at most 3 walk starts.
    func testExRiderLeavesWhenTheLawnSpotsAreTaken() {
        for seed in UInt64(1)...3 {
            let lab = parkLab(seed: seed, n: 5)
            let sl = DecorField.shared.foot(ParkToys.slideUID)!
            let rigs = lab.rigs, a = rigs[0].brain
            let landing = a.slideLanding(sl), peer = a.peerGap
            let half = sl.quarter & 1 == 0 ? sl.spec.half : SIMD2(sl.spec.half.y, sl.spec.half.x)
            for k in 0..<3 { place(rigs[1 + k], sl.centre + sl.turned(BlobBrain.slideOutSpots[k])) }          // (a friend on every out spot: all three are refused)
            place(rigs[4], a.fixed(SIMD2(-2.4, -1.6))); place(rigs[0], a.fixed(SIMD2(sl.centre.x - half.x - 1.2, sl.centre.y)))
            for _ in 0..<5 { lab.tick(watching: false) }
            var t: Float = 0, started = false, t6: Float?, prevNone = true, walkStarts = 0
            var refusedAtFloor: String = "?", leftAt: Float?, minBox = Float.infinity
            while t < 60 {
                if t >= 1, !started { started = a.startCommandedDecor(.decorSlide, only: .slide, rigs[0].sim, rigs[0].skinner) }
                lab.tick(watching: false); DecorField.shared.tick(dt: 1.0 / 60); t += 1.0 / 60
                let s = a.idleState
                if s.kind == .decorSlide, s.slideStage == 6, t6 == nil { t6 = t; refusedAtFloor = a.slideWalkOut(sl) == nil ? "nil (all spots refused)" : "has a spot" }
                guard let f6 = t6 else { continue }
                var isNone = true; if case .none = a.script { isNone = true } else { isNone = false }
                if prevNone, case .walk = a.script { walkStarts += 1 }
                prevNone = isNone
                if t - f6 >= 1.5 { minBox = min(minBox, sl.distance(a.position)) }
                if leftAt == nil, simd_distance(a.position, landing) >= peer { leftAt = t - f6 }
                if Int(t * 60) % 30 == 0 { print(bState(a, sl, landing, t - f6)) }
                if t - f6 > 10 { break }
            }
            func ft(_ x: Float?) -> String { x.map { String(format: "%.1f", $0) } ?? "-" }
            let line = "[exrider] seed=\(seed) slideWalkOut at the floor: \(refusedAtFloor) | leftLandingAt=\(ft(leftAt))s after the floor walkStarts=\(walkStarts) minBox(after 1.5 s)=\(String(format: "%.2f", minBox)) rode=\(t6 != nil)"
            print(line)
            XCTAssertNotNil(t6, line)
            XCTAssertNotNil(leftAt, line)
            if let l = leftAt { XCTAssertLessThanOrEqual(l, 6, "off the landing within 6 s. \(line)") }
            XCTAssertLessThanOrEqual(walkStarts, 3, "walkStarts. \(line)")
            XCTAssertGreaterThanOrEqual(minBox, 0, "never inside the box. \(line)")
        }
    }
}
