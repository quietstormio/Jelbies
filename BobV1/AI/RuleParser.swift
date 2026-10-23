//
//  RuleParser.swift
//  Tier B of natural voice commands: a deterministic parser for phones without Apple Intelligence (and the fallback when the model is unavailable,
//  not ready, slow or wrong). Names, pet forms and nicknames come from `JellyNames`; "everyone / all of you" from `VoicePhrases`; verbs from the
//  synonym tables below; objects are fuzzy-matched against the catalog (owned foods / drinks, placed decor, toys, wearables); "with <name>" is a
//  partner, not a target. Instant, no allocation to speak of, and it covers the same command set as the model.
//
//  Order of the verb tables matters: a question ("who's hungry") is checked before the feed words it contains; "put on" before the generic verbs;
//  sleep before sit ("lie down"); feed / drink before come ("everyone come eat" is a meal); "play with Moss" before plain play. The store's trick
//  pages (spin, hop, roll) parse as tricks like the starters; the legacy decision then checks the page is bought and the word learned.
//

import Foundation

@MainActor
enum RuleParser {
    struct Result: Equatable, Sendable {
        var command: JellyCommand
        /// A verb (or question) was recognised: the parse can stand on its own.
        var confident: Bool
        /// The words left after names, "everyone", the verb and the object were removed (the model gets the whole phrase anyway).
        var rest: [String]
    }

    // MARK: tables (normalised tokens: lowercase, no punctuation; "who's" -> "who s")

