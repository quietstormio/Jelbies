//
//  SeesawRideTests.swift
//  The Park seesaw's ride (Park/SeesawRide.swift), headless: the derived amplitude and the bumper press, the plank controller on its own (continuous angle through every change of
//  state), and full sequences with real bodies (Bob + Pip, Teddy + Lavender, one alone; two seeds each; one with a mid-ride call-away): both get on, ride at least 3 full swings, both
//  get off. Every number the brief asks for is printed (MotionLog, TEST_RUNNER_MOTION_LOG) and asserted. Written before the first build: the numbers below are the targets.
//

import XCTest
import simd
@testable import BobV1

@MainActor
final class SeesawRideTests: XCTestCase {
    nonisolated(unsafe) static var keep: [AnyObject] = []
    nonisolated(unsafe) static var hopUpMax: Float = 0, hopDownMax: Float = 0
    nonisolated(unsafe) static var hopCount = 0, hopRefusals = 0
    let uid = ParkToys.seesawUID

    override func setUp() {
        DecorField.shared.clear(); DecorField.shared.toys = ToyBook(); ToyTuning.settle = 0
        SeesawRide.shared.reset()
    }
    override func tearDown() {
        DecorField.shared.clear(); ToyTuning.settle = 5
        SeesawRide.shared.reset()
        GameCamera.endPark(count: 3); _ = GameCamera.camera(aspect: 440.0 / 956.0)
        GameCamera.configureRoom(count: 1); GameCamera.clearRoam(); RoomLayout.apply(RoomCatalog.home)
    }

    // MARK: the numbers that do not need a body

    func testAmplitudeShapeAndBumperPress() {
        let A = SeesawTuning.amplitude, touch = SeesawTuning.touchAngle
        MotionLog.write(String(format: "SEESAW derived A %.4f rad (contract v2: about 0.1754), first touch %.4f rad (about 0.150)", A, touch))
        XCTAssertEqual(A, 0.1754, accuracy: 0.005)
        XCTAssertEqual(touch, 0.150, accuracy: 0.005)
        var top: Float = 0
        for i in 0..<720 { top = max(top, SeesawTuning.shape(Float(i) / 720 * 2 * .pi)) }
        XCTAssertEqual(top, 1, accuracy: 1e-4, "the shape peaks at 1")
        // flat top: within 2 % of the peak for at least 0.45 rad either side of it (a plain sine is within 2 % for ~0.2 rad)
        XCTAssertGreaterThan(SeesawTuning.shape(.pi / 2 - 0.45), 0.97)
        // the plank's underside over the bumper centre line = y(theta) = 0.27 - 0.96 tan - 0.015 / cos
        let t: Float = 0.2
        XCTAssertEqual(SeesawTuning.undersideY(atX: 0.96, theta: -t), 0.27 - 0.96 * tanf(t) - 0.015 / cosf(t), accuracy: 1e-5)
        // the bumper's top follows the underside while pressed (within 2 mm) and is never above it; never pressed before the touch
        var worstGap: Float = 0, pressedSamples = 0
        var th: Float = -0.23
        while th <= 0.23 {
            for side: Float in [-1, 1] {
                let under = SeesawTuning.undersideY(atX: side * SeesawTuning.bumperX, theta: th)
                let bt = SeesawTuning.bumperTop(side: side, theta: th)
                XCTAssertLessThanOrEqual(bt, under + 1e-6, "the bumper never pokes through the plank (side \(side) theta \(th))")
                XCTAssertLessThanOrEqual(bt, SeesawTuning.bumperRest + 1e-6)
                if bt < SeesawTuning.bumperRest - 1e-6 && bt > 0.02 { pressedSamples += 1; worstGap = max(worstGap, under - bt) }
            }
            th += 0.001
        }
        MotionLog.write(String(format: "SEESAW bumper: pressed samples %d, worst gap while pressed %.2f mm (limit 2 mm); at A the bumper is %.0f %% of its height", pressedSamples, worstGap * 1000, SeesawTuning.bumperTop(side: 1, theta: -A) / SeesawTuning.bumperRest * 100))
        XCTAssertGreaterThan(pressedSamples, 50)
        XCTAssertLessThanOrEqual(worstGap, 0.002)
        XCTAssertEqual(SeesawTuning.bumperTop(side: 1, theta: -A) / SeesawTuning.bumperRest, 0.77, accuracy: 0.03)
        XCTAssertEqual(SeesawTuning.bumperTop(side: 1, theta: 0), SeesawTuning.bumperRest, "level: the bumper is at rest height")
        // the seat frame (contract v2): level it is the contract's cushion top; tilted, the seat is only TRANSLATED by R(theta) * h - h (h = hinge - pivot), never turned
        let k = DecorKind.seesaw.scale
        for seat in 0..<2 {
            let sx: Float = seat == 0 ? -1 : 1
            let s0 = SeesawTuning.seatLocal(seat: seat, theta: 0)
            XCTAssertEqual(s0.x, sx * 0.66 * k, accuracy: 1e-5); XCTAssertEqual(s0.y, 0.475 * k, accuracy: 1e-5)
            XCTAssertEqual(simd_length(SeesawTuning.seatShift(seat: seat, theta: 0)), 0, accuracy: 1e-6)
            for ang in [-A, -0.1, 0.05, 0.1, A] {
                let h = SIMD3<Float>(sx * SeesawTuning.hingeX, SeesawTuning.hingeY - SeesawTuning.pivotY, 0)
                let q = simd_quatf(angle: ang, axis: SIMD3(0, 0, 1))
                let want = q.act(h) - h, got = SeesawTuning.seatShift(seat: seat, theta: ang)
                XCTAssertEqual(got.x, want.x, accuracy: 1e-5); XCTAssertEqual(got.y, want.y, accuracy: 1e-5)
                let sl = SeesawTuning.seatLocal(seat: seat, theta: ang)
                XCTAssertEqual(sl.x, (sx * 0.66 + want.x) * k, accuracy: 1e-5); XCTAssertEqual(sl.y, (0.475 + want.y) * k, accuracy: 1e-5)
                let back = SeesawTuning.toSeat(sl, seat: seat, theta: ang)
                XCTAssertEqual(back.x, sx * 0.66, accuracy: 1e-4); XCTAssertEqual(back.y, 0.475, accuracy: 1e-4); XCTAssertEqual(back.z, 0, accuracy: 1e-4)
                if seat == 1 { MotionLog.write(String(format: "SEESAW seat shift (seat 1) at theta %+.3f: dx %+.2f cm dy %+.2f cm (world)", ang, want.x * k * 100, want.y * k * 100)) }
            }
        }
        // seat up = plank end up
        XCTAssertGreaterThan(SeesawTuning.seatLocal(seat: 1, theta: A).y, SeesawTuning.seatLocal(seat: 1, theta: 0).y + 0.10)
    }

    /// The baked model of contract v2 (RED until the art branch is merged: the old file has no seatL / seatR and its plank pivot is 0.34).
    func testArtFileContractV2() {
        let k = DecorKind.seesaw.scale
        guard let art = DecorMeshes.loaded[.seesaw] else { XCTFail("ART CONTRACT v2: decor_seesaw.bin is not loaded"); return }
        MotionLog.write("SEESAW art parts: " + art.parts.map { String(format: "%@ pivot (%.4f, %.4f, %.4f)", $0.name, $0.pivot.x, $0.pivot.y, $0.pivot.z) }.joined(separator: "; "))
        XCTAssertEqual(art.parts.map { $0.name }, ["base", "plank", "bumperL", "bumperR", "seatL", "seatR"], "ART CONTRACT v2: the parts, in this order")
        func near(_ a: SIMD3<Float>?, _ b: SIMD3<Float>, _ what: String) {
            guard let a else { XCTFail("ART CONTRACT v2: no \(what)"); return }
            XCTAssertLessThan(simd_distance(a, b), 0.002 * 1.7321, "ART CONTRACT v2: \(what)'s pivot is \(a), the contract says \(b)")
        }
        near(art.part("plank")?.pivot, SIMD3(0, SeesawTuning.pivotY * k, 0), "plank")
        near(art.part("seatL")?.pivot, SIMD3(-SeesawTuning.hingeX * k, SeesawTuning.hingeY * k, 0), "seatL")
        near(art.part("seatR")?.pivot, SIMD3(SeesawTuning.hingeX * k, SeesawTuning.hingeY * k, 0), "seatR")
    }

    // MARK: the controller alone (riders reported by hand)

    /// Two riders seated by hand: beat, ride 5...8 swings, the end, the beat, the leaving order; the angle and its rate stay continuous at every step through the ramps; then a
    /// call-away from full tilt eases level within 0.6 s.
    func testControllerSequenceAndContinuity() {
        let f = DecorField.shared, R = SeesawRide.shared
        f.set([PlacedDecor(uid: uid, kind: .seesaw, x: 0, z: 0, turns: nil)])
        f.take(uid, seat: 0, by: 1)
        var prevTh: Float = 0, prevD: Float = 0, maxD: Float = 0, maxDD: Float = 0, maxDDCall: Float = 0
        var modes: [SeesawRide.Mode] = [], calledAt = -1
        func step(_ i: Int) {
            f.tick(dt: 1.0 / 60)
            let th = R.theta(uid), d = th - prevTh, dd = d - prevD
            maxD = max(maxD, abs(d))
            if i > 1 { if R.mode(uid) == .callAway || calledAt >= 0 && i - calledAt < 60 { maxDDCall = max(maxDDCall, abs(dd)) } else { maxDD = max(maxDD, abs(dd)) } }
            prevTh = th; prevD = d
            if modes.last != R.mode(uid) { modes.append(R.mode(uid)) }
        }
        var i = 0
        R.report(uid, 0, .coming)
        for _ in 0..<30 { step(i); i += 1 }
        // the first one is seated, a bounce alone starts after 0.4 s; the second arrives later: the plank must ease level before he may hop
        R.report(uid, 0, .seated)
        var gate = -1
        for _ in 0..<(60 * 4) { step(i); i += 1 }
        XCTAssertGreaterThan(R.amp(uid), 0.2, "alone: the gentle bounce has started"); XCTAssertLessThanOrEqual(R.amp(uid), 0.26)
        // the second rider takes the other seat (coming): the seated one eases to level, the comer's hop waits for it
        f.take(uid, seat: 1, by: 2)
        R.report(uid, 1, .coming)          // (at his spot: a comer still walking from afar does not stop the solo rock)
        XCTAssertFalse(R.mayHopOn(uid, 1), "the plank moves: the comer waits")
        for k in 0..<(60 * 3) { step(i); i += 1; if gate < 0, R.mayHopOn(uid, 1) { gate = k } }
        XCTAssertEqual(R.amp(uid), 0); XCTAssertEqual(R.theta(uid), 0)
        XCTAssertGreaterThan(gate, 0, "the comer's hop opens only after the plank is level and still"); XCTAssertLessThan(Float(gate) / 60, 0.7)
        R.report(uid, 1, .boarding)
        for _ in 0..<30 { step(i); i += 1 }
        XCTAssertEqual(R.theta(uid), 0, "nothing moves while he is in the air")
        R.report(uid, 1, .seated)
        var rideSteps = 0
        for _ in 0..<(60 * 60) { step(i); i += 1; if R.mode(uid) == .pairRide { rideSteps += 1 }; if R.mode(uid) == .leaving { break } }
        XCTAssertEqual(R.mode(uid), .leaving, "the ride ended and the plank arrived still")
        let swings = Float(rideSteps) / 60 / SeesawTuning.period
        MotionLog.write(String(format: "SEESAW controller: modes %@, pair ride %.1f s = %.1f swings, max |dtheta| %.4f, max |ddtheta| %.5f (calls %.5f)", "\(modes)", Float(rideSteps) / 60, swings, maxD, maxDD, maxDDCall))
        XCTAssertGreaterThanOrEqual(swings, 5); XCTAssertLessThanOrEqual(swings, 9.1)
        XCTAssertTrue(R.still(uid))
        // the order: nobody may leave before the beat; the second a gap after the first
        let first = R.rides[uid]!.order[0], second = R.rides[uid]!.order[1]
        XCTAssertTrue(R.mayLeave(uid, first)); XCTAssertFalse(R.mayLeave(uid, second), "the second waits 0.3 s")
        for _ in 0..<20 { step(i); i += 1 }
        XCTAssertTrue(R.mayLeave(uid, second))
        // a second ride, then a call-away at full tilt
        R.report(uid, first, .hopOff); R.report(uid, second, .hopOff)
        f.leave(uid, by: 1); f.leave(uid, by: 2)
        for _ in 0..<60 { step(i); i += 1 }
        f.take(uid, seat: 0, by: 1); f.take(uid, seat: 1, by: 2)
        R.report(uid, 0, .seated); R.report(uid, 1, .seated)
        var started = false
        for _ in 0..<(60 * 20) { step(i); i += 1; if R.mode(uid) == .pairRide, R.amp(uid) > 0.95 { started = true; break } }
        XCTAssertTrue(started, "the second ride reached full amplitude")
        R.report(uid, 1, .leaving, forced: true); calledAt = i
        var level = -1
        for k in 0..<(60 * 2) { step(i); i += 1; if level < 0, R.amp(uid) == 0 { level = k } }
        MotionLog.write(String(format: "SEESAW call-away: level after %.2f s (limit 0.6 s + a frame), max |dtheta| %.4f, max |ddtheta| in the ease %.5f (limit 0.004)", Float(level) / 60, maxD, maxDDCall))
        XCTAssertGreaterThan(level, 0); XCTAssertLessThanOrEqual(level, Int(0.6 * 60) + 2)
        XCTAssertLessThan(maxD, 0.019, "|dtheta| per step")
        XCTAssertLessThan(maxDD, 0.002, "the change of dtheta between steps")
        XCTAssertLessThan(maxDDCall, 0.004, "the change of dtheta between steps in the call-away ease")
        f.clear()
    }

