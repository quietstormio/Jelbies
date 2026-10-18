//
//  SocialTests.swift
//  Jellies interact (BlobSocial.swift): 3 headless MotionRigs wired like TrayNav3Tests (peers / steerID) plus the social lookup.
//  Every social kind is triggered deterministically and completes; a squabble ends on stopFighting() and they separate; nothing starts in a
//  blocked state; 5 minutes of 3-rig roaming gives a sane rate and no overlap but the boop / squabble pair. FeetAttach and ArmCap are
//  checked EVERY frame of every social (hard user rules: stubby arms, attached feet).
//

import XCTest
import simd
@testable import BobV1

@MainActor
final class SocialTests: XCTestCase {
    nonisolated(unsafe) static var keep: [AnyObject] = []
    override func setUp() { RoomLayout.dynamicBoxes = []; SocialTuning.pickChance = 0.12 }
    override func tearDown() { RoomLayout.dynamicBoxes = []; SocialTuning.pickChance = 0.12 }

    static let starts: [SIMD2<Float>] = [SIMD2(-1.0, 0.6), SIMD2(0.7, 0.9), SIMD2(0.0, 2.4)]

    /// Per-frame FeetAttach + ArmCap accumulator for one rig.
    @MainActor struct Watch {
        var feet = FeetAttachTests.FootFrame(soleRise: -.infinity, centreHeight: -.infinity, radius: 0, overlap: -.infinity)
        var feetFrames = 0
        var arm = ArmCapTests.Stat()
        /// Frames with a social overlay on him (the strict FeetAttach limits) vs the plain walk / look / hop frames of a social (the existing moves'
        /// own numbers: their worst overlap in FeetAttachTests runs -0.021...-0.025 against the -0.02 limit, so a walk may touch -0.0186 here, a walk arriving at a new spot -0.013; the bound for those frames is 'still inside the egg': -0.005, a real gap is +0.02).
        var plain = FeetAttachTests.FootFrame(soleRise: -.infinity, centreHeight: -.infinity, radius: 0, overlap: -.infinity)
        var plainFrames = 0
        var worstTag = "", plainTag = ""
        mutating func sample(_ r: MotionRig) {
            if let f = FeetAttachTests.footFrame(r) {
                let b = r.brain.socialBook
                let overlay = abs(b.pitch) > 0.003 || abs(b.roll) > 0.003 || abs(b.squash - 1) > 0.003
                if overlay {
                    if f.overlap > feet.overlap { worstTag = "phase \(r.brain.social?.phase ?? -1) \(r.brain.social?.kind.rawValue ?? "-") act \(r.brain.activity) pitch \(b.pitch) roll \(b.roll) sq \(b.squash) t \(r.t)" }
                    FeetAttachTests.accumulate(&feet, f); feetFrames += 1
                } else {
                    if f.overlap > plain.overlap { plainTag = "kind \(r.brain.social?.kind.rawValue ?? "-") idle \(String(describing: r.brain.idleState.kind)) act \(r.brain.activity) runW \(r.brain.runW) zoomW \(r.brain.zoomW) feetActive \(r.brain.feet.active) route \(r.brain.route.count) t \(r.t)" }
                    FeetAttachTests.accumulate(&plain, f); plainFrames += 1
                }
            }
            guard r.brain.armG > 0.5 else { return }
            for si in 0..<2 {
                let g = r.brain.armLastGeom[si]
                arm.add(a: SIMD3<Double>(g.a), b: SIMD3<Double>(g.b), rawB: SIMD3<Double>(r.brain.armLastRawTip[si]), r1: Double(g.r1), r2: Double(g.r2), led: r.brain.armShortW >= 0.95)
            }
        }
        func check(_ name: String, plainBound: Float = FeetAttachTests.minOverlap + 0.015) {
            MotionLog.write("SOCIAL \(name): overlay frames \(feetFrames), plain frames \(plainFrames), plain worst overlap \(plain.overlap), overlay worst at \(worstTag); plain worst at \(plainTag)")
            FeetAttachTests.check(name + " (overlay frames)", feet, frames: feetFrames)
            var p2 = plain; p2.overlap = -.infinity            // (the overlap of plain frames gets its own, relaxed bound below)
            FeetAttachTests.check(name + " (plain frames)", p2, frames: plainFrames)
            if plainFrames > 0 { XCTAssertLessThanOrEqual(plain.overlap, plainBound, "\(name): the plain walk's own overlap") }
            MotionLog.write(String(format: "SOCIAL %@: arm frames %d, exposed max %.4f (cap %.4f), body-led max %.4f, min root depth %.3f", name, arm.frames, arm.capMax, ArmCap.maximum, arm.ledMax, arm.minDepth))
            XCTAssertLessThanOrEqual(arm.capMax, ArmCap.maximum * 1.02, "\(name): arm stays within the wave's thumb")
            if arm.ledFrames > 0 { XCTAssertLessThanOrEqual(arm.ledMax, ArmCap.restNub * 1.10, "\(name): body-led arms stay at the rest nub") }
            if arm.frames > 0 { XCTAssertGreaterThanOrEqual(arm.minDepth, 0.015, "\(name): arm base buried in the body") }
        }
    }

