//
//  NightSongKeepTests.swift
//  The user (2026-11-14): "When they go to sleep at night don't change the song keep the song that was going when they went to sleep".
//  At bedtime hours (`SleepHours.isNight`, about 20:22-07:07) the song that plays runs on through falling asleep and through a wake-up (only the level
//  eases); a daytime nap still switches to quiet lo-fi and back. Pure director cases + one hub case that walks the clock.
//

import XCTest
import AVFoundation
@testable import BobV1

@MainActor
final class NightSongKeepTests: XCTestCase {
    private typealias Track = BobV1.MusicTrack
    private let rule = "at bedtime hours the playing song runs on through sleep and wake"

    private func makeDirector() -> MusicDirector { MusicDirector(length: { _ in 150 }, rand: { 0.9 }) }

    @discardableResult
    private func run(_ d: inout MusicDirector, _ seconds: Double, _ input: MusicInput) -> [MusicEvent] {
        var out: [MusicEvent] = []
        var t = 0.0
        while t < seconds { out += d.update(dt: 0.25, input: input); t += 0.25 }
        return out
    }
    private func plays(_ ev: [MusicEvent]) -> [(track: Track, fade: Double)] {
        ev.compactMap { if case .playTrack(let t, let f) = $0 { return (t, f) }; return nil }
    }
    private func fadeOuts(_ ev: [MusicEvent]) -> Int { ev.filter { if case .fadeOutMain = $0 { return true }; return false }.count }

    private func night(_ nap: Bool = false) -> MusicInput { MusicInput(phase: .night, allNapping: nap, bedtime: true) }
    private func evening(_ nap: Bool = false, bedtime: Bool = true) -> MusicInput { MusicInput(phase: .evening, allNapping: nap, bedtime: bedtime) }

    // 1
    func testNightSongIsKeptOnSleepAndOnWake() {
        var d = makeDirector()
        run(&d, 20, night())
        let song = d.current
        XCTAssertNotNil(song)
        XCTAssertTrue(Track.lofiPool.contains(song!))
        let e0 = d.elapsed
        let asleep = run(&d, 12, night(true))
        XCTAssertTrue(plays(asleep).isEmpty, "\(rule): no new song when they fall asleep at night")
        XCTAssertEqual(fadeOuts(asleep), 0)
        XCTAssertEqual(d.current, song, "\(rule): same song")
        XCTAssertEqual(d.mode, .nap)
        XCTAssertEqual(d.elapsed - e0, 12, accuracy: 0.6, "the song keeps playing (its clock keeps running)")
        XCTAssertEqual(d.modeGain(), 0.5, accuracy: 1e-9, "only the level eases: nap 0.5")
        let e1 = d.elapsed
        let awake = run(&d, 12, night())
        XCTAssertTrue(plays(awake).isEmpty, "\(rule): no new song on a wake-up at night")
        XCTAssertEqual(fadeOuts(awake), 0)
        XCTAssertEqual(d.current, song)
        XCTAssertEqual(d.mode, .night)
        XCTAssertEqual(d.elapsed - e1, 12, accuracy: 0.6)
        XCTAssertEqual(d.modeGain(), 0.75, accuracy: 1e-9)
    }

    // 2
    func testKeptSongRunsToItsEndThenLofiFollows() {
        var d = makeDirector()
        run(&d, 20, night())
        let song = d.current!
        run(&d, 20, night(true))
        let ev = run(&d, 140, night(true))
        let p = plays(ev)
        XCTAssertEqual(p.count, 1, "the kept song ends, then exactly one next song")
        XCTAssertTrue(Track.lofiPool.contains(p[0].track), "asleep: the lo-fi playlist follows")
        XCTAssertNotEqual(p[0].track, song)
        XCTAssertEqual(d.mode, .nap)
    }

    // 3
    func testEveningSongIsKeptAtBedtimeAndWhenThePhaseTurnsNight() {
        var d = makeDirector()
        run(&d, 20, evening())
        let song = d.current!
        XCTAssertTrue(Track.eveningPool.contains(song), "an evening track opens the evening")
        let ev = run(&d, 12, evening(true))
        XCTAssertTrue(ev.isEmpty, "\(rule): phase evening, 20:22-21:00, asleep -> nothing happens: \(ev)")
        XCTAssertEqual(d.current, song)
        XCTAssertEqual(d.mode, .nap)
        let ev2 = run(&d, 12, night(true))
        XCTAssertTrue(ev2.isEmpty, "the phase turning night while asleep does not change the song: \(ev2)")
        XCTAssertEqual(d.current, song)
    }

