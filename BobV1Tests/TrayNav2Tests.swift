//
//  TrayNav2Tests.swift
//  He never walks through the tray: the REAL care flow (GameCare) from every kind of start, sampled every frame against the real tray footprint
//  with his skin (sim particles low enough to touch the tray), plus three Blobs and Come here with the tray out.
//
//  Why the tray waits: the visible floor beside the 1.56-wide tray is only ~0.2 u wide, so no on-screen path around it exists for a 1.4-wide body.
//  GameCare therefore pops the tray in only once he is at (or behind) his place: in front of it he walks there first, with no tray out.
//

import XCTest
import simd
@testable import BobV1

@MainActor
final class TrayNav2Tests: XCTestCase {
    override func setUp() { RoomLayout.dynamicBoxes = [] }
    override func tearDown() { RoomLayout.dynamicBoxes = [] }

    /// Signed distance (positive = clear) from the xz point to the tray's real footprint (rim included), `scale` = its pop scale.
    static func rectDistance(_ p: SIMD2<Float>, tray d: DiningSet) -> Float {
        let c = SIMD2(d.origin.x, d.origin.y + d.layout.trayCentreZ * d.scale), h = d.layout.half * d.scale
        let q = simd_abs(p - c) - h
        return simd_length(simd_max(q, .zero)) + min(max(q.x, q.y), 0)
    }
    /// Smallest clearance of any skin particle low enough to touch the tray (y < 0.3) to the tray footprint; nil when nothing is that low.
    static func skinClearance(_ sim: SoftBody, tray d: DiningSet) -> Float {
        var m = Float.infinity
        for i in 0..<sim.x.count / 3 where sim.x[3 * i + 1] < 0.30 {
            m = min(m, rectDistance(SIMD2(sim.x[3 * i], sim.x[3 * i + 2]), tray: d))
        }
        return m
    }

    struct Result { var skin = Float.infinity; var skinWalking = Float.infinity; var centroid = Float.infinity; var ate = false; var minPopGap = Float.infinity }

    /// N = 1 through GameCare: walk to `start` (no tray), tap Feed / Drink, run the meal; sample every frame while a tray is out.
    private func meal(from start: SIMD2<Float>, id: String, name: String) -> Result {
        let m = MealRun()
        m.brain.requestNow(.goTo(start))
        m.run(14) { m.brain.activity == .idle && simd_distance(m.brain.position, start) < 0.3 }
        m.run(0.8)
        MotionLog.write("NAV2 \(name) start (\(m.brain.position.x), \(m.brain.position.y))")
        if Consumables.with(id: id)!.kind == .food { m.care.feed(id) } else { m.care.drink(id) }
        var r = Result(), n = 0
        for _ in 0..<(60 * 45) {
            m.tick(); n += 1
            let t = m.tray
            if t.phase == .popping || t.phase == .present {
                let s = Self.skinClearance(m.rig.sim, tray: t)
                r.skin = min(r.skin, s)
                if m.brain.activity == .walking || m.brain.activity == .turning { r.skinWalking = min(r.skinWalking, s) }
                let c = m.rig.sim.centroid()
                r.centroid = min(r.centroid, Self.rectDistance(SIMD2(c.x, c.z), tray: t))
            }
            if m.brain.activity == .eating || m.brain.activity == .drinking { r.ate = true }
            if n % 6 == 0 { let c = m.rig.sim.centroid(); MotionLog.write(String(format: "NAV2PATH %@ %.3f %.3f %d %.3f %@ %@ root=%.3f,%.3f sc=%.2f", name, c.x, c.z, t.phase == .absent ? 0 : 1, t.phase == .absent ? 9 : Self.skinClearance(m.rig.sim, tray: t), "\(m.brain.activity)", m.brain.dinePhaseName, m.brain.position.x, m.brain.position.y, t.scale)) }
            if r.ate, t.phase == .absent, !m.care.trayOut { break }
        }
        if let o = m.tray.places.first { _ = o }
        MotionLog.write(String(format: "NAV2 %@ ate=%d skin clearance min %.3f (while walking %.3f) centroid clearance %.3f", name, r.ate ? 1 : 0, r.skin, r.skinWalking, r.centroid))
        return r
    }

