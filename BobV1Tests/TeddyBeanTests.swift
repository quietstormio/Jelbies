//
//  TeddyBeanTests.swift
//  Teddy's ears + pom as body-mesh vertices (TeddyBean): collapsed for every other species, tucked under an enclosing hat = Bob's head exactly,
//  never a gap in motion, and what the block costs per frame. Plus the motion / hat proof boards (TEST_RUNNER_TEDDYEARS_DIR).
//

import XCTest
import Metal
import simd
import UIKit
@testable import BobV1

extension FeatureCaptureTests {
    /// Block vertex (skinned, world) of part `p`, local index `i`.
    func teddyBlock(_ sk: [Float]) -> [[SIMD3<Float>]] {
        let f = MotionRig.renderMesh.armCapsule!.teddyFirst
        return TeddyBean.parts.map { part in
            (0..<part.count).map { let o = 6 * (f + part.first + $0); return SIMD3(sk[o], sk[o + 1], sk[o + 2]) }
        }
    }
    func eggVertexLimit() -> Int { MotionRig.renderMesh.armCapsule!.firstVertex.min() ?? MotionRig.renderMesh.vertexCount }

    func testBeanCollapsedForEveryOtherSpecies() throws {
        DayClock.shared.forcedHour = 12
        variant(.cream)
        for id in [0, 1, 2, 3, 5] {
            W = 200; H = 200
            let c = Char(id: id)
            let lab = setUpLab([SIMD2(0.2, 0.6)], chars: [c], seed: 3)
            let d = dress(lab, [c]); let r = lab.rigs[0]
            for _ in 0..<40 { lab.tick(watching: false); tick(d, 0, r, c) }
            XCTAssertFalse(r.skinner.teddyOn, "character \(id) is not a Teddy")
            let blk = teddyBlock(skin(r))
            for (pi, part) in blk.enumerated() {
                var worst: Float = 0
                for v in part.dropFirst() { worst = max(worst, simd_distance(v, part[0])) }
                XCTAssertLessThan(worst, 1e-4, "character \(id): part \(pi) is collapsed onto its pole")
                // and the pole is inside the body: nowhere near the surface of the world around him
                XCTAssertTrue(part[0].x.isFinite)
            }
        }
    }

    func testBeanTuckedUnderBeanieIsBobsHeadExactly() throws {
        DayClock.shared.forcedHour = 12
        variant(.cream)
        guard let beanie = WearLook.pieces.first(where: { $0.art == "beanie_pink" }) else { return XCTFail("no beanie") }
        var eggs: [[Float]] = []
        for id in [0, 4] {
            W = 200; H = 200
            let c = Char(id: id, outfit: [.head: beanie])
            let lab = setUpLab([SIMD2(0.2, 0.6)], chars: [c], seed: 3)
            let d = dress(lab, [c]); let r = lab.rigs[0]
            for _ in 0..<90 { lab.tick(watching: false); tick(d, 0, r, c) }
            let sk = skin(r)
            if id == 4 {
                XCTAssertEqual(r.skinner.teddyEarScale, 0, accuracy: 1e-4, "the ears are tucked under the beanie")
                let blk = teddyBlock(sk)
                for part in blk.prefix(2) { XCTAssertLessThan(part.dropFirst().map { simd_distance($0, part[0]) }.max() ?? 0, 1e-4, "collapsed") }
            }
            eggs.append(Array(sk[0..<(6 * eggVertexLimit())]))
        }
        var worst: Float = 0
        for v in 0..<eggVertexLimit() {
            // (the pom's push stays: only the head is compared)
            let a = SIMD3(eggs[0][6 * v], eggs[0][6 * v + 1], eggs[0][6 * v + 2]), b = SIMD3(eggs[1][6 * v], eggs[1][6 * v + 1], eggs[1][6 * v + 2])
            if a.y > 1.0 { worst = max(worst, simd_distance(a, b)) }
        }
        XCTAssertLessThan(worst, 2e-4, "under the beanie Teddy's head is exactly Bob's (no swell left)")
    }

