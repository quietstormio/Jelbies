//
//  DiningGroupFoodTests.swift
//  The group meal: with several Jellies and nobody singled out, Feed brings ONE serving with a place each; every Jelly eats to his own tier
//  (Full refuses, Normal 1 piece, Hungry 2, Famished 3), is paid per piece and leaves when done; one Jelly keeps the single flow. Capture: FOOD3_OUT.
//

import XCTest
import Metal
import simd
import UIKit
@testable import BobV1

@MainActor
final class DiningGroupFoodTests: XCTestCase {
    private func room(count: Int = 3) -> DiningJellyTests.Room {
        let r = DiningJellyTests.Room(count: count)
        DiningJellyTests.keep.append(r.care); DiningJellyTests.keep.append(contentsOf: r.actors)
        return r
    }
    private func hunger(_ r: DiningJellyTests.Room, _ v: [Float]) { for (i, x) in v.enumerated() { r.care.needs(for: i).set(.hunger, x) } }

    func testThreeHungryJelliesAllEatFromOneServing() {
        let r = room()
        hunger(r, [0.1, 0.1, 0.1])
        r.run(1)
        r.care.feed()
        XCTAssertTrue(r.care.groupActive)
        var places = 0, together = false, earlyRelease = false
        r.run(90) {
            if r.care.dining.isPresent { places = max(places, r.care.dining.n) }
            // a diner who is done is let go (no longer held / reserved) while the others are still at the tray
            if r.care.group.isActive, r.care.trayOut, r.actors.contains(where: { a in
                guard let b = a.brain, r.sawEating[a.id], !r.care.group.isHolding(a.id) else { return false }
                return !b.reserved && r.care.group.memberIDs.contains(a.id) }) { earlyRelease = true }
            if r.actors.filter({ $0.brain?.activity == .eating }).count >= 3 { together = true }
            return r.t > 2 && !r.care.trayOut
        }
        XCTAssertFalse(r.care.trayOut, "the serving went away when all were done")
        XCTAssertEqual(places, 3)
        XCTAssertTrue(r.sawEating.allSatisfy { $0 }, "all three ate \(r.sawEating)")
        XCTAssertTrue(together, "they ate at the same time")
        XCTAssertTrue(earlyRelease, "the first to finish was released before the group ended")
        for i in 0..<3 { XCTAssertGreaterThanOrEqual(r.level(i, .hunger), 0.85, "Jelly \(i) is at or near Full: \(r.level(i, .hunger))") }
    }

    /// Four Jellies, three places: the three hungriest sit first, the fourth waits where he stands and eats at a second sitting of the same serving.
    func testFourHungryJelliesEatInTwoSittingsOfThree() throws {
        throw XCTSkip("the roster cap is 3 Jelbies (2026-10-21); the 4-diner queue code stays but cannot be reached from a room")
        let r = room(count: 4)
        hunger(r, [0.1, 0.1, 0.1, 0.1])
        r.run(1)
        r.care.feed()
        XCTAssertTrue(r.care.groupActive)
        XCTAssertEqual(GameCare.seating([0, 1, 2, 3], level: { [0.5, 0.1, 0.3, 0.2][$0] }).now, [1, 2, 3])
        XCTAssertEqual(GameCare.seating([0, 1, 2, 3], level: { [0.5, 0.1, 0.3, 0.2][$0] }).later, [0])
        var places = 0, spawns = 0, wasPresent = false, firstSitting: [Int] = [], waiterMoved: Float = 0, waiterStart: SIMD2<Float>?
        r.run(150) {
            if r.care.dining.isPresent {
                places = max(places, r.care.dining.n)
                if !wasPresent { spawns += 1; if spawns == 1 { firstSitting = r.care.group.memberIDs } }
            }
            wasPresent = r.care.dining.isPresent
            if spawns == 1, let w = r.care.groupQueue.first {
                let p = r.actors[w].floor
                if waiterStart == nil { waiterStart = p }
                waiterMoved = max(waiterMoved, simd_distance(p, waiterStart!))
                XCTAssertTrue(r.actors[w].brain!.reserved, "the waiter is reserved")
            }
            return r.t > 2 && !r.care.trayOut
        }
        XCTAssertFalse(r.care.trayOut, "the serving went away when all were done")
        XCTAssertFalse(r.care.groupActive); XCTAssertTrue(r.care.groupQueue.isEmpty); XCTAssertNil(r.care.groupNext)
        XCTAssertEqual(places, 3, "three places at most")
        XCTAssertEqual(spawns, 2, "two sittings")
        XCTAssertEqual(firstSitting.count, 3)
        XCTAssertTrue(r.sawEating.allSatisfy { $0 }, "all four ate \(r.sawEating)")
        XCTAssertLessThan(waiterMoved, 0.6, "the waiter stayed put while the first three ate")
        for i in 0..<4 { XCTAssertGreaterThanOrEqual(r.level(i, .hunger), 0.85, "Jelly \(i) is at or near Full: \(r.level(i, .hunger))") }
        for a in r.actors { XCTAssertFalse(a.brain!.reserved, "Jelly \(a.id) was let go"); XCTAssertNil(a.brain!.waitFocus) }
    }

