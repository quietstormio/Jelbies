//
//  ShowFlow.swift
//  The Jelly Show's whole trip, as one state machine (no bodies of its own; GameCare+Show.swift wires it to the Jelbies):
//
//      off -> fade to white -> [swap to the stage] -> fade in -> Look (a judged walk-on, auto-advances) -> Dance (3-2-1-GO on the stage music, the prompt
//      lane) -> Trick (three turns: pick a trick off his menu) -> results (podium, Drops, trophies) -> (Done) fade -> room.
//
//  The rules are `ShowSim`; this class adds time: the fade, the countdown that waits for the music, the song clock the dance is judged by, the
//  seconds a trick takes to perform, the one-time settlement at the results, and the cues.
//

import Foundation
import Observation
import simd

/// The show's sound cues (AudioHub.showCue maps them to files; tests count them).
nonisolated enum ShowCue: Equatable, Sendable { case perfect, good, slip, countdown, go, ring, land, flop, burst, applause, jingle(win: Bool) }

@MainActor
@Observable
final class ShowFlow {
    enum Phase: Equatable { case off, fade, stage }
    enum Dest { case stage, room }
    enum FadeStage { case out, hold, `in` }
    /// The Dance round's clock.
    enum Beat: Equatable { case idle, countdown, dancing, danced }
    /// The Trick round's turn.
    /// `rivals`: the player's trick is over and the rivals take their turn one after another (walk up, perform, step back), then it is his turn again.
    enum TrickStage: Equatable { case pick, performing, rivals }
    /// What one rival is doing now (and, last, the player's Jelbie walking back to the centre).
    enum RivalStep: Equatable { case walkIn, perform, walkOut, playerBack }
    /// What the bodies are asked to do (GameCare+Show.swift): the player steps aside / back, rival `i` walks up / performs / steps back, everybody snaps home (Skip).
    enum RivalCue: Equatable { case playerAside(Bool), walkIn(Int), perform(Int, VoiceTrick, Bool), walkOut(Int), snap }

    private(set) var phase: Phase = .off
    /// 0...1 white overlay opacity (the view draws it).
    private(set) var wipe: Float = 0
    /// The stage is shown instead of the room (0 / 1: snapped under the white, never blended on screen).
    @ObservationIgnored private(set) var cameraBlend: Float = 0
    /// The rules (nil when off). Not observed (the dance changes it every step); the views read `revision` and the published bits.
    @ObservationIgnored private(set) var sim: ShowSim?
    /// Bumped whenever the show moved on in a way the screens redraw for.
    private(set) var revision = 0
    /// Ranks won and trophies (saved outside tests).
    var progress = ShowProgress(persists: ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil)

    private(set) var playerID = 0
    private(set) var playerName = ""
    private(set) var character = 0
    private(set) var rank: ShowRank = .puddle
    private(set) var theme: ShowTheme = .bunnyPicnic
    private(set) var dayKey = 0
    /// How many bodies stand on the stage (the player's plus the rival bodies borrowed from the room).
    private(set) var bodies = 1

    // the Dance round
    private(set) var beat: Beat = .idle
    private(set) var countdown = 0
    /// Bumped on every countdown number / GO so the view can animate each.
    private(set) var cueSerial = 0
    private(set) var flash: DrillGrade?
    private(set) var flashSerial = 0
    @ObservationIgnored private var flashAge: Float = 0
    @ObservationIgnored private var countdownLeft: Float = 0
    @ObservationIgnored private var audioWait: Float = 0
    @ObservationIgnored private(set) var song: Double = 0
    /// The dance song of this show (picked from the seed at `begin`); its clock is the song's own playback time.
    @ObservationIgnored private(set) var danceSong: DanceSong = DanceSong.all[0]
    /// The dance clock: seconds of the dance song as heard (0 = its first sample). Held at 0 until the song is audible, then the audio engine's own player time.
    @ObservationIgnored private(set) var danceT: Double = 0
    @ObservationIgnored private var danceMusicOn = false
    @ObservationIgnored private var danceHeard = false
    @ObservationIgnored private var danceAudioWait: Float = 0
    @ObservationIgnored private var goAge: Float = 0
    @ObservationIgnored private var dancedAge: Float = 0
    /// Seconds the Look card has been up.
    @ObservationIgnored private(set) var lookAge: Float = 0