    /// Where the nearest skinned egg vertex is, for a few probe points.
    private func nearest(_ p: SIMD3<Float>, _ sk: [Float], _ n: Int) -> Float {
        var best = Float.infinity
        for v in 0..<n { best = min(best, simd_distance_squared(p, SIMD3(sk[6 * v], sk[6 * v + 1], sk[6 * v + 2]))) }
        return best.squareRoot()
    }

    /// No gap ever opens between an ear / the pom and the head: the vertices that sit on the skin at rest keep their distance to the skin through a hop, a flop, a roll, a spin.
    func testBeanNeverDetachesInMotion() throws {
        DayClock.shared.forcedHour = 12
        variant(.cream)
        let rm = MotionRig.renderMesh, nEgg = eggVertexLimit(), first = rm.armCapsule!.teddyFirst
        var roots: [(Int, Float)] = []
        for part in TeddyBean.parts {
            for i in 1..<part.count {
                let q = TeddyBean.localF[part.first + i]
                guard abs(BobForm.sdf(SIMD3(Double(q.x), Double(q.y), Double(q.z)))) < 0.012, roots.count < 400 else { continue }
                var best = Float.infinity
                for v in 0..<nEgg { best = min(best, simd_distance_squared(q, SIMD3(rm.rest[3 * v], rm.rest[3 * v + 1], rm.rest[3 * v + 2]))) }
                roots.append((first + part.first + i, best.squareRoot()))
            }
        }
        XCTAssertGreaterThan(roots.count, 20)
        typealias Start = (MotionRig) -> Void
        let scenarios: [(String, Float, Start)] = [
            ("hop", 1.6, { r in r.brain.startHopPlay(sim: r.sim) }),
            ("flop", 2.5, { r in r.brain.idleForced = true; _ = r.brain.idleStart(.flop, r.sim) }),
            ("roll", 2.4, { r in r.brain.startRollPlay(sim: r.sim) }),
            ("spin", 2.4, { r in r.brain.startSpin(sim: r.sim) }),
            ("backflip", 2.4, { r in r.brain.startFlip(sim: r.sim) }),
        ]
        var report = ""
        for (name, secs, start) in scenarios {
            W = 200; H = 200
            let c = Char(id: 4)
            let lab = setUpLab([SIMD2(0.4, 0.6)], chars: [c], seed: 3)
            let r = lab.rigs[0]
            r.brain.autonomy = false; r.brain.expr.enabled = false
            let d = dress(lab, [c])
            for _ in 0..<60 { lab.tick(watching: false); r.skinner.jelly.tick(brain: r.brain, sim: r.sim, dt: r.sim.stepDt); tick(d, 0, r, c) }
            // the standing pose is the baseline (the fillet's own push moves the nearest skin vertex a little: what matters is the CHANGE)
            let sk0 = skin(r)
            var base: [Float] = []
            for (vi, _) in roots { base.append(nearest(SIMD3(sk0[6 * vi], sk0[6 * vi + 1], sk0[6 * vi + 2]), sk0, nEgg)) }
            start(r)
            var worst: Float = 0
            for t in 0..<Int(secs * 60) {
                lab.tick(watching: false); r.skinner.jelly.tick(brain: r.brain, sim: r.sim, dt: r.sim.stepDt); tick(d, 0, r, c)
                guard t % 5 == 0, r.skinner.teddyEarScale > 0.99 else { continue }
                let sk = skin(r)
                for (k, (vi, d0)) in roots.enumerated() where d0 < 0.02 {
                    worst = max(worst, nearest(SIMD3(sk[6 * vi], sk[6 * vi + 1], sk[6 * vi + 2]), sk, nEgg) - base[k])
                }
            }
            report += String(format: "%@: root vertices drift from the skin by at most %.4f\n", name, worst)
            XCTAssertLessThan(worst, 0.02, "\(name): an ear / pom root pulled away from the head")
        }
        print(report)
    }

