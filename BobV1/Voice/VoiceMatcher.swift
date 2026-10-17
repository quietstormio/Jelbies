//
//  VoiceMatcher.swift
//  Voice v1: matching what the player said against the words Bob knows. Pure (no views, no audio).
//  Normalise (lowercase, no punctuation or diacritics) -> tokens + bigrams -> fuzzy match: Levenshtein (<= 1 for stored words of 4 letters
//  or fewer, <= 2 for longer) or the same Soundex key. His NAME also takes a prefix rule ("Bobby", "Bobbie" -> "Bob").
//  Name vs trick in one utterance ("sit down bob"): the name tokens are stripped first; what is left is matched against the tricks.
//  So name + trick = the trick (the name only gets his attention), and the name alone = the name lesson / perk-up.
//

import Foundation

nonisolated enum VoiceMatcher {
    /// Lowercase, strip diacritics and punctuation (letters and digits of any script stay), collapse spaces.
    static func normalise(_ s: String) -> String {
        let folded = s.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .init(identifier: "en_US_POSIX")).lowercased()
        var out = ""
        for ch in folded {
            if ch.isLetter || ch.isNumber { out.append(ch) } else { out.append(" ") }
        }
        return out.split(separator: " ").joined(separator: " ")
    }

    static func tokens(_ s: String) -> [String] {
        normalise(s).split(separator: " ").map(String.init)
    }

    /// Every token, every neighbouring pair ("sit down"), and the whole phrase when it is 3 words or fewer.
    static func candidates(_ toks: [String]) -> [String] {
        var out = toks
        if toks.count >= 2 { for i in 0..<(toks.count - 1) { out.append(toks[i] + " " + toks[i + 1]) } }
        if toks.count == 3 { out.append(toks.joined(separator: " ")) }
        return out
    }

    /// Loose "come here": any of these tokens, or the usual mishears ("calm here", "come hear", "c'mere" = "c mere", "come ear").
    static let comeTokens: Set<String> = ["come", "here", "hear", "ear", "mere", "cmere", "comere", "comehere", "kum", "cum"]
    static func looksLikeCome(_ toks: [String]) -> Bool {
        if toks.contains(where: { comeTokens.contains($0) }) { return true }
        for i in 0..<toks.count where toks[i] == "c" && i + 1 < toks.count && toks[i + 1] == "mere" { return true }
        return false
    }

    static func levenshtein(_ a: String, _ b: String) -> Int {
        let x = Array(a), y = Array(b)
        if x.isEmpty { return y.count }
        if y.isEmpty { return x.count }
        var prev = Array(0...y.count)
        for i in 1...x.count {
            var cur = [i] + Array(repeating: 0, count: y.count)
            for j in 1...y.count {
                cur[j] = min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + (x[i - 1] == y[j - 1] ? 0 : 1))
            }
            prev = cur
        }
        return prev[y.count]
    }

    /// Classic Soundex (letter + 3 digits) for ASCII letters; "" when the word has no ASCII letters (other scripts rely on edit distance).
    static func soundex(_ word: String) -> String {
        let letters = word.lowercased().filter { $0.isASCII && $0.isLetter }
        guard let first = letters.first else { return "" }
        func code(_ c: Character) -> Character? {
            switch c {
            case "b", "f", "p", "v": return "1"
            case "c", "g", "j", "k", "q", "s", "x", "z": return "2"
            case "d", "t": return "3"
            case "l": return "4"
            case "m", "n": return "5"
            case "r": return "6"
            default: return nil          // vowels, h, w, y
            }
        }
        var out = String(first).uppercased()
        var last = code(first)
        for c in letters.dropFirst() {
            let k = code(c)
            if let k, k != last { out.append(k) }
            if c != "h" && c != "w" { last = k }
            if out.count == 4 { break }
        }
        return out.padding(toLength: 4, withPad: "0", startingAt: 0)
    }

    /// 0 = no match. 1 exact, 0.9 / 0.8 one / two edits, 0.6 same sound.
    static func score(heard: String, stored: String) -> Float {
        if heard == stored { return 1 }
        let limit = stored.count <= 4 ? 1 : 2
        let d = levenshtein(heard, stored)
        if d <= limit && stored.count >= 2 { return 1 - 0.1 * Float(d) }
        // phonetic: single words only, 3+ letters each, similar length
        if !heard.contains(" ") && !stored.contains(" "), heard.count >= 3, stored.count >= 3, abs(heard.count - stored.count) <= 2 {
            let s = soundex(stored)
            if !s.isEmpty && s == soundex(heard) { return 0.6 }
        }
        return 0
    }

    struct Hit: Equatable {
        /// Index into the `words` that were searched.
        let index: Int
        let score: Float
    }

    /// Best stored word for what was said (highest score; ties go to the first). Empty stored words are skipped.
    static func best(in tokens: [String], among words: [String]) -> Hit? {
        let cands = candidates(tokens)
        var best: Hit?
        for (i, w) in words.enumerated() where !w.isEmpty {
            for c in cands {
                let s = score(heard: c, stored: w)
                if s > 0, s > (best?.score ?? 0) { best = Hit(index: i, score: s) }
            }
        }
        return best
    }

    /// How well one spoken token is "his name": exact, a close spelling, the same sound, or name + up to 3 letters ("Bobby", "Bobbie").
    /// 3-letter names allow no edit distance (rob, job, bog are not Bob); the prefix rule and Soundex still apply.
    static func nameScore(token: String, name: String) -> Float {
        guard !name.isEmpty, !token.isEmpty else { return 0 }
        if token == name { return 1 }
        if name.count >= 3, token.hasPrefix(name), token.count - name.count <= 3 { return 0.9 }
        if name.count >= 4, levenshtein(token, name) <= (name.count <= 4 ? 1 : 2) { return 0.8 }
        if token.count >= 3, name.count >= 3, abs(token.count - name.count) <= 1 {
            let s = soundex(name)
            if !s.isEmpty && s == soundex(token) { return 0.6 }
        }
        return 0
    }

    /// Splits an utterance into the name part and the rest. `nameScore` is the best name score over the tokens (0 = he was not addressed);
    /// `rest` is every token that is NOT the name, in order.
    static func splitName(tokens: [String], name: String) -> (nameScore: Float, rest: [String]) {
        var best: Float = 0
        var rest: [String] = []
        for t in tokens {
            let s = nameScore(token: t, name: name)
            if s > 0 { best = max(best, s) } else { rest.append(t) }
        }
        return (best, rest)
    }
}
