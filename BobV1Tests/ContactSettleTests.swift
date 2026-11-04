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
        HapticDriver.cueTap = { if $0.name == "sfx.squish" { c.haptic += 1 } }
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
            AudioHub.requestTap = { if $0 == "squish" { c.squish += 1 } }
            let n = kind == .groupHug ? 3 : 2
            let d = FeatureClipTests.Duo(positions: Array(SocialTests.starts.prefix(n)), features: [JellyFeature](repeating: .none, count: n), seed: 3)
            d.live = true
            wireHaptics(c); d.onTick = { [unowned self] in self.fakeNow += 1.0 / 60 }
            for r in d.lab.rigs { r.brain.anticsEnabled = true }
            guard d.lab.rigs[0].brain.socialStart(kind, with: d.lab.rigs[1].brain, d.lab.rigs[0].sim) else { rows.append("\(kind): could not start"); continue }
            var episodes = 0
            var armed = [Bool](repeating: true, count: n * n)
            var minGap: Float = .infinity
            var epLog: [String] = [], evLog: [String] = [], lastEv = 0
            // a re-touch within `eventGap` (0.35 s) of the pair's last touch is the same touch bouncing (a slap's rebound, a sway): one sound, as the brain does
            var lastStart = [Int](repeating: -1000, count: n * n)
            let debounce = Int((ContactTuning.eventGap * 60).rounded(.up))
            for fr in 0..<(60 * 30) {
                d.tick()
                for i in 0..<n { for j in (i + 1)..<n {
                    guard let g = ContactField.gap(i, j, features: true) else { continue }
                    minGap = min(minGap, g)
                    if g > ContactTuning.rearmGap { armed[i * n + j] = true } else if g <= ContactTuning.touchGap, armed[i * n + j], fr - lastStart[i * n + j] >= debounce { armed[i * n + j] = false; lastStart[i * n + j] = fr; episodes += 1; epLog.append("f\(fr) \(i)-\(j) \(String(format: "%.3f", g))") }
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
}
