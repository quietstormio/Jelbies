//
//  ContactSurveyTests.swift
//  MEASURE-ONLY survey of every touching emote on the current base (2026-11-09): per run the deepest skin gap, the frames deeper than -1 cm, the hold gap, features / limbs inside the partner
//  (and whether one ever came within 5 cm), foot slide / lift while planted, and whether the emote ran to completion. Asserts nothing about the bar; it fails only if an emote cannot start.
//  One parseable line per run ("SURVEY run ...") and one per emote ("SURVEY sum ..."); set TEST_RUNNER_SURVEY_OUT=<file> to also append the lines to a file.
//

import XCTest
import simd
@testable import BobV1

@MainActor
final class ContactSurveyTests: XCTestCase {
    enum Scn { case pair(SocialKind), group(SocialKind), lie(IdleKind), sleepPair }
    struct Run {
        var started = false, completed = false, frames = 0
        var deepest: Float = .infinity, deepestPhase = -1, deepestFrame = -1
        var below1 = 0, measured = 0
        var holdGaps: [Float] = [], touchGaps: [Float] = []
        var featPen: Float = -1, limbPen: Float = -1, featRawPen: Float = -1, limbRawPen: Float = -1
        var featNear = 0, limbNear = 0, featChecks = 0
        var footSlide: Float = 0, rootSlide: Float = 0, liftMax: Float = 0, liftFrames = 0, airFrames = 0, plantedFrames = 0
    }
    static var keep: [FeatureClipTests.Duo] = []
    static let casts: [(String, [Int])] = [("Bob+Teddy", [0, 4]), ("Lavender+Pip", [3, 1])]
    static let trios: [(String, [Int])] = [("Pip+Lavender+Teddy", [1, 3, 4]), ("Bob+Teddy+Pearl", [0, 4, 5])]
    static let quad: (String, [Int]) = ("Bob+Teddy+Lavender+Pip", [0, 4, 3, 1])
    static let startsA: [SIMD2<Float>] = [SIMD2(-1.5, 0.6), SIMD2(1.35, 0.9), SIMD2(0.0, 2.4), SIMD2(-2.2, 2.0)]
    static let startsB: [SIMD2<Float>] = [SIMD2(1.5, 0.3), SIMD2(-1.2, 1.1), SIMD2(0.3, 2.5), SIMD2(2.2, 2.2)]

    override func setUp() {
        super.setUp()
        EmoteFeetTests.reset()
        RoomLayout.dynamicBoxes = []; SocialTuning.pickChance = 0.12
        GameCamera.configureRoom(count: 3, option: .A, wide: 2); _ = GameCamera.camera(aspect: 440 / 956)
        FeatureClip.enabled = true; LieClearTuning.enabled = true
        DecorField.shared.clear(); DecorField.shared.toys = ToyBook()
    }
    override func tearDown() {
        FeatureClip.enabled = true; FeatureClip.eggs = []; ContactField.reset(); ContactField.enabled = true
        DecorField.shared.clear(); DecorField.shared.toys = ToyBook()
        EmoteFeetTests.reset(); super.tearDown()
    }

    static func log(_ s: String) {
        MotionLog.write(s)
        if let p = ProcessInfo.processInfo.environment["SURVEY_OUT"], !p.isEmpty {
            let line = s + "\n"
            if let h = FileHandle(forWritingAtPath: p) { h.seekToEndOfFile(); h.write(Data(line.utf8)); try? h.close() } else { try? line.write(toFile: p, atomically: true, encoding: .utf8) }
        }
    }
    static func median(_ a: [Float]) -> Float? { a.isEmpty ? nil : a.sorted()[a.count / 2] }
    static func cm(_ f: Float?) -> String { guard let f, f.isFinite, abs(f) < 8 else { return "na" }; return String(format: "%.2f", f * 100) }

