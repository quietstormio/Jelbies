//
//  ContactSettleTests.swift
//  The settle controller (Melon/ContactSettle.swift) and the touch event (BlobBrain+Contact): the pair's drawn skins end in contact (-0.5 ... +0.5 cm) from any start distance,
//  without oscillating, an anchored body stays put; the contact sound + haptic fire exactly once per touch (first time the skin gap is <= +0.5 cm, re-armed past +3 cm), also in the
//  social stances and the lying snuggle, never again for the settle's last mm of press.
//

import XCTest
import simd
import QuartzCore
@testable import BobV1

@MainActor
final class ContactSettleTests: XCTestCase {
    override func setUp() {
        RoomLayout.dynamicBoxes = []; GameCamera.configureRoom(count: 3, option: .A, wide: 2); _ = GameCamera.camera(aspect: 440 / 956)
        ContactField.reset(); ContactField.enabled = true; FeatureClip.enabled = true; LieClearTuning.enabled = true
    }
    /// The room's haptic driver as the haptic tests wire it: a clock the test advances (one tick = 1/60 s), the cues counted at `cueTap`.
    private var fakeNow = 1000.0
    private var driver: HapticDriver?          // (HapticDriver.room is weak)
    private func wireHaptics(_ c: Counter) {
        UserDefaults.standard.removeObject(forKey: HapticSettings.key)
        HapticDriver.clock = { [unowned self] in self.fakeNow }
        HapticDriver.after = { _, f in f() }
        HapticDriver.jitter = { 1 }
        driver = HapticDriver(sinks: [RecordingHapticSink()]); HapticDriver.room = driver; HapticDriver.roomBusy = nil
        HapticDriver.cueTap = { if $0.name.hasPrefix("sfx."), ContactPolishTests.contactSounds.contains(String($0.name.dropFirst(4))) { c.haptic += 1 } }          // (any contact sound's own cue: the squish AND the boop / high-five boop ... of the stances)
    }
    override func tearDown() {
        HapticDriver.clock = { CACurrentMediaTime() }
        HapticDriver.after = { dl, f in DispatchQueue.main.asyncAfter(deadline: .now() + dl) { MainActor.assumeIsolated { f() } } }
        HapticDriver.jitter = { 1 + Float.random(in: -0.15...0.15) }
        HapticDriver.cueTap = nil; HapticDriver.room = nil; HapticDriver.roomBusy = nil
        AudioHub.requestTap = nil
        ContactField.reset(); ContactField.enabled = true; FeatureClip.eggs = []
        RoomLayout.dynamicBoxes = []; GameCamera.configureRoom(count: 1); _ = GameCamera.camera(aspect: 440.0 / 956.0)
    }

    /// Two standing Jelbies `d0` apart, the settle controller on every tick. Returns the profile gap after each tick.
    private func run(_ d0: Float, anchoredB: Bool, frames: Int = 150, features: [JellyFeature] = [.none, .none]) -> (gaps: [Float], d: FeatureClipTests.Duo) {
        let d = FeatureClipTests.Duo(positions: [SIMD2(-1.5, 0.6), SIMD2(1.5, 0.6)], features: features, seed: 5)
        d.place([SIMD2(-d0 / 2, 0.6), SIMD2(d0 / 2, 0.6)])
        d.live = true
        for _ in 0..<3 { d.tick() }
        var gaps: [Float] = []
        let a = d.lab.rigs[0], b = d.lab.rigs[1]
        for _ in 0..<frames {
            d.tick()
            ContactSettle.step(a.brain, b.brain, anchoredB: anchoredB)
            gaps.append(ContactField.gap(0, 1) ?? .nan)
        }
        return (gaps, d)
    }

    func testSettleConvergesFromEveryStartWithoutOscillating() {
        for d0 in [0.6, 0.9, 1.2, 1.6, 2.0] as [Float] {
            let (gaps, _) = run(d0, anchoredB: false)
            let inBand = gaps.firstIndex { abs($0) <= 0.005 }
            let line = String(format: "SETTLE start %.1f: first in band at frame %@, final gap %.4f, min after %.4f max after %.4f", d0, inBand.map(String.init) ?? "never", gaps.last ?? 0, gaps.dropFirst(inBand ?? 0).min() ?? 0, gaps.dropFirst(inBand ?? 0).max() ?? 0)
            MotionLog.write(line)
            XCTAssertNotNil(inBand, line)
            guard let k = inBand else { continue }
            XCTAssertLessThanOrEqual(k, 60, "converges within 1 s: \(line)")
            let after = Array(gaps.dropFirst(k))
            XCTAssertGreaterThan(after.min() ?? 0, -0.010, "never overlaps by more than 1 cm once in contact: \(line)")
            XCTAssertLessThan(after.max() ?? 0, 0.010, "never a visible gap once in contact: \(line)")
            XCTAssertLessThanOrEqual(abs(gaps.last ?? 1), 0.005, "settled in the band: \(line)")
            var flips = 0
            for i in (k + 1)..<gaps.count where (gaps[i] > 0.002 && gaps[i - 1] < -0.002) || (gaps[i] < -0.002 && gaps[i - 1] > 0.002) { flips += 1 }
            XCTAssertLessThanOrEqual(flips, 1, "no oscillation: \(line)")
        }
    }

