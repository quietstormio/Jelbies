//
//  StormComfortTests.swift
//  The thunderstorm comfort arcs (BlobBrain+Weather.swift, "comfort"): after the scare every Jelbie gets better while the storm still goes on and stays better.
//  A full storm (notice to clear) per cast and seed, headless like WeatherTests / StormFeetTests, on the Duo of FeatureClipTests (the contact helpers, the feature sets):
//    1 Jelbie (Bob), 2 (Bob + Pip), 2 (Teddy + Lavender), 3 (Bob + Pip + Lavender), 2 seeds each.
//  Asserted and printed (STORMCOMFORT lines): the tremble stops within about 14 s of the first one and never comes back (later thunder included); the hold really happened (the emote, or the
//  in-place fallback: which), hearts per Jelbie, exactly one haptic per arc, a PLAYED comfort voice per arc (the hub's post-guard tap); the lone one lies with its eyes shut and gets up at the clearing;
//  skin gap and features during the holds; feet / neck / leash checks of StormFeetTests through the whole storm; a lock or a call during a hold frees both; the player's stroke sticks after 1.5 s.
//

import XCTest
import simd
import QuartzCore
@testable import BobV1

@MainActor
final class StormComfortTests: XCTestCase {
    override func setUp() {
        super.setUp()
        _ = OnePieceInvariantTests.configured
        ToyTuning.settle = 0
        RoomLayout.dynamicBoxes = []; GameCamera.configureRoom(count: 3, option: .A, wide: 2); _ = GameCamera.camera(aspect: 603.0 / 1311.0)
        FeatureClip.enabled = true; LieClearTuning.enabled = true; ContactField.reset(); ContactField.enabled = true
    }
    override func tearDown() {
        AudioHub.firedTap = nil; AudioHub.dropTap = nil; AudioHub.dryRun = false; AudioHub.clock = { CACurrentMediaTime() }
        Skinner.leashObserver = nil
        StormReactor.holdAtRest = true; StormReactor.forceEmote = nil
        FeatureClip.enabled = true; LieClearTuning.enabled = true; FeatureClip.eggs = []; ContactField.reset(); ContactField.enabled = true
        ToyTuning.settle = 5; DecorField.shared.clear()
        RoomLayout.dynamicBoxes = []; GameCamera.configureRoom(count: 1); _ = GameCamera.camera(aspect: 440.0 / 956.0)
        super.tearDown()
    }

    // MARK: the room

    struct Cast { let name: String; let features: [JellyFeature]; let positions: [SIMD2<Float>] }
    static let solo = Cast(name: "Bob alone", features: [.none], positions: [SIMD2(0.2, 0.9)])
    static let bobPip = Cast(name: "Bob + Pip", features: [.none, .spines], positions: [SIMD2(-1.5, 0.6), SIMD2(1.4, 0.9)])
    static let teddyLavender = Cast(name: "Teddy + Lavender", features: [.ears, .wings], positions: [SIMD2(-1.4, 0.8), SIMD2(1.5, 0.5)])
    static let trio = Cast(name: "Bob + Pip + Lavender", features: [.none, .spines, .wings], positions: SocialTests.starts)

    @MainActor final class Room {
        let duo: FeatureClipTests.Duo
        let reactor = StormReactor()
        let book: WeatherBook
        var js: [StormReactor.Jelly]
        var rigs: [MotionRig] { duo.lab.rigs }
        nonisolated deinit {}
        init(_ cast: Cast, seed: UInt64 = 11) {
            duo = FeatureClipTests.Duo(positions: cast.positions, features: cast.features, seed: seed)
            book = WeatherBook(defaults: UserDefaults(suiteName: "stormcomfort-\(UUID().uuidString)")!)
            js = duo.lab.rigs.enumerated().map { StormReactor.Jelly(id: $0.offset, brain: $0.element.brain, sim: $0.element.sim, skinner: $0.element.skinner) }
            for r in duo.lab.rigs { r.brain.anticsEnabled = true }
        }
        /// One 60 Hz step like the stage: the weather, the reactor, then the bodies (the contact profiles are fresh while anything touches or an arc runs).
        func step() {
            let ev = book.tick(dt: 1.0 / 60)
            if !ev.isEmpty { reactor.handle(ev, plan: book.plan, jellies: js, care: nil) }
            reactor.tick(jellies: js, care: nil, dt: 1.0 / 60)
            duo.live = duo.lab.anySocial || !reactor.arcs.isEmpty
            duo.tick()
        }
        func run(_ seconds: Float, until: (() -> Bool)? = nil) { for _ in 0..<Int(seconds * 60) { step(); if until?() == true { break } } }
        /// Starts the storm at the peak (the first close thunder opens it) and hands the events to the reactor.
        func beginAtPeak(seed: UInt64) {
            let ev = book.begin(seed: seed, jumpTo: .peak)
            reactor.handle(ev, plan: book.plan, jellies: js, care: nil)
        }
        func holdPair() -> (Int, Int)? {
            let r = duo.lab.rigs
            for i in 0..<r.count {
                for j in (i + 1)..<r.count {
                    guard let s = r[i].brain.social, s === r[j].brain.social, s.kind == .swayHug || s.kind == .cuddleLean, s.phase >= 2, s.end == nil else { continue }
                    return (i, j)
                }
            }
            return nil
        }
    }

