//
//  TrayNav3Tests.swift
//  Two and three Blobs at the tray (DiningGroup): from a grid of room starts, including in front of the tray, nobody's body enters the tray
//  and nobody walks through another. `testLegacyBaseline` measures the OLD behaviour (tray pops at once, everybody walks to place i) for the
//  before/after numbers. Timing is judged on states and positions, never on walk durations (the walk speed is being changed elsewhere).
//
//  Paths are written to $DINE3_OUT (default: the temp dir) as CSV: label,mode,blob,t,x,z,trayOut  and  TRAY,label,mode,ox,oz,hx,hz.
//

import XCTest
import simd
@testable import BobV1

@MainActor
final class TrayNav3Tests: XCTestCase {
    override func setUp() { RoomLayout.dynamicBoxes = [] }
    override func tearDown() { RoomLayout.dynamicBoxes = [] }

    static let front = SIMD2<Float>(0, 2.3), spot = SIMD2<Float>(0, 1.3), left = SIMD2<Float>(-0.9, 1.3), right = SIMD2<Float>(0.9, 1.3)
    static let frontL = SIMD2<Float>(-0.9, 2.2), frontR = SIMD2<Float>(0.9, 2.2), behind = SIMD2<Float>(0, -0.3)
    static let behindL = SIMD2<Float>(-1.3, 0.2), behindR = SIMD2<Float>(1.3, 0.2)
    static let frontFar = SIMD2<Float>(-1.5, 2.3)

    /// Start grids: every one has at least one Blob in front of the tray or on its spot.
    static let grid2: [[SIMD2<Float>]] = [
        [front, behind], [spot, behindL], [frontL, frontR], [front, spot], [frontL, behindR], [left.mapZ(0.5), right], [spot, front.mapX(1.3)],
        [behindL, frontR], [front.mapX(-0.7), front.mapX(0.7)], [right, frontL],
    ]
    static let grid3: [[SIMD2<Float>]] = [
        [front, behindL, behindR], [frontL, spot, frontR], [frontL, SIMD2(0.1, 1.2), frontR], [spot, SIMD2(-0.95, 0.3), SIMD2(0.95, 1.9)],
        [front.mapX(0.6), behind, frontFar], [behindL, behind, behindR], [frontL, behindR, spot.mapZ(0.6)], [left.mapZ(1.0), front, right.mapZ(1.0)],
    ]

    /// Centre gap a walking Blob keeps from another (the stands themselves are 0.85-1.1 apart and their soft bodies overlap by design).
    static let walkGap: Float = 0.6

    struct Metrics {
        var n = 0, label = "", ate = [Bool](), arrivedAll = false
        var centroidInside = [Int](), walkSkin = [Float](), standSkin = [Float](), minPair = Float.infinity, minPairTrayOut = Float.infinity, minPairWalk = Float.infinity, startGap = Float.infinity
        var trayBeforeClear = false              // the tray popped while somebody was still in front of his line
        var rows: [String] = []
        /// Blob `i`'s walk went through the tray: its centre was inside, or its walking skin was deeper in than the eating pose itself.
        func hitTray(_ i: Int) -> Bool { centroidInside[i] > 0 || walkSkin[i] < standSkin[i] - 0.06 }
        var trayHits: Int { (0..<n).filter { hitTray($0) }.count }
    }

    static func moving(_ a: BlobActivity) -> Bool { a == .walking || a == .turning || a == .coming }
    private func csvDir() -> String { ProcessInfo.processInfo.environment["DINE3_OUT"] ?? NSTemporaryDirectory() }

