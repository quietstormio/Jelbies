//
//  PetTwoTests.swift
//  Two-finger petting (pet-two-r1). Part 1: the ONE-finger baseline, recorded on the base commit (before any production edit): a 3 s stroke on one Jelmiko through a real
//  HapticDriver + RecordingHapticSink must give the same hearts, love, purr and haptic events after the change. The numbers are pinned below.
//

import XCTest
import simd
@testable import BobV1

@MainActor
final class PetTwoTests: XCTestCase {
    nonisolated(unsafe) static var savedHour: Double?
    override func setUp() { Self.savedHour = DayClock.shared.forcedHour; DayClock.shared.forcedHour = 14 }
    override func tearDown() { DayClock.shared.forcedHour = Self.savedHour }

    static let eye = SIMD3<Float>(0, 0.9, 6)

    /// One Jelmiko on its own rig with its own recording haptic driver.
    @MainActor final class Body {
        let rig: MotionRig
        let rec = RecordingHapticSink()
        let driver: HapticDriver
        let play: TouchPlay
        let surface = RestSurface(mesh: MotionRig.renderMesh)
        var born = Set<Double>()
        var now = 100.0
        init() {
            rig = MotionRig(game: true, settle: 2)
            driver = HapticDriver(sinks: [rec])
            play = TouchPlay(haptics: driver)
            driver.enabled = true
            driver.setWarm(true)
            rec.clock = { [unowned self] in self.now }
            rec.clear()
            driver.setWarm(false); driver.setWarm(true)
        }
        func ray(localX: Float, localY: Float) -> (o: SIMD3<Float>, d: SIMD3<Float>) {
            let e = BodyEllipsoid(sim: rig.sim)
            let p = e.center + e.rot.act(SIMD3(localX, localY, 0))
            return (PetTwoTests.eye, simd_normalize(p - PetTwoTests.eye))
        }
        func frame(clock: Double, ray r: (o: SIMD3<Float>, d: SIMD3<Float>)?) {
            now = clock
            play.petFrame(dt: 1.0 / 60, now: clock, ray: r, screen: r == nil ? nil : SIMD2(0.5, 0.5), sim: rig.sim, brain: rig.brain, skinner: rig.skinner, surface: surface)
            for h in play.hearts { born.insert(h.born) }
            rig.tick()
        }
    }

    struct Numbers: Equatable, CustomStringConvertible {
        var hearts = 0, petEvents = 0, transients = 0, loveAt3s: Float = 0, purrAt3s: Float = 0, maxPetIntensity: Float = 0, firstHeartT: Double = -1, firstPurrT: Double = -1
        var description: String { "hearts \(hearts) petEvents \(petEvents) transients \(transients) love \(loveAt3s) purr \(purrAt3s) maxPet \(maxPetIntensity) firstHeart \(firstHeartT) firstPurr \(firstPurrT)" }
    }

    /// A 3 s stroke on one body (x sweep on the plain-stroke area), then 0.5 s hands-off.
    static func singleStroke(seconds: Float = 3, companionHook: Bool = false) -> Numbers {
        let b = Body()
        let lanes = PetLanes()
        if companionHook { b.driver.companion = { lanes.companionLevels() } }
        var clock = 100.0
        var n = Numbers()
        var t: Float = 0
        while t < seconds {
            b.frame(clock: clock, ray: b.ray(localX: 0.38 + 0.12 * sinf(2 * .pi * 1.2 * t), localY: 0.15))
            if n.firstPurrT < 0, b.play.isPurring { n.firstPurrT = clock - 100 }
            if n.firstHeartT < 0, !b.born.isEmpty { n.firstHeartT = clock - 100 }
            clock += 1.0 / 60; t += 1.0 / 60
        }
        n.loveAt3s = b.play.love; n.purrAt3s = b.play.purrLevel
        for _ in 0..<30 { b.frame(clock: clock, ray: nil); clock += 1.0 / 60 }
        n.hearts = b.born.count
        let pet = b.rec.events(.continuous, channel: "pet")
        n.petEvents = pet.count; n.maxPetIntensity = pet.map { $0.intensity }.max() ?? 0
        n.transients = b.rec.events(.transient).count
        return n
    }

