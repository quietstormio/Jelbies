//
//  DayNightSoundTests.swift
//  Day phase + blend, the curtain skip and time-lapse, the music director's state machine, the mic duck, the settings, the variant picker,
//  the night-nap needs drain and the overnight away maths. All headless: no players, no GPU.
//

import XCTest
@testable import BobV1

/// 12:00 local time on the day of `ts` (tests of the away maths: the needs fall at half rate in the 21:00-06:00 hours, so their fixed
/// instants are anchored in the daytime, whatever the host's time zone).
func localNoon(_ ts: TimeInterval) -> Date {
    let off = Double(TimeZone.current.secondsFromGMT(for: Date(timeIntervalSince1970: ts)))
    return Date(timeIntervalSince1970: ((ts + off) / 86400).rounded(.down) * 86400 - off + 12 * 3600)
}

@MainActor
final class DayNightSoundTests: XCTestCase {
    // MARK: day phase + blend

    func testPhaseFromHour() {
        XCTAssertEqual(DayPhase.of(hour: 5.99), .night)
        XCTAssertEqual(DayPhase.of(hour: 6), .morning)
        XCTAssertEqual(DayPhase.of(hour: 10.99), .morning)
        XCTAssertEqual(DayPhase.of(hour: 11), .day)
        XCTAssertEqual(DayPhase.of(hour: 16.99), .day)
        XCTAssertEqual(DayPhase.of(hour: 17), .evening)
        XCTAssertEqual(DayPhase.of(hour: 20.99), .evening)
        XCTAssertEqual(DayPhase.of(hour: 21), .night)
        XCTAssertEqual(DayPhase.of(hour: 0), .night)
        XCTAssertEqual(DayPhase.of(hour: 25), .night)          // wraps
        XCTAssertEqual(DayPhase.of(hour: -1), .night)
    }

    func testBlendSumsToOneAndIsContinuous() {
        var prev = DayBlend(hour: 0)
        var h = 0.0
        while h < 24.0001 {
            let b = DayBlend(hour: h)
            XCTAssertEqual(b.sum, 1, accuracy: 1e-9, "hour \(h)")
            for p in DayPhase.allCases { XCTAssertGreaterThanOrEqual(b[p], 0) }
            // no hard jumps: a 36-second step moves any weight by well under 2 %
            for p in DayPhase.allCases { XCTAssertLessThan(abs(b[p] - prev[p]), 0.02, "jump in \(p) at \(h)") }
            prev = b; h += 0.01
        }
        XCTAssertEqual(DayBlend(hour: 3).night, 1)
        XCTAssertEqual(DayBlend(hour: 8.5).morning, 1)
        XCTAssertEqual(DayBlend(hour: 13).day, 1)
        XCTAssertEqual(DayBlend(hour: 19).evening, 1)
        XCTAssertEqual(DayBlend(hour: 23).night, 1)
        // sunrise 6-8: halfway at 7; sunset 19.5-21.5: halfway at 20.5
        XCTAssertEqual(DayBlend(hour: 7).morning, 0.5, accuracy: 1e-9)
        XCTAssertEqual(DayBlend(hour: 20.5).night, 0.5, accuracy: 1e-9)
        XCTAssertEqual(DayBlend(hour: 8).dominant, .morning)
    }

    // MARK: clock + curtain skip

    private func makeClock(hour: Double, suite: String = UUID().uuidString, uptime: UnsafeMutablePointer<Double>? = nil) -> (DayClock, UserDefaults, ClockBox) {
        let d = UserDefaults(suiteName: suite)!
        d.removePersistentDomain(forName: suite)
        d.set(true, forKey: DayClock.followKey)          // these suites test the real-clock mode; the game clock has its own tests below
        let box = ClockBox(hour: hour)
        let c = DayClock(defaults: d, now: { box.date }, uptime: { box.uptime }, calendar: box.cal)
        return (c, d, box)
    }

    final class ClockBox {
        var cal: Calendar = { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!; return c }()
        var date: Date
        var uptime = 1000.0
        static let base: Double = Double((1_800_000_000 / 86400) * 86400)
        init(hour: Double) { date = Date(timeIntervalSince1970: ClockBox.base + hour * 3600) }
        func set(hour: Double, dayOffset: Int = 0) { date = Date(timeIntervalSince1970: ClockBox.base + Double(dayOffset) * 86400 + hour * 3600) }
    }

