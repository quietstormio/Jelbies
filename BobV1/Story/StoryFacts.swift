//
//  StoryFacts.swift
//  Everything a text about one Jelmiko may draw on, gathered from data the game really has (plain Codable; no player-typed word is ever sent to a writer: `StoryFill` swaps the
//  placeholders for the real words only AFTER the guard). The values here are KEYS and facts; the words for the keys live in `StoryPhrases`.
//

import Foundation

nonisolated struct StoryFacts: Codable, Equatable, Sendable {
    struct Trophies: Codable, Equatable, Sendable {
        var raceWins = 0, raceRibbons = 0, volleyWins = 0, showCups = 0, rosettes = 0
        /// The hardest course a race was won on ("Puddle", "Ripple" ...), the highest Show rank with a cup.
        var bestRaceTier: String?, bestShowRank: String?
        /// The most recent engraved win: "race" / "volley" / "show" / "trophy", its tier or rank title, its date text and how many days ago.
        var recentKind: String?, recentTier: String?, recentDate: String?, recentDaysAgo: Int?
        var total: Int { raceWins + volleyWins + showCups + rosettes }
    }
    struct Housemate: Codable, Equatable, Sendable {
        var id: Int
        var name: String, kindName: String
        /// This housemate's share of the pair / group time (0...1), seconds lately, the pair emote done together most (a SocialKind key), and whether they are the most played with.
        var playShare = 0.0, togetherSeconds = 0
        var topEmote: String?
        var mostPlayedWith = false
        /// Took part in a group activity together lately (about half a minute or more).
        var sharedGroup = false
        /// Phase 3 fills this (a "Relationship" level for the pair); nil for now.
        var relationshipLevel: String?
    }

    var id: Int
    var name: String
    var kindName: String
    /// The kind's short description (the Jelly Spring's `SpeciesInfo.about`).
    var kindAbout: String
    /// The static paragraph the Profile shows above the blurb: ALREADY SHOWN, never repeated (colour and character note).
    var shownParagraph: String?
    var personality: String?
    /// The favourite snack's store id ("cookie", "popsicle"): `StoryPhrases.food` has the words.
    var favouriteFood: String?
    /// hungry / thirsty / sleepy / happy (the Profile's own status words), "" when unknown.
    var mood: String
    var trophies = Trophies()
    /// "naps" when much of the time lately is rest, else nil.
    var sleepHabit: String?
    // habits
    var favouriteActivity: String?          // a StoryPhrases activity key ("bounce", "chase", "toy")
    var favouriteActivityKind: String?      // "solo" / "pair" / "toy"
    var favouriteSpot: String?              // "window" / "rug" / "couch" / "front"
    var togetherShare = 0.0
    var restShare = 0.0
    var minutesSeen = 0
    var daysTracked = 0
    /// A brand-new Jelmiko: almost no history anywhere.
    var newcomer = false
    var housemates: [Housemate] = []
    var mostPlayedWithID: Int?
    /// The Relationship stage with the player ("Good friends"), nil when unknown.
    var relationshipLevel: String?
    /// Recent events (StoryEvents.swift) and the one piece of NEWS the line should prefer: from today or yesterday, and not already used for its day. `today` = the real day number.
    var events: [StoryEvent] = []
    var news: StoryEvent?
    var today = 0
}

