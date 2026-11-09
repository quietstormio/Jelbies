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
    func contactSurfaces(bodyOnly: Bool = false, triangles: Bool = false) -> [ContactSurface] {
        skinForContact()
        return contactSurfacesNoSkin(bodyOnly: bodyOnly, triangles: triangles)
    }
    /// Skins every body like the stage does (+ the clip pass) into `dyn`. `contactSurfacesNoSkin` / `contactHandTips` then read the SAME frame (skin once, measure the body-only and the whole skin from it).
    func skinForContact() {
        var jobs: [JellyParallel.SkinJob] = []
        for (i, r) in lab.rigs.enumerated() {
            r.skinner.update(x: r.sim.x, index: MotionRig.renderMesh.index, into: dyn[i])
            jobs.append(JellyParallel.SkinJob(skinner: r.skinner, sim: r.sim, dst: dyn[i], id: i))
        }
        FeatureClip.apply(jobs: jobs)
    }
    /// The drawn hand tips of body i (world): the FIRST vertex of each drawn arm capsule (the pole of the tip sphere). Empty when the arms are not drawn. Reads the last `skinForContact`.
    func contactHandTips(_ i: Int) -> [SIMD3<Float>] {
        let sk = lab.rigs[i].skinner
        guard sk.armCapsulesActive else { return [] }
        return (0..<2).map { s in let v = sk.armFirst[s]; return SIMD3(dyn[i][6 * v], dyn[i][6 * v + 1], dyn[i][6 * v + 2]) }
    }
    /// Every vertex of body i's two arm capsules (hand-on-hand).
    func contactArmPoints(_ i: Int) -> [SIMD3<Float>] {
        let sk = lab.rigs[i].skinner
        guard sk.armCapsulesActive else { return [] }
        return (0..<2).flatMap { s in (sk.armFirst[s]..<(sk.armFirst[s] + ArmCapsule.vertexCount)).map { v in SIMD3(dyn[i][6 * v], dyn[i][6 * v + 1], dyn[i][6 * v + 2]) } }
    }
    func contactSurfacesNoSkin(bodyOnly: Bool = false, triangles: Bool = false) -> [ContactSurface] {
        return lab.rigs.indices.map {
            let ranges = bodyOnly ? [0..<eggLimit] : contactRanges($0)
            return triangles ? ContactSurface(root: lab.rigs[$0].root, dyn: UnsafePointer(dyn[$0]), ranges: ranges, index: MotionRig.renderMesh.index)
                             : ContactSurface(root: lab.rigs[$0].root, dyn: UnsafePointer(dyn[$0]), ranges: ranges)
        }
    }
}

// MARK: - the catalogue (mirrors docs/CONTACT_EMOTES.md)

enum ContactClass: String { case touching, proximity }
enum ContactScenario { case social(SocialKind), lie(IdleKind), sleepPair }
enum ContactProp { case none, ball, beanbag, loveseat }
extension ContactScenario { var kind: SocialKind? { if case .social(let k) = self { return k }; return nil } }

struct ContactEntry {
    var name: String
    var scenario: ContactScenario
    var stance: ContactClass
    var props: ContactProp = .none
    var maxSec: Float = 70
    /// true = start from the lab's default spots (1.7 apart: already inside a boop's / greet's window); false = 3 apart, so the walk-up happens.
    var near = false
    /// true = the emote IS the touch: the session ends the moment the skins meet (boop). It has no hold to take a median of; the bar reads the gap at the touch frames instead.
    var momentary = false
}

@MainActor
final class ContactPolishTests: XCTestCase {
    typealias Duo = FeatureClipTests.Duo

    // MARK: config

    static let outDir: String? = { let d = ProcessInfo.processInfo.environment["CONTACT_OUT"] ?? ""; return d.isEmpty ? nil : d }()
    static let enforce = ProcessInfo.processInfo.environment["CONTACT_ENFORCE"] == "1"
    /// CONTACT_ONLY=boop,bump,... runs just those emotes (names as in the catalogue; a quick iteration loop). Unset = all.
    static let only: Set<String>? = { let v = ProcessInfo.processInfo.environment["CONTACT_ONLY"] ?? ""; return v.isEmpty ? nil : Set(v.split(separator: ",").map(String.init)) }()
    /// CONTACT_TRACE=boop,... also writes trace_<emote>_<cast>.tsv (t, phase, skin gap, root distance, standing) into CONTACT_OUT: the timeline for debugging a stance.
    /// CONTACT_TRACE_COLS=1 (needs CONTACT_TRACE): the engine's own per-tick stamps (ContactTrace) become extra columns in the trace tsv; the Lab's wall counters too.
    static let traceCols = ProcessInfo.processInfo.environment["CONTACT_TRACE_COLS"] == "1"
    static let traced: Set<String> = Set((ProcessInfo.processInfo.environment["CONTACT_TRACE"] ?? "").split(separator: ",").map(String.init))
    static func wanted(_ e: ContactEntry) -> Bool { only.map { $0.contains(e.name) } ?? true }
    /// 0 Bob, 1 Pip, 2 Moss, 3 Lavender, 4 Teddy, 5 Pearl.
    static let names = OnePieceInvariantTests.characters.map { $0.0 }
    static let pairs: [(String, [Int])] = [("Bob+Teddy", [0, 4]), ("Teddy+Pearl", [4, 5]), ("Lavender+Pip", [3, 1]), ("Pip+Teddy", [1, 4]), ("Moss+Pearl", [2, 5])]
    static let trios: [(String, [Int])] = [("Pip+Lavender+Teddy", [1, 3, 4]), ("Pip+Pearl+Moss", [1, 5, 2]), ("Bob+Teddy+Pearl", [0, 4, 5])]
    /// The contact sounds (SFX raw values) the catalogue talks about.
    static let contactSounds: Set<String> = ["squish", "boop", "wobble", "highfive_boop", "emote_spinhug", "conga_tick", "ring_chime"]
    static let touchOn: Float = 0.01, touchOff: Float = 0.03
    /// A step BACK after the first touch is >= ~10 cm; the stance's own approach step opens the skins by up to ~4 cm by design (measured: hum 3.5-4.3, nuzzle 3.7). Past 5 cm the pair has really parted and walks in again.
    static let retreatMax: Float = 0.05
    /// The emotes whose HAND must end on the partner's skin (user rule 2): the hand-tip gap is measured for these.
    static let handKinds: Set<SocialKind> = [.boop, .highFive, .cheekSquish, .whisperGiggle]
    /// The hand gap of a frame: the least over every ordered pair (tip of i against the whole drawn skin of j) of `BruteForceContactMetric.handGap`; `farApart` when no hand is near anybody.
    static func handGapNow(_ d: Duo, _ S: [ContactSurface], n: Int) -> Float {
        var m = Float.infinity
        for i in 0..<n { for tip in d.contactHandTips(i) { for j in 0..<n where j != i { m = min(m, BruteForceContactMetric.handGap(tip: tip, against: S[j])) } } }
        return m.isFinite ? m : BruteForceContactMetric.farApart
    }
    static func handHandNow(_ d: Duo, n: Int) -> Float {
        var m = Float.infinity
        for i in 0..<n { for tip in d.contactHandTips(i) { for j in 0..<n where j != i { m = min(m, BruteForceContactMetric.handToHand(tip: tip, armPoints: d.contactArmPoints(j))) } } }
        return m.isFinite ? m : BruteForceContactMetric.farApart
    }
    /// Start spots 2.9 apart (pairs) so the walk-up to the stance really happens; the third is further back.
    static let farStarts: [SIMD2<Float>] = [SIMD2(-1.5, 0.6), SIMD2(1.35, 0.9), SIMD2(0.0, 2.4)]
    nonisolated(unsafe) static var keep: [AnyObject] = []
    nonisolated(unsafe) static var all: [Result] = []

