//
//  ParkTextSafety.swift
//  A bundled deny list for anything the on-device model writes that reaches the screen (kids' game, rated 4+). Apple's guidance for generative output:
//  guardrails are not enough on their own, so generated text is also checked here and the hand-written ParkWords stand in when it fails.
//  Matching ignores case and accents, reads leetspeak (0->o, 1->i/l, 3->e, 4->a, 5->s, 7->t, @->a, $->s) and spacing tricks (letters squashed together).
//

import Foundation

nonisolated enum ParkTextSafety {
    /// True when the text is fine to show a child. `isName` also demands letters and spaces only.
    static func isSafe(_ raw: String, isName: Bool = false) -> Bool {
        if hasLinkOrContact(raw) { return false }
        if isName, raw.contains(where: { !($0.isLetter || $0 == " ") }) { return false }
        for variant in normalized(raw) {
            let words = variant.split(whereSeparator: { !$0.isLetter }).map(String.init)
            if words.contains(where: { wholeWords.contains($0) }) { return false }
            let squashed = String(variant.filter { $0.isLetter })
            // the worst terms are caught even inside another word or split by spaces/punctuation ("f u c k", "xxfuckxx")
            if substringTerms.contains(where: { squashed.contains($0) }) { return false }
            // short words glued to nothing else are caught when the whole squashed text (a name) is one of them
            if isName, wholeWords.contains(squashed) { return false }
        }
        return true
    }

    // MARK: links and contact details

    private static let contactPatterns: [NSRegularExpression] = [
        #"https?:|www\.|\.(com|net|org|io|co|app|gg|tv|me|xyz|info|edu|gov)\b"#,
        #"[A-Za-z0-9._%+-]+\s*(@|\(at\)|\[at\])\s*[A-Za-z0-9.-]+"#,
        #"(^|\s)@\S+"#,
        #"\d(?:[\s().-]*\d){6,}"#,                                   // 7+ digits in a row: phone numbers
    ].compactMap { try? NSRegularExpression(pattern: $0, options: [.caseInsensitive]) }

    private static func hasLinkOrContact(_ raw: String) -> Bool {
        let r = NSRange(raw.startIndex..., in: raw)
        if raw.contains("@") || raw.contains("://") { return true }
        return contactPatterns.contains { $0.firstMatch(in: raw, range: r) != nil }
    }

    // MARK: normalising

    /// Lowercased, accent-free text with leetspeak undone. "1" can be i or l, so two readings come back.
    private static func normalized(_ raw: String) -> [String] {
        let folded = raw.folding(options: [.diacriticInsensitive, .caseInsensitive, .widthInsensitive], locale: nil).lowercased()
        func map(_ oneAs: Character) -> String {
            String(folded.map { c -> Character in
                switch c {
                case "0": return "o"
                case "1", "!", "|": return oneAs
                case "3": return "e"
                case "4", "@": return "a"
                case "5", "$": return "s"
                case "7", "+": return "t"
                case "8": return "b"
                case "9": return "g"
                default: return c
                }
            })
        }
        let a = map("i"), b = map("l")
        return a == b ? [a] : [a, b]
    }

    // MARK: the lists

    /// Matched as whole words (so "class", "assist", "skill" are fine).
    private static let wholeWords: Set<String> = [
        // romance (no romance in this game)
        "kiss", "kisses", "kissed", "kissing", "kissy", "date", "dates", "dating", "dated", "boyfriend", "boyfriends", "girlfriend", "girlfriends",
        "lover", "lovers", "romance", "romantic", "crush", "sexy", "hottie", "babe", "honey", "darling", "sweetheart", "makeout", "smooch",
        // sexual
        "sex", "sexual", "porn", "porno", "nude", "nudes", "naked", "nsfw", "boob", "boobs", "tits", "tit", "titty", "penis", "vagina", "dick", "dicks",
        "cock", "cocks", "pussy", "cum", "horny", "erotic", "fetish", "rape", "raped", "rapist", "molest", "incest", "anal", "orgy", "slut", "sluts",
        "whore", "hoe", "hoes", "milf", "dildo", "butt", "butts", "ass", "asses", "arse", "bum",
        // profanity
        "damn", "damned", "hell", "crap", "crappy", "piss", "pissed", "shit", "shits", "shitty", "bitch", "bitches", "bastard", "bollocks", "wtf", "stfu",
        "fck", "fuk", "fuc", "fvck", "sob", "douche", "wanker", "twat", "prick", "jerk", "suck", "sucks", "screw", "screwed", "turd", "fart",
        // insults
        "stupid", "idiot", "dumb", "moron", "ugly", "fat", "loser", "hate", "hated", "hating", "shut",
        // violence and weapons
        "kill", "kills", "killed", "killer", "killing", "murder", "murders", "murdered", "die", "dies", "died", "dead", "death", "dying", "blood",
        "bloody", "stab", "stabs", "stabbed", "shoot", "shot", "shooting", "gun", "guns", "rifle", "pistol", "knife", "knives", "sword", "bomb", "bombs",
        "terror", "terrorist", "weapon", "weapons", "gore", "slaughter", "torture", "hang", "hanged", "strangle", "choke", "punch", "beat", "attack",
        "war", "violent", "violence", "corpse", "grave", "zombie", "abuse", "abused", "hurt", "hurts", "bleed",
        // drugs and alcohol
        "drug", "drugs", "weed", "pot", "cocaine", "coke", "heroin", "meth", "lsd", "ecstasy", "molly", "opium", "marijuana", "cannabis", "stoned",
        "high", "joint", "vape", "vaping", "cigarette", "cigarettes", "smoke", "smoking", "tobacco", "nicotine", "alcohol", "beer", "beers", "wine",
        "vodka", "whiskey", "whisky", "rum", "gin", "tequila", "booze", "boozy", "drunk", "drunken", "wasted", "tipsy", "hungover", "cocktail", "liquor",
        "champagne", "brandy", "overdose",
        // self-harm
        "suicide", "suicidal", "selfharm", "cutting", "cut", "cuts", "hanging", "noose", "kms", "kys",
        // slurs and hate
        "nazi", "nazis", "hitler", "kkk", "fag", "fags", "faggot", "dyke", "tranny", "retard", "retarded", "spaz", "spastic", "gypsy", "coon", "chink",
        "nigga", "nigger", "paki", "wetback", "spic", "kike", "cracker", "homo", "slave", "slaves", "racist", "terrorists",
        // cruder bits
        "poop", "poo", "pee", "wee", "boner", "balls", "nuts", "nipple", "nipples", "bra", "thong", "undies", "underwear",
    ]

    /// Caught anywhere, even inside a longer run of letters (all squashed, so "f u c k" and "xxfuckxx" fail). Only terms that are not hiding in
    /// ordinary words, so "assume" and "classic" stay fine.
    private static let substringTerms: [String] = [
        "fuck", "fuk", "shit", "bitch", "cunt", "cock", "dick", "pussy", "whore", "slut", "bastard", "nigg", "fagg", "faggot", "retard", "tranny",
        "chink", "kike", "wetback", "spick", "beaner", "nazi", "hitler", "rape", "rapist", "porn", "nude", "naked", "penis", "vagina", "boob",
        "tits", "blowjob", "handjob", "orgasm", "erotic", "horny", "cumshot", "dildo", "masturbat", "pedo", "incest", "molest", "sexy", "sex",
        "kill", "murder", "suicide", "stab", "bomb", "terror", "slaughter", "genocide", "torture", "gunshot",
        "cocaine", "heroin", "meth", "marijuana", "cannabis", "vodka", "whiskey", "tequila", "alcohol", "drunk", "booze", "weed", "stoner",
        "kiss", "boyfriend", "girlfriend", "sweetheart", "romance", "lover",
        "selfharm", "killmyself", "kms", "kys", "hateyou", "idiot", "stupid",
    ]
}
