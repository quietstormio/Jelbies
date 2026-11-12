//
//  SoftMealOffTests.swift
//  `BlobBrain.softMealWake` OFF = today's meal call (`requestNow`): the same lab run prints its numbers (`SOFTWAKE-OFF ...`); the log from the base commit and from this branch must be identical.
//  Compiles on the base commit too (uses only API that exists there).
//

import XCTest
import simd
@testable import BobV1

@MainActor
final class SoftMealOffTests: XCTestCase {
    override func setUp() { RoomLayout.dynamicBoxes = []; GameCamera.configureRoom(count: 3, option: .A, wide: 2); _ = GameCamera.camera(aspect: 440 / 956); SleepOrder.reset() }
    override func tearDown() { RoomLayout.dynamicBoxes = []; GameCamera.configureRoom(count: 1); _ = GameCamera.camera(aspect: 440.0 / 956.0); SleepOrder.reset() }
    private let dt: Float = 1.0 / 60

    private func night(n: Int, seed: UInt64) -> SocialTests.Lab {
        let lab = SocialTests.Lab(n: n, quiet: false, seed: seed)
        for r in lab.rigs {
            r.brain.sleepEnabled = true; r.brain.watching = true
            r.brain.idleNight = 1; r.brain.idleDeepNight = 1
            r.brain.idleState.cooldown = 0; r.brain.restTimer = 0.5; r.brain.socialBook.cooldown = 1e6
        }
        for _ in 0..<120 { lab.tick(watching: false) }
        NightRestTuning.sendToBed(lab.rigs.map(\.brain))
        var t: Float = 0
        while t < 40, !lab.rigs.allSatisfy({ $0.brain.isNapping }) { lab.tick(watching: false); t += dt }
        for _ in 0..<60 { lab.tick(watching: false) }
        for r in lab.rigs { r.brain.idleNight = 0; r.brain.idleDeepNight = 0; r.brain.autonomy = false }
        SleepOrder.reset()
        return lab
    }

    /// One group meal on sleepers; returns each diner's first eat time (nil = never) and the end time.
    static func meal(_ lab: SocialTests.Lab, limit: Float = 60) -> (ate: [Float?], end: Float?) {
        let dt: Float = 1.0 / 60
        let brains = lab.rigs.map(\.brain)
        let group = DiningGroup()
        group.start(Consumables.berries, brains: brains, floor: { lab.rigs[$0].brain.position })
        var ate = [Float?](repeating: nil, count: brains.count), end: Float?
        var t: Float = 0
        while t < limit, end == nil {
            lab.tick(watching: false); group.tick(dt: lab.rigs[0].sim.stepDt); t += dt
            for (i, b) in brains.enumerated() where ate[i] == nil { if b.activity == .eating || b.activity == .drinking { ate[i] = t } }
            if group.state == .idle { end = t }
        }
        group.cancel(); group.dining.reset()
        return (ate, end)
    }

    func testFlagOffNumbers() {
        let was = BlobBrain.softMealWake; BlobBrain.softMealWake = false; defer { BlobBrain.softMealWake = was }
        for seed in UInt64(1)...10 {
            for n in [1, 3] {
                let lab = night(n: n, seed: seed)
                let r = Self.meal(lab)
                func f(_ v: Float?) -> String { v.map { String(format: "%.2f", $0) } ?? "nil" }
                let line = "SOFTWAKE-OFF seed \(seed) n \(n) ate \(r.ate.map(f)) end \(f(r.end))"
                MotionLog.write(line); print(line)
            }
        }
    }
}