    func testSingleStrokeBaseline() {
        let n = Self.singleStroke()
        print("PETTWO baseline: \(n)")
        // recorded on the base commit 24c0eb8f, before any production edit (identical on pet-two-r1)
        XCTAssertEqual(n.hearts, 4)
        XCTAssertEqual(n.petEvents, 143)
        XCTAssertEqual(n.transients, 7)
        XCTAssertEqual(n.loveAt3s, 1.0)
        XCTAssertEqual(n.purrAt3s, 1.0)
        XCTAssertEqual(n.maxPetIntensity, 0.5870892, accuracy: 1e-6)
        XCTAssertEqual(n.firstHeartT, 0.6, accuracy: 1e-6)
        XCTAssertEqual(n.firstPurrT, 2.05, accuracy: 1e-6)
    }

    // MARK: routing table (pure)

    func testRouteTable() {
        typealias R = PetRoute
        // nothing down: the finger is the primary, as always; a body a lane is petting is not taken over
        XCTAssertEqual(R.route(primary: .none, picked: 1, touchID: 0, liveLanes: [], getUpOff: true), .primary)
        XCTAssertEqual(R.route(primary: .none, picked: 1, touchID: 0, liveLanes: [], getUpOff: false), .ignore)
        XCTAssertEqual(R.route(primary: .none, picked: 1, touchID: 0, liveLanes: [1]), .ignore)
        XCTAssertEqual(R.route(primary: .none, picked: nil, touchID: 0, liveLanes: []), .ignore, "empty floor")
        // a stroke (or a press that has not decided) + a finger on ANOTHER Jelmiko = a lane
        XCTAssertEqual(R.route(primary: .pet, picked: 1, touchID: 0, liveLanes: []), .lane)
        XCTAssertEqual(R.route(primary: .pending, picked: 2, touchID: 0, liveLanes: [1]), .lane)
        // the same Jelmiko: a pending press keeps the cheeks pinch, a stroke ignores it (one stroke per body)
        XCTAssertEqual(R.route(primary: .pending, picked: 0, touchID: 0, liveLanes: []), .cheeksCandidate)
        XCTAssertEqual(R.route(primary: .pet, picked: 0, touchID: 0, liveLanes: []), .ignore)
        XCTAssertEqual(R.route(primary: .pet, picked: 1, touchID: 0, liveLanes: [1]), .ignore, "a lane already pets him")
        // three fingers at most: the primary + two lanes
        XCTAssertEqual(R.route(primary: .pet, picked: 2, touchID: 0, liveLanes: [1, 3]), .ignore, "a third lane is ignored")
        // a hold / drag / throw flight / cheeks pinch is never disturbed by another finger
        XCTAssertEqual(R.route(primary: .grab, picked: 1, touchID: 0, liveLanes: []), .ignore)
        XCTAssertEqual(R.route(primary: .cheeks, picked: 1, touchID: 0, liveLanes: []), .ignore)
    }

    // MARK: haptic mix

    func testMixIsIdentityWithoutASecondLevelAndFullerWithOne() {
        for a: Float in [0, 0.12, 0.3, 0.77, 1] { XCTAssertEqual(HapticDriver.mix(a, 0), a, "bit-identical with no lane") }
        XCTAssertEqual(HapticDriver.mix(0, 0.4), 0.4)
        XCTAssertEqual(HapticDriver.mix(0.4, 0.4), 0.5, accuracy: 1e-6)
        XCTAssertGreaterThan(HapticDriver.mix(0.3, 0.2), 0.3)
        XCTAssertLessThanOrEqual(HapticDriver.mix(1, 1), 1)
        XCTAssertEqual(HapticDriver.mix(0.9, 0.9), 1)
    }

    /// With the companion hook installed but no lane, the one-finger stroke is the very same numbers (the baseline).
    func testNoLaneCompanionHookChangesNothing() {
        XCTAssertEqual(Self.singleStroke(), Self.singleStroke(companionHook: true))
    }

    // MARK: two bodies, two fingers