    // MARK: a whole storm

    struct Run {
        var n = 0
        var firstTremble: [Float?] = [], postCalmTremble: [Int] = [], hearts: [Int] = []
        var haptics = 0
        var arcs: [StormReactor.ArcRecord] = []
        var calmAt: [Int: Float] = [:]
        var played: [(t: Float, what: String)] = []
        var fired: [(t: Float, name: String)] = []
        var holdFrames = 0, holdGapMin: Float = .infinity, featPen: Float = -1, limbPen: Float = -1
        var agg = OnePieceInvariantTests.Agg(), leashHits = 0, tiltMax: Float = 0
        var firstLie: Float?, lieBreaks = 0, eyesShutFrames = 0, lieFrames = 0, joyHops = 0, flops = 0
        var endNeutral = false, membersAtEnd = -1, stormSeconds: Float = 0
        var log: [String] = [], odd: [String] = []
        /// The deepest skin gap of each hold, by emote (what the plain start of the same emote is compared with), and the emote each hold ran.
        var gapByKind: [String: Float] = [:]
        var beats: [String] = []
    }

    /// STORM_TRACE=1: the per-frame trace of the holds and of the frames before a leash hit (printed into the test log).
    static let tracing = ProcessInfo.processInfo.environment["STORM_TRACE"] != nil

