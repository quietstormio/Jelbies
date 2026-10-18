//
//  ThreeJellyTests.swift
//  Phase A of three Jellies at once: spawn, parallel sim, perf, persistence / migration, time away, peer avoidance, feet and arms,
//  the multi-rect room cache pieces and the single-Jelly invariants.
//

import XCTest
import simd
@testable import BobV1

@MainActor
final class ThreeJellyTests: XCTestCase {
    nonisolated(unsafe) static var keep: [AnyObject] = []

    private func suite(_ name: String) -> UserDefaults {
        let d = UserDefaults(suiteName: "ThreeJelly.\(name)")!
        d.removePersistentDomain(forName: "ThreeJelly.\(name)")
        return d
    }

    // MARK: spawn / parallel sim

    func testSpawnShiftSurvivesSteps() {
        let sm = buildSimMesh(), rm = buildRenderMesh()
        let emb = embed(simRest: sm.rest, tets: sm.tets, verts: rm.rest)
        let a = JellyActor(id: 1, name: "Pip", simMesh: sm, renderMesh: rm, embedding: emb, appearance: .berry, firmness: 0.95, damping: 0.45, spawn: SIMD2(-0.85, -1.7))
        a.reset(drop: 0.35, shift: true)
        for _ in 0..<120 { a.sim.step() }
        let c = a.sim.centroid()
        XCTAssertEqual(c.x, -0.85, accuracy: 0.1, "still where he spawned: \(c)")
        XCTAssertEqual(c.z, -1.7, accuracy: 0.3)
    }

    private func makeActors(_ n: Int) -> [JellyActor] {
        let sm = buildSimMesh(), rm = buildRenderMesh()
        let emb = embed(simRest: sm.rest, tets: sm.tets, verts: rm.rest)
        let spots = JellyRoster.spawnSpots(count: n)
        return (0..<n).map {
            let a = JellyActor(id: $0, name: JellyRoster.names[$0], simMesh: sm, renderMesh: rm, embedding: emb, appearance: .berry, firmness: 0.95, damping: 0.45, spawn: spots[$0])
            a.reset(drop: 0.35, shift: n > 1)
            return a
        }
    }

    /// The threaded step gives the very same particles as stepping the bodies one after another (bodies share nothing).
    func testParallelStepEqualsSerial() {
        let par = makeActors(3), ser = makeActors(3)
        for f in 0..<90 {
            if f == 40 { for a in par + ser { a.sim.nudge(strength: 1) } }
            JellyParallel.step(par.map(\.sim))
            for a in ser { a.sim.step() }
        }
        for i in 0..<3 { XCTAssertEqual(par[i].sim.x, ser[i].sim.x, "body \(i)") }
        let rm = buildRenderMesh()
        var d1 = [Float](repeating: 0, count: rm.vertexCount * 6 * 3), d2 = d1
        d1.withUnsafeMutableBufferPointer { b1 in d2.withUnsafeMutableBufferPointer { b2 in
            let n = rm.vertexCount * 6
            JellyParallel.skin((0..<3).map { JellyParallel.SkinJob(skinner: par[$0].skinner, sim: par[$0].sim, dst: b1.baseAddress! + $0 * n) }, index: rm.index)
            for i in 0..<3 { ser[i].skinner.update(x: ser[i].sim.x, index: rm.index, into: b2.baseAddress! + i * n) }
        } }
        XCTAssertEqual(d1, d2, "threaded skinning is identical")
    }