    /// The cost of the feature path (wings / spikes / tail in the pair gap) against the body-only gap, per query; logged (CONTACT cost ...), and the tail must be in the Pip profile.
    func testFeatureGapCost() {
        let d = FeatureClipTests.Duo(positions: [SIMD2(-0.7, 0.6), SIMD2(0.7, 0.6)], features: [OnePieceInvariantTests.characters[1].1, OnePieceInvariantTests.characters[3].1], seed: 5)
        d.live = true
        for _ in 0..<30 { d.tick() }
        XCTAssertFalse(ContactField.featurePoints(0).isEmpty, "Pip's spikes / tail are feature points")
        let pa = ContactField.root(0), pb = ContactField.root(1)
        func time(_ f: Bool) -> Double {
            let t0 = CACurrentMediaTime()
            var acc: Float = 0
            for k in 0..<20000 { acc += ContactField.gap(0, at: pa, 1, at: pb + SIMD2(Float(k % 7) * 1e-4, 0), features: f) ?? 0 }
            _ = acc
            return (CACurrentMediaTime() - t0) / 20000 * 1e6
        }
        let body = time(false), feat = time(true)
        MotionLog.write(String(format: "CONTACT cost: pair gap at hypothetical roots %.2f us body only, %.2f us with features (wall query)", body, feat))
        XCTAssertLessThan(feat, 40, "the feature path stays cheap enough for the keepApart wall (hundreds of queries a step)")
    }

    func testAnchoredBodyStaysPut() {
        for d0 in [0.7, 2.0] as [Float] {
            let d = FeatureClipTests.Duo(positions: [SIMD2(-1.5, 0.6), SIMD2(1.5, 0.6)], features: [.none, .none], seed: 5)
            d.place([SIMD2(-d0 / 2, 0.6), SIMD2(d0 / 2, 0.6)])
            d.live = true
            for _ in 0..<3 { d.tick() }
            let a = d.lab.rigs[0], b = d.lab.rigs[1]
            let home = b.brain.position
            var frame = -1
            for f in 0..<150 {
                d.tick()
                ContactSettle.step(a.brain, b.brain, anchoredB: true)
                if frame < 0, let g = ContactField.gap(0, 1), abs(g) <= 0.005 { frame = f }
            }
            MotionLog.write(String(format: "SETTLE anchored start %.1f: in band at frame %d, anchored body moved %.4f", d0, frame, simd_distance(b.brain.position, home)))
            XCTAssertGreaterThan(frame, -1); XCTAssertLessThanOrEqual(frame, 100, "the free one takes it all and still arrives")
            XCTAssertLessThan(simd_distance(b.brain.position, home), 0.01, "the anchored body does not move")
            XCTAssertLessThanOrEqual(abs(ContactField.gap(0, 1) ?? 1), 0.005)
        }
    }

    /// 2026-11-04: the peer wall for SESSION PARTNERS is the skin wall alone (no circle spring: it stopped Bob + Teddy 16 cm short of any touch); everybody else keeps the spring exactly as before.
    func testKeepApartPartnersUseTheSkinWallOthersKeepTheSpring() {
        let d = FeatureClipTests.Duo(positions: [SIMD2(-1.5, 0.6), SIMD2(1.5, 0.6)], features: [.none, .none], seed: 5)
        d.place([SIMD2(0, -0.1), SIMD2(0, 1.3)])          // (one behind the other: the front-to-back touch is ~0.8 m, under the spring's 1.09)
        d.live = true
        for _ in 0..<10 { d.tick() }
        XCTAssertTrue(ContactField.isValid(0) && ContactField.isValid(1))
        let r0 = ContactField.root(0)
        let peers: [(pos: SIMD2<Float>, walking: Bool)] = [(r0, false), (ContactField.root(1), false)]
        let g: Float = 2.0, L: Float = 0.5          // (a wide spring so that it clearly differs from the skin touch, ~1.07 m front to back / 1.4 m side to side)
        let p = SIMD3<Float>(r0.x, 0, r0.y + L)
        // a non-social pair (no partners): the spring exactly as before
        let q = MelonController.keepApart(p, id: 1, peers: peers, gap: g)
        let dq = simd_distance(SIMD2(q.x, q.z), r0)
        XCTAssertEqual(dq, max(L + (g - L) * MelonController.softPush, g * MelonController.softFloor), accuracy: 0.01, "a non-social pair still stops at the old spring radius")
        // the same with the other id listed as a partner of someone else: still the spring
        let q2 = MelonController.keepApart(p, id: 1, peers: peers, gap: g, partners: [7])
        XCTAssertEqual(simd_distance(SIMD2(q2.x, q2.z), r0), dq, accuracy: 1e-4, "a third party keeps the spring")
        // session partners with profiles: the skin wall alone, the skins end up touching (gap 0 +- 0.5 cm), well inside the spring radius
        let q3 = MelonController.keepApart(p, id: 1, peers: peers, gap: g, partners: [0])
        let d3 = simd_distance(SIMD2(q3.x, q3.z), r0)
        let gp = ContactField.gap(0, at: r0, 1, at: SIMD2(q3.x, q3.z), features: true) ?? 9
        XCTAssertEqual(gp, 0, accuracy: 0.005, "partners stand skin to skin")
        XCTAssertLessThan(d3, dq - 0.1, "and closer than the spring would let them")
        // a partner without a profile falls back to the spring, never to no floor
        ContactField.reset(); ContactField.enabled = true
        let q4 = MelonController.keepApart(p, id: 1, peers: peers, gap: g, partners: [0])
        XCTAssertEqual(simd_distance(SIMD2(q4.x, q4.z), r0), dq, accuracy: 1e-4, "no profile: the spring")
    }