    /// Every start. The skin clearance while the tray is out must never go below what the eating pose itself has at the stand (the designed
    /// belly-over-the-back-rim overlap, measured with the same probe) minus a hair.
    func testOneBlobFromEveryStart() {
        let starts: [(String, SIMD2<Float>)] = [
            ("front", SIMD2(0, 2.3)), ("onTraySpot", SIMD2(0, 1.3)), ("left", SIMD2(-0.9, 1.3)), ("right", SIMD2(0.9, 1.3)),
            ("frontLeft", SIMD2(-0.9, 2.2)), ("frontRight", SIMD2(0.9, 2.2)), ("behind", SIMD2(0, -0.3)), ("behindLeft", SIMD2(-1.3, 0.2)), ("behindRight", SIMD2(1.3, 0.2)),
        ]
        let base = meal(from: SIMD2(0, 0.2), id: "berries", name: "baseline")
        for (name, p) in starts {
            let r = meal(from: p, id: "berries", name: name)
            XCTAssertTrue(r.ate, "\(name): he gets to his place and eats")
            XCTAssertGreaterThanOrEqual(r.skin, base.skin - 0.01, "\(name): never closer to the tray than the eating pose itself")
        }
        for (name, p) in [("frontWater", SIMD2<Float>(0, 2.3)), ("onTraySpotWater", SIMD2(0, 1.3))] {
            let wb = meal(from: SIMD2(0, 0.2), id: "water", name: "baselineWater")
            let w = meal(from: p, id: "water", name: name)
            XCTAssertTrue(w.ate, "\(name): he sips")
            XCTAssertGreaterThanOrEqual(w.skin, wb.skin - 0.01, "\(name): never closer than the sipping pose itself (the sip stand is 0.08 closer)")
        }
    }

    /// Dropped in front of the tray in the middle of a meal (a grab and a put-down): the tray poofs, he walks back to his place with nothing in
    /// the way, the tray pops in again and he eats; no frame of the second tray has more overlap than the eating pose itself.
    func testDroppedInFrontOfTheTrayMidMeal() {
        let base = meal(from: SIMD2(0, 0.2), id: "berries", name: "baselineDrop")
        let m = MealRun()
        m.brain.requestNow(.goTo(SIMD2(0, 0.2)))
        m.run(10) { m.brain.activity == .idle && simd_distance(m.brain.position, SIMD2(0, 0.2)) < 0.3 }
        m.run(0.8)
        m.care.feed("berries")
        m.run(30) { m.brain.activity == .eating }
        XCTAssertEqual(m.brain.activity, .eating)
        // the grab: his job is cancelled and he is put down 1.7 u nearer the camera (in front of the tray)
        m.brain.abortScript(m.rig.sim, m.rig.skinner)
        for i in 0..<m.rig.sim.x.count / 3 { m.rig.sim.x[3 * i + 2] += 1.7 }
        for i in m.rig.sim.v.indices { m.rig.sim.v[i] = 0 }
        m.brain.currentPose(m.rig.sim)
        var sawAbsent = false, ateAgain = false, skin = Float.infinity
        for _ in 0..<(60 * 50) {
            m.tick()
            if m.tray.phase == .absent && m.care.trayOut { sawAbsent = true }
            if sawAbsent, m.tray.phase == .popping || m.tray.phase == .present { skin = min(skin, Self.skinClearance(m.rig.sim, tray: m.tray)) }
            if sawAbsent, m.brain.activity == .eating { ateAgain = true }
            if ateAgain, m.tray.phase == .absent, !m.care.trayOut { break }
        }
        MotionLog.write("NAV2 drop: re-served \(sawAbsent) ate again \(ateAgain) skin min after \(skin) (baseline \(base.skin))")
        XCTAssertTrue(sawAbsent, "the tray went away while he was displaced")
        XCTAssertTrue(ateAgain, "he ate after walking back")
        XCTAssertGreaterThanOrEqual(skin, base.skin - 0.01, "the second tray never overlaps him more than the eating pose")
    }

    /// Come here while he is still walking to his place (the tray is not out yet): the pending tray is dropped, he comes and STAYS at the call spot.
    func testComeHereWhileWalkingToThePlace() {
        let m = MealRun()
        m.brain.requestNow(.goTo(SIMD2(0, 2.3)))
        m.run(14) { m.brain.activity == .idle && simd_distance(m.brain.position, SIMD2(0, 2.3)) < 0.3 }
        m.run(0.8)
        m.care.feed("berries")
        m.run(1.0)
        XCTAssertTrue(m.care.trayOut, "the meal is pending")
        XCTAssertEqual(m.tray.phase, .absent, "no tray yet: he is walking to his place")
        m.care.comeHere()
        m.run(25) { m.care.focus.phase == .focused }
        XCTAssertEqual(m.care.focus.phase, .focused)
        for _ in 0..<(60 * 4) {
            m.tick()
            XCTAssertLessThan(simd_distance(m.brain.position, GameCamera.callSpot), 0.5, "he stays at the call spot")
        }
        XCTAssertFalse(m.care.trayOut, "the pending tray was dropped")
        XCTAssertEqual(m.tray.phase, .absent)
    }

