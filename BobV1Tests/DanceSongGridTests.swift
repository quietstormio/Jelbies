//
//  DanceSongGridTests.swift
//  The Jelly Show's four dance songs: each beat grid in `DanceSong.all` must sit on the song's real beats. The audio is decoded the way the app plays it
//  (`SceneRender.render`), an onset envelope is measured (log spectral magnitude rising, 512-sample frames, hop 64), and for every beat 0...lastBeat the strongest
//  onset within +-60 ms of the grid beat is taken. A straight line through (onset - grid beat) against the beat index must be flat: a slope is a wrong period
//  (the old grids were 0.2 % long: prompts drifted 20 to 29 ms late by the last beat). `measuredGrid` is how the grid numbers in ShowModel.swift were found.
//

import XCTest
import Accelerate
import AVFoundation
@testable import BobV1

final class DanceSongGridTests: XCTestCase {
    struct Envelope { var flux: [Double]; var times: [Double]; var duration: Double; var mono: [Float] = []; var sampleRate = 44100.0
        /// Broadband level (dB) of the 50 ms from `t`.
        func levelDB(from t: Double) -> Double {
            let a = max(Int(t * sampleRate), 0), b = min(a + Int(0.05 * sampleRate), mono.count)
            guard b > a else { return -120 }
            var s = 0.0; for i in a..<b { s += Double(mono[i] * mono[i]) }
            return 10 * log10(s / Double(b - a) + 1e-12)
        } }
    struct Fit { var slopeMS: Double; var interceptMS: Double; var offsetsMS: [Double]
        func atBeat(_ b: Int) -> Double { interceptMS + slopeMS * Double(b) } }