    /// A: the primary (as the stage runs it: petFrame on his own TouchPlay); B and C: lanes. One shared motor (A's driver).
    @MainActor final class Pair {
        let a = Body(), b = Body(), c = Body()
        let lanes = PetLanes()
        let fb = ObjectIdentifier(NSObject()), fc = ObjectIdentifier(NSObject())
        var clock = 100.0
        var credited: [Int: Float] = [:]
        var hubHearts: [Int: Int] = [:]
        var laneRay: [Int: (o: SIMD3<Float>, d: SIMD3<Float>)] = [:]
        init() { a.driver.companion = { [unowned self] in self.lanes.companionLevels() } }
        func body(_ k: Int) -> Body { [a, b, c][k] }
        func laneFrame() {
            lanes.tick(dt: 1.0 / 60, now: clock, surface: a.surface, body: { [unowned self] l in
                let bd = self.body(l.jelly)
                var ray: (o: SIMD3<Float>, d: SIMD3<Float>)?
                if l.finger != nil { ray = self.laneRay[l.jelly] }
                return PetLanes.Body(sim: bd.rig.sim, brain: bd.rig.brain, skinner: bd.rig.skinner, mood: .happy, attentionWanted: false, ray: ray, screen: ray == nil ? nil : SIMD2(0.5, 0.5))
            }, credit: { [unowned self] id, amt in self.credited[id, default: 0] += amt }, heart: { [unowned self] id, _ in self.hubHearts[id, default: 0] += 1 })
        }
        /// One frame: lanes first (as the stage does), then the primary on A, then every body's sim.
        func frame(primaryRay: (o: SIMD3<Float>, d: SIMD3<Float>)?) {
            a.now = clock
            laneFrame()
            a.play.petFrame(dt: 1.0 / 60, now: clock, ray: primaryRay, screen: primaryRay == nil ? nil : SIMD2(0.5, 0.5), sim: a.rig.sim, brain: a.rig.brain, skinner: a.rig.skinner, surface: a.surface)
            for h in a.play.hearts { a.born.insert(h.born) }
            a.rig.tick(); b.rig.tick(); c.rig.tick()
            clock += 1.0 / 60
        }
        func sweep(_ k: Int, _ t: Float) -> (o: SIMD3<Float>, d: SIMD3<Float>) { body(k).ray(localX: 0.38 + 0.12 * sinf(2 * .pi * 1.2 * t + Float(k)), localY: 0.15) }
    }

    static let sz = CGSize(width: 100, height: 100)

    func testTwoFingersOnTwoJelmikoBothGetHeartsLoveAndTheirOwnPurr() {
        let single = Self.singleStroke()
        let p = Pair()
        p.lanes.begin(jelly: 1, finger: p.fb, point: .zero, size: Self.sz, target: p.a.driver)
        var t: Float = 0
        var firstHeartA = -1.0, firstHeartB = -1.0, purrB = -1.0
        while t < 3 {
            p.laneRay[1] = p.sweep(1, t)
            p.frame(primaryRay: p.sweep(0, t))
            if firstHeartA < 0, !p.a.born.isEmpty { firstHeartA = Double(t) }
            if firstHeartB < 0, (p.hubHearts[1] ?? 0) > 0 { firstHeartB = Double(t) }
            if purrB < 0, p.lanes.lanes[1]?.play.isPurring == true { purrB = Double(t) }
            t += 1.0 / 60
        }
        let lane = p.lanes.lanes[1]!.play
        print("PETTWO two: A love \(p.a.play.love) hearts \(p.a.born.count); B love \(lane.love) hearts(hub) \(p.hubHearts[1] ?? 0) firstHeartA \(firstHeartA) B \(firstHeartB) purrB \(purrB); credited \(p.credited); single \(single)")
        XCTAssertGreaterThan(p.a.play.love, 0.85, "A is petted")
        XCTAssertGreaterThan(lane.love, 0.85, "B is petted at the same time, on his own lane")
        XCTAssertGreaterThan(p.a.born.count, 0); XCTAssertGreaterThan(p.hubHearts[1] ?? 0, 0, "B gets his own hearts")
        XCTAssertGreaterThan(purrB, 0, "B purrs")
        XCTAssertLessThan(abs(firstHeartB - single.firstHeartT), 0.35, "B's first heart comes within the single-stroke timing")
        XCTAssertLessThan(abs(firstHeartA - single.firstHeartT), 0.35)
        XCTAssertGreaterThan(p.credited[1] ?? 0, 0, "B's love (attention) is credited to B")
        XCTAssertNil(p.credited[0], "nothing is credited to A by the lane")
        XCTAssertTrue(p.b.rig.sim.pressing, "B is dented under his finger")
        XCTAssertTrue(p.a.rig.sim.pressing)
        XCTAssertEqual(p.b.rec.events.filter { $0.kind != .start && $0.kind != .stop }.count, 0, "B's own driver has no motor: only A's driver plays")
    }

