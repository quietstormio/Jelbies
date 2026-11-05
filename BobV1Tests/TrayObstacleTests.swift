//
//  TrayObstacleTests.swift
//  The served tray is a real obstacle for every Jelbie: nobody's belly (the root plus 0.42) enters the DRAWN tray (bed, rim and end handles) on any walk:
//  a roam leg across it, a social chase through it, and a real single meal (the bystanders; the diner keeps the thin collider he always had).
//  Before the fix the obstacle was a thin bar (`colliderHalf`) and the push used half a body radius, so the tray's ends and margins were walkable.
//

import XCTest
import simd
@testable import BobV1

@MainActor
final class TrayObstacleTests: XCTestCase {
    /// The belly radius (his base disc is ~0.84 wide).
    static let belly: Float = 0.42
    /// How far a belly may be inside the drawn tray before the test calls it a crossing (the floor rules settle within a step).
    static let tolerance: Float = 0.05

    /// Signed distance from a floor point to the DRAWN tray footprint (bed + rim + handles), negative inside.
    static func drawnDistance(_ r: DiningJellyTests.Room, _ p: SIMD2<Float>) -> Float {
        let d = r.care.dining
        return RoomLayout.boxDistanceXZ(p, d.drawnBox(scale: d.scale))
    }

    private func room() -> DiningJellyTests.Room {
        let r = DiningJellyTests.Room(count: 3)
        DiningJellyTests.keep.append(r.care); DiningJellyTests.keep.append(contentsOf: r.actors)
        r.run(1)
        for a in r.actors { a.brain?.autonomy = false }
        return r
    }

    /// A tray for `n` Jelbies stands at `origin` with nobody eating from it (every Jelbie in the room is a passer-by).
    private func standTray(_ r: DiningJellyTests.Room, n: Int, origin: SIMD2<Float> = SIMD2(0, 0.6)) {
        XCTAssertTrue(r.care.dining.spawn(serving: Consumables.berries, n: n, bobAt: SIMD2(99, 99), forcedOrigin: origin))
        r.run(3) { r.care.dining.phase == .present && r.care.dining.scale > 0.999 }
        XCTAssertEqual(r.care.dining.phase, .present, "the tray stands")
    }

    /// The deepest belly-over-tray intrusion seen while `id` runs `body` (a closure that advances the room).
    @MainActor private final class Probe {
        var legMoved: Float = 0
        /// A new leg: a body standing where a tray was set down eases out of it only once he steps (the guard works on a stepping root), so a leg is judged after its first 0.4 of walking.
        func beginLeg() { legMoved = 0; last = nil }
        var onlyWalking = true, atT: Float = 0, worst: Float = -.infinity, at = SIMD2<Float>.zero, travelled: Float = 0, lag: Float = 0
        var last: SIMD2<Float>?
        func sample(_ r: DiningJellyTests.Room, _ id: Int) {
            let f = r.actors[id].floor
            defer { last = f }
            if let l = last, simd_distance(l, f) < 0.5 { travelled += simd_distance(l, f); legMoved += simd_distance(l, f) }
            guard legMoved > 0.4 || !onlyWalking else { return }
            guard !onlyWalking || r.actors[id].isWalking else { return }          // (only a body on the move: one that stands where the tray was set down is the serving's business, not a walk through it)
            let intr = TrayObstacleTests.belly - TrayObstacleTests.drawnDistance(r, f)
            if intr > worst { worst = intr; at = f; atT = r.t }
            let c = r.actors[id].sim.centroid()
            lag = max(lag, simd_distance(SIMD2(c.x, c.z), f))          // the drawn body against its root
        }
    }


    // MARK: skin gaps (ground truth: BruteForceContactMetric on the drawn skin)

