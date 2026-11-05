//
//  LineupTests.swift
//  Jelbies walk AROUND each other (never through) and line up smartly (2026-11-01: "one will walk right through another", "just line up for what's best in the line").
//  Steering level only: no body-vs-body push. Crossing walkers (head on, 90 degrees, overtaking), the "Come here" row from the worst start layouts, and the group meal.
//

import XCTest
import simd
@testable import BobV1

@MainActor
final class LineupTests: XCTestCase {
    nonisolated(unsafe) static var keep: [AnyObject] = []
    nonisolated(unsafe) static var debug = false

    /// The sim must not depend on the wall clock: the autonomous goal search stops at a wall-clock budget (BlobBrain.pickBudgetSeconds), so a loaded machine could change a pick.
    /// The meal's tray spot is a system-random pick among the free spots (DiningSpot.choose), which made the meal tests flake: the test takes the free spot nearest the
    /// preferred front spot instead.
    override func setUp() {
        BlobBrain.pickBudgetSeconds = .infinity
        DiningSpot.pickOpen = { $0.min { simd_distance($0, DiningSpot.preferred) < simd_distance($1, DiningSpot.preferred) } }
    }
    override func tearDown() {
        BlobBrain.pickBudgetSeconds = BlobBrain.defaultPickBudgetSeconds
        DiningSpot.pickOpen = { $0.randomElement() }
    }

    /// Closest two bodies over a run (only samples where at least one of the pair walks), and the path each one took.
    struct Track {
        var minDist: Float = .infinity
        var paths: [[SIMD2<Float>]]
        init(count: Int) { paths = [[SIMD2<Float>]](repeating: [], count: count) }
    }

    private func run(_ r: FocusAnyRun, _ secs: Float, track: inout Track, until: (() -> Bool)? = nil) -> Bool {
        var k = 0
        for _ in 0..<Int(secs * 60) {
            r.tick()
            let f = r.actors.map(\.floor)
            for i in 0..<f.count { for j in (i + 1)..<f.count where r.actors[i].isWalking || r.actors[j].isWalking { track.minDist = min(track.minDist, simd_distance(f[i], f[j])) } }
            k += 1
            if LineupTests.debug, k % 30 == 0 { print("DBG t=\(Float(k)/60) " + (0..<f.count).map { let b = r.actors[$0].brain!; return "[\($0) \(String(format: "%.2f,%.2f", f[$0].x, f[$0].y)) \(b.activity) y=\(String(format: "%.1f", b.yieldT)) rt=\(b.route.count) st=\(String(format: "%.1f", b.stuckT)) sw=\(String(format: "%.1f", b.steerWait)) job=\(b.job != nil)]" }.joined(separator: " ")) }
            if k % 15 == 0 { for i in 0..<f.count { track.paths[i].append(f[i]) } }
            if let until, until() { return true }
        }
        return until?() ?? false
    }

    /// The meal tests leave their tray (a global `RoomLayout.dynamicBoxes` obstacle in the middle of the floor, z ~ 1.1) standing, which blocked every later walker /
    /// Come here test at z ~ 1.1 (the "shared obstacle"): those start on an empty floor. (The meal tests keep the stage as they have always run: see `mealCheck`.)
    private func rig(count: Int = 3, clearTray: Bool = true) -> FocusAnyRun {
        if clearTray { RoomLayout.dynamicBoxes = [] }
        let r = FocusAnyRun(count: count, peers: true); Self.keep.append(r)
        r.run(1)
        for a in r.actors { a.brain!.autonomy = false }
        return r
    }

    private func cross(_ a: SIMD2<Float>, _ b: SIMD2<Float>, _ c: SIMD2<Float>, _ d: SIMD2<Float>) -> Bool {
        func o(_ p: SIMD2<Float>, _ q: SIMD2<Float>, _ r: SIMD2<Float>) -> Float { (q.x - p.x) * (r.y - p.y) - (q.y - p.y) * (r.x - p.x) }
        return o(a, b, c) * o(a, b, d) < 0 && o(c, d, a) * o(c, d, b) < 0
    }

    // MARK: crossing walkers

