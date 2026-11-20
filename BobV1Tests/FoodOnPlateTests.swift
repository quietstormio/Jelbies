//
//  FoodOnPlateTests.swift
//  food-on-plate-r1 (the owner 2026-11-19: "The foods not on the plate what's the point of it"): every piece of every food that is served in pieces lies on the platter's flat top
//  with a small margin, for 1, 2 and 3 diners (every place), at home and at the café (same layouts; the café's tray is its table skin), in the layouts the game can be in:
//  the ends layout at the end seats 1.12 / 1.2 / 1.25 (+ the café's 1.25) and the wide row (-MealEnds 0). Pieces rest on the platter (not floating, not sunk); the ends layout's tray
//  has no raised short-side rim under the platter; drinks get no platter.
//

import XCTest
import simd
@testable import BobV1

@MainActor
final class FoodOnPlateTests: XCTestCase {
    static let margin: Float = 0.008
    typealias Config = (name: String, n: Int, ends: Bool, sx: Float)
    static let configs: [Config] = [
        ("1", 1, false, 1.11), ("2", 2, false, 1.11),
        ("3 ends 1.12", 3, true, 1.12), ("3 ends 1.2", 3, true, 1.2), ("3 ends 1.25", 3, true, 1.25), ("3 wide 1.11", 3, false, 1.11), ("3 wide 1.45", 3, false, 1.45)]

    private var saved: (Bool, Float, Bool)?
    override func setUp() { saved = (DiningLayout.ends, DiningLayout.sideX, DiningLayout.reachFood) }
    override func tearDown() { if let s = saved { (DiningLayout.ends, DiningLayout.sideX, DiningLayout.reachFood) = s } }

    /// Every food served in pieces: the Feed picker's berries + pizza, the store foods and the café treats.
    static func foods() -> [Consumable] {
        Consumables.all.filter { $0.kind == .food } + CafeTreatID.allCases.map { Consumables.cafeFood($0) }.filter { $0.piece != nil }
    }
    private func layout(_ c: Config) -> TrayLayout {
        DiningLayout.ends = c.ends; DiningLayout.sideX = c.sx; DiningLayout.reachFood = true
        return DiningLayout.make(n: c.n)
    }

    func testEveryPieceLiesOnThePlatterTop() {
        var checked = 0
        for c in Self.configs {
            let L = layout(c)
            for f in Self.foods() {
                let pizza = f.pizzaLayout || f.id == Consumables.pizza.id
                let P = DiningModels.platter(layout: L, pizza: pizza)
                let b = RoomMeshBuilder(); b.material = .plain
                f.serving?(b, ServingState(n: c.n, bitesLeft: Array(repeating: 3, count: c.n)), f.palette, L)
                var worst: Float = -1, lowest: Float = 9
                for v in b.mesh.vertices {
                    worst = max(worst, P.distance(x: v.pos.x, z: v.pos.z)); lowest = min(lowest, v.pos.y)
                }
                XCTAssertFalse(b.mesh.vertices.isEmpty, "\(f.id) \(c.name)")
                XCTAssertLessThanOrEqual(worst, -Self.margin, "\(f.id) at \(c.name): a piece reaches \(worst) m from the platter's edge (needs <= -\(Self.margin))")
                XCTAssertGreaterThanOrEqual(lowest - Platter.floorY, -0.002, "\(f.id) at \(c.name): a piece sinks into the platter")
                XCTAssertLessThanOrEqual(lowest - Platter.floorY, 0.012, "\(f.id) at \(c.name): a piece floats \(lowest - Platter.floorY) above the platter")
                // each place on its own (every place's pieces, one diner left)
                for place in 0..<c.n {
                    for j in 0..<3 {
                        let skip = Set((0..<(3 * c.n)).filter { $0 != place * 3 + j })
                        let one = RoomMeshBuilder(); one.material = .plain
                        f.serving?(one, ServingState(n: c.n, bitesLeft: Array(repeating: 3, count: c.n), skipped: skip), f.palette, L)
                        XCTAssertFalse(one.mesh.vertices.isEmpty, "\(f.id) \(c.name) place \(place) piece \(j)")
                        for v in one.mesh.vertices { XCTAssertLessThanOrEqual(P.distance(x: v.pos.x, z: v.pos.z), -Self.margin, "\(f.id) \(c.name) place \(place) piece \(j)") }
                    }
                }
                checked += 1
            }
        }
        XCTAssertGreaterThan(checked, 100)
    }

