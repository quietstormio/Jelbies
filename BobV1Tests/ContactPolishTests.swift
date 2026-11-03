//
//  ContactPolishTests.swift
//  The contact-polish harness (2026-11-02, g-contactcat; catalogue in docs/CONTACT_EMOTES.md): every emote where Jelbies come within touching range, run for the species pairs that
//  stress it (Bob+Teddy, Teddy+Pearl = the user's photo, Lavender+Pip, Pip+Teddy, Moss+Pearl; three-Jelbie emotes with a winged one and Pip), and measured EVERY pair EVERY frame with the
//  ground-truth `ContactMetric` (BruteForceContactMetric: root distance minus the skins' reach, signed, metres):
//    gap        the minimum skin gap over all pairs (negative = the drawn surfaces overlap)
//    stance     the median gap of the frames where the pair stands still inside the session (the "touching stance")
//    features   the deepest feature vertex (wings, spikes, daisy; plus the limbs: arms, ears, tail) inside another body's fitted egg, with the shipped FeatureClip on and (raw) off
//    sounds     the contact sounds (squish, boop, wobble, highfive_boop, emote_spinhug, conga_tick, ring_chime) and the haptic requests (emote haptics, the boop / shove events), per touch
//               episode (an episode starts at gap <= +1 cm and is re-armed when the gap is > +3 cm again)
//  The assertions are the contact brief; they need the new contact engine (BlobBrain / ContactSettle), so they run only with CONTACT_ENFORCE=1 and are XCTSkip-ped otherwise: the suite
//  still runs the ground-truth measuring today and writes the BEFORE table. With TEST_RUNNER_CONTACT_OUT=<dir> it also writes the per-run table (results_*.tsv, worst_frames.tsv,
//  static_spacing.tsv) and, in testZ_strips, a 6-frame strip per emote (worst species pair, centred on its worst frame; the real renderer, features drawn).
//    xcodebuild test-without-building ... -parallel-testing-enabled NO TEST_RUNNER_CONTACT_OUT=/path [TEST_RUNNER_CONTACT_ENFORCE=1]   (Release + ENABLE_TESTABILITY=YES)
//

import XCTest
import Metal
import simd
import UIKit
@testable import BobV1

// MARK: - the Duo, measured

extension FeatureClipTests.Duo {
    /// The ranges of body i's drawn skin: the egg part, then the limb blocks that are drawn (arms, tail, Teddy's ears + pom, the foot beans).
    func contactRanges(_ i: Int) -> [Range<Int>] {
        let sk = lab.rigs[i].skinner
        var r: [Range<Int>] = [0..<eggLimit]
        if sk.armCapsulesActive { for s in 0..<2 { r.append(sk.armFirst[s]..<(sk.armFirst[s] + ArmCapsule.vertexCount)) } }
        if sk.tailOn, sk.tailFirst >= 0 { r.append(sk.tailFirst..<(sk.tailFirst + TailBean.vertexCount)) }
        if sk.teddyOn, sk.teddyFirst >= 0 { r.append(sk.teddyFirst..<(sk.teddyFirst + TeddyBean.vertexCount)) }
        if sk.beansActive, let cap = MotionRig.renderMesh.armCapsule { for side in [-1, 1] { let f = cap.beanFirst(side: side); r.append(f..<(f + FootBean.vertexCount)) } }
        return r
    }
    /// Every body skinned like the stage does (+ the clip pass), as `ContactSurface`s (no feature meshes: those are judged by depth).
    func contactSurfaces(bodyOnly: Bool = false) -> [ContactSurface] {
        var jobs: [JellyParallel.SkinJob] = []
        for (i, r) in lab.rigs.enumerated() {
            r.skinner.update(x: r.sim.x, index: MotionRig.renderMesh.index, into: dyn[i])
            jobs.append(JellyParallel.SkinJob(skinner: r.skinner, sim: r.sim, dst: dyn[i], id: i))
        }
        FeatureClip.apply(jobs: jobs)
        return lab.rigs.indices.map { ContactSurface(root: lab.rigs[$0].root, dyn: UnsafePointer(dyn[$0]), ranges: bodyOnly ? [0..<eggLimit] : contactRanges($0)) }
    }
}

// MARK: - the catalogue (mirrors docs/CONTACT_EMOTES.md)

enum ContactStance: String { case touching, proximity }
enum ContactScenario { case social(SocialKind), lie(IdleKind), sleepPair }
enum ContactProp { case none, ball, beanbag, loveseat }

