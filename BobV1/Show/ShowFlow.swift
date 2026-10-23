//
//  ShowFlow.swift
//  The Jelly Show's whole trip, as one state machine (no bodies of its own; GameCare+Show.swift wires it to the Jelbies):
//
//      off -> fade to white -> [swap to the stage] -> fade in -> Look (dress up, live score) -> Dance (3-2-1-GO on the stage music, the prompt
//      lane) -> Trick (three turns: pick a trick, tap when the spotlight ring hugs him) -> results (podium, Drops, trophies) -> (Done) fade -> room.
//
//  The rules are `ShowSim`; this class adds time: the fade, the countdown that waits for the music, the song clock the dance is judged by, the
//  closing ring, the seconds a trick takes to perform, the one-time settlement at the results, and the cues. `kind == .practice` is the Studio's
//  dance drill: the same stage and lane, alone, studio music, the dance's skill grows at the end and nothing is paid.
//

import Foundation
import Observation
import simd

/// The show's sound cues (AudioHub.showCue maps them to files; tests count them).
nonisolated enum ShowCue: Equatable, Sendable { case perfect, good, slip, countdown, go, ring, land, flop, burst, applause, jingle(win: Bool) }

/// What the dance drill in the Studio gave.
nonisolated struct DancePracticeResult: Equatable, Sendable {
    var dance: DanceID
    var accuracy: Float
    var perfects: Int, goods: Int, misses: Int
    var before: Float, after: Float
    var pepLeft: Int
    var pepSpent: Bool
    var gain: Float { after - before }
}

@MainActor
@Observable
final class ShowFlow {
    enum Phase: Equatable { case off, fade, stage }
    enum Kind: Equatable { case show, practice }
    enum Dest { case stage, room }
    enum FadeStage { case out, hold, `in` }
    /// The Dance round's clock.
    enum Beat: Equatable { case idle, countdown, dancing, danced }
    /// The Trick round's turn.
    enum TrickStage: Equatable { case pick, ring, performing }

    private(set) var phase: Phase = .off
    private(set) var kind: Kind = .show
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
    @ObservationIgnored private var dancedAge: Float = 0

    // the Trick round
    private(set) var trickStage: TrickStage = .pick
    /// Seconds since the ring started closing (the view draws the ring from it).
    @ObservationIgnored private(set) var ringAge: Double = 0
    @ObservationIgnored private var clock: Double = 0
    private(set) var lastTurn: ShowTrickTurn?
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

    // the Studio's dance drill
    @ObservationIgnored private(set) var practice: ShowDanceSim?
    private(set) var practiceDance: DanceID = .sway
    private(set) var practiceResult: DancePracticeResult?
    @ObservationIgnored weak var stats: JellyStats?
    static let practicePrompts = 24

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
    /// Money (the care glue sets it).
    @ObservationIgnored var wallet: DropsWallet?
    @ObservationIgnored var cue: (ShowCue) -> Void = { AudioHub.shared.showCue($0) }
    /// The audio clock of the stage / studio music (song seconds), nil = not playing (muted, still decoding): the dance then counts frames.
    @ObservationIgnored var songClock: (SceneTrack) -> Double? = { AudioHub.shared.songTime(of: $0) }
    /// The music is up (muted = nothing to wait for).
    @ObservationIgnored var audioReady: (MusicScene) -> Bool = { AudioHub.shared.muted || AudioHub.shared.scenePlaying($0) }
    /// Test / capture aid: the dance is tapped for him (a few late, one missed) and the ring is tapped near its best.
    @ObservationIgnored var auto = false
    @ObservationIgnored private var autoDone = 0
    @ObservationIgnored private var ringNowSaid = false
    /// Dance prompts whose left / right audio cue has played (accessibility; PlayAssist.swift).
    @ObservationIgnored var danceCued = 0
    @ObservationIgnored private var autoTrickWait: Float = 0

    /// Seconds of white (fade out / hold / fade in), the countdown beat, how long a trick holds the stage.
    static let fadeOut: Float = 0.45, fadeHold: Float = 0.3, fadeIn: Float = 0.5
    static let countdownBeat: Float = 0.85
    static let performSeconds: Float = 2.6
    /// The ring is judged a miss (timing 0) this long after its best moment.
    static let ringGrace: Double = 0.45

