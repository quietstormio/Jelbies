//
//  BallSolidCaptureTests.swift
//  Not a regression test: before/after motion strips for solid balls, with the REAL renderer, when FURN_CAP_DIR is set. Each strip is 6 frames:
//  a_walk (Bob walks into the beach ball), b_drag (dragged into the soccer ball against the sofa), c_balls (two balls pushed into each other), d_kick (soccer kick).
//  "before" = DecorField.ballsSolid off.
//

import XCTest
import Metal
import simd
import UIKit
@testable import BobV1

extension FurnCaptureTests {
    private func ballRig(from: SIMD2<Float>) -> MotionRig {
        let r = MotionRig(game: true)
        Self.keep.append(r)
        r.renderSamples = false
        r.skinner.autoBlink = false
        r.brain.abortScript(r.sim, r.skinner)
        r.sim.teleport(toXZ: from)
        for _ in 0..<120 { r.sim.step() }
        r.brain.currentPose(r.sim)
        return r
    }
    private func ballCtx() { GameCamera.configureRoom(count: 3, option: .A, wide: 2); _ = GameCamera.camera(aspect: 440.0 / 956.0); GameCamera.refreshRoam(aspect: 440.0 / 956.0) }

    private func strip(_ name: String, _ title: String, solid: Bool, side: Bool = false, w: Int = 520, h: Int = 440, build: (Bool) -> (rig: MotionRig, advance: (MotionRig) -> Void, focus: (MotionRig) -> SIMD3<Float>, frames: Int, every: Int)) throws {
        guard let device = MTLCreateSystemDefaultDevice() else { throw XCTSkip("no Metal") }
        DecorField.ballsSolid = solid
        defer { DecorField.ballsSolid = true }
        let s = build(solid)
        let (ren, t) = try makeRenderer(device, s.rig, w: w, h: h)
        var cells: [(LockImage, String)] = []
        for k in 0..<s.frames {
            for _ in 0..<s.every { s.advance(s.rig) }
            print(String(format: "BALLCAP %@ %@ f%d body (%.2f,%.2f) ball7 (%.2f,%.2f) v %.2f", name, solid ? "after" : "before", k, s.rig.brain.position.x, s.rig.brain.position.y, DecorField.shared.anim[7]!.pos.x, DecorField.shared.anim[7]!.pos.y, simd_length(DecorField.shared.anim[7]!.vel)))
            let p = s.focus(s.rig)
            cells.append((side ? sideView(ren, t, rigs: [s.rig], focus: p, dist: 5.0, w: w, h: h) : closeUp(ren, t, rigs: [s.rig], focus: p, dist: 5.2, w: w, h: h), "\(k + 1). t \(String(format: "%.1f", Float((k + 1) * s.every) / 60)) s"))
        }
        try save(sheet(cells, cols: 3, title: "\(title) (\(solid ? "AFTER: balls solid" : "BEFORE: walked through"))"), "\(name)_\(solid ? "after" : "before").png")
    }
    private func fstep(_ r: MotionRig, touched: Bool = false) {
        r.tick(touched: touched); r.skinner.jelly.tick(brain: r.brain, sim: r.sim, dt: r.sim.stepDt)
        let c = r.sim.centroid()
        DecorField.shared.bodies = [(r.brain.steerID, touched ? SIMD2(c.x, c.z) : r.brain.position)]          // (held: the body's own middle)
        DecorField.shared.tick(dt: 1.0 / 60)
    }
    private func ballMid(_ r: MotionRig, _ uid: Int = 7) -> SIMD3<Float> {
        let p = r.sim.centroid(), b = DecorField.shared.anim[uid]!.pos
        return SIMD3((p.x + b.x) / 2, 0.45, (p.z + b.y) / 2)
    }

