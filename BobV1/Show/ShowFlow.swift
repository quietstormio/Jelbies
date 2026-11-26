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
nonisolated enum ShowCue: Equatable, Sendable { case perfect, good, slip, countdown, go, ring, land, flop, burst, jingle(win: Bool) }

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
    enum RivalStep: Equatable { case playerAway, walkIn, perform, walkOut, playerBack }
    /// What the bodies are asked to do (GameCare+Show.swift): the player steps aside / back, rival `i` walks up / performs / steps back, everybody snaps home (Skip).
    enum RivalCue: Equatable { case playerAside(Bool), walkIn(Int), perform(Int, VoiceTrick, Bool), walkOut(Int), snap, enter, formLine }
    /// `formLine` (show-handover-r1): the hard backstop of a handover: every stage body that is not on its seat for the step under way is put on it, at once (the glue clears every pending walk).

    private(set) var phase: Phase = .off
    /// 0...1 white overlay opacity (the view draws it).
    private(set) var wipe: Float = 0
    /// The stage is shown instead of the room (0 / 1: snapped under the white, never blended on screen).
    @ObservationIgnored private(set) var cameraBlend: Float = 0
    /// The rules (nil when off). Not observed (the dance changes it every step); the views read `revision` and the published bits.
    @ObservationIgnored var sim: ShowSim?
    /// Bumped whenever the show moved on in a way the screens redraw for.
    private(set) var revision = 0
    /// Ranks won and trophies (saved outside tests).
    var progress = ShowProgress(persists: ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil)

    private(set) var playerID = 0
    var playerName = ""
    var character = 0
    var rank: ShowRank = .puddle
    var theme: ShowTheme = .bunnyPicnic
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
    /// Set once, the moment a dance has run 1.5 s without the song's clock and so counts frames: the reason (diagnostics; also logged under `-AudioLog 1`).
    @ObservationIgnored private(set) var danceFallback: String?
    @ObservationIgnored private var danceNoClock: Double = 0
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
    /// show-trick-tut-r1: WHERE THE PLAYER GOES IN EACH TURN. The turn's entrants (`turnQueue`) are `preCount(turn:)` before him and the rest after (so he sometimes goes first, sometimes last). `rivalPre`: the
    /// entrants on the stage now are the ones BEFORE his go (his Jelmiko walks back after them, to a go of the SAME turn, not the next); `preTurnDone`: the turn whose "before" part is handled. Off = he always goes first (tests).
    private(set) var rivalPre = false
    @ObservationIgnored private var preTurnDone = -1
    @ObservationIgnored var randomTurnOrder = true
    /// HOW MANY OTHER ENTRANTS PERFORM ON STAGE AFTER EACH OF THE PLAYER'S TRICKS: the one place to change it (1 = one entrant per turn, in a fixed order: entrant k on turn k;
    /// 3 = all three every turn: 2026-11-17, the owner: "my Jelmiko went three times and the other three went once, they should all go during a round"). Every entrant's three tricks
    /// are rolled and scored whatever this is (ShowSim.rollRivalTurns), so the Results totals do not depend on it. `entrantsPerTurn` of a flow is this unless a test sets it.
    static let entrantsPerTurn = 3
    @ObservationIgnored var entrantsPerTurn = ShowFlow.entrantsPerTurn
    /// An entrant's trick is shown for at most this long on the stage (a highlight: the long ones, a 7 s moonwalk, are cut at it; her points are the same), so three entrants take about 12 s.
    static let rivalPerformCap: Float = 1.6
    /// The entrants that have performed in the turn under way (their points are on the scoreboard strip).
    private(set) var rivalPerformed: Set<Int> = []
    /// The Trick round opens with the entrants walking on from the wing (the wide shot); `entranceDone` ends it and the camera moves in on the contestant for "pick a trick".
    @ObservationIgnored private var entranceStarted = false
    @ObservationIgnored private var entranceDone = false
    @ObservationIgnored private var entranceT: Float = 0
    @ObservationIgnored private var entranceTapT: Float = 0
    @ObservationIgnored private var entrancePick: VoiceTrick?
    /// The entrants are walking on (the wide camera shot, the contestant's menu already usable).
    var trickEntering: Bool { sim?.round == .trick && phase == .stage && !entranceDone }
    @ObservationIgnored private var rivalT: Float = 0
    @ObservationIgnored private var performLeft: Float = 0
    /// The Glow Burst fired on the last turn (the view throws confetti).
    private(set) var burstFlash = 0

    // results
    var earned = 0
    var awards: ShowProgress.Awards?
    @ObservationIgnored private(set) var settled = false
    /// The player went home in the middle (Race/ForfeitHome.swift): nothing is settled and the trip is not a win.
    @ObservationIgnored private(set) var forfeited = false
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
    /// A press of the L (0) / R (1) button during the dance, before it is judged: his foot on that side steps.
    @ObservationIgnored var onTap: (Int) -> Void = { _ in }
    @ObservationIgnored var onResults: (Int) -> Void = { _ in }
    /// A cup placing (1...3) was settled for this character at this rank (the trophy plate's date: Trophies/TrophyBook.swift).
    @ObservationIgnored var onCup: (Int, ShowRank, Int) -> Void = { _, _, _ in }
    @ObservationIgnored var onBurst: () -> Void = {}
    /// The rivals' turn on the stage (bodies) and whether a body has got where it was sent (`who` nil = the player's Jelbie; `atCentre`: at the middle, else at his rest / aside spot).
    @ObservationIgnored var onRival: (RivalCue) -> Void = { _ in }
    @ObservationIgnored var rivalReady: (_ who: Int?, _ atCentre: Bool) -> Bool = { _, _ in true }
    /// The walk to the middle has used up its own allowance (its length at the stage pace + 1.5 s, counted on the body by the glue): the turn goes on with her where she stands.
    @ObservationIgnored var rivalGiveUp: (_ who: Int?) -> Bool = { _ in false }
    /// Everybody who has a seat stands in it (the glue's line keeper): an entrant performs, and his go opens, only with the line formed (show-line-r1). Always true without a stage (the pure-flow tests).
    @ObservationIgnored var lineFormed: () -> Bool = { true }
    /// Money (the care glue sets it).
    @ObservationIgnored var wallet: DropsWallet?
    @ObservationIgnored var cue: (ShowCue) -> Void = { AudioHub.shared.showCue($0) }
    /// The audio clock of the stage / studio music (song seconds), nil = not playing (muted, still decoding): the dance then counts frames.
    @ObservationIgnored var songClock: (SceneTrack) -> Double? = { AudioHub.shared.songTime(of: $0) }
    /// Why `songClock` is nil for a track (the log line and `danceFallback`).
    @ObservationIgnored var songClockWhy: (SceneTrack) -> String = { AudioHub.shared.songClockWhy(of: $0) }
    /// The music is up (muted = nothing to wait for).
    @ObservationIgnored var audioReady: (MusicScene) -> Bool = { AudioHub.shared.muted || AudioHub.shared.scenePlaying($0) }
    /// Test / capture aid: the dance is tapped for him (a few late, one missed) and the tricks are picked for him.
    @ObservationIgnored var auto = false
    /// Capture aid (`-ShowHomeAfter s`, with `-ShowAuto`): the auto player presses Done this many seconds after the Results card is up (nil = never).
    @ObservationIgnored var autoHomeAfter: Float?
    /// show-soak-r1 (dev arguments only, off by default; Dev/ShowSoakProbe.swift): the dance is played for him (the tricks are NOT), and / or cut short this many song seconds in (the soak's fast lane).
    @ObservationIgnored var soakAutoDance = false
    @ObservationIgnored var soakFastDance: Double?
    var soakPreTurnDone: Int { preTurnDone }
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
    /// "GO!" in the lane: while the DANCE CLOCK (the song's own time, the one the chips run on) is under `goWordSeconds`, never longer than 2 s on the wall clock. Tied to the song clock
    /// so a slow frame can never leave the word up while the first step arrives (the first prompt is at beat 4; the chip reaches the word's area at about 0.66 s on the fastest song in landscape).
    var showsGo: Bool { phase == .stage && beat == .dancing && danceT < Self.goWordSeconds && goAge < 2.0 }
    static let goWordSeconds: Double = 0.5
    /// The foot buttons are live.
    var buttonsLive: Bool { phase == .stage && beat == .dancing && wipe == 0 && !(sim?.danceDone ?? false) }
    var hasResults: Bool { sim?.round == .results && trickStage == .pick }
    /// Is turn `k` (0...2) of the Trick round the one being played right now, by anyone: his go, his result showing, the entrant on stage, or (the last entrant back) his next go.
    /// The ONE source for the turn pills and the header pips (the pips never keep a counter of their own).
    func isTrickTurnNow(_ k: Int) -> Bool {
        guard let s = sim, k >= 0, k < 3 else { return false }
        let done = s.turns.count
        let playerBack = trickStage == .rivals && rivalStep == .playerBack
        let entrantNow = trickStage == .rivals && rivalRound == k && !playerBack
        let nextGo = playerBack && k == rivalRound + (rivalPre ? 0 : 1)
        return entrantNow || nextGo || (trickStage == .performing && k == done - 1) || (trickStage == .pick && !s.tricksDone && k == done && !prePending)
    }
    /// The entrants of turn `k` (the ones who perform on it, in a fixed order: all of them, or `entrantsPerTurn` of them).
    func turnQueue(_ k: Int) -> [Int] {
        guard let s = sim else { return [] }
        let n = s.rivals.count, per = min(max(entrantsPerTurn, 1), n)
        guard n > 0 else { return [] }
        return per >= n ? Array(s.rivals.indices) : (0..<per).map { (k * per + $0) % n }          // (one per turn: entrant k on turn k)
    }
    /// How many of turn `k`'s entrants go BEFORE the player: 0...all, from the show's seed and the turn alone (its own generator: the player's slip rolls are never touched), so a replay of the seed is the same.
    func preCount(turn k: Int) -> Int {
        guard randomTurnOrder, let s = sim, !s.rivals.isEmpty else { return 0 }
        let q = turnQueue(k).count
        var g = RaceRNG(seed: s.seed &* 0x9E3779B97F4A7C15 &+ UInt64(k + 1) &* 0xD1B54A32D192ED03 &+ 0x7A11)
        _ = g.next()
        return min(Int(g.next() * Float(q + 1)), q)
    }
    /// The Trick round is at a turn whose entrants-before are still to go (so it is not his go yet: the menu is dim, the pill does not say "Your go").
    var prePending: Bool {
        guard let s = sim, s.round == .trick, !s.tricksDone, phase == .stage, trickStage == .pick, preTurnDone != s.turns.count else { return false }
        return preCount(turn: s.turns.count) > 0
    }
    /// show-trick-tut-r1 (the owner: "as competitors walk out add a tutorial screen that says like pick a move"): the small "Pick a move" card over the Trick round's first seconds (the walk-out, and any entrants who go
    /// before him on turn 1), until his first go starts or a tap on it. Shown on every visit until he has picked a move once (that flag is stored under `trickTutorialKey`, the way the Volley's one-time hint is).
    static let trickTutorialKey = "show.hint.pickMove"
    @ObservationIgnored var tutorialDefaults: UserDefaults = .standard
    private(set) var tutorialDismissed = false
    var trickTutorialUp: Bool {
        guard let s = sim, s.round == .trick, phase == .stage, s.turns.isEmpty, !tutorialDismissed, !tutorialDefaults.bool(forKey: Self.trickTutorialKey) else { return false }
        return trickEntering || prePending || (trickStage == .rivals && rivalPre)
    }
    func dismissTrickTutorial() { tutorialDismissed = true; revision += 1 }
    /// The walk-out lasts at least this long while the card is up (so it can be read).
    static let tutorialMin: Float = 3.0
    /// The trick menu takes taps: his go, the round not over, no entrant still to go before him.
    var pickLive: Bool { trickStage == .pick && !(sim?.tricksDone ?? true) && !prePending }
    /// The turn being played now (0...2), nil when none is (the round is over, or a pause between turns).
    var trickTurnNow: Int? { (0..<3).first { isTrickTurnNow($0) } }
    /// The rival under the lights and what she shows this turn (her name, trick, stars and points come from this).
    var rivalNow: (rival: Int, turn: ShowTrickTurn)? {
        guard trickStage == .rivals, let i = rivalTurn, let s = sim, s.rivalTurns.indices.contains(i), s.rivalTurns[i].indices.contains(rivalRound) else { return nil }
        return (i, s.rivalTurns[i][rivalRound])
    }
    /// How many of rival `i`'s turns have been SHOWN on the stage (or settled by Skip): the scoreboard strip counts only those, so it never gives away the turn about to be shown.
    func rivalShownTurns(_ i: Int) -> Int {
        guard let s = sim else { return 0 }
        switch trickStage {
        case .pick: return min(s.turns.count + (rivalPerformed.contains(i) ? 1 : 0), s.rivalTurns.indices.contains(i) ? s.rivalTurns[i].count : 0)          // (an entrant who went before him this turn has shown it)
        case .performing: return max(s.turns.count - 1, 0) + (rivalPerformed.contains(i) ? 1 : 0)
        case .rivals: return rivalRound + (rivalPerformed.contains(i) ? 1 : 0)
        }
    }
    /// The Trick points of rival `i` shown so far (the Results' Trick score once all three are shown: ShowSim.rivalScores).
    func rivalTrickPoints(_ i: Int) -> Int {
        guard let s = sim, s.rivalTurns.indices.contains(i) else { return 0 }
        return min(100, s.rivalTurns[i].prefix(rivalShownTurns(i)).reduce(0) { $0 + $1.points })
    }
    /// The player's Trick points so far (his own turns are shown as he takes them; the Burst included).
    var playerTrickPoints: Int { sim?.trickTotal ?? 0 }
    /// Her points are on the screen (she has performed).
    var rivalScored: Bool { rivalStep == .perform || rivalStep == .walkOut }
    /// The scene track the stage plays now.
    var track: SceneTrack { .contestStage }
    /// The dance song's track (plays once under the dance) and its measured beat grid.
    var danceTrack: SceneTrack { danceSong.track }
    var grid: ShowBeat { danceSong.grid }
    /// The prompt pattern of this show's dance (by rank; `-DancePattern` forces one in dev builds).
    var dancePattern: DancePattern { DancePattern.resolve(rank: rank) }
    /// Capture aid (dev builds): `-ShowDoneHold <s>` keeps the auto player on the score card that long (default 1.5 s).
    /// Capture aid (dev builds): `-ShowPickHold <s>` keeps the Trick menu open that long (default 1.2 s) before the auto player picks.
    static var autoPickAfter: Float { DevArgs.enabled ? max(1.2, Float(UserDefaults.standard.double(forKey: "ShowPickHold"))) : 1.2 }
    static var autoDoneHold: Float { DevArgs.enabled ? max(1.5, Float(UserDefaults.standard.double(forKey: "ShowDoneHold"))) : 1.5 }
    /// The cheer word of the score card after the song.
    static func danceCheerWord(score: Float) -> String { score >= 80 ? "Great dancing!" : score >= 50 ? "Nice moves!" : "Good try!" }
    /// Seconds in the dance song's file (44.1 kHz), else the last prompt plus the ring-out.
    @ObservationIgnored private var lengthCache: [Int: Double] = [:]
    var danceLength: Double {
        if let c = lengthCache[danceSong.song] { return c }
        let v = SceneRender.fileLength(danceTrack).map { Double($0) / 44100 } ?? (danceSong.time(ofSlot: 2 * danceSong.lastBeat) + DanceSong.ringOut)
        lengthCache[danceSong.song] = v
        return v
    }
    /// 0...1: how far into the dance song (the thin progress line under the lane).
    var danceProgress: Double { beat == .danced ? 1 : (beat == .dancing ? min(max(danceNow() / max(danceLength, 1), 0), 1) : 0) }
    /// How many prompts the dance has (the chip's "y"): the running dance's count, else the count this show's pattern will have.
    var dancePromptTotal: Int { sim?.dance?.total ?? danceSong.promptCount(dancePattern) }
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
        case .look: return .look(pad: PadLayout.isPad)
        case .dance: return .dance(bodies: bodies, pad: PadLayout.isPad)
        case .trick: return .trick(pad: PadLayout.isPad)          // (one frame for the whole round: the performer big, the others behind it)
        case .results: return trickStage == .pick ? .results(pad: PadLayout.isPad) : .trick(pad: PadLayout.isPad)          // (the rivals' last turn still plays on the trick frame)
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
        danceT = 0; danceMusicOn = false; danceHeard = false; danceAudioWait = 0; danceFallback = nil; danceNoClock = 0
        trickStage = .pick; clock = 0; lastTurn = nil; performLeft = 0; burstFlash = 0
        tutorialDismissed = false; entranceStarted = false; entranceDone = false; entranceT = 0; entranceTapT = 0; entrancePick = nil
        rivalTurn = nil; rivalStep = .walkIn; rivalRound = 0; rivalQueue = []; rivalT = 0; rivalPre = false; preTurnDone = -1; rivalPerformed = []
        earned = 0; awards = nil; settled = false; forfeited = false; cardAge = 0; againWanted = false
        autoDone = 0; autoTrickWait = 0; danceCued = 0
        ShowAssist.refresh()
    }

    /// A forfeit can be asked: the stage is up and live, before the results.
    var canForfeit: Bool { phase == .stage && wipe == 0 && cameraBlend > 0 && round != .results && !leaving && !forfeited }
    /// The sim clock can stand still behind the card (everything but the dance, which follows the song's own audio clock).
    var canPause: Bool { !(round == .dance && beat == .dancing) }

    /// "Go home" in the middle of the show: the usual fade home with no settlement (no Drops, ribbon, trophy or stats) and no win.
    func forfeit() {
        guard canForfeit else { return }
        forfeited = true; settled = true; leaving = true; againWanted = false
        onDance(nil, false)
        phase = .fade; fadeDest = .room; fadeStage = .out; holdT = 0; swapped = false
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
                        danceT = 0; danceMusicOn = true; danceHeard = false; danceAudioWait = 0; danceFallback = nil; danceNoClock = 0
                        s.beginDance(song: danceSong, songTime: 0); sim = s
                        if AudioHub.audioLog, let d = s.dance { NSLog("[melon] dance start song=%d \"%@\" pattern=%@ bpm=%.2f firstBeat=%.4f prompts=%d %.3f..%.3f s", danceSong.song, danceSong.title, dancePattern.rawValue, danceSong.bpm, danceSong.grid.firstBeat, d.total, d.prompts.first?.time ?? 0, d.prompts.last?.time ?? 0) }
                    }
                    revision += 1
                }
            }
        case .dancing:
            flashAge += dt; goAge += dt
            if flashAge > 0.7, flash != nil { flash = nil }
            now = danceClock(dt: dt)
            if let f = soakFastDance, danceT > f, !(sim?.danceDone ?? false) { beat = .danced; dancedAge = 0; danceMusicOn = false; revision += 1; return }
            if auto || soakAutoDance || ShowAssist.autoDance { autoPlay(now) }
            promptCues(now: now)
            guard var s = sim else { return }
            let ev = s.tickDance(songTime: now)
            sim = s
            handle(ev)
            if s.danceDone { beat = .danced; dancedAge = 0; danceMusicOn = false; revision += 1 }          // (the stage loop comes back)
        }
    }

    /// The dance clock, advanced once per tick: the song's OWN playback time from the audio engine (player sample time minus output latency), so the prompts
    /// stay with the music however the frames drop. Held at 0 while the song decodes; frame counted only when there is no audio clock (muted, tests, a failed decode).
    private func danceClock(dt: Float) -> Double {
        if let a = songClock(danceTrack) {
            if !danceHeard, AudioHub.audioLog { NSLog("[melon] dance song heard: clock %.3f s (output latency %.0f ms)", a, AudioHub.shared.outputLatencyMS) }
            danceHeard = true; danceT = max(danceT, a); return danceT
        }
        if !danceHeard, !audioReady(.danceSong(danceSong.song - 1)), danceAudioWait < 1.5 { danceAudioWait += dt; danceNoClock += Double(dt); return danceT }          // decoding: the prompts wait
        if !danceHeard {
            danceNoClock += Double(dt)
            if danceNoClock >= 1.5, danceFallback == nil {          // the song's clock never came: say so (the phone build used to go quiet here)
                let why = songClockWhy(danceTrack) + (audioReady(.danceSong(danceSong.song - 1)) ? "" : "; scene voice not playing")
                danceFallback = why
                if AudioHub.audioLog { NSLog("[melon] dance song NOT heard after %.2f s: %@", danceNoClock, why) }
            }
        }
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
        onTap(foot)
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
            onTap(p.foot)
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
        if trickEntering { if preCount(turn: 0) > 0 { return }; entrancePick = t; return }          // (a rival goes first this turn: not his go yet)
        guard !prePending else { return }          // (a tap during the walk-on: the walk-on ends within a second, then he performs it)
        guard let turn = s.perform(t) else { return }
        sim = s
        tutorialDefaults.set(true, forKey: Self.trickTutorialKey)          // (he has picked a move: the card is never shown again)
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
        trickStage = .performing; performLeft = ShowTrickInfo.seconds(turn.trick)
        cue(turn.success ? .land : .flop)
        if turn.burst { burstFlash += 1; cue(.burst); onBurst() }
        onPerform(turn.trick, turn.success)
        revision += 1
    }
    private func tickTrick(dt: Float) {
        clock += Double(dt)
        if trickEntering { tickEntrance(dt: dt); return }
        switch trickStage {
        case .pick:
            if let s = sim, s.round == .trick, !s.tricksDone, preTurnDone != s.turns.count {          // a new turn: the entrants before him go first (when the draw puts any there)
                preTurnDone = s.turns.count
                if !s.rivals.isEmpty, preCount(turn: s.turns.count) > 0 { startRivals(pre: true); return }
            }
            if auto, let s = sim, !s.tricksDone {
                autoTrickWait += dt
                if autoTrickWait > Self.autoPickAfter {
                    let t = s.knownTricks.first(where: { !s.usedTricks.contains($0) }) ?? s.knownTricks.first ?? .sit
                    autoTrickWait = 0
                    if s.burstReady { armBurst() }
                    pick(t)
                }
            }
        case .performing:
            performLeft -= dt
            if performLeft <= 0 {
                if let s = sim, !s.rivals.isEmpty { startRivals(pre: false) }
                else { trickStage = .pick; if sim?.round == .results { settle() }; revision += 1 }
            }
        case .rivals: tickRivals(dt: dt)
        }
    }

    // MARK: the entrants' walk-on

    /// The Trick round's first seconds: the camera shows the whole stage, the entrants walk on from the wing to their rest spots (the walk they use to come to the middle),
    /// about two seconds; then the camera moves in on the contestant. A trick tapped meanwhile ends it within a second (a walker still on the way is put at its spot).
    private func tickEntrance(dt: Float) {
        guard let s = sim else { return }
        if !entranceStarted { entranceStarted = true; entranceT = 0; entranceTapT = 0; onRival(.enter); revision += 1; return }
        entranceT += dt
        if entrancePick != nil { entranceTapT += dt }
        let arrived = s.rivals.indices.allSatisfy { rivalReady($0, false) }
        if entranceT >= (trickTutorialUp ? Self.tutorialMin : Self.entranceMin) && arrived && (lineFormed() || entranceT > Self.entranceMax - 1) || entranceT > Self.entranceMax || (entrancePick != nil && entranceTapT >= 1.0) {
            if !arrived { onRival(.snap) }
            entranceDone = true
            revision += 1
            if let t = entrancePick { entrancePick = nil; pick(t) }
        }
    }
    static let entranceMin: Float = 1.2, entranceMax: Float = 5.5

    // MARK: the rivals' turns

    /// The player's trick is over: each rival in turn walks up to the middle, shows the trick she rolled for this turn and steps back (his Jelbie waits aside).
    private func startRivals(pre: Bool) {
        guard var s = sim else { return }
        rivalRound = pre ? s.turns.count : max(s.turns.count - 1, 0)
        let q = turnQueue(rivalRound), p = min(preCount(turn: rivalRound), q.count)
        rivalQueue = pre ? Array(q.prefix(p)) : Array(q.dropFirst(p))
        if pre { s.rollRivalTurns(turn: rivalRound); sim = s; rivalPerformed = [] }          // (an entrant's turn is rolled the moment it is needed: it never depends on the player's, so the totals are the same whoever goes first)
        rivalPre = pre
        trickStage = .rivals
        rivalTurn = nil; rivalStep = .playerAway; rivalT = 0
        onRival(.playerAside(true))          // (he steps back first; the first entrant sets off once he is clear of the middle)
        revision += 1
    }
    private func nextRival() {
        rivalT = 0
        if rivalQueue.isEmpty, !rivalPre, let s = sim, s.round == .trick, !s.tricksDone, !s.rivals.isEmpty, preCount(turn: s.turns.count) > 0 {          // the next turn opens with entrants: they follow at once (his Jelmiko stays aside: no walk back and out again)
            var s2 = s
            rivalRound = s.turns.count; preTurnDone = s.turns.count; rivalPre = true; rivalPerformed = []
            s2.rollRivalTurns(turn: rivalRound); sim = s2
            rivalQueue = Array(turnQueue(rivalRound).prefix(min(preCount(turn: rivalRound), turnQueue(rivalRound).count)))
        }
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
        case .playerAway:
            guard rivalT >= 0.3, rivalReady(nil, false) || rivalT > 0.9 else { return }
            nextRival()
        case .walkIn:
            guard let i = rivalTurn, rivalT >= 0.3, rivalReady(i, true) || rivalGiveUp(i) || rivalT > Self.walkInCap, lineFormed() || rivalT > Self.lineCap else { return }          // (the turn WAITS for her to arrive: no teleport; past the cap the line is formed by hand and she performs)
            if rivalT > Self.walkInCap, !rivalReady(i, true) || !lineFormed() { onRival(.formLine) }
            startRivalPerform(i)
        case .perform:
            guard let i = rivalTurn, rivalT >= Self.rivalSeconds(rivalNow?.turn.trick ?? .sit) else { return }
            rivalStep = .walkOut; rivalT = 0; onRival(.walkOut(i)); revision += 1
        case .walkOut:
            guard rivalT >= 0.25, rivalT >= 0.55 || (rivalTurn.map { rivalReady($0, false) } ?? true) else { return }          // (the next entrant sets off while she is still stepping back: they leave and arrive on opposite sides)
            nextRival()
        case .playerBack:
            guard rivalT >= 0.3, (rivalReady(nil, true) || rivalGiveUp(nil)) && lineFormed() || rivalT > Self.playerBackCap else { return }          // (past the cap the line is formed by hand: "Your go" never waits on a body that cannot get there)
            if rivalT > Self.playerBackCap, !(rivalReady(nil, true) && lineFormed()) { onRival(.formLine) }
            endRivals()
        }
    }
    /// How long the turn waits for an entrant to reach the middle (was 3.5 s, and she was put there when it ran out), and for his Jelmiko to come back (was 3 s): 2.5 s more each.
    /// The most a turn waits for the line to form (the keeper carries any body to its seat within ~3.5 s, so this is a safety net that is never meant to be reached).
    static let lineCap: Float = 10.0
    static let walkInCap: Float = 10.0, playerBackCap: Float = 8.0          // (hard ceilings only: each walk has its own allowance, `rivalGiveUp`)
    /// The entrant who is up after the one performing now (for the glue to start a far one walking early), nil at the end of the turn.
    var nextRivalUp: Int? { rivalQueue.first }
    /// The spotlight's state changed: the screens redraw (the light layer subscribes to `revision`).
    func nudge() { revision += 1 }
    static func rivalSeconds(_ t: VoiceTrick) -> Float { min(ShowTrickInfo.seconds(t), rivalPerformCap) }
    private func startRivalPerform(_ i: Int) {
        guard let n = rivalNow else { return }
        rivalStep = .perform; rivalT = 0
        rivalPerformed.insert(i)
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
        if !rivalPre { rivalPerformed = [] }
        rivalPre = false
        trickStage = .pick; rivalTurn = nil; rivalQueue = []; rivalT = 0
        if sim?.round == .results { settle() }
        revision += 1
    }
    /// "Skip": the rest of the rivals' tricks of this turn are settled (their points already count), the bodies snap to their spots and it is his turn.
    func skipRivals() {
        guard trickStage == .rivals else { return }
        onRival(.snap)
        A11yEvents.say("Skipped", .normal)
        if rivalPre { rivalPerformed.formUnion(turnQueue(rivalRound).prefix(preCount(turn: rivalRound))) }          // (the entrants before him are settled by Skip: their points count)
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
        if place <= 3 { onCup(character, s.rank, place) }
        cardAge = 0
        cue(.jingle(win: place <= 2))
        A11yEvents.say("\(playerName) placed \(A11yEvents.ordinal(place)) in the Jelly Show. \(earned) JellyCoins", .high)
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
            if auto, beat == .danced, dancedAge > Self.autoDoneHold { finishDance() }
        case .trick: tickTrick(dt: dt)
        case .results:
            if trickStage != .pick { tickTrick(dt: dt) } else { if !settled { settle() }; cardAge += dt; if auto, let h = autoHomeAfter, cardAge >= h { goHome() } }          // (the last turn's rivals still perform after the sim has its results)
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
        let won = !forfeited && (sim?.playerWon ?? false)
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