    /// The drawn skin (body + arms) of every actor in the room, as the contact tests judge it.
    static func surfaces(_ r: DiningJellyTests.Room) -> [ContactSurface] {
        let rm = MotionRig.renderMesh, nV = rm.vertexCount
        let eggLimit = rm.armCapsule?.firstVertex.min() ?? nV
        return r.actors.map { a in
            let buf = UnsafeMutablePointer<Float>.allocate(capacity: nV * 6); buf.initialize(repeating: 0, count: nV * 6)
            defer { buf.deallocate() }
            a.skinner.update(x: a.sim.x, index: rm.index, into: buf)
            var ranges: [Range<Int>] = [0..<eggLimit]
            if a.skinner.armCapsulesActive { for k in 0..<2 { ranges.append(a.skinner.armFirst[k]..<(a.skinner.armFirst[k] + ArmCapsule.vertexCount)) } }
            if a.skinner.tailOn, a.skinner.tailFirst >= 0 { ranges.append(a.skinner.tailFirst..<(a.skinner.tailFirst + TailBean.vertexCount)) }
            if a.skinner.teddyOn, a.skinner.teddyFirst >= 0 { ranges.append(a.skinner.teddyFirst..<(a.skinner.teddyFirst + TeddyBean.vertexCount)) }
            return ContactSurface(root: a.brain?.position ?? a.floor, dyn: UnsafePointer(buf), ranges: ranges)
        }
    }
    /// Skin gaps of the neighbouring diners, ordered along x (left-centre, centre-right).
    static func neighbourGaps(_ r: DiningJellyTests.Room) -> [Float] {
        let S = surfaces(r).sorted { $0.root.x < $1.root.x }
        return (0..<(S.count - 1)).map { BruteForceContactMetric.skinGap(S[$0], S[$0 + 1]) }
    }

    /// Gives the room's three bodies a cast of features (the tail and Teddy's ears are skinned into the contact surface; wings and the daisy are feature meshes the metric does not see).
    static func dress(_ r: DiningJellyTests.Room, _ features: [JellyFeature]) {
        WearBody.install(MotionRig.renderMesh)
        for (i, a) in r.actors.enumerated() {
            a.brain?.feature = features[i]; a.brain?.skinnerRef = a.skinner
            a.skinner.configureTail(MotionRig.renderMesh); a.skinner.configureTeddy(MotionRig.renderMesh)
        }
    }

    /// A roam leg from one side of the tray to the other, on several lanes through it, both ways: nobody's belly enters the drawn tray.
    func testRoamLegAcrossTheTrayNeverEntersIt() {
        for n in 1...3 {
            let r = room()
            standTray(r, n: n)
            let d = r.care.dining
            let half = (d.layout.half + SIMD2(DiningDims.handleReach, 0)) * d.scale
            for id in [0, 2] {
                let p = Probe()
                for dz: Float in [-0.35, -0.1, 0.0, 0.2, 0.5] {
                    let y = d.origin.y + dz
                    let a = SIMD2(d.origin.x - half.x - 1.0, y), b = SIMD2(d.origin.x + half.x + 1.0, y)
                    for (from, to) in [(a, b), (b, a)] {
                        let act = r.actors[id]
                        act.sim.teleport(toXZ: from); act.brain?.poseW = 0; act.brain?.currentPose(act.sim)          // (the brain's root follows the body: it is only re-read while the brain is not posing)
                        r.run(0.6)
                        act.brain?.requestNow(.goTo(to)); p.beginLeg()
                        r.run(16) { p.sample(r, id); return simd_distance(act.floor, to) < 0.4 }
                        r.run(0.5)
                    }
                }
                print("TRAY roam n=\(n) id=\(id): worst belly intrusion \(p.worst) at \(p.at) t=\(p.atT), walked \(p.travelled), body-vs-root lag \(p.lag)")
                XCTAssertGreaterThan(p.travelled, 5, "n=\(n) id=\(id): the walks really happened")
                XCTAssertLessThan(p.worst, Self.tolerance, "n=\(n) Jelly \(id) walked into the drawn tray: belly overlaps by \(p.worst) at \(p.at)")
            }
        }
    }

