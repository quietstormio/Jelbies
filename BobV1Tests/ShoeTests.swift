//
//  ShoeTests.swift
//  Shoes (store, cosmetic): a 3D shell grown from the foot bean's own vertices, so it is attached in every move, needs no body slot and changes
//  nothing about the body, the gait or the speed. The big per-move checks live in FeetAttachTests / ArmCapTests (`shoes` variants).
//

import XCTest
import simd
@testable import BobV1

@MainActor
final class ShoeTests: XCTestCase {
    nonisolated(unsafe) static var keep: [AnyObject] = []

    /// The planted rest foot in foot-local coordinates.
    static var restBean: [SIMD3<Float>] { FootBean.localF }

    static func vertices(_ m: RoomMesh) -> [SIMD3<Float>] { m.vertices.map { SIMD3($0.pos.x, $0.pos.y, $0.pos.z) } }

    func testEveryLookGrowsFromTheBeanWithinTheThickness() {
        for look in WearLook.shoes {
            let b = RoomMeshBuilder(); b.material = .plain
            ShoeModel.build(look, bean: Self.restBean, floorY: -10, time: 0.3, side: 0, into: b)
            let v = Self.vertices(b.mesh)
            XCTAssertGreaterThanOrEqual(v.count, FootBean.vertexCount, "\(look)")
            XCTAssertGreaterThan(b.mesh.indices.count, 2000, "\(look): a real mesh")
            for i in 0..<FootBean.vertexCount {
                XCTAssertLessThanOrEqual(simd_distance(v[i], Self.restBean[i]), ShoeModel.maxThickness + 1e-4, "\(look) vertex \(i) stays on the bean")
                XCTAssertFalse(v[i].x.isNaN)
            }
            let minShoe = v.prefix(FootBean.vertexCount).map(\.y).min()!, minBean = Self.restBean.map(\.y).min()!
            XCTAssertLessThan(minShoe, minBean, "\(look): a sole under the foot")
        }
    }

    func testTheSoleNeverGoesThroughTheFloor() {
        let b = RoomMeshBuilder(); b.material = .plain
        ShoeModel.build(.sneakerMint, bean: Self.restBean, floorY: 0, time: 0, side: 1, into: b)
        XCTAssertGreaterThanOrEqual(Self.vertices(b.mesh).map(\.y).min()!, -1e-6)
    }

    func testSneakersAreColouredBySoleUpperAndToe() {
        let b = RoomMeshBuilder(); b.material = .plain
        ShoeModel.build(.sneakerCoral, bean: Self.restBean, floorY: -10, time: 0, side: 0, into: b)
        let cols = b.mesh.vertices.prefix(FootBean.vertexCount).map { SIMD3($0.color.x, $0.color.y, $0.color.z) }
        XCTAssertGreaterThan(Set(cols.map { "\(Int($0.x * 20))\(Int($0.y * 20))\(Int($0.z * 20))" }).count, 4, "several colour regions")
        let pal = ShoeModel.palette(.sneakerCoral)
        let lowest = (0..<FootBean.vertexCount).min { ShoeModel.style.u[$0] < ShoeModel.style.u[$1] }!
        XCTAssertEqual(cols[lowest].x, pal.sole.x, accuracy: 0.02, "cream sole")
    }

    func testLooksAreDistinctAndOwnTheFeetSlot() {
        var seen = Set<String>()
        for l in WearLook.shoes {
            XCTAssertEqual(l.slot, .feet)
            seen.insert("\(ShoePaint.paintVertices(l, body: SIMD3(0.3, 0.5, 0.9)).col.map { $0.x + 3 * $0.y + 7 * $0.z }.reduce(0, +))")
        }
        XCTAssertEqual(seen.count, WearLook.shoes.count)
        XCTAssertEqual(Set(WearSlot.allCases), [.head, .face, .feet, .neck, .hands, .body], "the wardrobe's six slots")
        XCTAssertEqual(WearLook.shoes.count, 9, "five original shoes and the four of batch two")
    }

