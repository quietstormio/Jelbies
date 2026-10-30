//
//  TouchContactTests.swift
//  Touching Jelbies (2026-10-30): two soft bodies that press must flatten against each other, never pass through (ContactMetric measures the DRAWN skins), and
//  nobody goes through Pip's tail. Every touch social is run between Pip (the dino tail) and Moss, in both seats, and the deepest overlap and the deepest
//  tail intrusion are logged (MOTION_LOG) next to the bounds the touches must keep. TOUCH_ONLY=kind,kind limits the kinds; TOUCH_LOG_ONLY=1 logs without asserting
//  (the before / after numbers of the round).
//

import XCTest
import simd
@testable import BobV1

@MainActor
final class TouchContactTests: XCTestCase {
    override func setUp() { RoomLayout.dynamicBoxes = []; SocialTuning.pickChance = 0.12 }
    override func tearDown() { RoomLayout.dynamicBoxes = []; SocialTuning.pickChance = 0.12 }

    /// Every social where the bodies meet.
    static let touchKinds: [SocialKind] = [.boop, .bump, .nuzzle, .chestBump, .highFive, .hum, .cheekSquish, .noseBoop, .backToBack, .bellyBounce,
                                           .cuddleLean, .swayHug, .leapfrog, .sitTogether, .hopAlong, .peekaboo, .whisperGiggle, .mirrorDance]
    /// The deepest a drawn body may sink into the other, and into Pip's tail tube (world units; a body is ~1.0 wide): a small squish, not a pass-through.
    static let depthBound: Float = 0.12, tailBound: Float = 0.05

    struct Result { var depth: Float = 0, tail: Float = 0, depthAt: Float = 0, tailAt: Float = 0, seconds: Float = 0, done = false }

    /// Runs `kind` between rig 0 and rig 1 (pip: which seat Pip has) and measures every 3rd frame.
    func run(_ kind: SocialKind, pipSeat: Int, seed: UInt64 = 31, maxSeconds: Float = 40) -> Result {
        let lab = SocialTests.Lab(n: 2, positions: [SIMD2(-1.0, 0.6), SIMD2(0.7, 0.9)], seed: seed)
        let rm = MotionRig.renderMesh
        for (i, r) in lab.rigs.enumerated() {
            r.renderSamples = false
            r.brain.feature = i == pipSeat ? .spines : .daisy
            r.skinner.configureTail(rm); r.skinner.tailOn = i == pipSeat; r.brain.skinnerRef = r.skinner
        }
        let tailFirst = rm.armCapsule?.tailFirst ?? -1
        let skip = tailFirst >= 0 ? tailFirst..<(tailFirst + TailBean.vertexCount) : 0..<0
        var res = Result()
        _ = lab.rigs[0].brain.socialStart(kind, with: lab.rigs[1].brain, lab.rigs[0].sim)
        var f = 0
        while f < Int(maxSeconds * 60) {
            lab.tick(watching: false)
            f += 1
            if f % 3 == 0 {
                for r in lab.rigs { r.render() }
                let a = lab.rigs[0], b = lab.rigs[1]
                let d = a.dyn.withUnsafeBufferPointer { pa in b.dyn.withUnsafeBufferPointer { pb in ContactMetric.mutualDepth(pa.baseAddress!, pb.baseAddress!, vertices: rm.vertexCount, skip: skip) } }
                if d > res.depth { res.depth = d; res.depthAt = Float(f) / 60 }
                if tailFirst >= 0 {
                    let p = lab.rigs[pipSeat], o = lab.rigs[1 - pipSeat]
                    let t = p.dyn.withUnsafeBufferPointer { pp in o.dyn.withUnsafeBufferPointer { po in ContactMetric.tailIntrusion(tail: pp.baseAddress!, first: tailFirst, other: po.baseAddress!, vertices: rm.vertexCount, skip: skip) } }
                    if t > res.tail { res.tail = t; res.tailAt = Float(f) / 60 }
                }
            }
            if !lab.anySocial && f > 10 { res.done = true; break }
        }
        res.seconds = Float(f) / 60
        return res
    }

    func testEveryTouchSocial() {
        let env = ProcessInfo.processInfo.environment
        let only = env["TOUCH_ONLY"].map { Set($0.split(separator: ",").map(String.init)) }
        let logOnly = env["TOUCH_LOG_ONLY"] != nil
        for kind in Self.touchKinds where only?.contains(kind.rawValue) ?? true {
            for seat in 0..<2 {
                let r = run(kind, pipSeat: seat)
                MotionLog.write(String(format: "TOUCH %@ pip=%d: depth %.3f (t %.1f) tail %.3f (t %.1f) done=%d in %.1f s", kind.rawValue, seat, r.depth, r.depthAt, r.tail, r.tailAt, r.done ? 1 : 0, r.seconds))
                if !logOnly {
                    XCTAssertLessThanOrEqual(r.depth, Self.depthBound, "\(kind) pip=\(seat): bodies stay out of each other")
                    XCTAssertLessThanOrEqual(r.tail, Self.tailBound, "\(kind) pip=\(seat): nobody goes through the tail")
                }
            }
        }
    }
}