    // the Trick round
    private(set) var trickStage: TrickStage = .pick
    @ObservationIgnored private var clock: Double = 0
    private(set) var lastTurn: ShowTrickTurn?
    /// The rival on the stage now (nil between turns) and what she is doing; `rivalRound` is the turn (0...2) the rivals are on.
    private(set) var rivalTurn: Int?
    private(set) var rivalStep: RivalStep = .walkIn
    private(set) var rivalRound = 0
    @ObservationIgnored private var rivalQueue: [Int] = []
    @ObservationIgnored private var rivalT: Float = 0
    @ObservationIgnored private var performLeft: Float = 0
    /// The Glow Burst fired on the last turn (the view throws confetti).
    private(set) var burstFlash = 0

    // results
    private(set) var earned = 0
    private(set) var awards: ShowProgress.Awards?
    @ObservationIgnored private(set) var settled = false
    var cardAge: Float = 0
    /// "Show again" was tapped: the lobby reopens once the room is back.
    @ObservationIgnored private(set) var againWanted = false

    @ObservationIgnored private(set) var fadeDest: Dest = .stage
    @ObservationIgnored private(set) var fadeStage: FadeStage = .out
    @ObservationIgnored private var holdT: Float = 0
    @ObservationIgnored private var swapped = false
    @ObservationIgnored private(set) var leaving = false
    @ObservationIgnored private(set) var started = 0

    /// Where the world swaps happen (GameCare+Show.swift): called with the white opaque.
    @ObservationIgnored var onSwap: (Dest) -> Void = { _ in }
    /// The trip is over and the room is back (`won`: a 1st; `again`: open the lobby again).
    @ObservationIgnored var onReturned: (_ playerID: Int, _ won: Bool, _ again: Bool) -> Void = { _, _, _ in }
    /// The player's Jelbie performs `trick` (`success` false = the cute flop) / the whole stage dances (`on`) / the results: he celebrates (`place`).
    @ObservationIgnored var onPerform: (VoiceTrick, Bool) -> Void = { _, _ in }
    @ObservationIgnored var onDance: (DanceID?, Bool) -> Void = { _, _ in }
    @ObservationIgnored var onHit: (DrillGrade) -> Void = { _ in }
    @ObservationIgnored var onResults: (Int) -> Void = { _ in }
    @ObservationIgnored var onBurst: () -> Void = {}
    /// The rivals' turn on the stage (bodies) and whether a body has got where it was sent (`who` nil = the player's Jelbie; `atCentre`: at the middle, else at his rest / aside spot).
    @ObservationIgnored var onRival: (RivalCue) -> Void = { _ in }
    @ObservationIgnored var rivalReady: (_ who: Int?, _ atCentre: Bool) -> Bool = { _, _ in true }
    /// Money (the care glue sets it).
    @ObservationIgnored var wallet: DropsWallet?
    @ObservationIgnored var cue: (ShowCue) -> Void = { AudioHub.shared.showCue($0) }
    /// The audio clock of the stage / studio music (song seconds), nil = not playing (muted, still decoding): the dance then counts frames.
    @ObservationIgnored var songClock: (SceneTrack) -> Double? = { AudioHub.shared.songTime(of: $0) }
    /// The music is up (muted = nothing to wait for).
    @ObservationIgnored var audioReady: (MusicScene) -> Bool = { AudioHub.shared.muted || AudioHub.shared.scenePlaying($0) }
    /// Test / capture aid: the dance is tapped for him (a few late, one missed) and the tricks are picked for him.
    @ObservationIgnored var auto = false
    @ObservationIgnored private var autoDone = 0
    /// Dance prompts whose left / right audio cue has played (accessibility; PlayAssist.swift).
    @ObservationIgnored var danceCued = 0
    @ObservationIgnored private var autoTrickWait: Float = 0