    /// Notice to clear, for `cast` and storm `seed`.
    func runStorm(_ cast: Cast, seed: UInt64) -> Run {
        let room = Room(cast)
        var ring = [[String]](repeating: [], count: cast.features.count)
        let n = cast.features.count
        var out = Run()
        out.n = n
        out.firstTremble = [Float?](repeating: nil, count: n); out.postCalmTremble = [Int](repeating: 0, count: n); out.hearts = [Int](repeating: 0, count: n)
        // sound: an unmuted hub of its own on the sim clock (no real audio); the post-guard tap is what counts as PLAYED
        let hub = AudioHub(defaults: UserDefaults(suiteName: "stormcomfort-audio-\(UUID().uuidString)")!, muted: false)
        hub._openForTest(); AudioHub.dryRun = true
        var simNow = 70_000.0 + Double(seed) * 1_000, rclock: Float = 0
        AudioHub.clock = { simNow }
        AudioHub.dropTap = { what, why in if why == nil, what.hasSuffix("@storm") { out.played.append((rclock, what)) } }
        AudioHub.firedTap = { name in if name.hasPrefix("chirp_jelly") || name.hasPrefix("babble_jelly") { out.fired.append((rclock, name)) } }
        var haptics = 0
        room.reactor.onComfortHearts = { id in if id < n { out.hearts[id] += 1 } }
        room.reactor.onComfortHaptic = { haptics += 1 }
        room.reactor.onComfortVoice = { id, comforter in StormReactor.playComfortVoice(on: hub, id: id, comforter: comforter, x: 0) }

        let ev0 = room.book.begin(seed: seed)
        room.reactor.handle(ev0, plan: room.book.plan, jellies: room.js, care: nil)
        var steps = 0, tail = 0
        while steps < 60 * 320 {
            room.step(); steps += 1
            simNow += 1.0 / 60; rclock = room.reactor.clock
            for i in 0..<n {
                let r = room.rigs[i], b = r.brain
                // the tremble, as the reactor intends it (the eased pose lags a moment behind a clear)
                if abs(b.storm.wantRoll) > 1e-4 {
                    if out.firstTremble[i] == nil { out.firstTremble[i] = rclock }
                    if let c = room.reactor.calmAt[i], rclock > c + 0.02 { out.postCalmTremble[i] += 1 }
                }
                // the lone one: down on its belly with its eyes shut, and it stays so until the clearing
                if n == 1 {
                    let lying = b.idleState.kind == .floorNapFlop && b.idleState.phase == 2
                    if lying { out.lieFrames += 1; if r.skinner.openness.left < 0.1 { out.eyesShutFrames += 1 }; if out.firstLie == nil { out.firstLie = rclock } }
                    else if out.firstLie != nil, room.book.phase == .peak { out.lieBreaks += 1 }
                }
            }
            if Self.tracing {
                for i in 0..<n {
                    let b = room.rigs[i].brain, m = room.reactor.members[i]
                    ring[i].append(String(format: "t %.2f J%d mode %@ trem %.2f flinch %.2f storm p %.4f r %.4f s %.4f want r %.4f s %.4f act %@ idle %@ soc %@ ph %d yaw %.3f", rclock, i, String(describing: m?.mode), m?.tremble ?? -1, m?.flinch ?? -1, b.storm.pitch, b.storm.roll, b.storm.squash, b.storm.wantRoll, b.storm.wantSquash, String(describing: b.activity), String(describing: b.idleState.kind), String(describing: b.socialKind), b.social?.phase ?? -1, b.yaw))
                    if ring[i].count > 48 { ring[i].removeFirst() }
                }
            }
            // the contact during a hold: the skin gap of the pair, features and limbs inside the other body
            if steps % 3 == 0, let (i, j) = room.holdPair() {
                let feat = room.duo.skinAll()
                for k in 0..<n {
                    out.featPen = max(out.featPen, room.duo.penetration(feat[k], owner: k))
                    out.limbPen = max(out.limbPen, room.duo.penetration(room.duo.limbPoints(k), owner: k))
                }
                let g = room.duo.truthGap(i, j)
                out.holdGapMin = min(out.holdGapMin, g)
                if let k = room.rigs[i].brain.socialKind.map({ "\($0.rawValue)/\(i)-\(j)" }) { out.gapByKind[k] = min(out.gapByKind[k] ?? .infinity, g) }
                out.holdFrames += 1
            }
            if Self.tracing, steps % 3 == 0, let arc = room.reactor.arcs.first(where: { ($0.stage == .hold || $0.stage == .holding) && $0.b >= 0 }) {
                let i = arc.a, j = arc.b
                let g = room.duo.truthGap(i, j)
                let s = room.rigs[i].brain.social ?? room.rigs[j].brain.social
                var line = String(format: "STORMTRACE %@ seed %d t %.2f stage %@ %@ ph %d gap %.2f cm dist %.3f", cast.name, Int(seed), rclock, String(describing: arc.stage), s?.kind.rawValue ?? "-", s?.phase ?? -1, g * 100, simd_distance(room.rigs[i].brain.position, room.rigs[j].brain.position))
                for k in [i, j] {
                    let b = room.rigs[k].brain, m = room.reactor.members[k]
                    line += String(format: " | J%d trem %.2f fl %.2f p %.4f r %.4f s %.4f ke %.5f soc %@", k, m?.tremble ?? -1, m?.flinch ?? -1, b.storm.pitch, b.storm.roll, b.storm.squash, room.rigs[k].sim.kineticEnergy() / room.rigs[k].sim.totalMass, String(describing: b.socialKind))
                }
                MotionLog.write(line)
            }
            // the feet, the neck join, the leash (the checks of StormFeetTests), every 6th frame
            if steps % 6 == 0 {
                for (ri, r) in room.rigs.enumerated() {
                    // only while the reactor owns him: the autonomous slides / runs / tags of the quiet lab outside the storm are not this change's (round 1: all tilt > 0.5 and most leash frames came after the storm)
                    guard room.reactor.members[ri] != nil else { continue }
                    var hit = 0
                    Skinner.leashObserver = { _, _, _ in hit += 1 }
                    r.render()
                    Skinner.leashObserver = nil
                    out.leashHits += hit
                    let f = OnePieceInvariantTests.frame(r)
                    out.tiltMax = max(out.tiltMax, f.tilt)
                    if hit > 0, Self.tracing { for l in ring[ri] { MotionLog.write("STORMLEASH \(cast.name) seed \(seed) \(l)") } }
                    if hit > 0 || f.tilt > 0.5, out.odd.count < 8 {
                        let stages = room.reactor.arcs.map { "\($0.kind)/\($0.stage)" }
                        out.odd.append("t \(rclock) J\(ri) leash \(hit) tilt \(f.tilt) idle \(String(describing: r.brain.idleState.kind)) social \(String(describing: r.brain.socialKind)) mode \(String(describing: room.reactor.members[ri]?.mode)) arcs \(stages)")
                    }
                    out.agg.add(f, frame: steps)
                }
            }
            if !room.book.isStorming { tail += 1; if tail > 60 * 4 { break } }
        }
        out.haptics = haptics
        out.arcs = room.reactor.arcLog
        out.calmAt = room.reactor.calmAt
        out.log = room.reactor.log
        out.stormSeconds = Float(steps) / 60
        out.endNeutral = room.rigs.allSatisfy { $0.brain.storm.isNeutral && !$0.brain.hurry && !$0.brain.commanded && $0.brain.idleState.kind != .floorNapFlop }
        out.membersAtEnd = room.reactor.members.count
        out.joyHops = room.rigs.map { $0.brain.idleState.counts[.joy] ?? 0 }.reduce(0, +)
        out.flops = room.rigs.map { $0.brain.idleState.counts[.floorNapFlop] ?? 0 }.reduce(0, +)
        return out
    }

