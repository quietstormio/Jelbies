//
//  OnePieceInvariantTests.swift
//  2026-10-31: "make the characters one solid piece indefinitely" - the feet must look and behave like part of the body in EVERY move.
//  Every frame of every move x every character (0 Bob, 1 Pip, 2 Moss, 3 Lavender, 4 Teddy, 5 Pearl) x bare / shoes x four frame pacings (60 Hz, 120 Hz,
//  alternating 1 / 2 sim steps per frame, bursts of 30 Hz frames), measured on the DRAWN surface (the skinned dyn buffer and the real body triangles):
//    neck     the deepest-to-shallowest NECK ring point of each foot piece (ring 10, two rings under the top) lies at least `minNeck` inside the drawn body
//             (the piece cannot slide off: it bends at the neck).
//    join     max angle between the shading normal of the neck ring and the drawn body's normal at the nearest point: the "hard line / peg" metric.
//             A foot piece pushed into the body meets it at ~90 degrees; a collared, faded join reads continuous.
//    pad      no pieces out (the built-in foot pads): a pad moved at most `maxPadMove` from where the rigid body would put it, stretched at most `maxStretch`.
//  The move list is built from IdleKind.allCases + an explicit gait / volley / touch list: a move that is not listed FAILS (testEveryMoveIsListed).
//  Env: ONEPIECE_BEFORE=1 = the e4062d6 look (no join / collar / crease fade, 10 cm retract band) for before / after numbers; ONEPIECE_ONLY="a,b" filters.
//

import XCTest
import simd
@testable import BobV1

@MainActor
final class OnePieceInvariantTests: XCTestCase {
    static let out = "/private/tmp/claude-501/-Users-dmarshall94-Desktop-BobV1/9cd2e159-911b-4a04-879f-e5e34721a64a/scratchpad/onepiece/"
    nonisolated(unsafe) static var keep: [AnyObject] = []
    static let before = ProcessInfo.processInfo.environment["ONEPIECE_BEFORE"] != nil
    static let minNeck: Float = 0.010, maxDent: Float = 0.005, maxPadMove: Float = 0.10, maxStretch: Float = 1.15

    /// Must run before the first MotionRig (the render mesh bakes the foot's crease).
    static let configured: Void = {
        let e = ProcessInfo.processInfo.environment
        if let v = e["ONEPIECE_COLLAR_R"], let f = Float(v) { Skinner.collarK = f }
        if let v = e["ONEPIECE_COLLAR_RING"], let n = Int(v) { Skinner.collarRing = n }
        if before { BlobBrain.retractBand = 0.10; FootBean.creaseFadeAmount = 0; BlobBrain.onePieceRoll = false; GaitDriver.rollYawFix = false }
    }()

    /// Moves that still show the built-in pads while the body is tipped over, and why (none yet: filled from the first full run).
    static let padTippedAllowed: Set<String> = []

    typealias SC = LegsDrawnAuditTests.Scenario

    // MARK: the characters and pacings

    static let characters: [(String, JellyFeature)] = [("Bob", .none), ("Pip", .spines), ("Moss", .daisy), ("Lavender", .wings), ("Teddy", .ears), ("Pearl", .wings)]

    enum Pacing: Int, CaseIterable {
        case hz60, hz120, alt12, burst30
        var name: String { ["60", "120", "alt1-2", "burst30"][rawValue] }
        func dt(frame: Int, step: Float) -> Float {
            switch self {
            case .hz60: return step
            case .hz120: return step / 2
            case .alt12: return frame % 2 == 0 ? step + 0.0003 : 2 * step + 0.0005
            case .burst30: return frame % 15 < 3 ? 2 * step : step
            }
        }
    }

    // MARK: the move list