    func testOneMotorPlaysOneFullerPattern() {
        let one = Pair()                      // A alone
        var t: Float = 0
        while t < 3 { one.frame(primaryRay: one.sweep(0, t)); t += 1.0 / 60 }
        let two = Pair()
        two.lanes.begin(jelly: 1, finger: two.fb, point: .zero, size: Self.sz, target: two.a.driver)
        t = 0
        while t < 3 { two.laneRay[1] = two.sweep(1, t); two.frame(primaryRay: two.sweep(0, t)); t += 1.0 / 60 }
        let p1 = one.a.rec.events(.continuous, channel: "pet"), p2 = two.a.rec.events(.continuous, channel: "pet")
        let m1 = p1.map(\.intensity).max() ?? 0, m2 = p2.map(\.intensity).max() ?? 0
        print("PETTWO motor: one-finger max pet \(m1), two-finger max pet \(m2), events \(p1.count) vs \(p2.count)")
        XCTAssertGreaterThanOrEqual(m2, m1)
        XCTAssertLessThanOrEqual(m2, 1)
        for k in 1..<p2.count { XCTAssertGreaterThanOrEqual(p2[k].t - p2[k - 1].t, 1.0 / 60 - 0.001, "still at most 60 Hz on the one channel") }
        for k in 1..<p2.count { XCTAssertNotEqual(p2[k].intensity, p2[k - 1].intensity, "only on change") }
        XCTAssertEqual(two.a.rec.events(.start).count, one.a.rec.events(.start).count, "no second engine start / cut-off")
        XCTAssertEqual(two.a.rec.events(.stop).count, one.a.rec.events(.stop).count)
    }

    func testLaneFingerLiftEndsOnlyItsStroke() {
        let p = Pair()
        p.lanes.begin(jelly: 1, finger: p.fb, point: .zero, size: Self.sz, target: p.a.driver)
        var t: Float = 0
        while t < 2 { p.laneRay[1] = p.sweep(1, t); p.frame(primaryRay: p.sweep(0, t)); t += 1.0 / 60 }
        XCTAssertTrue(p.lanes.end(finger: p.fb))                    // B's finger lifts (or the system cancels it)
        XCTAssertFalse(p.lanes.end(finger: p.fb), "once")
        let loveA = p.a.play.love
        for _ in 0..<12 { p.frame(primaryRay: p.sweep(0, t)); t += 1.0 / 60 }
        XCTAssertGreaterThan(p.a.play.love, 0.85, "A is still being petted")
        XCTAssertGreaterThanOrEqual(p.a.play.love, loveA - 0.05)
        XCTAssertTrue(p.a.rig.sim.pressing)
        for _ in 0..<240 { p.frame(primaryRay: p.sweep(0, t)); t += 1.0 / 60 }
        XCTAssertTrue(p.lanes.isEmpty, "B's lane has settled and is gone")
        XCTAssertFalse(p.b.rig.sim.pressing, "B's dent is out")
        XCTAssertNil(p.lanes.companionLevels())
        XCTAssertEqual(p.b.rig.brain.touchRoll, 0); XCTAssertEqual(p.b.rig.brain.touchPitch, 0); XCTAssertEqual(p.b.rig.brain.touchSquash, 1)
    }

