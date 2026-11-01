//
//  LivelyLabTests.swift
//  "They literally walk and then stop then walk again ... They're too bland." / "Add more interactions where a Jelbie is reacting to another Jelbie".
//  The 3-Jelly room as the stage runs it (antics, a watching player, sleep, the seven toys), 300 s, two seeds, okay and happy moods:
//    plain walk + stand time below 55 % (okay) / 45 % (happy); at least 4 flourish kinds per Jelly and 8 in the room; at least 6 face changes per minute per Jelly
//    with at least 3 brow-expression kinds; no 12 s without an event per Jelly; the reaction bus (15 events, 6 kinds, none while reserved / asleep / racing);
//    never more than two fast movers; the stubby-arm and attached-feet caps through all of it.
//

import XCTest
import simd
@testable import BobV1

@MainActor
final class LivelyLabTests: XCTestCase {
    override func setUp() { RoomLayout.dynamicBoxes = []; SocialTuning.pickChance = 0.12 }
    override func tearDown() { RoomLayout.dynamicBoxes = []; DecorField.shared.clear(); GameCamera.configureRoom(count: 1); _ = GameCamera.camera(aspect: 440.0 / 956.0) }

    struct Report {
        var plain = [Float](repeating: 0, count: 3), total: Float = 0
        var flourishKinds = [Set<IdleKind>](repeating: [], count: 3)
        var flourishStarts = [Int](repeating: 0, count: 3)
        var faceChanges = [Int](repeating: 0, count: 3)
        var browKinds = [Set<FaceKind>](repeating: [], count: 3)
        var maxQuiet = [Float](repeating: 0, count: 3)
        var over2 = 0
        var reactionLog: [(t: Float, event: BusEventKind, reactor: Int, kind: ReactionKind)] = []
        var events = 0, violations = 0
        var labels = [[String: Int]](repeating: [:], count: 3)
        var fastTag = ""
        var gapTags: [String] = []
        var legs = [String](repeating: "", count: 3)
    }

    static func isPlain(_ b: BlobBrain) -> Bool {
        if b.social != nil || b.idleState.kind != nil { return false }
        switch b.script {
        case .none, .walk, .turn, .look, .stepInPlace: return true
        default: return false
        }
    }
    static func label(_ b: BlobBrain) -> String? {
        if let s = b.social { return "social:\(s.kind.rawValue)" }
        if let k = b.idleState.kind { return "idle:\(k.rawValue)" }
        switch b.script {
        case .hopPlay: return "play:hop"
        case .spin: return "play:spin"
        case .rollPlay: return "play:roll"
        case .flipPlay: return "play:flip"
        case .wave: return "wave"
        default: return nil
        }
    }

    /// The seven toys in the room (ball, yarn ball, drum, duck, slide, blocks, toy car) on valid spots.
    static func placeToys() {
        var placed: [PlacedDecor] = []
        for (i, k) in [DecorKind.ball, .yarnball, .drum, .duck, .slide, .blocks, .toycar].enumerated() {
            if let p = DecorPlacement.findSpot(k, among: placed) { placed.append(PlacedDecor(uid: 20 + i, kind: k, x: p.x, z: p.y)) }
        }
        DecorField.shared.set(placed)
    }