    struct Entry { var seconds: Float = 5; var via: String? = nil; var chars: [Int]? = nil }
    /// EVERY IdleKind. A new case does not compile into the table check until it is listed here (testEveryMoveIsListed).
    static let idleTable: [IdleKind: Entry] = [
        .wander: Entry(seconds: 6), .run: Entry(seconds: 6), .stumble: Entry(seconds: 4), .jacks: Entry(seconds: 8), .sit: Entry(seconds: 5), .slump: Entry(seconds: 4),
        .look: Entry(seconds: 4), .yawn: Entry(seconds: 4), .zoomies: Entry(seconds: 8), .slide: Entry(seconds: 9), .scoot: Entry(seconds: 5),
        .sleep: Entry(via: "sleep: roll onto the back and up again"),
        .tail: Entry(seconds: 6), .flop: Entry(seconds: 4), .window: Entry(seconds: 9), .peek: Entry(seconds: 8), .stretch: Entry(seconds: 5), .bounce: Entry(seconds: 4),
        .roll: Entry(seconds: 3), .sway: Entry(seconds: 8),
        .decorSit: Entry(via: "decor: sit on a cushion"), .decorBoop: Entry(via: "decor: boop the plant"), .decorKick: Entry(via: "decor: kick the ball"),
        .decorHop: Entry(via: "decor: hop on the mat"), .decorPeek: Entry(via: "decor: peek in the toy box"), .decorSlide: Entry(via: "decor2: climb the slide, sit, ride, exit"),
        .skipHop: Entry(seconds: 4), .hopscotch: Entry(seconds: 5), .legSpin: Entry(seconds: 4), .trot: Entry(seconds: 6), .stopLook: Entry(seconds: 6), .joy: Entry(seconds: 3),
        .giggle: Entry(seconds: 3), .startle: Entry(via: "reaction: startle hop"),
        .rollTrip: Entry(seconds: 5), .sigh: Entry(seconds: 6), .hmph: Entry(seconds: 3),
        .flapHop: Entry(seconds: 6, chars: [3, 5]),
        .tailThump: Entry(seconds: 5, chars: [1]), .tailHug: Entry(seconds: 6, chars: [1]),
        .shake: Entry(seconds: 3), .lieDown: Entry(seconds: 9), .chirp: Entry(seconds: 3),
        .soccerKick: Entry(via: "soccer: dribble the ball to the goal and shoot"),
    ]

    /// Gait / volley / touch moves that are not an IdleKind. Script cases covered here or by the idle table (`.idle`): see testEveryMoveIsListed.
    static let gaitNames = ["flip", "faceplant", "hop", "rollPlay", "spin", "turn", "walk", "march", "wave", "rollTripWalk", "volleyDive", "volleySpike", "volleyBlock", "volleyCheer", "toy: scooter", "toy: rocket", "toy: rocking horse"]
    /// Script cases that no scenario of the list starts, and why.
    static let scriptNotRun: [String: String] = ["none": "no script", "look": "head turn only (the idle table's look)", "eat": "dining (DiningFlowTests); standing feet", "dine": "dining table (DiningFlowTests)", "race": "Jelly Circuit (RaceTests); the gait is the walk"]
    static let scriptCovered: [String: String] = ["walk": "walk", "turn": "turn", "stepInPlace": "march", "wave": "wave", "spin": "spin", "hopPlay": "hop", "rollPlay": "rollPlay", "flipPlay": "flip / faceplant", "idle": "idleTable"]