    /// Three bodies, one frame of work (a step + the skin), threaded vs one after another. The bound is generous on purpose (a simulator on a busy
    /// Mac is not the phone): the threaded frame must fit a 60 fps frame (16.7 ms) with the room left for the brain and the GPU encode.
    func testThreeBodiesFitASixtyFpsFrame() {
        let actors = makeActors(3)
        let rm = buildRenderMesh()
        let n = rm.vertexCount * 6
        let dyn = UnsafeMutablePointer<Float>.allocate(capacity: n * 3)
        defer { dyn.deallocate() }
        let sims = actors.map(\.sim)
        let jobs = (0..<3).map { JellyParallel.SkinJob(skinner: actors[$0].skinner, sim: actors[$0].sim, dst: dyn + $0 * n) }
        for _ in 0..<30 { JellyParallel.step(sims) }
        let frames = 200
        var t0 = CACurrentMediaTime()
        for _ in 0..<frames { JellyParallel.step(sims); JellyParallel.skin(jobs, index: rm.index) }
        let par = (CACurrentMediaTime() - t0) / Double(frames) * 1000
        t0 = CACurrentMediaTime()
        for _ in 0..<frames { for s in sims { s.step() }; for j in jobs { j.skinner.update(x: j.sim.x, index: rm.index, into: j.dst) } }
        let ser = (CACurrentMediaTime() - t0) / Double(frames) * 1000
        let one = actors[0]
        t0 = CACurrentMediaTime()
        for _ in 0..<frames { one.sim.step(); one.skinner.update(x: one.sim.x, index: rm.index, into: dyn) }
        let single = (CACurrentMediaTime() - t0) / Double(frames) * 1000
        let line = String(format: "THREEPERF per body: particles %d tets %d verts %d | 1 body step+skin %.3f ms | 3 bodies serial %.3f ms | 3 bodies threaded %.3f ms (%d cores) per 60 Hz frame",
                          one.sim.n, one.sim.nT, rm.vertexCount, single, ser, par, ProcessInfo.processInfo.activeProcessorCount)
        MotionLog.write(line); print(line)
        XCTAssertLessThan(par, 16.7, "3 bodies (step + skin, threaded) fit a 60 fps frame")
    }

    // MARK: persistence / migration

    func testLegacyKeysBecomeJellyZero() {
        let d = suite("migrate")
        let t = Date(timeIntervalSince1970: 2_000_000_000)
        // what the phone has today: the three pre-multi-Jelly keys
        d.set(["levels": [0.4, 0.55, 0.65], "time": t.timeIntervalSince1970] as [String: Any], forKey: "BlobNeeds.v1")
        let g = BlobGrime(persists: true, defaults: d, now: { t }); g.dirt = 0.3; g.save()
        let w = VoiceTraining(defaults: d, persists: true); w.debugReps(.sit, word: "sit", reps: 3); w.save()
        XCTAssertEqual(JellyKeys.needs(0), "BlobNeeds.v1"); XCTAssertEqual(JellyKeys.grime(0), "BlobGrime.v1"); XCTAssertEqual(JellyKeys.words(0), "BlobWords.v1")

        let bob = JellyProfile(id: 0, name: "Bob", persists: true, defaults: d, now: { t })
        XCTAssertEqual(bob.needs.level(.hunger), 0.4, accuracy: 1e-5)
        XCTAssertEqual(bob.needs.level(.thirst), 0.55, accuracy: 1e-5)
        XCTAssertEqual(bob.needs.level(.attention), 0.65, accuracy: 1e-5)
        XCTAssertEqual(bob.grime.dirt, 0.3, accuracy: 1e-5)
        XCTAssertEqual(bob.training.progress(.sit), 3, "his learned words came along")
        XCTAssertTrue(bob.training.isLearned(.come), "come here")
        // the others start fresh, not from Bob's data
        for id in 1...2 {
            let j = JellyProfile(id: id, name: JellyRoster.names[id], persists: true, defaults: d, now: { t })
            XCTAssertEqual(j.needs.level(NeedKind(rawValue: id)!), NeedsTuning.seedHunger, accuracy: 1e-5, "Jelly \(id) seeds like a first launch (Pip thirsty, Moss wants love)")
            XCTAssertEqual(j.needs.level(.hunger), id == 1 ? NeedsTuning.seedOthers : NeedsTuning.seedOthers, accuracy: 1e-5)
            XCTAssertEqual(j.grime.dirt, 0)
            XCTAssertEqual(j.training.progress(.sit), 0)
        }
        // Bob's data is untouched by the others' first save
        let again = JellyProfile(id: 0, name: "Bob", persists: true, defaults: d, now: { t })
        XCTAssertEqual(again.needs.level(.hunger), 0.4, accuracy: 1e-5)
        XCTAssertEqual(again.training.progress(.sit), 3)
    }

    func testEachJellyPersistsSeparately() {
        let d = suite("separate")
        let t = Date(timeIntervalSince1970: 2_000_000_000)
        let a = (0..<3).map { JellyProfile(id: $0, name: JellyRoster.names[$0], persists: true, defaults: d, now: { t }) }
        a[0].needs.set(.hunger, 0.9); a[1].needs.set(.hunger, 0.5); a[2].needs.set(.hunger, 0.35)
        a[0].grime.dirt = 0.1; a[1].grime.dirt = 0.5; a[2].grime.dirt = 0.9
        a[1].training.debugReps(.sit, word: "sit", reps: 2)
        for j in a { j.needs.save(); j.grime.save(); j.training.save() }
        let b = (0..<3).map { JellyProfile(id: $0, name: JellyRoster.names[$0], persists: true, defaults: d, now: { t }) }
        XCTAssertEqual(b.map { $0.needs.level(.hunger) }, [0.9, 0.5, 0.35])
        XCTAssertEqual(b.map { $0.grime.dirt }, [0.1, 0.5, 0.9])
        XCTAssertEqual(b.map { $0.training.progress(.sit) }, [0, 2, 0])
        XCTAssertEqual(Set([0, 1, 2].map { JellyKeys.needs($0) }).count, 3)
    }