    /// Seconds of white (fade out / hold / fade in), the countdown beat, how long a trick holds the stage.
    static let fadeOut: Float = 0.45, fadeHold: Float = 0.3, fadeIn: Float = 0.5
    static let countdownBeat: Float = 0.85
    static let performSeconds: Float = 2.6
    /// How long the judged walk-on (Look) shows before it moves on by itself.
    static let lookSeconds: Float = 3

    init() {}
    nonisolated deinit {}

    // MARK: queries

    var active: Bool { phase != .off }
    var onStage: Bool { cameraBlend > 0 }
    var round: ShowRound { sim?.round ?? .look }
    var showsCountdown: Bool { phase == .stage && beat == .countdown && countdown > 0 }
    var showsGo: Bool { phase == .stage && beat == .dancing && goAge < 0.6 }
    /// The foot buttons are live.
    var buttonsLive: Bool { phase == .stage && beat == .dancing && wipe == 0 && !(sim?.danceDone ?? false) }
    var hasResults: Bool { sim?.round == .results && trickStage == .pick }
    /// The rival under the lights and what she shows this turn (her name, trick, stars and points come from this).
    var rivalNow: (rival: Int, turn: ShowTrickTurn)? {
        guard trickStage == .rivals, let i = rivalTurn, let s = sim, s.rivalTurns.indices.contains(i), s.rivalTurns[i].indices.contains(rivalRound) else { return nil }
        return (i, s.rivalTurns[i][rivalRound])
    }
    /// Her points are on the screen (she has performed).
    var rivalScored: Bool { rivalStep == .perform || rivalStep == .walkOut }
    /// The scene track the stage plays now.
    var track: SceneTrack { .contestStage }
    /// The dance song's track (plays once under the dance) and its measured beat grid.
    var danceTrack: SceneTrack { danceSong.track }
    var grid: ShowBeat { danceSong.grid }
    /// The dance song is playing under the dance.
    var danceSongOn: Bool { beat == .dancing && danceMusicOn }

    /// What the stage plays (Audio/SceneMusic.swift): the stage music; silence at the results (a jingle plays) and on the way home.
    var musicScene: MusicScene {
        guard phase != .off, cameraBlend > 0, !(phase == .fade && fadeDest == .room) else { return .none }
        if hasResults { return .results }
        if danceSongOn { return .danceSong(danceSong.song - 1) }          // the dance song plays once; the stage loop comes back after the dance
        return .show
    }
    /// How the camera frames the stage this moment (GameCamera.showPose).
    var frame: ShowFrame {
        switch round {
        case .look: return .look
        case .dance: return .dance(bodies: bodies)
        case .trick: return .trick
        case .results: return trickStage == .pick ? .results : .trick          // (the rivals' last turn still plays on the trick frame)
        }
    }

    // MARK: start

    /// "Start show": Jelbie `id` enters at `rank`. Ignored while a trip is running or the rank is locked.
    func begin(playerID id: Int, name: String, character c: Int, input: ShowPlayerInput, rank r: ShowRank, dayKey day: Int, bodies n: Int, seed: UInt64) {
        guard phase == .off, progress.unlocked(r) else { return }
        playerID = id; playerName = name; character = c; rank = r; dayKey = day; bodies = max(1, min(n, 4))
        theme = ShowSchedule.theme(dayKey: day)
        let rivals = ShowRivalSource.rivals(dayKey: day, rank: r, theme: theme, firstShow: progress.firstShowEver)
        sim = ShowSim(rank: r, theme: theme, dayKey: day, player: input, rivals: rivals, seed: seed)
        danceSong = DanceSong.pick(seed: seed)
        resetStage()
        phase = .fade; fadeDest = .stage; fadeStage = .out; holdT = 0; swapped = false; leaving = false
        started += 1
        revision += 1
    }

