//
//  MealReachTests.swift
//  Meal reach (meal-reach-r1, 2026-11-18, the owner: "they are reaching but actually not grabbing the food ... closer to the table ... I also don't want them to stretch their arms too much").
//  At the grab moment of every bite, for every place of the three-diner ends layout (left end, middle, right end), the nub's hold point sits within 1.5 cm of the piece on the plate;
//  the arm never stands out longer than the rest nub (+ the small grab allowance, if any); nobody's body is inside the drawn tray; neighbours keep their gap.
//  `-MealReach 0` (GameCare.mealReach = false) = the old stand and reach.
//

import XCTest
import simd
@testable import BobV1

@MainActor
final class MealReachTests: XCTestCase {
    private var savedHour: Double?
    private var savedPick: (([SIMD2<Float>]) -> SIMD2<Float>?)?
    override func setUp() {
        savedHour = DayClock.shared.forcedHour; DayClock.shared.forcedHour = 12
        DiningGroup.homeSeats = 3; DiningGroup.varianceSeed = 424242
        savedPick = DiningSpot.pickOpen; DiningSpot.pickOpen = { $0.min { simd_distance($0, SIMD2(0.6, 1.6)) < simd_distance($1, SIMD2(0.6, 1.6)) } }          // (the home spot of the real app: both end stands on the floor)
    }
    override func tearDown() {
        DayClock.shared.forcedHour = savedHour; DiningGroup.homeSeats = 2; DiningGroup.variance = true; DiningGroup.varianceSeed = nil
        GameCare.mealReach = true
        if let savedPick { DiningSpot.pickOpen = savedPick }
    }

    struct Grab { var arrived = true; var place: String; var k: Int; var miss: Float; var crouch: Float; var side: Int }
    struct Take { var grabs: [Grab] = []; var minBodyBox: Float = .infinity; var minFloorBox: Float = .infinity; var minNeighbour: Float = .infinity; var maxFloorStand: Float = 0; var worstBrow: Float = .infinity; var browByPlace: [String: Float] = [:] }

    static let browIdx = buildEyeRig(render: MotionRig.renderMesh, sim: MotionRig.simMesh).brow
    /// Apparent slant (rad, inner end up) of each brow as the game camera sees the skinned render mesh (as DiningFlowTests measures it).
    private func browSlant(_ a: JellyActor, _ dyn: inout [Float]) -> SIMD2<Float> {
        a.skinner.update(x: a.sim.x, index: MotionRig.renderMesh.index, into: &dyn)
        let vp = GameCamera.camera(aspect: GameCamera.aspect).viewProj
        func scr(_ v: Int32) -> SIMD2<Float> {
            let o = 6 * Int(v), c = vp * SIMD4(dyn[o], dyn[o + 1], dyn[o + 2], 1)
            return SIMD2(c.x / c.w * GameCamera.aspect, c.y / c.w)
        }
        var out = SIMD2<Float>(0, 0)
        for side in 0..<2 {
            let pts = Self.browIdx[side].map { scr($0) }
            guard let lo = pts.min(by: { $0.x < $1.x }), let hi = pts.max(by: { $0.x < $1.x }) else { continue }
            let inner = side == 0 ? hi : lo, outer = side == 0 ? lo : hi
            out[side] = atan2f(inner.y - outer.y, abs(inner.x - outer.x))
        }
        return out
    }