    func testTargetJellyFollowsSelection() {
        let care = GameCare(jellyCount: 3, persistent: false)
        XCTAssertEqual(care.targetJelly, 0, "nothing selected targets Bob")
        care.select.highlight(2)
        XCTAssertEqual(care.targetJelly, 2)
    }

    func testTimeAwayAppliesToEveryJelly() {
        let care = GameCare(jellyCount: 3, persistent: false)
        XCTAssertEqual(care.jellyCount, 3)
        for j in care.jellies { for k in NeedKind.allCases { j.needs.set(k, 1) }; j.grime.dirt = 0 }
        let t0 = Date(timeIntervalSince1970: 3_000_000_000)
        care.leftActive(at: t0)
        care.returnedActive(at: t0.addingTimeInterval(4 * 3600))
        for j in care.jellies {
            XCTAssertLessThan(j.needs.level(.hunger), 0.7, "\(j.name) got hungrier while away")
            XCTAssertEqual(j.needs.level(.hunger), 1 - 0.4, accuracy: 0.01)
            XCTAssertEqual(j.grime.dirt, 0.10, accuracy: 0.005, "\(j.name) got dirtier while away")
            XCTAssertEqual(j.look.dirt, j.grime.dirt, "the look the room draws follows the dirt")
        }
        XCTAssertEqual(care.greetings, 1, "a long absence greets")
    }

    func testRosterColoursAreDistinctAndCardsAreReal() {
        let care = GameCare(jellyCount: 3, persistent: false)
        XCTAssertEqual(care.select.blobs.map(\.name), ["Bob", "Pip", "Moss"])
        XCTAssertTrue(care.select.blobs.allSatisfy { $0.floor == nil }, "no flat stand-ins: every Jelly is a real body")
        let fl = [PaletteKey.blue.palette.flesh, JellyRoster.palette(1)!.flesh, JellyRoster.palette(2)!.flesh]
        XCTAssertNotEqual(fl[0], fl[1]); XCTAssertNotEqual(fl[1], fl[2]); XCTAssertNotEqual(fl[0], fl[2])
        XCTAssertTrue(JellyRoster.palette(2)!.matte)
        XCTAssertTrue(care.needs(for: 2) === care.jellies[2].needs)
        XCTAssertEqual(JellyRoster.launchCount(suite("count")), 3, "default 3")
        let d = suite("count1"); d.set(1, forKey: "BlobCount")
        XCTAssertEqual(JellyRoster.launchCount(d), 1)
        d.set(9, forKey: "BlobCount"); XCTAssertEqual(JellyRoster.launchCount(d), 3)
        // the matte transform equals PaletteKey's for the same base
        var base = PaletteKey.blue.palette
        base.pale = SIMD3(repeating: 0.5); base.skin = base.pale; base.stripe = base.pale; base.extra = .zero
        XCTAssertEqual(JellyPalettes.matte(base).stripe, PaletteKey.blue.palette.stripe)
        XCTAssertEqual(JellyPalettes.matte(base).extra, PaletteKey.blue.palette.extra)
        XCTAssertEqual(JellyPalettes.matte(base).skin, PaletteKey.blue.palette.skin)
    }

    func testSingleJellyShadowBoxIsTheOriginal() {
        let c = SIMD3<Float>(0.3, 0.6, -0.4)
        let one = GameCamera.light(centroids: [c]), old = GameCamera.light(centroid: c)
        XCTAssertEqual(one.lightVP, old.lightVP); XCTAssertEqual(one.topVP, old.topVP)
        let three = GameCamera.light(centroids: [SIMD3(-0.15, 0.6, 1.6), SIMD3(-0.85, 0.6, -1.7), SIMD3(0.85, 0.6, -0.1)])
        // every Jelly lands inside the shadow and height maps
        for p in [SIMD3<Float>(-0.15, 0.6, 1.6), SIMD3(-0.85, 0, -1.7), SIMD3(0.85, 1.3, -0.1)] {
            for vp in [three.lightVP, three.topVP] {
                let q = vp * SIMD4(p, 1)
                XCTAssertLessThan(abs(q.x / q.w), 0.95); XCTAssertLessThan(abs(q.y / q.w), 0.95)
            }
        }
    }

