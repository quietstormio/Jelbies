//
//  StoryTemplates.swift
//  The fallback writer that needs no model: a bank of pre-written one-sentence patterns with {slots}, picked from the facts with seeded variety.
//  About line: ONE plain sentence, at most 90 characters, that says one or two TRUE things from the fact sheet (a favourite, who they play with most, a routine, a trophy and what the next one
//  needs, that they have just moved in) in the way a parent would say it aloud. Every pattern names the facts it uses (`keys`); StoryGuard checks that the sheet backs them.
//  Friendship note: one plain sentence, at most 80 characters.
//  No pronouns (the game has no gender data): the name, or no subject. No stage directions. Every text that leaves here has passed `StoryGuard` with its real names in.
//  Pure Foundation (no game types), nonisolated.
//

import Foundation

nonisolated enum StoryNeed: String, Hashable, Sendable { case pers, act, spot, food, race, show, volley, recentRace, partner, emote, milestone, nap, newcomer, settled, notNewcomer }

nonisolated struct StoryPattern: Sendable {
    let id: Int
    let needs: Set<StoryNeed>
    /// The fact keys the sentence states (StoryGuard.allFactKeys).
    let keys: [String]
    let text: String
    /// A NEWS pattern: the fact key of the event it is about ("recentRace") and whether it needs a win (1), a non-win (2) or either (0).
    var news: String? = nil
    var cond = 0
}