    func testFullJellyRefusesAndTiersTakeDifferentAmounts() {
        let r = room()
        hunger(r, [0.1, 1.0, 0.6])
        r.run(1)
        let tiers = (0..<3).map { r.care.needs(for: $0).tier(.hunger) }
        XCTAssertEqual(tiers[0], .famished); XCTAssertEqual(tiers[1], .full); XCTAssertEqual(tiers[2], .normal)
        let before = (0..<3).map { r.level($0, .hunger) }
        r.care.feed()
        r.run(90) { r.t > 2 && !r.care.trayOut }
        XCTAssertFalse(r.care.trayOut)
        XCTAssertEqual(r.level(1, .hunger), before[1], accuracy: 0.02, "the Full Jelly ate nothing")
        XCTAssertGreaterThan(r.level(0, .hunger), before[0] + 2.5 * MealAppetite.gainPerPiece, "Famished ate the most")
        XCTAssertEqual(r.level(2, .hunger) - before[2], MealAppetite.gainPerPiece, accuracy: 0.05, "Normal took one piece")
    }

    func testOneJellyKeepsTheOldFoodFlow() {
        let r = room(count: 1)
        hunger(r, [0.1])
        r.run(1)
        let before = r.level(0, .hunger)
        r.care.feed()
        XCTAssertFalse(r.care.groupActive)
        XCTAssertNotNil(r.care.wanted)
        r.run(60) { r.t > 2 && !r.care.trayOut }
        XCTAssertFalse(r.care.group.isActive)
        XCTAssertGreaterThan(r.level(0, .hunger), before + 2.5 * MealAppetite.gainPerPiece)
    }

    // MARK: capture

    func testCaptureThreeJellyMeal() throws {
        guard let path = ProcessInfo.processInfo.environment["FOOD3_OUT"] else { throw XCTSkip("FOOD3_OUT not set") }
        let r = room()
        hunger(r, [0.1, 0.1, 0.1])
        r.run(1)
        r.care.feed()
        r.run(40) { r.actors.filter { $0.brain?.activity == .eating }.count == 3 && r.care.dining.isPresent && r.care.dining.bitesLeft.allSatisfy { $0 <= 2 } }
        MotionLog.write("FOOD3 activities \(r.actors.map { String(describing: $0.brain?.activity) }) bites \(r.care.dining.bitesLeft) t=\(r.t)")
        let W = 603, H = 1311
        guard let device = MTLCreateSystemDefaultDevice(),
              let ren = MelonRenderer(device: device, colorPixelFormat: .bgra8Unorm, mesh: MotionRig.renderMesh, simEdges: r.actors[0].sim.edges, particleCount: r.actors[0].sim.n, game: true, bodyCount: 3),
              let room = ren.room else { throw XCTSkip("no Metal") }
        ren.resize(width: W, height: H)
        for a in r.actors.dropFirst() { if let p = JellyRoster.palette(a.id) { ren.setPalette(p, body: a.id) } }
        let td = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: W, height: H, mipmapped: false)
        td.usage = [.renderTarget, .shaderRead]; td.storageMode = .shared
        let target = device.makeTexture(descriptor: td)!
        let cam = GameCamera.camera(aspect: Float(W) / Float(H), focus: 0)
        let light = GameCamera.light(centroid: r.actors[0].sim.centroid())
        if let f = r.care.dining.frame(theme: room.theme) { room.setDining(f) }
        for _ in 0..<2 {
            ren.beginFrame()
            for a in r.actors {
                a.skinner.update(x: a.sim.x, index: MotionRig.renderMesh.index, into: ren.dynPointer(body: a.id))
                ren.setMouth(a.brain?.mouthOpen ?? 0, body: a.id)
            }
            var fp = FrameParams()
            fp.shape = SIMD4<Float>(Shape.T, Shape.Ro, Shape.skin, Shape.pale)
            fp.exposure = 1; fp.meshAlpha = 0
            let pal = PaletteKey.blue.palette
            fp.bg = pal.matte ? melonCreamLinear : melonBackgroundLinear
            ren.setUniforms(camera: cam, light: light, palette: pal, params: fp, viewSize: SIMD2<Float>(Float(W), Float(H)))
            let cmd = ren.queue.makeCommandBuffer()!
            ren.draw(to: target, commandBuffer: cmd, showMesh: false)
            cmd.waitUntilCompleted()
        }
        var px = [UInt8](repeating: 0, count: W * H * 4)
        px.withUnsafeMutableBytes { target.getBytes($0.baseAddress!, bytesPerRow: W * 4, from: MTLRegionMake2D(0, 0, W, H), mipmapLevel: 0) }
        guard let base = LockImage(w: W, h: H, bgra: px).uiImage() else { return }
        let img = UIGraphicsImageRenderer(size: CGSize(width: W, height: H)).image { _ in
            base.draw(at: .zero)
            let cap = "feed(): one serving, a spot each; Bob, Pip and Moss each eat to their fill" as NSString
            cap.draw(in: CGRect(x: 20, y: H - 110, width: W - 40, height: 100), withAttributes: [.font: UIFont.boldSystemFont(ofSize: 28), .foregroundColor: UIColor.white])
        }
        try FileManager.default.createDirectory(atPath: (path as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
        try img.pngData()!.write(to: URL(fileURLWithPath: path))
    }
}
