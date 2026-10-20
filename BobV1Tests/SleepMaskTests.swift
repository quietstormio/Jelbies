//
//  SleepMaskTests.swift
//  The sleep eye mask (Room/SleepMask.swift): on only while he is settled asleep on his back, poofs away at the start of every way out of sleep,
//  never shown in a race, and the geometry lies on the front of the head (outside the locked body, near the eyes).
//

import XCTest
import simd
@testable import BobV1

@MainActor
final class SleepMaskTests: XCTestCase {
    nonisolated(unsafe) static var keep: [AnyObject] = []
    override func setUp() { RoomLayout.dynamicBoxes = []; GameCamera.configureRoom(count: 3, option: .A, wide: 2); _ = GameCamera.camera(aspect: 440 / 956) }
    override func tearDown() { RoomLayout.dynamicBoxes = []; GameCamera.configureRoom(count: 1); _ = GameCamera.camera(aspect: 440.0 / 956.0) }

    private func sleeper(hold: Float = 500) -> (MotionRig, SleepMaskSet) {
        let r = MotionRig(game: true)
        Self.keep.append(r)
        r.renderSamples = false
        r.skinner.autoBlink = false
        r.sim.teleport(toXZ: SIMD2(0, 0.2))
        for _ in 0..<120 { r.sim.step() }
        r.brain.currentPose(r.sim)
        r.brain.seed = 11
        r.brain.idleForced = true
        XCTAssertTrue(r.brain.idleStart(.sleep, r.sim))
        r.brain.sleep.hold = hold
        let set = SleepMaskSet(); set.soundOn = false
        return (r, set)
    }
    /// One fixed step of the rig and of the mask set.
    private func step(_ r: MotionRig, _ set: SleepMaskSet, touched: Bool = false, race: Bool = false) {
        r.tick(touched: touched)
        set.tick(id: 0, brain: r.brain, sim: r.sim, raceBusy: race, dt: r.sim.stepDt)
        set.stepPuffs(dt: r.sim.stepDt)
    }
    private func runUntil(_ r: MotionRig, _ set: SleepMaskSet, _ seconds: Float, touched: Bool = false, _ until: () -> Bool) {
        for _ in 0..<Int(seconds * 60) { step(r, set, touched: touched); if until() { break } }
    }
    /// Naps with the mask fully on.
    private func napWithMask(_ r: MotionRig, _ set: SleepMaskSet) {
        runUntil(r, set, 20) { r.brain.isNapping }
        XCTAssertTrue(r.brain.isNapping)
        runUntil(r, set, 2) { false }
        XCTAssertEqual(set.phase(0), .shown)
        XCTAssertEqual(set.scale(0), 1, accuracy: 0.001)
    }
    /// The mask is gone (or going) by the end of the poof, and a puff was spawned for it.
    private func assertPoofsAway(_ r: MotionRig, _ set: SleepMaskSet, _ what: String, file: StaticString = #filePath, line: UInt = #line) {
        var n = 0
        while set.phase(0) != .poofOut && n < 120 { step(r, set); n += 1 }
        XCTAssertEqual(set.phase(0), .poofOut, "\(what): poofing", file: file, line: line)
        if r.brain.idleState.kind == .sleep && r.brain.sleep.stage == 4 {
            XCTAssertGreaterThan(r.brain.sleep.t, SleepTuning.rollBackTime * 0.45, "\(what): the mask stays until the roll back is about half done", file: file, line: line)
            XCTAssertLessThan(r.brain.sleep.t, SleepTuning.rollBackTime * 0.7, "\(what): ... and then poofs", file: file, line: line)
        }
        let spawns = set.puffSpawns
        XCTAssertEqual(spawns, 2, "\(what): one puff in, one puff away", file: file, line: line)
        for _ in 0..<Int((SleepMaskTuning.poofTime + 0.05) * 60) { step(r, set) }
        XCTAssertFalse(set.isShown(0), "\(what): gone", file: file, line: line)
        XCTAssertEqual(set.phase(0), .hidden, file: file, line: line)
    }