    /// A ride left mid-swing, the layout rebuilt as on a new park visit: the plank is level and still on the first step.
    func testStaleRideStartsFreshOnANewVisit() {
        let f = DecorField.shared, R = SeesawRide.shared
        let place = [PlacedDecor(uid: uid, kind: .seesaw, x: 0, z: 0, turns: nil)]
        f.set(place)
        f.take(uid, seat: 0, by: 1); f.take(uid, seat: 1, by: 2)
        R.report(uid, 0, .seated); R.report(uid, 1, .seated)
        var swinging = false
        for _ in 0..<(60 * 12) { f.tick(dt: 1.0 / 60); if R.mode(uid) == .pairRide, abs(R.theta(uid)) > 0.1 { swinging = true; break } }
        XCTAssertTrue(swinging, "mid-swing")
        // the riders are gone with the park, the piece comes back with the next visit
        f.leave(uid, by: 1); f.leave(uid, by: 2)
        f.set([])
        f.set(place)
        f.tick(dt: 1.0 / 60)
        XCTAssertEqual(R.theta(uid), 0, "level on the first step of the new visit"); XCTAssertEqual(R.amp(uid), 0)
        XCTAssertTrue(R.still(uid))
        // and a rider who is on the piece when the version moves is never reset
        f.take(uid, seat: 0, by: 1); R.report(uid, 0, .seated)
        for _ in 0..<(60 * 4) { f.tick(dt: 1.0 / 60) }
        let before = R.theta(uid)
        f.set(place + [PlacedDecor(uid: 5, kind: .rug, x: 3, z: 3, turns: nil)])
        f.tick(dt: 1.0 / 60)
        XCTAssertEqual(R.theta(uid), before, accuracy: 0.012, "no reset under a rider")
        f.clear()
    }

    // MARK: full sequences with bodies

    struct Hop {
        var kind = "", rider = 0, forced = false, capped = false
        var from = SIMD2<Float>.zero, to = SIMD2<Float>.zero          // (the body's centre over the floor, relative to the piece's centre, metres)
        var dist: Float = 0, thetaAtStart: Float = 0, startVsSeat: Float = 0, landing: Float = 0
        var step = 0
    }

    struct Report {
        var tag = ""
        var rootSeatRide: Float = 0, rootSeatAny: Float = 0          // (the root against the DRAWN seat point: while riding / at every seated step)
        var maxRelTrans: Float = 0, maxDVTrans: Float = 0
        var maxRel: Float = 0, maxWorldStep: Float = 0, maxSeatedDV: Float = 0, maxAirDV: Float = 0, maxAirStep: Float = 0
        var maxD: Float = 0, maxDD: Float = 0, maxDDCall: Float = 0
        var calLo: [Float] = [], calHi: [Float] = [], rideLo: [Float] = [], rideHi: [Float] = []          // (per rider: the lowest skin point against the pad's top plane, level and still / riding)
        var calN: [Int] = [], rideN: [Int] = []
        var leashFrames = 0, leashMax: Float = 0
        var beamDepth: Float = 0, handleMin: Float = .infinity, padOther: Float = 0, bodyGapMin: Float = .infinity
        var hops: [Hop] = []
        var refused = 0
        var maxAmp: Float = 0, swings: Float = 0
        var finished = false, seatedAll = false
        var waitMinZ: Float = .infinity
        var standWhere = ""
        var standMinZ: Float = .infinity, standRootZ: Float = 0, riderSkin: Float = .infinity
        var beamWhere = "", padWhere = "", clearWhere = "", dvWhere = "", airDvWhere = "", relWhere = ""
        var standClear: Float = .infinity, armMax = 0.0, featureBeam: Float = 0, featureHandle: Float = .infinity, featurePad: Float = 0
        var seatedSteps = 0, rideSteps = 0
        var rootWhere = "", handleWhere = ""
        var tailN = 0, tailFirst = -1, tailLast = -1, tailMax: Float = 0, tailInfo = ""
        var offLandInfo: [String] = []
        var stage0Lines = 0, standLowSum: Float = 0, standLowN = 0
        var aboveN: [Int] = [], aboveRunMax: [Int] = []          // (per rider: riding steps with the lowest skin point more than 0.5 cm above the pad's plane, and the longest run of them)
        var walkLines: [String] = [], walkFails: [String] = []
        var offLandMinY: [Float] = [], offLandLater: [Float] = []
        var offLandMinYOld: [Float] = []          // (the lowest skin point at the first step after a hop off, against the ground)
        var topRelMax: Float = 0, topRelWhere = ""          // (settled: the highest skin point's motion against the seat, per step)
    }

    /// One body's distance outside a box (negative = inside by that much), the box given by its centre and half extents (frame of the part, model units).
    private static func boxDist(_ p: SIMD3<Float>, _ c: SIMD3<Float>, _ h: SIMD3<Float>) -> Float {
        let q = simd_abs(p - c) - h
        return simd_length(simd_max(q, .zero)) + min(max(q.x, max(q.y, q.z)), 0)
    }
    /// The render buffer's blocks: per side [arm capsule, foot bean], then Pip's tail, then Teddy's ears and pom (Geometry.swift).
    private static let partNames = ["body", "left arm capsule", "left foot bean", "right arm capsule", "right foot bean", "tail", "teddy ears/pom"]
    private static let capInfo = MotionRig.renderMesh.armCapsule, capAN = ArmCapsule.vertexCount, capFN = FootBean.vertexCount
    private static func partCode(_ idx: Int) -> Int {
        guard let c = capInfo else { return 0 }
        if c.teddyFirst >= 0, idx >= c.teddyFirst { return 6 }
        if c.tailFirst >= 0, idx >= c.tailFirst { return 5 }
        let an = capAN, fn = capFN
        for s in 0..<2 {
            let base = c.firstVertex[s]
            if idx >= base, idx < base + an { return 1 + 2 * s }
            if idx >= base + an, idx < base + an + fn { return 2 + 2 * s }
        }
        return 0
    }
    private static func part(_ idx: Int) -> String { partNames[partCode(idx)] }
    private static func partName(_ idx: Int) -> String { part(idx) }
    /// A vertex of a piece that is not in use right now (the arm capsules before the arms are up, the foot beans before the feet are on, the tail / teddy pieces of a species without them) is parked, not drawn.
    private static func parked(_ idx: Int, armOn: Bool, tailOn: Bool, teddyOn: Bool, beansOn: Bool = true) -> Bool {
        switch partCode(idx) {
        case 6: return !teddyOn
        case 5: return !tailOn
        case 1, 3: return !armOn
        case 2, 4: return !beansOn
        default: return false
        }
    }
    /// Per block: the farthest a vertex is from the root over the floor, and its height range (what a stale or parked block would show).
    private static func blockStats(_ d: UnsafeBufferPointer<Float>, root: SIMD2<Float>) -> String {
        guard let c = MotionRig.renderMesh.armCapsule else { return "" }
        func st(_ lo: Int, _ n: Int) -> String {
            var mx: Float = 0, ymin = Float.infinity, ymax = -Float.infinity
            for k in lo..<(lo + n) { let v = 6 * k; guard v + 2 < d.count else { break }; mx = max(mx, hypotf(d[v] - root.x, d[v + 2] - root.y)); ymin = min(ymin, d[v + 1]); ymax = max(ymax, d[v + 1]) }
            return String(format: "far %.2f m, y %.2f..%.2f", mx, ymin, ymax)
        }
        let an = ArmCapsule.vertexCount, fn = FootBean.vertexCount
        return "armL [\(st(c.firstVertex[0], an))] footL [\(st(c.firstVertex[0] + an, fn))] armR [\(st(c.firstVertex[1], an))] footR [\(st(c.firstVertex[1] + an, fn))]"
    }
    /// Distance (model units, negative = inside) from a point to the seesaw's REAL parts as drawn, level plank: the two pads, the beam, each handle's post and bar, the two bumper domes, the base's low
    /// block and its two cheeks (the contract / the art's numbers: tools/make_park_seesaw/build_seesaw.py), each on its own, not a bounding box.
    private static func standDist(_ p: SIMD3<Float>) -> Float {
        var m = boxDist(p, SIMD3(0, SeesawTuning.beamCentreY, 0), SeesawTuning.beamHalf)
        let postTop = SeesawTuning.handleTopY - 0.036, postBot = SeesawTuning.handleBottomY
        for sx: Float in [-1, 1] {
            m = min(m, boxDist(p, SIMD3(sx * SeesawTuning.cushionX, SeesawTuning.cushionCentreY, 0), SeesawTuning.cushionHalf))
            m = min(m, boxDist(p, SIMD3(sx * SeesawTuning.handleX, (postTop + postBot) / 2, 0), SIMD3(0.031, (postTop - postBot) / 2, 0.031)))
            m = min(m, boxDist(p, SIMD3(sx * SeesawTuning.handleX, SeesawTuning.handleTopY - 0.018, 0), SIMD3(SeesawTuning.handleBarHalfX, 0.018, SeesawTuning.handleBarHalfZ)))
            m = min(m, simd_length(p - SIMD3(sx * SeesawTuning.bumperX, 0, 0)) - SeesawTuning.bumperRest)          // (a sphere of the dome's height: a little fuller than the dome)
            m = min(m, boxDist(p, SIMD3(0, 0.26, sx * 0.2285), SIMD3(0.11, 0.11, 0.0435)))          // (the cheeks)
        }
        m = min(m, boxDist(p, SIMD3(0, 0.075, 0), SIMD3(0.24, 0.075, 0.27)))          // (the low block)
        return m
    }
    /// How far a skin point (WORLD x, y, z) is inside the beam, a handle (both in the plank's frame, `toPlank`) and the deep part of a pad (in the LEVEL seat's frame, `toSeat`: the pad's box
    /// from its underside up to 3 cm under its flat top; the top's own contact is the pad margin). Returns depth inside the beam (+), distance to the handle (negative = inside), depth inside a pad (+); metres.
    private static func clearances(_ w: SIMD3<Float>, centre: SIMD2<Float>, th: Float) -> (beam: Float, handle: Float, pad: Float)? {
        let k = DecorKind.seesaw.scale
        let local = SIMD3(w.x - centre.x, w.y, w.z - centre.y)
        let p = SeesawTuning.toPlank(local, theta: th)
        guard abs(p.x) < 1.5, p.y > 0.15, p.y < 0.9, abs(p.z) < 0.5 else { return nil }
        let beam = -boxDist(p, SIMD3(0, SeesawTuning.beamCentreY, 0), SeesawTuning.beamHalf) * k
        var handle = Float.infinity, pad: Float = -.infinity
        let hy = (SeesawTuning.handleTopY + SeesawTuning.handleBottomY) / 2, hh = (SeesawTuning.handleTopY - SeesawTuning.handleBottomY) / 2
        let underside = SeesawTuning.cushionCentreY - SeesawTuning.cushionHalf.y, top = SeesawTuning.cushionCentreY + SeesawTuning.cushionHalf.y - 0.03 / k
        for sx: Float in [-1, 1] {
            handle = min(handle, boxDist(p, SIMD3(sx * SeesawTuning.handleX, hy, 0), SIMD3(SeesawTuning.handleHalfX, hh, SeesawTuning.handleBarHalfZ)) * k)
            let ps = SeesawTuning.toSeat(local, seat: sx < 0 ? 0 : 1, theta: th)
            pad = max(pad, -boxDist(ps, SIMD3(sx * SeesawTuning.cushionX, (underside + top) / 2, 0), SIMD3(SeesawTuning.cushionHalf.x, (top - underside) / 2, SeesawTuning.cushionHalf.z)) * k)
        }
        return (beam, handle, pad)
    }