    // 4
    func testWakeWhileTheKeptEveningSongStillPlaysKeepsIt() {
        var d = makeDirector()
        run(&d, 20, evening())
        let song = d.current!
        run(&d, 12, evening(true))
        let ev = run(&d, 12, evening())
        XCTAssertTrue(ev.isEmpty, "waking in the evening while its song still plays keeps it: \(ev)")
        XCTAssertEqual(d.current, song)
        XCTAssertEqual(d.mode, .evening)
    }

    // 5
    func testWakeAfterLofiFollowedStartsTheEveningsOwnMusic() {
        var d = makeDirector()
        run(&d, 20, evening())
        let song = d.current!
        let asleep = run(&d, 160, evening(true))
        let lofi = plays(asleep)
        XCTAssertEqual(lofi.count, 1)
        XCTAssertTrue(Track.lofiPool.contains(lofi[0].track))
        XCTAssertNotEqual(lofi[0].track, song)
        let ev = run(&d, 12, evening())
        let p = plays(ev)
        XCTAssertEqual(p.count, 1, "lo-fi no longer fits the evening: exactly one play on the wake-up")
        XCTAssertTrue(Track.eveningPool.contains(p[0].track), "from the evening playlist")
        XCTAssertEqual(d.mode, .evening)
    }

    // 6
    func testEarlyMorningBedtimeKeepsADaySongBothWays() {
        var d = makeDirector()
        let morning = MusicInput(phase: .morning, allNapping: false, bedtime: true)
        let morningNap = MusicInput(phase: .morning, allNapping: true, bedtime: true)
        run(&d, 20, morning)
        let song = d.current!
        XCTAssertTrue(Track.dayPool.contains(song))
        XCTAssertTrue(run(&d, 12, morningNap).isEmpty, "asleep at 06:30: the day song runs on")
        XCTAssertEqual(d.current, song)
        XCTAssertEqual(d.mode, .nap)
        XCTAssertTrue(run(&d, 12, morning).isEmpty, "awake again: still the same song")
        XCTAssertEqual(d.current, song)
        XCTAssertEqual(d.mode, .day)
    }

    // 7
    func testANightGapStaysAGapThroughSleepThenLofiStarts() {
        var d = makeDirector()
        run(&d, 20, night())
        d.forceGap(60)
        XCTAssertNotNil(d.gapLeft)
        let ev = run(&d, 12, night(true))
        XCTAssertTrue(ev.isEmpty, "falling asleep in a quiet gap changes nothing: \(ev)")
        XCTAssertNotNil(d.gapLeft, "the gap stays a gap")
        XCTAssertEqual(d.mode, .nap)
        let end = run(&d, 60, night(true))
        let p = plays(end)
        XCTAssertEqual(p.count, 1, "exactly one song when the gap ends")
        XCTAssertTrue(Track.lofiPool.contains(p[0].track))
    }

    // 8
    func testDaytimeAndEveningNapsStillSwitchBothWays() {
        var d = makeDirector()
        let day = MusicInput(phase: .day, allNapping: false, bedtime: false)
        run(&d, 20, day)
        let a = plays(run(&d, 12, MusicInput(phase: .day, allNapping: true, bedtime: false)))
        XCTAssertEqual(a.count, 1, "a daytime nap still gets lo-fi")
        XCTAssertTrue(Track.lofiPool.contains(a[0].track))
        let b = plays(run(&d, 12, day))
        XCTAssertEqual(b.count, 1, "and the day music when one wakes")
        XCTAssertTrue(Track.dayPool.contains(b[0].track))

        var e = makeDirector()
        run(&e, 20, evening(bedtime: false))
        let c = plays(run(&e, 12, evening(true, bedtime: false)))
        XCTAssertEqual(c.count, 1)
        XCTAssertTrue(Track.lofiPool.contains(c[0].track))
        let f = plays(run(&e, 12, evening(bedtime: false)))
        XCTAssertEqual(f.count, 1)
        XCTAssertTrue((Track.eveningPool + Track.dayPool).contains(f[0].track))
    }

    // 9
    func testAfterResumedTheClocksMusicStartsAtOnceButNightToNapStillKeeps() {
        var d = makeDirector()
        run(&d, 20, MusicInput(phase: .day))
        XCTAssertTrue(d.resumed(deckPlaying: true).isEmpty)
        let ev = d.update(dt: 0.1, input: evening(true))
        let p = plays(ev)
        XCTAssertEqual(p.count, 1, "back from away: the snap is unchanged")
        XCTAssertEqual(p.first?.fade ?? 0, 0.4, accuracy: 1e-9)
        XCTAssertTrue(Track.lofiPool.contains(p[0].track))

        var n = makeDirector()
        run(&n, 20, night())
        let song = n.current
        XCTAssertTrue(n.resumed(deckPlaying: true).isEmpty)
        let kept = n.update(dt: 0.1, input: night(true))
        XCTAssertTrue(plays(kept).isEmpty, "night -> nap after a return is lo-fi both ways: kept")
        XCTAssertEqual(n.current, song)
        XCTAssertEqual(n.mode, .nap)
    }

