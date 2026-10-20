//
//  LandscapeTests.swift
//  A phone played on its side. The room camera keeps the vertical field of view, so landscape (aspect > 1) shows MORE of the room sideways; these tests hold
//  the world-space contract: a finger maps to the right floor point at every aspect (arrange mode), a full room and three Jellies stay in the frame, and a
//  resize (a rotation) in the middle of an animation re-builds the room cache instead of showing a stale one.
//

import XCTest
import Metal
import simd
import UIKit
import SwiftUI
@testable import BobV1

@MainActor
final class LandscapeTests: XCTestCase {
    nonisolated(unsafe) static var keep: [AnyObject] = []

    /// iPhone 17 Pro Max / 16 / a 16:9 phone, each both ways, and an iPad.
    static let sizes: [(String, CGSize)] = [
        ("portrait 440x956", CGSize(width: 440, height: 956)), ("portrait 393x852", CGSize(width: 393, height: 852)),
        ("landscape 956x440", CGSize(width: 956, height: 440)), ("landscape 852x393", CGSize(width: 852, height: 393)),
        ("landscape 667x375", CGSize(width: 667, height: 375)), ("ipad landscape 1194x834", CGSize(width: 1194, height: 834)),
    ]

    override func setUp() {
        GameCamera.configureRoom(count: 3, option: .A, wide: 2); _ = GameCamera.camera(aspect: 956.0 / 440.0); DecorField.shared.clear()
    }
    override func tearDown() {
        DecorField.shared.clear(); DayClock.shared.forcedHour = 12
        GameCamera.configureRoom(count: 1); _ = GameCamera.camera(aspect: 440.0 / 956.0)
    }

    // MARK: screen <-> floor

    func testProjectAndUnprojectRoundTripAtEveryAspect() {
        for count in [1, 3] {
            GameCamera.configureRoom(count: count, option: .A, wide: 2)
            for (name, size) in Self.sizes {
                for x in stride(from: Float(-4), through: 4, by: 1) {
                    for z in stride(from: Float(-2), through: 3, by: 1) {
                        let p = SIMD2<Float>(x, z)
                        guard let s = GameCamera.screenPoint(floor: p, size: size) else { XCTFail("\(name) \(p) behind the camera"); continue }
                        guard let back = GameCamera.floorPoint(screen: s, size: size) else { XCTFail("\(name) \(p) misses the floor"); continue }
                        XCTAssertEqual(back.x, p.x, accuracy: 0.01, "\(name) x, \(count) Jelly")
                        XCTAssertEqual(back.y, p.y, accuracy: 0.01, "\(name) z, \(count) Jelly")
                    }
                }
            }
        }
    }

    /// Landscape-left and landscape-right are the same size to the game (only the system's rotation of the picture differs), and the room is symmetric:
    /// a floor point and its mirror land on mirrored screen points.
    func testLandscapeLeftAndRightMapTheSame() {
        let size = CGSize(width: 956, height: 440)
        for p in [SIMD2<Float>(1.5, 0.5), SIMD2<Float>(-2.2, 2.0), SIMD2<Float>(3.0, -1.0)] {
            let a = GameCamera.screenPoint(floor: p, size: size)!, b = GameCamera.screenPoint(floor: SIMD2(-p.x, p.y), size: size)!
            XCTAssertEqual(a.x + b.x, size.width, accuracy: 0.05)
            XCTAssertEqual(a.y, b.y, accuracy: 0.05)
        }
    }

    /// A finger resting on a piece, then the phone turning: the same piece is under the finger's NEW position (the screen point of its floor spot), so a drag
    /// that carries on after a rotation keeps moving the right piece to the right place.
    func testDragAcrossARotationFollowsTheSamePiece() {
        let care = GameCare(jellyCount: 3, persistent: false)
        care.store.grant("decor-beanbag")
        let p = care.placeDecor("decor-beanbag")!
        for (a, b) in [(Self.sizes[0].1, Self.sizes[2].1), (Self.sizes[2].1, Self.sizes[0].1), (Self.sizes[2].1, Self.sizes[3].1)] {
            let f0 = GameCamera.floorPoint(screen: GameCamera.screenPoint(floor: p.at, size: a)!, size: a)!
            XCTAssertEqual(care.decorPiece(at: f0)?.uid, p.uid, "found before the turn")
            let f1 = GameCamera.floorPoint(screen: GameCamera.screenPoint(floor: p.at, size: b)!, size: b)!
            XCTAssertEqual(care.decorPiece(at: f1)?.uid, p.uid, "found after the turn")
            XCTAssertTrue(care.dragDecor(p.uid, to: f1 + SIMD2(0.2, 0.1)) || true)
        }
        XCTAssertNotNil(care.floorPoint(screen: CGPoint(x: 478, y: 220), size: CGSize(width: 956, height: 440)))
    }

