//
//  DiningPlacementTests.swift
//  Owner rule 2026-11-10: "don't put food where food is, a toy is, or something that could block obviously". Where the group's tray may appear
//  (DiningSpot.chooseStrict / spotFree / touchesBlocker): every blocker kind put on the preferred spot is kept off, and a room so full that nothing fits gives nil
//  (GameCare then refuses at once with "No room for the table", see GameCare+Group.swift).
//

import XCTest
import simd
@testable import BobV1

@MainActor
final class DiningPlacementTests: XCTestCase {
    private var savedFeet: [DecorFoot] = [], savedBoxes: [RoomLayout.FlatBox] = [], savedTables: [Int: RoomLayout.FlatBox] = [:]
    private var savedPick: (([SIMD2<Float>]) -> SIMD2<Float>?)!
    override func setUp() {
        savedFeet = RoomLayout.decorFeet; savedBoxes = RoomLayout.dynamicBoxes; savedTables = RoomLayout.tableBoxes; savedPick = DiningSpot.pickOpen
        RoomLayout.decorFeet = []; RoomLayout.dynamicBoxes = []; RoomLayout.tableBoxes = [:]; DiningSpot.floorThings = []
        GameCamera.configureRoom(count: 3, option: .A, wide: 2); _ = GameCamera.camera(aspect: 440 / 956)
        DiningSpot.pickOpen = { open in open.min { simd_distance($0, DiningSpot.preferred) < simd_distance($1, DiningSpot.preferred) } }          // (the open spot nearest the preferred one: a blocker there must push the pick away)
    }
    override func tearDown() {
        RoomLayout.decorFeet = savedFeet; RoomLayout.dynamicBoxes = savedBoxes; RoomLayout.tableBoxes = savedTables; DiningSpot.pickOpen = savedPick; DiningSpot.floorThings = []
        GameCamera.configureRoom(count: 1); _ = GameCamera.camera(aspect: 440.0 / 956.0)
    }

    private let L = DiningLayout.make(n: 3)
    private func pick(jellies: [SIMD2<Float>] = [], lies: [(c: SIMD2<Float>, yaw: Float)] = []) -> SIMD2<Float>? {
        DiningSpot.chooseStrict(layout: L, jellies: jellies, lies: lies, accept: { _ in true }, score: { _ in 0 })
    }
    /// Every point of the tray rectangle, each stand and the approach strip is `clear` away from a disc (c, r).
    private func assertClear(_ o: SIMD2<Float>, of c: SIMD2<Float>, radius r: Float, _ what: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertGreaterThanOrEqual(DiningSpot.distance(from: c, origin: o, layout: L), r + 0.3 - 0.01, "\(what): the tray rectangle (at \(o)) is too close to it", file: file, line: line)
        for p in L.places { XCTAssertGreaterThanOrEqual(simd_distance(o + p.rel, c), r + 0.5 - 0.13, "\(what): a stand is too close to it", file: file, line: line) }
    }

    func testEmptyRoomHasASpot() {
        XCTAssertNotNil(pick(), "an empty room has room for the table")
    }

    func testDecorAndToysOnThePreferredSpotAreKeptOff() throws {
        let base = try XCTUnwrap(pick())
        for kind in [DecorKind.toybox, .petbed, .beanbag, .kickscooter, .frisbee, .footbag, .skateboard, .soccerball, .bookshelf] {
            RoomLayout.decorFeet = [DecorFoot(uid: 1, kind: kind, centre: base)]
            let o = try XCTUnwrap(pick(), "\(kind): there is still room elsewhere")
            let f = RoomLayout.decorFeet[0]
            let r = max(f.spec.half.x, f.spec.half.y)
            assertClear(o, of: base, radius: r, "\(kind)")
            XCTAssertTrue(DiningSpot.spotFree(origin: o, layout: L), "\(kind): the chosen spot passes the predicate")
        }
    }

    func testWalkOverRugIsAllowed() throws {
        let base = try XCTUnwrap(pick())
        RoomLayout.decorFeet = [DecorFoot(uid: 1, kind: .rug, centre: base)]
        XCTAssertTrue(DiningSpot.spotFree(origin: base, layout: L), "a rug is walk-over: the tray may stand on it (flat, footprint >= \(DiningSpot.walkOverRadius))")
    }

    func testLooseBallAndOtherFoodAreKeptOff() throws {
        let base = try XCTUnwrap(pick())
        DiningSpot.floorThings = [(c: base, r: 0.27)]
        let o = try XCTUnwrap(pick())
        assertClear(o, of: base, radius: 0.27, "ball")
        DiningSpot.floorThings = []
        RoomLayout.dynamicBoxes = [.init(centre: base, half: SIMD2(0.55, 0.3), height: 0.3)]          // (another tray's collider)
        let o2 = try XCTUnwrap(pick())
        XCTAssertGreaterThan(RoomLayout.boxDistanceXZ(o2, RoomLayout.dynamicBoxes[0]), 0.3, "another tray: kept off")
        XCTAssertTrue(DiningSpot.spotFree(origin: o2, layout: L))
        RoomLayout.dynamicBoxes = []
        RoomLayout.tableBoxes = [7: .init(centre: base, half: SIMD2(0.5, 0.5), height: 0.7)]          // (a café table)
        let o3 = try XCTUnwrap(pick())
        XCTAssertGreaterThan(RoomLayout.boxDistanceXZ(o3, RoomLayout.tableBoxes[7]!), 0.3, "a café table: kept off")
    }

    func testStandingAndLyingJelbiesAreKeptOff() throws {
        let base = try XCTUnwrap(pick())
        let o = try XCTUnwrap(pick(jellies: [base]))
        XCTAssertGreaterThanOrEqual(DiningSpot.distance(from: base, origin: o, layout: L), DiningSpot.jellyClear - 0.01, "a standing Jelbie")
        let o2 = try XCTUnwrap(pick(lies: [(c: base, yaw: 0.4)]))
        XCTAssertGreaterThanOrEqual(DiningSpot.lieDistance(from: base, yaw: 0.4, origin: o2, layout: L), DiningSpot.lieMargin - 0.01, "a lying sleeper's footprint")
    }

    func testAWalkerWhoCannotGetThereRejectsTheSpot() {
        // a wall of toy boxes across the floor in front of the walker: no way round inside the floor's width
        var feet: [DecorFoot] = []
        var x: Float = -2.4, uid = 10
        while x <= 2.41 { feet.append(DecorFoot(uid: uid, kind: .toybox, centre: SIMD2(x, 3.0))); uid += 1; x += 0.4 }
        RoomLayout.decorFeet = feet
        XCTAssertFalse(DiningSpot.walkable(from: SIMD2(0, 3.8), to: SIMD2(0, 0.6)), "a wall of toy boxes cuts the walk (and there is no detour)")
        XCTAssertTrue(DiningSpot.walkable(from: SIMD2(0, 2.4), to: SIMD2(0, 0.6)), "the same room, a walker on this side of it")
    }

    func testARoomSoFullThatNothingFitsHasNoSpot() {
        var feet: [DecorFoot] = []
        var uid = 100, x: Float = -2.4
        while x <= 2.41 { var z: Float = -1.8; while z <= 3.2 { feet.append(DecorFoot(uid: uid, kind: .toybox, centre: SIMD2(x, z))); uid += 1; z += 0.5 }; x += 0.5 }
        RoomLayout.decorFeet = feet
        XCTAssertNil(pick(), "nothing fits: the group serving is refused at once (GameCare: 'No room for the table')")
    }
}