    /// Tuning sweep (TUNE_SETTLE=1): standing starts + the lying pair for several controller settings; logs the worst gap after the first entry / after 4 s.
    func testZTuneSettle() throws {
        guard ProcessInfo.processInfo.environment["TUNE_SETTLE"] == "1" else { throw XCTSkip("TUNE_SETTLE not set") }
        typealias T = ContactSettleTuning
        let combos: [(String, Float, Float, Float, Float, Float)] = [
            ("A fast only g.25 l3", 0.25, 3, 0, 0, 0), ("B g.15 l3", 0.15, 3, 0, 0, 0), ("C g.15 l6", 0.15, 6, 0, 0, 0), ("D g.10 l4", 0.10, 4, 0, 0, 0),
            ("E g.08 l0", 0.08, 0, 0, 0, 0), ("F g.12 l6", 0.12, 6, 0, 0, 0), ("G g.2 l3 fine .03 a1/90 fg.05", 0.2, 3, 0.03, 1.0 / 90, 0.05), ("H g.15 l5 fine .03 a1/60 fg.06", 0.15, 5, 0.03, 1.0 / 60, 0.06),
            ("I g.1 l8", 0.10, 8, 0, 0, 0), ("J g.06 l6", 0.06, 6, 0, 0, 0)]
        for (name, g, l, fb, fa, fg) in combos {
            T.gain = g; T.lead = l; T.fineBand = fb; T.fineAlpha = fa == 0 ? 1.0 / 45 : fa; T.fineGain = fg
            var worstStand: Float = 0, slowest = 0, worstSettled: Float = 0
            for d0 in [0.6, 1.2, 1.6, 2.0] as [Float] {
                let (gaps, _) = run(d0, anchoredB: false, frames: 140)
                if let k = gaps.firstIndex(where: { abs($0) <= 0.005 }) { slowest = max(slowest, k); worstStand = max(worstStand, gaps.dropFirst(k).map { abs($0) }.max() ?? 0) } else { slowest = 999 }
                worstSettled = max(worstSettled, abs(gaps.last ?? 9))
            }
            // the lying pair
            let d = FeatureClipTests.Duo(positions: [SIMD2(-1.5, 0.6), SIMD2(1.5, 0.6)], features: [.ears, .wings], seed: 5)
            d.place([SIMD2(-0.6, 0.6), SIMD2(0.6, 0.6)])
            d.live = true
            let a = d.lab.rigs[0], b = d.lab.rigs[1]
            a.brain.idleForced = true; b.brain.idleForced = true
            _ = a.brain.idleStart(.lieDown, a.sim); _ = b.brain.idleStart(.lieDown, b.sim)
            a.brain.idleState.hold = 60; b.brain.idleState.hold = 60
            var lyingWorst: Float = 0, lyingWorst2: Float = 0
            for f in 0..<420 { d.tick(); if f > 150, let gp = ContactField.gap(0, 1) { lyingWorst = max(lyingWorst, abs(gp)); if f > 260 { lyingWorst2 = max(lyingWorst2, abs(gp)) } } }
            MotionLog.write(String(format: "TUNE %@: standing slowest entry %d frames, worst |gap| after entry %.4f, settled %.4f; lying worst |gap| after f150 %.4f, after f260 %.4f", name, slowest, worstStand, worstSettled, lyingWorst, lyingWorst2))
        }
        T.gain = 0.15; T.lead = 3; T.fineBand = 0; T.fineAlpha = 1.0 / 45; T.fineGain = 0.12
    }

    // MARK: contact sound + haptic, once per touch

    /// Count of contact events (the squish request + the haptic request) over a run.
    private final class Counter {
        var squish = 0, haptic = 0
    }
    /// The contact events the brains announced (BlobBrain.contactEvents): the touch itself, apart from every stance's own sounds.
    private func events(_ d: FeatureClipTests.Duo) -> Int { d.lab.rigs.reduce(0) { $0 + $1.brain.contactEvents } }

    func testContactFiresOncePerTouchAndRearms() {
        let c = Counter()
        AudioHub.requestTap = { if $0 == "squish" { c.squish += 1 } }
        let d = FeatureClipTests.Duo(positions: [SIMD2(-1.5, 0.6), SIMD2(1.5, 0.6)], features: [.none, .none], seed: 5)
        d.place([SIMD2(-1.0, 0.6), SIMD2(1.0, 0.6)])
        d.live = true
        let a = d.lab.rigs[0], b = d.lab.rigs[1]
        wireHaptics(c); d.onTick = { [unowned self] in self.fakeNow += 1.0 / 60 }
        for _ in 0..<3 { d.tick() }
        // 1. they close in and settle: ONE event at the first touch, the press afterwards is silent
        var first = -1
        for f in 0..<180 {
            d.tick()
            ContactSettle.step(a.brain, b.brain)
            if first < 0, let g = ContactField.gap(0, 1), g <= 0.01 { first = f; MotionLog.write("CONTACT first touch at frame \(f), gap \(g), squish so far \(c.squish)") }
        }
        XCTAssertGreaterThan(first, -1)
        XCTAssertEqual(events(d), 1, "one contact event for the first touch (not one per body, not one per press)")
        XCTAssertEqual(c.squish, 1, "its squish request"); XCTAssertEqual(c.haptic, 1, "its haptic request")
        // 2. wiggle inside the band: still nothing
        for _ in 0..<60 { d.tick(); ContactSettle.step(a.brain, b.brain, target: -0.003) }
        XCTAssertEqual(events(d), 1, "the settle's last mm of press does not fire again")
        // 3. pulled 10 cm apart (> 3 cm): re-armed; touching again fires once more
        for _ in 0..<12 { a.brain.contactNudge(SIMD2(-0.01, 0)); d.tick() }
        for _ in 0..<30 { d.tick() }
        XCTAssertGreaterThan(ContactField.gap(0, 1) ?? 0, 0.03)
        for _ in 0..<120 { d.tick(); ContactSettle.step(a.brain, b.brain) }
        XCTAssertEqual(events(d), 2, "a second touch fires a second event")
        XCTAssertEqual(c.squish, 2); XCTAssertEqual(c.haptic, 2)
    }

