//
//  AudioHub.swift
//  The game's sound: music (director-driven playlist, crossfades, gaps, play layer), the room ambience bed and the effects.
//
//  AUDIO SESSION OWNER: this hub. Its base category is `.ambient` (respects the silent switch, mixes with other apps' audio). The voice mic
//  (Voice/SpeechInput.swift) still needs `.playAndRecord`; it switches the category while its engine runs and tells the hub through
//  `micSessionBegan()` / `micSessionEnded()`. While the mic's session is up the hub never touches the category; when it ends the hub puts
//  `.ambient` back (instead of the old `setActive(false)`). While Bob LISTENS (voice.mode onOpen/onClose -> `micListening`) music, ambience and
//  effects duck to silence (DuckState) and come back after a short settle, so the speaker cannot leak into dictation.
//
//  Everything is AVAudioPlayer based (music/ambience stream, effects are tiny pooled players, per-effect rate limits, no immediate variant
//  repeat, optional pan by the Jelly's screen x). Muted (`-Mute 1`, or the XCTest host) the hub creates nothing and every call returns at once.
//

import Foundation
import AVFoundation
import Observation
import QuartzCore

@MainActor
@Observable
final class AudioHub {
    static let shared = AudioHub()

    var settings: AudioSettings { didSet { if settings != oldValue { settings.save(to: defaults); applyLevels() } } }
    /// `-Mute 1` or running under XCTest: no session, no players.
    let muted: Bool

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var duck = DuckState()
    @ObservationIgnored private var director: MusicDirector
    @ObservationIgnored private var input = MusicInput()
    @ObservationIgnored private var picker = VariantPicker()
    @ObservationIgnored private var started = false
    @ObservationIgnored private var active = true                // foreground
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var lastTick = CACurrentMediaTime()
    @ObservationIgnored private var micSession = false
    @ObservationIgnored private var verifyTask: Task<Void, Never>?
    // music
    private struct Deck { var player: AVAudioPlayer; var fader = Fader(); var track: MusicTrack }
    @ObservationIgnored private var decks: [Deck] = []
    @ObservationIgnored private var scene: SceneMusicEngine?
    /// What the screens want: the race / drill (from the stage) wins over the town / shop (from the game screen).
    @ObservationIgnored private var raceScene: MusicScene = .none
    @ObservationIgnored private var townScene: MusicScene = .none
    @ObservationIgnored private var jingle: AVAudioPlayer?
    @ObservationIgnored private var layer: (player: AVAudioPlayer, fader: Fader)?
    @ObservationIgnored private var ambDay: (player: AVAudioPlayer, fader: Fader)?
    @ObservationIgnored private var ambEve: (player: AVAudioPlayer, fader: Fader)?
    @ObservationIgnored private var lengths: [MusicTrack: Double] = [:]
    // effects
    @ObservationIgnored private var pool: [String: [AVAudioPlayer]] = [:]
    @ObservationIgnored private var variantCount: [String: Int] = [:]
    @ObservationIgnored private var lastPlay: [String: Double] = [:]
    @ObservationIgnored private var lastFoot: [Double] = [0, 0, 0]
    @ObservationIgnored private var snores = SnoreScheduler()
    /// Called for the Jelly that snores now (the sleep z's ride it).
    @ObservationIgnored var onSnore: ((Int) -> Void)?
    @ObservationIgnored private var lastVoice: [Double] = [0, 0, 0]
    @ObservationIgnored private var lastMood: [Int: BlobMood] = [:]
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    /// The most recent music events (tests / the debug log).
    @ObservationIgnored private(set) var eventLog: [MusicEvent] = []

    init(defaults: UserDefaults = .standard, muted: Bool? = nil) {
        self.defaults = defaults
        let d = defaults
        self.muted = muted ?? (d.integer(forKey: "Mute") != 0 || ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil)
        settings = AudioSettings(defaults: d)
        director = MusicDirector()
        director.length = { [unowned self] t in self.trackLength(t) }
    }
    nonisolated deinit {}

    // MARK: lifecycle