struct ContactEntry {
    var name: String
    var scenario: ContactScenario
    var stance: ContactStance
    var props: ContactProp = .none
    var maxSec: Float = 70
    /// true = start from the lab's default spots (1.7 apart: already inside a boop's / greet's window); false = 3 apart, so the walk-up happens.
    var near = false
}

@MainActor
final class ContactPolishTests: XCTestCase {
    typealias Duo = FeatureClipTests.Duo

    // MARK: config

    static let outDir: String? = { let d = ProcessInfo.processInfo.environment["CONTACT_OUT"] ?? ""; return d.isEmpty ? nil : d }()
    static let enforce = ProcessInfo.processInfo.environment["CONTACT_ENFORCE"] == "1"
    /// 0 Bob, 1 Pip, 2 Moss, 3 Lavender, 4 Teddy, 5 Pearl.
    static let names = OnePieceInvariantTests.characters.map { $0.0 }
    static let pairs: [(String, [Int])] = [("Bob+Teddy", [0, 4]), ("Teddy+Pearl", [4, 5]), ("Lavender+Pip", [3, 1]), ("Pip+Teddy", [1, 4]), ("Moss+Pearl", [2, 5])]
    static let trios: [(String, [Int])] = [("Pip+Lavender+Teddy", [1, 3, 4]), ("Pip+Pearl+Moss", [1, 5, 2]), ("Bob+Teddy+Pearl", [0, 4, 5])]
    /// The contact sounds (SFX raw values) the catalogue talks about.
    static let contactSounds: Set<String> = ["squish", "boop", "wobble", "highfive_boop", "emote_spinhug", "conga_tick", "ring_chime"]
    static let touchOn: Float = 0.01, touchOff: Float = 0.03
    /// Start spots 2.9 apart (pairs) so the walk-up to the stance really happens; the third is further back.
    static let farStarts: [SIMD2<Float>] = [SIMD2(-1.5, 0.6), SIMD2(1.35, 0.9), SIMD2(0.0, 2.4)]
    nonisolated(unsafe) static var keep: [AnyObject] = []
    nonisolated(unsafe) static var all: [Result] = []

    static func e(_ n: String, _ k: SocialKind, _ s: ContactStance, props: ContactProp = .none, sec: Float = 70) -> ContactEntry { ContactEntry(name: n, scenario: .social(k), stance: s, props: props, maxSec: sec) }
    /// Pair emotes (rig 0 starts it with rig 1).
    static let pairEntries: [ContactEntry] = [
        e("boop", .boop, .touching), e("squabble", .squabble, .touching), e("bump", .bump, .touching), e("nuzzle", .nuzzle, .touching), e("sitTogether", .sitTogether, .touching),
        e("sneak", .sneak, .touching), e("chestBump", .chestBump, .touching), e("highFive", .highFive, .touching), e("hum", .hum, .touching), e("cheekSquish", .cheekSquish, .touching),
        e("bellyBounce", .bellyBounce, .touching), e("noseBoop", .noseBoop, .touching), e("backToBack", .backToBack, .touching), e("cuddleLean", .cuddleLean, .touching),
        e("ringAround", .ringAround, .touching), e("swayHug", .swayHug, .touching), e("whisperGiggle", .whisperGiggle, .touching), e("spinHug", .spinHug, .touching),
        e("tag", .tag, .touching), e("chase", .chase, .touching, sec: 40),
        ContactEntry(name: "greet", scenario: .social(.greet), stance: .proximity, near: true), e("look", .look, .proximity), e("follow", .follow, .proximity), e("zoomies", .zoomies, .proximity, sec: 40), e("dance", .dance, .proximity),
        e("keepAway", .keepAway, .proximity, sec: 30), e("line", .line, .proximity), e("twirl", .twirl, .proximity), e("hopAlong", .hopAlong, .proximity), e("littleRace", .littleRace, .proximity),
        e("leapfrog", .leapfrog, .proximity), e("peekaboo", .peekaboo, .proximity), e("mirrorDance", .mirrorDance, .proximity), e("danceOff", .danceOff, .proximity), e("shyWave", .shyWave, .proximity),
        e("pass (ball)", .pass, .proximity, props: .ball, sec: 80), e("bagSit (beanbag)", .bagSit, .touching, props: .beanbag), e("cuddle (loveseat)", .cuddle, .touching, props: .loveseat),
        ContactEntry(name: "lieDown pair (LieClear)", scenario: .lie(.lieDown), stance: .touching, maxSec: 8),
        ContactEntry(name: "flop pair (LieClear)", scenario: .lie(.flop), stance: .touching, maxSec: 8),
        ContactEntry(name: "sleep pile", scenario: .sleepPair, stance: .touching, maxSec: 45),
    ]
    /// Group emotes (three Jelbies; rig 0 starts it with rig 1, the others join).
    static let groupEntries: [ContactEntry] = [
        e("groupHug", .groupHug, .touching), e("groupCheer", .groupCheer, .proximity), e("conga", .conga, .proximity), e("circleDance", .circleDance, .touching),
        e("congaLine", .congaLine, .proximity), e("ringDance", .ringDance, .proximity),
    ]