    func testGameClockRunsSavesResumesAndFreshMorning() {
        let suite = UUID().uuidString
        let d = UserDefaults(suiteName: suite)!; d.removePersistentDomain(forName: suite)
        let box = ClockBox(hour: 15)
        let c = DayClock(defaults: d, now: { box.date }, uptime: { box.uptime }, calendar: box.cal)
        XCTAssertEqual(c.hour, 8, accuracy: 1e-6); XCTAssertEqual(c.day, 1)          // a new game: 8:00, Day 1
        box.uptime += 0.9; _ = c.hour
        for _ in 0..<60 { box.uptime += 0.9; _ = c.hour }                              // 54 s + 0.9 s = ~55 s
        XCTAssertEqual(c.hour, 8 + 54.9 / 60, accuracy: 1e-6)
        c.leaving(); box.uptime += 500; box.date = box.date.addingTimeInterval(500)    // away 500 s: nothing runs
        c.snapToNow(); XCTAssertEqual(c.hour, 8 + 54.9 / 60, accuracy: 1e-6)
        let c2 = DayClock(defaults: d, now: { box.date }, uptime: { box.uptime }, calendar: box.cal)
        XCTAssertEqual(c2.hour, 8 + 54.9 / 60, accuracy: 1e-3)                          // a relaunch resumes
        c2.leaving(); box.date = box.date.addingTimeInterval(7 * 3600)
        c2.snapToNow(); XCTAssertEqual(c2.hour, 7, accuracy: 1e-6); XCTAssertEqual(c2.day, 2)          // 6 h or more away: a fresh morning
        c2.skipToMorning(); XCTAssertEqual(c2.hour, 7, accuracy: 1e-6); XCTAssertEqual(c2.day, 3)
    }

    func testClockReadsHourAndForcedHour() {
        let (c, _, _) = makeClock(hour: 9.5)
        XCTAssertEqual(c.realHour, 9.5, accuracy: 1e-6)
        XCTAssertEqual(c.phase, .morning)
        c.forcedHour = 22
        XCTAssertEqual(c.hour, 22, accuracy: 1e-9)
        XCTAssertEqual(c.phase, .night)
    }

    func testCurtainSkipOffsetPersistsThenClearsOnRealPhaseChange() {
        let suite = UUID().uuidString
        let (c, d, box) = makeClock(hour: 9, suite: suite)
        XCTAssertEqual(c.offsetHours, 0)
        c.skipToNextPhase()                                   // morning -> day starts at 11
        XCTAssertEqual(c.hour, 11, accuracy: 1e-6)
        XCTAssertEqual(DayPhase.of(hour: c.hour), .day)
        XCTAssertEqual(c.offsetHours, 2, accuracy: 1e-6)
        XCTAssertTrue(c.isLapsing)
        // persisted: a new clock on the same defaults sees the offset
        let c2 = DayClock(defaults: d, now: { box.date }, uptime: { box.uptime }, calendar: box.cal)
        XCTAssertEqual(c2.hour, 11, accuracy: 1e-6)
        // the real clock stays in the morning: the offset stays
        box.set(hour: 10.5); c.refresh()
        XCTAssertEqual(c.offsetHours, 2, accuracy: 1e-6)
        XCTAssertEqual(c.hour, 12.5, accuracy: 1e-6)
        // the real clock reaches the next phase: the offset clears and the real time shows
        box.set(hour: 11.2); c.refresh()
        XCTAssertEqual(c.offsetHours, 0)
        XCTAssertEqual(c.hour, 11.2, accuracy: 1e-6)
        XCTAssertNil(d.string(forKey: DayClock.offsetPhaseKey))
        // skipping again and again walks day -> evening -> night -> morning
        c.skipToNextPhase(); XCTAssertEqual(DayPhase.of(hour: c.hour), .evening); XCTAssertEqual(c.hour, 17, accuracy: 1e-6)
        c.skipToNextPhase(); XCTAssertEqual(DayPhase.of(hour: c.hour), .night); XCTAssertEqual(c.hour, 21, accuracy: 1e-6)
        c.skipToNextPhase(); XCTAssertEqual(DayPhase.of(hour: c.hour), .morning); XCTAssertEqual(c.hour, 6, accuracy: 1e-6)
    }

