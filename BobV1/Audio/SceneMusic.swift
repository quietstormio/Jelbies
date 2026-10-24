//
//  SceneMusic.swift
//  The music of the screens (race, final stretch, training, shop, town) with sample-accurate loops.
//
//    SceneTrack      which file, its loop points in 44.1 kHz frames (from music_pick/picks.json; bar-aligned, on zero crossings) and whether it starts
//                    at the loop (training does: its beat grid is the loop's).
//    MusicScene      what the screen wants; MusicDirector turns a change of scene into events.
//    SceneRender     decodes a track into an intro buffer and a LOOP buffer whose last ~15 ms are crossfaded with the audio just before the loop start,
//                    so scheduling the loop buffer with `.loops` is gapless and click free.
//    SceneMusicEngine  one AVAudioEngine with a player node per playing track; fades, volume and the song clock (the drill's beat grid reads it).
//
//  Only the tracks that are playing are held in memory (a float32 stereo track is ~20-30 MB; a crossfade between two tracks holds both for a second).
//

import Foundation
import AVFoundation

nonisolated enum SceneTrack: String, CaseIterable, Sendable {
    case circuitRace = "circuit_race_3", circuitFinal = "circuit_final_2", training = "training_1", shop = "shop_2", town = "town_1"
    case studioPractice = "studio_practice_1", contestStage = "contest_stage_2"
    case park1 = "park_1", park2 = "park_2", cafe1 = "cafe_1", cafe2 = "cafe_2"      // 2026-10-24; loops = the whole file (past a 2000-frame lead-in), seam crossfaded

    var loopStartFrame: Int {
        switch self {
        case .circuitRace: return 1_289_559
        case .circuitFinal: return 362_406
        case .training: return TrainingTuning.loopStartFrame
        case .shop: return 1_205_040
        case .town: return 655_869
        case .studioPractice: return 1_235_736
        case .contestStage: return 1_511_597
        case .park1, .park2, .cafe1, .cafe2: return 2_000
        }
    }
    var loopEndFrame: Int {
        switch self {
        case .circuitRace: return 3_732_037
        case .circuitFinal: return 1_118_625
        case .training: return TrainingTuning.loopEndFrame
        case .shop: return 2_898_470
        case .town: return 3_075_098
        case .studioPractice: return 2_646_955
        case .contestStage: return 2_922_798
        case .park1, .park2: return 3_970_058
        case .cafe1, .cafe2: return 4_411_412
        }
    }
    /// Starts at the loop start (the intro is skipped): the training drill's beat grid is the loop's, and the drill waits for nothing.
    var skipsIntro: Bool { self == .training }
    static let sampleRate = 44100.0
    var loopStart: Double { Double(loopStartFrame) / Self.sampleRate }
    var loopEnd: Double { Double(loopEndFrame) / Self.sampleRate }
    /// Loudness trim in the mix.
    var gain: Float { 1 }
}

/// A one-shot result jingle, trimmed to `trim` seconds with a short fade at its end.
nonisolated enum Jingle: String, Sendable {
    case win = "results_win_2", lose = "results_lose_2"
    var trim: Double { self == .win ? 6.0 : 5.0 }
}

/// What a screen wants to hear (the director picks the files). `results` = the screen's music stops (a jingle plays) and the room music stays out.
nonisolated enum MusicScene: Equatable, Sendable {
    case none, race, raceFinal, training, shop, town, results
    /// The Park visit and the café outing: one of two tracks each, picked per visit by the director (`tracks`).
    case park, cafe
    /// The Jelly Show (Show/): the Studio and its dance drill play studio_practice_1, the stage plays contest_stage_2.
    case studio, show

    var track: SceneTrack? {
        switch self {
        case .race: return .circuitRace
        case .raceFinal: return .circuitFinal
        case .training: return .training
        case .shop: return .shop
        case .town: return .town
        case .studio: return .studioPractice
        case .show: return .contestStage
        case .park: return .park1
        case .cafe: return .cafe1
        case .none, .results: return nil
        }
    }
    /// The candidates for a visit (the director picks one at random); one entry for the other scenes.
    var tracks: [SceneTrack] {
        switch self {
        case .park: return [.park1, .park2]
        case .cafe: return [.cafe1, .cafe2]
        default: return track.map { [$0] } ?? []
        }
    }
}