/// The words for the keys. ONE table per kind; a key with no entry is simply not used in a sentence.
nonisolated enum StoryPhrases {
    /// {ACT}: fits "likes {ACT}" and "is often found {ACT}".
    static let activity: [String: String] = [
        "bounce": "bouncing about", "jacks": "doing jumping jacks", "sway": "swaying to the music", "window": "looking out of the window", "tail": "chasing a tail",
        "chirp": "chirping a little tune", "skipHop": "skipping about",
        "hopscotch": "playing hopscotch", "legSpin": "spinning about", "trot": "trotting about", "giggle": "giggling", "proudStrut": "strutting about", "flapHop": "flapping and hopping", "peek": "peeking round the sofa",
        "decorSit": "settling into a cushion", "decorKick": "kicking the ball about", "decorHop": "bouncing on the mat", "decorPeek": "peeking in the toy box",
        "decorSlide": "riding the slide", "slide": "sliding about", "scoot": "scooting about", "zoomies": "zooming about", "run": "running about", "toy": "playing with the toys",
        // together
        "chase": "playing chase", "tag": "playing tag", "dance": "dancing together", "highFive": "swapping high fives", "pass": "passing the ball", "hopAlong": "hopping along together",
        "twirl": "twirling together", "leapfrog": "playing leapfrog", "peekaboo": "playing peekaboo", "mirrorDance": "mirror dancing", "sitTogether": "sitting side by side",
        "bagSit": "sharing a beanbag", "cuddle": "cuddling on the couch", "cuddleLean": "leaning on each other", "nuzzle": "sitting close", "boop": "giving little boops",
        "follow": "following each other about", "line": "walking in a line", "chestBump": "bumping tummies", "littleRace": "having little races", "bellyBounce": "bouncing tummies",
        "backToBack": "standing back to back", "ringAround": "going round in a ring", "swayHug": "swaying in a hug", "danceOff": "having a dance-off", "whisperGiggle": "whispering and giggling",
        "shyWave": "waving hello", "cheekSquish": "squishing side by side", "spinHug": "spinning in a hug", "keepAway": "playing keep away", "greet": "saying hello", "spinTogether": "spinning together",
        "orbit": "circling round", "upDown": "bouncing up and down together", "jumpTurns": "taking turns to jump",
    ]
    /// {FOOD}: bare plural / mass forms, so every pattern reads right ("never says no to cookies", "a soft spot for sushi"). Store food ids (JellyPersonality.snacks).
    static let food: [String: String] = [
        "donut": "donuts", "fries": "fries", "taco": "tacos", "cookie": "cookies", "cupcake": "cupcakes", "dumplings": "dumplings", "sushi": "sushi", "sandwich": "sandwiches",
        "popsicle": "ice pops", "onigiri": "rice balls", "pancakestack": "pancakes", "minipizza": "mini pizzas", "cheeseburger": "cheeseburgers", "cinnamonroll": "cinnamon rolls",
        "fruitskewer": "fruit skewers", "nuggets": "nuggets", "cakeslice": "cake",
    ]
    /// {SPOT}
    static let spot: [String: String] = ["window": "by the window", "rug": "on the rug", "couch": "near the couch", "front": "at the front of the room"]
    /// The words of a personality, lower case ("a sleepy type").
    static func personality(_ p: String?) -> String? { p?.lowercased() }
    /// The longest name the game allows (JellyRoster caps at 14); names are cleaned and cut here too.
    static func cleanName(_ raw: String, fallback: String = "This Jelmiko") -> String {
        var s = ""
        for ch in raw where ch.isLetter || ch.isNumber || ch == " " || ch == "-" || ch == "'" || ch == "\u{2019}" { s.append(ch) }
        s = s.split(separator: " ").joined(separator: " ")
        s = String(s.prefix(14)).trimmingCharacters(in: .whitespaces)
        return s.isEmpty ? fallback : s
    }
}