    func runSequence(chars: [Int], seed: UInt64, callAway: Bool, label: String) -> Report {
        var rep = Report(); rep.tag = label
        RoomLayout.apply(RoomCatalog.park); GameCamera.configurePark(); _ = GameCamera.refreshRoam(aspect: 440.0 / 956.0)
        let starts: [SIMD2<Float>] = [SIMD2(-0.7, 0.2), SIMD2(0.4, -0.4)]
        let lab = SocialTests.Lab(n: chars.count, positions: Array(starts.prefix(chars.count)), quiet: true, seed: seed)
        Self.keep.append(lab)
        for (k, r) in lab.rigs.enumerated() {
            r.sim.arenaCenter = GameCamera.arenaCenter; r.sim.arenaRadius = GameCamera.arenaRadius
            r.brain.anticsEnabled = true; r.brain.idleMood = .happy; r.brain.idleForced = true; r.skinner.autoBlink = false; r.renderSamples = false
            r.brain.feature = JellyRoster.feature(chars[k])
            r.skinner.configureTail(MotionRig.renderMesh); r.skinner.tailOn = r.brain.feature == .spines; r.brain.skinnerRef = r.skinner
        }
        WearBody.install(MotionRig.renderMesh)
        var feats: [FeatureSet] = []
        for _ in chars { let f = FeatureSet(); f.body = WearBody.shared; Self.keep.append(f); feats.append(f) }
        var afterOff = [Int](repeating: 0, count: chars.count)
        let place = ParkToys.placed.filter { $0.kind == .seesaw }
        DecorField.shared.set(place)
        DecorField.shared.toys.news.removeAll()
        let centre = place[0].at
        let R = SeesawRide.shared, field = DecorField.shared
        R.refusedHops = 0
        for r in lab.rigs { XCTAssertTrue(r.brain.decorStart(.decorSit, r.sim, only: .seesaw, uid: uid), "\(label): a rider found a seat") }
        let bodyEnd = 6 * (MotionRig.renderMesh.armCapsule?.firstVertex[0] ?? 0)
        let n = lab.rigs.count
        let k = DecorKind.seesaw.scale
        /// The seat's point as it is DRAWN in this frame (the angle the riders were placed with in the last brain step), world.
        func drawnSeat(_ seat: Int) -> SIMD3<Float> {
            guard let f = field.foot(uid) else { return .zero }
            let p = SeesawTuning.seatLocal(seat: seat, theta: R.drawnTheta(uid)), w = f.turned(SIMD2(p.x, p.z))
            return SIMD3(f.centre.x + w.x, p.y + f.lift, f.centre.y + w.y)
        }
        rep.calLo = [Float](repeating: .infinity, count: n); rep.calHi = [Float](repeating: -.infinity, count: n)
        rep.rideLo = rep.calLo; rep.rideHi = rep.calHi
        rep.calN = [Int](repeating: 0, count: n); rep.rideN = rep.calN
        rep.aboveN = rep.calN; rep.aboveRunMax = rep.calN
        var aboveRun = [Int](repeating: 0, count: n)
        var walkT = [Int](repeating: 0, count: n), walkArrYaw = [Float](repeating: 0, count: n), walkArrBear = [Float](repeating: 0, count: n)
        var walkYawSum = [Float](repeating: 0, count: n), walkPrevYaw = [Float](repeating: 0, count: n), walkMaxDist = [Float](repeating: 0, count: n), walkBadYaw = [Float](repeating: 0, count: n)
        var justOffLanded = [Bool](repeating: false, count: n), afterOffLow = [Int](repeating: 0, count: n)
        var lastBlock = [String](repeating: "", count: n)
        var prevSw = [SIMD3<Float>](repeating: .zero, count: n)
        var prevTop = [SIMD3<Float>](repeating: .zero, count: n), prevTopValid = [Bool](repeating: false, count: n)
        func wrap(_ a: Float) -> Float { atan2f(sinf(a), cosf(a)) }
        var rode = [Bool](repeating: false, count: n)
        var prevC = lab.rigs.map { $0.sim.centroid() }
        var prevStepVec = [SIMD3<Float>](repeating: .zero, count: n)
        var prevRel = [SIMD3<Float>](repeating: .zero, count: n)
        var seatedRun = [Int](repeating: 0, count: n), airRun = [Int](repeating: 0, count: n)
        var prevRoot = lab.rigs.map { $0.brain.position }
        var prevStage = [Int](repeating: -1, count: n)
        var hopCur = [Hop](repeating: Hop(), count: n)
        var leaveStart = [Int](repeating: -1, count: n)
        var prevTh: Float = 0, prevD: Float = 0, lastCall = -1000
        var everSeated = Set<Int>(), doneAt = -1, called = false, pairRideSteps = 0
        let total = 60 * 110
        for i in 0..<total {
            lab.tick(watching: false); field.tick(dt: 1.0 / 60)
            let th = R.theta(uid), drawn = R.drawnTheta(uid), mode = R.mode(uid)
            if i > 0 {
                let d = th - prevTh, dd = d - prevD
                rep.maxD = max(rep.maxD, abs(d))
                if mode == .callAway { lastCall = i }
                if i - lastCall < 45 { rep.maxDDCall = max(rep.maxDDCall, abs(dd)) } else { rep.maxDD = max(rep.maxDD, abs(dd)) }
                prevD = d
            }
            prevTh = th
            rep.maxAmp = max(rep.maxAmp, R.amp(uid))
            if mode == .pairRide { pairRideSteps += 1 }
            for (j, r) in lab.rigs.enumerated() { feats[j].tick(id: 0, brain: r.brain, sim: r.sim, feature: JellyRoster.feature(chars[j]), worn: [], hideAll: false, dt: 1.0 / 60) }
            for (j, r) in lab.rigs.enumerated() {
                let b = r.brain, st = b.idleState
                let cen = r.sim.centroid()
                let cenXZ = SIMD2(cen.x, cen.z)
                let stepVec = cen - prevC[j]
                // (a rider who walks to the seesaw after an earlier sit still has the old bagStage until he arrives: that is no stage; decorGo is true during the walk)
                let stage = st.kind == .decorSit && !st.decorGo ? st.bagStage : -1
                let sw = drawnSeat(st.seat)
                // the walk-up: from his first step at the spot to the hop's first step: he stays at his spot, faces the SEAT, and never turns away and back
                if stage == 0, let f = field.foot(uid) {
                    let spots = b.seesawStandSpots(f, seat: st.seat)
                    let dmin = spots.map { simd_distance($0, b.position) }.min() ?? 0
                    let bearing = atan2f(sw.x - b.position.x, sw.z - b.position.y)
                    if walkT[j] == 0 { walkArrYaw[j] = b.yaw; walkArrBear[j] = bearing; walkYawSum[j] = 0; walkMaxDist[j] = 0; walkBadYaw[j] = 0 }
                    else { walkYawSum[j] += abs(wrap(b.yaw - walkPrevYaw[j])) }
                    walkPrevYaw[j] = b.yaw
                    if walkT[j] % 15 == 0, rep.stage0Lines < 40 {
                        rep.stage0Lines += 1
                        MotionLog.write(String(format: "SEESAW STAGE0 %@ i %d rider %d t %.2f s phaseT %.2f: root rel (%.3f, %.3f), centroid rel (%.3f, %.3f), centroid to seat %.3f m (hop limit %.2f), root to seat %.3f m, yaw %.2f bearing %.2f, activity %@, pitch %.3f roll %.3f", label, i, j, Float(walkT[j]) / 60, st.phaseT, b.position.x - centre.x, b.position.y - centre.y, cen.x - centre.x, cen.z - centre.y, simd_distance(cenXZ, SIMD2(sw.x, sw.z)), SeesawTuning.maxHop, simd_distance(b.position, SIMD2(sw.x, sw.z)), b.yaw, bearing, "\(b.activity)", b.pitch, b.roll))
                    }
                    walkT[j] += 1
                    walkMaxDist[j] = max(walkMaxDist[j], dmin)
                    if walkT[j] > 30 { walkBadYaw[j] = max(walkBadYaw[j], abs(wrap(b.yaw - bearing))) }
                } else if stage == 1 && prevStage[j] == 0 {
                    let allowed = abs(wrap(walkArrYaw[j] - walkArrBear[j])) + 0.3
                    rep.walkLines.append(String(format: "SEESAW walk-up: %@ rider %d turn before the hop max %.2f rad (arrived %.2f rad off the seat, allowed %.2f), wait %.2f s, farthest from his spot %.2f m, worst yaw error after 0.5 s %.2f rad", label, j, walkYawSum[j], abs(wrap(walkArrYaw[j] - walkArrBear[j])), allowed, Float(walkT[j]) / 60, walkMaxDist[j], walkBadYaw[j]))
                    if walkYawSum[j] > allowed { rep.walkFails.append("\(label) rider \(j): turned \(walkYawSum[j]) rad before the hop, allowed \(allowed)") }
                    if walkMaxDist[j] > 0.15 { rep.walkFails.append("\(label) rider \(j): \(walkMaxDist[j]) m from his spot while waiting") }
                    if walkBadYaw[j] > 0.6 { rep.walkFails.append("\(label) rider \(j): yaw \(walkBadYaw[j]) rad off the bearing to the seat after 0.5 s") }
                    walkT[j] = 0
                } else if stage != 0 { walkT[j] = 0 }
                // hops: from the first step of stage 1 (after 0) / stage 3 (after 2) to the first step after it
                if (stage == 1 && prevStage[j] == 0) || (stage == 3 && prevStage[j] == 2) {
                    var h = Hop()
                    h.kind = stage == 1 ? "on" : "off"; h.rider = j; h.step = i
                    h.from = SIMD2(prevC[j].x, prevC[j].z) - centre; h.thetaAtStart = drawn
                    h.forced = R.rides[uid]?.riders[st.seat]?.forced ?? false
                    h.startVsSeat = stage == 1 ? 0 : simd_distance(prevRoot[j], SIMD2(sw.x, sw.z))          // (the ROOT against the seat point: the body's centroid sits ~15 cm off it)
                    h.capped = leaveStart[j] >= 0 && Float(i - leaveStart[j]) / 60 >= SeesawTuning.calledWaitCap - 0.03
                    hopCur[j] = h
                }
                if (prevStage[j] == 1 && stage == 2) || (prevStage[j] == 3 && stage != 3) {
                    var h = hopCur[j]
                    h.to = cenXZ - centre
                    h.dist = simd_distance(h.to, h.from)
                    h.landing = prevStage[j] == 1 ? simd_distance(cenXZ, SIMD2(sw.x, sw.z)) : 0
                    if prevStage[j] == 3 { afterOff[j] = 20; justOffLanded[j] = true }
                    rep.hops.append(h)
                }
                if stage == 2, st.phase == 3, leaveStart[j] < 0 { leaveStart[j] = i }
                if stage != 2 { leaveStart[j] = stage == 3 ? leaveStart[j] : -1 }
                // smoothness: seated (relative to the drawn seat, the world step, the step vector's change) and in the air of a hop
                if stage == 2 {
                    seatedRun[j] += 1
                    let rel = cen - sw
                    // settled (phase 2, fully sat): the strict smoothness numbers; the sit-down and the get-up (phases 1 and 3: the body's squash lowers it by ~20 cm in about a second) get their own numbers
                    let settled = st.phase == 2 && st.k > 0.99 && st.phaseT > 0.3
                    if seatedRun[j] >= 2 {
                        rep.maxWorldStep = max(rep.maxWorldStep, simd_length(stepVec))
                        let rs = simd_distance(rel, prevRel[j])
                        if settled { if rs > rep.maxRel { rep.relWhere = String(format: "i %d rider %d phase %d k %.2f phaseT %.2f theta %.3f feet.active %@ step %.2f cm (prev %.2f)", i, j, st.phase, st.k, st.phaseT, drawn, "\(b.feet.active)", simd_length(stepVec) * 100, simd_length(prevStepVec[j]) * 100) }; rep.maxRel = max(rep.maxRel, rs) }
                        else { rep.maxRelTrans = max(rep.maxRelTrans, rs) }
                    }
                    if seatedRun[j] >= 3 {
                        let dv = simd_distance(stepVec, prevStepVec[j])
                        if settled { if dv > rep.maxSeatedDV { rep.dvWhere = String(format: "i %d rider %d phase %d k %.2f phaseT %.2f theta %.3f feet.active %@ step %.2f cm (prev %.2f)", i, j, st.phase, st.k, st.phaseT, drawn, "\(b.feet.active)", simd_length(stepVec) * 100, simd_length(prevStepVec[j]) * 100) }; rep.maxSeatedDV = max(rep.maxSeatedDV, dv) }
                        else { rep.maxDVTrans = max(rep.maxDVTrans, dv) }
                    }
                    prevRel[j] = rel
                    rep.seatedSteps += 1
                } else { seatedRun[j] = 0 }
                if (stage == 1 || stage == 3), b.gait.phase == .air {
                    airRun[j] += 1
                    rep.maxAirStep = max(rep.maxAirStep, simd_length(stepVec))
                    if airRun[j] >= 2, simd_distance(stepVec, prevStepVec[j]) > rep.maxAirDV { rep.airDvWhere = String(format: "i %d rider %d stage %d air step no %d step %.2f cm (prev %.2f) dy %.2f cm", i, j, stage, airRun[j], simd_length(stepVec) * 100, simd_length(prevStepVec[j]) * 100, stepVec.y * 100) }
                    if airRun[j] >= 2 { rep.maxAirDV = max(rep.maxAirDV, simd_distance(stepVec, prevStepVec[j])) }
                } else { airRun[j] = 0 }
                prevStepVec[j] = stepVec; prevC[j] = cen; prevStage[j] = stage; prevRoot[j] = b.position; prevSw[j] = sw
                let standing = (stage == 0 && b.activity != .walking && st.phaseT > 0.3) || afterOff[j] > 0
                if afterOff[j] > 0 { afterOff[j] -= 1 }
                guard stage >= 1 || standing || afterOffLow[j] > 0 || (stage == 0 && walkT[j] > 3) else { continue }
                r.render()
                // the arm capsule / foot bean blocks of the render buffer around the first hop start (are they ever away from the body in the DRAWN buffer?)
                if stage == 0 { r.dyn.withUnsafeBufferPointer { lastBlock[j] = Self.blockStats($0, root: b.position) } }
                else if stage == 1, i - hopCur[j].step <= 2, !rep.hops.contains(where: { $0.rider == j }) {
                    var now = ""
                    r.dyn.withUnsafeBufferPointer { now = Self.blockStats($0, root: b.position) }
                    MotionLog.write("SEESAW ARMS \(label) rider \(j) step \(i) (hop start + \(i - hopCur[j].step)) armG \(b.armG) beansActive \(r.skinner.beansActive) gait \(b.gait.phase): \(now)\n    one step before the hop (stage 0): \(lastBlock[j])")
                }
                if stage == 0, walkT[j] > 3 {
                    var lowY = Float.infinity
                    r.dyn.withUnsafeBufferPointer { d in var v = 0; while v + 2 < bodyEnd { lowY = min(lowY, d[v + 1]); v += 6 } }
                    rep.standLowSum += lowY; rep.standLowN += 1
                }
                if justOffLanded[j] {
                    justOffLanded[j] = false
                    var lowY = Float.infinity
                    r.dyn.withUnsafeBufferPointer { d in var v = 0; while v + 2 < bodyEnd { lowY = min(lowY, d[v + 1]); v += 6 } }
                    rep.offLandMinY.append(lowY)
                    afterOffLow[j] = 30
                } else if afterOffLow[j] > 0 {
                    afterOffLow[j] -= 1
                    if afterOffLow[j] == 0, st.kind == nil, b.activity != .walking, b.gait.phase == .idle {
                        var lowY = Float.infinity
                        r.dyn.withUnsafeBufferPointer { d in var v = 0; while v + 2 < bodyEnd { lowY = min(lowY, d[v + 1]); v += 6 } }
                        rep.offLandLater.append(lowY)
                        rep.offLandInfo.append(String(format: "rider %d: lowest skin %.2f cm; kind %@ stage %d activity %@ gait %@ root rel (%.2f, %.2f) y of the centre %.2f", j, lowY * 100, "\(String(describing: st.kind))", stage, "\(b.activity)", "\(b.gait.phase)", b.position.x - centre.x, b.position.y - centre.y, r.sim.centroid().y))
                    }
                }
                if b.armG > 0.5 { for si in 0..<2 { let g = b.armLastGeom[si]; rep.armMax = max(rep.armMax, ArmCap.exposed(a: SIMD3<Double>(g.a), b: SIMD3<Double>(g.b), r2: Double(g.r2))) } }
                // feet: the leash never moves a foot piece
                if r.skinner.beansActive {
                    let pull = max(max(r.skinner.joinLeash[0], r.skinner.joinLeash[1]), max(r.skinner.weldPull[0], r.skinner.weldPull[1]))
                    if pull > 0.002 { rep.leashFrames += 1; rep.leashMax = max(rep.leashMax, pull) }
                }
                if standing {
                    var zmin = Float.infinity
                    r.dyn.withUnsafeBufferPointer { d in
                        var v = 0
                        while v + 2 < bodyEnd { if d[v + 1] > 0.25, d[v + 1] < 0.9, abs(d[v] - centre.x) < 1.5 { zmin = min(zmin, abs(d[v + 2] - centre.y)) }; v += 6 }
                    }
                    if stage == 0 {
                        rep.waitMinZ = min(rep.waitMinZ, zmin)
                    }
                    if zmin < rep.standMinZ {
                        rep.standMinZ = zmin; rep.standRootZ = abs(b.position.y - centre.y)
                        var wv = -1
                        r.dyn.withUnsafeBufferPointer { d in
                            var v = 0
                            while v + 2 < bodyEnd { if d[v + 1] > 0.25, d[v + 1] < 0.9, abs(d[v] - centre.x) < 1.5, abs(abs(d[v + 2] - centre.y) - zmin) < 1e-6 { wv = v / 6; break }; v += 6 }
                        }
                        rep.standWhere = String(format: "vertex %d at rel (%.2f, %.2f, %.2f), root rel (%.2f, %.2f), stage %d, activity %@, phaseT %.2f, i %d", wv, wv >= 0 ? r.dyn[6 * wv] - centre.x : 0, wv >= 0 ? r.dyn[6 * wv + 1] : 0, wv >= 0 ? r.dyn[6 * wv + 2] - centre.y : 0, b.position.x - centre.x, b.position.y - centre.y, stage, "\(b.activity)", st.phaseT, i)
                    }
                    // the smallest distance from the skin to the piece (beam, pads, base, handles; level plank) while he waits on his stand spot / just after the hop off
                    r.dyn.withUnsafeBufferPointer { d in
                        var v = 0
                        while v + 2 < d.count {
                            if Self.parked(v / 6, armOn: b.armG > 0.5, tailOn: r.skinner.tailOn, teddyOn: r.skinner.teddyOn, beansOn: r.skinner.beansActive) { v += 6; continue }
                            let p = SIMD3<Float>((d[v] - centre.x) / k, d[v + 1] / k, (d[v + 2] - centre.y) / k)
                            if abs(p.x) < 1.6, p.y < 0.8, abs(p.z) < 1.2 {
                                let m = Self.standDist(p)
                                if m * k < rep.standClear { rep.standClear = m * k; rep.clearWhere = String(format: "i %d rider %d stage %d phase %d phaseT %.2f activity %@ vertex %d rel (%.2f, %.2f, %.2f) root rel (%.2f, %.2f)", i, j, stage, st.phase, st.phaseT, "\(b.activity)", v / 6, d[v] - centre.x, d[v + 1], d[v + 2] - centre.y, b.position.x - centre.x, b.position.y - centre.y) }
                            }
                            v += 6
                        }
                    }
                }
                if stage == 2 { everSeated.insert(j) }
                // seated: the root against the drawn seat point; settled: the lowest skin point against the pad's top plane
                if stage == 2 {
                    let rs = simd_distance(b.position, SIMD2(sw.x, sw.z))
                    if rs > rep.rootSeatAny {
                        rep.rootWhere = String(format: "i %d rider %d phase %d phaseT %.2f k %.2f theta %.4f thetaRate %.3f/s, seat moved %.2f cm since the last step, feet.active %@, forced %@, mode %@, hold %.0f, root-to-seat %.2f cm", i, j, st.phase, st.phaseT, st.k, drawn, R.thetaRate(uid), simd_distance(SIMD2(sw.x, sw.z), SIMD2(prevSw[j].x, prevSw[j].z)) * 100, "\(b.feet.active)", "\(R.rides[uid]?.riders[st.seat]?.forced ?? false)", "\(mode)", st.hold, rs * 100)
                    }
                    rep.rootSeatAny = max(rep.rootSeatAny, rs)
                    if rode[j], st.phase == 2, st.phaseT > 0.5 { rep.rootSeatRide = max(rep.rootSeatRide, rs); rep.rideSteps += 1 }
                }
                if stage == 2, st.phase == 2, st.phaseT > 0.25, st.k > 0.99 {
                    var lowest = Float.infinity
                    var topY = -Float.infinity, topPos = SIMD3<Float>.zero
                    let sx: Float = st.seat == 0 ? -1 : 1
                    r.dyn.withUnsafeBufferPointer { d in
                        var v = 0
                        while v + 2 < bodyEnd {
                            let ps = SeesawTuning.toSeat(SIMD3(d[v] - centre.x, d[v + 1], d[v + 2] - centre.y), seat: st.seat, theta: drawn)
                            // the pad's top: the patch around the sit point (x within 0.2, z within 0.14, model units)
                            if abs(ps.x - sx * SeesawTuning.seatX) < 0.2, abs(ps.z) < 0.14 { lowest = min(lowest, (ps.y - SeesawTuning.seatTopY) * k) }
                            if d[v + 1] > topY { topY = d[v + 1]; topPos = SIMD3(d[v], d[v + 1], d[v + 2]) }
                            v += 6
                        }
                    }
                    if lowest.isFinite {
                        if abs(drawn) < 0.003, R.amp(uid) == 0 { rep.calLo[j] = min(rep.calLo[j], lowest); rep.calHi[j] = max(rep.calHi[j], lowest); rep.calN[j] += 1 }
                        if rode[j] { rep.rideLo[j] = min(rep.rideLo[j], lowest); rep.rideHi[j] = max(rep.rideHi[j], lowest); rep.rideN[j] += 1 }
                        if !rode[j], abs(drawn) >= 0.003 { rode[j] = true; rep.rideLo[j] = min(rep.rideLo[j], lowest); rep.rideHi[j] = max(rep.rideHi[j], lowest); rep.rideN[j] += 1 }
                        if rode[j] {
                            if lowest > 0.005 { rep.aboveN[j] += 1; aboveRun[j] += 1; rep.aboveRunMax[j] = max(rep.aboveRunMax[j], aboveRun[j]) } else { aboveRun[j] = 0 }
                        }
                    }
                    let topRel = topPos - sw
                    if prevTopValid[j], st.phaseT > 0.3 {
                        let tr = simd_distance(topRel, prevTop[j])
                        if tr > rep.topRelMax { rep.topRelMax = tr; rep.topRelWhere = String(format: "i %d rider %d theta %.4f thetaRate %.3f/s: highest skin point rel (%.2f, %.2f, %.2f) m, moved %.2f cm against the seat that step (settled centroid max %.2f cm so far)", i, j, drawn, R.thetaRate(uid), topRel.x, topRel.y, topRel.z, tr * 100, rep.maxRel * 100) }
                    }
                    prevTop[j] = topRel; prevTopValid[j] = true
                } else { prevTopValid[j] = false }
                // nothing of the rider inside the beam, a handle or the deep part of a pad (every skin vertex, the feet and the tail included), every 2nd step
                if i % 2 == 0 {
                    var tailHit = false, tailMaxV = -1
                    r.dyn.withUnsafeBufferPointer { d in
                        var v = 0
                        while v + 2 < d.count {
                            if Self.parked(v / 6, armOn: b.armG > 0.5, tailOn: r.skinner.tailOn, teddyOn: r.skinner.teddyOn, beansOn: r.skinner.beansActive) { v += 6; continue }
                            if let c = Self.clearances(SIMD3(d[v], d[v + 1], d[v + 2]), centre: centre, th: drawn) {
                                if c.handle < rep.handleMin {
                                    let pl = SeesawTuning.toPlank(SIMD3(d[v] - centre.x, d[v + 1], d[v + 2] - centre.y), theta: drawn)
                                    rep.handleWhere = String(format: "i %d rider %d stage %d phase %d phaseT %.2f gait %@ feet.active %@ theta %.3f: vertex %d (%@) at plank-frame (%.3f, %.3f, %.3f) model units = handle %@ side, %.2f cm from the handle box (negative = inside); root rel (%.2f, %.2f)", i, j, stage, st.phase, st.phaseT, "\(b.gait.phase)", "\(b.feet.active)", drawn, v / 6, Self.partName(v / 6), pl.x, pl.y, pl.z, pl.x < 0 ? "left" : "right", c.handle * 100, b.position.x - centre.x, b.position.y - centre.y)
                                }
                                if c.beam > 0.005, Self.partCode(v / 6) == 5 { tailHit = true; if c.beam > rep.tailMax { rep.tailMax = c.beam; tailMaxV = v } }
                                rep.beamDepth = max(rep.beamDepth, c.beam); rep.handleMin = min(rep.handleMin, c.handle); rep.padOther = max(rep.padOther, c.pad)
                                let at = String(format: "i %d rider %d stage %d phase %d phaseT %.2f gait %@ theta %.3f vertex %d (body ends at %d, arm caps %d/%d, tail %d, teddy %d) rel (%.2f, %.2f, %.2f) root rel (%.2f, %.2f)", i, j, stage, st.phase, st.phaseT, "\(b.gait.phase)", drawn, v / 6, bodyEnd / 6, MotionRig.renderMesh.armCapsule?.firstVertex[0] ?? -1, MotionRig.renderMesh.armCapsule?.firstVertex[1] ?? -1, MotionRig.renderMesh.armCapsule?.tailFirst ?? -1, MotionRig.renderMesh.armCapsule?.teddyFirst ?? -1, d[v] - centre.x, d[v + 1], d[v + 2] - centre.y, b.position.x - centre.x, b.position.y - centre.y)
                                if c.beam >= rep.beamDepth { rep.beamWhere = at }; if c.pad >= rep.padOther { rep.padWhere = at }
                            }
                            v += 6
                        }
                    }
                    if tailHit {
                        rep.tailN += 1; if rep.tailFirst < 0 { rep.tailFirst = i }; rep.tailLast = i
                        if tailMaxV >= 0 && rep.tailMax > 0 {
                            var mean = SIMD3<Float>.zero, cnt: Float = 0
                            r.dyn.withUnsafeBufferPointer { d in
                                var w = 0
                                while w + 2 < d.count { if Self.partCode(w / 6) == 5 { mean += SIMD3(d[w], d[w + 1], d[w + 2]); cnt += 1 }; w += 6 }
                                let vv = tailMaxV
                                if rep.tailMax > 0.005 { rep.tailInfo = String(format: "sim t=%.2f s (step %d) rider %d stage %d phase %d phaseT %.2f gait %@ activity %@ yaw %.2f (%@): deepest tail vertex rel root (%.2f, %.2f, %.2f) m = %.2f cm inside the beam; tail mean rel root (%.2f, %.2f, %.2f), root rel centre (%.2f, %.2f)", Float(i) / 60, i, j, stage, st.phase, st.phaseT, "\(b.gait.phase)", "\(b.activity)", b.yaw, b.feet.active ? "feet stepping" : "feet still", d[vv] - b.position.x, d[vv + 1], d[vv + 2] - b.position.y, rep.tailMax * 100, cnt > 0 ? mean.x / cnt - b.position.x : 0, cnt > 0 ? mean.y / cnt : 0, cnt > 0 ? mean.z / cnt - b.position.y : 0, b.position.x - centre.x, b.position.y - centre.y) }
                            }
                        }
                    }
                }
            }
            if i % 4 == 0 {
                for (j, r) in lab.rigs.enumerated() where lab.rigs[j].brain.idleState.kind == .decorSit && lab.rigs[j].brain.idleState.bagStage == 2 {
                    let ff = r.dyn.withUnsafeBufferPointer { p in feats[j].frame { _ in p.baseAddress } }
                    for v in ff.vertices {
                        if let c = Self.clearances(SIMD3(v.pos.x, v.pos.y, v.pos.z), centre: centre, th: drawn) {
                            rep.featureBeam = max(rep.featureBeam, c.beam); rep.featureHandle = min(rep.featureHandle, c.handle); rep.featurePad = max(rep.featurePad, c.pad)
                        }
                    }
                }
            }
            if n == 2, i % 6 == 0, lab.rigs.allSatisfy({ $0.brain.idleState.bagStage == 2 && $0.brain.idleState.kind == .decorSit }) {
                var best = Float.infinity
                lab.rigs[0].dyn.withUnsafeBufferPointer { a in
                    lab.rigs[1].dyn.withUnsafeBufferPointer { c in
                        var u = 0
                        while u + 2 < bodyEnd {
                            var w = 0
                            while w + 2 < bodyEnd {
                                let dx = a[u] - c[w], dy = a[u + 1] - c[w + 1], dz = a[u + 2] - c[w + 2]
                                best = min(best, dx * dx + dy * dy + dz * dz)
                                w += 48
                            }
                            u += 48
                        }
                    }
                }
                rep.riderSkin = min(rep.riderSkin, best.squareRoot())
            }
            if n == 2, lab.rigs.allSatisfy({ $0.brain.idleState.bagStage == 2 && $0.brain.idleState.kind == .decorSit }) {
                rep.bodyGapMin = min(rep.bodyGapMin, simd_distance(lab.rigs[0].sim.centroid(), lab.rigs[1].sim.centroid()))
            }
            if callAway, !called, mode == .pairRide, (R.rides[uid]?.modeT ?? 0) > 3 { called = true; lab.rigs[1].brain.idleState.hold = 0; for r in lab.rigs { r.brain.anticsEnabled = false } }          // (he does not pick the seesaw again on his own)
            if everSeated.count == n { rep.seatedAll = true }
            if rep.seatedAll, lab.rigs.allSatisfy({ $0.brain.idleState.kind == nil }) { if doneAt < 0 { doneAt = i }; if i - doneAt > 180 { break } }
        }
        rep.finished = doneAt >= 0
        rep.swings = Float(pairRideSteps) / 60 / SeesawTuning.period
        rep.refused = R.refusedHops
        MotionLog.write("SEESAW \(label): stage-0 re-walks to the own spot by seat \(R.rewalks) at distances (m) \(R.rewalkDists.map { String(format: "%.2f", $0) }) (0 expected: the walk-up ends on the own spot)")
        for r in lab.rigs { r.brain.abortScript(r.sim, r.skinner) }
        return rep
    }