    static func e(_ n: String, _ k: SocialKind, _ s: ContactClass, props: ContactProp = .none, sec: Float = 70) -> ContactEntry { ContactEntry(name: n, scenario: .social(k), stance: s, props: props, maxSec: sec) }
    /// Pair emotes (rig 0 starts it with rig 1): the CURATED entries (a name, a class, a prop, a time cap). `pairEntries` adds an automatic entry for any SocialKind nobody wrote one for.
    static let curatedPairEntries: [ContactEntry] = [
        ContactEntry(name: "boop", scenario: .social(.boop), stance: .touching, momentary: true), e("squabble", .squabble, .touching), e("nuzzle", .nuzzle, .touching), e("sitTogether", .sitTogether, .touching),
        e("sneak", .sneak, .touching), e("chestBump", .chestBump, .touching), e("highFive", .highFive, .touching), e("cheekSquish", .cheekSquish, .touching),
        e("bellyBounce", .bellyBounce, .touching), e("backToBack", .backToBack, .touching), e("cuddleLean", .cuddleLean, .touching),
        e("ringAround", .ringAround, .touching), e("swayHug", .swayHug, .touching), e("whisperGiggle", .whisperGiggle, .touching), e("spinHug", .spinHug, .touching),
        ContactEntry(name: "tag", scenario: .social(.tag), stance: .touching, momentary: true), ContactEntry(name: "chase", scenario: .social(.chase), stance: .touching, maxSec: 40, momentary: true),          // (tag / chase: the emote IS a soft bump in a run: its hold step is the chase itself, so a "hold median" read 59-94 cm of running; judged at the touch frames like a boop)
        ContactEntry(name: "greet", scenario: .social(.greet), stance: .proximity, near: true), e("look", .look, .proximity), e("follow", .follow, .proximity), e("zoomies", .zoomies, .proximity, sec: 40), e("dance", .dance, .proximity),
        e("keepAway", .keepAway, .proximity, sec: 30), e("line", .line, .proximity), e("twirl", .twirl, .proximity), e("hopAlong", .hopAlong, .proximity), e("littleRace", .littleRace, .proximity),
        e("leapfrog", .leapfrog, .proximity), e("peekaboo", .peekaboo, .proximity), e("mirrorDance", .mirrorDance, .proximity), e("danceOff", .danceOff, .proximity), e("shyWave", .shyWave, .proximity),
        e("pass (ball)", .pass, .proximity, props: .ball, sec: 80), e("bagSit (beanbag)", .bagSit, .touching, props: .beanbag), e("cuddle (loveseat)", .cuddle, .touching, props: .loveseat),
        ContactEntry(name: "lieDown pair (LieClear)", scenario: .lie(.lieDown), stance: .touching, maxSec: 8),
        ContactEntry(name: "flop pair (LieClear)", scenario: .lie(.flop), stance: .touching, maxSec: 8),
        ContactEntry(name: "sleep pile", scenario: .sleepPair, stance: .touching, maxSec: 45),
    ]
    /// Group emotes (three Jelbies; rig 0 starts it with rig 1, the others join).
    static let curatedGroupEntries: [ContactEntry] = [
        e("groupHug", .groupHug, .touching), e("groupCheer", .groupCheer, .proximity), e("conga", .conga, .proximity), e("circleDance", .circleDance, .touching),
        e("congaLine", .congaLine, .proximity), e("ringDance", .ringDance, .proximity),
    ]

    /// USER RULE 3 (2026-11-04): every interactive emote follows the same formula, and a new one is measured WITHOUT anybody remembering to add it: every SocialKind that no curated entry covers gets an
    /// automatic entry here (class from its ContactStance row; proximity when it has none). `testEveryInteractiveKindIsInTheHarness` fails while a kind only has an automatic entry (it still runs, but it needs a
    /// curated one: a name, a scene row), `testEveryInteractiveKindHasAStanceRow` fails while it has no table row.
    static let curatedKinds: Set<SocialKind> = Set((curatedPairEntries + curatedGroupEntries).compactMap { if case .social(let k) = $0.scenario { return k }; return nil })
    static let autoEntries: [ContactEntry] = SocialKind.allCases.filter { !curatedKinds.contains($0) }.map { k in
        e(k.rawValue, k, ContactStance.entry(k)?.cls == .touching ? .touching : .proximity)
    }
    /// A HOLDING stance (the pair stays pressed from the hold step on: hum, nuzzle, cheekSquish ...) as opposed to a pressing one (a bump / boop: approach, press, part): from the table, never a list here.
    static func holdsStance(_ e: ContactEntry) -> Bool {
        guard !e.momentary, let k = kindOf(e), let st = ContactStance.entry(k), st.cls == .touching else { return false }
        return st.steps.contains { $0.target == ContactStance.hold } && !st.steps.contains { $0.target == ContactStance.ready && !$0.onlySeparate }          // (`near` and `ready` are both 1.2 cm: the pressing approach is the step that is not onlySeparate)
    }
    static func kindOf(_ e: ContactEntry) -> SocialKind? { if case .social(let k) = e.scenario { return k }; return nil }
    static let pairEntries: [ContactEntry] = curatedPairEntries + autoEntries.filter { !($0.scenario.kind?.isGroup ?? false) }
    static let groupEntries: [ContactEntry] = curatedGroupEntries + autoEntries.filter { $0.scenario.kind?.isGroup ?? false }

    // MARK: results

    struct Result {
        var name = "", cast = "", stance = ContactClass.proximity, kind = ""
        var started = false, completed = false
        var seconds: Float = 0, frames = 0
        var minGap: Float = .infinity, minGapT: Float = 0, minGapFrame = 0, minGapPair = "", minGapPhase = ""
        var stance01: [Float] = []                      // gaps of the standing frames inside the session
        /// The hold step of the stance table, EVERY sampled frame of it (moving or not: a press is short and dynamic): the real hold, however short (2026-11-04).
        var holdGaps: [Float] = []
        var momentary = false
        /// The skin gap at the frame each touch event fired (exact frame, not the 2-frame sampling): what a momentary touch (boop) is judged on.
        var touchGaps: [Float] = []
        var lastPlantCm: Float? = nil, stops = 0          // the gap at the LAST stop before the touch, and how many times the pair stopped (walk-stop-walk = more than one)
        var arrivalFrame = -1, firstTouchFrame = -1
        /// Was the arrival stop a TRUE stop, or a pause before a turn in place? The largest heading change (deg) of either body between the arrival frame and the first touch, and the seconds between them.
        var arrivalTurnDeg: Float? = nil, arrivalToTouchS: Float? = nil
        var arrivalCm: Float? = nil, arrivalT: Float = 0          // the skin gap at the frame the last stance step planted (ArrivalTracker), metres
        var worstReach: Float = 0, worstLag: Float = 0          // at the worst overlap frame: the longest reach of a drawn body from its centroid, the largest sim-centroid vs brain-root distance (m)
        var footMin: Float = .infinity                  // the least FOOTPRINT gap over the frames where the support gap read an overlap (what the eye sees; support is the strict lower bound)
        var touchFrames = 0
        /// WHAT THE RUN SAW (round 3): the skin gap at the LAST sampled frame (a proximity emote whose min is the start distance still shows where the pair ended up: stalled, drifted closer or apart) and the session phases reached
        /// (a follow / line whose trailing phase never ran shows as one phase). Both are context columns: no bar reads them.
        var endGap: Float? = nil
        /// STUTTER-STEP ARRIVAL (holding stances only): after the skins first touched and before the hold began, the largest skin gap the pair reached (m). A pair that touches, backs off and walks in again (cheekSquish: touches at
        /// 1.6 s in the drive's own walk-up, then the stance walk opens 55 cm and returns) reads as a bug even when the hold itself is perfect. 0 = never backed off.
        var retreat: Float = 0
        var phases: Set<Int> = []
        /// The BODY-ONLY support gap (the egg: no arms / ears / feet beans), the min over the run, the hold step's frames, and at each touch-event frame. The whole-skin `minGap` includes the arms: a pair can read
        /// touching on a hand or a tail while the bodies stand apart (backToBack on Pip), and boop's bodies must stand at hand reach.
        var minGapBody: Float = .infinity
        var holdGapsBody: [Float] = []
        var bodyTouch: [Float] = []
        /// THE HAND GAP (user rule 2; hand emotes only): the least over all drawn hand tips of the signed tip-to-the-other-skin gap, the min over the run, at each touch-event frame, and the hold step's frames.
        /// handHand: highFive's unsigned closest approach of a tip to the other body's arm vertices at each touch frame.
        var handMin: Float = .infinity
        var handTouch: [Float] = []
        var handHold: [Float] = []
        var handHand: [Float] = []
        /// How many drawn hand tips each body has at the touch frames, per body ("2,0"): a body whose arms are not drawn as capsules at that moment (Teddy's rest pose) has no hand to measure, so its hand gap is Bob-side only.
        var handTips: [String] = []
        var episodes = 0, sndInEpisode: [Int] = [], hapInEpisode: [Int] = [], sndOutside = 0, hapOutside = 0
        var sndGapMin: Float = .infinity, sndGapMax: Float = -.infinity
        var boopEvents = 0
        var featRaw: Float = -1, featClip: Float = -1, limbRaw: Float = -1, limbClip: Float = -1, eggPen: Float = -1
        var sounds: [String: Int] = [:], haps: [String: Int] = [:]
        var stanceMedian: Float? { stance01.count >= 10 ? stance01.sorted()[stance01.count / 2] : nil }
        /// Median of the hold step's frames; nil under `minHold` samples (never a hold from one frame).
        static let minHold = 3
        var holdMedian: Float? { holdGaps.count >= Self.minHold ? holdGaps.sorted()[holdGaps.count / 2] : nil }
        var holdTouchN: Int { holdGaps.filter { $0 <= 0.005 }.count }
        var holdMedianBody: Float? { holdGapsBody.count >= Self.minHold ? holdGapsBody.sorted()[holdGapsBody.count / 2] : nil }
        var handHoldMedian: Float? { handHold.count >= Self.minHold ? handHold.sorted()[handHold.count / 2] : nil }
        /// The sounds per touch as ONE value for a roll-up: "1" = every touch fired exactly one contact sound; "-" = no touch; else the distinct counts ("0,2").
        var sndPerTouch: String {
            if sndInEpisode.isEmpty { return "-" }
            let u = Set(sndInEpisode)
            return u == [1] ? "1" : u.sorted().map(String.init).joined(separator: ",")
        }
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

