//
//  DiningGroupDrinkTests.swift
//  The group drink: with several Jellies and nobody singled out, Drink brings ONE drink with a straw each; every Jelly drinks to his own tier
//  (Quenched refuses), is paid per gulp and leaves when done; one Jelly keeps the single flow. Also the labelled capture (DRINK3_OUT).
//

import XCTest
import Metal
import simd
import UIKit
@testable import BobV1

@MainActor
final class DiningGroupDrinkTests: XCTestCase {
    private func room(count: Int = 3) -> DiningJellyTests.Room {
        let r = DiningJellyTests.Room(count: count)
        DiningJellyTests.keep.append(r.care); DiningJellyTests.keep.append(contentsOf: r.actors)
        return r
    }
    private func thirst(_ r: DiningJellyTests.Room, _ v: [Float]) { for (i, x) in v.enumerated() { r.care.needs(for: i).set(.thirst, x) } }

    func testThreeThirstyJelliesAllDrinkFromOneDrinkWithThreeStraws() {
        let r = room()
        thirst(r, [0.1, 0.1, 0.1])
        r.run(1)
        XCTAssertEqual((0..<3).map { r.care.needs(for: $0).tier(.thirst) }, [.famished, .famished, .famished])
        r.care.drink()
        XCTAssertTrue(r.care.groupActive)
        var straws = 0, drunkMax = [Float](repeating: 0, count: 3), together = false
        r.run(70) {
            if r.care.dining.isPresent { straws = max(straws, r.care.dining.n) }
            for p in 0..<r.care.dining.drunk.count where p < 3 { drunkMax[p] = max(drunkMax[p], r.care.dining.drunk[p]) }
            if r.actors.filter({ $0.brain?.activity == .drinking }).count >= 3 { together = true }
            return r.t > 2 && !r.care.trayOut
        }
        XCTAssertFalse(r.care.trayOut, "the drink went away when all were done")
        XCTAssertEqual(straws, 3, "one drink, three straws")
        XCTAssertTrue(r.sawEating.allSatisfy { $0 }, "all three drank \(r.sawEating)")
        XCTAssertTrue(together, "they drank at the same time")
        for p in 0..<3 { XCTAssertGreaterThan(drunkMax[p], 0.95, "place \(p) drank his whole share") }
        for i in 0..<3 { XCTAssertGreaterThanOrEqual(r.level(i, .thirst), 0.85, "Jelly \(i) is at or near Quenched: \(r.level(i, .thirst))") }
    }

    func testQuenchedJellyDoesNotDrinkAndTiersTakeDifferentAmounts() {
        let r = room()
        thirst(r, [0.1, 1.0, 0.6])
        r.run(1)
        let tiers = (0..<3).map { r.care.needs(for: $0).tier(.thirst) }
        XCTAssertEqual(tiers[0], .famished); XCTAssertEqual(tiers[1], .full)
        XCTAssertNotEqual(tiers[2], .famished); XCTAssertNotEqual(tiers[2], .full)
        let before = (0..<3).map { r.level($0, .thirst) }
        r.care.drink()
        var drunkMax = [Float](repeating: 0, count: 3)
        r.run(70) {
            for p in 0..<r.care.dining.drunk.count where p < 3 { drunkMax[p] = max(drunkMax[p], r.care.dining.drunk[p]) }
            return r.t > 2 && !r.care.trayOut
        }
        XCTAssertFalse(r.care.trayOut)
        XCTAssertEqual(r.level(1, .thirst), before[1], accuracy: 0.02, "the Quenched Jelly drank nothing")
        XCTAssertGreaterThan(r.level(0, .thirst), before[0] + 2.5 * MealAppetite.gainPerPiece, "Parched drank the most")
        XCTAssertGreaterThan(r.level(2, .thirst), before[2] + 0.5 * MealAppetite.gainPerPiece, "the middle one drank a little")
        XCTAssertLessThan(r.level(2, .thirst) - before[2], r.level(0, .thirst) - before[0] + 0.001)
        XCTAssertEqual(drunkMax.min() ?? 1, 0, accuracy: 0.01, "one share stayed untouched")
    }

