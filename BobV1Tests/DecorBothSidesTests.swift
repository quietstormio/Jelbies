//
//  DecorBothSidesTests.swift
//  Big decor (the slide, the mini goal) can be placed on the right of the floor as well as the left, in every room, in portrait and landscape.
//

import XCTest
import simd
@testable import BobV1

@MainActor
final class DecorBothSidesTests: XCTestCase {
    override func tearDown() {
        RoomLayout.apply(RoomCatalog.home)
        GameCamera.configureRoom(count: 1); _ = GameCamera.camera(aspect: 440.0 / 956.0)
    }

    /// The reach (largest |x|) of valid spots on each side, scanning the floor.
    private func reach(_ k: DecorKind) -> (left: Float, right: Float) {
        var l: Float = 0, r: Float = 0
        var z: Float = DecorPlacement.minZ
        while z <= DecorPlacement.maxZ {
            var x: Float = -5
            while x <= 5 {
                if DecorPlacement.isValid(k, at: SIMD2(x, z), among: []) { if x < 0 { l = max(l, -x) } else { r = max(r, x) } }
                x += 0.1
            }
            z += 0.1
        }
        return (l, r)
    }

    /// Slide and goal, every room, portrait (three Jelbies: the wide camera) and landscape: a lane at least `minLane` wide on BOTH sides of the core.
    func testBigPiecesReachBothSidesInEveryRoomAndOrientation() {
        for def in RoomCatalog.all {
            for (name, aspect) in [("portrait", Float(440.0 / 956.0)), ("landscape", Float(2.16))] {
                RoomLayout.apply(def)
                GameCamera.configureRoom(count: 3, option: .A, wide: 2); _ = GameCamera.camera(aspect: aspect)
                for k in [DecorKind.slide, .minigoal] {
                    let r = reach(k), s = k.spec
                    let want = DecorPlacement.coreMax.x + s.inner.x + s.round + 0.45 - 0.15
                    XCTAssertGreaterThan(r.right, want, "\(k) cannot go far enough right: \(def.id) \(name) R\(r.right)")
                    XCTAssertGreaterThan(r.left, want, "\(k) cannot go far enough left: \(def.id) \(name) L\(r.left)")
                }
            }
        }
    }

    /// The user's bug: placed on one side, a finger could not put the piece on the other.
    func testDragMovesTheSlideAndGoalFromLeftToRight() {
        for def in RoomCatalog.all {
            for aspect in [Float(440.0 / 956.0), Float(2.16)] {
                RoomLayout.apply(def)
                GameCamera.configureRoom(count: 3, option: .A, wide: 2); _ = GameCamera.camera(aspect: aspect)
                let b = StoreBook(wallet: DropsWallet(persists: false), persists: false)
                for k in [DecorKind.slide, .minigoal] {
                    b.grant(k.storeID)
                    let p = b.place(k.storeID)!
                    XCTAssertTrue(b.move(p.uid, to: SIMD2(-3.15, 0.5)), "\(k) left \(def.id) \(aspect)")
                    XCTAssertTrue(b.move(p.uid, to: SIMD2(3.15, 0.5)), "\(k) right \(def.id) \(aspect)")
                    b.putAway(p.uid)
                }
            }
        }
    }
}