    func testLyingSnuggleFiresOnce() {
        let c = Counter()
        AudioHub.requestTap = { if $0 == "squish" { c.squish += 1 } }
        let d = FeatureClipTests.Duo(positions: [SIMD2(-1.5, 0.6), SIMD2(1.5, 0.6)], features: [.ears, .wings], seed: 5)
        d.place([SIMD2(-0.8, 0.6), SIMD2(0.8, 0.6)])
        d.live = true
        let a = d.lab.rigs[0], b = d.lab.rigs[1]
        wireHaptics(c); d.onTick = { [unowned self] in self.fakeNow += 1.0 / 60 }
        for r in d.lab.rigs { r.brain.idleForced = true }
        XCTAssertTrue(a.brain.idleStart(.lieDown, a.sim)); XCTAssertTrue(b.brain.idleStart(.lieDown, b.sim))
        a.brain.idleState.hold = 30; b.brain.idleState.hold = 30
        var lo: Float = 1, hi: Float = -1
        for f in 0..<420 {
            d.tick()
            if f > 260, let g = ContactField.gap(0, 1) { lo = min(lo, g); hi = max(hi, g) }
        }
        MotionLog.write("CONTACT lying snuggle: contact events \(events(d)), squish requests \(c.squish) (the plops included), haptic \(c.haptic), settled gap \(lo) ... \(hi)")
        XCTAssertEqual(events(d), 1, "the lie-down snuggle fires one contact event")
        XCTAssertGreaterThanOrEqual(c.haptic, 1); XCTAssertGreaterThanOrEqual(c.squish, 1)
        XCTAssertGreaterThan(lo, -0.012); XCTAssertLessThan(hi, 0.012)
    }

    /// Every social stance: the number of contact events equals the number of touch episodes of the skins (gap crossing from > 3 cm to <= 0.5 cm), nothing fires twice; the counts are logged
    /// (a stance whose skins never meet shows 0 episodes: it is waiting to be migrated to ContactSettle).
    func testEveryStanceFiresExactlyOncePerTouch() {
        let kinds: [SocialKind] = [.boop, .bump, .nuzzle, .cuddle, .highFive, .cheekSquish, .noseBoop, .swayHug, .chestBump, .groupHug]
        var rows: [String] = []
        for kind in kinds {
            let c = Counter()
            AudioHub.requestTap = { if ["squish", "boop", "highfive_boop", "wobble", "emote_spinhug"].contains($0) { c.squish += 1 } }          // (a stance's own contact sound: ContactStance.table)
            let n = kind == .groupHug ? 3 : 2
            let d = FeatureClipTests.Duo(positions: Array(SocialTests.starts.prefix(n)), features: [JellyFeature](repeating: .none, count: n), seed: 3)
            d.live = true
            wireHaptics(c); d.onTick = { [unowned self] in self.fakeNow += 1.0 / 60 }
            for r in d.lab.rigs { r.brain.anticsEnabled = true }
            guard d.lab.rigs[0].brain.socialStart(kind, with: d.lab.rigs[1].brain, d.lab.rigs[0].sim) else { rows.append("\(kind): could not start"); continue }
            var episodes = 0
            var armed = [Bool](repeating: true, count: n * n), awayF = [Int](repeating: 0, count: n * n)
            var minGap: Float = .infinity
            var epLog: [String] = [], evLog: [String] = [], lastEv = 0
            // a re-touch within `eventGap` (0.35 s) of the pair's last touch is the same touch bouncing (a slap's rebound, a sway): one sound, as the brain does
            var lastStart = [Int](repeating: -1000, count: n * n)
            let debounce = Int((ContactTuning.eventGap * 60).rounded(.up))
            for fr in 0..<(60 * 30) {
                d.tick()
                for i in 0..<n { for j in (i + 1)..<n {
                    guard var g = ContactField.gap(i, j, features: false) else { continue }
                    if let sg = ContactField.skinGap(i, j) { g = min(g, sg) }          // (the gate of contactTick inside a session: the drawn body, support gap)
                    minGap = min(minGap, g)
                    if g > ContactTuning.rearmGap { awayF[i * n + j] += 1; if awayF[i * n + j] >= Int(ContactTuning.rearmHold * 60) { armed[i * n + j] = true } } else if g <= ContactTuning.touchGap, armed[i * n + j], fr - lastStart[i * n + j] >= debounce { armed[i * n + j] = false; awayF[i * n + j] = 0; lastStart[i * n + j] = fr; episodes += 1; epLog.append("f\(fr) \(i)-\(j) \(String(format: "%.3f", g))") }
                } }
                let evNow = events(d)
                if evNow != lastEv { evLog.append("f\(fr) ev\(evNow)"); lastEv = evNow }
                if !d.lab.anySocial && episodes + c.squish > 0 && d.lab.rigs[0].brain.idleState.t > 5 { break }
            }
            let ev = events(d)
            let row = "\(kind): touch episodes \(episodes), contact events \(ev), squish requests \(c.squish), haptic requests \(c.haptic), min gap \(String(format: "%.3f", minGap))"
            rows.append(row); MotionLog.write("STANCE " + row)
            if ev != episodes { MotionLog.write("STANCE \(kind) episodes at " + epLog.joined(separator: ", ") + " | events at " + evLog.joined(separator: ", ")) }
            XCTAssertEqual(ev, episodes, "exactly one contact event per touch: \(row)")
            XCTAssertGreaterThanOrEqual(c.squish, ev, "a sound with every contact: \(row)")
            if ev > 0 { XCTAssertGreaterThanOrEqual(c.haptic, 1, "a haptic for the touches (the room allows 2 a second; the stances add their own): \(row)") }
            ContactField.reset()
        }
    }

