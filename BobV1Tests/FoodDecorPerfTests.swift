//
//  FoodDecorPerfTests.swift
//  Frame cost of the new content: three Jellies eating at the tray (Blender food meshes, three pieces each), a room with all 10 decor spots used and
//  one piece animating (the beanbag's wobble), shoes worn. Measured in the GpuOptPerfTests scene (3 Jellies, 1100 x 2390, the real renderer, frames
//  submitted back to back), against the SAME scene with no food, no decor and no shoes. The worst case is measured: tray, decor and shoe meshes are
//  REBUILT and uploaded every frame (the game only rebuilds them on change). Prints "FOODDECOR ..." lines.
//  Budget: the existing perf tests' sanity bound (frame < 200 ms) plus the per-frame CPU for the extra meshes held to half a 60 fps frame.
//

import XCTest
import Metal
import simd
import QuartzCore
@testable import BobV1

@MainActor
final class FoodDecorPerfTests: XCTestCase {
    nonisolated(unsafe) static var keep: [AnyObject] = []
    override func tearDown() { DecorField.shared.clear(); GameCamera.configureRoom(count: 1); _ = GameCamera.camera(aspect: 440.0 / 956.0) }

    func testThreeJelliesEatingInAFullRoomWithShoes() throws {
        GameCamera.configureRoom(count: 3, option: .A, wide: 2)
        let s = try XCTUnwrap(GpuOptPerfTests.Scene(n: 3, W: 1100, H: 2390))
        Self.keep.append(s)
        let room = try XCTUnwrap(s.ren.room)
        let L = DiningLayout.make(n: 3)
        let st = ServingState(n: 3, bitesLeft: [3, 3, 3])
        let book = StoreBook(wallet: DropsWallet(persists: false), persists: false)
        for k in DecorTests.fullMix { book.grant(k.storeID); XCTAssertNotNil(book.place(k.storeID)) }
        XCTAssertEqual(book.placedDecor.count, DecorTests.fullMix.count)
        let bagUID = try XCTUnwrap(book.placedDecor.first { $0.kind == .beanbag }?.uid)

        var extraMs = 0.0, extraMeshes = (tray: 0, decor: 0, shoes: 0)
        /// One frame of work: sim step + skin happen in `frame()` (skin) and here (sim); `loaded` adds the meshes.
        func work(loaded: Bool, count: Bool = false) {
            for a in s.actors { a.sim.step() }
            guard loaded else { return }
            let t0 = CACurrentMediaTime()
            DecorField.shared.kick(bagUID, 1); DecorField.shared.tick(dt: 1.0 / 60)
            let f = Consumables.sushi
            let g = DiningModels.trayGroup(layout: L, serving: f, state: st, theme: room.theme)
            room.setDining(DiningFrame(opaque: g.opaque, translucent: g.translucent))
            let dm = DecorModels.build(feet: DecorField.shared.feet, field: DecorField.shared, time: s.time)
            room.setDecorStatic(dm)
            let sb = RoomMeshBuilder(); sb.material = .plain
            for a in s.actors {
                let br = a.brain ?? BlobBrain()
                a.brain = br
                guard let beans = GameCare.footBeans(brain: br, sim: a.sim, skinner: a.skinner) else { continue }
                for side in 0..<2 { ShoeModel.build(.rainBoots, bean: beans[side], floorY: a.sim.floorY, time: s.time, side: side, into: sb) }
            }
            room.setShoes(sb.mesh)
            extraMs += (CACurrentMediaTime() - t0) * 1000
            if count { extraMeshes = (g.opaque.indices.count / 3, dm.indices.count / 3, sb.mesh.indices.count / 3) }
        }
        func run(loaded: Bool, frames: Int = 60) -> (total: Double, extra: Double) {
            for _ in 0..<6 { work(loaded: loaded); s.frame(wait: false) }
            s.lastCmd?.waitUntilCompleted()
            extraMs = 0
            let t0 = CACurrentMediaTime()
            for i in 0..<frames { work(loaded: loaded, count: i == 0); s.frame(wait: false) }
            s.lastCmd?.waitUntilCompleted()
            return ((CACurrentMediaTime() - t0) / Double(frames) * 1000, extraMs / Double(frames))
        }
        // interleaved blocks cancel clock drift
        var emptyT = 0.0, loadT = 0.0, loadExtra = 0.0
        let blocks = 3
        for _ in 0..<blocks {
            DecorField.shared.clear(); room.setDining(DiningFrame(opaque: RoomMesh(), translucent: RoomMesh())); room.setDecorStatic(RoomMesh()); room.setShoes(RoomMesh())
            emptyT += run(loaded: false).total
            DecorField.shared.set(book.placedDecor)
            let r = run(loaded: true)
            loadT += r.total; loadExtra += r.extra
        }
        emptyT /= Double(blocks); loadT /= Double(blocks); loadExtra /= Double(blocks)
        let line = String(format: "3 Jellies, 1100x2390, back-to-back frames: no food/decor/shoes %.2f ms/frame | eating (3x3 sushi) + 10 decor spots (beanbag wobbling) + rain boots %.2f ms/frame (+%.2f ms) | extra mesh build+upload CPU %.2f ms/frame (tray %d tris, decor %d tris, shoes %d tris, all rebuilt every frame)",
                          emptyT, loadT, loadT - emptyT, loadExtra, extraMeshes.tray, extraMeshes.decor, extraMeshes.shoes)
        print("FOODDECOR " + line); NSLog("FOODDECOR %@", line)
        XCTAssertLessThan(loadT, 200, "sanity bound the other perf tests use")
        XCTAssertLessThan(loadExtra, 8.3, "the extra meshes, rebuilt EVERY frame, cost under half a 60 fps frame of CPU")
        XCTAssertGreaterThan(extraMeshes.decor, 3000, "the full room's decor is really there")
        XCTAssertGreaterThan(extraMeshes.shoes, 100, "the shoes are really there")
    }