    // MARK: results

    struct Result {
        var name = "", cast = "", stance = ContactStance.proximity, kind = ""
        var started = false, completed = false
        var seconds: Float = 0, frames = 0
        var minGap: Float = .infinity, minGapT: Float = 0, minGapFrame = 0, minGapPair = "", minGapPhase = ""
        var stance01: [Float] = []                      // gaps of the standing frames inside the session
        var touchFrames = 0
        var episodes = 0, sndInEpisode: [Int] = [], hapInEpisode: [Int] = [], sndOutside = 0, hapOutside = 0
        var sndGapMin: Float = .infinity, sndGapMax: Float = -.infinity
        var boopEvents = 0
        var featRaw: Float = -1, featClip: Float = -1, limbRaw: Float = -1, limbClip: Float = -1, eggPen: Float = -1
        var sounds: [String: Int] = [:], haps: [String: Int] = [:]
        var stanceMedian: Float? { stance01.count >= 10 ? stance01.sorted()[stance01.count / 2] : nil }
        var sndTotalContact: Int { sndInEpisode.reduce(0, +) + sndOutside }
    }

    final class Tap {
        var frame = 0
        var sounds: [(Int, String)] = [], haps: [(Int, String)] = []
    }

    override func setUp() {
        super.setUp()
        EmoteFeetTests.reset()
        RoomLayout.dynamicBoxes = []; SocialTuning.pickChance = 0.12
        GameCamera.configureRoom(count: 3, option: .A, wide: 2); _ = GameCamera.camera(aspect: 440 / 956)
        FeatureClip.enabled = true; LieClearTuning.enabled = true
    }
    override func tearDown() {
        AudioHub.requestTap = nil; EmoteHaptic.requestTap = nil; EmoteTreats.requestTap = nil; HapticDriver.cueTap = nil
        FeatureClip.enabled = true; FeatureClip.eggs = []; ContactField.reset(); ContactField.enabled = true
        DecorField.shared.clear(); DecorField.shared.toys = ToyBook()
        EmoteFeetTests.reset()
        super.tearDown()
    }

    // MARK: the run

    func makeDuo(cast: [Int], positions: [SIMD2<Float>]? = nil, seed: UInt64 = 31) -> Duo {
        let n = cast.count
        let d = Duo(positions: positions ?? Array(SocialTests.starts.prefix(n)), features: cast.map { OnePieceInvariantTests.characters[$0].1 }, seed: seed, quiet: true)
        for r in d.lab.rigs { r.brain.anticsEnabled = true; r.brain.sleepEnabled = true }
        d.live = ProcessInfo.processInfo.environment["CONTACT_ENGINE"] != "0"          // (the contact engine as in the app: a profile every tick; CONTACT_ENGINE=0 = the BEFORE table)
        return d
    }

    func setProps(_ p: ContactProp) {
        DecorField.shared.clear(); DecorField.shared.toys = ToyBook()
        switch p {
        case .none: break
        case .ball: DecorField.shared.set([PlacedDecor(uid: 7, kind: .soccerball, x: 0.2, z: 1.0)])
        case .beanbag: DecorField.shared.set([PlacedDecor(uid: 7, kind: .beanbag, x: 0.0, z: 1.3)])
        case .loveseat: DecorField.shared.set([PlacedDecor(uid: 7, kind: .loveseat, x: 0.0, z: 1.5)])
        }
    }