/// Putting the real words in, AFTER the guard. A writer (templates or the model) only ever handles the tokens.
nonisolated enum StoryFill {
    static let numberWords = ["zero", "one", "two", "three", "four", "five", "six", "seven", "eight", "nine", "ten", "eleven", "twelve", "thirteen", "fourteen", "fifteen", "sixteen", "seventeen", "eighteen", "nineteen", "twenty"]
    /// Race wins that earn the next milestone trophy (TrophyBook: 5, 10, 25 wins).
    static let milestones = [5, 10, 25]

    /// The token values for a blurb about `f` (B = the housemate played with most), or a note about `f` and `with`. Only tokens with a real fact behind them are offered.
    static func values(_ f: StoryFacts, with h: StoryFacts.Housemate? = nil) -> [String: String] {
        var v: [String: String] = ["A": StoryPhrases.cleanName(f.name)]
        let mate = h ?? f.housemates.first(where: { $0.id == f.mostPlayedWithID })
        if let mate { v["B"] = StoryPhrases.cleanName(mate.name, fallback: "a housemate"); if !mate.kindName.isEmpty { v["BKIND"] = mate.kindName } }
        if let food = f.favouriteFood, let p = StoryPhrases.food[food] { v["FOOD"] = p }
        if let k = f.favouriteActivity, let p = StoryPhrases.activity[k] { v["ACT"] = p }
        if let s = f.favouriteSpot, let p = StoryPhrases.spot[s] { v["SPOT"] = p }
        if let mate, let e = mate.topEmote, let p = StoryPhrases.activity[e] { v["EMOTE"] = p }
        if f.trophies.raceWins > 0, let t = f.trophies.bestRaceTier { v["RACE"] = t }
        if let t = f.trophies.bestShowRank, f.trophies.showCups > 0 { v["SHOW"] = t }
        if let p = f.personality { v["PERS"] = p.lowercased() }
        if let n = f.news {
            v["WHEN"] = f.today - n.day <= 0 ? "today" : "yesterday"
            if let t = n.d["tier"], !t.isEmpty { v["TIER"] = t }
            if let p = n.d["place"], let i = Int(p), i >= 1, i <= 4 { v["PLACE"] = ["first", "second", "third", "fourth"][i - 1] }
            if let l = n.d["level"] { v["LEVEL"] = l }
        }
        if f.trophies.raceWins > 0, let next = milestones.first(where: { $0 > f.trophies.raceWins }) {
            let left = next - f.trophies.raceWins
            if left < numberWords.count { v["LEFT"] = "\(numberWords[left]) more race win\(left == 1 ? "" : "s")" }
        }
        return v
    }
    /// The fact keys this sheet really backs (StoryGuard.allFactKeys is the vocabulary): a line may name only these.
    static func facts(_ f: StoryFacts, with h: StoryFacts.Housemate? = nil) -> Set<String> {
        let v = values(f, with: h)
        var k: Set<String> = []
        if v["PERS"] != nil { k.insert("personality") }
        if v["FOOD"] != nil { k.insert("favouriteFood") }
        if v["ACT"] != nil { k.insert("favouriteActivity") }
        if v["SPOT"] != nil { k.insert("favouriteSpot") }
        if v["RACE"] != nil { k.insert("raceWin") }
        if v["SHOW"] != nil { k.insert("showCup") }
        if f.trophies.volleyWins > 0 { k.insert("volleyWin") }
        if v["LEFT"] != nil { k.insert("raceMilestone") }
        if f.sleepHabit != nil { k.insert("nap") }
        if f.newcomer { k.insert("newcomer") } else if f.daysTracked >= 4 { k.insert("settled") }
        if let m = h ?? f.housemates.first(where: { $0.id == f.mostPlayedWithID }), m.togetherSeconds >= 60 {
            if h == nil { k.insert("partner") } else { k.insert("together"); if m.sharedGroup { k.insert("sharedGroup") } }
            if v["EMOTE"] != nil { k.insert("topEmote") }
        } else if h != nil { k.insert("gettingToKnow") }
        if f.relationshipLevel != nil { k.insert("bond") }
        if let n = f.news, n.kind != "bond" || v["LEVEL"] != nil { k.insert(n.factKey) }
        return k
    }
    static func offered(_ f: StoryFacts, with h: StoryFacts.Housemate? = nil) -> Set<String> { Set(values(f, with: h).keys) }

    /// Puts the values in. Unknown tokens are left alone (the guard rejects a text that still has braces).
    static func apply(_ text: String, _ values: [String: String]) -> String {
        var out = text
        for (k, val) in values { out = out.replacingOccurrences(of: "{\(k)}", with: val) }
        return capitaliseSentences(out)
    }

    /// A value that starts a sentence ("cookies ...") gets a capital; names are left as typed.
    static func capitaliseSentences(_ t: String) -> String {
        var out = "", up = true
        for ch in t {
            if up, ch.isLetter { out.append(contentsOf: String(ch).uppercased()); up = false } else { out.append(ch); if ch.isLetter || ch.isNumber { up = false } }
            if ch == "." || ch == "!" { up = true }
        }
        return out
    }
}
