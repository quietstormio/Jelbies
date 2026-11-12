//
//  ParkSlideRoundWanderTests.swift
//  park-slide-r2: the park roam pick rejects a goal whose straight leg crosses a keep-out (BlobBrain.pickRoamGoal, `ParkClearSpot.legCrossesSolid`). Three bodies, 3 seeds, 60 sim-s, with the check on and off:
//  wander walk starts per minute (on >= 90% of off), box samples (centre inside the slide box while walking: 0 with the check), rejects per pick printed, nobody without a walk.
//

import XCTest
import simd
@testable import BobV1

extension ParkSlideRoundTests {
    struct WanderRun { var starts = 0, boxSamples = 0, checks = 0, rejects = 0, silentBodies = 0 }

    func wanderRun(check: Bool) -> WanderRun {
        var out = WanderRun()
        ParkClearSpot.legCheckEnabled = check
        defer { ParkClearSpot.legCheckEnabled = true }
        for seed in UInt64(1)...3 {
            let lab = parkLab(n: 3, seed: seed, aspect: Self.portrait, starts: [SIMD2(1.30, 1.90), SIMD2(-0.7, 0.2), SIMD2(0.4, 2.4)], quiet: false)
            for r in lab.rigs { r.brain.idleState.cooldown = 1e6; r.brain.socialBook.cooldown = 1e6 }          // (only the ordinary wander: no specials, no socials)
            for r in lab.rigs { r.brain.restTimer = 0.5 }
            let sl = DecorField.shared.foot(ParkToys.slideUID)!, bx = box(sl)
            ParkClearSpot.legChecks = 0; ParkClearSpot.legRejects = 0
            var was = [Bool](repeating: false, count: 3), own = [Int](repeating: 0, count: 3)
            for _ in 0..<(60 * 60) {
                lab.tick(watching: false); DecorField.shared.tick(dt: 1.0 / 60)
                for (k, r) in lab.rigs.enumerated() {
                    var walking = false
                    if case .walk = r.brain.script, r.brain.idleState.kind == nil { walking = true }
                    if walking, !was[k] { out.starts += 1; own[k] += 1 }
                    was[k] = walking
                    if walking, insideDepth(bx, r.brain.position) > 0.02 { out.boxSamples += 1 }
                }
            }
            out.checks += ParkClearSpot.legChecks; out.rejects += ParkClearSpot.legRejects
            out.silentBodies += own.filter { $0 == 0 }.count
            for r in lab.rigs { r.brain.abortAll(r.sim, r.skinner) }
        }
        return out
    }

    func testRoamPickRejectsLegsThroughTheSlide() {
        let off = wanderRun(check: false)
        let on = wanderRun(check: true)
        let picks = max(on.starts, 1)
        print("PSR WANDER off: starts \(off.starts) (per minute \(Float(off.starts) / 3)) box samples \(off.boxSamples) silent bodies \(off.silentBodies)")
        print("PSR WANDER on: starts \(on.starts) (per minute \(Float(on.starts) / 3)) box samples \(on.boxSamples) silent bodies \(on.silentBodies); candidates checked \(on.checks), rejected \(on.rejects) (\(Float(on.rejects) / Float(picks)) per started pick)")
        XCTAssertGreaterThan(off.starts, 10, "wander happens")
        XCTAssertGreaterThanOrEqual(Float(on.starts), 0.9 * Float(off.starts), "wander starts per minute stay at 90% or more")
        XCTAssertEqual(on.silentBodies, 0, "nobody ends the minute without a goal")
        XCTAssertEqual(on.boxSamples, 0, "no wander walker inside the slide box with the check on")
    }
}
