//
//  RaceFlow.swift
//  The Race button's whole trip, as one state machine (no bodies of its own; GameCare+Race.swift wires it to the Jellies):
//
//      off -> fade to white -> [swap to the track] -> fade in -> 3-2-1-GO -> race -> finish -> placings card
//          -> (Back home) fade to white -> [swap to the room] -> fade in -> off, and the welcome home starts.
//
//  The swaps happen only while the white is fully opaque (like the clean-up). The race itself is `RaceSim`; this class adds the transition,
//  the cues (countdown beeps, GO, finish), and the one-time settlement at the placings: Drops into the wallet and the waddle growth.
//

import Foundation
import Observation
import simd

@MainActor
@Observable
final class RaceFlow {
    enum Phase: Equatable { case off, fade, racing }
    /// A race against rivals, or a practice drill alone on the track (Training/DrillFlow.swift).
    enum Kind { case race, drill }
    enum Dest { case track, room }
    enum FadeStage { case out, hold, `in` }

    private(set) var phase: Phase = .off
    private(set) var kind: Kind = .race
    /// The course the next race is on (Race/RaceCourse.swift). The Track panel's picker sets it; `progress` says which are open.
    var courseTier: CourseTier {
        get { progress.chosen }
        set { progress.chosen = newValue }
    }
    /// What has been won on each course, the unlocks, and the chosen course (saved outside tests).
    var progress = CourseProgress(persists: ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil)
    /// The course of the race under way (the chosen one when none is).
    var course: RaceCourse { sim?.course ?? RaceCourse.course(courseTier) }
    /// 0...1 white overlay opacity (the view draws it).
    private(set) var wipe: Float = 0
    /// The track is shown instead of the room (0 / 1: snapped under the white, never blended on screen).
    @ObservationIgnored private(set) var cameraBlend: Float = 0
    /// The race (nil when off). Not observed (it changes every step); the view reads `ui`.
    @ObservationIgnored var sim: RaceSim?
    /// What the view needs of the race, republished only when it changes.
    private(set) var ui = RaceUI()
    /// Bumped on every countdown number / GO / finish so the view can animate each (the numbers themselves are in `sim`).
    var cueSerial = 0
    /// Seconds the placings card has been up.
    var cardAge: Float = 0
    /// What the player earned and gained, once settled.
    private(set) var earned = 0
    var waddleGain: Float = 0
    /// A course this race opened (the placings card says so), nil when none.
    private(set) var unlockedNow: CourseTier?
    /// Rivals of this race (names / tints / stats), for the lane labels and the body colours.
    private(set) var rivals: [Rival] = []
    private(set) var playerName = ""
    private(set) var playerID = 0
    /// How many races have been started (tests).
    private(set) var started = 0
    // the practice drill (Training/DrillFlow.swift)
    @ObservationIgnored var drill: DrillSim?
    var drillUI = DrillUI()
    var drillResult: DrillResult?
    /// 0...1 white dip between laps (the view draws it over the track).
    var dip: Float = 0
    @ObservationIgnored var drillState = DrillRun()
    @ObservationIgnored var drillCue: (DrillCue) -> Void = { AudioHub.shared.drillCue($0) }
    /// The audio clock of the training music (song seconds), nil = not playing (muted, still decoding): the drill then counts frames.
    @ObservationIgnored var songClock: () -> Double? = { AudioHub.shared.trainingSongTime() }
    /// The training music is up (muted = nothing to wait for).
    @ObservationIgnored var audioReady: () -> Bool = { AudioHub.shared.muted || AudioHub.shared.scenePlaying(.training) }
    /// The body goes back to the start line for the next lap (called with the dip fully white).
    @ObservationIgnored var onLapReset: () -> Void = {}
    /// -TrainAuto: the drill is tapped for him (captures / tests).
    @ObservationIgnored var drillAuto = false