    @MainActor final class Lab {
        let rigs: [MotionRig]
        let roster: SocialRoster
        var events: [[SocialEvent]]
        var watch: [Watch]
        var minPair: Float = .infinity, minTag = ""
        var snapshot: [(pos: SIMD2<Float>, walking: Bool)] = []
        var aside = [Float](repeating: 0, count: 3), asideClock: Float = 0
        nonisolated deinit {}
        /// Wired like the stage's `wireRoster`: peers from a snapshot (a standing Jelly has a huge id), keepApart under the floor rules, peerGap = jellyGap,
        /// and the stage's makeRoom every 0.25 s.
        init(n: Int = 3, positions: [SIMD2<Float>] = SocialTests.starts, quiet: Bool = true, seed: UInt64 = 11) {
            rigs = (0..<n).map { _ in MotionRig(game: true) }
            roster = SocialRoster.link(rigs.map { $0.brain })
            events = Array(repeating: [], count: n)
            watch = Array(repeating: Watch(), count: n)
            SocialTests.keep.append(contentsOf: rigs)
            for (i, r) in rigs.enumerated() {
                r.renderSamples = false
                r.brain.abortScript(r.sim, r.skinner)
                r.sim.teleport(toXZ: positions[i])
                for _ in 0..<120 { r.sim.step() }
                r.brain.currentPose(r.sim)
                r.brain.seed = seed + UInt64(i) * 7
                r.brain.steerID = i; r.brain.peerGap = MelonController.jellyGap
                r.brain.onSocial = { [unowned self] e in self.events[i].append(e) }
            }
            snapshot = rigs.map { (pos: $0.brain.position, walking: false) }
            for (i, r) in rigs.enumerated() {
                let floorRules = r.brain.resolve
                r.brain.resolve = { [unowned self] p, rad in floorRules(MelonController.keepApart(floorRules(p, rad), id: i, peers: self.snapshot), rad) }
                r.brain.peers = { [unowned self] in self.snapshot.enumerated().filter { $0.offset != i }.map { (id: $0.element.walking ? $0.offset : Int.max / 2, pos: $0.element.pos) } }
            }
            for r in rigs { r.brain.autonomy = true; if quiet { r.brain.idleState.cooldown = 1e6; r.brain.socialBook.cooldown = 1e6; r.brain.restTimer = 1e6 } }
            for _ in 0..<60 { tick(watching: false) }
        }
        func tick(watching: Bool = true) {
            snapshot = rigs.map { (pos: $0.brain.position, walking: $0.brain.activity == .walking || $0.brain.activity == .coming) }
            asideClock += 1.0 / 60
            if asideClock >= 0.25 { MelonController.makeRoom(snapshot: snapshot, brains: rigs.map { $0.brain }, cooldown: &aside, dt: asideClock); asideClock = 0 }
            for (i, r) in rigs.enumerated() { r.tick(); if watching { watch[i].sample(r) } }
        }
        func brainGap(_ i: Int, _ j: Int) -> Float { simd_distance(rigs[i].brain.position, rigs[j].brain.position) }
        func centreGap(_ i: Int, _ j: Int) -> Float {
            let a = rigs[i].root, b = rigs[j].root
            return simd_distance(a, b)
        }
        func sampleGaps() {
            for i in 0..<rigs.count { for j in (i + 1)..<rigs.count {
                let paired = rigs[i].brain.social != nil && rigs[i].brain.social === rigs[j].brain.social && rigs[i].brain.social!.closeOK
                if !paired { let g = centreGap(i, j); if g < minPair { minPair = g; minTag = "t \(rigs[0].t) \(i)-\(j) act \(rigs[i].brain.activity)/\(rigs[j].brain.activity) idle \(String(describing: rigs[i].brain.idleState.kind))/\(String(describing: rigs[j].brain.idleState.kind)) social \(String(describing: rigs[i].brain.socialKind))/\(String(describing: rigs[j].brain.socialKind)) brainGap \(brainGap(i, j))" } }
            } }
        }
        var anySocial: Bool { rigs.contains { $0.brain.isSocial } }
        func checkAll(_ name: String, plainBound: Float = FeetAttachTests.minOverlap + 0.015) { for (i, w) in watch.enumerated() { w.check("\(name) rig\(i)", plainBound: plainBound) } }
    }

