//
//  EarsDetector.swift
//  The sound-reaction state machine. Pure logic on an injected clock: classifier frames (`EarsFrame`) give the KIND of sound, DSP onsets give the
//  COUNT and timing of claps, a beat estimate gives the tempo. Per kind: hysteresis (on / off thresholds, consecutive frames) and a cooldown.
//  Clap: the first clap waits `clapDecide` for a second one (double clap = everyone comes). Music: on for `musicHold` seconds before it starts
//  (short dips bridged), off for `musicRelease` before it stops. App-music exclusion: while the app's own music is audible, the music confidence
//  must beat a learned baseline (what the classifier says about the app's music) by a margin.
//

import Foundation

nonisolated struct EarsDetector {
    /// False = the DSP fallback feeds this detector: claps come straight from broadband onsets, music from the tempo tracker.
    var usesClassifier = true

    // per-kind hysteresis
    private var active: Set<EarKind> = []
    private var run: [EarKind: Int] = [:]
    private var lastFired: [EarKind: Double] = [:]
    private var lastDouble: Double = -1e9
    // claps
    private var claps: [Double] = []                 // clap times still being decided
    private var onsets: [EarOnset] = []              // recent DSP onsets (last ~1.5 s)
    private var lastClapWindow: Double = -1e9        // the last frame in which the classifier heard clapping
    private var clapsAdopted: Double = -1e9          // onsets up to this time were already counted
    // music
    private var musicOnSince: Double?
    private var musicLastSeen: Double = -1e9
    private(set) var musicPlaying = false
    private var beat: EarBeat?
    private var lastBeatSent: EarBeat?
    private var appMusicBaseline: Float = EarsTuning.appMusicBaselineStart
    // level
    private var rmsAvg: Float = 0
    private var lastBang: Double = -1e9
    private var appSoundAt: Double = -1e9
    // hud
    private(set) var hearing: EarKind?
    private var hearingAt: Double = -1e9
    private(set) var now: Double = 0

    init(usesClassifier: Bool = true) { self.usesClassifier = usesClassifier }

    // MARK: inputs

    /// The app played one of its own sound effects (jump, boop ...): transient kinds are masked for a moment.
    mutating func noteAppSound(at t: Double) { appSoundAt = max(appSoundAt, t) }

    /// A DSP onset (any mode). In classifier mode it only counts as a clap once a clap window covers it.
    mutating func onset(_ o: EarOnset) -> [EarEvent] {
        onsets.append(o)
        onsets.removeAll { $0.time < o.time - 2 }
        var out: [EarEvent] = []
        if !usesClassifier, o.strength >= 3, o.flatness >= 0.2, o.time - appSoundAt > EarsTuning.appSoundMask {
            addClap(o.time, &out)
        }
        return out + advance(to: max(now, o.time))
    }

    /// A tempo estimate (or nil when the beat was lost).
    mutating func beat(_ b: EarBeat?, at t: Double) -> [EarEvent] {
        beat = b
        var out: [EarEvent] = []
        if musicPlaying, let b, b != lastBeatSent { lastBeatSent = b; out.append(.musicBeat(b)) }
        return out + advance(to: max(now, t))
    }

    /// One classifier window (or a DSP summary frame).
    mutating func frame(_ f: EarsFrame) -> [EarEvent] {
        var out: [EarEvent] = []
        now = max(now, f.time)
        rmsAvg = rmsAvg == 0 ? f.rms : rmsAvg + (f.rms - rmsAvg) * 0.1
        // --- per-kind hysteresis
        for k in EarKind.allCases where k != .music {
            let s = f[k]
            let rising = !active.contains(k)
            if rising {
                if s >= EarsTuning.on[k]! { run[k, default: 0] += 1 } else { run[k] = 0 }
                if run[k, default: 0] >= EarsTuning.onFrames(k) {
                    active.insert(k)
                    turnedOn(k, f, &out)
                }
            } else if s < EarsTuning.off[k]! {
                active.remove(k); run[k] = 0
            }
        }
        // --- a loud spike by level alone (the DSP fallback, or a bang the classifier has no word for)
        if f.rms >= EarsTuning.bangRms, f.rms >= rmsAvg * EarsTuning.bangRatio, f.time - lastBang > EarsTuning.cooldown[.loudBang]!,
           f.time - appSoundAt > EarsTuning.appSoundMask, !active.contains(.loudBang) {
            lastBang = f.time
            out.append(.bang(level: min(1, f.rms)))
            see(.loudBang, f.time)
        }
        // --- music, with the app-music exclusion
        let m = f[.music]
        let appOn = f.appMusic >= EarsTuning.appMusicAudible
        var musicHere = false
        if appOn {
            if !musicPlaying, musicOnSince == nil { appMusicBaseline += (m - appMusicBaseline) * 0.08 }        // learn what the app's own music sounds like to the classifier
            musicHere = m >= max(EarsTuning.appMusicFloor, min(0.95, appMusicBaseline + EarsTuning.appMusicMargin))
        } else {
            musicHere = m >= (musicOnSince == nil ? EarsTuning.on[.music]! : EarsTuning.off[.music]!)
        }
        if musicHere {
            musicLastSeen = f.time
            if musicOnSince == nil { musicOnSince = f.time }
            see(.music, f.time)
        }
        return out + advance(to: f.time)
    }

    /// Time passes: pending clap decisions, music start / stop. Call at least a few times a second.
    mutating func advance(to t: Double) -> [EarEvent] {
        now = max(now, t)
        var out: [EarEvent] = []
        // claps: decide once the partner window has passed
        if let first = claps.first, now - first >= EarsTuning.clapDecide || claps.count >= 2 {
            let recent = claps.filter { $0 >= first - 0.01 && $0 <= first + EarsTuning.doubleClapWindow }
            if recent.count >= 2 {
                if now - lastDouble >= EarsTuning.doubleClapCooldown { lastDouble = now; out.append(.doubleClap) }
                claps.removeAll()
            } else if claps.count >= 2 || now - first >= EarsTuning.clapDecide {
                if fire(.clap, at: first) { out.append(.heard(.clap)) }
                claps.removeFirst()
            }
        }
        // music: hold before start, release (with gap bridging) before stop
        if let since = musicOnSince {
            if now - musicLastSeen > EarsTuning.musicGap && !musicPlaying { musicOnSince = nil }
            else if !musicPlaying, now - since >= EarsTuning.musicHold {
                musicPlaying = true; lastBeatSent = beat
                out.append(.musicStarted(beat))
            }
        }
        if musicPlaying, now - musicLastSeen >= EarsTuning.musicRelease {
            musicPlaying = false; musicOnSince = nil; lastBeatSent = nil
            out.append(.musicStopped)
        }
        if hearing != nil, now - hearingAt > EarsTuning.hearingHold { hearing = nil }
        return out
    }

    // MARK: internals

    private mutating func turnedOn(_ k: EarKind, _ f: EarsFrame, _ out: inout [EarEvent]) {
        let masked = f.time - appSoundAt <= EarsTuning.appSoundMask + 0.5          // a 0.5 s window may hold the app's own boop
        switch k {
        case .clap, .snap:
            guard !masked else { return }
            lastClapWindow = f.time
            // the DSP onsets inside this window are the claps; without onsets (classifier only) the window itself is one clap
            let mine = onsets.filter { $0.time > clapsAdopted && $0.time >= f.time - EarsTuning.clapOnsetLookback && $0.time <= f.time + 0.05 }
            if mine.isEmpty { addClap(f.time, &out) } else { for o in mine { addClap(o.time, &out) } }
            clapsAdopted = f.time
            see(k, f.time)
        case .loudBang:
            guard !masked else { return }
            if f.time - lastBang > EarsTuning.cooldown[.loudBang]! { lastBang = f.time; out.append(.bang(level: max(min(1, f.rms), 0.5))) }
            see(k, f.time)
        case .speech:
            see(k, f.time)
        case .music:
            break
        default:
            if k == .whistle, masked { return }
            if fire(k, at: f.time) { out.append(.heard(k)) }
            see(k, f.time)
        }
    }

    private mutating func addClap(_ t: Double, _ out: inout [EarEvent]) {
        if let last = claps.last, t - last < 0.08 { return }        // one clap, two detections
        claps.append(t)
        see(.clap, t)
        if claps.count >= 2 { out += advance(to: now) }
    }

    @discardableResult
    private mutating func fire(_ k: EarKind, at t: Double) -> Bool {
        if let l = lastFired[k], t - l < EarsTuning.cooldown[k]! { return false }
        lastFired[k] = t
        return true
    }

    private mutating func see(_ k: EarKind, _ t: Double) {
        // talking never pushes a fresher, more interesting kind off the button
        if k == .speech, let h = hearing, h != .speech, t - hearingAt <= EarsTuning.hearingHold { return }
        hearing = k; hearingAt = t
    }

    /// Tests: the learned app-music baseline.
    var appMusicBaselineValue: Float { appMusicBaseline }
}