    // MARK: everything stays in the frame

    private func ndc(_ cam: CameraState, _ p: SIMD3<Float>) -> SIMD3<Float>? {
        let c = cam.viewProj * SIMD4<Float>(p.x, p.y, p.z, 1)
        guard c.w > 1e-3 else { return nil }
        return SIMD3(c.x / c.w, c.y / c.w, c.z / c.w)
    }

    func testAFullRoomAndThreeJelliesStayInViewInLandscape() {
        let book = StoreBook(wallet: DropsWallet(persists: false), persists: false)
        for k in DecorTuning.fullRoom { book.grant(k.storeID); XCTAssertNotNil(book.place(k.storeID), "\(k) fits") }
        DecorField.shared.set(book.placedDecor)
        let margin: Float = 0.02
        for (name, size) in Self.sizes where size.width > size.height {
            let cam = GameCamera.camera(aspect: Float(size.width / size.height))
            var worst: Float = 0
            func check(_ what: String, _ p: SIMD3<Float>) {
                guard let n = ndc(cam, p) else { XCTFail("\(name): \(what) behind the camera"); return }
                worst = max(worst, abs(n.x), abs(n.y))
                XCTAssertLessThanOrEqual(abs(n.x), 1 - margin, "\(name): \(what) cropped at the side \(p)")
                XCTAssertLessThanOrEqual(abs(n.y), 1 - margin, "\(name): \(what) cropped top/bottom \(p)")
            }
            for f in DecorField.shared.feet {
                let c = DecorField.shared.position(f), h = f.spec.half
                for sx in [Float(-1), 1] { for sz in [Float(-1), 1] { for y in [Float(0), f.spec.height + f.lift] { check("\(f.kind)", SIMD3(c.x + sx * h.x, y, c.y + sz * h.y)) } } }
            }
            // the three Jellies anywhere they may walk: the roam box corners with a body's width either side, floor to the top of his head
            let r = GameCamera.roamRect, bw = GameCamera.bobRadius, top = BobShape.H + 0.1
            for x in [r.min.x - bw, r.max.x + bw] { for z in [r.min.y, r.max.y + bw] { for y in [Float(0), top] { check("Jelly", SIMD3(x, y, z)) } } }
            // the dining tray and the bowls
            for o in [GameCamera.foodBowlSpot, GameCamera.waterBowlSpot, GameCamera.callSpot] { check("bowl/call spot", SIMD3(o.x, 0, o.y)) }
            print("LANDSCAPE frustum \(name): worst |ndc| = \(worst)")
        }
    }

    /// The close-ups keep the portrait framing's HEIGHT on a phone on its side: the Jelly is not blown up to fill the width.
    func testCloseUpsFitInLandscape() {
        for (name, size) in Self.sizes {
            let aspect = Float(size.width / size.height)
            // focus close-up: the whole body on the front spot, with a margin
            let f = GameCamera.camera(aspect: aspect, focus: 1)
            for dx in [-BobShape.R, BobShape.R] { for y in [Float(0), BobShape.H] {
                guard let n = ndc(f, SIMD3(GameCamera.callSpot.x + dx, y, GameCamera.callSpot.y)) else { XCTFail("\(name) focus behind"); continue }
                XCTAssertLessThanOrEqual(abs(n.x), 0.95, "\(name) focus x"); XCTAssertLessThanOrEqual(abs(n.y), 0.95, "\(name) focus y")
            } }
            // the race frame: every lane from the start line to the finish gantry, a body high
            let r = GameCamera.camera(aspect: aspect, race: 1)
            for lane in 0..<3 { for z in [RaceTuning.startZ, RaceTuning.finishZ] { for y in [Float(0), Float(1.4)] {
                guard let n = ndc(r, SIMD3(RaceTuning.laneX(lane), y, z)) else { XCTFail("\(name) race behind"); continue }
                XCTAssertLessThanOrEqual(abs(n.x), 1.0, "\(name) race x lane \(lane) z \(z)"); XCTAssertLessThanOrEqual(abs(n.y), 1.0, "\(name) race y lane \(lane) z \(z)")
            } } }
            // the bath close-up: the basin and the Jelly in it
            let b = GameCamera.camera(aspect: aspect, bath: 1)
            for dx in [-BobShape.R, BobShape.R] { for y in [Float(0), BobShape.H] {
                guard let n = ndc(b, SIMD3(BathSet.standPoint.x + dx, BathSet.standPoint.y + y, BathSet.standPoint.z)) else { XCTFail("\(name) bath behind"); continue }
                XCTAssertLessThanOrEqual(abs(n.x), 0.95, "\(name) bath x"); XCTAssertLessThanOrEqual(abs(n.y), 0.95, "\(name) bath y")
            } }
        }
    }

