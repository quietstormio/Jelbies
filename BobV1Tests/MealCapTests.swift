//
//  MealCapTests.swift
//  2026-11-17 feeding survey, fix C1: the 12 s gather cap never pops the tray onto a diner who is still crossing the tray's floor.
//

import XCTest
import simd
@testable import BobV1

@MainActor
final class MealCapTests: XCTestCase {
    private var feet: [DecorFoot] = [], balls: [BallSphere] = [], boxes: [RoomLayout.FlatBox] = [], tables: [Int: RoomLayout.FlatBox] = [:]
    override func setUp() {
        GameCamera.configureRoom(count: 1); GameCamera.clearRoam(); RoomLayout.apply(RoomCatalog.home)
        feet = RoomLayout.decorFeet; balls = RoomLayout.ballSpheres; boxes = RoomLayout.dynamicBoxes; tables = RoomLayout.tableBoxes
        RoomLayout.decorFeet = []; RoomLayout.ballSpheres = []; RoomLayout.dynamicBoxes = []; RoomLayout.tableBoxes = [:] }
    override func tearDown() {
        MealTrace.spotOnce = nil
        RoomLayout.decorFeet = feet; RoomLayout.ballSpheres = balls; RoomLayout.dynamicBoxes = boxes; RoomLayout.tableBoxes = tables }

    private let O = SIMD2<Float>(0, 0.6)

    private func run(_ group: DiningGroup, _ seconds: Float) { for _ in 0..<Int(seconds * 60) { group.tick(dt: 1.0 / 60) } }

    /// Starts a berries sitting at O; returns the group, its brains and the lab (kept alive).
    private func begin(_ floors: [SIMD2<Float>], at box: UnsafeMutablePointer<[SIMD2<Float>]>) -> (DiningGroup, [BlobBrain], SocialTests.Lab) {
        let lab = SocialTests.Lab(n: 3, quiet: true, seed: 11)
        let brains = lab.rigs.map(\.brain)
        box.pointee = floors
        let group = DiningGroup()
        MealTrace.spotOnce = O
        group.start(Consumables.berries, brains: brains, floor: { box.pointee[$0] })
        return (group, brains, lab)
    }

    /// Guards C1: the cap does not pop the tray under a diner still on its floor, but pops once he is off it or the hold (4 s) is over.
    func testCapNeverPopsTheTrayOntoADinerStillCrossingItsFloor() {
        let at = UnsafeMutablePointer<[SIMD2<Float>]>.allocate(capacity: 1); at.initialize(to: [])
        defer { at.deinitialize(count: 1); at.deallocate() }
        let (group, brains, lab) = begin([O + SIMD2(-1.2, -1.2), O + SIMD2(0, -1.2), O + SIMD2(1.2, 1.2)], at: at)
        withExtendedLifetime(lab) {
            at.pointee[0] = group.approachPoint(blob: 0); at.pointee[1] = group.approachPoint(blob: 1)
            brains[0].activity = .idle; brains[1].activity = .idle
            at.pointee[2] = group.standsNow[group.placeOf[2]] + SIMD2(0, 0.35); brains[2].activity = .walking
            XCTAssertLessThan(group.trayDistance(at.pointee[2]), DiningGroup.trayClearance)
            XCTAssertGreaterThanOrEqual(group.trayDistance(group.approachPoint(blob: 0)), DiningGroup.trayClearance)
            run(group, 13)
            XCTAssertEqual(group.dining.phase, .absent, "no tray under a diner still crossing its floor at the 12 s cap")
            run(group, 3.2)
            XCTAssertNotEqual(group.dining.phase, .absent, "the hold is bounded")
            XCTAssertEqual(group.popReason, "cap")
            group.cancel(); group.dining.reset()
        }
    }

    /// Guards C1: once the late diner is behind his line (off the tray's floor) the cap pops the tray at once.
    func testTheTrayComesOutOnceHeIsOffItsFloor() {
        let at = UnsafeMutablePointer<[SIMD2<Float>]>.allocate(capacity: 1); at.initialize(to: [])
        defer { at.deinitialize(count: 1); at.deallocate() }
        let (group, brains, lab) = begin([O + SIMD2(-1.2, -1.2), O + SIMD2(0, -1.2), O + SIMD2(1.2, 1.2)], at: at)
        withExtendedLifetime(lab) {
            at.pointee[0] = group.approachPoint(blob: 0); at.pointee[1] = group.approachPoint(blob: 1)
            brains[0].activity = .idle; brains[1].activity = .idle
            at.pointee[2] = group.standsNow[group.placeOf[2]] + SIMD2(0, 0.35); brains[2].activity = .walking
            run(group, 13)
            XCTAssertEqual(group.dining.phase, .absent)
            at.pointee[2] = group.approachPoint(blob: 2) + SIMD2(0, -0.8); brains[2].activity = .walking
            run(group, 0.1)
            XCTAssertNotEqual(group.dining.phase, .absent)
            XCTAssertEqual(group.popReason, "cap")
            group.cancel(); group.dining.reset()
        }
    }

    /// Control: a diner standing at his stand never holds the gathered pop back.
    func testADinerAtHisStandNeverHoldsTheGatheredPop() {
        let at = UnsafeMutablePointer<[SIMD2<Float>]>.allocate(capacity: 1); at.initialize(to: [])
        defer { at.deinitialize(count: 1); at.deallocate() }
        let (group, brains, lab) = begin([O + SIMD2(-1.2, -1.2), O + SIMD2(0, -1.2), O + SIMD2(1.2, 1.2)], at: at)
        withExtendedLifetime(lab) {
            at.pointee[0] = group.standsNow[group.placeOf[0]]
            at.pointee[1] = group.approachPoint(blob: 1); at.pointee[2] = group.approachPoint(blob: 2)
            for b in brains { b.activity = .idle }
            for i in 0..<3 { brains[i].yaw = DiningLayout.make(n: 3).places[group.placeOf[i]].yaw }          // (C3 gathers a diner once he faces his place)
            XCTAssertLessThan(group.trayDistance(at.pointee[0]), DiningGroup.trayClearance)
            run(group, 0.1)
            XCTAssertNotEqual(group.dining.phase, .absent)
            XCTAssertEqual(group.popReason, "gathered")
            group.cancel(); group.dining.reset()
        }
    }
}