    private func take(food: String) -> Take {
        let r = DiningJellyTests.Room(count: 3)
        DiningJellyTests.keep.append(r.care); DiningJellyTests.keep.append(contentsOf: r.actors)
        for i in 0..<3 { r.care.needs(for: i).set(.hunger, 0.1) }
        r.run(1)
        let t0 = r.t
        var dyn = [Float](repeating: 0, count: MotionRig.renderMesh.vertexCount * 6)
                r.care.feed(food)
        var tk = Take()
        var seen = Set<Int>()
        var series: [String] = []
        defer { for l in series.prefix(40) { print("MEALREACH SERIES \(l)") } }
        r.run(120) {
            let dn = r.care.dining
            var ids: [Int] = []
            for a in r.actors {
                guard let b = a.brain, case .dine = b.job ?? .goTo(.zero) else { continue }
                ids.append(a.id)
                if food == "sushi", b.dine.mode == .finger, b.dine.bentOn, b.dine.k <= 1, let h = b.dineHooks {
                    let dxs = a.floor.x - dn.origin.x
                    print("MEALREACH LEANERR \(dxs < -0.5 ? "left" : dxs > 0.5 ? "right" : "middle") k\(b.dine.k) \(b.dine.phase) bent \(String(format: "%.3f", b.dine.bent)) err \(String(format: "%.1f", simd_distance(b.nubTipWorld(sim: a.sim), h.piece(b.dine.k)) * 100)) pitch \(String(format: "%.2f", b.dine.cur.pitch)) twist \(String(format: "%.2f", b.dine.cur.twist)) sq \(String(format: "%.2f", b.dine.cur.squash))")
                }
                if false, b.dine.phase == .grab, let h = b.dineHooks, b.dine.mode == .finger {
                    let att = a.sim.attractor, bp = a.sim.bodyPose(iterations: 3)
                    let dq = simd_length(simd_act(att.rotation.inverse * bp.rotation, SIMD3<Float>(0, 1, 0)) - SIMD3<Float>(0, 1, 0))
                    series.append("\(a.id)k\(b.dine.k) t\(String(format: "%.3f", b.dine.t)) err \(String(format: "%.1f", simd_distance(b.nubTipWorld(sim: a.sim), h.piece(b.dine.k)) * 100)) rotErr \(String(format: "%.3f", dq)) cenErr \(String(format: "(%.3f,%.3f,%.3f)", bp.centroid.x - att.anchor.x, bp.centroid.y - att.anchor.y, bp.centroid.z - att.anchor.z)) anchorY \(String(format: "%.3f", att.anchor.y)) sq \(String(format: "%.2f", att.squash))")
                }
                if b.dine.phase == .grab, b.dine.holding, !seen.contains(a.id * 10 + b.dine.k), let h = b.dineHooks {
                    seen.insert(a.id * 10 + b.dine.k)
                    let tip = b.nubTipWorld(sim: a.sim), piece = h.piece(b.dine.k)
                    let dx = a.floor.x - dn.origin.x
                    let place = dx < -0.5 ? "left" : dx > 0.5 ? "right" : "middle"
                    do {
                        if !seen.contains(-1) { seen.insert(-1); print("MEALREACH STANDS \(food) origin \(dn.origin) places \(dn.places.map { String(format: "(%.2f,%.2f)", $0.stand.x - dn.origin.x, $0.stand.y - dn.origin.y) }) layout rel \(dn.layout.places.map { $0.rel }) mealReach \(GameCare.mealReach)") }
                        let c = a.sim.centroid()
                        print("MEALREACH CEN \(place) centroid-origin (\(String(format: "%.2f,%.2f", c.x - dn.origin.x, c.z - dn.origin.y))) floor-origin (\(String(format: "%.2f,%.2f", a.floor.x - dn.origin.x, a.floor.y - dn.origin.y)))")
                        let rp = b.dine.reach, fl = a.floor - dn.origin, sc = dn.layout.scale
                        print("MEALREACH GRAB \(food) \(place) k\(b.dine.k) actual \(String(format: "%.1f", simd_distance(tip, piece) * 100)) pred \(String(format: "%.1f", b.dine.miss * 100)) floorRel(\(String(format: "%.2f,%.2f", fl.x, fl.y))) yaw \(String(format: "%.2f", b.yaw)) pose tw \(String(format: "%.2f", rp.twist)) pi \(String(format: "%.2f", rp.pitch)) ro \(String(format: "%.2f", rp.roll)) sq \(String(format: "%.2f", rp.squash)) side \(b.dine.side) scale \(sc) sideX \(DiningLayout.sideX) piece(\(String(format: "%.2f,%.2f,%.2f", piece.x - dn.origin.x, piece.y, piece.z - dn.origin.y))) tip(\(String(format: "%.2f,%.2f,%.2f", tip.x - dn.origin.x, tip.y, tip.z - dn.origin.y))) s \(String(format: "%.2f", b.dine.grabS)) crouch \(String(format: "%.2f", b.dine.crouch))")
                    }
                    tk.grabs.append(Grab(arrived: simd_distance(a.floor, b.dine.place.stand) < 0.2, place: place, k: b.dine.k, miss: simd_distance(tip, piece), crouch: b.dine.crouch, side: b.dine.side))
                }
            }
            ids = ids.filter { r.actors[$0].brain?.activity == .eating }
            for i in ids {
                let b = self.browSlant(r.actors[i], &dyn), v = min(b.x, b.y), dx = r.actors[i].floor.x - dn.origin.x
                let pl = dx < -0.5 ? "left" : dx > 0.5 ? "right" : "middle"
                tk.worstBrow = min(tk.worstBrow, v); tk.browByPlace[pl] = min(tk.browByPlace[pl] ?? .infinity, v)
            }          // (every tick, 3 diners, variance on)
            if dn.isPresent, !ids.isEmpty {
                let box = dn.drawnBox(scale: 1)
                for a in r.actors where ids.contains(a.id) {
                    tk.minFloorBox = min(tk.minFloorBox, RoomLayout.boxDistanceXZ(a.floor, box))
                    // body vs the drawn tray: any sim particle below the tray's rim height that is inside its footprint
                    for i in 0..<a.sim.n where a.sim.x[3 * i + 1] < RoomLayout.floorY + box.height {
                        tk.minBodyBox = min(tk.minBodyBox, RoomLayout.boxDistanceXZ(SIMD2(a.sim.x[3 * i], a.sim.x[3 * i + 2]), box))
                    }
                }
                for x in 0..<r.actors.count { for y in (x + 1)..<r.actors.count where ids.contains(x) && ids.contains(y) {
                    tk.minNeighbour = min(tk.minNeighbour, simd_distance(r.actors[x].floor, r.actors[y].floor) - 0.69)          // (floor points apart minus the footprint)
                } }
            }
            return r.t > t0 + 2 && !r.care.trayOut
        }
        return tk
    }