    func testTimeLapseSweepsAndEnds() {
        let (c, _, box) = makeClock(hour: 9)
        c.skipToNextPhase()
        XCTAssertEqual(c.displayHour, 9, accuracy: 0.01)       // starts where it was
        box.uptime += 1.3
        let mid = c.displayHour
        XCTAssertGreaterThan(mid, 9.2); XCTAssertLessThan(mid, 10.9)
        box.uptime += 5
        c.refresh()
        XCTAssertFalse(c.isLapsing)
        XCTAssertEqual(c.displayHour, 11, accuracy: 1e-6)
        let l = TimeLapse(from: 22, to: 3, start: 0)            // wraps midnight
        XCTAssertEqual(l.to, 27, accuracy: 1e-9)
        XCTAssertEqual(l.hour(at: 100), 3, accuracy: 1e-9)
        let long = TimeLapse(from: 2, to: 2 + 100, start: 0)    // never whirls more than a day
        XCTAssertLessThanOrEqual(long.to - long.from, 24.0001)
    }

    /// Round 1022: the day is on the real clock before the first frame, however long he was away (the sweep is only for the curtain tap).
    func testReturnSnapsWithNoLapse() {
        let (c, _, box) = makeClock(hour: 20)
        let left = box.date
        box.set(hour: 20.5, dayOffset: 0)
        c.returned(from: left)
        XCTAssertFalse(c.isLapsing, "30 minutes away: no sweep")
        box.set(hour: 7, dayOffset: 1)
        c.returned(from: left)
        XCTAssertFalse(c.isLapsing, "a night away: no sweep either")
        XCTAssertEqual(c.displayHour, c.hour, accuracy: 1e-9)
        c.skipToNextPhase()
        XCTAssertTrue(c.isLapsing, "the curtain tap still sweeps")
        c.snapToNow()
        XCTAssertFalse(c.isLapsing)
        XCTAssertEqual(c.displayHour, c.hour, accuracy: 1e-9)
    }

    func testWindowTapTarget() {
        XCTAssertTrue(DayWindow.contains(x: 0, y: 3))
        XCTAssertTrue(DayWindow.contains(x: -3.5, y: 2))
        XCTAssertFalse(DayWindow.contains(x: 1.5, y: 3))        // wall between windows
        XCTAssertFalse(DayWindow.contains(x: 0, y: 0.5))
    }

    // MARK: light

    func testDayLightIsIdentityByDayAndNightHasSkyStarsLamp() {
        let day = DayLight.at(hour: 13)
        XCTAssertEqual(day, DayLight.day.withLampW(0))
        XCTAssertEqual(day.sky1.w, 0); XCTAssertEqual(day.jellyMul, 1)
        let night = DayLight.at(hour: 23)
        XCTAssertEqual(night.sky1.w, 1); XCTAssertEqual(night.sky0.w, 1); XCTAssertEqual(night.lamp.w, 1)
        XCTAssertGreaterThan(night.jellyMul, 0.6, "Jellies stay readable")
        let eve = DayLight.at(hour: 19)
        XCTAssertGreaterThan(eve.lamp.w, 0.5)
        XCTAssertGreaterThan(eve.keyCol.x, eve.keyCol.z, "golden key light")
        // quantised to a minute: two readings inside a minute are identical
        XCTAssertEqual(DayLight.at(hour: 12.0001), DayLight.at(hour: 12.0002))
    }

    // MARK: music director

    private func rng(_ seq: [Double]) -> () -> Double {
        var i = 0
        return { defer { i += 1 }; return seq[i % seq.count] }
    }

    private func run(_ d: inout MusicDirector, seconds: Double, input: MusicInput, dt: Double = 0.5) -> [MusicEvent] {
        var out: [MusicEvent] = []
        var t = 0.0
        while t < seconds { out += d.update(dt: dt, input: input); t += dt }
        return out
    }

    private func tracks(_ ev: [MusicEvent]) -> [MusicTrack] { ev.compactMap { if case .playTrack(let t, _) = $0 { return t }; return nil } }