    @ObservationIgnored private(set) var fadeDest: Dest = .track
    @ObservationIgnored private(set) var fadeStage: FadeStage = .out
    @ObservationIgnored var holdT: Float = 0
    @ObservationIgnored var swapped = false
    @ObservationIgnored var settled = false
    @ObservationIgnored private(set) var swapLog: [(wipe: Float, dest: Dest)] = []
    @ObservationIgnored var leaving = false
    @ObservationIgnored var introT: Float = 0

    /// Where the world swaps happen (GameCare+Race.swift): called with the white opaque.
    @ObservationIgnored var onSwap: (Dest) -> Void = { _ in }
    /// The trip is over and the room is back (`won`: the player placed first): the welcome home.
    @ObservationIgnored var onReturned: (_ playerID: Int, _ won: Bool) -> Void = { _, _ in }
    /// A drill used up the day's last Pep (`playerID`): the Pep Live Activity (GameCare+Race wires it).
    @ObservationIgnored var onPepDepleted: (_ playerID: Int) -> Void = { _ in }
    /// Money and stats: set by the care glue (the wallet and the player's JellyStats).
    @ObservationIgnored var wallet: DropsWallet?
    @ObservationIgnored var stats: JellyStats?
    /// The cue hooks (AudioHub names; tests count them).
    @ObservationIgnored var cue: (RaceCue) -> Void = { AudioHub.shared.raceCue($0) }

    // capture / test aids
    /// -RaceAuto <taps per second>: the player's two buttons are tapped for him, alternately, at that rate.
    @ObservationIgnored var autoRate: Float?
    @ObservationIgnored var autoT: Float = 0
    @ObservationIgnored private var autoFoot = 0
    /// -RaceAuto also sends him home by himself this long after the card appears.
    @ObservationIgnored var autoReturnAfter: Float?
    @ObservationIgnored var rivalSource: RivalSource = LocalRivalSource()
    /// Seconds of white (fade out / hold / fade in).
    static let fadeOut: Float = 0.45, fadeHold: Float = 0.25, fadeIn: Float = 0.5
    /// Seconds he stands on the track before the numbers start.
    static let introPause: Float = 0.5

    init() {}
    nonisolated deinit {}

    // MARK: queries

    var active: Bool { phase != .off }
    /// The track is on screen (or about to be): the renderer draws it and the HUD is the race's.
    var trackVisible: Bool { cameraBlend > 0 }
    var racing: Bool { phase == .racing && wipe == 0 }
    var isDrill: Bool { kind == .drill }
    /// Drops this trip has paid (a drill pays none).
    var earnedDropsForTest: Int { earned }
    /// The foot buttons are live.
    var buttonsLive: Bool { racing && ui.live }
    var showsCountdown: Bool { phase == .racing && ui.phase == .countdown && cameraBlend > 0 }
    var showsGo: Bool { phase == .racing && ui.go }
    var showsCard: Bool { phase == .racing && ui.phase == .results && !leaving && cameraBlend > 0 }
    /// The race has results (the card is up or the way home has started).
    var hasResults: Bool { kind == .drill ? drillResult != nil : sim?.phase == .results }

    /// What the track screens play (Audio/SceneMusic.swift): the race music, the final stretch near the line, the training loop; silence at the results
    /// (a jingle plays) and on the way home.
    var musicScene: MusicScene {
        guard phase != .off, cameraBlend > 0, !(phase == .fade && fadeDest == .room) else { return .none }
        if kind == .drill { return drillResult != nil ? .results : .training }
        guard let s = sim else { return .none }
        if s.phase == .results || s.racers[0].finished { return .results }
        if s.phase == .countdown { return .race }
        return s.racers.map(\.dist).max().map { $0 >= s.course.length - RaceTuning.finalStretch } == true ? .raceFinal : .race
    }

    // MARK: start