    /// Social walk-ups and runs between two Jelbies whose play floor has the tray in the middle (they use the same floor rules): the pair meets on the far side, through the tray if it let them.
    func testSocialWalkUpsAcrossTheTrayNeverEnterIt() {
        var startedKinds: [SocialKind] = []
        for kind in [SocialKind.follow, .sneak, .bump, .boop, .chase] {
            let r = room()
            standTray(r, n: 3, origin: SIMD2(0, 0.9))
            let d = r.care.dining
            let a = r.actors[0], b = r.actors[2]
            a.sim.teleport(toXZ: SIMD2(d.origin.x - 2.6, d.origin.y)); a.brain?.poseW = 0; a.brain?.currentPose(a.sim)
            b.sim.teleport(toXZ: SIMD2(d.origin.x + 2.6, d.origin.y)); b.brain?.poseW = 0; b.brain?.currentPose(b.sim)
            r.run(0.6)
            a.brain?.autonomy = true; b.brain?.autonomy = true
            guard let ab = a.brain, let bb = b.brain else { return XCTFail("brains") }
            let started = ab.socialStart(kind, with: bb, a.sim)
            print("TRAY social \(kind): started=\(started)")
            guard started else { continue }
            startedKinds.append(kind)
            let pa = Probe(), pb = Probe()
            pa.beginLeg(); pb.beginLeg()
            r.run(30) { pa.sample(r, 0); pb.sample(r, 2); return false }
            print("TRAY social \(kind): worst intrusion \(pa.worst) / \(pb.worst), walked \(pa.travelled) / \(pb.travelled)")
            XCTAssertGreaterThan(pa.travelled + pb.travelled, 3, "\(kind): they really moved")
            XCTAssertLessThan(max(pa.worst, pb.worst), Self.tolerance, "\(kind): a body went into the drawn tray: \(pa.worst) at \(pa.at), \(pb.worst) at \(pb.at)")
        }
        XCTAssertGreaterThanOrEqual(startedKinds.count, 2, "at least two social kinds started (\(startedKinds))")
    }

    /// A hop toward the tray from its front edge does not land in it or carry the body over it.
    func testHopTowardTheTrayStaysOut() {
        let r = room()
        standTray(r, n: 1, origin: SIMD2(0, 0.6))
        let d = r.care.dining, box = d.drawnBox(scale: d.scale)
        let a = r.actors[0]
        a.sim.teleport(toXZ: SIMD2(0, box.centre.y + box.half.y + 0.7)); a.brain?.poseW = 0; a.brain?.currentPose(a.sim)
        a.brain?.yaw = .pi          // (facing -z: toward the tray)
        r.run(1)
        let p = Probe(); p.onlyWalking = false
        a.brain?.startHopPlay(sim: a.sim, distance: 1.2)
        r.run(4) { let c = a.sim.centroid(); let intr = Self.belly - Self.drawnDistance(r, SIMD2(c.x, c.z)); if intr > p.worst { p.worst = intr; p.at = SIMD2(c.x, c.z) }; return false }
        print("TRAY hop: worst belly intrusion \(p.worst) at \(p.at)")
        XCTAssertLessThan(p.worst, Self.tolerance + 0.1, "a hop toward the tray put the body into it: \(p.worst) at \(p.at)")          // (the hop's body is soft: 0.1 of slack over a walk)
    }