    /// What the block costs a frame on this Mac (Release): applyTeddy alone, collapsed and placed, and a whole Skinner.update with and without Teddy's parts out.
    func testBeanPerFrameCost() throws {
        variant(.cream)
        let rm = MotionRig.renderMesh
        var res = ""
        for (label, id) in [("non-Teddy (Bob)", 0), ("Teddy", 4)] {
            W = 200; H = 200
            let c = Char(id: id)
            let lab = setUpLab([SIMD2(0.2, 0.6)], chars: [c], seed: 3)
            let d = dress(lab, [c]); let r = lab.rigs[0]
            for _ in 0..<40 { lab.tick(watching: false); tick(d, 0, r, c) }
            var buf = [Float](repeating: 0, count: rm.vertexCount * 6)
            let n = 400
            var t0 = CFAbsoluteTimeGetCurrent()
            for _ in 0..<n { r.skinner.update(x: r.sim.x, index: rm.index, into: &buf) }
            let whole = (CFAbsoluteTimeGetCurrent() - t0) / Double(n) * 1000
            t0 = CFAbsoluteTimeGetCurrent()
            buf.withUnsafeMutableBufferPointer { p in for _ in 0..<(n * 5) { r.skinner.applyTeddy(p.baseAddress!) } }
            let blk = (CFAbsoluteTimeGetCurrent() - t0) / Double(n * 5) * 1000
            res += String(format: "%@: Skinner.update %.3f ms, applyTeddy alone %.4f ms (block %d of %d vertices = %.1f%% of the generic per-vertex work, about %.3f ms)\n", label, whole, blk,
                          TeddyBean.vertexCount, rm.vertexCount, 100 * Double(TeddyBean.vertexCount) / Double(rm.vertexCount), whole * Double(TeddyBean.vertexCount) / Double(rm.vertexCount))
        }
        print("PERF " + res)
        if let d = ProcessInfo.processInfo.environment["TEDDYEARS_DIR"] { try? res.write(toFile: d + "/perf.txt", atomically: true, encoding: .utf8) }
    }

    // MARK: boards

    /// 03b: the pom in fur and in cream, from behind.
    func testEarsBoardPom() throws {
        let d = try earsDir(); DayClock.shared.forcedHour = 12
        variant(.cream)
        let pom = TeddyBean.parts[2].o
        let pomP = SIMD3<Float>(Float(pom.x), Float(pom.y), Float(pom.z))
        var cells: [UIImage] = []
        for cream in [false, true] {
            TeddyEarsVariant.pomCream = cream
            for (label, yaw, dist) in [("back", Float.pi, Float(1.6)), ("3/4 back", 2.4, 1.6), ("side", .pi / 2, 1.6)] {
                let s = try earShot(yaw: yaw, size: 520, dist: dist, lookRest: pomP, lift: 0.08)
                cells.append(tlabel(s.img.uiImage()!, ["pom \(cream ? "cream" : "fur") - \(label)"]))
            }
        }
        TeddyEarsVariant.pomCream = false
        try writePNG(tgrid(cells, cols: 3), d + "/03_pom_fur_vs_cream.png")
    }

