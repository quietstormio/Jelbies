//
//  FeaturePerfTests.swift
//  Frame cost of the character layer: FOUR Jellies (Bob, Pip, Moss, Lavender) each in a full outfit WITH their features (spines, daisy on the hat
//  variant, wings) in the GpuOptPerfTests scene (1100 x 2390, the real renderer, frames back to back), against the same scene with nothing worn and
//  no features. The worst case: wardrobe, features and shoes are ticked, rebuilt and uploaded every frame. Prints "FEATUREPERF ..." lines.
//

import XCTest
import Metal
import simd
import QuartzCore
@testable import BobV1

@MainActor
final class FeaturePerfTests: XCTestCase {
    nonisolated(unsafe) static var keep: [AnyObject] = []
    override func tearDown() { GameCamera.configureRoom(count: 1); _ = GameCamera.camera(aspect: 440.0 / 956.0) }

    func testFourJelliesWithFeaturesAndOutfits() throws {
        GameCamera.configureRoom(count: 4, option: .A, wide: 2)
        let s = try XCTUnwrap(GpuOptPerfTests.Scene(n: 4, W: 1100, H: 2390))
        Self.keep.append(s)
        let room = try XCTUnwrap(s.ren.room)
        WearBody.install(MotionRig.renderMesh)
        let outfits: [[WearSlot: WearLook]] = [
            [.head: .pirateHat, .face: .monocleGold, .neck: .scarfCosy, .body: .capeHero, .hands: .boxingMitts, .feet: .hightopRed],
            [.head: .catEars, .face: .heartShades, .neck: .pearls, .body: .tutuPink, .hands: .gloveSky, .feet: .sneakerLightup],
            [.head: .beanieHoney, .face: .gogglesAviator, .neck: .whistleCoach, .body: .heroPatch, .hands: .wristbandsSky, .feet: .balletPink],
            [.face: .glassesRound, .body: .backpackSky, .hands: .glovePink, .feet: .rainBoots]]          // (a hat or a neck item with the backpack folds the wings: the lab's intersection rule)
        let set = WornSet(); set.body = WearBody.shared; set.soundOn = false; Self.keep.append(set)
        let feats = FeatureSet(); feats.body = WearBody.shared; Self.keep.append(feats)
        for a in s.actors where a.brain == nil {
            let b = BlobBrain.forGame(); b.attach(renderMesh: MotionRig.renderMesh, synchronous: true); b.autonomy = false; b.feature = JellyRoster.feature(a.id); b.currentPose(a.sim)
            a.brain = b
        }
        var extraMs = 0.0, tris = (wear: 0, feat: 0, shoes: 0)
        func work(loaded: Bool, count: Bool = false) {
            for a in s.actors { a.sim.step() }
            guard loaded else { return }
            let t0 = CACurrentMediaTime()
            for a in s.actors {
                let b = a.brain!
                set.tick(id: a.id, brain: b, sim: a.sim, outfit: outfits[a.id], role: .none, hideAll: false, dt: 1.0 / 60)
                var worn: [String] = []
                for sl in WearSlot.allCases where sl != .feet { if let l = set.shown(a.id, sl), !l.art.isEmpty { worn.append(l.art) } }
                feats.tick(id: a.id, brain: b, sim: a.sim, feature: JellyRoster.feature(a.id), worn: worn, hideAll: false, dt: 1.0 / 60)
                if let fs = feats.slot(a.id) { set.setArtOverride(a.id, fs.fit.hatVariant); b.wingsFolded = fs.fit.folded; b.wingFlapLimit = fs.fit.flapMax }
            }
            for a in s.actors where set.shown(a.id, .hands) != nil { set.setArms(a.id, GameCare.armFrames(brain: a.brain!, sim: a.sim)) }
            var f = set.frame(theme: room.theme, time: s.time) { s.ren.skinPointer(body: $0) }
            let ff = feats.frame { s.ren.skinPointer(body: $0) }
            let base = UInt32(f.opaque.vertices.count)
            f.opaque.vertices += ff.vertices; f.opaque.indices += ff.indices.map { $0 + base }
            room.setWear(opaque: f.opaque, translucent: f.translucent, bounds: set.lastBounds + feats.lastBounds)
            let sb = RoomMeshBuilder(); sb.material = .plain
            for a in s.actors {
                guard let beans = GameCare.footBeans(brain: a.brain!, sim: a.sim, skinner: a.skinner) else { continue }
                for side in 0..<2 { ShoeModel.build(outfits[a.id][.feet]!, bean: beans[side], floorY: a.sim.floorY, time: s.time, side: side, into: sb) }
            }
            room.setShoes(sb.mesh)
            extraMs += (CACurrentMediaTime() - t0) * 1000
            if count { tris = (f.opaque.indices.count / 3 - ff.indices.count / 3, ff.indices.count / 3, sb.mesh.indices.count / 3) }
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
        let line = String(format: "4 Jellies, 1100x2390, back-to-back frames: bare %.2f ms/frame | full outfits + features (spines, daisy on hat, wings) + shoes %.2f ms/frame (+%.2f ms) | wardrobe+feature+shoe tick/build/upload CPU %.2f ms/frame (wear %d tris, features %d tris, shoes %d tris, all rebuilt every frame)",
                          emptyT, loadT, loadT - emptyT, loadExtra, tris.wear, tris.feat, tris.shoes)
        print("FEATUREPERF " + line); NSLog("FEATUREPERF %@", line); MotionLog.write("FEATUREPERF " + line)
        XCTAssertLessThan(loadT, 200, "sanity bound the other perf tests use")
        XCTAssertLessThan(loadExtra, 8.3, "the extra meshes, rebuilt EVERY frame, cost under half a 60 fps frame of CPU")
        XCTAssertGreaterThan(tris.feat, 2500, "the three features are really there")
        XCTAssertGreaterThan(tris.wear, 3000, "the outfits are really there")
        XCTAssertEqual(feats.slot(2)?.fit.onHat, true, "Moss's daisy sits on the beanie")
        XCTAssertEqual(feats.slot(3)?.fit.wingDY, 0.16, "Lavender's wings ride up over the backpack")
    }
}
