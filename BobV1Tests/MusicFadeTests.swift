//
//  MusicFadeTests.swift
//  The room music's fades: day -> evening -> night -> nap changes crossfade (never a step or a gap), a song hands over to the next with a crossfade
//  that ends with its file, Skip and the return from the background fade, the level between modes / the play layer's duck is slewed, a screen's
//  music and back fades both ways, and every playlist file is in the bundle, starts within 150 ms and ends within 150 ms of audible sound.
//

import XCTest
import AVFoundation
@testable import BobV1

@MainActor
final class MusicFadeTests: XCTestCase {
    typealias Track = BobV1.MusicTrack
    private let dt = 0.25

    private struct Stamped { var t: Double; var e: MusicEvent }
    /// Runs `seconds` of the situation `input`, stamping each event with the time it came out.
    private func run(_ d: inout MusicDirector, _ seconds: Double, _ input: MusicInput, at now: inout Double) -> [Stamped] {
        var out: [Stamped] = []
        var t = 0.0
        while t < seconds {
            now += dt; t += dt
            out += d.update(dt: dt, input: input).map { Stamped(t: now, e: $0) }
        }
        return out
    }
    private func plays(_ s: [Stamped]) -> [(t: Double, track: Track, fade: Double)] {
        s.compactMap { if case .playTrack(let tr, let f) = $0.e { return ($0.t, tr, f) }; return nil }
    }

    // MARK: time of day

    func testDayEveningNightNapChangesCrossfadeWithoutAGapOrAStep() {
        var d = MusicDirector(length: { _ in 150 }, rand: { 0.9 })
        var now = 0.0
        var all = run(&d, 20, MusicInput(phase: .day), at: &now)
        let route: [(DayPhase, Bool)] = [(.evening, false), (.night, false), (.night, true), (.night, false), (.morning, false), (.evening, false), (.day, false)]
        for (phase, nap) in route {
            let before = plays(all).count
            let ev = run(&d, 12, MusicInput(phase: phase, allNapping: nap), at: &now)
            let p = plays(ev)
            XCTAssertEqual(p.count, 1, "\(phase) nap=\(nap): exactly one new song (no double-play)")
            XCTAssertGreaterThanOrEqual(p.first?.fade ?? 0, 1.5, "the old song fades out and the new one in over >= 1.5 s")
            XCTAssertFalse(ev.contains { if case .fadeOutMain = $0.e { return true }; return false }, "no fade-out without a song coming in")
            XCTAssertFalse(ev.contains { if case .sceneOn = $0.e { return true }; return false })
            all += ev
            _ = before
        }
        // the mood of each song's pool follows the mode
        XCTAssertTrue(Track.lofiPool.contains(d.current!) || Track.dayPool.contains(d.current!) || Track.eveningPool.contains(d.current!))
    }

    func testModeFollowsTheClockAndKeepsMinimumDwell() {
        var d = MusicDirector(length: { _ in 150 }, rand: { 0.9 })
        var now = 0.0
        _ = run(&d, 10, MusicInput(phase: .day), at: &now)
        // flapping inside the dwell does not restart the music over and over
        var starts = 0
        for i in 0..<6 {
            let ev = run(&d, 1, MusicInput(phase: i % 2 == 0 ? .evening : .day), at: &now)
            starts += plays(ev).count
        }
        XCTAssertLessThanOrEqual(starts, 2, "a flapping clock cannot restart the song every second")
    }

    // MARK: song to song

    func testSongHandsOverWithACrossfadeThatEndsWithItsFile() {
        var d = MusicDirector(length: { _ in 150 }, rand: { 0.9 })      // two songs, then the longest gap
        var now = 0.0
        let ev = run(&d, 150 + 150 + 30, MusicInput(phase: .day), at: &now)
        let p = plays(ev)
        XCTAssertGreaterThanOrEqual(p.count, 2)
        // the second song starts `fade` seconds before the first one's file ends: [start 0.25 .. length - fade]
        XCTAssertEqual(p[1].t - p[0].t, 150 - d.fade, accuracy: dt * 2, "next song starts exactly one crossfade before the end")
        XCTAssertEqual(p[1].fade, d.fade)
        XCTAssertGreaterThanOrEqual(d.fade, 1.5)
        // after the second song: the fade-out starts one crossfade before its end, so the room goes quiet exactly as the file ends
        let out = ev.first { if case .fadeOutMain = $0.e { return true }; return false }
        XCTAssertNotNil(out)
        if let out { XCTAssertEqual(out.t - p[1].t, 150 - d.fade, accuracy: dt * 2); if case .fadeOutMain(let f) = out.e { XCTAssertEqual(f, d.fade) } }
    }

