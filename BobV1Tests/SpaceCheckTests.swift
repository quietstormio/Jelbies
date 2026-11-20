//
//  SpaceCheckTests.swift
//  Not a regression test: MEASURES whether the Jelmiko use the whole walkable floor (home: 1 / 2 / 3 bodies; park: 3 own + 2 visitors), portrait and landscape of an iPhone 17 Pro Max.
//  Runs only when SPACE_DIR is set (TEST_RUNNER_SPACE_DIR=<folder>); writes per run a CSV of every body's floor position + what it does at 10 Hz, and per (room, count, orientation) a
//  geometry JSON (polygon rows, free spans, a reason code per 0.25 cell, obstacles). The pictures and numbers are made by space_report.py from those files.
//  Switches: SPACE_MIN (simulated minutes, default 30), SPACE_SEEDS ("1,2,3"), SPACE_ORIENT ("p,l"), TEST_RUNNER_ prefix on each.
//  Floor = the app's own functions with the app's own inputs: RoomLayout.apply, GameCamera.configureRoom(count:) / configurePark(), GameCamera.refreshRoam(aspect: drawable w / h), as MelonStage.syncRoam does.
//  Bodies = SocialTests.Lab (wired as the stage wires its roster: keepApart, makeRoom, peers), the brain flags the stage sets each frame (homeRoom, watching, anticsEnabled, sleepEnabled).
//

import XCTest
import simd
@testable import BobV1

@MainActor
final class SpaceCheckTests: XCTestCase {
    private let env = ProcessInfo.processInfo.environment
    private var dir: String { env["SPACE_DIR"] ?? "" }

    override func setUp() { DecorField.shared.clear(); DecorField.shared.toys = ToyBook(); ToyTuning.settle = 0 }
    override func tearDown() {
        DecorField.shared.clear(); ToyTuning.settle = 5
        GameCamera.endPark(count: 3); _ = GameCamera.camera(aspect: 440.0 / 956.0); GameCamera.homeRailCutouts = true; EmoteSpot.enabled = true
        GameCamera.configureRoom(count: 1); GameCamera.clearRoam(); RoomLayout.apply(RoomCatalog.home)
        HUDLayout.measuredSize = .zero; HUDLayout.measuredInsets = .zero
        SocialTests.keep.removeAll()
    }

    // iPhone 17 Pro Max: 1320 x 2868 px drawable (aspect 440 / 956 points)
    static let portrait: Float = 1320.0 / 2868.0
    static let landscape: Float = 2868.0 / 1320.0

    func testHome1() throws { try runRoom(home: 1) }
    func testHome2() throws { try runRoom(home: 2) }
    func testHome3() throws { try runRoom(home: 3) }
    func testPark() throws { try runRoom(home: 0) }
    /// The owner's real states: 19:00 and low needs (SPACE_LOW=1 is set by these two): hunger 0.08, thirst 0.08, attention 0.5 (BlobNeeds.mood(of:) names the mood: grumpy), dirt 0.8 (dirt is not read by the roaming brain).
    func testHome3Low() throws { low = true; defer { low = false }; try runRoom(home: 3) }
    func testParkLow() throws { low = true; defer { low = false }; try runRoom(home: 0) }
    private var low = false

    private func runRoom(home n: Int) throws {
        guard !dir.isEmpty else { throw XCTSkip("SPACE_DIR not set") }
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let seeds = (env["SPACE_SEEDS"] ?? "1,2,3").split(separator: ",").compactMap { UInt64($0) }
        let orients = (env["SPACE_ORIENT"] ?? "p,l").split(separator: ",").map(String.init)
        let minutes = Double(env["SPACE_MIN"] ?? "30") ?? 30
        GameCamera.homeRailCutouts = env["SPACE_RAILS"] != "0"          // (SPACE_RAILS=0: the home-room button cut-outs off)
        for o in orients {
            let aspect = o == "p" ? Self.portrait : Self.landscape
            for seed in seeds { try runCase(home: n, orient: o, aspect: aspect, seed: seed, minutes: minutes) }
        }
    }

    // MARK: one run