    func check(_ rep: Report, pair: Bool, callAway: Bool) {
        let t = rep.tag
        let hopsOn = rep.hops.filter { $0.kind == "on" }, hopsOff = rep.hops.filter { $0.kind == "off" }
        MotionLog.write(String(format: "SEESAW %@: finished %@ seated %@ | root-seat riding max %.2f cm (limit 0.3), at every seated step max %.2f cm (limit 1) | seated steps %d, riding %d | settled: motion vs the seat max %.2f cm/step (0.5); sit-down / get-up (not asserted): motion vs the seat max %.2f, step-vector change max %.2f cm; seated, world step max %.2f cm (3), step-vector change max %.2f cm (0.6) | air: step max %.2f cm (9.7), step-vector change max %.2f cm (1.5) | dtheta %.4f ddtheta %.5f (call %.5f) | leash frames %d (max %.1f cm) | beam depth %.2f cm, handle min %.2f cm, deep pad %.2f cm, riders %.2f m | swings %.1f amp max %.2f | hops on %d off %d, longest %.2f m, refused %d | stand clearance %.2f cm | arm %.4f (max %.4f) | features: beam %.2f cm handle %.2f cm deep pad %.2f cm | stand reach: skin z %.1f cm from the piece centre line (root %.1f cm) | rider skin to rider skin min %.1f cm",
                              t, rep.finished ? "Y" : "N", rep.seatedAll ? "Y" : "N", rep.rootSeatRide * 100, rep.rootSeatAny * 100, rep.seatedSteps, rep.rideSteps, rep.maxRel * 100, rep.maxRelTrans * 100, rep.maxDVTrans * 100, rep.maxWorldStep * 100, rep.maxSeatedDV * 100, rep.maxAirStep * 100, rep.maxAirDV * 100,
                              rep.maxD, rep.maxDD, rep.maxDDCall, rep.leashFrames, rep.leashMax * 100, rep.beamDepth * 100, rep.handleMin * 100, rep.padOther * 100, rep.bodyGapMin,
                              rep.swings, rep.maxAmp, hopsOn.count, hopsOff.count, rep.hops.map { $0.dist }.max() ?? 0, rep.refused, rep.standClear * 100, rep.armMax, ArmCap.maximum, rep.featureBeam * 100, rep.featureHandle * 100, rep.featurePad * 100, rep.standMinZ * 100, rep.standRootZ * 100, rep.riderSkin * 100))
        MotionLog.write("SEESAW \(t): TRACE handle (min \(rep.handleMin * 100) cm): \(rep.handleWhere)")
        MotionLog.write("SEESAW \(t): TRACE root to seat (max \(rep.rootSeatAny * 100) cm): \(rep.rootWhere)")
        MotionLog.write("SEESAW \(t): settled head top: \(rep.topRelWhere)")
        for j in 0..<rep.aboveN.count { MotionLog.write(String(format: "SEESAW %@: rider %d riding steps more than 0.5 cm above the pad's plane: %d of %d (%.1f %%), longest run %d steps", t, j, rep.aboveN[j], rep.rideN[j], rep.rideN[j] > 0 ? 100 * Float(rep.aboveN[j]) / Float(rep.rideN[j]) : 0, rep.aboveRunMax[j])) }
        for l in rep.walkLines { MotionLog.write(l) }
        MotionLog.write("SEESAW \(t): lowest skin point at the first step after a hop off, against the ground (cm): \(rep.offLandMinY.map { String(format: "%.2f", $0 * 100) })")
        MotionLog.write("SEESAW \(t): WHERE beam depth: \(rep.beamWhere) | deep pad: \(rep.padWhere) | stand clearance: \(rep.clearWhere) | worst relative-to-seat step: \(rep.relWhere) | worst seated dv: \(rep.dvWhere) | worst air dv: \(rep.airDvWhere)")
        for j in 0..<rep.calLo.count {
            MotionLog.write(String(format: "SEESAW %@: rider %d pad margin (lowest skin point vs the pad's top plane): level and still [%.2f, %.2f] cm (%d samples), riding [%.2f, %.2f] cm (%d samples)", t, j, rep.calLo[j] * 100, rep.calHi[j] * 100, rep.calN[j], rep.rideLo[j] * 100, rep.rideHi[j] * 100, rep.rideN[j]))
        }
        MotionLog.write(String(format: "SEESAW %@: deepest stand reach: %@ | waiting on the stand spot (stage 0): skin %.1f cm from the centre line (cushion edge 28 cm)", t, rep.standWhere, rep.waitMinZ * 100))
        for h in rep.hops { MotionLog.write(String(format: "SEESAW %@: HOP %@ rider %d step %d stage %@ forced %@ capped %@ from (%.2f, %.2f) to (%.2f, %.2f) = %.2f m | theta at start %.4f, start vs seat %.2f cm, landing error %.2f cm", t, h.kind, h.rider, h.step, h.kind == "on" ? "0->1->2" : "2->3->out", h.forced ? "Y" : "N", h.capped ? "Y" : "N", h.from.x, h.from.y, h.to.x, h.to.y, h.dist, h.thetaAtStart, h.startVsSeat * 100, h.landing * 100)) }
        // the proof line for "no jump across the park": running totals over every cast and seed run so far (the LAST such line of a run is the total)
        Self.hopUpMax = max(Self.hopUpMax, hopsOn.map { $0.dist }.max() ?? 0); Self.hopDownMax = max(Self.hopDownMax, hopsOff.map { $0.dist }.max() ?? 0)
        Self.hopCount += rep.hops.count; Self.hopRefusals += rep.refused
        MotionLog.write(String(format: "SEESAW HOPS upMax=%.2f downMax=%.2f hops=%d refusals=%d", Self.hopUpMax, Self.hopDownMax, Self.hopCount, Self.hopRefusals))
        XCTAssertTrue(rep.seatedAll, "\(t): everybody sat down"); XCTAssertTrue(rep.finished, "\(t): everybody got off")
        // root to the drawn seat, same step
        XCTAssertLessThan(rep.rootSeatRide, 0.003, "\(t): riding, the root is within 0.3 cm of the drawn seat")
        XCTAssertLessThan(rep.rootSeatAny, 0.01, "\(t): at every seated step the root is within 1 cm of the drawn seat")
        // smooth, not slow
        XCTAssertLessThan(rep.maxRel, 0.007, "\(t): settled, the body moves under 0.7 cm a step relative to the seat (the lean alone moves the head top about 0.4 cm a step at the swing's fastest point)")
        XCTAssertLessThan(rep.maxWorldStep, 0.03, "\(t): seated, the world step is under 3 cm")
        XCTAssertLessThan(rep.maxSeatedDV, 0.006, "\(t): settled, the step vector changes by under 0.6 cm between steps")
        // (the air-phase step-vector change is judged against the stock hop: testSlowerHopIsGentler)
        XCTAssertLessThanOrEqual(rep.maxAirStep, 0.097, "\(t): no air step over 9.7 cm (the stock bag hop)")
        // the pad contact, self-calibrated
        for j in 0..<rep.calLo.count {
            XCTAssertGreaterThan(rep.calN[j], 0, "\(t): rider \(j) has calibration samples (level, still, settled)")
            XCTAssertGreaterThan(rep.rideN[j], 0, "\(t): rider \(j) has riding samples")
            guard rep.calN[j] > 0, rep.rideN[j] > 0 else { continue }
            XCTAssertGreaterThanOrEqual(rep.rideLo[j], rep.calLo[j] - 0.005, "\(t): rider \(j) riding, the lowest skin point is not lower than level + 0.5 cm")
            XCTAssertLessThanOrEqual(rep.rideHi[j], 0.0075, "\(t): rider \(j) riding, the lowest skin point is never more than 0.75 cm above the pad's plane")
        }
        XCTAssertEqual(rep.leashFrames, 0, "\(t): the skin's leash never moved a foot piece (max \(rep.leashMax * 100) cm)")
        XCTAssertLessThan(rep.beamDepth, 0.005, "\(t): nothing of the rider is more than 0.5 cm inside the beam")
        XCTAssertGreaterThanOrEqual(rep.handleMin, -0.005, "\(t): nothing of the rider is more than 0.5 cm inside a handle")
        XCTAssertLessThan(rep.padOther, 0.005, "\(t): nothing of the rider is inside the deep part of a pad")
        if pair { XCTAssertGreaterThanOrEqual(rep.riderSkin, 0.20, "\(t): rider skin to rider skin stays at least 20 cm apart") }
        if pair { XCTAssertGreaterThan(rep.bodyGapMin, 1.2, "\(t): the riders' bodies stay apart") }
        XCTAssertGreaterThanOrEqual(rep.standClear, 0.01, "\(t): standing on the stand spot or just landed, the body is at least 1 cm from the pads, beam, handles, bumpers and the base's parts")
        for f in rep.walkFails { XCTFail("SEESAW walk-up: \(f)") }
        // (a standing body's lowest skin point is not at y 0: the feet carry it. So "on the ground" = as high as he stands at his spot, within 1.5 cm)
        let standLow = rep.standLowN > 0 ? rep.standLowSum / Float(rep.standLowN) : 0
        MotionLog.write(String(format: "SEESAW %@: a body standing at his spot has its lowest skin point %.2f cm above the ground", t, standLow * 100))
        for l in rep.offLandInfo { MotionLog.write("SEESAW \(t): ground reading 0.5 s after a hop off: \(l)") }
        MotionLog.write("SEESAW \(t): TAIL in the beam: \(rep.tailN) samples (every 2nd step) from step \(rep.tailFirst) to \(rep.tailLast), max \(rep.tailMax * 100) cm. \(rep.tailInfo)")
        MotionLog.write("SEESAW \(t): 0.5 s after the hop off the lowest skin point is (cm) \(rep.offLandLater.map { String(format: "%.2f", $0 * 100) })")
        // (the first step after the hop is still in the landing squash, 6-9 cm up: printed above; half a second later he is on the ground)
        for y in rep.offLandLater { XCTAssertLessThanOrEqual(abs(y), 0.015, "\(t): 0.5 s after a hop off the lowest skin point is within 1.5 cm of the ground (it is \(y * 100) cm)") }
        XCTAssertLessThanOrEqual(rep.armMax, ArmCap.maximum * 1.02, "\(t): the arms stay stubby")
        XCTAssertLessThan(rep.featureBeam, 0.005, "\(t): wings / ears / features not more than 0.5 cm inside the beam")
        XCTAssertGreaterThanOrEqual(rep.featureHandle, -0.005, "\(t): wings / ears / features not more than 0.5 cm inside a handle")
        XCTAssertLessThan(rep.featurePad, 0.005, "\(t): wings / ears / features not inside the deep part of a pad")
        // hops
        for h in rep.hops {
            XCTAssertLessThanOrEqual(h.dist, SeesawTuning.maxHopCentre, "\(t): a hop \(h.kind) travels \(h.dist) m (centre to centre, limit \(SeesawTuning.maxHopCentre))")
            if h.kind == "on" { XCTAssertLessThan(h.landing, 0.01, "\(t): lands on the seat within 1 cm"); XCTAssertLessThan(abs(h.thetaAtStart), 0.01, "\(t): nobody hops on while the plank moves") }
            if h.forced { XCTAssertLessThan(h.startVsSeat, 0.01, "\(t): the called-away hop starts within 1 cm of the seat"); if h.kind == "off" { XCTAssertTrue(abs(h.thetaAtStart) < 0.01 || h.capped, "\(t): a called-away rider hops off a still plank or after the capped wait") } }
            else if h.kind == "off" { XCTAssertLessThan(abs(h.thetaAtStart), 0.01, "\(t): nobody hops off while the plank moves") }
        }
        XCTAssertEqual(rep.refused, 0, "\(t): the hop guard refused nothing")
        XCTAssertEqual(hopsOn.count, pair ? 2 : 1, "\(t): hops on"); XCTAssertEqual(hopsOff.count, pair ? 2 : 1, "\(t): hops off")
        if pair && !callAway { XCTAssertGreaterThanOrEqual(rep.swings, 3, "\(t): at least 3 full swings together") }
        if !pair { XCTAssertLessThanOrEqual(rep.maxAmp, 0.3, "\(t): alone the bounce never exceeds amp 0.3") }
    }