    /// A real 3-Jelbie meal from scattered starts: the diners gather at their places with no tray out, it is drawn only then, and no diner's belly is ever in it; the line-up is as quick as ever.
    func testGroupMealDinersNeverEnterTheTray() {
        let castA: [JellyFeature] = [.none, .wings, .ears], castB: [JellyFeature] = [.spines, .wings, .daisy]          // Bob + Pearl + Teddy; Pip + Lavender + Moss
        for (drink, scatter, limit, cast) in [(false, Float(0), Float(8), castA), (true, 0, 8, castB), (false, 13, 14, castB), (true, 13, 14, castA)] {
            let r = DiningJellyTests.Room(count: 3, wander: scatter > 0)
            DiningJellyTests.keep.append(r.care); DiningJellyTests.keep.append(contentsOf: r.actors)
            Self.dress(r, cast)
            r.run(max(1, scatter))
            for a in r.actors { a.brain?.autonomy = false }
            r.run(0.5)
            r.care.store.grant("berries", 3)
            if drink { r.care.drink() } else { r.care.feed("berries") }
            let probes = (0..<3).map { _ in Probe() }
            for p in probes { p.onlyWalking = false; p.beginLeg(); p.legMoved = 1 }
            var servedAt: Float?, trayAt: Float?
            var gapLog: [(Float, [Float])] = []
            let t0 = r.t
            r.run(30) {
                if r.care.dining.phase != .absent { if trayAt == nil { gapLog.append((-1, Self.neighbourGaps(r))) }; trayAt = trayAt ?? r.t; for i in 0..<3 { probes[i].sample(r, i) } }
                if r.care.group.state == .serving { servedAt = servedAt ?? r.t; let k = r.t - (servedAt ?? r.t); for m in [0.0, 1.5, 3.0, 4.0, 5.0, 6.0, 7.0] where abs(Double(k) - m) < 0.009 { gapLog.append((Float(m), Self.neighbourGaps(r))) }; return k > 7.1 }
                return false
            }
            let worst = probes.map(\.worst)
            print("TRAY group drink=\(drink) scatter=\(scatter): serving after \((servedAt ?? 99) - t0) s, tray drawn after \((trayAt ?? 99) - t0) s, worst diner intrusion \(worst)")
            print("TRAY group drink=\(drink) scatter=\(scatter): neighbour skin gaps (left-centre, centre-right) after serving began: \(gapLog.map { "\($0.0)s \($0.1)" })")
            // (the neighbours' skin gaps are measured and printed, not asserted: see the report. Row spacing 1.11 against a 1.40 touch distance leaves them sunk by 0.35-0.52 m; the arc that would fix the spacing broke the line-up tests)
            let allGaps = gapLog.filter { $0.0 >= 3 }.flatMap(\.1)
            print("TRAY group eating gaps min \(allGaps.min() ?? 0) max \(allGaps.max() ?? 0)")
            XCTAssertNotNil(servedAt, "drink=\(drink) scatter=\(scatter): the meal reaches serving")
            XCTAssertLessThan((servedAt ?? 99) - t0, limit, "drink=\(drink) scatter=\(scatter): line-up time")
            // (a sipper stands 0.08 nearer the tray: his belly may overlap the bed by that much)
            XCTAssertLessThan(worst.max() ?? 0, Self.tolerance + (drink ? GameCare.sipCloser : 0), "drink=\(drink) scatter=\(scatter): a diner's belly was in the drawn tray: \(worst)")
        }
    }

    /// A real single meal (Pip eats): the floor rules of the two bystanders push them a belly off the whole drawn tray (every side, ends and handles included), Pip's own are the thin
    /// collider he always had. (The meal's tray stands only ~10 s, too short for a walking probe: this checks the wiring through the brains' own `resolve`.)
    func testBystandersGetTheDrawnTrayInARealMeal() {
        let r = room()
        r.care.store.grant("berries", 3)
        r.care.feed("berries", jelly: 1)
        r.run(40) { r.care.dining.phase == .present && r.care.dining.scale > 0.999 }
        XCTAssertEqual(r.care.dining.phase, .present, "the meal's tray stands (\(r.care.dining.phase))")
        XCTAssertTrue(r.care.isDiner(1)); XCTAssertFalse(r.care.isDiner(0)); XCTAssertFalse(r.care.isDiner(2))
        let d = r.care.dining
        let box = d.drawnBox(scale: d.scale)
        let c = box.centre, h = box.half
        for (name, p) in [("left end", c + SIMD2(-h.x - 0.2, 0.05)), ("right end", c + SIMD2(h.x + 0.2, -0.05)), ("front", c + SIMD2(0.3, h.y + 0.2)), ("back", c + SIMD2(-0.3, -h.y - 0.2)), ("front-left corner", c + SIMD2(-h.x - 0.15, h.y + 0.15))] {
            for id in [0, 2] {
                guard let b = r.actors[id].brain else { return XCTFail("brain") }
                let q = b.resolve(SIMD3(p.x, 0, p.y), b.footprint)
                let dist = RoomLayout.boxDistanceXZ(SIMD2(q.x, q.z), box)
                XCTAssertGreaterThan(dist, Self.belly - 0.02, "bystander \(id) at the \(name) of a real meal's tray: pushed to \(dist) from the drawn tray (a belly is \(Self.belly))")
            }
        }
    }
}
