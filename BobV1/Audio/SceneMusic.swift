//
//  SceneMusic.swift
//  The music of the screens (race, final stretch, shop, town) with sample-accurate loops.
//
//    SceneTrack      which file, its loop points in 44.1 kHz frames (from music_pick/picks.json; bar-aligned, on zero crossings) and (the intro is
//                    played once, then the loop).
//    MusicScene      what the screen wants; MusicDirector turns a change of scene into events.
//    SceneRender     decodes a track into an intro buffer and a LOOP buffer whose last ~15 ms are crossfaded with the audio just before the loop start,
//                    so scheduling the loop buffer with `.loops` is gapless and click free.
//    SceneMusicEngine  one AVAudioEngine with a player node per playing track; fades, volume and the song clock (the Jelly Show's beat grid reads it).
//
//  Only the tracks that are playing are held in memory (a float32 stereo track is ~20-30 MB; a crossfade between two tracks holds both for a second).
//

import Foundation
import AVFoundation

nonisolated enum SceneTrack: String, CaseIterable, Sendable {
    case circuitRace = "circuit_race_3", circuitFinal = "circuit_final_2", shop = "shop_2", town = "town_1"
    case studioPractice = "studio_practice_1", contestStage = "contest_stage_2"
    /// The Profile screen's own calm loop (2026-11-22; about 88 BPM, 60 s): the whole file loops like the park / café tracks. The Studio keeps studio_practice_1 (the dance drill's beat grid is tied to it).
    case profile1 = "profile_1"
    case park1 = "park_1", park2 = "park_2", cafe1 = "cafe_1", cafe2 = "cafe_2", volley1 = "volley_1", volley2 = "volley_2"      // 2026-10-24; loops = the whole file (past a 2000-frame lead-in), seam crossfaded

    /// The café playlist's other tracks (2026-11-03): the whole file loops like the others.
    case cafe3 = "cafe_3", cafe4 = "cafe_4", cafe5 = "cafe_5", cafe6 = "cafe_6", cafe7 = "cafe_7", cafe8 = "cafe_8"

    /// The park playlist's other tracks (2026-11-06): the whole file loops like the others.
    case park3 = "park_3", park4 = "park_4", park5 = "park_5", park6 = "park_6"

    /// The Jelly Show's dance songs (2026-11-08): played ONCE from their first frame (no loop, no intro split) under the dance round; Show/DanceSongs.swift has each song's measured beat grid.
    case dance1 = "show_dance_1", dance2 = "show_dance_2", dance3 = "show_dance_3", dance4 = "show_dance_4"
    static let danceSongs: [SceneTrack] = [.dance1, .dance2, .dance3, .dance4]
    /// Plays once from the first frame to the last (the song clock is the file's own).
    var playsOnce: Bool { Self.danceSongs.contains(self) }

    var loopStartFrame: Int {
        switch self {
        case .dance1, .dance2, .dance3, .dance4: return 0
        case .circuitRace: return 1_289_559
        case .circuitFinal: return 362_406
        case .shop: return 1_205_040
        case .town: return 655_869
        case .studioPractice: return 1_235_736
        case .contestStage: return 1_511_597
        case .park1, .park2, .park3, .park4, .park5, .park6, .cafe1, .cafe2, .cafe3, .cafe4, .cafe5, .cafe6, .cafe7, .cafe8, .volley1, .volley2, .profile1: return 2_000
        }
    }
    var loopEndFrame: Int {
        switch self {
        case .circuitRace: return 3_732_037
        case .circuitFinal: return 1_118_625
        case .shop: return 2_898_470
        case .town: return 3_075_098
        case .studioPractice: return 2_646_955
        case .contestStage: return 2_922_798
        case .park1, .park2: return 3_970_058
        case .park3: return 4_632_576
        case .park4: return 4_632_576
        case .park5: return 4_632_576
        case .park6: return 4_632_576
        case .cafe1, .cafe2: return 4_411_412
        case .cafe3, .cafe7: return 4_634_469
        case .cafe4, .cafe5: return 4_632_175
        case .cafe6, .cafe8: return 4_629_882
        case .volley1: return 3_308_105
        case .volley2: return 3_307_833
        case .profile1: return 2_647_058          // = the decoded length of profile_1.m4a (AVAudioFile.length), like the park / café tracks
        case .dance1, .dance2, .dance3, .dance4: return 0          // (plays once: the whole file, see SceneRender.render)
        }
    }
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
    case none, race, raceFinal, shop, town, results
    /// The Park visit and the café outing: one of two tracks each, picked per visit by the director (`tracks`).
    case park, cafe
    /// The beach volleyball court: one of two tracks per match.
    case volley
    /// The Jelly Show (Show/): the Studio and its dance drill play studio_practice_1, the stage plays contest_stage_2.
    case studio, show
    /// The Profile screen (BobV1/Show/ProfileScreen.swift): its own slower loop, profile_1.
    case profile
    /// The Jelly Show's dance round plays dance song `i` (0...3) once; the stage loop is out while it plays.
    case danceSong(Int)

    var track: SceneTrack? {
        switch self {
        case .race: return .circuitRace
        case .raceFinal: return .circuitFinal
        case .shop: return .shop
        case .town: return .town
        case .studio: return .studioPractice
        case .profile: return .profile1
        case .show: return .contestStage
        case .danceSong(let i): return SceneTrack.danceSongs[min(max(i, 0), SceneTrack.danceSongs.count - 1)]
        case .park: return .park1
        case .cafe: return .cafe1
        case .volley: return .volley1
        case .none, .results: return nil
        }
    }
    /// A playlist scene advances at the end of each track (shuffled, no repeat until the list is through) and has a Skip; the others loop one track.
    var isPlaylist: Bool { self == .cafe || self == .park }
    var isDanceSong: Bool { if case .danceSong = self { return true }; return false }
    /// The candidates for a visit (the director picks one at random); one entry for the other scenes.
    var tracks: [SceneTrack] {
        switch self {
        case .park: return ParkMusic.tracks.map(\.track)
        case .cafe: return CafeMusic.tracks.map(\.track)
        case .volley: return [.volley1, .volley2]
        default: return track.map { [$0] } ?? []
        }
    }
}

