//
//  MusicSkipTests.swift
//  The Skip / next-song button: the director's skip, the now-playing row's states, the hub's disabled states, and the playlists loading.
//

import XCTest
import AVFoundation
@testable import BobV1

@MainActor
final class MusicSkipTests: XCTestCase {
    private func make(length: Double = 600, rand: @escaping () -> Double = { Double.random(in: 0..<1) }) -> MusicDirector {
        MusicDirector(length: { _ in length }, rand: rand)
    }
    private func run(_ d: inout MusicDirector, _ seconds: Double, input: MusicInput = MusicInput(phase: .day), dt: Double = 0.25) -> [MusicEvent] {
        var out: [MusicEvent] = []
        var t = 0.0
        while t < seconds { out += d.update(dt: dt, input: input); t += dt }
        return out
    }
    private func plays(_ ev: [MusicEvent]) -> [(BobV1.MusicTrack, Double)] { ev.compactMap { if case .playTrack(let t, let f) = $0 { return (t, f) }; return nil } }

    func testSkipAdvancesWithShortCrossfade() {
        var d = make()
        _ = run(&d, 10)
        let before = d.current
        let ev = d.skip()
        let p = plays(ev)
        XCTAssertEqual(p.count, 1)
        XCTAssertEqual(p[0].1, MusicDirector.skipFade)
        XCTAssertNotEqual(p[0].0, before)
        XCTAssertEqual(d.current, p[0].0)
        XCTAssertEqual(d.elapsed, 0)
    }

    func testSkipNeverRepeatsUntilPoolCycles() {
        for (phase, pool) in [(DayPhase.day, BobV1.MusicTrack.dayPool), (.night, BobV1.MusicTrack.lofiPool)] {
            var d = make()
            var seq: [BobV1.MusicTrack] = []
            _ = run(&d, 6, input: MusicInput(phase: phase))
            seq.append(d.current!)
            for _ in 0..<200 {
                _ = run(&d, 1, input: MusicInput(phase: phase))
                seq += plays(d.skip()).map { $0.0 }
            }
            XCTAssertEqual(seq.count, 201)
            for i in 1..<seq.count { XCTAssertNotEqual(seq[i], seq[i - 1]) }
            let n = pool.count
            for c in stride(from: 0, to: seq.count - n, by: n) { XCTAssertEqual(Set(seq[c..<c + n]).count, n, "each round plays each track once") }
        }
    }

    func testSkipInGapEndsGap() {
        var d = make()
        _ = run(&d, 3)
        d.forceGap(60)
        XCTAssertNotNil(d.gapLeft)
        let ev = d.skip()
        XCTAssertEqual(plays(ev).count, 1)
        XCTAssertNil(d.gapLeft)
        let after = run(&d, 5)
        XCTAssertFalse(after.contains { if case .fadeOutMain = $0 { return true }; return false })
    }

    func testSkipDebounce() {
        var d = make()
        _ = run(&d, 3)
        XCTAssertFalse(d.skip().isEmpty)
        _ = run(&d, 0.2, dt: 0.1)
        XCTAssertTrue(d.skip().isEmpty)
        _ = run(&d, 1)
        XCTAssertFalse(d.skip().isEmpty)
    }

    func testSkipIgnoredBeforeStartAndDuringScene() {
        var fresh = make()
        XCTAssertTrue(fresh.skip().isEmpty)
        var d = make()
        _ = run(&d, 3)
        _ = run(&d, 3, input: MusicInput(phase: .day, scene: .shop))
        let cur = d.current
        XCTAssertTrue(d.skip().isEmpty)
        XCTAssertEqual(d.current, cur)
    }

    func testSkipReleasesPlayLayer() {
        var d = make()
        _ = run(&d, 3, input: MusicInput(phase: .day, playing: true))
        XCTAssertTrue(d.layerOn)
        let ev = d.skip()
        XCTAssertTrue(ev.contains(.layerOff(fade: MusicDirector.skipFade)))
        XCTAssertEqual(plays(ev).count, 1)
        XCTAssertFalse(d.layerOn)
    }