    static func measure(seconds: Int, seed: UInt64, mood: BlobMood, watchCaps: Bool = false, toys: Bool = true) -> Report {
        GameCamera.configureRoom(count: 3, option: .A, wide: 2); _ = GameCamera.camera(aspect: 440 / 956)
        if toys { placeToys() }
        let lab = SocialTests.Lab(quiet: false, seed: seed)
        for (i, r) in lab.rigs.enumerated() {
            let b = r.brain
            b.idleMood = mood; b.socialBook.cooldown = 8; b.idleState.cooldown = 9; b.restTimer = 0.5 + Float(i)
            b.anticsEnabled = true; b.watching = true; b.sleepEnabled = true
        }
        var rep = Report()
        let bus = lab.roster.eventBus
        bus.onStart = { b, _ in if b.held || b.isNapping || b.race.active || b.idleState.kind == .sleep { rep.violations += 1 } }
        var prev = [String?](repeating: nil, count: 3)
        var lastChanges = [0, 0, 0], lastReact = [0, 0, 0]
        var curKind = ["-", "-", "-"], lastKind = ["-", "-", "-"], lastKindT = [Float](repeating: 0, count: 3)
        var quietFrom = [Float](repeating: 0, count: 3)
        let frames = 60 * seconds
        for f in 0..<frames {
            lab.tick(watching: watchCaps)
            let t = Float(f) / 60
            var fast = 0
            for (i, r) in lab.rigs.enumerated() {
                let b = r.brain
                if Self.isPlain(b) { rep.plain[i] += 1 }
                let l = Self.label(b)
                var event = false
                if let l, l != prev[i] { event = true; rep.labels[i][l, default: 0] += 1 }
                prev[i] = l
                if let k = b.idleState.kind, BlobBrain.flourishKinds.contains(k) {
                    if rep.flourishKinds[i].insert(k).inserted { }
                }
                if b.expr.changes != lastChanges[i] { event = true; lastChanges[i] = b.expr.changes }
                let rc = b.react.started.values.reduce(0, +)
                if rc != lastReact[i] { event = true; lastReact[i] = rc }
                // a "dead stretch" = he only walks / stands (no behaviour, social, flourish or reaction) and his face does not change
                if event || l != nil || !Self.isPlain(b) { rep.maxQuiet[i] = max(rep.maxQuiet[i], t - quietFrom[i]); quietFrom[i] = t }
                if b.isFastMove { fast += 1 }
            }
            if fast > 2 {
                rep.over2 += 1
                if rep.fastTag.isEmpty { rep.fastTag = "t \(t): " + lab.rigs.map { b in "\(b.brain.idleState.kind.map { $0.rawValue } ?? "-")|\(b.brain.social.map { $0.kind.rawValue } ?? "-")|\(String(describing: b.brain.script).prefix(9))|greetHop=\(b.brain.socialBook.greetHop) nameHop=\(b.brain.nameHopping) cmd=\(b.brain.commanded)" }.joined(separator: " ; ") }
            }
            if watchCaps {
                lab.sampleGaps()
                for (i, r) in lab.rigs.enumerated() where r.brain.social == nil {
                    guard let ff = FeetAttachTests.footFrame(r), ff.overlap > -0.004 || ff.soleRise > 0.12 else { continue }
                    if rep.gapTags.count < 14 { rep.gapTags.append(String(format: "t %.2f rig%d overlap %.4f rise %.3f | kind %@ (prev %@ %.1f s ago) script %@ runW %.2f feetActive %d stepLive %d beanG %.2f", t, i, ff.overlap, ff.soleRise, "\(r.brain.idleState.kind.map { $0.rawValue } ?? "-")", "\(lastKind[i])", t - lastKindT[i], String(describing: r.brain.script).prefix(14) as CVarArg, r.brain.runW, r.brain.feet.active ? 1 : 0, r.brain.stepLive ? 1 : 0, r.brain.beanG)) }
                }
            }
            for (i, r) in lab.rigs.enumerated() { let k = r.brain.idleState.kind?.rawValue ?? "-"; if k != curKind[i] { lastKind[i] = curKind[i]; lastKindT[i] = t; curKind[i] = k } }
        }
        for i in 0..<3 {
            rep.maxQuiet[i] = max(rep.maxQuiet[i], Float(seconds) - quietFrom[i])
            rep.faceChanges[i] = lab.rigs[i].brain.expr.changes
            rep.browKinds[i] = lab.rigs[i].brain.expr.browSeen
            rep.flourishStarts[i] = BlobBrain.flourishKinds.reduce(0) { $0 + (lab.rigs[i].brain.idleState.counts[$1] ?? 0) }
            rep.plain[i] /= Float(frames)
            let lg = lab.rigs[i].brain.leg
            rep.legs[i] = "legs>=1.5u \(lg.legs) wanted \(lg.wanted) fired \(lg.fired) missedBeforeTrigger \(lg.noTrigger) blocked \(lg.blocked)"
        }
        rep.reactionLog = bus.log
        rep.events = bus.eventCount
        // the plain-walk overlap bound is 0.04 here: the 3-Jelly lab shows walking frames up to +0.025 (and +0.03 after a trot) on the code BEFORE this round too (same seeds, same frames, measured on HEAD),
        // so the room soak guards the other limits (sole rise, centre height, radius, arms, the overlay frames) and the per-move suites (FeetAttach, the mid-walk test below) hold the strict ones
        if watchCaps { for g in rep.gapTags { MotionLog.write("LIVELY GAP \(g)") }; lab.checkAll("lively \(mood.rawValue) \(seed)", plainBound: 0.04) }
        return rep
    }