    /// Three Jellies each in a FULL outfit (hat, face, neck, body, hands, feet) in the same scene, against the same scene with nothing worn. The worst case:
    /// the wardrobe (tick, surface binds read from the skin, arm frames) and the shoe shells are rebuilt and uploaded every frame (the game rebuilds the shoes only
    /// when a foot moves). Prints "WEARPERF ..." lines.
    func testThreeJelliesInFullOutfits() throws {
        GameCamera.configureRoom(count: 3, option: .A, wide: 2)
        let s = try XCTUnwrap(GpuOptPerfTests.Scene(n: 3, W: 1100, H: 2390))
        Self.keep.append(s)
        let room = try XCTUnwrap(s.ren.room)
        WearBody.install(MotionRig.renderMesh)
        let outfits: [[WearSlot: WearLook]] = [
            [.head: .pirateHat, .face: .monocleGold, .neck: .scarfCosy, .body: .capeHero, .hands: .boxingMitts, .feet: .hightopRed],
            [.head: .flowerCrown, .face: .heartShades, .neck: .pearls, .body: .tutuPink, .hands: .gloveSky, .feet: .sneakerLightup],
            [.head: .crownGold, .face: .gogglesAviator, .neck: .whistleCoach, .body: .backpackSky, .hands: .wristbandsSky, .feet: .balletPink]]
        let set = WornSet(); set.body = WearBody.shared; set.soundOn = false; Self.keep.append(set)
        for a in s.actors { if a.brain == nil { a.brain = BlobBrain() } }
        var extraMs = 0.0, tris = (wear: 0, shoes: 0)
        func work(loaded: Bool, count: Bool = false) {
            for a in s.actors { a.sim.step() }
            guard loaded else { return }
            let t0 = CACurrentMediaTime()
            for a in s.actors { set.tick(id: a.id, brain: a.brain!, sim: a.sim, outfit: outfits[a.id], role: .none, hideAll: false, dt: 1.0 / 60) }
            for a in s.actors where set.shown(a.id, .hands) != nil { set.setArms(a.id, GameCare.armFrames(brain: a.brain!, sim: a.sim)) }
            let f = set.frame(theme: room.theme, time: s.time) { s.ren.skinPointer(body: $0) }
            room.setWear(opaque: f.opaque, translucent: f.translucent, bounds: set.lastBounds)
            let sb = RoomMeshBuilder(); sb.material = .plain
            for a in s.actors {
                guard let beans = GameCare.footBeans(brain: a.brain!, sim: a.sim, skinner: a.skinner), let look = outfits[a.id][.feet] else { continue }
                for side in 0..<2 { ShoeModel.build(look, bean: beans[side], floorY: a.sim.floorY, time: s.time, side: side, into: sb) }
            }
            room.setShoes(sb.mesh)
            extraMs += (CACurrentMediaTime() - t0) * 1000
            if count { tris = (f.opaque.indices.count / 3, sb.mesh.indices.count / 3) }
        }
        func run(loaded: Bool, frames: Int = 60) -> (total: Double, extra: Double) {
            for _ in 0..<6 { work(loaded: loaded); s.frame(wait: false) }
            s.lastCmd?.waitUntilCompleted()
            extraMs = 0
            let t0 = CACurrentMediaTime()
            for i in 0..<frames { work(loaded: loaded, count: i == 0); s.frame(wait: false) }
            s.lastCmd?.waitUntilCompleted()
            return ((CACurrentMediaTime() - t0) / Double(frames) * 1000, extraMs / Double(frames))
        }
        var emptyT = 0.0, loadT = 0.0, loadExtra = 0.0
        let blocks = 3
        for _ in 0..<blocks {
            room.setWear(opaque: RoomMesh(), translucent: RoomMesh(), bounds: []); room.setShoes(RoomMesh())
            emptyT += run(loaded: false).total
            let r = run(loaded: true)
            loadT += r.total; loadExtra += r.extra
        }
        emptyT /= Double(blocks); loadT /= Double(blocks); loadExtra /= Double(blocks)
        let line = String(format: "3 Jellies, 1100x2390, back-to-back frames: nothing worn %.2f ms/frame | full outfits x3 (hat, face, neck, body, hands, feet) %.2f ms/frame (+%.2f ms) | wardrobe+shoes build+upload CPU %.2f ms/frame (%d wardrobe tris, %d shoe tris, everything rebuilt every frame)",
                          emptyT, loadT, loadT - emptyT, loadExtra, tris.wear, tris.shoes)
        print("WEARPERF " + line); NSLog("WEARPERF %@", line)
        XCTAssertLessThan(loadT, 200)
        XCTAssertLessThan(loadExtra, 8.3, "the wardrobe, rebuilt EVERY frame, costs under half a 60 fps frame of CPU")
        XCTAssertGreaterThan(tris.wear, 5000)
    }

