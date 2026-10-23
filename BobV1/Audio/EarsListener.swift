//
//  EarsListener.swift
//  "Ears on": the live microphone. OFF by default. While on and in the foreground the app listens continuously (one AVAudioEngine input tap);
//  in the background, or while the player holds to talk, the engine stops (the system's orange dot goes out). Mic permission is asked once, when
//  the switch is turned on. NOTHING IS RECORDED OR SENT: every buffer goes to the on-device SoundAnalysis classifier (SNAudioStreamAnalyzer,
//  built-in version 1) and to a few hundred bytes of signal processing (EarsDSP: onsets, level, tempo), then it is gone. Where SoundAnalysis
//  is not available the DSP alone feeds the detector (claps, bangs, music by its beat).
//
//  Threads: the tap hands buffers to one serial analysis queue (`EarsPipeline`: DSP + classifier + `EarsDetector`, all in STREAM time, seconds
//  since the engine started). Events are stamped into the host clock (`EarsClock`: CACurrentMediaTime = AVAudioTime host seconds) and dropped
//  into a locked outbox; the stage drains it once per fixed step (`Ears.tick`) and the reactor (BlobBrain+Ears.swift) does the rest on main.
//
//  AUDIO SESSION: `.playAndRecord` with `[.defaultToSpeaker, .mixWithOthers]` while on (the hub's `.ambient` cannot record); the hub keeps its
//  hands off the category while `earsSession` is up and puts `.ambient` back when Ears is switched off. The voice mic owns the session while
//  it runs: Ears pauses on `micSessionBegan` and resumes on `micSessionEnded`.
//
//  Inert under XCTest (and in `-EarsDemo` captures): no session, no engine; the switch, the HUD state and `inject` still work.
//

import Foundation
import AVFoundation
import SoundAnalysis
import Observation
import QuartzCore
import UIKit

// MARK: - clock

/// Stream seconds (the DSP / analyzer clock, 0 at engine start) <-> host seconds (CACurrentMediaTime). Noted on every buffer, so a dropped
/// buffer or a restart is absorbed at once; small jitter is smoothed.
nonisolated struct EarsClock: Equatable, Sendable {
    private(set) var offset: Double?
    var isSet: Bool { offset != nil }

    mutating func note(bufferHost: Double, streamStart: Double) {
        let o = bufferHost - streamStart
        if let old = offset, abs(o - old) < 0.05 { offset = old + (o - old) * 0.25 } else { offset = o }
    }
    func media(_ stream: Double) -> Double { stream + (offset ?? 0) }
    func stream(_ media: Double) -> Double { media - (offset ?? 0) }
    func media(_ b: EarBeat) -> EarBeat { var c = b; c.anchor = media(b.anchor); return c }
    func media(_ e: EarEvent) -> EarEvent {
        switch e {
        case .musicStarted(let b): return .musicStarted(b.map(media))
        case .musicBeat(let b): return .musicBeat(media(b))
        default: return e
        }
    }
}

// MARK: - pipeline (analysis queue)

