//
//  TouchGrumpyTests.swift
//  A grumpy Blob does not enjoy being touched (docs/Emotions.md): pet, cheeks and pick up get the annoyed reaction (lean away, squint, a short
//  "hmph" squash, short stiff haptics, no purr, no hearts) unless attention is the very thing he wants. When his mood recovers the next touch is
//  happy again. Also: the one-Blob highlight outline is his real projected outline when the stage publishes it.
//

import XCTest
import simd
@testable import BobV1

@MainActor
final class TouchGrumpyTests: XCTestCase {
    typealias Run = TouchPetTests.Run
    let eye = SIMD3<Float>(0, 0.9, 6)

    private func stroke(_ r: Run, _ s: Float = 4) { r.stroke(s, eye: eye, amp: 0.12, hz: 1.2, y: 0.15, cx: 0.38) }   // the plain-stroke area, finger on the +x side

    func testHappyBlobGetsTextureAndPurr() {
        let r = Run()
        r.play.mood = .happy
        stroke(r)
        let pet = r.rec.events(.continuous, channel: "pet")
        XCTAssertGreaterThan(pet.map { $0.intensity }.max() ?? 0, 0.3, "soft texture")
        XCTAssertLessThanOrEqual(pet.map { $0.sharpness }.max() ?? 1, 0.31)
        XCTAssertTrue(r.play.isPurring)
        XCTAssertGreaterThan(r.play.love, 0.9)
        XCTAssertLessThan(r.rig.brain.touchRoll, 0, "leans INTO a finger on the +x side")
        XCTAssertEqual(r.play.hmphs, 0)
    }

    func testGrumpyBlobGetsAShortStiffAnnoyedReaction() {
        let r = Run()
        r.play.mood = .grumpy; r.play.attentionWanted = false
        XCTAssertTrue(r.play.annoyed)
        var maxRoll: Float = 0, maxPitch: Float = 0, minSquash: Float = 1
        for k in 0..<240 {
            r.frame(r.ray(localX: 0.38 + 0.12 * sinf(2 * .pi * 1.2 * Float(k) / 60), localY: 0.15, eye: eye))
            maxRoll = max(maxRoll, r.rig.brain.touchRoll); maxPitch = max(maxPitch, r.rig.brain.touchPitch); minSquash = min(minSquash, r.rig.brain.touchSquash)
        }
        XCTAssertGreaterThanOrEqual(r.play.hmphs, 1, "an hmph on touchdown")
        XCTAssertLessThan(minSquash, 0.97, "a quick squash puff")
        XCTAssertGreaterThan(maxRoll, 0.08, "leans AWAY from a finger on the +x side")
        XCTAssertGreaterThan(maxPitch, 0.05, "head down: the flat brows read angry")
        XCTAssertLessThan(r.rig.skinner.eyeHeight.left, 0.7, "grumpy squint")
        // stiff and short: no soft texture, only sharp ticks
        XCTAssertLessThan(r.rec.events(.continuous, channel: "pet").map { $0.intensity }.max() ?? 0, 0.01, "no texture")
        let tr = r.rec.events(.transient)
        XCTAssertFalse(tr.isEmpty)
        XCTAssertTrue(tr.allSatisfy { $0.sharpness >= 0.9 }, "every transient is crisp and stiff")
        XCTAssertGreaterThanOrEqual(tr.first?.sharpness ?? 0, 0.95)
        XCTAssertFalse(r.play.isPurring, "no purr")
        XCTAssertEqual(r.play.love, 0, "not happy")
        XCTAssertTrue(r.play.hearts.isEmpty, "no hearts")
        // petting still counts for the needs model (contact + speed are read by GameCare)
        XCTAssertTrue(r.play.contact)
        // and it all lets go
        r.idle(2)
        XCTAssertEqual(r.rig.brain.touchRoll, 0, accuracy: 1e-3)
        XCTAssertEqual(r.rig.brain.touchSquash, 1, accuracy: 1e-3)
        XCTAssertEqual(r.rig.skinner.eyeHeight.left, 1, accuracy: 0.05)
    }

    func testWantingAttentionMakesPettingWelcomeEvenWhenGrumpy() {
        let r = Run()
        r.play.mood = .grumpy; r.play.attentionWanted = true
        XCTAssertFalse(r.play.annoyed)
        stroke(r)
        XCTAssertTrue(r.play.isPurring)
        XCTAssertGreaterThan(r.play.love, 0.9)
        XCTAssertEqual(r.play.hmphs, 0)
    }

    func testWhenTheMoodRecoversTheNextTouchIsHappyAgain() {
        let r = Run()
        r.play.mood = .grumpy
        stroke(r, 1.5)
        XCTAssertGreaterThanOrEqual(r.play.hmphs, 1)
        r.idle(1.5)
        r.play.mood = .okay
        let before = r.play.hmphs
        stroke(r, 4)
        XCTAssertEqual(r.play.hmphs, before, "no more hmph")
        XCTAssertGreaterThan(r.play.love, 0.9)
        XCTAssertTrue(r.play.isPurring)
        XCTAssertGreaterThan(r.rec.events(.continuous, channel: "pet").map { $0.intensity }.max() ?? 0, 0.3)
    }