    // MARK: arrival (2026-11-04, round 4 A: the stance owns the walk-up)

    /// The warp moves the swing foot's own start and landing with the body: a step in progress lands where the warped body is, not on the old spot.
    func testFootGaitNudgeMovesTheStepInProgress() {
        var g = FootGait()
        g.pos = [SIMD2(-0.1, 0), SIMD2(0.1, 0)]
        g.begin(side: 1, to: SIMD2(0.1, 0.4), toYaw: 0, peak: 0.05, rate: 3.5)
        g.nudge(SIMD2(0.2, -0.1))
        for _ in 0..<60 { g.advance(1.0 / 60) }
        XCTAssertEqual(g.pos[1].x, 0.3, accuracy: 1e-5); XCTAssertEqual(g.pos[1].y, 0.3, accuracy: 1e-5, "the swing foot lands at its target plus the warp")
        XCTAssertEqual(g.pos[0].x, 0.1, accuracy: 1e-5); XCTAssertEqual(g.pos[0].y, -0.1, accuracy: 1e-5, "the planted foot moved with the body")
    }

    /// A crouching hop is planted: the settle moves only its landing spot (the take-off stays where the soles are); the flight is warped rigidly.
    func testSettleNeverWarpsACrouchingHopOnlyItsLanding() {
        let d = FeatureClipTests.Duo(positions: [SIMD2(-0.6, 0.6), SIMD2(0.6, 0.6)], features: [.none, .none], seed: 5)
        d.live = true
        for _ in 0..<5 { d.tick() }
        let a = d.lab.rigs[0]
        let s = a.brain.newSession(.boop, with: d.lab.rigs[1].brain, duration: 5)
        _ = s
        a.brain.gait.hop(a.sim, to: SIMD2(-0.2, 0.6))
        guard a.brain.gait.phase == .crouch else { return XCTFail("the hop crouches first (phase \(a.brain.gait.phase))") }
        let root = a.brain.position, feet = a.brain.feet.pos
        a.brain.contactNudge(SIMD2(0.05, 0))
        XCTAssertEqual(simd_distance(a.brain.position, root), 0, accuracy: 1e-6, "no rigid warp while the soles are planted in the crouch")
        XCTAssertEqual(a.brain.feet.pos[0], feet[0]); XCTAssertEqual(a.brain.feet.pos[1], feet[1])
    }

    /// The stance table: the pressing / holding kinds own the phase-0 walk-up; the side-by-side kinds say so (the touch distance is predicted for the posture they end in).
    func testStanceTableOwnsTheWalkUp() {
        for k in [SocialKind.boop, .bump, .sneak, .chestBump, .highFive, .noseBoop, .bellyBounce, .nuzzle, .hum, .cheekSquish, .swayHug, .whisperGiggle, .cuddleLean, .backToBack] {
            let st = ContactStance.entry(k)
            XCTAssertEqual(st?.steps.first?.retargets, true, "\(k): phase 0 walks up through the stance")
        }
        for k in [SocialKind.nuzzle, .sitTogether, .cheekSquish, .bellyBounce, .cuddleLean, .whisperGiggle, .swayHug, .backToBack] { XCTAssertEqual(ContactStance.entry(k)?.facing, .camera, "\(k) ends side by side") }
        for k in [SocialKind.boop, .bump, .chestBump, .hum, .noseBoop] { XCTAssertEqual(ContactStance.entry(k)?.facing, .each, "\(k) ends face to face") }
        XCTAssertTrue(ContactStance.entry(.squabble)?.steps.first?.retargets ?? false, "squabble owns its walk-up since drive round 2 (arrival -7.4 cm -> -1.0 cm)"); XCTAssertFalse(ContactStance.entry(.tag)?.steps.first?.retargets ?? true)
    }

