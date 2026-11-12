//
//  EmoteFeetTests.swift
//  One focused test per emote where a foot came off on the phone (r1052, 2026-11-01). Each runs the emote for every character, bare and with shoes, on fresh bodies, and asserts in EVERY frame:
//    leash    the skin's leash / tether never moves a foot piece (the brain placed it inside the body itself);
//    ring     with both pieces off the floor, the piece's ring 2 under the top is >= 70 % of the standing boot's ring;
//    join     with both pieces off the floor, each of the 32 neck meridians has a neck-ring point inside the drawn body by OnePieceInvariantTests.minNeck (1 cm);
//    collar   with both pieces off the floor, the skin collar moves no vertex more than 2 cm (it used to tear into a saw-toothed rim round the leg roots).
//  Failure messages name the emote, the character, shoes, the first bad frame and the cm. The class resets only the statics it touches, so each test passes alone and in any order.
//

import XCTest
import simd
@testable import BobV1

@MainActor
final class EmoteFeetTests: XCTestCase {
    override func setUp() { super.setUp(); Self.reset() }
    override func tearDown() { Self.reset(); super.tearDown() }
    /// Only the statics these tests touch.
    static func reset() {
        BlobBrain.topDepthFix = true; BlobBrain.airTuck = true; OnePieceInvariantTests.guardArmed = true; Skinner.leashObserver = nil; FootBean.neckKeepOn = true; Skinner.collarAirFade = true; Skinner.teleportJump = 1.0
        ToyTuning.settle = 5; DecorField.shared.clear(); DecorField.shared.toys = ToyBook()
        RoomLayout.dynamicBoxes = []; GameCamera.playBlend = 0; RoomLayout.ballSpheres = []
        GameCamera.configureRoom(count: 1); _ = GameCamera.camera(aspect: 440.0 / 956.0)
    }

    static let out = ProcessInfo.processInfo.environment["EMOTEFEET_OUT"] ?? "/private/tmp/claude-501/-Users-dmarshall94-Desktop-BobV1/9cd2e159-911b-4a04-879f-e5e34721a64a/scratchpad/feetsrc/"          // (EMOTEFEET_OUT: a run writes its reports into its own folder)
    static let maxCollar: Float = 0.02, minRatio: Float = 0.7
    static let A = FootBean.around

    static func ringRadius(_ p: [SIMD3<Float>], _ ring: Int) -> Float {
        var c = SIMD3<Float>.zero; for j in 0..<A { c += p[1 + A * ring + j] }; c /= Float(A)
        var m: Float = 0; for j in 0..<A { m += simd_length(p[1 + A * ring + j] - c) }; return m / Float(A)
    }
    static let standing = ringRadius(FootBean.localF, 10)

    struct Sample { var ratio: Float; var join: Float; var collar: Float; var info = "" }