// MARK: - decoding

nonisolated enum SceneRender {
    /// Crossfade at the loop seam (frames at 44.1 kHz): 15 ms.
    static let crossfadeFrames = 661

    struct Result: @unchecked Sendable {
        var intro: AVAudioPCMBuffer?
        var loop: AVAudioPCMBuffer
        var format: AVAudioFormat
    }

    static func url(_ t: SceneTrack, bundle: Bundle = .main) -> URL? { bundle.url(forResource: t.rawValue, withExtension: "m4a") }

    /// Frames in the file (nil = no file).
    static func fileLength(_ t: SceneTrack, bundle: Bundle = .main) -> Int? {
        guard let u = url(t, bundle: bundle), let f = try? AVAudioFile(forReading: u) else { return nil }
        return Int(f.length)
    }

    static func render(_ t: SceneTrack, bundle: Bundle = .main) -> Result? {
        guard let u = url(t, bundle: bundle),
              let file = try? AVAudioFile(forReading: u, commonFormat: .pcmFormatFloat32, interleaved: false) else { return nil }
        let fmt = file.processingFormat
        let s = t.loopStartFrame, e = t.loopEndFrame, n = e - s, x = crossfadeFrames
        guard e <= Int(file.length), s >= x, n > 2 * x, fmt.channelCount >= 1, fmt.commonFormat == .pcmFormatFloat32,
              let pre = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: AVAudioFrameCount(x)),
              let loop = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: AVAudioFrameCount(n)) else { return nil }
        do {
            file.framePosition = AVAudioFramePosition(s - x)
            try file.read(into: pre, frameCount: AVAudioFrameCount(x))
            try file.read(into: loop, frameCount: AVAudioFrameCount(n))      // continues at the loop start
        } catch { return nil }
        // the last x frames of the loop fade into the x frames BEFORE the loop start, so the seam continues the music as it was
        crossfadeTail(loop: loop, pre: pre, x: x)
        var intro: AVAudioPCMBuffer?
        if !t.skipsIntro, s > 0, let ib = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: AVAudioFrameCount(s)) {
            file.framePosition = 0
            do { try file.read(into: ib, frameCount: AVAudioFrameCount(s)); intro = ib } catch { return nil }
        }
        return Result(intro: intro, loop: loop, format: fmt)
    }

    /// loop[n-x+i] = loop[n-x+i] * (1-a) + pre[i] * a, a rising 0 -> 1 (pre[i] is the audio at frame loopStart - x + i).
    static func crossfadeTail(loop: AVAudioPCMBuffer, pre: AVAudioPCMBuffer, x: Int) {
        guard let ld = loop.floatChannelData, let pd = pre.floatChannelData else { return }
        let n = Int(loop.frameLength)
        for c in 0..<Int(loop.format.channelCount) {
            for i in 0..<x {
                let a = Float(i + 1) / Float(x)
                ld[c][n - x + i] = ld[c][n - x + i] * (1 - a) + pd[c][i] * a
            }
        }
    }
}

// MARK: - the engine

/// Plays scene tracks: intro (once) then the loop buffer (forever). Each play fades in; a stop fades out and frees the buffers.
@MainActor
final class SceneMusicEngine {
    private final class Voice {
        let node = AVAudioPlayerNode()
        let track: SceneTrack
        var fader = Fader()
        var stopping = false
        var ready = false
        var started = false
        var cancelled = false
        init(track: SceneTrack) { self.track = track }
    }

    private let engine = AVAudioEngine()
    private var voices: [Voice] = []
    private var level: Float = 1
    private var configObserver: NSObjectProtocol?

