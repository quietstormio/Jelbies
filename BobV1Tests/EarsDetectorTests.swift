//
//  EarsDetectorTests.swift
//  The sound-reaction state machine on synthetic classifier results: hysteresis, cooldowns, the double clap, music start / stop, the app-music
//  exclusion, the app-SFX mask. Plus: every label the kind map names exists in the built-in classifier (version 1).
//

import XCTest
import SoundAnalysis
@testable import BobV1

final class EarsDetectorTests: XCTestCase {
    /// Frames every 0.25 s (the 0.5 s window with 0.5 overlap) from `t0` for `seconds`, scores by closure.
    func feed(_ d: inout EarsDetector, from t0: Double, seconds: Double, appMusic: Float = 0, rms: Float = 0.05, _ scores: (Double) -> [EarKind: Float]) -> [EarEvent] {
        var out: [EarEvent] = []
        var t = t0
        while t < t0 + seconds - 1e-9 {
            out += d.frame(EarsFrame(time: t, scores: scores(t), rms: rms, appMusic: appMusic))
            t += 0.25
        }
        return out
    }

    func testLabelsExistInTheBuiltInClassifier() throws {
        let req = try SNClassifySoundRequest(classifierIdentifier: .version1)
        let known = Set(req.knownClassifications)
        for (k, ls) in EarKind.labels { for l in ls { XCTAssertTrue(known.contains(l), "\(k): label \(l) is not a known classification") } }
        XCTAssertEqual(EarKind.kindOf["clapping"], .clap)
        XCTAssertEqual(EarKind.kindOf["music"], .music)
    }

    func testHysteresisNeedsTwoFramesForSteadyKindsAndOneForTransients() {
        var d = EarsDetector()
        // laughter: one frame above `on` is not enough, two are; a dip under `off` re-arms it only after it fell below `off`
        XCTAssertEqual(d.frame(EarsFrame(time: 0.5, scores: [.laugh: 0.9])), [])
        XCTAssertEqual(d.frame(EarsFrame(time: 0.75, scores: [.laugh: 0.9])), [.heard(.laugh)])
        XCTAssertEqual(d.frame(EarsFrame(time: 1.0, scores: [.laugh: 0.4])), [], "between off and on: still active, nothing new")
        XCTAssertEqual(d.frame(EarsFrame(time: 1.25, scores: [.laugh: 0.9])), [], "still active: no second event")
        // a dog bark fires on the first frame
        XCTAssertEqual(d.frame(EarsFrame(time: 1.5, scores: [.dogBark: 0.8])), [.heard(.dogBark)])
        // a kind just under `on` never fires
        var e = EarsDetector()
        XCTAssertEqual(feed(&e, from: 0, seconds: 3) { _ in [.whistle: 0.45] }, [])
    }

    func testCooldownStopsRepeats() {
        var d = EarsDetector()
        var events: [EarEvent] = []
        // meow on / off / on every second for 20 s: the 6 s cooldown lets ~3 through, not 10
        for k in 0..<20 {
            let t = Double(k)
            events += d.frame(EarsFrame(time: t, scores: [.catMeow: 0.9]))
            events += d.frame(EarsFrame(time: t + 0.25, scores: [.catMeow: 0.9]))
            events += d.frame(EarsFrame(time: t + 0.5, scores: [.catMeow: 0.1]))
            events += d.frame(EarsFrame(time: t + 0.75, scores: [.catMeow: 0.1]))
        }
        let meows = events.filter { $0 == .heard(.catMeow) }.count
        XCTAssertGreaterThanOrEqual(meows, 3); XCTAssertLessThanOrEqual(meows, 4)
    }

    func testSingleClapWaitsThenFires() {
        var d = EarsDetector()
        var out = d.frame(EarsFrame(time: 1.0, scores: [.clap: 0.8]))
        XCTAssertEqual(out, [], "a first clap waits for its partner")
        out += d.advance(to: 1.3)
        XCTAssertEqual(out, [])
        out += d.advance(to: 1.6)
        XCTAssertEqual(out, [.heard(.clap)])
        XCTAssertEqual(d.hearing, .clap)
    }