    /// The second decor batch: the 10-spot room filled with the HEAVIEST new meshes (loveseat 2200, dining set 1944, bookshelf 1500, toy car, yarn ball, monstera, rocking chair, duck: about 12.7k triangles), three Jellies,
    /// the rocking chair rocking and the toy car rolling so the decor is rebuilt every frame (the worst case). Prints "FURNPERF ...".
    func testHeaviestFurnitureRoomFrameCost() throws {
        GameCamera.configureRoom(count: 3, option: .A, wide: 2)
        let s = try XCTUnwrap(GpuOptPerfTests.Scene(n: 3, W: 1100, H: 2390))
        Self.keep.append(s)
        let room = try XCTUnwrap(s.ren.room)
        let book = StoreBook(wallet: DropsWallet(persists: false), persists: false)
        for k in DecorTuning.heaviestRoom { book.grant(k.storeID); XCTAssertNotNil(book.place(k.storeID), "\(k) fits") }
        let rocker = try XCTUnwrap(book.placedDecor.first { $0.kind == .rockingchair }?.uid)
        let car = try XCTUnwrap(book.placedDecor.first { $0.kind == .toycar }?.uid)
        let tris = book.placedDecor.reduce(0) { $0 + (DecorMeshes.loaded[$1.kind]?.triangles ?? 0) }
        var extraMs = 0.0, decorTris = 0
        func work(loaded: Bool, count: Bool = false) {
            for a in s.actors { a.sim.step() }
            guard loaded else { return }
            let t0 = CACurrentMediaTime()
            DecorField.shared.rock(rocker, 1); DecorField.shared.tick(dt: 1.0 / 60)
            if DecorField.shared.anim[car]?.moving != true { DecorField.shared.kickBall(car, direction: SIMD2(1, 0), speed: 3) }
            let dm = DecorModels.build(feet: DecorField.shared.feet, field: DecorField.shared, time: s.time)
            room.setDecorStatic(dm)
            extraMs += (CACurrentMediaTime() - t0) * 1000
            if count { decorTris = dm.indices.count / 3 }
        }
        func run(loaded: Bool, frames: Int = 60) -> (total: Double, extra: Double) {
            for _ in 0..<6 { work(loaded: loaded); s.frame(wait: false) }
            s.lastCmd?.waitUntilCompleted()
            extraMs = 0
            let t0 = CACurrentMediaTime()
            for i in 0..<frames { work(loaded: loaded, count: i == 0); s.frame(wait: false) }
            s.lastCmd?.waitUntilCompleted()
            return ((CACurrentMediaTime() - t0) / Double(frames) * 1000, extraMs / Double(frames))
        }
        var emptyT = 0.0, loadT = 0.0, loadExtra = 0.0
        let blocks = 3
        for _ in 0..<blocks {
            DecorField.shared.clear(); room.setDecorStatic(RoomMesh())
            emptyT += run(loaded: false).total
            DecorField.shared.set(book.placedDecor)
            let r = run(loaded: true)
            loadT += r.total; loadExtra += r.extra
        }
        emptyT /= Double(blocks); loadT /= Double(blocks); loadExtra /= Double(blocks)
        let line = String(format: "3 Jellies, 1100x2390, back-to-back frames: empty room %.2f ms/frame | 10 spots of the heaviest new furniture (%d pieces, %d art tris, %d drawn, rocking chair rocking, toy car rolling, decor rebuilt EVERY frame) %.2f ms/frame (+%.2f ms) | extra mesh build CPU %.2f ms/frame",
                          emptyT, book.placedDecor.count, tris, decorTris, loadT, loadT - emptyT, loadExtra)
        print("FURNPERF " + line); NSLog("FURNPERF %@", line)
        XCTAssertLessThan(loadT, 200, "sanity bound the other perf tests use")
        XCTAssertLessThan(loadExtra, 8.3, "the decor, rebuilt EVERY frame, costs under half a 60 fps frame of CPU")
    }
}