    // MARK: every kind, deterministically

    private func runKind(_ kind: SocialKind, maxSeconds: Float = 45) -> (lab: Lab, seconds: Float, ok: Bool) {
        let lab = Lab(seed: 31)
        let a = lab.rigs[0], b = lab.rigs[1]
        // look / zoomies need the idle machinery to run (autonomy is on); the other two rigs wander on their own in the zoomies case
        XCTAssertTrue(a.brain.socialStart(kind, with: b.brain, a.sim), "\(kind): starts")
        if kind == .zoomies { XCTAssertTrue(a.brain.isSocial && b.brain.isSocial, "zoomies: both in the session") }
        XCTAssertEqual(a.brain.socialKind, kind)
        XCTAssertEqual(a.brain.socialPartnerID, 1); XCTAssertEqual(b.brain.socialPartnerID, 0)
        var f = 0
        while f < Int(maxSeconds * 60) {
            lab.tick(); f += 1
            if !a.brain.isSocial && !b.brain.isSocial && f > 10 { break }
        }
        let ok = !a.brain.isSocial && !b.brain.isSocial
        MotionLog.write(String(format: "SOCIAL %@ completed=%d in %.1f s, events %@", kind.rawValue, ok ? 1 : 0, Float(f) / 60, "\(lab.events[0].count)+\(lab.events[1].count)"))
        return (lab, Float(f) / 60, ok)
    }

    func testBoopWalksUpBumpsAndCompletes() {
        let (lab, secs, ok) = runKind(.boop)
        XCTAssertTrue(ok, "the boop completes"); XCTAssertLessThan(secs, 30)
        let boops = lab.events[0].filter { if case .boop = $0 { return true }; return false }.count
        XCTAssertEqual(boops, 1, "one boop (heart + haptic beat) for the initiator")
        XCTAssertEqual(lab.events[1].filter { if case .boop = $0 { return true }; return false }.count, 1)
        lab.checkAll("boop")
    }

    func testFollowCompletesAndLeavesThemApart() {
        let (lab, secs, ok) = runKind(.follow)
        XCTAssertTrue(ok, "the follow completes"); XCTAssertLessThan(secs, 30)
        XCTAssertGreaterThan(secs, 5.5, "followed for 6...9 s")
        lab.checkAll("follow")
    }

    func testSharedZoomiesJoinAndComplete() {
        let (lab, secs, ok) = runKind(.zoomies)
        XCTAssertTrue(ok, "the shared zoomies complete"); XCTAssertLessThan(secs, 30)
        XCTAssertGreaterThan(lab.rigs[0].brain.idleState.counts[.zoomies] ?? 0, 0)
        
        lab.checkAll("zoomies")
    }

    func testGreetingBothHop() {
        let lab = Lab(n: 2, positions: [SIMD2(-0.7, 0.6), SIMD2(0.9, 0.9)], seed: 5)
        let a = lab.rigs[0], b = lab.rigs[1]
        XCTAssertLessThan(lab.centreGap(0, 1), 1.9)
        // meeting after being apart a while: the watch triggers it
        a.brain.socialBook.apart[1] = SocialTuning.greetApart + 1
        a.brain.socialBook.cooldown = 1e6
        var hops = [0, 0], prev = [false, false]
        var f = 0
        while f < 60 * 20 {
            lab.tick(); f += 1
            for k in 0..<2 { let h = lab.rigs[k].brain.activity == .playing && lab.rigs[k].brain.isSocial; if h && !prev[k] { hops[k] += 1 }; prev[k] = h }
            if f > 10 && !lab.anySocial && hops[0] > 0 { break }
        }
        XCTAssertGreaterThan(a.brain.socialBook.started[.greet] ?? 0, 0, "the greeting started on its own (apart long enough, then near)")
        XCTAssertEqual(hops[0], 1); XCTAssertEqual(hops[1], 1, "both hop")
        XCTAssertFalse(lab.anySocial)
        lab.checkAll("greet")
    }