    func survey(_ scn: Scn, name: String, cast: [Int], seed: UInt64, starts: [SIMD2<Float>], maxSec: Float = 70) -> Run {
        ContactField.reset(); FeatureClip.eggs = []
        let n = cast.count
        var res = Run()
        var pos = Array(starts.prefix(n))
        if case .lie = scn { pos = [SIMD2(-1.5, 0.6), SIMD2(1.5, 0.6)] }
        let d = FeatureClipTests.Duo(positions: pos, features: cast.map { OnePieceInvariantTests.characters[$0].1 }, seed: seed, quiet: true)
        for r in d.lab.rigs { r.brain.anticsEnabled = true; r.brain.sleepEnabled = true }
        d.live = true
        Self.keep.append(d)
        let rigs = d.lab.rigs
        let a = rigs[0], b = rigs[1]
        var isSocial = false
        switch scn {
        case .pair(let k), .group(let k):
            isSocial = true
            res.started = a.brain.socialStart(k, with: b.brain, a.sim)
        case .lie(let k):
            d.place([SIMD2(-0.8, 0.6), SIMD2(0.8, 0.6)])
            for r in rigs { r.brain.idleForced = true }
            res.started = a.brain.idleStart(k, a.sim) && b.brain.idleStart(k, b.sim)
        case .sleepPair:
            d.place([SIMD2(-0.4, 0.8), SIMD2(1.0, 0.8)])
            for r in rigs { r.brain.idleForced = true }
            res.started = a.brain.idleStart(.sleep, a.sim)
            if res.started { a.brain.sleep.hold = 600 }
        }
        guard res.started else { return res }
        var secondSleeper = false
        var prevRoot = rigs.map { $0.root }
        var lastGap: Float = 9
        var evPrev = 0
        var plantedRun = [Int](repeating: 0, count: n)
        var anchorFeet = [[SIMD2<Float>]?](repeating: nil, count: n), anchorPos = [SIMD2<Float>?](repeating: nil, count: n)
        let maxF = Int(maxSec * 60)
        var frame = 0
        while frame < maxF {
            d.tick()
            let roots = rigs.map { $0.root }
            let still = zip(roots, prevRoot).allSatisfy { simd_distance($0, $1) * 60 < 0.12 }
            prevRoot = roots
            if case .sleepPair = scn, !secondSleeper, a.brain.isNapping {
                secondSleeper = true
                d.lab.snapshot = rigs.map { (pos: GameCare.floorPos($0.brain, $0.sim), walking: false) }
                _ = b.brain.idleStart(.sleep, b.sim); b.brain.sleep.hold = 600
            }
            let ph = a.brain.social?.phase ?? 0
            let inSession = isSocial ? ph >= 1 : frame > 60
            // feet: planted = no step, no gait, no walk (the brain's own account); then the feet must not slide or lift one at a time
            for i in 0..<n {
                let br = rigs[i].brain
                var walking = false; if case .walk = br.script { walking = true }
                let planted = !(br.feet.active || br.stepLive || br.gait.isBusy || walking)
                let sk = rigs[i].skinner
                guard planted, sk.beansActive else { plantedRun[i] = 0; anchorFeet[i] = nil; anchorPos[i] = nil; continue }
                plantedRun[i] += 1
                res.plantedFrames += 1
                let feetXZ: [SIMD2<Float>] = (0..<2).map { s in let p = sk.beanPos[s]; var c = SIMD2<Float>.zero; for v in p { c += SIMD2(v.x, v.z) }; return c / Float(max(p.count, 1)) }
                let low: [Float] = (0..<2).map { s in sk.beanPos[s].reduce(Float.infinity) { min($0, $1.y) } - rigs[i].sim.floorY }
                if low[0] > 0.01 && low[1] > 0.01 { res.airFrames += 1 }
                else if max(low[0], low[1]) > 0.01 { res.liftFrames += 1; res.liftMax = max(res.liftMax, max(low[0], low[1])) }
                if plantedRun[i] == 6 { anchorFeet[i] = feetXZ; anchorPos[i] = br.position }
                if let af = anchorFeet[i], let ap = anchorPos[i], plantedRun[i] > 6 {
                    res.footSlide = max(res.footSlide, simd_distance(feetXZ[0], af[0]), simd_distance(feetXZ[1], af[1]))
                    res.rootSlide = max(res.rootSlide, simd_distance(br.position, ap))
                }
            }
            // skin gap (every frame once anything is near; far apart only every 6th)
            let evNow = rigs.reduce(0) { $0 + $1.brain.contactEvents }
            let evDelta = evNow - evPrev; evPrev = evNow
            if lastGap < 0.4 || frame % 6 == 0 || evDelta > 0 {
                let Sf = d.contactSurfaces()
                var gm: Float = 9
                for i in 0..<n { for j in (i + 1)..<n { let g = BruteForceContactMetric.skinGap(Sf[i], Sf[j]); if g < gm { gm = g } } }
                lastGap = gm
                if gm < 8 {
                    res.measured += 1
                    if gm < res.deepest { res.deepest = gm; res.deepestPhase = isSocial ? ph : -1; res.deepestFrame = frame }
                    if gm < -0.01 { res.below1 += 1 }
                    var active = true
                    if case .pair(let k) = scn, let st = ContactStance.entry(k), st.cls == .touching { active = st.step(at: ph)?.target == ContactStance.hold }
                    if still && inSession && active && gm < 0.3 { res.holdGaps.append(gm) }
                    if evDelta > 0 { for _ in 0..<evDelta { res.touchGaps.append(gm) } }
                }
            }
            // features / limbs vs the partners (every 4th frame once anything is near)
            if frame % 4 == 1 && frame > 20 && lastGap < 0.4 {
                FeatureClip.enabled = false
                let rawF = d.skinAll(), rawL = (0..<n).map { d.limbPoints($0) }
                FeatureClip.enabled = true
                let clipF = d.skinAll(), clipL = (0..<n).map { d.limbPoints($0) }
                res.featChecks += 1
                var fNear = false, lNear = false
                func judge(_ pts: [SIMD3<Float>], raw: [SIMD3<Float>], owner i: Int) -> (pen: Float, near: Bool) {
                    var pen: Float = -1; var near = false
                    for (k, p) in pts.enumerated() {
                        if d.egg(i).depthFull(raw[k]) > -0.01 { continue }          // (the join with the owner is where the clip lets go)
                        for j in 0..<n where j != i {
                            let e = d.egg(j)
                            let dist = simd_distance(p, e.centroid)
                            if dist > e.radius + 0.08 { continue }
                            let df = e.depthFull(p)
                            if df > -0.05 { near = true }
                            pen = max(pen, df)
                        }
                    }
                    return (pen, near)
                }
                for i in 0..<n {
                    let f = judge(clipF[i], raw: rawF[i], owner: i), l = judge(clipL[i], raw: rawL[i], owner: i)
                    let fr = judge(rawF[i], raw: rawF[i], owner: i), lr = judge(rawL[i], raw: rawL[i], owner: i)
                    res.featPen = max(res.featPen, f.pen); res.limbPen = max(res.limbPen, l.pen)
                    res.featRawPen = max(res.featRawPen, fr.pen); res.limbRawPen = max(res.limbRawPen, lr.pen)
                    fNear = fNear || f.near; lNear = lNear || l.near
                }
                if fNear { res.featNear += 1 }
                if lNear { res.limbNear += 1 }
            }
            frame += 1
            switch scn {
            case .pair, .group: if !d.lab.anySocial && frame > 10 { res.completed = true }
            case .lie: if frame >= 60 * 7 { res.completed = true }
            case .sleepPair: if secondSleeper, frame >= maxF - 1 || (b.brain.isNapping && frame > 60 * 12) { res.completed = true }
            }
            if res.completed { break }
        }
        res.frames = frame
        return res
    }

