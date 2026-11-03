//
//  BlowDetectorTests.swift
//  The bubble wand's blow detector against synthetic audio: low-passed white / pink noise = a blow; a speech-like formant signal, claps, a music chord,
//  a short puff, a quiet hiss = NOT a blow; strength rises with the level; the app's own loud music switches it off.
//

import XCTest
@testable import BobV1

final class BlowDetectorTests: XCTestCase {
    static let sr = 44_100.0

    // MARK: signals

    struct Rng { var s: UInt64 = 0x1234ABCD
        mutating func next() -> Float { s ^= s << 13; s ^= s >> 7; s ^= s << 17; return Float(s >> 40) / Float(1 << 24) * 2 - 1 } }

    static func white(_ n: Int, seed: UInt64 = 7) -> [Float] { var r = Rng(s: seed | 1); return (0..<n).map { _ in r.next() } }
    /// Two-pole low-pass (two one-pole stages) at `fc`.
    static func lowpass(_ x: [Float], fc: Double) -> [Float] {
        let a = Float(1 - exp(-2 * Double.pi * fc / sr))
        var y1: Float = 0, y2: Float = 0
        return x.map { v in y1 += a * (v - y1); y2 += a * (y1 - y2); return y2 }
    }
    /// Voss-style pink-ish noise (three cascaded one-pole low-passes mixed).
    static func pink(_ n: Int, seed: UInt64 = 9) -> [Float] {
        let w = white(n, seed: seed)
        var b0: Float = 0, b1: Float = 0, b2: Float = 0
        return w.map { v in b0 = 0.99765 * b0 + v * 0.0990460; b1 = 0.96300 * b1 + v * 0.2965164; b2 = 0.57000 * b2 + v * 1.0526913; return b0 + b1 + b2 + v * 0.1848 }
    }
    static func scaled(_ x: [Float], toDb db: Float) -> [Float] {
        let rms = (x.reduce(0) { $0 + $1 * $1 } / Float(x.count)).squareRoot()
        let g = powf(10, db / 20) / max(rms, 1e-9)
        return x.map { $0 * g }
    }
    static func blow(_ n: Int, db: Float, seed: UInt64 = 7) -> [Float] { scaled(lowpass(white(n, seed: seed), fc: 600), toDb: db) }
    static func pinkBlow(_ n: Int, db: Float) -> [Float] { scaled(lowpass(pink(n), fc: 900), toDb: db) }
    /// A voiced vowel: 120 Hz harmonics shaped by formants at 700 / 1200 Hz, with a syllable envelope (about 4 Hz).
    static func speech(_ n: Int, db: Float) -> [Float] {
        var x = [Float](repeating: 0, count: n)
        for h in 1...30 {
            let f = 120.0 * Double(h)
            let g = Float(exp(-pow((f - 700) / 250, 2)) + 0.7 * exp(-pow((f - 1200) / 300, 2)) + 0.05)
            for i in 0..<n { x[i] += g * sinf(Float(2 * Double.pi * f * Double(i) / sr)) }
        }
        for i in 0..<n { x[i] *= 0.6 + 0.4 * sinf(Float(2 * Double.pi * 4 * Double(i) / sr)) }
        return scaled(x, toDb: db)
    }
    /// Claps: a 12 ms exponentially decaying noise burst every 0.3 s.
    static func claps(_ n: Int, peakDb: Float) -> [Float] {
        let w = white(n, seed: 21), g = powf(10, peakDb / 20)
        var x = [Float](repeating: 0, count: n)
        var t = 2000
        while t < n { for k in 0..<Int(0.04 * sr) where t + k < n { x[t + k] = w[t + k] * g * expf(-Float(k) / Float(0.004 * sr)) }; t += Int(0.3 * sr) }
        return x
    }
    static func chord(_ n: Int, db: Float) -> [Float] {
        var x = [Float](repeating: 0, count: n)
        for f in [261.6, 329.6, 392.0, 523.3] { for h in 1...4 { for i in 0..<n { x[i] += sinf(Float(2 * Double.pi * f * Double(h) * Double(i) / sr)) / Float(h) } } }
        return scaled(x, toDb: db)
    }

    /// Feeds `x` in tap-sized buffers; returns (ever blowing, blowing at the end, strength at the end, first blowing second).
    static func run(_ x: [Float], appLoud: Bool = false) -> (ever: Bool, end: Bool, strength: Float, first: Double?, d: BlowDetector) {
        let d = BlowDetector(sampleRate: sr)
        d.appLoud = appLoud
        var ever = false, first: Double?
        var i = 0
        while i < x.count {
            let e = min(i + 1024, x.count)
            d.feed(Array(x[i..<e]))
            if d.blowing, !ever { ever = true; first = Double(e) / sr }
            i = e
        }
        return (ever, d.blowing, d.strength, first, d)
    }