    /// Runs one emote for one cast. `plan`: when set, the frames to shoot (the strip) with the shooter.
    func run(_ e: ContactEntry, cast: [Int], castName: String, plan: [Int]? = nil, device: MTLDevice? = nil) -> (Result, [UIImage]) {
        setProps(e.props)
        let n = cast.count
        var res = Result(); res.name = e.name; res.cast = castName; res.stance = e.stance
        var positions: [SIMD2<Float>]? = nil
        if case .lie = e.scenario { positions = [SIMD2(-1.5, 0.6), SIMD2(1.5, 0.6)] }
        else if !e.near { positions = Array(Self.farStarts.prefix(n)) }
        let d = makeDuo(cast: cast, positions: positions)
        Self.keep.append(d)
        let tap = Tap()
        AudioHub.requestTap = { tap.sounds.append((tap.frame, $0)) }
        EmoteHaptic.requestTap = { tap.haps.append((tap.frame, "emote:" + $0)) }
        EmoteTreats.requestTap = { tap.haps.append((tap.frame, "treat:" + $0)) }
        HapticDriver.cueTap = { tap.haps.append((tap.frame, "room:\($0.name)")) }
        let rigs = d.lab.rigs
        let a = rigs[0], b = rigs[1]
        var ok = false
        switch e.scenario {
        case .social(let k):
            res.kind = k.rawValue
            ok = a.brain.socialStart(k, with: b.brain, a.sim)
        case .lie(let k):
            res.kind = k.rawValue
            d.place([SIMD2(-0.6, 0.6), SIMD2(0.6, 0.6)])
            for r in rigs { r.brain.idleForced = true }
            ok = a.brain.idleStart(k, a.sim) && b.brain.idleStart(k, b.sim)
        case .sleepPair:
            res.kind = "sleep"
            d.place([SIMD2(-0.4, 0.8), SIMD2(1.0, 0.8)])
            for r in rigs { r.brain.idleForced = true }
            ok = a.brain.idleStart(.sleep, a.sim)
            if ok { a.brain.sleep.hold = 600 }
        }
        res.started = ok
        guard ok else { AudioHub.requestTap = nil; return (res, []) }
        var shooter: FeatureClipCaptureTests.Shooter? = nil
        var palettes: [Palette] = []
        if plan != nil, let device {
            shooter = try? FeatureClipCaptureTests.Shooter(device: device, d: d, W: 520, H: 440)
            palettes = cast.map { Self.palette($0) }
        }
        var cells: [UIImage] = []
        var prevRoot = rigs.map { $0.root }
        var evCount = Array(repeating: 0, count: n)
        var inEpisode = false, lastEnd = -1000, lastMg: Float = 9
        var curEpisode = -1
        var sndSeen = 0, hapSeen = 0
        var secondSleeper = false
        let maxF = Int(e.maxSec * 60)
        var frame = 0
        while frame < maxF {
            tap.frame = frame
            d.tick()
            if case .sleepPair = e.scenario, !secondSleeper, a.brain.isNapping {
                secondSleeper = true
                d.lab.snapshot = rigs.map { (pos: GameCare.floorPos($0.brain, $0.sim), walking: false) }
                _ = b.brain.idleStart(.sleep, b.sim); b.brain.sleep.hold = 600
            }
            // events (boop / shove)
            for i in 0..<n {
                let evs = d.lab.events[i]
                if evs.count > evCount[i] {
                    for ev in evs[evCount[i]...] { switch ev { case .boop, .shove: res.boopEvents += 1; tap.haps.append((frame, "event:boop")); default: break } }
                    evCount[i] = evs.count
                }
            }
            // speeds
            let roots = rigs.map { $0.root }
            let still = zip(roots, prevRoot).allSatisfy { simd_distance($0, $1) * 60 < 0.12 }
            prevRoot = roots
            let sampled = frame % 2 == 0
            var inSession = true
            if case .social = e.scenario { inSession = (a.brain.social?.phase ?? 0) >= 1 } else { inSession = frame > 60 }
            var gapNow: Float? = nil
            if sampled || (plan?.contains(frame) ?? false) {
                let S = d.contactSurfaces()
                var mg = Float.infinity, mp = ""
                for i in 0..<n { for j in (i + 1)..<n {
                    let g = BruteForceContactMetric.skinGap(S[i], S[j])
                    if g < mg { mg = g; mp = "\(Self.names[cast[i]])-\(Self.names[cast[j]])" }
                } }
                if sampled && mg < 8 {
                    gapNow = mg
                    if mg < res.minGap { res.minGap = mg; res.minGapT = Float(frame) / 60; res.minGapFrame = frame; res.minGapPair = mp
                        res.minGapPhase = "\(a.brain.socialKind.map { $0.rawValue } ?? "-")/ph\(a.brain.social?.phase ?? -1)/idle \(a.brain.idleState.kind.map { "\($0)" } ?? "-")" }
                    if mg <= Self.touchOn { res.touchFrames += 1 }
                    if still, inSession, mg < 2.2 { res.stance01.append(mg) }
                    // episodes
                    if !inEpisode, mg <= Self.touchOn { inEpisode = true; res.episodes += 1; curEpisode = res.episodes - 1; res.sndInEpisode.append(0); res.hapInEpisode.append(0) }
                    else if inEpisode, mg > Self.touchOff { inEpisode = false; lastEnd = frame }
                    lastMg = mg
                }
                if let sh = shooter, let pl = plan, pl.contains(frame), cells.count < pl.count {
                    let cs = rigs.map { $0.sim.centroid() }
                    var c = SIMD3<Float>.zero; for x in cs { c += x }; c /= Float(n)
                    cells.append(sh.shot(d, palettes: palettes, focus: SIMD3(c.x, 0.55, c.z), dirv: simd_normalize(SIMD3(0.35, 0, 1)), dist: n == 2 ? 3.6 : 4.4, lift: 0.5))
                }
            }
            // sounds / haptics requested this frame
            while sndSeen < tap.sounds.count {
                let (f, name) = tap.sounds[sndSeen]; sndSeen += 1
                guard !name.hasPrefix("chirp:") else { continue }
                res.sounds[name, default: 0] += 1
                if Self.contactSounds.contains(name) {
                    res.sndGapMin = min(res.sndGapMin, lastMg); res.sndGapMax = max(res.sndGapMax, lastMg)
                    if inEpisode || f - lastEnd <= 20, curEpisode >= 0 { res.sndInEpisode[curEpisode] += 1 } else { res.sndOutside += 1 }
                }
            }
            while hapSeen < tap.haps.count {
                let (f, name) = tap.haps[hapSeen]; hapSeen += 1
                res.haps[name, default: 0] += 1
                if inEpisode || f - lastEnd <= 20, curEpisode >= 0 { res.hapInEpisode[curEpisode] += 1 } else { res.hapOutside += 1 }
            }
            _ = gapNow
            // features / limbs (every 6th frame while it is going on)
            if frame % 6 == 3 && frame > 20, plan == nil {
                FeatureClip.enabled = false
                let rawF = d.skinAll(), rawL = (0..<n).map { d.limbPoints($0) }
                FeatureClip.enabled = true
                let clipF = d.skinAll(), clipL = (0..<n).map { d.limbPoints($0) }
                for i in 0..<n { for j in (i + 1)..<n { res.eggPen = max(res.eggPen, d.bodyGap(i, j)) } }
                for i in 0..<n {
                    res.featRaw = max(res.featRaw, d.penetration(rawF[i], owner: i)); res.limbRaw = max(res.limbRaw, d.penetration(rawL[i], owner: i))
                    res.featClip = max(res.featClip, d.penetration(clipF[i], owner: i, raw: rawF[i])); res.limbClip = max(res.limbClip, d.penetration(clipL[i], owner: i, raw: rawL[i]))
                }
            }
            frame += 1
            switch e.scenario {
            case .social: if !d.lab.anySocial && frame > 10 { res.completed = true }
            case .lie: if frame >= 60 * 7 { res.completed = true }
            case .sleepPair: if secondSleeper, frame >= maxF - 1 || (b.brain.isNapping && frame > 60 * 12) { res.completed = true }
            }
            if res.completed { break }
        }
        res.frames = frame; res.seconds = Float(frame) / 60
        AudioHub.requestTap = nil; EmoteHaptic.requestTap = nil; EmoteTreats.requestTap = nil; HapticDriver.cueTap = nil
        return (res, cells)
    }

