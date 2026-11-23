//
//  CurvedWalkTests.swift
//  curved-walk-r1: a route corner is walked without a turn on the spot, a re-aim of 1.5 rad arcs, a reversal still turns, and the walks the curved walk must not touch (a meal walk, a stance walk,
//  a walk that starts from a stand) plan exactly the steps they planned before (the switch off against on, positions identical).
//

import XCTest
import simd
@testable import BobV1

@MainActor
final class CurvedWalkTests: XCTestCase {
    nonisolated(unsafe) static var keep: [AnyObject] = []
    var was = true
    override func setUp() { was = BlobBrain.curvedWalk }
    override func tearDown() { BlobBrain.curvedWalk = was; ContactTouchMemory.exact.removeAll() }

    struct Trace { var steps: [(pos: SIMD2<Float>, yaw: Float, rootD: Float, dyaw: Float)] = []; var curved = 0 }

    /// Walks `seconds` in the home room (the SocialTests Lab, one body); `reaim` (at game second t) swaps the walk's target; records every step start (root, yaw, the step's root travel and heading change).
    func walk(on: Bool, start: SIMD2<Float> = SIMD2(-2.0, 1.2), yaw0: Float = .pi / 2, route: [SIMD2<Float>] = [], target: SIMD2<Float>, seconds: Float, setup: ((BlobBrain) -> Void)? = nil, reaim: (t: Float, to: SIMD2<Float>)? = nil, moving: Bool = true) -> Trace {
        BlobBrain.curvedWalk = on
        GameCamera.configureRoom(count: 3, option: .A, wide: 2); _ = GameCamera.camera(aspect: 440 / 956)
        _ = GameCamera.refreshRoam(aspect: 440 / 956)
        RoomLayout.dynamicBoxes = []
        let lab = SocialTests.Lab(n: 1, positions: [start], quiet: true, seed: 5)
        Self.keep.append(lab)
        let rig = lab.rigs[0], b = rig.brain
        b.yaw = yaw0
        setup?(b)
        var tr = Trace()
        var didReaim = false
        var last = (SIMD2<Float>.zero, SIMD2<Float>.zero, Float(0), Float(0)), t: Float = 0
        BlobBrain.curveCounts = [0, 0]
        b.route = route; b.scriptT = 0; b.stuckT = 0; b.script = .walk(target: target, then: .none); b.activity = .walking
        if moving { b.lastTranslateClock = b.peerClock }          // (a walk that is already moving; `moving: false` = a walk from a stand)
        for fr in 0..<Int(seconds * 60) {
            if let r = reaim, !didReaim, t >= r.t, case .walk = b.script { didReaim = true; b.script = .walk(target: r.to, then: .none); b.route = []; b.scriptT = 0 }
            lab.tick(watching: false); t += 1.0 / 60
            let cur = (b.stepRoot0, b.stepRootD, b.stepYaw0, b.stepYawD)          // (a new step = a new plan: its start, travel, heading and heading change)
            if cur.0 != last.0 || cur.1 != last.1 || cur.2 != last.2 || cur.3 != last.3 { tr.steps.append((b.stepRoot0, b.stepYaw0, simd_length(b.stepRootD), b.stepYawD)); last = cur }
            if !b.isWalkScript, t > 1 { break }
        }
        tr.curved = BlobBrain.curveCounts[0]
        return tr
    }
    /// A step that turns the body on the spot (no travel, a real heading change).
    func spotTurns(_ tr: Trace, after n: Int = 3) -> Int { tr.steps.dropFirst(n).filter { $0.rootD < 0.03 && abs($0.dyaw) > 0.2 }.count }
    func distToPolyline(_ p: SIMD2<Float>, _ pts: [SIMD2<Float>]) -> Float {
        var best = Float.infinity
        for (a, b) in zip(pts, pts.dropFirst()) {
            let ab = b - a, t = max(0, min(1, simd_dot(p - a, ab) / max(simd_dot(ab, ab), 1e-6)))
            best = min(best, simd_distance(p, a + ab * t))
        }
        return best
    }

    /// A three-point route with a 90 degree corner is walked at a walk: no turn on the spot, inside a corridor round the polyline, and the old way (switch off) does stop and turn.
    func testRouteCornerIsRounded() {
        let a = SIMD2<Float>(-2.0, 0.4), c = SIMD2<Float>(0.2, 0.4), e = SIMD2<Float>(0.2, 2.4)
        let on = walk(on: true, start: a, route: [c], target: e, seconds: 14)
        let off = walk(on: false, start: a, route: [c], target: e, seconds: 14)
        MotionLog.write("CURVED corner: on \(on.steps.count) steps, spot turns \(spotTurns(on)), curved steps \(on.curved); off \(off.steps.count) steps, spot turns \(spotTurns(off))")
        XCTAssertEqual(spotTurns(on), 0, "the corner is walked round")
        XCTAssertGreaterThan(on.curved, 0, "some steps bend")
        XCTAssertGreaterThan(spotTurns(off), 0, "the old walk stops and turns at the corner (the test sees it)")
        for s in on.steps { XCTAssertLessThan(distToPolyline(s.pos, [a, c, e]), 0.6, "inside the corridor") }
        XCTAssertLessThan(simd_distance(on.steps.last!.pos, e), 0.8, "and arrives")
    }