    private func twoWalkers(_ name: String, a0: SIMD2<Float>, a1: SIMD2<Float>, b0: SIMD2<Float>, b1: SIMD2<Float>, secs: Float = 6.5, tol: Float = 0.9, floor: Float = 0.78 * MelonController.jellyGap) {
        let r = rig(count: 2)
        r.place(0, at: a0); r.place(1, at: b0)
        var tr = Track(count: 2)
        r.actors[0].brain!.requestNow(.goTo(a1)); r.actors[1].brain!.requestNow(.goTo(b1))
        _ = run(r, secs, track: &tr)
        let fa = r.actors[0].floor, fb = r.actors[1].floor
        print("LINEUP \(name) minDist=\(tr.minDist) (steering floor 0.78 gap = \(0.78 * MelonController.jellyGap)) end0=\(fa) end1=\(fb)")
        XCTAssertGreaterThanOrEqual(tr.minDist, floor, "\(name): nobody passes through the other")
        XCTAssertLessThan(simd_distance(fa, a1), tol, "\(name): Jelly 0 reaches his goal (at \(fa))")
        XCTAssertLessThan(simd_distance(fb, b1), tol, "\(name): Jelly 1 reaches his goal (at \(fb))")
    }

    // (the floor is ~2.2 wide in portrait and 5.4 deep: walkers swing out along the other axis)
    func testHeadOnWalkersPassWithoutTouching() { twoWalkers("headOn", a0: SIMD2(-2.15, 0.4), a1: SIMD2(0.7, 0.4), b0: SIMD2(2.15, 0.4), b1: SIMD2(-0.7, 0.4)) }
    func testHeadOnExactlyInLineStillPass() { twoWalkers("headOnExact", a0: SIMD2(-2.15, 0), a1: SIMD2(0.7, 0), b0: SIMD2(2.15, 0), b1: SIMD2(-0.7, 0)) }
    func testHeadOnDownTheDeepAxisPass() { twoWalkers("headOnDeep", a0: SIMD2(-0.2, -2.0), a1: SIMD2(-0.2, 2.4), b0: SIMD2(0.2, 2.4), b1: SIMD2(0.2, -2.0)) }
    /// Paths that cross like an X.
    func testCrossingWalkersDoNotPassThrough() { twoWalkers("cross", a0: SIMD2(-1.0, -1.5), a1: SIMD2(1.0, 2.4), b0: SIMD2(1.0, -1.5), b1: SIMD2(-1.0, 2.4)) }
    /// A right angle: A along the width, B up the depth, meeting in the middle.
    func testNinetyDegreeCrossingWalkersDoNotPassThrough() { twoWalkers("cross90", a0: SIMD2(-1.0, 0.4), a1: SIMD2(1.0, 0.4), b0: SIMD2(0.0, -0.6), b1: SIMD2(0.0, 2.6), secs: 9, tol: 1.0) }
    /// B walks ahead and stops in A's lane: A (behind, same speed) must go round him.
    func testOvertakingWalkerGoesRoundTheOneAhead() { twoWalkers("overtake", a0: SIMD2(0, -2.0), a1: SIMD2(0, 2.6), b0: SIMD2(-0.5, -0.8), b1: SIMD2(-0.5, 0.6), secs: 10) }

    // MARK: the Come here row

    private func rowCheck(_ name: String, starts: [SIMD2<Float>]) {
        let r = rig()
        FocusGroup.softAccept = 99          // (measure the natural arrival: the net would hide it)
        defer { FocusGroup.softAccept = 5.5 }
        for (i, s) in starts.enumerated() { r.place(i, at: s) }
        var tr = Track(count: 3)
        r.care.comeHereEveryone()
        let t0 = r.care.focusGroup.clock
        var secs: Float = 0
        var dk = 0
        let done = run(r, 12, track: &tr) {
            secs += 1 / 60; dk += 1
            if LineupTests.debug, dk % 30 == 0 { let g = r.care.focusGroup; print("DBG t=\(secs) arrived=\(g.arrived) clock=\(g.clock) front=\(g.front) " + (0..<3).map { let b = r.actors[$0].brain!; return "[\($0) \(String(format: "%.2f,%.2f", r.actors[$0].floor.x, r.actors[$0].floor.y)) -> \(String(format: "%.2f,%.2f", g.spot(of: $0).x, g.spot(of: $0).y)) \(b.activity) job=\(b.job.map { "\($0)" } ?? "nil") sc=\(b.script)]" }.joined(separator: " ")) }
            return r.care.focus.isFocused
        }
        _ = t0
        let spots = r.care.focusGroup.spots
        var crossings = 0
        for i in 0..<3 { for j in (i + 1)..<3 { if let si = spots[i], let sj = spots[j], cross(starts[i], si, starts[j], sj) { crossings += 1 } } }
        print("LINEUP row \(name) done=\(done) time=\(secs) minDist=\(tr.minDist) crossings=\(crossings) spots=\(spots)")
        XCTAssertTrue(done, "\(name): the line-up completes")
        XCTAssertEqual(r.care.focusGroup.netAccepted, 0, "\(name): everybody ARRIVED on his own (the safety net accepted none)")
        XCTAssertLessThan(secs, 8.0, "\(name): in under 8 s")
        XCTAssertLessThanOrEqual(crossings, 1, "\(name): at most one pair of assigned paths cross (a Jelbie stuck behind two standing ones)")
        XCTAssertGreaterThanOrEqual(tr.minDist, 0.78 * GameCamera.focusRowGap, "\(name): nobody passed through anybody")
    }
    func testRowFromTwoOuterOnesNearTheMiddleSlot() { rowCheck("nearMiddle", starts: [SIMD2(0, -1.2), SIMD2(-0.6, 0.8), SIMD2(0.6, 0.8)]) }
    func testRowFromOneFarBehind() { rowCheck("farBehind", starts: [SIMD2(0, -2.0), SIMD2(-1.0, 0.6), SIMD2(1.0, 0.6)]) }
    func testRowFromAllOnOneSide() { rowCheck("oneSide", starts: [SIMD2(-1.0, 0.0), SIMD2(-1.0, 1.6), SIMD2(-1.0, -1.6)]) }