    func testShoesHaveNoSpeedEffect() {
        let care = GameCare(jellyCount: 1, persistent: false)
        care.store.grant("shoe-rain"); care.store.wear(.rainBoots, on: 0)
        let sim = RaceSim(player: RacerStats(waddle: 0.5, focus: 0.5), playerName: "Bob", rivals: [], seed: 1)
        XCTAssertEqual(sim.racers[0].stride, RaceTuning.stride(waddle: 0.5), "no speed effect from shoes")
        XCTAssertEqual(sim.racers[0].rate, RaceTuning.maxRate(waddle: 0.5))
    }

    // MARK: through the game (actors in a room)

    private func room() -> (GameCare, [JellyActor]) {
        let sm = MotionRig.simMesh, rm = MotionRig.renderMesh
        let emb = embed(simRest: sm.rest, tets: sm.tets, verts: rm.rest)
        let care = GameCare(jellyCount: 3, persistent: false)
        let spots = JellyRoster.spawnSpots(count: 3)
        let actors: [JellyActor] = (0..<3).map {
            let a = JellyActor(id: $0, name: JellyRoster.names[$0], simMesh: sm, renderMesh: rm, embedding: emb, appearance: .berry, firmness: 0.95, damping: 0.45, spawn: spots[$0])
            a.profile = care.jelly($0); a.care = care
            a.sim.arenaCenter = GameCamera.arenaCenter; a.sim.arenaRadius = GameCamera.arenaRadius
            a.reset(drop: 0.35, shift: true)
            let b = BlobBrain.forGame()
            b.attach(renderMesh: rm, synchronous: true)
            b.autonomy = false; b.steerID = $0
            care.wireWorld(b, isBob: $0 == 0)
            a.brain = b
            for _ in 0..<200 { a.sim.step() }
            b.currentPose(a.sim)
            return a
        }
        Self.keep += actors; Self.keep.append(care)
        return (care, actors)
    }

    func testShoesAreDrawnOnWearersOnlyAndOnlyOnThePlayersRacerOnTheTrack() {
        let (care, actors) = room()
        XCTAssertTrue(care.shoeMesh(actors, time: 0).vertices.isEmpty, "nobody wears shoes yet")
        care.store.grant("shoe-mint"); care.store.grant("shoe-glitter")
        care.store.wear(.sneakerMint, on: 0); care.store.wear(.glitterShoes, on: 1)
        let m = care.shoeMesh(actors, time: 0)
        XCTAssertGreaterThan(m.vertices.count, 2 * 2 * FootBean.vertexCount - 1, "two wearers, two feet each")
        XCTAssertNotNil(care.footBeans(actors[0]))
        // the track: the player's racer keeps them, the borrowed rival bodies do not (and no fourth body slot is used)
        care.race.begin(playerID: 0, name: "Bob", player: RacerStats(waddle: 0.5, focus: 0.5), playerTint: JellyRoster.tint(0), rivalCount: 2, seed: 3)
        XCTAssertNotNil(care.shoeLook(for: actors[0]))
        XCTAssertNil(care.shoeLook(for: actors[1]), "a rival wears none, whatever its owner has")
        XCTAssertNil(care.shoeLook(for: actors[2]))
        care.race.abort()
        XCTAssertNotNil(care.shoeLook(for: actors[1]))
    }

    func testShoeMeshFollowsTheFeetWhileHeWalks() {
        let (care, actors) = room()
        care.store.grant("shoe-sun"); care.store.wear(.sneakerSun, on: 0)
        let a = actors[0], b = a.brain!
        b.request(.goTo(SIMD2(1.4, 0.6)))
        var frames = 0, maxOff: Float = 0
        for k in 0..<(60 * 5) {
            b.tick(sim: a.sim, skinner: a.skinner, dt: a.sim.stepDt, touched: false)
            a.sim.step()
            guard k % 6 == 0, let beans = care.footBeans(a) else { continue }
            for s in 0..<2 {
                let b2 = RoomMeshBuilder(); b2.material = .plain
                ShoeModel.build(.sneakerSun, bean: beans[s], floorY: -10, time: 0, side: s, into: b2)
                let v = Self.vertices(b2.mesh)
                for i in 0..<FootBean.vertexCount { maxOff = max(maxOff, simd_distance(beans[s][i], v[i])) }
            }
            frames += 1
        }
        XCTAssertGreaterThan(frames, 30)
        XCTAssertLessThanOrEqual(maxOff, ShoeModel.maxThickness + 1e-3, "the shoe stays on the foot through the walk")
    }