/// The café's playlist, data-driven: a file (a SceneTrack case; its loop points are in SceneTrack) and the title the Sound panel shows. New tracks are added here.
nonisolated enum CafeMusic {
    static let tracks: [(track: SceneTrack, title: String)] = [(.cafe1, "Morning Latte"), (.cafe2, "Rainy Window"), (.cafe3, "Window Seat"), (.cafe4, "Sunny Bossa"),
                                                                (.cafe5, "Dusty Rhodes"), (.cafe6, "Steamed Milk"), (.cafe7, "Late Library"), (.cafe8, "Golden Hour Café")]
    static func title(_ t: SceneTrack) -> String? { tracks.first { $0.track == t }?.title }
}

/// The park's playlist (2026-11-06), data-driven like the café's: a file (a SceneTrack case) and the title the Sound panel shows.
nonisolated enum ParkMusic {
    static let tracks: [(track: SceneTrack, title: String)] = [(.park1, "Sunny Lawn"), (.park2, "Picnic Hour"), (.park3, "Dandelion Drift"),
                                                                (.park4, "Duck Pond"), (.park5, "Swing Set Breeze"), (.park6, "Cloud Watching")]
    static func title(_ t: SceneTrack) -> String? { tracks.first { $0.track == t }?.title }
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
        if t.playsOnce {          // the whole file, scheduled once (its own faded ring-out is the ending); AVAudioFile drops the AAC priming, so frame 0 = the song's first sample
            guard file.length > 0, fmt.commonFormat == .pcmFormatFloat32, let all = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: AVAudioFrameCount(file.length)) else { return nil }
            do { try file.read(into: all) } catch { return nil }
            return Result(intro: nil, loop: all, format: fmt)
        }
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
        if s > 0, let ib = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: AVAudioFrameCount(s)) {
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

// MARK: - resuming a song

/// Where a once-only song (the Jelly Show's dance songs) picks up when its engine is rebuilt mid-song. The song "keeps running" on the wall clock while the
/// engine is down (or the phone is silenced), so a rebuild lands where the song has got to, never back at frame 0 (the dance's prompts are on the song's own beats).
nonisolated enum SongResume {
    /// The frame to start at after `elapsed` seconds of song, or nil when the song is over (less than `tail` seconds left).
    static func startFrame(elapsed: Double, lengthFrames: Int, sampleRate: Double, tail: Double = 0.5) -> Int? {
        if elapsed < 0.05 { return 0 }
        let f = Int(elapsed * sampleRate)
        return f >= lengthFrames - Int(tail * sampleRate) ? nil : f
    }
}

/// A scene voice whose engine would not start (the session was still held by someone else) tries again a few times, quickly, before it gives up.
nonisolated enum EngineStartRetry {
    static let maxAttempts = 8, delay = 0.25
    static func shouldRetry(attempt: Int) -> Bool { attempt < maxAttempts }
}

// MARK: - the engine

/// Plays scene tracks: intro (once) then the loop buffer (forever). Each play fades in; a stop fades out and frees the buffers.
@MainActor
final class SceneMusicEngine {
    private final class Voice {
        let node = AVAudioPlayerNode()
        let track: SceneTrack
        var fader = Fader()
        var fadeIn = 1.0
        var stopping = false
        var ready = false
        var started = false
        var cancelled = false
        var attempts = 0
        /// Song seconds already gone when this voice was asked for (a rebuild mid-song) and the song second its first frame is (set when it starts).
        var offset = 0.0
        var startSeconds = 0.0
        let born = CACurrentMediaTime()
        /// show-perfect-r1 (the music guard): when it started, and the player's sample position at the last health check (it must move).
        var readyAt = 0.0
        var lastSample: Int64?
        var lastSampleHost = 0.0
        init(track: SceneTrack) { self.track = track }
    }

    private let engine = AVAudioEngine()
    /// show-soak-r1 (dev probe, read-only): the engine is running.
    var engineRunning: Bool { engine.isRunning }
    private var voices: [Voice] = []
    private var level: Float = 1
    private var configObserver: NSObjectProtocol?
    /// The once-only song that is playing: the wall-clock time its frame 0 would have been (a rebuild carries on from `now - origin`).
    private var songOrigin: (track: SceneTrack, host: Double)?
    /// Always on (a handful of lines per track change, none per frame): the phone's console shows what the engine was asked and what it did.
    private func nlog(_ s: String) { NSLog("[audio] %@", s); JLog.audio(s) }

    /// `-AudioLog 1`: why a scene voice did not start, how long it took, and what dropped / replayed it (the Jelly Show's dance song fails silently otherwise).
    private func alog(_ s: @autoclosure () -> String) { if AudioHub.audioLog { NSLog("[audio] %@", s()) } }

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
    func play(_ t: SceneTrack, fade: Double, resumeAt: Double? = nil) {
        // a once-only song asked for again while it is still running (the hub found it lost) carries on where it has got to
        var offset = resumeAt ?? 0
        if resumeAt == nil, t.playsOnce, let o = songOrigin, o.track == t { offset = CACurrentMediaTime() - o.host }
        if songOrigin?.track != t { songOrigin = nil }
        nlog("scene ask \(t.rawValue) fade=\(String(format: "%.2f", fade)) resumeAt=\(String(format: "%.2f", offset)) engineRunning=\(engine.isRunning) voices=\(voices.count)")
        for v in voices where !v.stopping { v.stopping = true; v.fader.ramp(to: 0, over: fade) }
        // Each decoded track is a whole-loop PCM buffer (tens of MB). Rapid scene hopping used to stack one per hop while the old ones faded: keep the
        // newest fading voice plus the new one, free the older ones now.
        let fading = voices.filter { $0.stopping }
        if fading.count > 1 { for v in fading.dropLast() { drop(v) } }
        let v = Voice(track: t)
        v.offset = offset
        v.fadeIn = fade
        v.fader.snap(0); v.fader.ramp(to: 1, over: fade)
        voices.append(v)
        engine.attach(v.node)
        Task.detached(priority: .userInitiated) { [weak self] in
            let r = SceneRender.render(t)
            await self?.finishLoading(v, r)
        }
    }

    private func finishLoading(_ v: Voice, _ r: SceneRender.Result?) {
        guard var r, !v.cancelled, voices.contains(where: { $0 === v }) else {
            nlog("scene voice \(v.track.rawValue) NOT started: \(r == nil ? "decode failed" : "cancelled") (after \(Int((CACurrentMediaTime() - v.born) * 1000)) ms)")
            drop(v); return
        }
        // a rebuild mid-song: the song has been running since it was asked for, so start at its elapsed frame (nil = it is over)
        if v.track.playsOnce, v.offset > 0 {
            let elapsed = v.offset + (CACurrentMediaTime() - v.born)
            guard let f = SongResume.startFrame(elapsed: elapsed, lengthFrames: Int(r.loop.frameLength), sampleRate: r.format.sampleRate),
                  let tail = Self.tail(of: r.loop, from: f) else {
                nlog("scene voice \(v.track.rawValue) not restarted: the song is over (elapsed \(String(format: "%.1f", elapsed)) s)")
                songOrigin = nil; drop(v); return
            }
            r.loop = tail; v.startSeconds = Double(f) / r.format.sampleRate
        }
        engine.connect(v.node, to: engine.mainMixerNode, format: r.format)
        if !engine.isRunning {
            engine.prepare()
            do { try engine.start(); pausedByHub = false; JLog.audio("scene engine started for \(v.track.rawValue)") } catch {
                // the session can still be held by another app / mid route change: try again in a moment (keeps the decoded buffers), never drop the song at once
                nlog("scene voice \(v.track.rawValue) engine start failed (attempt \(v.attempts + 1)): \(error)")
                if EngineStartRetry.shouldRetry(attempt: v.attempts) {
                    v.attempts += 1
                    let keep = r
                    Task { @MainActor [weak self, weak v] in
                        try? await Task.sleep(for: .seconds(EngineStartRetry.delay))
                        guard let self, let v else { return }
                        self.finishLoading(v, keep)
                    }
                } else { drop(v) }
                return
            }
        }
        if let i = r.intro { v.node.scheduleBuffer(i, completionHandler: nil) }
        v.node.scheduleBuffer(r.loop, at: nil, options: v.track.playsOnce ? [] : .loops, completionHandler: nil)
        if !v.stopping { v.fader.snap(0); v.fader.ramp(to: 1, over: v.fadeIn) }          // decoding can outlast the fade: fade in from the moment it really starts (never a pop-in)
        v.node.volume = v.stopping ? v.fader.level * level * v.track.gain : 0
        v.node.play()
        v.ready = true; v.started = true; v.readyAt = CACurrentMediaTime(); v.lastSample = nil
        if v.track.playsOnce { songOrigin = (v.track, CACurrentMediaTime() - v.startSeconds) }
        nlog("scene voice \(v.track.rawValue) started after \(Int((CACurrentMediaTime() - v.born) * 1000)) ms: engineRunning=\(engine.isRunning) playing=\(v.node.isPlaying) nodeVolume=\(String(format: "%.2f", v.node.volume)) masterLevel=\(String(format: "%.2f", level)) fromSong=\(String(format: "%.1f", v.startSeconds)) s")
    }

    /// The buffer from `frame` to its end (a copy), nil when nothing is left or the copy cannot be made.
    private static func tail(of b: AVAudioPCMBuffer, from frame: Int) -> AVAudioPCMBuffer? {
        if frame == 0 { return b }
        let n = Int(b.frameLength) - frame
        guard n > 0, let out = AVAudioPCMBuffer(pcmFormat: b.format, frameCapacity: AVAudioFrameCount(n)),
              let src = b.floatChannelData, let dst = out.floatChannelData else { return nil }
        for c in 0..<Int(b.format.channelCount) { dst[c].update(from: src[c] + frame, count: n) }
        out.frameLength = AVAudioFrameCount(n)
        return out
    }

    func stopAll(fade: Double) {
        nlog("scene stopAll fade=\(String(format: "%.2f", fade)) voices=\(voices.map(\.track.rawValue))")
        songOrigin = nil
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
        if voices.isEmpty, engine.isRunning { engine.stop(); JLog.audio("scene engine stopped (no voices)") }
    }

    private func drop(_ v: Voice) {
        alog("scene drop \(v.track.rawValue) ready=\(v.ready ? 1 : 0) stopping=\(v.stopping ? 1 : 0)")
        v.cancelled = true
        if v.node.engine != nil { v.node.stop(); engine.detach(v.node) }
        voices.removeAll { $0 === v }
    }

    /// Memory warning: free every voice that is already fading out (the playing track stays).
    func trim() { for v in voices where v.stopping { drop(v) } }

    /// show-perfect-r1: the hub paused the engine itself (the app went to the background): its voices keep their scheduled audio, so a resume just starts them again. An engine that is found
    /// stopped WITHOUT this (a route change, an interruption, a media services reset) may have lost what its nodes had scheduled, so it is never resumed: the voice is rebuilt.
    private var pausedByHub = false
    func pause() { JLog.audio("scene pause"); pausedByHub = true; for v in voices where v.ready { v.node.pause() }; if engine.isRunning { engine.pause() } }
    func resume() {
        guard !voices.isEmpty else { pausedByHub = false; return }
        JLog.audio("scene resume engineRunning=\(engine.isRunning) pausedByHub=\(pausedByHub)")
        let paused = pausedByHub; pausedByHub = false
        if !engine.isRunning {
            if !paused { restartAfterConfigChange(); return }
            do { try engine.start() } catch { restartAfterConfigChange(); return }
        }
        for v in voices where v.ready { v.node.play() }
    }
    /// Everything stops and the engine is let go (the hub drops the whole engine after a media services reset, or when restarts keep failing, and makes a new one).
    func shutdown() {
        JLog.audio("scene engine shutdown")
        if let o = configObserver { NotificationCenter.default.removeObserver(o); configObserver = nil }
        for v in voices { v.cancelled = true; if v.node.engine != nil { v.node.stop(); engine.detach(v.node) } }
        voices.removeAll()
        if engine.isRunning { engine.stop() }
    }
    /// Test hook: the loudest sample on the mixer over `seconds` (the proof that a recovered voice is really AUDIBLE, not just flagged as playing).
    func _peak(over seconds: Double) async -> Float {
        guard engine.isRunning else { return 0 }
        let box = PeakBox()
        let mixer = engine.mainMixerNode
        mixer.installTap(onBus: 0, bufferSize: 2048, format: nil) { buf, _ in
            guard let d = buf.floatChannelData else { return }
            var m: Float = 0
            for c in 0..<Int(buf.format.channelCount) { for i in 0..<Int(buf.frameLength) { m = max(m, abs(d[c][i])) } }
            box.add(m)
        }
        try? await Task.sleep(for: .seconds(seconds))
        mixer.removeTap(onBus: 0)
        return box.value
    }
    private final class PeakBox: @unchecked Sendable {
        private let lock = NSLock(); private var m: Float = 0
        func add(_ x: Float) { lock.lock(); m = max(m, x); lock.unlock() }
        var value: Float { lock.lock(); defer { lock.unlock() }; return m }
    }

    /// show-perfect-r1 (the music guard): what the scene voice for `t` is really doing. `.loading`: asked for, decoding or just started (the render clock has not begun: give it a moment).
    /// `.stalled(why)`: the engine is not running, the node is not playing, or its render clock has stood still since the last check (a stopped engine can leave `isPlaying` true).
    enum Health: Equatable { case absent, loading, healthy, stalled(String) }
    func health(of t: SceneTrack) -> Health {
        guard let v = voices.last(where: { $0.track == t && !$0.stopping }) else { return .absent }
        let now = CACurrentMediaTime()
        guard v.ready, v.started else { return now - v.born > 6 ? .stalled("voice never became ready after \(Int(now - v.born)) s") : .loading }
        if !engine.isRunning { return pausedByHub ? .loading : .stalled("engine not running") }
        if !v.node.isPlaying { return .stalled("node not playing") }
        if now - v.readyAt < 0.4 { return .healthy }          // (just started: engine running + node playing is all that can be asked yet)
        guard let nt = v.node.lastRenderTime, nt.isSampleTimeValid, let pt = v.node.playerTime(forNodeTime: nt) else { return .stalled("no render time") }
        let sample = Int64(pt.sampleTime)
        if let last = v.lastSample, last == sample {          // (lastSampleHost = when the position last MOVED)
            return now - v.lastSampleHost >= 0.9 ? .stalled("render clock stuck at sample \(sample)") : .healthy
        }
        v.lastSample = sample; v.lastSampleHost = now
        return .healthy
    }
    /// Rebuilds the voice for the guard: the engine is stopped first, so a half-dead engine starts clean; a once-only song carries on where it has got to.
    func rebuild(reason: String) {
        nlog("scene rebuild: \(reason)")
        if engine.isRunning { engine.stop() }
        restartAfterConfigChange()
    }
    /// Test hooks (the fault injection): the engine stops under the voice, as a route change / media services reset does.
    func _injectEngineStop() { engine.stop() }
    var _voiceCount: Int { voices.count }

    /// A voice is decoded but not playing (the engine stopped under it): rebuild.
    func recoverIfStalled() {
        if voices.contains(where: { $0.ready && !$0.stopping && !$0.node.isPlaying }) { restartAfterConfigChange() }
    }

    /// Rebuilds the playing track on a fresh start of the engine (config change: route change, interruption end). Internal for tests.
    var traceEngineID: ObjectIdentifier { ObjectIdentifier(engine) }
    func restartAfterConfigChange() {
        guard let t = current else { return }
        MicTrace.record("sceneRestart", t.rawValue)
        // a once-only song carries on where it has got to (wall clock since its first frame); a loop restarts (its position does not matter)
        var resume: Double?
        if t.playsOnce, let o = songOrigin, o.track == t { resume = max(CACurrentMediaTime() - o.host, 0.0001) }
        nlog("scene engine config change / rebuild: \(t.rawValue) engineRunning=\(engine.isRunning) resumeAt=\(resume.map { String(format: "%.2f", $0) } ?? "0")")
        let fade = 0.3
        for v in voices { v.cancelled = true; if v.node.engine != nil { v.node.stop(); engine.detach(v.node) } }
        voices.removeAll()
        play(t, fade: fade, resumeAt: resume)
    }

    /// Seconds of SONG time of the newest playing track, as heard (output latency taken off): the file's own clock for a track that plays from its
    /// start. It keeps counting past the loop (the loop is a whole number of beats).
    func songTime(of t: SceneTrack) -> Double? {
        guard let v = voices.last(where: { $0.track == t && !$0.stopping && $0.ready && $0.started }),
              let nt = v.node.lastRenderTime, nt.isSampleTimeValid, let pt = v.node.playerTime(forNodeTime: nt) else { return nil }
        // the player's own sample position at the last render, plus the time since that render (the reading is up to one IO buffer old; capped, never negative), minus the route's output latency (Bluetooth)
        var stale = 0.0
        if nt.isHostTimeValid { stale = min(max(AVAudioTime.seconds(forHostTime: mach_absolute_time()) - AVAudioTime.seconds(forHostTime: nt.hostTime), 0), 0.05) }
        let played = v.startSeconds + Double(pt.sampleTime) / pt.sampleRate + stale - AVAudioSession.sharedInstance().outputLatency
        return played
    }

    /// Why `songTime(of:)` is nil right now (empty when it is not). Built only when asked for (the diagnostics), never on the per-frame read.
    func songTimeWhy(of t: SceneTrack) -> String {
        guard let v = voices.last(where: { $0.track == t && !$0.stopping && $0.ready && $0.started }) else {
            let any = voices.last(where: { $0.track == t })
            return any == nil ? "no scene voice for \(t.rawValue)" : any!.stopping ? "voice stopping" : "voice not ready (decoding or start failed)"
        }
        guard let nt = v.node.lastRenderTime else { return "voice has not rendered yet (lastRenderTime nil\(engine.isRunning ? "" : ", engine not running")\(v.node.isPlaying ? "" : ", node not playing"))" }
        guard nt.isSampleTimeValid else { return "render sample time invalid" }
        guard v.node.playerTime(forNodeTime: nt) != nil else { return "player time nil" }
        return ""
    }
}