    func testDayPlaylistShufflesWithoutRepeatUntilAllPlayed() {
        var d = MusicDirector(length: { _ in 20 }, rand: { Double.random(in: 0..<1) })
        d.fade = 3
        let ev = run(&d, seconds: 8000, input: MusicInput(phase: .day))
        let t = tracks(ev)
        XCTAssertGreaterThan(t.count, 10)
        let n = MusicTrack.dayPool.count
        XCTAssertGreaterThan(t.count, n * 2)
        for chunk in stride(from: 0, to: t.count - n, by: n) {
            XCTAssertEqual(Set(t[chunk..<chunk + n]).count, n, "each round plays every day track once")
        }
        for i in 1..<t.count { XCTAssertNotEqual(t[i], t[i - 1], "no immediate repeat") }
        XCTAssertTrue(t.allSatisfy { MusicTrack.dayPool.contains($0) })
    }

    func testGapsAfterOneOrTwoTracksAreThirtyToNinetySeconds() {
        var d = MusicDirector(length: { _ in 30 }, rand: { Double.random(in: 0..<1) })
        var inGap = false, gapStart = 0.0, now = 0.0, run1 = 0, runs: [Int] = [], gaps: [Double] = []
        for _ in 0..<20000 {
            let ev = d.update(dt: 0.25, input: MusicInput(phase: .day)); now += 0.25
            for e in ev {
                switch e {
                case .fadeOutMain: inGap = true; gapStart = now; runs.append(run1); run1 = 0
                case .playTrack: if inGap { gaps.append(now - gapStart); inGap = false }; run1 += 1
                default: break
                }
            }
        }
        XCTAssertGreaterThan(gaps.count, 6)
        for g in gaps { XCTAssertGreaterThanOrEqual(g, 30 - 0.3); XCTAssertLessThanOrEqual(g, 90 + 0.3) }
        for r in runs { XCTAssertTrue(r == 1 || r == 2, "\(r) tracks before a gap") }
        XCTAssertTrue(runs.contains(1) && runs.contains(2))
        // only ambience during a gap: no current track
        var d2 = MusicDirector(length: { _ in 30 }, rand: { 0.0 })   // one track, then the shortest gap
        _ = run(&d2, seconds: 28, input: MusicInput(phase: .day))
        _ = run(&d2, seconds: 3, input: MusicInput(phase: .day))
        XCTAssertNil(d2.current)
        XCTAssertNotNil(d2.gapLeft)
    }

    func testEveningStartsWithAnEveningTrackThenMixesDayTracksQuieter() {
        var d = MusicDirector(length: { _ in 20 }, rand: { Double.random(in: 0..<1) })
        let ev = run(&d, seconds: 600, input: MusicInput(phase: .evening))
        let t = tracks(ev)
        XCTAssertTrue(MusicTrack.eveningPool.contains(t.first!))
        XCTAssertTrue(t.allSatisfy { (MusicTrack.eveningPool + MusicTrack.dayPool).contains($0) })
        XCTAssertEqual(d.mode, .evening)
        XCTAssertLessThan(d.mainGain(), MusicDirector(rand: { 0 }).mainGain())
    }

    func testNightUsesLofiAndModeSwitchesCrossfade() {
        var d = MusicDirector(length: { _ in 60 }, rand: { Double.random(in: 0..<1) })
        var ev = run(&d, seconds: 30, input: MusicInput(phase: .day))
        XCTAssertTrue(MusicTrack.dayPool.contains(tracks(ev).last!))
        ev = run(&d, seconds: 10, input: MusicInput(phase: .night))
        let t = tracks(ev)
        XCTAssertEqual(t.count, 1)
        XCTAssertTrue(MusicTrack.lofiPool.contains(t[0]))
        if case .playTrack(_, let fade)? = ev.first(where: { if case .playTrack = $0 { return true }; return false }) { XCTAssertEqual(fade, 3) }
        XCTAssertEqual(d.mode, .night)
        // night playlist also never repeats until all three played
        var d2 = MusicDirector(length: { _ in 10 }, rand: { Double.random(in: 0..<1) })
        let t2 = tracks(run(&d2, seconds: 5000, input: MusicInput(phase: .night)))
        let k = MusicTrack.lofiPool.count
        for chunk in stride(from: 0, to: t2.count - k, by: k) { XCTAssertEqual(Set(t2[chunk..<chunk + k]).count, k) }
    }