    private static let everyoneExtra: Set<String> = ["everyone", "everybody", "all", "guys", "both"]
    private static let questionPhrases: [(String, NeedKind)] = [
        ("who s hungry", .hunger), ("who is hungry", .hunger), ("whos hungry", .hunger), ("who wants food", .hunger), ("who wants to eat", .hunger),
        ("anyone hungry", .hunger), ("anybody hungry", .hunger), ("who needs food", .hunger), ("is anyone hungry", .hunger), ("who wants a snack", .hunger),
        ("who s thirsty", .thirst), ("who is thirsty", .thirst), ("whos thirsty", .thirst), ("who wants a drink", .thirst), ("anyone thirsty", .thirst),
        ("who needs a drink", .thirst), ("who wants water", .thirst),
        ("who wants love", .attention), ("who wants a cuddle", .attention), ("who wants cuddles", .attention), ("who needs love", .attention),
        ("who wants attention", .attention), ("who wants a hug", .attention), ("who misses me", .attention), ("who s lonely", .attention), ("who is lonely", .attention),
    ]
    private static let wearPhrases = ["put on", "wear", "wears", "dress up", "try on", "wear the", "put your"]
    private static let wearWords: Set<String> = ["wear", "wearing", "outfit", "costume", "hat", "cap", "crown", "bow", "scarf", "glasses"]
    private static let sleepPhrases = ["go to sleep", "go to bed", "time for bed", "night night", "good night", "nighty night", "sleep tight",
                                       "take a nap", "have a nap", "go night night", "off to bed", "sweet dreams", "time to sleep", "get some rest", "go sleep"]
    private static let sleepWords: Set<String> = ["sleep", "sleepy", "bed", "bedtime", "nap", "naptime", "goodnight", "snooze", "zzz", "rest"]
    private static let feedPhrases = ["come eat", "come and eat", "time to eat", "eat up", "dinner time", "lunch time", "breakfast time", "snack time", "have some", "here s some",
                                      "come get food", "food s ready", "dig in", "eat your", "have a bite"]
    private static let feedWords: Set<String> = ["eat", "eats", "eating", "feed", "food", "dinner", "lunch", "breakfast", "snack", "supper", "meal", "yummy", "nom", "noms", "hungry"]
    private static let drinkPhrases = ["have a drink", "come drink", "time to drink", "drink up", "get a drink", "have a sip", "drink your"]
    private static let drinkWords: Set<String> = ["drink", "drinks", "drinking", "sip", "slurp", "thirsty", "juice"]
    private static let cleanPhrases = ["bath time", "take a bath", "get clean", "clean up", "wash up", "time for a bath", "have a bath", "get washed", "shower time"]
    private static let cleanWords: Set<String> = ["bath", "bathe", "wash", "clean", "shower", "scrub", "soap", "rinse", "dirty", "filthy"]
    private static let spinPhrases = ["spin around", "turn around", "do a spin", "spin round", "do a twirl"]
    private static let spinWords: Set<String> = ["spin", "twirl", "pirouette", "spinny", "spins"]
    private static let jacksPhrases = ["jumping jacks", "jumping jack", "jump up and down", "do some jumps", "star jumps"]
    private static let jacksWords: Set<String> = ["jump", "jumps", "jumping", "exercise", "workout"]
    private static let hopPhrases = ["hop hop", "do a hop", "hop up", "hop up and down", "bounce around"]
    private static let hopWords: Set<String> = ["hop", "hops", "hopping", "bounce", "bouncy", "boing"]
    private static let rollPhrases = ["roll over", "do a roll", "roly poly", "roll around", "rolly polly"]
    private static let rollWords: Set<String> = ["roll", "rolls", "rolling", "rollover"]
    private static let flipPhrases = ["do a flip", "back flip", "do a backflip"]
    private static let flipWords: Set<String> = ["flip", "backflip", "somersault", "flips"]
    private static let runPhrases = ["go for a run", "run around", "run run", "do a lap", "go run"]
    private static let runWords: Set<String> = ["run", "running", "zoomies", "zoom", "dash", "sprint", "runs"]
    private static let lookPhrases = ["look around", "have a look", "take a look", "look over there", "look there"]
    private static let lookWords: Set<String> = ["look", "peek", "watch"]
    private static let sitPhrases = ["sit down", "take a seat", "have a seat", "sit here", "sit still", "park yourself", "sit there", "sit on"]
    private static let sitWords: Set<String> = ["sit", "sits", "seat", "sitting"]
    private static let goPhrases = ["go to", "go on", "go sit", "go lie", "get on", "get in", "hop on", "hop in", "go over to", "head to", "go to the", "jump on", "walk to", "climb on"]
    private static let racePhrases = ["let s race", "go race", "time to race", "run a race", "do a race", "enter the race", "jelly circuit"]
    private static let raceWords: Set<String> = ["race", "racing", "circuit", "racetrack"]
    private static let trainPhrases = ["let s train", "time to train", "do some training", "practice time", "let s practice", "go train"]
    private static let trainWords: Set<String> = ["train", "training", "practice", "practise", "workout"]
    private static let playPhrases = ["let s play", "wanna play", "want to play", "go play", "playtime", "play time", "play together", "play a game", "have fun"]
    private static let playWords: Set<String> = ["play", "playing", "soccer", "football", "ball", "fetch", "game", "tag"]
    private static let gameWords: Set<String> = ["soccer", "football", "ball", "fetch", "tag", "catch", "frisbee", "bowling"]
    private static let comePhrases = ["come here", "over here", "come to me", "come on", "come see me", "here boy", "here girl", "c mere"]
    private static let comeWords: Set<String> = ["come", "cmere", "comere", "here"]
    private static let fillers: Set<String> = ["please", "now", "hey", "ok", "okay", "go", "a", "an", "the", "to", "on", "in", "at", "your", "some", "and", "then", "right",
                                                 "do", "can", "you", "could", "would", "will", "little", "buddy", "pal", "boy", "girl", "um", "uh", "for", "me", "it", "that", "this",
                                                 "there", "over", "up", "down", "of", "with", "want", "wanna", "let", "s", "time", "get", "have", "take", "make", "give"]

    private static func padded(_ t: [String]) -> String { " " + t.joined(separator: " ") + " " }
    private static func has(_ t: [String], _ phrases: [String]) -> String? {
        let p = padded(t)
        return phrases.first { p.contains(" \($0) ") }
    }
    private static func hasWord(_ t: [String], _ words: Set<String>) -> Bool { t.contains { words.contains($0) } }
    /// Removes the first occurrence of a phrase's tokens.
    private static func strip(_ t: [String], phrase: String) -> [String] {
        let pt = phrase.split(separator: " ").map(String.init)
        guard !pt.isEmpty, t.count >= pt.count else { return t }
        for i in 0...(t.count - pt.count) where Array(t[i..<(i + pt.count)]) == pt { return Array(t[..<i]) + Array(t[(i + pt.count)...]) }
        return t
    }

    // MARK: parse

