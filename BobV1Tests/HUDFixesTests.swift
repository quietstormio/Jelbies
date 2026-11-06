//
//  HUDFixesTests.swift
//  Feed row lists only owned foods (an empty bag shows the one short line); the close-up's "too hungry to cuddle" notice follows the cuddle gate.
//

import XCTest
import simd
@testable import BobV1

@MainActor
final class HUDFixesTests: XCTestCase {
    nonisolated(unsafe) static var keep: [AnyObject] = []

    func testFeedRowListsOnlyOwnedFoods() {
        XCTAssertEqual(CareMenu.feedRowIDs(bag: ["popsicle": 3, "cookie": 2, "berries": 0, "pizza": 0]), ["popsicle", "cookie"], "exactly the ice pop and the cookie, in shop order")
    }

    func testEmptyBagListsNothingAndHasTheLine() {
        XCTAssertEqual(CareMenu.feedRowIDs(bag: ["berries": 0, "pizza": 0]), [])
        XCTAssertEqual(CareMenu.feedRowIDs(bag: [:]), [])
        XCTAssertEqual(CareMenu.noFoodLine, "No food. Visit the store.")
    }

    func testCuddleLineFollowsTheGate() {
        // blocked by hunger / thirst / both
        XCTAssertEqual(GameCare.cuddleBlockLine(name: "Teddy", mood: .grumpy, wanted: .hunger, hungry: true, thirsty: false), "Teddy is too hungry to cuddle")
        XCTAssertEqual(GameCare.cuddleBlockLine(name: "Teddy", mood: .grumpy, wanted: .thirst, hungry: false, thirsty: true), "Teddy is too thirsty to cuddle")
        XCTAssertEqual(GameCare.cuddleBlockLine(name: "Teddy", mood: .grumpy, wanted: .hunger, hungry: true, thirsty: true), "Teddy is too hungry and thirsty to cuddle")
        // not blocked: happy / okay, or love is exactly what he wants
        XCTAssertNil(GameCare.cuddleBlockLine(name: "Teddy", mood: .happy, wanted: nil, hungry: false, thirsty: false))
        XCTAssertNil(GameCare.cuddleBlockLine(name: "Teddy", mood: .okay, wanted: nil, hungry: false, thirsty: false))
        XCTAssertNil(GameCare.cuddleBlockLine(name: "Teddy", mood: .grumpy, wanted: .attention, hungry: false, thirsty: false))
    }

    func testNoticeShowsInTheCloseUpWhileHungryAndClearsWhenFed() {
        let c = GameCare(jellyCount: 1, persistent: false, defaults: UserDefaults(suiteName: "HUDFixes.1")!)
        Self.keep.append(c)
        c.focus.force(.focused); c.focusGroup.begin(ids: [0])
        c.needs(for: 0).set(.hunger, 0.1); c.needs(for: 0).set(.thirst, 1); c.needs(for: 0).set(.attention, 1)
        XCTAssertEqual(c.cuddleNotices.count, 1); XCTAssertTrue(c.cuddleNotices[0].hasSuffix("is too hungry to cuddle"), c.cuddleNotices.first ?? "")
        c.needs(for: 0).set(.hunger, 1)
        XCTAssertEqual(c.cuddleNotices, [], "need met: the notice is gone")
        c.needs(for: 0).set(.thirst, 0.1)
        XCTAssertEqual(c.cuddleNotices.count, 1)
        c.focus.force(.roaming)
        XCTAssertEqual(c.cuddleNotices, [], "no notice outside the close-up")
    }

    /// The group close-up frames where the bodies really stand (wider than the slots), every body fully inside with a margin, portrait and landscape.
    func testGroupCloseUpFramesEveryBodyPortraitAndLandscape() {
        let saved = (GameCamera.focusSpots, GameCamera.focusFramed, GameCamera.aspect)
        defer { GameCamera.focusSpots = saved.0; GameCamera.focusFramed = saved.1; GameCamera.aspect = saved.2 }
        for n in [2, 3] {
            let slots = GameCamera.focusRowSpots(count: n)
            GameCamera.focusSpots = slots
            let bodies = slots.map { SIMD2<Float>($0.x * 1.4 - 0.3, $0.y + 0.2) }          // they stopped off their slots, further out
            GameCamera.focusFramed = bodies
            for aspect in [Float(0.46), 2.16] {
                let vp = GameCamera.camera(aspect: aspect, focus: 1).viewProj
                for b in bodies { for dx in [-BobShape.R, BobShape.R] { for y in [Float(0), Float(BobShape.H)] {
                    let q = vp * SIMD4<Float>(b.x + dx, y, b.y, 1)
                    XCTAssertLessThan(abs(q.x / q.w), 0.94, "n=\(n) aspect \(aspect): body edge inside the width with a margin")
                    XCTAssertLessThan(abs(q.y / q.w), 0.94, "n=\(n) aspect \(aspect): body inside the height")
                } } }
            }
        }
        // one Jelbie keeps today's single close-up exactly
        GameCamera.focusSpots = [GameCamera.callSpot]; GameCamera.focusFramed = []
        let one = GameCamera.camera(aspect: 0.46, focus: 1).pos, ref = GameCamera.focusPose(aspect: 0.46).eye
        XCTAssertEqual(simd_distance(one, ref), 0, accuracy: 1e-4)
    }
}