    init() {}
    nonisolated deinit {}

    // MARK: queries

    var active: Bool { phase != .off }
    var onStage: Bool { cameraBlend > 0 }
    var isPractice: Bool { kind == .practice }
    var round: ShowRound { sim?.round ?? .look }
    var showsCountdown: Bool { phase == .stage && beat == .countdown && countdown > 0 }
    var showsGo: Bool { phase == .stage && beat == .dancing && song - danceGoSong < 0.6 }
    @ObservationIgnored private var danceGoSong: Double = -10
    /// The foot buttons are live.
    var buttonsLive: Bool { phase == .stage && beat == .dancing && wipe == 0 && !(sim?.danceDone ?? false) && practiceResult == nil }
    var hasResults: Bool { kind == .practice ? practiceResult != nil : sim?.round == .results }
    /// The scene track the stage plays now.
    var track: SceneTrack { kind == .practice ? .studioPractice : .contestStage }
    var grid: ShowBeat { ShowBeat.grid(for: track) }

    /// What the stage plays (Audio/SceneMusic.swift): the stage music, the studio loop for a drill; silence at the results (a jingle plays) and on the way home.
    var musicScene: MusicScene {
        guard phase != .off, cameraBlend > 0, !(phase == .fade && fadeDest == .room) else { return .none }
        if hasResults { return .results }
        return kind == .practice ? .studio : .show
    }
    /// How the camera frames the stage this moment (GameCamera.showPose).
    var frame: ShowFrame {
        if kind == .practice { return .practice }
        switch round {
        case .look: return .look
        case .dance: return .dance(bodies: bodies)
        case .trick: return .trick
        case .results: return .results
        }
    }

    // MARK: start

    /// "Start show": Jelbie `id` enters at `rank`. Ignored while a trip is running or the rank is locked.
    func begin(playerID id: Int, name: String, character c: Int, input: ShowPlayerInput, rank r: ShowRank, dayKey day: Int, bodies n: Int, seed: UInt64) {
        guard phase == .off, progress.unlocked(r) else { return }
        kind = .show
        playerID = id; playerName = name; character = c; rank = r; dayKey = day; bodies = max(1, min(n, 4))
        theme = ShowSchedule.theme(dayKey: day)
        let rivals = ShowRivalSource.rivals(dayKey: day, rank: r, theme: theme, firstShow: progress.firstShowEver)
        sim = ShowSim(rank: r, theme: theme, dayKey: day, player: input, rivals: rivals, seed: seed)
        resetStage()
        phase = .fade; fadeDest = .stage; fadeStage = .out; holdT = 0; swapped = false; leaving = false
        started += 1
        revision += 1
    }

    /// "Practise dance" (the Studio): Jelbie `id` dances `dance` alone to the studio music; its skill grows at the end.
    func beginPractice(playerID id: Int, name: String, character c: Int, dance: DanceID, stats s: JellyStats, seed: UInt64) {
        guard phase == .off else { return }
        kind = .practice
        playerID = id; playerName = name; character = c; bodies = 1
        practiceDance = dance; stats = s; practiceResult = nil; practice = nil
        sim = nil
        resetStage()
        phase = .fade; fadeDest = .stage; fadeStage = .out; holdT = 0; swapped = false; leaving = false
        started += 1
        revision += 1
    }

    private func resetStage() {
        beat = .idle; countdown = 0; countdownLeft = 0; audioWait = 0; song = 0; flash = nil; flashAge = 0; dancedAge = 0; danceGoSong = -10
        trickStage = .pick; ringAge = 0; clock = 0; lastTurn = nil; performLeft = 0; burstFlash = 0
        earned = 0; awards = nil; settled = false; cardAge = 0; againWanted = false
        autoDone = 0; autoTrickWait = 0; ringNowSaid = false; danceCued = 0
        ShowAssist.refresh()
        practiceSeed = UInt64(dayKey) &+ UInt64(playerID) &* 977
    }
    @ObservationIgnored private var practiceSeed: UInt64 = 1