    /// The same hold started the plain way (nobody scared, two Jelbies 1.47 m apart): its deepest skin gap in m. One run per pair and emote (the cast fixes the bodies).
    nonisolated(unsafe) static var plainGaps: [String: Float] = [:]
    func plainGap(_ cast: Cast, _ kind: SocialKind) -> Float {
        let key = cast.name + "/" + kind.rawValue
        if let g = Self.plainGaps[key] { return g }
        let g = controlGapValue(cast, kind)
        Self.plainGaps[key] = g
        return g
    }

    /// `emote`: the hold every arc of this storm uses (so a run of seeds covers both); nil = the reactor's own seeded choice.
    func check(_ cast: Cast, seed: UInt64, emote: SocialKind? = nil, file: StaticString = #filePath, line: UInt = #line) {
        StormReactor.forceEmote = emote
        defer { StormReactor.forceEmote = nil; StormReactor.holdAtRest = true }
        let r = runStorm(cast, seed: seed)
        let who = "\(cast.name), seed \(seed)"
        let n = r.n
        var report = "STORMCOMFORT \(who): storm \(String(format: "%.0f", r.stormSeconds)) s"
        // 1. everybody who trembled got better within about 14 s of the first tremble, and never trembled again
        for i in 0..<n {
            guard let t0 = r.firstTremble[i] else { XCTFail("\(who): Jelbie \(i) never trembled (no huddle?) log \(r.log)", file: file, line: line); continue }
            guard let c = r.calmAt[i] else { XCTFail("\(who): Jelbie \(i) was never comforted (first tremble \(t0)) log \(r.log)", file: file, line: line); continue }
            report += String(format: " | J%d trembled %.1f calm %.1f (%.1f s) post-calm tremble frames %d", i, t0, c, c - t0, r.postCalmTremble[i])
            XCTAssertLessThanOrEqual(c - t0, 15, "\(who): Jelbie \(i) trembled \(c - t0) s before it got better", file: file, line: line)
            XCTAssertEqual(r.postCalmTremble[i], 0, "\(who): Jelbie \(i) trembled again after it was comforted", file: file, line: line)
        }
        // 2. the holds
        if n >= 2 {
            let holds = r.arcs.filter { $0.kind == .comfort || $0.kind == .mutual }
            XCTAssertFalse(holds.isEmpty, "\(who): no comfort hold was planned: \(r.arcs)", file: file, line: line)
            for a in r.arcs where a.endedAt != nil {
                let which = a.emote.map { $0.rawValue } ?? (a.fallback ? "in-place calm (fallback)" : "none")
                report += " | arc \(a.kind) \(a.ids): \(which), tries \(a.tries), hearts \(a.hearts), haptics \(a.haptics), voices \(a.voices)"
                XCTAssertEqual(a.haptics, 1, "\(who): arc \(a.kind) \(a.ids) must send exactly one haptic", file: file, line: line)
                if a.kind == .comfort || a.kind == .mutual { XCTAssertTrue(a.emote != nil || a.fallback, "\(who): arc \(a.ids) neither held nor fell back", file: file, line: line) }
                let t1 = (a.endedAt ?? a.startedAt) + 1
                let playedHere = r.played.filter { $0.t >= a.startedAt && $0.t <= t1 }.count
                XCTAssertGreaterThanOrEqual(playedHere, 1, "\(who): no comfort voice was PLAYED in arc \(a.kind) \(a.ids) (requests \(a.voices))", file: file, line: line)
            }
            for i in 0..<n { XCTAssertGreaterThanOrEqual(r.hearts[i], 1, "\(who): no hearts over Jelbie \(i)", file: file, line: line) }
            XCTAssertEqual(r.haptics, r.arcs.filter { $0.haptics > 0 }.count, "\(who): one haptic per arc", file: file, line: line)
            report += " | hearts \(r.hearts), haptics \(r.haptics), voices played \(r.played.count), chirps fired \(r.fired.count)"
            for a in r.arcs where a.endedAt != nil {
                let t0 = r.firstTremble.compactMap { $0 }.min() ?? 0
                MotionLog.write(String(format: "STORMCOMFORT BEATS %@ seed %d arc %@ %@: first tremble %.1f -> comfort starts %.1f -> hold %@ -> calm %@ | hearts %d, played %d, haptics %d", cast.name, Int(seed), String(describing: a.kind), a.ids.description, t0, a.startedAt,
                                      a.holdStart.map { String(format: "%.1f-%@", $0, a.holdEnd.map { String(format: "%.1f", $0) } ?? "?") } ?? "none", a.ids.compactMap { r.calmAt[$0] }.max().map { String(format: "%.1f", $0) } ?? "?", a.hearts, r.played.filter { $0.t >= a.startedAt && $0.t <= (a.endedAt ?? a.startedAt) + 1 }.count, a.haptics))
            }
            // 3. the contact during the holds (only when an emote really held them)
            if r.holdFrames > 0 {
                report += String(format: " | hold frames %d, closest skin gap %.2f cm, feature inside other body %.2f cm, limb %.2f cm", r.holdFrames, r.holdGapMin * 100, r.featPen * 100, r.limbPen * 100)
                // the storm hold may be as deep as the same plain emote, not deeper (ruling of the integrator 2026-11-11), and never below -1.0 cm
                for (k, g) in r.gapByKind.sorted(by: { $0.key < $1.key }) {
                    // k = "emote/i-j": the plain start of the same emote for the same two bodies (their species, so Teddy's belly and the wings are the same)
                    let parts = k.split(separator: "/").map(String.init)
                    let ij = parts[1].split(separator: "-").compactMap { Int($0) }
                    let pair = Cast(name: ij.map { String(describing: cast.features[$0]) }.joined(separator: " + "), features: ij.map { cast.features[$0] }, positions: [SIMD2(-1.4, 0.8), SIMD2(1.5, 0.5)])
                    let plain = SocialKind(rawValue: parts[0]).map { plainGap(pair, $0) } ?? -0.01
                    let limit = max(plain - 0.001, -0.010)
                    report += String(format: " | HOLD %@ seed %d: storm %.2f cm, plain %.2f cm, limit %.2f cm", k, Int(seed), g * 100, plain * 100, limit * 100)
                    MotionLog.write(String(format: "STORMCOMFORT DEPTH %@ | %@ | seed %d | plain %.2f cm | storm %.2f cm | limit %.2f cm", cast.name, k, Int(seed), plain * 100, g * 100, limit * 100))
                    XCTAssertGreaterThanOrEqual(g, limit, "\(who): the \(k) hold is deeper than the plain emote (storm \(g * 100) cm, plain \(plain * 100) cm, limit \(limit * 100) cm)", file: file, line: line)
                }
                XCTAssertGreaterThanOrEqual(r.holdGapMin, -0.010, "\(who): the bodies overlap during the hold (gap \(r.holdGapMin * 100) cm; never below -1.0 cm)", file: file, line: line)
                XCTAssertLessThanOrEqual(r.holdGapMin, 0.005, "\(who): the bodies never touched during the hold (closest gap \(r.holdGapMin * 100) cm)", file: file, line: line)
                XCTAssertLessThanOrEqual(r.featPen, FeatureClipTests.tol, "\(who): a feature is inside the other body (\(r.featPen * 100) cm)", file: file, line: line)
                XCTAssertLessThanOrEqual(r.limbPen, FeatureClipTests.tol, "\(who): a limb is inside the other body (\(r.limbPen * 100) cm)", file: file, line: line)
            } else { report += " | no emote hold sampled (in-place fallback only)" }
        } else {
            // the lone one: sighs, lies down with its eyes shut within about 20 s of the scare, stays so until the clearing, then gets up with a stretch and a hop
            let t0 = r.firstTremble[0] ?? 0
            report += String(format: " | lies from %.1f s (first tremble %.1f), eyes shut %d of %d lying frames, breaks %d, joy hops %d, flops %d", r.firstLie ?? -1, t0, r.eyesShutFrames, r.lieFrames, r.lieBreaks, r.joyHops, r.flops)
            guard let lie = r.firstLie else { XCTFail("\(who): it never lay down: \(r.arcs) \(r.log)", file: file, line: line); print(report); return }
            XCTAssertLessThanOrEqual(lie - t0, 20, "\(who): lay down \(lie - t0) s after it started to tremble", file: file, line: line)
            XCTAssertEqual(r.lieBreaks, 0, "\(who): it got up before the clearing", file: file, line: line)
            XCTAssertGreaterThan(r.eyesShutFrames, r.lieFrames * 9 / 10, "\(who): its eyes were not shut while it lay", file: file, line: line)
            XCTAssertGreaterThanOrEqual(r.joyHops, 1, "\(who): no happy hop after it got up", file: file, line: line)
            XCTAssertEqual(r.haptics, 1, "\(who): one haptic for its arc", file: file, line: line)
            XCTAssertGreaterThanOrEqual(r.played.count, 1, "\(who): no comfort voice PLAYED", file: file, line: line)
        }
        // 4. feet attached, no leash, neck closed, no tipping, through the whole storm
        XCTAssertEqual(r.leashHits, 0, "\(who): the skin's leash moved a foot piece in \(r.leashHits) frames", file: file, line: line)
        XCTAssertEqual(r.agg.leashed, 0, "\(who): leashed frames", file: file, line: line)
        XCTAssertEqual(r.agg.detached, 0, "\(who): a foot came off the body in \(r.agg.detached) frames (worst leg sdf \(r.agg.worstLeg))", file: file, line: line)
        XCTAssertEqual(r.agg.neckBad, 0, "\(who): the neck join was open in \(r.agg.neckBad) frames", file: file, line: line)
        XCTAssertLessThanOrEqual(r.tiltMax, 0.5, "\(who): the body tipped \(r.tiltMax) rad", file: file, line: line)
        // 5. the end: everybody free, no pose left
        XCTAssertEqual(r.membersAtEnd, 0, "\(who): the reactor still holds Jelbies after the storm", file: file, line: line)
        XCTAssertTrue(r.endNeutral, "\(who): a storm pose / hurry / lying pose is left after the storm", file: file, line: line)
        report += " | ODD \(r.odd)"
        report += String(format: " | feet: frames %d beans %d leashed %d detached %d neckBad %d tilt %.3f", r.agg.frames, r.agg.beanFrames, r.agg.leashed, r.agg.detached, r.agg.neckBad, r.tiltMax)
        print(report)
        MotionLog.write(report)
    }