    func testOneJellyKeepsTheOldSingleStrawFlow() {
        let r = room(count: 1)
        thirst(r, [0.1])
        r.run(1)
        let before = r.level(0, .thirst)
        r.care.drink()
        XCTAssertFalse(r.care.groupActive, "no group with a single Jelly")
        XCTAssertNotNil(r.care.wanted)
        var straws = 0
        r.run(40) { if r.care.dining.isPresent { straws = max(straws, r.care.dining.n) }; return r.t > 2 && !r.care.trayOut }
        XCTAssertEqual(straws, 1)
        XCTAssertFalse(r.care.group.isActive)
        XCTAssertGreaterThan(r.level(0, .thirst), before + 2.5 * MealAppetite.gainPerPiece)
    }

    func testSingledOutJellyDrinksAloneEvenWithThree() {
        let r = room()
        thirst(r, [0.1, 0.1, 0.1])
        r.run(1)
        r.care.drink(jelly: 1)
        XCTAssertFalse(r.care.groupActive)
        r.run(40) { r.t > 2 && !r.care.trayOut }
        XCTAssertTrue(r.sawEating[1]); XCTAssertFalse(r.sawEating[0] || r.sawEating[2])
    }

    /// Spots are not assigned per Jelly: scrambled Jellies (Bob right, Pip middle, Moss left) each take the nearest free spot, nobody shares one.
    func testNearestFreeSpotNobodyShares() {
        // pure rule: two Jellies close to the same spot; the nearer keeps it, the other gets his next-closest free one
        let spots: [SIMD2<Float>] = [SIMD2(-1.1, 0), SIMD2(0, 0), SIMD2(1.1, 0)]
        let a = DiningGroup.nearestSpots(floors: [SIMD2(0.1, -1), SIMD2(0.4, -1), SIMD2(-1.0, -1)], spots: spots)
        XCTAssertEqual(a, [1, 2, 0], "the nearer Jelly keeps the middle spot, the other takes the next-closest free one")
        XCTAssertEqual(Set(a).count, 3)
        // in the room
        let r = room()
        thirst(r, [0.1, 0.1, 0.1])
        r.actors[0].brain?.requestNow(.goTo(SIMD2(1.3, -0.8)))
        r.actors[1].brain?.requestNow(.goTo(SIMD2(0, -0.8)))
        r.actors[2].brain?.requestNow(.goTo(SIMD2(-1.3, -0.8)))
        r.run(10)
        r.care.drink()
        r.run(6) { r.care.group.isActive }
        XCTAssertTrue(r.care.group.isActive)
        let place = r.care.group.placeOf
        XCTAssertEqual(Set(place).count, 3, "no two share a spot: \(place)")
        let xs = place.map { DiningLayout.make(n: 3).places[$0].rel.x }
        XCTAssertGreaterThan(xs[0], 0.5, "Bob (right) took the right spot"); XCTAssertEqual(xs[1], 0, accuracy: 0.1, "Pip (middle) the middle one"); XCTAssertLessThan(xs[2], -0.5, "Moss (left) the left one")
        r.run(70) { r.t > 2 && !r.care.trayOut }
        XCTAssertTrue(r.sawEating.allSatisfy { $0 })
    }

    // MARK: capture

    func testCaptureThreeStrawDrink() throws {
        guard let path = ProcessInfo.processInfo.environment["DRINK3_OUT"] else { throw XCTSkip("DRINK3_OUT not set") }
        let r = room()
        thirst(r, [0.1, 0.1, 0.1])
        r.run(1)
        r.care.drink()
        r.run(40) { r.actors.filter { $0.brain?.activity == .drinking }.count == 3 && r.care.dining.isPresent && r.care.dining.drunk.allSatisfy { $0 > 0.3 } }
        MotionLog.write("DRINK3 activities \(r.actors.map { String(describing: $0.brain?.activity) }) drunk \(r.care.dining.drunk) t=\(r.t)")
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
            let cap = "drink(): one drink, three straws; Bob, Pip and Moss each drink to their fill" as NSString
            cap.draw(in: CGRect(x: 20, y: H - 110, width: W - 40, height: 100), withAttributes: [.font: UIFont.boldSystemFont(ofSize: 28), .foregroundColor: UIColor.white])
        }
        try FileManager.default.createDirectory(atPath: (path as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
        try img.pngData()!.write(to: URL(fileURLWithPath: path))
    }
}
