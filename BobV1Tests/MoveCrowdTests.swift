//
//  MoveCrowdTests.swift
//  move-crowd-r1: the scope of MoveCrowd (free autonomous walkers at home / on a park visit only; never a requested walk, a meal, a social walk-up) and the mechanism on the
//  plain meetings (head on, crossing, same way): with the switch on the two keep outside the push radius where the switch off lets them in.
//

import XCTest
import simd
@testable import BobV1

@MainActor
final class MoveCrowdTests: XCTestCase {
    nonisolated(unsafe) static var keep: [AnyObject] = []
    var was = false
    override func setUp() { was = MoveCrowd.on }
    override func tearDown() { MoveCrowd.on = was; GameCamera.configureRoom(count: 1); GameCamera.clearRoam(); RoomLayout.apply(RoomCatalog.home) }

    func room() {
        GameCamera.configureRoom(count: 3, option: .A, wide: 2); _ = GameCamera.camera(aspect: 440 / 956)
        _ = GameCamera.refreshRoam(aspect: 440 / 956)
        RoomLayout.dynamicBoxes = []
    }

    /// Requested walks (come here, a goTo job, a command), meals (`homeRoom` is false while the tray is out) and social walk-ups are never steered by MoveCrowd.
    func testGateOnlyFreeAutonomousWalkers() {
        room()
        let l = SocialTests.Lab(n: 3, quiet: true, seed: 5)
        Self.keep.append(l)
        let b = l.rigs[0].brain
        MoveCrowd.on = true
        b.homeRoom = true
        XCTAssertTrue(b.crowdLive, "a free body at home")
        b.homeRoom = false; b.outingPlay = false
        XCTAssertFalse(b.crowdLive, "a meal / drink / bath (homeRoom false), the café, the Show")
        b.homeRoom = true
        b.job = .goTo(SIMD2(1, 1)); XCTAssertFalse(b.crowdLive, "a requested walk (come here, goTo)"); b.job = nil
        b.commanded = true; XCTAssertFalse(b.crowdLive, "a voice command"); b.commanded = false
        _ = b.newSession(.boop, with: l.rigs[1].brain, duration: 4)
        XCTAssertFalse(b.crowdLive, "a social walk-up")
        if let s = b.social { s.finish(.done) }
        MoveCrowd.on = false
        XCTAssertFalse(b.crowdLive, "switch off")
    }

    /// Two free walkers meeting (head on, crossing, same way side by side): the closest centre distance with the switch off and on.
    func run(_ a0: SIMD2<Float>, _ a1: SIMD2<Float>, _ b0: SIMD2<Float>, _ b1: SIMD2<Float>, on: Bool) -> (minD: Float, arrived: Int) {
        room()
        MoveCrowd.on = on
        let l = SocialTests.Lab(n: 3, positions: [a0, b0, SIMD2(2.6, -3.0)], quiet: true, seed: 5)
        Self.keep.append(l)
        let a = l.rigs[0].brain, b = l.rigs[1].brain
        for x in [a, b, l.rigs[2].brain] { x.homeRoom = true }
        for (x, g) in [(a, a1), (b, b1)] {
            x.yaw = atan2f(g.x - x.position.x, g.y - x.position.y)
            x.route = []; x.scriptT = 0; x.stuckT = 0; x.script = .walk(target: g, then: .none); x.activity = .walking
        }
        var minD = Float.infinity
        for _ in 0..<(60 * 10) { l.tick(watching: false); minD = min(minD, l.brainGap(0, 1)) }
        let arrived = [a, b].filter { if case .walk = $0.script { return false }; return true }.count
        MoveCrowd.on = was
        return (minD, arrived)
    }

    func testPlainMeetingsKeepOutsideThePushRadius() {
        let cases: [(String, SIMD2<Float>, SIMD2<Float>, SIMD2<Float>, SIMD2<Float>)] = [
            ("head on", SIMD2(-2.4, 1.0), SIMD2(2.4, 1.0), SIMD2(2.4, 1.2), SIMD2(-2.4, 1.2)),
            ("crossing", SIMD2(-2.4, 1.0), SIMD2(2.4, 1.0), SIMD2(0.0, -1.6), SIMD2(0.2, 3.6)),
            ("same way", SIMD2(-2.4, 0.6), SIMD2(2.4, 1.4), SIMD2(-2.4, 1.6), SIMD2(2.4, 0.6)),
        ]
        var lines: [String] = []
        for (name, a0, a1, b0, b1) in cases {
            let off = run(a0, a1, b0, b1, on: false), on = run(a0, a1, b0, b1, on: true)
            lines.append("\(name): off closest \(off.minD) arrived \(off.arrived) | on closest \(on.minD) arrived \(on.arrived)")
            XCTAssertGreaterThanOrEqual(on.minD, min(off.minD, 1.3), "\(name): never closer with the switch on")
        }
        MotionLog.write("MOVECROWD meetings:\n" + lines.joined(separator: "\n"))
    }

    /// A requested walk (goTo) whose leg passes a STANDING body inside its margin: the 6 s patience must run out (it was reset every 3 s by the stall re-plan: the walker stood for good).
    func standOff(on: Bool) -> (arrived: Bool, longest: Float) {
        room()
        MoveCrowd.on = on
        let l = SocialTests.Lab(n: 3, positions: [SIMD2(-2.2, 1.0), SIMD2(0.0, 1.25), SIMD2(2.6, -3.0)], quiet: true, seed: 5)
        Self.keep.append(l)
        let a = l.rigs[0].brain
        a.requestNow(.goTo(SIMD2(2.2, 1.0)))
        var still: Float = 0, longest: Float = 0, last = a.position, arrived = false
        for _ in 0..<(60 * 20) {
            l.tick(watching: false)
            if simd_distance(a.position, last) < 0.0005 { still += 1.0 / 60; longest = max(longest, still) } else { still = 0 }
            last = a.position
            if a.job == nil, simd_distance(a.position, SIMD2(2.2, 1.0)) < 0.6 { arrived = true; break }
        }
        MoveCrowd.on = was
        return (arrived, longest)
    }

    func testRequestedWalkPastAStanderEnds() {
        let off = standOff(on: false), on = standOff(on: true)
        MotionLog.write("MOVECROWD stand-off: off arrived \(off.arrived) longest still \(off.longest) s | on arrived \(on.arrived) longest still \(on.longest) s")
        XCTAssertTrue(on.arrived, "the requested walk arrives within 20 s")
        XCTAssertLessThan(on.longest, 8, "no stand longer than the 6 s patience + a step")
    }
}
