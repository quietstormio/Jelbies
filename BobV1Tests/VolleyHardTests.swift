//
//  VolleyHardTests.swift
//  Jelly Volleyball, harder and more polished (2026-11-24, "slightly increase difficulty of volleyball opponents ... I won every set the same way ... ensure no buggy look,
//  they can still kick with their backs turned"):
//   1. the pure sim, played by the scripted bots of VolleyHarness: nobody touches the ball with it behind his back, nobody hits his own ball twice running, a spike never ends in the tape;
//   2. the win-rate bars: a repeated placement no longer wins every set, the varied attentive player still wins most of them on the low tiers, the first level stays clearly winnable;
//   3. the same on REAL soft bodies (the touch's angle is read off the body's real heading).
//

import XCTest
import simd
@testable import BobV1

@MainActor
final class VolleyHardTests: XCTestCase {
    nonisolated(unsafe) static var keep: [AnyObject] = []

    /// The harder tuning is off by default; these tests turn it on as harness config and put the defaults back after each test.
    override func tearDown() { VolleyTuning.hard = false; VolleyTuning.facing = true; super.tearDown() }

    private func run(_ p: VolleyScriptProfile, tier: VolleyTier, n: Int, seed0: UInt64 = 9100) -> (win: Float, secs: Float, backTurned: Int, touches: Int, doubles: Int) {
        var w = 0, secs: Float = 0, bt = 0, tt = 0, dh = 0
        for k in 0..<n {
            let r = VolleyHarness.play(tier: tier, seed: seed0 + UInt64(k) * 7919, profile: p)
            if r.win { w += 1 }; secs += r.seconds; bt += r.backTurned; tt += r.touches; dh += r.doubleHits
        }
        return (Float(w) / Float(n) * 100, secs / Float(n), bt, tt, dh)
    }

    /// Nobody hits a ball that is behind his back (outside the front 60 degrees of his heading, and not right over him), whoever he is and whatever the script does.
    func testNoTouchStartsWithTheBallBehindTheHitter() {
        VolleyTuning.hard = true
        let bots: [VolleyScriptProfile] = [.ordinary, .skilled, VolleyScriptProfile.ordinary.with("aim") { $0.aim = SIMD2(1, -1) }, VolleyScriptProfile.ordinary.with("spike") { $0.alwaysSpike = true },
                                           VolleyScriptProfile.ordinary.with("spam") { $0.spam = true }, VolleyScriptProfile.ordinary.with("still") { $0.noMove = true }]
        var touches = 0
        for b in bots { for t in VolleyTier.allCases {
            let r = run(b, tier: t, n: 6)
            touches += r.touches
            XCTAssertEqual(r.backTurned, 0, "\(b.name) vs \(t.title): \(r.backTurned) of \(r.touches) touches began with the ball behind the hitter")
        } }
        XCTAssertGreaterThan(touches, 500)
    }

    /// The facing rule alone (`-VolleyHard 0 -VolleyFacing 1`): the old play with only "no touch begins behind a back": 0 back-turned touches, and the old play without it has many.
    func testFacingRuleAloneIsolated() {
        VolleyTuning.hard = false
        var withRule = 0, without = 0
        for t in VolleyTier.allCases {
            VolleyTuning.facing = true; withRule += run(.ordinary, tier: t, n: 6).backTurned
            VolleyTuning.facing = false; without += run(.ordinary, tier: t, n: 6).backTurned
        }
        XCTAssertEqual(withRule, 0, "back-turned touches with only the facing rule")
        XCTAssertGreaterThan(without, 20, "(the rig sees them without it)")
    }

    /// The spiker's own slow ball is never hit by him a second time (that was the fourth-touch fault the computer lost most points to).
    func testNobodyHitsHisOwnBallTwiceRunning() {
        VolleyTuning.hard = true
        for t in VolleyTier.allCases {
            let r = run(.ordinary, tier: t, n: 20)
            XCTAssertLessThanOrEqual(r.doubles, 2, "\(t.title): \(r.doubles) double hits in 20 matches")          // (a few honest ones remain: a dive and a bump a moment apart)
        }
        VolleyTuning.hard = false
        let before = run(.ordinary, tier: .reef, n: 20)
        VolleyTuning.hard = true
        print("VOLLEYDOUBLES old play (reef, 20 matches): \(before.doubles)")
        XCTAssertGreaterThan(before.doubles, 5, "(the rig sees the old bug with -VolleyHard 0)")
    }