/// Everything that touches audio data. Owned by `Ears`, used only on `queue` (plus the locked hand-offs).
nonisolated final class EarsPipeline: NSObject, @unchecked Sendable, SNResultsObserving {
    let queue = DispatchQueue(label: "io.mgsllc.BobV1.ears", qos: .userInitiated)
    let sampleRate: Double
    let dsp: EarsDSP
    private(set) var detector: EarsDetector
    private(set) var clock = EarsClock()
    private(set) var analyzer: SNAudioStreamAnalyzer?
    var usesClassifier: Bool { analyzer != nil }
    private var framePos: AVAudioFramePosition = 0
    private var latestRms: Float = 0
    private var samples: [Float] = []

    private let lock = NSLock()
    private var outbox: [EarEvent] = []
    private var appMusic: Float = 0
    private var hearing: EarKind?
    private var level: Float = 0
    private(set) var buffers = 0

    /// `classify`: try the built-in classifier (false = DSP-only, the fallback and the tests).
    init(format: AVAudioFormat, classify: Bool) {
        sampleRate = format.sampleRate
        dsp = EarsDSP(sampleRate: format.sampleRate)
        detector = EarsDetector(usesClassifier: false)
        super.init()
        if classify {
            let an = SNAudioStreamAnalyzer(format: format)
            if let req = try? SNClassifySoundRequest(classifierIdentifier: .version1) {
                req.windowDuration = CMTime(seconds: 0.5, preferredTimescale: 48_000)
                req.overlapFactor = 0.5
                if (try? an.add(req, withObserver: self)) != nil { analyzer = an; detector = EarsDetector(usesClassifier: true) }
            }
        }
        dsp.onOnset = { [unowned self] o in self.emit(self.detector.onset(o)) }
        dsp.onBeat = { [unowned self] b, t in self.emit(self.detector.beat(b, at: t)) }
        dsp.onFrame = { [unowned self] f in
            self.latestRms = f.rms
            self.publishLevel(f.rms)
            if !self.usesClassifier {
                var g = f; g.appMusic = self.readAppMusic()
                self.emit(self.detector.frame(g))
            } else {
                self.emit(self.detector.advance(to: f.time))
            }
        }
    }

    // MARK: audio in (analysis queue)

    func process(_ buffer: AVAudioPCMBuffer, hostTime: UInt64) {
        buffers += 1
        let n = Int(buffer.frameLength)
        guard n > 0, let ch = buffer.floatChannelData else { return }
        let streamStart = dsp.time
        if hostTime != 0 { clock.note(bufferHost: AVAudioTime.seconds(forHostTime: hostTime), streamStart: streamStart) }
        // mono: channel 0 (the phone mic is mono; a stereo accessory's left channel is plenty)
        if buffer.stride == 1 { dsp.feed(UnsafeBufferPointer(start: ch[0], count: n)) }
        else {
            if samples.count < n { samples = [Float](repeating: 0, count: n) }
            for i in 0..<n { samples[i] = ch[0][i * buffer.stride] }
            samples.withUnsafeBufferPointer { dsp.feed(UnsafeBufferPointer(start: $0.baseAddress, count: n)) }
        }
        if let analyzer { analyzer.analyze(buffer, atAudioFramePosition: framePos) }
        framePos += AVAudioFramePosition(n)
    }

    /// Test seam: PCM straight into the pipeline with a synthetic host clock.
    func feed(_ x: [Float], hostStart: Double) {
        clock.note(bufferHost: hostStart, streamStart: dsp.time)
        dsp.feed(x)
    }

    // MARK: classifier results (SoundAnalysis calls these on the analysis queue)

    func request(_ request: SNRequest, didProduce result: SNResult) {
        guard let r = result as? SNClassificationResult else { return }
        var f = EarsFrame(time: CMTimeGetSeconds(CMTimeRangeGetEnd(r.timeRange)))
        for c in r.classifications {
            guard let k = EarKind.kindOf[c.identifier] else { continue }
            f.scores[k] = max(f.scores[k] ?? 0, Float(c.confidence))
        }
        f.rms = latestRms
        f.appMusic = readAppMusic()
        emit(detector.frame(f))
    }
    func request(_ request: SNRequest, didFailWithError error: Error) { NSLog("[ears] classifier failed: \(error)") }
    func requestDidComplete(_ request: SNRequest) {}

    // MARK: hand-offs

    /// The app played a sound effect at host time `media`.
    func noteAppSound(at media: Double) { queue.async { [self] in detector.noteAppSound(at: clock.stream(media)) } }
    func setAppMusic(_ l: Float) { lock.lock(); appMusic = l; lock.unlock() }
    private func readAppMusic() -> Float { lock.lock(); defer { lock.unlock() }; return appMusic }
    private func publishLevel(_ rms: Float) {
        let db = 20 * log10(max(rms, 1e-6))
        let norm = max(0, min(1, (db + 50) / 40))
        lock.lock(); level = norm; hearing = detector.hearing; lock.unlock()
    }
    private func emit(_ events: [EarEvent]) {
        lock.lock(); defer { lock.unlock() }
        for e in events { outbox.append(clock.media(e)) }
        hearing = detector.hearing
        if outbox.count > 64 { outbox.removeFirst(outbox.count - 64) }
    }
    /// Main thread: the events since the last drain (host time), what is heard, the level.
    func drain() -> (events: [EarEvent], hearing: EarKind?, level: Float) {
        lock.lock(); defer { lock.unlock() }
        let out = outbox; outbox.removeAll(keepingCapacity: true)
        return (out, hearing, level)
    }
}

