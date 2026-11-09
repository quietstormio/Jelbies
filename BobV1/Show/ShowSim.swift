//
//  ShowSim.swift
//  One Jelly Show as a pure model: Look -> Dance -> Trick -> results. The player's inputs are read once at the start (his condition, shine, dance
//  skill and learned tricks); his outfit is chosen in the Studio and judged in the Look round; the Dance round is a ShowDanceSim on the stage music's beat grid; the
//  Trick round is three turns of picking a trick off his menu (stars = points, and a small chance to slip). Nothing fails: a flop is cute and still scores.
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
    var name = "Jelbie"
    /// Condition in every stat (by WearTag).
    var condition: [WearTag: Float] = [:]
    var glow: Float = 0
    var dirt: Float = 0
    /// The dance he shows and how well he knows it (0 = freestyle, no dance learned).
    var dance: DanceID? = nil
    /// Learned tricks (the value is the old voice reliability, no longer used for scoring; the defaults are always on the menu).
    var tricks: [VoiceTrick: Float] = [:]
    /// How well cared for he is, 0...1 (needs met and clean): lowers the chance a trick slips.
    var care: Float = 0.5
    func stat(_ t: WearTag) -> Float { condition[t] ?? 0 }
}

nonisolated struct ShowTrickTurn: Equatable, Sendable {
    var trick: VoiceTrick
    var success: Bool
    var repeated: Bool
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
    private(set) var burstUsed = false
    /// The Glow Burst is armed for the turn under way.
    private(set) var burstArmed = false
    private var rng: RaceRNG
    /// The rivals' tricks, one list per rival (index = rival), one entry per turn. Rolled the moment the player's turn lands, from the DAY's seed (never the
    /// show's), so a same-day replay meets the same rivals doing the same tricks; ShowFlow only paces them on the stage.
    private(set) var rivalTurns: [[ShowTrickTurn]] = []

    // results
    private(set) var entrants: [ShowEntrant] = []

    init(rank: ShowRank, theme: ShowTheme, dayKey: Int, player: ShowPlayerInput, rivals: [ShowRival], seed: UInt64) {
        self.rank = rank; self.theme = theme; self.dayKey = dayKey; self.player = player; self.rivals = rivals; self.seed = seed
        rng = RaceRNG(seed: seed &* 0x2545F4914F6CDD1D &+ 0x51)
        rivalTurns = Array(repeating: [], count: rivals.count)
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
    /// The walk-on is over: the Look score is locked.
    mutating func finishLook() {
        guard round == .look else { return }
        round = .dance
    }

    // MARK: Dance

    /// GO: the prompts sit on `song`'s own beats (song time 0 = the song's first sample, `songTime` is the clock now).
    mutating func beginDance(song: DanceSong, songTime: Double) {
        guard round == .dance, dance == nil else { return }
        dance = ShowDanceSim(song: song, timing: rank.timing, seed: seed, songTime: songTime)
    }
    /// GO on a beat grid (the old fixed dance: `rank.promptCount` prompts from `leadInBeats` after `songTime`); tests and the grid drill.
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
        if dance!.finished { danceScore = ShowScoring.dance(accuracy: dance!.accuracy) }
        return ev
    }
    var danceDone: Bool { danceScore != nil }
    /// On to the Trick round (after the dance has finished; a dance that never ran scores freestyle 0 accuracy).
    mutating func finishDance() {
        guard round == .dance else { return }
        if danceScore == nil { danceScore = ShowScoring.dance(accuracy: dance?.accuracy ?? 0) }
        round = .trick
    }

    // MARK: Trick

    var turnIndex: Int { turns.count }
    var tricksDone: Bool { turns.count >= ShowScoring.turns }
    /// Tricks already shown this show (a repeat is worth less).
    var usedTricks: [VoiceTrick] { turns.map(\.trick) }
    /// The known tricks he can pick from, in a fixed order.
    var knownTricks: [VoiceTrick] { ShowTrickInfo.menu(learned: player.tricks.keys) }
    /// His chance to slip on `t` (stars x care).
    func missChance(_ t: VoiceTrick) -> Float { ShowScoring.missChance(difficulty: ShowTrickInfo.difficulty(t), care: player.care) }
    /// What `t` scores if it lands now (stars, theme, a repeat).
    func points(_ t: VoiceTrick) -> Int {
        ShowScoring.turn(difficulty: ShowTrickInfo.difficulty(t), success: true, repeated: usedTricks.contains(t), tags: ShowTrickInfo.tags(t), theme: theme)
    }
    /// The Glow Burst can be armed: once, when the crowd cheers and he is shiny.
    var burstReady: Bool { !burstUsed && ShowScoring.burstReady(cheer: cheer, glow: player.glow) }
    var burstUnlocked: Bool { ShowScoring.burstReady(cheer: cheer, glow: player.glow) }
    /// The trick total so far (the Burst included).
    var trickTotal: Int { min(100, turns.reduce(0) { $0 + $1.points } + (burstUsed ? ShowScoring.burstPoints : 0)) }

    /// Arms the Burst for the next trick (it fires with that trick's turn).
    mutating func armBurst() { guard burstReady, round == .trick, !tricksDone else { return }; burstArmed = true }

    /// A menu row is tapped: he performs `t` (a trick off the menu is allowed too). `roll` decides a slip (nil = the sim's own seeded roll):
    /// below the miss chance he slips into the cute flop, which still scores.
    @discardableResult
    mutating func perform(_ t: VoiceTrick, roll: Float? = nil) -> ShowTrickTurn? {
        guard round == .trick, !tricksDone else { return nil }
        let r = roll ?? rng.next()
        let d = ShowTrickInfo.difficulty(t)
        let success = r >= missChance(t)
        let repeated = usedTricks.contains(t)
        let pts = ShowScoring.turn(difficulty: d, success: success, repeated: repeated, tags: ShowTrickInfo.tags(t), theme: theme)
        let burst = burstArmed
        if burst { burstUsed = true; burstArmed = false }
        let turn = ShowTrickTurn(trick: t, success: success, repeated: repeated, points: pts, burst: burst)
        turns.append(turn)
        rollRivalTurns(turn: turns.count - 1)
        if tricksDone { finishTricks() }
        return turn
    }

    // MARK: the rivals' tricks

    /// The generator of rival `i`'s turn `k` (a pick and a slip roll): fixed by the day and the rank only.
    private func rivalRNG(_ i: Int, _ k: Int) -> RaceRNG {
        var g = RaceRNG(seed: ShowSchedule.rivalSeed(dayKey: dayKey, rank: rank) &+ UInt64(i + 1) &* 0x9E3779B97F4A7C15 &+ UInt64(k + 1) &* 0xBF58476D1CE4E5B9)
        _ = g.next()
        return g
    }
    /// What rival `i` shows on turn `k` (given the turns she already took): the Trickster goes for the most stars, the Poser for a trick that matches the
    /// theme (main, then friend), the Dancer for the middle (2 stars); nobody repeats while a fresh trick is left.
    func rivalPick(_ i: Int, turn k: Int) -> VoiceTrick {
        var g = rivalRNG(i, k)
        let used = rivalTurns[i].prefix(k).map(\.trick)
        var pool = ShowTrickInfo.stageTricks.filter { !used.contains($0) }
        if pool.isEmpty { pool = ShowTrickInfo.stageTricks }
        var want = pool
        switch rivals[i].persona {
        case .trickster:
            let top = pool.map { ShowTrickInfo.difficulty($0) }.max() ?? 1
            want = pool.filter { ShowTrickInfo.difficulty($0) == top }
        case .poser:
            let main = pool.filter { ShowTrickInfo.tags($0).contains(theme.main) }
            let friend = pool.filter { ShowTrickInfo.tags($0).contains(theme.friend) }
            want = !main.isEmpty ? main : (!friend.isEmpty ? friend : pool)
        case .dancer:
            let mid = pool.filter { ShowTrickInfo.difficulty($0) == 2 }
            want = mid.isEmpty ? pool : mid
        }
        return want[Int(g.next() * Float(want.count)) % want.count]
    }
    /// Every rival takes her turn `k`: the player's rule (stars, theme, a repeat, the cap) with the miss chance at the rivals' care.
    private mutating func rollRivalTurns(turn k: Int) {
        for i in rivals.indices where rivalTurns[i].count == k {
            let t = rivalPick(i, turn: k)
            var g = rivalRNG(i, k)
            _ = g.next(); _ = g.next()
            let d = ShowTrickInfo.difficulty(t)
            let success = g.next() >= ShowScoring.missChance(difficulty: d, care: ShowTuning.rivalCare)
            let repeated = rivalTurns[i].contains { $0.trick == t }
            let pts = ShowScoring.turn(difficulty: d, success: success, repeated: repeated, tags: ShowTrickInfo.tags(t), theme: theme)
            rivalTurns[i].append(ShowTrickTurn(trick: t, success: success, repeated: repeated, points: pts, burst: false))
        }
    }
    /// Rival `i`'s scores today: her Look and Dance are fixed with her, her Trick is what she really showed (plus her Burst).
    func rivalScores(_ i: Int) -> ShowScores {
        var sc = rivals[i].scores
        let sum = rivalTurns[i].reduce(0) { $0 + $1.points } + (rivals[i].burst ? ShowScoring.burstPoints : 0)
        sc.trick = Float(min(100, sum))
        return sc
    }

    // MARK: results

    var playerScores: ShowScores { ShowScores(look: lookScore, dance: danceScore ?? 0, trick: Float(trickTotal)) }

    private mutating func finishTricks() {
        var list = [ShowEntrant(name: player.name, isPlayer: true, persona: nil, tint: .zero, scores: playerScores, burst: burstUsed, rival: nil)]
        for (i, r) in rivals.enumerated() { list.append(ShowEntrant(name: r.name, isPlayer: false, persona: r.persona, tint: r.tint, scores: rivalScores(i), burst: r.burst, rival: i)) }
        let places = ShowScoring.places(totals: list.map { Float($0.scores.totalPts) })
        for i in list.indices { list[i].place = places[i] }
        entrants = list
        round = .results
    }
    /// Tests / the flow: a show cut short still has a results list.
    mutating func settleNow() {
        if round == .look { round = .dance }
        if round == .dance { finishDance() }
        if round == .trick, !tricksDone { while !tricksDone { turns.append(ShowTrickTurn(trick: .sit, success: false, repeated: true, points: 0, burst: false)); rollRivalTurns(turn: turns.count - 1) }; finishTricks() }
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
        let best = rivals.indices.map { rivalScores($0) }.reduce(ShowScores()) { ShowScores(look: max($0.look, $1.look), dance: max($0.dance, $1.dance), trick: max($0.trick, $1.trick)) }
        let gaps: [(ShowRound, Float)] = [(.look, best.look - p.look), (.dance, best.dance - p.dance), (.trick, best.trick - p.trick)]
        let worst = gaps.max { $0.1 < $1.1 }!
        let name = player.name
        if worst.1 <= 0 { return "\(name) topped every round. Try the next rank up!" }
        switch worst.0 {
        case .look:
            let parts = lookParts
            if parts.outfit < 24 { return "Look was \(name)'s weakest at \(p.lookPts). Wear more \(theme.main.title) things: each matching item is worth a lot." }
            if parts.glow < 12 { return "Look was \(name)'s weakest at \(p.lookPts). A Clean before the Jelly Show makes \(name) glow, and Glow is 20 of the 100." }
            return "Look was \(name)'s weakest at \(p.lookPts). \(theme.main.title) food fills \(name)'s \(theme.main.title) jar, which counts 70% of the stats part."
        case .dance:
            return "Dance was \(name)'s lowest at \(p.dancePts). Tap right on the beat: Perfects are worth most."
        default:
            return "Trick was \(name)'s lowest at \(p.trickPts). Harder tricks (more stars) score more, a trick that matches \(theme.main.title) adds points, and a happy, clean Jelbie slips less."
        }
    }
}
