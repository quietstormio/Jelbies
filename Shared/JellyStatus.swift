//
//  JellyStatus.swift
//  The words the Lock Screen, StandBy and Siri use for the Jelbies' state, built from the projected `JellyState`s (JellySnapshot.swift).
//  Pure text, shared by the app (Siri snippet / dialog) and the widget extension.
//

import Foundation

nonisolated enum JellyStatus {
    /// What a Jelbie is up to right now, in two words or so: "hungry", "napping", "happy", "fine", "sparkling".
    static func word(_ s: JellyState, sleeping: Bool) -> String {
        if sleeping, !s.needsAttention { return "napping" }
        let (c, t) = s.neediest
        if t.rawValue >= NeedTier.hungry.rawValue {
            switch c {
            case .food: return t.word(.hunger).lowercased()
            case .water: return t.word(.thirst).lowercased()
            case .heart: return t.word(.attention).lowercased()
            case .soap: return s.coat.word.lowercased()
            }
        }
        if sleeping { return "napping" }
        if s.coat == .beautiful { return "sparkling" }
        return s.mood == .happy ? "happy" : "fine"
    }

    /// "Bob is hungry · Pip napping · Moss fine" (the first gets "is", the rest are terse), or "Open the game" with nobody.
    static func line(_ states: [JellyState], sleeping: Bool) -> String {
        guard !states.isEmpty else { return "Open the game to meet your Jelbies" }
        let sorted = states.sorted { $0.id < $1.id }
        return sorted.enumerated().map { i, s in i == 0 ? "\(s.name) is \(word(s, sleeping: sleeping))" : "\(s.name) \(word(s, sleeping: sleeping))" }
            .joined(separator: " · ")
    }

    /// One short phrase for the inline Lock Screen slot: the neediest Jelbie, or "Everyone is napping" / "All N Jelbies are fine".
    static func inline(_ states: [JellyState], sleeping: Bool) -> String {
        guard !states.isEmpty else { return "Jelbies" }
        if let n = JellyState.neediest(in: states), n.needsAttention { return "\(n.name) is \(word(n, sleeping: false))" }
        if sleeping { return states.count == 1 ? "\(states[0].name) is napping" : "Everyone is napping" }
        if states.count == 1 { return "\(states[0].name) is \(word(states[0], sleeping: false))" }
        let happy = states.filter { $0.mood == .happy }.count
        return happy == states.count ? "All \(states.count) Jelbies are happy" : "All \(states.count) Jelbies are fine"
    }

    /// The Siri answer: one sentence per Jelbie with its mood and every item that wants care, e.g.
    /// "Bob is hungry and a little lonely. Pip is napping. Moss is happy and sparkling."
    static func spoken(_ states: [JellyState], sleeping: Bool) -> String {
        guard !states.isEmpty else { return noneYet }
        // Everyone fine and awake (2+): one sentence instead of near-identical ones.
        if states.count >= 2, !sleeping, !states.contains(where: \.needsAttention) {
            let allHappy = states.allSatisfy { $0.mood == .happy }
            if states.count == 2 {
                let names = joinNames(states.sorted { $0.id < $1.id }.map(\.name))
                return "\(names) are both \(allHappy ? "happy" : "doing fine")."
            }
            return "All \(states.count == 3 ? "three" : String(states.count)) are \(allHappy ? "happy" : "doing fine")."
        }
        return states.sorted { $0.id < $1.id }.map { sentence($0, sleeping: sleeping) }.joined(separator: " ")
    }

    static let noneYet = "You have not met your Jelbies yet. Open the game to say hello."

    /// "A", "A and B", "A, B and C".
    static func joinNames(_ names: [String]) -> String {
        switch names.count {
        case 0: return ""
        case 1: return names[0]
        default: return names.dropLast().joined(separator: ", ") + " and " + names.last!
        }
    }

    /// "Are my Jelbies asleep?": "Yes, Lemon and Pip are asleep." / "No, they are awake." (one Jelbie: "No, Lemon is awake.").
    /// When asleep and someone wants care, a short clause follows: "Pip will wake up hungry."
    static func asleepAnswer(_ states: [JellyState], sleeping: Bool) -> String {
        guard !states.isEmpty else { return noneYet }
        let sorted = states.sorted { $0.id < $1.id }
        let one = sorted.count == 1
        guard sleeping else { return one ? "No, \(sorted[0].name) is awake." : "No, they are awake." }
        var answer = "Yes, \(joinNames(sorted.map(\.name))) \(one ? "is" : "are") asleep."
        let wakes = sorted.filter(\.needsAttention).map { "\($0.name) will wake up \(wakeWord($0))" }
        if !wakes.isEmpty { answer += " " + joinNames(wakes) + "." }
        return answer
    }

    /// The need word for "will wake up ...": hungry, thirsty, lonely, dirty.
    private static func wakeWord(_ s: JellyState) -> String {
        let (c, t) = s.neediest
        switch c {
        case .food: return t.word(.hunger).lowercased() == "famished" ? "very hungry" : "hungry"
        case .water: return t.word(.thirst).lowercased() == "parched" ? "very thirsty" : "thirsty"
        case .heart: return "lonely"
        case .soap: return "dirty"
        }
    }

    /// "Are my Jelbies hungry?": food AND water. "Yes, Lemon is hungry and Pip is thirsty." / "Yes, Lemon is very hungry." (famished / parched)
    /// / "No, everyone has eaten." (one Jelbie: "No, Lemon is full."). `sleeping` does not change the answer (they would still be hungry).
    static func hungryAnswer(_ states: [JellyState], sleeping: Bool) -> String {
        guard !states.isEmpty else { return noneYet }
        _ = sleeping
        let sorted = states.sorted { $0.id < $1.id }
        var clauses: [String] = []
        for s in sorted {
            var wants: [String] = []
            let f = s.tier(.food), w = s.tier(.water)
            if f.rawValue >= NeedTier.hungry.rawValue { wants.append(f == .famished ? "very hungry" : "hungry") }
            if w.rawValue >= NeedTier.hungry.rawValue { wants.append(w == .famished ? "very thirsty" : "thirsty") }
            if !wants.isEmpty { clauses.append("\(s.name) is \(wants.joined(separator: " and "))") }
        }
        if clauses.isEmpty { return sorted.count == 1 ? "No, \(sorted[0].name) is full." : "No, everyone has eaten." }
        return "Yes, \(joinNames(clauses))."
    }

    static func sentence(_ s: JellyState, sleeping: Bool) -> String {
        var wants: [String] = []
        for c in JellyCare.allCases {
            let t = s.tier(c)
            guard t.rawValue >= NeedTier.hungry.rawValue else { continue }
            let w: String
            switch c {
            case .food: w = t.word(.hunger).lowercased()
            case .water: w = t.word(.thirst).lowercased()
            case .heart: w = t.word(.attention).lowercased()
            case .soap: w = t == .famished ? "really dirty" : "a bit dirty"
            }
            wants.append(t == .famished || c == .soap ? w : "a little \(w)")
        }
        if wants.isEmpty {
            if sleeping { return "\(s.name) is napping." }
            if s.coat == .beautiful { return "\(s.name) is happy and sparkling." }
            return s.mood == .happy ? "\(s.name) is happy." : "\(s.name) is doing fine."
        }
        let list: String
        switch wants.count {
        case 1: list = wants[0]
        case 2: list = "\(wants[0]) and \(wants[1])"
        default: list = wants.dropLast().joined(separator: ", ") + " and \(wants.last!)"
        }
        let mood = s.mood == .grumpy ? "\(s.name) is grumpy: " : "\(s.name) is "
        return "\(mood)\(list).\(sleeping ? " Still dozing, though." : "")"
    }

    /// How many Jelbies want something right now.
    static func needyCount(_ states: [JellyState]) -> Int { states.filter(\.needsAttention).count }
}