    /// The café's lounge cups (one per place, on the same anchors) and the empty café table sit on the platter too.
    func testCafeCupsAndEmptyTable() {
        for c in Self.configs {
            let L = layout(c)
            let P = DiningModels.platter(layout: L)
            for t in [CafeTreatID.cocoa, .latte, .juice] {
                let f = CafePlate.cups(Dictionary(uniqueKeysWithValues: (0..<c.n).map { ($0, t) }))
                let b = RoomMeshBuilder(); b.material = .plain
                f.serving?(b, ServingState(n: c.n, bitesLeft: Array(repeating: 3, count: c.n)), f.palette, L)
                XCTAssertFalse(b.mesh.vertices.isEmpty)
                for v in b.mesh.vertices { XCTAssertLessThanOrEqual(P.distance(x: v.pos.x, z: v.pos.z), -Self.margin, "cups \(t) \(c.name)") }
            }
            let g = DiningModels.trayGroup(layout: L, serving: CafePlate.emptyTable, state: ServingState(n: c.n, bitesLeft: Array(repeating: 3, count: c.n)), theme: RoomTheme())
            XCTAssertGreaterThan(g.opaque.vertices.count, 100, "the empty café table still shows the platter")
        }
    }

    /// The built platter: its flat top is at the old plate's floor height, covers exactly the shape, and the lip never rises above the pieces' resting height (7.5 mm).
    func testPlatterMeshMatchesItsShape() {
        for c in Self.configs {
            let L = layout(c)
            let P = DiningModels.platter(layout: L)
            let m = DiningModels.platterMesh(P, theme: RoomTheme())
            let flat = m.vertices.filter { abs($0.pos.y - Platter.floorY) < 1e-5 && $0.normal.y > 0.99 }
            XCTAssertFalse(flat.isEmpty)
            XCTAssertEqual(flat.map { $0.pos.x }.max() ?? 0, P.cx + P.hx, accuracy: 1e-3, c.name)
            XCTAssertEqual(flat.map { $0.pos.x }.min() ?? 0, P.cx - P.hx, accuracy: 1e-3, c.name)
            XCTAssertEqual(flat.map { $0.pos.z }.max() ?? 0, P.cz + P.hz, accuracy: 1e-3, c.name)
            XCTAssertEqual(flat.map { $0.pos.z }.min() ?? 0, P.cz - P.hz, accuracy: 1e-3, c.name)
            XCTAssertLessThanOrEqual(m.vertices.map { $0.pos.y }.max() ?? 9, Platter.floorY + 0.008, "the lip stays low")
            XCTAssertGreaterThanOrEqual(m.vertices.map { $0.pos.y }.min() ?? 0, DiningDims.trayTop, "the platter rests on the tray's top")
            let theme = RoomTheme()
            let g = DiningModels.trayGroup(layout: L, serving: Consumables.sushi, state: ServingState(n: c.n, bitesLeft: Array(repeating: 3, count: c.n)), theme: theme)
            let b = RoomMeshBuilder(); b.material = .plain
            Consumables.sushi.serving?(b, ServingState(n: c.n, bitesLeft: Array(repeating: 3, count: c.n)), Consumables.sushi.palette, L)
            XCTAssertEqual(g.opaque.vertices.count, DiningModels.tray(layout: L, theme: theme).vertices.count + DiningModels.plate(layout: L, theme: theme).vertices.count + b.mesh.vertices.count, c.name)
            XCTAssertEqual(DiningModels.plate(layout: L, theme: theme).vertices.count, m.vertices.count, "the platter is what is drawn (\(c.name))")
        }
    }

    /// Ends layout: the tray has no raised short-side rim (the platter lies over the bed to the tray's edge); the far and near rims stay; the footprint and handles are as before.
    func testEndsTrayHasNoShortSideRim() {
        let L = layout(("3 ends 1.25", 3, true, 1.25))
        XCTAssertTrue(L.arcToCentre)
        let v = DiningModels.tray(layout: L, theme: RoomTheme()).vertices
        XCTAssertLessThanOrEqual(v.filter { abs($0.pos.x) > 0.3 && abs($0.pos.x) < 0.56 && abs($0.pos.z) < 0.5 }.map { $0.pos.y }.max() ?? 0, DiningDims.trayTop + 0.004, "nothing stands up from the bed at the two ends")
        XCTAssertGreaterThan(v.map { $0.pos.y }.max() ?? 0, DiningDims.trayTop + 0.03, "the far and near rims remain")
        XCTAssertEqual(L.half, SIMD2(0.55, 0.6)); XCTAssertEqual(L.colliderHalf, SIMD2(0.45, 0.3))
    }

    /// Drinks: no plate, no platter (the cup and straws stand on the bare tray as before).
    func testDrinksGetNoPlatter() {
        for c in Self.configs {
            DiningLayout.ends = c.ends; DiningLayout.sideX = c.sx; DiningLayout.reachFood = false
            let L = DiningLayout.make(n: c.n), theme = RoomTheme()
            XCTAssertFalse(L.arcToCentre)
            let g = DiningModels.trayGroup(layout: L, serving: Consumables.water, state: ServingState(n: c.n, bitesLeft: Array(repeating: 2, count: c.n)), theme: theme)
            XCTAssertFalse(g.opaque.vertices.contains { abs($0.pos.y - Platter.floorY) < 1e-5 && $0.normal.y > 0.99 && abs($0.pos.x) < 0.2 && abs($0.pos.z) < 0.2 && $0.pos.y > DiningDims.trayTop + 0.015 }, "no platter floor (\(c.name))")
        }
    }
}