    /// The onset envelope of the decoded song (mono mix).
    static func envelope(_ track: SceneTrack) throws -> Envelope {
        let r = try XCTUnwrap(SceneRender.render(track), "decode \(track.rawValue)")
        let buf = r.loop, n = Int(buf.frameLength), ch = Int(buf.format.channelCount), sr = buf.format.sampleRate
        let data = try XCTUnwrap(buf.floatChannelData)
        var x = [Float](repeating: 0, count: n)
        for c in 0..<ch { vDSP.add(x, UnsafeBufferPointer(start: data[c], count: n), result: &x) }
        x = vDSP.multiply(1 / Float(ch), x)
        let N = 512, H = 64, half = N / 2
        let win: [Float] = (0..<N).map { Float(0.5 - 0.5 * cos(2 * Double.pi * Double($0) / Double(N - 1))) }
        let setup = try XCTUnwrap(vDSP_create_fftsetup(9, FFTRadix(kFFTRadix2)))
        defer { vDSP_destroy_fftsetup(setup) }
        var flux: [Double] = [0], prev = [Double](repeating: 0, count: half + 1)
        var frame = [Float](repeating: 0, count: N), re = [Float](repeating: 0, count: half), im = [Float](repeating: 0, count: half)
        var i = 0, frames = 0
        while i < n - N {
            vDSP.multiply(win, x[i..<(i + N)], result: &frame)
            var sp = [Double](repeating: 0, count: half + 1)
            re.withUnsafeMutableBufferPointer { rp in im.withUnsafeMutableBufferPointer { ip in
                var split = DSPSplitComplex(realp: rp.baseAddress!, imagp: ip.baseAddress!)
                frame.withUnsafeBufferPointer { fp in fp.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: half) { vDSP_ctoz($0, 2, &split, 1, vDSP_Length(half)) } }
                vDSP_fft_zrip(setup, &split, 1, 9, FFTDirection(kFFTDirection_Forward))
            } }
            // vDSP's real FFT is scaled by 2 (and packs Nyquist in imagp[0]): the same magnitudes numpy's rfft gives
            sp[0] = log1p(10 * Double(abs(re[0])) / 2); sp[half] = log1p(10 * Double(abs(im[0])) / 2)
            for k in 1..<half { sp[k] = log1p(10 * Double((re[k] * re[k] + im[k] * im[k]).squareRoot()) / 2) }
            if frames > 0 { var s = 0.0; for k in 0...half { s += max(sp[k] - prev[k], 0) }; flux.append(s) }
            prev = sp; frames += 1; i += H
        }
        let times = (0..<flux.count).map { (Double($0 * H) + Double(N) / 2) / sr }
        return Envelope(flux: flux, times: times, duration: Double(n) / sr, mono: x, sampleRate: sr)
    }

    /// (onset - grid beat) per beat 0...lastBeat, ms, and the straight-line fit against the beat index.
    static func fit(_ e: Envelope, grid: ShowBeat, lastBeat: Int) -> Fit {
        var offs: [Double] = []
        for b in 0...lastBeat {
            let g = grid.time(ofBeat: b)
            var best = -1.0, at = g
            for (j, t) in e.times.enumerated() where t > g - 0.06 && t < g + 0.06 && e.flux[j] > best { best = e.flux[j]; at = t }
            offs.append((at - g) * 1000)
        }
        let m = Double(offs.count), xs = (0..<offs.count).map(Double.init)
        let sx = xs.reduce(0, +), sy = offs.reduce(0, +), sxx = xs.reduce(0) { $0 + $1 * $1 }, sxy = zip(xs, offs).reduce(0) { $0 + $1.0 * $1.1 }
        let slope = (m * sxy - sx * sy) / (m * sxx - sx * sx)
        return Fit(slopeMS: slope, interceptMS: (sy - slope * sx) / m, offsetsMS: offs)
    }

    /// Strongest flux within +-`half` s of `t`.
    static func peak(_ e: Envelope, at t: Double, half: Double = 0.02) -> Double {
        var best = 0.0
        for (j, x) in e.times.enumerated() where x > t - half && x < t + half && e.flux[j] > best { best = e.flux[j] }
        return best
    }
    /// Mean onset strength AT the grid beats over mean onset strength half a beat after them (an off-beat lock, or a half / double tempo grid, scores near 1 or below).
    static func onOffRatio(_ e: Envelope, grid: ShowBeat, lastBeat: Int) -> Double {
        var on = 0.0, off = 0.0
        for b in 0...lastBeat { on += peak(e, at: grid.time(ofBeat: b)); off += peak(e, at: grid.time(ofBeat: b) + grid.period / 2) }
        return on / max(off, 1e-9)
    }
    /// Measured on the four songs: 1.39 / 1.33 / 1.28 / 1.26 on the right grids, 0.76 to 0.84 half a beat off (songs 1 and 3 have weak transients, so the margin is modest).
    static let minOnOffRatio = 1.1
    /// All of the test's criteria for one grid (what a right grid passes and a wrong one must fail).
    static func problems(_ e: Envelope, grid: ShowBeat, lastBeat: Int) -> [String] {
        var out: [String] = []
        let f = fit(e, grid: grid, lastBeat: lastBeat)
        if abs(f.slopeMS) > 0.3 { out.append(String(format: "slope %+.2f ms/beat", f.slopeMS)) }
        if abs(f.atBeat(lastBeat)) > 10 { out.append(String(format: "%+.1f ms at the last beat", f.atBeat(lastBeat))) }
        let r = onOffRatio(e, grid: grid, lastBeat: lastBeat)
        if r < minOnOffRatio { out.append(String(format: "on/off-beat ratio %.2f", r)) }
        if grid.time(ofBeat: lastBeat) + 0.06 >= e.duration { out.append("last beat outside the file") }
        return out
    }

    /// The grid the measurer fits (two passes: the second re-picks the onsets around the first fit).
    static func measuredGrid(_ e: Envelope, from g: ShowBeat, lastBeat: Int) -> ShowBeat {
        var grid = g
        for _ in 0..<2 {
            let f = fit(e, grid: grid, lastBeat: lastBeat)
            grid = ShowBeat(firstBeat: grid.firstBeat + f.interceptMS / 1000, period: grid.period + f.slopeMS / 1000)
        }
        return grid
    }

    func testEveryDanceSongGridSitsOnItsBeats() throws {
        var report: [String] = []
        for s in DanceSong.all {
            let e = try Self.envelope(s.track)
            let f = Self.fit(e, grid: s.grid, lastBeat: s.lastBeat)
            let m = Self.measuredGrid(e, from: s.grid, lastBeat: s.lastBeat)
            let line = String(format: "[gridtest] song %d: slope %+.2f ms/beat, at beat 0 %+.1f ms, at last beat %+.1f ms | measured grid firstBeat %.4f period %.5f (code %.4f / %.5f)",
                              s.song, f.slopeMS, f.interceptMS, f.atBeat(s.lastBeat), m.firstBeat, m.period, s.grid.firstBeat, s.grid.period)
            report.append(line); print(line)
            XCTAssertLessThanOrEqual(abs(f.slopeMS), 0.3, line)
            XCTAssertLessThanOrEqual(abs(f.atBeat(s.lastBeat)), 10, line)
            let ratio = Self.onOffRatio(e, grid: s.grid, lastBeat: s.lastBeat)
            let g = s.grid, half = ShowBeat(firstBeat: g.firstBeat, period: g.period * 2), dbl = ShowBeat(firstBeat: g.firstBeat, period: g.period / 2)
            let shifted = ShowBeat(firstBeat: g.firstBeat + g.period / 2, period: g.period)
            let wrong: [(String, [String])] = [("half tempo", Self.problems(e, grid: half, lastBeat: s.lastBeat / 2)), ("double tempo", Self.problems(e, grid: dbl, lastBeat: s.lastBeat * 2)),
                                               ("half a beat off", Self.problems(e, grid: shifted, lastBeat: s.lastBeat))]
            print(String(format: "[gridtest] song %d: on/off ratio %.2f, duration %.2f s, last beat + 0.06 = %.2f s", s.song, ratio, e.duration, g.time(ofBeat: s.lastBeat) + 0.06))
            for (name, p) in wrong { print("[gridtest] song \(s.song) \(name): \(p)") }
            XCTAssertTrue(Self.problems(e, grid: s.grid, lastBeat: s.lastBeat).isEmpty, "\(Self.problems(e, grid: s.grid, lastBeat: s.lastBeat))")
            // An off-beat lock must fail. Half and double tempo grids are only REPORTED above: on these songs the on / off-beat ratio does not separate them
            // (double tempo passes every criterion on every song, half tempo on song 3), so the test cannot rule out an octave error; that rests on the measured tempi.
            XCTAssertFalse(wrong[2].1.isEmpty, "song \(s.song): a grid half a beat off must FAIL the criteria")
        }
        XCTAssertEqual(report.count, 4)
    }
}