    func runMood(_ mood: BlobMood, maxPlain: Float) {
        var allKinds = Set<IdleKind>()
        var seenKinds = Set<String>()
        defer { MotionLog.write("LIVELY \(mood.rawValue) union of idle kinds seen: \(seenKinds.sorted())") }
        for seed in [101, 202] as [UInt64] {
            let r = Self.measure(seconds: 300, seed: seed, mood: mood)
            let flourishAll = r.flourishKinds.reduce(into: Set<IdleKind>()) { $0.formUnion($1) }
            allKinds.formUnion(flourishAll)
            for l in r.labels { for k in l.keys { seenKinds.insert(k) } }
            let rk = Set(r.reactionLog.map(\.kind))
            MotionLog.write("LIVELY \(mood.rawValue) seed \(seed): plain share \(r.plain.map { String(format: "%.2f", $0) }), flourish kinds per Jelly \(r.flourishKinds.map { $0.count }) starts \(r.flourishStarts), room kinds \(flourishAll.count) \(flourishAll.map(\.rawValue).sorted()), face changes/min \(r.faceChanges.map { Float($0) / 5 }), brow kinds \(r.browKinds.map { $0.count }), max quiet \(r.maxQuiet.map { String(format: "%.1f", $0) }), fast>2 frames \(r.over2) [\(r.fastTag)], legs \(r.legs), bus events \(r.events), reactions \(r.reactionLog.count) kinds \(rk.map(\.rawValue).sorted()), violations \(r.violations)")
            MotionLog.write("LIVELY \(mood.rawValue) seed \(seed) labels: \(r.labels.map { $0.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: " ") })")
            MotionLog.write("LIVELY \(mood.rawValue) seed \(seed) reactions: \(r.reactionLog.map { String(format: "%.0f:%@<-%@/%d", $0.t, $0.kind.rawValue, $0.event.rawValue, $0.reactor) }.joined(separator: " "))")
            for i in 0..<3 {
                XCTAssertLessThan(r.plain[i], maxPlain, "\(mood) seed \(seed) Jelly \(i): plain walk + stand time")
                XCTAssertGreaterThanOrEqual(r.flourishKinds[i].count, 4, "\(mood) seed \(seed) Jelly \(i): flourish kinds \(r.flourishKinds[i].map(\.rawValue))")
                XCTAssertGreaterThanOrEqual(Float(r.faceChanges[i]) / 5, 6, "\(mood) seed \(seed) Jelly \(i): face changes per minute")
                XCTAssertGreaterThanOrEqual(r.browKinds[i].count, 3, "\(mood) seed \(seed) Jelly \(i): brow expression kinds \(r.browKinds[i].map(\.rawValue))")
                XCTAssertLessThanOrEqual(r.maxQuiet[i], 12, "\(mood) seed \(seed) Jelly \(i): longest stretch with no event")
            }
            XCTAssertGreaterThanOrEqual(r.flourishKinds.reduce(0) { $0 + $1.count }, 8, "flourish kinds in the room (Jelly x kind)")
            XCTAssertGreaterThanOrEqual(flourishAll.count, 6, "distinct flourish kinds in the room \(flourishAll.map(\.rawValue).sorted())")
            XCTAssertEqual(r.over2, 0, "never more than two fast movers")
            XCTAssertGreaterThanOrEqual(r.reactionLog.count, 15, "reactions in 5 minutes")
            XCTAssertGreaterThanOrEqual(rk.count, 6, "distinct reaction kinds \(rk.map(\.rawValue).sorted())")
            XCTAssertEqual(r.violations, 0, "no reaction while reserved, asleep or racing")
        }
        XCTAssertTrue(seenKinds.contains("idle:rollTrip"), "the roll along a leg shows up in 2 x 300 s (\(mood))")
    }

    func testLivelyOkay300() { runMood(.okay, maxPlain: 0.55) }

    /// Grumpy room, 2 x 200 s: the sigh and the hmph puff both show up (and nothing jumps for joy).
    func testGrumpyRoomSighsAndHmphs() {
        var seen = Set<String>()
        for seed in [101, 202] as [UInt64] {
            let r = Self.measure(seconds: 200, seed: seed, mood: .grumpy)
            for l in r.labels { for k in l.keys { seen.insert(k) } }
            MotionLog.write("LIVELY grumpy seed \(seed): labels \(r.labels.map { $0.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: " ") }) reactions \(r.reactionLog.map { "\($0.kind.rawValue)<-\($0.event.rawValue)" })")
            XCTAssertEqual(r.violations, 0)
        }
        XCTAssertTrue(seen.contains("idle:hmph"), "a grumpy Jelly huffs \(seen.sorted())")
        XCTAssertTrue(seen.contains("idle:sigh"), "and sighs \(seen.sorted())")
    }
    func testLivelyHappy300() { runMood(.happy, maxPlain: 0.45) }

