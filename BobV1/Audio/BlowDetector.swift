//
//  BlowDetector.swift
//  Blowing into the microphone for the bubble wand. Wind on the mic capsule is sustained, LOUD, low-frequency, noise-like sound.
//  Per block (1024 samples, ~23 ms) the detector measures
//    level      RMS in dBFS                                   blow needs  >= -30 dBFS
//    low share  power below 1 kHz / power 40 Hz...8 kHz       blow needs  >= 0.70   (speech fricatives, hiss and claps have high-frequency energy)
//    flatness   geometric / arithmetic mean of the 60...1000 Hz power bins (~0.56 for noise, ~0.05 for a voice's harmonics or a chord)
//                                                               blow needs  >= 0.28   (speech, music and whistles are tonal)
//  and calls a block "windy" when all three hold. Blowing = windy blocks for at least `onsetSeconds` (120 ms) in a row (one stray block is
//  forgiven), so a clap (one or two blocks, broadband) never counts. It ends after `releaseSeconds` without wind.
//  While the app's own music/effects are loud (`appLoud`), nothing counts (like Ears: the speaker would be heard on the mic).
//  Strength 0...1 follows the level (-30 dBFS = 0 ... -8 dBFS = 1), rising fast and falling slowly: monotonic in RMS for a steady blow.
//  Not thread-safe to feed from two threads; reading `blowing` / `strength` is locked (the stage reads them on main).
//

import Foundation
import Accelerate

nonisolated final class BlowDetector: @unchecked Sendable {
    enum Tuning {
        static let minDb: Float = -30
        static let fullDb: Float = -8
        static let lowShare: Float = 0.70
        static let flatness: Float = 0.28
        static let onsetSeconds: Double = 0.12
        static let releaseSeconds: Double = 0.18
        static let block = 1024
    }

    /// The app's speaker music level (Ears) from which the mic is ignored.
    static let appLoudLevel: Float = 0.25
    let sampleRate: Double
    private let n = Tuning.block
    private let setup: vDSP_DFT_Setup
    private let window: [Float]
    private var pending: [Float] = []
    private var re: [Float], im: [Float], outR: [Float], outI: [Float], windowed: [Float]
    private let lock = NSLock()
    private var _blowing = false, _strength: Float = 0, _appLoud = false

    // block state (feeding thread)
    private var windyRun: Double = 0            // seconds of wind in a row (a one-block gap is forgiven)
    private var gap = 0
    private var quiet: Double = 0
    private var smooth: Float = 0
    /// Last block's features (tests, tuning).
    private(set) var lastDb: Float = -120, lastLow: Float = 0, lastFlat: Float = 0

    var blowing: Bool { lock.lock(); defer { lock.unlock() }; return _blowing }
    var strength: Float { lock.lock(); defer { lock.unlock() }; return _strength }
    /// The app's own sound is loud on the speaker: ignore the mic.
    var appLoud: Bool {
        get { lock.lock(); defer { lock.unlock() }; return _appLoud }
        set { lock.lock(); _appLoud = newValue; lock.unlock() }
    }

    init(sampleRate: Double) {
        self.sampleRate = max(8000, sampleRate)
        setup = vDSP_DFT_zrop_CreateSetup(nil, vDSP_Length(Tuning.block), .FORWARD)!
        window = vDSP.window(ofType: Float.self, usingSequence: .hanningDenormalized, count: Tuning.block, isHalfWindow: false)
        let h = Tuning.block / 2
        re = [Float](repeating: 0, count: h); im = re; outR = re; outI = re
        windowed = [Float](repeating: 0, count: Tuning.block)
    }
    deinit { vDSP_DFT_DestroySetup(setup) }

    func reset() {
        pending.removeAll(keepingCapacity: true)
        windyRun = 0; gap = 0; quiet = 0; smooth = 0
        lock.lock(); _blowing = false; _strength = 0; lock.unlock()
    }

    func feed(_ x: [Float]) { x.withUnsafeBufferPointer { feed($0) } }
    func feed(_ x: UnsafeBufferPointer<Float>) {
        pending.append(contentsOf: x)
        var pos = 0
        while pending.count - pos >= n {
            block(pending, from: pos)
            pos += n
        }
        if pos > 0 { pending.removeFirst(pos) }
    }

    private func block(_ b: [Float], from s: Int) {
        let dt = Double(n) / sampleRate
        var ms: Float = 0
        b.withUnsafeBufferPointer { p in vDSP_measqv(p.baseAddress! + s, 1, &ms, vDSP_Length(n)) }
        let db = 10 * log10f(max(ms, 1e-12))
        lastDb = db
        // spectrum
        b.withUnsafeBufferPointer { p in vDSP_vmul(p.baseAddress! + s, 1, window, 1, &windowed, 1, vDSP_Length(n)) }
        let half = n / 2
        for i in 0..<half { re[i] = windowed[2 * i]; im[i] = windowed[2 * i + 1] }
        re.withUnsafeBufferPointer { r in im.withUnsafeBufferPointer { i in
            outR.withUnsafeMutableBufferPointer { oR in outI.withUnsafeMutableBufferPointer { oI in
                vDSP_DFT_Execute(setup, r.baseAddress!, i.baseAddress!, oR.baseAddress!, oI.baseAddress!)
            } }
        } }
        let binHz = Float(sampleRate) / Float(n)
        let kLo = max(1, Int(40 / binHz)), kFlatLo = max(1, Int(60 / binHz)), kOne = max(kFlatLo + 2, Int(1000 / binHz))
        let kHi = min(half - 1, Int(8000 / binHz))
        var total: Float = 0, low: Float = 0, logSum: Float = 0, flatSum: Float = 0
        var flatN: Float = 0
        for k in kLo...kHi {
            let p = outR[k] * outR[k] + outI[k] * outI[k]
            total += p
            if k <= kOne { low += p }
            if k >= kFlatLo && k <= kOne { logSum += logf(p + 1e-12); flatSum += p; flatN += 1 }
        }
        let lowShare = total > 1e-12 ? low / total : 0
        let flat = flatN > 0 && flatSum > 1e-12 ? expf(logSum / flatN) / (flatSum / flatN + 1e-12) : 0
        lastLow = lowShare; lastFlat = flat
        let loud = appLoud
        let windy = !loud && db >= Tuning.minDb && lowShare >= Tuning.lowShare && flat >= Tuning.flatness

        if windy { windyRun += dt + (gap > 0 ? dt : 0); gap = 0; quiet = 0 }
        else if windyRun > 0, gap == 0, !loud { gap = 1 }          // one stray block is forgiven
        else { windyRun = 0; gap = 0; quiet += dt }
        let isBlow = windyRun >= Tuning.onsetSeconds || (_blowingNow && quiet < Tuning.releaseSeconds && windyRun > 0)
        // strength: level mapped, fast attack / slow release
        let target = windy ? max(0, min(1, (db - Tuning.minDb) / (Tuning.fullDb - Tuning.minDb))) : 0
        if target > smooth { smooth += (target - smooth) * 0.6 } else { smooth += (target - smooth) * 0.12 }
        lock.lock()
        _blowing = isBlow || (_blowing && quiet < Tuning.releaseSeconds && smooth > 0.02)
        _strength = _blowing ? max(smooth, 0.05) : 0
        lock.unlock()
    }
    private var _blowingNow: Bool { lock.lock(); defer { lock.unlock() }; return _blowing }
}