    func testLoneJelbieSighsLiesDownEyesShutAndGetsUp() { for seed: UInt64 in [4, 9] { check(Self.solo, seed: seed) } }
    /// Both holds run in every cast: seed 4 with swayHug, seed 9 with cuddleLean (the contact limits are asserted on each).
    func testBobAndPipComfortEachOther() { check(Self.bobPip, seed: 4, emote: .swayHug); check(Self.bobPip, seed: 9, emote: .cuddleLean) }
    func testTeddyAndLavenderComfortEachOther() { check(Self.teddyLavender, seed: 4, emote: .swayHug); check(Self.teddyLavender, seed: 9, emote: .cuddleLean) }
    func testThreeJelbiesTheBraveOneComfortsAndNobodyIsLeftOut() { check(Self.trio, seed: 4, emote: .swayHug); check(Self.trio, seed: 9, emote: .cuddleLean) }

    /// STORM_TRACE=1 only: the worst Teddy + Lavender seed (9, cuddleLean) with round 1's hold (storm pose still on a held body) and with the hold at rest, per-frame trace lines STORMTRACE (gap, tremble, storm pose, emote phase).
    func testTraceTeddyLavenderHoldBeforeAndAfter() throws {
        try XCTSkipUnless(Self.tracing, "set TEST_RUNNER_STORM_TRACE=1")
        for rest in [false, true] {
            StormReactor.holdAtRest = rest; StormReactor.forceEmote = .cuddleLean
            MotionLog.write("STORMTRACE ===== hold at rest: \(rest) =====")
            let r = runStorm(Self.teddyLavender, seed: 9)
            MotionLog.write("STORMTRACE ===== hold at rest \(rest): deepest gap by emote \(r.gapByKind) =====")
        }
        StormReactor.holdAtRest = true
    }