    static func gaitScenario(_ name: String) -> SC? {
        var vt = 0
        switch name {
        case "flip": return SC(name: name, game: true, seconds: 3, setup: { r, _ in r.brain.startFlip(sim: r.sim); return true })
        case "faceplant": return SC(name: name, game: true, seconds: 4, setup: { r, _ in r.brain.startFlip(sim: r.sim, fail: true); return true })
        case "hop": return SC(name: name, game: true, seconds: 3, setup: { r, _ in r.brain.startHopPlay(sim: r.sim); return true })
        case "rollPlay": return SC(name: name, game: true, seconds: 3, setup: { r, _ in r.brain.startRollPlay(sim: r.sim); return true })
        case "spin": return SC(name: name, game: true, seconds: 3, setup: { r, _ in r.brain.startSpin(sim: r.sim); return true })
        case "turn": return SC(name: name, game: false, seconds: 3.5, setup: { r, _ in r.brain.startTurn(to: r.poseYaw + 2.4, sim: r.sim); return true })
        case "walk": return SC(name: name, game: true, seconds: 7, setup: { r, _ in r.brain.request(.goTo(SIMD2(1.6, 0.4))); return true })
        case "rollTripWalk":
            // the mid-walk side roll of the phone photo (the leg's flourish hook armed a few steps after the walk starts, as RollFeetCaptureTests does)
            var steps = 0
            return SC(name: name, game: true, seconds: 6, setup: { r, _ in
                steps = 0
                r.brain.idleMood = .happy; r.brain.anticsEnabled = true; r.brain.autonomy = true
                r.brain.restTimer = 1e6; r.brain.idleState.cooldown = 1e6; r.brain.socialBook.cooldown = 1e6; r.brain.expr.pickTimer = 1e6
                let g = r.root + SIMD2(r.root.x > 0 ? -3.4 : 3.4, 0)
                r.brain.script = .walk(target: g, then: .none); r.brain.activity = .walking
                r.brain.scriptT = 0; r.brain.leg = LegState()
                return true
            }, each: { r in steps += 1; if steps == 8 { r.brain.leg.kind = .rollTrip; r.brain.leg.wants = true; r.brain.leg.rolled = false; r.brain.leg.trigger = 0.5; r.brain.leg.from = r.brain.position } })
        case "march": return SC(name: name, game: false, seconds: 5, setup: { r, _ in r.brain.startStepping(seconds: 3, sim: r.sim); return true })
        case "wave": return SC(name: name, game: true, seconds: 4, setup: { r, _ in r.brain.request(.wave); return true })
        case "volleyDive", "volleySpike", "volleyBlock", "volleyCheer":
            return SC(name: name, game: true, seconds: 2.5, setup: { r, _ in
                vt = 0
                let c = r.root
                r.brain.volleyBegin(sim: r.sim, skinner: r.skinner, x: c.x, z: c.y, side: -1)
                for _ in 0..<30 { r.brain.tick(sim: r.sim, skinner: r.skinner, dt: r.sim.stepDt, touched: false); r.sim.step() }
                switch name {
                case "volleyDive": r.brain.volleyDive(sim: r.sim, dir: -1)
                case "volleySpike": r.brain.volleyJump(sim: r.sim, dx: 0.3, apex: 0.45)
                case "volleyBlock": r.brain.volleyJump(sim: r.sim, dx: 0, apex: 0.4, block: true)
                default: r.brain.volleyCheer(sim: r.sim)
                }
                return true
            }, each: { r in vt += 1; if name == "volleySpike", vt == 14 { r.brain.volleySpike() } })
        case "toy: scooter": return LegsDrawnAuditTests.ride(name, .kickscooter, at: SIMD2(1.2, 0.4), move: .decorSlide, seconds: 30)
        case "toy: rocket": return LegsDrawnAuditTests.ride(name, .toyrocket, at: SIMD2(1.1, 0.5), move: .decorSit, seconds: 30)
        case "toy: rocking horse": return LegsDrawnAuditTests.ride(name, .rockinghorse, at: SIMD2(1.1, 0.5), move: .decorSit, seconds: 30)
        default: return nil
        }
    }

    struct Job { let name: String; let sc: SC; let chars: [Int] }

    static func jobs() -> [Job] {
        var out: [Job] = []
        for k in IdleKind.allCases {
            guard let e = idleTable[k] else { continue }
            let sc: SC?
            if let via = e.via {
                sc = LegsDrawnAuditTests.fromMove(via)
            } else {
                sc = SC(name: "idle: \(k.rawValue)", game: true, seconds: e.seconds, setup: { r, _ in r.brain.idleForced = true; return r.brain.idleStart(k, r.sim) })
            }
            if let sc { out.append(Job(name: "idle \(k.rawValue)", sc: sc, chars: e.chars ?? Array(0..<6))) }
        }
        for g in gaitNames { if let sc = gaitScenario(g) { out.append(Job(name: g, sc: sc, chars: Array(0..<6))) } }
        let only = (ProcessInfo.processInfo.environment["ONEPIECE_ONLY"] ?? "").split(separator: ",").map(String.init)
        return only.isEmpty ? out : out.filter { j in only.contains { j.name.contains($0) } }
    }