// MARK: - Ears (main)

@MainActor
@Observable
final class Ears {
    static let shared = Ears()

    enum Pause: Equatable, Sendable { case background, voice, interrupted }
    enum State: Equatable, Sendable {
        case off, starting, listening, paused(Pause), denied, unavailable
        var isOn: Bool { self != .off && self != .denied && self != .unavailable }
    }

    static let key = "Ears.on"

    private(set) var state: State = .off
    /// What the Jellies hear right now (the ear button's badge) and the mic level 0...1 (its halo).
    private(set) var hearing: EarKind?
    private(set) var level: Float = 0
    /// False once the engine runs on the DSP fallback (no SoundAnalysis).
    private(set) var usesClassifier = true
    /// The switch as saved. `state` is the truth about the engine.
    var isOn: Bool { defaults.bool(forKey: Self.key) }

    let reactor = EarsReactor()
    /// XCTest (or `-EarsDemo`): no session, no engine; everything else works.
    let inert: Bool
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var foreground = true
    @ObservationIgnored private var voiceHeld = false
    @ObservationIgnored private var engine: AVAudioEngine?
    @ObservationIgnored private var pipeline: EarsPipeline?
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    @ObservationIgnored private var sessionUp = false
    @ObservationIgnored private var jellies: [EarsReactor.Jelly] = []
    @ObservationIgnored private var injected: [EarEvent] = []
    @ObservationIgnored private var demoHearing: (EarKind, Double)?
    @ObservationIgnored private var hudClock = 0
    @ObservationIgnored private weak var care: GameCare?
    @ObservationIgnored private var starting = false
    @ObservationIgnored private(set) var log: [String] = []

    // injection seams
    @ObservationIgnored var requestPermission: () async -> Bool = { await AVAudioApplication.requestRecordPermission() }
    @ObservationIgnored var permissionGranted: () -> Bool = { AVAudioApplication.shared.recordPermission == .granted }
    @ObservationIgnored var permissionDenied: () -> Bool = { AVAudioApplication.shared.recordPermission == .denied }
    @ObservationIgnored var makeEngine: () -> AVAudioEngine = { AVAudioEngine() }
    @ObservationIgnored var classify = true
    /// Called when the session category is set (true) or Ears lets go of it (false): the hub.
    @ObservationIgnored var sessionHook: (Bool) -> Void = { on in if on { AudioHub.shared.earsSessionBegan() } else { AudioHub.shared.earsSessionEnded() } }
    @ObservationIgnored var danceHook: (Bool) -> Void = { AudioHub.shared.earsDancing($0) }

    init(defaults: UserDefaults = .standard, inert: Bool? = nil) {
        self.defaults = defaults
        let env = ProcessInfo.processInfo.environment
        self.inert = inert ?? (env["XCTestConfigurationFilePath"] != nil || defaults.string(forKey: "EarsDemo") != nil)
        reactor.onDance = { [weak self] on in self?.danceHook(on) }
        if self.inert, defaults.string(forKey: "EarsDemo") != nil { applyDemo(defaults.string(forKey: "EarsDemo") ?? "") }
    }
    nonisolated deinit {}

    // MARK: the switch

    /// The game screen appeared: pick up a saved ON (permission must still be granted).
    func launch(care: GameCare) {
        self.care = care
        reactor.comeHere = { [weak care] id in care?.comeHere(jelly: id) }
        reactor.comeEveryone = { [weak care] in care?.comeHereEveryone() }
        guard !inert else { return }
        if isOn {
            if permissionGranted() { start() } else { state = .denied }
        }
    }

