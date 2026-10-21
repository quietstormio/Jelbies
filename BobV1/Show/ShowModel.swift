//
//  ShowModel.swift
//  The Jelly Show (the beauty contest): the second way to earn Drops. Pure rules, no bodies, no screen, so everything here runs headless in tests.
//
//    ShowRank        Puddle / Pond / Lagoon / Ocean: wear slots, prompt counts, timing kindness and the payout table.
//    ShowTheme       the five daily themes, each a MAIN stat and a FRIEND stat; ShowSchedule picks the day's theme from DayClock.dayKey.
//    ShowScoring     the three rounds' formulas (Look / Dance / Trick, 100 each), the Cheer meter and the Glow Burst.
//    ShowTrickInfo   which stat each trick counts as (a starter trick, the flip, also counts as Sparkly).
//    ShowDanceSim    the Dance round's prompt lane on the stage music's beat grid, judged from the audio clock like Rhythm Steps.
//
//  Words we do not use (Pokemon's): contest, appeal, hearts, sheen, spectacular, ribbon, and the Normal...Master rank names.
//

import Foundation
import simd

// MARK: - ranks

nonisolated enum ShowRank: String, CaseIterable, Codable, Sendable {
    case puddle, pond, lagoon, ocean

    var title: String { switch self { case .puddle: return "Puddle"; case .pond: return "Pond"; case .lagoon: return "Lagoon"; case .ocean: return "Ocean" } }
    var index: Int { ShowRank.allCases.firstIndex(of: self) ?? 0 }
    var below: ShowRank? { index > 0 ? ShowRank.allCases[index - 1] : nil }
    var above: ShowRank? { index + 1 < ShowRank.allCases.count ? ShowRank.allCases[index + 1] : nil }

    /// Wear slots the Look round scores (2 / 3 / 4 / 6).
    var slots: Int { switch self { case .puddle: return 2; case .pond: return 3; case .lagoon: return 4; case .ocean: return 6 } }
    /// Which slots those are, in order (the first `slots` of these).
    var slotOrder: [WearSlot] { Array(ShowRank.allSlotOrder.prefix(slots)) }
    static let allSlotOrder: [WearSlot] = [.head, .feet, .neck, .face, .body, .hands]
    /// Prompts in the Dance round (16 / 20 / 24 / 28).
    var promptCount: Int { switch self { case .puddle: return 16; case .pond: return 20; case .lagoon: return 24; case .ocean: return 28 } }
    /// Puddle and Pond judge one notch kinder (Perfect within 80 ms instead of 60).
    var kindTiming: Bool { self == .puddle || self == .pond }
    var timing: ShowTiming { kindTiming ? .kind : .standard }

    /// Drops by place (1-based). The user's table: Puddle 12 / 7 / 4 / 2, Pond 15 / 9 / 5 / 3, Lagoon 18 / 11 / 7 / 4, Ocean 22 / 13 / 8 / 5.
    func drops(place: Int) -> Int {
        let table: [Int]
        switch self {
        case .puddle: table = [12, 7, 4, 2]
        case .pond: table = [15, 9, 5, 3]
        case .lagoon: table = [18, 11, 7, 4]
        case .ocean: table = [22, 13, 8, 5]
        }
        return table[min(max(place, 1), 4) - 1]
    }
    /// What the rivals of this rank score on average, in words for the lobby.
    var rivalEstimate: Int { switch self { case .puddle: return 130; case .pond: return 175; case .lagoon: return 220; case .ocean: return 265 } }
}

/// The judging windows (seconds either side of the beat).
nonisolated struct ShowTiming: Equatable, Sendable {
    var perfect: Double, good: Double, miss: Double
    static let standard = ShowTiming(perfect: TrainingTuning.perfectWindow, good: TrainingTuning.goodWindow, miss: TrainingTuning.missWindow)
    static let kind = ShowTiming(perfect: 0.080, good: 0.150, miss: 0.220)
}

// MARK: - stats and tags

extension ConditionKey {
    /// The one name used everywhere: the stat and the wear tag are both "Sparkly".
    var tag: WearTag {
        switch self { case .cute: return .cute; case .cool: return .cool; case .sparkle: return .sparkly; case .sweet: return .sweet; case .sporty: return .sporty }
    }
    static func of(_ t: WearTag) -> ConditionKey {
        switch t { case .cute: return .cute; case .cool: return .cool; case .sparkly: return .sparkle; case .sweet: return .sweet; case .sporty: return .sporty }
    }
}

