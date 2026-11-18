//
//  SleepGetUpTests.swift
//  The get-up (owner 2026-11-17: "getting up more natural from sleep, they just like slide up"): the roll back is now beats (rock onto a side and prop with the arms pressing,
//  push up with a small overshoot, settle) in `SleepTuning.getUpSoft` / `getUpShort` seconds, three variants. Measured on the real body: feet attached and legs within 1.15x rest
//  every frame (SocialTests.Watch), the body rises without a dip once the push starts, no sideways travel, and it ends standing with the root where the body is.
//

import XCTest
import simd
@testable import BobV1

@MainActor
final class SleepGetUpTests: XCTestCase {
    nonisolated(unsafe) static var keep: [AnyObject] = []
    private var savedHour: Double?
    private var savedNew = true
    override func setUp() {
        RoomLayout.dynamicBoxes = []; GameCamera.configureRoom(count: 3, option: .A, wide: 2); _ = GameCamera.camera(aspect: 440 / 956)
        SleepOrder.reset(); savedHour = DayClock.shared.forcedHour; DayClock.shared.forcedHour = 12; savedNew = SleepTuning.getUpNew
    }
    override func tearDown() {
        SleepTuning.getUpNew = savedNew; DayClock.shared.forcedHour = savedHour
        RoomLayout.dynamicBoxes = []; GameCamera.configureRoom(count: 1); _ = GameCamera.camera(aspect: 440.0 / 956.0); SleepOrder.reset()
    }

    enum Kind: String, CaseIterable { case normal, poke, meal }

    struct Result { var footTravel: Float = 0, variant = 0, dur: Float = 0, travel: Float = 0, dip: Float = 0, maxLeg: Float = 0, endGap: Float = 0, rootJump: Float = 0, endTilt: Float = 0, finished = false, minLegFrac: Float = 1 }

    private func legLen(_ r: MotionRig, _ s: Int) -> Float {
        let c = r.sim.centroid()
        var a = SIMD3<Float>.zero
        for p in r.feetIdx[s] { a += SIMD3(r.sim.x[3 * p], r.sim.x[3 * p + 1], r.sim.x[3 * p + 2]) }
        a /= Float(max(r.feetIdx[s].count, 1))
        return simd_distance(a, c)
    }

    /// One body at `p` (kept: the test host dies when many rigs pile up, so a body sleeps and wakes again and again).
    func makeRig(at p: SIMD2<Float>) -> (rig: MotionRig, rest: (Float, Float)) {
        let r = MotionRig(game: true)
        Self.keep.append(r)
        r.renderSamples = false
        r.skinner.autoBlink = false
        r.sim.teleport(toXZ: p)
        for _ in 0..<120 { r.sim.step() }
        r.brain.currentPose(r.sim)
        return (r, (legLen(r, 0), legLen(r, 1)))
    }