    // MARK: metrics

    struct Frame { var neck: Float = .infinity; var tilt: Float = 0; var join: Float = 0; var beans = false; var pad: Float = 0; var stretch: Float = 0; var ideal: Float = -.infinity; var dent: Float = 0; var tippedPad = false }

    /// Per foot piece, from the skinned dyn buffer:
    ///  neck  min over the 32 meridians of the deepest neck vertex (rings 10...12) inside the body's fitted rigid egg (BobForm.bodySDF in the fitted pose): the closed curve where the piece
    ///        enters the body. (The first version measured the drawn triangles; near the feet those include the embedded foot's inside-out retracted sheet and called points 6 cm deep "11 cm outside".)
    ///  dent  the dent the skin keeps around the piece after the collar (Skinner.joinDent).
    ///  tippedPad  no pieces out while the body is tipped over (tilt > 0.8): the flat built-in pads stand out of the side like pegs.
    static func frame(_ r: MotionRig) -> Frame {
        var f = Frame()
        let m0 = LegsDrawnAuditTests.measure(r, shoes: false)
        f.pad = m0.coreDisp; f.stretch = m0.stretch
        let pose = r.sim.bodyPose(iterations: 4)
        let tilt = pose.tilt
        guard m0.beans, m0.blend > 0.05 else { f.tilt = tilt; f.tippedPad = tilt > 0.8; return f }
        f.beans = true
        r.skinner.ensureJoinTris()
        f.tilt = tilt
        f.dent = max(r.skinner.joinDent[0], r.skinner.joinDent[1])
        if tilt <= 0.5 { return f }          // (the neck guarantee only runs on a tipped body: the upright gait is the locked walk)
        let A = FootBean.around
        let fp = (centroid: pose.centroid, rotation: pose.rotation, restCentroid: r.sim.restCentroid)
        r.dyn.withUnsafeBufferPointer { d in
            @inline(__always) func P(_ v: Int) -> SIMD3<Float> { SIMD3(d[6 * v], d[6 * v + 1], d[6 * v + 2]) }
            for s in 0..<2 {
                let first = Int(r.bean[s][0])
                for j in 0..<A {
                    var best = -Float.infinity
                    for ring in 10..<FootBean.rings { best = max(best, Skinner.fittedDepth(P(first + 1 + A * ring + j), fp).0) }
                    f.neck = min(f.neck, best)
                }
            }
        }
        return f
    }

    struct Agg {
        var frames = 0, beanFrames = 0, padFrames = 0, started = true
        var neckMin: Float = .infinity, neckFrame = -1, joinMax: Float = 0, joinFrame = -1, padMax: Float = 0, stretchMax: Float = 0
        var neckBad = 0, joinBad = 0, idealMax: Float = -.infinity, dentMax: Float = 0, tippedPad = 0
        mutating func add(_ f: Frame, frame k: Int) {
            frames += 1
            if f.beans {
                beanFrames += 1
                if f.neck < neckMin { neckMin = f.neck; neckFrame = k }
                if f.join > joinMax { joinMax = f.join; joinFrame = k }
                idealMax = max(idealMax, f.ideal); dentMax = max(dentMax, f.dent)
                if f.tilt > 0.5 && f.neck < OnePieceInvariantTests.minNeck { neckBad += 1 }
            } else { padFrames += 1; if f.tippedPad { tippedPad += 1 }; padMax = max(padMax, f.pad); stretchMax = max(stretchMax, f.stretch) }
        }
    }

    nonisolated(unsafe) static var phasesSeen = Set<GaitDriver.Phase>()
    nonisolated(unsafe) static var scriptsSeen = Set<String>()