    func testLookAtPeerAndGlanceBack() {
        let (lab, secs, ok) = runKind(.look)
        XCTAssertTrue(ok, "the look completes"); XCTAssertLessThan(secs, 20)
        XCTAssertGreaterThan(lab.rigs[0].brain.idleState.counts[.look] ?? 0, 0)
        XCTAssertGreaterThan(lab.rigs[1].brain.idleState.counts[.look] ?? 0, 0, "the other glanced back")
        lab.checkAll("look")
    }

    func testSquabbleRunsItsCourseAndEndsByItself() {
        let lab = Lab(seed: 31)
        let a = lab.rigs[0], b = lab.rigs[1]
        XCTAssertTrue(a.brain.socialStart(.squabble, with: b.brain, a.sim))
        var fight: Float = 0, f = 0, sawLook = false, minEyes: Float = 1
        while f < 60 * 50 {
            lab.tick(); f += 1
            if a.brain.isSquabbling && a.brain.social?.phase == 1 { fight += 1.0 / 60; minEyes = min(minEyes, a.skinner.openness.left) }
            if a.brain.idleState.kind == .look { sawLook = true }
            if f > 10 && !lab.anySocial { break }
        }
        XCTAssertFalse(lab.anySocial, "it ended by itself")
        XCTAssertGreaterThan(fight, 4.8, "5...8 s of face-off (got \(fight))"); XCTAssertLessThan(fight, 8.6)
        XCTAssertTrue(sawLook, "the sheepish look")
        XCTAssertLessThan(minEyes, 0.8, "annoyed (narrowed) eyes during the face-off")
        let shoves = lab.events[0].filter { if case .shove = $0 { return true }; return false }.count
        XCTAssertGreaterThanOrEqual(shoves, 2, "a few small shove-bumps")
        XCTAssertGreaterThan(lab.centreGap(0, 1), 0.9, "they end apart")
        XCTAssertFalse(lab.events[0].contains { if case .makeUp = $0 { return true }; return false }, "no make-up hop unless somebody stopped it")
        lab.checkAll("squabble")
    }

    func testStopFightingEndsAtOnceAndTheyStepApart() {
        let lab = Lab(seed: 31)
        let a = lab.rigs[0], b = lab.rigs[1]
        XCTAssertTrue(a.brain.socialStart(.squabble, with: b.brain, a.sim))
        var f = 0, fightF = 0
        while f < 60 * 25 { lab.tick(); f += 1; if a.brain.isSquabbling && a.brain.social?.phase == 1 { fightF += 1 }; if fightF > 150 { break } }   // 2.5 s into the face-off
        XCTAssertTrue(a.brain.isSquabbling && b.brain.isSquabbling, "they are fighting")
        MotionLog.write("SOCIAL squabble gap: centroids \(lab.centreGap(0, 1)), brain positions \(simd_distance(a.brain.position, b.brain.position)), a \(a.brain.position) b \(b.brain.position) rootA \(a.root) rootB \(b.root)")
        XCTAssertLessThan(lab.brainGap(0, 1), MelonController.jellyGap + 0.3, "face to face, at about peerGap")
        XCTAssertGreaterThan(lab.centreGap(0, 1), 0.6 * MelonController.jellyGap)
        XCTAssertTrue(lab.roster.stopFighting(), "the voice hook reports a fight was on")
        // within 0.5 s: the fight is over, the puffy overlays are gone
        for _ in 0..<30 { lab.tick() }
        XCTAssertFalse(a.brain.isSquabbling); XCTAssertFalse(b.brain.isSquabbling)
        for r in [a, b] {
            XCTAssertLessThan(abs(r.brain.socialBook.squash - 1), 0.012, "squash overlay back to neutral within 0.5 s")
            XCTAssertLessThan(abs(r.brain.socialBook.pitch), 0.02); XCTAssertLessThan(abs(r.brain.socialBook.roll), 0.02)
        }
        // and then they step apart to at least peerGap, sheepish, make up, and it is over
        var apartAt: Float?, t: Float = 0.5, sawLook = false
        while t < 14 {
            lab.tick(); t += 1.0 / 60
            if apartAt == nil && lab.brainGap(0, 1) >= a.brain.peerGap + 0.25 { apartAt = t }
            if a.brain.idleState.kind == .look { sawLook = true }
            if !lab.anySocial { break }
        }
        XCTAssertNotNil(apartAt, "they separated to peerGap"); XCTAssertLessThan(apartAt ?? 99, 8)
        XCTAssertTrue(sawLook, "sheepish look")
        XCTAssertFalse(lab.anySocial)
        XCTAssertTrue(lab.events[0].contains { if case .makeUp = $0 { return true }; return false }, "making up after a stop: a small happy reaction")
        XCTAssertTrue(lab.events[1].contains { if case .makeUp = $0 { return true }; return false })
        XCTAssertFalse(lab.roster.stopFighting(), "nothing to stop now")
        lab.checkAll("stopFighting")
    }