    // MARK: the group meal

    /// The tray is never offered where a side diner cannot reach his place. Before: with the tray at x +-0.2 (z 1.6...2.0) the far side stand (x +-1.31) lies outside the
    /// walkable width (the floor rules move it to +-1.0), the side diner stopped 0.5 short and the line-up never finished (done=false, 14 s) in 6 of the 14 spots.
    func testTrayNeverOffersAnUnreachableSidePlace() {
        _ = rig(count: 3)
        var offered: [SIMD2<Float>] = []
        DiningSpot.pickOpen = { offered = $0; return $0.first }
        _ = DiningSpot.choose(bob: SIMD2(99, 99), layout: DiningLayout.make(n: 3))
        XCTAssertFalse(offered.isEmpty, "some spot is offered")
        for o in offered { for p in DiningLayout.make(n: 3).places { XCTAssertTrue(DiningSpot.placeReachable(o + p.rel), "tray \(o): the place at \(o + p.rel) is reachable") } }
        XCTAssertFalse(DiningSpot.placeReachable(SIMD2(1.31, 0.76)), "a stand beyond the walkable width is not a place")
        XCTAssertFalse(DiningSpot.placeReachable(SIMD2(-1.31, 0.76)))
        XCTAssertTrue(DiningSpot.placeReachable(SIMD2(1.11, 0.76)), "the centre column's side stand is")
        XCTAssertTrue(DiningSpot.placeReachable(SIMD2(-1.11, 0.76)))
    }

    private func mealCheck(_ name: String, starts: [SIMD2<Float>]) {
        let r = rig(clearTray: false)
        for (i, s) in starts.enumerated() { r.place(i, at: s) }
        for i in 0..<3 { r.care.needs(for: i).set(.thirst, 0.1) }
        r.run(0.5)
        var tr = Track(count: 3)
        r.care.drink()
        var secs: Float = 0
        let done = run(r, 14, track: &tr) { secs += 1 / 60; return r.care.group.state == .serving }
        print("LINEUP meal \(name) done=\(done) time=\(secs) minDist=\(tr.minDist) places=\(r.care.group.placeOf)")
        XCTAssertTrue(done, "\(name): the meal line-up completes")
        XCTAssertLessThan(secs, 8.0, "\(name): in under 8 s")
        XCTAssertGreaterThanOrEqual(tr.minDist, 0.9 * DiningGroup.diningGap * 1.2, "\(name): nobody passed through anybody")
    }
    func testMealFromTwoOuterOnesNearTheMiddle() { mealCheck("nearMiddle", starts: [SIMD2(0, -1.8), SIMD2(-0.7, 0.2), SIMD2(0.7, 0.2)]) }
    func testMealFromOneFarBehind() { mealCheck("farBehind", starts: [SIMD2(0, -2.0), SIMD2(-1.0, 0.6), SIMD2(1.0, 0.6)]) }
    func testMealFromAllOnOneSide() { mealCheck("oneSide", starts: [SIMD2(-1.0, 0.0), SIMD2(-1.0, 1.6), SIMD2(-1.0, -1.6)]) }
}