    static func palette(_ c: Int) -> Palette {
        switch c {
        case 0: return PaletteKey.blue.palette
        case 4: return JellyRoster.palette(JellyRoster.teddyID) ?? PaletteKey.blue.palette
        case 5: return WhiteWing.palette
        default: return JellyRoster.palette(c) ?? PaletteKey.blue.palette
        }
    }

    // MARK: the table

    static func cm(_ f: Float) -> String { f.isFinite ? String(format: "%.1f", f * 100) : "-" }
    /// A depth in cm; "-" when there was none to measure (the sentinel is -1 u).
    static func dcm(_ f: Float) -> String { f <= -0.99 ? "-" : cm(f) }
    static let header = ["emote", "cast", "stance", "started", "sec", "minGap_cm", "at_s", "pair", "where", "stanceMedian_cm", "stanceN", "touchFrames", "episodes", "snd_per_episode", "snd_outside", "hap_per_episode", "hap_outside",
                         "sndGap_cm(min..max)", "boopEv", "featRaw_cm", "featClip_cm", "limbRaw_cm", "limbClip_cm", "eggPen_cm", "sounds", "haptics"].joined(separator: "\t")
    static func row(_ r: Result) -> String {
        [r.name, r.cast, r.stance.rawValue, r.started ? "yes" : "NO START", String(format: "%.1f", r.seconds), cm(r.minGap), String(format: "%.1f", r.minGapT), r.minGapPair, r.minGapPhase,
         r.stanceMedian.map(cm) ?? "-", "\(r.stance01.count)", "\(r.touchFrames)", "\(r.episodes)", r.sndInEpisode.map(String.init).joined(separator: ","), "\(r.sndOutside)", r.hapInEpisode.map(String.init).joined(separator: ","), "\(r.hapOutside)",
         r.sndGapMin.isFinite ? "\(cm(r.sndGapMin))..\(cm(r.sndGapMax))" : "-", "\(r.boopEvents)", dcm(r.featRaw), dcm(r.featClip), dcm(r.limbRaw), dcm(r.limbClip), dcm(r.eggPen),
         r.sounds.sorted { $0.key < $1.key }.map { "\($0.key)x\($0.value)" }.joined(separator: " "), r.haps.sorted { $0.key < $1.key }.map { "\($0.key)x\($0.value)" }.joined(separator: " ")].joined(separator: "\t")
    }
    static func write(_ rows: [Result], file: String) {
        guard let dir = outDir else { return }
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let text = ([header] + rows.map(row)).joined(separator: "\n") + "\n"
        try? text.write(toFile: dir + "/" + file, atomically: true, encoding: .utf8)
    }