    func testCancelAllCleansUpEverything() {
        let p = Pair()
        p.lanes.begin(jelly: 1, finger: p.fb, point: .zero, size: Self.sz, target: p.a.driver)
        p.lanes.begin(jelly: 2, finger: p.fc, point: .zero, size: Self.sz, target: p.a.driver)
        var t: Float = 0
        while t < 2 { p.laneRay[1] = p.sweep(1, t); p.laneRay[2] = p.sweep(2, t); p.frame(primaryRay: p.sweep(0, t)); t += 1.0 / 60 }
        XCTAssertEqual(p.lanes.liveIDs, [1, 2])
        p.lanes.cancelAll { [unowned p] in let b = p.body($0); return (b.rig.sim, b.rig.brain, b.rig.skinner) }
        XCTAssertTrue(p.lanes.isEmpty); XCTAssertTrue(p.lanes.liveIDs.isEmpty)
        XCTAssertFalse(p.b.rig.sim.pressing); XCTAssertFalse(p.c.rig.sim.pressing)
        XCTAssertNil(p.lanes.companionLevels())
    }

    func testThreeFingersOnThreeJelmiko() {
        let p = Pair()
        p.lanes.begin(jelly: 1, finger: p.fb, point: .zero, size: Self.sz, target: p.a.driver)
        p.lanes.begin(jelly: 2, finger: p.fc, point: .zero, size: Self.sz, target: p.a.driver)
        var t: Float = 0
        while t < 3 { p.laneRay[1] = p.sweep(1, t); p.laneRay[2] = p.sweep(2, t); p.frame(primaryRay: p.sweep(0, t)); t += 1.0 / 60 }
        XCTAssertGreaterThan(p.a.play.love, 0.85)
        XCTAssertGreaterThan(p.lanes.lanes[1]!.play.love, 0.85)
        XCTAssertGreaterThan(p.lanes.lanes[2]!.play.love, 0.85)
        XCTAssertGreaterThan(p.hubHearts[1] ?? 0, 0); XCTAssertGreaterThan(p.hubHearts[2] ?? 0, 0)
        XCTAssertEqual(PetRoute.route(primary: .pet, picked: 3, touchID: 0, liveLanes: p.lanes.liveIDs), .ignore, "a fourth finger is ignored cleanly")
        XCTAssertLessThanOrEqual(p.a.rec.events(.continuous, channel: "pet").map(\.intensity).max() ?? 0, 1)
    }

    func testSameJelmikoStaysOneStrokeAtTheSingleRate() {
        // a second finger on the primary's Jelmiko never gets a lane; neither does a second on a lane's body: hearts, love and attention stay at the single rate
        XCTAssertEqual(PetRoute.route(primary: .pet, picked: 0, touchID: 0, liveLanes: []), .ignore)
        let p = Pair()
        p.lanes.begin(jelly: 1, finger: p.fb, point: .zero, size: Self.sz, target: p.a.driver)
        XCTAssertEqual(PetRoute.route(primary: .pet, picked: 1, touchID: 0, liveLanes: p.lanes.liveIDs), .ignore)
        let single = Self.singleStroke()
        var t: Float = 0
        while t < 3 { p.laneRay[1] = p.sweep(1, t); p.frame(primaryRay: p.sweep(0, t)); t += 1.0 / 60 }
        XCTAssertLessThanOrEqual(abs((p.hubHearts[1] ?? 0) - single.hearts), 1)
    }

    func testHoldDragAndFlickAreNeverDisturbed() {
        for primary in [PetRoute.Primary.grab, .cheeks] {
            for picked in [0, 1, 2] { XCTAssertEqual(PetRoute.route(primary: primary, picked: picked, touchID: 0, liveLanes: []), .ignore, "\(primary) / finger on \(picked)") }
        }
        // a lane only pets: it has no hold / grab of its own
        let p = Pair()
        let l = p.lanes.begin(jelly: 1, finger: p.fb, point: .zero, size: CGSize(width: 10, height: 10), target: p.a.driver)
        XCTAssertFalse(l.play.holdsBrain)
        XCTAssertFalse(p.b.rig.sim.grabbing)
    }
}