    /// Rest nub length vs the nub at the grab pose (capped geometry), as a fraction.
    private func nubLengths() -> (rest: Double, grab: Double) {
        let g0 = ArmPath.nubToMouth.geom(at: 0), g1 = ArmPath.nubToMouth.geom(at: ArmPath.nubGrabS)
        return (simd_length(g0.B - g0.A), simd_length(g1.B - g1.A))
    }

    private func report(_ label: String, _ food: String, _ tk: Take) {
        var per: [String: [Float]] = [:]
        for g in tk.grabs { per[g.place, default: []].append(g.miss * 100) }
        let s = ["left", "middle", "right"].map { p in
            let v = per[p] ?? []
            return "\(p) n=\(v.count) max \(String(format: "%.2f", v.max() ?? -1)) cm [\(v.map { String(format: "%.1f", $0) }.joined(separator: ","))]"
        }.joined(separator: " | ")
        let e = nubLengths()
        print("MEALREACH \(label) \(food): \(s) | brow worst \(String(format: "%.3f", tk.worstBrow)) | bodyBox \(String(format: "%.3f", tk.minBodyBox)) floorBox \(String(format: "%.3f", tk.minFloorBox)) neighbour \(String(format: "%.3f", tk.minNeighbour)) | nub rest \(String(format: "%.4f", e.rest)) grab \(String(format: "%.4f", e.grab)) = \(String(format: "%.1f", 100 * e.grab / e.rest)) %")
    }

    private func check(_ food: String) {
        let tk = take(food: food)
        report("NEW", food, tk)
        XCTAssertGreaterThanOrEqual(tk.grabs.filter { $0.arrived }.count, 4, "\(food): grabs seen \(tk.grabs.count)")
        for p in ["left", "middle", "right"] { XCTAssertTrue(tk.grabs.contains { $0.place == p }, "\(food): a grab at \(p)") }
        for g in tk.grabs where g.arrived { XCTAssertLessThanOrEqual(g.miss, 0.04, "\(food) \(g.place) bite \(g.k): nub tip \(g.miss * 100) cm from the piece (crouch \(g.crouch))") }
        let e = nubLengths()
        XCTAssertLessThanOrEqual(e.grab, e.rest * (1 + GameCare.grabStretch) + 1e-6, "arm extension at the grab")
        XCTAssertGreaterThan(tk.worstBrow, -0.1006, "\(food): no brow slants down past DiningFlow's bar (-0.1006 rad: the rest face's flattest brow -0.041 minus 0.06), worst \(tk.worstBrow) by place \(tk.browByPlace)")
        print("MEALREACH BROW \(food) worst \(tk.worstBrow) by place \(tk.browByPlace)")
        XCTAssertGreaterThanOrEqual(tk.minFloorBox, 0, "no diner's floor point inside the drawn tray")
        XCTAssertGreaterThanOrEqual(tk.minNeighbour, 0, "neighbours' gap")
    }