    /// "Race": player `id` goes to the track with `rivals` (made by the rival source) on `course` (the chosen one by default; a locked one falls back
    /// to the Puddle). Ignored while a trip is running.
    func begin(playerID id: Int, name: String, player: RacerStats, playerTint: SIMD3<Float>, rivalCount: Int, seed: UInt64, boost: RaceBoost = .none, course tier: CourseTier? = nil) {
        guard phase == .off else { return }
        var t = tier ?? courseTier
        if !progress.unlocked(t) { t = .puddle }
        let rs = rivalSource.rivals(count: rivalCount, player: player, playerTint: playerTint, seed: seed, tier: t)
        kind = .race; drill = nil; drillResult = nil; drillUI = DrillUI(); dip = 0
        rivals = rs; playerName = name; playerID = id
        sim = RaceSim(player: player, playerName: name, rivals: rs, seed: seed, playerBoost: boost, course: RaceCourse.course(t))
        ui = RaceUI()
        phase = .fade; fadeDest = .track; fadeStage = .out; holdT = 0; swapped = false; leaving = false
        settled = false; earned = 0; waddleGain = 0; cardAge = 0; introT = 0; cueSerial = 0; autoT = 0; autoFoot = 0; unlockedNow = nil
        started += 1
    }

    /// "Train": Jelly `id` practises alone on the track (Rhythm Steps), always on the Puddle's straight. Ignored while a trip is running.
    func beginDrill(playerID id: Int, name: String, player: RacerStats, seed: UInt64) {
        guard phase == .off else { return }
        kind = .drill; drill = nil; drillResult = nil; drillUI = DrillUI(); drillState = DrillRun(); dip = 0
        rivals = []; playerName = name; playerID = id
        sim = RaceSim(player: player, playerName: name, rivals: [], seed: seed)
        ui = RaceUI()
        phase = .fade; fadeDest = .track; fadeStage = .out; holdT = 0; swapped = false; leaving = false
        settled = false; earned = 0; waddleGain = 0; cardAge = 0; introT = 0; cueSerial = 0; autoT = 0; autoFoot = 0
        drillState.song = TrainingTuning.loopStart
        started += 1
    }

    /// "Back home" on the placings card.
    func goHome() {
        guard phase == .racing, hasResults, !leaving else { return }
        leaving = true
        phase = .fade; fadeDest = .room; fadeStage = .out; holdT = 0; swapped = false
    }

    /// The X on the drill: leaves without settling (no gain, no Pep used).
    func quitDrill() {
        guard kind == .drill, phase == .racing, !leaving else { return }
        leaving = true
        phase = .fade; fadeDest = .room; fadeStage = .out; holdT = 0; swapped = false
    }

    /// A tap of the player's foot button (0 left, 1 right).
    @discardableResult
    func tap(foot: Int) -> RaceTapModel.Outcome {
        if kind == .drill { drillTap(foot: foot); return .ignored }
        guard buttonsLive else { return .ignored }
        let o = sim?.playerTap(foot: foot) ?? .ignored
        refreshUI()
        return o
    }

    /// The body's measured progress for racer `i` (units from the start line).
    func setMeasured(_ i: Int, dist: Float) { sim?.setMeasured(i, dist: dist) }

    // MARK: per fixed step

    /// Advances the trip; returns the race events of this step for the glue to put on the bodies. `bodyFree(i)` / `bodyReady(i)`: see RaceSim.tick.
    func tick(dt: Float, bodyFree: (Int) -> Bool, bodyReady: (Int) -> Bool, bodyBetween: (Int) -> Bool = { _ in true }) -> [RaceEvent] {
        switch phase {
        case .off: return []
        case .fade: tickFade(dt: dt); return []
        case .racing: break
        }
        guard sim != nil, wipe == 0 else { return [] }
        if kind == .drill { return tickDrill(dt: dt) }
        if sim!.phase == .countdown, introT < Self.introPause { introT += dt; return [] }
        if let r = autoRate, buttonsLive {
            autoT += dt
            while autoT >= 1 / max(r, 0.1) { autoT -= 1 / max(r, 0.1); _ = tap(foot: autoFoot); autoFoot = 1 - autoFoot }
        }
        sim!.tick(dt: dt, bodyFree: bodyFree, bodyReady: bodyReady, bodyBetween: bodyBetween)
        let ev = sim!.takeEvents()
        for e in ev { handle(e) }
        if sim!.phase == .results {
            cardAge += dt
            if let a = autoReturnAfter, cardAge >= a { goHome() }
        }
        refreshUI()
        return ev
    }