    private func setup(home n: Int, aspect: Float) -> (floor: GameCamera.RoamFloor, bodies: Int, spots: [SIMD2<Float>]) {
        GameCamera.clearRoam(); DecorField.shared.clear(); DecorField.shared.toys = ToyBook(); ToyTuning.settle = 0
        if env["SPACE_HUD"] == "1" {          // the app's own inputs for the button cut-outs: the measured window (points, incl. safe areas) and its safe insets (iPhone 17 Pro Max)
            let port = aspect < 1
            HUDLayout.measuredSize = port ? CGSize(width: 440, height: 956) : CGSize(width: 956, height: 440)
            HUDLayout.measuredInsets = port ? UIEdgeInsets(top: 62, left: 0, bottom: 34, right: 0) : UIEdgeInsets(top: 0, left: 62, bottom: 21, right: 62)
        } else { HUDLayout.measuredSize = .zero; HUDLayout.measuredInsets = .zero }
        for (uid, ps) in HopscotchLine.shared.lines { for pl in ps { HopscotchLine.shared.remove(uid, pl.id) } }
        if n == 0 {
            ParkPlayTuning.seesawInPark = false          // the shipped park has no seesaw (the test host turns it on for the seesaw's own suites)
            RoomLayout.apply(RoomCatalog.park); GameCamera.configurePark()
            let rf = GameCamera.refreshRoam(aspect: aspect)!
            DecorField.shared.set(ParkToys.placed)
            DecorField.shared.toys.news.removeAll()
            return (rf, 5, ParkLayout.spots(count: 5))
        }
        RoomLayout.apply(RoomCatalog.home); GameCamera.configureRoom(count: n)
        let rf = GameCamera.refreshRoam(aspect: aspect)!
        return (rf, n, JellyRoster.spawnSpots(count: n))
    }

    private func stateOf(_ b: BlobBrain) -> String {
        if let s = b.social { return (s.kind.isGroup ? "group:" : "pair:") + s.kind.rawValue }
        if let k = b.idleState.kind {
            let nm = "\(k)"
            if nm == "sleep" || nm == "sit" { return "rest:" + nm }
            if BlobBrain.decorKinds.contains(k) || nm.hasPrefix("decor") || nm == "hopscotch" { return "toy:" + nm }
            return "solo:" + nm
        }
        if b.activity == .walking || b.activity == .coming { return "walk" }
        if case .walk = b.script { return "walk" }
        return "stand:\(b.activity)/\(b.scriptKindName)"
    }