    func line(_ name: String, _ cast: String, _ seed: UInt64, _ r: Run) -> String {
        String(format: "SURVEY run emote=%@ cast=%@ seed=%d started=%d completed=%d frames=%d deepest_cm=%@ deepest_phase=%d deepest_frame=%d below1_frames=%d measured=%d hold_cm=%@ hold_n=%d touch_cm=%@ touch_n=%d feat_pen_cm=%@ limb_pen_cm=%@ feat_raw_pen_cm=%@ limb_raw_pen_cm=%@ feat_near5=%d limb_near5=%d feat_checks=%d foot_slide_cm=%.2f root_slide_cm=%.2f lift_cm=%.2f lift_frames=%d air_frames=%d planted_frames=%d",
               name, cast, Int(seed), r.started ? 1 : 0, r.completed ? 1 : 0, r.frames, Self.cm(r.deepest), r.deepestPhase, r.deepestFrame, r.below1, r.measured, Self.cm(Self.median(r.holdGaps)), r.holdGaps.count, Self.cm(Self.median(r.touchGaps)), r.touchGaps.count,
               Self.cm(r.featPen), Self.cm(r.limbPen), Self.cm(r.featRawPen), Self.cm(r.limbRawPen), r.featNear, r.limbNear, r.featChecks, r.footSlide * 100, r.rootSlide * 100, r.liftMax * 100, r.liftFrames, r.airFrames, r.plantedFrames)
    }