    /// "Done" / "Show again" on the results (or the X on a drill): back to the room.
    func goHome(again: Bool = false) {
        guard phase == .stage, !leaving else { return }
        leaving = true; againWanted = again
        onDance(nil, false)
        phase = .fade; fadeDest = .room; fadeStage = .out; holdT = 0; swapped = false
    }

    // MARK: the Look round

    /// The wardrobe changed: the tags worn in the scored slots (the glue reads the real StoreBook).
    func setOutfit(_ o: [WearSlot: [WearTag]]) {
        guard var s = sim, s.round == .look else { return }
        s.setOutfit(o); sim = s
        revision += 1
    }
    /// "Looks great. On to Dance".
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
        let now = songNow(dt: dt)
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
                    beat = .dancing; danceGoSong = now; cueSerial += 1; cue(.go)
                    if kind == .practice { practice = ShowDanceSim(count: Self.practicePrompts, grid: grid, timing: .kind, seed: practiceSeed, songTime: now) }
                    else if var s = sim { s.beginDance(grid: grid, songTime: now); sim = s }
                    revision += 1
                }
            }
        case .dancing:
            flashAge += dt
            if flashAge > 0.7, flash != nil { flash = nil }
            if auto || ShowAssist.autoDance { autoPlay(now) }
            promptCues(now: now)
            if kind == .practice {
                guard var p = practice else { return }
                p.tick(songTime: now)
                handle(p.takeEvents())
                practice = p
                if p.finished { finishPractice(p) }
            } else {
                guard var s = sim else { return }
                let ev = s.tickDance(songTime: now)
                sim = s
                handle(ev)
                if s.danceDone { beat = .danced; dancedAge = 0; cue(.applause); revision += 1 }
            }
        }
    }

    /// A tap of the foot button during the dance.
    func tap(foot: Int) {
        guard buttonsLive else { return }
        let now = songClock(track) ?? song
        song = max(song, now)
        if kind == .practice {
            guard var p = practice else { return }
            p.tap(foot: foot, at: song)
            handle(p.takeEvents())
            practice = p
            if p.finished { finishPractice(p) }
        } else {
            guard var s = sim else { return }
            let ev = s.tapDance(foot: foot, at: song)
            sim = s
            handle(ev)
        }
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
        let prompts = kind == .practice ? (practice?.prompts ?? []) : (sim?.dance?.prompts ?? [])
        while autoDone < prompts.count {
            let p = prompts[autoDone]
            let late: Double = ShowAssist.autoDance ? 0.07 : (autoDone % 5 == 3 ? 0.1 : (autoDone % 7 == 4 ? 0.02 : 0))
            let at = p.time + ShowDanceSim.latencyOffset + late
            if at > now { break }
            autoDone += 1
            if autoDone % 11 == 6, !ShowAssist.autoDance { continue }
            song = max(song, at)
            if kind == .practice { practice?.tap(foot: p.foot, at: at); if let p2 = practice { var q = p2; handle(q.takeEvents()); practice = q } }
            else if var s = sim { handle(s.tapDance(foot: p.foot, at: at)); sim = s }
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

    /// A trick card is tapped: the ring starts closing.
    func pick(_ t: VoiceTrick) {
        guard var s = sim, s.round == .trick, trickStage == .pick, phase == .stage, !s.tricksDone else { return }
        s.beginTurn(t, at: clock); sim = s
        guard sim?.ringTrick != nil else { return }
        trickStage = .ring; ringAge = 0; ringNowSaid = false; cue(.ring); A11yEvents.say(ShowAssist.ringScale > 1 ? "Ring closing slowly. Tap when you hear now" : "Ring closing. Tap when you hear now", .normal)
        revision += 1
    }
    /// The Glow Burst button.
    func armBurst() {
        guard var s = sim, s.round == .trick, s.burstReady else { return }
        s.armBurst(); sim = s
        revision += 1
    }
    /// The tap while the ring closes.
    func tapRing() {
        guard var s = sim, trickStage == .ring, phase == .stage else { return }
        guard let turn = s.tapRing(at: clock) else { return }
        sim = s
        land(turn)
    }
    private func land(_ turn: ShowTrickTurn) {
        lastTurn = turn
        trickStage = .performing; performLeft = Self.performSeconds
        cue(turn.success ? .land : .flop)
        if turn.burst { burstFlash += 1; cue(.burst); onBurst() }
        onPerform(turn.trick, turn.success)
        revision += 1
    }
    /// The ring's progress 0 (open) ... 1 (hugging him) ... past 1 (too late).
    var ringProgress: Double { trickStage == .ring ? ringAge / ShowScoring.ringSeconds : 0 }

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
        case .ring:
            ringAge += Double(dt)
            if !ringNowSaid, ringAge >= ShowScoring.ringSeconds - 0.06 { ringNowSaid = true; A11yEvents.say("Now", .high) }          // for VoiceOver: the moment the ring hugs him
            if auto || ShowAssist.autoDance, ringAge >= ShowScoring.ringSeconds - 0.04 { tapRing(); return }
            if ringAge > ShowScoring.ringSeconds + Self.ringGrace, var s = sim, let turn = s.tapRing(at: clock) { sim = s; land(turn) }          // no tap: timing 0, still a turn
        case .performing:
            performLeft -= dt
            if performLeft <= 0 {
                trickStage = .pick
                if sim?.round == .results { settle() }
                revision += 1
            }
        }
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
        A11yEvents.say("\(playerName) placed \(A11yEvents.ordinal(place)) in the show. \(earned) Drops", .high)
        onResults(place)
        revision += 1
    }

    // MARK: the Studio drill

    private func finishPractice(_ p: ShowDanceSim) {
        guard practiceResult == nil, let st = stats else { return }
        let before = st.proficiency(practiceDance)
        let spent = st.pepFactor < 1
        let gain = st.finishDancePractice(practiceDance, accuracy: p.accuracy)
        practiceResult = DancePracticeResult(dance: practiceDance, accuracy: p.accuracy, perfects: p.perfects, goods: p.goods, misses: p.misses,
                                             before: before, after: before + gain, pepLeft: st.pepLeft, pepSpent: spent)
        beat = .danced; cardAge = 0
        onDance(nil, false)
        cue(p.accuracy >= 0.5 ? .applause : .slip)
        cue(.jingle(win: p.accuracy >= 0.5))
        revision += 1
    }
    /// The Studio drill starts its countdown as soon as the stage is up.
    private func practiceStart() {
        guard kind == .practice, beat == .idle, practice == nil, practiceResult == nil else { return }
        beat = .countdown; countdown = 3; countdownLeft = Self.countdownBeat; audioWait = 0; cueSerial += 1; cue(.countdown)
        onDance(practiceDance, true)
    }

    // MARK: per fixed step

    func tick(dt: Float) {
        switch phase {
        case .off: return
        case .fade: tickFade(dt: dt); return
        case .stage: break
        }
        guard wipe == 0 else { return }
        if kind == .practice {
            practiceStart()
            tickDance(dt: dt)
            if practiceResult != nil { cardAge += dt }
            return
        }
        guard let s = sim else { return }
        switch s.round {
        case .look:
            if auto { clock += Double(dt); if clock > 2.5 { clock = 0; finishLook() } }
        case .dance:
            tickDance(dt: dt)
            if auto, beat == .danced, dancedAge > 1.5 { finishDance() }
        case .trick: tickTrick(dt: dt)
        case .results:
            if trickStage == .performing { tickTrick(dt: dt) } else { if !settled { settle() }; cardAge += dt }
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
        sim = nil; practice = nil
        onReturned(id, won, again)
        revision += 1
    }

    /// Hard stop (tests, the app leaving): everything back to the room at once.
    func abort() {
        guard phase != .off else { return }
        if cameraBlend > 0 || (swapped && fadeDest == .stage) { onSwap(.room) }
        cameraBlend = 0; wipe = 0; phase = .off; sim = nil; practice = nil; leaving = false
        onDance(nil, false)
        revision += 1
    }
}