    private func runCase(home n: Int, orient: String, aspect: Float, seed: UInt64, minutes: Double) throws {
        let name = (n == 0 ? "park" : "home\(n)") + "_" + orient + (low ? "_low" : "") + (env["SPACE_RAILS"] == "0" ? "_norail" : "")
        DayClock.shared.forcedHour = low ? 19 : 12
        EmoteSpot.reset(); EmoteSpot.enabled = env["SPACE_SPOT"] != "0"
        let (rf, bodies, spots) = setup(home: n, aspect: aspect)
        if seed == (env["SPACE_SEEDS"].flatMap { $0.split(separator: ",").compactMap { UInt64($0) }.first } ?? 1) { try writeGeometry(name: name, rf: rf, aspect: aspect, home: n) }
        let lab = SocialTests.Lab(n: bodies, positions: spots, quiet: false, seed: seed &* 1009 &+ UInt64(n) &* 17)
        for r in lab.rigs {
            r.sim.arenaCenter = GameCamera.arenaCenter; r.sim.arenaRadius = GameCamera.arenaRadius
            let b = r.brain
            b.anticsEnabled = true; b.idleMood = .happy; b.watching = true; b.sleepEnabled = true
            if low {          // as MelonStage.otherTick sets them each frame: the mood the needs make, and the clock's night / morning factors
                b.idleMood = BlobNeeds.mood(of: [0.08, 0.08, 0.5])
                b.idleNight = DayClock.shared.nightFactor; b.idleMorning = DayClock.shared.morningFactor; b.idleDeepNight = DayClock.shared.deepNightFactor
            }
            if n == 0 { b.outingPlay = true; b.homeRoom = false } else { b.homeRoom = true }
        }
        let steps = Int(minutes * 60 * 60)
        var csv = "t,id,x,z,state\n"
        var emotes = "t,id,x,z,class,kind,walk\n"
        var prevKind = [String](repeating: "", count: bodies)
        var seen = Set<ObjectIdentifier>()
        var arrived = Set<ObjectIdentifier>(); var began = [ObjectIdentifier: Double](); var preWalk = [ObjectIdentifier: Float]()
        var arrive = "t,kind,group,walk\n"
        let t0 = Date()
        for s in 0..<steps {
            lab.tick(watching: false)
            // sessions: record the session's own spot once
            for r in lab.rigs { if let sess = r.brain.social, true, !seen.contains(ObjectIdentifier(sess)) {
                seen.insert(ObjectIdentifier(sess)); began[ObjectIdentifier(sess)] = Double(s) / 60
                var pre: Float = 0; for r2 in lab.rigs where r2.brain.social === sess { pre = max(pre, r2.brain.emoteSpot.walked); r2.brain.emoteSpot.walked = 0 }; preWalk[ObjectIdentifier(sess)] = pre
                let t = Double(s) / 60
                var spot: SIMD2<Float>
                if sess.kind.isGroup, !sess.slotSpot.isEmpty { spot = sess.slotSpot.values.reduce(SIMD2<Float>(0, 0), +) / Float(sess.slotSpot.count) }
                else { let ps = lab.rigs.filter { $0.brain.social === sess }.map { GameCare.floorPos($0.brain, $0.sim) }; spot = ps.reduce(SIMD2<Float>(0, 0), +) / Float(max(ps.count, 1)) }
                emotes += String(format: "%.2f,%d,%.3f,%.3f,%@,%@,0\n", t, -1, spot.x, spot.y, sess.kind.isGroup ? "group" : "pair", sess.kind.rawValue)
            } }
            for r in lab.rigs { if let sess = r.brain.social, sess.phase >= 1, !arrived.contains(ObjectIdentifier(sess)), let b0 = began[ObjectIdentifier(sess)] {
                arrived.insert(ObjectIdentifier(sess)); arrive += String(format: "%.2f,%@,%d,%.2f\n", b0, sess.kind.rawValue, sess.kind.isGroup ? 1 : 0, Double(s) / 60 - b0 + Double(preWalk[ObjectIdentifier(sess)] ?? 0))
            } }
            if s % 6 == 0 {
                let t = Double(s) / 60
                for (i, r) in lab.rigs.enumerated() {
                    let p = GameCare.floorPos(r.brain, r.sim)
                    let st = stateOf(r.brain)
                    csv += String(format: "%.1f,%d,%.3f,%.3f,%@\n", t, i, p.x, p.y, st)
                    if st.hasPrefix("solo:"), prevKind[i] != st { emotes += String(format: "%.2f,%d,%.3f,%.3f,solo,%@,%.2f\n", t, i, p.x, p.y, String(st.dropFirst(5)), r.brain.emoteSpot.walked); r.brain.emoteSpot.walked = 0 }
                    prevKind[i] = st
                }
            }
        }
        let wall = Date().timeIntervalSince(t0)
        // the floor must still be ours at the end (the hosting app's stage could rebuild it)
        let end = GameCamera.roamFloor
        XCTAssertEqual(end?.aspect, rf.aspect, "\(name): the floor is still the one the run started with"); XCTAssertEqual(end?.zs.count, rf.zs.count)
        let meta = "mood \(lab.rigs[0].brain.idleMood) night \(lab.rigs[0].brain.idleNight) morning \(lab.rigs[0].brain.idleMorning) deepNight \(lab.rigs[0].brain.idleDeepNight); case \(name) seed \(seed) aspect \(aspect) bodies \(bodies) minutes \(minutes) wall \(wall) s; floor minZ \(rf.minZ) maxZ \(rf.maxZ) rows \(rf.zs.count) area \(rf.area); traffic \(RoomRoam.traffic) loneFloor \(RoomTraffic.loneFloor) loneBack \(RoomTraffic.loneBack) loneBackCount \(RoomTraffic.counts[5]) spreadNew \(ParkPlayTuning.spreadNew) arena \(GameCamera.arenaCenter) r \(GameCamera.arenaRadius) forcedHour \(String(describing: DayClock.shared.forcedHour))"
        print("[space] " + meta)
        try csv.write(toFile: "\(dir)/\(name)_s\(seed).csv", atomically: true, encoding: .utf8)
        try emotes.write(toFile: "\(dir)/\(name)_s\(seed)_emotes.csv", atomically: true, encoding: .utf8)
        try arrive.write(toFile: "\(dir)/\(name)_s\(seed)_arrive.csv", atomically: true, encoding: .utf8)
        try meta.write(toFile: "\(dir)/\(name)_s\(seed).meta.txt", atomically: true, encoding: .utf8)
        RoomTraffic.counts = [0, 0, 0, 0, 0, 0]
        SocialTests.keep.removeAll()
    }

    // MARK: geometry

