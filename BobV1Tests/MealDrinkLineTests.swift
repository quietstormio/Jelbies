//
//  MealDrinkLineTests.swift
//  2026-11-17 feeding survey, fix C2: a drink at the home tray lines up like food (x-ordered places given once, no re-plan, a quiet row); the café keeps the smart line-up.
//

import XCTest
import simd
@testable import BobV1

@MainActor
final class MealDrinkLineTests: XCTestCase {
    private var savedHour: Double?          // (the day clock as this class found it: put back in tearDown)
    private var feet: [DecorFoot] = [], balls: [BallSphere] = [], boxes: [RoomLayout.FlatBox] = [], tables: [Int: RoomLayout.FlatBox] = [:]
    override func setUp() {
        savedHour = DayClock.shared.forcedHour; DayClock.shared.forcedHour = 12          // (2026-11-17: the night rest follows the real clock; dining tests run at noon)
        GameCamera.configureRoom(count: 1); GameCamera.clearRoam(); RoomLayout.apply(RoomCatalog.home)
        feet = RoomLayout.decorFeet; balls = RoomLayout.ballSpheres; boxes = RoomLayout.dynamicBoxes; tables = RoomLayout.tableBoxes
        RoomLayout.decorFeet = []; RoomLayout.ballSpheres = []; RoomLayout.dynamicBoxes = []; RoomLayout.tableBoxes = [:] }
    override func tearDown() {
        DayClock.shared.forcedHour = savedHour
        MealTrace.spotOnce = nil
        RoomLayout.decorFeet = feet; RoomLayout.ballSpheres = balls; RoomLayout.dynamicBoxes = boxes; RoomLayout.tableBoxes = tables }

    private let O = SIMD2<Float>(0, 0.6)

    private func run(_ group: DiningGroup, _ seconds: Float) { for _ in 0..<Int(seconds * 60) { group.tick(dt: 1.0 / 60) } }

    private final class Floors { var at: [SIMD2<Float>] = [] }

    private var far: [SIMD2<Float>] { [O + SIMD2(1.5, -2.5), O + SIMD2(-1.5, -2.5), O + SIMD2(0.2, -2.9)] }

    private func begin(_ c: Consumable, _ floors: Floors, cafe: Bool = false) -> (DiningGroup, [BlobBrain], SocialTests.Lab) {
        let lab = SocialTests.Lab(n: 3, quiet: true, seed: 11)
        let brains = lab.rigs.map(\.brain)
        floors.at = far
        let group = DiningGroup()
        if cafe { group.forcedOrigin = O } else { MealTrace.spotOnce = O }
        group.start(c, brains: brains, floor: { floors.at[$0] })
        return (group, brains, lab)
    }

    /// Guards C2: a drink sitting gets its places once (x-ordered here) and never re-plans, however the diners shuffle.
    func testADrinkSittingGetsItsPlacesOnceAndNeverReplans() {
        let f = Floors()
        let (group, brains, lab) = begin(Consumables.water, f)
        withExtendedLifetime(lab) {
            let first = f.at
            let x = group.placeOf.map { group.standsNow[$0].x }
            XCTAssertLessThan(x[1], x[2]); XCTAssertLessThan(x[2], x[0])
            let places = group.placeOf
            f.at[0] = first[1]; f.at[1] = first[0]
            for b in brains { b.activity = .walking }
            run(group, 2)
            XCTAssertEqual(group.replans, 0)
            XCTAssertEqual(group.placeOf, places)
            group.cancel(); group.dining.reset()
        }
    }

    /// Guards C2: the drink row standing at the tray is quiet (the diners do not push each other).
    func testTheDrinkRowAtTheTrayIsQuiet() {
        let f = Floors()
        let (group, brains, lab) = begin(Consumables.water, f)
        withExtendedLifetime(lab) {
            f.at = (0..<3).map { group.approachPoint(blob: $0) }
            for b in brains { b.activity = .idle }
            run(group, 0.1)
            for i in 0..<3 { XCTAssertEqual(group.quietPeers(of: i), Set([0, 1, 2]), "diner \(i)") }
            group.cancel(); group.dining.reset()
        }
    }

    /// Control: the café keeps the smart line-up (it re-plans, and its row is never quiet).
    func testTheCafeKeepsTheSmartLineup() {
        let f = Floors()
        let (group, brains, lab) = begin(Consumables.berries, f, cafe: true)
        withExtendedLifetime(lab) {
            let first = f.at
            f.at[0] = first[1]; f.at[1] = first[0]
            for b in brains { b.activity = .walking }
            run(group, 2)
            XCTAssertGreaterThan(group.replans, 0)
            f.at = (0..<3).map { group.approachPoint(blob: $0) }
            for b in brains { b.activity = .idle }
            run(group, 0.1)
            XCTAssertTrue(group.quietPeers(of: 0).isEmpty)
            group.cancel(); group.dining.reset()
        }
    }
}
