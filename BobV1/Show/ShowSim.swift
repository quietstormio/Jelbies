//
//  ShowSim.swift
//  One Jelly Show as a pure model: Look -> Dance -> Trick -> results. The player's inputs are read once at the start (his condition, shine, dance
//  skill and learned tricks); his outfit changes live in the Look round; the Dance round is a ShowDanceSim on the stage music's beat grid; the
//  Trick round is three turns of (pick a trick, tap when the spotlight ring hugs him). Nothing fails: a flop is cute and still scores.
//  The rivals' scores are fixed with the rivals (ShowRivalSource). Ties share the place. The flow (ShowFlow) adds time, bodies and sound.
//

import Foundation
import simd

nonisolated enum ShowRound: Int, Codable, Sendable, Comparable {
    case look, dance, trick, results
    var title: String { switch self { case .look: return "Look"; case .dance: return "Dance"; case .trick: return "Trick"; case .results: return "Results" } }
    static func < (a: ShowRound, b: ShowRound) -> Bool { a.rawValue < b.rawValue }
}

/// What the player's Jelbie brings to the show (read from his real state when the show starts).
nonisolated struct ShowPlayerInput: Equatable, Sendable {
    var name = "Bob"
    /// Condition in every stat (by WearTag).
    var condition: [WearTag: Float] = [:]
    var glow: Float = 0
    var dirt: Float = 0
    /// The dance he shows and how well he knows it (0 = freestyle, no dance learned).
    var dance: DanceID? = nil
    var danceSkill: Float = 0
    /// Learned tricks with their reliability.
    var tricks: [VoiceTrick: Float] = [:]
    func stat(_ t: WearTag) -> Float { condition[t] ?? 0 }
}

nonisolated struct ShowTrickTurn: Equatable, Sendable {
    var trick: VoiceTrick
    var success: Bool
    var repeated: Bool
    var timing: Float
    var points: Int
    var burst: Bool
}

/// One entrant on the results screen.
nonisolated struct ShowEntrant: Equatable, Sendable {
    var name: String
    var isPlayer: Bool
    var persona: ShowPersona?
    var tint: SIMD3<Float>
    var scores: ShowScores
    var place = 0
    var burst = false
    /// The rival's index (nil for the player).
    var rival: Int?
}