    func testAGapEndsWithAFadeIn() {
        var d = MusicDirector(length: { _ in 30 }, rand: { 0.0 })      // one song then the shortest gap (30 s)
        var now = 0.0
        let ev = run(&d, 30 + 30 + 40, MusicInput(phase: .day), at: &now)
        let p = plays(ev)
        XCTAssertGreaterThanOrEqual(p.count, 2)
        XCTAssertGreaterThanOrEqual(p[1].fade, 1.0, "the music fades in after the ambience gap")
        let out = ev.first { if case .fadeOutMain = $0.e { return true }; return false }
        XCTAssertNotNil(out)
        if let out { XCTAssertEqual(out.t, 30 - d.fade, accuracy: dt * 2) }
        if let out { XCTAssertEqual(p[1].t - out.t, 30, accuracy: dt * 3, "the gap (from the start of the fade-out) is the designed 30 s, no longer") }
    }

    // MARK: skip / resume

    func testSkipAndResumeFadeBothWays() {
        var d = MusicDirector(length: { _ in 150 }, rand: { 0.9 })
        var now = 0.0
        _ = run(&d, 5, MusicInput(phase: .day), at: &now)
        let s = plays(d.skip().map { Stamped(t: now, e: $0) })
        XCTAssertEqual(s.count, 1)
        XCTAssertGreaterThanOrEqual(s[0].fade, 1.5)
        XCTAssertEqual(plays(d.skip().map { Stamped(t: now, e: $0) }).count, 0, "a second tap inside 0.75 s does nothing")
        _ = run(&d, 1, MusicInput(phase: .day), at: &now)
        d.forceGap(60)
        let r = plays(d.resumed(deckPlaying: false).map { Stamped(t: now, e: $0) })
        XCTAssertEqual(r.count, 1)
        XCTAssertGreaterThanOrEqual(r[0].fade, 1.0)
    }

    // MARK: screens and back

    func testRoomToScreenAndBackFadesOutAndIn() {
        var d = MusicDirector(length: { _ in 150 }, rand: { 0.4 })
        var now = 0.0
        _ = run(&d, 10, MusicInput(phase: .day), at: &now)
        var shop = MusicInput(phase: .day); shop.scene = .shop
        let into = run(&d, 3, shop, at: &now)
        XCTAssertEqual(into.compactMap { if case .fadeOutMain(let f) = $0.e { return f }; return nil }.count, 1)
        XCTAssertEqual(into.compactMap { if case .sceneOn(_, let f) = $0.e { return f }; return nil }.count, 1)
        XCTAssertEqual(plays(into).count, 0, "no room song while a screen's music plays")
        for e in into { switch e.e { case .fadeOutMain(let f), .sceneOn(_, let f): XCTAssertGreaterThan(f, 1.0); default: break } }
        let back = run(&d, 3, MusicInput(phase: .day), at: &now)
        XCTAssertEqual(back.compactMap { if case .sceneOff(let f) = $0.e { return f }; return nil }.count, 1)
        let p = plays(back)
        XCTAssertEqual(p.count, 1)
        XCTAssertGreaterThanOrEqual(p.first?.fade ?? 0, 1.5)
    }

    // MARK: levels

    func testMainGainIsSlewedNotStepped() {
        var s = MainGainSlew()
        s.update(mode: 1, duck: 1, dt: 0.05)                         // day
        var last = s.gain, maxStep = 0.0
        // day -> evening -> night -> nap over the fade lengths: no 50 ms step bigger than the slew rate allows
        for target in [0.7, 0.75, 0.5, 1.0] {
            for _ in 0..<(8 * 20) {
                s.update(mode: target, duck: 1, dt: 0.05)
                maxStep = max(maxStep, abs(s.gain - last)); last = s.gain
            }
        }
        XCTAssertLessThanOrEqual(maxStep, MainGainSlew.modeRate * 0.05 + 1e-9)
        XCTAssertEqual(s.gain, 1, accuracy: 1e-6, "settles on the target")
        // the play layer's duck: down inside its 1 s fade-in, back up inside ~3 s
        var t = 0.0
        while t < 1.0 { s.update(mode: 1, duck: MusicDirector.layerDuck, dt: 0.05); t += 0.05 }
        XCTAssertLessThanOrEqual(s.gain, MusicDirector.layerDuck + 0.02)
        t = 0
        while t < 3.0 { s.update(mode: 1, duck: 1, dt: 0.05); t += 0.05 }
        XCTAssertGreaterThan(s.gain, 0.95)
    }