    private func resetStage() {
        beat = .idle; countdown = 0; countdownLeft = 0; audioWait = 0; song = 0; flash = nil; flashAge = 0; dancedAge = 0; lookAge = 0; goAge = 0
        danceT = 0; danceMusicOn = false; danceHeard = false; danceAudioWait = 0
        trickStage = .pick; clock = 0; lastTurn = nil; performLeft = 0; burstFlash = 0
        rivalTurn = nil; rivalStep = .walkIn; rivalRound = 0; rivalQueue = []; rivalT = 0
        earned = 0; awards = nil; settled = false; cardAge = 0; againWanted = false
        autoDone = 0; autoTrickWait = 0; danceCued = 0
        ShowAssist.refresh()
    }

    /// "Done" / "Show again" on the results (or the X on a drill): back to the room.
    func goHome(again: Bool = false) {
        guard phase == .stage, !leaving else { return }
        leaving = true; againWanted = again
        onDance(nil, false)
        phase = .fade; fadeDest = .room; fadeStage = .out; holdT = 0; swapped = false
    }

    // MARK: the Look round

    /// The tags worn in the scored slots, read when the show starts (the Studio's Dress up chose them; the stage has no wardrobe).
    func setOutfit(_ o: [WearSlot: [WearTag]]) {
        guard var s = sim, s.round == .look else { return }
        s.setOutfit(o); sim = s
        revision += 1
    }
    /// "Next" (or the walk-on timing out): on to the Dance.
    func finishLook() {
        guard var s = sim, s.round == .look, phase == .stage else { return }
        s.finishLook(); sim = s
        A11yEvents.say("Round 2: Dance", .normal)
        beat = .countdown; countdown = 3; countdownLeft = Self.countdownBeat; audioWait = 0; cueSerial += 1; cue(.countdown)
        onDance(s.player.dance, true)
        revision += 1
    }

    // MARK: the Dance round

    private func songNow(dt: Float) -> Double {
        if let a = songClock(track) { song = a } else { song += Double(dt) }
        return song
    }

    private func tickDance(dt: Float) {
        var now = songNow(dt: dt)
        switch beat {
        case .idle, .danced:
            if beat == .danced { dancedAge += dt }
            return
        case .countdown:
            if !audioReady(musicScene), audioWait < 3 { audioWait += dt; return }
            countdownLeft -= dt
            if countdownLeft <= 0 {
                countdown -= 1
                if countdown > 0 { countdownLeft = Self.countdownBeat; cueSerial += 1; cue(.countdown) }
                else {
                    beat = .dancing; goAge = 0; cueSerial += 1; cue(.go)
                    if var s = sim {
                        // the dance song starts now (the scene switches on the next frame) and its prompts are on ITS beats: the clock is the song's own
                        // player time, held at 0 until the song is audible, so the start can never drift from the clock
                        danceT = 0; danceMusicOn = true; danceHeard = false; danceAudioWait = 0
                        s.beginDance(song: danceSong, songTime: 0); sim = s
                        if AudioHub.audioLog { NSLog("[melon] dance start song=%d \"%@\" bpm=%.2f firstBeat=%.4f prompts=%d %.3f..%.3f s", danceSong.song, danceSong.title, danceSong.bpm, danceSong.grid.firstBeat, danceSong.promptCount, danceSong.grid.time(ofBeat: DanceSong.firstPromptBeat), danceSong.grid.time(ofBeat: danceSong.lastBeat)) }
                    }
                    revision += 1
                }
            }
        case .dancing:
            flashAge += dt; goAge += dt
            if flashAge > 0.7, flash != nil { flash = nil }
            now = danceClock(dt: dt)
            if auto || ShowAssist.autoDance { autoPlay(now) }
            promptCues(now: now)
            guard var s = sim else { return }
            let ev = s.tickDance(songTime: now)
            sim = s
            handle(ev)
            if s.danceDone { beat = .danced; dancedAge = 0; danceMusicOn = false; cue(.applause); revision += 1 }          // (the stage loop comes back)
        }
    }

