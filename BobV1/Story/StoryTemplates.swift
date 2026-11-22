//
//  StoryTemplates.swift
//  The fallback writer that needs no model: a bank of pre-written sentence patterns with {slots}, picked from the facts with seeded variety.
//  About blurb (one or two short sentences, <= 110 characters): the bank below is about THEIR LIFE (lately, spot, food, trophies, who they play with, the personality type woven in, how settled
//  they are); it never says the colour or the kind (the static paragraph above it does). Friendship note (one sentence, <= 80 characters).
//  No pronouns (the game has no gender data): sentences use the name or no subject. Every text that leaves here has passed `StoryGuard` with its real names in.
//  Pure Foundation (no game types), nonisolated.
//

import Foundation

nonisolated enum StoryNeed: String, Hashable, Sendable { case pers, act, spot, food, race, show, volley, recent, together, nap, newcomer, settled, notNewcomer, history }

nonisolated struct StoryPattern: Sendable {
    enum Role { case first, second, either }
    let id: Int
    let role: Role
    /// What the sentence is about: a blurb never uses two sentences of one topic.
    let topic: String
    let needs: Set<StoryNeed>
    let text: String
}

nonisolated enum StoryTemplates {
    // MARK: seeds

    /// FNV-1a: a stable hash (Swift's `hashValue` changes every launch).
    static func fnv(_ parts: [String]) -> UInt64 {
        var h: UInt64 = 0xcbf29ce484222325
        for p in parts { for b in p.utf8 { h ^= UInt64(b); h = h &* 0x100000001b3 }; h ^= 0xff; h = h &* 0x100000001b3 }
        return h
    }

    // MARK: the About bank

    private static func P(_ id: Int, _ role: StoryPattern.Role, _ topic: String, _ needs: [StoryNeed], _ text: String) -> StoryPattern {
        StoryPattern(id: id, role: role, topic: topic, needs: Set(needs), text: text)
    }

    static let aboutBank: [StoryPattern] = [
        // personality
        P(1, .first, "pers", [.pers, .notNewcomer], "{A} is a {PERS} type through and through."),
        P(2, .first, "pers", [.pers, .notNewcomer], "{A} is the {PERS} one of the house."),
        P(3, .first, "pers", [.pers, .notNewcomer], "Everybody knows {A} as the {PERS} one."),
        P(4, .first, "pers", [.pers, .notNewcomer], "A {PERS} type, {A} has settled in well."),
        P(5, .either, "pers", [.pers, .notNewcomer], "{A} is a {PERS} little Jelmiko with a big heart."),
        // lately
        P(10, .first, "act", [.act, .history], "Lately {A} has been busy {ACT}."),
        P(11, .first, "act", [.act, .history], "{A} spends a lot of time {ACT}."),
        P(12, .first, "act", [.act, .history], "These days {A} is happiest {ACT}."),
        P(13, .first, "act", [.act, .history], "Most days {A} ends up {ACT}."),
        P(14, .either, "act", [.act, .history], "Lately {A} cannot get enough of {ACT}."),
        P(15, .either, "act", [.act, .history], "{A} has been {ACT} a lot lately."),
        P(16, .second, "act", [.act, .history], "Best of all, {A} likes {ACT}."),
        P(17, .first, "act", [.act, .pers, .history], "A {PERS} type, {A} has lately been {ACT}."),
        P(18, .first, "act", [.act, .pers, .history], "{A} is a {PERS} type who spends a lot of time {ACT}."),
        // spot
        P(20, .first, "spot", [.spot, .history], "Lately {A} likes to hang about {SPOT}."),
        P(21, .first, "spot", [.spot, .history], "{A} is often {SPOT}, watching the room."),
        P(22, .either, "spot", [.spot, .history], "{A} keeps coming back to the spot {SPOT}."),
        P(23, .second, "spot", [.spot, .history], "{A} likes it best {SPOT}."),
        P(24, .first, "spot", [.spot, .pers, .history], "{A} is a {PERS} type who likes it best {SPOT}."),
        // food
        P(30, .second, "food", [.food], "{A} never says no to {FOOD}."),
        P(31, .second, "food", [.food], "{A}'s favourite treat is {FOOD}."),
        P(32, .second, "food", [.food], "{A} comes running at the first sniff of {FOOD}."),
        P(33, .second, "food", [.food], "Nothing cheers {A} up like {FOOD}."),
        P(34, .second, "food", [.food], "{A} would pick {FOOD} every time."),
        P(35, .either, "food", [.food, .pers, .notNewcomer], "{A} is a {PERS} type with a soft spot for {FOOD}."),
        P(36, .second, "food", [.food, .newcomer], "So far, {A} has a soft spot for {FOOD} in the new home."),
        // trophies
        P(40, .second, "race", [.race], "{A} has won a {RACE} race, and it shows."),
        P(41, .second, "race", [.race], "A {RACE} race win sits on {A}'s shelf."),
        P(42, .either, "race", [.race], "{A} is a proper racer with a {RACE} win."),
        P(43, .second, "race", [.race, .pers], "A {PERS} type, {A} still found time to win a {RACE} race."),
        P(44, .second, "show", [.show], "{A} has a {SHOW} cup from the Jelly Show."),
        P(45, .either, "show", [.show], "{A} shone at the {SHOW} Jelly Show."),
        P(46, .second, "volley", [.volley], "{A} has won on the volleyball sand."),
        P(47, .second, "recent", [.recent], "{A} is still glowing from a recent win."),
        P(48, .first, "recent", [.recent], "A win came {A}'s way only the other day."),
        // company
        P(50, .second, "together", [.together, .history], "{A} is happiest with a housemate nearby."),
        P(51, .second, "together", [.together, .history], "{A} likes company and always finds a playmate."),
        P(52, .first, "together", [.together, .pers, .history], "A {PERS} type, {A} is happiest with a housemate nearby."),
        P(53, .second, "together", [.together, .history], "Playtime with the housemates is a favourite."),
        // sleep
        P(60, .either, "nap", [.nap], "{A} is a champion napper."),
        P(61, .second, "nap", [.nap], "A cosy nap is never far from {A}'s mind."),
        P(62, .second, "nap", [.nap], "Naps are a big part of {A}'s day."),
        P(63, .first, "nap", [.nap, .pers], "{A} is a {PERS} type who never turns down a nap."),
        // settled in
        P(70, .second, "settled", [.settled], "{A} knows every corner of the room by now."),
        P(71, .second, "settled", [.settled], "{A} has settled in as if it was always home."),
        P(72, .either, "settled", [.settled], "{A} has been a happy part of the home for a good while."),
        // brand new
        P(80, .first, "new", [.newcomer], "{A} has only just moved in, and everything is new."),
        P(81, .first, "new", [.newcomer], "{A} is settling in, one little sniff at a time."),
        P(82, .first, "new", [.newcomer], "New here, {A} is still finding the best spots."),
        P(83, .first, "new", [.newcomer], "{A} has only just arrived and is getting to know the room."),
        P(84, .second, "new2", [.newcomer], "Everything is new and worth a sniff."),
        P(85, .second, "new2", [.newcomer], "It is a big, bright new home to explore."),
        P(86, .second, "new2", [.newcomer, .pers], "A {PERS} type, {A} is already making a mark."),
        P(87, .second, "new2", [.newcomer], "Every day brings something new to wiggle at."),
        // always works
        P(90, .either, "any", [.notNewcomer], "{A} is a happy little Jelmiko."),
        P(91, .either, "any", [.notNewcomer], "{A} is a good Jelmiko to have around."),
        P(92, .either, "any", [.notNewcomer], "Home is a cosy place for {A}."),
        P(93, .second, "any2", [.notNewcomer], "There is always something to wiggle at."),
        P(94, .second, "any2", [.notNewcomer], "Every day has a little adventure in it."),
    ]

    // MARK: the friendship bank

    enum Tier: String, Sendable { case close, regular, few }
    struct NotePattern: Sendable { let id: Int; let tiers: Set<Tier>; let emote: Bool; let text: String }
    private static func N(_ id: Int, _ tiers: [Tier], _ emote: Bool, _ text: String) -> NotePattern { NotePattern(id: id, tiers: Set(tiers), emote: emote, text: text) }

    static let noteBank: [NotePattern] = [
        N(1, [.close], false, "{A} and {B} are the best of pals."),
        N(2, [.close], false, "{A} and {B} are hardly ever apart."),
        N(3, [.close], true, "{A} and {B} are inseparable, always {EMOTE}."),
        N(4, [.close], false, "{A} and {B} spend most of the day together."),
        N(5, [.close], false, "No one plays with {A} more than {B} does."),
        N(6, [.close], false, "{B} is {A}'s favourite playmate."),
        N(7, [.close, .regular], true, "{A} and {B} are often {EMOTE}."),
        N(8, [.regular], false, "{A} and {B} often play together."),
        N(9, [.regular, .close], false, "{A} and {B} make a happy pair."),
        N(10, [.regular, .close], false, "{A} has a lot of fun with {B}."),
        N(11, [.regular], false, "{B} often joins {A} for a bit of fun."),
        N(12, [.regular, .few], false, "{A} and {B} are good housemates."),
        N(13, [.regular, .few], false, "{A} and {B} share the room happily."),
        N(14, [.regular], true, "Sometimes {A} and {B} end up {EMOTE}."),
        N(15, [.regular, .close], true, "{A} and {B} have fun {EMOTE}."),
        N(16, [.regular], false, "{B} and {A} are good company for each other."),
        N(17, [.few], false, "{A} and {B} are still getting to know each other."),
        N(18, [.few], false, "{A} and {B} are warming up to each other."),
        N(19, [.few], false, "{A} is making friends with {B}, bit by bit."),
        N(20, [.few], false, "{A} and {B} say hello now and then."),
        N(21, [.few], false, "{A} is getting used to having {B} around."),
        N(22, [.few], false, "{A} is still learning what {B} likes best."),
        N(23, [.few], false, "Slowly, {A} and {B} are becoming friends."),
        N(24, [.few, .regular], false, "{A} shares a cosy home with {B}."),
        N(25, [.few, .regular], true, "{A} and {B} sometimes try {EMOTE}."),
        N(26, [.regular, .close], true, "{A} likes {EMOTE} with {B}."),
        N(27, [.regular, .few], false, "{A} and {B} are growing closer, one day at a time."),
        N(28, [.close], false, "{B} is never far from {A}."),
        N(29, [.close, .regular], false, "{A} and {B} keep each other company."),
        N(30, [.close, .regular], false, "With {B} around, {A} always has a playmate."),
        N(31, [.few, .regular], false, "{A} and {B} have their own little ways of saying hello."),
        N(32, [.close, .regular], false, "{A} and {B} are a good team."),
    ]

    // MARK: eligibility

    static func needs(_ f: StoryFacts) -> Set<StoryNeed> {
        var n: Set<StoryNeed> = []
        if f.personality != nil { n.insert(.pers) }
        if f.favouriteActivity != nil, StoryFill.values(f)["ACT"] != nil { n.insert(.act) }
        if f.favouriteSpot != nil, StoryFill.values(f)["SPOT"] != nil { n.insert(.spot) }
        if StoryFill.values(f)["FOOD"] != nil { n.insert(.food) }
        if f.trophies.raceWins > 0, f.trophies.bestRaceTier != nil { n.insert(.race) }
        if f.trophies.showCups > 0, f.trophies.bestShowRank != nil { n.insert(.show) }
        if f.trophies.volleyWins > 0 { n.insert(.volley) }
        if let d = f.trophies.recentDaysAgo, d <= 7, f.trophies.total > 0 { n.insert(.recent) }
        if f.togetherShare >= 0.12, f.housemates.contains(where: { $0.togetherSeconds >= 60 }) { n.insert(.together) }
        if f.sleepHabit != nil { n.insert(.nap) }
        if f.newcomer { n.insert(.newcomer) } else { n.insert(.notNewcomer) }
        if f.daysTracked >= 4 && !f.newcomer { n.insert(.settled) }
        if f.minutesSeen >= 5 { n.insert(.history) }
        return n
    }

    static func tier(_ h: StoryFacts.Housemate) -> Tier {
        if h.togetherSeconds >= 300 && h.playShare >= 0.5 { return .close }
        if h.togetherSeconds >= 60 { return .regular }
        return .few
    }

    /// Stable order of the candidates for this Jelmiko and this write: a hash of (seed, who, pattern id).
    private static func order<T>(_ items: [T], id: (T) -> Int, seed: UInt64, salt: String) -> [T] {
        items.sorted { fnv([salt, String(seed), String(id($0))]) < fnv([salt, String(seed), String(id($1))]) }
    }

    // MARK: writing

    struct Written: Sendable, Equatable { var template: String; var ids: [Int]; var final: String; var rejected = 0 }

    /// The About blurb for `f`: the first combination of patterns (in this seed's order, skipping the ones in `used` until the bank is through) that passes the guard with the real names in.
    /// Never nil in practice (the always-works patterns fit any facts); nil only if every candidate failed.
    static func about(_ f: StoryFacts, used: Set<Int>, seed: UInt64, kind: StoryKind = .about) -> Written? {
        let have = needs(f)
        let offeredTokens = StoryFill.offered(f)
        let values = StoryFill.values(f)
        let eligible = aboutBank.filter { $0.needs.isSubset(of: have) }
        var pool = eligible.filter { !used.contains($0.id) }
        if pool.count < 3 { pool = eligible }          // the bank is through: start over
        var firstPool = pool.filter { $0.role != .second }
        if f.newcomer { let n = firstPool.filter { $0.topic == "new" }; if !n.isEmpty { firstPool = n } }          // a brand-new Jelmiko's blurb opens with "just moved in"
        let firsts = order(firstPool, id: \.id, seed: seed, salt: "f\(f.id)")
        let seconds = order(pool.filter { $0.role != .first }, id: \.id, seed: seed, salt: "s\(f.id)")
        var rejected = 0
        func tryText(_ t: String, _ ids: [Int]) -> Written? {
            let fin = StoryFill.apply(t, values)
            let v = StoryGuard.check(template: t, final: fin, kind: .about, offered: offeredTokens, shown: f.shownParagraph, values: values)
            if v.passed { return Written(template: t, ids: ids, final: fin, rejected: rejected) }
            rejected += 1; return nil
        }
        // prefer the facts that are most specific: rank the first sentences by how many needs they use (more = more about this Jelmiko), then by the seed's order
        for p1 in firsts.prefix(8) {
            for p2 in seconds where p2.topic != p1.topic && p2.id != p1.id {
                if let w = tryText(p1.text + " " + p2.text, [p1.id, p2.id]) { return w }
                if rejected > 40 { break }
            }
        }
        for p in firsts + seconds { if let w = tryText(p.text, [p.id]) { return w } }
        for p in aboutBank.filter({ $0.needs.isSubset(of: have.intersection([.notNewcomer, .newcomer])) }) { if let w = tryText(p.text, [p.id]) { return w } }
        return nil
    }

    /// One friendship note for `f` about housemate `h`.
    static func friendship(_ f: StoryFacts, with h: StoryFacts.Housemate, used: Set<Int>, seed: UInt64) -> Written? {
        let t = tier(h)
        let hasEmote = StoryFill.values(f, with: h)["EMOTE"] != nil
        let values = StoryFill.values(f, with: h)
        let offeredTokens = StoryFill.offered(f, with: h)
        let eligible = noteBank.filter { $0.tiers.contains(t) && (!$0.emote || hasEmote) }
        var pool = eligible.filter { !used.contains($0.id) }
        if pool.isEmpty { pool = eligible }
        var rejected = 0
        // the unused ones first (in the seed's order), then, if none of them fits these names, the rest of the bank
        let seeded = order(pool, id: \.id, seed: seed, salt: "n\(f.id)-\(h.id)")
        for p in seeded + order(eligible.filter { e in !pool.contains { $0.id == e.id } }, id: \.id, seed: seed, salt: "m\(f.id)-\(h.id)") {
            let fin = StoryFill.apply(p.text, values)
            if StoryGuard.check(template: p.text, final: fin, kind: .friendship, offered: offeredTokens, values: values).passed { return Written(template: p.text, ids: [p.id], final: fin, rejected: rejected) }
            rejected += 1
        }
        return nil
    }
}