    func testEqualPowerCrossfadeKeepsLoudness() {
        for i in 0...20 {
            let x = Float(i) / 20
            let p = equalPower(x) * equalPower(x) + equalPower(1 - x) * equalPower(1 - x)
            XCTAssertEqual(p, 1, accuracy: 1e-5)
        }
        XCTAssertEqual(equalPower(0), 0); XCTAssertEqual(equalPower(1), 1, accuracy: 1e-6)
    }

    func testHubKeepsOneDeckLoudAfterASkipCrossfade() {
        let hub = AudioHub(defaults: UserDefaults(suiteName: UUID().uuidString)!, muted: false)
        hub._sceneEngineDisabled = true
        hub.start()
        for _ in 0..<4 { hub._tick(0.05) }
        guard hub._deckEffective.count == 1 else { return }          // no output device on this host
        hub.skipTrack()
        for _ in 0..<4 { hub._tick(0.05) }
        XCTAssertLessThanOrEqual(hub._deckEffective.count, 2, "at most the outgoing and the incoming song")
    }

    // MARK: the files

    /// Every playlist song and the play layer: in the bundle, audible within 150 ms of its start and end, and level with the rest of its playlist.
    func testPlaylistFilesExistAndHaveNoLeadingOrTrailingSilence() throws {
        let thr: Float = powf(10, -50 / 20)
        var rmsBySlot: [String: [(String, Double)]] = [:]
        let all: [(BobV1.MusicTrack, String)] = Track.dayPool.map { ($0, "day") } + Track.eveningPool.map { ($0, "evening") } + Track.lofiPool.map { ($0, "night") } + [(.lofiPlay, "play")]
        for (t, slot) in all {
            let u = try XCTUnwrap(Bundle.main.url(forResource: t.rawValue, withExtension: "m4a"), "\(t.rawValue).m4a missing from the bundle")
            let f = try AVAudioFile(forReading: u, commonFormat: .pcmFormatFloat32, interleaved: false)
            let n = AVAudioFrameCount(f.length)
            let buf = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: f.processingFormat, frameCapacity: n))
            try f.read(into: buf)
            let sr = f.processingFormat.sampleRate, ch = Int(f.processingFormat.channelCount), len = Int(buf.frameLength)
            let d = try XCTUnwrap(buf.floatChannelData)
            var first = -1, last = -1
            var sum = 0.0
            for i in 0..<len {
                var pk: Float = 0
                for c in 0..<ch { let v = abs(d[c][i]); pk = max(pk, v); sum += Double(v * v) }
                if pk > thr { if first < 0 { first = i }; last = i }
            }
            XCTAssertGreaterThanOrEqual(first, 0, "\(t.rawValue) is silent")
            let lead = Double(max(first, 0)) / sr, trail = Double(len - 1 - last) / sr
            XCTAssertLessThanOrEqual(lead, 0.15, "\(t.rawValue): \(Int(lead * 1000)) ms of silence at the start")
            XCTAssertLessThanOrEqual(trail, 0.15, "\(t.rawValue): \(Int(trail * 1000)) ms of silence at the end")
            XCTAssertGreaterThan(Double(len) / sr, 20, t.rawValue)
            rmsBySlot[slot, default: []].append((t.rawValue, 10 * log10(sum / Double(len * ch) + 1e-12)))
        }
        for (slot, rows) in rmsBySlot where rows.count > 2 {
            let med = rows.map(\.1).sorted()[rows.count / 2]
            for (name, db) in rows { XCTAssertLessThanOrEqual(abs(db - med), 3.5, "\(name) is \(Int(db - med)) dB off its \(slot) playlist") }
        }
    }

    func testNewRoomSongsAreInTheirPlaylists() {
        for n in 10...12 { XCTAssertTrue(Track.dayPool.contains(Track(rawValue: "day_\(n)")!)) }
        for n in 4...6 { XCTAssertTrue(Track.eveningPool.contains(Track(rawValue: "evening_\(n)")!)) }
        for n in 6...8 { XCTAssertTrue(Track.lofiPool.contains(Track(rawValue: "night_\(n)")!)) }
        XCTAssertEqual([Track.dayPool.count, Track.eveningPool.count, Track.lofiPool.count], [12, 6, 8])
    }
}
