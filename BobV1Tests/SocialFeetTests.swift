//
//  SocialFeetTests.swift
//  The feet invariant for every TOUCHING social stance (2026-11-04, g-contactfeet), now that the contact engine (contactNudge / ContactSettle / the stance hold) moves bodies, steps, soles and the sim body during a session.
//  EmoteFeetTests covers solo emotes in isolation and never covered socials. One test method per stance (run alone with -only-testing); each runs two casts:
//    Pip+Bob(+Moss)        a tail (Pip) in the cast
//    Pearl+Teddy(+Lavender) the winged species and Teddy
//  Rig and Lab setup are ContactPolishTests' (Duo with the live contact engine, rig 0 starts the social with rig 1 from 2.9 u apart, lie / sleep scenarios as there).
//  Measured EVERY frame on EVERY rig, with the metrics and thresholds of the existing suites (nothing new is invented):
//    leash     (EmoteFeetTests)   Skinner.leashObserver: the skin's leash / tether never moves a foot piece                                              == 0 frames
//    ring      (EmoteFeetTests)   both pieces off the floor: ring 2 under the top >= 70 % of the standing boot                                              EmoteFeetTests.minRatio
//    join      (EmoteFeetTests)   both pieces off the floor: every neck meridian inside the drawn body                                                       OnePieceInvariantTests.minNeck (1 cm)
//    collar    (EmoteFeetTests)   both pieces off the floor: the collar moves no skin vertex more than                                                       EmoteFeetTests.maxCollar (2 cm)
//    attach    (FeetAttachTests via SocialTests.Watch)  gap = deepest foot vertex vs the fitted egg (overlap <= -0.02), float = body-frame sole rise (<= 0.12) and foot-centre height, radius;
//                                                       social-overlay frames strict, plain walk frames the Watch's relaxed bound (0.03 as GroupEmoteFeetTests)
//  plus ONE new metric, SOLE SKATING: while a foot is planted (the locomotion code's notion: feetDrive on, the foot not the swing foot of `feet` (FootGait.swinging / side), the drawn sole within
//  1.2 cm of the floor, not airborne) the horizontal drift of the drawn sole (mean xz of the bean's lowest vertices) from where the planted phase began, mm. Worst over every phase is reported.
//  No skating threshold exists in EmoteFeetTests or the locomotion code (only the comment "a planted foot must not skate"), so it is LOGGED, not asserted.
//  Results go to SOCIALFEET_OUT (default: /private/tmp/socialfeet/) socialfeet.tsv and to the test log as "SOCIALFEET ...".
//

import XCTest
import simd
@testable import BobV1

@MainActor
final class SocialFeetTests: XCTestCase {
    typealias Duo = FeatureClipTests.Duo

    static let outDir: String = { let d = ProcessInfo.processInfo.environment["SOCIALFEET_OUT"] ?? ""; return d.isEmpty ? "/private/tmp/socialfeet/" : d + "/" }()
    nonisolated(unsafe) static var keep: [AnyObject] = []
    /// 0 Bob, 1 Pip, 2 Moss, 3 Lavender, 4 Teddy, 5 Pearl.
    static let pairCasts: [(String, [Int])] = [("Pip+Bob", [1, 0]), ("Pearl+Teddy", [5, 4])]
    static let trioCasts: [(String, [Int])] = [("Pip+Bob+Moss", [1, 0, 2]), ("Pearl+Teddy+Lavender", [5, 4, 3])]
    static let planted: Float = 0.012          // (m) a sole this close to the floor, on a foot the gait holds, is planted

    override func setUp() {
        super.setUp()
        EmoteFeetTests.reset()
        RoomLayout.dynamicBoxes = []; SocialTuning.pickChance = 0.12
        GameCamera.configureRoom(count: 3, option: .A, wide: 2); _ = GameCamera.camera(aspect: 440 / 956)
        FeatureClip.enabled = true; LieClearTuning.enabled = true
    }
    override func tearDown() {
        Skinner.leashObserver = nil
        FeatureClip.enabled = true; FeatureClip.eggs = []; ContactField.reset(); ContactField.enabled = true
        DecorField.shared.clear(); DecorField.shared.toys = ToyBook()
        EmoteFeetTests.reset()
        super.tearDown()
    }