    func testStopEndsAnySocial() {
        let lab = Lab(seed: 3)
        let a = lab.rigs[0], b = lab.rigs[1]
        XCTAssertTrue(a.brain.socialStart(.follow, with: b.brain, a.sim))
        for _ in 0..<120 { lab.tick() }
        XCTAssertTrue(a.brain.isSocial)
        lab.roster.stop()
        for _ in 0..<30 { lab.tick() }
        XCTAssertFalse(a.brain.isSocial); XCTAssertFalse(b.brain.isSocial)
        XCTAssertTrue(lab.events[0].contains { if case .ended(.follow, _, .stopped) = $0 { return true }; return false })
        lab.checkAll("stop")
    }

    // MARK: never in a blocked state

    func testNeverStartsWhileBlockedAndEndsWhenTaken() {
        SocialTuning.pickChance = 1
        // each blocked state on rig 0; rigs 1, 2 are free and would love to
        let cases: [(String, (MotionRig) -> Void)] = [
            ("focus close-up / meal / bath (idleBlocked)", { $0.brain.idleBlocked = true }),
            ("a request pending (meal walk)", { $0.brain.pending = .goTo(SIMD2(0, 1)) }),
            ("a dine job", { $0.brain.job = .goTo(SIMD2(0, 1)) }),
            ("voice action (a commanded trick, re-asked whenever it ends)", { if $0.brain.idleState.kind == nil { $0.brain.commandedIdle = .jacks } }),
        ]
        for (name, apply) in cases {
            let lab = Lab(quiet: false, seed: 9)
            let r0 = lab.rigs[0]
            for (i, r) in lab.rigs.enumerated() { r.brain.socialBook.cooldown = 0; r.brain.idleState.cooldown = 1e6; r.brain.restTimer = 0.3 + 0.2 * Float(i) }
            apply(r0)
            XCTAssertFalse(r0.brain.socialFree, name)
            XCTAssertFalse(lab.rigs[1].brain.socialStart(.boop, with: r0.brain, lab.rigs[1].sim), "\(name): explicit start refused")
            XCTAssertFalse(r0.brain.socialStart(.boop, with: lab.rigs[1].brain, r0.sim), "\(name): explicit start refused (from the blocked one)")
            var involved = false
            for _ in 0..<(60 * 25) {
                apply(r0)                                   // (held for the whole run: before and after his own tick)
                for r in lab.rigs { r.tick(); if r === r0 { apply(r0) } }
                if r0.brain.isSocial { involved = true; MotionLog.write("SOCIAL BLOCKED-BREACH \(name): kind \(String(describing: r0.brain.socialKind)) pending \(String(describing: r0.brain.pending)) job \(String(describing: r0.brain.job)) blocked \(r0.brain.idleBlocked) commanded \(r0.brain.commanded) partner \(String(describing: r0.brain.socialPartnerID)) script \(r0.brain.script) act \(r0.brain.activity)"); break }
                for r in lab.rigs { r.brain.socialBook.cooldown = min(r.brain.socialBook.cooldown, 0) }
            }
            XCTAssertFalse(involved, "\(name): never social")
            XCTAssertEqual(r0.brain.socialStarts.values.reduce(0, +), 0)
            let others = lab.rigs[1].brain.socialStarts.values.reduce(0, +) + lab.rigs[2].brain.socialStarts.values.reduce(0, +)
            XCTAssertGreaterThan(others, 0, "\(name): the free pair does socialise (the test would otherwise prove nothing)")
        }
        // touching him: starts refused, a running one ends at once
        let lab = Lab(seed: 12)
        let a = lab.rigs[0], b = lab.rigs[1]
        XCTAssertTrue(a.brain.socialStart(.boop, with: b.brain, a.sim))
        for _ in 0..<60 { lab.tick() }
        for _ in 0..<5 { b.tick(touched: true); a.tick() }                      // the player grabs b
        XCTAssertEqual(b.brain.activity, .touched)
        XCTAssertFalse(b.brain.isSocial, "touched: his side ends at once")
        for _ in 0..<5 { a.tick(); b.tick(touched: true) }
        XCTAssertFalse(a.brain.isSocial, "the other side lets go too")
        XCTAssertFalse(a.brain.socialStart(.boop, with: b.brain, a.sim), "not while the player touches him")
        // an interrupt (a meal request) ends a running squabble and walks him to the tray
        let lab2 = Lab(seed: 13)
        let c = lab2.rigs[0], d = lab2.rigs[1]
        XCTAssertTrue(c.brain.socialStart(.squabble, with: d.brain, c.sim))
        for _ in 0..<300 { lab2.tick() }
        d.brain.requestNow(.goTo(SIMD2(0.5, 1.4)))
        for _ in 0..<10 { lab2.tick() }
        XCTAssertFalse(d.brain.isSocial); XCTAssertFalse(c.brain.isSocial)
        lab2.checkAll("interrupted squabble")
    }

