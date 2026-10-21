//
//  EarsDSP.swift
//  Small signal processing on the mic stream, used two ways: ALWAYS for onsets (clap counting) and the beat (tempo + phase the dance follows),
//  and as the whole detector on a phone where SoundAnalysis is not available (then it also writes `EarsFrame`s: claps from broadband onsets,
//  music from a sustained periodic onset envelope in 70...160 BPM, a bang from the RMS).
//  Frames: a Hann window of ~20 ms (power of two), hop = half. Per frame: RMS, power spectrum (vDSP real DFT), spectral flux (the onset envelope),
//  spectral flatness (geometric / arithmetic mean of the power spectrum: ~0.5 for noise, ~0 for a tone). Tempo: autocorrelation of the last 6 s of
//  the envelope over the lag band, a half-tempo harmonic bonus, parabolic peak interpolation, then a comb search for the beat phase.
//  Not thread-safe: feed it from one thread (the listener's analysis queue) and read the callbacks there.
//

import Foundation
import Accelerate

nonisolated final class EarsDSP {
    let sampleRate: Double
    let n: Int
    let hop: Int
    var hopSeconds: Double { Double(hop) / sampleRate }

    /// Callbacks (on the feeding thread).
    var onOnset: ((EarOnset) -> Void)?
    var onBeat: ((EarBeat?, Double) -> Void)?
    /// Summary frame every `frameEvery` seconds (fallback mode writes classifier-like scores into it; the listener uses `rms` in both modes).
    var onFrame: ((EarsFrame) -> Void)?
    var frameEvery: Double = 0.25
    var tempoEvery: Double = 0.5
    /// Onset envelope ratio (flux over its running mean) that counts as an onset.
    var onsetThreshold: Float = 3.0
    /// Periodicity ratio (autocorrelation peak / band mean) needed before a beat is reported.
    var beatRatio: Float = 2.2
    static let bpmRange: ClosedRange<Float> = 70...160

    private let setup: vDSP_DFT_Setup
    private let window: [Float]
    private var pending: [Float] = []
    private var consumed = 0                     // samples consumed from the start of the stream
    private var frames = 0
    private var framesForBeat = 0
    private var framesForFrame = 0
    private var prevMag: [Float]
    private var fluxMean: Float = 0
    private var ratioHist: [Float] = [0, 0, 0]
    private var flatHist: [Float] = [0, 0, 0]
    private var lastOnsetFrame = -1000
    private var env: [Float]                     // onset envelope ring (last ~6 s)
    private var envHead = 0
    private var envFill = 0
    private var frameRmsMax: Float = 0
    private var frameRmsSum: Float = 0
    private var frameRmsN = 0
    private(set) var beat: EarBeat?
    private var beatRuns = 0
    private(set) var lastRatio: Float = 0
    /// Scratch
    private var re: [Float], im: [Float], outR: [Float], outI: [Float], power: [Float], windowed: [Float]

    init(sampleRate: Double) {
        self.sampleRate = sampleRate
        let want = max(256, Int(sampleRate * 0.02))
        var p = 256
        while p < want { p <<= 1 }
        n = p; hop = p / 2
        setup = vDSP_DFT_zrop_CreateSetup(nil, vDSP_Length(p), .FORWARD)!
        window = vDSP.window(ofType: Float.self, usingSequence: .hanningDenormalized, count: p, isHalfWindow: false)
        prevMag = [Float](repeating: 0, count: p / 2)
        let ringLen = Int(6.0 / (Double(p / 2) / sampleRate)) + 1
        env = [Float](repeating: 0, count: ringLen)
        re = [Float](repeating: 0, count: p / 2); im = re; outR = re; outI = re; power = re
        windowed = [Float](repeating: 0, count: p)
    }
    deinit { vDSP_DFT_DestroySetup(setup) }

    /// Seconds into the stream of frame `k`'s END.
    private func frameTime(_ k: Int) -> Double { Double(k * hop + n) / sampleRate }
    var time: Double { Double(consumed + pending.count) / sampleRate }

    // MARK: feeding

    func feed(_ samples: UnsafeBufferPointer<Float>) {
        pending.append(contentsOf: samples)
        while pending.count >= n {
            analyzeFrame()
            pending.removeFirst(hop)
            consumed += hop
        }
    }
    func feed(_ samples: [Float]) { samples.withUnsafeBufferPointer { feed($0) } }

    private func analyzeFrame() {
        let half = n / 2
        // rms of the hop (the new part)
        var ms: Float = 0
        pending.withUnsafeBufferPointer { p in vDSP_measqv(p.baseAddress! + half, 1, &ms, vDSP_Length(half)) }
        let rms = ms.squareRoot()
        frameRmsMax = max(frameRmsMax, rms); frameRmsSum += rms; frameRmsN += 1
        // spectrum
        pending.withUnsafeBufferPointer { p in
            window.withUnsafeBufferPointer { w in
                windowed.withUnsafeMutableBufferPointer { o in vDSP_vmul(p.baseAddress!, 1, w.baseAddress!, 1, o.baseAddress!, 1, vDSP_Length(n)) }
            }
        }
        windowed.withUnsafeBufferPointer { wp in
            re.withUnsafeMutableBufferPointer { r in im.withUnsafeMutableBufferPointer { i in
                wp.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: half) { c in
                    var split = DSPSplitComplex(realp: r.baseAddress!, imagp: i.baseAddress!)
                    vDSP_ctoz(c, 2, &split, 1, vDSP_Length(half))
                }
            } }
        }
        re.withUnsafeBufferPointer { r in im.withUnsafeBufferPointer { i in
            outR.withUnsafeMutableBufferPointer { oR in outI.withUnsafeMutableBufferPointer { oI in
                vDSP_DFT_Execute(setup, r.baseAddress!, i.baseAddress!, oR.baseAddress!, oI.baseAddress!)
            } }
        } }
        var flux: Float = 0, logSum: Float = 0, powSum: Float = 0
        let eps: Float = 1e-9
        for k in 1..<half {
            let p = outR[k] * outR[k] + outI[k] * outI[k]
            power[k] = p
            let mag = p.squareRoot()
            flux += max(0, mag - prevMag[k])
            prevMag[k] = mag
            logSum += logf(p + eps); powSum += p
        }
        let bins = Float(half - 1)
        let flatness = powSum > eps ? expf(logSum / bins) / (powSum / bins + eps) : 0
        // onset envelope: flux over its slow running mean
        fluxMean = fluxMean == 0 ? flux : fluxMean + (flux - fluxMean) * Float(hopSeconds / 1.0)
        let ratio = flux / max(fluxMean, 1e-6)
        ratioHist.removeFirst(); ratioHist.append(ratio)
        flatHist.removeFirst(); flatHist.append(flatness)
        // ring
        env[envHead] = min(ratio, 12)
        envHead = (envHead + 1) % env.count
        envFill = min(envFill + 1, env.count)
        // peak picking on the previous frame
        if frames >= 2, ratioHist[1] >= onsetThreshold, ratioHist[1] >= ratioHist[0], ratioHist[1] >= ratioHist[2], frames - 1 - lastOnsetFrame >= Int(0.08 / hopSeconds), rms > 0.002 {
            lastOnsetFrame = frames - 1
            onOnset?(EarOnset(time: frameTime(frames - 1), strength: ratioHist[1], flatness: flatHist[1]))
        }
        frames += 1
        framesForBeat += 1; framesForFrame += 1
        if Double(framesForBeat) * hopSeconds >= tempoEvery { framesForBeat = 0; estimateTempo() }
        if Double(framesForFrame) * hopSeconds >= frameEvery { framesForFrame = 0; emitFrame() }
    }

    // MARK: tempo

    private func estimateTempo() {
        let t = frameTime(frames - 1)
        guard envFill >= Int(3.0 / hopSeconds) else { return }
        let len = envFill
        // unroll the ring, oldest first, mean removed, half-wave rectified
        var x = [Float](repeating: 0, count: len)
        let start = (envHead - len + env.count) % env.count
        var mean: Float = 0
        for i in 0..<len { let v = env[(start + i) % env.count]; x[i] = v; mean += v }
        mean /= Float(len)
        var energy: Float = 0, peaks = 0, inPeak = false
        for i in 0..<len {
            if x[i] >= onsetThreshold { if !inPeak { peaks += 1; inPeak = true } } else { inPeak = false }
            x[i] = max(0, x[i] - mean); energy += x[i] * x[i]
        }
        guard energy > 1e-6 else { lose(t); return }
        let span = Double(len) * hopSeconds
        let lagMin = Int(60.0 / Double(Self.bpmRange.upperBound) / hopSeconds)
        let lagMax = Int(60.0 / Double(Self.bpmRange.lowerBound) / hopSeconds) + 1
        let lagTop = min(2 * lagMax + 1, len - 2)
        guard lagTop > lagMax else { return }
        var ac = [Float](repeating: 0, count: lagTop + 1)
        for l in 1...lagTop {
            var s: Float = 0
            x.withUnsafeBufferPointer { p in vDSP_dotpr(p.baseAddress!, 1, p.baseAddress! + l, 1, &s, vDSP_Length(len - l)) }
            ac[l] = s / Float(len - l)
        }
        // score: the lag plus half its harmonic (prefers the beat over the half-beat)
        var best = lagMin, bestScore: Float = -1, bandSum: Float = 0
        for l in lagMin...lagMax {
            let s = ac[l] + (2 * l <= lagTop ? 0.5 * ac[2 * l] : 0)
            bandSum += ac[l]
            if s > bestScore { bestScore = s; best = l }
        }
        let bandMean = bandSum / Float(lagMax - lagMin + 1)
        let ratio = bandMean > 1e-9 ? ac[best] / bandMean : 0
        lastRatio = ratio
        guard ratio >= beatRatio, ac[best] > 0 else { lose(t); return }
        // parabolic interpolation of the peak
        var lag = Float(best)
        if best > lagMin && best < lagMax {
            let a = ac[best - 1], b = ac[best], c = ac[best + 1]
            let d = a - 2 * b + c
            if abs(d) > 1e-9 { lag += 0.5 * (a - c) / d }
        }
        let period = Double(lag) * hopSeconds
        var bpm = Float(60 / period)
        bpm = min(max(bpm, Self.bpmRange.lowerBound), Self.bpmRange.upperBound)
        // a beat needs beats: at least 5 onsets in the window, and most of the grid's beats present (a few sparse claps are periodic to the
        // autocorrelation but they are not music)
        guard peaks >= 5, Double(peaks) >= 0.6 * span / period else { lose(t); return }
        // beat phase: the offset (frames back from the newest frame) whose comb collects the most envelope
        var bestOff = 0, bestComb: Float = -1
        let L = Double(lag)
        let combs = Int(Double(len) / L) - 1
        if combs >= 2 {
            for off in 0..<Int(lag.rounded(.up)) {
                var s: Float = 0
                for k in 0..<combs {
                    let idx = len - 1 - off - Int((Double(k) * L).rounded())
                    if idx >= 0 { s += x[idx] }
                }
                if s > bestComb { bestComb = s; bestOff = off }
            }
        }
        let anchor = t - Double(bestOff) * hopSeconds
        beatRuns += 1
        var b = EarBeat(bpm: bpm, anchor: anchor, strength: ratio)
        if let old = beat, abs(old.bpm - bpm) / old.bpm < 0.08 {
            b.bpm = old.bpm + (bpm - old.bpm) * 0.5       // smooth a steady tempo (the anchor stays the fresh measurement: only its fraction matters)
        }
        beat = b
        onBeat?(beatRuns >= 2 ? b : nil, t)
    }

    private func lose(_ t: Double) {
        if beat != nil || beatRuns > 0 { beat = nil; beatRuns = 0; onBeat?(nil, t) }
    }

    // MARK: summary frames (the fallback detector's input)

    private func emitFrame() {
        let t = frameTime(frames - 1)
        var f = EarsFrame(time: t)
        f.rms = frameRmsMax
        frameRmsMax = 0; frameRmsSum = 0; frameRmsN = 0
        if let b = beat, beatRuns >= 2 { f.scores[.music] = min(1, max(0, (b.strength - 1.6) / 2.4)) }
        onFrame?(f)
    }
}