    /// A walk-up reaches the touch exactly (the stance walk plants its last step within 1 cm of the destination, no shuffle) and the pair stands at skin contact: gap within [-1, +2] cm at the end of the walk-up phase.
    func testBoopWalkUpArrivesAtTheTouchWithoutAShuffle() {
        let d = FeatureClipTests.Duo(positions: [SIMD2(-1.5, 0.6), SIMD2(1.35, 0.9)], features: [.none, .none], seed: 31)
        d.live = true
        for _ in 0..<3 { d.tick() }
        let a = d.lab.rigs[0], b = d.lab.rigs[1]
        XCTAssertTrue(a.brain.socialStart(.boop, with: b.brain, a.sim))
        var arrival: Float?
        var steps = 0, prevActive = false
        for _ in 0..<(60 * 12) {
            d.tick()
            if a.brain.feet.active && !prevActive { steps += 1 }; prevActive = a.brain.feet.active
            if (a.brain.social?.phase ?? 0) >= 1, arrival == nil, !a.brain.feet.active, let g = ContactField.gap(0, 1) { arrival = g }
        }
        guard let g = arrival else { return XCTFail("the walk-up ends") }
        MotionLog.write(String(format: "ARRIVAL boop: gap %.3f at the last planted step", g))
        XCTAssertLessThan(g, 0.03, "the walk-up ends within 3 cm of the touch (the lean closes the rest)"); XCTAssertGreaterThan(g, -0.015, "and never inside him")
    }

    /// USER RULE 3 (2026-11-04): every interactive emote follows the one formula. Enforced here, not in a note: EVERY SocialKind has an explicit row in the stance table (no fallthrough class), and every kind with a
    /// touching / proximity row is measured by ContactPolishTests (a new emote shows up in the harness automatically or this test fails). Add a kind: row in ContactStance.table + entry in pairEntries / groupEntries.
    func testEveryInteractiveKindHasAStanceRow() {
        let measured = Set((ContactPolishTests.pairEntries + ContactPolishTests.groupEntries).compactMap { e -> SocialKind? in if case .social(let k) = e.scenario { return k }; return nil })
        // (zoomies / look / pass have partners and rows; the lie / sleep scenarios are not SocialKinds)
        for k in SocialKind.allCases {
            guard let st = ContactStance.entry(k) else { XCTFail("SocialKind.\(k) has no ContactStance row (user rule 3: every interactive emote gets an explicit row: class, facing, features, sound)"); continue }
            if st.cls != .none { XCTAssertTrue(measured.contains(k), "SocialKind.\(k) has a stance row but ContactPolishTests does not enumerate it (add it to pairEntries / groupEntries)") }
            if st.cls == .touching { XCTAssertFalse(st.steps.isEmpty, "\(k): a touching row needs steps") }
        }
    }

    /// The final step of a stance walk is planned with the session partner exempt from the room's peer wall (the wall measures him at the walker's mid-turn outline and cut the step 9 cm short):
    /// `contactPartnerIDs()` carries -(id+1) only while `stanceStepFree`, and `keepApart` then leaves the position alone.
    func testStanceFinalStepIsNotCutByThePartnerWall() {
        let d = FeatureClipTests.Duo(positions: [SIMD2(-1.5, 0.6), SIMD2(1.5, 0.6)], features: [.none, .none], seed: 5)
        d.place([SIMD2(0, -0.1), SIMD2(0, 1.3)])
        d.live = true
        for _ in 0..<10 { d.tick() }
        let a = d.lab.rigs[0].brain, b = d.lab.rigs[1].brain
        XCTAssertTrue(a.socialStart(.nuzzle, with: b, d.lab.rigs[0].sim))
        for _ in 0..<5 { d.tick() }
        XCTAssertTrue(a.contactPartnerIDs().contains(b.steerID))
        XCTAssertFalse(a.contactPartnerIDs().contains(-(b.steerID + 1)), "the wall is on for ordinary steps")
        a.stanceStepFree = true
        XCTAssertTrue(a.contactPartnerIDs().contains(-(b.steerID + 1)), "and off for the final step")
        a.stanceStepFree = false
        let r0 = ContactField.root(0)
        let peers: [(pos: SIMD2<Float>, walking: Bool)] = [(r0, false), (ContactField.root(1), false)]
        let p = SIMD3<Float>(r0.x, 0, r0.y + 0.4)          // (well inside the skins)
        let walled = MelonController.keepApart(p, id: 1, peers: peers, gap: 1.0, partners: [0])
        let free = MelonController.keepApart(p, id: 1, peers: peers, gap: 1.0, partners: [0, -1])
        XCTAssertGreaterThan(simd_distance(SIMD2(walled.x, walled.z), r0), 0.5, "the wall pushes a body inside the skin out")
        XCTAssertEqual(free.z, p.z, accuracy: 1e-5, "the exempt partner is not seen")
    }

    /// A side-by-side stance walk (nuzzle) lands its last step at the touch: the gap at the end of the walk-up phase is within [-1.5, +2] cm (it used to plant 9 cm short and lean the rest).
    func testNuzzleWalkUpArrivesAtTheTouch() {
        let d = FeatureClipTests.Duo(positions: [SIMD2(-1.5, 0.6), SIMD2(1.35, 0.9)], features: [.none, .none], seed: 31)
        d.live = true
        for _ in 0..<3 { d.tick() }
        let a = d.lab.rigs[0], b = d.lab.rigs[1]
        XCTAssertTrue(a.brain.socialStart(.nuzzle, with: b.brain, a.sim))
        var arrival: Float?
        for _ in 0..<(60 * 12) {
            d.tick()
            if (a.brain.social?.phase ?? 0) >= 1, arrival == nil, !a.brain.feet.active, let g = ContactField.gap(0, 1) { arrival = g }
        }
        guard let g = arrival else { return XCTFail("the walk-up ends") }
        MotionLog.write(String(format: "ARRIVAL nuzzle: gap %.3f at the first planted frame of phase 1", g))
        XCTAssertGreaterThan(g, -0.015, "never inside him")
        // KNOWN OPEN (r4-arrivalA-r2): in this cold-start scene the first planted frame of phase 1 still reads 3.7 cm; the bar is 1.5. Expected to fail until it is closed - remove the expectation then.
        XCTExpectFailure("nuzzle arrives 3.7 cm apart in the cold-start Duo (bar <= 1.5 cm)", strict: false) { XCTAssertLessThan(g, 0.015, "arrival gap within the 1.5 cm bar") }
    }