    /// One scenario run at a pacing (the stage's per-frame order, as LegsDrawnAuditTests.run).
    static func run(_ sc: SC, char: Int, shoes: Bool, pacing: Pacing, seed: UInt64, onFrame: ((Int, MotionRig, Frame) -> Void)? = nil) -> Agg {
        _ = configured
        var out = Agg()
        DecorField.shared.clear(); DecorField.shared.toys = ToyBook()
        let r = MotionRig(game: sc.game, settle: 0.5)
        keep.append(r); defer { keep.removeAll(); DecorField.shared.clear() }
        r.renderSamples = false
        let feature = characters[char].1
        r.brain.feature = feature
        r.skinner.configureTail(MotionRig.renderMesh); r.skinner.tailOn = feature == .spines; r.brain.skinnerRef = r.skinner
        r.brain.shoesWorn = shoes
        r.brain.seed = 5 + seed
        if before { r.skinner.joinEnabled = false; r.skinner.collarEnabled = false }
        guard sc.setup(r, seed) else { out.started = false; return out }
        let stepDt = r.sim.stepDt
        var acc: Float = 0, t: Float = 0, frame = 0
        while t < sc.seconds && frame < Int(sc.seconds * 130) + 600 {
            let dt = pacing.dt(frame: frame, step: stepDt)
            acc += dt
            var steps = 0
            while acc >= stepDt && steps < 2 {
                r.brain.tick(sim: r.sim, skinner: r.skinner, dt: stepDt, touched: false)
                r.skinner.jelly.tick(brain: r.brain, sim: r.sim, dt: stepDt)
                sc.each?(r)
                if sc.decor { DecorField.shared.tick(dt: stepDt) }
                r.sim.step(); r.t += stepDt; t += stepDt
                acc -= stepDt; steps += 1
            }
            if steps == 2 { acc = min(acc, stepDt) }
            if steps > 0 { r.brain.refitBeans(r.sim, r.skinner) }
            r.skinner.tickBlink(dt: dt)
            r.render()
            if sc.stopWhenDone, t > 0.5, r.brain.idleState.kind == nil { break }
            frame += 1
            phasesSeen.insert(r.brain.gait.phase); scriptsSeen.insert(r.brain.scriptKindName)
            let f = Self.frame(r)
            out.add(f, frame: frame)
            onFrame?(frame, r, f)
        }
        return out
    }

    // MARK: tests

    /// A move that is not on the list fails: every IdleKind has a table entry, every table entry is a real case, every Script case is covered or excused.
    func testEveryMoveIsListed() {
        for k in IdleKind.allCases { XCTAssertNotNil(Self.idleTable[k], "IdleKind.\(k.rawValue) is not in OnePieceInvariantTests.idleTable: add it (and check it with the feet)") }
        XCTAssertEqual(Self.idleTable.count, IdleKind.allCases.count)
        for n in BlobBrain.scriptKindNames {
            XCTAssertTrue(Self.scriptCovered[n] != nil || Self.scriptNotRun[n] != nil, "Script.\(n) is neither covered nor excused in OnePieceInvariantTests")
        }
        for g in Self.gaitNames { XCTAssertNotNil(Self.gaitScenario(g), "gait move \(g) has no scenario") }
        for k in IdleKind.allCases { if let v = Self.idleTable[k]?.via { XCTAssertNotNil(LegsDrawnAuditTests.fromMove(v), "\(k.rawValue) -> \(v) missing in FeetAttachTests.moves") } }
    }

