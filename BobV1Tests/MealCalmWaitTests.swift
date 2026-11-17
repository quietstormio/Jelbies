//
//  MealCalmWaitTests.swift
//  2026-11-17 feeding survey, fix C3: the meal's calm wait (each diner faces his place, approaches along its facing, stands still, steps straight in).
//

import XCTest
import simd
@testable import BobV1

@MainActor
final class MealCalmWaitTests: XCTestCase {
    private var feet: [DecorFoot] = [], balls: [BallSphere] = [], boxes: [RoomLayout.FlatBox] = [], tables: [Int: RoomLayout.FlatBox] = [:]
    override func setUp() {
        GameCamera.configureRoom(count: 1); GameCamera.clearRoam(); RoomLayout.apply(RoomCatalog.home)
        feet = RoomLayout.decorFeet; balls = RoomLayout.ballSpheres; boxes = RoomLayout.dynamicBoxes; tables = RoomLayout.tableBoxes
        RoomLayout.decorFeet = []; RoomLayout.ballSpheres = []; RoomLayout.dynamicBoxes = []; RoomLayout.tableBoxes = [:] }
    override func tearDown() {
        MealTrace.spotOnce = nil; DiningGroup.calmWait = true
        RoomLayout.decorFeet = feet; RoomLayout.ballSpheres = balls; RoomLayout.dynamicBoxes = boxes; RoomLayout.tableBoxes = tables }

    private let O = SIMD2<Float>(0, 0.6)
    private let L = DiningLayout.make(n: 3)

    private func run(_ group: DiningGroup, _ seconds: Float) { for _ in 0..<Int(seconds * 60) { group.tick(dt: 1.0 / 60) } }

    private final class Floors { var at: [SIMD2<Float>] = [] }

    private func begin(_ floors: Floors) -> (DiningGroup, [BlobBrain], SocialTests.Lab) {
        let lab = SocialTests.Lab(n: 3, quiet: true, seed: 11)
        let brains = lab.rigs.map(\.brain)
        floors.at = [O + SIMD2(-1.2, -1.2), O + SIMD2(0, -1.2), O + SIMD2(1.2, -1.2)]
        let group = DiningGroup()
        MealTrace.spotOnce = O
        group.start(Consumables.berries, brains: brains, floor: { floors.at[$0] })
        return (group, brains, lab)
    }

    /// Guards C3: each diner faces his own place and his approach point lies along that facing.
    func testEachDinerFacesHisPlaceAndApproachesAlongIt() {
        let f = Floors()
        let (group, brains, lab) = begin(f)
        withExtendedLifetime(lab) {
            for i in 0..<3 {
                let y = L.places[group.placeOf[i]].yaw, stand = group.standsNow[group.placeOf[i]]
                XCTAssertEqual(brains[i].mealFaceYaw, y)
                let want = stand - 0.25 * SIMD2(sinf(y), cosf(y)), got = group.approachPoint(blob: i)
                XCTAssertEqual(got.x, want.x, accuracy: 1e-4); XCTAssertEqual(got.y, want.y, accuracy: 1e-4)
            }
            group.cancel(); group.dining.reset()
        }
    }

    /// Guards C3: the calm wait never outlives an abort or the end of the sitting.
    func testAnAbortMidWaitClearsItAndTheEndClearsIt() {
        let f = Floors()
        let (group, brains, lab) = begin(f)
        withExtendedLifetime(lab) {
            XCTAssertNotNil(brains[0].mealFaceYaw)
            brains[0].abortAll(lab.rigs[0].sim, lab.rigs[0].skinner)
            XCTAssertNil(brains[0].mealFaceYaw)
            group.cancel()
            for b in brains { XCTAssertNil(b.mealFaceYaw) }
            group.dining.reset()
        }
    }

    /// Guards C3: a diner is gathered only once he faces his place, or after the 1.5 s fallback.
    func testADinerIsSentToEatOnlyOnceHeFacesHisPlaceOrAfterTheFallback() {
        let f = Floors()
        let (group, brains, lab) = begin(f)
        withExtendedLifetime(lab) {
            f.at = (0..<3).map { group.approachPoint(blob: $0) }
            for b in brains { b.activity = .idle }
            for i in 0..<3 { brains[i].yaw = L.places[group.placeOf[i]].yaw + (i == 2 ? Float.pi : 0) }
            run(group, 1.0)
            XCTAssertEqual(group.dining.phase, .absent)
            run(group, 0.7)
            XCTAssertNotEqual(group.dining.phase, .absent)
            group.cancel(); group.dining.reset()
        }
    }

    /// Guards C3 follow-up: the café keeps its own wait (no facing, straight-back approach).
    func testTheCafeKeepsItsOwnWait() {
        let lab = SocialTests.Lab(n: 3, quiet: true, seed: 11)
        let brains = lab.rigs.map(\.brain)
        let at: [SIMD2<Float>] = [O + SIMD2(-1.2, -1.2), O + SIMD2(0, -1.2), O + SIMD2(1.2, -1.2)]
        let group = DiningGroup()
        group.forcedOrigin = O
        group.start(Consumables.berries, brains: brains, floor: { at[$0] })
        withExtendedLifetime(lab) {
            for i in 0..<3 {
                XCTAssertNil(brains[i].mealFaceYaw)
                let stand = group.standsNow[group.placeOf[i]], a = group.approachPoint(blob: i)
                XCTAssertEqual(a.x, stand.x, accuracy: 1e-4); XCTAssertEqual(a.y, stand.y - 0.25, accuracy: 1e-4)
            }
            group.cancel(); group.dining.reset()
        }
    }

    /// Guards C3's switch: off, the old wait (no facing, straight-back approach, gathered whatever the yaw).
    func testTheSwitchOffKeepsTheOldWait() {
        DiningGroup.calmWait = false
        let f = Floors()
        let (group, brains, lab) = begin(f)
        withExtendedLifetime(lab) {
            for i in 0..<3 {
                XCTAssertNil(brains[i].mealFaceYaw)
                let stand = group.standsNow[group.placeOf[i]], a = group.approachPoint(blob: i)
                XCTAssertEqual(a.x, stand.x, accuracy: 1e-4); XCTAssertEqual(a.y, stand.y - 0.25, accuracy: 1e-4)
            }
            f.at = (0..<3).map { group.approachPoint(blob: $0) }
            for b in brains { b.activity = .idle; b.yaw = 2 }
            run(group, 0.1)
            XCTAssertNotEqual(group.dining.phase, .absent)
            group.cancel(); group.dining.reset()
        }
    }
}