    func testCaptureBallsWalk() throws {
        guard dir != nil else { throw XCTSkip("FURN_CAP_DIR not set") }
        for solid in [false, true] {
            try strip("a_walk", "Bob walks into the beach ball", solid: solid, side: true) { _ in
                ballCtx(); DecorField.shared.clear()
                DecorField.shared.set([PlacedDecor(uid: 7, kind: .beachball, x: 0.0, z: 1.0)])
                let r = ballRig(from: SIMD2(-2.0, 1.0))
                r.brain.script = .walk(target: SIMD2(2.2, 1.0), then: .none); r.brain.activity = .walking
                for _ in 0..<40 { fstep(r) }
                return (r, { self.fstep($0) }, { self.ballMid($0) }, 6, 20)
            }
        }
    }

    func testCaptureBallsDragAgainstSofa() throws {
        guard dir != nil else { throw XCTSkip("FURN_CAP_DIR not set") }
        for solid in [false, true] {
            try strip("b_drag", "Bob dragged into the soccer ball pinned against the toy box", solid: solid, side: true) { _ in
                ballCtx(); DecorField.shared.clear()
                let boxC = SIMD2<Float>(0.4, -0.2)          // (the sofa's front edge lies behind the walkable floor: a toy box stands in for the wall the ball is pinned against)
                let bx = boxC.x, bz = boxC.y + 0.41 + SoccerTuning.radius + 0.02
                DecorField.shared.set([PlacedDecor(uid: 7, kind: .soccerball, x: bx, z: bz), PlacedDecor(uid: 8, kind: .toybox, x: boxC.x, z: boxC.y)])
                let r = ballRig(from: SIMD2(bx, bz + 1.6))
                let c = r.sim.centroid()
                let hit = SIMD3(c.x, r.sim.floorY + 0.4, c.z)
                r.sim.beginGrab(hit: hit, radius: 0.42)
                var i = 0
                return (r, { rr in
                    let k = min(1, Float(i) / 150); i += 1
                    let tz = (bz + 1.6) + (boxC.y - (bz + 1.6)) * k
                    let q = GameCamera.constrain(SIMD3(bx, 0, tz), radius: 0.35)
                    rr.sim.moveGrab(target: SIMD3(q.x, hit.y + 0.15, q.z), rot: nil)
                    self.fstep(rr, touched: true)
                }, { self.ballMid($0) }, 6, 28)
            }
        }
    }

    func testCaptureBallsBallToBall() throws {
        guard dir != nil else { throw XCTSkip("FURN_CAP_DIR not set") }
        for solid in [false, true] {
            try strip("c_balls", "Two balls pushed into each other", solid: solid) { _ in
                ballCtx(); DecorField.shared.clear()
                DecorField.shared.set([PlacedDecor(uid: 7, kind: .beachball, x: -1.2, z: 1.0), PlacedDecor(uid: 8, kind: .beachball, x: 0.1, z: 1.0)])
                let r = ballRig(from: SIMD2(-2.6, 1.0))
                r.brain.script = .walk(target: SIMD2(1.0, 1.0), then: .none); r.brain.activity = .walking
                for _ in 0..<150 { fstep(r) }
                return (r, { self.fstep($0) }, { r in let a = DecorField.shared.anim[7]!.pos, b = DecorField.shared.anim[8]!.pos; return SIMD3((a.x + b.x) / 2, 0.45, (a.y + b.y) / 2) }, 6, 24)
            }
        }
    }

    func testCaptureBallsSoccerKick() throws {
        guard dir != nil else { throw XCTSkip("FURN_CAP_DIR not set") }
        for solid in [false, true] {
            try strip("d_kick", "A ball kicked in soccer play", solid: solid) { _ in
                ballCtx(); DecorField.shared.clear(); SoccerState.shared.reset(); SoccerEvents.clear()
                DecorField.shared.set([PlacedDecor(uid: 7, kind: .soccerball, x: 0.6, z: 0.6)])
                let r = ballRig(from: SIMD2(-1.2, 1.4))
                r.brain.anticsEnabled = true
                r.brain.seed = 7; r.brain.soccerModeForce = 0; r.brain.idleForced = true
                XCTAssertTrue(r.brain.idleStart(.soccerKick, r.sim))
                return (r, { self.fstep($0) }, { self.ballMid($0) }, 6, 30)
            }
        }
    }
}