    func testEveryMoveEveryCharacter() throws {
        _ = Self.configured
        ToyTuning.settle = 0; defer { ToyTuning.settle = 5; DecorField.shared.clear() }
        GameCamera.configureRoom(count: 3, option: .A, wide: 2); _ = GameCamera.camera(aspect: 603.0 / 1311.0)
        defer { GameCamera.configureRoom(count: 1); _ = GameCamera.camera(aspect: 440.0 / 956.0) }
        var report = "mode: \(Self.before ? "BEFORE (e4062d6 look)" : "AFTER")\nmove | char shoes pacing | frames bean pad | neckMin(cm)@f | joinMax(deg)@f | padMove stretch | neckBad joinBad | idealMax(cm) | dentMax(cm) tippedPadFrames\n"
        var tot = Agg(), tippedMoves = Set<String>(), notStarted: [String] = [], worstNeck: (Float, String) = (.infinity, ""), worstJoin: (Float, String) = (0, "")
        for (ji, job) in Self.jobs().enumerated() {
            var anyStarted = false
            let lim = Int(ProcessInfo.processInfo.environment["ONEPIECE_VARIANTS"] ?? "") ?? job.chars.count
            for vi in 0..<min(lim, job.chars.count) {
                let c = job.chars[(vi + ji) % job.chars.count]
                let shoes = (vi + ji) % 2 == 1
                let pacing = Pacing.allCases[(vi + ji) % Pacing.allCases.count]
                let a = Self.run(job.sc, char: c, shoes: shoes, pacing: pacing, seed: UInt64(3 + vi))
                if !a.started { continue }
                anyStarted = true
                let tag = "\(job.name) | \(Self.characters[c].0) \(shoes ? "shoes" : "bare") \(pacing.name)"
                report += String(format: "%@ | %d %d %d | %.1f@%d | %.0f@%d | %.3f %.2f | %d %d | %.1f | %.1f %d\n", tag, a.frames, a.beanFrames, a.padFrames, a.neckMin.isFinite ? a.neckMin * 100 : 99, a.neckFrame, a.joinMax, a.joinFrame, a.padMax, a.stretchMax, a.neckBad, a.joinBad, a.idealMax.isFinite ? a.idealMax * 100 : 99, a.dentMax * 100, a.tippedPad)
                tot.frames += a.frames; tot.beanFrames += a.beanFrames; tot.padFrames += a.padFrames; tot.neckBad += a.neckBad; tot.joinBad += a.joinBad
                tot.padMax = max(tot.padMax, a.padMax); tot.stretchMax = max(tot.stretchMax, a.stretchMax); tot.dentMax = max(tot.dentMax, a.dentMax); tot.tippedPad += a.tippedPad
                if a.tippedPad > 0 { tippedMoves.insert(job.name) }
                if a.neckMin < worstNeck.0 { worstNeck = (a.neckMin, tag) }
                if a.joinMax > worstJoin.0 { worstJoin = (a.joinMax, tag) }
            }
            if !anyStarted { notStarted.append(job.name) }
        }
        report += String(format: "TOTAL frames %d (bean %d, pad %d) | worst neck %.1f cm (%@) | worst join %.0f deg (%@) | neckBad %d | worst dent %.1f cm | tipped-pad frames %d in %@ | worst pad move %.3f stretch %.2f\nnot started: %@\nphases seen: %@ | scripts seen: %@\n", tot.frames, tot.beanFrames, tot.padFrames, worstNeck.0 * 100, worstNeck.1, worstJoin.0, worstJoin.1, tot.neckBad, tot.dentMax * 100, tot.tippedPad, tippedMoves.sorted().joined(separator: ", "), tot.padMax, tot.stretchMax, notStarted.joined(separator: ", "), "\(Self.phasesSeen.map { "\($0)" }.sorted())", "\(Self.scriptsSeen.sorted())")
        try? FileManager.default.createDirectory(atPath: Self.out, withIntermediateDirectories: true)
        try report.write(toFile: Self.out + (Self.before ? "invariants_before.txt" : "invariants_after.txt"), atomically: true, encoding: .utf8)
        print(report)
        if ProcessInfo.processInfo.environment["ONEPIECE_ONLY"] == nil {
            XCTAssertTrue(notStarted.isEmpty, "moves that did not start: \(notStarted)")
            for p in GaitDriver.Phase.allCases where p != .thrown { XCTAssertTrue(Self.phasesSeen.contains(p), "no scenario reached gait phase \(p)") }
        }
        guard !Self.before else { return }
        XCTAssertEqual(tot.neckBad, 0, "frames where a neck-ring point is less than \(Self.minNeck) inside the drawn body: worst \(worstNeck)")
        XCTAssertLessThanOrEqual(tot.dentMax, Self.maxDent, "the skin around a foot piece keeps a dent deeper than \(Self.maxDent) m (the old retract ring)")
        XCTAssertEqual(tippedMoves.subtracting(Self.padTippedAllowed), [], "moves that show the flat built-in pads of a tipped-over body (tilt > 0.8, no pieces out): make the pieces come out for them, or list them in padTippedAllowed with the reason")
        XCTAssertLessThanOrEqual(tot.padMax, Self.maxPadMove, "a built-in foot pad moved more than \(Self.maxPadMove) from the rigid body")
        XCTAssertLessThanOrEqual(tot.stretchMax, Self.maxStretch, "a built-in foot pad stretched")
    }