    func testNowPlayingStates() {
        func np(muted: Bool = false, on: Bool = true, vol: Float = 0.8, other: Bool = false, mode: MusicMode = .day, scene: MusicScene = .none,
                cur: BobV1.MusicTrack? = .day1, gap: Bool = false, layer: Bool = false) -> NowPlaying {
            NowPlaying.make(muted: muted, musicOn: on, musicVolume: vol, otherAudioPlaying: other, mode: mode, scene: scene, current: cur, inGap: gap, layerOn: layer)
        }
        XCTAssertEqual(np(muted: true).state, .muted); XCTAssertFalse(np(muted: true).canSkip)
        XCTAssertEqual(np(on: false).state, .musicOff); XCTAssertFalse(np(on: false).canSkip)
        XCTAssertEqual(np(vol: 0).state, .musicOff); XCTAssertFalse(np(vol: 0).canSkip)
        XCTAssertEqual(np(other: true).state, .yourMusic); XCTAssertFalse(np(other: true).canSkip)
        XCTAssertEqual(np(scene: .race).state, .screen); XCTAssertFalse(np(scene: .race).canSkip)
        XCTAssertEqual(np(gap: true).state, .quiet); XCTAssertTrue(np(gap: true).canSkip)
        XCTAssertEqual(np().line, "Day · Soft Sunset"); XCTAssertTrue(np().canSkip)
        XCTAssertEqual(np(mode: .evening, cur: .evening2).line, "Evening · Lamp Glow")
        XCTAssertTrue(np(mode: .nap, cur: .night1).line.hasPrefix("Nap time · "))
        XCTAssertEqual(np(layer: true).line, "Play time · Zoomies")
    }

    func testHubSkipDisabledWhenMusicOffOrSilenced() {
        let hub = AudioHub(defaults: UserDefaults(suiteName: UUID().uuidString)!, muted: false)
        hub._sceneEngineDisabled = true
        hub.start()
        hub._tick(0.05)
        func plays() -> Int { hub.eventLog.filter { if case .playTrack = $0 { return true }; return false }.count }
        hub._setOtherAudio(true)
        XCTAssertFalse(hub.nowPlaying.canSkip)
        var n = plays(); hub.skipTrack(); XCTAssertEqual(plays(), n)
        hub._setOtherAudio(false)
        hub.settings.musicOn = false
        XCTAssertFalse(hub.nowPlaying.canSkip); XCTAssertEqual(hub.nowPlaying.state, .musicOff)
        n = plays(); hub.skipTrack(); XCTAssertEqual(plays(), n)
        hub.settings.musicOn = true
        if !hub.nowPlaying.canSkip { hub._forceGap(0); hub._tick(0.05) }
        n = plays(); hub.skipTrack()
        XCTAssertEqual(plays(), n + 1)
        if case .playTrack(_, let f)? = hub.eventLog.last(where: { if case .playTrack = $0 { return true }; return false }) { XCTAssertEqual(f, MusicDirector.skipFade) }
    }

    func testPlaylistsLoad() throws {
        for t in BobV1.MusicTrack.allCases {
            let u = try XCTUnwrap(Bundle.main.url(forResource: t.rawValue, withExtension: "m4a"), "\(t.rawValue).m4a missing")
            let f = try AVAudioFile(forReading: u)
            let secs = Double(f.length) / f.processingFormat.sampleRate
            XCTAssertGreaterThan(secs, t.isNew ? 110 : 20, t.rawValue)
        }
        let pools = [BobV1.MusicTrack.dayPool, BobV1.MusicTrack.eveningPool, BobV1.MusicTrack.lofiPool]
        XCTAssertEqual(Set(pools.flatMap { $0 }).count, pools.map(\.count).reduce(0, +), "pools are disjoint")
        XCTAssertEqual(pools.map(\.count), [9, 3, 5])
        for t in BobV1.MusicTrack.allCases where t != .lofiPlay { XCTAssertEqual(pools.filter { $0.contains(t) }.count, 1, t.rawValue) }
        let titles = BobV1.MusicTrack.allCases.map(\.title)
        XCTAssertTrue(titles.allSatisfy { !$0.isEmpty })
        XCTAssertEqual(Set(titles).count, titles.count)
    }
}