    init() {
        configObserver = NotificationCenter.default.addObserver(forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.restartAfterConfigChange() }
        }
    }
    nonisolated deinit {}

    var current: SceneTrack? { voices.last(where: { !$0.stopping })?.track }
    /// The loudest playing voice's volume now (Ears: how much of the app's own music is on the speaker).
    var loudest: Float { voices.filter { $0.started && $0.node.isPlaying }.map { $0.node.volume }.max() ?? 0 }
    /// A voice is decoded and playing.
    func isPlaying(_ t: SceneTrack) -> Bool { voices.contains { $0.track == t && !$0.stopping && $0.ready && $0.node.isPlaying } }

    /// Starts `t` (fading in over `fade` s) and fades every other voice out. Decoding happens off the main thread; the voice starts when it is ready.
    func play(_ t: SceneTrack, fade: Double) {
        for v in voices where !v.stopping { v.stopping = true; v.fader.ramp(to: 0, over: fade) }
        let v = Voice(track: t)
        v.fader.snap(0); v.fader.ramp(to: 1, over: fade)
        voices.append(v)
        engine.attach(v.node)
        Task.detached(priority: .userInitiated) { [weak self] in
            let r = SceneRender.render(t)
            await self?.finishLoading(v, r)
        }
    }

    private func finishLoading(_ v: Voice, _ r: SceneRender.Result?) {
        guard let r, !v.cancelled, voices.contains(where: { $0 === v }) else { drop(v); return }
        engine.connect(v.node, to: engine.mainMixerNode, format: r.format)
        if !engine.isRunning { engine.prepare(); do { try engine.start() } catch { drop(v); return } }
        if let i = r.intro { v.node.scheduleBuffer(i, completionHandler: nil) }
        v.node.scheduleBuffer(r.loop, at: nil, options: .loops, completionHandler: nil)
        v.node.volume = v.fader.level * level * v.track.gain
        v.node.play()
        v.ready = true; v.started = true
    }

    func stopAll(fade: Double) {
        for v in voices where !v.stopping { v.stopping = true; v.fader.ramp(to: 0, over: fade) }
    }

    /// Master level (music setting x duck x mix).
    func setLevel(_ l: Float) {
        level = l
        for v in voices { v.node.volume = v.fader.level * level * v.track.gain }
    }

    func update(dt: Double) {
        for v in voices {
            v.fader.update(dt: dt)
            v.node.volume = v.fader.level * level * v.track.gain
        }
        for v in voices where v.stopping && v.fader.level <= 0.0001 { drop(v) }
        if voices.isEmpty, engine.isRunning { engine.stop() }
    }

    private func drop(_ v: Voice) {
        v.cancelled = true
        if v.node.engine != nil { v.node.stop(); engine.detach(v.node) }
        voices.removeAll { $0 === v }
    }

    func pause() { for v in voices where v.ready { v.node.pause() }; if engine.isRunning { engine.pause() } }
    func resume() {
        guard !voices.isEmpty else { return }
        if !engine.isRunning {
            do { try engine.start() } catch { restartAfterConfigChange(); return }
        }
        for v in voices where v.ready { v.node.play() }
    }

    /// A voice is decoded but not playing (the engine stopped under it): rebuild.
    func recoverIfStalled() {
        if voices.contains(where: { $0.ready && !$0.stopping && !$0.node.isPlaying }) { restartAfterConfigChange() }
    }

    /// Rebuilds the playing track on a fresh start of the engine (config change: route change, interruption end). Internal for tests.
    func restartAfterConfigChange() {
        guard let t = current else { return }
        let fade = 0.3
        for v in voices { v.cancelled = true; if v.node.engine != nil { v.node.stop(); engine.detach(v.node) } }
        voices.removeAll()
        play(t, fade: fade)
    }

    /// Seconds of SONG time of the newest playing track, as heard (output latency taken off): the file's own clock for a track that plays from its
    /// start, the loop start + the time played for a track that skips its intro. It keeps counting past the loop (the loop is a whole number of beats).
    func songTime(of t: SceneTrack) -> Double? {
        guard let v = voices.last(where: { $0.track == t && !$0.stopping && $0.ready && $0.started }),
              let nt = v.node.lastRenderTime, nt.isSampleTimeValid, let pt = v.node.playerTime(forNodeTime: nt) else { return nil }
        let played = Double(pt.sampleTime) / pt.sampleRate - AVAudioSession.sharedInstance().outputLatency
        return (t.skipsIntro ? t.loopStart : 0) + played
    }
}