nonisolated enum StoryTemplates {
    /// FNV-1a: a stable hash (Swift's `hashValue` changes every launch).
    static func fnv(_ parts: [String]) -> UInt64 {
        var h: UInt64 = 0xcbf29ce484222325
        for p in parts { for b in p.utf8 { h ^= UInt64(b); h = h &* 0x100000001b3 }; h ^= 0xff; h = h &* 0x100000001b3 }
        return h
    }

    private static func P(_ id: Int, _ needs: [StoryNeed], _ keys: [String], _ text: String) -> StoryPattern { StoryPattern(id: id, needs: Set(needs), keys: keys, text: text) }
    private static func NW(_ id: Int, _ key: String, _ cond: Int, _ text: String, extra: [String] = []) -> StoryPattern {
        StoryPattern(id: id, needs: [], keys: [key] + extra, text: text, news: key, cond: cond)
    }

    // MARK: the About bank (one sentence each)

    static let aboutBank: [StoryPattern] = [
        // a favourite
        P(1, [.food], ["favouriteFood"], "{A}'s favourite food is {FOOD}."),
        P(2, [.food], ["favouriteFood"], "{A} likes {FOOD} best."),
        P(3, [.food], ["favouriteFood"], "The treat {A} likes most is {FOOD}."),
        // a routine
        P(4, [.spot], ["favouriteSpot"], "{A} spends a lot of time {SPOT}."),
        P(5, [.spot], ["favouriteSpot"], "{A}'s favourite place in the room is {SPOT}."),
        P(6, [.spot], ["favouriteSpot"], "{A} has been {SPOT} a lot this week."),
        P(7, [.act], ["favouriteActivity"], "{A} has been {ACT} a lot this week."),
        P(8, [.act], ["favouriteActivity"], "{A} spends a lot of time {ACT}."),
        P(9, [.act], ["favouriteActivity"], "{A} likes {ACT}."),
        P(10, [.nap], ["nap"], "{A} naps a lot."),
        P(11, [.nap], ["nap"], "{A} is a big napper."),
        P(12, [.nap], ["nap"], "{A} has been napping a lot this week."),
        // who they play with
        P(13, [.partner], ["partner"], "{A} plays with {B} most."),
        P(14, [.partner], ["partner"], "{B} is the one {A} plays with most."),
        P(15, [.partner], ["partner"], "{A} and {B} play together a lot."),
        P(16, [.partner, .emote], ["partner", "topEmote"], "{A} and {B} are often {EMOTE}."),
        P(17, [.partner, .emote], ["partner", "topEmote"], "{A} plays with {B} most, often {EMOTE}."),
        // trophies and what is next
        P(18, [.race], ["raceWin"], "{A} has won a {RACE} race."),
        P(19, [.race], ["raceWin"], "{A} is a {RACE} race winner."),
        P(20, [.show], ["showCup"], "{A} has a {SHOW} cup from the Jelly Show."),
        P(21, [.volley], ["volleyWin"], "{A} has won a volleyball match."),
        P(22, [.milestone], ["raceMilestone"], "{A} needs {LEFT} for a new trophy."),
        P(23, [.milestone], ["raceMilestone"], "{A} is {LEFT} away from a new trophy."),
        // brand new
        P(25, [.newcomer], ["newcomer"], "{A} has only just moved in."),
        P(26, [.newcomer], ["newcomer"], "{A} is still settling in."),
        P(27, [.newcomer], ["newcomer"], "{A} is still getting to know the room."),
        P(28, [.newcomer, .pers], ["newcomer", "personality"], "{A} is a {PERS} type who has only just moved in."),
        P(29, [.newcomer, .food], ["newcomer", "favouriteFood"], "{A} has only just moved in and likes {FOOD} best."),
        P(30, [.settled], ["settled"], "{A} knows the room well by now."),
        // the personality type woven in
        P(31, [.pers], ["personality"], "{A} is a {PERS} type."),
        P(32, [.pers, .act, .notNewcomer], ["personality", "favouriteActivity"], "{A} is a {PERS} type who likes {ACT}."),
        P(33, [.pers, .food, .notNewcomer], ["personality", "favouriteFood"], "{A} is a {PERS} type whose favourite food is {FOOD}."),
        P(34, [.pers, .spot], ["personality", "favouriteSpot"], "{A} is a {PERS} type who likes it {SPOT}."),
        P(35, [.pers, .partner], ["personality", "partner"], "{A} is a {PERS} type who plays with {B} most."),
        P(36, [.pers, .nap], ["personality", "nap"], "{A} is a {PERS} type who naps a lot."),
        P(37, [.pers, .race], ["personality", "raceWin"], "{A} is a {PERS} type with a {RACE} race win."),
        // two facts, joined plainly
        P(38, [.partner, .food], ["partner", "favouriteFood"], "{A} plays with {B} most and likes {FOOD} best."),
        P(39, [.spot, .food], ["favouriteSpot", "favouriteFood"], "{A} spends a lot of time {SPOT} and likes {FOOD} best."),
        P(40, [.act, .food], ["favouriteActivity", "favouriteFood"], "{A} has been {ACT} lately and likes {FOOD} best."),
        P(41, [.race, .food], ["raceWin", "favouriteFood"], "{A} has won a {RACE} race and likes {FOOD} best."),
        P(42, [.race, .partner], ["raceWin", "partner"], "{A} has won a {RACE} race and plays with {B} most."),
        P(43, [.nap, .spot], ["nap", "favouriteSpot"], "{A} naps a lot and likes it {SPOT}."),
        P(44, [.nap, .food], ["nap", "favouriteFood"], "{A} naps a lot and likes {FOOD} best."),
        P(45, [.show, .food], ["showCup", "favouriteFood"], "{A} has a {SHOW} cup and likes {FOOD} best."),
        P(46, [.spot, .partner], ["favouriteSpot", "partner"], "{A} spends time {SPOT} and plays with {B} most."),
        P(47, [.act, .partner], ["favouriteActivity", "partner"], "{A} has been {ACT} and plays with {B} most."),
        P(48, [.volley, .food], ["volleyWin", "favouriteFood"], "{A} has won a volleyball match and likes {FOOD} best."),
        P(49, [.milestone, .partner], ["raceMilestone", "partner"], "{A} plays with {B} most and needs {LEFT} for a new trophy."),
    ]

    /// NEWS: what happened today or yesterday (StoryEvents.swift). When there is news the line says it; otherwise it falls back to the bank above.
    static let newsBank: [StoryPattern] = [
        NW(100, "recentRace", 1, "{A} won the {TIER} race {WHEN}."),
        NW(101, "recentRace", 2, "{A} ran the {TIER} race {WHEN}."),
        NW(102, "recentShow", 0, "{A} came {PLACE} at the {TIER} Jelly Show {WHEN}."),
        NW(103, "recentShow", 0, "{A} took part in the {TIER} Jelly Show {WHEN}."),
        NW(104, "recentVolley", 1, "{A} won a volleyball match on the {TIER} court {WHEN}."),
        NW(105, "recentVolley", 2, "{A} played volleyball on the {TIER} court {WHEN}."),
        NW(106, "recentPark", 0, "{A} went to the park {WHEN}."),
        NW(107, "recentPark", 0, "{A} had a day out at the park {WHEN}."),
        NW(108, "recentCafe", 0, "{A} went to the cafe {WHEN}."),
        NW(109, "recentCafe", 0, "{A} had a treat at the cafe {WHEN}."),
        NW(110, "recentBubbles", 0, "{A} played with bubbles {WHEN}."),
        NW(111, "recentBubbles", 0, "{A} chased bubbles {WHEN}."),
        NW(112, "recentBall", 0, "{A} played with the ball {WHEN}."),
        NW(113, "recentBath", 0, "{A} had a bath {WHEN}."),
        NW(114, "recentGroom", 0, "{A} was groomed {WHEN}."),
        NW(115, "recentTrick", 0, "{A} did a trick when asked {WHEN}."),
        NW(116, "recentMeal", 0, "{A} had a favourite meal {WHEN}."),
        NW(117, "recentMeal", 0, "{A} had {FOOD} {WHEN}, a favourite.", extra: ["favouriteFood"]),
        NW(118, "recentCuddle", 0, "{A} had a good cuddle {WHEN}."),
        NW(119, "recentBond", 0, "{A} has moved up to {LEVEL}."),
    ]

    // MARK: the friendship bank (one sentence each)

    enum Tier: String, Sendable { case close, regular, few }
    struct NotePattern: Sendable { let id: Int; let tiers: Set<Tier>; let emote: Bool; let keys: [String]; let text: String }
    private static func N(_ id: Int, _ tiers: [Tier], _ emote: Bool, _ text: String) -> NotePattern {
        let together = tiers.contains(.close) || tiers.contains(.regular)
        return NotePattern(id: id, tiers: Set(tiers), emote: emote, keys: (together ? ["together"] : ["gettingToKnow"]) + (emote ? ["topEmote"] : []), text: text)
    }

    static let noteBank: [NotePattern] = [
        N(1, [.close], false, "{A} and {B} play together more than anyone."),
        N(2, [.close], false, "{A} plays with {B} most of all."),
        N(3, [.close], false, "{B} is the one {A} plays with most."),
        N(4, [.close], false, "{A} and {B} spend most of their time together."),
        N(5, [.close], false, "{A} and {B} are close friends."),
        N(6, [.close], false, "{A} and {B} are hardly ever apart."),
        N(7, [.close], false, "{A} and {B} are the best of friends."),
        N(8, [.close, .regular], true, "{A} and {B} are often {EMOTE}."),
        N(9, [.close, .regular], true, "{A} and {B} have been {EMOTE} a lot."),
        N(10, [.close, .regular], true, "{A} and {B} spend a lot of time {EMOTE}."),
        N(11, [.close, .regular], true, "When {A} and {B} play, they are often {EMOTE}."),
        N(12, [.regular], false, "{A} and {B} play together now and then."),
        N(13, [.regular], false, "{A} plays with {B} fairly often."),
        N(14, [.regular], false, "{A} and {B} get on well."),
        N(15, [.regular], false, "{B} often joins {A} to play."),
        N(16, [.regular], false, "{A} and {B} have been playing together more lately."),
        N(17, [.regular], false, "{A} and {B} share the room and often play."),
        N(18, [.few], false, "{A} and {B} are still getting to know each other."),
        N(19, [.few], false, "{A} and {B} have only played together a little so far."),
        N(20, [.few], false, "{A} and {B} have not played together much yet."),
        N(21, [.few], false, "{A} and {B} are just getting started as friends."),
        N(22, [.few], false, "{A} is still getting to know {B}."),
        N(23, [.few], false, "{A} and {B} are getting used to each other."),
        N(24, [.few], false, "{A} and {B} mostly keep to themselves for now."),
        N(25, [.few, .regular], false, "{A} and {B} share the room."),
        N(26, [.few], false, "{A} and {B} say hello now and then."),
        N(27, [.regular, .close], false, "{A} and {B} play together a lot."),
        N(28, [.regular], false, "{A} and {B} play together some days."),
    ]

    // MARK: eligibility

    static func needs(_ f: StoryFacts) -> Set<StoryNeed> {
        let k = StoryFill.facts(f), v = StoryFill.values(f)
        var n: Set<StoryNeed> = []
        if k.contains("personality") { n.insert(.pers) }
        if k.contains("favouriteActivity") { n.insert(.act) }
        if k.contains("favouriteSpot") { n.insert(.spot) }
        if k.contains("favouriteFood") { n.insert(.food) }
        if k.contains("raceWin") { n.insert(.race) }
        if k.contains("showCup") { n.insert(.show) }
        if k.contains("volleyWin") { n.insert(.volley) }
        if k.contains("partner"), v["B"] != nil { n.insert(.partner) }
        if k.contains("topEmote") { n.insert(.emote) }
        if k.contains("raceMilestone") { n.insert(.milestone) }
        if k.contains("nap") { n.insert(.nap) }
        if f.newcomer { n.insert(.newcomer) } else { n.insert(.notNewcomer) }
        if k.contains("settled") { n.insert(.settled) }
        return n
    }

    static func tier(_ h: StoryFacts.Housemate) -> Tier {
        if h.togetherSeconds >= 300 && h.playShare >= 0.5 { return .close }
        if h.togetherSeconds >= 60 { return .regular }
        return .few
    }

    private static func order<T>(_ items: [T], id: (T) -> Int, seed: UInt64, salt: String) -> [T] {
        items.sorted { fnv([salt, String(seed), String(id($0))]) < fnv([salt, String(seed), String(id($1))]) }
    }

    // MARK: writing

    struct Written: Sendable, Equatable { var template: String; var ids: [Int]; var keys: [String]; var final: String; var rejected = 0 }

    /// The About line for `f`: the first pattern (in this seed's order, skipping the ones in `used` until the bank is through) that the sheet backs and the guard passes with the real names in.
    static func about(_ f: StoryFacts, used: Set<Int>, seed: UInt64) -> Written? {
        let have = needs(f), values = StoryFill.values(f), offered = Set(values.keys), avail = StoryFill.facts(f)
        var eligible = aboutBank.filter { $0.needs.isSubset(of: have) }
        if let n = f.news, avail.contains(n.factKey) {          // news first (today or yesterday); the bank above is the fallback
            let win = n.d["win"] == "1"
            let news = newsBank.filter { $0.news == n.factKey && ($0.cond == 0 || ($0.cond == 1) == win) }
            if !news.isEmpty { eligible = news }
        }
        var pool = eligible.filter { !used.contains($0.id) }
        if pool.count < 2 { pool = eligible }          // the bank is through: start over
        var rejected = 0
        let seeded = order(pool, id: \.id, seed: seed, salt: "f\(f.id)")
        let rest = order(eligible.filter { e in !pool.contains { $0.id == e.id } }, id: \.id, seed: seed, salt: "r\(f.id)")
        for p in seeded + rest {
            let fin = StoryFill.apply(p.text, values)
            let v = StoryGuard.check(template: p.text, final: fin, kind: .about, offered: offered, shown: f.shownParagraph, values: values, keys: p.keys, available: avail)
            if v.passed { return Written(template: p.text, ids: [p.id], keys: p.keys, final: fin, rejected: rejected) }
            rejected += 1
        }
        return nil
    }

    /// One friendship note for `f` about housemate `h`.
    static func friendship(_ f: StoryFacts, with h: StoryFacts.Housemate, used: Set<Int>, seed: UInt64) -> Written? {
        let t = tier(h)
        let values = StoryFill.values(f, with: h), offered = StoryFill.offered(f, with: h), avail = StoryFill.facts(f, with: h)
        let eligible = noteBank.filter { $0.tiers.contains(t) && (!$0.emote || values["EMOTE"] != nil) }
        var pool = eligible.filter { !used.contains($0.id) }
        if pool.isEmpty { pool = eligible }
        var rejected = 0
        let seeded = order(pool, id: \.id, seed: seed, salt: "n\(f.id)-\(h.id)")
        let rest = order(eligible.filter { e in !pool.contains { $0.id == e.id } }, id: \.id, seed: seed, salt: "m\(f.id)-\(h.id)")
        for p in seeded + rest {
            let fin = StoryFill.apply(p.text, values)
            if StoryGuard.check(template: p.text, final: fin, kind: .friendship, offered: offered, values: values, keys: p.keys, available: avail).passed {
                return Written(template: p.text, ids: [p.id], keys: p.keys, final: fin, rejected: rejected)
            }
            rejected += 1
        }
        return nil
    }
}