    struct Skate { var worst: Float = 0, frame = -1, rig = -1, foot = -1, tag = "", phases = 0, over5 = 0 }
    struct Result {
        var name = "", cast = "", started = false, completed = false, frames = 0, seconds: Float = 0
        var leash = 0, leashFirst = -1, leashPull: Float = 0
        var airSess = 0, joinSess: Float = .infinity, collarSess: Float = 0, joinWalk: Float = .infinity, collarWalk: Float = 0, badSess = ""
        var air = 0, ratio: Float = .infinity, join: Float = .infinity, collar: Float = 0, bad = ""
        var skate = Skate()          // (in-session planted phases only)
        var skateWalk: Float = 0          // (worst drift of the planted phases outside the session: the walk-up and the walk away)
        var plantedFrames = 0, plantedInSession = 0
        var plantedFloat: Float = 0            // (m) highest planted sole clearance seen
        var overlap: Float = -.infinity, soleRise: Float = -.infinity, centre: Float = -.infinity, radius: Float = 0, overlapTag = ""
    }

    func makeDuo(cast: [Int], positions: [SIMD2<Float>]) -> Duo {
        let d = Duo(positions: positions, features: cast.map { OnePieceInvariantTests.characters[$0].1 }, seed: 31, quiet: true)
        for r in d.lab.rigs { r.brain.anticsEnabled = true; r.brain.sleepEnabled = true }
        d.live = ProcessInfo.processInfo.environment["SOCIALFEET_ENGINE"] != "0"          // (the contact engine as in the app: a profile every tick; SOCIALFEET_ENGINE=0 = the baseline without profiles)
        return d
    }

    enum Scenario { case social(SocialKind), lie(IdleKind), sleepPair }