    private func writeGeometry(name: String, rf: GameCamera.RoamFloor, aspect: Float, home n: Int) throws {
        let size = CGSize(width: CGFloat(1000 * aspect), height: 1000)
        let cam = GameCamera.camera(aspect: aspect, gamePose: true)
        let rails = (aspect < 1 || HUDLayout.phoneMeasured ? HUDLayout.railRects(aspect: aspect) : []) + (GameCamera.parkRoamMaxZ != nil ? [HUDLayout.parkHomeRect(aspect: aspect)] : [])
        let c = GameCamera.roamFurnitureClearance
        let x0: Float = -6, z0: Float = -6, cell: Float = 0.25, cols = 48, rowsN = 72
        var codes = [[Int]]()          // 0 outside polygon, 1 walkable, 2 sofa, 3 cylinder, 4 HUD rail / pill, 5 solid toy footprint, 6 other cut
        for j in 0..<rowsN {
            var row = [Int]()
            for i in 0..<cols {
                let p = SIMD2<Float>(x0 + (Float(i) + 0.5) * cell, z0 + (Float(j) + 0.5) * cell)
                if !rf.contains(p) { row.append(0); continue }
                let ri = max(0, min(rf.zs.count - 1, Int(floorf((p.y - rf.minZ) / GameCamera.RoamFloor.step))))
                let inSpan = rf.free[ri].contains { $0.contains(p.x) }
                let toy = DecorField.shared.feet.filter { $0.spec.solid }.map { $0.distance(p) }.min() ?? 9
                if inSpan { row.append(toy < 0.7 ? 5 : 1); continue }
                if HUDLayout.bodyHitsRail(x: p.x, z: p.y, viewProj: cam.viewProj, size: size, rails: rails) { row.append(4) }
                else if RoomLayout.sofaDistanceXZ(p) < c { row.append(2) }
                else if RoomLayout.cylinders.contains(where: { simd_distance(p, $0.centre) < $0.radius + c }) { row.append(3) }
                else { row.append(6) }
            }
            codes.append(row)
        }
        var objs = [[String: Any]]()
        let s = RoomLayout.sofa
        objs.append(["kind": "box", "name": n == 0 ? "bench" : "sofa", "cx": s.centre.x, "cz": s.centre.z, "hx": s.halfExtents.x, "hz": s.halfExtents.z])
        for (k, cy) in RoomLayout.cylinders.enumerated() { objs.append(["kind": "circle", "name": n == 0 ? "cyl\(k)" : (k == 0 ? "side table + lamp" : "plant"), "cx": cy.centre.x, "cz": cy.centre.y, "r": cy.radius]) }
        for f in DecorField.shared.feet { objs.append(["kind": "box", "name": "\(f.kind.rawValue)", "cx": f.centre.x, "cz": f.centre.y, "hx": f.spec.half.x, "hz": f.spec.half.y, "solid": f.spec.solid]) }
        if n == 0 {
            objs.append(["kind": "circle", "name": "pond (scenery, no collider)", "cx": 3.5, "cz": -4.2, "r": 1.0, "soft": true])
            objs.append(["kind": "circle", "name": "lamp post", "cx": ParkScenery.benchX + 1.72, "cz": -4.85, "r": 0.2])
            objs.append(["kind": "path", "name": "path (scenery)", "pts": stride(from: Float(-5), through: 5, by: 0.5).map { [0.7 * sinf(0.34 * $0), $0] }, "half": 0.62])
        } else {
            objs.append(["kind": "circle", "name": "rug (floor art)", "cx": RoomLayout.rugCentre.x, "cz": RoomLayout.rugCentre.y, "r": RoomLayout.rugRadius, "soft": true])
            objs.append(["kind": "circle", "name": "food bowl spot", "cx": GameCamera.foodBowlSpot.x, "cz": GameCamera.foodBowlSpot.y, "r": 0.25, "soft": true])
            objs.append(["kind": "circle", "name": "water bowl spot", "cx": GameCamera.waterBowlSpot.x, "cz": GameCamera.waterBowlSpot.y, "r": 0.25, "soft": true])
        }
        let info: [String: Any] = ["name": name, "aspect": aspect, "x0": x0, "z0": z0, "cell": cell, "cols": cols, "rows": rowsN, "codes": codes,
                                   "zs": rf.zs, "hw": rf.hw, "free": rf.free.map { $0.map { [$0.lowerBound, $0.upperBound] } }, "minZ": rf.minZ, "maxZ": rf.maxZ, "objects": objs,
                                   "loneBackFrom": RoomTraffic.loneBackFrom, "loneBackFull": RoomTraffic.loneBackFull, "loneBackChance": RoomTraffic.loneBackChance, "zoneBackZ": GameCamera.RoamFloor.zoneBackZ]
        let data = try JSONSerialization.data(withJSONObject: info, options: [.sortedKeys])
        try data.write(to: URL(fileURLWithPath: "\(dir)/\(name)_geom.json"))
    }
}
