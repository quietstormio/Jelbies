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
        MotionLog.write(String(format: "SEESAW derived A %.4f rad (brief about 0.245), first touch %.4f rad (about 0.220)", A, touch))
        XCTAssertEqual(A, 0.245, accuracy: 0.01)
        XCTAssertEqual(touch, 0.220, accuracy: 0.01)
        var top: Float = 0
        for i in 0..<720 { top = max(top, SeesawTuning.shape(Float(i) / 720 * 2 * .pi)) }
        XCTAssertEqual(top, 1, accuracy: 1e-4, "the shape peaks at 1")
        // flat top: within 2 % of the peak for at least 0.45 rad either side of it (a plain sine is within 2 % for ~0.2 rad)
        XCTAssertGreaterThan(SeesawTuning.shape(.pi / 2 - 0.45), 0.97)
        // the plank's underside over the bumper centre line = y(theta) = 0.34 - 0.96 tan - 0.015 / cos
        let t: Float = 0.2
        XCTAssertEqual(SeesawTuning.undersideY(atX: 0.96, theta: -t), 0.34 - 0.96 * tanf(t) - 0.015 / cosf(t), accuracy: 1e-5)
        // test 9: the bumper's top follows the underside while pressed (within 2 mm) and is never above it; never pressed before the touch
        var worstGap: Float = 0, pressedSamples = 0
        var th: Float = -0.3
        while th <= 0.3 {
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
        // the seat frame: level it is the contract's cushion top; tilted it stays on the turned plank
        let s0 = SeesawTuning.seatLocal(seat: 1, theta: 0)
        XCTAssertEqual(s0.x, 0.66 * 1.4, accuracy: 1e-5); XCTAssertEqual(s0.y, 0.475 * 1.4, accuracy: 1e-5)
        let s1 = SeesawTuning.seatLocal(seat: 1, theta: 0.2), p = SeesawTuning.toPlank(s1, theta: 0.2)
        XCTAssertEqual(p.x, 0.66, accuracy: 1e-4); XCTAssertEqual(p.y, 0.475, accuracy: 1e-4)
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

    struct Report {
        var tag = ""
        var maxRootSeat: Float = 0, maxCentroidSeat: Float = 0
        var maxSeatedStep: Float = 0, maxHopStep: Float = 0, worstJump: Float = 0
        var maxD: Float = 0, maxDD: Float = 0, maxDDCall: Float = 0
        var minMargin: Float = .infinity, maxMargin: Float = -.infinity
        var leashFrames = 0, leashMax: Float = 0
        var beamDepth: Float = 0, handleMin: Float = .infinity, bodyGapMin: Float = .infinity
        var hops: [(kind: String, dist: Float, thetaAtStart: Float, startVsSeat: Float, landing: Float, forced: Bool)] = []
        var maxAmp: Float = 0, swings: Float = 0
        var finished = false, seatedAll = false
        var endInner: Float = .infinity, endOuter: Float = .infinity          // lowest skin vs the TILTED cushion plane at the swing's ends (|theta| > 0.2), inner / outer side of the patch
        var waitMinZ: Float = .infinity
        var standWhere = "", levelMin: Float = .infinity, levelMax: Float = -.infinity
        var standMinZ: Float = .infinity, standRootZ: Float = 0, riderSkin: Float = .infinity
        var standClear: Float = .infinity, armMax = 0.0, featureBeam: Float = 0, featureHandle: Float = .infinity
    }

    /// One body's distance outside a box (negative = inside by that much), the box given by its centre and half extents (plank frame, model units).
    private static func boxDist(_ p: SIMD3<Float>, _ c: SIMD3<Float>, _ h: SIMD3<Float>) -> Float {
        let q = simd_abs(p - c) - h
        return simd_length(simd_max(q, .zero)) + min(max(q.x, max(q.y, q.z)), 0)
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
        for r in lab.rigs { XCTAssertTrue(r.brain.decorStart(.decorSit, r.sim, only: .seesaw, uid: uid), "\(label): a rider found a seat") }
        let bodyEnd = 6 * (MotionRig.renderMesh.armCapsule?.firstVertex[0] ?? 0)
        let n = lab.rigs.count
        var prevC = lab.rigs.map { $0.sim.centroid() }
        var prevStep = [Float](repeating: 0, count: n)
        var prevKey = [[Int]](repeating: [-1, -1, -1], count: n)
        var hopWho = [String](repeating: "", count: n)
        var prevRoot = lab.rigs.map { $0.brain.position }, diagLines = 0
        var prevStage = [Int](repeating: 0, count: n), hopFrom = [SIMD3<Float>](repeating: .zero, count: n), hopThetaStart = [Float](repeating: 0, count: n)
        var hopStartVsSeat = [Float](repeating: 0, count: n), hopForced = [Bool](repeating: false, count: n), hopSeat = [Int](repeating: 0, count: n)
        var prevTh: Float = 0, prevD: Float = 0, lastCall = -1000
        var everSeated = Set<Int>(), doneAt = -1, called = false, pairRideSteps = 0
        let total = 60 * 110
        for i in 0..<total {
            lab.tick(watching: false); field.tick(dt: 1.0 / 60)
            let th = R.theta(uid), mode = R.mode(uid)
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
            let c0 = cosf(-th), s0 = sinf(-th), k = DecorKind.seesaw.scale
            for (j, r) in lab.rigs.enumerated() { feats[j].tick(id: 0, brain: r.brain, sim: r.sim, feature: JellyRoster.feature(chars[j]), worn: [], hideAll: false, dt: 1.0 / 60) }
            for (j, r) in lab.rigs.enumerated() {
                let b = r.brain, st = b.idleState
                let cen = r.sim.centroid()
                let step = simd_distance(cen, prevC[j])
                let stage = st.kind == .decorSit ? st.bagStage : -1
                // hops: from the first step of stage 1 / 3 to the first step after it
                if (stage == 1 || stage == 3) && prevStage[j] != stage {
                    let seat = st.seat
                    hopFrom[j] = prevC[j]; hopThetaStart[j] = th; hopSeat[j] = seat
                    let sw = field.seatWorld(uid, seat: seat) ?? .zero
                    hopStartVsSeat[j] = simd_distance(prevRoot[j], SIMD2(sw.x, sw.z))          // (the ROOT against the seat point: the body's centroid sits ~15 cm off it)
                    hopForced[j] = R.rides[uid]?.riders[seat]?.forced ?? false
                    hopWho[j] = String(format: "rider %d seat %d occupants %@ root rel (%.2f, %.2f) mode %@ theta %.3f i %d", j, seat, "\(field.seatOccupant[uid] ?? [:])", prevRoot[j].x - centre.x, prevRoot[j].y - centre.y, "\(mode)", th, i)
                    if stage == 1 { hopStartVsSeat[j] = 0 }
                }
                if (prevStage[j] == 1 && stage == 2) || (prevStage[j] == 3 && stage != 3) {
                    let landing: Float
                    if prevStage[j] == 1 { let sw = field.seatWorld(uid, seat: st.seat) ?? .zero; landing = simd_distance(SIMD2(cen.x, cen.z), SIMD2(sw.x, sw.z)) } else { landing = 0 }
                    if prevStage[j] == 3 { afterOff[j] = 20 }
                    if simd_distance(SIMD2(cen.x, cen.z), SIMD2(hopFrom[j].x, hopFrom[j].z)) > 1.1 { MotionLog.write("SEESAW LONG HOP \(label): \(hopWho[j]) from (\(hopFrom[j].x - centre.x), \(hopFrom[j].z - centre.y)) to (\(cen.x - centre.x), \(cen.z - centre.y)) kind \(prevStage[j] == 1 ? "on" : "off")") }
                    rep.hops.append((prevStage[j] == 1 ? "on" : "off", simd_distance(SIMD2(cen.x, cen.z), SIMD2(hopFrom[j].x, hopFrom[j].z)), hopThetaStart[j], hopStartVsSeat[j], landing, hopForced[j]))
                }
                // pops
                let key = [mode.hashValue & 0xff, stage, st.phase]
                if stage == 1 || stage == 3 { rep.maxHopStep = max(rep.maxHopStep, step) }
                else if stage == 2 {
                    rep.maxSeatedStep = max(rep.maxSeatedStep, step)
                    if prevStage[j] == 2, key != prevKey[j] { rep.worstJump = max(rep.worstJump, step - prevStep[j]) }
                }
                if diagLines < 40, (stage == 1 || stage == 3) && step > 0.06 || stage == 2 && step > 0.02 || stage == 2 && prevStage[j] == 2 && key != prevKey[j] && step - prevStep[j] > 0.005 {
                    diagLines += 1
                    MotionLog.write(String(format: "SEESAW DIAG %@ i %d rider %d stage %d phase %d k %.2f mode %@ theta %.4f amp %.3f gait %@ step %.2f cm (prev %.2f) d(xz) %.2f dy %.2f cm", label, i, j, stage, st.phase, st.k, "\(mode)", th, R.amp(uid), "\(b.gait.phase)", step * 100, prevStep[j] * 100, simd_distance(SIMD2(cen.x, cen.z), SIMD2(prevC[j].x, prevC[j].z)) * 100, (cen.y - prevC[j].y) * 100))
                }
                prevKey[j] = key; prevStep[j] = step; prevC[j] = cen; prevStage[j] = stage; prevRoot[j] = b.position
                let standing = (stage == 0 && b.activity != .walking && st.phaseT > 0.3) || afterOff[j] > 0
                if afterOff[j] > 0 { afterOff[j] -= 1 }
                guard stage >= 1 || standing else { continue }
                r.render()
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
                    if stage == 0 { rep.waitMinZ = min(rep.waitMinZ, zmin) }
                    if zmin < rep.standMinZ {
                        rep.standMinZ = zmin; rep.standRootZ = abs(b.position.y - centre.y)
                        var wv = -1
                        r.dyn.withUnsafeBufferPointer { d in
                            var v = 0
                            while v + 2 < bodyEnd { if d[v + 1] > 0.25, d[v + 1] < 0.9, abs(d[v] - centre.x) < 1.5, abs(abs(d[v + 2] - centre.y) - zmin) < 1e-6 { wv = v / 6; break }; v += 6 }
                        }
                        rep.standWhere = String(format: "vertex %d at rel (%.2f, %.2f, %.2f), root rel (%.2f, %.2f), stage %d, activity %@, phaseT %.2f, i %d", wv, wv >= 0 ? r.dyn[6 * wv] - centre.x : 0, wv >= 0 ? r.dyn[6 * wv + 1] : 0, wv >= 0 ? r.dyn[6 * wv + 2] - centre.y : 0, b.position.x - centre.x, b.position.y - centre.y, stage, "\(b.activity)", st.phaseT, i)
                    }
                    // the smallest distance from the skin to the piece (beam, cushions, base, handles; level plank) while he waits on his stand spot / just after the hop off
                    r.dyn.withUnsafeBufferPointer { d in
                        var v = 0
                        while v + 2 < d.count {
                            let p = SIMD3<Float>((d[v] - centre.x) / k, d[v + 1] / k, (d[v + 2] - centre.y) / k)
                            if abs(p.x) < 1.6, p.y < 0.8, abs(p.z) < 1.2 {
                                var m = Self.boxDist(p, SIMD3(0, SeesawTuning.beamCentreY, 0), SeesawTuning.beamHalf)
                                for sx: Float in [-1, 1] {
                                    m = min(m, Self.boxDist(p, SIMD3(sx * SeesawTuning.cushionX, SeesawTuning.cushionCentreY, 0), SeesawTuning.cushionHalf))
                                    m = min(m, Self.boxDist(p, SIMD3(sx * SeesawTuning.handleX, 0.5185, 0), SIMD3(SeesawTuning.handleHalfX, 0.1165, SeesawTuning.handleBarHalfZ)))
                                }
                                m = min(m, Self.boxDist(p, SIMD3(0, 0.22, 0), SIMD3(0.2263, 0.22, 0.272)))
                                rep.standClear = min(rep.standClear, m * k)
                            }
                            v += 6
                        }
                    }
                }
                if stage == 2 { everSeated.insert(j) }
                // seated and settled: the root is on the seat; the lowest skin point against the cushion plane
                if stage == 2, st.phase == 2, st.phaseT > 0.5, st.k > 0.99 {
                    let sw = field.seatWorld(uid, seat: st.seat)!
                    rep.maxRootSeat = max(rep.maxRootSeat, simd_distance(b.position, SIMD2(sw.x, sw.z)))
                    rep.maxCentroidSeat = max(rep.maxCentroidSeat, simd_distance(SIMD2(cen.x, cen.z), SIMD2(sw.x, sw.z)))
                    var lowest = Float.infinity, lowInner = Float.infinity, lowOuter = Float.infinity
                    let slope = tanf(th), innerSign: Float = st.seat == 0 ? 1 : -1          // (toward the fulcrum)
                    r.dyn.withUnsafeBufferPointer { d in
                        var v = 0
                        while v + 2 < bodyEnd {
                            let dx = d[v] - sw.x, dz = d[v + 2] - sw.z
                            // the cushion's flat top: |x - 0.62| <= 0.28, |z| <= 0.14 (model units x 1.4)
                            if abs(dx) < 0.28, abs(dz) < 0.196 {
                                let m = d[v + 1] - (sw.y + slope * dx)
                                lowest = min(lowest, m)
                                if dx * innerSign > 0 { lowInner = min(lowInner, m) } else { lowOuter = min(lowOuter, m) }
                            }
                            v += 6
                        }
                    }
                    if lowest.isFinite { rep.minMargin = min(rep.minMargin, lowest); rep.maxMargin = max(rep.maxMargin, lowest) }
                    if lowest.isFinite, abs(th) < 0.003 { rep.levelMin = min(rep.levelMin, lowest); rep.levelMax = max(rep.levelMax, lowest) }
                    if abs(th) > 0.2 { rep.endInner = min(rep.endInner, lowInner); rep.endOuter = min(rep.endOuter, lowOuter) }
                }
                // nothing of the rider inside the beam or the handle (every skin vertex, the feet and the tail included), every 2nd step
                if i % 2 == 0 {
                    r.dyn.withUnsafeBufferPointer { d in
                        var v = 0
                        while v + 2 < d.count {
                            let wx = d[v] - centre.x, wy = d[v + 1], wz = d[v + 2] - centre.y
                            // the plank frame, model units
                            let x = wx / k, y = wy / k - SeesawTuning.pivotY, z = wz / k
                            let p = SIMD3<Float>(x * c0 - y * s0, SeesawTuning.pivotY + x * s0 + y * c0, z)
                            if abs(p.x) < 1.5, p.y > 0.3, p.y < 0.7, abs(p.z) < 0.5 {
                                let beam = -Self.boxDist(p, SIMD3(0, SeesawTuning.beamCentreY, 0), SeesawTuning.beamHalf) * k
                                rep.beamDepth = max(rep.beamDepth, beam)
                                for sx: Float in [-1, 1] {
                                    // (one box round the whole handle: x 0.169..0.231, y 0.402..0.6347, z +-0.136)
                                    let hy = (SeesawTuning.handleTopY + SeesawTuning.handleBottomY) / 2, hh = (SeesawTuning.handleTopY - SeesawTuning.handleBottomY) / 2
                                    rep.handleMin = min(rep.handleMin, Self.boxDist(p, SIMD3(sx * SeesawTuning.handleX, hy, 0), SIMD3(SeesawTuning.handleHalfX, hh, SeesawTuning.handleBarHalfZ)) * k)
                                }
                            }
                            v += 6
                        }
                    }
                }
            }
            if i % 4 == 0 {
                for (j, r) in lab.rigs.enumerated() where lab.rigs[j].brain.idleState.kind == .decorSit && lab.rigs[j].brain.idleState.bagStage == 2 {
                    let ff = r.dyn.withUnsafeBufferPointer { p in feats[j].frame { _ in p.baseAddress } }
                    for v in ff.vertices {
                        let wx = v.pos.x - centre.x, wy = v.pos.y, wz = v.pos.z - centre.y
                        let x = wx / k, y = wy / k - SeesawTuning.pivotY, z = wz / k
                        let p = SIMD3<Float>(x * c0 - y * s0, SeesawTuning.pivotY + x * s0 + y * c0, z)
                        rep.featureBeam = max(rep.featureBeam, -Self.boxDist(p, SIMD3(0, SeesawTuning.beamCentreY, 0), SeesawTuning.beamHalf) * k)
                        for sx: Float in [-1, 1] {
                            let hy = (SeesawTuning.handleTopY + SeesawTuning.handleBottomY) / 2, hh = (SeesawTuning.handleTopY - SeesawTuning.handleBottomY) / 2
                            rep.featureHandle = min(rep.featureHandle, Self.boxDist(p, SIMD3(sx * SeesawTuning.handleX, hy, 0), SIMD3(SeesawTuning.handleHalfX, hh, SeesawTuning.handleBarHalfZ)) * k)
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
            if callAway, !called, mode == .pairRide, (R.rides[uid]?.modeT ?? 0) > 3 { called = true; lab.rigs[1].brain.idleState.hold = 0; lab.rigs[1].brain.anticsEnabled = false }          // (he does not pick the seesaw again on his own)
            if everSeated.count == n { rep.seatedAll = true }
            if rep.seatedAll, lab.rigs.allSatisfy({ $0.brain.idleState.kind == nil }) { if doneAt < 0 { doneAt = i }; if i - doneAt > 180 { break } }
        }
        rep.finished = doneAt >= 0
        rep.swings = Float(pairRideSteps) / 60 / SeesawTuning.period
        for r in lab.rigs { r.brain.abortScript(r.sim, r.skinner) }
        return rep
    }

    func check(_ rep: Report, pair: Bool, callAway: Bool) {
        let t = rep.tag
        let hopsOn = rep.hops.filter { $0.kind == "on" }, hopsOff = rep.hops.filter { $0.kind == "off" }
        MotionLog.write(String(format: "SEESAW %@: finished %@ seated %@ | root-seat max %.2f cm, centroid-seat max %.2f cm | step seated max %.2f cm, hop max %.2f cm, worst first-step excess %.2f cm | dtheta %.4f ddtheta %.5f (call %.5f) | skin vs cushion %.2f..%.2f cm | leash frames %d (max %.1f cm) | beam depth %.2f cm, handle min %.2f cm, riders %.2f m | swings %.1f amp max %.2f | hops on %d off %d, longest %.2f m | tilted-plane margin at swing ends inner %.2f outer %.2f cm | stand clearance %.2f cm | arm %.4f (max %.4f) | wings/ears beam %.2f cm handle %.2f cm | stand reach: skin z %.1f cm from the piece centre line (root %.1f cm) | rider skin to rider skin min %.1f cm",
                              t, rep.finished ? "Y" : "N", rep.seatedAll ? "Y" : "N", rep.maxRootSeat * 100, rep.maxCentroidSeat * 100, rep.maxSeatedStep * 100, rep.maxHopStep * 100, rep.worstJump * 100,
                              rep.maxD, rep.maxDD, rep.maxDDCall, rep.minMargin * 100, rep.maxMargin * 100, rep.leashFrames, rep.leashMax * 100, rep.beamDepth * 100, rep.handleMin * 100, rep.bodyGapMin,
                              rep.swings, rep.maxAmp, hopsOn.count, hopsOff.count, rep.hops.map { $0.dist }.max() ?? 0, rep.endInner * 100, rep.endOuter * 100, rep.standClear * 100, rep.armMax, ArmCap.maximum, rep.featureBeam * 100, rep.featureHandle * 100, rep.standMinZ * 100, rep.standRootZ * 100, rep.riderSkin * 100))
        MotionLog.write(String(format: "SEESAW %@: level plank (|theta| < 0.003) skin vs cushion %.2f..%.2f cm; deepest stand reach: %@ | waiting on the stand spot (stage 0): skin %.1f cm from the centre line (cushion edge 28 cm)", t, rep.levelMin * 100, rep.levelMax * 100, rep.standWhere, rep.waitMinZ * 100))
        for h in rep.hops { MotionLog.write(String(format: "SEESAW %@:   hop %@ %.2f m, theta at start %.4f, start vs seat %.2f cm, landing error %.2f cm%@", t, h.kind, h.dist, h.thetaAtStart, h.startVsSeat * 100, h.landing * 100, h.forced ? " (called away)" : "")) }
        XCTAssertTrue(rep.seatedAll, "\(t): everybody sat down"); XCTAssertTrue(rep.finished, "\(t): everybody got off")
        // 1
        XCTAssertLessThan(rep.maxRootSeat, 0.01, "\(t): seated, the root is within 1 cm of the seat")
        // 2
        XCTAssertLessThan(rep.maxSeatedStep, 0.02, "\(t): outside a hop the body moves under 2 cm a step")
        XCTAssertLessThan(rep.maxHopStep, 0.06, "\(t): in a hop under 6 cm a step")
        XCTAssertLessThanOrEqual(rep.worstJump, 0.005, "\(t): the first step after a state change is no bigger than the step before by more than 0.5 cm")
        for h in hopsOn { XCTAssertLessThan(h.landing, 0.01, "\(t): lands on the seat within 1 cm") }
        // 3
        XCTAssertLessThan(rep.maxD, 0.019, "\(t): |dtheta| per step")
        XCTAssertLessThan(rep.maxDD, 0.002, "\(t): the change of dtheta")
        XCTAssertLessThan(rep.maxDDCall, 0.004, "\(t): the change of dtheta during the call-away ease")
        // 4
        XCTAssertGreaterThanOrEqual(rep.minMargin, -0.006, "\(t): the lowest skin point is not below the cushion plane by more than 0.6 cm")
        XCTAssertLessThanOrEqual(rep.maxMargin, 0.005, "\(t): the lowest skin point is not above the cushion plane by more than 0.5 cm")
        // 5
        XCTAssertEqual(rep.leashFrames, 0, "\(t): the skin's leash never moved a foot piece (max \(rep.leashMax * 100) cm)")
        // 6
        XCTAssertLessThan(rep.beamDepth, 0.01, "\(t): nothing of the rider is more than 1 cm inside the beam")
        XCTAssertGreaterThanOrEqual(rep.handleMin, -0.005, "\(t): nothing of the rider is inside a handle")
        if pair { XCTAssertGreaterThanOrEqual(rep.riderSkin, 0.20, "\(t): rider skin to rider skin stays at least 20 cm apart") }
        if pair { XCTAssertGreaterThan(rep.bodyGapMin, 1.2, "\(t): the riders' bodies stay apart") }
        XCTAssertGreaterThanOrEqual(rep.standClear, 0.01, "\(t): standing on the stand spot or just landed, the body is at least 1 cm from the cushion, beam, base and handles")
        XCTAssertLessThanOrEqual(rep.armMax, ArmCap.maximum * 1.02, "\(t): the arms stay stubby")
        XCTAssertLessThan(rep.featureBeam, 0.01, "\(t): wings / ears / features not inside the beam")
        XCTAssertGreaterThanOrEqual(rep.featureHandle, -0.005, "\(t): wings / ears / features not inside a handle")
        // 7
        for h in rep.hops {
            XCTAssertLessThanOrEqual(h.dist, SeesawTuning.maxHop, "\(t): a hop \(h.kind) travels \(h.dist) m (limit 0.8)")
            if h.forced { XCTAssertLessThan(h.startVsSeat, 0.01, "\(t): the called-away hop starts within 1 cm of the seat") }
            else if h.kind == "off" { XCTAssertLessThan(abs(h.thetaAtStart), 0.01, "\(t): nobody hops off while the plank moves") }
            if h.kind == "on" { XCTAssertLessThan(abs(h.thetaAtStart), 0.01, "\(t): nobody hops on while the plank moves") }
        }
        XCTAssertEqual(hopsOn.count, pair ? 2 : 1, "\(t): hops on"); XCTAssertEqual(hopsOff.count, pair ? 2 : 1, "\(t): hops off")
        if pair && !callAway { XCTAssertGreaterThanOrEqual(rep.swings, 3, "\(t): at least 3 full swings together") }
        // 8
        if !pair { XCTAssertLessThanOrEqual(rep.maxAmp, 0.3, "\(t): alone the bounce never exceeds amp 0.3") }
    }

    func testBobAndPip() { for seed: UInt64 in [3, 8] { check(runSequence(chars: [0, 1], seed: seed, callAway: false, label: "Bob+Pip s\(seed)"), pair: true, callAway: false) } }
    func testTeddyAndLavender() { for seed: UInt64 in [3, 8] { check(runSequence(chars: [4, 3], seed: seed, callAway: false, label: "Teddy+Lavender s\(seed)"), pair: true, callAway: false) } }
    func testAlone() { for seed: UInt64 in [3, 8] { check(runSequence(chars: [2], seed: seed, callAway: false, label: "Moss alone s\(seed)"), pair: false, callAway: false) } }
    func testCallAwayMidRide() {
        check(runSequence(chars: [0, 1], seed: 3, callAway: true, label: "Bob+Pip call-away"), pair: true, callAway: true)
        check(runSequence(chars: [4, 3], seed: 8, callAway: true, label: "Teddy+Lavender call-away"), pair: true, callAway: true)
    }
}