    static let traceHeader = "\tevent" + ["a", "b"].map { w in ["act", "idle", "script", "feetAct", "gaitBusy", "dRootToward_mm", "step", "e_mm", "c_mm", "m_mm", "nudge", "want", "leanTrim", "walkRetarget", "walkGeom", "shuffle", "resolveCalls", "resolvePass", "resolvePush_mm", "brainDist", "pitch", "roll", "squash", "kick", "reachToward", "airBoth", "flapHop", "simMinusBrain_mm", "simAlong_mm", "feetMidAlong_mm", "stepRoot0Along_mm", "stepLive", "yawDeg", "anchorAlong_mm", "profileRootAlong_mm", "profileValid"].map { "\(w)_\($0)" }.joined(separator: "\t") }.map { "\t" + $0 }.joined()
    /// One row of the engine's per-tick stamps for the first two rigs (ContactTrace).
    static func traceRow(_ rigs: [MotionRig], _ lab: SocialTests.Lab, _ pre: [SIMD2<Float>], _ ev: [String], _ mg: Float) -> String {
        var out = "\t" + ev.joined(separator: ";")
        for i in 0..<2 {
            let b = rigs[i].brain, o = rigs[1 - i].brain
            let r = ContactTrace.rec[b.steerID] ?? ContactTrace.Rec()
            let toward = simd_normalize(rigs[1 - i].root - rigs[i].root + SIMD2(1e-6, 0))
            let dRoot = simd_dot(rigs[i].root - pre[i], toward) * 1000
            var sc = "none"; switch b.script { case .none: sc = "none"; case .walk: sc = "walk"; default: sc = "other" }
            _ = o
            let st = lab.resolveStat[i]
            out += String(format: "\t%@\t%@\t%@\t%d\t%d\t%.1f\t%@\t%.1f\t%.1f\t%.1f\t%@\t%.3f\t%.3f\t%@\t%@\t%@\t%d\t%d\t%.1f", "\(b.activity)", b.idleState.kind.map { "\($0)" } ?? "nil", sc, b.feet.active ? 1 : 0, b.gait.isBusy ? 1 : 0, dRoot, r.step, r.e * 1000, r.c * 1000, r.m * 1000, r.nudge, r.want, b.socialBook.leanTrim, r.walk, r.tgt, r.shuffle, st.calls, st.pass, st.push * 1000)
            let u2 = simd_normalize(o.position - b.position + SIMD2(1e-6, 0))
            out += String(format: "\t%.3f\t%.3f\t%.3f\t%.3f\t%.2f\t%.3f\t%d\t%d\t%.1f", simd_distance(b.position, o.position), b.socialBook.pitch, b.socialBook.roll, b.socialBook.squash, b.jellyKick, ContactField.supportExt(b.steerID, u2) ?? -1, b.airBothFeet ? 1 : 0, b.flapHop.active ? 1 : 0, simd_distance(rigs[i].root, b.position) * 1000)
            let fm = (b.feet.pos.count > 1) ? (b.feet.pos[0] + b.feet.pos[1]) * 0.5 : b.position
            out += String(format: "\t%.1f\t%.1f\t%.1f\t%d\t%.1f", simd_dot(rigs[i].root - b.position, u2) * 1000, simd_dot(fm - b.position, u2) * 1000, simd_dot(b.stepRoot0 - b.position, u2) * 1000, b.stepLive ? 1 : 0, b.yaw * 57.2958)
            let an = rigs[i].sim.attractor.anchor
            out += String(format: "\t%.1f\t%.1f\t%d", simd_dot(SIMD2(an.x, an.z) - b.position, u2) * 1000, simd_dot(ContactField.root(b.steerID) - b.position, u2) * 1000, ContactField.isValid(b.steerID) ? 1 : 0)
        }
        return out
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
        // ORDER INDEPENDENCE (round 3): tag measured -0.9 cm alone and -25.2 cm after cheekSquish in the same process, because the previous run's profiles (keyed by steerID) and clip eggs were still in the statics. Every run starts clean.
        ContactField.reset(); FeatureClip.eggs = []
        let n = cast.count
        var res = Result(); res.momentary = e.momentary; res.name = e.name; res.cast = castName; res.stance = e.stance
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
            d.place([SIMD2(-0.8, 0.6), SIMD2(0.8, 0.6)])          // (1.6 apart: clear of each other, so the first frames are not a harness-made overlap)
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
        var curEpisode = -1, evPrev = 0, evDelta = 0
        var sndSeen = 0, hapSeen = 0
        var secondSleeper = false
        var trace: [String] = []
        if Self.traceCols { ContactTrace.on = true }
        defer { ContactTrace.on = false }
        var arrival = ArrivalTracker()
        let handKind: Bool = { if case .social(let k) = e.scenario { return Self.handKinds.contains(k) }; return false }()
        var holdTouched = false, touchedPre = false, firstHoldFrame = -1
        let holds = Self.holdsStance(e)
        var firstTouchFrame = -1
        var yawHist: [[Float]] = []
        var wasWalking = [Bool](repeating: false, count: n)
        var arriveEv = [String](repeating: "", count: n)
        let maxF = Int(e.maxSec * 60)
        var frame = 0
        while frame < maxF {
            tap.frame = frame
            if Self.traceCols {
                ContactTrace.rec = [:]
                for i in 0..<8 { d.lab.resolveStat[i] = (0, 0, 0) }
                if frame == 0 { for i in 0..<n { wasWalking[i] = false } }
            }
            let preRoots = rigs.map { $0.root }
            d.tick()
            yawHist.append(rigs.prefix(n).map { $0.brain.yaw })
            if Self.traceCols {
                for i in 0..<n {
                    var isWalk = false; if case .walk = rigs[i].brain.script { isWalk = true }
                    if wasWalking[i], !isWalk, let g = ContactField.gap(rigs[0].brain.steerID, rigs[1].brain.steerID, features: false) { arriveEv[i] = String(format: "ARRIVE%d gap=%.1fcm", i, g * 100) }
                    wasWalking[i] = isWalk
                }
            }
            // the arrival residual: the skin gap at the first frame everybody who walked in has stopped stepping (only for the social emotes: the others have no stance walk)
            if case .social = e.scenario, !arrival.closed {
                let stepping = rigs.prefix(n).contains { r in
                    if r.brain.stepLive || r.brain.gait.isBusy { return true }
                    if case .walk = r.brain.script { return true }
                    return false
                }
                var g: Float? = nil
                if arrival.wantsGap(anyStepping: stepping) { g = Self.pairMin(d.contactSurfaces(), e: e, n: n).gap }
                arrival.feed(frame: frame, anyStepping: stepping, gap: g)
                if let ag = arrival.gap { res.arrivalCm = ag; res.arrivalT = Float(arrival.frame ?? frame) / 60; res.arrivalFrame = arrival.frame ?? frame; res.lastPlantCm = arrival.last; res.stops = arrival.settles.count }
            }
            if res.episodes > 0, firstTouchFrame < 0 { firstTouchFrame = frame }
            let closeRef = holds ? firstHoldFrame : firstTouchFrame          // (a holding stance's arrival ends 1 s into its HOLD: a first touch in the drive's own walk-up that is then backed off from is the stutter, `retreat`, not the arrival)
            if closeRef >= 0, frame >= closeRef + 60 { arrival.close() }          // (1 s after the first touch the approach is over: a stop that CONFIRMS later is the hold, not the arrival; the last plant usually comes <= 0.4 s before the touch)
            // THE touch event: the gate's own (contactTick: fires at skin gap <= +0.5 cm, re-armed past +3 cm). One episode per event; its sound / haptic are the ones requested in the same frame.
            let evNow = rigs.reduce(0) { $0 + $1.brain.contactEvents }
            evDelta = evNow - evPrev; evPrev = evNow
            if evDelta > 0, case .social = e.scenario {
                let St = d.contactSurfaces(), Sb = d.contactSurfacesNoSkin(bodyOnly: true)          // (skinned once: the whole skin with the arms, and the egg alone)
                let gt = Self.pairMin(St, e: e, n: n).gap, gb = Self.pairMin(Sb, e: e, n: n).gap
                let hg: Float? = handKind ? Self.handGapNow(d, St, n: n) : nil, hh: Float? = handKind ? Self.handHandNow(d, n: n) : nil
                for _ in 0..<evDelta {
                    res.touchGaps.append(gt); res.bodyTouch.append(gb)
                    if gt < res.minGap { res.minGap = gt; res.minGapT = Float(frame) / 60; res.minGapFrame = frame; res.minGapPair = "touch-event"; res.minGapPhase = "\(a.brain.socialKind.map { $0.rawValue } ?? "-")/ph\(a.brain.social?.phase ?? -1)" }          // (the 2-frame sampling can miss the deepest frame: the exact touch frame counts too)
                    if res.firstTouchFrame < 0 { res.firstTouchFrame = frame }
                    if let hg { res.handTouch.append(hg) }
                    if let hh { res.handHand.append(hh) }
                    if handKind { res.handTips.append((0..<n).map { String(d.contactHandTips($0).count) }.joined(separator: ",")) }
                    if handKind, Self.traced.contains(e.name) {          // (the hand numbers of the touch frame, to tell a hand that is not reaching from a measuring artefact)
                        let tips = (0..<n).map { d.contactHandTips($0) }, arms = (0..<n).map { d.contactArmPoints($0).count }
                        MotionLog.write("CONTACT handdebug \(e.name) \(castName) f\(frame) tips=\(tips.map { $0.map { String(format: "(%.2f,%.2f,%.2f)", $0.x, $0.y, $0.z) } }) armPts=\(arms) roots=\(rigs.prefix(n).map { String(format: "(%.2f,%.2f)", $0.root.x, $0.root.y) }) hg=\(hg.map { String($0) } ?? "-") hh=\(hh.map { String($0) } ?? "-")")
                    }
                }
            }
            if evDelta > 0 { for _ in 0..<evDelta { res.episodes += 1; res.sndInEpisode.append(0); res.hapInEpisode.append(0) }; curEpisode = res.episodes - 1 }
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
            var activePhase = true          // the stance median only counts the frames where the table is HOLDING the touch (a walk-up, a run, a part are not the stance)
            if case .social(let k) = e.scenario, let st = ContactStance.entry(k), st.cls == .touching, let ph = a.brain.social?.phase { activePhase = st.step(at: ph)?.target == ContactStance.hold }
            if sampled || (plan?.contains(frame) ?? false) {
                let S = d.contactSurfaces()
                let Sb = d.contactSurfacesNoSkin(bodyOnly: true)
                let mgb = Self.pairMin(Sb, e: e, n: n).gap
                let hg: Float? = handKind ? Self.handGapNow(d, S, n: n) : nil
                let pm = Self.pairMin(S, e: e, n: n)
                let mg = pm.gap, mp = pm.pair.map { "\(Self.names[cast[$0.0]])-\(Self.names[cast[$0.1]])" } ?? ""
                if sampled { res.endGap = mg; if let ph = a.brain.social?.phase { res.phases.insert(ph) } }
                if sampled, mg < -0.01 {          // a support overlap: what does the footprint (the eye's view) say about the same frame?
                    let T = d.contactSurfaces(triangles: true)
                    var fm = Float.infinity
                    for i in 0..<n { for j in (i + 1)..<n { fm = min(fm, BruteForceContactMetric.footprintGap(T[i], T[j])) } }
                    res.footMin = min(res.footMin, fm)
                    if mg <= res.minGap {          // the worst frame: how far each drawn body reaches from its centroid, and how far the sim body lags its brain (a smeared / lagging body is not an axis artefact)
                        res.worstReach = S.prefix(n).map { s in s.points.reduce(Float(0)) { max($0, simd_length(SIMD2($1.x, $1.z) - s.root)) } }.max() ?? 0
                        res.worstLag = (0..<n).map { simd_distance(rigs[$0].root, rigs[$0].brain.position) }.max() ?? 0
                    }
                }
                if sampled && mg < 8 {
                    gapNow = mg
                    res.minGapBody = min(res.minGapBody, mgb)
                    if let hg, hg < 8 { res.handMin = min(res.handMin, hg) }
                    if mg < res.minGap { res.minGap = mg; res.minGapT = Float(frame) / 60; res.minGapFrame = frame; res.minGapPair = mp
                        res.minGapPhase = "\(a.brain.socialKind.map { $0.rawValue } ?? "-")/ph\(a.brain.social?.phase ?? -1)/idle \(a.brain.idleState.kind.map { "\($0)" } ?? "-")" }
                    if Self.traced.contains(e.name) { trace.append(String(format: "%.2f\t%d\t%.1f\t%.3f\t%d\t%@", Float(frame) / 60, a.brain.social?.phase ?? -1, mg * 100, simd_distance(a.root, b.root), still ? 1 : 0, tap.sounds.suffix(1).map { $0.1 }.joined()) + Self.traceExtra(rigs, S, n) + (Self.traceCols ? Self.traceRow(rigs, d.lab, preRoots, arriveEv, mg) : "")) ; if Self.traceCols { arriveEv = [String](repeating: "", count: n) } }
                    if mg <= Self.touchOn { res.touchFrames += 1 }
                    if holds, !holdTouched { if mg <= 0.005 { touchedPre = true } else if touchedPre { res.retreat = max(res.retreat, mg) } }
                    if still, inSession, activePhase, mg < 2.2 { res.stance01.append(mg) }
                    // the REAL hold: inside the table's hold step, from the first frame the skins touch (<= +0.5 cm) to the end of the step. (The hold step of a press is entered while the walker is still
                    // closing in: those frames are the arrival, not the hold.)
                    if inSession, activePhase, case .social(let k) = e.scenario, ContactStance.entry(k)?.cls == .touching {
                        if mg <= 0.005 { if !holdTouched { firstHoldFrame = frame }; holdTouched = true }
                        if holdTouched { res.holdGaps.append(mg); res.holdGapsBody.append(mgb); if let hg, hg < 8 { res.handHold.append(hg) } }
                    }
                    // episodes
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
                    _ = f; if evDelta > 0, curEpisode >= 0 { res.sndInEpisode[curEpisode] += 1 } else { res.sndOutside += 1 }
                }
            }
            while hapSeen < tap.haps.count {
                let (f, name) = tap.haps[hapSeen]; hapSeen += 1
                res.haps[name, default: 0] += 1
                _ = f; if evDelta > 0, curEpisode >= 0 { res.hapInEpisode[curEpisode] += 1 } else { res.hapOutside += 1 }
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
        if res.arrivalFrame >= 0, res.firstTouchFrame >= res.arrivalFrame, res.firstTouchFrame < yawHist.count, res.arrivalFrame < yawHist.count {
            var worst: Float = 0
            for i in 0..<n { var dy = yawHist[res.firstTouchFrame][i] - yawHist[res.arrivalFrame][i]; while dy > .pi { dy -= 2 * .pi }; while dy < -.pi { dy += 2 * .pi }; worst = max(worst, abs(dy)) }
            res.arrivalTurnDeg = worst * 180 / .pi; res.arrivalToTouchS = Float(res.firstTouchFrame - res.arrivalFrame) / 60
        }
        if !trace.isEmpty, let dir = Self.outDir { try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true); try? (["t\tphase\tgap_cm\troot\tstill\tlastSound\tprofGap_cm\tprofRoot\treach0_cm\treach1_cm\tmeshSpan0_cm\tmeshSpan1_cm" + (Self.traceCols ? Self.traceHeader : "")] + trace).joined(separator: "\n").write(toFile: dir + "/trace_\(Self.fileName(e.name))_\(Self.fileName(castName)).tsv", atomically: true, encoding: .utf8) }
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

    /// The least support gap over all pairs of the cast, and the pair that has it (leapfrog: a hopper whose soles clear the lying body's top reads +0.5).
    static func pairMin(_ S: [ContactSurface], e: ContactEntry, n: Int) -> (gap: Float, pair: (Int, Int)?) {
        var mg = Float.infinity, mp: (Int, Int)? = nil
        for i in 0..<n { for j in (i + 1)..<n {
            var g = BruteForceContactMetric.skinGap(S[i], S[j])
            if e.name == "leapfrog", verticallyClear(S[i], S[j]) { g = max(g, 0.5) }          // (the hopper's soles are above the lying body's top: the plan view means nothing)
            if g < mg { mg = g; mp = (i, j) }
        } }
        return (mg, mp)
    }
    /// 3D check for a pass-over: one body's lowest point is above the other's highest (its soles clear the lying body's top).
    static func verticallyClear(_ a: ContactSurface, _ b: ContactSurface) -> Bool {
        guard let aLo = a.points.map(\.y).min(), let aHi = a.points.map(\.y).max(), let bLo = b.points.map(\.y).min(), let bHi = b.points.map(\.y).max() else { return false }
        return aLo >= bHi - 0.01 || bLo >= aHi - 0.01
    }
    /// Trace columns that tell a measurement artefact from a real overlap: the ENGINE's profile gap (ContactField, polygons of the skin at the brain roots) and root distance next to the harness gap; how far each drawn body reaches from its centroid, and the longest span between two of its vertices.
    static func traceExtra(_ rigs: [MotionRig], _ S: [ContactSurface], _ n: Int) -> String {
        let pg = ContactField.gap(rigs[0].brain.steerID, rigs[1].brain.steerID, features: false)
        let pr = simd_distance(ContactField.root(rigs[0].brain.steerID), ContactField.root(rigs[1].brain.steerID))
        func reach(_ s: ContactSurface) -> Float { s.points.reduce(Float(0)) { max($0, simd_length(SIMD2($1.x, $1.z) - s.root)) } }
        func span(_ s: ContactSurface) -> Float {
            guard let a = s.points.map({ $0.x }).min(), let b = s.points.map({ $0.x }).max(), let c = s.points.map({ $0.z }).min(), let d = s.points.map({ $0.z }).max() else { return 0 }
            return max(b - a, d - c)
        }
        return String(format: "\t%@\t%.3f\t%.1f\t%.1f\t%.1f\t%.1f", pg.map { String(format: "%.1f", $0 * 100) } ?? "-", pr, reach(S[0]) * 100, reach(S[1]) * 100, span(S[0]) * 100, span(S[1]) * 100)
    }
    static func cm(_ f: Float) -> String { f.isFinite ? String(format: "%.1f", f * 100) : "-" }
    /// A depth in cm; "-" when there was none to measure (the sentinel is -1 u).
    static func dcm(_ f: Float) -> String { f <= -0.99 ? "-" : cm(f) }
    /// A hand gap in cm; "far" = no skin / no hand near the tip (the metric's `farApart` 9 m).
    static func hcm(_ f: Float) -> String { f >= 8 ? "far" : cm(f) }
    static let header = ["emote", "cast", "stance", "started", "sec", "minGap_cm", "at_s", "pair", "where", "stanceMedian_cm", "stanceN", "touchFrames", "episodes", "snd_per_episode", "snd_outside", "hap_per_episode", "hap_outside",
                         "sndGap_cm(min..max)", "boopEv", "featRaw_cm", "featClip_cm", "limbRaw_cm", "limbClip_cm", "eggPen_cm", "sounds", "haptics",
                         "arrival_cm", "arrival_at_s", "lastPlant_cm", "stops", "holdMedian_cm", "holdN", "holdTouchN", "touchGaps_cm", "footMin_cm", "worstReach_cm", "worstLag_cm", "bar",
                         "minGapBody_cm", "holdMedianBody_cm", "snd_per_touch", "handMin_cm", "handTouch_cm", "handHoldMedian_cm", "handHand_cm", "bodyTouch_cm", "arrivalTurn_deg", "arrivalToTouch_s", "retreat_cm", "endGap_cm", "phases", "handTips"].joined(separator: "\t")
    static func row(_ r: Result) -> String {
        let bar = barFails(r)
        let a: [String] = [r.name, r.cast, r.stance.rawValue, r.started ? "yes" : "NO START", String(format: "%.1f", r.seconds), cm(r.minGap), String(format: "%.1f", r.minGapT), r.minGapPair, r.minGapPhase]
        let b: [String] = [r.stanceMedian.map(cm) ?? "-", "\(r.stance01.count)", "\(r.touchFrames)", "\(r.episodes)", r.sndInEpisode.map(String.init).joined(separator: ","), "\(r.sndOutside)", r.hapInEpisode.map(String.init).joined(separator: ","), "\(r.hapOutside)"]
        let sg: String = r.sndGapMin.isFinite ? "\(cm(r.sndGapMin))..\(cm(r.sndGapMax))" : "-"
        let c: [String] = [sg, "\(r.boopEvents)", dcm(r.featRaw), dcm(r.featClip), dcm(r.limbRaw), dcm(r.limbClip), dcm(r.eggPen)]
        let snd: String = r.sounds.sorted { $0.key < $1.key }.map { "\($0.key)x\($0.value)" }.joined(separator: " ")
        let hap: String = r.haps.sorted { $0.key < $1.key }.map { "\($0.key)x\($0.value)" }.joined(separator: " ")
        let arr: [String] = [r.arrivalCm.map(cm) ?? "-", r.arrivalCm == nil ? "-" : String(format: "%.1f", r.arrivalT), r.lastPlantCm.map(cm) ?? "-", "\(r.stops)"]
        let hold: [String] = [r.holdMedian.map(cm) ?? "-", "\(r.holdGaps.count)", "\(r.holdTouchN)", r.touchGaps.map(cm).joined(separator: ",")]
        let feet: [String] = [r.footMin.isFinite ? cm(r.footMin) : "-", r.worstReach > 0 ? cm(r.worstReach) : "-", r.worstReach > 0 ? cm(r.worstLag) : "-", bar.isEmpty ? "pass" : bar.joined(separator: "; ")]
        let body: [String] = [r.minGapBody.isFinite ? cm(r.minGapBody) : "-", r.holdMedianBody.map(cm) ?? "-", r.sndPerTouch]
        let hand: [String] = [r.handMin.isFinite ? hcm(r.handMin) : "-", r.handTouch.map(hcm).joined(separator: ","), r.handHoldMedian.map(hcm) ?? "-", r.handHand.map(hcm).joined(separator: ","), r.bodyTouch.map(cm).joined(separator: ","), r.arrivalTurnDeg.map { String(format: "%.0f", $0) } ?? "-", r.arrivalToTouchS.map { String(format: "%.1f", $0) } ?? "-",
                              r.retreat > 0 ? cm(r.retreat) : "0",
                              r.endGap.map { $0 >= 8 ? "far" : cm($0) } ?? "-", r.phases.isEmpty ? "-" : r.phases.sorted().map(String.init).joined(separator: ","), Array(Set(r.handTips)).sorted().joined(separator: " ")]
        let all: [String] = a + b + c + [snd, hap] + arr + hold + feet + body + hand
        return all.joined(separator: "\t")
    }
    /// THE BAR as far as the harness measures it (the planted-sole drift and the mid-air join are SocialFeetTests'): empty = every measured number meets it.
    ///   touching: arrival residual in -1...+1.5 cm; hold median 0 +- 0.5 cm (a hold must be reached: >= 3 frames); min skin gap >= -1 cm; features / limbs inside <= 0.5 cm; one contact sound per touch, none outside.
    ///   proximity: min skin gap >= 0.
    static func barFails(_ r: Result) -> [String] {
        guard r.started else { return ["no start"] }
        var f: [String] = []
        if r.stance == .proximity { if r.minGap < 0 { f.append("minGap \(cm(r.minGap))") }; return f }
        if r.minGap < -0.01 { f.append("minGap \(cm(r.minGap))") }
        f += handFails(r)
        if let a = r.arrivalCm, a > 0.015 || a < -0.01 { f.append("arrival \(cm(a))") }
        if r.momentary {          // (boop: the session ends at the touch) the gap at the frames the touch fired, never a hold from one frame
            if r.touchGaps.isEmpty { f.append("never touches") }
            else if let lo = r.touchGaps.min(), let hi = r.touchGaps.max(), lo < -0.01 || hi > 0.005 { f.append("touch at \(cm(lo))..\(cm(hi))") }
        } else if r.holdGaps.count < Result.minHold { if r.kind != "lieDown", r.kind != "flop", r.kind != "sleep" { f.append("no hold (\(r.holdGaps.count) touching frames)") } }
        if r.retreat > Self.retreatMax { f.append("touched, backed off \(cm(r.retreat)) cm and came back (stutter-step arrival)") }
        if r.arrivalCm == nil, !r.momentary, r.kind != "lieDown", r.kind != "flop", r.kind != "sleep" { f.append("never stood still on arrival") }
        else if !r.momentary, let m = r.holdMedian, abs(m) > 0.005 { f.append("hold \(cm(m))") }
        if max(r.featClip, r.limbClip) > 0.005 { f.append("feature inside \(dcm(max(r.featClip, r.limbClip)))") }
        if r.episodes == 0 { f.append("never touches") }
        for s in r.sndInEpisode where s != 1 { f.append("\(s) sounds in a touch"); break }
        if r.sndOutside > 0 { f.append("\(r.sndOutside) sounds outside a touch") }
        return f
    }
    /// USER RULE 2 (hands must land): the hand-tip gap of the hand emotes. Never inside the partner (>= -0.5 cm) for all four. Boop: at the touch frames the hand ends ON the skin (0 +- 0.5 cm) while the BODIES stand at hand
    /// reach, never pressed (egg-only gap >= 0; 1 mm of float noise allowed). HighFive: at the touch frames the two hand tips meet (closest approach to the other arm <= 0.5 cm).
    static func handFails(_ r: Result) -> [String] {
        guard let k = SocialKind(rawValue: r.kind), handKinds.contains(k) else { return [] }
        var f: [String] = []
        if r.handMin.isFinite, r.handMin < -0.005 { f.append("hand inside \(cm(r.handMin))") }
        if k == .boop {
            if r.handTouch.isEmpty { f.append("no hand reading at the touch") }
            else if let lo = r.handTouch.min(), let hi = r.handTouch.max(), lo < -0.005 || hi > 0.005 { f.append("hand at touch \(hcm(lo))..\(hcm(hi))") }
            if let lo = r.bodyTouch.min(), lo < -0.001 { f.append("bodies pressed \(cm(lo)) (want >= 0: hand reach)") }
        }
        if k == .highFive, let hi = r.handHand.max(), hi > 0.005 { f.append(hi >= 8 ? "hands apart: far (a body draws no arm capsule at the touch: hand-on-hand unmeasurable, see handTips)" : "hands apart \(hcm(hi))") }
        return f
    }
    static func write(_ rows: [Result], file: String) {
        guard let dir = outDir else { return }
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let text = ([header] + rows.map(row)).joined(separator: "\n") + "\n"
        try? text.write(toFile: dir + "/" + file, atomically: true, encoding: .utf8)
    }

    /// worst_frames.tsv from every run of this process (the file the judges read; it used to be written only by testZ_strips) + worst_frames_<what>.tsv for this call.
    static func writeWorstFrames(label: String) {
        guard let dir = outDir else { return }
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let head = "emote\tcast\tminGap_cm\tat_s\tframe\tpair\twhere\tstance\tstanceMedian_cm\tminGapBody_cm\tworstReach_cm\tworstLag_cm"
        func line(_ r: Result) -> String {
            let cols: [String] = [r.name, r.cast, cm(r.minGap), String(format: "%.1f", r.minGapT), "\(r.minGapFrame)", r.minGapPair, r.minGapPhase, r.stance.rawValue,
                                  r.stanceMedian.map(cm) ?? "-", r.minGapBody.isFinite ? cm(r.minGapBody) : "-", r.worstReach > 0 ? cm(r.worstReach) : "-", r.worstReach > 0 ? cm(r.worstLag) : "-"]
            return cols.joined(separator: "\t")
        }
        let rows = all.filter { $0.started }.sorted { $0.minGap < $1.minGap }
        try? ([head] + rows.map(line)).joined(separator: "\n").appending("\n").write(toFile: dir + "/worst_frames.tsv", atomically: true, encoding: .utf8)
        try? ([head] + rows.filter { $0.cast == label || label == "groups" && $0.cast.split(separator: "+").count == 3 }.map(line)).joined(separator: "\n").appending("\n").write(toFile: dir + "/worst_frames_\(fileName(label)).tsv", atomically: true, encoding: .utf8)
    }

    /// The contact brief as assertions. Needs the new engine: only with CONTACT_ENFORCE=1, else the test is skipped after the table is written.
    func finish(_ rs: [Result], _ what: String) throws {
        Self.all.removeAll { a in rs.contains { $0.name == a.name && $0.cast == a.cast } }
        Self.all += rs
        for r in rs { MotionLog.write("CONTACT " + Self.row(r)) }
        Self.writeWorstFrames(label: what)
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
                if let a = r.arrivalCm { XCTAssertLessThanOrEqual(a, 0.015, "\(who): arrives \(Self.cm(a)) cm apart (want <= 1.5)"); XCTAssertGreaterThanOrEqual(a, -0.01, "\(who): arrives \(Self.cm(-a)) cm sunk in (want <= 1)") }
                for why in Self.handFails(r) { XCTAssertTrue(false, "\(who): \(why)") }
                if r.momentary { for g in r.touchGaps { XCTAssertTrue(g >= -0.01 && g <= 0.005, "\(who): a momentary touch fired at \(Self.cm(g)) cm (want -1 ... +0.5)") } }
                else if r.kind != "lieDown", r.kind != "flop", r.kind != "sleep" { XCTAssertGreaterThanOrEqual(r.holdGaps.count, Result.minHold, "\(who): never held a touch (\(r.holdGaps.count) frames in the hold step from the first touch on)") }
                XCTAssertLessThanOrEqual(r.retreat, Self.retreatMax, "\(who): touched, then backed off \(Self.cm(r.retreat)) cm before the hold (stutter-step arrival)")
                if !r.momentary, let m = r.holdMedian { XCTAssertLessThanOrEqual(abs(m), 0.005, "\(who): the hold sits \(Self.cm(m)) cm from touching (want 0 +- 0.5) over \(r.holdGaps.count) frames") }
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

    /// The results table: header and row have the same columns, the arrival residual is in its column (cm), and the bar reads it.
    func testArrivalColumnInTheTable() {
        var r = Result(); r.name = "x"; r.cast = "A+B"; r.stance = .touching; r.kind = "swayHug"; r.started = true
        r.arrivalCm = 0.062; r.arrivalT = 3.5; r.lastPlantCm = 0.012; r.stops = 2
        r.holdGaps = [0.001, 0.002, -0.001, 0.0]; r.episodes = 1; r.sndInEpisode = [1]
        let head = Self.header.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
        let cols = Self.row(r).split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
        XCTAssertEqual(head.count, cols.count, "header and row line up")
        XCTAssertEqual(cols[head.firstIndex(of: "arrival_cm")!], "6.2")
        XCTAssertEqual(cols[head.firstIndex(of: "arrival_at_s")!], "3.5")
        XCTAssertEqual(cols[head.firstIndex(of: "lastPlant_cm")!], "1.2")
        XCTAssertEqual(cols[head.firstIndex(of: "stops")!], "2")
        XCTAssertTrue(Self.barFails(r).contains { $0.hasPrefix("arrival") }, "6.2 cm apart on arrival fails the bar (<= 1.5)")
        r.arrivalCm = 0.01; XCTAssertFalse(Self.barFails(r).contains { $0.hasPrefix("arrival") })
        r.arrivalCm = -0.02; XCTAssertTrue(Self.barFails(r).contains { $0.hasPrefix("arrival") }, "sunk in by 2 cm on arrival fails too")
        r.retreat = 0.55; XCTAssertTrue(Self.barFails(r).contains { $0.hasPrefix("touched, backed off") }, "touch, back off 55 cm, walk in again = the stutter-step arrival fails the bar")
        r.retreat = 0.04; XCTAssertFalse(Self.barFails(r).contains { $0.hasPrefix("touched, backed off") }, "the stance's own 4 cm opening is not a retreat")
        r.retreat = 0.012; XCTAssertFalse(Self.barFails(r).contains { $0.hasPrefix("touched, backed off") }, "the near step's 1 cm separation is not a retreat"); r.retreat = 0
        r.arrivalCm = nil; XCTAssertTrue(Self.barFails(r).contains("never stood still on arrival"))
        r.arrivalCm = 0.0; r.holdGaps = [0.001]; XCTAssertTrue(Self.barFails(r).contains { $0.hasPrefix("no hold") }, "never a hold from one frame")
        var b = Result(); b.name = "boop"; b.stance = .touching; b.kind = "boop"; b.started = true; b.momentary = true; b.episodes = 1; b.sndInEpisode = [1]; b.touchGaps = [-0.002]; b.bodyTouch = [0.02]; b.handTouch = [0.002]; b.handMin = -0.001
        XCTAssertTrue(Self.barFails(b).isEmpty, "a boop whose hand rests on the skin (+0.2 cm) with the bodies 2 cm apart meets the bar: \(Self.barFails(b))")
        b.touchGaps = [0.03]; XCTAssertFalse(Self.barFails(b).isEmpty)
        b.touchGaps = [-0.002]
        b.handTouch = [0.02]; XCTAssertTrue(Self.barFails(b).contains { $0.hasPrefix("hand at touch") }, "a hand hovering 2 cm short fails (rule 2)")
        b.handTouch = [-0.02]; b.handMin = -0.02; XCTAssertTrue(Self.barFails(b).contains { $0.hasPrefix("hand inside") }, "a hand 2 cm inside fails")
        b.handTouch = [0.002]; b.handMin = 0; b.bodyTouch = [-0.01]; XCTAssertTrue(Self.barFails(b).contains { $0.hasPrefix("bodies pressed") }, "bodies pressed together fail the boop (they stand at hand reach)")
        b.bodyTouch = [0.02]; b.handTouch = []; XCTAssertTrue(Self.barFails(b).contains("no hand reading at the touch"), "no hand number = unproven = fail")
        var hf = Result(); hf.name = "highFive"; hf.stance = .touching; hf.kind = "highFive"; hf.started = true; hf.holdGaps = [0, 0, 0]; hf.arrivalCm = 0; hf.episodes = 1; hf.sndInEpisode = [1]
        hf.handHand = [0.03]; XCTAssertTrue(Self.barFails(hf).contains { $0.hasPrefix("hands apart") }, "highFive hands 3 cm apart fail")
        hf.handHand = [0.002]; XCTAssertFalse(Self.barFails(hf).contains { $0.hasPrefix("hands apart") })
        // the new columns line up with the header
        let hh = Self.header.split(separator: "\t", omittingEmptySubsequences: false).map(String.init), rr = Self.row(b).split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
        XCTAssertEqual(hh.count, rr.count)
        XCTAssertEqual(rr[hh.firstIndex(of: "snd_per_touch")!], "1")
        XCTAssertEqual(rr[hh.firstIndex(of: "bodyTouch_cm")!], "2.0")
    }

    /// tag / chase are judged at their touch frames (a soft bump inside a run), the holding stances (hum ...) are the ones whose arrival / retreat apply, the pressing ones (bump ...) are not.
    func testHoldsStanceClassification() {
        func entry(_ k: SocialKind) -> ContactEntry { (Self.pairEntries + Self.groupEntries).first { Self.kindOf($0) == k }! }
        for k in [SocialKind.nuzzle, .cheekSquish, .backToBack, .cuddleLean, .swayHug, .whisperGiggle, .groupHug, .highFive] { XCTAssertTrue(Self.holdsStance(entry(k)), "\(k) is a holding stance") }
        for k in [SocialKind.boop, .tag, .chase, .look, .follow] { XCTAssertFalse(Self.holdsStance(entry(k)), "\(k) is not") }
        XCTAssertTrue(entry(.tag).momentary && entry(.chase).momentary, "tag / chase: judged at the touch")
    }

    // MARK: the formula is enforced, not noted (user rule 3)

    /// Every SocialKind is a Jelbie-with-a-partner emote (the enum has no solo kind), so every one needs an EXPLICIT ContactStance row: touching, proximity or none by decision, never a fall-through.
    /// FAILS while a kind has no row (as of 2026-11-04: look, zoomies, pass): ContactStance.swift is the stance owner's file.
    func testEveryInteractiveKindHasAStanceRow() {
        let missing = SocialKind.allCases.filter { ContactStance.table[$0] == nil }.map(\.rawValue)
        XCTAssertTrue(missing.isEmpty, "SocialKinds with no ContactStance row (add one to ContactStance.table: class, hand/feature flags, walk-up, sound): \(missing.joined(separator: ", "))")
    }
    /// Every SocialKind has a CURATED harness entry (a name, a class, its props) and the entry's class agrees with the table's: a new emote is measured automatically (autoEntries) but this FAILS until someone
    /// states how it is judged. Also: no kind appears twice.
    func testEveryInteractiveKindIsInTheHarness() {
        let all = Self.pairEntries + Self.groupEntries
        let auto = Self.autoEntries.map(\.name)
        XCTAssertTrue(auto.isEmpty, "SocialKinds with only an AUTOMATIC harness entry (add a curated one to ContactPolishTests.curatedPairEntries / curatedGroupEntries): \(auto.joined(separator: ", "))")
        let covered = Set(all.compactMap { Self.kindOf($0) })
        XCTAssertEqual(covered, Set(SocialKind.allCases), "kinds missing from the harness: \(Set(SocialKind.allCases).subtracting(covered).map(\.rawValue))")
        var seen = Set<SocialKind>(); var dup: [String] = []
        for e in all { if let k = Self.kindOf(e) { if !seen.insert(k).inserted { dup.append(k.rawValue) } } }
        XCTAssertTrue(dup.isEmpty, "kinds with two harness entries: \(dup)")
        for e in all { if let k = Self.kindOf(e), let st = ContactStance.entry(k) {
            let want: ContactClass = st.cls == .touching ? .touching : .proximity
            XCTAssertEqual(e.stance, want, "\(e.name): the harness judges it \(e.stance) but its ContactStance row is \(st.cls)")
        } }
        // pair kinds go through testPairs, group kinds through testGroups
        for e in Self.pairEntries { XCTAssertFalse(Self.kindOf(e)?.isGroup ?? false, "\(e.name) is a group kind in the pair list") }
        for e in Self.groupEntries { XCTAssertTrue(Self.kindOf(e)?.isGroup ?? true, "\(e.name) is a pair kind in the group list") }
    }
    /// EVERY interactive kind (touching AND proximity: round 2's judges flagged littleRace / ringDance / look ... as "no scene row, nothing to look at") has a real-app scene row in scripts/contact_scenes.tsv, so its clip is
    /// captured and judged next to the numbers (the prop ones, bagSit / cuddle / pass, need furniture or a ball ContactDemo cannot place).
    func testEveryTouchingKindHasASceneRow() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        guard let text = try? String(contentsOf: root.appendingPathComponent("scripts/contact_scenes.tsv"), encoding: .utf8) else { throw XCTSkip("scripts/contact_scenes.tsv not readable from the test host") }
        let demoKinds = Set(text.split(separator: "\n").filter { !$0.hasPrefix("#") }.compactMap { $0.split(separator: "\t", omittingEmptySubsequences: false).dropFirst(2).first.map(String.init) })
        let needsFurniture: Set<SocialKind> = [.bagSit, .cuddle, .pass]
        let missing = SocialKind.allCases.filter { !needsFurniture.contains($0) && !demoKinds.contains($0.rawValue) }.map(\.rawValue)
        XCTAssertTrue(missing.isEmpty, "interactive kinds with no scene row in scripts/contact_scenes.tsv: \(missing.joined(separator: ", "))")
        for extra in ["lieDown", "flop", "sleepPile"] { XCTAssertTrue(demoKinds.contains(extra), "no scene row for \(extra)") }
    }

    // MARK: the hand gap (user rule 2)

    /// A tip placed 2 cm short of a body reads +2, one placed inside reads negative, one held above the body (no shared height) reads far apart.
    func testHandGapMetric() {
        // a synthetic body: a 40 cm-radius disc of skin points at x = 1.0 .. , centred (1.0, 0), heights 0..0.6
        var pts: [SIMD3<Float>] = []
        for ai in 0..<360 { let a = Float(ai) * .pi / 180; for yi in 0..<7 { pts.append(SIMD3(1.0 + 0.4 * cosf(a), Float(yi) * 0.1, 0.4 * sinf(a))) } }
        let body = ContactSurface(root: SIMD2(1.0, 0), points: pts)
        // the body's nearest skin along -x is at x = 0.6
        XCTAssertEqual(BruteForceContactMetric.handGap(tip: SIMD3(0.58, 0.3, 0), against: body), 0.02, accuracy: 0.002, "2 cm short reads +2 cm")
        XCTAssertEqual(BruteForceContactMetric.handGap(tip: SIMD3(0.6, 0.3, 0), against: body), 0, accuracy: 0.002, "on the skin reads 0")
        XCTAssertLessThan(BruteForceContactMetric.handGap(tip: SIMD3(0.64, 0.3, 0), against: body), -0.03, "4 cm inside reads about -4 cm")
        XCTAssertEqual(BruteForceContactMetric.handGap(tip: SIMD3(0.64, 0.3, 0), against: body), -0.04, accuracy: 0.004)
        XCTAssertEqual(BruteForceContactMetric.handGap(tip: SIMD3(0.58, 1.5, 0), against: body), BruteForceContactMetric.farApart, "a hand above the body touches nothing")
        // off-axis: the line is tip -> root, so a tip beside the body measures the skin along that line
        XCTAssertEqual(BruteForceContactMetric.handGap(tip: SIMD3(1.0, 0.3, -0.45), against: body), 0.05, accuracy: 0.004, "5 cm off the side")
        // hand on hand
        let arm = (0..<20).map { SIMD3<Float>(0.5 + Float($0) * 0.001, 0.3, 0) }
        XCTAssertEqual(BruteForceContactMetric.handToHand(tip: SIMD3(0.48, 0.3, 0), armPoints: arm), 0.02, accuracy: 0.001)
    }
    /// The app's version: `ContactField.build` records the drawn hand tips from the arm blocks (the profile's x, z = the mesh's first arm vertex), and `ContactField.handGap` (radial against the profile outline) reads 0 on the outline.
    func testHandGapInTheProfile() throws {
        let d = makeDuo(cast: [0, 4], positions: [SIMD2(-0.5, 0.6), SIMD2(0.5, 0.6)])
        Self.keep.append(d)
        for _ in 0..<40 { d.tick() }
        _ = d.contactSurfaces()
        let ids = d.lab.rigs.map { $0.brain.steerID }
        for (i, r) in d.lab.rigs.enumerated() { ContactField.build(id: ids[i], dyn: UnsafePointer(d.dyn[i]), count: r.skinner.vertexCount, root: r.root, blocks: r.skinner.contactBlocks) }          // (the profile of THIS skinned frame)
        var checked = 0
        for i in 0..<2 {
            let mesh = d.contactHandTips(i), prof = ContactField.handTips(ids[i])
            XCTAssertEqual(mesh.count, prof.count, "rig \(i): the profile records the same arms the mesh draws")
            for (m, p) in zip(mesh, prof) {
                let r = d.lab.rigs[i].root
                XCTAssertEqual(m.x - r.x, p.x, accuracy: 0.002); XCTAssertEqual(m.z - r.y, p.y, accuracy: 0.002)
                checked += 1
            }
        }
        // a point exactly on body 1's outline toward body 0 reads 0 against it, 3 cm farther out reads +3 cm, 3 cm inside reads -3 cm
        let r1 = ContactField.root(ids[1]), r0 = ContactField.root(ids[0]), u = simd_normalize(r0 - r1)
        let e = ContactField.ext(ids[1], u)!
        func clear(_ off: Float) -> Float { ContactField.clearance(of: [r1 + u * (e + off) - r0], ownerRoot: r0, against: ids[1]) ?? 9 }
        XCTAssertEqual(clear(0), 0, accuracy: 0.002); XCTAssertEqual(clear(0.03), 0.03, accuracy: 0.002); XCTAssertEqual(clear(-0.03), -0.03, accuracy: 0.002)
        if checked == 0 { throw XCTSkip("no arm drawn in the rest pose on either rig: the recorder was not exercised (the outline check above ran)") }
    }

    private func pairTest(_ pi: Int) throws {
        let (label, cast) = Self.pairs[pi]
        var rs: [Result] = []
        for e in Self.pairEntries where Self.wanted(e) { rs.append(run(e, cast: cast, castName: label).0) }
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
        for (label, cast) in Self.trios { for e in Self.groupEntries where Self.wanted(e) { rs.append(run(e, cast: cast, castName: label).0) } }
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