    /// A walk re-aimed by about 1.5 rad while walking arcs; a reversal still stops and turns; every curved step turns the heading by at most the gait's own turn.
    func testReaimArcsAndReversalTurns() {
        let far = SIMD2<Float>(2.2, 1.2)
        let side = SIMD2<Float>(-0.2, 2.6)          // after 2 s the body is near (-0.3, 1.2) heading +x: this is about 1.5 rad to the left
        let on = walk(on: true, target: far, seconds: 12, reaim: (t: 2.0, to: side))
        MotionLog.write("CURVED reaim: spot turns \(spotTurns(on)), curved \(on.curved)")
        XCTAssertEqual(spotTurns(on), 0, "re-aimed at 1.5 rad: no stop and turn")
        XCTAssertGreaterThan(on.curved, 0)
        for s in on.steps { XCTAssertLessThanOrEqual(abs(s.dyaw), 0.75, "no step turns more than the gait's own turn") }
        let back = SIMD2<Float>(-2.3, 1.2)
        let rev = walk(on: true, target: far, seconds: 8, reaim: (t: 2.0, to: back))
        MotionLog.write("CURVED reversal: spot turns \(spotTurns(rev))")
        XCTAssertGreaterThan(spotTurns(rev), 0, "a reversal still stops and turns")
    }

    /// The walks the curved walk must not touch plan exactly the steps they planned before: switch off against on, every step identical.
    func testMealStanceAndStandStartWalksAreUnchanged() {
        let a = SIMD2<Float>(-2.0, 0.4), c = SIMD2<Float>(0.2, 0.4), e = SIMD2<Float>(0.2, 2.4)
        func same(_ x: Trace, _ y: Trace, _ tag: String) {
            XCTAssertEqual(x.steps.count, y.steps.count, "\(tag): same number of steps")
            for (p, q) in zip(x.steps, y.steps) { XCTAssertEqual(simd_distance(p.pos, q.pos), 0, accuracy: 1e-5, "\(tag): same step"); XCTAssertEqual(p.dyaw, q.dyaw, accuracy: 1e-5) }
            XCTAssertEqual(x.curved, 0, "\(tag): no curved step planned")
        }
        let meal = { (b: BlobBrain) in b.mealFinalYaw = 1.0 }
        same(walk(on: true, start: a, route: [c], target: e, seconds: 10, setup: meal), walk(on: false, start: a, route: [c], target: e, seconds: 10, setup: meal), "meal")
        let stance = { (b: BlobBrain) in _ = ContactTouchMemory.exact.insert(b.steerID) }
        same(walk(on: true, start: a, route: [c], target: e, seconds: 10, setup: stance), walk(on: false, start: a, route: [c], target: e, seconds: 10, setup: stance), "stance")
        // a walk that starts from a stand with the target behind-left: turn on the spot first, as before
        let back = SIMD2<Float>(-2.3, 2.2)
        same(walk(on: true, start: a, target: back, seconds: 6, moving: false), walk(on: false, start: a, target: back, seconds: 6, moving: false), "stand start")
    }

    /// An obtuse corner (about 125 degrees) is rounded without doubling back on the route: the path is not much longer than the polyline and the body arrives.
    func testObtuseCornerDoesNotDoubleBack() {
        let a = SIMD2<Float>(-2.0, 0.4), c = SIMD2<Float>(0.2, 0.4), e = SIMD2<Float>(-1.0, 2.2)
        let on = walk(on: true, start: a, route: [c], target: e, seconds: 16)
        var len: Float = 0
        for (p, q) in zip(on.steps, on.steps.dropFirst()) { len += simd_distance(p.pos, q.pos) }
        let poly = simd_distance(a, c) + simd_distance(c, e)
        MotionLog.write("CURVED obtuse: steps \(on.steps.count), path \(len) against polyline \(poly), curved \(on.curved), end \(on.steps.last!.pos)")
        XCTAssertLessThan(len, poly * 1.35, "no doubling back")
        XCTAssertLessThan(simd_distance(on.steps.last!.pos, e), 0.8, "and arrives")
    }

    /// A body in the ball game (the Play session's chase) plans no curved step, whatever its route.
    func testBallGameBodyPlansNoCurvedStep() {
        let a = SIMD2<Float>(-2.0, 0.4), c = SIMD2<Float>(0.2, 0.4), e = SIMD2<Float>(0.2, 2.4)
        let tr = walk(on: true, start: a, route: [c], target: e, seconds: 10, setup: { $0.playChase = 1 })
        XCTAssertEqual(tr.curved, 0, "no curved step in the ball game")
    }
}