extension WearTag {
    var title: String { rawValue.capitalized }
    var condition: ConditionKey { ConditionKey.of(self) }
    /// The jar / chip colour (sRGB hex) of each stat: Cute pink, Sweet honey, Sparkly sky, Cool lavender, Sporty mint.
    var hex: UInt32 {
        switch self { case .cute: return 0xE98AA4; case .sweet: return 0xF9CC59; case .sparkly: return 0x6EB3D1; case .cool: return 0xB58BDB; case .sporty: return 0x9FD9B0 }
    }
    /// Jar order on the Condition card: Cute, Sweet, Sparkly, Cool, Sporty (neighbours are friends).
    static let jarOrder: [WearTag] = [.cute, .sweet, .sparkly, .cool, .sporty]
}

// MARK: - themes

nonisolated enum ShowTheme: Int, CaseIterable, Codable, Sendable {
    case sweetTeaParty, starlightGala, beachGames, coolCats, bunnyPicnic

    var title: String {
        switch self {
        case .sweetTeaParty: return "Sweet Tea Party"; case .starlightGala: return "Starlight Gala"; case .beachGames: return "Beach Games"
        case .coolCats: return "Cool Cats"; case .bunnyPicnic: return "Bunny Picnic"
        }
    }
    /// The stat that counts most, and its friend (30 % of the stat part, half an outfit match).
    var main: WearTag {
        switch self { case .sweetTeaParty: return .sweet; case .starlightGala: return .sparkly; case .beachGames: return .sporty; case .coolCats: return .cool; case .bunnyPicnic: return .cute }
    }
    var friend: WearTag {
        switch self { case .sweetTeaParty: return .cute; case .starlightGala: return .cool; case .beachGames: return .cute; case .coolCats: return .sporty; case .bunnyPicnic: return .sweet }
    }
    /// 1 for the main stat, 0.5 for the friend, 0.15 for anything else (an item counts once, at its best tag).
    func match(_ tags: [WearTag]) -> Float {
        if tags.contains(main) { return 1 }
        if tags.contains(friend) { return 0.5 }
        return 0.15
    }
    /// The Trick round's theme points: +6 for a main-stat trick, +3 for a friend one.
    func trickBonus(_ tags: [WearTag]) -> Int { tags.contains(main) ? 6 : tags.contains(friend) ? 3 : 0 }
}