    /// The caps (stubby arms, attached feet) hold through a watched lively minute, every frame of every Jelly.
    func testCapsHoldThroughTheLivelyRoom() {
        let r = Self.measure(seconds: 90, seed: 303, mood: .happy, watchCaps: true)
        XCTAssertEqual(r.over2, 0)
    }

    /// Diagnostic: the same minute with the flourishes / reactions switched off, to see which behaviour a feet measurement belongs to (not a regression).
    func testDiagnoseCapsWithoutFlourishesOrReactions() throws {
        guard ProcessInfo.processInfo.environment["LIVELY_DIAG"] != nil else { throw XCTSkip("LIVELY_DIAG not set") }
        defer { FlourishTuning.enabled = true; ReactionRules.enabled = true }
        for (name, fl, re, toys) in [("no toys, everything on", true, true, false), ("no toys, flourishes + reactions off", false, false, false), ("toys, both off", false, false, true)] {
            FlourishTuning.enabled = fl; ReactionRules.enabled = re
            MotionLog.write("LIVELY DIAG \(name)")
            _ = Self.measure(seconds: 90, seed: 303, mood: .happy, watchCaps: true, toys: toys)
        }
    }

    /// Every flourish inserted between two steps of a walk: stubby arms and attached feet in every frame of it and of the steps after, and the walk resumes to its goal.
    func testEachFlourishMidWalkKeepsTheCapsAndResumesTheWalk() {
        for kind in [IdleKind.skipHop, .hopscotch, .legSpin, .trot, .stopLook, .rollTrip, .joy, .giggle, .startle] {
            let r = MotionRig(game: true)
            SocialTests.keep.append(r)
            r.renderSamples = false
            let b = r.brain
            b.autonomy = true; b.anticsEnabled = true; b.restTimer = 1e6; b.idleState.cooldown = 1e6; b.socialBook.cooldown = 1e6; b.expr.pickTimer = 1e6
            b.seed = 5
            r.sim.teleport(toXZ: SIMD2(-0.2, -0.5))
            for _ in 0..<120 { r.sim.step() }
            b.currentPose(r.sim)
            let start0 = r.root
            let goal = b.pickRunGoal(from: r.root, minD: 3.0, maxD: 4.4) ?? (r.root + SIMD2(0.4, 2.0))
            b.script = .walk(target: goal, then: .none); b.activity = .walking
            b.leg = LegState()
            var started = false
            switch kind {
            case .joy, .giggle, .startle:
                r.run(0.9)
                started = kind == .startle ? b.idleStart(kind, r.sim, goal: r.root + SIMD2(0, -0.25)) : b.idleStart(kind, r.sim)
                b.idleState.resume = goal
            default:
                // through the real hook: the walk's own step boundary starts it (kind chosen, trigger 0.4 u along the leg)
                r.run(0.1)
                b.leg.kind = kind; b.leg.wants = true; b.leg.rolled = false; b.leg.trigger = 0.4; b.leg.from = b.position
                r.run(3.0, until: { b.idleState.kind == kind })
                started = b.idleState.kind == kind
            }
            XCTAssertTrue(started, "\(kind) starts mid-walk through the walk's own hook: start0 \(start0) here \(b.position) goal \(goal) leg \(b.leg)")
            var w = SocialTests.Watch()
            var kinds = Set<String>()
            var closest = Float.infinity
            r.run(11) { w.sample(r); closest = min(closest, simd_distance(b.position, goal)); if let k = b.idleState.kind { kinds.insert(k.rawValue) } }
            w.check("flourish mid-walk \(kind)")
            MotionLog.write("FLOURISH \(kind): ran \(kinds.sorted()), came within \(String(format: "%.2f", closest)) u of the goal (\(String(format: "%.1f", simd_distance(r.root, goal) + closest)) u away at the start), idle \(String(describing: b.idleState.kind)) script \(b.script)")
            XCTAssertLessThan(closest, 0.9, "\(kind): the walk resumed and arrived")
        }
    }
}