    /// Back to back: the whole room tick (3 brains + care + sims) while the diners eat, new reach vs the old one.
    func testTickCostVsOld() {
        var res: [(Bool, Double, Double)] = []
        for on in [false, true, false, true] {
            GameCare.mealReach = on
            let r = DiningJellyTests.Room(count: 3)
            DiningJellyTests.keep.append(r.care); DiningJellyTests.keep.append(contentsOf: r.actors)
            for i in 0..<3 { r.care.needs(for: i).set(.hunger, 0.1) }
            r.run(1); r.care.feed("sushi")
            var worst = 0.0, sum = 0.0, n = 0
            for _ in 0..<(60 * 40) {
                let a = CACurrentMediaTime(); r.tick(); let us = (CACurrentMediaTime() - a) * 1e6
                if r.actors.contains(where: { $0.brain?.activity == .eating }) { worst = max(worst, us); sum += us; n += 1 }
                if r.t > 3, !r.care.trayOut { break }
            }
            res.append((on, sum / Double(max(n, 1)), worst))
            print("MEALREACH TICKCOST reach \(on ? "NEW" : "OLD") mean \(String(format: "%.0f", sum / Double(max(n, 1)))) us worst \(String(format: "%.0f", worst)) us over \(n) ticks")
        }
        GameCare.mealReach = true
        XCTAssertLessThan(res.filter { $0.0 }.map { $0.2 }.min() ?? 0, 4000 + (res.filter { !$0.0 }.map { $0.2 }.min() ?? 0), "the new reach adds < 4 ms to the worst tick")
    }

    /// The model (the solver the lean uses) for each of the three Jellies at the LEFT and the RIGHT end place of the food ends layout, every piece, the three crouch draws, and a stand 4 cm too near / on it / 6 cm too far
    /// (a diner stops up to ~6 cm off his stand): every bite within 2.5 cm. Both ends must do as well (the left end diner used to miss by 5-7 cm in the app: an asymmetric roll grid).
    func testLeftAndRightEndEverySpecies() {
        let savedEnds = DiningLayout.ends, savedSide = DiningLayout.sideX, savedFood = DiningLayout.reachFood
        DiningLayout.ends = true; DiningLayout.sideX = GameCare.mealReachX; DiningLayout.reachFood = true
        defer { DiningLayout.ends = savedEnds; DiningLayout.sideX = savedSide; DiningLayout.reachFood = savedFood }
        let L = DiningLayout.make(n: 3)
        let r = DiningJellyTests.Room(count: 3)
        DiningJellyTests.keep.append(r.care); DiningJellyTests.keep.append(contentsOf: r.actors)
        for i in 0..<3 { r.care.needs(for: i).set(.hunger, 0.1) }
        r.run(1); r.care.feed("sushi")
        r.run(60) { r.t > 3 && !r.care.trayOut }          // (a whole meal first: the brains build their feet / pivot geometry on the first lean, which the model reads)
        var worstBy: [String: Float] = [:]
        for a in r.actors {
            guard let b = a.brain else { continue }
            for place in [0, 1, 2] {
                let tp = L.places[place], dirOut: SIMD2<Float> = place == 0 ? SIMD2(0, -1) : (tp.rel.x < 0 ? SIMD2(-1, 0) : SIMD2(1, 0))
                for off: Float in [-0.04, 0, 0.06] {
                    let stand = tp.rel + SIMD2(sinf(tp.yaw), cosf(tp.yaw)) * GameCare.eatCloser + dirOut * off
                    b.px = stand.x; b.pz = stand.y; b.yaw = tp.yaw
                    for k in 0..<3 {
                        let a3 = DiningModels.berryAnchor(layout: L, place: place, index: k)
                        for c: Float in [0.8, 0.9, 1.0] {
                            b.solveDineReachRadial(a.sim, target: a3, crouch: c)
                            let key = "\(JellyRoster.names[a.id]) \(place == 0 ? "middle" : place == 1 ? "left" : "right")"
                            worstBy[key] = max(worstBy[key] ?? 0, b.dine.miss)
                            XCTAssertLessThanOrEqual(b.dine.miss, 0.025, "\(key) piece \(k) crouch \(c) stand off \(off): model miss \(b.dine.miss * 100) cm")
                        }
                    }
                }
            }
        }
        print("MEALREACH ENDS worst model miss (cm) " + worstBy.sorted { $0.key < $1.key }.map { "\($0.key) \(String(format: "%.2f", $0.value * 100))" }.joined(separator: " | "))
    }