    /// Runs every cast x seed of one emote, prints the lines, then the worst-case summary.
    func runEmote(_ name: String, _ scn: Scn, casts: [(String, [Int])], maxSec: Float = 70, quad: Bool = false) {
        var runs: [Run] = []
        var all = casts
        if quad { all.append(Self.quad) }
        for (cn, cast) in all {
            for (seed, starts) in [(UInt64(31), Self.startsA), (UInt64(32), Self.startsB)] {
                if cast.count == 4 && seed == 32 { continue }          // (one 4-Jelbie cast is enough)
                let r = survey(scn, name: name, cast: cast, seed: seed, starts: starts, maxSec: maxSec)
                Self.log(line(name, cn, seed, r))
                if r.started { runs.append(r) } else if cast.count == 4 { Self.log("SURVEY note emote=\(name) cast=\(cn) 4-Jelbie cast did not start") } else { XCTFail("\(name) \(cn) \(seed): did not start") }
            }
        }
        guard !runs.isEmpty else { return }
        let worstHold = runs.compactMap { Self.median($0.holdGaps) }
        let touchMed = runs.compactMap { Self.median($0.touchGaps) }
        Self.log(String(format: "SURVEY sum emote=%@ runs=%d completed=%d deepest_cm=%@ below1_max=%d hold_max_cm=%@ hold_min_cm=%@ touch_max_cm=%@ feat_pen_max_cm=%@ limb_pen_max_cm=%@ feat_near5=%d limb_near5=%d foot_slide_max_cm=%.2f root_slide_max_cm=%.2f lift_max_cm=%.2f lift_frames_max=%d",
                        name, runs.count, runs.filter { $0.completed }.count, Self.cm(runs.map { $0.deepest }.min()), runs.map { $0.below1 }.max() ?? 0, Self.cm(worstHold.max()), Self.cm(worstHold.min()), Self.cm(touchMed.max()),
                        Self.cm(runs.map { $0.featPen }.max()), Self.cm(runs.map { $0.limbPen }.max()), runs.map { $0.featNear }.reduce(0, +), runs.map { $0.limbNear }.reduce(0, +),
                        (runs.map { $0.footSlide }.max() ?? 0) * 100, (runs.map { $0.rootSlide }.max() ?? 0) * 100, (runs.map { $0.liftMax }.max() ?? 0) * 100, runs.map { $0.liftFrames }.max() ?? 0))
    }

    func pairs(_ list: [(String, SocialKind)], maxSec: Float = 70) { for (n, k) in list { runEmote(n, .pair(k), casts: Self.casts, maxSec: maxSec) } }

    func testSurvey1_contactPairsA() { pairs([("chestBump", .chestBump), ("bellyBounce", .bellyBounce), ("backToBack", .backToBack), ("spinHug", .spinHug), ("squabble", .squabble), ("sneak", .sneak)]) }
    func testSurvey2_contactPairsB() { pairs([("sitTogether", .sitTogether), ("tag", .tag), ("ringAround", .ringAround), ("twirl", .twirl), ("peekaboo", .peekaboo), ("leapfrog", .leapfrog)]) }
    func testSurvey3_chase() { pairs([("chase", .chase)], maxSec: 40) }
    func testSurvey4_controls() { pairs([("nuzzle", .nuzzle), ("swayHug", .swayHug), ("cuddleLean", .cuddleLean), ("boop", .boop), ("cheekSquish", .cheekSquish), ("whisperGiggle", .whisperGiggle), ("bump", .bump), ("highFive", .highFive)]) }
    func testSurvey5_lying() {
        runEmote("lieDownTogether", .lie(.lieDown), casts: Self.casts, maxSec: 8)
        runEmote("flopTogether", .lie(.flop), casts: Self.casts, maxSec: 8)
        runEmote("sleepPile", .sleepPair, casts: Self.casts, maxSec: 45)
    }
    func testSurvey6_groups() {
        for (n, k) in [("groupHug", SocialKind.groupHug), ("circleDance", .circleDance), ("conga", .conga), ("congaLine", .congaLine), ("ringDance", .ringDance), ("groupCheer", .groupCheer)] {
            runEmote(n, .group(k), casts: Self.trios, quad: true)
        }
    }
}