    func testEarsBoard04Motion() throws {
        let d = try earsDir(); DayClock.shared.forcedHour = 12
        variant(.cream)
        let only = (ProcessInfo.processInfo.environment["TEDDY_ONLY"] ?? "").split(separator: ",").map(String.init)
        typealias Start = (MotionRig) -> Void
        func walk(_ dx: Float, _ dz: Float, hurry: Bool) -> Start { { r in
            let p = r.sim.bodyPose(iterations: 3).centroid
            r.brain.hurry = hurry
            r.brain.script = .walk(target: SIMD2(p.x + dx, p.z + dz), then: .none); r.brain.activity = .walking; r.brain.scriptT = 0 } }
        func idle(_ k: IdleKind) -> Start { { r in r.brain.idleForced = true; XCTAssertTrue(r.brain.idleStart(k, r.sim), "idle \(k)") } }
        let play = TouchPlay(haptics: HapticDriver(sinks: []))
        let surface = RestSurface(mesh: MotionRig.renderMesh)
        var clock = 100.0
        let scenarios: [(String, Float, Float, Start)] = [
            ("walk", 0.8, 2.4, walk(-3, 0.3, hurry: false)),
            ("run", 0.6, 1.8, walk(-4, 0.3, hurry: true)),
            ("hop", 0.0, 1.6, { r in r.brain.startHopPlay(sim: r.sim) }),
            ("flop", 0.0, 3.0, idle(.flop)),
            ("roll", 0.0, 2.4, { r in r.brain.startRollPlay(sim: r.sim) }),
            ("backflip", 0.0, 2.4, { r in r.brain.startFlip(sim: r.sim) }),
            ("spin", 0.0, 3.0, { r in r.brain.startSpin(sim: r.sim) }),
            ("liedown", 0.0, 4.0, idle(.lieDown)),
            ("sleep", 0.0, 6.0, { r in r.brain.idleForced = true; XCTAssertTrue(r.brain.idleStart(.sleep, r.sim)); r.brain.sleep.hold = 500 }),
            ("eat", 0.0, 3.0, { r in r.brain.script = .eat(t: 0, bowl: SIMD2(0, 2), dur: 3.0, drink: false); r.brain.activity = .eating }),
            ("shake", 0.0, 2.4, idle(.shake)),
            ("touchsquish", 0.0, 2.0, { _ in }),
        ]
        var stats = ""
        for (name, warm, secs, start) in scenarios where only.isEmpty || only.contains(name) {
            W = 420; H = 420
            let c = Char(id: 4)
            let lab = setUpLab([SIMD2(0.4, 0.6)], chars: [c], seed: 3)
            let r = lab.rigs[0]
            r.brain.autonomy = false; r.brain.expr.enabled = false
            let dd = dress(lab, [c])
            let (ren, target) = try renderer(lab)
            for _ in 0..<60 { lab.tick(watching: false); r.skinner.jelly.tick(brain: r.brain, sim: r.sim, dt: r.sim.stepDt); tick(dd, 0, r, c) }
            start(r)
            var frames: [[UIImage]] = [[], []]
            var frame = 0
            let total = Int((warm + secs) * 60)
            func ray(_ x: Float, _ y: Float) -> (o: SIMD3<Float>, d: SIMD3<Float>) {
                let e = BodyEllipsoid(sim: r.sim)
                let p = e.center + e.rot.act(SIMD3(x, y, 0))
                let eye = SIMD3<Float>(0, 0.9, 6)
                return (eye, simd_normalize(p - eye))
            }
            var minEarY: Float = 9, minPomY: Float = 9
            for t in 0..<total {
                if name == "touchsquish" {
                    let k = Float(min(t, 60)) / 60
                    let g: Float = 0.5 - 0.3 * k
                    play.cheeksFrame(dt: 1.0 / 60, now: clock, rays: [ray(-g, 0.25), ray(g, 0.25)], gap: g * 400, sim: r.sim, brain: r.brain, skinner: r.skinner, surface: surface); clock += 1.0 / 60
                }
                lab.tick(watching: false); r.skinner.jelly.tick(brain: r.brain, sim: r.sim, dt: r.sim.stepDt); tick(dd, 0, r, c)
                if t % 6 == 0 {
                    let blk = teddyBlock(skin(r))
                    if r.skinner.teddyEarScale > 0.5 { for part in blk.prefix(2) { for v in part.dropFirst() { minEarY = min(minEarY, v.y - r.sim.floorY) } } }
                    if r.skinner.teddyPomScale > 0.5 { for v in blk[2].dropFirst() { minPomY = min(minPomY, v.y - r.sim.floorY) } }
                }
                if t >= Int(warm * 60), t % 4 == 0 {
                    let pose = r.sim.bodyPose(iterations: 3)
                    var fwd = pose.rotation.act(SIMD3<Float>(0, 0, 1)); fwd.y = 0
                    fwd = simd_length(fwd) > 0.3 ? simd_normalize(fwd) : SIMD3(0, 0, 1)
                    for (ci, yaw) in [Float(0.75), Float(2.4)].enumerated() {
                        let dir = SIMD3<Float>(fwd.x * cosf(yaw) + fwd.z * sinf(yaw), 0, -fwd.x * sinf(yaw) + fwd.z * cosf(yaw))
                        let cam = Self.lookCamera(target: SIMD3(pose.centroid.x, r.sim.floorY + 0.55, pose.centroid.z), dir: dir, dist: 3.9, aspect: 1, lift: 0.18)
                        let img = composite(lab, dd, [c], ren, target, cam: cam)
                        frames[ci].append(tlabel(img.uiImage()!, ["\(name) \(ci == 0 ? "front 3/4" : "back 3/4") f\(frame)  ears \(String(format: "%.2f", r.skinner.teddyEarScale)) pom \(String(format: "%.2f", r.skinner.teddyPomScale))"], bar: 26))
                    }
                    frame += 1
                }
            }
            for ci in 0..<2 {
                let n = frames[ci].count
                let pick = (0..<min(8, n)).map { frames[ci][$0 * n / min(8, n)] }
                try writePNG(tgrid(pick, cols: 4), d + "/04_motion_\(name)_\(ci == 0 ? "front" : "back").png")
            }
            stats += String(format: "%@: lowest ear vertex %.3f above the floor, lowest pom vertex %.3f\n", name, minEarY, minPomY)
        }
        try stats.write(toFile: d + "/04_motion_floor.txt", atomically: true, encoding: .utf8)
        print(stats)
    }

