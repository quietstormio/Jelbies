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

    /// Does a ray from `p` along `d` meet a triangle of the shoe within 9 cm?
    static func covered(_ p: SIMD3<Float>, _ d0: SIMD3<Float>, _ v: [SIMD3<Float>], _ idx: [UInt32]) -> Bool {
        // a ray through a vertex or edge of the shoe can slip between two triangles in float: try a few nearly parallel rays
        let t1 = simd_normalize(simd_cross(d0, abs(d0.y) < 0.9 ? SIMD3(0, 1, 0) : SIMD3(1, 0, 0))), t2 = simd_cross(d0, t1)
        for k in 0..<5 {
            let d = simd_normalize(d0 + (k == 1 ? t1 : k == 2 ? -t1 : k == 3 ? t2 : k == 4 ? -t2 : .zero) * 0.03)
            if hit(p, d, v, idx) { return true }
        }
        return false
    }
    static func hit(_ p: SIMD3<Float>, _ d: SIMD3<Float>, _ v: [SIMD3<Float>], _ idx: [UInt32]) -> Bool {
        var t = 0
        while t + 2 < idx.count {
            let a = v[Int(idx[t])], e1 = v[Int(idx[t + 1])] - a, e2 = v[Int(idx[t + 2])] - a
            t += 3
            let h = simd_cross(d, e2), det = simd_dot(e1, h)
            if abs(det) < 1e-12 { continue }
            let f = 1 / det, s = p - a, u = f * simd_dot(s, h)
            if u < 0 || u > 1 { continue }
            let q = simd_cross(s, e1), w = f * simd_dot(d, q)
            if w < 0 || u + w > 1 { continue }
            let tt = f * simd_dot(e2, q)
            if tt > 0 && tt < 0.09 { return true }
        }
        return false
    }

    func testEveryLookGrowsFromTheBeanWithinTheThickness() {
        ShoeArt.forceProcedural = true; defer { ShoeArt.forceProcedural = false }          // the procedural fallback shell
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
        ShoeArt.forceProcedural = true; defer { ShoeArt.forceProcedural = false }          // the procedural fallback shell
        let b = RoomMeshBuilder(); b.material = .plain
        ShoeModel.build(.sneakerMint, bean: Self.restBean, floorY: 0, time: 0, side: 1, into: b)
        XCTAssertGreaterThanOrEqual(Self.vertices(b.mesh).map(\.y).min()!, -1e-6)
    }

    func testSneakersAreColouredBySoleUpperAndToe() {
        ShoeArt.forceProcedural = true; defer { ShoeArt.forceProcedural = false }          // the procedural fallback shell
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
        var frames = 0, worstLow: Float = 0, worstCentre: Float = 0
        for k in 0..<(60 * 5) {
            b.tick(sim: a.sim, skinner: a.skinner, dt: a.sim.stepDt, touched: false)
            a.sim.step()
            guard k % 6 == 0, let beans = care.footBeans(a) else { continue }
            for s in 0..<2 {
                let b2 = RoomMeshBuilder(); b2.material = .plain
                ShoeModel.build(.sneakerSun, bean: beans[s], floorY: -10, time: 0, side: s, into: b2)
                let v = Self.vertices(b2.mesh)
                XCTAssertTrue(v.allSatisfy { $0.x.isFinite && $0.y.isFinite && $0.z.isFinite })
                // the sole is under the foot (never more than a few mm lower: it is the bottom of the bean), the shoe is centred on it
                worstLow = max(worstLow, beans[s].map(\.y).min()! - v.map(\.y).min()!)
                let cb = beans[s].reduce(SIMD3<Float>.zero, +) / Float(beans[s].count), cs = v.reduce(SIMD3<Float>.zero, +) / Float(v.count)
                worstCentre = max(worstCentre, simd_distance(SIMD2(cb.x, cb.z), SIMD2(cs.x, cs.z)))
                XCTAssertLessThanOrEqual(beans[s].map(\.y).min()! - v.map(\.y).min()!, 0.04, "the sole is the bottom of the foot, frame \(k)")
            }
            frames += 1
        }
        XCTAssertGreaterThan(frames, 30)
        XCTAssertLessThanOrEqual(worstCentre, 0.07, "the shoe stays centred on the foot through the walk")
    }

    // MARK: the modelled shoes

    /// The sole's bottom is a drawn face: it faces DOWN (a lifted foot, a cartwheel and a sit show it), and the ledge round the upper faces up.
    func testTheSolesBottomFacesDown() {
        for look in WearLook.shoes {
            let b = RoomMeshBuilder(); b.material = .plain
            ShoeModel.build(look, bean: Self.restBean, floorY: -10, time: 0, side: 0, into: b)
            let v = Self.vertices(b.mesh)
            var down = 0, up = 0, wrong = 0
            var t = 0
            while t + 2 < b.mesh.indices.count {
                let p0 = v[Int(b.mesh.indices[t])], p1 = v[Int(b.mesh.indices[t + 1])], p2 = v[Int(b.mesh.indices[t + 2])]
                t += 3
                guard max(p0.y, p1.y, p2.y) < -0.002, min(p0.y, p1.y, p2.y) > -0.0165 else { continue }
                let g = simd_cross(p1 - p0, p2 - p0)
                guard abs(g.y) > 0.9 * simd_length(g) else { continue }
                if g.y < 0 { down += 1 } else { wrong += 1 }
                _ = up; up += 0
            }
            XCTAssertGreaterThan(down, 20, "\(look): a bottom cap"); XCTAssertEqual(wrong, 0, "\(look): no bottom triangle faces up")
        }
    }

    func testEveryShoeHasModelledArtBoundToTheBean() {
        for look in WearLook.shoes {
            guard let art = ShoeArt.art(look) else { XCTFail("\(look): no shoe_\(look.rawValue).bin"); continue }
            XCTAssertGreaterThan(art.verts.count, 700, "\(look): a real model"); XCTAssertLessThan(art.verts.count, 5000, "\(look): within the vertex budget")
            XCTAssertGreaterThan(art.indices.count, 3 * 1000); XCTAssertEqual(art.indices.count % 3, 0)
            XCTAssertTrue(art.indices.allSatisfy { Int($0) < art.verts.count }, "\(look): indices in range")
            XCTAssertLessThan(art.verts.map { abs($0.d) }.max()!, 0.075, "\(look): every vertex is within a hand's width of the foot surface")
            XCTAssertGreaterThan(Set(art.verts.map { "\(Int($0.col.x * 30))-\(Int($0.col.y * 30))-\(Int($0.col.z * 30))" }).count, 3, "\(look): several colours")
            let b = RoomMeshBuilder(); b.material = .plain
            ShoeModel.build(look, bean: Self.restBean, floorY: -10, time: 0.3, side: 0, into: b)
            XCTAssertEqual(b.mesh.vertices.count, art.verts.count)
            let v = Self.vertices(b.mesh), bean = Self.restBean
            XCTAssertTrue(v.allSatisfy { $0.x.isFinite && $0.y.isFinite && $0.z.isFinite })
            XCTAssertLessThan(v.map(\.y).min()!, bean.map(\.y).min()! + 1e-4, "\(look): a sole at the bottom of the foot")
            XCTAssertGreaterThan(v.map(\.y).min()!, -0.016, "\(look): the sole is not buried deeper than a dish under the floor")
        }
        XCTAssertEqual(Set(WearLook.shoes.map { ShoeArt.art($0)!.verts.count }).count, WearLook.shoes.count, "nine different models")
    }

    /// A shoe follows its foot exactly: the same shoe on a rotated + moved bean is the rest shoe rotated + moved (the binding is rigid-equivariant).
    func testTheShoeFollowsAMovedFootExactly() {
        let q = simd_quatf(angle: 0.8, axis: simd_normalize(SIMD3<Float>(0.2, 1, 0.3)))
        let t = SIMD3<Float>(0.7, 0.1, -0.4)
        let moved = Self.restBean.map { q.act($0) + t }
        for look in WearLook.shoes {
            let a = RoomMeshBuilder(), c = RoomMeshBuilder(); a.material = .plain; c.material = .plain
            ShoeModel.build(look, bean: Self.restBean, floorY: -10, time: 0, side: 0, into: a)
            ShoeModel.build(look, bean: moved, floorY: -10, time: 0, side: 0, into: c)
            let va = Self.vertices(a.mesh), vc = Self.vertices(c.mesh)
            var worst: Float = 0
            for i in va.indices { worst = max(worst, simd_distance(q.act(va[i]) + t, vc[i])) }
            XCTAssertLessThan(worst, 2e-4, "\(look): the shoe moves with the foot")
            for i in stride(from: 0, to: a.mesh.vertices.count, by: 13) {
                let na = SIMD3(a.mesh.vertices[i].normal.x, a.mesh.vertices[i].normal.y, a.mesh.vertices[i].normal.z)
                let nc = SIMD3(c.mesh.vertices[i].normal.x, c.mesh.vertices[i].normal.y, c.mesh.vertices[i].normal.z)
                XCTAssertGreaterThan(simd_dot(q.act(na), nc), 0.99, "\(look): normals turn with the foot")
            }
        }
    }

    /// The mirrored foot (the -x one: its bean triangles wind the other way) gets the mirrored shoe, facing out.
    func testTheMirroredFootGetsAnOutwardFacingShoe() {
        let mirrored = Self.restBean.map { SIMD3(-$0.x, $0.y, $0.z) }
        for look in [WearLook.sneakerMint, .frogBoots] {
            let b = RoomMeshBuilder(); b.material = .plain
            ShoeModel.build(look, bean: mirrored, floorY: -10, time: 0, side: 1, into: b)
            let v = Self.vertices(b.mesh)
            var out = 0.0, tot = 0.0
            var t = 0
            let c = mirrored.reduce(SIMD3<Float>.zero, +) / Float(mirrored.count)
            while t + 2 < b.mesh.indices.count {
                let p0 = v[Int(b.mesh.indices[t])], p1 = v[Int(b.mesh.indices[t + 1])], p2 = v[Int(b.mesh.indices[t + 2])]
                let g = simd_cross(p1 - p0, p2 - p0), cen = (p0 + p1 + p2) / 3
                if simd_dot(g, cen - c) > 0 { out += 1 }; tot += 1
                t += 3
            }
            let plus = RoomMeshBuilder(); plus.material = .plain
            ShoeModel.build(look, bean: Self.restBean, floorY: -10, time: 0, side: 0, into: plus)
            let vp = Self.vertices(plus.mesh), cp = Self.restBean.reduce(SIMD3<Float>.zero, +) / Float(Self.restBean.count)
            var outP = 0.0
            t = 0
            while t + 2 < plus.mesh.indices.count {
                let p0 = vp[Int(plus.mesh.indices[t])], p1 = vp[Int(plus.mesh.indices[t + 1])], p2 = vp[Int(plus.mesh.indices[t + 2])]
                if simd_dot(simd_cross(p1 - p0, p2 - p0), (p0 + p1 + p2) / 3 - cp) > 0 { outP += 1 }
                t += 3
            }
            XCTAssertEqual(out / tot, outP / tot, accuracy: 0.01, "\(look): the mirrored shoe faces out as much as the +x one (\(out / tot) vs \(outP / tot))")
            // and its shading normals are the mirror image of the +x foot's
            let a = RoomMeshBuilder(); a.material = .plain
            ShoeModel.build(look, bean: Self.restBean, floorY: -10, time: 0, side: 0, into: a)
            var worst: Float = 1
            for i in stride(from: 0, to: a.mesh.vertices.count, by: 9) {
                let na = a.mesh.vertices[i].normal, nb = b.mesh.vertices[i].normal
                worst = min(worst, simd_dot(SIMD3(-na.x, na.y, na.z), SIMD3(nb.x, nb.y, nb.z)))
            }
            XCTAssertGreaterThan(worst, 0.98, "\(look): mirrored normals mirror")
        }
    }

    /// The lamp of the light-up sneakers cycles and the sequins twinkle; the other shoes are static (their shell is cached while the foot is planted).
    func testOnlyTheLampAndTheSequinsAnimate() {
        for look in WearLook.shoes {
            let a = RoomMeshBuilder(), c = RoomMeshBuilder(); a.material = .plain; c.material = .plain
            ShoeModel.build(look, bean: Self.restBean, floorY: -10, time: 0.0, side: 0, into: a)
            ShoeModel.build(look, bean: Self.restBean, floorY: -10, time: 1.1, side: 0, into: c)
            let changed = zip(a.mesh.vertices, c.mesh.vertices).filter { $0.color != $1.color || $0.normal.w != $1.normal.w }.count
            if look == .sneakerLightup || look == .glitterShoes { XCTAssertGreaterThan(changed, 20, "\(look) animates") } else { XCTAssertEqual(changed, 0, "\(look) is static") }
            XCTAssertEqual(ShoeArt.isAnimated(look), look == .sneakerLightup || look == .glitterShoes)
        }
    }

    /// No foot poking through: from every bean vertex of the sole, and of the toe box on the closed shoes, a ray along the bean's normal meets the shoe.
    func testTheShoeCoversTheSoleAndToeOfTheFootAtRestAndSquashed() {
        let open: Set<WearLook> = [.sneakerSun, .balletPink]
        let rest = Self.restBean
        // a squashed + sheared foot too (a bean under a hard landing): y x0.8, x x1.1, a shear along z
        let squashed = rest.map { SIMD3($0.x * 1.1, $0.y * 0.8, $0.z + $0.y * 0.15) }
        for (label, bean) in [("rest", rest), ("squashed", squashed)] {
            let n = ShoeModel.normals(bean)
            for look in WearLook.shoes {
                let b = RoomMeshBuilder(); b.material = .plain
                ShoeModel.build(look, bean: bean, floorY: -10, time: 0, side: 0, into: b)
                let v = Self.vertices(b.mesh)
                var checked = 0
                for i in 0..<FootBean.vertexCount {
                    let st = FootBean.localF[i]
                    let sole = st.y < 0.03
                    let toe = !open.contains(look) && st.z > 0.07 && st.y < 0.10
                    guard sole || toe, i % 3 == 0 else { continue }
                    checked += 1
                    XCTAssertTrue(Self.covered(bean[i] - n[i] * 0.0005, n[i], v, b.mesh.indices), "\(look) \(label): bean vertex \(i) (rest \(st)) is not covered")
                    if checked > 60 { break }
                }
            }
        }
    }

    /// The first version's cream outsole made a lifted foot read as a bare whitish ball: now the bottom is a dark outsole and cream is only a thin midsole line.
    func testTheOutsoleIsDarkAndCreamIsOnlyAThinLine() {
        ShoeArt.forceProcedural = true; defer { ShoeArt.forceProcedural = false }          // the procedural fallback shell
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