    /// The dance clock, advanced once per tick: the song's OWN playback time from the audio engine (player sample time minus output latency), so the prompts
    /// stay with the music however the frames drop. Held at 0 while the song decodes; frame counted only when there is no audio clock (muted, tests, a failed decode).
    private func danceClock(dt: Float) -> Double {
        if let a = songClock(danceTrack) {
            if !danceHeard, AudioHub.audioLog { NSLog("[melon] dance song heard: clock %.3f s (output latency %.0f ms)", a, AudioHub.shared.outputLatencyMS) }
            danceHeard = true; danceT = max(danceT, a); return danceT
        }
        if !danceHeard, !audioReady(.danceSong(danceSong.song - 1)), danceAudioWait < 1.5 { danceAudioWait += dt; return danceT }          // decoding: the prompts wait
        danceT += Double(dt)
        return danceT
    }
    /// The dance clock read now (a tap, the prompt lane's frame): the audio's latest answer once the song is heard.
    func danceNow() -> Double {
        guard danceMusicOn, danceHeard, let a = songClock(danceTrack) else { return danceT }
        return max(danceT, a)
    }

    /// A tap of the foot button during the dance.
    func tap(foot: Int) {
        guard buttonsLive else { return }
        let now = danceNow()
        danceT = max(danceT, now)
        guard var s = sim else { return }
        let nearest = s.dance?.nearestPrompt(to: ShowDanceSim.judgedTime(now))
        let ev = s.tapDance(foot: foot, at: now)
        sim = s
        if AudioHub.audioLog, let n = nearest {          // the phone's proof of sync: how far each tap landed from the song's prompt (positive = late)
            NSLog("[melon] dance tap song=%d foot=%d t=%.3f prompt#%d at %.3f err=%+.0f ms (heard=%d)", danceSong.song, foot, now, n.index, n.time, (ShowDanceSim.judgedTime(now) - n.time) * 1000, danceHeard ? 1 : 0)
        }
        handle(ev)
    }

    private func handle(_ events: [ShowDanceSim.Event]) {
        for e in events {
            switch e {
            case .hit(_, _, let g): flash = g; flashSerial += 1; flashAge = 0; cue(g == .perfect ? .perfect : .good); onHit(g); if flashSerial % 3 == 0 { A11yEvents.say(g == .perfect ? "Perfect" : "Good", .low) }
            case .slip: flash = .miss; flashSerial += 1; flashAge = 0; cue(.slip); onHit(.miss); if flashSerial % 3 == 0 { A11yEvents.say("Miss", .low) }
            case .stray, .finished: break
            }
        }
    }

    /// Plays the dance for him: every prompt on the beat, except a few (a late good one, a missed one) so the screen shows all the grades.
    private func autoPlay(_ now: Double) {
        let prompts = sim?.dance?.prompts ?? []
        while autoDone < prompts.count {
            let p = prompts[autoDone]
            let late: Double = ShowAssist.autoDance ? 0.07 : (autoDone % 5 == 3 ? 0.1 : (autoDone % 7 == 4 ? 0.02 : 0))
            let at = p.time + ShowDanceSim.latencyOffset + late
            if at > now { break }
            autoDone += 1
            if autoDone % 11 == 6, !ShowAssist.autoDance { continue }
            song = max(song, at)
            if var s = sim { handle(s.tapDance(foot: p.foot, at: at)); sim = s }
        }
    }

    /// "On to Trick" after the dance (also taken by the auto player).
    func finishDance() {
        guard var s = sim, s.round == .dance, phase == .stage, beat == .danced || s.danceDone else { return }
        s.finishDance(); sim = s
        A11yEvents.say("Round 3: Trick", .normal)
        onDance(nil, false)
        beat = .idle
        trickStage = .pick
        revision += 1
    }