    /// Back from the background: the music snaps to the clock's mood at once (fade 0.4), even before minDwell.
    func testResumeSnapsMusicToTheClock() {
        var d = MusicDirector(length: { _ in 80 }, rand: { Double.random(in: 0..<1) })
        _ = run(&d, seconds: 20, input: MusicInput(phase: .day))
        XCTAssertEqual(d.mode, .day)
        _ = d.resumed(deckPlaying: true)
        let ev = d.update(dt: 0.1, input: MusicInput(phase: .night))
        XCTAssertEqual(d.mode, .night)
        guard case .playTrack(let t, let fade)? = ev.first(where: { if case .playTrack = $0 { return true }; return false }) else { return XCTFail("a track starts at once") }
        XCTAssertTrue(MusicTrack.lofiPool.contains(t))
        XCTAssertEqual(fade, 0.4, accuracy: 1e-9)
    }

    func testAllJelliesNappingSwitchesToLofiAnyTimeAndBack() {
        var d = MusicDirector(length: { _ in 80 }, rand: { Double.random(in: 0..<1) })
        _ = run(&d, seconds: 20, input: MusicInput(phase: .day))
        XCTAssertEqual(d.mode, .day)
        var ev = run(&d, seconds: 10, input: MusicInput(phase: .day, allNapping: true))
        XCTAssertEqual(d.mode, .nap)
        XCTAssertTrue(MusicTrack.lofiPool.contains(tracks(ev).last!))
        XCTAssertLessThan(d.mainGain(), 0.6, "quiet for sleepers")
        ev = run(&d, seconds: 10, input: MusicInput(phase: .day, allNapping: false))     // one woke up
        XCTAssertEqual(d.mode, .day)
        XCTAssertTrue(MusicTrack.dayPool.contains(tracks(ev).last!))
    }

    func testPlayLayerTriggerReleaseCooldownAndNeverAtNight() {
        var d = MusicDirector(length: { _ in 600 }, rand: { 0.5 })
        _ = run(&d, seconds: 5, input: MusicInput(phase: .day))
        var ev = run(&d, seconds: 1, input: MusicInput(phase: .day, playing: true))
        XCTAssertTrue(ev.contains(.layerOn(fade: 1)))
        XCTAssertTrue(d.layerOn)
        XCTAssertLessThan(d.mainGain(), 0.2, "the playlist makes way for the play music")
        // still playing: stays on; calm: off after 8...10 s (rand 0.5 -> 9 s)
        ev = run(&d, seconds: 20, input: MusicInput(phase: .day, playing: true))
        XCTAssertFalse(ev.contains(.layerOff(fade: 3)))
        ev = run(&d, seconds: 8, input: MusicInput(phase: .day, playing: false))
        XCTAssertFalse(ev.contains(.layerOff(fade: 3)), "not before 8 s of calm")
        ev = run(&d, seconds: 2.5, input: MusicInput(phase: .day, playing: false))
        XCTAssertTrue(ev.contains(.layerOff(fade: 3)))
        XCTAssertFalse(d.layerOn)
        // cooldown 2 minutes: playing again right away does nothing; after the cooldown it does
        ev = run(&d, seconds: 60, input: MusicInput(phase: .day, playing: true))
        XCTAssertFalse(ev.contains(.layerOn(fade: 1)))
        ev = run(&d, seconds: 61, input: MusicInput(phase: .day, playing: true))
        XCTAssertTrue(ev.contains(.layerOn(fade: 1)))
        // never at night; a slight lift instead
        var n = MusicDirector(length: { _ in 600 }, rand: { 0.5 })
        _ = run(&n, seconds: 5, input: MusicInput(phase: .night))
        ev = run(&n, seconds: 30, input: MusicInput(phase: .night, playing: true))
        XCTAssertFalse(ev.contains(.layerOn(fade: 1)))
        XCTAssertGreaterThan(n.mainGain(playing: true), n.mainGain(playing: false))
        XCTAssertLessThan(n.mainGain(playing: true), n.mainGain(playing: false) * 1.3, "slight")
        // night arrives while the layer is on: it goes
        var m = MusicDirector(length: { _ in 600 }, rand: { 0.5 })
        _ = run(&m, seconds: 5, input: MusicInput(phase: .day))
        _ = run(&m, seconds: 1, input: MusicInput(phase: .day, playing: true))
        XCTAssertTrue(m.layerOn)
        ev = run(&m, seconds: 8, input: MusicInput(phase: .night, playing: true))
        XCTAssertFalse(m.layerOn)
    }