    // MARK: tests

    func testLowPassedWhiteNoiseIsABlow() {
        let r = Self.run(Self.blow(Int(Self.sr), db: -18))
        XCTAssertTrue(r.ever, "feat: db \(r.d.lastDb) low \(r.d.lastLow) flat \(r.d.lastFlat)")
        XCTAssertTrue(r.end, "feat: db \(r.d.lastDb) low \(r.d.lastLow) flat \(r.d.lastFlat)")
        XCTAssertGreaterThan(r.strength, 0.3)
        XCTAssertLessThan(r.first ?? 9, 0.30, "onset within ~120 ms plus a block or two")
        XCTAssertGreaterThanOrEqual(r.first ?? 0, 0.11, "never earlier than the 120 ms onset")
    }
    func testLowPassedPinkNoiseIsABlow() {
        let r = Self.run(Self.pinkBlow(Int(Self.sr), db: -20))
        XCTAssertTrue(r.ever && r.end, "feat: db \(r.d.lastDb) low \(r.d.lastLow) flat \(r.d.lastFlat)")
    }
    func testSpeechIsNotABlow() {
        for db: Float in [-12, -20, -28] {
            let r = Self.run(Self.speech(Int(Self.sr * 1.5), db: db))
            XCTAssertFalse(r.ever, "speech at \(db) dB read as a blow (low \(r.d.lastLow) flat \(r.d.lastFlat))")
        }
    }
    func testClapsAreNotABlow() {
        let r = Self.run(Self.claps(Int(Self.sr * 2), peakDb: -3))
        XCTAssertFalse(r.ever)
    }
    func testMusicChordIsNotABlow() {
        for db: Float in [-10, -18, -26] {
            let r = Self.run(Self.chord(Int(Self.sr * 1.5), db: db))
            XCTAssertFalse(r.ever, "a chord at \(db) dB read as a blow (low \(r.d.lastLow) flat \(r.d.lastFlat))")
        }
    }
    func testWhiteHissAndQuietNoiseAreNotABlow() {
        XCTAssertFalse(Self.run(Self.scaled(Self.white(Int(Self.sr)), toDb: -15)).ever, "broadband hiss has high-frequency energy")
        XCTAssertFalse(Self.run(Self.blow(Int(Self.sr), db: -45)).ever, "a quiet low rumble is below the level gate")
    }
    func testAShortPuffIsNotABlow() {
        let puff = Self.blow(Int(Self.sr * 0.07), db: -15)
        let x = puff + [Float](repeating: 0, count: Int(Self.sr))
        XCTAssertFalse(Self.run(x).ever, "70 ms is under the 120 ms onset")
    }
    func testStopsWhenTheWindStops() {
        let x = Self.blow(Int(Self.sr * 0.8), db: -16) + [Float](repeating: 0, count: Int(Self.sr * 0.6))
        let r = Self.run(x)
        XCTAssertTrue(r.ever)
        XCTAssertFalse(r.end)
        XCTAssertEqual(r.strength, 0)
    }
    func testStrengthRisesWithTheLevel() {
        var last: Float = -1
        for db: Float in [-28, -22, -16, -10] {
            let r = Self.run(Self.blow(Int(Self.sr), db: db))
            XCTAssertTrue(r.end, "blow at \(db) dB not detected")
            XCTAssertGreaterThan(r.strength, last, "strength must rise with RMS (\(db) dB -> \(r.strength) after \(last))")
            last = r.strength
        }
        XCTAssertGreaterThan(last, 0.8)
    }
    func testTheAppsOwnLoudSoundIsIgnored() {
        let r = Self.run(Self.blow(Int(Self.sr), db: -16), appLoud: true)
        XCTAssertFalse(r.ever)
    }
    func testWorksAt48k() {
        let d = BlowDetector(sampleRate: 48_000)
        let w = Self.white(48_000)
        let a = Float(1 - exp(-2 * Double.pi * 600 / 48_000)); var y1: Float = 0, y2: Float = 0
        let lp = w.map { v -> Float in y1 += a * (v - y1); y2 += a * (y1 - y2); return y2 }
        d.feed(Self.scaled(lp, toDb: -18))
        XCTAssertTrue(d.blowing)
    }
}