/// Which theme is on which day. One theme a day for everybody, announced a day ahead, never the same two days running.
/// Deterministic from the calendar day (DayClock.dayKey, yyyymmdd) with plain integer mixing: no Hasher (its seed changes per process).
nonisolated enum ShowSchedule {
    /// yyyymmdd -> days since 1970-01-01 (proleptic Gregorian; the civil-from-days algorithm run backwards).
    static func dayOrdinal(_ dayKey: Int) -> Int {
        let y0 = dayKey / 10000, m = (dayKey / 100) % 100, d = dayKey % 100
        let y = m <= 2 ? y0 - 1 : y0
        let era = (y >= 0 ? y : y - 399) / 400
        let yoe = y - era * 400
        let doy = (153 * (m + (m > 2 ? -3 : 9)) + 2) / 5 + d - 1
        let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy
        return era * 146097 + doe - 719468
    }
    /// days since 1970 -> yyyymmdd.
    static func dayKey(ordinal z0: Int) -> Int {
        let z = z0 + 719468
        let era = (z >= 0 ? z : z - 146096) / 146097
        let doe = z - era * 146097
        let yoe = (doe - doe / 1460 + doe / 36524 - doe / 146096) / 365
        let y = yoe + era * 400
        let doy = doe - (365 * yoe + yoe / 4 - yoe / 100)
        let mp = (5 * doy + 2) / 153
        let d = doy - (153 * mp + 2) / 5 + 1
        let m = mp + (mp < 10 ? 3 : -9)
        return (m <= 2 ? y + 1 : y) * 10000 + m * 100 + d
    }
    /// splitmix64 finaliser.
    static func mix(_ x: UInt64) -> UInt64 {
        var z = x &+ 0x9E3779B97F4A7C15
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
    /// The five themes in a seeded order for a five-day block.
    private static func block(_ b: Int) -> [ShowTheme] {
        var order = ShowTheme.allCases
        var s = mix(UInt64(bitPattern: Int64(b)) &* 31 &+ 7)
        for i in stride(from: order.count - 1, to: 0, by: -1) {
            s = mix(s)
            order.swapAt(i, Int(s % UInt64(i + 1)))
        }
        return order
    }
    static func theme(ordinal n: Int) -> ShowTheme {
        let b = n >= 0 ? n / 5 : (n - 4) / 5
        let k = n - b * 5
        var order = block(b)
        // the first day of a block must not repeat the last day of the block before (the swap is applied for every day of the block, so the
        // block's order is one fixed list)
        if order[0] == block(b - 1).last! { order.swapAt(0, 1) }
        return order[k]
    }
    static func theme(dayKey: Int) -> ShowTheme { theme(ordinal: dayOrdinal(dayKey)) }
    static func tomorrow(dayKey: Int) -> ShowTheme { theme(ordinal: dayOrdinal(dayKey) + 1) }
    /// The seed the rivals of a day / rank are made from.
    static func rivalSeed(dayKey: Int, rank: ShowRank) -> UInt64 { mix(UInt64(dayKey) &* 8 &+ UInt64(rank.index) &+ 0x5A17) }
}

// MARK: - tricks

nonisolated enum ShowTrickInfo {
    /// What each trick counts as. The flip (a starter) also counts as Sparkly, so a new Jelbie can match a Sparkly show.
    static func tags(_ t: VoiceTrick) -> [WearTag] {
        switch t {
        case .spin: return [.sparkly]
        case .hop: return [.sporty]
        case .roll: return [.cute]
        case .flip: return [.cool, .sparkly]
        case .jacks: return [.sporty]
        case .sit: return [.sweet]
        case .look: return [.cute]
        case .come: return [.sweet]
        case .run: return [.cool]
        }
    }
    /// The tricks a Jelbie can show on stage: everything learned but the come and the run (walks, not stage tricks: he would leave the spotlight).
    static let stageTricks: [VoiceTrick] = VoiceTrick.allCases.filter { $0 != .come && $0 != .run }
    static func symbol(_ t: VoiceTrick) -> String {
        switch t {
        case .spin: return "arrow.triangle.2.circlepath"; case .hop: return "arrow.up.to.line"; case .roll: return "circle.dotted.circle"
        case .flip: return "arrow.uturn.up"; case .jacks: return "figure.jumprope"; case .sit: return "chair.fill"; case .look: return "eye.fill"
        case .come: return "figure.walk"; case .run: return "figure.run"
        }
    }
}

// MARK: - scoring

/// One entrant's three round scores (0...100 each).
nonisolated struct ShowScores: Equatable, Codable, Sendable {
    var look: Float = 0, dance: Float = 0, trick: Float = 0
    var total: Float { look + dance + trick }
    /// Whole points for the screen (each round rounded, the total is their sum so the bars add up).
    var lookPts: Int { Int(look.rounded()) }
    var dancePts: Int { Int(dance.rounded()) }
    var trickPts: Int { Int(trick.rounded()) }
    var totalPts: Int { lookPts + dancePts + trickPts }
}

nonisolated enum ShowScoring {
    // MARK: Look
    /// Σ m(item) / slots, capped at 1: m = 1 main tag, 0.5 friend tag, 0.15 anything else.
    static func outfitMatch(items: [[WearTag]], slots: Int, theme: ShowTheme) -> Float {
        guard slots > 0 else { return 0 }
        return min(1, items.reduce(0) { $0 + theme.match($1) } / Float(slots))
    }
    /// Look = 40 x outfit match + 40 x (0.7 main + 0.3 friend) + 20 x glow x (1 - 0.5 dirt).
    static func look(outfit: Float, main: Float, friend: Float, glow: Float, dirt: Float) -> Float {
        40 * clamp01(outfit) + 40 * (0.7 * clamp01(main) + 0.3 * clamp01(friend)) + 20 * clamp01(glow) * (1 - 0.5 * clamp01(dirt))
    }
    /// The three parts, for the breakdown.
    static func lookParts(outfit: Float, main: Float, friend: Float, glow: Float, dirt: Float) -> (outfit: Float, stats: Float, glow: Float) {
        (40 * clamp01(outfit), 40 * (0.7 * clamp01(main) + 0.3 * clamp01(friend)), 20 * clamp01(glow) * (1 - 0.5 * clamp01(dirt)))
    }

    // MARK: Dance
    /// Dance = 100 x (0.7 accuracy + 0.3 dance skill).
    static func dance(accuracy: Float, skill: Float) -> Float { 100 * (0.7 * clamp01(accuracy) + 0.3 * clamp01(skill)) }
    /// Perfect 1, Good 0.6, Slip 0.
    static func gradeValue(_ g: DrillGrade) -> Float { switch g { case .perfect: return 1; case .good: return 0.6; case .miss: return 0 } }
    /// The Cheer meter: +1/8 per Perfect, +1/16 per Good, -1/16 per Slip, clamped 0...1.
    static func cheer(_ c: Float, after g: DrillGrade) -> Float {
        switch g { case .perfect: return min(1, c + 1.0 / 8); case .good: return min(1, c + 1.0 / 16); case .miss: return max(0, c - 1.0 / 16) }
    }

    // MARK: Trick
    static let turns = 3
    static let turnMax = 30
    static let burstPoints = 10
    static let burstCheer: Float = 0.75, burstGlow: Float = 0.5
    /// The spotlight ring closes over this long; the tap's error is judged against it.
    static let ringSeconds: Double = 1.2
    /// t = 1 - |error| / 0.3 s, clamped.
    static func timing(error: Double) -> Float { Float(min(max(1 - abs(error) / 0.3, 0), 1)) }
    /// Points of one turn (max 30): base 18 on success (12 for a trick already shown this show), 8 for a cute flop; + theme 6 / 3; + 6 x timing.
    static func turn(success: Bool, repeated: Bool, tags: [WearTag], theme: ShowTheme, timing t: Float) -> Int {
        let base = success ? (repeated ? 12 : 18) : 8
        return min(turnMax, base + theme.trickBonus(tags) + Int((6 * clamp01(t)).rounded()))
    }
    /// The one-time Glow Burst (+10) is on offer when the crowd is cheering and he is shiny.
    static func burstReady(cheer: Float, glow: Float) -> Bool { cheer >= burstCheer && glow >= burstGlow }

    // MARK: placings
    /// Places by total, descending; ties share the place (both get the higher place's payout). Returns a place per entrant index.
    static func places(totals: [Float]) -> [Int] {
        totals.map { t in 1 + totals.filter { $0 > t + 1e-4 }.count }
    }

    static func clamp01(_ v: Float) -> Float { min(max(v, 0), 1) }
}

// MARK: - the dance lane

/// A beat grid: beat n is at `firstBeat + n * period` seconds of song time. The two show tracks are 120 BPM (music_pick/picks.json).
nonisolated struct ShowBeat: Equatable, Sendable {
    var firstBeat: Double
    var period: Double
    /// contest_stage_2: beats at 0.277 s + n x 0.5; the 16-bar loop starts on beat 68 (34.277 s), so the grid holds across the seam.
    static let stage = ShowBeat(firstBeat: 0.277, period: 0.5)
    /// studio_practice_1: beats at 0.023 s + n x 0.5; its loop starts at 28.021 s (beat 56).
    static let studio = ShowBeat(firstBeat: 0.023, period: 0.5)
    static func grid(for t: SceneTrack) -> ShowBeat { t == .studioPractice ? .studio : .stage }

    func time(ofBeat n: Int) -> Double { firstBeat + Double(n) * period }
    func beat(atOrAfter t: Double) -> Int { Int(((t - firstBeat) / period).rounded(.up)) }
}

/// One dance: `count` L / R prompts on the beat grid, each judged Perfect / Good / Slip from the tap's SONG time. Nothing fails: a Slip is just 0 points.
nonisolated struct ShowDanceSim: Sendable {
    nonisolated struct Prompt: Equatable, Sendable {
        var index: Int
        /// 0 = left, 1 = right.
        var foot: Int
        var beat: Int
        var time: Double
        var grade: DrillGrade?
    }
    nonisolated enum Event: Equatable, Sendable { case hit(index: Int, foot: Int, grade: DrillGrade), slip(index: Int, foot: Int), stray, finished }

    private(set) var prompts: [Prompt] = []
    private(set) var songTime: Double
    private(set) var perfects = 0, goods = 0, misses = 0, strays = 0
    private(set) var streak = 0, bestStreak = 0
    private(set) var cheer: Float = 0
    private(set) var events: [Event] = []
    private(set) var finished = false
    let grid: ShowBeat
    let timing: ShowTiming
    static let leadInBeats = 4
    static let latencyOffset = TrainingTuning.latencyOffset
    static let visibleBeats = 5

    var total: Int { prompts.count }
    var judged: Int { perfects + goods + misses }
    /// Σ grade values / prompts, a little off for stray taps (mashing).
    var accuracy: Float {
        guard total > 0 else { return 0 }
        return min(max((Float(perfects) + 0.6 * Float(goods) - 0.5 * Float(strays)) / Float(total), 0), 1)
    }
    var endTime: Double { (prompts.last?.time ?? songTime) + timing.good }

    /// `songTime`: song time at GO; the first prompt is `leadInBeats` later, on the grid. Feet alternate from a seeded start.
    init(count: Int, grid: ShowBeat, timing: ShowTiming, seed: UInt64, songTime: Double) {
        self.grid = grid; self.timing = timing; self.songTime = songTime
        var rng = RaceRNG(seed: seed &* 0x9E3779B97F4A7C15 &+ 0xD17)
        var beat = grid.beat(atOrAfter: songTime + Double(Self.leadInBeats) * grid.period)
        var foot = Int(rng.next() * 2) % 2
        for i in 0..<max(count, 0) {
            prompts.append(Prompt(index: i, foot: foot, beat: beat, time: grid.time(ofBeat: beat)))
            foot = 1 - foot; beat += 1
        }
    }

    mutating func takeEvents() -> [Event] { let e = events; events.removeAll(keepingCapacity: true); return e }
    private var judgedTime: Double { songTime - Self.latencyOffset }

    /// Prompts on screen: (prompt, beats ahead of now).
    func visible(at t: Double? = nil) -> [(prompt: Prompt, ahead: Double)] {
        let now = (t ?? songTime) - Self.latencyOffset
        let span = Double(Self.visibleBeats) * grid.period
        return prompts.filter { $0.grade == nil && $0.time - now < span && $0.time - now > -timing.good - 0.05 }.map { ($0, ($0.time - now) / grid.period) }
    }

    mutating func tick(songTime t: Double) {
        guard !finished else { return }
        songTime = max(songTime, t)
        for i in prompts.indices where prompts[i].grade == nil && judgedTime > prompts[i].time + timing.good { judge(i, .miss) }
        if !prompts.contains(where: { $0.grade == nil }), !finished { finished = true; events.append(.finished) }
    }

    mutating func tap(foot: Int, at t: Double) {
        guard !finished else { return }
        tick(songTime: t)
        tap(foot: foot)
    }

    mutating func tap(foot: Int) {
        guard !finished else { return }
        let f = foot == 0 ? 0 : 1
        let now = judgedTime
        var best: Int?
        for i in prompts.indices where prompts[i].grade == nil {
            let d = abs(prompts[i].time - now)
            if d <= timing.miss, best == nil || d < abs(prompts[best!].time - now) { best = i }
            if prompts[i].time - now > timing.miss { break }
        }
        guard let i = best else { strays += 1; events.append(.stray); return }
        let err = abs(prompts[i].time - now)
        if prompts[i].foot != f { judge(i, .miss); return }
        if err <= timing.perfect { judge(i, .perfect) } else if err <= timing.good { judge(i, .good) } else { judge(i, .miss) }
    }

    private mutating func judge(_ i: Int, _ g: DrillGrade) {
        prompts[i].grade = g
        switch g {
        case .perfect: perfects += 1; streak += 1
        case .good: goods += 1; streak += 1
        case .miss: misses += 1; streak = 0
        }
        bestStreak = max(bestStreak, streak)
        cheer = ShowScoring.cheer(cheer, after: g)
        if g == .miss { events.append(.slip(index: i, foot: prompts[i].foot)) } else { events.append(.hit(index: i, foot: prompts[i].foot, grade: g)) }
        if judged == total, !finished { finished = true; events.append(.finished) }
    }
}