    /// nil unless both pieces are blended in and off the floor.
    static func sample(_ r: MotionRig, frame: Int) -> Sample? {
        guard r.skinner.beansActive, r.skinner.beanBlend > 0.9 else { return nil }
        guard (0..<2).allSatisfy({ k in (r.skinner.beanPos[k].map(\.y).min() ?? 0) - r.sim.floorY > 0.03 }) else { return nil }
        let pose = r.sim.bodyPose(iterations: 4)
        let fp = (centroid: pose.centroid, rotation: pose.rotation, restCentroid: r.sim.restCentroid)
        var ratio = Float.infinity, join = Float.infinity
        r.dyn.withUnsafeBufferPointer { d in
            @inline(__always) func P(_ v: Int) -> SIMD3<Float> { SIMD3(d[6 * v], d[6 * v + 1], d[6 * v + 2]) }
            for k in 0..<2 {
                ratio = min(ratio, ringRadius(r.skinner.beanPos[k], 10) / standing)
                let first = Int(r.bean[k][0])
                for j in 0..<A {
                    var best = -Float.infinity
                    for ring in 10..<FootBean.rings { best = max(best, Skinner.fittedDepth(P(first + 1 + A * ring + j), fp).0) }
                    join = min(join, best)
                }
            }
        }
        var collar: Float = 0
        if frame % 3 == 0 {
            // (Pip's tail is switched off for the two comparison renders: it moves between them, and lying on the back it is next to the feet)
            let tail = r.skinner.tailOn; r.skinner.tailOn = false
            r.render()
            let withCollar = r.dyn
            r.skinner.collarEnabled = false; r.render()
            let without = r.dyn
            r.skinner.collarEnabled = true; r.skinner.tailOn = tail; r.render()
            var i = 0
            // (only skin within 30 cm of a foot piece: Pip's tail moves between two renders and is not the collar)
            let poles = (0..<2).map { r.skinner.beanPos[$0][FootBean.vertexCount - 1] }
            let bodyEnd = 6 * (MotionRig.renderMesh.armCapsule?.firstVertex[0] ?? 0)          // (the body skin only: the appended tail / ears / foot pieces are not what the collar moves)
            while i + 2 < min(withCollar.count, bodyEnd) {
                let p = SIMD3(withCollar[i], withCollar[i + 1], withCollar[i + 2])
                if poles.contains(where: { simd_distance($0, p) < 0.3 }) { collar = max(collar, simd_length(p - SIMD3(without[i], without[i + 1], without[i + 2]))) }
                i += 6
            }
        }
        var lo = Float.infinity; for k in 0..<2 { lo = min(lo, (r.skinner.beanPos[k].map(\.y).min() ?? 0) - r.sim.floorY) }
        return Sample(ratio: ratio, join: join, collar: collar, info: String(format: "clearance %.3f air %@ fade %.2f tilt %.2f phase %@", lo, r.brain.airBothFeet ? "Y" : "n", r.skinner.collarFade, pose.tilt, "\(r.brain.gait.phase)"))
    }

    /// Asserts one case (one move, one character, bare / shoes) and returns its report line.
    @discardableResult
    func check(_ move: String, _ c: Int, _ shoes: Bool, _ air: Int, _ worst: (ratio: Float, join: Float, collar: Float), badFrame: Int, info: String = "", file: StaticString = #filePath, line: UInt = #line) -> String {
        let who = "\(move), \(OnePieceInvariantTests.characters[c].0) \(shoes ? "with shoes" : "bare")"
        let row = String(format: "%@ | %d | %.2f | %.1f | %.1f", who, air, worst.ratio, worst.join * 100, worst.collar * 100)
        if air > 0 {
            XCTAssertGreaterThanOrEqual(worst.ratio, Self.minRatio, "\(who): the neck ring shrank to \(String(format: "%.0f", worst.ratio * 100)) % of standing (first bad frame \(badFrame): \(info))", file: file, line: line)
            XCTAssertGreaterThanOrEqual(worst.join, OnePieceInvariantTests.minNeck, "\(who): the join is open: a meridian's neck ring is \(String(format: "%.1f", -worst.join * 100)) cm outside the body (first bad frame \(badFrame): \(info))", file: file, line: line)
            XCTAssertLessThanOrEqual(worst.collar, Self.maxCollar, "\(who): the collar moved the skin \(String(format: "%.1f", worst.collar * 100)) cm round the leg roots (limit \(Self.maxCollar * 100) cm; first bad frame \(badFrame): \(info))", file: file, line: line)
        }
        return row
    }