    /// Start the session, the music and the 30 Hz mixer. Call once when the game screen appears.
    func start() {
        guard !muted, !started else { return }
        started = true
        setUpSession()
        ambDay = loopPlayer("day_room"); ambEve = loopPlayer("evening_room")
        ambDay?.player.play(); ambEve?.player.play()
        let nc = NotificationCenter.default
        observers.append(nc.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] n in
            let type = (n.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt).flatMap(AVAudioSession.InterruptionType.init)
            Task { @MainActor in if type == .ended { self?.resumeAfterInterruption(verify: true) } }
        })
        observers.append(nc.addObserver(forName: AVAudioSession.mediaServicesWereResetNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.resumeAfterInterruption(verify: true) }
        })
        lastTick = CACurrentMediaTime()
        let t = Timer(timeInterval: 1.0 / 30, repeats: true) { [weak self] _ in Task { @MainActor in self?.tick() } }
        RunLoop.main.add(t, forMode: .common)
        timer = t
        preloadEffects()
    }

    private func setUpSession() {
        guard !micSession else { return }
        let s = AVAudioSession.sharedInstance()
        try? s.setCategory(.ambient, mode: .default, options: [])
        try? s.setActive(true)
    }

    private func resumeAfterInterruption(verify: Bool = false) {
        guard started, active else { return }
        if !micSession { setUpSession() }
        for d in decks { d.player.play() }
        layer?.player.play(); ambDay?.player.play(); ambEve?.player.play()
        scene?.resume()
        ensureMusic(delay: false)
        if verify { verifyTask?.cancel(); verifyTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            if !Task.isCancelled { self?.ensureMusic(delay: true) }
        } }
    }

    /// True when a main deck that should be audible is really playing.
    private var deckPlaying: Bool { decks.contains { $0.fader.target > 0 && $0.player.isPlaying } }

    /// After a resume: start the next room track when the director is in a gap or nothing plays (1.5 s fade-in), and bring a scene's music back
    /// if its engine lost it. `delay`: the 0.5 s re-check (also rebuilds a scene whose engine is not running).
    func ensureMusic(delay: Bool) {
        guard started, active else { return }
        perform(director.resumed(deckPlaying: deckPlaying, fade: 1.5))
        if let t = director.scene.track, !(scene?.isPlaying(t) ?? false) {
            if scene?.current != t { perform([.sceneOn(t, fade: 1.5)]) }          // lost (or never started)
            else if delay { scene?.recoverIfStalled() }                             // decoded but its node stopped
        }
    }

    /// Test seams.
    /// Tests on a host without audio output (the simulator) must not start an AVAudioEngine: the scene request is logged only.
    @ObservationIgnored var _sceneEngineDisabled = false
    var _decksPlaying: Bool { deckPlaying }
    var _directorScene: MusicScene { director.scene }
    func _forceGap(_ s: Double) { director.forceGap(s) }
    var _inGap: Bool { director.gapLeft != nil }
    var _micSession: Bool { micSession }
    var _sceneEngine: SceneMusicEngine? { scene }
    func _tick(_ dt: Double) { _ = dt; tick() }

    /// Foreground / background (scenePhase).
    func setForeground(_ on: Bool) {
        guard started, on != active else { return }
        active = on
        if on {
            lastTick = CACurrentMediaTime()
            resumeAfterInterruption(verify: true)
        } else {
            verifyTask?.cancel()
            micSession = false          // the mic engine died with the background; a stale flag would skip setUpSession on return
            for d in decks { d.player.pause() }
            layer?.player.pause(); ambDay?.player.pause(); ambEve?.player.pause()
            scene?.pause(); jingle?.pause()
            for ps in pool.values { for p in ps where p.isPlaying { p.stop() } }
        }
    }

    // MARK: mic (single session owner)

    /// SpeechInput brought its `.playAndRecord` session up: hands off.
    func micSessionBegan() { micSession = true }
    /// SpeechInput's engine is down: put the ambient session back. Returns false when the hub is not running (the caller then deactivates as before).
    @discardableResult
    func micSessionEnded() -> Bool {
        micSession = false
        guard started else { return false }
        setUpSession()
        return true
    }
    /// Bob starts / stops listening: everything ducks to silence and returns after a short settle.
    func micListening(_ on: Bool) {
        if on { duck.micOpened() } else { duck.micClosed() }
    }
    var isDucked: Bool { duck.isDucked || duck.listening }

    /// Music is on and audible (the Jellies sway to it).
    var musicAudible: Bool { started && !muted && settings.musicLevel > 0.05 }

    // MARK: situation (from the stage, once per sim step; cheap)

    /// `napping[i]`: Jelly i is settled in a night nap. `playing`: any Jelly zooms / plays (with each other or a toy). `xs`: their floor x (pan).
    func situation(napping: [Bool], playing: Bool, xs: [Float], moods: [BlobMood], scene: MusicScene = .none) {
        guard !muted, started else { return }
        input.allNapping = !napping.isEmpty && !napping.contains(false)
        input.playing = playing
        raceScene = scene
        input.scene = scene != .none ? scene : townScene
        let now = CACurrentMediaTime()
        for i in snores.due(napping: napping, now: now, random: { Double.random(in: $0) }) {
            play(.snore, jelly: i, x: i < xs.count ? xs[i] : 0)
            onSnore?(i)
        }
        for i in moods.indices {
            if let old = lastMood[i], old != moods[i] {
                if moods[i] == .happy { chirp(jelly: i, .happy, x: i < xs.count ? xs[i] : 0) }
                else if moods[i] == .grumpy { chirp(jelly: i, .sad, x: i < xs.count ? xs[i] : 0) }
            }
            lastMood[i] = moods[i]
        }
    }

    /// The Town / Shop / Track screens (the game screen tells; `.none` = back in the room).
    func setTownScene(_ s: MusicScene) {
        townScene = s
        guard !muted, started else { return }
        input.scene = raceScene != .none ? raceScene : townScene
    }

    /// Song time (seconds, as heard) of the training music, nil while it is not playing (muted, still decoding): the drill's audio clock.
    func trainingSongTime() -> Double? {
        guard !muted, started, active else { return nil }
        return scene?.songTime(of: .training)
    }
    /// The track of this scene is decoded and playing.
    func scenePlaying(_ s: MusicScene) -> Bool { s.track.map { scene?.isPlaying($0) ?? false } ?? false }

    /// A result jingle (trimmed, faded at its end). Follows the music setting.
    func playJingle(_ j: Jingle) {
        guard !muted, started, active else { return }
        let level = settings.musicLevel * duck.gain
        guard level > 0.01, let u = url(j.rawValue), let p = try? AVAudioPlayer(contentsOf: u) else { return }
        jingle?.stop()
        p.volume = min(1, level * 0.7)
        p.prepareToPlay(); p.play()
        jingle = p
        DispatchQueue.main.asyncAfter(deadline: .now() + max(j.trim - 0.4, 0.1)) { [weak p] in p?.setVolume(0, fadeDuration: 0.4) }
        DispatchQueue.main.asyncAfter(deadline: .now() + j.trim) { [weak p] in p?.stop() }
    }

    // MARK: effects

    private func url(_ name: String) -> URL? { Bundle.main.url(forResource: name, withExtension: "m4a") }

    private func variants(_ sfx: SFX) -> Int {
        if let n = variantCount[sfx.rawValue] { return n }
        var n = 0
        while url("\(sfx.rawValue)_\(n + 1)") != nil { n += 1 }
        variantCount[sfx.rawValue] = n
        return n
    }

    private func preloadEffects() {
        for s in SFX.allCases {
            for v in 1...max(variants(s), 1) {
                let name = "\(s.rawValue)_\(v)"
                guard pool[name] == nil, let u = url(name), let p = try? AVAudioPlayer(contentsOf: u) else { continue }
                p.prepareToPlay()
                pool[name] = [p]
            }
        }
    }

    private func panFor(x: Float?) -> Float { x.map { min(max($0 / 5, -1), 1) * 0.5 } ?? 0 }

    private func fire(_ name: String, volume: Float, pan: Float, rate: Float = 1) {
        guard let u = url(name) else { return }
        var ps = pool[name] ?? []
        var p = ps.first(where: { !$0.isPlaying })
        if p == nil, ps.count < 3, let np = try? AVAudioPlayer(contentsOf: u) { np.enableRate = true; np.prepareToPlay(); ps.append(np); pool[name] = ps; p = np }
        guard let p else { return }
        p.volume = volume
        p.pan = pan
        p.rate = rate
        p.currentTime = 0
        p.play()
    }

    /// Plays a random variant of `sfx` (never the same twice in a row). `x`: the Jelly's floor x for a gentle pan.
    /// `rate`: playback speed (1 = as recorded; a squeak is a boop at 1.7, a drum thump a boop at 0.55).
    func play(_ sfx: SFX, jelly: Int? = nil, x: Float? = nil, volume: Float = 1, rate: Float = 1) {
        guard !muted, started, active else { return }
        let level = settings.sfxLevel * duck.gain
        guard level > 0.01 else { return }
        let now = CACurrentMediaTime()
        let key = jelly.map { "\(sfx.rawValue)#\($0)" } ?? sfx.rawValue
        if let l = lastPlay[key], now - l < sfx.minGap { return }
        lastPlay[key] = now
        let n = variants(sfx)
        guard n > 0 else { return }
        let v = picker.pick(sfx.rawValue, count: n) + 1
        fire("\(sfx.rawValue)_\(v)", volume: min(1, sfx.gain * volume * level * AudioMix.sfxMaster), pan: panFor(x: x), rate: rate)
    }

    // Jelly Circuit cues. Named hooks: dedicated sounds are added later under these names; for now they use existing effects.
    func raceCountdownBeep() { play(.countdownBeep) }
    func raceGo() { play(.raceGo) }
    func raceFinish() { play(.raceFinish) }
    func raceStumble() { play(.stumble) }
    func raceCue(_ c: RaceCue) {
        switch c { case .countdownBeep: raceCountdownBeep(); case .go: raceGo(); case .finish: raceFinish() }
    }

    /// The practice drill's sounds (Training/DrillFlow.swift).
    func drillCue(_ c: DrillCue) {
        switch c {
        case .perfect: play(.tick, volume: 0.9)
        case .good: play(.goodStep)
        case .streak: play(.perfectStreak)
        case .lap: play(.whistle, volume: 0.6)
        case .go: play(.whistle)
        case .statUp: play(.statUp); play(.cheerSmall, volume: 0.7)
        case .tired: play(.tired)
        case .jingle(let win): playJingle(win ? .win : .lose)
        }
    }

    // MARK: race crowd (quiet loop with a crossfade at the loop point)

    @ObservationIgnored private var crowdPlayers: [AVAudioPlayer] = []
    @ObservationIgnored private var crowdWant = false
    @ObservationIgnored private var crowdLevel: Float = 0
    @ObservationIgnored private var crowdCur = 0
    @ObservationIgnored private var crowdFade: Double = -1          // seconds into a crossfade, -1 = none

    /// The crowd murmurs while a race is on (fades in and out).
    func raceCrowd(_ on: Bool) {
        guard !muted, started else { return }
        crowdWant = on
        if on, crowdPlayers.isEmpty, let u = url("crowd_loop_1") {
            crowdPlayers = (0..<2).compactMap { _ in try? AVAudioPlayer(contentsOf: u) }
            for p in crowdPlayers { p.volume = 0; p.prepareToPlay() }
        }
        if on, crowdPlayers.count == 2, !crowdPlayers[crowdCur].isPlaying, active { crowdPlayers[crowdCur].currentTime = 0; crowdPlayers[crowdCur].play() }
    }

    private func tickCrowd(dt: Double) {
        guard crowdPlayers.count == 2 else { return }
        crowdLevel += Float(dt) * (crowdWant ? 1 : -1) / 1.2
        crowdLevel = min(max(crowdLevel, 0), 1)
        let cur = crowdPlayers[crowdCur], nxt = crowdPlayers[1 - crowdCur]
        let base = settings.sfxLevel * duck.gain * AudioMix.crowd * crowdLevel
        if crowdWant || crowdLevel > 0 {
            if crowdFade < 0, cur.isPlaying, cur.duration - cur.currentTime <= AudioMix.crowdCrossfade { nxt.currentTime = 0; nxt.play(); crowdFade = 0 }
        }
        if crowdFade >= 0 {
            crowdFade += dt
            let k = Float(min(crowdFade / AudioMix.crowdCrossfade, 1))
            cur.volume = base * (1 - k); nxt.volume = base * k
            if k >= 1 { cur.stop(); crowdCur = 1 - crowdCur; crowdFade = -1 }
        } else { cur.volume = base }
        if !crowdWant, crowdLevel == 0 { for p in crowdPlayers where p.isPlaying { p.stop() }; crowdFade = -1 }
    }

    func uiTap() { play(.uitap) }
    func uiConfirm() { play(.uiconfirm) }

    /// A quiet foot plant (rate limited per Jelly; louder on a run).
    func footstep(jelly: Int, x: Float, running: Bool) {
        guard !muted, started else { return }
        let i = min(max(jelly, 0), 2)
        let now = CACurrentMediaTime()
        if now - lastFoot[i] < (running ? 0.16 : 0.26) { return }
        lastFoot[i] = now
        play(.footstep, jelly: i, x: x, volume: running ? 1.2 : 0.8)
    }

    /// The Jelly's own voice: pitch by Jelly (1 mid, 2 high, 3 low), happy / sad / babble.
    func chirp(jelly: Int, _ v: JellyVoice, x: Float = 0) {
        guard !muted, started, active else { return }
        let level = settings.sfxLevel * duck.gain
        guard level > 0.01 else { return }
        let i = min(max(jelly, 0), 2)
        let now = CACurrentMediaTime()
        if now - lastVoice[i] < 2.2 { return }
        lastVoice[i] = now
        let name = v == .babble ? "babble_jelly\(i + 1)" : "chirp_jelly\(i + 1)_\(v.rawValue)"
        fire(name, volume: 0.7 * level, pan: panFor(x: x))
    }

    /// Haptics' touch transients -> squish / boop / wobble (the pairing HapticDriver.soundHook promised).
    func touch(kind: String, intensity: Float) {
        guard !muted, started else { return }
        switch kind {
        case "wobble": play(.wobble, volume: 0.5 + 0.5 * min(1, intensity * 1.5))
        case "impact": play(.squish, volume: 0.6 + 0.4 * min(1, intensity))
        default:
            if intensity >= 0.85 { play(.boop, volume: 0.9) }
            else if intensity >= 0.28 { play(.squish, volume: 0.55 + 0.5 * intensity) }
        }
    }

    // MARK: music

    private func loopPlayer(_ name: String) -> (player: AVAudioPlayer, fader: Fader)? {
        guard let u = url(name), let p = try? AVAudioPlayer(contentsOf: u) else { return nil }
        p.numberOfLoops = -1
        p.volume = 0
        p.prepareToPlay()
        return (p, Fader())
    }

    private func trackLength(_ t: MusicTrack) -> Double {
        if let l = lengths[t] { return l }
        let l = url(t.rawValue).flatMap { try? AVAudioPlayer(contentsOf: $0).duration } ?? 90
        lengths[t] = l
        return l
    }

    private func perform(_ events: [MusicEvent]) {
        for e in events {
            eventLog.append(e); if eventLog.count > 40 { eventLog.removeFirst() }
            switch e {
            case .playTrack(let t, let fade):
                for i in decks.indices { decks[i].fader.ramp(to: 0, over: fade) }
                guard let u = url(t.rawValue), let p = try? AVAudioPlayer(contentsOf: u) else { break }
                p.volume = 0
                p.prepareToPlay()
                if active { p.play() }
                var f = Fader(); f.snap(0); f.ramp(to: 1, over: fade)
                decks.append(Deck(player: p, fader: f, track: t))
            case .fadeOutMain(let fade):
                for i in decks.indices { decks[i].fader.ramp(to: 0, over: fade) }
            case .layerOn(let fade):
                if layer == nil { layer = loopPlayer("lofi_play") }
                layer?.player.currentTime = 0
                if active { layer?.player.play() }
                layer?.fader.ramp(to: 1, over: fade)
            case .layerOff(let fade):
                layer?.fader.ramp(to: 0, over: fade)
            case .sceneOn(let t, let fade):
                if _sceneEngineDisabled { break }
                if scene == nil { scene = SceneMusicEngine() }
                scene?.play(t, fade: fade)
            case .sceneOff(let fade):
                scene?.stopAll(fade: fade)
            }
        }
    }

    private func tick() {
        guard started else { return }
        let now = CACurrentMediaTime()
        let dt = min(now - lastTick, 0.25)
        lastTick = now
        guard active else { return }
        DayClock.shared.refresh()
        duck.update(dt: dt)
        var inp = input
        inp.phase = DayPhase.of(hour: DayClock.shared.hour)
        perform(director.update(dt: dt, input: inp))
        for i in decks.indices { decks[i].fader.update(dt: dt) }
        scene?.update(dt: dt)
        layer?.fader.update(dt: dt); ambDay?.fader.update(dt: dt); ambEve?.fader.update(dt: dt)
        tickCrowd(dt: dt)
        decks.removeAll { d in
            if d.fader.level <= 0.0001 && d.fader.target == 0 { d.player.stop(); return true }
            return false
        }
        if let l = layer, l.fader.level <= 0.0001, l.fader.target == 0, l.player.isPlaying { l.player.pause() }
        applyLevels()
    }

    private func applyLevels() {
        guard started else { return }
        let m = settings.musicLevel * duck.gain * AudioMix.music
        let main = Float(director.mainGain(playing: input.playing))
        for d in decks { d.player.volume = d.fader.level * main * m }
        layer?.player.volume = (layer?.fader.level ?? 0) * m * 1.1
        scene?.setLevel(m)
        // ambience follows the clock blend continuously (day room by day, evening room evening + night)
        let b = DayClock.shared.blend
        let a = settings.musicLevel * duck.gain * AudioMix.ambience
        ambDay?.player.volume = Float(b.morning + b.day) * a
        ambEve?.player.volume = Float(b.evening + b.night) * a
    }
}