    func wake(_ kind: Kind, seed: UInt64, rig b: (rig: MotionRig, rest: (Float, Float)), facing yaw: Float, getUpNew: Bool = true) -> Result {
        SleepTuning.getUpNew = getUpNew
        let r = b.rig
        r.brain.seed = seed
        r.brain.yaw = yaw; r.brain.gait.facingYaw = yaw
        let rest0 = b.rest
        let y0 = r.sim.centroid().y
        r.brain.idleForced = true
        XCTAssertTrue(r.brain.idleStart(.sleep, r.sim))
        r.brain.sleep.hold = 500
        r.run(24, until: { r.brain.isNapping })
        XCTAssertTrue(r.brain.isNapping)
        for _ in 0..<90 { r.tick() }
        let pos0 = r.brain.position
        var w = SocialTests.Watch()
        var out = Result()
        switch kind {
        case .normal: r.brain.sleepWake(groggy: false, slow: true)
        case .poke: r.brain.sleepWake(groggy: true)
        case .meal: r.brain.sleep.mealWake = true; r.brain.sleepWake(groggy: true, fast: true)
        }
        var stage4: Float = 0, started = false, prevY: Float = 0, c0 = SIMD2<Float>.zero, f0 = SIMD2<Float>.zero, touching = false, f = 0
        while f < 20 * 60, !(r.brain.idleState.kind == nil && started) {
            r.tick(); f += 1
            w.sample(r)
            let bs = r.brain.sleep
            if r.brain.idleState.kind == .sleep, bs.stage >= 4 {
                out.variant = bs.upVar
                if !started { started = true; c0 = r.root }
                // sliding on the floor: how far the feet's middle moves, frame to frame, while a foot is touching the floor (a foot in the air as he rolls up is not a slide)
                let fm = (r.footXZ(0) + r.footXZ(1)) / 2
                if r.groundGap < 0.03, touching { out.footTravel += simd_distance(fm, f0) }
                touching = r.groundGap < 0.03; f0 = fm
                if bs.stage == 4 {
                    stage4 += 1.0 / 60
                    let u = bs.t / max(bs.rollDur, 0.01), y = r.sim.centroid().y
                    if u > 0.35, u < 0.8 { out.dip = max(out.dip, prevY - y) }          // (a fall during the push-up)
                    prevY = y
                    out.dur = bs.rollDur
                }
                out.travel = max(out.travel, simd_distance(r.root, c0))
            }
            if started { out.maxLeg = max(out.maxLeg, max(legLen(r, 0) / rest0.0, legLen(r, 1) / rest0.1)) }
        }
        out.finished = r.brain.idleState.kind == nil
        for _ in 0..<120 { r.tick() }
        r.brain.sleep = SleepState()
        out.endGap = r.groundGap
        out.rootJump = simd_distance(r.brain.position, pos0)
        out.endTilt = r.sim.bodyPose(iterations: 6).tilt
        _ = y0
        w.check("get-up \(kind.rawValue) seed \(seed)")
        return out
    }

    func testTheGetUpRisesInPlaceAndEndsStandingForEveryVariantAndWake() {
        var seen = Set<Int>()
        let spots: [SIMD2<Float>] = [SIMD2(0, 0.2), SIMD2(-2.0, -1.0), SIMD2(2.0, 1.4)]
        let rigs = spots.map { makeRig(at: $0) }
        let oldRig = makeRig(at: SIMD2(0, 0.2))
        var seed: UInt64 = 0
        for kind in Kind.allCases {
            for k in 0..<4 {
                seed += 1
                let b = rigs[k % 3]
                let o = wake(kind, seed: seed * 7919, rig: b, facing: Float(seed) * 1.1)
                let old = k == 0 ? wake(kind, seed: seed * 7919, rig: oldRig, facing: Float(seed) * 1.1, getUpNew: false) : nil
                seen.insert(o.variant)
                MotionLog.write("GETUP \(kind.rawValue) #\(seed) var \(o.variant) dur \(o.dur) travel \(o.travel) feet \(o.footTravel) dip \(o.dip) maxLeg \(o.maxLeg) endGap \(o.endGap) jump \(o.rootJump) tilt \(o.endTilt)  | old dur \(old?.dur ?? -1) travel \(old?.travel ?? -1) feet \(old?.footTravel ?? -1)")
                XCTAssertTrue(o.finished, "\(kind) \(seed): the wake ends")
                XCTAssertLessThan(o.travel, 0.3, "\(kind) \(seed): the body's centre only swings over its feet as it pitches up (the old roll back is the same)")
                if let old { XCTAssertLessThanOrEqual(o.footTravel, old.footTravel + 0.05, "\(kind) \(seed): the feet slide on the floor no more than in the old roll back (\(old.footTravel))") }
                XCTAssertLessThan(o.footTravel, 0.1, "\(kind) \(seed): the feet do not slide on the floor")
                XCTAssertLessThan(o.dip, 0.015, "\(kind) \(seed): the body rises through the push-up")
                XCTAssertLessThanOrEqual(o.maxLeg, 1.15, "\(kind) \(seed): no leg stretched past 1.15x")
                XCTAssertLessThan(o.endGap, 0.05, "\(kind) \(seed): standing on the floor at the end")
                XCTAssertLessThan(o.rootJump, 0.01, "\(kind) \(seed): the root does not jump")
                XCTAssertLessThan(o.endTilt, 0.4, "\(kind) \(seed): upright at the end")
                if kind == .normal { XCTAssertGreaterThan(o.dur, 1.4, "a normal wake takes its time") } else { XCTAssertLessThan(o.dur, 1.2, "a poke / a meal is about a second") }
            }
        }
        XCTAssertEqual(seen, [0, 1, 2], "all three variants appear")
    }
}