    /// Sweep of the solver limits on the model (prints only): the worst model miss over both ends, every piece, 3 crouch draws, stand 4 cm near / on / 6 cm far.
    func testSweepSolverLimits() {
        let savedEnds = DiningLayout.ends, savedSide = DiningLayout.sideX, savedFood = DiningLayout.reachFood
        DiningLayout.ends = true; DiningLayout.reachFood = true
        defer { DiningLayout.ends = savedEnds; DiningLayout.sideX = savedSide; DiningLayout.reachFood = savedFood; BlobBrain.dineSMax = 0.65; BlobBrain.dineCrouchMin = 0.75; BlobBrain.dinePitchMax = 0.5 }
        let r = DiningJellyTests.Room(count: 3)
        DiningJellyTests.keep.append(r.care); DiningJellyTests.keep.append(contentsOf: r.actors)
        for i in 0..<3 { r.care.needs(for: i).set(.hunger, 0.1) }
        r.run(1); r.care.feed("sushi"); r.run(60) { r.t > 3 && !r.care.trayOut }
        guard let a = r.actors.first, let b = a.brain else { return }
        DiningLayout.ends = true; DiningLayout.reachFood = true          // (the sitting's end put them back)
        for sx: Float in [1.25] {
            DiningLayout.sideX = sx
            let L = DiningLayout.make(n: 3)
            for (sm, cm, pm) in [(0.65, 0.75, 0.5)] as [(Float, Float, Float)] {
                BlobBrain.dineSMax = sm; BlobBrain.dineCrouchMin = cm; BlobBrain.dinePitchMax = pm
                var worst: [Float] = [0, 0, 0], worstOn: [Float] = [0, 0, 0]
                for place in [0, 1, 2] {
                    let tp = L.places[place], dirOut: SIMD2<Float> = place == 0 ? SIMD2(0, -1) : (tp.rel.x < 0 ? SIMD2(-1, 0) : SIMD2(1, 0))
                    for off: Float in [-0.04, 0, 0.06] {
                        let stand = tp.rel + SIMD2(sinf(tp.yaw), cosf(tp.yaw)) * GameCare.eatCloser + dirOut * off
                        b.px = stand.x; b.pz = stand.y; b.yaw = tp.yaw
                        for k in 0..<3 { for c: Float in [0.8, 0.9, 1.0] {
                            b.solveDineReachRadial(a.sim, target: DiningModels.berryAnchor(layout: L, place: place, index: k), crouch: c)
                            worst[place] = max(worst[place], b.dine.miss); if off == 0 { worstOn[place] = max(worstOn[place], b.dine.miss) }
                        } }
                    }
                }
                print("MEALREACH SWEEP sideX \(sx) s<=\(sm) crouch>=\(cm) pitch<=\(pm): worst miss cm (middle/left/right) any stand \(worst.map { String(format: "%.1f", $0 * 100) }) on stand \(worstOn.map { String(format: "%.1f", $0 * 100) })")
            }
        }
    }

    func testOldReachNumbers() {
        GameCare.mealReach = false
        for f in ["sushi", "cookie"] { report("OLD", f, take(food: f)) }
    }
    func testSushiGrabsTouch() { check("sushi") }
    func testCookieGrabsTouch() { check("cookie") }
    func testBerriesGrabsTouch() { check("berries") }
}