    /// The bars (n = 80 a cell, fixed seeds): the first level stays winnable; a varied, attentive player (plain play with the smash placed somewhere different each time) still wins most
    /// of the sets on the low tiers; and the placements a player might repeat (the smash always deep and wide, always deep and near, short, wide of the middle) no longer win the way they did:
    /// the average of them above the first level is at most 65%, and well under what the 10t play gave (`hard = false`).
    func testWinRateBars() {
        let n = 80
        let placed = VolleyScriptProfile.ordinary.with("placed") { $0.aimCycle = true; $0.aimSpikeOnly = true }
        let fixed: [VolleyScriptProfile] = [SIMD2<Float>(1, -1), SIMD2(1, 1), SIMD2(-1, 0), SIMD2(0, -1)].map { a in VolleyScriptProfile.ordinary.with("spike to \(a)") { $0.aim = a; $0.aimSpikeOnly = true } }
        var lines: [String] = []
        for t in VolleyTier.allCases {
            VolleyTuning.hard = true
            let m = run(placed, tier: t, n: n)
            lines.append("\(t.title): placed \(m.win)% \(Int(m.secs)) s")
            if t == .sandcastle { XCTAssertGreaterThan(m.win, 65, "the first level is winnable"); XCTAssertLessThan(m.win, 97) }
            if t == .shore { XCTAssertGreaterThan(m.win, 50, "Shore: the varied player still wins about half or more of the sets") }
            guard t != .sandcastle else { continue }
            let after = fixed.map { run($0, tier: t, n: n).win }
            VolleyTuning.hard = false
            let before = fixed.map { run($0, tier: t, n: n).win }
            VolleyTuning.hard = true
            let mA = after.reduce(0, +) / Float(after.count), mB = before.reduce(0, +) / Float(before.count)
            lines.append("   repeated smash placements, mean: \(mB)% before -> \(mA)% after  (\(after))")
            XCTAssertLessThanOrEqual(mA, 65, "\(t.title): a repeated placement wins \(mA)% of the sets on average")
            XCTAssertLessThanOrEqual(mA, mB + 3, "\(t.title): the repeated placements got easier")
        }
        print("VOLLEYHARD\n" + lines.joined(separator: "\n"))
    }

    // MARK: real bodies

    /// The real soft bodies, two matches against Reef: every touch's angle from the body's real heading (the body turns in the air to what it hits), and no double hit.
    func testRealBodiesNeverHitWithTheirBacksTurned() throws {
        VolleyTuning.hard = true
        var touches = 0, back = 0
        for (k, tier) in [VolleyTier.reef, .tidal].enumerated() {
            let room = RaceThreeTests.Room(count: 2)
            Self.keep.append(room)
            let care = room.care
            care.startVolley(jelly: 0, mode: .match(tier), seed: UInt64(70 + k))
            var guardTicks = 0
            while !(care.volley.live && care.volley.sim?.phase == .serveWait) && guardTicks < 60 * 40 { room.step(); care.tickVolley(room.actors, dt: room.actors[0].sim.stepDt); guardTicks += 1 }
            XCTAssertTrue(care.volley.live)
            var script = VolleyScript(.ordinary, seed: UInt64(70 + k))
            let dt = room.actors[0].sim.stepDt
            var seen = -1, ticks = 0
            while care.volley.live, let s0 = care.volley.sim, s0.phase != .over, ticks < 60 * 200 {
                var s = s0
                script.drive(&s, dt: dt)
                care.volley.sim = s
                room.step(); care.tickVolley(room.actors, dt: dt); ticks += 1
                guard let s1 = care.volley.sim, s1.touchSerial != seen, s1.lastHit >= 0, s1.touchSerial > 0 else { continue }
                seen = s1.touchSerial
                guard care.volleyWork.players.indices.contains(s1.lastHit), let b = care.volleyWork.players[s1.lastHit].brain else { continue }
                let d = SIMD2(s1.contactBall.x - s1.players[s1.lastHit].x, s1.contactBall.z - s1.players[s1.lastHit].z), l = simd_length(d)
                touches += 1
                if l >= VolleyTuning.overheadRadius, simd_dot(VolleySim.forward(b.yaw), d / l) < cosf(VolleyTuning.facingHalfAngle) - 0.02 { back += 1 }
            }
        }
        print("VOLLEYREALFACING touches \(touches), back-turned \(back)")
        XCTAssertGreaterThan(touches, 30)
        XCTAssertEqual(back, 0, "\(back) of \(touches) real touches began with the ball behind the hitter")
    }
}