    /// The walk-up target for the seesaw is its own spot (1.0 m out), never the generic stand spot or the piece's far end.
    func testWalkUpGoesToTheOwnSpot() {
        RoomLayout.apply(RoomCatalog.park); GameCamera.configurePark(); _ = GameCamera.refreshRoam(aspect: 440.0 / 956.0)
        let place = ParkToys.placed.filter { $0.kind == .seesaw }
        let far = SIMD2<Float>(2.0, -0.3), start = SIMD2<Float>(0.4, -0.4)
        let probe = SocialTests.Lab(n: 1, positions: [start], quiet: true, seed: 5)
        Self.keep.append(probe)
        for r in probe.rigs { r.sim.arenaCenter = GameCamera.arenaCenter; r.sim.arenaRadius = GameCamera.arenaRadius }
        DecorField.shared.set(place)          // (a Lab clears the field when it is made: the piece goes in after it)
        guard let f = DecorField.shared.foot(uid) else { XCTFail("the seesaw is placed"); return }
        for seat in 0..<2 {
            let spots = probe.rigs[0].brain.seesawStandSpots(f, seat: seat)
            let sp = f.kind.sitPoints[seat], seatXZ = f.centre + f.turned(SIMD2(sp.x, sp.z))
            func stand(_ peers: [SIMD2<Float>], _ label: String) -> SIMD2<Float>? {
                let lab = SocialTests.Lab(n: 1 + peers.count, positions: [start] + peers, quiet: true, seed: 5)
                Self.keep.append(lab)
                RoomLayout.apply(RoomCatalog.park); GameCamera.configurePark(); _ = GameCamera.refreshRoam(aspect: 440.0 / 956.0)
                for r in lab.rigs { r.sim.arenaCenter = GameCamera.arenaCenter; r.sim.arenaRadius = GameCamera.arenaRadius }          // (the park's arena, as the riding runs: else the spots are off the floor)
                DecorField.shared.set(place)
                for _ in 0..<2 { lab.tick(watching: false) }
                lab.rigs[0].brain.decorIgnore = uid          // (as `decorStart` does while it asks for the stand spot: the piece itself does not push the spot)
                let r = lab.rigs[0].brain.decorStand(.decorSit, f, from: start, seat: seat)
                var idx = "nil"
                if let r, let i = spots.indices.min(by: { simd_distance(spots[$0], r) < simd_distance(spots[$1], r) }) { idx = "spot \(i) (off by \(String(format: "%.1f", simd_distance(spots[i], r) * 100)) cm), \(String(format: "%.2f", simd_distance(r, seatXZ))) m from the seat point" }
                let own = lab.rigs[0].brain.seesawFreeSpot(f, seat: seat, from: start)
                MotionLog.write("SEESAW walk-up seat \(seat) \(label): decorStand = \(idx); seesawFreeSpot = \(String(describing: own)); fixed(spot0) = \(lab.rigs[0].brain.fixed(spots[0])), peerFree(spot0) = \(lab.rigs[0].brain.peerFree(spots[0])), peers \(lab.rigs[0].brain.steerPeers().map { $0.pos }); spots \(spots); walkZ \(GameCamera.walkMinZ)...\(GameCamera.walkMaxZ)")
                return r
            }
            // free: the own spot
            // free: the first of his three spots the floor keeps where it is (seat 0's first spot is 0.2 m off the walkable floor on the portrait park camera: the +0.2 spot is his own then)
            probe.rigs[0].brain.decorIgnore = uid
            let firstOn = spots.firstIndex { simd_distance(probe.rigs[0].brain.fixed($0), $0) < 0.05 } ?? -1
            MotionLog.write("SEESAW walk-up seat \(seat): the first spot on the floor is spot \(firstOn)")
            if let r = stand([far, far + SIMD2(0, 0.9), far + SIMD2(0, -0.9)], "free") { XCTAssertGreaterThanOrEqual(firstOn, 0); if firstOn >= 0 { XCTAssertLessThan(simd_distance(r, spots[firstOn]), 0.01, "seat \(seat): free, the walk-up goes to the own spot") } } else { XCTFail("seat \(seat): free, a spot") }
            // a peer on the own spot: another of his spots or nil, never farther than maxHop from the seat point
            if let r = stand([spots[0], far, far + SIMD2(0, 0.9)], "peer on spot 0") {
                XCTAssertTrue(simd_distance(r, spots[1]) < 0.01 || simd_distance(r, spots[2]) < 0.01, "seat \(seat): the other spots")
                XCTAssertLessThanOrEqual(simd_distance(r, seatXZ), SeesawTuning.maxHop, "seat \(seat): in hop range")
            }
            // peers on all three: nil
            XCTAssertNil(stand([spots[0], spots[1], spots[2]], "peers on all three"), "seat \(seat): none free, the piece is skipped")
        }
        DecorField.shared.clear()
    }