    /// The contact brief as assertions. Needs the new engine: only with CONTACT_ENFORCE=1, else the test is skipped after the table is written.
    func finish(_ rs: [Result], _ what: String) throws {
        Self.all.removeAll { a in rs.contains { $0.name == a.name && $0.cast == a.cast } }
        Self.all += rs
        for r in rs { MotionLog.write("CONTACT " + Self.row(r)) }
        guard Self.enforce else {
            let bad = rs.filter { $0.started && $0.minGap < -0.01 }
            throw XCTSkip("pending engine: \(what): \(rs.count) runs measured (BEFORE), \(bad.count) overlap by more than 1 cm; set CONTACT_ENFORCE=1 to assert")
        }
        for r in rs where r.started {
            let who = "\(r.name) [\(r.cast)]"
            XCTAssertGreaterThanOrEqual(r.minGap, -0.01, "\(who): the skins overlap by \(Self.cm(-r.minGap)) cm at \(r.minGapT) s (\(r.minGapPair), \(r.minGapPhase))")
            if r.stance == .touching, let m = r.stanceMedian { XCTAssertLessThanOrEqual(m, 0.01, "\(who): the touching stance settles \(Self.cm(m)) cm apart (want <= 1 cm)") }
            XCTAssertLessThanOrEqual(max(r.featClip, r.limbClip), 0.005, "\(who): a feature / limb vertex is \(Self.cm(max(r.featClip, r.limbClip))) cm inside another body")
            if r.stance == .touching {
                XCTAssertGreaterThan(r.episodes, 0, "\(who): never touches")
                for (k, s) in r.sndInEpisode.enumerated() { XCTAssertEqual(s, 1, "\(who): touch \(k) fired \(s) contact sounds (want exactly 1)") }
                XCTAssertEqual(r.sndOutside, 0, "\(who): \(r.sndOutside) contact sounds fired while the skins were not touching")
            }
        }
    }

    // MARK: tests

    /// The metric itself (always on): signed, translation-consistent, +ve apart / -ve overlapping, and the plain closest-vertex distance never reads less than the gap.
    func testMetricSanity() {
        let d = makeDuo(cast: [0, 0], positions: [SIMD2(-1.5, 0.6), SIMD2(1.5, 0.6)])
        Self.keep.append(d)
        func gap(_ dist: Float) -> (Float, Float) {
            d.place([SIMD2(-dist / 2, 0.6), SIMD2(dist / 2, 0.6)])
            for _ in 0..<30 { d.tick() }
            let S = d.contactSurfaces()
            return (BruteForceContactMetric.skinGap(S[0], S[1]), BruteForceContactMetric.closestHorizontal(S[0], S[1]))
        }
        let far = gap(3.0), mid = gap(1.4), close = gap(0.9)
        MotionLog.write("CONTACT metric: 3.0 apart gap \(far.0) closest \(far.1); 1.4 gap \(mid.0); 0.9 gap \(close.0)")
        let touch = 3.0 - far.0
        XCTAssertGreaterThan(touch, 0.9); XCTAssertLessThan(touch, 1.5, "two plain standing Jelbies touch at a root distance of about a body width (\(touch))")
        XCTAssertGreaterThan(far.0, 1.2); XCTAssertEqual(mid.0, 1.4 - touch, accuracy: 0.06, "gap follows the root distance")
        XCTAssertLessThan(close.0, 0, "0.9 apart is an overlap")
        XCTAssertGreaterThanOrEqual(far.1, far.0 - 0.01, "closest vertex distance >= the gap while apart")
    }