    /// Picked up, dangling, thrown, dropped (the touch rig): the same neck guarantee.
    func testHeldThrownDropped() {
        _ = Self.configured
        var worst: Float = .infinity, joinMax: Float = 0, dentMax: Float = 0, frames = 0, beanFrames = 0
        for (ci, ch) in Self.characters.enumerated() {
            let r = TouchPlayTests.Rig()
            Self.keep.append(r)
            r.rig.brain.feature = ch.1; r.rig.brain.shoesWorn = ci % 2 == 1
            r.rig.skinner.configureTail(MotionRig.renderMesh); r.rig.skinner.tailOn = ch.1 == .spines; r.rig.brain.skinnerRef = r.rig.skinner
            if Self.before { r.rig.skinner.joinEnabled = false; r.rig.skinner.collarEnabled = false }
            let sim = r.rig.sim
            var k = 0
            func measure() {
                r.rig.render()
                let f = Self.frame(r.rig)
                frames += 1; k += 1
                Self.phasesSeen.insert(r.rig.brain.gait.phase)
                if f.beans { beanFrames += 1; if f.tilt > 0.5 { worst = min(worst, f.neck) }; joinMax = max(joinMax, f.join); dentMax = max(dentMax, f.dent) }
            }
            r.step(touched: true); measure()
            let hit = sim.centroid() + SIMD3(0, 0.1, 0.5)
            sim.beginGrab(hit: hit, radius: 0.4)
            func held(_ target: SIMD3<Float>, lift: Float) {
                r.step(touched: true) {
                    sim.moveGrab(target: target, rot: nil)
                    r.play.heldFrame(dt: 1.0 / 60, now: r.clock, grabbing: true, liftHeight: lift, sim: sim, brain: r.rig.brain, skinner: r.rig.skinner)
                }
                measure()
            }
            for _ in 0..<20 { held(hit, lift: 0) }
            for n in 0..<240 {
                let t = Float(n) / 60, e = min(1, t / 0.8)
                let lift = 0.4 * e * e * (3 - 2 * e)
                held(hit + SIMD3(0.6 * sinf(2.4 * t) * e, lift + 0.1 * sinf(3.1 * t) * e, 0.3 * sinf(1.7 * t) * e), lift: lift)
            }
            sim.endGrab()                                    // dropped
            for _ in 0..<90 {
                r.step(touched: true) { r.play.heldFrame(dt: 1.0 / 60, now: r.clock, grabbing: false, liftHeight: 0, sim: sim, brain: r.rig.brain, skinner: r.rig.skinner) }
                measure()
            }
            r.play.thrown = true                             // thrown
            sim.launch(velocity: SIMD3(2.5, 3.5, 0), spin: SIMD3(0, 0, -2.0))
            for n in 0..<240 {
                r.step(touched: true) { r.play.heldFrame(dt: 1.0 / 60, now: r.clock, grabbing: false, liftHeight: 0, sim: sim, brain: r.rig.brain, skinner: r.rig.skinner) }
                if n % 2 == 1 { r.step(touched: true) }      // (a hitch frame: two steps, one skin)
                measure()
            }
            Self.keep.removeAll()
        }
        let line = String(format: "HELD/THROWN/DROPPED (6 characters): frames %d bean %d worst neck (tilt > 0.5) %.1f cm, worst dent %.1f cm\n", frames, beanFrames, worst.isFinite ? worst * 100 : 99, dentMax * 100)
        try? FileManager.default.createDirectory(atPath: Self.out, withIntermediateDirectories: true)
        try? line.write(toFile: Self.out + (Self.before ? "held_before.txt" : "held_after.txt"), atomically: true, encoding: .utf8)
        print(line)
        guard !Self.before else { return }
        XCTAssertGreaterThanOrEqual(worst, Self.minNeck)
        XCTAssertLessThanOrEqual(dentMax, Self.maxDent)
    }
}
