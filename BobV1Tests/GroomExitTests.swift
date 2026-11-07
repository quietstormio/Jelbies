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
        W2CaptureTests.keep.append(r.care); W2CaptureTests.keep.append(r)          // (the runtime aborts when these are released)
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
        var emotes: [Int: IdleKind] = [:]
        let outDir = ProcessInfo.processInfo.environment["GROOMEXIT_OUT"].flatMap { $0.isEmpty ? nil : $0 }
        let shot = outDir != nil ? W2CaptureTests.Shot(r, W: 603, H: 1311) : nil
        if let shot { W2CaptureTests.keep.append(shot) }
        var frames: [(LockImage, String)] = []
        var nextSnap: Float = 0.1
        var n = 0
        while n < 60 * 40 {
            r.tick(); care.tickGroom(r.actors, dt: dt); t += dt; n += 1
            if care.groom.phase == .reveal {
                if emotes.isEmpty { emotes = care.groomBook.emote }
                for a in r.actors where care.groomBook.out.contains(a.id) && firstSeen[a.id] == nil { firstSeen[a.id] = t }
                let out = r.actors.filter { care.groomBook.out.contains($0.id) }
                for i in 0..<out.count { for j in (i + 1)..<out.count { minGap = min(minGap, simd_length(at(out[i]) - at(out[j]))) } }
            }
            if let shot, care.groom.phase == .reveal, care.groom.cheerT >= nextSnap, frames.count < 6 {
                nextSnap += 0.7; frames.append((shot.frame(r).0, String(format: "cheerT %.2f", care.groom.cheerT)))
            }
            if doneT == nil, !care.groom.active, n > 60 { doneT = t }
            if let d = doneT, t - d <= 4 { for a in r.actors where a.isWalking { walked.insert(a.id) } }
            if let d = doneT, t - d > 4 { break }
        }
        if let outDir, !frames.isEmpty {
            try FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)
            for (k, f) in frames.enumerated() { try f.0.uiImage()?.pngData()?.write(to: URL(fileURLWithPath: "\(outDir)/groomexit_\(k).png")) }
            try RunOutTests.sheet(frames, cols: 6).pngData()?.write(to: URL(fileURLWithPath: "\(outDir)/groomexit_strip.png"))
        }
        if outDir != nil { XCTAssertEqual(frames.count, 6, "the strip frames") }
        XCTAssertNotNil(doneT, "the visit ended")
        XCTAssertEqual(firstSeen.count, 3)
        let order = firstSeen.sorted { $0.value < $1.value }
        XCTAssertEqual(order.map(\.key), [0, 1, 2], "exit order")
        let gaps = zip(order.dropFirst(), order).map { $0.value - $1.value }
        print("GROOMEXIT minRootDist=\(minGap) jellyGap=\(MelonController.jellyGap) exitGaps=\(gaps) roaming=\(walked.sorted()) emotes=\(emotes)")
        XCTAssertTrue(gaps.allSatisfy { $0 >= 0.5 }, "spaced >= 0.5 s: \(gaps)")
        XCTAssertGreaterThanOrEqual(minGap, 0.9 * MelonController.jellyGap, "never overlap while coming out")
        XCTAssertGreaterThanOrEqual(walked.count, 2, "roaming resumes within 4 s of the end (autonomy picks each one's moment: a Jelbie may wave first; GroomVarietyTests checks every exit emote hands them back)")
    }
}