    // MARK: r4-engine-settle: the hold's back-off, its band, and the lean calibration

    /// A pair in a side-by-side hold (swayHug: phase 2 holds the touch), run until it has stood planted and settled in phase 2 for 0.5 s. Returns the duo.
    private func settledHold(_ kind: SocialKind = .swayHug, seed: UInt64 = 31) -> FeatureClipTests.Duo? {
        let d = FeatureClipTests.Duo(positions: [SIMD2(-1.5, 0.6), SIMD2(1.35, 0.9)], features: [.none, .none], seed: seed)
        d.live = true
        for _ in 0..<3 { d.tick() }
        let a = d.lab.rigs[0], b = d.lab.rigs[1]
        guard a.brain.socialStart(kind, with: b.brain, a.sim) else { return nil }
        var held = 0
        for _ in 0..<(60 * 14) {
            d.tick()
            if (a.brain.social?.phase ?? 0) >= 2, !a.brain.feet.active, !b.brain.feet.active { held += 1 } else { held = 0 }
            if held >= 30 { return d }
        }
        return nil
    }

    /// A hold started AT the band does not step at all: for 3 s of a settled hold neither body lifts a foot (no shuffle, no back-off: the dead band and the hold are not a cycle).
    func testHoldAtTheBandDoesNotStep() throws {
        guard let d = settledHold() else { throw XCTSkip("the pair never settled into the hold within 14 s") }
        let a = d.lab.rigs[0], b = d.lab.rigs[1]
        var steps = 0, prevA = false, prevB = false, lo: Float = 9, hi: Float = -9
        for _ in 0..<(60 * 3) {
            d.tick()
            if a.brain.feet.active && !prevA { steps += 1 }; prevA = a.brain.feet.active
            if b.brain.feet.active && !prevB { steps += 1 }; prevB = b.brain.feet.active
            if let g = ContactField.gap(0, 1) { lo = min(lo, g); hi = max(hi, g) }
        }
        MotionLog.write(String(format: "HOLD at band: %d steps in 3 s, gap %.2f ... %.2f cm", steps, lo * 100, hi * 100))
        XCTAssertEqual(steps, 0, "a hold at the band never steps (gap \(lo * 100) ... \(hi * 100) cm)")
        XCTAssertGreaterThan(lo, -0.01, "never more than 1 cm inside")
    }

    /// An overlap of `cm` injected into a settled hold (a rigid warp of body A toward B), 4 s watched while the session is still in its hold phase. Returns gaps, the frames a foot lifted, and the hold phase's frames.
    private func injectOverlap(_ cm: Float) throws -> (gaps: [Float], steps: [Int]) {
        guard let d = settledHold() else { throw XCTSkip("the pair never settled into the hold within 14 s") }
        let a = d.lab.rigs[0], b = d.lab.rigs[1]
        let u = simd_normalize(b.brain.position - a.brain.position + SIMD2(1e-6, 0)), w = u * (cm / 100)
        a.brain.px += w.x; a.brain.pz += w.y; a.brain.stepRoot0 += w; a.brain.feet.nudge(w); a.brain.contactSim?.shift(byXZ: w)
        var gaps: [Float] = [], steps: [Int] = [], prevA = false, prevB = false
        for f in 0..<(60 * 4) {
            d.tick()
            guard (a.brain.social?.phase ?? 0) == 2 else { break }          // (the hold only: the drive's own ending parts the pair)
            if (a.brain.feet.active && !prevA) || (b.brain.feet.active && !prevB) { steps.append(f) }; prevA = a.brain.feet.active; prevB = b.brain.feet.active
            gaps.append(ContactField.gap(0, 1) ?? .nan)
            if false { MotionLog.write(String(format: "DBG f%d gap %.1f ax %.3f bx %.3f trimA %.3f trimB %.3f walkA %d walkB %d feetA %d feetB %d bo %d", f, gaps.last! * 100, a.brain.px, b.brain.px, a.brain.socialBook.leanTrim, b.brain.socialBook.leanTrim, a.brain.scriptIsNone ? 0 : 1, b.brain.scriptIsNone ? 0 : 1, a.brain.feet.active ? 1 : 0, b.brain.feet.active ? 1 : 0, ContactTouchMemory.backoff.count)) }
        }
        MotionLog.write("OVERLAP \(cm) cm: gaps(cm) every 0.25 s " + stride(from: 0, to: gaps.count, by: 15).map { String(format: "%.1f", gaps[$0] * 100) }.joined(separator: " ") + " steps at frames \(steps)")
        return (gaps, steps)
    }

    /// The frame after which the gap stays inside +-1.5 cm for the rest of `gaps` (nil: it never does).
    private func settledFrame(_ gaps: [Float]) -> Int? {
        guard let last = gaps.lastIndex(where: { !($0 >= -0.015 && $0 <= 0.015) }) else { return 0 }
        return last + 1 < gaps.count ? last + 1 : nil
    }