    /// Runs one emote (a job of the one-piece list) for the given characters (default all), bare and with shoes; asserts leash, ring, join and collar in every frame.
    @discardableResult
    func emote(_ name: String, _ jobName: String, file: StaticString = #filePath, line: UInt = #line) throws -> Bool {
        _ = OnePieceInvariantTests.configured
        ToyTuning.settle = 0
        GameCamera.configureRoom(count: 3, option: .A, wide: 2); _ = GameCamera.camera(aspect: 603.0 / 1311.0)
        guard let job = OnePieceInvariantTests.jobs().first(where: { $0.name == jobName }) else { XCTFail("no move '\(jobName)' in the one-piece job list", file: file, line: line); return false }
        var anyStarted = false
        var report = String(format: "EMOTE %@ (standing ring-10 radius %.3f m)\nchar shoes | frames | leash frames, max pull (cm) | airborne frames | min ring ratio | worst join depth (cm; need >= 1) | max collar move (cm; need <= 2)\n", name, Self.standing)
        for c in job.chars {
            for shoes in [false, true] {
                var air = 0, badFrame = -1, badInfo = "", leashFrame = -1
                var worst: (ratio: Float, join: Float, collar: Float) = (.infinity, .infinity, 0)
                let a = OnePieceInvariantTests.run(job.sc, char: c, shoes: shoes, pacing: .hz60, seed: 3) { frame, r, f in
                    if leashFrame < 0, f.beans, f.leash > 0.002 || f.weldPull > 0.002 { leashFrame = frame }
                    guard let s = Self.sample(r, frame: frame) else { return }
                    air += 1
                    if (s.ratio < Self.minRatio || s.join < OnePieceInvariantTests.minNeck || s.collar > Self.maxCollar) && badFrame < 0 { badFrame = frame; badInfo = s.info }
                    worst = (min(worst.ratio, s.ratio), min(worst.join, s.join), max(worst.collar, s.collar))
                }
                guard a.started else { continue }
                anyStarted = true
                let who = "\(name), \(OnePieceInvariantTests.characters[c].0) \(shoes ? "with shoes" : "bare")"
                report += String(format: "%@ %@ | %d | %d %.1f | %d | %.2f | %.1f | %.1f\n", OnePieceInvariantTests.characters[c].0, shoes ? "shoes" : "bare", a.frames, a.leashed, a.leashMax * 100, air, worst.ratio, worst.join * 100, worst.collar * 100)
                XCTAssertEqual(a.leashed, 0, "\(who): the skin's leash / tether moved a foot piece in \(a.leashed) frames, first at frame \(leashFrame), max pull \(String(format: "%.1f", a.leashMax * 100)) cm", file: file, line: line)
                if air > 0 {
                    XCTAssertGreaterThanOrEqual(worst.ratio, Self.minRatio, "\(who): the neck ring shrank to \(String(format: "%.0f", worst.ratio * 100)) % of standing (first bad frame \(badFrame): \(badInfo))", file: file, line: line)
                    XCTAssertGreaterThanOrEqual(worst.join, OnePieceInvariantTests.minNeck, "\(who): the join is open: a meridian's neck ring is \(String(format: "%.1f", -worst.join * 100)) cm outside the body (first bad frame \(badFrame): \(badInfo))", file: file, line: line)
                    XCTAssertLessThanOrEqual(worst.collar, Self.maxCollar, "\(who): the collar moved the skin \(String(format: "%.1f", worst.collar * 100)) cm round the leg roots (limit \(Self.maxCollar * 100) cm; first bad frame \(badFrame): \(badInfo))", file: file, line: line)
                }
            }
        }
        try? FileManager.default.createDirectory(atPath: Self.out, withIntermediateDirectories: true)
        try? report.write(toFile: Self.out + "emote_\(name.replacingOccurrences(of: " ", with: "_").replacingOccurrences(of: ":", with: "")).txt", atomically: true, encoding: .utf8)
        if !anyStarted && Self.exempt[jobName] == nil { XCTFail("emote '\(name)' did not start for any character: the test would have passed without checking anything (exempt it in EmoteFeetTests.exempt only with a reason)", file: file, line: line) }
        return anyStarted
    }

    /// Emotes that cannot be started through the rig's own entry point, and why. The ONLY way out of the auto-coverage below: anything else that does not start FAILS the test.
    static let exempt: [String: String] = [
        "idle wander": "IdleKind.wander is never started by idleStart: the walk is the wander (the 'walk' emote covers it)",
        "idle stumble": "IdleKind.stumble is only reached from inside the run (the 'idle run' emote covers it)",
    ]

