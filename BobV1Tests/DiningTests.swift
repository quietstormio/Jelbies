import XCTest
import simd
@testable import BobV1

/// Test-only fork food: DEAD, unreachable code path (the user retired forks: every food is tossed from the nub). Kept only so the dormant machinery still compiles/passes.
enum TestFoods {
    static let fork = Consumable(id: "testfork", name: "Fork food", kind: .food, eatStyle: .fork, symbol: "fork.knife",
                                 palette: Consumables.pizza.palette, benefits: [.hunger: 0.1], serving: Consumables.pizza.serving)
}

@MainActor
final class DiningTests: XCTestCase {
    let aspects: [Float] = [440.0 / 956.0, 0.5]

    override func tearDown() { RoomLayout.dynamicBoxes = [] }

    // MARK: catalogue + shared timing

    func testCatalogue() {
        let ids = Consumables.all.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count, "ids are unique")
        XCTAssertEqual(Consumables.berries.eatStyle, .finger)
        XCTAssertEqual(Consumables.pizza.eatStyle, .finger, "pizza is finger food like the berries: the slice sticks to the nub and is tossed")
        XCTAssertNil(Consumables.with(id: "cake"), "cake is gone from the menu")
        XCTAssertTrue(Consumables.foods.allSatisfy { $0.eatStyle == .finger }, "every food is tossed from the nub: no fork food in the catalogue")
        XCTAssertEqual(Consumables.water.eatStyle, .sip)
        XCTAssertEqual(Consumables.foods.map(\.id), ["berries", "pizza"])
        XCTAssertEqual(Consumables.drinks.map(\.id), ["water", "soda"], "2+ drinks: the picker appears automatically")
        for c in Consumables.all { XCTAssertFalse(c.benefits.isEmpty, c.id); XCTAssertEqual(Consumables.with(id: c.id)?.id, c.id) }
        for f in Consumables.foods { XCTAssertNotNil(f.serving, f.id); XCTAssertNil(f.container) }
        for d in Consumables.drinks { XCTAssertNotNil(d.container, d.id); XCTAssertNotNil(d.strawColors, d.id); XCTAssertNil(d.serving) }
    }

    func testSharedTimingAndServingScale() {
        XCTAssertEqual(DiningTiming.bitesPerServing, 3)
        XCTAssertEqual(DiningTiming.gulpsPerDrink, 3)
        XCTAssertEqual(DiningTiming.beatsPerSecond, 1.5)
        XCTAssertEqual(DiningTiming.biteDuration, 2 / 1.5, accuracy: 1e-5)
        XCTAssertEqual(DiningTiming.servingDuration, 4, accuracy: 1e-4)
        XCTAssertEqual(DiningTiming.drinkDuration, 2, accuracy: 1e-4)
        XCTAssertEqual([1, 2, 3].map { DiningTiming.servingScale(n: $0) }, [1.0, 1.15, 1.3])
        for n in 1...3 { XCTAssertEqual(DiningLayout.make(n: n).scale, DiningTiming.servingScale(n: n)) }
    }

    // MARK: tray dimensions

    func testTrayDimensions() {
        let theme = RoomTheme(), sw = theme.swatches
        for n in 1...3 {
            let L = DiningLayout.make(n: n)
            let v = DiningModels.tray(layout: L, theme: theme).vertices
            func maxY(_ pred: (RoomVertex) -> Bool) -> Float { v.filter(pred).map { $0.pos.y }.max() ?? 0 }
            // a short, low tray: top about 0.25, rim a hair above, nothing taller than the rim
            XCTAssertEqual(DiningDims.trayTop, 0.25, accuracy: 1e-6)
            XCTAssertEqual(maxY { $0.normal.y > 0.95 && $0.pos.y < DiningDims.trayTop + 0.015 }, DiningDims.trayTop, accuracy: 4e-3, "top surface (n=\(n))")
            XCTAssertEqual(v.map { $0.pos.y }.max() ?? 0, DiningDims.trayTop + DiningDims.trayRim, accuracy: 6e-3, "raised rim")
            // short legs: the lowest points are at the floor, the legs end under the bed
            XCTAssertLessThan(v.map { $0.pos.y }.min() ?? 1, 0.01)
            XCTAssertLessThan(v.filter { $0.pos.y < 0.15 }.map { $0.pos.x }.max() ?? 9, L.half.x, "legs stand inside the tray's footprint")
            // two small handles at the ends stick out past the rim
            XCTAssertGreaterThan(v.map { $0.pos.x }.max() ?? 0, L.half.x + 0.1)
            XCTAssertLessThan(v.map { $0.pos.x }.min() ?? 0, -L.half.x - 0.1)
            // the top panel is lighter than the bed / rim shades
            let top = v.filter { $0.normal.y > 0.95 && abs($0.pos.y - (DiningDims.trayTop + 0.002)) < 1e-3 }
            XCTAssertFalse(top.isEmpty)
            func lum(_ c: SIMD3<Float>) -> Float { 0.2126 * c.x + 0.7152 * c.y + 0.0722 * c.z }
            XCTAssertGreaterThan(lum(SIMD3(top[0].color.x, top[0].color.y, top[0].color.z)), lum(sw[2]) * 1.1, "lighter top")
        }
    }

    /// His rest nub is a 0.15-radius ball at (0.55, 0.46, 0.06): a forward pitch of ~25 degrees (about the feet) and a ~8% crouch must bring
    /// its underside below the tray top, at a lateral reach inside his stubby arm's rest offset.
    func testTiltedNubCanReachTheTray() {
        let tip = BobForm.armTip, r = BobForm.armTipR
        XCTAssertEqual(Float(tip.y - r), 0.31, accuracy: 0.01, "rest nub underside ~0.31, just above the tray top + pieces")
        let th = 25.0 * Double.pi / 180, crouch = 0.92
        let y = (tip.y * cos(th) - tip.z * sin(th)) * crouch
        let underside = y - r
        XCTAssertLessThan(underside, Double(DiningDims.trayTop), "a tilted, crouched nub reaches the tray top")
        let forward = tip.z * cos(th) + tip.y * sin(th)
        XCTAssertGreaterThan(forward, 0.2, "and it has swung forward over the tray")
        // berries sit at tray top + ~0.06: still within the same reach
        XCTAssertLessThan(underside, Double(DiningDims.trayTop + 0.08))
    }

    // MARK: places

    func testPlacesForOneToThreeBlobs() {
        let counts = [1, 2, 3]
        for n in counts {
            let L = DiningLayout.make(n: n)
            XCTAssertEqual(L.places.count, n)
            // never overlapping each other
            for i in 0..<n { for j in (i + 1)..<max(n, i + 1) {
                XCTAssertGreaterThanOrEqual(simd_length(L.places[i].rel - L.places[j].rel), 2 * DiningDims.standRadius, "n=\(n) places \(i),\(j)")
            } }
            // on the far side / left / right, facing the camera (yaw angled inward for the sides)
            XCTAssertLessThan(L.places[0].rel.y, -0.5)
            if n == 1 { XCTAssertEqual(L.places[0].yaw, 0); XCTAssertEqual(L.places[0].rel.x, 0) }
            if n == 2 { XCTAssertLessThan(L.places[0].rel.x, 0); XCTAssertGreaterThan(L.places[1].rel.x, 0); XCTAssertGreaterThan(L.places[0].yaw, 0); XCTAssertLessThan(L.places[1].yaw, 0) }
            if n == 3 { XCTAssertEqual(L.places[0].rel.x, 0); XCTAssertLessThan(L.places[1].rel.x, 0); XCTAssertGreaterThan(L.places[2].rel.x, 0) }
            for (i, p) in L.places.enumerated() {
                XCTAssertGreaterThan(cosf(p.yaw), 0.4, "faces toward the camera side")
                // the walk resolver does not push a Blob (footprint 0.7) off his place: the collider stays under the tray
                let box = RoomLayout.FlatBox(centre: .zero, half: L.colliderHalf, height: 0.3)
                XCTAssertGreaterThanOrEqual(RoomLayout.boxDistanceXZ(p.rel, box), 0.69, "n=\(n) place \(i)")
                // mouth anchor is in front of him at mouth height
                let m = L.mouthRel(i)
                XCTAssertEqual(simd_length(SIMD2(m.x, m.z) - p.rel), DiningDims.mouthForward, accuracy: 1e-4)
                XCTAssertEqual(m.y, DiningDims.mouthHeight)
            }
        }
    }

    func testWiderTrayForTwoAndThreeAndNoBellyOverTheCorners() {
        XCTAssertEqual(DiningLayout.make(n: 1).half.x, 0.78); XCTAssertEqual(DiningLayout.make(n: 1).half.y, 0.34, "the N=1 tray is unchanged")
        let L2 = DiningLayout.make(n: 2), L3 = DiningLayout.make(n: 3)
        XCTAssertEqual(L2.half.x / 0.95, 1.17, accuracy: 0.03); XCTAssertEqual(L3.half.x / 0.85, 1.17, accuracy: 0.03, "15-20 % wider")
        // N = 3: all three stand in a row on the far side, wholly behind the tray (no belly over a corner or a handle)
        for i in 0..<3 { XCTAssertLessThanOrEqual(L3.places[i].rel.y + 0.42, -L3.half.y + 0.0001, "Blob \(i) behind the tray") }
        // every Blob's REAL skin (BobForm.sdf) clears the tray's bed and rim (every vertex of the tray) by >= 0.01
        for L in [L2, L3] {
            let tray = DiningModels.tray(layout: L, theme: RoomTheme()).vertices
            for (i, pl) in L.places.enumerated() {
                var gap = Double.infinity
                for v in tray {
                    // body frame of this Blob: rotate the world offset by -yaw (his facing = +z)
                    let dx = v.pos.x - pl.rel.x, dz = v.pos.z - pl.rel.y, c = cosf(pl.yaw), sn = sinf(pl.yaw)
                    let bx = dx * c - dz * sn, bz = dx * sn + dz * c
                    gap = min(gap, BobForm.sdf(SIMD3(Double(bx), Double(v.pos.y), Double(bz))))
                }
                print("SKIN GAP n=\(L.n) place \(i): \(gap)")
                XCTAssertGreaterThanOrEqual(gap, 0.01, "n=\(L.n) place \(i): skin-to-tray gap \(gap)")
            }
        }
    }

    func testSpotNeverOverlapsBobAndStaysOnScreen() {
        for n in 1...3 {
            let L = DiningLayout.make(n: n)
            for aspect in aspects {
                var x: Float = -2.0
                while x <= 2.0 {
                    var z: Float = -2.4
                    while z <= 3.0 {
                        let bob = SIMD2<Float>(x, z)
                        let o = DiningSpot.choose(bob: bob, layout: L, aspect: aspect)
                        XCTAssertGreaterThanOrEqual(DiningSpot.distance(from: bob, origin: o, layout: L), DiningSpot.bobClearance - 1e-4, "n=\(n) bob \(bob) -> \(o)")
                        XCTAssertTrue(DiningSpot.onScreen(origin: o, layout: L, aspect: aspect), "off screen n=\(n) bob \(bob) aspect \(aspect) -> \(o)")
                        z += 0.6
                    }
                    x += 0.8
                }
            }
        }
    }

    func testSameSpotWhenFree() {
        for n in 1...3 {
            let L = DiningLayout.make(n: n)
            XCTAssertEqual(DiningSpot.choose(bob: SIMD2(-2, -2.2), layout: L), DiningSpot.preferred)
            XCTAssertEqual(DiningSpot.choose(bob: SIMD2(-2, -2.2), layout: L), DiningSpot.choose(bob: SIMD2(2, -2.4), layout: L))
            XCTAssertNotEqual(DiningSpot.choose(bob: DiningSpot.preferred, layout: L), DiningSpot.preferred, "he is standing on the tray's spot")
        }
    }

    // MARK: shared serving scaled for N

    func testBerriesThreePerBlobOnABiggerPlate() {
        let theme = RoomTheme()
        var counts: [Int] = []
        var plateR: [Float] = []
        for n in 1...3 {
            let L = DiningLayout.make(n: n)
            let b = RoomMeshBuilder(); b.material = .plain
            Consumables.berries.serving!(b, ServingState(n: n, bitesLeft: Array(repeating: 3, count: n)), Consumables.berries.palette, L)
            counts.append(b.mesh.vertices.count)
            plateR.append(DiningModels.plate(layout: L, theme: theme).vertices.map { simd_length(SIMD2($0.pos.x, $0.pos.z)) }.max() ?? 0)
            // berries do not overlap each other and sit on the plate
            var pts: [SIMD3<Float>] = []
            for i in 0..<n { for j in 0..<3 { pts.append(DiningModels.berryAnchor(layout: L, place: i, index: j)) } }
            XCTAssertEqual(pts.count, 3 * n)
            for a in 0..<pts.count { for c in (a + 1)..<max(pts.count, a + 1) {
                XCTAssertGreaterThan(simd_length(pts[a] - pts[c]), 2 * 0.065 * L.scale * 0.95, "n=\(n) berries \(a),\(c)")
            } }
            for p in pts { XCTAssertLessThan(simd_length(SIMD2(p.x, p.z)) + 0.065 * L.scale, DiningDims.plateRadius * L.scale, "berry on the plate (n=\(n))") }
        }
        XCTAssertEqual(counts[1], counts[0] * 2); XCTAssertEqual(counts[2], counts[0] * 3, "3 berries per Blob")
        XCTAssertEqual(plateR[1] / plateR[0], 1.15, accuracy: 0.01); XCTAssertEqual(plateR[2] / plateR[0], 1.3, accuracy: 0.01)
        // pieces disappear per bite
        let L = DiningLayout.make(n: 2)
        var last = Int.max
        for left in stride(from: 3, through: 0, by: -1) {
            let b = RoomMeshBuilder(); b.material = .plain
            Consumables.berries.serving!(b, ServingState(n: 2, bitesLeft: [left, 3]), Consumables.berries.palette, L)
            XCTAssertLessThan(b.mesh.vertices.count, last); last = b.mesh.vertices.count
        }
    }

    func testPizzaThreeSlicesPerBlobAndScalesWithBlobs() {
        let theme = RoomTheme()
        var widths: [Float] = []
        for n in 1...3 {
            let L = DiningLayout.make(n: n)
            let b = RoomMeshBuilder(); b.material = .plain
            Consumables.pizza.serving!(b, ServingState(n: n, bitesLeft: Array(repeating: 3, count: n)), Consumables.pizza.palette, L)
            widths.append((b.mesh.vertices.map { $0.pos.x }.max() ?? 0) - (b.mesh.vertices.map { $0.pos.x }.min() ?? 0))
            // each slice is the same mesh: 3n slices => vertex count is a multiple of one slice
            let one = RoomMeshBuilder(); one.material = .plain
            DiningModels.pizzaSlice(one, centre: .zero, yaw: 0, palette: Consumables.pizza.palette, scale: L.scale)
            XCTAssertEqual(b.mesh.vertices.count, one.mesh.vertices.count * 3 * n, "3 slices per Blob (n=\(n))")
            // finger food: nothing but tray + plate + slices on the tray
            let g = DiningModels.trayGroup(layout: L, serving: Consumables.pizza, state: ServingState(n: n, bitesLeft: Array(repeating: 3, count: n)), theme: theme)
            XCTAssertEqual(g.opaque.vertices.count, DiningModels.tray(layout: L, theme: theme).vertices.count + DiningModels.plate(layout: L, theme: theme).vertices.count + b.mesh.vertices.count)
            // slices lie on the plate, inside the tray, never below the plate floor
            let ys = b.mesh.vertices.map { $0.pos.y }
            XCTAssertGreaterThan(ys.min() ?? 0, DiningDims.plateFloorY - 0.01)
            XCTAssertLessThan(ys.max() ?? 9, DiningDims.plateFloorY + 0.09 * L.scale)
            XCTAssertLessThan(b.mesh.vertices.map { abs($0.pos.x) }.max() ?? 9, L.half.x - 0.05)
        }
        XCTAssertGreaterThan(widths[1], widths[0]); XCTAssertGreaterThan(widths[2], widths[0])
        // the pie (one Blob): three DISTINCT slices fanned around one centre, tips toward the centre, crusts outward, all on the plate and within the nub's reach
        let L1 = DiningLayout.make(n: 1)
        let pie = DiningModels.pizzaPie(layout: L1, place: 0), plate = DiningModels.pizzaPlate(L1)
        var mids: [SIMD2<Float>] = []
        for j in 0..<3 {
            let a = DiningModels.pizzaAnchor(layout: L1, place: 0, index: j), y = DiningModels.sliceYaw(layout: L1, place: 0, index: j)
            let tip = SIMD2(sinf(y), cosf(y)), toCentre = pie.centre - SIMD2(a.x, a.z)
            XCTAssertGreaterThan(simd_dot(tip, simd_normalize(toCentre)), 0.99, "tip toward the pie centre (slice \(j))")
            XCTAssertLessThan(simd_length(SIMD2(a.x, a.z) - L1.places[0].rel), 0.60, "slice \(j) is within the nub's reach")
            mids.append(SIMD2(a.x, a.z))
            let one = RoomMeshBuilder(); one.material = .plain
            DiningModels.pizzaSlice(one, centre: a, yaw: y, palette: Consumables.pizza.palette, scale: 1)
            for v in one.mesh.vertices {
                XCTAssertLessThan(simd_length(SIMD2(v.pos.x, v.pos.z) - SIMD2(0, plate.cz)), plate.r + 0.005, "slice \(j) lies on the plate")
            }
        }
        for (a, c) in [(0, 1), (1, 2), (0, 2)] { XCTAssertGreaterThan(simd_length(mids[a] - mids[c]), 0.09, "slices \(a) and \(c) are distinct") }
        // bigger than the first version (0.176 x 0.116): about 0.26 long and 0.16 wide, a wedge about the size of his nub
        XCTAssertEqual(2 * DiningModels.sliceHalfLength, 0.26, accuracy: 0.01)
        XCTAssertEqual(2 * DiningModels.sliceHalfWidth, 0.16, accuracy: 0.01)
        // slices of neighbouring fan positions do not overlap at the crust: chord between crust middles > slice width
        XCTAssertGreaterThan(2 * (DiningModels.sliceMid + DiningModels.sliceHalfLength) * sinf(DiningModels.sliceFan / 2), 2 * DiningModels.sliceHalfWidth - 0.001)
        // a standalone held fork mesh exists (kept for the dormant fork machinery)
        let fm = DiningModels.fork(withBite: false), fb = DiningModels.fork(withBite: true)
        XCTAssertGreaterThan(fm.vertices.count, 100); XCTAssertGreaterThan(fb.vertices.count, fm.vertices.count)
        XCTAssertEqual(fm.vertices.map { $0.pos.z }.max() ?? 0, 0.335, accuracy: 0.01)
        XCTAssertEqual(DiningModels.forkTip.z, 0.27, accuracy: 1e-6)
        // slices leave the plate one by one, gone when everybody is done
        let L = DiningLayout.make(n: 2)
        var last = Int.max
        for left in stride(from: 6, through: 0, by: -1) {
            let b = RoomMeshBuilder(); b.material = .plain
            Consumables.pizza.serving!(b, ServingState(n: 2, bitesLeft: [left / 2 + left % 2, left / 2]), Consumables.pizza.palette, L)
            XCTAssertLessThan(b.mesh.vertices.count, last); last = b.mesh.vertices.count
        }
        XCTAssertEqual(last, 0)
    }

    func testPizzaSlicesLeaveThePlateOneByOne() {
        let d = DiningSet(); defer { d.reset() }
        d.spawn(serving: Consumables.pizza, n: 1, bobAt: SIMD2(-2, -2.2))
        d.update(dt: 3)
        let theme = RoomTheme()
        let full = d.frame(theme: theme)!.opaque.vertices.count
        var one = RoomMeshBuilder(); one.material = .plain
        DiningModels.pizzaSlice(one, centre: .zero, yaw: 0, palette: Consumables.pizza.palette, scale: 1)
        let slice = one.mesh.vertices.count
        for k in 1...3 {
            XCTAssertTrue(d.beginBite(place: 0))
            XCTAssertEqual(d.frame(theme: theme)!.opaque.vertices.count, full - (k - 1) * slice, "in hand: leaves the plate, drawn in his hand")
            d.finishBite(place: 0)
            XCTAssertEqual(d.frame(theme: theme)!.opaque.vertices.count, full - k * slice, "swallowed: gone (\(k) of 3)")
        }
        XCTAssertEqual(d.bitesLeft, [0])
        one = RoomMeshBuilder()
    }

    func testDrinkIsBiggerForMoreBlobs() {
        for d in Consumables.drinks {
            var tops: [Float] = [], widths: [Float] = []
            for n in 1...3 {
                let L = DiningLayout.make(n: n)
                let cm = DiningModels.containerModel(d, layout: L)!
                tops.append(cm.openingY * L.scale)
                widths.append(((cm.opaque.vertices + cm.translucent.vertices).map { $0.pos.x }.max() ?? 0) * L.scale)
                XCTAssertGreaterThan(cm.opaque.vertices.count, 100, d.id)
            }
            // heights stay put (his straw tips must stay at his mouth height); the bottle grows in WIDTH with N
            XCTAssertEqual(tops[1], tops[0], accuracy: 1e-4, d.id); XCTAssertEqual(tops[2], tops[0], accuracy: 1e-4)
            XCTAssertEqual(widths[1] / widths[0], 1.15, accuracy: 1e-3, d.id); XCTAssertEqual(widths[2] / widths[0], 1.3, accuracy: 1e-3)
        }
        // water: see-through plastic walls over an opaque water column; soda: tinted translucent glass over an opaque fizzy liquid
        for d in Consumables.drinks {
            let m = DiningModels.containerModel(d, layout: DiningLayout.make(n: 1))!
            XCTAssertGreaterThan(m.translucent.vertices.count, 50, d.id)
            XCTAssertTrue(m.translucent.vertices.allSatisfy { $0.color.w < 1 }, d.id)
        }
        // the soda bottle is taller and slimmer than the water bottle
        let w1 = DiningModels.containerModel(Consumables.water, layout: DiningLayout.make(n: 1))!, s1 = DiningModels.containerModel(Consumables.soda, layout: DiningLayout.make(n: 1))!
        func wide(_ m: ContainerModel) -> Float { m.translucent.vertices.map { $0.pos.x }.max() ?? 0 }
        let kY = DiningDims.bottleY
        XCTAssertEqual(w1.openingY, 0.52 * kY, accuracy: 1e-5); XCTAssertEqual(s1.openingY, 0.60 * kY, accuracy: 1e-5)
        XCTAssertEqual(wide(w1), 0.115, accuracy: 0.004); XCTAssertEqual(wide(s1), 0.095, accuracy: 0.004)
    }

    // MARK: bottles: the specified silhouettes, open neck, no cap, level, bubbles

    func testBottleSilhouettesFollowTheSpecifiedProfiles() {
        // radius of the translucent wall at given heights (the lathe is smooth through the coarse points)
        func r(_ d: Consumable, _ y: Float) -> Float {
            let m = DiningModels.containerModel(d, layout: DiningLayout.make(n: 1))!
            let yy = y * DiningDims.bottleY                      // the profile heights are stretched by bottleY
            let v = m.translucent.vertices.min { abs($0.pos.y - yy) < abs($1.pos.y - yy) }!
            return abs(v.pos.y - yy) < 0.01 ? simd_length(SIMD2(v.pos.x, v.pos.z)) : -1
        }
        // water: straight body 0.115, neck 0.048
        XCTAssertEqual(r(Consumables.water, 0.25), 0.115, accuracy: 0.003); XCTAssertEqual(r(Consumables.water, 0.47), 0.048, accuracy: 0.003)
        XCTAssertEqual(r(Consumables.water, 0.12), 0.109, accuracy: 0.003, "grip groove at 0.12 is 0.006 in"); XCTAssertEqual(r(Consumables.water, 0.16), 0.109, accuracy: 0.003)
        XCTAssertEqual(r(Consumables.water, 0.14), 0.115, accuracy: 0.003, "between the two grooves")
        // soda: waist 0.075 at 0.16, bulge 0.092 at 0.24, tall narrow neck 0.034-0.036
        XCTAssertEqual(r(Consumables.soda, 0.16), 0.075, accuracy: 0.003); XCTAssertEqual(r(Consumables.soda, 0.24), 0.092, accuracy: 0.003)
        XCTAssertGreaterThan(r(Consumables.soda, 0.10), r(Consumables.soda, 0.16) + 0.015, "pinched waist")
        XCTAssertGreaterThan(r(Consumables.soda, 0.24), r(Consumables.soda, 0.16) + 0.01, "a gentle bulge above it")
        XCTAssertEqual(r(Consumables.soda, 0.55), 0.044, accuracy: 0.004)
        XCTAssertLessThan(r(Consumables.soda, 0.55), r(Consumables.water, 0.47), "a narrower neck than the water bottle's")
    }

    func testBottlesAreOpenNeckedWithoutACapAndShowTheLevel() {
        for d in Consumables.drinks {
            let L = DiningLayout.make(n: 1)
            let cm = DiningModels.containerModel(d, layout: L)!
            let all = cm.opaque.vertices + cm.translucent.vertices
            XCTAssertEqual(all.map { $0.pos.y }.max() ?? 0, cm.openingY, accuracy: 0.012, "\(d.id): nothing rises above the opening: no cap")
            let capVerts = all.filter { $0.pos.y > cm.openingY - 0.003 && simd_length(SIMD2($0.pos.x, $0.pos.z)) < cm.openingRadius - 0.004 }
            XCTAssertTrue(capVerts.isEmpty, "\(d.id): open neck, no cap")
            // the liquid level steps down with the fill, to nothing
            let top = (d.id == "water" ? DiningModels.waterLevels.full : DiningModels.sodaLevels.full) * DiningDims.bottleY
            func liquidTop(_ f: Float) -> Float {
                let m = DiningModels.containerModel(d, layout: L, fill: f)!
                return (m.opaque.vertices.filter { $0.pos.y < top + 0.01 && $0.normal.y > 0.99 && simd_length(SIMD2($0.pos.x, $0.pos.z)) < 0.001 }.map { $0.pos.y }.max()) ?? -1
            }
            XCTAssertEqual(liquidTop(1), top, accuracy: 0.03, "\(d.id) full: 0.36 / 0.44")
            XCTAssertGreaterThan(liquidTop(1), liquidTop(0.67)); XCTAssertGreaterThan(liquidTop(0.67), liquidTop(0.34)); XCTAssertEqual(liquidTop(0), -1, "empty: no liquid")
        }
        // a few bubbles in the soda: liquid + 7 tiny spheres
        let L = DiningLayout.make(n: 1)
        let fullS = DiningModels.containerModel(Consumables.soda, layout: L, fill: 1)!.opaque.vertices.count
        let noBubbles = DiningModels.containerModel(Consumables.soda, layout: L, fill: 0)!.opaque.vertices.count
        XCTAssertGreaterThan(fullS - noBubbles, 100, "liquid + bubbles")
    }

    // MARK: straws: up out of the neck, ONE elbow, a short arm toward the place

    func testEveryStrawRisesOutOfTheNeckBendsOnceAndPointsAtItsPlace() {
        for d in Consumables.drinks { for n in 1...3 {
            let L = DiningLayout.make(n: n), s = L.scale
            let cm = DiningModels.containerModel(d, layout: L)!, rim = DiningDims.trayTop + cm.openingY * s
            var tips: [SIMD3<Float>] = []
            for i in 0..<n {
                let c = DiningModels.strawPath(layout: L, drink: d, place: i)
                let top = c.map { $0.y }.max()!, tip = c.last!
                XCTAssertEqual(top, tip.y, accuracy: 1e-4, "\(d.id) n=\(n) place \(i): the tip is the highest point, never lower than the bend")
                if n > 1 {
                    // the chosen N >= 2 formation: up out of the neck, ONE ~90 degree elbow, a long near-horizontal arm out to the place's mouth anchor
                    XCTAssertLessThan(simd_length(SIMD2(tip.x, tip.z) - L.sipTipXZ(i)), 1e-4, "arm ends in front of his mouth")
                    let elbow = max(rim + 0.012, DiningDims.mouthRestHeight - 0.005)
                    XCTAssertEqual(tip.y, elbow + 0.01, accuracy: 1e-4, "tip a hair above the bend")
                    XCTAssertGreaterThan(tip.y, 0.66); XCTAssertLessThan(tip.y, 0.72, "\(d.id) n=\(n) place \(i): arm end at his mouth height")
                    let a = c[c.count - 2], b = c.last!, dd = simd_normalize(b - a)
                    XCTAssertEqual(acosf(dd.y) * 180 / .pi, 90, accuracy: 10)
                    XCTAssertGreaterThan(simd_length(SIMD2(tip.x - c[0].x, tip.z - c[0].z)), 0.25, "a long arm")
                    var sharp = 0
                    for q in 1..<(c.count - 1) where simd_dot(simd_normalize(c[q] - c[q - 1]), simd_normalize(c[q + 1] - c[q])) < 0.995 { sharp += 1 }
                    XCTAssertLessThanOrEqual(sharp, 9, "a single rounded elbow")
                    var worst: Float = 0
                    for k in 1..<(c.count - 1) { worst = max(worst, acosf(min(max(simd_dot(simd_normalize(c[k] - c[k - 1]), simd_normalize(c[k + 1] - c[k])), -1), 1))) }
                    XCTAssertLessThan(worst, 45 * .pi / 180)
                    tips.append(tip)
                    continue
                }
                // N = 1: ONE straight straw slanted out of the neck toward his mouth, 25-35 degrees from vertical
                let dir = simd_normalize(tip - c[0])
                XCTAssertEqual(c.count, 24)
                for q in 1..<c.count { XCTAssertGreaterThan(simd_dot(simd_normalize(c[q] - c[q - 1]), dir), 0.9999, "\(d.id): perfectly straight") }
                let lean = acosf(dir.y) * 180 / .pi
                XCTAssertGreaterThanOrEqual(lean, 25, "\(d.id): lean \(lean)"); XCTAssertLessThanOrEqual(lean, 35, "\(d.id): lean \(lean)")
                // SIDEWAYS: the neck is to his right (screen-left), 0.12-0.18 off his mouth line, and the straw leans across to it, 20-35 degrees in the screen plane
                XCTAssertLessThanOrEqual(L.drinkCentre.x, -0.12 + 1e-5); XCTAssertGreaterThanOrEqual(L.drinkCentre.x, -0.18)
                XCTAssertGreaterThan(dir.x, 0, "leans up and across toward his mouth line")
                let screenLean = atanf(dir.x / dir.y) * 180 / .pi
                XCTAssertGreaterThanOrEqual(screenLean, 20); XCTAssertLessThanOrEqual(screenLean, 35, "\(d.id): screen-plane lean \(screenLean)")
                XCTAssertEqual(tip.x, 0, accuracy: 1e-4, "the tip arrives on his mouth line")
                // it passes through the neck axis at the lip height, inside the neck
                let kRim = c.firstIndex { $0.y >= rim }!
                let atRim = c[kRim - 1] + (c[kRim] - c[kRim - 1]) * ((rim - c[kRim - 1].y) / (c[kRim].y - c[kRim - 1].y))
                XCTAssertLessThan(simd_length(SIMD2(atRim.x, atRim.z) - L.drinkCentre), 0.004, "\(d.id): leaves the neck at its axis")
                XCTAssertGreaterThan(tip.y - rim, 0.10, "\(d.id): a clearly visible straw above the neck (\(tip.y - rim))")
                XCTAssertEqual(tip.y, DiningDims.strawTipHeight, accuracy: 1e-5)
                XCTAssertLessThan(simd_length(SIMD2(tip.x, tip.z) - L.sipTipXZ(0)), 1e-4)
                tips.append(tip)
                XCTAssertLessThan(c.first!.y, rim)
            }
            for a in 0..<n { for c in (a + 1)..<max(n, a + 1) {
                XCTAssertGreaterThan(simd_length(tips[a] - tips[c]), 0.1, "\(d.id) n=\(n): straws fan apart")
            } }
            // N straws: the drink group gains exactly one tube per Blob
            let st = ServingState(n: n, bitesLeft: Array(repeating: 3, count: n))
            let g = DiningModels.trayGroup(layout: L, serving: d, state: st, forksResting: [], theme: RoomTheme())
            var expect = DiningModels.tray(layout: L, theme: RoomTheme()).vertices.count + cm.opaque.vertices.count
            for i in 0..<n {
                let tube = RoomMeshBuilder(); tube.material = .plain
                DiningModels.appendTube(tube, centre: DiningModels.strawPath(layout: L, drink: d, place: i), radius: DiningDims.strawRadius, color: SIMD3(1, 0, 0), stripe: SIMD3(1, 1, 1))
                expect += tube.mesh.vertices.count
            }
            XCTAssertEqual(g.opaque.vertices.count, expect, "\(d.id) n=\(n): exactly one straw per Blob")
        } }
    }

    /// His REAL rest skin (BobForm.sdf, body + arms + feet) at the stand pose vs every vertex of the tray on his side (bed, rim ends, legs): a clear gap.
    func testRestSkinClearsTheTrayAtTheStandPose() {
        let L = DiningLayout.make(n: 1), stand = L.places[0].rel
        let tray = DiningModels.tray(layout: L, theme: RoomTheme()).vertices
        var gap = Double.infinity
        for v in tray where v.pos.z < 0.1 {
            // body frame: +z = his facing (yaw 0), origin on his vertical axis, y up from the floor
            gap = min(gap, BobForm.sdf(SIMD3(Double(v.pos.x - stand.x), Double(v.pos.y), Double(v.pos.z - stand.y))))
        }
        for k in 0...40 {                                                      // the near bed edge, finely
            let x = -L.half.x + Float(k) / 40 * 2 * L.half.x
            for y in stride(from: Float(0.17), through: DiningDims.trayTop, by: 0.01) {
                gap = min(gap, BobForm.sdf(SIMD3(Double(x - stand.x), Double(y), Double(-(L.half.y - L.trayCentreZ) - stand.y))))
            }
        }
        print("REAL GAP skin-to-tray:", gap)
        XCTAssertGreaterThanOrEqual(gap, 0.01, "skin-to-tray gap \(gap)")
        XCTAssertTrue(DiningModels.tray(layout: L, theme: RoomTheme()).vertices.allSatisfy { $0.pos.z >= -(L.half.y - L.trayCentreZ) - 1e-3 })
    }

    // MARK: N = 2 and 3: every straw tip is in front of its own Blob's mouth, and only his

    func testEachStrawTipIsInFrontOfItsOwnBlobsMouthAndNoOthers() {
        var rows: [String] = []
        for d in Consumables.drinks { for n in 1...3 {
            let L = DiningLayout.make(n: n)
            let tips = (0..<n).map { DiningModels.strawPath(layout: L, drink: d, place: $0).last! }
            for i in 0..<n {
                let mouth = L.restMouthRel(i)
                let dist = simd_length(tips[i] - mouth)
                rows.append("\(d.id) n=\(n) place \(i): tip-to-mouth \(String(format: "%.3f", dist)) (tip y \(String(format: "%.3f", tips[i].y)))")
                // N >= 2: within 0.05 of his mouth; N = 1 (short 65 degree arm, bend just above the lip; the soda rim alone is 0.67): in front of it at his mouth height, within 0.0755
                XCTAssertLessThanOrEqual(dist, n == 1 ? 0.075 : 0.05, "\(d.id) n=\(n) place \(i): tip within reach of his mouth")
                // 0.02-0.05 in front of the mouth, along his facing
                let f = SIMD3<Float>(sinf(L.places[i].yaw), 0, cosf(L.places[i].yaw))
                let ahead = simd_dot(tips[i] - mouth, f)
                XCTAssertGreaterThanOrEqual(ahead, 0.02); XCTAssertLessThanOrEqual(ahead, 0.05)
                XCTAssertGreaterThanOrEqual(tips[i].y, 0.66); XCTAssertLessThanOrEqual(tips[i].y, 0.75)
                // only his: every other Blob's mouth is far from this tip
                for j in 0..<n where j != i {
                    XCTAssertGreaterThan(simd_length(tips[i] - L.restMouthRel(j)), 0.5, "\(d.id) n=\(n): straw \(i) is out of reach of Blob \(j)")
                    XCTAssertLessThan(dist, simd_length(tips[i] - L.restMouthRel(j)) * 0.2)
                }
                // the straw does not cross another straw in the plan view (their arms fan from the bottle, no intersections beyond the shared root)
                let pi = DiningModels.strawPath(layout: L, drink: d, place: i).map { SIMD2($0.x, $0.z) }
                for j in (i + 1)..<max(n, i + 1) {
                    let pj = DiningModels.strawPath(layout: L, drink: d, place: j).map { SIMD2($0.x, $0.z) }
                    for a in 1..<pi.count { for c in 1..<pj.count {
                        let p = pi[a - 1], r = pi[a] - p, q = pj[c - 1], sv = pj[c] - q
                        let den = r.x * sv.y - r.y * sv.x
                        guard abs(den) > 1e-9 else { continue }
                        let t = ((q.x - p.x) * sv.y - (q.y - p.y) * sv.x) / den, u = ((q.x - p.x) * r.y - (q.y - p.y) * r.x) / den
                        if t > 0 && t < 1 && u > 0 && u < 1 {
                            // only allowed inside the neck footprint (shared root area)
                            XCTAssertLessThan(simd_length(p + r * t - L.drinkCentre), 0.08 * L.scale, "\(d.id) n=\(n): straws \(i),\(j) cross away from the neck")
                        }
                    } }
                }
            }
            // top-down data for the schematic image
            var js = "TOPDOWN {\"drink\":\"\(d.id)\",\"n\":\(n),\"half\":[\(L.half.x),\(L.half.y)],\"cz\":\(L.trayCentreZ),\"bottle\":[\(L.drinkCentre.x),\(L.drinkCentre.y)],\"places\":["
            js += (0..<n).map { i in
                let m = L.restMouthRel(i), path = DiningModels.strawPath(layout: L, drink: d, place: i)
                return "{\"stand\":[\(L.places[i].rel.x),\(L.places[i].rel.y)],\"yaw\":\(L.places[i].yaw),\"mouth\":[\(m.x),\(m.z)],\"path\":[" + path.map { "[\($0.x),\($0.z),\($0.y)]" }.joined(separator: ",") + "]}"
            }.joined(separator: ",") + "]}"
            print(js)
        } }
        print("TIPROWS\n" + rows.joined(separator: "\n"))
    }

    // MARK: reach layout (one Blob): everything he eats from is inside the stubby arm's body-led reach

    func testOneBlobReachSeparationAndNoBodyOverlapOfThePlate() {
        let L = DiningLayout.make(n: 1), stand = L.places[0].rel
        var ps: [SIMD3<Float>] = []
        for j in 0..<3 { ps.append(DiningModels.berryAnchor(layout: L, place: 0, index: j)) }
        let dists = ps.map { simd_length(SIMD2($0.x, $0.z) - stand) }
        XCTAssertLessThanOrEqual(dists.min()!, DiningDims.reach, "nearest berry inside his reach: \(dists)")
        XCTAssertLessThanOrEqual(dists.max()!, DiningDims.reach, "all three berries are reachable: \(dists)")
        XCTAssertGreaterThanOrEqual(abs(L.places[0].rel.y), 0.70); XCTAssertLessThanOrEqual(abs(L.places[0].rel.y), 0.75, "stand 0.70-0.75 behind the tray centre")
        for a in 0..<3 { for c in (a + 1)..<3 { XCTAssertGreaterThanOrEqual(simd_length(ps[a] - ps[c]), 0.1235) } }
        // the berries stay on the plate
        for p in ps { XCTAssertLessThan(simd_length(SIMD2(p.x, p.z)) + 0.065, DiningDims.plateRadius) }
        // the plate is inside the tray, and his stand clears the thin collider by his footprint
        XCTAssertLessThanOrEqual(DiningDims.plateRadius, L.half.y - 0.06)
        let box = RoomLayout.FlatBox(centre: .zero, half: L.colliderHalf, height: 0.3)
        XCTAssertGreaterThanOrEqual(RoomLayout.boxDistanceXZ(stand, box), 0.69)
    }

    // MARK: straws

    func testStrawCentrelineSweepExactTipNoKinks() {
        let root = SIMD3<Float>(0.05, 0.35, 0.0), rim: Float = 0.7
        var targets: [SIMD3<Float>] = []
        for ix in -3...3 { for iz in -2...2 { for y in [Float(0.45), 0.64, 0.8, 1.0] {
            targets.append(SIMD3(Float(ix) * 0.25, y, Float(iz) * 0.25 - 0.1))
        } } }
        for target in targets where simd_length(SIMD2(target.x - root.x, target.z - root.z)) > 0.1 {
            let c = DiningModels.strawCentreline(root: root, rimY: rim, target: target)
            XCTAssertLessThan(simd_length(c.last! - target), 1e-3, "tip within 1 mm of \(target)")
            var worst: Float = 0
            for i in 1..<(c.count - 1) {
                let a = c[i] - c[i - 1], b = c[i + 1] - c[i]
                XCTAssertGreaterThan(simd_length(a), 1e-4); XCTAssertGreaterThan(simd_length(b), 1e-4)
                worst = max(worst, acosf(min(max(simd_dot(simd_normalize(a), simd_normalize(b)), -1), 1)))
            }
            XCTAssertLessThan(worst, 55 * .pi / 180, "kink \(worst * 180 / .pi) deg for target \(target)")
        }
        let b = RoomMeshBuilder(); b.material = .plain
        DiningModels.appendTube(b, centre: DiningModels.strawCentreline(root: root, rimY: rim, target: SIMD3(0.5, 0.64, 0.3)), radius: DiningDims.strawRadius,
                                color: SIMD3(1, 0.5, 0.6), stripe: SIMD3(1, 1, 1))
        XCTAssertGreaterThan(b.mesh.vertices.count, 300)
        XCTAssertTrue(b.mesh.vertices.allSatisfy { $0.pos.x.isFinite && $0.pos.y.isFinite && $0.pos.z.isFinite })
        XCTAssertEqual(DiningDims.strawRadius, 0.035)
    }

    func testSetStrawTipsAreTheWorldTipsOfEachPlacesStraw() {
        for n in 1...3 { for drink in Consumables.drinks {
            let d = DiningSet(); defer { d.reset() }
            d.spawn(serving: drink, n: n, bobAt: SIMD2(-2, -2.2))
            d.update(dt: 0.4)
            XCTAssertEqual(d.phase, .present)
            for i in 0..<n {
                let local = DiningModels.strawPath(layout: d.layout, drink: drink, place: i).last!
                XCTAssertLessThan(simd_length(d.strawTip(place: i)! - SIMD3(d.origin.x + local.x, local.y, d.origin.y + local.z)), 1e-4, "\(drink.id) n=\(n) place \(i)")
                // the tip is on the Blob's side of the bottle, not beyond the place
                let toTip = SIMD2(d.strawTip(place: i)!.x, d.strawTip(place: i)!.z) - d.places[i].stand
                XCTAssertLessThan(simd_length(toTip), simd_length(d.layout.drinkCentre + d.origin - d.places[i].stand) + 0.01)
            }
        } }
    }

    // MARK: pop / poof timing, removal

    func testPopPoofTimingAndRemoval() {
        for n in 1...3 {
            let d = DiningSet()
            defer { d.reset() }
            XCTAssertTrue(RoomLayout.dynamicBoxes.isEmpty)
            XCTAssertTrue(d.spawn(serving: Consumables.berries, n: n, bobAt: SIMD2(-2, -2.2)))
            XCTAssertFalse(d.spawn(serving: Consumables.pizza, n: n, bobAt: SIMD2(-2, -2.2)), "one tray at a time")
            XCTAssertEqual(RoomLayout.dynamicBoxes.count, 1)
            var peak: Float = 0, t: Float = 0, presentAt: Float?
            var midHalf: Float?
            let dt: Float = 1.0 / 60
            while t < 0.6 {
                d.update(dt: dt); t += dt
                peak = max(peak, d.scale)
                if abs(t - 0.1) < dt / 2 { midHalf = RoomLayout.dynamicBoxes.first?.half.x }
                if d.phase == .present && presentAt == nil { presentAt = t }
            }
            XCTAssertGreaterThan(peak, 1.06); XCTAssertLessThan(peak, 1.10)
            XCTAssertEqual(presentAt ?? 9, DiningCurve.popDuration, accuracy: 2 * dt)
            XCTAssertEqual(d.scale, 1)
            XCTAssertLessThan(midHalf ?? 9, d.layout.colliderHalf.x * 1.12, "collider follows the pop scale"); XCTAssertGreaterThan(midHalf ?? 0, 0)
            let c = SIMD3<Float>(d.origin.x, 0, d.origin.y)
            XCTAssertNotEqual(d.obstacle(c, radius: 0.3), c)

            d.despawn()
            t = 0
            var absentAt: Float?
            while t < 1.0 {
                d.update(dt: dt); t += dt
                if d.phase == .absent && absentAt == nil { absentAt = t }
                XCTAssertLessThanOrEqual(d.scale, 1.0001)
            }
            XCTAssertEqual(absentAt ?? 9, DiningCurve.poofDuration, accuracy: 2 * dt)
            XCTAssertTrue(RoomLayout.dynamicBoxes.isEmpty, "no obstacle left behind")
            XCTAssertFalse(d.puffs.isActive, "puff is gone too")
            XCTAssertEqual(d.obstacle(c, radius: 0.3), c)
            let f = d.frame(theme: RoomTheme())
            XCTAssertEqual(f?.opaque.vertices.count, 0, "nothing of the tray is drawn after the poof")
            XCTAssertEqual(f?.translucent.vertices.count, 0, "no meshes (shadow, glass, puff) left")
            XCTAssertNil(d.frame(theme: RoomTheme()), "no further uploads once settled")
        }
    }

    func testTrayIsObstacleOnlyWhilePresentAndLeavesPlacesFree() {
        let d = DiningSet(); defer { d.reset() }
        d.spawn(serving: Consumables.water, n: 3, bobAt: SIMD2(-2, -2.2)); d.update(dt: 0.5)
        for p in d.places {
            let q = RoomLayout.resolve(position: SIMD3(p.stand.x, 0, p.stand.y), radius: 0.7)
            XCTAssertEqual(simd_length(SIMD2(q.x, q.z) - p.stand), 0, accuracy: 0.02, "his place is not pushed by the tray")
        }
        let centre = RoomLayout.resolve(position: SIMD3(d.origin.x, 0, d.origin.y), radius: 0.4)
        XCTAssertGreaterThan(RoomLayout.boxDistanceXZ(SIMD2(centre.x, centre.z), RoomLayout.dynamicBoxes[0]), 0.35)
    }

    func testPuffAndShadowInTheFrameWhileAnimating() {
        let d = DiningSet(); defer { d.reset() }
        d.spawn(serving: Consumables.pizza, n: 2, bobAt: SIMD2(-2, -2.2))
        d.update(dt: 0.05)
        let f = d.frame(theme: RoomTheme())
        XCTAssertGreaterThan(f?.translucent.vertices.count ?? 0, 200)
        XCTAssertGreaterThan(f?.opaque.vertices.count ?? 0, 1000)
        XCTAssertTrue((f?.translucent.vertices ?? []).contains { $0.color.w > 0 && $0.color.w < 1 })
    }

    // MARK: bites (3 per Blob for every food), held pieces and forks

    func testThreeBitesPerBlobForEveryFood() {
        for f in Consumables.foods { for n in 1...3 {
            let d = DiningSet(); defer { d.reset() }
            d.spawn(serving: f, n: n, bobAt: SIMD2(-2, -2.2)); d.update(dt: 0.4)
            for i in 0..<n {
                for _ in 0..<DiningTiming.bitesPerServing {
                    XCTAssertTrue(d.beginBite(place: i), "\(f.id) n=\(n) place \(i)")
                    d.finishBite(place: i)
                }
                XCTAssertEqual(d.bitesLeft[i], 0)
                XCTAssertFalse(d.beginBite(place: i), "his share is empty")
            }
            XCTAssertEqual(d.totalBitesLeft, 0)
        } }
    }

    func testHeldPieceAndForkFollowTheirTransform() {
        let d = DiningSet(); defer { d.reset() }
        d.spawn(serving: Consumables.berries, n: 2, bobAt: SIMD2(-2, -2.2)); d.update(dt: 0.4)
        _ = d.frame(theme: RoomTheme())
        func count() -> Int { d.frame(theme: RoomTheme())?.opaque.vertices.count ?? -1 }
        XCTAssertTrue(d.beginBite(place: 1))
        var m = matrix_identity_float4x4; m.columns.3 = SIMD4(5, 1, 5, 1)
        d.hold(.piece, place: 1, transform: m)
        let f = d.frame(theme: RoomTheme())
        XCTAssertTrue((f?.opaque.vertices ?? []).contains { abs($0.pos.x - 5) < 0.1 && abs($0.pos.y - 1) < 0.1 }, "the berry sticks to the transform")
        d.finishBite(place: 1)
        XCTAssertEqual(d.bitesLeft, [3, 2])
        _ = count()
        // fork foods: no fork on the tray; the held fork is drawn only while a pose is supplied
        let e = DiningSet(); defer { e.reset() }
        e.spawn(serving: TestFoods.fork, n: 3, bobAt: SIMD2(-2, -2.2)); e.update(dt: 0.4)
        let base = e.frame(theme: RoomTheme())!.opaque.vertices.count
        var fm = matrix_identity_float4x4; fm.columns.3 = SIMD4(5, 1, 5, 1)
        e.hold(.fork, place: 2, transform: fm)
        let held = e.frame(theme: RoomTheme())!
        XCTAssertTrue(held.opaque.vertices.contains { abs($0.pos.x - 5) < 0.4 })
        XCTAssertEqual(held.opaque.vertices.count, base + DiningModels.fork(withBite: false).vertices.count, "the held fork appears out of nowhere (poofed into his hand)")
        e.release(.fork, place: 2)
        XCTAssertEqual(e.frame(theme: RoomTheme())!.opaque.vertices.count, base)
    }
}