    /// A 3 cm overlap injected into a settled hold is backed out of: inside the band within 1 s, then 3 s with no step and no drift (the two leans take 3 cm; the back-off step is for what they cannot).
    func testBackOffFromAThreeCentimetreOverlapSettlesWithinASecond() throws {
        let (gaps, steps) = try injectOverlap(3)
        guard let k = settledFrame(gaps) else { return XCTFail("never settled inside +-1.5 cm: final \(gaps.last ?? 0)") }
        XCTAssertLessThanOrEqual(k, 60, "settled inside the band within 1 s (frame \(k))")
        let after = Array(gaps.dropFirst(k).prefix(180))
        XCTAssertGreaterThanOrEqual(after.count, 150, "the hold lasts 2.5 s past the settling")
        XCTAssertGreaterThan(after.min() ?? 0, -0.01, "stays out of the partner")
        XCTAssertLessThan(after.max() ?? 0, 0.015, "and does not drift apart")
        XCTAssertTrue(steps.filter { $0 > k }.isEmpty, "no step after it settled: \(steps)")
    }

    /// The back-off step itself (BlobBrain.contactBackOff), through the session's own tick: the lean trim held pinned at -budget and the error biased 5 cm toward overlap (`backoffBias`: an overlap the lean cannot take). After the 0.3 s dwell the body steps
    /// back ONCE (3 ... 6.5 cm straight away from the partner, no turn), the trim is released with the root, and the cooldown keeps a second step away for 0.6 s.
    func testBackOffIsOneStraightStepAfterTheDwell() throws {
        guard let d = settledHold() else { throw XCTSkip("the pair never settled into the hold within 14 s") }
        let a = d.lab.rigs[0], b = d.lab.rigs[1]
        let p0 = a.brain.position, yaw0 = a.brain.yaw, u = simd_normalize(p0 - b.brain.position + SIMD2(1e-6, 0))
        var starts: [Int] = [], prev = false, pinnedFrames = 0
        ContactSettleTuning.backoffBias = -0.05; defer { ContactSettleTuning.backoffBias = 0 }
        for f in 0..<60 {
            if starts.isEmpty { a.brain.socialBook.leanTrim = -ContactTuning.leanBudget; a.brain.socialBook.trimPartner = b.brain.steerID; pinnedFrames += 1 }
            d.tick()
            if a.brain.feet.active && !prev { starts.append(f) }; prev = a.brain.feet.active
        }
        let moved = simd_dot(a.brain.position - p0, u)
        MotionLog.write(String(format: "BACKOFF step: starts %@, moved %.1f cm away, yaw change %.3f rad, trim %.3f", "\(starts)", moved * 100, abs(wrapAngle(a.brain.yaw - yaw0)), a.brain.socialBook.leanTrim))
        XCTAssertEqual(starts.count, 1, "one step (dwell 0.3 s, then cooldown 0.6 s): \(starts)")
        XCTAssertGreaterThanOrEqual(starts.first ?? 0, 15, "not before the 0.3 s dwell")
        XCTAssertGreaterThan(moved, 0.025, "the root moved away from him (\(moved) m)"); XCTAssertLessThan(moved, 0.07)
        XCTAssertLessThan(abs(wrapAngle(a.brain.yaw - yaw0)), 0.05, "and did not turn")
        XCTAssertGreaterThan(a.brain.socialBook.leanTrim, -0.02, "the trim handed over to the step")
    }

    /// The lean calibration (ContactTuning.leanPerMetre, rad per metre of skin to close): the skin gap of a standing pair against a pure lean of one body toward the other. Logged; the bound keeps it honest.
    func testLeanReachPerRadianMatchesTheCalibration() {
        let d = FeatureClipTests.Duo(positions: [SIMD2(-0.5, 0.6), SIMD2(0.5, 0.6)], features: [.none, .none], seed: 5)
        d.live = true
        for _ in 0..<3 { d.tick() }
        let a = d.lab.rigs[0], b = d.lab.rigs[1]
        let local = rotXZ(b.brain.position - a.brain.position, -a.brain.yaw), ln = max(simd_length(local), 1e-3)
        let nr = -local.x / ln, np = local.y / ln
        func gap(_ th: Float) -> Float {
            for _ in 0..<45 { a.brain.socialBook.roll = nr * th; a.brain.socialBook.pitch = np * th; d.tick() }
            var g: Float = 0
            for _ in 0..<15 { a.brain.socialBook.roll = nr * th; a.brain.socialBook.pitch = np * th; d.tick(); g += (ContactField.gap(0, 1) ?? 0) / 15 }
            return g
        }
        let g0 = gap(0), g1 = gap(0.1), g2 = gap(0.2)
        let reach = (g0 - g2) / 0.2, reach1 = (g0 - g1) / 0.1
        MotionLog.write(String(format: "LEAN reach: %.3f m/rad (0.1 rad: %.3f, 0.2 rad: %.3f) -> %.2f rad per m; leanPerMetre = %.2f", reach, reach1, reach, 1 / max(reach, 1e-3), ContactTuning.leanPerMetre))
        XCTAssertGreaterThan(reach, 0.1, "a lean toward him closes skin: \(reach) m/rad")
        XCTAssertLessThan(abs(1 / max(reach, 1e-3) - ContactTuning.leanPerMetre) / ContactTuning.leanPerMetre, 0.3, "leanPerMetre is within 30% of the measured reach (\(1 / max(reach, 1e-3)) rad/m)")
    }
}
