//
//  FocusKeepOutTests.swift
//  The close-up keeps the others roaming (W2): nobody frozen, nobody hidden, nobody in the camera's keep-out wedge once the call has cleared the way.
//

import XCTest
import simd
@testable import BobV1

@MainActor
final class FocusKeepOutTests: XCTestCase {
    nonisolated(unsafe) static var keep: [AnyObject] = []
    override func setUp() {
        RoomLayout.dynamicBoxes = []
        GameCamera.configureRoom(count: 3, option: .A, wide: 2); _ = GameCamera.camera(aspect: 440.0 / 956.0); GameCamera.refreshRoam(aspect: 440.0 / 956.0)
    }
    override func tearDown() { GameCamera.clearRoam(); GameCamera.configureRoom(count: 1); _ = GameCamera.camera(aspect: 440.0 / 956.0) }

    // MARK: geometry

    func testWedgeWidthsPortraitAndLandscape() {
        let g = FocusGroup()
        g.begin(ids: [1])
        let p = g.keepOut(aspect: 440.0 / 956.0, total: 3)!
        let w = p.halfWidth(at: GameCamera.callSpot.y, radius: 0.55)
        XCTAssertEqual(w, 1.65, accuracy: 0.15, "portrait half-width at the call spot")
        let l = g.keepOut(aspect: 956.0 / 440.0, total: 3)!
        XCTAssertGreaterThan(l.halfWidth(at: GameCamera.callSpot.y, radius: 0.55), 3.0, "landscape: the whole front band")
        XCTAssertNil(g.keepOut(aspect: 0.46, total: 1), "a lone Jelly has nobody to keep out")
        let all = FocusGroup(); all.begin(ids: [0, 1, 2])
        XCTAssertNil(all.keepOut(aspect: 0.46, total: 3), "everyone focused needs no wedge")
    }

    func testContainsAndExitRoundTrip() {
        let g = FocusGroup(); g.begin(ids: [1])
        for aspect: Float in [440.0 / 956.0, 956.0 / 440.0] {
            let k = g.keepOut(aspect: aspect, total: 3)!
            for p in [SIMD2<Float>(0, 2.2), SIMD2(0.6, 2.7), SIMD2(-1.0, 3.0), SIMD2(0.2, 2.4)] where k.contains(p, radius: 0.55) {
                let e = k.exit(p, radius: 0.55)
                XCTAssertFalse(k.contains(e, radius: 0.55), "exit of \(p) is outside (\(e))")
            }
            XCTAssertFalse(k.contains(SIMD2(0, 1.0), radius: 0.55), "well behind the Jelly is outside")
            XCTAssertTrue(k.contains(SIMD2(0, 2.9), radius: 0.55), "between the camera and the Jelly is inside")
        }
    }

    // MARK: the room

    private func lively(_ r: FocusAnyRun) {
        for a in r.actors {
            let b = a.brain!
            b.anticsEnabled = true; b.watching = true; b.autonomy = true
            b.idleState.cooldown = 2; b.restTimer = 0.5; b.socialBook.cooldown = 1e6
        }
    }

    func testOthersKeepRoamingAndStayOutOfTheWedge() {
        let r = FocusAnyRun(peers: true); Self.keep.append(r)
        lively(r)
        r.run(1.0)
        r.care.comeHere(jelly: 1)
        XCTAssertTrue(r.run(30) { r.care.focus.isFocused }, "Pip arrives: phase \(r.care.focus.phase)")
        let t0 = [0, 2].map { r.actors[$0].floor }
        var travelled: [Float] = [0, 0]
        var last = t0
        var inside = 0, frames = 0
        let callSpot = GameCamera.callSpot
        for f in 0..<(40 * 60) {
            r.tick()
            for (k, id) in [0, 2].enumerated() {
                let p = r.actors[id].floor
                travelled[k] += simd_distance(p, last[k]); last[k] = p
                if f > 4 * 60, let ko = r.care.focusKeepOutFor(id) { frames += 1; if ko.contains(p, radius: 0) { inside += 1 } }
            }
        }
        XCTAssertTrue(r.care.focus.isFocused)
        for id in [0, 2] {
            let b = r.actors[id].brain!
            XCTAssertTrue(b.autonomy && !b.idleBlocked && !b.focusPaused, "Jelly \(id) is not frozen")
        }
        XCTAssertGreaterThan(travelled[0], 2.0, "Bob roamed \(travelled[0])"); XCTAssertGreaterThan(travelled[1], 2.0, "Lavender roamed \(travelled[1])")
        XCTAssertGreaterThan(frames, 1000)
        XCTAssertEqual(inside, 0, "no frame with a centre inside the wedge")
        XCTAssertLessThan(simd_distance(r.actors[1].floor, callSpot), 0.5, "Pip stays on his spot")
    }

    func testAJellyStandingInTheWedgeWalksOut() {
        let r = FocusAnyRun(peers: true); Self.keep.append(r)
        lively(r)
        r.run(0.5)
        r.place(2, at: GameCamera.callSpot + SIMD2(0.6, 0.3), rest: 0.5)
        r.care.comeHere(jelly: 1)
        let ko = r.care.focusKeepOutFor(2)!
        XCTAssertTrue(ko.contains(r.actors[2].floor, radius: 0), "Lavender starts inside the wedge")
        XCTAssertTrue(r.run(8) { !ko.contains(r.actors[2].floor, radius: 0.3) }, "Lavender is out within 8 s: \(r.actors[2].floor)")
        XCTAssertTrue(r.run(30) { r.care.focus.isFocused }, "and Pip still arrives")
    }

    func testLandscapeWedgeLeavesTheFrontBandEmpty() {
        _ = GameCamera.camera(aspect: 956.0 / 440.0); GameCamera.refreshRoam(aspect: 956.0 / 440.0)
        defer { _ = GameCamera.camera(aspect: 440.0 / 956.0); GameCamera.refreshRoam(aspect: 440.0 / 956.0) }
        let r = FocusAnyRun(peers: true); Self.keep.append(r)
        lively(r)
        r.run(1.0)
        r.care.comeHere(jelly: 1)
        XCTAssertTrue(r.run(30) { r.care.focus.isFocused })
        var inside = 0
        for f in 0..<(15 * 60) { r.tick(); if f > 5 * 60 { for id in [0, 2] where r.care.focusKeepOutFor(id)?.contains(r.actors[id].floor, radius: 0) == true { inside += 1 } } }
        XCTAssertEqual(inside, 0)
    }
}
