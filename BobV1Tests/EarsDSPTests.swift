//
//  EarsDSPTests.swift
//  The DSP fallback on synthetic PCM: a clap train gives broadband onsets (and claps through the fallback detector), a 120 BPM click track is music
//  with the beat within +-5 BPM and the beat grid on the clicks, silence and speech-like noise are not music.
//

import XCTest
@testable import BobV1

final class EarsDSPTests: XCTestCase {
    let sr = 16000.0

    /// A burst of noise with an exponential decay (a clap / a click) added at `t`.
    func burst(_ x: inout [Float], at t: Double, length: Double = 0.03, amp: Float = 0.6, seed: inout UInt64) {
        let i0 = Int(t * sr), n = Int(length * sr)
        for i in 0..<n where i0 + i < x.count {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            let r = Float(Int64(bitPattern: seed >> 11) % 2_000_000) / 1_000_000 - 1
            x[i0 + i] += amp * r * expf(-Float(i) / Float(n) * 4)
        }
    }
    func noiseFloor(_ x: inout [Float], amp: Float = 0.003, seed: inout UInt64) {
        for i in x.indices {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            x[i] += amp * (Float(Int64(bitPattern: seed >> 11) % 2_000_000) / 1_000_000 - 1)
        }
    }

    final class Sink {
        var onsets: [EarOnset] = []
        var beats: [(EarBeat?, Double)] = []
        var frames: [EarsFrame] = []
        var events: [EarEvent] = []
        var detector = EarsDetector(usesClassifier: false)
        func wire(_ d: EarsDSP) {
            d.onOnset = { [unowned self] o in onsets.append(o); events += detector.onset(o) }
            d.onBeat = { [unowned self] b, t in beats.append((b, t)); events += detector.beat(b, at: t) }
            d.onFrame = { [unowned self] f in frames.append(f); events += detector.frame(f) }
        }
    }

    func run(_ x: [Float]) -> (EarsDSP, Sink) {
        let d = EarsDSP(sampleRate: sr)
        let s = Sink()
        s.wire(d)
        var i = 0
        while i < x.count { let n = min(1024, x.count - i); d.feed(Array(x[i..<(i + n)])); i += n }      // fed in mic-sized chunks
        return (d, s)
    }

    func testClapTrainGivesBroadbandOnsetsAndClaps() {
        var seed: UInt64 = 7
        var x = [Float](repeating: 0, count: Int(sr * 8))
        noiseFloor(&x, seed: &seed)
        for t in [1.0, 1.4, 4.0, 7.0] { burst(&x, at: t, seed: &seed) }
        let (_, s) = run(x)
        XCTAssertEqual(s.onsets.count, 4, "one onset per clap: \(s.onsets.map { $0.time })")
        for (o, t) in zip(s.onsets, [1.0, 1.4, 4.0, 7.0]) {
            XCTAssertEqual(o.time, t, accuracy: 0.06)
            XCTAssertGreaterThan(o.flatness, 0.2, "a clap is broadband")
            XCTAssertGreaterThan(o.strength, 3)
        }
        let all = s.events + s.detector.advance(to: 8)
        XCTAssertEqual(all.filter { $0 == .doubleClap }.count, 1, "the pair at 1.0 / 1.4 is a double clap: \(all)")
        XCTAssertEqual(all.filter { $0 == .heard(.clap) }.count, 2, "the two single claps: \(all)")
        XCTAssertFalse(all.contains { if case .musicStarted = $0 { return true }; return false }, "claps are not music")
    }

    func testClickTrackIsMusicAtTheRightTempoAndPhase() {
        var seed: UInt64 = 3
        let bpm = 120.0, period = 60 / bpm
        var x = [Float](repeating: 0, count: Int(sr * 14))
        noiseFloor(&x, seed: &seed)
        var t = 0.37
        var clicks: [Double] = []
        while t < 14 { burst(&x, at: t, length: 0.012, amp: 0.5, seed: &seed); clicks.append(t); t += period }
        let (dsp, s) = run(x)
        let beat = try? XCTUnwrap(dsp.beat)
        XCTAssertNotNil(beat)
        if let b = beat {
            XCTAssertEqual(Double(b.bpm), bpm, accuracy: 5, "tempo")
            // the beat grid lands on the clicks (within a tenth of a beat)
            let nearest = clicks.min(by: { abs($0 - b.anchor) < abs($1 - b.anchor) })!
            XCTAssertEqual(b.anchor, nearest, accuracy: 0.06, "beat phase")
            XCTAssertGreaterThan(b.strength, 2.2)
        }
        let all = s.events + s.detector.advance(to: 14)
        let starts = all.filter { if case .musicStarted = $0 { return true }; return false }
        XCTAssertEqual(starts.count, 1, "the click track is music once it has held for 4 s: \(all)")
        XCTAssertFalse(all.contains(.doubleClap), "clicks on a beat are not claps")
        // and the tempo estimates stayed steady once found
        let found = s.beats.compactMap { $0.0 }.map { $0.bpm }
        XCTAssertGreaterThan(found.count, 4)
        for f in found.suffix(4) { XCTAssertEqual(Double(f), bpm, accuracy: 5) }
    }

    func testNinetyBpmClickTrackTempo() {
        var seed: UInt64 = 5
        let bpm = 90.0, period = 60 / bpm
        var x = [Float](repeating: 0, count: Int(sr * 14))
        noiseFloor(&x, seed: &seed)
        var t = 0.2
        while t < 14 { burst(&x, at: t, length: 0.012, amp: 0.5, seed: &seed); t += period }
        let (dsp, _) = run(x)
        XCTAssertEqual(Double(dsp.beat?.bpm ?? 0), bpm, accuracy: 5)
    }

    func testSilenceAndSpeechLikeNoiseAreNotMusic() {
        var seed: UInt64 = 11
        var quiet = [Float](repeating: 0, count: Int(sr * 10))
        noiseFloor(&quiet, seed: &seed)
        let (d1, s1) = run(quiet)
        XCTAssertNil(d1.beat)
        XCTAssertEqual(s1.events + s1.detector.advance(to: 10), [])
        // speech-like: irregular amplitude-modulated noise bursts ("syllables" 90...260 ms, pauses 40...400 ms), no steady period
        var speech = [Float](repeating: 0, count: Int(sr * 12))
        noiseFloor(&speech, seed: &seed)
        var t = 0.3
        func rnd(_ lo: Double, _ hi: Double) -> Double { seed = seed &* 6364136223846793005 &+ 1442695040888963407; return lo + (hi - lo) * Double(seed >> 11) / Double(1 << 53) }
        while t < 12 {
            let len = rnd(0.09, 0.26)
            let i0 = Int(t * sr), n = Int(len * sr)
            for i in 0..<n where i0 + i < speech.count {
                seed = seed &* 6364136223846793005 &+ 1442695040888963407
                let r = Float(Int64(bitPattern: seed >> 11) % 2_000_000) / 1_000_000 - 1
                let envv = sinf(.pi * Float(i) / Float(n))
                speech[i0 + i] += 0.25 * r * envv * (0.6 + 0.4 * sinf(Float(i) * 0.02))
            }
            t += len + rnd(0.04, 0.4)
        }
        let (d2, s2) = run(speech)
        let all = s2.events + s2.detector.advance(to: 12)
        XCTAssertFalse(all.contains { if case .musicStarted = $0 { return true }; return false }, "speech is not music (beat \(String(describing: d2.beat)), ratio \(d2.lastRatio))")
    }
}