    /// The Ears switch. Asks for the mic once (the first ON); a refusal shows the denied state and leaves the switch off.
    func setOn(_ on: Bool) {
        if !on {
            defaults.set(false, forKey: Self.key)
            stopEngine()
            if sessionUp { sessionUp = false; sessionHook(false) }
            reactor.reset(jellies)
            state = .off; hearing = nil; level = 0
            note("off")
            return
        }
        if inert { defaults.set(true, forKey: Self.key); if state == .off { state = .listening }; return }
        if permissionDenied() { state = .denied; note("denied"); return }
        guard !starting else { return }
        starting = true
        state = .starting
        Task { @MainActor [weak self] in
            guard let self else { return }
            let ok = await self.requestPermission()
            self.starting = false
            guard ok else { self.state = .denied; self.defaults.set(false, forKey: Self.key); self.note("permission refused"); return }
            self.defaults.set(true, forKey: Self.key)
            self.start()
        }
    }

    /// Tapped while denied: the Settings app.
    func openSettings() {
        if let u = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(u) }
    }

    // MARK: foreground / voice

    func setForeground(_ on: Bool) {
        guard on != foreground else { return }
        foreground = on
        guard !inert, isOn, state != .denied else { return }
        if on { start() } else { stopEngine(); reactor.reset(jellies); state = .paused(.background); hearing = nil; level = 0; note("background") }
    }

    /// The voice mic is up: Ears lets go of the input until `voiceResume`.
    func voicePause() {
        guard !voiceHeld else { return }
        voiceHeld = true
        guard !inert, isOn, state != .denied else { return }
        stopEngine()
        if state != .off { state = .paused(.voice) }
        hearing = nil; level = 0
        note("voice pause")
    }
    func voiceResume() {
        guard voiceHeld else { return }
        voiceHeld = false
        guard !inert, isOn, state != .denied, foreground else { return }
        start()
    }

    // MARK: engine

    private func start() {
        guard !inert, foreground, !voiceHeld, engine == nil, !starting else { return }
        starting = true
        state = .starting
        let mk = makeEngine, classify = classify
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let box = try await Task.detached { () -> EarsEngineBox in
                    try Self.activateSession()
                    let engine = mk()
                    let input = engine.inputNode
                    input.removeTap(onBus: 0)
                    let fmt = input.outputFormat(forBus: 0)
                    guard fmt.sampleRate > 0, fmt.channelCount > 0 else { throw EarsError.noInput }
                    let pipe = EarsPipeline(format: fmt, classify: classify)
                    input.installTap(onBus: 0, bufferSize: 2048, format: fmt) { buffer, when in
                        let host = when.isHostTimeValid ? when.hostTime : 0
                        pipe.queue.async { pipe.process(buffer, hostTime: host) }
                    }
                    engine.prepare()
                    try engine.start()
                    return EarsEngineBox(engine: engine, pipe: pipe)
                }.value
                self.starting = false
                // ON may have been switched off, or the app backgrounded, while the engine came up: let the session go again if it was OFF
                guard self.isOn, self.foreground, !self.voiceHeld else {
                    box.engine.inputNode.removeTap(onBus: 0); box.engine.stop()
                    if !self.isOn { if self.sessionUp { self.sessionUp = false }; self.sessionHook(false) }
                    return
                }
                if !self.sessionUp { self.sessionUp = true; self.sessionHook(true) }
                self.engine = box.engine
                self.pipeline = box.pipe
                self.usesClassifier = box.pipe.usesClassifier
                self.state = .listening
                self.observe(box.engine)
                self.note("listening (\(box.pipe.usesClassifier ? "classifier + dsp" : "dsp only"), \(Int(box.pipe.sampleRate)) Hz)")
            } catch {
                self.starting = false
                self.state = .unavailable
                self.note("engine start failed: \(error)")
            }
        }
    }

    nonisolated private static func activateSession() throws {
        let s = AVAudioSession.sharedInstance()
        let plan = SessionPolicy.plan(musicOn: true, otherAudioPlaying: false, micActive: true)
        try s.setCategory(plan.category, mode: .default, options: plan.options)
        try? s.setAllowHapticsAndSystemSoundsDuringRecording(true)
        try s.setActive(true)
    }

    private func stopEngine() {
        for o in observers { NotificationCenter.default.removeObserver(o) }
        observers.removeAll()
        guard let e = engine else { return }
        e.inputNode.removeTap(onBus: 0)
        e.stop()
        engine = nil
        pipeline = nil
    }

    private func observe(_ e: AVAudioEngine) {
        let nc = NotificationCenter.default
        observers.append(nc.addObserver(forName: .AVAudioEngineConfigurationChange, object: e, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in self?.restart(reason: "route / configuration change") }
        })
        observers.append(nc.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] n in
            let type = (n.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt).flatMap(AVAudioSession.InterruptionType.init)
            Task { @MainActor [weak self] in
                guard let self else { return }
                if type == .began { self.stopEngine(); self.state = .paused(.interrupted); self.note("interrupted") }
                else if type == .ended { self.restart(reason: "interruption ended") }
            }
        })
    }

    private func restart(reason: String) {
        guard isOn, state != .denied else { return }
        stopEngine()
        note("restart: \(reason)")
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 300_000_000)
            self?.start()
        }
    }

    // MARK: the stage's step

    /// Once per fixed sim step (MelonStage.hopTick): locks from the game, the detector's events into the reactor, the reactions' frame.
    func tick(actors: [JellyActor], care: GameCare, dt: Float) {
        refreshJellies(actors)
        reactor.update(care: care)
        let now = CACurrentMediaTime()
        var events = injected; injected.removeAll(keepingCapacity: true)
        if let p = pipeline {
            let d = p.drain()
            events += d.events
            hudClock += 1
            if hudClock % 6 == 0 {
                if hearing != d.hearing { hearing = d.hearing }
                if abs(level - d.level) > 0.02 { level = d.level }
            }
        } else if let (k, until) = demoHearing {
            if now >= until { demoHearing = nil; hearing = nil } else if hearing != k { hearing = k }
        }
        for e in events { reactor.handle(e, jellies: jellies, now: now); note("\(e)") }
        reactor.tick(jellies: jellies, dt: dt, now: now)
    }

    /// The reactor's view of the room, rebuilt only when an actor or a brain changes (no per-step array).
    private func refreshJellies(_ actors: [JellyActor]) {
        if jellies.count == actors.count {
            var same = true
            for (j, a) in zip(jellies, actors) where j.brain !== a.brain || j.sim !== a.sim { same = false; break }
            if same { return }
        }
        jellies = actors.compactMap { a in a.brain.map { EarsReactor.Jelly(id: a.id, brain: $0, sim: a.sim) } }
    }

    // MARK: hub hooks

    /// The app played one of its own effects now (its boops and thumps must not read as claps).
    func noteAppSound() { pipeline?.noteAppSound(at: CACurrentMediaTime()) }
    /// How loud the app's own music is on the speaker (0 = silent): the music exclusion.
    func speakerMusicLevel(_ l: Float) { pipeline?.setAppMusic(l) }

    // MARK: seams (tests, captures)

    /// An event as if the detector had heard it (host time = now).
    func inject(_ e: EarEvent) { injected.append(e) }
    /// The ear button shows this kind for `seconds`.
    func showHearing(_ k: EarKind, seconds: Double = 1.4) { demoHearing = (k, CACurrentMediaTime() + seconds) }
    func debugSetState(_ s: State) { state = s }

    /// `-EarsDemo off|on|hearing:<kind>|denied|paused|dance|clap|double|whistle|bark|laugh` (captures; see GameScreen.runDebugScript).
    private func applyDemo(_ spec: String) {
        let parts = spec.split(separator: ":").map(String.init)
        switch parts.first ?? "" {
        case "off": state = .off
        case "denied": state = .denied
        case "paused": state = .paused(.background)
        case "dsp": state = .listening; usesClassifier = false
        default: state = .listening
        }
    }

    private func note(_ s: String) { log.append(s); if log.count > 40 { log.removeFirst() } }
}

private enum EarsError: Error { case noInput }

/// Hands the freshly started engine back to the main actor.
private struct EarsEngineBox: @unchecked Sendable {
    let engine: AVAudioEngine
    let pipe: EarsPipeline
}