    /// Come here while the tray is out: the tray poofs first (its collider is gone at once) and he starts walking only once it has gone, so he
    /// never walks through it; he then arrives at the call spot.
    func testComeHereWithTheTrayOut() {
        let m = MealRun()
        m.brain.requestNow(.goTo(SIMD2(0, 0.2)))
        m.run(10) { m.brain.activity == .idle && simd_distance(m.brain.position, SIMD2(0, 0.2)) < 0.3 }
        m.care.feed("berries")
        m.run(30) { m.brain.activity == .eating }
        XCTAssertEqual(m.brain.activity, .eating)
        XCTAssertTrue(m.tray.isPresent)
        let start = m.brain.position
        m.care.comeHere()
        var walkedWithTray = false, sawGone = false, minSkinWalking = Float.infinity
        for _ in 0..<(60 * 25) {
            m.tick()
            if (m.brain.activity == .coming || m.brain.activity == .walking) && m.tray.isPresent { walkedWithTray = true }
            if m.tray.isPresent && m.brain.activity == .coming { minSkinWalking = min(minSkinWalking, Self.skinClearance(m.rig.sim, tray: m.tray)) }
            if m.tray.phase == .absent { sawGone = true; XCTAssertTrue(RoomLayout.dynamicBoxes.isEmpty, "no collider once the tray is poofing / gone") }
            if m.care.focus.phase == .focused { break }
        }
        MotionLog.write("NAV2 come: start \(start) end \(m.brain.position) walkedWithTray \(walkedWithTray) focus \(m.care.focus.phase)")
        XCTAssertTrue(sawGone, "the tray poofed")
        XCTAssertFalse(walkedWithTray, "he starts walking only after the tray has gone")
        XCTAssertLessThan(simd_distance(m.brain.position, GameCamera.callSpot), 0.5, "he arrives at the call spot")
    }

    /// Three Blobs with the tray out, from mixed starts behind it (and beside it), to their places: all arrive; the skin never gets closer to the
    /// tray than the standing pose of the same Blob at his place plus a little (the walk is not the thing that overlaps).
    func testThreeBlobsFromMixedStarts() {
        let rigs = (0..<3).map { _ in MotionRig(game: true) }
        for (i, r) in rigs.enumerated() {
            r.brain.autonomy = false; r.brain.steerID = i
            r.brain.peers = { rigs.enumerated().filter { $0.offset != i }.map { (id: $0.offset, pos: $0.element.brain.position) } }
        }
        let tray = DiningSet(); defer { tray.reset() }
        let origin = DiningSpot.preferred
        _ = tray.spawn(serving: Consumables.berries, n: 3, bobAt: SIMD2(99, 99), forcedOrigin: origin)
        for _ in 0..<40 { tray.update(dt: 1 / 60) }
        let places = tray.places.map { $0.stand }
        // starts: one far left behind, one right beside the stands, one centre-back; each goes to a place on the other side
        let starts: [SIMD2<Float>] = [SIMD2(0.9, places[0].y - 1.2), SIMD2(-0.9, places[0].y - 0.9), SIMD2(0.1, places[0].y - 1.6)]
        let goals = [places[1], places[2], places[0]]
        for (i, r) in rigs.enumerated() {
            r.brain.requestNow(.goTo(starts[i]))
            r.run(12) { r.brain.activity == .idle && simd_distance(r.brain.position, starts[i]) < 0.4 }
            r.run(0.5)
        }
        MotionLog.write("NAV2 three starts \(rigs.map { $0.brain.position }) places \(places)")
        for (i, r) in rigs.enumerated() { r.brain.requestNow(.goTo(goals[i])) }
        var skin = [Float](repeating: .infinity, count: 3), arrived = [Bool](repeating: false, count: 3), stand = [Float](repeating: .infinity, count: 3)
        var minPair = Float.infinity
        for f in 0..<(60 * 30) {
            for r in rigs { r.tick() }
            for i in 0..<3 {
                let c = Self.skinClearance(rigs[i].sim, tray: tray)
                skin[i] = min(skin[i], c)
                if rigs[i].brain.activity == .idle && simd_distance(rigs[i].brain.position, goals[i]) < 0.3 { arrived[i] = true; stand[i] = min(stand[i], c) }
                for j in (i + 1)..<3 where j < 3 { minPair = min(minPair, simd_distance(rigs[i].brain.position, rigs[j].brain.position)) }
            }
            if f % 6 == 0 { for i in 0..<3 { let c = rigs[i].sim.centroid(); MotionLog.write(String(format: "NAV2PATH three%d %.3f %.3f 1", i, c.x, c.z)) } }
            if !arrived.contains(false), f > 60 { break }
        }
        MotionLog.write("NAV2 three arrived \(arrived) skin min \(skin) at the stands \(stand) min pair \(minPair)")
        XCTAssertFalse(arrived.contains(false), "all three arrive")
        for i in 0..<3 { XCTAssertGreaterThanOrEqual(skin[i], stand[i] - 0.06, "Blob \(i): never closer to the tray than when standing at his place") }
        XCTAssertGreaterThan(minPair, 0.05, "nobody is on top of another")
    }
}