    // MARK: the Trick round

    /// A menu row is tapped: he performs it at once (a slip is the cute flop).
    func pick(_ t: VoiceTrick) {
        guard var s = sim, s.round == .trick, trickStage == .pick, phase == .stage, !s.tricksDone else { return }
        guard let turn = s.perform(t) else { return }
        sim = s
        land(turn)
    }
    /// The Glow Burst button.
    func armBurst() {
        guard var s = sim, s.round == .trick, s.burstReady else { return }
        s.armBurst(); sim = s
        revision += 1
    }
    private func land(_ turn: ShowTrickTurn) {
        lastTurn = turn
        trickStage = .performing; performLeft = Self.performSeconds
        cue(turn.success ? .land : .flop)
        if turn.burst { burstFlash += 1; cue(.burst); onBurst() }
        onPerform(turn.trick, turn.success)
        revision += 1
    }
    private func tickTrick(dt: Float) {
        clock += Double(dt)
        switch trickStage {
        case .pick:
            if auto, let s = sim, !s.tricksDone {
                autoTrickWait += dt
                if autoTrickWait > 1.2 {
                    let t = s.knownTricks.first(where: { !s.usedTricks.contains($0) }) ?? s.knownTricks.first ?? .sit
                    autoTrickWait = 0
                    if s.burstReady { armBurst() }
                    pick(t)
                }
            }
        case .performing:
            performLeft -= dt
            if performLeft <= 0 {
                if let s = sim, !s.rivals.isEmpty { startRivals() }
                else { trickStage = .pick; if sim?.round == .results { settle() }; revision += 1 }
            }
        case .rivals: tickRivals(dt: dt)
        }
    }

    // MARK: the rivals' turns

    /// The player's trick is over: each rival in turn walks up to the middle, shows the trick she rolled for this turn and steps back (his Jelbie waits aside).
    private func startRivals() {
        guard let s = sim else { return }
        rivalRound = max(s.turns.count - 1, 0)
        rivalQueue = Array(s.rivals.indices)
        trickStage = .rivals
        onRival(.playerAside(true))
        nextRival()
    }
    private func nextRival() {
        rivalT = 0
        guard !rivalQueue.isEmpty else {
            rivalTurn = nil; rivalStep = .playerBack
            onRival(.playerAside(false))
            revision += 1
            return
        }
        let i = rivalQueue.removeFirst()
        rivalTurn = i; rivalStep = .walkIn
        onRival(.walkIn(i))
        if let s = sim { A11yEvents.say("\(s.rivals[i].name) is up", .normal) }
        revision += 1
    }
    private func tickRivals(dt: Float) {
        rivalT += dt
        switch rivalStep {
        case .walkIn:
            guard let i = rivalTurn, rivalT >= 0.5, rivalReady(i, true) || rivalT > 4 else { return }
            startRivalPerform(i)
        case .perform:
            guard let i = rivalTurn, rivalT >= Self.performSeconds else { return }
            rivalStep = .walkOut; rivalT = 0; onRival(.walkOut(i)); revision += 1
        case .walkOut:
            guard let i = rivalTurn, rivalT >= 0.4, rivalReady(i, false) || rivalT > 3 else { return }
            nextRival()
        case .playerBack:
            guard rivalT >= 0.3, rivalReady(nil, true) || rivalT > 3.5 else { return }
            endRivals()
        }
    }
    private func startRivalPerform(_ i: Int) {
        guard let n = rivalNow else { return }
        rivalStep = .perform; rivalT = 0
        cue(n.turn.success ? .land : .flop)
        onRival(.perform(i, n.turn.trick, n.turn.success))
        if let s = sim {
            let t = n.turn
            A11yEvents.say("\(s.rivals[i].name): \(t.trick.title), \(t.success ? "\(t.points) points" : "a cute flop, \(t.points) points")", .normal)
        }
        revision += 1
    }
    /// The turn is over: his again (or the results, after the third).
    private func endRivals() {
        trickStage = .pick; rivalTurn = nil; rivalQueue = []; rivalT = 0
        if sim?.round == .results { settle() }
        revision += 1
    }
    /// "Skip": the rest of the rivals' tricks of this turn are settled (their points already count), the bodies snap to their spots and it is his turn.
    func skipRivals() {
        guard trickStage == .rivals else { return }
        onRival(.snap)
        A11yEvents.say("Skipped the rivals' tricks", .normal)
        endRivals()
    }
    /// A tap on the banner: only the rival under the lights is skipped (she steps back at once).
    func skipCurrentRival() {
        guard trickStage == .rivals, let i = rivalTurn, rivalStep == .walkIn || rivalStep == .perform else { return }
        rivalStep = .walkOut; rivalT = 0; onRival(.walkOut(i)); revision += 1
    }

