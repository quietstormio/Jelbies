//
//  VoiceNames.swift
//  Names every Jelly KNOWS from the start (no lesson): a registry keyed by Jelly id (0 Bob, 1 Pip, 2 Moss), their built-in pet forms and
//  recogniser near-misses, and the player's own nicknames (persisted per Jelly). Pure matching, no audio.
//
//  Matching is deliberately NOT generic edit distance for the short base names (a 3-4 letter name within 1 edit hits "bad", "bit", "mass",
//  "most", ...). Instead: the exact base, generated pet forms (Bobby, Bobbie, Bobo, Bobster, Bobbob ...), a curated near-miss list (Bab, Bop,
//  Pep, Pit, Moth, Mos ...), and a guarded phonetic key (first letter + vowel family + folded consonants) with a stoplist of real words that
//  share a key. Nicknames: exact, then edit distance 1 (5+ letters) or the same phonetic key (4+ letters).
//

import Foundation
import Observation

nonisolated struct JellyName: Equatable, Sendable {
    let id: Int
    let base: String
    /// Pet forms / diminutives (normalised, one token).
    let variants: Set<String>
    /// Things the recogniser tends to produce for this name.
    let nearMisses: Set<String>
    var display: String { base.prefix(1).uppercased() + base.dropFirst() }

    init(id: Int, base: String, extraVariants: [String] = [], nearMisses: [String]) {
        self.id = id; self.base = base
        var v: Set<String> = [base + base]
        let last = base.last.map(String.init) ?? ""
        let doubled = base.hasSuffix(last + last) ? base : base + last          // bob -> bobb, pip -> pipp, moss stays moss
        for suf in ["y", "ie", "o", "ster"] { v.insert(base + suf) }
        for suf in ["y", "ie", "o", "i"] { v.insert(doubled + suf) }
        v.formUnion(extraVariants)
        variants = v
        self.nearMisses = Set(nearMisses)
    }
}

nonisolated enum JellyNameRoster {
    static let all: [JellyName] = [
        JellyName(id: 0, base: "bob", extraVariants: ["bobbob", "bobbo", "bobs"], nearMisses: ["bab", "bop", "bahb", "baub", "bawb", "bobb"]),
        JellyName(id: 1, base: "pip", extraVariants: ["pipsqueak", "pipsqueaks", "pippip"], nearMisses: ["pep", "pit", "pipp", "peep", "pib"]),
        JellyName(id: 2, base: "moss", extraVariants: ["mossmoss", "mossa"], nearMisses: ["moth", "mos", "mauss", "moz", "mawss"]),
        JellyName(id: 3, base: "lavender", extraVariants: ["lav", "lavvy", "lavi", "lavenda"], nearMisses: ["lavander", "lavendar", "lavinder", "levender"]),
    ]
    static func name(_ id: Int) -> JellyName? { all.first { $0.id == id } }

    /// Real words that share a phonetic key with a name and must never count as it.
    static let stoplist: Set<String> = ["boob", "boobs", "pipe", "pipes", "mass", "maze", "muse", "mouse", "moose", "mousse", "mess", "miss", "most", "boss", "toss", "loss"]

    /// First letter, then the vowel family (F front i/e/y, B back a/o/u) and folded consonants (b=p, d=t, g=k=c=q, s=z=th), repeats collapsed,
    /// a trailing silent e dropped. "bob" "bop" "bab" "bub" -> bBP; "pip" "pep" "peep" -> pFP; "moss" "mos" "moth" -> mBS.
    static func phoneticKey(_ word: String) -> String {
        var w = word.lowercased().filter { $0.isASCII && $0.isLetter }
        guard let first = w.first else { return "" }
        w = w.replacingOccurrences(of: "th", with: "s").replacingOccurrences(of: "ph", with: "f")
        if w.count > 3, w.hasSuffix("e") { w.removeLast() }
        var out = String(first)
        var lastClass: Character?
        for c in w.dropFirst() {
            let cls: Character
            switch c {
            case "i", "e", "y": cls = "F"
            case "a", "o", "u": cls = "B"
            case "b", "p": cls = "P"
            case "d", "t": cls = "T"
            case "g", "k", "c", "q": cls = "K"
            case "s", "z": cls = "S"
            case "h", "w": continue
            default: cls = Character(c.uppercased())
            }
            if cls == "F" || cls == "B" {            // adjacent vowels: back wins ("ou", "oo" are back; "ee" front)
                if lastClass == "F" || lastClass == "B" {
                    if cls == "B", lastClass == "F" { out.removeLast(); out.append("B"); lastClass = "B" }
                    continue
                }
            } else if cls == lastClass { continue }
            out.append(cls); lastClass = cls
        }
        return out
    }
}

/// How well a spoken token (or token pair) is a Jelly's name.
nonisolated struct NameHit: Equatable, Sendable {
    let id: Int
    let score: Float
    /// How many tokens it used (2 for a two-word nickname).
    let width: Int
}

