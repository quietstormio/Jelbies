//
//  TeddyClearanceTests.swift
//  The ear / hat clearance in MOTION (numbers, no images): every hat the rule leaves ears beside, through a hop, a walk, a run and a tumble: the closest the ears' drawn
//  surface comes to the hat's drawn surface (CrownFit lifts the hat to the skin every frame, so the rest-pose rule needs a motion check), plus the jiggle and the
//  pom's floor clearance. Env-gated on TEDDY_DIR like the captures (it writes teddy_motion_clearance.txt); the assertions run only then.
//

import XCTest
import simd
import UIKit
@testable import BobV1

extension FeatureCaptureTests {
    /// Dense points (about 1.5 cm) on the triangles of a room mesh from vertex index `from`.
    func denseSurface(_ m: RoomMesh) -> [SIMD3<Float>] {
        var out: [SIMD3<Float>] = []
        var t = 0
        while t + 2 < m.indices.count {
            let a = m.vertices[Int(m.indices[t])].pos, b = m.vertices[Int(m.indices[t + 1])].pos, c = m.vertices[Int(m.indices[t + 2])].pos
            let A = SIMD3(a.x, a.y, a.z), B = SIMD3(b.x, b.y, b.z), C = SIMD3(c.x, c.y, c.z)
            let ext = max(simd_distance(A, B), simd_distance(B, C), simd_distance(A, C))
            let n = max(1, Int((ext / 0.015).rounded(.up)))
            for i in 0...n { for j in 0...(n - i) { let u = Float(i) / Float(n), v = Float(j) / Float(n); out.append(A * (1 - u - v) + B * u + C * v) } }
            t += 3
        }
        return out
    }

    func testTeddyMotionClearance() throws {
        let d = try teddyDir(); teddyTone()
        DayClock.shared.forcedHour = 12
        let hats: [WearLook] = [.flowerCrown, .partyHat, .tophat, .crownGold, .sweatband, .flowerClip, .hairBow, .beeAntennae, .visorTennis]
        typealias Start = (MotionRig) -> Void
        let moves: [(String, Float, Start)] = [
            ("hop", 1.6, { r in r.brain.startHopPlay(sim: r.sim) }),
            ("walk", 2.0, { r in let p = r.sim.bodyPose(iterations: 3).centroid; r.brain.script = .walk(target: SIMD2(p.x - 3, p.y + 0.3), then: .none); r.brain.activity = .walking; r.brain.scriptT = 0 }),
            ("run", 1.6, { r in let p = r.sim.bodyPose(iterations: 3).centroid; r.brain.hurry = true; r.brain.script = .walk(target: SIMD2(p.x - 4, p.y + 0.3), then: .none); r.brain.activity = .walking; r.brain.scriptT = 0 }),
            ("spin", 2.4, { r in r.brain.startSpin(sim: r.sim) }),
            ("shake", 2.0, { r in r.brain.idleForced = true; XCTAssertTrue(r.brain.idleStart(.shake, r.sim)) }),
        ]
        var out = "closest ear-surface to hat-surface distance over the move (u; the ear starts >= 0.030 clear at rest):\n"
        var worst: Float = 9
        for hat in hats {
            for (name, secs, start) in moves {
                W = 400; H = 400
                let c = Char(id: 4, outfit: [.head: hat])
                let lab = setUpLab([SIMD2(0.4, 0.6)], chars: [c], seed: 3)
                let r = lab.rigs[0]
                r.brain.autonomy = false; r.brain.expr.enabled = false
                let dd = dress(lab, [c])
                for _ in 0..<60 { lab.tick(watching: false); r.skinner.jelly.tick(brain: r.brain, sim: r.sim, dt: r.sim.stepDt); tick(dd, 0, r, c) }
                start(r)
                var minD: Float = 9, maxSway: Float = 0
                for t in 0..<Int(secs * 60) {
                    lab.tick(watching: false); r.skinner.jelly.tick(brain: r.brain, sim: r.sim, dt: r.sim.stepDt); tick(dd, 0, r, c)
                    guard t % 6 == 0, let s = dd.feats[0].slot(0) else { continue }
                    maxSway = max(maxSway, simd_length(s.sway))
                    if s.fit.earsHidden || s.scale < 0.99 { continue }
                    let sk = skin(r)
                    let ff = sk.withUnsafeBufferPointer { p in dd.feats[0].frame { _ in p.baseAddress } }
                    let ww = sk.withUnsafeBufferPointer { p in dd.worn[0].frame(theme: RoomTheme(), time: 0.4) { _ in p.baseAddress } }
                    let prep = FeatureMeshes.prepare(.ears, placement: { var pl = FeatureMeshes.Placement(); pl.slide = s.fit.earSlide; return pl }(), body: WearBody.shared)!
                    var earPts: [SIMD3<Float>] = []
                    for part in prep.parts.prefix(2) { for k in 0..<part.count { let p = ff.vertices[part.first + k].pos; earPts.append(SIMD3(p.x, p.y, p.z)) } }
                    var lo = SIMD3<Float>(repeating: .infinity), hi = SIMD3<Float>(repeating: -.infinity)
                    for q in earPts { lo = simd_min(lo, q); hi = simd_max(hi, q) }
                    lo -= 0.08; hi += 0.08
                    let hatPts = denseSurface(ww.opaque).filter { all($0 .>= lo) && all($0 .<= hi) }
                    let sub = earPts.enumerated().filter { $0.offset % 2 == 0 }.map(\.element)
                    for q in sub { for h in hatPts { minD = min(minD, simd_distance(q, h)) } }
                }
                out += String(format: "%@ + %@: min %.3f  (max jiggle %.1f deg)\n", hat.art, name, minD, maxSway)
                worst = min(worst, minD)
            }
        }
        out += String(format: "WORST: %.3f\n", worst)
        try out.write(toFile: d + "/teddy_motion_clearance.txt", atomically: true, encoding: .utf8)
        print(out)
        XCTAssertGreaterThan(worst, 0.004, "an ear came within 4 mm of (or through) a hat in motion")
    }
}