    // MARK: mic duck

    func testMicDucksHardThenRestores() {
        var duck = DuckState()
        XCTAssertEqual(duck.update(dt: 0.1), 1)
        duck.micOpened()
        for _ in 0..<5 { duck.update(dt: 0.05) }
        XCTAssertEqual(duck.gain, 0, accuracy: 1e-6, "silent within a quarter second")
        XCTAssertTrue(duck.isDucked)
        for _ in 0..<100 { duck.update(dt: 0.05) }
        XCTAssertEqual(duck.gain, 0, "stays down for as long as he listens")
        duck.micClosed()
        duck.update(dt: 0.2)
        XCTAssertEqual(duck.gain, 0, "a short settle first")
        for _ in 0..<10 { duck.update(dt: 0.1) }
        XCTAssertEqual(duck.gain, 1, accuracy: 1e-6, "restored")
        XCTAssertFalse(duck.isDucked)
        // re-opening mid-restore ducks again at once
        duck.micOpened(); duck.update(dt: 0.1); duck.micClosed(); duck.update(dt: 0.5)
        let mid = duck.gain
        XCTAssertGreaterThan(mid, 0); XCTAssertLessThan(mid, 1)
        duck.micOpened(); for _ in 0..<5 { duck.update(dt: 0.05) }
        XCTAssertEqual(duck.gain, 0, accuracy: 1e-6)
    }

    // MARK: settings, variants, fader

    func testSettingsPersist() {
        let suite = UUID().uuidString
        let d = UserDefaults(suiteName: suite)!
        d.removePersistentDomain(forName: suite)
        XCTAssertEqual(AudioSettings(defaults: d), AudioSettings())
        var s = AudioSettings()
        s.musicOn = false; s.sfxVolume = 0.3
        s.save(to: d)
        let r = AudioSettings(defaults: d)
        XCTAssertFalse(r.musicOn); XCTAssertTrue(r.sfxOn)
        XCTAssertEqual(r.sfxVolume, 0.3, accuracy: 1e-6)
        XCTAssertEqual(r.musicLevel, 0); XCTAssertEqual(r.sfxLevel, 0.3, accuracy: 1e-6)
    }

    func testHubIsSilentUnderTestsAndMute() {
        XCTAssertTrue(AudioHub.shared.muted)
        let hub = AudioHub(defaults: UserDefaults(suiteName: UUID().uuidString)!, muted: true)
        hub.start(); hub.play(.chomp); hub.chirp(jelly: 0, .happy); hub.micListening(true)
        XCTAssertTrue(hub.isDucked)
        hub.micListening(false)
    }

    func testVariantPickerNeverRepeatsImmediately() {
        var p = VariantPicker()
        var last = -1
        for _ in 0..<500 {
            let v = p.pick("squish", count: 3)
            XCTAssertNotEqual(v, last); XCTAssertTrue((0..<3).contains(v))
            last = v
        }
        XCTAssertEqual(p.pick("one", count: 1), 0)
        XCTAssertEqual(p.pick("one", count: 1), 0)
    }

    func testFaderRamps() {
        var f = Fader(); f.ramp(to: 1, over: 2)
        f.update(dt: 1); XCTAssertEqual(f.level, 0.5, accuracy: 1e-6)
        f.update(dt: 5); XCTAssertEqual(f.level, 1)
        f.ramp(to: 0, over: 1); f.update(dt: 0.25); XCTAssertEqual(f.level, 0.75, accuracy: 1e-6)
    }

    func testEverySfxAndMusicFileIsBundled() {
        let b = Bundle(for: DayNightSoundTests.self)
        let app = Bundle.main
        func has(_ n: String) -> Bool { app.url(forResource: n, withExtension: "m4a") != nil || b.url(forResource: n, withExtension: "m4a") != nil }
        for t in MusicTrack.allCases { XCTAssertTrue(has(t.rawValue), t.rawValue) }
        for s in SFX.allCases { XCTAssertTrue(has("\(s.rawValue)_1"), "\(s.rawValue)_1") }
        XCTAssertTrue(has("day_room")); XCTAssertTrue(has("evening_room"))
        for j in 1...JellyVoiceSet.count {
            XCTAssertTrue(has("babble_jelly\(j)"))
            for m in ["happy", "sad"] { XCTAssertTrue(has("chirp_jelly\(j)_\(m)")) }
        }
    }