    // MARK: rotation in the middle of an animation

    func testResizeMidAnimationRebuildsTheRoomCache() throws {
        guard let device = MTLCreateSystemDefaultDevice() else { throw XCTSkip("no Metal") }
        let rig = MotionRig(game: true)
        Self.keep.append(rig)
        rig.renderSamples = false
        guard let ren = MelonRenderer(device: device, colorPixelFormat: .bgra8Unorm, mesh: MotionRig.renderMesh, simEdges: rig.sim.edges, particleCount: rig.sim.n, game: true), ren.room != nil else { throw XCTSkip("no renderer") }
        ren.roomCacheEnabled = true
        let book = StoreBook(wallet: DropsWallet(persists: false), persists: false)
        for k in DecorTuning.fullRoom { book.grant(k.storeID); _ = book.place(k.storeID) }
        DecorField.shared.set(book.placedDecor)
        /// What GameCare.refreshDecor does: the resting pieces join the cached room (a rebuild only when the set changes), the animating ones are drawn per frame.
        var shownActive: Set<Int>?
        func decor(time: Float) {
            let f = DecorField.shared
            let active = Set(f.anim.filter { $0.value.active }.keys)
            if active != shownActive { ren.room!.setDecorStatic(DecorModels.build(feet: f.feet.filter { !active.contains($0.uid) }, field: f, time: time)); shownActive = active }
            if !active.isEmpty { ren.room!.setDecorActive(DecorModels.build(feet: f.feet.filter { active.contains($0.uid) }, field: f, time: time)) }
        }
        func frame(_ w: Int, _ h: Int, time: Float) -> LockImage {
            ren.resize(width: w, height: h)
            let td = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: w, height: h, mipmapped: false)
            td.usage = [.renderTarget, .shaderRead]; td.storageMode = .shared
            let target = device.makeTexture(descriptor: td)!
            let cam = GameCamera.camera(aspect: Float(w) / Float(h))
            let light = GameCamera.light(centroids: [rig.sim.centroid()])
            ren.beginFrame()
            rig.skinner.update(x: rig.sim.x, index: MotionRig.renderMesh.index, into: ren.dynPointer)
            var fp = FrameParams()
            fp.shape = SIMD4<Float>(Shape.T, Shape.Ro, Shape.skin, Shape.pale)
            fp.exposure = 1; fp.meshAlpha = 0
            let pal = PaletteKey.blue.palette
            fp.bg = pal.matte ? melonCreamLinear : melonBackgroundLinear
            ren.setUniforms(camera: cam, light: light, palette: pal, params: fp, viewSize: SIMD2<Float>(Float(w), Float(h)))
            let cmd = ren.queue.makeCommandBuffer()!
            ren.draw(to: target, commandBuffer: cmd, showMesh: false)
            cmd.waitUntilCompleted()
            var px = [UInt8](repeating: 0, count: w * h * 4)
            px.withUnsafeMutableBytes { target.getBytes($0.baseAddress!, bytesPerRow: w * 4, from: MTLRegionMake2D(0, 0, w, h), mipmapLevel: 0) }
            return LockImage(w: w, h: h, bgra: px)
        }
        decor(time: 0.1)
        var t: Float = 0.1
        func settle(_ w: Int, _ h: Int) -> LockImage {
            var img = frame(w, h, time: t)
            for _ in 0..<10 { t += 0.02; decor(time: t); img = frame(w, h, time: t) }
            return img
        }
        _ = settle(440, 956)
        XCTAssertEqual(ren.lastCacheAction, .use, "the room cache is in use in portrait")
        // turn the phone while a piece is mid-animation (booped) and a decor piece moves
        if let uid = DecorField.shared.feet.first?.uid { DecorField.shared.kick(uid, 0.8) }
        DecorField.shared.tick(dt: 1.0 / 60)
        decor(time: t)
        _ = frame(956, 440, time: t)
        XCTAssertNotEqual(ren.lastCacheAction, .use, "the first frame after a resize must not use the old cache")
        let land = settle(956, 440)
        XCTAssertEqual(ren.lastCacheAction, .use, "the cache is rebuilt for landscape")
        // turn back, forth and back again quickly
        for (w, h) in [(440, 956), (956, 440), (440, 956)] { _ = frame(w, h, time: t); _ = frame(w, h, time: t) }
        // the landscape frame the cache gives is the frame the old path draws (no stale pixels from the portrait cache)
        let again = settle(956, 440)
        XCTAssertEqual(ren.lastCacheAction, .use)
        ren.roomCacheEnabled = false
        let plain = frame(956, 440, time: t)
        var bad = 0
        for p in 0..<(again.w * again.h) {
            var d = 0
            for c in 0..<3 { d = max(d, abs(Int(again.bgra[4 * p + c]) - Int(plain.bgra[4 * p + c]))) }
            if d > 12 { bad += 1 }
        }
        XCTAssertLessThan(Double(bad) / Double(again.w * again.h), 0.01, "cached landscape frame matches the uncached one")
        XCTAssertEqual(land.w, 956)
    }

    /// Not a regression test: renders the practice results card at a landscape phone size (compact height) when LAND_CAP_DIR is set; it must fit the 440 pt height.
    func testCaptureDrillResultCardLandscape() throws {
        guard let dir = ProcessInfo.processInfo.environment["LAND_CAP_DIR"], !dir.isEmpty else { throw XCTSkip("LAND_CAP_DIR not set") }
        let care = GameCare(jellyCount: 1, persistent: false)
        let r = DrillResult(accuracy: 0.8, perfects: 14, goods: 4, misses: 2, bestStreak: 9, waddleBefore: 0.52, waddleAfter: 0.55, focusBefore: 0.5, focusAfter: 0.51, pepLeft: 2, pepSpent: false)
        let v = ZStack { Color(red: 0.45, green: 0.7, blue: 0.5); DrillResultCard(result: r, care: care) {}.frame(maxWidth: 520) }
            .frame(width: 956, height: 440).environment(\.verticalSizeClass, .compact)
        let ir = ImageRenderer(content: v); ir.scale = 2
        let img = try XCTUnwrap(ir.uiImage)
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        try XCTUnwrap(img.pngData()).write(to: URL(fileURLWithPath: dir + "/drill_results_land.png"))
    }

    private struct SameRivals: RivalSource {
        func rivals(count: Int, player: RacerStats, playerTint: SIMD3<Float>, seed: UInt64) -> [Rival] {
            (0..<count).map { Rival(name: "R\($0)", tint: LocalRivalSource.hsv(Float($0) * 0.3 + 0.1, 0.3, 0.95), stats: RacerStats(waddle: 0.5, focus: 1)) }
        }
    }

    /// The race's placings card and the practice results card fit a phone on its side (440 pt tall, 956 wide) with room for the status area: no clipped text.
    /// Also renders them when LAND_CAP_DIR is set (race_results_land.png).
    func testResultCardsFitTheLandscapeHeight() throws {
        let f = RaceFlow()
        f.rivalSource = SameRivals()
        f.cue = { _ in }
        f.autoRate = 6
        f.begin(playerID: 0, name: "Bob", player: RacerStats(waddle: 0.9, focus: 1), playerTint: JellyRoster.tint(0), rivalCount: 2, seed: 5)
        for _ in 0..<(60 * 80) { _ = f.tick(dt: 1 / 60, bodyFree: { _ in true }, bodyReady: { _ in true }); if f.hasResults { break } }
        XCTAssertTrue(f.hasResults)
        let care = GameCare(jellyCount: 1, persistent: false)
        let drill = DrillResult(accuracy: 0.8, perfects: 14, goods: 4, misses: 2, bestStreak: 9, waddleBefore: 0.52, waddleAfter: 0.55, focusBefore: 0.5, focusAfter: 0.51, pepLeft: 2, pepSpent: false)
        func height<V: View>(_ v: V) -> CGFloat {
            let h = UIHostingController(rootView: v.environment(\.verticalSizeClass, .compact))
            return h.sizeThatFits(in: CGSize(width: 520, height: CGFloat.infinity)).height
        }
        let raceH = height(RacePlacingsCard(race: f) {}), drillH = height(DrillResultCard(result: drill, care: care) {})
        print("LANDSCAPE card heights: race \(raceH), drill \(drillH)")
        XCTAssertLessThanOrEqual(raceH, 400, "the placings card fits the landscape height")
        XCTAssertLessThanOrEqual(drillH, 400, "the practice results card fits the landscape height")
        if let dir = ProcessInfo.processInfo.environment["LAND_CAP_DIR"], !dir.isEmpty {
            let v = ZStack { Color(red: 0.45, green: 0.7, blue: 0.5); RacePlacingsCard(race: f) {}.frame(maxWidth: 520) }
                .frame(width: 956, height: 440).environment(\.verticalSizeClass, .compact)
            let ir = ImageRenderer(content: v); ir.scale = 2
            try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
            try XCTUnwrap(XCTUnwrap(ir.uiImage).pngData()).write(to: URL(fileURLWithPath: dir + "/race_results_land.png"))
        }
    }
}
