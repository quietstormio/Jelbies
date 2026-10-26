//
//  VolleyFlow.swift
//  The whole Jelly Volleyball trip as one state machine (ParkTrip style): the white fade out, the swap to the beach while it is opaque, the fade in, the match (or
//  a training drill), the results card, and the same fade home. It owns no bodies: GameCare+Volley.swift does the swaps and ticks `sim`.
//  Also here: the one-time settlement (Drops, the tier unlocks, ribbons and trophies in the TrophyBook, the stat gains of a drill).
//

import Foundation
import QuartzCore
import Observation

/// What the screen needs of the match, republished only when it changes.
struct VolleyUI: Equatable {
    var phase: VolleyPhase = .intro
    var score = [0, 0]
    var serveTeam = 0
    var waitingToServe = false
    var humanServes = false
    var drillCount = 0, drillGood = 0, drillFeeds = 0, drillFlags = 0
    var drillTime: Float = 0
    var targetCushion = 0
    var rally = 0
    var airborne = false
    /// The touch counter: 0 empty, 1 filled, 2 filled by a Perfect touch (your side's possession only).
    var touchDots: [Int] = []
    var controlled = 0
    var hitLabel = "Hit"
    var fxSerial = 0, fxText = "", fxTone = 0
    var serveMeter: Float = -1
    var serveSweet: Float = 0.8, serveHalf: Float = 0.05
    var combo = false
    var calls: [Int] = []
}

@MainActor
@Observable
final class VolleyFlow {
    enum Phase { case off, goOut, hold, arriveIn, playing, leaveOut, leaveHold, leaveIn }
    enum Dest { case beach, home }

    private(set) var phase: Phase = .off
    private(set) var wipe: Float = 0
    var book = VolleyBook(persists: ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil)
    @ObservationIgnored var sim: VolleySim?
    /// CACurrentMediaTime when the sim last stepped (to date a touch against the sim state).
    @ObservationIgnored var lastStepMedia: Double = 0
    private(set) var ui = VolleyUI()
    private(set) var mode: VolleyMode = .match(.sandcastle)
    var playerID = 0
    var playerCharacter = 0
    var playerName = ""
    var partnerName = ""
    var opponentNames: [String] = []
    /// Results.
    private(set) var earned = 0
    private(set) var awards = TrophyAwards()
    private(set) var unlockedNow: VolleyTier?
    private(set) var gain = VolleyStats(speed: 0, power: 0, hops: 0, timing: 0)
    private(set) var settled = false
    private(set) var cueSerial = 0
    var toast: String?
    @ObservationIgnored var toastT: Float = 0
    @ObservationIgnored var holdFrames = 0
    @ObservationIgnored var onSwap: (Dest) -> Void = { _ in }
    @ObservationIgnored var trophies: TrophyBook?
    @ObservationIgnored var wallet: DropsWallet?
    @ObservationIgnored var assistFactor: Float = 1
    @ObservationIgnored var started = 0
    /// World positions (x, crown y, z) of the court's players, refreshed every step (not observed: the screen reads them per frame for the double-tap and the call bubbles).
    @ObservationIgnored var bodyPos: [SIMD3<Float>] = []
    @ObservationIgnored var callUntil: [Int: Double] = [:]
    @ObservationIgnored var onSwitchTap: (Int) -> Void = { _ in }
    /// Names of the human's team (the controlled one is announced when control moves).
    var teamNames: [String] = []
    static let fadeOut: Float = 0.45, fadeIn: Float = 0.5, holdSteps = 3
    nonisolated deinit {}

    var active: Bool { phase != .off }
    var inScene: Bool {
        switch phase { case .hold, .arriveIn, .playing, .leaveOut: return true; default: return false }
    }
    var hidesDecor: Bool { inScene }
    var cameraBlend: Float { inScene ? 1 : 0 }
    var isDrill: Bool { if case .drill = mode { return true }; return false }
    var tier: VolleyTier { if case .match(let t) = mode { return t }; return book.chosen }
    var showsCard: Bool { phase == .playing && sim?.phase == .over }
    var live: Bool { phase == .playing && sim != nil && sim?.phase != .over }
    var hasResults: Bool { sim?.phase == .over }

    func begin(mode m: VolleyMode, playerID id: Int, character: Int, name: String, sim s: VolleySim) {
        guard phase == .off else { return }
        mode = m; playerID = id; playerCharacter = character; playerName = name
        sim = s; ui = VolleyUI()
        earned = 0; awards = TrophyAwards(); unlockedNow = nil; gain = VolleyStats(speed: 0, power: 0, hops: 0, timing: 0); settled = false; cueSerial = 0
        phase = .goOut; wipe = 0; holdFrames = 0; started += 1
    }

    func goHome() {
        guard phase == .playing else { return }
        phase = .leaveOut
    }

    func say(_ s: String) { toast = s; toastT = 0 }