    func testMaskIsShownOnlyWhileAsleepOnHisBack() {
        var shownFrames = 0, napFrames = 0, shownWhenNotNapping = 0, popped = false
        let (r2, set2) = sleeper(hold: 6)
        for _ in 0..<(60 * 40) {
            step(r2, set2)
            if r2.brain.isNapping { napFrames += 1 }
            if set2.isShown(0) { shownFrames += 1; if !r2.brain.isNapping && set2.phase(0) != .poofOut && !SleepMaskSet.lingers(r2.brain) { shownWhenNotNapping += 1 } }
            if set2.phase(0) == .popIn, set2.scale(0) > 0.01 { popped = true }
            if r2.brain.sleep.stage < 3 || r2.brain.idleState.kind == nil { XCTAssertNotEqual(set2.phase(0), .shown, "not shown while standing / lying down") }
            XCTAssertGreaterThanOrEqual(set2.scale(0), 0)
            XCTAssertLessThanOrEqual(set2.scale(0), 1.12, "pop overshoot stays small")
            if r2.brain.idleState.kind == nil && r2.t > 4 && set2.phase(0) == .hidden { break }
        }
        XCTAssertGreaterThan(napFrames, 60)
        XCTAssertGreaterThan(shownFrames, 60)
        XCTAssertEqual(shownWhenNotNapping, 0, "off the moment he stops napping (the poof shrinks it, never a full mask)")
        XCTAssertTrue(popped)
        XCTAssertEqual(set2.popIns, 1)
        XCTAssertEqual(set2.poofOuts, 1)
        XCTAssertFalse(set2.isShown(0), "never on an awake Jelly")
        XCTAssertNil(r2.brain.idleState.kind)
        XCTAssertEqual(set2.puffSpawns, 2)
    }

    func testPoofsInOnlyOnceFullyOnHisBackWithEyesShut() {
        let (r, set) = sleeper()
        var firstShow: Int?
        var f = 0
        while f < 60 * 25 {
            step(r, set); f += 1
            if set.popIns > 0 && firstShow == nil {
                firstShow = f
                XCTAssertEqual(r.brain.sleep.stage, 3, "starts the moment he has settled on his back")
                XCTAssertLessThan(r.skinner.openness.left, 0.15, "eyes already shut")
            }
            if firstShow != nil { break }
        }
        XCTAssertNotNil(firstShow)
        XCTAssertEqual(set.puffSpawns, 1)
        runUntil(r, set, 0.1) { false }
        XCTAssertGreaterThan(set.scale(0), 0.2)
        runUntil(r, set, 0.3) { false }
        XCTAssertEqual(set.scale(0), 1, accuracy: 0.001, "full size after ~0.25 s")
    }

    func testPoofsAwayWhenTappedAwake() {
        let (r, set) = sleeper()
        napWithMask(r, set)
        for _ in 0..<8 { step(r, set, touched: true) }
        XCTAssertEqual(r.brain.sleep.stage, 4)
        assertPoofsAway(r, set, "tap")
    }

    func testPoofsAwayOnARequest() {
        let (r, set) = sleeper()
        napWithMask(r, set)
        r.brain.request(.goTo(SIMD2(1.0, 1.2)))
        for _ in 0..<3 { step(r, set) }
        assertPoofsAway(r, set, "request")
    }

    func testPoofsAwayOnTheRaceWake() {
        let (r, set) = sleeper()
        napWithMask(r, set)
        r.brain.sleepWake(groggy: false, fast: true)        // the Circuit wakes the sleepers
        step(r, set)
        assertPoofsAway(r, set, "race wake")
    }

    func testPoofsAwayInTheMorning() {
        let (r, set) = sleeper(hold: 3600)
        r.brain.idleNight = 1; r.brain.idleDeepNight = 1
        napWithMask(r, set)
        r.brain.idleNight = 0; r.brain.idleDeepNight = 0              // morning
        runUntil(r, set, 40) { set.phase(0) == .poofOut }
        XCTAssertEqual(r.brain.sleep.stage, 4)
        assertPoofsAway(r, set, "morning")
    }

    func testPoofsAwayWhenTimeIsUp() {
        let (r, set) = sleeper(hold: 4)
        runUntil(r, set, 20) { r.brain.isNapping }
        runUntil(r, set, 10) { set.phase(0) == .poofOut }
        XCTAssertEqual(set.phase(0), .poofOut)
        assertPoofsAway(r, set, "hold over")
    }

    func testPoofsAwayWhenPickedUpOrAborted() {
        let (r, set) = sleeper()
        napWithMask(r, set)
        for _ in 0..<90 { step(r, set, touched: true) }                // a real pick up
        XCTAssertEqual(r.brain.activity, .touched)
        XCTAssertFalse(set.isShown(0), "gone while held")
        XCTAssertEqual(set.puffSpawns, 2)
        runUntil(r, set, 12) { false }
        XCTAssertFalse(set.isShown(0), "and not back on while he rights himself")

        let (r2, set2) = sleeper()
        napWithMask(r2, set2)
        r2.brain.abortAll(r2.sim, r2.skinner)                          // recover / abortAll path
        step(r2, set2)
        assertPoofsAway(r2, set2, "abortAll")
        runUntil(r2, set2, 10) { false }
        XCTAssertFalse(set2.isShown(0))
    }