    /// AUTO-COVERAGE: every emote from the source of truth - every IdleKind (CaseIterable), every Script case, the gait / volley / touch / toy-ride list - runs the feet invariant for all 6 characters, bare and with shoes.
    /// A new IdleKind with no scenario fails (OnePieceInvariantTests.idleTable); a new Script case must be covered or excused there; a gait move must have a scenario. Nothing to update here.
    func testEveryEmoteKeepsItsFeet() throws {
        for k in IdleKind.allCases { XCTAssertNotNil(OnePieceInvariantTests.idleTable[k], "IdleKind.\(k.rawValue) is a new emote with no feet scenario: add it to OnePieceInvariantTests.idleTable, then it is tested here automatically") }
        for n in BlobBrain.scriptKindNames { XCTAssertTrue(OnePieceInvariantTests.scriptCovered[n] != nil || OnePieceInvariantTests.scriptNotRun[n] != nil, "Script.\(n) is a new emote that is neither covered nor excused in OnePieceInvariantTests") }
        for g in OnePieceInvariantTests.gaitNames { XCTAssertNotNil(OnePieceInvariantTests.gaitScenario(g), "gait move \(g) has no scenario") }
        var covered: [String] = []
        for job in OnePieceInvariantTests.jobs() {
            if try emote(job.name, job.name) { covered.append(job.name) }
            else if let why = Self.exempt[job.name] { print("EMOTE EXEMPT \(job.name): \(why)") }
            else { XCTFail("emote '\(job.name)' could not be started in the rig for any character: fix its scenario, or exempt it in EmoteFeetTests.exempt with the reason") }
        }
        print("EMOTES COVERED (\(covered.count)): \(covered.joined(separator: ", "))")
        try? covered.joined(separator: "\n").write(toFile: Self.out + "emotes_covered.txt", atomically: true, encoding: .utf8)
    }

    func testJacks() throws { try emote("jacks", "idle jacks") }
    func testHopPlay() throws { try emote("hopPlay", "hop") }
    func testFlip() throws { try emote("flip", "flip") }
    func testFaceplant() throws { try emote("faceplant", "faceplant") }
    func testFlapHop() throws { try emote("flapHop", "idle flapHop") }          // (the winged characters only: Lavender, Pearl)
    func testSkipHop() throws { try emote("skipHop", "idle skipHop") }
    func testLegSpin() throws { try emote("legSpin", "idle legSpin") }          // (the Jelly Spa exit pool: legSpin, skipHop, bounce, jacks, proudStrut, signatureFlourish)
    func testBounce() throws { try emote("bounce", "idle bounce") }
    func testProudStrut() throws { try emote("proudStrut", "idle proudStrut") }
    func testSuperSpring() throws { try emote("superSpring", "idle superSpring") }          // (the Super spring trick: a deep held crouch, a high launch, a big landing)
    func testCorkscrew() throws { try emote("corkscrew", "idle corkscrew") }          // (the Corkscrew jump: the flip's machinery, a twist about the vertical axis)
    func testOneLegSpin() throws { try emote("oneLegSpin", "idle oneLegSpin") }          // (the One-leg spin: one foot lifted out to the side through a pirouette)
    func testMoonwalk() throws { try emote("moonwalk", "idle moonwalk") }          // (the Moonwalk: feet planted / sliding flat under a gliding root, a walk back)
    func testBackBounce() throws { try emote("backBounce", "idle backBounce") }          // (the Back bounce: on his back, the feet kicking, forced beans)
    func testHeadstand() throws { try emote("headstand", "idle headstand") }          // (the Headstand: on his head, the feet kicking in the air, forced beans)
    func testHula() throws { try emote("hula", "idle hula") }          // (the Hula trick: standing, the base circles over planted feet)
    func testSing() throws { try emote("sing", "idle sing") }          // (the Sing trick: standing, feet planted)
    func testSignatureFlourish() throws { try emote("signatureFlourish", "idle signatureFlourish") }
    func testRunning() throws { try emote("run", "idle run") }          // (not testRun: XCTestCase has a property of that name)
    func testZoomies() throws { try emote("zoomies", "idle zoomies") }
    func testSit() throws { try emote("sit", "idle sit") }
    func testSway() throws { try emote("sway", "idle sway") }
    func testDecorSit() throws { try emote("decorSit", "idle decorSit") }
    func testDecorSlide() throws { try emote("decorSlide", "idle decorSlide") }
    func testDecorHopscotch() throws { try emote("decorHopscotch", "idle decorHopscotch") }