    func testDoubleClapFromTwoOnsetsInOneWindow() {
        var d = EarsDetector()
        var out: [EarEvent] = []
        out += d.onset(EarOnset(time: 0.9, strength: 6, flatness: 0.4))
        out += d.onset(EarOnset(time: 1.3, strength: 6, flatness: 0.4))
        XCTAssertEqual(out, [], "onsets alone are not claps in classifier mode")
        out += d.frame(EarsFrame(time: 1.5, scores: [.clap: 0.8]))
        XCTAssertEqual(out, [.doubleClap])
        // the second window of the same claps adds nothing
        out = d.frame(EarsFrame(time: 1.75, scores: [.clap: 0.7]))
        out += d.advance(to: 3)
        XCTAssertEqual(out, [])
    }

    func testDoubleClapFromTwoWindowsAndItsCooldown() {
        var d = EarsDetector()
        var out = d.frame(EarsFrame(time: 1.0, scores: [.clap: 0.8]))
        out += d.frame(EarsFrame(time: 1.25, scores: [.clap: 0.1]))
        out += d.frame(EarsFrame(time: 1.5, scores: [.clap: 0.8]))
        XCTAssertEqual(out, [.doubleClap])
        // again within the cooldown: nothing (the clapping dropped out between, so each window rises afresh)
        out = d.frame(EarsFrame(time: 3.75, scores: [.clap: 0.1]))
        out += d.frame(EarsFrame(time: 4.0, scores: [.clap: 0.8]))
        out += d.frame(EarsFrame(time: 4.25, scores: [.clap: 0.1]))
        out += d.frame(EarsFrame(time: 4.5, scores: [.clap: 0.8]))
        out += d.advance(to: 6)
        XCTAssertEqual(out, [])
        // after the cooldown it works again
        out = d.frame(EarsFrame(time: 11.75, scores: [.clap: 0.1]))
        out += d.frame(EarsFrame(time: 12.0, scores: [.clap: 0.8]))
        out += d.frame(EarsFrame(time: 12.25, scores: [.clap: 0.1]))
        out += d.frame(EarsFrame(time: 12.5, scores: [.clap: 0.8]))
        XCTAssertEqual(out, [.doubleClap])
    }

    func testMusicStartsAfterFourSecondsAndStopsThreeAfterItEnds() {
        var d = EarsDetector()
        var events = feed(&d, from: 0, seconds: 3.5) { _ in [.music: 0.8] }
        XCTAssertEqual(events, [], "under 4 s of music is not music yet")
        XCTAssertFalse(d.musicPlaying)
        events = feed(&d, from: 3.5, seconds: 1.5) { _ in [.music: 0.8] }
        XCTAssertEqual(events, [.musicStarted(nil)])
        XCTAssertTrue(d.musicPlaying)
        // a one-second dip is bridged
        events = feed(&d, from: 5, seconds: 1) { _ in [.music: 0.1] }
        events += feed(&d, from: 6, seconds: 2) { _ in [.music: 0.7] }
        XCTAssertEqual(events, [])
        XCTAssertTrue(d.musicPlaying)
        // gone: stops after 3 s of silence, not before
        events = feed(&d, from: 8, seconds: 2.75) { _ in [.music: 0.05] }
        XCTAssertEqual(events, [])
        events = feed(&d, from: 10.75, seconds: 1) { _ in [.music: 0.05] }
        XCTAssertEqual(events, [.musicStopped])
        XCTAssertFalse(d.musicPlaying)
    }

    func testMusicShortBurstsNeverStart() {
        var d = EarsDetector()
        var events: [EarEvent] = []
        for k in 0..<6 {
            events += feed(&d, from: Double(k) * 6, seconds: 2) { _ in [.music: 0.9] }
            events += feed(&d, from: Double(k) * 6 + 2, seconds: 4) { _ in [.music: 0.05] }
        }
        XCTAssertEqual(events, [])
    }

    func testBeatArrivesWithMusicStartAndUpdates() {
        var d = EarsDetector()
        let b = EarBeat(bpm: 120, anchor: 0.1, strength: 3)
        _ = d.beat(b, at: 1)
        var events = feed(&d, from: 0, seconds: 5) { _ in [.music: 0.8] }
        XCTAssertEqual(events, [.musicStarted(b)])
        let b2 = EarBeat(bpm: 121, anchor: 0.6, strength: 3.2)
        events = d.beat(b2, at: 5.1)
        XCTAssertEqual(events, [.musicBeat(b2)])
        XCTAssertEqual(d.beat(b2, at: 5.6), [], "the same estimate is not resent")
    }