    /// Runs one meal. `after`: DiningGroup; otherwise the old behaviour.
    func runMeal(_ starts: [SIMD2<Float>], food: Consumable = Consumables.berries, after: Bool, label: String) -> Metrics {
        let n = starts.count
        let rigs = (0..<n).map { _ in MotionRig(game: true) }
        for (i, r) in rigs.enumerated() {
            r.brain.autonomy = false; r.brain.steerID = i
            r.brain.peers = { rigs.enumerated().filter { $0.offset != i }.map { (id: $0.offset, pos: $0.element.brain.position) } }
        }
        // walk to the starts together
        for (i, r) in rigs.enumerated() { r.brain.requestNow(.goTo(starts[i])) }
        var f = 0
        while f < 60 * 16 {
            for r in rigs { r.tick() }
            f += 1
            if rigs.enumerated().allSatisfy({ $0.element.brain.activity == .idle && simd_distance($0.element.brain.position, starts[$0.offset]) < 0.45 }), f > 30 { break }
        }
        for _ in 0..<48 { for r in rigs { r.tick() } }
        var m = Metrics(); m.n = n; m.label = label
        m.ate = [Bool](repeating: false, count: n); m.centroidInside = [Int](repeating: 0, count: n)
        m.walkSkin = [Float](repeating: .infinity, count: n); m.standSkin = [Float](repeating: .infinity, count: n)
        let mode = after ? "after" : "before"
        let startPos = rigs.map { $0.brain.position }
        for i in 0..<n { for j in (i + 1)..<n where j < n { m.startGap = min(m.startGap, simd_distance(startPos[i], startPos[j])) } }
        MotionLog.write("NAV3 \(mode) \(label) starts \(startPos)")

        let group = DiningGroup()
        let legacy = DiningSet()
        var legacyDone = [Bool](repeating: false, count: n)
        var tray: DiningSet { after ? group.dining : legacy }
        if after {
            group.start(food, brains: rigs.map { $0.brain }, floor: { rigs[$0].brain.position })
        } else {
            _ = legacy.spawn(serving: food, n: n, bobAt: SIMD2(99, 99), forcedOrigin: DiningSpot.choose(bob: SIMD2(99, 99), layout: DiningLayout.make(n: n)))
            for (i, r) in rigs.enumerated() {
                r.brain.onFinished = { req in switch req { case .dine, .sip: legacyDone[i] = true; default: break } }
                let base = r.brain.resolve
                r.brain.resolve = { p, rad in legacy.obstacle(base(p, rad), radius: rad * RoomLayout.lowPropRadiusScale) }
                r.brain.dineHooks = GameCare.hooks(for: food, tray: legacy, place: i)
                r.brain.requestNow(GameCare.mealRequest(food, tray: legacy, place: i))
            }
        }
        var popped = false
        let t0 = rigs[0].t
        for frame in 0..<(60 * 70) {
            for r in rigs { r.tick() }
            if after { group.tick(dt: rigs[0].sim.stepDt) } else { legacy.update(dt: rigs[0].sim.stepDt) }
            let t = tray
            let out = t.phase == .popping || t.phase == .present
            if out && !popped {
                popped = true
                if after { for i in 0..<n where rigs[i].brain.position.y > group.dining.places.map(\.stand.y).min()! + 0.5 { m.trayBeforeClear = true } }
                m.rows.append("TRAY,\(label),\(mode),\(t.origin.x),\(t.origin.y),\(t.layout.half.x),\(t.layout.half.y)")
            }
            for i in 0..<n {
                let c = rigs[i].sim.centroid()
                if out {
                    let skin = TrayNav2Tests.skinClearance(rigs[i].sim, tray: t)
                    if TrayNav2Tests.rectDistance(SIMD2(c.x, c.z), tray: t) < 0 { m.centroidInside[i] += 1 }
                    let a = rigs[i].brain.activity
                    if a == .eating || a == .drinking { m.standSkin[i] = min(m.standSkin[i], skin); m.ate[i] = true }
                    if a == .walking || a == .turning { m.walkSkin[i] = min(m.walkSkin[i], skin) }
                }
                for j in (i + 1)..<n where j < n {
                    let d = simd_distance(SIMD2(c.x, c.z), SIMD2(rigs[j].sim.centroid().x, rigs[j].sim.centroid().z))
                    m.minPair = min(m.minPair, d)
                    let wa = rigs[i].brain.activity, wb = rigs[j].brain.activity
                    if Self.moving(wa) || Self.moving(wb) { m.minPairWalk = min(m.minPairWalk, d) }
                    if out { m.minPairTrayOut = min(m.minPairTrayOut, d) }
                }
                if frame % 6 == 0 { m.rows.append(String(format: "%@,%@,%d,%.2f,%.3f,%.3f,%d", label, mode, i, rigs[0].t - t0, c.x, c.z, out ? 1 : 0)) }
            }
            let finished = after ? (!group.isActive && popped) : legacyDone.allSatisfy { $0 }
            if finished && (after ? group.dining.phase == .absent : true) { break }
        }
        m.arrivedAll = m.ate.allSatisfy { $0 }
        for i in 0..<n where m.standSkin[i] == .infinity { m.standSkin[i] = -9 }          // never ate: no baseline
        let line = String(format: "%@ %@ n=%d ate=%@ trayHits=%d centroidInside=%@ walkSkin=%@ standSkin=%@ minPair=%.2f (tray out %.2f, while walking %.2f, start gap %.2f) trayBeforeClear=%d", mode, label, n, "\(m.ate)", m.trayHits, "\(m.centroidInside)", "\(m.walkSkin.map { String(format: "%.2f", $0) })", "\(m.standSkin.map { String(format: "%.2f", $0) })", m.minPair, m.minPairTrayOut, m.minPairWalk, m.startGap, m.trayBeforeClear ? 1 : 0)
        if let h = FileHandle(forWritingAtPath: csvDir() + "/summary_\(mode).txt") { h.seekToEndOfFile(); h.write(Data((line + "\n").utf8)); try? h.close() }
        else { try? (line + "\n").write(toFile: csvDir() + "/summary_\(mode).txt", atomically: true, encoding: .utf8) }
        MotionLog.write(String(format: "NAV3 %@ %@ n=%d ate=%@ trayHits=%d centroidInside=%@ walkSkin=%@ standSkin=%@ minPair=%.2f (tray out %.2f)", mode, label, n, "\(m.ate)", m.trayHits, "\(m.centroidInside)", "\(m.walkSkin.map { String(format: "%.2f", $0) })", "\(m.standSkin.map { String(format: "%.2f", $0) })", m.minPair, m.minPairTrayOut))
        legacy.reset(); group.dining.reset()
        return m
    }