nonisolated struct ShowSim: Sendable {
    let rank: ShowRank
    let theme: ShowTheme
    let dayKey: Int
    let seed: UInt64
    private(set) var player: ShowPlayerInput
    private(set) var rivals: [ShowRival]
    private(set) var round: ShowRound = .look

    // Look
    /// What he wears in the scored slots now (tags per slot).
    private(set) var outfit: [WearSlot: [WearTag]] = [:]
    private(set) var lookScore: Float = 0

    // Dance
    private(set) var dance: ShowDanceSim?
    private(set) var danceScore: Float?
    var cheer: Float { dance?.cheer ?? 0 }

    // Trick
    private(set) var turns: [ShowTrickTurn] = []
    /// The trick picked for the turn under way and when its ring started (song / wall seconds, the flow's clock).
    private(set) var ringTrick: VoiceTrick?
    private(set) var ringStart: Double?
    private(set) var burstUsed = false
    /// The Glow Burst is armed for the turn under way.
    private(set) var burstArmed = false
    private var rng: RaceRNG

    // results
    private(set) var entrants: [ShowEntrant] = []

    init(rank: ShowRank, theme: ShowTheme, dayKey: Int, player: ShowPlayerInput, rivals: [ShowRival], seed: UInt64) {
        self.rank = rank; self.theme = theme; self.dayKey = dayKey; self.player = player; self.rivals = rivals; self.seed = seed
        rng = RaceRNG(seed: seed &* 0x2545F4914F6CDD1D &+ 0x51)
        recomputeLook()
    }

    // MARK: Look

    /// The theme match of each worn item in the scored slots, and the three parts of the Look score.
    var outfitItems: [[WearTag]] { rank.slotOrder.compactMap { outfit[$0] } }
    var outfitMatch: Float { ShowScoring.outfitMatch(items: outfitItems, slots: rank.slots, theme: theme) }
    /// Σ m before the cap (the "2.5 of 3 slots" note).
    var outfitSum: Float { outfitItems.reduce(0) { $0 + theme.match($1) } }
    var lookParts: (outfit: Float, stats: Float, glow: Float) {
        ShowScoring.lookParts(outfit: outfitMatch, main: player.stat(theme.main), friend: player.stat(theme.friend), glow: player.glow, dirt: player.dirt)
    }
    /// How a worn item matches: 1 main (gold), 0.5 friend (half gold), else none.
    func match(of tags: [WearTag]) -> Float { theme.match(tags) }

    mutating func setOutfit(_ o: [WearSlot: [WearTag]]) {
        guard round == .look else { return }
        outfit = o.filter { rank.slotOrder.contains($0.key) }
        recomputeLook()
    }
    private mutating func recomputeLook() {
        lookScore = ShowScoring.look(outfit: outfitMatch, main: player.stat(theme.main), friend: player.stat(theme.friend), glow: player.glow, dirt: player.dirt)
    }
    /// "Looks great. On to Dance": the Look score is locked.
    mutating func finishLook() {
        guard round == .look else { return }
        round = .dance
    }

    // MARK: Dance

    /// GO: the prompts start `leadInBeats` after `songTime` on `grid`.
    mutating func beginDance(grid: ShowBeat, songTime: Double) {
        guard round == .dance, dance == nil else { return }
        dance = ShowDanceSim(count: rank.promptCount, grid: grid, timing: rank.timing, seed: seed, songTime: songTime)
    }
    mutating func tapDance(foot: Int, at t: Double) -> [ShowDanceSim.Event] {
        guard round == .dance, dance != nil, danceScore == nil else { return [] }
        dance!.tap(foot: foot, at: t)
        return dance!.takeEvents()
    }
    mutating func tickDance(songTime t: Double) -> [ShowDanceSim.Event] {
        guard round == .dance, dance != nil, danceScore == nil else { return [] }
        dance!.tick(songTime: t)
        let ev = dance!.takeEvents()
        if dance!.finished { danceScore = ShowScoring.dance(accuracy: dance!.accuracy, skill: player.danceSkill) }
        return ev
    }
    var danceDone: Bool { danceScore != nil }
    /// On to the Trick round (after the dance has finished; a dance that never ran scores freestyle 0 accuracy).
    mutating func finishDance() {
        guard round == .dance else { return }
        if danceScore == nil { danceScore = ShowScoring.dance(accuracy: dance?.accuracy ?? 0, skill: player.danceSkill) }
        round = .trick
    }

    // MARK: Trick

    var turnIndex: Int { turns.count }
    var tricksDone: Bool { turns.count >= ShowScoring.turns }
    /// Tricks already shown this show (a repeat scores 12, not 18).
    var usedTricks: [VoiceTrick] { turns.map(\.trick) }
    /// The known tricks he can pick from, in a fixed order.
    var knownTricks: [VoiceTrick] { ShowTrickInfo.stageTricks.filter { player.tricks[$0] != nil } }
    func reliability(_ t: VoiceTrick) -> Float { player.tricks[t] ?? 0 }
    /// The Glow Burst can be armed: once, when the crowd cheers and he is shiny.
    var burstReady: Bool { !burstUsed && ShowScoring.burstReady(cheer: cheer, glow: player.glow) }
    var burstUnlocked: Bool { ShowScoring.burstReady(cheer: cheer, glow: player.glow) }
    /// The trick total so far (the Burst included).
    var trickTotal: Int { min(100, turns.reduce(0) { $0 + $1.points } + (burstUsed ? ShowScoring.burstPoints : 0)) }

    /// Arms the Burst for the next trick (it fires with that trick's turn).
    mutating func armBurst() { guard burstReady, round == .trick, !tricksDone else { return }; burstArmed = true }

    /// A trick card is tapped: the spotlight ring starts closing at `time`.
    mutating func beginTurn(_ t: VoiceTrick, at time: Double) {
        guard round == .trick, !tricksDone, ringTrick == nil, player.tricks[t] != nil else { return }
        ringTrick = t; ringStart = time
    }
    /// The player taps while the ring closes (or the flow judges a missed ring with `time` = start + ring + 0.3). `roll` decides the success
    /// (nil = the sim's own seeded roll).
    @discardableResult
    mutating func tapRing(at time: Double, roll: Float? = nil) -> ShowTrickTurn? {
        guard round == .trick, let t = ringTrick, let s = ringStart else { return nil }
        let err = time - s - ShowScoring.ringSeconds
        let timing = ShowScoring.timing(error: err)
        let r = roll ?? rng.next()
        let success = r < reliability(t)
        let repeated = usedTricks.contains(t)
        let pts = ShowScoring.turn(success: success, repeated: repeated, tags: ShowTrickInfo.tags(t), theme: theme, timing: timing)
        let burst = burstArmed
        if burst { burstUsed = true; burstArmed = false }
        let turn = ShowTrickTurn(trick: t, success: success, repeated: repeated, timing: timing, points: pts, burst: burst)
        turns.append(turn)
        ringTrick = nil; ringStart = nil
        if tricksDone { finishTricks() }
        return turn
    }

    // MARK: results

    var playerScores: ShowScores { ShowScores(look: lookScore, dance: danceScore ?? 0, trick: Float(trickTotal)) }

    private mutating func finishTricks() {
        var list = [ShowEntrant(name: player.name, isPlayer: true, persona: nil, tint: .zero, scores: playerScores, burst: burstUsed, rival: nil)]
        for (i, r) in rivals.enumerated() { list.append(ShowEntrant(name: r.name, isPlayer: false, persona: r.persona, tint: r.tint, scores: r.scores, burst: r.burst, rival: i)) }
        let places = ShowScoring.places(totals: list.map { Float($0.scores.totalPts) })
        for i in list.indices { list[i].place = places[i] }
        entrants = list
        round = .results
    }
    /// Tests / the flow: a show cut short still has a results list.
    mutating func settleNow() {
        if round == .look { round = .dance }
        if round == .dance { finishDance() }
        if round == .trick, !tricksDone { while !tricksDone { turns.append(ShowTrickTurn(trick: .sit, success: false, repeated: true, timing: 0, points: 0, burst: false)) }; finishTricks() }
    }
    var playerPlace: Int? { entrants.first(where: \.isPlayer)?.place }
    var playerDrops: Int { playerPlace.map { rank.drops(place: $0) } ?? 0 }
    var playerWon: Bool { playerPlace == 1 }
    /// Entrants by place (ties keep the player first, then rivals in order).
    var standings: [ShowEntrant] { entrants.sorted { a, b in a.place != b.place ? a.place < b.place : (a.isPlayer && !b.isPlayer) } }
    /// Every Perfect, no Slip.
    var perfectDance: Bool { (dance?.total ?? 0) > 0 && dance?.perfects == dance?.total }
    /// Three different tricks shown.
    var hatTrick: Bool { Set(turns.map(\.trick)).count == 3 }

    /// "Next time try ...": the round that cost the most against the field, and what raises it.
    var tip: String {
        let p = playerScores
        let best = rivals.map(\.scores).reduce(ShowScores()) { ShowScores(look: max($0.look, $1.look), dance: max($0.dance, $1.dance), trick: max($0.trick, $1.trick)) }
        let gaps: [(ShowRound, Float)] = [(.look, best.look - p.look), (.dance, best.dance - p.dance), (.trick, best.trick - p.trick)]
        let worst = gaps.max { $0.1 < $1.1 }!
        let name = player.name
        if worst.1 <= 0 { return "\(name) topped every round. Try the next rank up!" }
        switch worst.0 {
        case .look:
            let parts = lookParts
            if parts.outfit < 24 { return "Look was \(name)'s weakest at \(p.lookPts). Wear more \(theme.main.title) things: each matching item is worth a lot." }
            if parts.glow < 12 { return "Look was \(name)'s weakest at \(p.lookPts). A Clean before the show makes him glow, and Glow is 20 of the 100." }
            return "Look was \(name)'s weakest at \(p.lookPts). \(theme.main.title) food fills his \(theme.main.title) jar, which counts 70% of the stats part."
        case .dance:
            return player.danceSkill < 0.5 ? "Dance was \(name)'s lowest at \(p.dancePts). Practise a dance in the Studio: dance skill is 30% of the round."
                : "Dance was \(name)'s lowest at \(p.dancePts). Tap right on the beat: Perfects are worth most."
        default:
            return knownTricks.count < 3 ? "Trick was \(name)'s lowest at \(p.trickPts). Teach him more tricks (the Shop has pages): a fresh trick scores 18, a repeat 12."
                : "Trick was \(name)'s lowest at \(p.trickPts). Practise his tricks by voice so they land more often, and tap when the ring hugs him."
        }
    }
}