    func step(dt: Float) {
        if toast != nil { toastT += dt; if toastT > 3 { toast = nil } }
        switch phase {
        case .off, .playing: break
        case .goOut:
            wipe = min(wipe + dt / Self.fadeOut, 1)
            if wipe >= 1 { phase = .hold; holdFrames = 0; onSwap(.beach) }
        case .hold:
            holdFrames += 1
            if holdFrames >= Self.holdSteps { phase = .arriveIn }
        case .arriveIn:
            wipe = max(wipe - dt / Self.fadeIn, 0)
            if wipe <= 0 { phase = .playing }
        case .leaveOut:
            wipe = min(wipe + dt / Self.fadeOut, 1)
            if wipe >= 1 { phase = .leaveHold; holdFrames = 0; onSwap(.home) }
        case .leaveHold:
            holdFrames += 1
            if holdFrames >= Self.holdSteps { phase = .leaveIn }
        case .leaveIn:
            wipe = max(wipe - dt / Self.fadeIn, 0)
            if wipe <= 0 { phase = .off; sim = nil; wipe = 0 }
        }
    }

    func refreshUI() {
        guard let s = sim else { if ui != VolleyUI() { ui = VolleyUI() }; return }
        var u = VolleyUI()
        u.phase = s.phase; u.score = s.score; u.serveTeam = s.server
        u.waitingToServe = s.waitingToServe; u.humanServes = s.waitingToServe && s.servingPlayer == 0
        u.drillCount = s.drillCount; u.drillGood = s.drillGood; u.drillFeeds = s.drillFeeds; u.drillFlags = s.flagIndex
        u.drillTime = (s.drillTime * 2).rounded() / 2
        u.targetCushion = s.targetCushion; u.rally = s.rallyHits
        u.airborne = s.players.indices.contains(s.controlled) ? !s.players[s.controlled].grounded : false
        u.controlled = s.controlled
        u.hitLabel = s.hitLabel
        if !s.isDrill, s.possession == 0 { u.touchDots = (0..<VolleyTuning.maxTouches).map { $0 < s.touchLog.count ? (s.touchLog[$0] == .perfect ? 2 : 1) : 0 } }
        else if !s.isDrill { u.touchDots = [] }
        u.fxSerial = s.fxSerial; u.fxText = s.fxText; u.fxTone = s.fxTone
        if let m = s.serveMeter { u.serveMeter = (m * 200).rounded() / 200; u.serveSweet = s.serveSweet.center; u.serveHalf = s.serveSweet.half } else { u.serveMeter = -1 }
        u.combo = s.comboFlash > 0
        let nowT = CACurrentMediaTime()
        u.calls = callUntil.filter { $0.value > nowT }.keys.sorted()
        if u != ui { ui = u }
    }

    /// The match or drill is over: Drops, unlocks, ribbons and gains, once.
    func settle() {
        guard !settled, let s = sim, s.phase == .over else { return }
        settled = true
        switch mode {
        case .match(let t):
            let win = s.humanTeamWon
            earned = Int((Float(VolleyTuning.drops(win: win, tier: t)) * assistFactor).rounded(.down))
            wallet?.add(earned)
            unlockedNow = book.finishMatch(character: playerCharacter, tier: t, win: win, closeLoss: s.closeLoss)
            if win, let tb = trophies { awards = tb.recordVolleyWin(character: playerCharacter, tier: t) }
            A11yEvents.say(win ? "You won \(s.score[0]) to \(s.score[1]). \(earned) Drops" : "They won \(s.score[1]) to \(s.score[0]). \(earned) Drops", .high)
            if awards.newRibbon { A11yEvents.say("New ribbon!", .normal) }
            for tr in awards.trophies { A11yEvents.say("Trophy! \(tr.title)", .normal) }
        case .drill(let k):
            gain = book.finishDrill(character: playerCharacter, kind: k, accuracy: s.drillAccuracy, factor: assistFactor)
            A11yEvents.say("\(k.title) done", .high)
        }
        cueSerial += 1
    }
}

extension TrophyBook {
    /// A beach volleyball match was won on `tier`: the ribbon for the first win there, then the 5 / 10 / 25 win trophies.
    @discardableResult
    func recordVolleyWin(character c: Int, tier: VolleyTier) -> TrophyAwards {
        var a = TrophyAwards(place: 1)
        var s = shelf(character: c)
        var w = s.volleyWins ?? [:]
        a.newRibbon = (w[tier.rawValue] ?? 0) == 0
        w[tier.rawValue, default: 0] += 1
        s.volleyWins = w
        func grant(_ t: Trophy) { if !s.has(t) { s.earned.append(t.id); a.trophies.append(t) } }
        grant(.volleyFirst(tier))
        for m in Trophy.volleyMilestones where s.volleyTotal >= m.wins { grant(m.trophy) }
        setShelf(s, character: c)
        return a
    }
}

extension Trophy {
    static func volleyFirst(_ t: VolleyTier) -> Trophy { Trophy(id: "vfirst.\(t.rawValue)", title: "\(t.title) volley winner", detail: "First volleyball win at \(t.title)") }
    static let volley5 = Trophy(id: "vwins5", title: "5 volley wins", detail: "Won 5 volleyball matches")
    static let volley10 = Trophy(id: "vwins10", title: "10 volley wins", detail: "Won 10 volleyball matches")
    static let volley25 = Trophy(id: "vwins25", title: "25 volley wins", detail: "Won 25 volleyball matches")
    static let volleyMilestones: [(wins: Int, trophy: Trophy)] = [(5, volley5), (10, volley10), (25, volley25)]
    static var allVolley: [Trophy] { VolleyTier.allCases.map(volleyFirst) + volleyMilestones.map(\.trophy) }
}
