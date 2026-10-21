//
//  StoreFoodTests.swift
//  Every store food goes through the existing toss-into-the-mouth dining flow: three pieces, one flick each, the bite flies an arc and lands in the mouth,
//  the nub never reaches toward the mouth, the tray goes, the serving is paid from the bag and the perk starts.
//

import XCTest
import simd
@testable import BobV1

@MainActor
final class StoreFoodTests: XCTestCase {
    private func dine(_ id: String, file: StaticString = #filePath, line: UInt = #line) {
        let m = MealRun()
        m.care.store.grant(StoreCatalog.items.first { $0.food == id }!.id, 2)
        let perks = m.care.jelly(0)!.perks
        let perk = Consumables.with(id: id)!.perk!
        perks.clear(perk)
        m.brain.expr.enabled = false          // (the expression layer's own faces - the open happy mouth of the sugar-rush zoomies after a taco - are not chomps; ExpressionTests covers the layer)
        m.moveAway()
        m.meal(id)
        let d = m.dineFrames, dt = m.rig.sim.stepDt, grabS = Float(ArmPath.nubGrabS)
        XCTAssertFalse(d.isEmpty, "\(id): he dined", file: file, line: line)
        XCTAssertEqual(m.tray.bitesLeft, [0], "\(id): all three pieces eaten", file: file, line: line)
        XCTAssertEqual(m.runs { $0.holding }, 3, "\(id): one piece in the hand per bite", file: file, line: line)
        XCTAssertEqual(m.runs { $0.mouth > 0.05 }, 6, "\(id): two chomps per bite", file: file, line: line)
        // the toss, never an arm reaching to the mouth
        XCTAssertLessThanOrEqual(d.map { $0.armS }.max() ?? 1, grabS + 0.001, "\(id): the nub never goes past the stub's swing", file: file, line: line)
        let carry = d.filter { $0.holding && !$0.flying && $0.phase != "grab" }.compactMap { $0.heldDist }
        XCTAssertLessThan(carry.max() ?? 1, 0.01, "\(id): the piece stays on the nub until the flick", file: file, line: line)
        let arcs = d.compactMap { $0.arc }
        XCTAssertGreaterThan(arcs.max() ?? 0, 0.10, "\(id): the piece flies an arc", file: file, line: line)
        let land = d.compactMap { $0.landDist }
        XCTAssertGreaterThanOrEqual(land.count, 18, file: file, line: line)
        XCTAssertLessThan(land.max() ?? 1, 0.03, "\(id): it lands in his mouth", file: file, line: line)
        var flicks = 0, was = false
        for f in d where f.phase == "chew" && !f.flying { let now = f.armS >= grabS - 0.002; if now && !was { flicks += 1 }; was = now }
        XCTAssertGreaterThanOrEqual(flicks, 3, "\(id): a flick per bite", file: file, line: line)
        XCTAssertLessThan(d.map { $0.miss }.filter { $0 > 0 }.max() ?? 1, Consumables.with(id: id)!.pizzaLayout ? 0.09 : 0.065, "\(id): the nub meets every piece", file: file, line: line)
        XCTAssertTrue(m.frames.filter { $0.phase != "chew" }.allSatisfy { $0.mouth == 0 }, file: file, line: line)
        // the tray goes, he is free, and the bag paid for ONE serving
        XCTAssertEqual(m.tray.phase, .absent, "\(id): tray gone", file: file, line: line)
        XCTAssertFalse(m.care.trayOut, "\(id): menu free", file: file, line: line)
        if perk == .zoomies {
            XCTAssertTrue(m.care.zoomiesDue.isEmpty, "\(id): the sugar rush was delivered", file: file, line: line)
            XCTAssertEqual(m.brain.idleState.kind, .zoomies, "\(id): zoomies in the room once he has eaten", file: file, line: line)
        } else {
            XCTAssertEqual(m.brain.activity, .idle, "\(id): idle again", file: file, line: line)
        }
        XCTAssertEqual(m.care.store.count(StoreCatalog.items.first { $0.food == id }!.id), 1, "\(id): one serving used", file: file, line: line)
        XCTAssertTrue(perks.isActive(perk), "\(id): its perk started", file: file, line: line)
        perks.clear(perk)
    }

    func testEveryNewFoodIsTossedIntoHisMouth() {
        for f in Consumables.storeFoods { dine(f.id) }
    }

    func testAStoreFoodNeedsOneInTheBag() {
        let care = GameCare(jellyCount: 1, persistent: false)
        care.feed("sushi")
        XCTAssertFalse(care.trayOut, "none in the bag: nothing is served")
        care.store.grant("sushi", 1)
        care.feed("sushi")
        XCTAssertTrue(care.trayOut)
    }

    func testMeshesAreRealAndSmall() {
        for f in Consumables.storeFoods {
            let h = DiningModels.heldPiece(f, index: 0, scale: 1)
            XCTAssertGreaterThan(h.vertices.count, 150, "\(f.id) is a real 3D mesh")
            XCTAssertEqual(h.indices.count % 3, 0)
            var lo = SIMD3<Float>(repeating: .infinity), hi = SIMD3<Float>(repeating: -.infinity)
            for v in h.vertices { let p = SIMD3(v.pos.x, v.pos.y, v.pos.z); lo = simd_min(lo, p); hi = simd_max(hi, p); XCTAssertFalse(p.x.isNaN) }
            let size = hi - lo
            XCTAssertLessThan(max(size.x, size.z), f.pizzaLayout ? 0.30 : 0.28, "\(f.id): fits its place on the plate")
            XCTAssertLessThan(size.y, 0.14, "\(f.id): low enough to toss")
            XCTAssertGreaterThan(size.y, 0.03)
            XCTAssertLessThan(lo.y, -0.025, "\(f.id): it sits on the plate, below its centre")
        }
    }

