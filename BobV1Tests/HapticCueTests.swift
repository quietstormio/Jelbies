import XCTest
@testable import BobV1

/// The room's haptic cues (Haptics+Emotes.swift) through the ONE HapticDriver: every move has its own pattern, intensity follows the energy, one engine, the touch haptics unharmed.
@MainActor
final class HapticCueTests: XCTestCase {
    var saved: Any?
    var now = 1000.0
    var rec = RecordingHapticSink()
    var d = HapticDriver()
    override func setUp() {
        super.setUp(); BlobBrain.pickBudgetSeconds = .infinity
        saved = UserDefaults.standard.object(forKey: HapticSettings.key)
        UserDefaults.standard.removeObject(forKey: HapticSettings.key)
        rec = RecordingHapticSink(); d = HapticDriver(sinks: [rec]); now = 1000
        HapticDriver.clock = { [unowned self] in self.now }
        HapticDriver.after = { _, f in f() }
        HapticDriver.jitter = { 1 }
        HapticDriver.room = d; HapticDriver.roomBusy = nil
    }
    override func tearDown() {
        super.tearDown(); BlobBrain.pickBudgetSeconds = BlobBrain.defaultPickBudgetSeconds
        HapticDriver.clock = { CACurrentMediaTime() }
        HapticDriver.after = { dl, f in DispatchQueue.main.asyncAfter(deadline: .now() + dl) { MainActor.assumeIsolated { f() } } }
        HapticDriver.jitter = { 1 + Float.random(in: -0.15...0.15) }
        HapticDriver.cueTap = nil; HapticDriver.room = nil; HapticDriver.roomBusy = nil
        if let v = saved { UserDefaults.standard.set(v, forKey: HapticSettings.key) } else { UserDefaults.standard.removeObject(forKey: HapticSettings.key) }
    }

    static var allCues: [HapticCue] {
        IdleKind.allCases.map { .idle($0) } + SocialKind.allCases.map { .social($0) } + EmoteCue.allCases.map { .emote($0) } + GroupCue.allCases.map { .group($0) } + SFXCue.allCases.map { .sfx($0) } + EmoteTreats.haptics.keys.sorted().map { .beat($0) }
    }

    func testEveryMoveHasItsOwnSoftPattern() {
        var seen: [String: String] = [:]
        for c in Self.allCues {
            let ps = c.pulses(energy: 1, jitter: 1)
            XCTAssertFalse(ps.isEmpty, c.name)
            for p in ps { XCTAssertLessThanOrEqual(p.s, { if case .beat = c { return 0.45 } else { return 0.3 } }() as Float, "\(c.name): rounded, not crisp"); XCTAssertLessThanOrEqual(p.i, 0.45, "\(c.name): soft") }
            let sig = ps.map { "\($0.delay)/\($0.i)/\($0.s)" }.joined(separator: ",")
            if let o = seen[sig] { XCTFail("\(c.name) has the same pattern as \(o)") }
            seen[sig] = c.name
        }
        // every solo emote of the room is covered by an IdleKind pattern (a new emote without one does not compile; a duplicate fails above)
        for k in BlobBrain.emoteKinds { XCTAssertNotNil(HapticCue.idle(k).spec) }
    }

    func testIntensityScalesWithEnergyAndJitterStaysWithin15Percent() {
        let c = HapticCue.sfx(.setdown)
        let lo = c.spec.pulses(energy: 0.4, jitter: 1)[0].i, hi = c.spec.pulses(energy: 1.4, jitter: 1)[0].i
        XCTAssertGreaterThan(hi, lo * 2)
        HapticDriver.jitter = { 1 + Float.random(in: -0.15...0.15) }
        var seenI = Set<Float>()
        for n in 0..<40 { now += 1; rec.clear(); d.cue(c); if let t = rec.events.first(where: { $0.kind == .transient }) { seenI.insert(t.intensity); let base = c.spec.i; XCTAssertTrue(t.intensity >= base * 0.849 && t.intensity <= base * 1.151, "n=\(n) \(t.intensity)") } }
        XCTAssertGreaterThan(seenI.count, 10, "varies a little on every play")
    }

    func testCueReachesTheSinkWithItsPulsesAndRateCapIsTwoPerSecond() {
        XCTAssertTrue(d.cue(.idle(.bounce)))
        XCTAssertEqual(rec.events.filter { $0.kind == .transient }.count, HapticCue.idleSpec(.bounce).n)
        XCTAssertEqual(rec.startCount, 1, "one engine start for the room")
        var ok: [Double] = []
        for t in [0.0, 0.2, 0.49, 0.5, 0.9, 1.0, 1.1, 1.6] { now = 2000 + t; if d.cue(.emote(.hic)) { ok.append(t) } }
        XCTAssertEqual(ok, [0.0, 0.5, 1.0, 1.6])
        XCTAssertEqual(rec.startCount, 1, "the same engine serves every cue")
    }

    func testSettingsOffWarmAndBusyStayOut() {
        HapticSettings.enabled = false
        XCTAssertFalse(d.cue(.idle(.bounce))); XCTAssertTrue(rec.events.isEmpty)
        HapticSettings.enabled = true
        now += 5; HapticDriver.roomBusy = { true }
        XCTAssertFalse(d.cue(.idle(.bounce))); HapticDriver.roomBusy = nil
        now += 5; d.setWarm(true)
        XCTAssertFalse(d.cue(.idle(.bounce)), "focus mode / the wash give their own haptics")
    }

    /// The regression: a room cue first (the engine up for the room), then focus mode: the touch haptics still reach the SAME engine, started once, and stop with it.
    func testTouchHapticsWorkAfterRoomCuesOnTheSameEngine() {
        XCTAssertTrue(d.cue(.sfx(.setdown)))
        XCTAssertEqual(rec.startCount, 1)
        d.setWarm(true)
        XCTAssertEqual(rec.startCount, 1, "no second start: the room's engine becomes focus's")
        rec.clear()
        d.transient(now: now, intensity: 0.4, sharpness: 0.2); d.wobble(now: now, peak: 0.3)
        XCTAssertEqual(rec.events.filter { $0.kind == .transient }.count, 1); XCTAssertEqual(rec.events.filter { $0.kind == .wobble }.count, 1)
        d.setWarm(false)
        XCTAssertFalse(rec.running)
        now += 5
        XCTAssertTrue(d.cue(.sfx(.squish)), "and the room can start it again")
        XCTAssertTrue(rec.running)
    }

    func testDefaultIsOnForAnOldSave() {
        UserDefaults.standard.removeObject(forKey: HapticSettings.key)
        XCTAssertTrue(HapticSettings.enabled)
        XCTAssertTrue(d.cue(.social(.greet)))
    }

    func testStormCuesPlayOutsideFocusThroughTheSameDriver() {
        let c = StormHaptics()
        c.request(.farRumble, now: 1, blocked: false, driver: d)
        XCTAssertFalse(rec.events.filter { $0.kind == .wobble }.isEmpty)
        XCTAssertEqual(rec.startCount, 1)
    }

    /// A brain's start of a move asks for exactly its cue; a racer asks for nothing.
    func testBrainMovesAskForTheirCue() {
        let r = MotionRig(game: true)
        var got: [String] = []
        HapticDriver.cueTap = { got.append($0.name) }
        r.brain.idleForced = true
        XCTAssertTrue(r.brain.idleStart(.hiccup, r.sim))
        XCTAssertTrue(got.contains("idle.hiccup"), "\(got)")
        r.brain.race.active = true
        got = []; now += 5
        r.brain.roomCue(.idle(.bounce))
        XCTAssertTrue(got.isEmpty)
    }
}