    // MARK: the friend who must get on (round 2c)

    /// A small world for the boarding tests: the park, the seesaw in play, `chars` at `starts`, nobody on the piece yet.
    private func boardWorld(chars: [Int], starts: [SIMD2<Float>], seed: UInt64) -> (lab: SocialTests.Lab, centre: SIMD2<Float>) {
        RoomLayout.apply(RoomCatalog.park); GameCamera.configurePark(); _ = GameCamera.refreshRoam(aspect: 440.0 / 956.0)
        let lab = SocialTests.Lab(n: chars.count, positions: starts, quiet: true, seed: seed)
        Self.keep.append(lab)
        for (k, r) in lab.rigs.enumerated() {
            r.sim.arenaCenter = GameCamera.arenaCenter; r.sim.arenaRadius = GameCamera.arenaRadius
            r.brain.anticsEnabled = true; r.brain.idleMood = .happy; r.brain.idleForced = true; r.skinner.autoBlink = false; r.renderSamples = false
            r.brain.feature = JellyRoster.feature(chars[k])
            r.skinner.configureTail(MotionRig.renderMesh); r.skinner.tailOn = r.brain.feature == .spines; r.brain.skinnerRef = r.skinner
        }
        WearBody.install(MotionRig.renderMesh)
        let place = ParkToys.placed.filter { $0.kind == .seesaw }
        DecorField.shared.set(place)
        DecorField.shared.toys.news.removeAll()
        SeesawRide.shared.reset()
        return (lab, place[0].at)
    }