    /// Runs one stance for one cast to its end, every frame measured on every rig. Returns the result; asserts the existing thresholds.
    @discardableResult
    func run(_ name: String, _ sc: Scenario, cast: [Int], castName: String, maxSec: Float = 70, file: StaticString = #filePath, line: UInt = #line) -> Result {
        _ = OnePieceInvariantTests.configured
        DecorField.shared.clear(); DecorField.shared.toys = ToyBook()
        let n = cast.count
        var res = Result(); res.name = name; res.cast = castName
        var positions = Array(ContactPolishTests.farStarts.prefix(n))
        if case .lie = sc { positions = [SIMD2(-1.5, 0.6), SIMD2(1.5, 0.6)] }
        let d = makeDuo(cast: cast, positions: positions)
        Self.keep.append(d)
        let rigs = d.lab.rigs
        let a = rigs[0], b = rigs[1]
        var frame = 0
        // (the live skin runs on concurrentPerform threads: the observer can fire off the main thread, so the counters sit behind a lock; the count is inflated, a render in the same frame can report the same leash again)
        let lock = NSLock(); nonisolated(unsafe) var lc = 0, lf = -1, lp: Float = 0; nonisolated(unsafe) var curFrame = 0
        Skinner.leashObserver = { _, pull, _ in lock.lock(); lc += 1; if lf < 0 { lf = curFrame }; lp = max(lp, pull); lock.unlock() }
        defer { Skinner.leashObserver = nil }
        var ok = false
        switch sc {
        case .social(let k): ok = a.brain.socialStart(k, with: b.brain, a.sim)
        case .lie(let k):
            d.place([SIMD2(-0.8, 0.6), SIMD2(0.8, 0.6)])
            for r in rigs { r.brain.idleForced = true }
            ok = a.brain.idleStart(k, a.sim) && b.brain.idleStart(k, b.sim)
        case .sleepPair:
            d.place([SIMD2(-0.4, 0.8), SIMD2(1.0, 0.8)])
            for r in rigs { r.brain.idleForced = true }
            ok = a.brain.idleStart(.sleep, a.sim)
            if ok { a.brain.sleep.hold = 600 }
        }
        res.started = ok
        let who = "\(name) [\(castName)]"
        XCTAssertTrue(ok, "\(who): starts", file: file, line: line)
        guard ok else { return res }
        var secondSleeper = false
        // sole skating: per rig, per foot, the planted phase's start xz
        var start: [[SIMD2<Float>?]] = Array(repeating: [nil, nil], count: n)
        var drift: [[Float]] = Array(repeating: [0, 0], count: n)
        var startSess: [[Bool]] = Array(repeating: [false, false], count: n), run: [[Int]] = Array(repeating: [0, 0], count: n)
        func endPhase(_ i: Int, _ s: Int) {
            guard start[i][s] != nil else { return }
            if startSess[i][s] { res.skate.phases += 1; if drift[i][s] > 0.005 { res.skate.over5 += 1 } }
            start[i][s] = nil; drift[i][s] = 0
        }
        let maxF = Int(maxSec * 60)
        let tracing = ProcessInfo.processInfo.environment["SOCIALFEET_TRACE"] == name
        var trace: [String] = []
        while frame < maxF {
            curFrame = frame
            d.tick()
            if case .sleepPair = sc, !secondSleeper, a.brain.isNapping {
                secondSleeper = true
                d.lab.snapshot = rigs.map { (pos: GameCare.floorPos($0.brain, $0.sim), walking: false) }
                _ = b.brain.idleStart(.sleep, b.sim); b.brain.sleep.hold = 600
            }
            for (i, r) in rigs.enumerated() {
                // EmoteFeetTests' own sample (ring / join / collar), with its gates
                if let s = EmoteFeetTests.sample(r, frame: frame) {
                    res.air += 1
                    if res.bad.isEmpty, s.ratio < EmoteFeetTests.minRatio || s.join < OnePieceInvariantTests.minNeck || s.collar > EmoteFeetTests.maxCollar { res.bad = "rig \(i) frame \(frame) social \(r.brain.socialKind?.rawValue ?? "-")/ph\(r.brain.social?.phase ?? -1): ratio \(s.ratio) join \(s.join * 100) cm collar \(s.collar * 100) cm (\(s.info))" }
                    res.ratio = min(res.ratio, s.ratio); res.join = min(res.join, s.join); res.collar = max(res.collar, s.collar)
                    let inSess: Bool = { if case .social = sc { return (r.brain.social?.phase ?? 0) >= 1 }; return frame > 60 }()
                    if inSess { res.airSess += 1; res.joinSess = min(res.joinSess, s.join); res.collarSess = max(res.collarSess, s.collar)
                        if res.badSess.isEmpty, s.ratio < EmoteFeetTests.minRatio || s.join < OnePieceInvariantTests.minNeck || s.collar > EmoteFeetTests.maxCollar { res.badSess = "rig \(i) frame \(frame) social \(r.brain.socialKind?.rawValue ?? "-")/ph\(r.brain.social?.phase ?? -1) act \(r.brain.activity): join \(s.join * 100) cm collar \(s.collar * 100) cm (\(s.info))" }
                    } else { res.joinWalk = min(res.joinWalk, s.join); res.collarWalk = max(res.collarWalk, s.collar) }
                }
                d.lab.watch[i].sample(r)
                // sole skating
                let sk = r.skinner
                if !(sk.beansActive && sk.beanBlend > 0.05) { r.render() }          // (the Watch's footFrame rendered r.dyn already while the beans are out)
                for s in 0..<2 {
                    var isPlanted = false
                    var xz = SIMD2<Float>.zero
                    // the locomotion code's notion: the feet follow world targets (feetDrive, feetInit) and this is not the swing foot of the FootGait; plus the drawn sole on the floor, not airborne
                    if r.brain.feetDrive, r.brain.feetInit, !r.brain.airBothFeet, !(r.brain.feet.swinging && r.brain.feet.side == s) {
                        let clr = r.renderedFootGap(s)
                        if clr < Self.planted { xz = r.renderedFootXZ(s); isPlanted = true; res.plantedFloat = max(res.plantedFloat, clr); res.plantedFrames += 1; if r.brain.social?.phase ?? 0 >= 1 { res.plantedInSession += 1 } }
                    }
                    if tracing, i == 0 { trace.append(String(format: "%d\tfoot%d\tplanted %d\txz %.3f %.3f\tclr %.3f\tph %d\tact %@\tfeetActive %d swinging %d side %d stepLive %d beans %d\troot %.3f %.3f", frame, s, isPlanted ? 1 : 0, r.renderedFootXZ(s).x, r.renderedFootXZ(s).y, r.renderedFootGap(s), r.brain.social?.phase ?? -1, "\(r.brain.activity)", r.brain.feet.active ? 1 : 0, r.brain.feet.swinging ? 1 : 0, r.brain.feet.side, r.brain.stepLive ? 1 : 0, sk.beansActive ? 1 : 0, r.root.x, r.root.y)) }
                    if isPlanted {
                        let sessNow: Bool = { if case .social = sc { return (r.brain.social?.phase ?? 0) >= 1 }; return frame > 60 }()
                        if start[i][s] != nil, startSess[i][s] != sessNow { endPhase(i, s) }          // (a phase never spans the walk-up and the session)
                        run[i][s] += 1
                        if run[i][s] == 4 { start[i][s] = xz; startSess[i][s] = sessNow }          // (the first 3 planted frames are the foot landing: the drawn sole trails the brain's by a frame)
                        else if let st = start[i][s] {
                            let dd = simd_distance(st, xz); drift[i][s] = max(drift[i][s], dd)
                            let tag = "social \(r.brain.socialKind?.rawValue ?? "-")/ph\(r.brain.social?.phase ?? -1) act \(r.brain.activity) idle \(r.brain.idleState.kind?.rawValue ?? "-") stepLive \(r.brain.stepLive) feetActive \(r.brain.feet.active) root \(r.root.x),\(r.root.y)"
                            if startSess[i][s] { if dd > res.skate.worst { res.skate.worst = dd; res.skate.frame = frame; res.skate.rig = i; res.skate.foot = s; res.skate.tag = tag } }
                            else if dd > res.skateWalk { res.skateWalk = dd }
                        }
                    } else { run[i][s] = 0; endPhase(i, s) }
                }
            }
            frame += 1
            switch sc {
            case .social: if !d.lab.anySocial && frame > 10 { res.completed = true }
            case .lie: if frame >= 60 * 7 { res.completed = true }
            case .sleepPair: if secondSleeper, frame >= maxF - 1 || (b.brain.isNapping && frame > 60 * 12) { res.completed = true }
            }
            if res.completed { break }
        }
        for i in 0..<n { for s in 0..<2 { endPhase(i, s) } }
        res.frames = frame; res.seconds = Float(frame) / 60
        lock.lock(); res.leash = lc; res.leashFirst = lf; res.leashPull = lp; lock.unlock()
        let wf = d.lab.watch.map { $0.feet }, wp = d.lab.watch.map { $0.plain }
        for f in wf + wp { res.overlap = max(res.overlap, f.overlap); res.soleRise = max(res.soleRise, f.soleRise); res.centre = max(res.centre, f.centreHeight); res.radius = max(res.radius, f.radius) }
        res.overlapTag = d.lab.watch.enumerated().map { "rig\($0.offset) overlay[\($0.element.worstTag)] plain[\($0.element.plainTag)]" }.joined(separator: "; ")
        if case .sleepPair = sc {} else { XCTAssertTrue(res.completed, "\(who): completes (\(res.seconds) s)", file: file, line: line) }
        // the existing thresholds
        XCTAssertEqual(res.leash, 0, "\(who): the skin's leash / tether moved a foot piece in \(res.leash) frames, first at frame \(res.leashFirst), max pull \(String(format: "%.1f", res.leashPull * 100)) cm", file: file, line: line)
        if res.air > 0 {
            XCTAssertGreaterThanOrEqual(res.ratio, EmoteFeetTests.minRatio, "\(who): the neck ring shrank to \(res.ratio * 100) %: \(res.bad)", file: file, line: line)
            XCTAssertGreaterThanOrEqual(res.join, OnePieceInvariantTests.minNeck, "\(who): the join is open by \(-res.join * 100) cm: \(res.bad)", file: file, line: line)
            XCTAssertLessThanOrEqual(res.collar, EmoteFeetTests.maxCollar, "\(who): the collar moved skin \(res.collar * 100) cm: \(res.bad)", file: file, line: line)
        }
        d.lab.checkAll(who, plainBound: 0.03)          // (FeetAttachTests limits per rig: gap / float / radius, plus the arm cap)
        // report
        if !trace.isEmpty { try? FileManager.default.createDirectory(atPath: Self.outDir, withIntermediateDirectories: true); try? trace.joined(separator: "\n").write(toFile: Self.outDir + "trace_\(name)_\(castName).tsv", atomically: true, encoding: .utf8) }
        let sk = res.skate
        let line1 = String(format: "SOCIALFEET %@ | %@ | %.1f s | air frames %d | leash %d | ring %.2f | join %.1f cm (session %.1f, walk-up %.1f) | collar %.1f cm (session %.1f) | first bad in session [%@] | attach gap(overlap) %.3f (limit %.3f) | float soleRise %.3f (limit %.3f) centre %.3f (limit %.3f) | planted sole clearance max %.1f mm (%d planted foot-frames, %d in session) | SKATE (session) worst %.1f mm over %d planted phases (%d > 5 mm), walk-up/away worst %.1f mm at frame %d rig %d foot %d [%@] | worst attach at %@",
                           name, castName, res.seconds, res.air, res.leash, res.ratio, res.join * 100, res.joinSess * 100, res.joinWalk * 100, res.collar * 100, res.collarSess * 100, res.badSess, res.overlap, FeetAttachTests.minOverlap, res.soleRise, FeetAttachTests.maxSoleRise, res.centre, FeetAttachTests.maxCentreHeight, res.plantedFloat * 1000, res.plantedFrames, res.plantedInSession, sk.worst * 1000, sk.phases, sk.over5, res.skateWalk * 1000, sk.frame, sk.rig, sk.foot, sk.tag, res.overlapTag)
        MotionLog.write(line1); print(line1)
        try? FileManager.default.createDirectory(atPath: Self.outDir, withIntermediateDirectories: true)
        let row = [name, castName, res.completed ? "done" : "cut", String(format: "%.1f", res.seconds), "\(res.leash)", String(format: "%.2f", res.ratio), String(format: "%.1f", res.join * 100), String(format: "%.1f", res.collar * 100),
                   String(format: "%.3f", res.overlap), String(format: "%.3f", res.soleRise), String(format: "%.3f", res.centre), String(format: "%.1f", sk.worst * 1000), "\(sk.frame)", String(format: "%.1f", res.skateWalk * 1000), String(format: "%.1f", res.joinSess * 100), String(format: "%.1f", res.joinWalk * 100), String(format: "%.1f", res.collarSess * 100), sk.tag, res.badSess, res.overlapTag].joined(separator: "\t") + "\n"
        let path = Self.outDir + "socialfeet.tsv"
        if let h = FileHandle(forWritingAtPath: path) { h.seekToEndOfFile(); h.write(Data(row.utf8)); try? h.close() } else { try? row.write(toFile: path, atomically: true, encoding: .utf8) }
        return res
    }