    /// Room <-> park: the body root jumps 5 m; the very next skinned frame has both pieces within the tether bound of the hip (45 cm), with or without a brain tick in between, and a control with the carry-over off proves the test can fail.
    func testSceneTeleportRoomToPark() throws {
        _ = OnePieceInvariantTests.configured
        GameCamera.configureRoom(count: 3, option: .A, wide: 2); _ = GameCamera.camera(aspect: 603.0 / 1311.0)
        var controlWorst: Float = 0
        OnePieceInvariantTests.guardArmed = false; defer { OnePieceInvariantTests.guardArmed = true }          // (the control makes the tether act on purpose)
        Skinner.teleportJump = .infinity
        _ = OnePieceInvariantTests.run(OnePieceInvariantTests.gaitScenario("walk")!, char: 4, shoes: false, pacing: .hz60, seed: 3) { frame, r, f in
            guard controlWorst == 0, f.beans, f.blend > 0.9, frame > 50 else { return }
            let c = r.sim.centroid()
            r.sim.teleport(toXZ: SIMD2(c.x + 3.5, c.z - 3.5)); r.render()
            controlWorst = max(r.skinner.weldDist[0], r.skinner.weldDist[1])
        }
        Skinner.teleportJump = 1.0
        OnePieceInvariantTests.guardArmed = true
        XCTAssertGreaterThan(controlWorst, 0.45, "control: without the carry-over a 5 m jump must leave the pieces behind (pole-to-hip \(controlWorst * 100) cm)")
        for name in ["walk", "hop", "march"] {
            for ch in 0..<OnePieceInvariantTests.characters.count {
                for shoes in [false, true] {
                    var done = false
                    _ = OnePieceInvariantTests.run(OnePieceInvariantTests.gaitScenario(name)!, char: ch, shoes: shoes, pacing: .hz60, seed: 3) { frame, r, f in
                        guard !done, f.beans, f.blend > 0.9, frame > 50 else { return }
                        done = true
                        let c = r.sim.centroid()
                        // exactly what GameCare.rehome does for a scene change (the body is reset onto the floor at the new spot, the brain forgets its script and re-roots)
                        let observer = Skinner.leashObserver; Skinner.leashObserver = nil          // (the frame of the jump itself may need the tether once: it is the net under the carry-over)
                        r.brain.abortScript(r.sim, r.skinner); r.brain.pending = nil; r.brain.idleReset(r.skinner); r.brain.decorIgnore = nil
                        r.sim.teleport(toXZ: SIMD2(c.x + 3.5, c.z - 3.5))
                        r.brain.currentPose(r.sim)
                        r.render()
                        let a = max(r.skinner.weldDist[0], r.skinner.weldDist[1])
                        Skinner.leashObserver = observer          // (every later frame of the emote is guarded: no tether, no leash)
                        r.brain.tick(sim: r.sim, skinner: r.skinner, dt: r.sim.stepDt, touched: false)
                        r.sim.step(); r.brain.refitBeans(r.sim, r.skinner); r.render()
                        let b = max(r.skinner.weldDist[0], r.skinner.weldDist[1])
                        let who = "scene teleport during \(name), \(OnePieceInvariantTests.characters[ch].0) \(shoes ? "with shoes" : "bare")"
                        XCTAssertLessThan(a, 0.45, "\(who): pole-to-hip \(String(format: "%.1f", a * 100)) cm on the next skinned frame (frame \(frame), limit 45 cm)")
                        XCTAssertLessThan(b, 0.45, "\(who): pole-to-hip \(String(format: "%.1f", b * 100)) cm one tick later (frame \(frame), limit 45 cm)")
                    }
                }
            }
        }
    }
}
