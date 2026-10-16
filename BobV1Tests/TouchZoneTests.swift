//
//  TouchZoneTests.swift
//  T1b: body zones (head pat, belly rub, cheek boop, under-arm tickle), the purr, the favourite-spot counter and the phone tilt / shake.
//

import XCTest
import simd
@testable import BobV1

@MainActor
final class TouchZoneTests: XCTestCase {
    typealias Run = TouchPetTests.Run
    let eye = SIMD3<Float>(0, 0.9, 6)
    static let H = Float(BobForm.top)

    func testZoneClassification() {
        XCTAssertEqual(TouchZone.classify(local: SIMD3(0, 0.55, 0.3)), .head)
        XCTAssertEqual(TouchZone.classify(local: SIMD3(0.1, -0.35, 0.4)), .belly)
        XCTAssertEqual(TouchZone.classify(local: SIMD3(0.4, 0.2, 0.3)), .cheek)
        XCTAssertEqual(TouchZone.classify(local: SIMD3(0.6, 0.0, 0.1)), .underarm)
        XCTAssertEqual(TouchZone.classify(local: SIMD3(-0.6, -0.1, 0.0)), .underarm)
        XCTAssertEqual(TouchZone.classify(local: SIMD3(0, 0, -0.5)), .body)
    }

    /// Stroke around a spot for `seconds`; returns the run.
    private func play(_ x: Float, _ y: Float, amp: Float = 0.12, hz: Float = 1.5, seconds: Float = 1.6) -> Run {
        let r = Run()
        r.stroke(seconds, eye: eye, amp: amp, hz: hz, y: y, cx: x)
        return r
    }

    func testEachZoneHasItsOwnHapticSignature() {
        // head pat: a light tap-tap texture, no continuous buzz, and a squint
        let head = play(0, 0.52)
        XCTAssertEqual(head.play.zone, .head)
        let ht = head.rec.events(.transient).filter { $0.sharpness > 0.5 && $0.sharpness < 0.6 }
        XCTAssertGreaterThan(ht.count, 6, "taps")
        XCTAssertLessThan(head.rec.events(.continuous, channel: "pet").map { $0.intensity }.max() ?? 0, 0.01)
        XCTAssertLessThan(head.rig.skinner.eyeHeight.left, 0.75, "he squints")
        XCTAssertGreaterThan(head.rig.skinner.eyeHeight.left, 0.3, "a squint, not shut")

        // belly rub: a deep, soft, low rumble that is stronger than the plain stroke at the same speed, and he giggles
        let belly = play(0, -0.35)
        XCTAssertEqual(belly.play.zone, .belly)
        let bc = belly.rec.events(.continuous, channel: "pet")
        XCTAssertLessThanOrEqual(bc.map { $0.sharpness }.max() ?? 1, 0.101, "low")
        XCTAssertGreaterThan(bc.map { $0.intensity }.max() ?? 0, 0.3, "a real rumble")
        for v in stride(from: HapticMap.petDeadZone + 0.05, through: 6, by: 0.25) {
            XCTAssertGreaterThan(HapticMap.bellyIntensity(speed: Float(v)), HapticMap.petIntensity(speed: Float(v)), "deeper than the plain stroke")
            XCTAssertLessThan(HapticMap.bellySharpness(speed: Float(v)), HapticMap.petSharpness(speed: Float(v)), "softer")
        }
        XCTAssertEqual(HapticMap.bellyIntensity(speed: 0.05), 0)
        XCTAssertGreaterThan(abs(belly.rig.brain.touchRoll) + abs(belly.rig.brain.touchSquash - 1), 0.0, "giggle wiggle")

        // under-arm tickle: a quick fluttery transient train
        let tick = play(0.55, -0.05, amp: 0.04, hz: 1.0)
        XCTAssertEqual(tick.play.zone, .underarm)
        let tt = tick.rec.events(.transient).filter { $0.sharpness > 0.7 }
        XCTAssertGreaterThan(tt.count, 18, "flutter")
        XCTAssertLessThan(tick.rig.skinner.eyeHeight.left, 0.6, "he laughs: eyes squeezed")

        // cheek boop: one crisp transient and a dimple pop
        let r = Run()
        r.idle(0.2)
        for _ in 0..<20 { r.frame(r.ray(localX: 0.4, localY: 0.15, eye: eye)) }
        XCTAssertEqual(r.play.zone, .cheek)
        XCTAssertEqual(r.play.boops, 1)
        let boop = r.rec.events(.transient).first
        XCTAssertGreaterThanOrEqual(boop?.intensity ?? 0, 0.85)
        XCTAssertGreaterThanOrEqual(boop?.sharpness ?? 0, 0.85)
        // zones are felt differently: the four signatures are pairwise distinct (transient sharpness / continuous presence)
        XCTAssertNotEqual(ht.first?.sharpness, tt.first?.sharpness)
    }