    func testGrumpyCheeksAndPickUp() {
        // cheeks: a stiff tick instead of the soft press and the bloop
        let r = Run()
        r.play.mood = .grumpy
        func frame(_ rays: [(o: SIMD3<Float>, d: SIMD3<Float>)]?, gap: Float) {
            r.play.cheeksFrame(dt: 1.0 / 60, now: r.clock, rays: rays, gap: gap, sim: r.rig.sim, brain: r.rig.brain, skinner: r.rig.skinner, surface: r.surface)
            r.rig.tick(); r.clock += 1.0 / 60
        }
        for k in 0..<60 { let g = 0.5 - 0.3 * Float(k) / 60; frame([r.ray(localX: -g, localY: 0.25, eye: eye), r.ray(localX: g, localY: 0.25, eye: eye)], gap: g * 400) }
        for _ in 0..<30 { frame([r.ray(localX: -0.2, localY: 0.25, eye: eye), r.ray(localX: 0.2, localY: 0.25, eye: eye)], gap: 80) }
        frame(nil, gap: 0)
        XCTAssertLessThan(r.rec.events(.continuous, channel: "squish").map { $0.intensity }.max() ?? 0, 0.01, "no soft press")
        XCTAssertTrue(r.rec.events(.transient).allSatisfy { $0.sharpness >= 0.9 })
        XCTAssertTrue(r.rec.events(.wobble).isEmpty, "no bloop rumble")
        XCTAssertGreaterThanOrEqual(r.play.hmphs, 2)

        // pick up: no excited flapping, a stiff hmph instead
        let h = TouchPlayTests.Rig()
        h.play.mood = .grumpy
        let sim = h.rig.sim, brain = h.rig.brain, sk = h.rig.skinner
        h.step(touched: true)
        var apex = 0, top: Float = -1
        for i in 0..<sim.n where sim.x[3 * i + 1] > top { top = sim.x[3 * i + 1]; apex = i }
        let hit = SIMD3(sim.x[3 * apex], sim.x[3 * apex + 1], sim.x[3 * apex + 2])
        sim.beginGrab(hit: hit, radius: 0.4)
        for k in 0..<90 {
            let lift = min(0.4, 0.4 * Float(k) / 60)
            h.step(touched: true) {
                sim.moveGrab(target: hit + SIMD3(0, lift, 0), rot: nil)
                h.play.heldFrame(dt: 1.0 / 60, now: h.clock, grabbing: true, liftHeight: lift, sim: sim, brain: brain, skinner: sk)
            }
        }
        XCTAssertEqual(h.play.excitement, 0, "no happy flapping when grumpy")
        XCTAssertFalse(brain.excitedOn)
        XCTAssertGreaterThanOrEqual(h.play.hmphs, 1)
        XCTAssertTrue(h.rec.events(.transient).allSatisfy { $0.sharpness >= 0.9 })
        XCTAssertLessThan(sk.eyeHeight.left, 0.7, "grumpy squint while held")
    }

    /// One Blob, a highlight is up: the stage publishes his real projected outline and the painter prefers it to the body-profile fallback.
    func testOneBlobHighlightUsesTheRealOutline() {
        let s = BlobSelect()
        XCTAssertEqual(s.count, 1)
        s.highlight(0)
        XCTAssertTrue(s.isSelecting)
        XCTAssertFalse(s.hasLiveOutline)
        let size = CGSize(width: 400, height: 860)
        let cam = GameCamera.camera(aspect: Float(size.width / size.height), focus: 0)
        // a distinctive "real" silhouette: a wide ellipse in the middle of the screen
        let pts = (0..<200).map { k -> CGPoint in let a = Double(k) / 200 * 2 * .pi; return CGPoint(x: 200 + 90 * cos(a), y: 500 + 70 * sin(a)) }
        s.publish(viewProj: cam.viewProj, size: size) { pts }
        XCTAssertTrue(s.hasLiveOutline)
        let o = s.outlines[0] ?? []
        XCTAssertGreaterThan(o.count, 8)
        XCTAssertEqual(o.map(\.x).min() ?? 0, 110, accuracy: 3)
        XCTAssertEqual(o.map(\.x).max() ?? 0, 290, accuracy: 3)
        // (there is no profile fallback any more: nothing but the stage writes his outline)
        // with no highlight a single Blob publishes nothing (no per-frame cost)
        let t = BlobSelect(); t.publish(viewProj: cam.viewProj, size: size) { pts }
        XCTAssertNil(t.outlines[0])
    }
}
