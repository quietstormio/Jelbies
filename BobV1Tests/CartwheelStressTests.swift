//
//  CartwheelStressTests.swift
//  2026-10-27 (cartwheel feet): many cartwheels with randomised state (character, shoes, entry from standing / walking / running / zoomies, a close
//  neighbour, a different sim step, a spot in the room) and the drawn foot measured EVERY frame against the same attached limits as FeetAttachTests.
//  The pass bar is zero detached frames.
//

import XCTest
import simd
@testable import BobV1

@MainActor
final class CartwheelStressTests: XCTestCase {
    nonisolated(unsafe) static var keep: [AnyObject] = []

    struct Verdict { var frames = 0, bad = 0, cartwheels = 0, noStart = 0; var worst = ""; var worstOverlap: Float = -.infinity; var byEntry: [String: Int] = [:] }

    static func lcg(_ s: inout UInt64) -> Float { s = s &* 6364136223846793005 &+ 1442695040888963407; return Float((s >> 40) & 0xFFFFFF) / Float(0x1000000) }

    /// Runs `count` randomised cartwheels; every frame from the start of the move to 0.5 s after it ends is measured.
    static func stress(count: Int, seed: UInt64) -> Verdict {
        var v = Verdict(), s = seed
        let entries = ["stand", "walk", "run", "zoomies"]
        let features: [JellyFeature] = [.none, .spines, .daisy, .wings]
        for n in 0..<count {
            let entry = entries[n % entries.count]
            let feat = features[(n / entries.count) % features.count]
            let shoes = (n / 16) % 2 == 1
            let nearby = (n / 8) % 2 == 1
            let r = MotionRig(game: true, settle: 0.5)
            keep.append(r)
            r.renderSamples = false
            r.brain.feature = feat
            r.brain.shoesWorn = shoes
            r.brain.seed = UInt64(1 + n)
            let px = (lcg(&s) - 0.5) * 2.4, pz = (lcg(&s) - 0.3) * 1.8
            r.sim.teleport(toXZ: SIMD2(px, pz)); r.run(0.4)
            r.brain.currentPose(r.sim)
            if nearby { let p = r.root + SIMD2(0.55 + 0.2 * lcg(&s), 0.3 * (lcg(&s) - 0.5)); r.brain.peers = { [(id: 1, pos: p)] }; r.brain.steerID = 0; r.brain.peerGap = 0.9 }
            r.brain.idleForced = true
            let goal = SIMD2<Float>(-px * 0.6 + 0.3 * (lcg(&s) - 0.5), 1.0 + 0.8 * lcg(&s))
            var started = false
            switch entry {
            case "stand": started = r.brain.idleStart(.cartwheel, r.sim)
            case "walk":
                r.brain.requestNow(.goTo(goal)); r.run(0.4 + 1.2 * lcg(&s))
                started = r.brain.flourishStart(.cartwheel, resume: goal, r.sim, r.skinner)
            case "run":
                _ = r.brain.idleStart(.run, r.sim); r.run(0.5 + 1.5 * lcg(&s))
                started = r.brain.flourishStart(.cartwheel, resume: goal, r.sim, r.skinner)
            default:
                r.brain.seed = 11; _ = r.brain.idleStart(.zoomies, r.sim); r.run(0.8 + 2.5 * lcg(&s))
                started = r.brain.flourishStart(.cartwheel, resume: goal, r.sim, r.skinner)
            }
            if !started { v.noStart += 1; continue }
            var flew = false
            var after: Float = 0, clock: Float = 0, bad = 0
            var frameN = 0
            let hitch = n % 5 == 4          // every fifth: a hitch (two sim steps per brain tick for a stretch, i.e. a long frame)
            for _ in 0..<(60 * 12) {
                if r.brain.idleState.kind != .cartwheel && !(r.brain.idleState.kind == nil && clock < 0.3) { after += 1.0 / 60 }
                if after > 0.5 { break }
                if r.brain.gait.phase == .air { flew = true }
                clock += 1.0 / 60; frameN += 1
                r.tick()
                if hitch && frameN % 17 < 3 { r.sim.step() }
                let f = FeetAttachTests.drawnFootFrame(r)
                let beans = r.skinner.beansActive && r.skinner.beanBlend > 0.05
                var detached = false
                if beans {
                    // (after the move the walk / run it resumes may swing a foot higher than the move's own limit: only the attachment is judged then)
                    let during = r.brain.idleState.kind == .cartwheel
                    detached = f.overlap > FeetAttachTests.minOverlap || f.radius > FeetAttachTests.maxRadius || (during && (f.centreHeight > FeetAttachTests.maxCentreHeight || f.soleRise > FeetAttachTests.maxSoleRise))
                }
                else { detached = f.stretch > FeetAttachTests.maxCoreStretch || f.overlap > FeetAttachTests.minCoreOverlap }
                v.frames += 1
                if f.overlap > v.worstOverlap && beans { v.worstOverlap = f.overlap }
                if detached {
                    bad += 1; v.bad += 1
                    if v.worst.isEmpty || bad == 1 { v.worst = String(format: "#%d %@ feat=%@ shoes=%d near=%d hitch=%d t=%.2f beans=%d gait=%@ overlap=%.3f radius=%.3f cen=%.3f sole=%.3f stretch=%.2f act=%@ kind=%@ script=%@ runW=%.2f feet=%d", n, entry, feat.rawValue, shoes ? 1 : 0, nearby ? 1 : 0, hitch ? 1 : 0, clock, beans ? 1 : 0, "\(r.brain.gait.phase)", f.overlap, f.radius, f.centreHeight, f.soleRise, f.stretch, "\(r.brain.activity)", "\(String(describing: r.brain.idleState.kind))", "\(r.brain.script)", r.brain.runW, r.brain.feet.active ? 1 : 0) }
                }
            }
            if flew { v.cartwheels += 1 } else { v.noStart += 1; v.bad -= bad; bad = 0 }          // (a start that never left the floor is not a cartwheel: the walk / run it fell back to is covered by the other suites)
            if bad > 0 { v.byEntry[entry, default: 0] += 1; MotionLog.write("CARTWHEEL BAD " + v.worst + " badFrames=\(bad)") }
            keep.removeAll()
        }
        MotionLog.write("CARTWHEEL STRESS: cartwheels=\(v.cartwheels) noStart=\(v.noStart) frames=\(v.frames) detachedFrames=\(v.bad) casesWithDetach=\(v.byEntry) worstBeanOverlap=\(v.worstOverlap)")
        return v
    }

    func testCartwheelStressNeverDetachesFeet() {
        let n = Int(ProcessInfo.processInfo.environment["CARTWHEEL_N"] ?? "") ?? 24
        let v = Self.stress(count: n, seed: 0xC0FFEE)
        XCTAssertGreaterThanOrEqual(v.cartwheels, n * 3 / 4, "most attempts started")
        XCTAssertEqual(v.bad, 0, "no detached-foot frames in \(v.cartwheels) cartwheels: \(v.worst)")
    }
}