    func testNeverShownInARace() {
        // asleep with the Circuit on: it never goes on
        let (r, set) = sleeper()
        r.brain.race.active = true
        for _ in 0..<(60 * 20) { step(r, set, race: true); XCTAssertFalse(set.isShown(0)); XCTAssertEqual(set.phase(0), .hidden) }
        XCTAssertEqual(set.popIns, 0)
        XCTAssertEqual(set.puffSpawns, 0)
        // the brain's own race flag alone is enough too
        let (r2, set2) = sleeper()
        r2.brain.race.active = true
        for _ in 0..<(60 * 15) { step(r2, set2); XCTAssertFalse(set2.isShown(0)) }
        XCTAssertEqual(set2.popIns, 0)
        // a mask that is on when the Circuit is called goes off
        let (r3, set3) = sleeper()
        napWithMask(r3, set3)
        step(r3, set3, race: true)
        XCTAssertEqual(set3.phase(0), .poofOut)
        // nothing is handed to the renderer for the track
        let f = set3.frame(theme: RoomTheme(), hidden: true)
        XCTAssertTrue(f.opaque.vertices.isEmpty && f.translucent.vertices.isEmpty)
    }

    func testMaskMeshSitsOnTheFrontOfTheHeadOutsideTheBody() {
        for id in 0..<3 {
            let rest = EyeMaskModel.rests[id]
            XCTAssertGreaterThan(rest.pos.count, 400)
            XCTAssertEqual(rest.idx.count % 3, 0)
            var padNear = 0
            for p in rest.pos {
                let d = BobForm.bodySDF(SIMD3(Double(p.x), Double(p.y), Double(p.z)))
                XCTAssertGreaterThan(d, -0.04, "mask vertex inside the body: \(p)")
                XCTAssertLessThan(d, 0.1, "mask is a thin shell: \(p)")
                if p.z > 0.2 { padNear += 1; XCTAssertEqual(p.y, 0.82, accuracy: 0.25); XCTAssertLessThan(abs(p.x), 0.62) }
            }
            XCTAssertGreaterThan(padNear, 300)
            XCTAssertEqual(rest.pivot.x, 0, accuracy: 0.001)
            XCTAssertEqual(rest.pivot.y, 0.83, accuracy: 0.05)
        }
        // colours differ per Jelly
        let c = (0..<3).map { EyeMaskModel.palette($0).band }
        XCTAssertNotEqual(c[0], c[1]); XCTAssertNotEqual(c[1], c[2]); XCTAssertNotEqual(c[0], c[2])
    }

    func testMaskFollowsTheFaceWhileHeLiesOnHisBack() {
        let (r, set) = sleeper()
        napWithMask(r, set)
        let f = set.frame(theme: RoomTheme())
        XCTAssertGreaterThan(f.opaque.vertices.count, 400)
        // on his back the face looks at the ceiling: the mask's front sits above the body centre, and near the face
        let c = r.sim.centroid()
        let pose = r.sim.bodyPose(iterations: 4)
        let faceDir = pose.rotation.act(SIMD3<Float>(0, 0, 1))
        XCTAssertGreaterThan(faceDir.y, 0.8)
        let pivotW = set.slots[0].carry.world(EyeMaskModel.rests[0].pivot)
        XCTAssertGreaterThan(pivotW.y, c.y + 0.3, "over the face")
        var lo = SIMD3<Float>(repeating: 1e9), hi = SIMD3<Float>(repeating: -1e9)
        for v in f.opaque.vertices { let p = SIMD3(v.pos.x, v.pos.y, v.pos.z); lo = simd_min(lo, p); hi = simd_max(hi, p) }
        XCTAssertLessThan(hi.y, c.y + 1.2)
        XCTAssertGreaterThan(lo.y, r.sim.floorY - 0.2)
    }

    // MARK: the z's