    func testStoreFoodTraysBuildForOneToThreeJellies() {
        let theme = RoomTheme()
        for f in Consumables.storeFoods { for n in 1...3 {
            let L = DiningLayout.make(n: n)
            let g = DiningModels.trayGroup(layout: L, serving: f, state: ServingState(n: n, bitesLeft: Array(repeating: 3, count: n)), theme: theme)
            XCTAssertGreaterThan(g.opaque.vertices.count, 800, "\(f.id) n=\(n)")
        } }
    }

    // MARK: the Blender meshes

    private func extent(_ m: RoomMesh) -> (lo: SIMD3<Float>, hi: SIMD3<Float>) {
        var lo = SIMD3<Float>(repeating: .infinity), hi = SIMD3<Float>(repeating: -.infinity)
        for v in m.vertices { let p = SIMD3(v.pos.x, v.pos.y, v.pos.z); lo = simd_min(lo, p); hi = simd_max(hi, p) }
        return (lo, hi)
    }

    func testEveryFoodLoadsFromTheBundledResourceWithinBudget() {
        for id in FoodMeshes.resourceIDs {
            guard let m = FoodMeshes.loaded[id] else { XCTFail("\(id): food_\(id).bin did not load"); continue }
            XCTAssertLessThanOrEqual(m.triangles, 1600, "\(id): triangle budget")
            XCTAssertGreaterThan(m.triangles, 300, "\(id): a real mesh")
            XCTAssertTrue(m.indices.allSatisfy { Int($0) < m.positions.count })
        }
        for f in Consumables.storeFoods {
            let b = RoomMeshBuilder(); b.material = .plain
            XCTAssertTrue(FoodMeshes.append(b, id: f.id, centre: .zero, variant: 0, scale: 1), "\(f.id): meshed, not the procedural fallback")
            XCTAssertLessThanOrEqual(b.mesh.indices.count / 3, 1600, f.id)
        }
    }

    func testNewMeshesHaveRoughlyTheOldPiecesBounds() {
        let old: [String: PieceBuilder] = ["nuggets": StoreFoodModels.nugget, "fries": StoreFoodModels.fries, "sushi": StoreFoodModels.sushi, "sandwich": StoreFoodModels.sandwich,
                                           "minipizza": StoreFoodModels.minipizzaSlice, "taco": StoreFoodModels.taco, "donut": StoreFoodModels.donut,
                                           "popsicle": StoreFoodModels.popsicle, "onigiri": StoreFoodModels.onigiri, "cookie": StoreFoodModels.cookie]
        for f in Consumables.storeFoods {
            let ob = RoomMeshBuilder(); ob.material = .plain
            old[f.id]!(ob, .zero, 0, 1, f.palette)
            let o = extent(ob.mesh), n = extent(DiningModels.heldPiece(f, index: 0, scale: 1))
            let os = o.hi - o.lo, ns = n.hi - n.lo
            XCTAssertLessThan(max(ns.x, ns.z), max(os.x, os.z) * 1.6 + 0.02, "\(f.id): footprint not much bigger than before")
            XCTAssertGreaterThan(max(ns.x, ns.z), max(os.x, os.z) * 0.6, "\(f.id): footprint not much smaller than before")
            XCTAssertLessThan(abs(n.lo.y - o.lo.y), 0.035, "\(f.id): rests on the plate like before")
        }
    }

    func testPlacementRules() {
        // the taco's long axis runs along x
        let t = extent(DiningModels.heldPiece(Consumables.taco, index: 0, scale: 1)), ts = t.hi - t.lo
        XCTAssertGreaterThan(ts.x, ts.z * 1.5, "taco lies along x")
        // the three nugget slots use the three variants
        let n = (0..<3).map { DiningModels.heldPiece(Consumables.nuggets, index: $0, scale: 1).vertices.count }
        XCTAssertEqual(Set(n).count, 3, "three different nugget meshes")
        // the onigiri stays upright (taller than the cookie, standing on its base)
        let o = extent(DiningModels.heldPiece(Consumables.onigiri, index: 0, scale: 1))
        XCTAssertGreaterThan(o.hi.y - o.lo.y, 0.12)
        // the ice pop's stick (grip) is at the piece centre in xz
        let p = extent(DiningModels.heldPiece(Consumables.popsicle, index: 0, scale: 1))
        XCTAssertLessThan(abs(p.lo.z - (-0.0625)), 0.06, "stick end near the nub")
        // scale multiplies
        let big = extent(DiningModels.heldPiece(Consumables.sushi, index: 0, scale: 1.3)), one = extent(DiningModels.heldPiece(Consumables.sushi, index: 0, scale: 1))
        XCTAssertEqual((big.hi.x - big.lo.x) / (one.hi.x - one.lo.x), 1.3, accuracy: 0.01)
    }
}