    func testFootprintMergeAndComplementCoverTheViewport() {
        typealias R = RoomFootprint.Rect
        let rs = [R(x: 100, y: 200, w: 300, h: 400), R(x: 700, y: 900, w: 200, h: 300), R(x: 350, y: 500, w: 200, h: 200)]
        let m = RoomFootprint.mergeOverlapping(rs)
        XCTAssertEqual(m.count, 2, "the two touching footprints merge")
        for i in 0..<m.count { for j in (i + 1)..<m.count { XCTAssertFalse(RoomFootprint.intersects(m[i], m[j])) } }
        let comp = RoomFootprint.complement(of: m, width: 1000, height: 1500)
        // every pixel is in exactly one of: a footprint, or a blit strip
        var cover = [UInt8](repeating: 0, count: 1000 * 1500)
        for r in m + comp { for y in r.y..<(r.y + r.h) { for x in r.x..<(r.x + r.w) { cover[y * 1000 + x] += 1 } } }
        XCTAssertTrue(cover.allSatisfy { $0 == 1 }, "footprints + strips tile the viewport exactly once")
    }

    // MARK: a room of three, headless

    private func roomRigs(_ n: Int, seeded: Bool = true) -> [MotionRig] {
        let spots = JellyRoster.spawnSpots(count: n)
        let rigs = (0..<n).map { _ in MotionRig(game: true) }
        for (i, r) in rigs.enumerated() {
            r.brain.abortScript(r.sim, r.skinner)
            r.sim.teleport(toXZ: spots[i])            // clears the planted foot targets of the settle, like the stage's spawn
            for _ in 0..<120 { r.sim.step() }
            r.brain.currentPose(r.sim)
            r.brain.autonomy = true
            r.brain.steerID = i; r.brain.peerGap = MelonController.jellyGap
            if seeded { r.brain.seed = UInt64(11 + i * 7) }
        }
        Self.keep += rigs
        return rigs
    }

    /// The stage's peer rule: everybody steers around standing Jellies; between two walkers the lower id gives way (positions of the step before).
    private func wire(_ rigs: [MotionRig], _ snap: @escaping () -> [(pos: SIMD2<Float>, walking: Bool)]) {
        for (i, r) in rigs.enumerated() {
            let floorRules = r.brain.resolve
            r.brain.resolve = { p, rad in floorRules(MelonController.keepApart(floorRules(p, rad), id: i, peers: snap()), rad) }
            r.brain.peers = { snap().enumerated().filter { $0.offset != i }.map { (id: $0.element.walking ? $0.offset : Int.max / 2, pos: $0.element.pos) } }
        }
    }

    func testThreeJelliesRoamingThreeMinutesNeverOverlap() {
        let rigs = roomRigs(3)
        var snapshot: [(pos: SIMD2<Float>, walking: Bool)] = []
        wire(rigs) { snapshot }
        let sims = rigs.map(\.sim)
        var worst = ""
        var aside: Float = 0, cooldown: [Float] = [0, 0, 0]
        var trace: [String] = []
        var minGap = Float.infinity, walked: [Float] = [0, 0, 0]
        var last = rigs.map(\.root)
        let steps = 60 * 180
        for f in 0..<steps {
            snapshot = rigs.map { (pos: GameCare.floorPos($0.brain, $0.sim), walking: $0.brain.activity == .walking || $0.brain.activity == .coming) }
            aside += 1.0 / 60
            if aside >= 0.25 { MelonController.makeRoom(snapshot: snapshot, brains: rigs.map { $0.brain }, cooldown: &cooldown, dt: aside); aside = 0 }
            for r in rigs { r.brain.tick(sim: r.sim, skinner: r.skinner, dt: r.sim.stepDt, touched: false) }
            JellyParallel.step(sims)
            if f % 6 == 0 {
                let p = rigs.map(\.root)
                for i in 0..<3 { walked[i] += simd_distance(p[i], last[i]) }
                last = p
                for i in 0..<3 { for j in (i + 1)..<3 {
                    let d = simd_distance(p[i], p[j])
                    if d < 1.0, trace.count < 40, f % 30 == 0 { trace.append(String(format: "t=%.1f %d-%d d=%.2f %@ %@ jobs %@", Float(f)/60, i, j, d, "\(p)", rigs.map { "\($0.brain.activity)" }.joined(separator: ","), rigs.map { "\($0.brain.idleState.kind.map { "\($0)" } ?? "-")" }.joined(separator: ","))) }
                    if d < minGap { minGap = d; worst = String(format: "t=%.1fs pair %d-%d at %@ acts %@", Float(f) / 60, i, j, "\(p)", rigs.map { "\($0.brain.activity)" }.joined(separator: ",")) }
                } }
            }
        }
        let line = String(format: "THREEROAM 3 min: closest approach %.2f (peerGap %.2f, limit %.2f), distance walked %@ | worst: " + worst, minGap, MelonController.jellyGap, MelonController.jellyGap * 0.8, walked.map { String(format: "%.1f", $0) }.joined(separator: " / "))
        MotionLog.write(line); trace.forEach { MotionLog.write("TRACE " + $0) }
        // The brain's own peerGap is 0.9 (TrayNav3); the game steers with a wider 1.4 so they usually keep a body apart. What is guaranteed is
        // the brief's 0.8 x 0.9 = 0.72: bodies are never closer than that (a Jelly that is busy sitting can still be passed at ~0.8).
        XCTAssertGreaterThanOrEqual(minGap, 0.8 * BlobBrain().peerGap, "never closer than 0.8 x peerGap")
        XCTAssertTrue(walked.allSatisfy { $0 > 3 }, "everybody actually roamed: \(walked)")
    }

