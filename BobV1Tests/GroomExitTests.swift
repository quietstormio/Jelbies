//
//  GroomExitTests.swift
//  Leaving the Jelly Spa: the Jelbies step out of the door ONE AT A TIME (spaced, never overlapping), then roam as usual.
//
import XCTest
import simd
@testable import BobV1

@MainActor
final class GroomExitTests: XCTestCase {
    override func setUp() { RoomLayout.dynamicBoxes = [] }
    override func tearDown() { RoomLayout.dynamicBoxes = []; GameCamera.clearRoam(); GameCamera.configureRoom(count: 1); _ = GameCamera.camera(aspect: 440.0 / 956.0) }

    func testThreeJelbiesComeOutOneAtATimeAndThenRoam() throws {
        let aspect: Float = 603.0 / 1311.0
        GameCamera.configureRoom(count: 3, option: .A, wide: 2); _ = GameCamera.camera(aspect: aspect); GameCamera.refreshRoam(aspect: aspect)
        let r = FocusAnyRun(count: 3, peers: true)
        W2CaptureTests.keep.append(r.care)
        let care = r.care
        care.bath.wallet.add(500, silent: true)
        for (i, a) in r.actors.enumerated() { a.brain?.autonomy = true; a.brain?.restTimer = 1e6; r.place(i, at: JellyRoster.spawnSpots(count: 3)[i]) }
        for _ in 0..<60 { r.tick() }
        let dt = r.actors[0].sim.stepDt
        care.groomBook.fixedDt = dt
        care.groom.openPicker(all: [0, 1, 2]); care.groom.begin(.quick)
        func at(_ a: JellyActor) -> SIMD2<Float> { GameCare.floorPos(a.brain!, a.sim) }
        var t: Float = 0, minGap: Float = 99
        var firstSeen: [Int: Float] = [:]
        var doneT: Float?
        var walked = Set<Int>()
        var n = 0
        while n < 60 * 40 {
            r.tick(); care.tickGroom(r.actors, dt: dt); t += dt; n += 1
            if care.groom.phase == .reveal {
                for a in r.actors where care.groomBook.out.contains(a.id) && firstSeen[a.id] == nil { firstSeen[a.id] = t }
                let out = r.actors.filter { care.groomBook.out.contains($0.id) }
                for i in 0..<out.count { for j in (i + 1)..<out.count { minGap = min(minGap, simd_length(at(out[i]) - at(out[j]))) } }
            }
            if doneT == nil, !care.groom.active, n > 60 { doneT = t }
            if let d = doneT, t - d <= 4 { for a in r.actors where a.isWalking { walked.insert(a.id) } }
            if let d = doneT, t - d > 4 { break }
        }
        XCTAssertNotNil(doneT, "the visit ended")
        XCTAssertEqual(firstSeen.count, 3)
        let order = firstSeen.sorted { $0.value < $1.value }
        XCTAssertEqual(order.map(\.key), [0, 1, 2], "exit order")
        let gaps = zip(order.dropFirst(), order).map { $0.value - $1.value }
        print("GROOMEXIT minRootDist=\(minGap) jellyGap=\(MelonController.jellyGap) exitGaps=\(gaps) roaming=\(walked.sorted())")
        XCTAssertTrue(gaps.allSatisfy { $0 >= 0.5 }, "spaced >= 0.5 s: \(gaps)")
        XCTAssertGreaterThanOrEqual(minGap, 0.9 * MelonController.jellyGap, "never overlap while coming out")
        XCTAssertEqual(walked.count, 3, "all roaming within 4 s of the end")
    }
}