    /// B (the GREEN species, Moss's body) takes the free LEFT seat while A's solo ride is in `mode` (.ending / .endBeat / .leaving): B must get on, within 4 s of standing at his spot, and never give up.
    func testFriendArrivesAsTheRideEnds() {
        SeesawTuning.invitations = false          // (this scenario sends B by hand: an invited free Jelbie would take the seat first)
        defer { SeesawTuning.invitations = true }
        for seed: UInt64 in [3, 8] {
            for mode in [SeesawRide.Mode.ending, .endBeat, .leaving] {
                let label = "friend arrives in \(mode) s\(seed)"
                let c0 = ParkToys.placed.first { $0.kind == .seesaw }!.at
                let (lab, centre) = boardWorld(chars: [0, 2], starts: [c0 + SIMD2(0.9, 1.6), c0 + SIMD2(0.2, 2.2)], seed: seed)
                let R = SeesawRide.shared, field = DecorField.shared
                let a = lab.rigs[0], b = lab.rigs[1]
                b.brain.anticsEnabled = false          // (B waits where he is until he is sent: he must not wander off meanwhile)
                XCTAssertTrue(a.brain.decorStart(.decorSit, a.sim, only: .seesaw, uid: uid), "\(label): A found the seat")
                var bStarted = -1, bBoarded = -1, lastReason = "", lastPrint = -1000, stage0Start = -1
                let total = 60 * 70
                for i in 0..<total {
                    lab.tick(watching: false); field.tick(dt: 1.0 / 60)
                    if bStarted < 0, R.mode(uid) == mode {
                        bStarted = i
                        XCTAssertTrue(b.brain.decorStart(.decorSit, b.sim, only: .seesaw, uid: uid), "\(label): B found the free seat")
                        b.brain.anticsEnabled = false
                    }
                    guard bStarted >= 0 else { continue }
                    let st = b.brain.idleState
                    let stage = st.kind == .decorSit && !st.decorGo ? st.bagStage : -1
                    if stage != 0, stage0Start < 0, (i - bStarted) % 30 == 0, i - bStarted < 60 * 8 { MotionLog.write(String(format: "SEESAWWAIT t=%.2f before stage 0: kind %@ decorGo %@ bagStage %d activity %@ root=(%.2f,%.2f) target=(%.2f,%.2f) occupants %@ mode %@ [%@]", Float(i) / 60, "\(String(describing: st.kind))", "\(st.decorGo)", st.bagStage, "\(b.brain.activity)", b.brain.position.x - centre.x, b.brain.position.y - centre.y, st.target.x - centre.x, st.target.y - centre.y, "\(field.seatOccupant[uid] ?? [:])", "\(R.mode(uid))", label)) }
                    if stage == 0 {
                        if stage0Start < 0 { stage0Start = i }
                        let info = R.waitInfo[st.seat] ?? "-|"
                        let parts = info.split(separator: "|", omittingEmptySubsequences: false)
                        let reason = String(parts.first ?? "-")
                        if reason != lastReason || i - lastPrint >= 60 {
                            lastReason = reason; lastPrint = i
                            let cen = b.sim.centroid()
                            MotionLog.write(String(format: "SEESAWWAIT t=%.2f reason=%@ root=(%.2f,%.2f) centre=(%.2f,%.2f) spot=%@ mode=%@ phaseT=%.2f | %@ [%@ s%d]", Float(i) / 60, reason, b.brain.position.x - centre.x, b.brain.position.y - centre.y, cen.x - centre.x, cen.z - centre.y, "\(b.brain.seesawStandSpots(field.foot(uid)!, seat: st.seat)[0] - centre)", "\(R.mode(uid))", st.phaseT, parts.count > 1 ? String(parts[1]) : "", label, seed))
                        }
                    }
                    if bBoarded < 0, stage == 1 { bBoarded = i }
                    if bBoarded >= 0, i - bBoarded > 60 * 4 { break }
                    if bStarted >= 0, i - bStarted > 60 * 25 { break }
                }
                let waited = stage0Start >= 0 && bBoarded >= 0 ? Float(bBoarded - stage0Start) / 60 : -1
                MotionLog.write(String(format: "SEESAW FRIEND %@: B started at step %d, stood at his spot from %d, hopped at %d, waited %.2f s; A's mode then %@; gave up %@", label, bStarted, stage0Start, bBoarded, waited, "\(R.mode(uid))", "\(R.gaveUp)"))
                if bBoarded < 0 { let bs = b.brain.idleState; MotionLog.write("SEESAW FRIEND \(label): B never boarded: kind \(String(describing: bs.kind)) decorGo \(bs.decorGo) bagStage \(bs.bagStage) phase \(bs.phase) activity \(b.brain.activity) at (\(b.brain.position.x - centre.x), \(b.brain.position.y - centre.y)) target \(bs.target - centre) occupants \(field.seatOccupant[uid] ?? [:])") }
                XCTAssertGreaterThanOrEqual(bStarted, 0, "\(label): the ride reached \(mode)")
                XCTAssertGreaterThanOrEqual(bBoarded, 0, "\(label): B got on")
                if bBoarded >= 0 { XCTAssertLessThanOrEqual(waited, 4.0, "\(label): B waited \(waited) s at his spot") }
                XCTAssertTrue(R.gaveUp.isEmpty, "\(label): nobody gave up \(R.gaveUp)")
                for r in lab.rigs { r.brain.abortScript(r.sim, r.skinner) }
                field.clear()
            }
        }
        MotionLog.write(String(format: "SEESAW WAITS max=%.2f mean=%.2f n=%d gaveUp=%d (friend-arrives soak, last scenario)", SeesawRide.shared.waitsMax, SeesawRide.shared.waitsN > 0 ? SeesawRide.shared.waitsSum / Float(SeesawRide.shared.waitsN) : 0, SeesawRide.shared.waitsN, SeesawRide.shared.gaveUp.count))
    }

    /// The six bodies on both seats, walking up from two sides: the hop starts within 1.5 s of arriving at the spot, from a spot where the guard and the centre have room.
    func testEverySpeciesBoardsBothSeats() {
        var worstWait: Float = 0, worstCentre: Float = 0, gaveUp = 0, n = 0, sumWait: Float = 0
        for species in 0..<6 {
            for seat in 0..<2 {
                for (si, side) in [0, 1].enumerated() {
                    let seed: UInt64 = UInt64(3 + 5 * si)
                    let c0 = ParkToys.placed.first { $0.kind == .seesaw }!.at
                    let sx: Float = seat == 0 ? -1 : 1
                    let start = side == 0 ? c0 + SIMD2(sx * 0.92, 2.4) : c0 + SIMD2(-sx * 0.3, 2.2)
                    let (lab, centre) = boardWorld(chars: [species], starts: [start], seed: seed)
                    let R = SeesawRide.shared, field = DecorField.shared
                    let r = lab.rigs[0]
                    r.brain.anticsEnabled = false
                    // the seat he picks is the free one nearest to where he stands: make the other seat taken by nobody, his preferred side by his start
                    XCTAssertTrue(r.brain.decorStart(.decorSit, r.sim, only: .seesaw, uid: uid), "species \(species) found a seat")
                    var stage0Start = -1, hopStep = -1, seatUsed = -1
                    var rootDist: Float = 0, centreDist: Float = 0
                    var prevCen = r.sim.centroid(), prevRoot = r.brain.position
                    for i in 0..<(60 * 20) {
                        lab.tick(watching: false); field.tick(dt: 1.0 / 60)
                        defer { prevCen = r.sim.centroid(); prevRoot = r.brain.position }
                        let st = r.brain.idleState
                        let stage = st.kind == .decorSit && !st.decorGo ? st.bagStage : -1
                        if stage == 0, stage0Start < 0 { stage0Start = i }
                        if stage == 1, hopStep < 0 {
                            hopStep = i; seatUsed = st.seat
                            let sw = field.seatWorld(uid, seat: st.seat) ?? .zero
                            rootDist = simd_distance(prevRoot, SIMD2(sw.x, sw.z))          // (the step BEFORE the hop's first: where he stood)
                            centreDist = simd_distance(SIMD2(prevCen.x, prevCen.z), SIMD2(sw.x, sw.z))
                            break
                        }
                    }
                    let wait = stage0Start >= 0 && hopStep >= 0 ? Float(hopStep - stage0Start) / 60 : -1
                    MotionLog.write(String(format: "SEESAW BOARD species=%d seat=%@ (wanted %@) side=%d wait=%.2f rootDist=%.3f centreDist=%.3f margin=%.3f (to the centre limit %.2f) [%@]", species, seatUsed == 0 ? "L" : "R", seat == 0 ? "L" : "R", side, wait, rootDist, centreDist, SeesawTuning.maxHopCentre - centreDist, SeesawTuning.maxHopCentre, "\(JellyRoster.feature(species))"))
                    XCTAssertGreaterThanOrEqual(hopStep, 0, "species \(species) seat \(seat) side \(side): he got on")
                    if hopStep >= 0 {
                        XCTAssertLessThanOrEqual(wait, 1.5, "species \(species) seat \(seat) side \(side): the hop starts within 1.5 s of arriving at the spot (\(wait) s)")
                        XCTAssertLessThanOrEqual(centreDist, SeesawTuning.maxHopCentre, "species \(species): centre travel")
                        XCTAssertGreaterThanOrEqual(SeesawTuning.maxHopCentre - centreDist, 0.03, "species \(species): within 3 cm of the centre limit")
                        worstWait = max(worstWait, wait); worstCentre = max(worstCentre, centreDist); sumWait += wait; n += 1
                    }
                    gaveUp += R.gaveUp.count
                    _ = centre
                    r.brain.abortScript(r.sim, r.skinner)
                    field.clear()
                }
            }
        }
        MotionLog.write(String(format: "SEESAW WAITS max=%.2f mean=%.2f n=%d gaveUp=%d; farthest centre travel %.3f m (boards of every species, both seats)", worstWait, n > 0 ? sumWait / Float(n) : 0, n, gaveUp, worstCentre))
        XCTAssertEqual(gaveUp, 0, "nobody gave up")
    }

