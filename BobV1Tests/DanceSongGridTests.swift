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
    struct Envelope { var flux: [Double]; var times: [Double] }
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
        return Envelope(flux: flux, times: times)
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
        }
        XCTAssertEqual(report.count, 4)
    }
}