    func testAppMusicExclusion() {
        // the app's own lo-fi on the speaker: the classifier says "music 0.6" all day. No dance.
        var d = EarsDetector()
        var events = feed(&d, from: 0, seconds: 30, appMusic: 0.6) { _ in [.music: 0.62] }
        XCTAssertEqual(events, [])
        XCTAssertFalse(d.musicPlaying)
        XCTAssertGreaterThan(d.appMusicBaselineValue, 0.58, "the baseline learned the app's music")
        // real music over the top: confidence well above the baseline -> music
        events = feed(&d, from: 30, seconds: 5, appMusic: 0.6) { _ in [.music: 0.96] }
        XCTAssertEqual(events, [.musicStarted(nil)])
        // the same 0.62 frames with the app music SILENT are music (nothing to exclude)
        var e = EarsDetector()
        events = feed(&e, from: 0, seconds: 5, appMusic: 0) { _ in [.music: 0.62] }
        XCTAssertEqual(events, [.musicStarted(nil)])
        // and a modest confidence with the app music on never passes, whatever the baseline
        var f = EarsDetector()
        events = feed(&f, from: 0, seconds: 8, appMusic: 0.3) { _ in [.music: 0.7] }
        XCTAssertEqual(events, [])
    }

    func testAppSoundMasksTransientsButNotLaughter() {
        var d = EarsDetector()
        d.noteAppSound(at: 1.0)
        var out = d.frame(EarsFrame(time: 1.25, scores: [.clap: 0.9]))
        out += d.advance(to: 2.5)
        XCTAssertEqual(out, [], "the app's own boop is not a clap")
        out = d.frame(EarsFrame(time: 1.25, scores: [.laugh: 0.9]))
        out += d.frame(EarsFrame(time: 1.5, scores: [.laugh: 0.9]))
        XCTAssertEqual(out, [.heard(.laugh)])
    }

    func testBangFromLevelSpikeAndFromClassifier() {
        var d = EarsDetector()
        var out = feed(&d, from: 0, seconds: 3, rms: 0.05) { _ in [:] }
        out += d.frame(EarsFrame(time: 3, scores: [:], rms: 0.6))
        XCTAssertEqual(out, [.bang(level: 0.6)])
        out = d.frame(EarsFrame(time: 3.25, scores: [:], rms: 0.6))
        XCTAssertEqual(out, [], "cooldown")
        var e = EarsDetector()
        out = e.frame(EarsFrame(time: 1, scores: [.loudBang: 0.8], rms: 0.2))
        XCTAssertEqual(out, [.bang(level: 0.5)])
        XCTAssertEqual(e.hearing, .loudBang)
    }

    func testHearingFadesAndSpeechDoesNotCoverAClap() {
        var d = EarsDetector()
        _ = d.frame(EarsFrame(time: 1, scores: [.clap: 0.9]))
        XCTAssertEqual(d.hearing, .clap)
        _ = d.frame(EarsFrame(time: 1.25, scores: [.speech: 0.9]))
        _ = d.frame(EarsFrame(time: 1.5, scores: [.speech: 0.9]))
        XCTAssertEqual(d.hearing, .clap)
        _ = d.frame(EarsFrame(time: 3.5, scores: [.speech: 0]))        // the talking paused (re-arms the hysteresis)
        XCTAssertNil(d.hearing)
        _ = d.frame(EarsFrame(time: 4, scores: [.speech: 0.9]))
        _ = d.frame(EarsFrame(time: 4.25, scores: [.speech: 0.9]))
        XCTAssertEqual(d.hearing, .speech)
    }

    func testFallbackModeClapsFromBroadbandOnsets() {
        var d = EarsDetector(usesClassifier: false)
        var out = d.onset(EarOnset(time: 1.0, strength: 6, flatness: 0.4))
        out += d.onset(EarOnset(time: 1.4, strength: 6, flatness: 0.4))
        XCTAssertEqual(out, [.doubleClap])
        out = d.onset(EarOnset(time: 12, strength: 6, flatness: 0.05))       // a tonal attack (a note) is not a clap
        out += d.advance(to: 13)
        XCTAssertEqual(out, [])
        out = d.onset(EarOnset(time: 14, strength: 6, flatness: 0.4))
        out += d.advance(to: 15)
        XCTAssertEqual(out, [.heard(.clap)])
    }
}
