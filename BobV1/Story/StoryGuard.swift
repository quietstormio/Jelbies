//
//  StoryGuard.swift
//  The one gate every sentence about a Jelmiko passes before it is shown or saved, whoever wrote it (the pre-written templates, or the on-device model in phase 2).
//
//  PLACEHOLDERS: a writer only ever sees and returns text with tokens such as {A}, {B}, {FOOD}, {KIND}, {RACE}; the real words (the player's names for the Jelmiko included)
//  are put in AFTER the guard (`StoryFill.apply`). So a name can never carry a bad word into a writer, and the guard looks at the template text (the writer's words) AND the final text.
//
//  Template text (what the writer wrote): characters, shape, voice, vocabulary, placeholders.
//  Final text (what the player would read): sentence count, length, full stop, no line break, language and tone (Apple's Natural Language framework).
//  Result: `.pass` or `.reject(reason)`; a rejected text is never shown: the caller moves on to the next writer / template.
//
//  Pure Foundation + NaturalLanguage, no game types, nonisolated (the writer runs off the main thread).
//

import Foundation
import NaturalLanguage
import UIKit

nonisolated enum StoryKind: String, Codable, Sendable { case about, friendship }

nonisolated enum StoryReason: Equatable, Sendable, CustomStringConvertible {
    case empty, lineBreak, quote, bracket, emoji, badCharacter, digit, allCaps, tooManyExclamations, noFullStop, sentenceCount, tooLong
    case firstPerson, secondPerson, question
    case denied(String), unknownPlaceholder(String), unfilledPlaceholder
    case notEnglish, negativeTone, tooWide, repeatsShown, strained, noFacts, unknownFact(String), missingFactKey(String)
    var description: String {
        switch self {
        case .empty: return "empty"
        case .lineBreak: return "line-break"
        case .quote: return "quote"
        case .bracket: return "bracket"
        case .emoji: return "emoji"
        case .badCharacter: return "bad-character"
        case .digit: return "digit"
        case .allCaps: return "all-caps"
        case .tooManyExclamations: return "too-many-exclamations"
        case .noFullStop: return "no-full-stop"
        case .sentenceCount: return "sentence-count"
        case .tooLong: return "too-long"
        case .firstPerson: return "first-person"
        case .secondPerson: return "second-person"
        case .question: return "question"
        case .denied(let w): return "denied:\(w)"
        case .unknownPlaceholder(let t): return "unknown-placeholder:\(t)"
        case .unfilledPlaceholder: return "unfilled-placeholder"
        case .notEnglish: return "not-english"
        case .negativeTone: return "negative-tone"
        case .tooWide: return "needs-a-third-line"
        case .repeatsShown: return "repeats-shown-text"
        case .strained: return "strained-phrase"
        case .noFacts: return "no-fact-named"
        case .unknownFact(let k): return "unknown-fact:\(k)"
        case .missingFactKey(let k): return "fact-not-named:\(k)"
        }
    }
}

nonisolated enum StoryVerdict: Equatable, Sendable, CustomStringConvertible {
    case pass
    case reject(StoryReason)
    var passed: Bool { self == .pass }
    var description: String { if case .reject(let r) = self { return "reject(\(r))" }; return "pass" }
}