    private func dump(_ ms: [Metrics], mode: String) {
        let path = csvDir() + "/paths_\(mode).csv"
        var s = "label,mode,blob,t,x,z,trayOut\n"
        for m in ms { s += m.rows.joined(separator: "\n") + "\n" }
        try? s.write(toFile: path, atomically: true, encoding: .utf8)
    }

    private func sweep(after: Bool) -> [Metrics] {
        var out: [Metrics] = []
        try? FileManager.default.removeItem(atPath: csvDir() + "/summary_\(after ? "after" : "before").txt")
        for (k, g) in Self.grid2.enumerated() { out.append(runMeal(g, after: after, label: "n2g\(k)")) }
        for (k, g) in Self.grid3.enumerated() { out.append(runMeal(g, after: after, label: "n3g\(k)")) }
        dump(out, mode: after ? "after" : "before")
        let blobs = out.reduce(0) { $0 + $1.n }
        let hits = out.reduce(0) { $0 + $1.trayHits }
        let bad = out.filter { $0.minPairWalk < Self.walkGap }.count
        let sum = "NAV3SUMMARY \(after ? "after" : "before"): runs \(out.count), blobs \(blobs), blob paths intersecting tray \(hits), runs where a walking Blob came within \(Self.walkGap) of another \(bad), runs where not everybody ate \(out.filter { !$0.arrivedAll }.count), worst pair while walking \(out.map(\.minPairWalk).min() ?? 0)"
        MotionLog.write(sum)
        try? (sum + "\n").write(toFile: csvDir() + "/totals_\(after ? "after" : "before").txt", atomically: true, encoding: .utf8)
        return out
    }

    /// The old behaviour, measured (no assertions: these are the "before" numbers).
    func testLegacyBaseline() { _ = sweep(after: false) }

    /// The tray never has a body in it (centre inside, or deeper skin overlap while walking than the eating pose itself), nobody is walked through,
    /// everybody eats, and the tray only pops once nobody is left in front of his place.
    func testGroupNeverOverlapsTrayOrEachOther() {
        let ms = sweep(after: true)
        for m in ms {
            XCTAssertTrue(m.arrivedAll, "\(m.label): everybody eats \(m.ate)")
            XCTAssertEqual(m.trayHits, 0, "\(m.label): nobody's body is in the tray (centroid \(m.centroidInside), walking skin \(m.walkSkin) vs eating \(m.standSkin))")
            XCTAssertFalse(m.trayBeforeClear, "\(m.label): the tray popped while somebody was still in front of it")
            XCTAssertGreaterThan(m.startGap, 0.9, "\(m.label): the grid itself starts them apart")
            XCTAssertGreaterThan(m.minPairWalk, Self.walkGap, "\(m.label): a walking Blob never overlaps another (min centre gap \(m.minPairWalk))")
        }
    }

    /// Drinking with three straws takes the same road.
    func testGroupOfThreeSips() {
        let m = runMeal(Self.grid3[0], food: Consumables.water, after: true, label: "n3water")
        XCTAssertTrue(m.arrivedAll, "everybody sips \(m.ate)")
        XCTAssertEqual(m.trayHits, 0)
        XCTAssertGreaterThan(m.minPairWalk, Self.walkGap)
    }
}

private extension SIMD2 where Scalar == Float {
    func mapX(_ x: Float) -> SIMD2<Float> { SIMD2(x, y) }
    func mapZ(_ z: Float) -> SIMD2<Float> { SIMD2(x, z) }
}