    func refreshUI() {
        guard let s = sim else { if ui != RaceUI() { ui = RaceUI() }; return }
        var u = RaceUI()
        u.phase = kind == .drill && drill != nil ? (drillResult != nil ? .results : .running) : s.phase
        u.countdown = s.countdownNumber
        u.go = kind == .drill ? (drill != nil && drillState.goAge < RaceTuning.goFlash) : s.goFlashing
        u.live = kind == .drill ? (drill != nil && drillResult == nil) : (s.phase == .running || s.phase == .finishing) && !s.racers[0].finished
        u.stalled = s.phase != .countdown && s.racers[0].stalled && u.live && s.clock > 1.2
        u.stumbling = s.racers[0].tap.stumbling
        u.tripped = s.racers[0].tap.tripped
        u.inTurn = kind == .race && u.live && s.inTurn(0)
        u.course = s.course.tier
        u.placings = s.placings
        u.earned = earned
        u.waddleGain = waddleGain
        u.playerPlace = s.playerPlace
        if u != ui { ui = u }
    }

    func handle(_ e: RaceEvent) {
        switch e {
        case .countdown: cueSerial += 1; cue(.countdownBeep)
        case .go: cueSerial += 1; cue(.go)
        case .finished(let r, _): if r == RaceSim.playerIndex { cue(.finish) }
        case .results: settle()
        default: break
        }
    }

    /// The placings are in: Drops by place and the waddle nudge, once.
    private func settle() {
        guard !settled, let s = sim else { return }
        settled = true
        earned = s.playerDrops
        if let place = s.playerPlace {
            wallet?.add(earned)
            waddleGain = stats?.afterRace(place: place) ?? 0
            let open = progress.unlockedTiers
            progress.record(tier: s.course.tier, place: place)
            unlockedNow = progress.unlockedTiers.first { !open.contains($0) }
            drillCue(.jingle(win: place <= 2))
        }
        cueSerial += 1
        refreshUI()
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
                swapLog.append((wipe, fadeDest))
                cameraBlend = fadeDest == .track ? 1 : 0
                onSwap(fadeDest)
            }
            if holdT >= Self.fadeHold { fadeStage = .in }
        case .in:
            wipe = max(0, wipe - dt / Self.fadeIn)
            if wipe <= 0 {
                if fadeDest == .track { phase = .racing; introT = 0 }
                else { finishTrip() }
            }
        }
    }

    private func finishTrip() {
        let won = kind == .race ? (sim?.playerWon ?? false) : false
        let id = playerID
        phase = .off; leaving = false
        sim = nil
        onReturned(id, won)
    }

    /// Hard stop (tests, the app leaving): everything back to the room at once.
    func abort() {
        guard phase != .off else { return }
        if cameraBlend > 0 || swapped && fadeDest == .track { onSwap(.room) }
        cameraBlend = 0; wipe = 0; phase = .off; sim = nil; leaving = false; drill = nil; dip = 0
    }
}

/// The three race sound cues (AudioHub maps them to existing effects for now; dedicated sounds are added later under the same names).
enum RaceCue: Equatable { case countdownBeep, go, finish }

/// What the race view draws (republished only when it changes).
struct RaceUI: Equatable {
    var phase: RacePhase?
    var countdown = 0
    var go = false
    var live = false
    var stalled = false
    var stumbling = false
    var tripped = false
    /// The player is in a bend (the "ease off" hint).
    var inTurn = false
    var course: CourseTier = .puddle
    var placings: [RacePlacing] = []
    var earned = 0
    var waddleGain: Float = 0
    var playerPlace: Int?
}
