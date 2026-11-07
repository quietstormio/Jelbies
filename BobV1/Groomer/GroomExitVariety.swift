//
//  GroomExitVariety.swift
//  Leaving the Jelly Spa: a different slogan on the banner each visit (a non-repeating shuffle bag of 15) and a DIFFERENT happy solo emote per Jelbie in one exit.
//
import Foundation

nonisolated enum SpaSlogans {
    static let all: [String] = [
        "Fit for royalty! \u{2728}", "Freshly polished \u{2728}", "Simply radiant \u{2728}", "Glowing and gorgeous \u{2728}", "Pampered to perfection \u{2728}",
        "Spotless and shining \u{2728}", "A little luxury \u{2728}", "Polished and poised \u{2728}", "Feeling refreshed \u{2728}", "Shimmering softly \u{2728}",
        "Perfectly pampered \u{2728}", "Radiant as ever \u{2728}", "Beautifully refreshed \u{2728}", "Sparkling clean \u{2728}", "Looking splendid \u{2728}",
    ]
    /// A shuffle bag: every slogan once, in random order, then a new shuffle whose first is never the last one shown.
    struct Bag {
        var remaining: [Int] = []
        var last: Int?
        mutating func next<G: RandomNumberGenerator>(using g: inout G) -> Int {
            if remaining.isEmpty {
                var order = Array(0..<SpaSlogans.all.count).shuffled(using: &g)
                if let l = last, order.first == l, order.count > 1 { order.swapAt(0, order.count - 1) }
                remaining = order
            }
            let i = remaining.removeFirst(); last = i; return i
        }
    }
    private static let bagKey = "SpaSloganBag", lastKey = "SpaSloganLast"
    /// The next slogan, persisted across launches (the bag and the last one shown).
    static func next(defaults: UserDefaults = .standard) -> String {
        var bag = Bag(remaining: (defaults.array(forKey: bagKey) as? [Int] ?? []).filter { all.indices.contains($0) },
                      last: defaults.object(forKey: lastKey) as? Int)
        var g = SystemRandomNumberGenerator()
        let i = bag.next(using: &g)
        defaults.set(bag.remaining, forKey: bagKey); defaults.set(i, forKey: lastKey)
        return all[i]
    }
}

nonisolated enum SpaExitEmotes {
    /// Approved happy solo emotes (all existing; none touching / partner emotes, no nose boop / kiss).
    static let pool: [IdleKind] = [.joy, .bounce, .giggle, .tail, .politeBow, .signatureFlourish, .chirp]
    /// One emote per Jelbie, all different; avoids last visit's set when the pool allows.
    static func assign<G: RandomNumberGenerator>(count: Int, avoiding last: [IdleKind] = [], using g: inout G) -> [IdleKind] {
        let n = min(count, pool.count)
        let fresh = pool.filter { !last.contains($0) }
        var picks = Array(fresh.shuffled(using: &g).prefix(n))
        if picks.count < n { picks += pool.filter { !picks.contains($0) }.shuffled(using: &g).prefix(n - picks.count) }
        return picks.shuffled(using: &g)
    }
    nonisolated(unsafe) static var lastSet: [IdleKind] = []
}
