//
//  ContactSettleTests.swift
//  The settle controller (Melon/ContactSettle.swift) and the touch event (BlobBrain+Contact): the pair's drawn skins end in contact (-0.5 ... +0.5 cm) from any start distance,
//  without oscillating, an anchored body stays put; the contact sound + haptic fire exactly once per touch (first time the skin gap is <= +0.5 cm, re-armed past +3 cm), also in the
//  social stances and the lying snuggle, never again for the settle's last mm of press.
//

import XCTest
import simd
@testable import BobV1

@MainActor
final class ContactSettleTests: XCTestCase {
    override func setUp() {
        RoomLayout.dynamicBoxes = []; GameCamera.configureRoom(count: 3, option: .A, wide: 2); _ = GameCamera.camera(aspect: 440 / 956)
        ContactField.reset(); ContactField.enabled = true; FeatureClip.enabled = true; LieClearTuning.enabled = true
    }
    override func tearDown() {
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

    // MARK: contact sound + haptic, once per touch

    /// Count of contact events (the squish request + the haptic request) over a run.
    private final class Counter {
        var squish = 0, haptic = 0
    }

    func testContactFiresOncePerTouchAndRearms() {
        let c = Counter()
        AudioHub.requestTap = { if $0 == "squish" { c.squish += 1 } }
        let d = FeatureClipTests.Duo(positions: [SIMD2(-1.5, 0.6), SIMD2(1.5, 0.6)], features: [.none, .none], seed: 5)
        d.place([SIMD2(-1.0, 0.6), SIMD2(1.0, 0.6)])
        d.live = true
        let a = d.lab.rigs[0], b = d.lab.rigs[1]
        for r in d.lab.rigs { r.brain.onEmoteHaptic = { _, _ in c.haptic += 1 } }
        for _ in 0..<3 { d.tick() }
        // 1. they close in and settle: ONE event at the first touch, the press afterwards is silent
        var first = -1
        for f in 0..<180 {
            d.tick()
            ContactSettle.step(a.brain, b.brain)
            if first < 0, let g = ContactField.gap(0, 1), g <= 0.005 { first = f; MotionLog.write("CONTACT first touch at frame \(f), gap \(g), squish so far \(c.squish)") }
        }
        XCTAssertGreaterThan(first, -1)
        XCTAssertEqual(c.squish, 1, "one squish request for the first touch (not one per body, not one per press)")
        XCTAssertEqual(c.haptic, 1, "one haptic request for the first touch")
        // 2. wiggle inside the band: still nothing
        for _ in 0..<60 { d.tick(); ContactSettle.step(a.brain, b.brain, target: -0.003) }
        XCTAssertEqual(c.squish, 1, "the settle's last mm of press does not fire again")
        // 3. pulled 10 cm apart (> 3 cm): re-armed; touching again fires once more
        for _ in 0..<12 { a.brain.contactNudge(SIMD2(-0.01, 0)); d.tick() }
        for _ in 0..<30 { d.tick() }
        XCTAssertGreaterThan(ContactField.gap(0, 1) ?? 0, 0.03)
        for _ in 0..<120 { d.tick(); ContactSettle.step(a.brain, b.brain) }
        XCTAssertEqual(c.squish, 2, "a second touch fires a second event")
        XCTAssertEqual(c.haptic, 2)
    }

    func testLyingSnuggleFiresOnce() {
        let c = Counter()
        AudioHub.requestTap = { if $0 == "squish" { c.squish += 1 } }
        let d = FeatureClipTests.Duo(positions: [SIMD2(-1.5, 0.6), SIMD2(1.5, 0.6)], features: [.ears, .wings], seed: 5)
        d.place([SIMD2(-0.8, 0.6), SIMD2(0.8, 0.6)])
        d.live = true
        let a = d.lab.rigs[0], b = d.lab.rigs[1]
        for r in d.lab.rigs { r.brain.onEmoteHaptic = { _, _ in c.haptic += 1 }; r.brain.idleForced = true }
        XCTAssertTrue(a.brain.idleStart(.lieDown, a.sim)); XCTAssertTrue(b.brain.idleStart(.lieDown, b.sim))
        a.brain.idleState.hold = 30; b.brain.idleState.hold = 30
        var lo: Float = 1, hi: Float = -1
        for f in 0..<420 {
            d.tick()
            if f > 260, let g = ContactField.gap(0, 1) { lo = min(lo, g); hi = max(hi, g) }
        }
        MotionLog.write("CONTACT lying snuggle: squish \(c.squish) haptic \(c.haptic), settled gap \(lo) ... \(hi)")
        XCTAssertEqual(c.squish, 1, "the lie-down snuggle fires one contact event")
        XCTAssertEqual(c.haptic, 1)
        XCTAssertGreaterThan(lo, -0.010); XCTAssertLessThan(hi, 0.010)
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
            for r in d.lab.rigs { r.brain.onEmoteHaptic = { _, _ in c.haptic += 1 }; r.brain.anticsEnabled = true }
            guard d.lab.rigs[0].brain.socialStart(kind, with: d.lab.rigs[1].brain, d.lab.rigs[0].sim) else { rows.append("\(kind): could not start"); continue }
            var episodes = 0
            var armed = [Bool](repeating: true, count: n * n)
            var minGap: Float = .infinity
            for _ in 0..<(60 * 30) {
                d.tick()
                for i in 0..<n { for j in (i + 1)..<n {
                    guard let g = ContactField.gap(i, j) else { continue }
                    minGap = min(minGap, g)
                    if g > 0.03 { armed[i * n + j] = true } else if g <= 0.005, armed[i * n + j] { armed[i * n + j] = false; episodes += 1 }
                } }
                if !d.lab.anySocial && episodes + c.squish > 0 && d.lab.rigs[0].brain.idleState.t > 5 { break }
            }
            let row = "\(kind): touch episodes \(episodes), contact squish \(c.squish), haptics \(c.haptic), min gap \(String(format: "%.3f", minGap))"
            rows.append(row); MotionLog.write("STANCE " + row)
            XCTAssertEqual(c.squish, episodes, "exactly one contact event per touch: \(row)")
            XCTAssertEqual(c.haptic, c.squish, "a haptic with every contact: \(row)")
            ContactField.reset()
        }
    }
}