    // MARK: night: napping, behaviour weights, needs

    func testNightShiftsIdleWeightsTowardNapsAndMorningTowardStretch() {
        func w(_ m: BlobMood, _ k: IdleKind, night: Float = 0, morning: Float = 0) -> Float {
            IdleTable.weights(m, night: night, morning: morning).first { $0.kind == k }?.weight ?? 0
        }
        for m in [BlobMood.happy, .okay, .grumpy] {
            XCTAssertGreaterThan(w(m, .sit, night: 1), w(m, .sit), "\(m) naps more at night")
            XCTAssertGreaterThan(w(m, .yawn, night: 1), w(m, .yawn))
            XCTAssertGreaterThan(w(m, .yawn, morning: 1), w(m, .yawn), "\(m) stretches in the morning")
        }
        XCTAssertLessThan(w(.happy, .zoomies, night: 1), w(.happy, .zoomies) * 0.5)
        // bedtime is the player's call: the night table never offers sleep by itself
        XCTAssertNil(IdleTable.weights(.happy, night: 1, morning: 0, sleep: true).first { $0.kind == .sleep }, "no autonomous sleep at night")
        // with no time of day it is exactly the old table
        for m in [BlobMood.happy, .okay, .grumpy] {
            let a = IdleTable.weights(m), b = IdleTable.weights(m, night: 0, morning: 0)
            XCTAssertEqual(a.map(\.kind), b.map(\.kind)); XCTAssertEqual(a.map(\.weight), b.map(\.weight))
        }
    }

    func testNightNapHalvesTheNeedsDrain() {
        let a = BlobNeeds(persists: false), b = BlobNeeds(persists: false)
        a.set(.hunger, 1); b.set(.hunger, 1)
        for _ in 0..<600 { a.step(dt: 1); b.step(dt: 1, drainScale: NeedsTuning.napDrain) }
        let da = 1 - a.level(.hunger), db = 1 - b.level(.hunger)
        XCTAssertGreaterThan(da, 0)
        XCTAssertEqual(db, da * 0.5, accuracy: da * 0.01)
    }

    func testOvernightAbsenceCountsHalfOnTheNeeds() {
        var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "UTC")!
        func date(_ day: Int, _ h: Double) -> Date { Date(timeIntervalSince1970: ClockBox.base + Double(day) * 86400 + h * 3600) }
        // 20:00 -> 08:00: night is 21-24 (3 h) + 0-6 (6 h) = 9 h of the 12
        XCTAssertEqual(AwayMath.nightSeconds(from: date(0, 20), to: date(1, 8), calendar: cal), 9 * 3600, accuracy: 1)
        XCTAssertEqual(AwayMath.needSeconds(from: date(0, 20), to: date(1, 8), calendar: cal), 7.5 * 3600, accuracy: 1)
        // a daytime absence is unchanged
        XCTAssertEqual(AwayMath.needSeconds(from: date(0, 9), to: date(0, 15), calendar: cal), 6 * 3600, accuracy: 1)
        // a whole day: 9 night hours of 24
        XCTAssertEqual(AwayMath.nightSeconds(from: date(0, 12), to: date(1, 12), calendar: cal), 9 * 3600, accuracy: 1)
        // gentler levels overnight than for the same duration by day
        let night = AwayMath.needLevels([1, 1, 1], from: date(0, 21), to: date(1, 5), calendar: cal)
        let day = AwayMath.needLevels([1, 1, 1], from: date(0, 9), to: date(0, 17), calendar: cal)
        XCTAssertGreaterThan(night[0], day[0])
        // the model applies it when it knows when the absence ended
        let n = BlobNeeds(persists: false)
        n.set(.hunger, 1)
        n.applyAway(seconds: 8 * 3600, endingAt: date(1, 5))         // (not the real clock's timezone: still never gentler-than-nothing)
        XCTAssertLessThanOrEqual(n.level(.hunger), 1)
    }

    func testBrainNapStateAndDrainScale() {
        let b = BlobBrain()
        XCTAssertFalse(b.isNapping)
        XCTAssertEqual(b.napDrainScale, 1)
    }
}

private extension DayLight {
    func withLampW(_ w: Float) -> DayLight { var c = self; c.lamp.w = w; return c }
}
