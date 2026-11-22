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
        // brand new
        P(25, [.newcomer], ["newcomer"], "{A} has only just moved in."),
        P(26, [.newcomer], ["newcomer"], "{A} is still settling in."),
        P(27, [.newcomer], ["newcomer"], "{A} is still getting to know the room."),
        P(28, [.newcomer, .pers], ["newcomer", "personality"], "{A} is a {PERS} type who has only just moved in."),
        P(29, [.newcomer, .food], ["newcomer", "favouriteFood"], "{A} has only just moved in and likes {FOOD} best."),
        // the personality type woven in
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
    struct NotePattern: Sendable {
        let id: Int; let tiers: Set<Tier>; let keys: [String]; let text: String
        var emote = false          // uses {EMOTE}
        var only: String?          // only when their top shared activity is exactly this SocialKind key
        var groupKinds: [String] = []          // only when the group session they shared most is one of these SocialKind keys
        var spot = false, nap = false
    }
    private static func N(_ id: Int, _ tiers: [Tier], _ keys: [String], _ text: String, emote: Bool = false, only: String? = nil, groupKinds: [String] = [], spot: Bool = false, nap: Bool = false) -> NotePattern {
        NotePattern(id: id, tiers: Set(tiers), keys: keys, text: text, emote: emote, only: only, groupKinds: groupKinds, spot: spot, nap: nap)
    }
    private static let tg = ["together"], few = ["gettingToKnow"]

    /// The row title on the Profile is the housemate's name, so a note has no subject and never repeats the names. The openings are varied on purpose: no opening word leads more than a fifth of the
    /// bank and "They" none (tested); the two notes on one Profile never start with the same word (`friendship(avoid:)`).
    static let noteBank: [NotePattern] = [
        // little time together (they have just met)
        N(1, [.few], few, "Only just met."),
        N(2, [.few], few, "Still new to each other."),
        N(3, [.few], few, "Just getting to know each other."),
        N(4, [.few], few, "Not much play together yet."),
        N(5, [.few], few, "Getting used to each other."),
        N(6, [.few], few, "Just getting started as friends."),
        // some play
        N(7, [.regular], tg, "Starting to play together."),
        N(8, [.regular], tg, "Play together now and then."),
        N(9, [.regular], tg, "Sometimes play together."),
        // most played with
        N(11, [.regular, .close], tg, "Play together a lot."),
        N(12, [.close], tg, "Together most of the day."),
        N(13, [.close], tg, "Hardly ever apart."),
        N(16, [.close], tg, "Inseparable."),
        N(17, [.close], tg, "Favourite playmate."),
        N(18, [.close], tg, "Spend most of their time together."),
        // what they do together most
        N(19, [.close, .regular], tg + ["topEmote"], "Often {EMOTE}.", emote: true),
        N(20, [.close, .regular], tg + ["topEmote"], "Always up for {EMOTE}.", emote: true),
        N(23, [.close, .regular], tg + ["topEmote"], "Chase is their favourite thing.", only: "chase"),
        N(24, [.close, .regular], tg + ["topEmote"], "Always up for a round of chase.", only: "chase"),
        N(25, [.close, .regular], tg + ["topEmote"], "Love a dance together.", only: "dance"),
        N(26, [.close, .regular], tg + ["topEmote"], "Often found side by side on the couch.", only: "cuddle"),
        N(27, [.close, .regular], tg + ["topEmote"], "Cuddles on the couch are a favourite.", only: "cuddle"),
        N(28, [.close, .regular], tg + ["topEmote"], "Lots of high fives.", only: "highFive"),
        N(29, [.close, .regular], tg + ["topEmote"], "Passing the ball about is their thing.", only: "pass"),
        N(30, [.close, .regular], tg + ["topEmote"], "Hopping along side by side.", only: "hopAlong"),
        // a shared spot and a shared habit
        N(31, [.close, .regular, .few], ["favouriteSpot", "sharedSpot"], "Both like it {SPOT}.", spot: true),
        N(32, [.close, .regular, .few], ["favouriteSpot", "sharedSpot"], "Share a favourite spot {SPOT}.", spot: true),
        N(33, [.close, .regular, .few], ["favouriteSpot", "sharedSpot"], "Often found {SPOT} together.", spot: true),
        N(34, [.close, .regular, .few], ["napBuddies"], "Nap buddies.", nap: true),
        N(35, [.close, .regular, .few], ["napBuddies"], "Both big nappers.", nap: true),
        // a group session they shared lately (only when the game knows which kind it was)
        N(36, [.close, .regular], tg + ["sharedGroup"], "Joined a conga line together.", groupKinds: ["conga", "congaLine"]),
        N(37, [.close, .regular], tg + ["sharedGroup"], "Shared a group hug lately.", groupKinds: ["groupHug"]),
        N(38, [.close, .regular], tg + ["sharedGroup"], "Danced in a ring together.", groupKinds: ["circleDance", "ringDance"]),
        N(39, [.close, .regular], tg + ["sharedGroup"], "Cheered together lately.", groupKinds: ["groupCheer"]),
    ]

    /// The first word of a note as it will be read (letters only, lower case).
    static func firstWord(_ text: String) -> String {
        String(text.split(separator: " ").first ?? "").lowercased().filter { $0.isLetter }
    }

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

    /// Sampled awake time together below which a long-time Jelmiko's row says nothing ("Still finding out"): about 10 minutes. The "little time together" notes belong to a real newcomer only.
    static let noteMinSeconds = 600
    static func noteAllowed(_ f: StoryFacts, _ h: StoryFacts.Housemate) -> Bool { f.newcomer || h.togetherSeconds >= noteMinSeconds }

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
        if f.newcomer, f.news == nil { let n = eligible.filter { $0.needs.contains(.newcomer) }; if !n.isEmpty { eligible = n } }          // a brand-new Jelmiko: "just moved in" lines only
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

    /// One friendship note for `f` about housemate `h`. `avoid`: opening words already used by the note above on the same Profile (never two notes that start alike).
    static func friendship(_ f: StoryFacts, with h: StoryFacts.Housemate, used: Set<Int>, seed: UInt64, avoid: Set<String> = []) -> Written? {
        guard noteAllowed(f, h) else { return nil }
        let t = tier(h)
        let values = StoryFill.values(f, with: h), offered = StoryFill.offered(f, with: h), avail = StoryFill.facts(f, with: h)
        let eligible = noteBank.filter { p in
            guard p.tiers.contains(t), !p.emote || values["EMOTE"] != nil, p.only == nil || p.only == h.topEmote, (p.groupKinds.isEmpty || (h.groupKind.map { p.groupKinds.contains($0) } ?? false)), !p.spot || (h.sharedSpot != nil && values["SPOT"] != nil), !p.nap || h.napBuddies else { return false }
            return !avoid.contains(firstWord(p.text))
        }
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