@MainActor
@Observable
final class JellyNames {
    static let defaultsKey = "JellyNicknames.v1"
    static let maxNicknames = 5
    /// The app-wide registry (every Jelly's voice book uses it; tests with their own defaults make their own).
    static let shared = JellyNames()
    /// Nicknames per Jelly id (normalised, 1-2 tokens).
    private(set) var nicknames: [Int: [String]] = [:]
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let key: String
    @ObservationIgnored private let persists: Bool

    nonisolated deinit {}

    init(defaults: UserDefaults = .standard, key: String = JellyNames.defaultsKey, persists: Bool = true) {
        self.defaults = defaults; self.key = key; self.persists = persists
        if persists {
            if defaults.bool(forKey: "VoiceReset") { defaults.removeObject(forKey: key) }
            if let d = defaults.data(forKey: key), let m = try? JSONDecoder().decode([String: [String]].self, from: d) {
                for (k, v) in m { if let id = Int(k) { nicknames[id] = v } }
            }
        }
    }

    func displayName(_ id: Int) -> String { JellyNameRoster.name(id)?.display ?? "Jelly" }
    func nicknames(for id: Int) -> [String] { nicknames[id] ?? [] }
    /// The words to hand the recogniser: every base name, pet form and nickname.
    var contextualWords: [String] {
        JellyNameRoster.all.flatMap { [$0.base] + $0.variants.sorted().prefix(6) } + nicknames.values.flatMap { $0 }
    }

    /// Adds a nickname for `id`. False = rejected (empty, too long, already a name of any Jelly, or the cap was reached).
    @discardableResult
    func addNickname(_ raw: String, for id: Int) -> Bool {
        let n = VoiceMatcher.normalise(raw)
        let toks = n.split(separator: " ")
        guard JellyNameRoster.name(id) != nil, !toks.isEmpty, toks.count <= 2, n.count >= 2, n.count <= 16 else { return false }
        guard !nicknames(for: id).contains(n), nicknames(for: id).count < Self.maxNicknames else { return false }
        if toks.count == 1, let h = match(token: n), h.score >= 0.8 { return false }          // already one of the names
        if nicknames.values.contains(where: { $0.contains(n) }) { return false }               // another Jelly's nickname
        nicknames[id, default: []].append(n)
        save()
        return true
    }

    func removeNickname(_ raw: String, for id: Int) {
        let n = VoiceMatcher.normalise(raw)
        nicknames[id]?.removeAll { $0 == n }
        if nicknames[id]?.isEmpty == true { nicknames[id] = nil }
        save()
    }

    func save() {
        guard persists else { return }
        var m: [String: [String]] = [:]
        for (k, v) in nicknames { m[String(k)] = v }
        if let d = try? JSONEncoder().encode(m) { defaults.set(d, forKey: key) }
    }

    // MARK: matching

    /// Best Jelly for one spoken token.
    func match(token t: String) -> NameHit? {
        guard !t.isEmpty else { return nil }
        var best: NameHit?
        func offer(_ id: Int, _ s: Float, _ w: Int = 1) { if s > (best?.score ?? 0) { best = NameHit(id: id, score: s, width: w) } }
        let key = JellyNameRoster.phoneticKey(t)
        let stop = JellyNameRoster.stoplist.contains(t)
        for n in JellyNameRoster.all {
            if t == n.base { offer(n.id, 1); continue }
            if n.variants.contains(t) { offer(n.id, 0.9); continue }
            if n.nearMisses.contains(t) { offer(n.id, 0.8); continue }
            if !stop, t.count >= 3, abs(t.count - n.base.count) <= 1, key == JellyNameRoster.phoneticKey(n.base) { offer(n.id, 0.65) }
        }
        for (id, list) in nicknames {
            for nick in list where !nick.contains(" ") {
                if t == nick { offer(id, 1) }
                else if nick.count >= 5, t.count >= 4, VoiceMatcher.levenshtein(t, nick) <= 1 { offer(id, 0.85) }
                else if nick.count >= 4, t.count >= 4, !stop, abs(t.count - nick.count) <= 1,
                        JellyNameRoster.phoneticKey(t) == JellyNameRoster.phoneticKey(nick), t.first == nick.first { offer(id, 0.6) }
            }
        }
        return best
    }

    /// Two-word nicknames ("mister bob") against a token pair.
    private func matchPair(_ a: String, _ b: String) -> NameHit? {
        let pair = a + " " + b
        for (id, list) in nicknames { for nick in list where nick.contains(" ") {
            if pair == nick || VoiceMatcher.levenshtein(pair, nick) <= (nick.count >= 8 ? 1 : 0) { return NameHit(id: id, score: pair == nick ? 1 : 0.85, width: 2) }
        } }
        return nil
    }

    /// Scans an utterance: the first name found (earliest) and every token that is not part of any name, in order.
    func resolve(tokens: [String]) -> (first: NameHit?, all: [NameHit], rest: [String]) {
        var rest: [String] = [], hits: [NameHit] = []
        var i = 0
        while i < tokens.count {
            if i + 1 < tokens.count, let h = matchPair(tokens[i], tokens[i + 1]) { hits.append(h); i += 2; continue }
            if let h = match(token: tokens[i]) { hits.append(h) } else { rest.append(tokens[i]) }
            i += 1
        }
        return (hits.first, hits, rest)
    }
}