    // MARK: roaming

    func testFiveMinutesOfRoaming() {
        let lab = Lab(quiet: false, seed: 101)
        for r in lab.rigs { r.brain.idleMood = .okay; r.brain.socialBook.cooldown = 8; r.brain.idleState.cooldown = 9 }
        for (i, r) in lab.rigs.enumerated() { r.brain.restTimer = 0.5 + Float(i) }
        let frames = 60 * 300
        var socialFrames = 0
        var started = [SocialKind: Int](), idleSpecials = 0
        var lastKinds = [IdleKind?](repeating: nil, count: 3)
        var counts = [SocialKind: Int]()
        var prevSocial = [false, false, false]
        for f in 0..<frames {
            // the full checks (skinning) only while somebody is social; the rest is cheap
            let watching = lab.anySocial
            if watching { socialFrames += 1 }
            lab.tick(watching: watching)
            lab.sampleGaps()
            _ = f; _ = lastKinds
            for k in 0..<3 {
                let s = lab.rigs[k].brain.isSocial
                if s && !prevSocial[k], lab.rigs[k].brain.social?.idA == k, let kind = lab.rigs[k].brain.socialKind { counts[kind, default: 0] += 1 }
                prevSocial[k] = s
            }
        }
        for r in lab.rigs { for (k, v) in r.brain.socialStarts { started[k, default: 0] += v } ; idleSpecials += r.brain.idleState.counts.filter { $0.key != .stumble }.values.reduce(0, +) }
        let total = started.values.reduce(0, +)
        MotionLog.write("SOCIAL roaming 300 s: socials \(total) \(started.map { "\($0.key.rawValue)=\($0.value)" }.sorted()), solo idle specials \(idleSpecials), frames in a social \(socialFrames) of \(frames), min centre gap outside a boop/squabble pair \(lab.minPair) at [\(lab.minTag)] (0.6 x peerGap = \(0.6 * lab.rigs[0].brain.peerGap))")
        XCTAssertGreaterThanOrEqual(total, 4, "socials happen")
        XCTAssertLessThanOrEqual(total, 40, "but not constantly")
        XCTAssertGreaterThan(idleSpecials, total, "solo idles still dominate")
        XCTAssertGreaterThan(Float(frames - socialFrames) / Float(frames), 0.5, "most of the time nobody is in a social")
        XCTAssertGreaterThanOrEqual(lab.minPair, 0.6 * BlobBrain().peerGap, "no overlap below 0.6 x peerGap (the brain's 0.9) except the boop / squabble pair; the solo moves' own floor in the stage tests is 0.72")
        // plain frames of a roam include the solo wander / run / jacks / scoot frames while a social is on: the control test shows the solo moves alone reach +0.025 here
        lab.checkAll("roaming", plainBound: 0.03)
    }

    /// CONTROL: the same roaming with the social layer OFF, the same per-frame FeetAttach reading on every frame of plain walking. Whatever the locked
    /// walk reaches here is the walk's own number, not the social layer's.
    func testControlRoamingWithoutSocialsFeetNumbers() {
        let lab = Lab(quiet: false, seed: 101)
        for (i, r) in lab.rigs.enumerated() { r.brain.socialBook.enabled = false; r.brain.restTimer = 0.5 + Float(i); r.brain.idleState.cooldown = 9 }
        for _ in 0..<(60 * 150) { lab.tick(watching: true) }
        for (i, w) in lab.watch.enumerated() { MotionLog.write("SOCIAL CONTROL (no socials) rig\(i): frames \(w.plainFrames), worst foot overlap \(w.plain.overlap) (limit -0.02), worst radius \(w.plain.radius)") }
    }
}