    // MARK: the invitation soak (round 2c, part 2): how often does a ride have two on it?

    struct Share { var minutes: Float = 0, rides = 0, solo = 0, pair = 0, missed = 0, invites = 0, noticed = 0, joined = 0 }

    /// `n` free Jelbies in the park with the seesaw in play for `minutes` sim-minutes, the invitation on or off. A ride (session) = from the first body on the piece to the last one off.
    private func shareSoak(n: Int, minutes: Float, invitations: Bool, seed: UInt64) -> Share {
        SeesawTuning.invitations = invitations
        let pts: [SIMD2<Float>] = [SIMD2(-1.0, 0.4), SIMD2(1.0, -0.4), SIMD2(0.0, 1.6), SIMD2(-2.2, 1.0), SIMD2(2.0, 1.6)]
        let chars = [0, 1, 2, 3, 4]
        RoomLayout.apply(RoomCatalog.park); GameCamera.configurePark(); _ = GameCamera.refreshRoam(aspect: 440.0 / 956.0)
        let lab = SocialTests.Lab(n: n, positions: Array(pts.prefix(n)), quiet: false, seed: seed)
        Self.keep.append(lab)
        for (k, r) in lab.rigs.enumerated() {
            r.sim.arenaCenter = GameCamera.arenaCenter; r.sim.arenaRadius = GameCamera.arenaRadius
            r.brain.anticsEnabled = true; r.brain.outingPlay = true; r.skinner.autoBlink = false; r.renderSamples = false
            r.brain.feature = JellyRoster.feature(chars[k])
            r.skinner.configureTail(MotionRig.renderMesh); r.skinner.tailOn = r.brain.feature == .spines; r.brain.skinnerRef = r.skinner
        }
        WearBody.install(MotionRig.renderMesh)
        let place = ParkToys.placed.filter { $0.kind == .seesaw }
        let field = DecorField.shared, R = SeesawRide.shared
        field.set(place); field.toys.news.removeAll(); R.reset()
        var out = Share()
        var inSession = false, bothSeated = false, sawSecond = false, invitedBefore = 0, emptyFor = 0
        var timeline: [String] = [], lastKey = ""
        let steps = Int(minutes * 3600)
        for i in 0..<steps {
            lab.tick(watching: false); field.tick(dt: 1.0 / 60)
            let occ = field.seatOccupant[uid]?.count ?? 0
            if occ > 0 || inSession {
                let key = "\(R.mode(uid)) s0=\(String(describing: R.stage(uid, seat: 0))) s1=\(String(describing: R.stage(uid, seat: 1))) occ=\(occ) near=\(R.rides[uid]?.riders.map { "\($0.key):\($0.value.near)" } ?? [])"
                if key != lastKey { lastKey = key; timeline.append(String(format: "t=%.1f %@", Float(i) / 60, key)); if timeline.count > 40 { timeline.removeFirst() } }
            }
            if occ > 0 {
                if !inSession { inSession = true; bothSeated = false; sawSecond = false; invitedBefore = R.invitesPostedTotal }
                emptyFor = 0
                if occ >= 2 { sawSecond = true }
                if R.stage(uid, seat: 0) == .seated, R.stage(uid, seat: 1) == .seated { bothSeated = true }
            } else if inSession {
                emptyFor += 1
                if emptyFor > 30 {
                    inSession = false
                    out.rides += 1
                    if bothSeated { out.pair += 1; if R.invitesPostedTotal > invitedBefore { out.joined += 1 } }
                    else { out.solo += 1; if sawSecond { out.missed += 1; MotionLog.write("SEESAW MISSED JOIN (n=\(n), invitations \(invitations)):\n  " + timeline.suffix(14).joined(separator: "\n  ")) } }
                    timeline.removeAll()
                }
            }
            if i % 3600 == 0 { _ = i }
        }
        out.minutes = Float(steps) / 3600
        out.invites = R.invitesPostedTotal; out.noticed = R.noticedTotal
        for r in lab.rigs { r.brain.abortScript(r.sim, r.skinner) }
        field.clear()
        SeesawTuning.invitations = true
        return out
    }

    /// Run on its own: TEST_RUNNER_SEESAW_SOAK=1 (about 12 sim-minutes for 3 and for 5 Jelbies, before and after the invitation); =after3 / =after5: only the run with the invitation for that many.
    func testSeesawShareSoak() throws {
        guard let mode = ProcessInfo.processInfo.environment["SEESAW_SOAK"] else { throw XCTSkip("set TEST_RUNNER_SEESAW_SOAK=1 to run the soak") }
        let only = mode.hasPrefix("after") ? Int(mode.dropFirst(5)) : nil
        for n in [3, 5] where only == nil || only == n {
            var before: Share? = nil
            if only == nil {
                let b = shareSoak(n: n, minutes: 12, invitations: false, seed: 21)
                before = b
                MotionLog.write(String(format: "SEESAW SHARE before n=%d rides=%d solo=%d pair=%d missedJoin=%d invites=%d (sim minutes %.1f, starts per minute %.2f)", n, b.rides, b.solo, b.pair, b.missed, b.invites, b.minutes, Float(b.rides) / b.minutes))
            }
            let after = shareSoak(n: n, minutes: 12, invitations: true, seed: 21)
            MotionLog.write(String(format: "SEESAW SHARE after n=%d rides=%d solo=%d pair=%d missedJoin=%d invites=%d noticed=%d joined=%d (sim minutes %.1f, starts per minute %.2f)", n, after.rides, after.solo, after.pair, after.missed, after.invites, after.noticed, after.joined, after.minutes, Float(after.rides) / after.minutes))
            XCTAssertEqual(after.missed, 0, "n=\(n): no missed join")
            if after.rides >= 5 {
                XCTAssertGreaterThanOrEqual(Float(after.pair) / Float(after.rides), 0.6, "n=\(n): at least 60 % of the rides are pair rides")
                XCTAssertGreaterThanOrEqual(after.solo, 1, "n=\(n): a solo ride still happens")
            }
            if let before { XCTAssertLessThanOrEqual(Float(after.rides), Float(max(before.rides, 1)) * 1.10 + 1, "n=\(n): the invitation does not add ride starts") }
        }
    }

    /// The stock `bounce` idle hop, far from the seesaw: the same block readout as the seesaw's hop start (SEESAW ARMS), to say whether a far arm / foot-bean block is the stock behaviour.
    func testStockBounceBlocks() {
        let (lab, centre) = boardWorld(chars: [0], starts: [SIMD2(0.5, 1.5)], seed: 3)
        _ = centre
        let r = lab.rigs[0]
        r.brain.anticsEnabled = false
        var prevBusy = false, prevStats = "", shown = 0, after = 0
        _ = r.brain.idleStart(.bounce, r.sim)
        for i in 0..<400 {
            lab.tick(watching: false)
            r.render()
            let busy = r.brain.gait.isBusy
            var now = ""
            r.dyn.withUnsafeBufferPointer { now = Self.blockStats($0, root: r.brain.position) }
            if busy && !prevBusy && shown < 2 { shown += 1; after = 3; MotionLog.write("SEESAW STOCK BOUNCE step \(i) hop start: armG \(r.brain.armG) beansActive \(r.skinner.beansActive) gait \(r.brain.gait.phase): \(now)\n    one step before: \(prevStats)") }
            else if after > 0 { after -= 1; MotionLog.write("SEESAW STOCK BOUNCE step \(i) (+\(3 - after)): armG \(r.brain.armG) gait \(r.brain.gait.phase): \(now)") }
            prevBusy = busy; prevStats = now
        }
        XCTAssertGreaterThan(shown, 0, "the stock bounce hopped")
    }

    /// The slower hop must be the gentler one: the same quantity (the step vector's change between steps in the air of a hop) measured with the stock hop (hopSlow 1.0) and with ours.
    func testSlowerHopIsGentler() {
        let ours = SeesawTuning.hopSlow
        defer { SeesawTuning.hopSlow = ours }
        SeesawTuning.hopSlow = 1.0
        let stock = runSequence(chars: [2], seed: 3, callAway: false, label: "stock hop (hopSlow 1.0)")
        SeesawTuning.hopSlow = ours
        let slow = runSequence(chars: [2], seed: 3, callAway: false, label: "ours (hopSlow \(ours))")
        MotionLog.write(String(format: "SEESAW HOP COMPARISON: air step-vector change max stock %.2f cm vs ours %.2f cm; air step max stock %.2f cm vs ours %.2f cm", stock.maxAirDV * 100, slow.maxAirDV * 100, stock.maxAirStep * 100, slow.maxAirStep * 100))
        XCTAssertGreaterThan(stock.maxAirDV, 0, "the stock hop was measured")
        XCTAssertLessThanOrEqual(slow.maxAirDV, stock.maxAirDV, "the slower hop is the gentler one")
        XCTAssertLessThanOrEqual(slow.maxAirStep, stock.maxAirStep, "and not faster")
    }

    func testBobAndPip() { for seed: UInt64 in [3, 8] { check(runSequence(chars: [0, 1], seed: seed, callAway: false, label: "Bob+Pip s\(seed)"), pair: true, callAway: false) } }
    func testTeddyAndLavender() { for seed: UInt64 in [3, 8] { check(runSequence(chars: [4, 3], seed: seed, callAway: false, label: "Teddy+Lavender s\(seed)"), pair: true, callAway: false) } }
    func testAlone() { for seed: UInt64 in [3, 8] { check(runSequence(chars: [2], seed: seed, callAway: false, label: "Moss alone s\(seed)"), pair: false, callAway: false) } }
    func testCallAwayMidRide() {
        check(runSequence(chars: [0, 1], seed: 3, callAway: true, label: "Bob+Pip call-away"), pair: true, callAway: true)
        check(runSequence(chars: [4, 3], seed: 8, callAway: true, label: "Teddy+Lavender call-away"), pair: true, callAway: true)
    }
}