nonisolated enum StoryGuard {
    // MARK: the limits

    /// About blurb: ONE plain sentence, at most this many characters (the final text, names included): two lines in its bubble. (The owner cut it from 130 to 110 to 90.)
    static let aboutMaxChars = 90, aboutSentences = 1
    /// Friendship note: one sentence, at most this many characters.
    static let noteMaxChars = 60, noteSentences = 1
    /// Tone: NLTagger's paragraph sentiment (-1...1) of the final text must be at least this. NLTagger scores in steps of 0.2 and is very noisy on short factual sentences (measured on the Mac: "Zed naps a lot." -0.8, "Luna naps a lot." -0.2, "The dog is sad and hurt." -0.6, "Berry is not happy at all." -1.0), so it cannot tell a plain line from an unkind one. It is only a backstop for the very negative (it rejects -1.0); the deny list and the fact check do the real work.
    static let sentimentMin = -0.9
    /// Language: NLLanguageRecognizer's confidence for English must be at least this on the final text.
    static let englishMin = 0.60

    static func maxChars(_ k: StoryKind) -> Int { k == .about ? aboutMaxChars : noteMaxChars }
    static func sentences(_ k: StoryKind) -> Int { k == .about ? aboutSentences : noteSentences }
    static func sentenceRange(_ k: StoryKind) -> ClosedRange<Int> { 1...sentences(k) }

    // MARK: the one function

    /// `template`: the writer's text WITH placeholders. `final`: the same text with the real words put in. `offered`: the placeholder names the writer was allowed ("A", "B", "FOOD" ...).
    /// `checkTone`: false only for the pure-shape tests that must not depend on the language model's mood.
    /// `shown`: text the screen already shows next to this one (the static kind paragraph: colour and character note); an About blurb must not repeat it (`repeatsShown`).
    static func check(template: String, final: String, kind: StoryKind, offered: Set<String>, shown: String? = nil, values: [String: String]? = nil, keys: [String]? = nil, available: Set<String>? = nil, checkTone: Bool = true) -> StoryVerdict {
        if let r = checkTemplate(template, kind: kind, offered: offered) { return .reject(r) }
        if kind == .about, repeatsShown(masked(template), shown: shown) { return .reject(.repeatsShown) }
        if let r = checkFacts(template, kind: kind, keys: keys, available: available) { return .reject(r) }
        if let r = checkFinal(final, kind: kind, checkTone: checkTone, toneText: values.map { toneText(template, $0) }) { return .reject(r) }
        return .pass
    }

    // MARK: template text

    static let tokenPattern = try! NSRegularExpression(pattern: "\\{([A-Z]+)\\}")

    static func tokens(in text: String) -> [String] {
        let ns = text as NSString
        return tokenPattern.matches(in: text, range: NSRange(location: 0, length: ns.length)).map { ns.substring(with: $0.range(at: 1)) }
    }

    /// The text with every well-formed token replaced by a plain stand-in word ("Zed"), for the scans that must not see a token.
    static func masked(_ text: String) -> String {
        tokenPattern.stringByReplacingMatches(in: text, range: NSRange(location: 0, length: (text as NSString).length), withTemplate: "Zed")
    }

    static func checkTemplate(_ t: String, kind: StoryKind, offered: Set<String>) -> StoryReason? {
        if t.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return .empty }
        if t.contains(where: { $0.isNewline }) || t.contains("\t") || t.unicodeScalars.contains(where: { $0.value < 0x20 || $0.value == 0x2028 || $0.value == 0x2029 }) { return .lineBreak }
        for tok in tokens(in: t) where !offered.contains(tok) { return .unknownPlaceholder(tok) }
        let m = masked(t)
        if m.unicodeScalars.contains(where: isEmojiLike) { return .emoji }
        if m.contains(where: { "\"\u{201C}\u{201D}\u{2018}\u{00AB}\u{00BB}`".contains($0) }) { return .quote }
        if m.contains(where: { "()[]{}<>".contains($0) }) { return .bracket }
        if m.contains(where: { $0.isNumber }) { return .digit }
        // The whole alphabet of a writer's text: ASCII letters, space, comma, full stop, exclamation mark, apostrophe, hyphen. Anything else (a question mark, a colon, a symbol, a dash) is not a Jelmiko sentence.
        for ch in m.unicodeScalars where !allowed.contains(ch) {
            return ch == "?" ? .question : .badCharacter
        }
        if m.contains("..") { return .badCharacter }
        if m.filter({ $0 == "!" }).count > 1 { return .tooManyExclamations }
        if let w = shouting(m) { _ = w; return .allCaps }
        if !m.trimmingCharacters(in: .whitespaces).hasSuffix(".") { return .noFullStop }
        if isQuestion(m) { return .question }
        if let r = voice(m) { return r }
        if let w = denied(m, raw: t) { return .denied(w) }
        if strained(m) { return .strained }
        let n = sentenceCount(m)
        if !sentenceRange(kind).contains(n) { return .sentenceCount }
        return nil
    }

    private static let allowed: CharacterSet = {
        var s = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ")
        s.insert(charactersIn: " ,.!'-\u{2019}")
        return s
    }()

    static func isEmojiLike(_ s: Unicode.Scalar) -> Bool {
        if s.properties.isEmojiPresentation { return true }
        let v = s.value
        return v >= 0x1F000 || (0x2190...0x21FF).contains(v) || (0x2300...0x23FF).contains(v) || (0x2600...0x27BF).contains(v) || (0x2B00...0x2BFF).contains(v) || v == 0xFE0F || v == 0x200D || v == 0x20E3 || (0xE0000...0xE007F).contains(v)
    }

    /// An ALL CAPS word (two or more letters, none lower case).
    static func shouting(_ m: String) -> String? {
        for w in m.split(whereSeparator: { !$0.isLetter }) where w.count >= 2 && w == w.uppercased() { return String(w) }
        return nil
    }

    static func sentenceCount(_ m: String) -> Int {
        var n = 0, pending = false
        for ch in m {
            if ch == "." || ch == "!" || ch == "?" { if pending { n += 1; pending = false } }
            else if ch.isLetter { pending = true }
        }
        return n + (pending ? 1 : 0)
    }

    private static let questionStart = try! NSRegularExpression(pattern: "(^|[.!]\\s+)(who|what|why|where|do|does|did|is|are|can|could|will|would|shall|should)\\s", options: [.caseInsensitive])
    static func isQuestion(_ m: String) -> Bool {
        m.contains("?") || questionStart.firstMatch(in: m, range: NSRange(location: 0, length: (m as NSString).length)) != nil
    }

    private static let voiceWords = try! NSRegularExpression(
        pattern: "(?<![A-Za-z'\u{2019}])(i|i'm|i'll|i've|i'd|me|my|mine|myself|we|we're|we'll|we've|us|our|ours|ourselves|you|you're|you'll|you've|you'd|your|yours|yourself|yourselves)(?![A-Za-z'\u{2019}])", options: [.caseInsensitive])
    static func voice(_ m: String) -> StoryReason? {
        let ns = m as NSString
        guard let hit = voiceWords.firstMatch(in: m, range: NSRange(location: 0, length: ns.length)) else { return nil }
        let w = ns.substring(with: hit.range).lowercased()
        return w.hasPrefix("you") || w == "your" || w == "yours" ? .secondPerson : .firstPerson
    }

    // MARK: the deny list (ONE editable place)

    /// Whole-word, case-insensitive; each entry is a regex fragment (plurals and endings spelt out). Add words here and nowhere else.
    static let denyWords: [String] = [
        // romance
        "kiss\\w*", "smooch\\w*", "dat(?:e|es|ed|ing)", "boyfriends?", "girlfriends?", "sweethearts?", "crush(?:es|ed)?", "marry", "married", "marriage", "wed(?:ding|s)?", "husbands?", "wives", "wife", "lovers?", "lovebirds?",
        "romantic", "romance", "honey", "darling", "babe", "baby", "sexy", "flirt\\w*", "hottie", "passion\\w*", "adore[sd]?", "desire", "in love", "falls? in love", "fell in love", "soulmates?", "mates?", "mating",
        // body and bathroom
        "poo\\w*", "pee", "peed", "peeing", "wee", "toilets?", "bathrooms?", "potty", "diapers?", "butt\\w*", "bum", "bums", "bottoms?", "fart\\w*", "burp\\w*", "belch\\w*", "snot\\w*", "boogers?", "vomit\\w*", "puke", "pukes", "sick",
        "drool\\w*", "spit", "sweat\\w*", "stink\\w*", "smelly", "sniffles", "naked", "nude", "underwear", "pants", "bare", "breasts?", "nipples?", "penis", "private parts", "belly button",
        // violence, injury, illness, death
        "fight\\w*", "hit", "hits", "hitting", "punch\\w*", "kick(?:s|ed|ing)? (?:out|off)", "bite[sd]?", "biting", "kill\\w*", "hurt\\w*", "injur\\w*", "wound\\w*", "bleed\\w*", "blood\\w*", "pain\\w*", "ouch", "cry", "cries", "cried", "crying", "tears?", "weep\\w*",
        "ill", "illness", "disease\\w*", "fever", "cough\\w*", "sneez\\w*", "flu", "cold", "virus", "germs?", "doctors?", "hospital", "medicine", "pills?", "dead", "die", "dies", "died", "dying", "death", "dies", "funeral", "grave", "ghosts?", "weapons?", "guns?", "swords?", "knives", "knife", "bombs?", "war",
        "attack\\w*", "hate[sd]?", "hating", "angry", "anger", "mad", "furious", "rage", "squabbl\\w*", "argu\\w*", "quarrel\\w*", "bully", "bullies", "bullied", "mean", "nasty", "rude", "violent", "violence", "destroy\\w*", "smash\\w*", "break(?:s|ing)?", "broke\\w*",
        // scary
        "scary", "scared", "scare[sd]?", "afraid", "fear\\w*", "terrif\\w*", "horrible", "horror", "monsters?", "nightmares?", "creepy", "spooky", "danger\\w*", "panic\\w*", "alone", "lonely", "lost", "abandon\\w*", "trapped", "dark",
        // money and shop
        "money", "coins?", "jellycoins?", "dollars?", "cash", "buy", "buys", "bought", "buying", "sell\\w*", "sold", "shop\\w*", "store", "stores", "price\\w*", "cost\\w*", "pay\\w*", "paid", "rich", "poor", "purchas\\w*", "sale", "discount\\w*", "wallet", "bank", "drops?",
        // brands, places, people
        "disney", "pokemon", "nintendo", "mario", "pikachu", "lego", "minecraft", "roblox", "google", "apple", "iphone", "ipad", "android", "youtube", "tiktok", "facebook", "instagram", "netflix", "amazon", "coca", "cola", "pepsi", "mcdonald\\w*", "nike", "barbie", "hello kitty", "peppa",
        "america\\w*", "england", "london", "paris", "china", "japan", "france", "europe", "africa", "asia", "australia", "canada", "texas", "california", "new york", "trump", "biden", "obama", "santa",
        // religion and politics
        "god", "gods", "jesus", "church", "pray\\w*", "heaven", "hell", "devil", "demons?", "angels?", "bible", "allah", "buddha", "religio\\w*", "politic\\w*", "president", "election", "vote", "votes", "voting", "government", "party", "republican", "democrat",
        // insults
        "stupid", "dumb", "idiot\\w*", "silly billy", "fat", "ugly", "loser", "hate", "shut up", "jerk", "brat", "naughty", "bad", "worst", "useless", "boring", "lazy", "greedy", "spoiled", "selfish", "grumpy", "grouchy", "moody", "sulk\\w*", "whin\\w*", "mope\\w*", "sad", "unhappy", "miserable", "gloomy",
        // the machinery (never say what the text is, or where it is read)
        "ai", "a\\.i", "models?", "generated", "generate", "algorithm", "bots?", "robots?", "computers?", "apps?", "phones?", "players?", "gamers?", "games?", "screens?", "levels?", "score\\w*", "points?", "download\\w*", "online", "internet", "wifi", "software", "program", "code", "update[sd]?",
    ]
    /// Patterns that are not single words: love as a verb between two creatures, and its romantic compounds.
    static let denyPatterns: [(name: String, regex: String)] = [
        ("love-between", "\\blov(?:e|es|ed|ing)\\s+(?:really |so |truly )?(?:\\{(?:A|B|C|BKIND)\\}|(?:each other|one another|them|him|her)\\b)"),
        ("love-between-2", "\\b(?:\\{(?:A|B|C)\\}|\\w+)\\s+and\\s+(?:\\{(?:A|B|C)\\}|\\w+)\\s+(?:really |so |truly )?lov(?:e|ed)\\s+(?:each|one)\\b"),
        ("love-with", "\\blove\\s+with\\b"),
        ("loved-ones", "\\bloved ones\\b"),
    ]

    private static let denyRegex: [(String, NSRegularExpression)] = {
        let joined = denyWords.map { "\\b(?:\($0))\\b" }
        var out: [(String, NSRegularExpression)] = []
        for (w, p) in zip(denyWords, joined) { if let r = try? NSRegularExpression(pattern: p, options: [.caseInsensitive]) { out.append((w, r)) } }
        for p in denyPatterns { if let r = try? NSRegularExpression(pattern: p.regex, options: [.caseInsensitive]) { out.append((p.name, r)) } }
        return out
    }()

    /// The first deny-listed word or pattern in `m` (tokens already masked), nil when clean. The pattern check is run on the unmasked text by `denied(unmasked:)`.
    static func denied(_ m: String, raw: String? = nil) -> String? {
        let range = NSRange(location: 0, length: (m as NSString).length)
        let rawRange = NSRange(location: 0, length: ((raw ?? m) as NSString).length)
        for (name, r) in denyRegex {
            // the token-aware patterns (love between two creatures) read the raw text with its {A} {B}; the word list reads the masked text
            if name.hasPrefix("love-") || name == "loved-ones" { if r.firstMatch(in: raw ?? m, range: rawRange) != nil { return name } }
            else if r.firstMatch(in: m, range: range) != nil { return name }
        }
        return nil
    }

    // MARK: traceable to the fact sheet

    /// Which fact each placeholder stands for. A text that uses one must name that fact.
    static let tokenFact: [String: String] = ["FOOD": "favouriteFood", "ACT": "favouriteActivity", "SPOT": "favouriteSpot", "RACE": "raceWin", "SHOW": "showCup", "PERS": "personality", "EMOTE": "topEmote", "LEFT": "raceMilestone"]
    /// Every fact key a text may name (the writers' vocabulary; the model's guide lists these).
    static let allFactKeys = ["personality", "favouriteFood", "favouriteActivity", "favouriteSpot", "raceWin", "showCup", "volleyWin", "partner", "topEmote", "nap", "newcomer", "settled", "raceMilestone", "together", "gettingToKnow", "sharedGroup", "sharedSpot", "napBuddies", "bond"] + StoryEvent.kinds.map { "recent" + $0.prefix(1).uppercased() + $0.dropFirst() }

    /// The line must name at least one fact, every named fact must be on the sheet (true), and every fact placeholder it uses must be named. `keys` nil = not checked (pure-shape tests).
    static func checkFacts(_ t: String, kind: StoryKind, keys: [String]?, available: Set<String>?) -> StoryReason? {
        guard let keys else { return nil }
        if keys.isEmpty { return .noFacts }
        if let available { for k in keys where !available.contains(k) { return .unknownFact(k) } }
        for tok in tokens(in: t) { if let need = tokenFact[tok], !keys.contains(need) { return .missingFactKey(need) } }
        if kind == .about, tokens(in: t).contains("B"), !keys.contains("partner") { return .missingFactKey("partner") }
        if !Set(tokens(in: t)).isDisjoint(with: ["WHEN", "TIER", "PLACE", "LEVEL"]), !keys.contains(where: { $0.hasPrefix("recent") }) { return .missingFactKey("recent news") }
        return nil
    }

    // MARK: strained phrases (editable)

    /// Stage directions and strained verbs the owner does not want ("trots over the moment ... appears"). Whole-phrase, case-insensitive. Add to it, nowhere else.
    static let strainedPhrases: [String] = [
        "trots over", "trots", "the moment", "never says no", "never say no", "every time", "a little spin", "comes running", "cannot get enough", "through and through", "as if it was always", "wiggle at",
        "adventure", "big, bright", "big heart", "makes a mark", "making a mark", "cheers up", "ends up", "can often be found", "keeps coming back", "hang about", "sniff", "pick every", "is happiest",
        "does a little", "dances for joy", "shone", "shows", "proper racer", "glowing", "champion napper", "little jelmiko", "good jelmiko", "happy little",
    ]
    /// Pronouns that would guess a gender (the game has none): a Jelmiko is its name.
    static let pronounPattern = try! NSRegularExpression(pattern: "(?<![A-Za-z'\u{2019}])(he|she|him|her|hers|his|himself|herself|he's|she's|he'll|she'll)(?![A-Za-z'\u{2019}])", options: [.caseInsensitive])
    static func strained(_ m: String) -> Bool {
        let l = m.lowercased()
        if strainedPhrases.contains(where: { l.contains($0) }) { return true }
        return pronounPattern.firstMatch(in: m, range: NSRange(location: 0, length: (m as NSString).length)) != nil
    }

    // MARK: not repeating the static paragraph

    /// Colour words an About blurb never uses (the static paragraph above it says the colour, for every skin).
    static let colourWords: Set<String> = ["pink", "rose", "blue", "yellow", "purple", "violet", "green", "orange", "red", "white", "black", "grey", "gray", "silver", "gold", "golden", "brown", "teal", "mint", "lilac",
                                           "peach", "cream", "pale", "patches", "patch", "spots", "spotted", "stripes", "striped", "shade", "colour", "color", "coloured", "gradient", "shimmer", "shimmering", "glitter"]
    private static let plain: Set<String> = ["the", "and", "that", "this", "with", "then", "than", "from", "they", "their", "them", "when", "what", "have", "has", "had", "are", "was", "were", "for", "but", "not", "one", "all", "any",
                                             "can", "will", "just", "very", "more", "most", "some", "into", "over", "out", "its", "her", "his", "she", "who", "how", "now", "too", "also", "still", "always", "never", "every", "each", "about"]
    private static func words(_ t: String) -> [String] { t.lowercased().split(whereSeparator: { !$0.isLetter && $0 != "'" }).map(String.init) }

    /// True when the blurb uses a colour word, or repeats the static paragraph: a run of three of its words, or two of its own content words (a character note like "shy at first" / "friendliest").
    static func repeatsShown(_ m: String, shown: String?) -> Bool {
        let w = words(m)
        if w.contains(where: { colourWords.contains($0) }) { return true }
        guard let shown, !shown.isEmpty else { return false }
        let s = words(shown)
        if w.count >= 3, s.count >= 3 {
            let grams = Set((0...(s.count - 3)).map { s[$0...($0 + 2)].joined(separator: " ") })
            if (0...(w.count - 3)).contains(where: { grams.contains(w[$0...($0 + 2)].joined(separator: " ")) }) { return true }
        }
        let content = Set(s.filter { $0.count >= 4 && !plain.contains($0) })
        return Set(w.filter { content.contains($0) }).count >= 2
    }

    // MARK: final text

    /// The text the language and tone checks read: the real values put in, but the names (the player's own words) replaced by stand-ins, so a name can never tip the tone.
    static func toneText(_ template: String, _ values: [String: String]) -> String {
        var v = values
        v["A"] = "Rosie"; v["B"] = "Max"; v["C"] = "Pip"; v["BKIND"] = "friend"
        return StoryFill.apply(template, v)
    }

    static func checkFinal(_ f: String, kind: StoryKind, checkTone: Bool, toneText: String? = nil) -> StoryReason? {
        if f.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return .empty }
        if f.contains(where: { $0.isNewline }) || f.unicodeScalars.contains(where: { $0.value < 0x20 }) { return .lineBreak }
        if f.contains("{") || f.contains("}") { return .unfilledPlaceholder }
        if f.unicodeScalars.contains(where: isEmojiLike) { return .emoji }
        if f.count > maxChars(kind) { return .tooLong }
        if !f.hasSuffix(".") { return .noFullStop }
        if !sentenceRange(kind).contains(sentenceCount(f)) { return .sentenceCount }
        // the Profile's slots hold two lines at the narrowest phone (375 pt): a longer text is refused here, never cut with "..." on screen
        if !fitsLines(f, width: kind == .about ? StoryLayout.lineWidth : StoryLayout.noteWidth, size: kind == .about ? StoryLayout.lineSize : StoryLayout.noteSize, lines: 2) { return .tooWide }
        if checkTone {
            let t = toneText ?? f
            if !isEnglish(t) { return .notEnglish }
            if sentiment(t) < sentimentMin { return .negativeTone }
        }
        return nil
    }

    /// True when `text` wraps to at most `lines` lines in a column `width` wide at semibold rounded `size` (the Profile's own face, measured with UIKit; a 4 % margin for the font's own width).
    static func fitsLines(_ text: String, width: CGFloat, size: CGFloat, lines: Int) -> Bool {
        var font = UIFont.systemFont(ofSize: size, weight: .semibold)
        if let d = font.fontDescriptor.withDesign(.rounded) { font = UIFont(descriptor: d, size: size) }
        let ns = NSAttributedString(string: text, attributes: [.font: font])
        let r = ns.boundingRect(with: CGSize(width: width * 0.96, height: .greatestFiniteMagnitude), options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil)
        return Int((r.height / font.lineHeight).rounded()) <= lines
    }

    // MARK: Natural Language

    static func englishConfidence(_ text: String) -> Double {
        let r = NLLanguageRecognizer()
        r.processString(text)
        return r.languageHypotheses(withMaximum: 5)[.english] ?? 0
    }
    static func isEnglish(_ text: String) -> Bool {
        let r = NLLanguageRecognizer()
        r.processString(text)
        let c = r.languageHypotheses(withMaximum: 5)[.english] ?? 0
        // a very short phrase ("Nap buddies.") cannot be told apart reliably: English only has to be a real candidate; the alphabet, the deny list and the facts check still apply
        if text.count < 26 { return r.dominantLanguage == .english || c >= 0.25 }
        return r.dominantLanguage == .english && c >= englishMin
    }

    /// NLTagger's sentiment score of the whole text, -1 (very negative) ... 1 (very positive); 0 when the tagger has no answer.
    static func sentiment(_ text: String) -> Double {
        let tagger = NLTagger(tagSchemes: [.sentimentScore])
        tagger.string = text
        tagger.setLanguage(.english, range: text.startIndex..<text.endIndex)
        let (tag, _) = tagger.tag(at: text.startIndex, unit: .paragraph, scheme: .sentimentScore)
        return tag.flatMap { Double($0.rawValue) } ?? 0
    }
}