    // 10
    func testSwitchOffRestoresOneNewSongEachWayAtNight() {
        var d = makeDirector()
        d.keepSongAtBedtime = false
        run(&d, 20, night())
        XCTAssertEqual(plays(run(&d, 12, night(true))).count, 1, "old behaviour: a new song when they fall asleep")
        XCTAssertEqual(plays(run(&d, 12, night())).count, 1, "old behaviour: a new song on the wake-up")
    }

    // 11
    func testFlappingAsleepAndAwakeAtNightNeverRestartsTheMusic() {
        var d = makeDirector()
        run(&d, 20, night())
        var all: [MusicEvent] = []
        for i in 0..<60 { all += run(&d, 1, night(i % 2 == 0)) }
        XCTAssertTrue(plays(all).isEmpty, "\(rule): 60 s of waking and sleeping, no new song")
        XCTAssertEqual(fadeOuts(all), 0)
    }

    // 12
    func testTheBedtimeHoursSitInsideTheEveningPhase() {
        XCTAssertTrue(SleepHours.isNight(hour: 20.7))
        XCTAssertTrue(SleepHours.isNight(hour: 22))
        XCTAssertFalse(SleepHours.isNight(hour: 12))
        XCTAssertFalse(SleepHours.isNight(hour: 19))
        XCTAssertEqual(DayPhase.of(hour: 20.7), .evening, "20:22-21:00 is bedtime but the music phase is still evening")
    }

    // 13
    func testHubKeepsTheSongThroughTheClockWalk() {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        defaults.set(0.1, forKey: AudioSettings.keys.musicVolume)          // these run on a Mac with speakers
        defaults.set(0.1, forKey: AudioSettings.keys.sfxVolume)
        let clock = DayClock.shared
        let savedHour = clock.forcedHour
        defer { clock.forcedHour = savedHour }
        clock.forcedHour = 22
        let hub = AudioHub(defaults: defaults, muted: false)
        hub._sceneEngineDisabled = true
        hub.start()
        hub._setMinDwell(0)
        func playCount() -> Int { hub.eventLog.filter { if case .playTrack = $0 { return true }; return false }.count }
        func lastPlay() -> MusicTrack? {
            for e in hub.eventLog.reversed() { if case .playTrack(let t, _) = e { return t } }
            return nil
        }
        func step(asleep: Bool) {
            hub.situation(napping: [asleep], playing: false, xs: [0], moods: [.happy])
            hub._tick(0.05)
        }
        step(asleep: false)
        XCTAssertEqual(playCount(), 1, "22:00 awake: the first song starts")
        let first = hub._directorCurrent
        XCTAssertNotNil(first)
        XCTAssertTrue(MusicTrack.lofiPool.contains(first!))

        var n = playCount()
        step(asleep: true)
        XCTAssertEqual(playCount(), n, "22:00 they fall asleep: no new song")
        XCTAssertEqual(hub._directorCurrent, first)
        XCTAssertEqual(hub._directorMode, .nap)

        clock.forcedHour = 20.7
        step(asleep: false)
        XCTAssertEqual(playCount(), n + 1, "20:42 awake: lo-fi no longer fits, the evening's own music starts")
        XCTAssertTrue(MusicTrack.eveningPool.contains(lastPlay()!))
        n = playCount()
        let eveningSong = hub._directorCurrent
        step(asleep: true)
        XCTAssertEqual(playCount(), n, "20:42 they fall asleep: no new song")
        XCTAssertEqual(hub._directorCurrent, eveningSong)
        XCTAssertEqual(hub._directorMode, .nap)

        clock.forcedHour = 15
        step(asleep: true)
        XCTAssertEqual(playCount(), n, "the clock moving on while they sleep changes nothing")

        step(asleep: false)
        XCTAssertEqual(playCount(), n + 1, "15:00 awake: the day music")
        XCTAssertTrue(MusicTrack.dayPool.contains(lastPlay()!))
        n = playCount()
        step(asleep: true)
        XCTAssertEqual(playCount(), n + 1, "15:00 a daytime nap: lo-fi as before")
        XCTAssertTrue(MusicTrack.lofiPool.contains(lastPlay()!))
    }
}