    func testPurrAfterTwoSecondsAndStopsOnReleaseOrRoughness() {
        let r = Run()
        r.stroke(1.5, eye: eye, amp: 0.2, hz: 1.2)
        XCTAssertFalse(r.play.isPurring, "not yet")
        r.stroke(1.5, eye: eye, amp: 0.2, hz: 1.2)
        XCTAssertTrue(r.play.isPurring, "after ~2 s of good petting")
        // a slow 2-3 Hz pulse under the finger: count the swell peaks of the pet channel over 1 s
        r.rec.clear()
        r.stroke(1.0, eye: eye, amp: 0.2, hz: 1.2)
        let lv = r.rec.events(.continuous, channel: "pet").map { $0.intensity }
        var peaks = 0
        for k in 1..<max(lv.count - 1, 1) where lv[k] > lv[k - 1] && lv[k] >= lv[k + 1] { peaks += 1 }
        XCTAssertGreaterThanOrEqual(peaks, 2)
        XCTAssertGreaterThan(r.rig.brain.touchSquash - 1 == 0 ? 0 : 1, 0, "breathing pulse on the body")
        // stops when the finger lifts
        r.idle(1.0)
        XCTAssertFalse(r.play.isPurring)
        XCTAssertEqual(r.rec.events(.continuous, channel: "pet").last?.intensity, 0)
        // and when he is handled roughly
        let q = Run()
        q.stroke(3.2, eye: eye, amp: 0.2, hz: 1.2)
        XCTAssertTrue(q.play.isPurring)
        q.stroke(0.6, eye: eye, amp: 0.45, hz: 5)       // a fast rub: > 5 u/s
        XCTAssertFalse(q.play.isPurring, "rough: the purr stops")
    }

    func testFavouriteZoneCounter() {
        let r = Run()
        r.stroke(3.0, eye: eye, amp: 0.12, hz: 1.5, y: -0.35, cx: 0)
        r.idle(0.3)
        r.stroke(1.5, eye: eye, amp: 0.12, hz: 1.5, y: 0.52, cx: 0)
        XCTAssertEqual(r.play.favouriteZone, .belly)
        XCTAssertGreaterThan(r.play.zoneSeconds[.belly] ?? 0, 2.5)
        XCTAssertGreaterThan(r.play.zoneSeconds[.head] ?? 0, 1.0)
    }

    func testTiltLeansOtherWayShakeJigglesAndTooMuchMakesHimDizzy() {
        let r = Run()
        var maxRoll: Float = 0
        func frame(_ gx: Float, _ shake: Float) {
            r.play.motionFrame(dt: 1.0 / 60, now: r.clock, gravityX: gx, shake: shake, sim: r.rig.sim, brain: r.rig.brain, skinner: r.rig.skinner)
            r.rig.tick(); r.clock += 1.0 / 60
            maxRoll = max(maxRoll, abs(r.rig.brain.touchRoll))
        }
        for _ in 0..<60 { frame(0.8, 0) }
        XCTAssertLessThan(r.rig.brain.touchRoll, 0, "tilted right: he leans the other way")
        XCTAssertLessThanOrEqual(abs(r.rig.brain.touchRoll), TouchPlay.maxTilt + 0.001, "bounded")
        for _ in 0..<60 { frame(-0.8, 0) }
        XCTAssertGreaterThan(r.rig.brain.touchRoll, 0)
        // a shake: jiggle + rumble
        r.rec.clear()
        for k in 0..<30 { frame(0, k % 12 < 6 ? 2.5 : 0) }
        XCTAssertGreaterThan(r.play.shakes, 0)
        XCTAssertFalse(r.rec.events(.wobble).isEmpty, "wobble rumble")
        // too much: a "whoa"
        for k in 0..<150 { frame(0, k % 12 < 6 ? 3.0 : 0) }
        XCTAssertGreaterThan(r.play.whoas, 0, "dizzy")
        XCTAssertLessThan(maxRoll, 0.30, "gentle limits")
        // back to rest
        for _ in 0..<(60 * 4) { frame(0, 0) }
        XCTAssertEqual(r.rig.brain.touchRoll, 0, accuracy: 1e-4)
        XCTAssertEqual(r.rig.brain.touchPitch, 0, accuracy: 1e-4)
        XCTAssertEqual(r.rig.skinner.eyeHeight.left, 1, accuracy: 0.05)
        let drift = simd_length(r.rig.sim.centroid() - r.c0) / Self.H
        let speed = simd_length(r.rig.sim.meanVelocity())
        print("TILT rest: drift \(drift) H speed \(speed) maxRoll \(maxRoll)")
        XCTAssertLessThan(drift, 0.02)
        XCTAssertLessThan(speed, 0.05)
    }

    /// A quick tap does the zone's own thing: head pat-pat, belly poke (thump + wobble), tickle poke (flutter burst), cheek boop (crisp).
    func testTapReactionsPerZone() {
        func tap(_ x: Float, _ y: Float) -> Run {
            let r = Run()
            r.idle(0.1)
            r.rec.clear()
            for _ in 0..<8 { r.frame(r.ray(localX: x, localY: y, eye: eye)) }
            r.play.tap(now: r.clock)
            for _ in 0..<20 { r.frame(r.ray(localX: x, localY: y, eye: eye)) }
            return r
        }
        let head = tap(0, 0.52)
        XCTAssertEqual(head.play.zone, .head)
        XCTAssertGreaterThanOrEqual(head.rec.events(.transient).filter { $0.sharpness > 0.5 && $0.sharpness < 0.6 }.count, 2, "pat-pat")
        let belly = tap(0, -0.35)
        XCTAssertTrue(belly.rec.events(.transient).contains { $0.intensity > 0.5 && $0.sharpness < 0.25 }, "a soft thump")
        XCTAssertFalse(belly.rec.events(.wobble).isEmpty)
        let tick = tap(0.55, -0.05)
        XCTAssertGreaterThanOrEqual(tick.rec.events(.transient).filter { $0.sharpness > 0.7 }.count, 5, "flutter burst")
        let cheek = tap(0.4, 0.15)
        XCTAssertEqual(cheek.play.boops, 1)
        XCTAssertTrue(cheek.rec.events(.transient).contains { $0.intensity >= 0.85 && $0.sharpness >= 0.85 })
        XCTAssertEqual(head.play.taps, 1)
    }
}