    private func pair(_ name: String, _ k: SocialKind, sec: Float = 70) { for (label, cast) in Self.pairCasts { run(name, .social(k), cast: cast, castName: label, maxSec: sec) } }
    private func trio(_ name: String, _ k: SocialKind) { for (label, cast) in Self.trioCasts { run(name, .social(k), cast: cast, castName: label) } }

    func testBoop() { pair("boop", .boop) }
    func testSquabble() { pair("squabble", .squabble) }
    func testBump() { pair("bump", .bump) }
    func testNuzzle() { pair("nuzzle", .nuzzle) }
    func testSitTogether() { pair("sitTogether", .sitTogether) }
    func testSneak() { pair("sneak", .sneak) }
    func testChestBump() { pair("chestBump", .chestBump) }
    func testHighFive() { pair("highFive", .highFive) }
    func testHum() { pair("hum", .hum) }
    func testCheekSquish() { pair("cheekSquish", .cheekSquish) }
    func testTag() { pair("tag", .tag) }
    func testBellyBounce() { pair("bellyBounce", .bellyBounce) }
    func testNoseBoop() { pair("noseBoop", .noseBoop) }
    func testBackToBack() { pair("backToBack", .backToBack) }
    func testCuddleLean() { pair("cuddleLean", .cuddleLean) }
    func testRingAround() { pair("ringAround", .ringAround) }
    func testSwayHug() { pair("swayHug", .swayHug) }
    func testWhisperGiggle() { pair("whisperGiggle", .whisperGiggle) }
    func testSpinHug() { pair("spinHug", .spinHug) }
    func testGroupHug() { trio("groupHug", .groupHug) }
    func testCircleDance() { trio("circleDance", .circleDance) }
    func testLieDownPair() { for (label, cast) in Self.pairCasts { run("lieDown pair", .lie(.lieDown), cast: cast, castName: label, maxSec: 8) } }
    func testSleepPile() { for (label, cast) in Self.pairCasts { run("sleep pile", .sleepPair, cast: cast, castName: label, maxSec: 45) } }
}