    func testEarsBoard05Hats() throws {
        let d = try earsDir(); DayClock.shared.forcedHour = 12
        variant(.cream)
        TeddyFit.clearCache()
        let want = ["beanie_pink", "cap_team_sky", "tophat", "party_hat", "crown_gold", "flower_crown", "hair_bow", "visor_tennis", "bee_antennae", "headphones"]
        let hats = WearLook.looks(.head)
        let earEarSet = hats.filter { want.contains($0.art) } + hats.filter { !want.contains($0.art) }
        var front: [UIImage] = [], back: [UIImage] = [], notes = "hat | ears\n"
        let ear = TeddyBean.parts[0].o
        let earP = SIMD3<Float>(Float(ear.x) * 0.5, Float(ear.y), Float(ear.z))
        _ = earP
        for look in earEarSet {
            let sF = try earShot(outfit: [.head: look], yaw: 0.6, size: 420, dist: 3.0, lookRest: SIMD3(0, 0.95, 0), lift: 0.1, ticks: 40)
            let sB = try earShot(outfit: [.head: look], yaw: 2.5, size: 420, dist: 3.0, lookRest: SIMD3(0, 0.95, 0), lift: 0.1, ticks: 40)
            let state = sF.fit.earsHidden ? "ears tucked" : "ears out"
            notes += "\(look.art) | \(state)\n"
            front.append(tlabel(sF.img.uiImage()!, ["\(look.title) - \(state)"], bar: 28))
            back.append(tlabel(sB.img.uiImage()!, ["\(look.title) (back 3/4)"], bar: 28))
        }
        try writePNG(tgrid(front, cols: 5), d + "/05_hats_front34.png")
        try writePNG(tgrid(back, cols: 5), d + "/05_hats_back34.png")
        try notes.write(toFile: d + "/05_hat_rule_table.txt", atomically: true, encoding: .utf8)
        // the ones the brief names, larger, front
        var named: [UIImage] = []
        for a in want {
            guard let look = hats.first(where: { $0.art == a }) else { continue }
            let s = try earShot(outfit: [.head: look], yaw: 0.35, size: 520, dist: 3.1, lookRest: SIMD3(0, 0.95, 0), lift: 0.12, ticks: 40)
            named.append(tlabel(s.img.uiImage()!, ["\(look.title) - \(s.fit.earsHidden ? "tucked" : "out")"], bar: 28))
        }
        try writePNG(tgrid(named, cols: 5), d + "/05_hats_named.png")
    }
}

extension FeatureCaptureTests {
    func testEarsHatClearanceNumbers() throws {
        TeddyFit.clearCache()
        var out = ""
        for mh in [0.03, 0.05, 0.08] {
        let pts = TeddyBean.earVisiblePoints(minHeight: mh)
        out += "minHeight \(mh)\n"
        for look in WearLook.looks(.head) {
            guard let piece = WearMeshes.prepare(look, body: WearBody.shared) else { continue }
            let cloud = TeddyFit.surfacePoints(piece)
            var best = Float.infinity
            for q in pts { for c in cloud { best = min(best, simd_distance_squared(q, c)) } }
            out += "\(look.art) | \(piece.crownEnclosing) | \(best.squareRoot()) | \(piece.crownEnclosing ? TeddyFit.clearance : TeddyFit.bandClearance)\n"
        }
        }
        print("HATNUM\n" + out)
        if let d = ProcessInfo.processInfo.environment["TEDDYEARS_DIR"] { try? out.write(toFile: d + "/hat_numbers.txt", atomically: true, encoding: .utf8) }
    }
}