    private func pairTest(_ pi: Int) throws {
        let (label, cast) = Self.pairs[pi]
        var rs: [Result] = []
        for e in Self.pairEntries { rs.append(run(e, cast: cast, castName: label).0) }
        Self.write(rs, file: "results_\(label).tsv")
        try finish(rs, label)
    }
    func testPairs1_BobTeddy() throws { try pairTest(0) }
    func testPairs2_TeddyPearl() throws { try pairTest(1) }
    func testPairs3_LavenderPip() throws { try pairTest(2) }
    func testPairs4_PipTeddy() throws { try pairTest(3) }
    func testPairs5_MossPearl() throws { try pairTest(4) }

    func testGroups() throws {
        var rs: [Result] = []
        for (label, cast) in Self.trios { for e in Self.groupEntries { rs.append(run(e, cast: cast, castName: label).0) } }
        Self.write(rs, file: "results_groups.tsv")
        try finish(rs, "groups")
    }

    /// The stances the stage / sessions place by a fixed centre distance (focus row, dining places, sleeping row, huddle slots, the volley court ...): the skin gap of two idle Jelbies put exactly there.
    /// Side by side (along x) and one behind the other (along z), every species pair. Also the touch distance (root distance at gap 0) of each pair and axis.
    func testStaticSpacing() throws {
        let spacings: [(String, Float)] = [
            ("keepApart spring floor 0.78 x jellyGap", 0.78 * 1.4), ("closeGapFactor 0.74 x jellyGap", 0.74 * 1.4), ("faceGap 0.76 / spinHug 0.84 x", 0.8 * 1.4),
            ("Dining stands (3 places) 1.11", 1.11), ("Focus row hard gap 1.0 (GameCamera.focusRowGap)", 1.0), ("Focus row steer gap 1.05 (FocusGroup.rowSteerGap)", 1.05), ("Focus row spacing 1.15", 1.15),
            ("Dining 2 places 1.86", 1.86), ("Group hug / circle touch chord 0.78 x 1.4 = 1.09", 1.092), ("sideSpot 0.95 x 1.4 = 1.33", 1.33), ("jellyGap 1.4 (highFive 1.05 x = 1.47)", 1.4), ("highFive 1.47", 1.47),
            ("Sleep pile row 1.66", 1.66), ("Volley partnerGap 1.6", 1.6), ("conga follow 1.15 x 1.4 = 1.61", 1.61), ("Group loose circle 1.61", 1.61), ("ringDance chord 1.25 x 1.4 = 1.75", 1.75),
        ]
        var lines = ["pair\taxis\ttouchDistance_cm\tbodyOnlyTouchDistance_cm\t" + spacings.map { $0.0 }.joined(separator: "\t")]
        for (label, cast) in Self.pairs {
            for axis in ["x", "z"] {
                let d = makeDuo(cast: cast, positions: [SIMD2(-1.5, 0.6), SIMD2(1.5, 0.6)])
                Self.keep.append(d)
                func place(_ dist: Float) -> Float {
                    let u: SIMD2<Float> = axis == "x" ? SIMD2(1, 0) : SIMD2(0, 1)
                    d.place([SIMD2(0, 0.6) - u * dist / 2, SIMD2(0, 0.6) + u * dist / 2])
                    for _ in 0..<40 { d.tick() }
                    let S = d.contactSurfaces()
                    return BruteForceContactMetric.skinGap(S[0], S[1])
                }
                let far = place(3.0)
                let touch = 3.0 - far
                let bodyTouch = 3.0 - BruteForceContactMetric.skinGap(d.contactSurfaces(bodyOnly: true)[0], d.contactSurfaces(bodyOnly: true)[1])
                var row = [label, axis, Self.cm(touch), Self.cm(bodyTouch)]
                for (_, s) in spacings { row.append(Self.cm(place(s))) }
                lines.append(row.joined(separator: "\t"))
            }
        }
        if let dir = Self.outDir {
            try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
            try? (lines.joined(separator: "\n") + "\n").write(toFile: dir + "/static_spacing.tsv", atomically: true, encoding: .utf8)
        }
        for l in lines { MotionLog.write("CONTACT static " + l) }
        if !Self.enforce { throw XCTSkip("pending engine: static spacing table written (BEFORE)") }
    }

