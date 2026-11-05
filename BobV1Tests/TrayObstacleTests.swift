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
        var shown = 0, atT: Float = 0, worst: Float = -.infinity, at = SIMD2<Float>.zero, travelled: Float = 0, lag: Float = 0
        var last: SIMD2<Float>?
        func sample(_ r: DiningJellyTests.Room, _ id: Int) {
            let f = r.actors[id].floor
            defer { last = f }
            if let l = last, simd_distance(l, f) < 0.5 { travelled += simd_distance(l, f); legMoved += simd_distance(l, f) }
            guard legMoved > 0.4 else { return }
            guard r.actors[id].isWalking else { return }          // (only a body on the move: one that stands where the tray was set down is the serving's business, not a walk through it)
            let intr = TrayObstacleTests.belly - TrayObstacleTests.drawnDistance(r, f)
            if intr > worst { worst = intr; at = f; atT = r.t }
            if intr > TrayObstacleTests.tolerance, shown < 3, let b = r.actors[id].brain {
                shown += 1
                let c = r.actors[id].sim.centroid()
                print("TRAYDIAG id=\(id) t=\(r.t) intr=\(intr) floor=\(f) root=\(b.position) centroid=\(SIMD2(c.x, c.z)) poseW=\(b.poseW) act=\(b.activity) drawnDist=\(TrayObstacleTests.drawnDistance(r, f)) rootDist=\(TrayObstacleTests.drawnDistance(r, b.position))")
            }
            let c = r.actors[id].sim.centroid()
            lag = max(lag, simd_distance(SIMD2(c.x, c.z), f))          // the drawn body against its root
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

    /// A tag chase between two Jelbies whose play floor has the tray in the middle (a social walk-up and the runs after it use the same floor rules).
    func testSocialChaseAcrossTheTrayNeverEntersIt() {
        for kind in [SocialKind.chase, .follow] {
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
            let pa = Probe(), pb = Probe()
            r.run(30) { pa.sample(r, 0); pb.sample(r, 2); return false }
            print("TRAY social \(kind): worst intrusion \(pa.worst) / \(pb.worst), walked \(pa.travelled) / \(pb.travelled)")
            XCTAssertGreaterThan(pa.travelled + pb.travelled, 1, "\(kind): they really moved")
            XCTAssertLessThan(max(pa.worst, pb.worst), Self.tolerance, "\(kind): a body went into the drawn tray: \(pa.worst) at \(pa.at), \(pb.worst) at \(pb.at)")
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
