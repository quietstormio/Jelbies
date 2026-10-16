//
//  MotionScenarios.swift
//  The scripted scenarios the motion suites run (studio brain unless noted), each returning the per-step samples.
//

import XCTest
import simd
@testable import BobV1

@MainActor
enum MotionScenario {
    static let tol: Float = 0.02 * MotionRig.H      // grounded tolerance: 0.02 H above the floor

    static func wave(side: Int, game: Bool) -> (MotionRig, [MotionSample]) {
        let r = MotionRig(game: game)
        UserDefaults.standard.set(side > 0 ? 1 : 0, forKey: "BlobWaveSide")
        defer { UserDefaults.standard.removeObject(forKey: "BlobWaveSide") }
        r.brain.request(.wave)
        var started = false
        let s = r.record(5) { if r.brain.activity == .waving { started = true }; return started && r.brain.activity != .waving }
        return (r, s)
    }
    static func walk(game: Bool) -> (MotionRig, [MotionSample]) {
        let r = MotionRig(game: game)
        r.brain.request(.goTo(game ? SIMD2(1.6, 0.4) : r.root + SIMD2(1.4, 0.6)))
        var moved = false
        let s = r.record(9) { if r.brain.activity == .walking { moved = true }; return moved && r.brain.activity == .idle }
        return (r, s)
    }
    static func step(game: Bool = false) -> (MotionRig, [MotionSample]) {
        let r = MotionRig(game: game)
        r.brain.startStepping(seconds: 4, sim: r.sim)
        let s = r.record(7) { r.brain.activity == .idle && r.t > 1.5 }
        return (r, s)
    }
    static func turn(game: Bool = false, by: Float = 2.4) -> (MotionRig, [MotionSample]) {
        let r = MotionRig(game: game)
        r.brain.startTurn(to: r.poseYaw + by, sim: r.sim)
        let s = r.record(5) { r.brain.activity == .idle && r.t > 1.5 }
        return (r, s)
    }
    /// Game: walk toward the camera (Call), stepped turn, wave.
    static func call() -> (MotionRig, [MotionSample]) {
        let r = MotionRig(game: true)
        r.brain.requestNow(.come(to: SIMD2(0.0, 1.4)))
        var waved = false
        let s = r.record(14) { if r.brain.isWaving { waved = true }; return waved && r.brain.activity == .idle }
        return (r, s)
    }
    static func spin() -> (MotionRig, [MotionSample]) {
        let r = MotionRig(game: false)
        r.brain.startSpin(sim: r.sim)
        return (r, r.record(2.5))
    }
    static func eat() -> (MotionRig, [MotionSample]) {
        let r = MotionRig(game: false)
        var done = false
        r.brain.onFinished = { _ in done = true }
        r.brain.request(.eat(at: SIMD2(0.6, -0.5)))
        let s = r.record(16) { done }
        return (r, s)
    }
    static func idle(game: Bool) -> (MotionRig, [MotionSample]) {
        let r = MotionRig(game: game)
        return (r, r.record(2))
    }
}

extension Array where Element == MotionSample {
    func maxGap() -> Float { map { Swift.min($0.gap[0], $0.gap[1]) }.max() ?? 0 }
}