    /// The reactor's own choice is seeded and about half and half; and the choice is what the arc really runs.
    func testTheHoldIsASeededChoiceOfBoth() {
        var sway = 0, lean = 0
        for key in UInt64(1000)..<UInt64(1400) { for arc in 0..<3 { if StormReactor.emoteChoice(stormKey: key, arc: arc) == .swayHug { sway += 1 } else { lean += 1 } } }
        MotionLog.write("STORMCOMFORT CHOICE swayHug \(sway), cuddleLean \(lean) of \(sway + lean)")
        XCTAssertEqual(Double(sway) / Double(sway + lean), 0.5, accuracy: 0.08, "about half and half")
        XCTAssertEqual(StormReactor.emoteChoice(stormKey: 4321, arc: 1), StormReactor.emoteChoice(stormKey: 4321, arc: 1), "seeded: the same storm chooses the same")
    }

    // MARK: the player

    /// A hold in progress: both Jelbies, the hold pair found.
    private func holding(_ room: Room, seed: UInt64) -> Bool {
        room.beginAtPeak(seed: seed)
        var found = false
        room.run(120) { found = room.reactor.arcs.contains { $0.stage == .holding && $0.holdT > 0.6 }; return found }
        return found
    }

    func testAMealLockDuringAHoldFreesBothAtOnce() {
        for seed: UInt64 in [4, 9] {
            let room = Room(Self.bobPip)
            XCTAssertTrue(holding(room, seed: seed), "seed \(seed): a hold started: \(room.reactor.log) \(room.reactor.arcLog)")
            room.reactor.locks.meal = true          // a meal is asked for
            room.run(0.5)
            XCTAssertTrue(room.reactor.members.isEmpty, "seed \(seed): everybody is free at once: \(room.reactor.log)")
            XCTAssertTrue(room.reactor.arcs.isEmpty)
            room.run(1.5)
            for r in room.rigs {
                XCTAssertFalse(r.brain.isSocial, "seed \(seed): the hold ended")
                XCTAssertTrue(r.brain.storm.isNeutral && !r.brain.hurry, "seed \(seed): no storm pose is left")
            }
        }
    }

