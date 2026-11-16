//
//  ToyInteractionTests.swift
//  Every toy the shop sells has something a Jelbie does with it at home (kick / boop / peek / hop / slide), the retired babyish toys are gone, and the
//  fifth batch (hacky sack, frisbee, mini skateboard, basketball hoop) is wired the way the existing systems expect.
//

import XCTest
@testable import BobV1

@MainActor
final class ToyInteractionTests: XCTestCase {
    /// Toys with no interaction of their own: none (2026-11-15: the mini goal alone is booped; with a soccer ball it is shot at through the ball).
    private static let viaBall: Set<DecorKind> = []

    func testEverySoldToyHasAnInteraction() {
        let toys = StoreCatalog.decorItems(.toys).compactMap(\.decor)
        XCTAssertFalse(toys.isEmpty)
        for k in toys where !Self.viaBall.contains(k) { XCTAssertNotNil(k.activeInteraction, "\(k) is a toy nobody can play with") }
        // the goal's ball is sold too
        XCTAssertTrue(toys.contains(.soccerball))
        for k in DecorKind.allCases where k.category == .toys && !DecorKind.parkOnly.contains(k) && !k.isRetired && !Self.viaBall.contains(k) {
            XCTAssertNotNil(k.activeInteraction, "\(k) has no interaction")
        }
    }

    func testTheBabyishToysAreRetiredAndTheSportToysAreSold() {
        for k in [DecorKind.duck, .ringstacker, .jackinbox, .toypiano] { XCTAssertTrue(k.isRetired); XCTAssertNil(StoreCatalog.item(k.storeID)) }
        for k in DecorKind.batch5Toys where !k.isRetired {          // (the frisbee was retired on 2026-11-15)
            XCTAssertNotNil(StoreCatalog.item(k.storeID), "\(k) is sold")
            XCTAssertEqual(k.category, .toys)
            XCTAssertNotNil(DecorMeshes.loaded[k], "\(k) art is bundled")
            XCTAssertGreaterThan(DecorModels.thumbnail(k).indices.count / 3, 100, "\(k) is drawn from its art")
        }
    }

    func testTheSportToysReuseTheExistingInteractionSystems() {
        XCTAssertEqual(DecorKind.footbag.interaction, .decorKick); XCTAssertTrue(DecorKind.footbag.isBallLike); XCTAssertTrue(DecorKind.footbag.rolls)
        XCTAssertEqual(DecorKind.frisbee.interaction, .decorKick); XCTAssertTrue(DecorKind.frisbee.isBallLike)
        XCTAssertEqual(DecorKind.skateboard.interaction, .decorKick); XCTAssertTrue(DecorKind.skateboard.rolls); XCTAssertFalse(DecorKind.skateboard.isBallLike)
        XCTAssertEqual(DecorKind.hoop.interaction, .decorBoop); XCTAssertTrue(DecorKind.hoop.spec.solid)
        // the balls the Play picker flicks include the new ones
        XCTAssertTrue(BallToy.kinds.contains(.footbag) && !BallToy.kinds.contains(.frisbee), "the frisbee was retired on 2026-11-15")
        for k in DecorKind.batch5Toys where !k.isRetired { XCTAssertTrue((25...120).contains(StoreCatalog.item(k.storeID)?.price ?? 0), "\(k) price") }
    }

    func testTheArtHasTheSubMeshesThePoseUses() {
        XCTAssertNotNil(DecorMeshes.loaded[.footbag]?.part("ball"))
        XCTAssertNotNil(DecorMeshes.loaded[.frisbee]?.part("disc"))
        XCTAssertNotNil(DecorMeshes.loaded[.hoop]?.part("frame")); XCTAssertNotNil(DecorMeshes.loaded[.hoop]?.part("net"))
        let sk = DecorMeshes.loaded[.skateboard]
        XCTAssertNotNil(sk?.part("deck")); XCTAssertEqual(sk?.parts.filter { $0.name.hasPrefix("wheel") }.count, 4)
    }
}
