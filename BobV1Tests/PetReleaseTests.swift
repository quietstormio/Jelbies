//
//  PetReleaseTests.swift
//  Petting in the close-up, then "Let go": the Jelbie who was cuddled walks off and lives his normal idle life again within a couple of seconds
//  (one called, or everybody called). Runs the mini stage of FocusAnyJellyTests with a real TouchPlay stroking the touched Jelbie, like the stage's touch tick.
//

import XCTest
import simd
@testable import BobV1

@MainActor
final class PetReleaseTests: XCTestCase {
    nonisolated(unsafe) static var keep: [AnyObject] = []

    /// The mini stage plus the stage's touch tick for the Jelbie under the finger: stroke while `focused` and `stroking`, let go of the touch when the close-up ends.
    @MainActor final class Rig {
        let r: FocusAnyRun
        let play = TouchPlay(haptics: nil)
        let rs = RestSurface(mesh: MotionRig.renderMesh)
        var clock = 100.0
        var stroking = false
        var t: Float = 0
        init(peers: Bool = true) {
            r = FocusAnyRun(peers: peers)
            r.care.touchPlay = play
        }
        var care: GameCare { r.care }
        func tick() {
            let id = care.focusGroup.touchID
            let a = r.actors[id]
            let dt: Float = 1.0 / 60
            if care.focus.isFocused {
                var ray: (o: SIMD3<Float>, d: SIMD3<Float>)?
                if stroking {
                    t += dt
                    let e = BodyEllipsoid(sim: a.sim)
                    let p = e.center + e.rot.act(SIMD3(0.35 * sinf(2 * .pi * 1.2 * t), 0, 0))
                    let eye = SIMD3<Float>(0, 0.9, 8)
                    ray = (eye, simd_normalize(p - eye))
                }
                play.petFrame(dt: dt, now: clock, ray: ray, screen: ray == nil ? nil : SIMD2(0.5, 0.5), sim: a.sim, brain: a.brain, skinner: a.skinner, surface: nil)
            } else if !play.holdsBrain { play.cancel(sim: a.sim, brain: a.brain, skinner: a.skinner) }
            r.tick()
            clock += Double(dt)
        }
        func run(_ s: Float, until: (() -> Bool)? = nil) { for _ in 0..<Int(s * 60) { tick(); if until?() == true { return } } }
    }

    /// Seconds after the let-go until each Jelbie is first seen walking (nil = not within `seconds`).
    private func firstWalk(_ rig: Rig, ids: [Int], seconds: Float) -> [Int: Float?] {
        var at: [Int: Float?] = [:]
        for id in ids { at[id] = .some(nil) }
        for k in 0..<Int(seconds * 60) {
            rig.tick()
            for id in ids where at[id]! == nil && rig.r.actors[id].brain!.activity == .walking { at[id] = .some(Float(k) / 60) }
        }
        return at
    }

    /// One Jelbie called, cuddled by touch, let go: he is walking about again within a few seconds, and nothing of the close-up or the touch is left on his brain.
    func testCuddledJelbieWalksOffAfterLetGo() { cuddleAndLetGo(jelly: 1, walks: true); cuddleAndLetGo(jelly: 0, walks: false) }

    /// `walks`: also wait for him to be seen walking (Jelbie 0 stands at the front edge of the mini stage's floor, where his wander picks are often dragged back onto his own spot).
    private func cuddleAndLetGo(jelly id: Int, walks: Bool) {
        let rig = Rig(); Self.keep.append(rig)
        rig.run(1.5)
        rig.care.comeHere(jelly: id)
        rig.run(30) { rig.care.focus.isFocused }
        XCTAssertTrue(rig.care.focus.isFocused)
        rig.stroking = true
        rig.run(6)
        XCTAssertGreaterThan(rig.play.love, 0.5, "the cuddle took")
        rig.stroking = false
        rig.care.release()
        rig.run(10) { rig.care.focus.phase == .roaming }
        XCTAssertEqual(rig.care.focus.phase, .roaming)
        rig.run(0.1)
        let b = rig.r.actors[id].brain!
        XCTAssertTrue(b.autonomy, "his wandering is handed back")
        XCTAssertFalse(b.held, "no held / reserved flag left")
        XCTAssertFalse(b.commanded)
        guard walks else { return }
        let walk = firstWalk(rig, ids: [id], seconds: 8)
        XCTAssertNotNil(walk[id]!, "Jelbie \(id) walked off within 8 s of the let-go")
    }

    /// Everybody called and cuddled, then all let go: every one of them walks off.
    func testEveryoneWalksOffAfterAGroupLetGo() {
        let rig = Rig(); Self.keep.append(rig)
        rig.run(1.5)
        rig.care.comeHereEveryone()
        rig.run(40) { rig.care.focus.isFocused }
        XCTAssertTrue(rig.care.focus.isFocused)
        rig.stroking = true
        rig.run(4)
        rig.stroking = false
        rig.care.release()
        rig.run(10) { rig.care.focus.phase == .roaming }
        XCTAssertEqual(rig.care.focus.phase, .roaming)
        rig.run(0.1)
        for a in rig.r.actors { XCTAssertTrue(a.brain!.autonomy, "Jelbie \(a.id) wanders again"); XCTAssertFalse(a.brain!.held) }
        let walk = firstWalk(rig, ids: [0, 1, 2], seconds: 8)
        for id in 0..<3 { XCTAssertNotNil(walk[id]!, "Jelbie \(id) walked off within 8 s of the let-go") }
    }
}