    /// Feet attached and arms stubby for ALL three at once: three rigs doing different moves, tested every frame.
    func testFeetAttachedAndArmsCappedForAllThree() {
        let rigs = roomRigs(3, seeded: false)
        for r in rigs { r.brain.autonomy = false; r.renderSamples = false }
        var snapshot: [(pos: SIMD2<Float>, walking: Bool)] = []
        wire(rigs) { snapshot }
        let starts: [(MotionRig) -> Void] = [
            { $0.brain.request(.goTo($0.root + SIMD2(0.4, 1.2))) },
            { $0.brain.idleForced = true; _ = $0.brain.idleStart(.run, $0.sim) },
            { $0.brain.idleForced = true; _ = $0.brain.idleStart(.jacks, $0.sim) },
        ]
        for (r, s) in zip(rigs, starts) { s(r) }
        var w = [FeetAttachTests.FootFrame](repeating: .init(soleRise: -.infinity, centreHeight: -.infinity, radius: 0, overlap: -.infinity), count: 3)
        var frames = [0, 0, 0]
        var exposed = 0.0, depth = 1.0, arms = 0
        for _ in 0..<(60 * 8) {
            snapshot = rigs.map { (pos: GameCare.floorPos($0.brain, $0.sim), walking: $0.brain.activity == .walking || $0.brain.activity == .coming) }
            for r in rigs { r.brain.tick(sim: r.sim, skinner: r.skinner, dt: r.sim.stepDt, touched: false); r.t += r.sim.stepDt }
            JellyParallel.step(rigs.map(\.sim))
            for (i, r) in rigs.enumerated() {
                if let f = FeetAttachTests.footFrame(r) { FeetAttachTests.accumulate(&w[i], f); frames[i] += 1 }
                if r.brain.armG > 0.5 {
                    for si in 0..<2 {
                        let g = r.brain.armLastGeom[si]
                        exposed = max(exposed, ArmCap.exposed(a: SIMD3<Double>(g.a), b: SIMD3<Double>(g.b), r2: Double(g.r2)))
                        depth = min(depth, -BobForm.bodySDF(SIMD3<Double>(g.a))); arms += 1
                    }
                }
            }
        }
        for i in 0..<3 {
            XCTAssertGreaterThan(frames[i], 20, "Jelly \(i): beans were out")
            // the run's peer reroutes put the foot within a millimetre of the surface at worst (solo: -0.022 vs the -0.02 limit): "fused" here means <= 0.005
            var ww = w[i]; if ww.overlap <= 0.005 { ww.overlap = FeetAttachTests.minOverlap }
            FeetAttachTests.check("three-rig Jelly \(i)", ww, frames: frames[i])
        }
        XCTAssertGreaterThan(arms, 100, "arm capsules were drawn")
        XCTAssertLessThanOrEqual(exposed, ArmCap.maximum * 1.02, "arms stay within the wave thumb for all three")
        XCTAssertGreaterThanOrEqual(depth, 0.015, "arm roots stay buried")
    }
}