    // MARK: results

    /// The placings are in: Drops by place, the record, the trophies, once.
    private func settle() {
        guard !settled, let s = sim, let place = s.playerPlace else { return }
        settled = true
        earned = s.playerDrops
        wallet?.add(earned)
        awards = progress.record(rank: s.rank, place: place, theme: s.theme, character: character, burst: s.entrants.first(where: \.isPlayer)?.burst ?? false,
                                 perfectDance: s.perfectDance, hatTrick: s.hatTrick)
        cardAge = 0
        cue(.jingle(win: place <= 2))
        A11yEvents.say("\(playerName) placed \(A11yEvents.ordinal(place)) in the show. \(earned) JellyCoins", .high)
        onResults(place)
        revision += 1
    }

    // MARK: per fixed step

    func tick(dt: Float) {
        switch phase {
        case .off: return
        case .fade: tickFade(dt: dt); return
        case .stage: break
        }
        guard wipe == 0 else { return }
        guard let s = sim else { return }
        switch s.round {
        case .look:
            lookAge += dt
            if lookAge >= Self.lookSeconds { finishLook() }          // the judges have looked: on to the dance (or the Next button)
        case .dance:
            tickDance(dt: dt)
            if auto, beat == .danced, dancedAge > 1.5 { finishDance() }
        case .trick: tickTrick(dt: dt)
        case .results:
            if trickStage != .pick { tickTrick(dt: dt) } else { if !settled { settle() }; cardAge += dt }          // (the last turn's rivals still perform after the sim has its results)
        }
    }

    // MARK: fade (swaps under the white)

    private func tickFade(dt: Float) {
        switch fadeStage {
        case .out:
            wipe = min(1, wipe + dt / Self.fadeOut)
            if wipe >= 1 { fadeStage = .hold; holdT = 0 }
        case .hold:
            wipe = 1
            holdT += dt
            if !swapped {
                swapped = true
                cameraBlend = fadeDest == .stage ? 1 : 0
                onSwap(fadeDest)
            }
            if holdT >= Self.fadeHold { fadeStage = .in }
        case .in:
            wipe = max(0, wipe - dt / Self.fadeIn)
            if wipe <= 0 {
                if fadeDest == .stage { phase = .stage; clock = 0 } else { finishTrip() }
            }
        }
    }

    private func finishTrip() {
        let won = sim?.playerWon ?? false
        let id = playerID, again = againWanted
        phase = .off; leaving = false
        sim = nil
        onReturned(id, won, again)
        revision += 1
    }

    /// Hard stop (tests, the app leaving): everything back to the room at once.
    func abort() {
        guard phase != .off else { return }
        if cameraBlend > 0 || (swapped && fadeDest == .stage) { onSwap(.room) }
        cameraBlend = 0; wipe = 0; phase = .off; sim = nil; leaving = false
        trickStage = .pick; rivalTurn = nil; rivalQueue = []
        onDance(nil, false)
        revision += 1
    }
}