    func testZsOnlyWhileFullyAsleepPacedAndCapped() {
        let (r, set) = sleeper(hold: 500)
        var zWhileNotShown = 0, maxAlive = 0
        var spawnTimes: [Float] = []
        var lastSpawns = 0
        for _ in 0..<(60 * 14) {
            step(r, set)
            if set.liveZ(0) > 0 && set.phase(0) != .shown { zWhileNotShown += 1 }
            maxAlive = max(maxAlive, set.liveZ(0))
            if set.zSpawns != lastSpawns { spawnTimes.append(r.t); lastSpawns = set.zSpawns }
            if !r.brain.isNapping { XCTAssertEqual(set.liveZ(0), 0, "no z's while he is not asleep: stage \(r.brain.sleep.stage)") }
        }
        XCTAssertEqual(zWhileNotShown, 0, "none before the mask is on")
        XCTAssertGreaterThanOrEqual(spawnTimes.count, 3)
        XCTAssertLessThanOrEqual(maxAlive, SleepMaskTuning.zMax)
        for (a, b) in zip(spawnTimes, spawnTimes.dropFirst()) {
            XCTAssertGreaterThanOrEqual(b - a, 1.45, "about one every 1.5 to 2.5 s")
            XCTAssertLessThanOrEqual(b - a, 2.6)
        }
        // a snore rides a z of its own
        let before = set.zSpawns
        set.snore(0)
        XCTAssertLessThanOrEqual(set.zSpawns, before + 1)
    }

    func testZsStopAndFadeFastWhenWakingStarts() {
        let (r, set) = sleeper()
        napWithMask(r, set)
        runUntil(r, set, 8) { set.liveZ(0) >= 2 }
        XCTAssertGreaterThanOrEqual(set.liveZ(0), 1)
        let spawns = set.zSpawns
        r.brain.sleepWake(groggy: true)
        for _ in 0..<5 { step(r, set) }
        for _ in 0..<Int(1.0 * 60) { step(r, set) }                  // < 3.4 s / 4 + margin
        XCTAssertEqual(set.liveZ(0), 0, "faded fast")
        XCTAssertEqual(set.zSpawns, spawns, "no new z once waking started")
    }

    func testNoZsWhenAwakeOrInARace() {
        let r = MotionRig(game: true); Self.keep.append(r)
        let set = SleepMaskSet(); set.soundOn = false
        for _ in 0..<(60 * 8) { step(r, set); XCTAssertEqual(set.liveZ(0), 0) }
        XCTAssertEqual(set.zSpawns, 0, "awake: none")
        set.snore(0)
        XCTAssertEqual(set.zSpawns, 0, "a stray snore callback does nothing when he is awake")
        let (r2, set2) = sleeper()
        r2.brain.race.active = true
        for _ in 0..<(60 * 15) { step(r2, set2, race: true); XCTAssertEqual(set2.liveZ(0), 0) }
        XCTAssertEqual(set2.zSpawns, 0)
        // asleep with z's, then the Circuit: they go at once and nothing is drawn
        let (r3, set3) = sleeper()
        napWithMask(r3, set3)
        runUntil(r3, set3, 8) { set3.liveZ(0) > 0 }
        XCTAssertGreaterThan(set3.liveZ(0), 0)
        step(r3, set3, race: true)
        XCTAssertEqual(set3.liveZ(0), 0)
        let f = set3.frame(theme: RoomTheme(), hidden: true)
        XCTAssertTrue(f.translucent.vertices.isEmpty)
    }

    func testZLetterMeshIsSoftAndSmall() {
        let m = ZLetterModel.mesh
        XCTAssertGreaterThan(m.vertices.count, 100)
        XCTAssertLessThan(m.vertices.count, 1500, "one cheap mesh, instanced by transform")
        var lo = SIMD3<Float>(repeating: 1e9), hi = SIMD3<Float>(repeating: -1e9)
        for v in m.vertices { let p = SIMD3(v.pos.x, v.pos.y, v.pos.z); lo = simd_min(lo, p); hi = simd_max(hi, p) }
        XCTAssertEqual(hi.y - lo.y, 1.0, accuracy: 0.02, "unit height")
        XCTAssertEqual(hi.x - lo.x, 0.6, accuracy: 0.02)
        XCTAssertGreaterThan(hi.z - lo.z, 0.15, "extruded, not a flat sprite")
    }

    func testMaskStaysOnUntilHalfTheRollBackThenPoofs() {
        let (r, set) = sleeper()
        napWithMask(r, set)
        r.brain.sleepWake(groggy: false)
        var poofAt: Float?
        for _ in 0..<120 {
            step(r, set)
            if poofAt == nil && set.phase(0) == .poofOut { poofAt = r.brain.sleep.t }
            if r.brain.sleep.stage == 4 && r.brain.sleep.t < SleepTuning.rollBackTime * 0.4 { XCTAssertEqual(set.phase(0), .shown, "still on early in the roll") }
        }
        XCTAssertNotNil(poofAt)
        XCTAssertEqual(poofAt ?? 0, SleepTuning.rollBackTime * 0.5, accuracy: 0.1)
        XCTAssertFalse(set.isShown(0))
        XCTAssertEqual(set.liveZ(0), 0)
    }
}