    func testACallDuringAHoldFreesBothAndTheCalledOneKeepsItsWalk() {
        for seed: UInt64 in [4, 9] {
            let room = Room(Self.bobPip)
            XCTAssertTrue(holding(room, seed: seed), "seed \(seed): a hold started: \(room.reactor.log)")
            let called = room.rigs[0].brain
            called.requestNow(.come(to: SIMD2(1.9, 1.6)))          // the player's come-here
            room.run(0.4)
            XCTAssertNil(room.reactor.members[0], "seed \(seed): the called one is not the storm's any more")
            XCTAssertTrue(room.reactor.arcs.isEmpty, "seed \(seed): the arc ended")
            for r in room.rigs { XCTAssertFalse(r.brain.isSocial, "seed \(seed): the hold ended for both") }
            XCTAssertTrue(called.storm.isNeutral || abs(called.storm.wantRoll) < 1e-6, "seed \(seed): no tremble on the called one")
            XCTAssertNotEqual(called.activity, .idle, "seed \(seed): the player's walk runs (the huddle did not take it over)")
        }
    }

    /// Everybody in the huddle, trembling.
    private func huddled(_ room: Room, seed: UInt64 = 4, limit: Float = 25) -> Bool {
        room.beginAtPeak(seed: seed)
        var ok = false
        room.run(limit) { ok = room.rigs.indices.allSatisfy { room.reactor.members[$0]?.mode == .huddle }; return ok }
        return ok
    }

    func testAStrokeOfOneAndAHalfSecondsMakesTheCalmStick() {
        let room = Room(Self.bobPip)
        XCTAssertTrue(huddled(room))
        let b = room.rigs[1].brain
        for _ in 0..<(Int(StormComfortTuning.petStick * 60) + 12) { room.reactor.tick(jellies: room.js, care: nil, dt: 1.0 / 60); b.activity = .touched }
        XCTAssertEqual(room.reactor.members[1]?.mode, .comforted)
        XCTAssertNotNil(room.reactor.calmAt[1], "the calm stuck after the stroke")
        b.activity = .idle
        room.run(8)
        let m = room.reactor.members[1]
        XCTAssertTrue(m?.mode == .calm || m?.mode == .arc, "after the stroke he stays calm, not back in the huddle: \(String(describing: m?.mode)) \(room.reactor.log)")
        for _ in 0..<(60 * 10) { room.step(); XCTAssertEqual(b.storm.wantRoll, 0, "no tremble after a long enough stroke") }
    }

    func testAShortStrokeDoesNotStick() {
        let room = Room(Self.bobPip)
        XCTAssertTrue(huddled(room))
        let b = room.rigs[1].brain
        for _ in 0..<60 { room.reactor.tick(jellies: room.js, care: nil, dt: 1.0 / 60); b.activity = .touched }
        XCTAssertNil(room.reactor.calmAt[1], "one second is not enough")
        b.activity = .idle
        room.run(16)
        XCTAssertNotEqual(room.reactor.members[1]?.mode, .comforted)
    }

    // MARK: controls (printed, not asserted): is the hold overlap the emote's own?

    private func controlGapValue(_ cast: Cast, _ kind: SocialKind) -> Float {
        let d = FeatureClipTests.Duo(positions: cast.positions, features: cast.features, seed: 11)
        d.place([SIMD2(-0.735, 0.9), SIMD2(0.735, 0.9)]); d.live = true
        for _ in 0..<3 { d.tick() }
        let a = d.lab.rigs[0], b = d.lab.rigs[1]
        guard a.brain.socialStart(kind, with: b.brain, a.sim) else { XCTFail("the plain \(kind.rawValue) of \(cast.name) did not start: no plain depth to compare with"); return -0.010 }
        var gmin = Float.infinity
        for s in 0..<(60 * 14) {
            d.tick()
            if s % 3 == 0, let sess = a.brain.social, sess.phase >= 2 {
                let g = d.truthGap(0, 1)
                gmin = min(gmin, g)
                if Self.tracing { MotionLog.write(String(format: "STORMTRACE PLAIN %@ %@ step %d ph %d gap %.2f cm ke %.5f %.5f", cast.name, kind.rawValue, s, sess.phase, g * 100, a.sim.kineticEnergy() / a.sim.totalMass, b.sim.kineticEnergy() / b.sim.totalMass)) }
            }
            if a.brain.social == nil, s > 30 { break }
        }
        return gmin
    }
    private func controlGap(_ cast: Cast, _ kind: SocialKind) -> String {
        String(format: "%@ %@ without any storm: closest skin gap %.2f cm", cast.name, kind.rawValue, plainGap(cast, kind) * 100)
    }