    /// Last: the worst-frame table and a 6-frame strip per emote (the worst species pair, centred on its worst frame). Needs CONTACT_OUT.
    func testZ_strips() throws {
        guard let dir = Self.outDir else { throw XCTSkip("CONTACT_OUT not set") }
        let rs = Self.all.filter { $0.started }
        guard !rs.isEmpty else { throw XCTSkip("no measured runs in this process (run the whole class)") }
        var worst: [String: Result] = [:]
        for r in rs where r.minGap < (worst[r.name]?.minGap ?? .infinity) { worst[r.name] = r }
        let ordered = worst.values.sorted { $0.minGap < $1.minGap }
        let table = (["emote\tcast\tminGap_cm\tat_s\tpair\twhere\tstance\tstanceMedian_cm"] + ordered.map { "\($0.name)\t\($0.cast)\t\(Self.cm($0.minGap))\t\(String(format: "%.1f", $0.minGapT))\t\($0.minGapPair)\t\($0.minGapPhase)\t\($0.stance.rawValue)\t\($0.stanceMedian.map(Self.cm) ?? "-")" }).joined(separator: "\n") + "\n"
        try? table.write(toFile: dir + "/worst_frames.tsv", atomically: true, encoding: .utf8)
        guard let device = MTLCreateSystemDefaultDevice() else { throw XCTSkip("no Metal (worst_frames.tsv written)") }
        let stripsDir = dir + "/strips"
        try FileManager.default.createDirectory(atPath: stripsDir, withIntermediateDirectories: true)
        let limit = Int(ProcessInfo.processInfo.environment["CONTACT_STRIPS"] ?? "") ?? 99
        for r in ordered.prefix(limit) {
            guard let entry = (Self.pairEntries + Self.groupEntries).first(where: { $0.name == r.name }) else { continue }
            let cast = (Self.pairs + Self.trios).first(where: { $0.0 == r.cast })!.1
            let fw = r.minGapFrame
            let plan = [-66, -42, -24, 0, 18, 42].map { max(0, fw + $0) }
            let (res, cells) = run(entry, cast: cast, castName: r.cast, plan: plan, device: device)
            guard cells.count == plan.count else { MotionLog.write("CONTACT strip \(r.name): only \(cells.count) cells"); continue }
            let title = String(format: "%@ | %@ | worst gap %@ cm at %.1f s (%@, %@) | frames %@", r.name, r.cast, Self.cm(r.minGap), r.minGapT, r.minGapPair, r.minGapPhase, plan.map { String(format: "%.1f", Float($0) / 60) }.joined(separator: " "))
            try? Self.stripImage(title: title, cells: cells).write(to: URL(fileURLWithPath: stripsDir + "/" + Self.fileName(r.name) + ".png"))
            _ = res
        }
    }

    static func fileName(_ s: String) -> String { String(s.map { $0.isLetter || $0.isNumber ? $0 : "_" }) }

    static func stripImage(title: String, cells: [UIImage]) -> Data {
        let cw = Int(cells[0].size.width), ch = Int(cells[0].size.height), cols = 3, rows = (cells.count + cols - 1) / cols, pad = 4, label = 28
        let sw = cols * (cw + pad) + pad, sh = rows * (ch + pad) + pad + label
        let fmt = UIGraphicsImageRendererFormat(); fmt.scale = 1
        let img = UIGraphicsImageRenderer(size: CGSize(width: sw, height: sh), format: fmt).image { ctx in
            UIColor(white: 0.12, alpha: 1).setFill(); ctx.fill(CGRect(x: 0, y: 0, width: sw, height: sh))
            (title as NSString).draw(at: CGPoint(x: 8, y: 6), withAttributes: [.font: UIFont.boldSystemFont(ofSize: 14), .foregroundColor: UIColor.white])
            for (i, c) in cells.enumerated() { c.draw(in: CGRect(x: pad + (i % cols) * (cw + pad), y: label + pad + (i / cols) * (ch + pad), width: cw, height: ch)) }
        }
        return img.pngData()!
    }
}