    /// `selected`: the Jelly a command with no name goes to (only used to drop a self-partner). Names outside `catalog.jellyIDs` are "not here"
    /// (kept as a target so the caller can show the confused look for an absent Jelly).
    static func parse(_ text: String, names: JellyNames, catalog: AICatalog) -> Result {
        var toks = VoiceMatcher.tokens(text)
        guard !toks.isEmpty else { return Result(command: JellyCommand(action: .none), confident: false, rest: []) }

        // 1. who: names (a name right after "with" is a partner), "everyone"
        var targets: [Int] = []
        var partner: Int?
        var kept: [String] = []
        var i = 0
        while i < toks.count {
            let t = toks[i]
            var hit: NameHit?
            var width = 1
            if i + 1 < toks.count {
                let pair = names.resolve(tokens: [t, toks[i + 1]])
                if let h = pair.first, h.width == 2 { hit = h; width = 2 }
            }
            if hit == nil, let h = names.match(token: t), h.score >= 0.6 { hit = h }
            if let h = hit {
                let afterWith = kept.last == "with" || (kept.count >= 2 && kept[kept.count - 2] == "with" && ["your", "the", "his", "her"].contains(kept.last ?? ""))
                if afterWith, partner == nil { partner = h.id; if kept.last == "with" { kept.removeLast() } }
                else if !targets.contains(h.id) { targets.append(h.id) }
                i += width; continue
            }
            kept.append(t); i += 1
        }
        toks = kept
        let (all, afterAll) = VoicePhrases.everyone(toks)
        var everyone = all
        toks = afterAll
        if let f = toks.first, everyoneExtra.contains(f), toks.count > 1 { toks.removeFirst(); everyone = true }      // "all come eat", "both of you sit"
        let who: JellyWho = everyone ? .everyone : (targets.isEmpty ? .selected : .jellies(targets))

        var cmd = JellyCommand(who: who, action: .none, partner: partner, source: .rules)
        func finish(_ action: JellyAction, strip phrase: String? = nil, words: Set<String> = []) -> Result {
            cmd.action = action
            var rest = toks
            if let p = phrase { rest = strip(rest, phrase: p) }
            rest = rest.filter { !words.contains($0) }
            // the object: what is left, matched against the catalog (narrowed to the kind the action wants)
            let kinds = action.objectKinds
            let objectTokens = rest.filter { !fillers.contains($0) }
            if !objectTokens.isEmpty {
                if let it = catalog.match(objectTokens, kinds: kinds) {
                    cmd.object = it.id
                    let objWords = Set(([it.id, it.name] + it.aliases).flatMap { VoiceMatcher.tokens($0) })
                    rest = rest.filter { !objWords.contains($0) }
                } else if action == .playWith {
                    cmd.unknownObject = objectTokens.first { gameWords.contains($0) }          // "soccer": the game asked for, not in the room yet
                } else if action.needsObject {
                    cmd.unknownObject = objectTokens.joined(separator: " ")                     // "beanbag", "pirate hat": what is missing
                }
            }
            return Result(command: cmd, confident: true, rest: rest.filter { !fillers.contains($0) })
        }

        // 2. questions
        if let q = questionPhrases.first(where: { padded(toks).contains(" \($0.0) ") }) {
            cmd.who = .everyone
            return finish(.whoIs(q.1), strip: q.0)
        }
        // 3. wardrobe
        if let p = has(toks, wearPhrases) { return finish(.wear, strip: p, words: wearWords.subtracting(["hat", "cap", "crown", "bow", "scarf", "glasses"])) }
        if hasWord(toks, ["wear", "wearing"]) { return finish(.wear, words: ["wear", "wearing"]) }
        // 4. sleep
        if VoicePhrases.isWake(toks) { return finish(.wake) }          // before the sleep words ("wake up" has none, but "good morning" would otherwise be praise)
        if let p = has(toks, sleepPhrases) { return finish(.sleep, strip: p, words: sleepWords) }
        if hasWord(toks, sleepWords) { return finish(.sleep, words: sleepWords) }
        // 5. meals (a named food / drink alone is a meal too: "Bob, pizza!")
        if let p = has(toks, drinkPhrases) { return finish(.drink, strip: p, words: drinkWords) }
        if let p = has(toks, feedPhrases) { return finish(.feed, strip: p, words: feedWords.union(comeWords)) }
        if hasWord(toks, drinkWords) { return finish(.drink, words: drinkWords.union(comeWords)) }
        if hasWord(toks, feedWords) { return finish(.feed, words: feedWords.union(comeWords)) }
        if let it = catalog.match(toks.filter { !fillers.contains($0) }, kinds: [.food, .drink]) {
            return finish(it.kind == .drink ? .drink : .feed)
        }
        // 6. clean
        if let p = has(toks, cleanPhrases) { return finish(.clean, strip: p, words: cleanWords) }
        if hasWord(toks, cleanWords) { return finish(.clean, words: cleanWords) }
        // 7. races, training, playing with someone
        if let p = has(toks, racePhrases) { return finish(.race, strip: p, words: raceWords) }
        if hasWord(toks, raceWords) { return finish(.race, words: raceWords) }
        if let p = has(toks, trainPhrases) { return finish(.train, strip: p, words: trainWords) }
        if hasWord(toks, trainWords) { return finish(.train, words: trainWords) }
        if partner != nil || hasWord(toks, gameWords) {
            if hasWord(toks, playWords) || has(toks, playPhrases) != nil || hasWord(toks, gameWords) {
                return finish(.playWith, strip: has(toks, playPhrases), words: ["play", "playing", "with"])
            }
        }
        // 8. moves: spin, jacks, flip, run, look, go to decor, sit
        if let p = has(toks, spinPhrases) { return finish(.trick(.spin), strip: p, words: spinWords) }
        if hasWord(toks, spinWords) { return finish(.trick(.spin), words: spinWords) }
        if let p = has(toks, jacksPhrases) { return finish(.trick(.jacks), strip: p, words: jacksWords) }
        if let p = has(toks, flipPhrases) { return finish(.trick(.flip), strip: p, words: flipWords) }
        if hasWord(toks, flipWords) { return finish(.trick(.flip), words: flipWords) }
        if hasWord(toks, jacksWords) { return finish(.trick(.jacks), words: jacksWords) }
        if let p = has(toks, hopPhrases) { return finish(.trick(.hop), strip: p, words: hopWords) }
        if hasWord(toks, hopWords) { return finish(.trick(.hop), words: hopWords) }
        if let p = has(toks, rollPhrases) { return finish(.trick(.roll), strip: p, words: rollWords) }
        if hasWord(toks, rollWords) { return finish(.trick(.roll), words: rollWords) }
        if let p = has(toks, runPhrases) { return finish(.trick(.run), strip: p, words: runWords) }
        if hasWord(toks, runWords) { return finish(.trick(.run), words: runWords) }
        if let p = has(toks, lookPhrases) { return finish(.trick(.look), strip: p, words: lookWords) }
        if let p = has(toks, goPhrases) {                      // "go to the beanbag", "go sit on the rug": a place
            let r = finish(.goTo, strip: p, words: sitWords.union(["lie", "lay"]))
            if r.command.object != nil || r.command.unknownObject != nil { return r }
            cmd.object = nil; cmd.unknownObject = nil
        }
        if has(toks, sitPhrases) != nil || hasWord(toks, sitWords) {           // "sit on the beanbag" is a place; "sit down" the trick
            let p = has(toks, sitPhrases)
            if catalog.match(toks.filter { !sitWords.contains($0) && !fillers.contains($0) }, kinds: [.decor, .toy]) != nil { return finish(.goTo, strip: p, words: sitWords) }
            return finish(.trick(.sit), strip: p, words: sitWords)
        }
        if hasWord(toks, lookWords) { return finish(.trick(.look), words: lookWords) }
        // 9. decor named with a place verb only ("on the beanbag")
        if catalog.match(toks.filter { !fillers.contains($0) }, kinds: [.decor, .toy]) != nil { return finish(.goTo) }
        // 10. come, then the social phrases
        if let p = has(toks, comePhrases) { return finish(.come, strip: p, words: comeWords) }
        if hasWord(toks, comeWords) || VoiceMatcher.looksLikeCome(toks) { return finish(.come, words: comeWords) }
        if let s = VoicePhrases.social(toks) {
            switch s {
            case .stop: return finish(.stop)
            case .stopFighting: return finish(.stopFighting)
            case .praise: return finish(.praise)
            case .scold: return finish(.scold)
            case .play: return finish(.play)
            case .goodnight: return finish(.sleep)
            case .wakeUp: return finish(.wake)
            }
        }
        // a wearable / toy named alone
        if catalog.match(toks.filter { !fillers.contains($0) }, kinds: [.wearable]) != nil { return finish(.wear) }
        return Result(command: cmd, confident: false, rest: toks.filter { !fillers.contains($0) })
    }
}