    func testControlHoldGapWithoutStorm() {
        var lines: [String] = []
        for c in [Self.bobPip, Self.teddyLavender] { for k in [SocialKind.swayHug, .cuddleLean] { lines.append(controlGap(c, k)) } }
        for l in lines { MotionLog.write("STORMCOMFORT CONTROL " + l) }
    }

    /// The relief test of WeatherTests (cluster, then scatter) with the comfort code off and on: same numbers = the comfort code does not change it.
    func testControlReliefScatterWithAndWithoutComfort() {
        GameCamera.configureRoom(count: 3, option: .A, wide: 2); _ = GameCamera.camera(aspect: 440 / 956)
        ToyTuning.settle = 5
        defer { StormReactor.comfortOn = true; ToyTuning.settle = 0; _ = GameCamera.camera(aspect: 603.0 / 1311.0) }
        for on in [false, true] {
            StormReactor.comfortOn = on
            let lab = SocialTests.Lab(n: 3, quiet: true, seed: 11)
            let reactor = StormReactor()
            let book = WeatherBook(defaults: UserDefaults(suiteName: "stormcomfort-ctl-\(UUID().uuidString)")!)
            let js = lab.rigs.enumerated().map { StormReactor.Jelly(id: $0.offset, brain: $0.element.brain, sim: $0.element.sim, skinner: $0.element.skinner) }
            for r in lab.rigs { r.brain.anticsEnabled = true }
            func step() {
                let ev = book.tick(dt: 1.0 / 60)
                if !ev.isEmpty { reactor.handle(ev, plan: book.plan, jellies: js, care: nil) }
                reactor.tick(jellies: js, care: nil, dt: 1.0 / 60)
                lab.tick(watching: false)
                for r in lab.rigs { r.skinner.jelly.tick(brain: r.brain, sim: r.sim, dt: r.sim.stepDt) }
            }
            func meanGap() -> Float { (lab.centreGap(0, 1) + lab.centreGap(0, 2) + lab.centreGap(1, 2)) / 3 }
            let ev = book.begin(seed: 4, jumpTo: .peak)
            reactor.handle(ev, plan: book.plan, jellies: js, care: nil)
            var t = 0
            while t < 25 * 60 { step(); t += 1; if (0..<3).allSatisfy({ reactor.members[$0]?.mode == .huddle }) { break } }
            for _ in 0..<60 { step() }
            let cluster = meanGap()
            let plan = book.plan!
            while book.stormTime < plan.clearStart - 0.2 - 0.01 && book.isStorming {
                let e = book.tick(dt: min(4.9, plan.clearStart - 0.2 - book.stormTime))
                if !e.isEmpty { reactor.handle(e, plan: book.plan, jellies: js, care: nil) }
            }
            for _ in 0..<30 { step() }
            for _ in 0..<(60 * 14) { step() }
            MotionLog.write(String(format: "STORMCOMFORT CONTROL relief scatter, comfort %@: huddled after %.1f s, cluster %.3f, after the scatter %.3f (the test wants > cluster + 0.2)", on ? "ON" : "OFF", Float(t) / 60, cluster, meanGap()))
        }
    }

    // MARK: the schedule

    /// The storms stay as rare as they were: this change does not touch Melon/Weather.swift (git diff) and the next-storm roll is still the same 2...5 hours away.
    func testStormScheduleIsUntouched() {
        let book = WeatherBook(defaults: UserDefaults(suiteName: "stormcomfort-sched-\(UUID().uuidString)")!)
        XCTAssertGreaterThanOrEqual(book.nextStormAt - book.playSeconds, WeatherTuning.gap.lowerBound)
        XCTAssertLessThanOrEqual(book.nextStormAt - book.playSeconds, WeatherTuning.gap.upperBound)
        XCTAssertEqual(WeatherTuning.gap.lowerBound, 2 * 3600, accuracy: 1, "the schedule's lower bound (2 h)")
        XCTAssertEqual(WeatherTuning.gap.upperBound, 5 * 3600, accuracy: 1, "the schedule's upper bound (5 h)")
    }
}