    /// The first version's cream outsole made a lifted foot read as a bare whitish ball: now the bottom is a dark outsole and cream is only a thin midsole line.
    func testTheOutsoleIsDarkAndCreamIsOnlyAThinLine() {
        for look in [WearLook.sneakerMint, .sneakerSun, .sneakerCoral, .glitterShoes] {
            let b = RoomMeshBuilder(); b.material = .plain
            ShoeModel.build(look, bean: Self.restBean, floorY: -10, time: 0, side: 0, into: b)
            let pal = ShoeModel.palette(look)
            let cols = b.mesh.vertices.prefix(FootBean.vertexCount).map { SIMD3($0.color.x, $0.color.y, $0.color.z) }
            let nearCream = cols.filter { simd_distance($0, pal.band) < 0.08 }.count
            XCTAssertLessThan(Float(nearCream) / Float(cols.count), 0.12, "\(look): cream is a line, not the whole foot")
            let sole = cols.filter { simd_distance($0, pal.sole) < 0.02 }.count
            XCTAssertGreaterThan(Float(sole) / Float(cols.count), 0.2, "\(look): the bottom rings are the dark outsole")
            XCTAssertGreaterThan(simd_length(pal.sole), 0.0); XCTAssertLessThan(pal.sole.x + pal.sole.y + pal.sole.z, 1.6, "\(look): the outsole is dark")
        }
    }

    /// A foot that has not moved reuses its shell (and nothing is re-uploaded); a moving one rebuilds. Also logs what a frame costs for three wearers.
    func testPlantedFeetReuseTheShellAndTheFrameIsCheap() {
        let (care, actors) = room()
        for (i, look) in [WearLook.sneakerMint, .rainBoots, .sneakerCoral].enumerated() where i < actors.count {
            let id = ["shoe-mint", "shoe-rain", "shoe-coral"][i]
            care.store.grant(id); care.store.wear(look, on: i)
        }
        let first = care.shoeFrame(actors, time: 0)
        XCTAssertTrue(first.changed)
        let wearers = actors.filter { care.shoeLook(for: $0) != nil }.count
        let rebuilt0 = care.shoeStats.rebuilt
        XCTAssertEqual(rebuilt0, wearers * 2, "every foot was built once")
        let again = care.shoeFrame(actors, time: 0.016)
        XCTAssertFalse(again.changed, "nothing moved: nothing to upload")
        XCTAssertEqual(care.shoeStats.rebuilt, rebuilt0)
        XCTAssertEqual(care.shoeStats.reused, wearers * 2)
        XCTAssertEqual(again.mesh.vertices.count, first.mesh.vertices.count)
        XCTAssertEqual(again.mesh.indices, first.mesh.indices, "the reused shells are the same triangles")
        // a walking Jelly moves his feet: rebuilt
        let a = actors[0], b = a.brain!
        b.request(.goTo(SIMD2(1.4, 0.6)))
        for _ in 0..<90 { b.tick(sim: a.sim, skinner: a.skinner, dt: a.sim.stepDt, touched: false); a.sim.step() }
        _ = care.shoeFrame(actors, time: 1)
        XCTAssertGreaterThan(care.shoeStats.rebuilt, rebuilt0, "a moving foot is rebuilt")
        // cost per frame for the wearers: rebuilding every foot vs reusing every shell
        let n = 200
        var t0 = CACurrentMediaTime()
        for k in 0..<n { care.shoeCache = [:]; _ = care.shoeFrame(actors, time: Float(k)) }
        let rebuildMs = (CACurrentMediaTime() - t0) * 1000 / Double(n)
        _ = care.shoeFrame(actors, time: 0)
        t0 = CACurrentMediaTime()
        for k in 0..<n { _ = care.shoeFrame(actors, time: Float(k)) }
        let reuseMs = (CACurrentMediaTime() - t0) * 1000 / Double(n)
        MotionLog.write(String(format: "SHOE COST %d wearers (%d feet): rebuild all %.3f ms / frame, reuse all %.3f ms / frame (the beans themselves are computed either way)", wearers, wearers * 2, rebuildMs, reuseMs))
        XCTAssertLessThan(rebuildMs, 3.0)
        XCTAssertLessThan(reuseMs, rebuildMs)
    }
}
