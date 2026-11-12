//
//  VoiceTraining.swift
//  Voice v1: what each Jelbie answers to. Tricks are bought in the Shop (Store/TrickCatalog.swift) and obeyed by their plain word; a word taught in the old
//  lessons (kept in the save) still works with its own reliability. Pure model, persisted to UserDefaults.
//  Commanding: a learned word makes him do the move with probability `reliability` (0.6 at learn + 0.15 per rep beyond 3, +0.03 per success, cap 0.95).
//  A miss is half "wrong trick" (another learned trick) and half ignored. Grumpy refuses every trick except come (come is always obeyed).
//  `decide` is the single entry point: transcript in, a VoiceReaction out (GameCare executes it). The RNG is injectable so tests are deterministic.
//

import Foundation
import Observation

/// The tricks he can be taught; each reuses an existing move (the flip is the one new move: BlobBrain+Flip.swift). `rawValue` is the persisted id.
nonisolated enum VoiceTrick: String, CaseIterable, Codable, Sendable {
    case sit, jacks, run, flip, look, come
    /// Store trick pages: locked until the page is bought (StoreBook), then taught like the others.
    case spin, hop
    /// Shop tricks that reuse or add a move (stage 1 of the trick plan: show off, strut, sing).
    case showOff, strut, sing
    /// Stage 2 of the trick plan (new moves): hula, ...
    case hula, superSpring, corkscrew, oneLegSpin
    /// Stage 3 of the trick plan (prototypes): moonwalk, back bounce, headstand.
    case moonwalk, backBounce, headstand

    var isStarter: Bool { switch self { case .sit, .jacks, .run, .flip, .look, .come: return true; default: return false } }
    static var starters: [VoiceTrick] { allCases.filter(\.isStarter) }

    /// Our UI name (the trick book), never the player's word.
    var title: String {
        switch self {
        case .sit: return "Sit"; case .jacks: return "Jumping jacks"; case .run: return "Run"
        case .flip: return "Flip"; case .look: return "Look"; case .come: return "Come"
        case .spin: return "Spin"; case .hop: return "Hop"
        case .showOff: return "Show off"; case .strut: return "Strut"; case .sing: return "Sing"
        case .hula: return "Hula"; case .superSpring: return "Super spring"; case .corkscrew: return "Corkscrew jump"; case .oneLegSpin: return "One-leg spin"
        case .moonwalk: return "Moonwalk"; case .backBounce: return "Back bounce"; case .headstand: return "Headstand"
        }
    }
    /// The words that command this trick (exact match, short commands). A trick the Jelbie owns is commanded with these; a word taught in the old
    /// lessons keeps working too.
    var commandWords: [String] {
        switch self {
        case .sit: return ["sit"]; case .jacks: return ["jump", "jacks", "jumping jacks"]; case .run: return ["run"]
        case .flip: return ["flip"]; case .look: return ["look"]; case .come: return []
        case .spin: return ["spin"]; case .hop: return ["hop"]
        case .showOff: return ["show off", "showoff", "show it off"]; case .strut: return ["strut"]; case .sing: return ["sing", "sing a song"]
        case .hula: return ["hula", "hula dance"]; case .superSpring: return ["super spring", "spring"]; case .corkscrew: return ["corkscrew", "corkscrew jump"]; case .oneLegSpin: return ["one leg spin", "pirouette", "tiptoe spin"]
        case .moonwalk: return ["moonwalk", "moon walk"]; case .backBounce: return ["back bounce", "bounce on your back"]; case .headstand: return ["headstand", "head stand"]
        }
    }
    /// A word to suggest, in the tip text only.
    var suggestion: String {
        switch self {
        case .sit: return "sit"; case .jacks: return "jump"; case .run: return "run"
        case .flip: return "flip"; case .look: return "look"; case .come: return "come"
        case .spin: return "spin"; case .hop: return "hop"
        case .showOff: return "show off"; case .strut: return "strut"; case .sing: return "sing"
        case .hula: return "hula"; case .superSpring: return "super spring"; case .corkscrew: return "corkscrew"; case .oneLegSpin: return "one leg spin"
        case .moonwalk: return "moonwalk"; case .backBounce: return "back bounce"; case .headstand: return "headstand"
        }
    }
}

/// What the game should do with what was said.
nonisolated enum VoiceReaction: Equatable, Sendable {
    /// Do the trick.
    case perform(VoiceTrick)
    /// The player asked for `said`, he did `did` instead.
    case wrongTrick(said: VoiceTrick, did: VoiceTrick)
    /// Shrug: look away briefly.
    case ignore
    /// A trick this Jelbie does not know (not a default, not bought for him or for everyone): the small "don't know that" shrug.
    case dontKnow(VoiceTrick)
    /// Grumpy: slump turn-away plus the need bubble.
    case grumpyIgnore
    /// Tilt "?" (unknown word, or a half-learned word with no move running).
    case puzzled
    /// Only a name was said (or "everyone"): perk up and walk toward the camera. Names are known from the start (no lesson).
    case nameHeard
    /// A built-in social command (stop, stopFighting, praise, scold, play).
    case social(VoiceSocial)
    /// A nickname lesson rep (the player is teaching a nickname by voice) / the rep that completed it.
    case nicknameStep(reps: Int)
    case nicknameLearned
    /// A natural command was understood and handed to the game (a meal, a nap, a bath ...): a blink and the ear-perk, no move of its own.
    case acknowledged
}

/// `decide`'s full answer: the reaction, who it is for, and whether NOTHING matched (the model fallback may then try).
nonisolated struct VoiceDecision: Equatable, Sendable {
    var reaction: VoiceReaction
    var target: VoiceTarget = .selected
    /// No name, word, alias, social phrase or teaching rep matched: the text is free phrasing.
    var noMatch = false
}

nonisolated enum VoiceTuning {
    /// The one rep count: a trick (or his name) is learned after this many listens that carry the word. Dots, docs and tests all read it.
    static let repsToLearn = 3
    static let baseReliability: Float = 0.6
    static let perExtraRep: Float = 0.15
    static let perSuccess: Float = 0.03
    static let maxReliability: Float = 0.95
    /// On a miss: this fraction is a wrong trick (when another is learned), the rest is ignored.
    static let wrongShare = 0.5
    /// A bound word keeps at most this many spoken words.
    static let maxWordTokens = 2
    static let defaultsKey = "BlobWords.v1"
    /// The language-model fallback: it must answer within this many seconds (target ~0.8 s) or the deterministic result stands.
    nonisolated(unsafe) static var modelBudget: Double = 1.5
    /// Below this confidence the model's answer is treated as "none".
    static let modelMinConfidence = 0.5
    /// Praise gives this much attention (0...1).
    static let praiseAttention: Float = 0.08
    /// "Come here" is innate: he knows it from the first launch. 0.92 (not the 0.95 cap) so successes still nudge it up, yet a miss is rare
    /// (about 1 in 12); the player never has to teach it, and a miss only shrugs.
    static let comeWord = "come here"
    static let comeReliability: Float = 0.92
    /// Loose spoken variants of the come command (exact phrases; the stored "come here" also takes the usual fuzzy match). The name is stripped
    /// first, so "come here bob" is "come here".
    static let comeAliases = ["come", "come on", "here boy", "come here boy", "come here now", "come to me"]
    /// A bought (or default) trick that was never taught a word obeys at this reliability; a taught one keeps its own.
    static let knownReliability: Float = 0.95
    /// A short command is a trick only without these ("sit on the couch" is a place, "hop in the bath" a bath).
    static let placeWords: Set<String> = ["on", "in", "into", "onto", "to", "at", "under", "by", "for", "with", "off"]
}

/// One lesson (a trick, or the name): the bound word, reps, which listen sessions they came from.
nonisolated struct VoiceLesson: Codable, Equatable, Sendable {
    var word = ""
    var reps = 0
    var sessions: [Int] = []
    var learned = false
    var reliability: Float = 0

    var started: Bool { !word.isEmpty }

    /// One more hearing in `session`: one rep per listen (a second hearing in the same listen is not counted). Completes the lesson at
    /// `repsToLearn` reps. Returns true on the completing rep.
    mutating func addRep(session: Int) -> Bool {
        guard !sessions.contains(session) else { return false }
        reps += 1
        sessions.append(session)
        guard !learned, reps >= VoiceTuning.repsToLearn else { return false }
        learned = true
        reliability = min(max(VoiceTuning.baseReliability + VoiceTuning.perExtraRep * Float(reps - VoiceTuning.repsToLearn),
                              VoiceTuning.baseReliability), VoiceTuning.maxReliability)
        return true
    }
}

/// Everything persisted.
nonisolated struct VoiceBook: Codable, Equatable, Sendable {
    var name = VoiceLesson()
    var tricks: [String: VoiceLesson] = [:]
    var sessionCounter = 0
}

/// Small deterministic generator (SplitMix64) for tests.
nonisolated struct VoiceSeededRNG: RandomNumberGenerator, Sendable {
    private var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

@MainActor
@Observable
final class VoiceTraining {
    private(set) var book = VoiceBook()
    /// Every Jelly's name, pet forms and nicknames (known from the start; nothing to learn).
    let names: JellyNames

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let key: String
    @ObservationIgnored private let persists: Bool
    /// Uniform 0..<1; every random choice goes through it.
    @ObservationIgnored private var roll: () -> Double
    /// The learned trick whose reliability roll failed in the last `decide` (nil otherwise): the host shows "he knew it but missed".
    @ObservationIgnored private(set) var lastMiss: VoiceTrick?
    /// Which tricks THIS Jelbie knows (defaults, bought for him, bought for everyone). GameCare sets it from the StoreBook; the default allows everything.
    @ObservationIgnored var unlocked: (VoiceTrick) -> Bool = { _ in true }

    nonisolated deinit {}

    /// `random` defaults to the system generator; pass `VoiceTraining.seededRoll(_:)` in tests. `-VoiceReset 1` clears the book.
    init(defaults: UserDefaults = .standard, key: String = VoiceTuning.defaultsKey, name: String = "bob", names: JellyNames? = nil,
         persists: Bool = true, random: (() -> Double)? = nil) {
        self.defaults = defaults; self.key = key; self.persists = persists
        // `name` is accepted for the per-Jelly books (JellyProfile) and ignored: every book shares one name registry
        self.names = names ?? (persists && defaults === UserDefaults.standard ? JellyNames.shared : JellyNames(defaults: defaults, persists: persists))
        self.roll = random ?? { Double.random(in: 0..<1) }
        if persists {
            if defaults.bool(forKey: "VoiceReset") { defaults.removeObject(forKey: key) }       // capture aid: -VoiceReset 1 forgets everything
            load()
        }
        ensureCome()
        ensureNameKnown()
    }

    /// Names are known from the start. An old save with a half-learned (or empty) name lesson is completed on load.
    private func ensureNameKnown() {
        guard !book.name.learned else { return }
        book.name = Self.knownName
        save()
    }
    /// The name row of the book: always "learned" (kept in the save format so old builds' data still decodes).
    static var knownName: VoiceLesson {
        var l = VoiceLesson()
        l.word = "bob"; l.reps = VoiceTuning.repsToLearn; l.learned = true; l.reliability = VoiceTuning.maxReliability
        return l
    }

    /// The come command is innate: unlearned (a fresh install, an old save, a reset) means "come here" at `comeReliability`.
    /// A player who already taught come their own word keeps it.
    private func ensureCome() {
        guard !isLearned(.come) else { return }
        book.tricks[VoiceTrick.come.rawValue] = Self.innateCome
        save()
    }
    static var innateCome: VoiceLesson {
        var l = VoiceLesson()
        l.word = VoiceTuning.comeWord; l.reps = VoiceTuning.repsToLearn; l.sessions = [0, 1, 2]; l.learned = true; l.reliability = VoiceTuning.comeReliability
        return l
    }

    static func seededRoll(_ seed: UInt64) -> () -> Double {
        var g = VoiceSeededRNG(seed: seed)
        return { Double.random(in: 0..<1, using: &g) }
    }

    // MARK: queries (trick book)

    func lesson(_ t: VoiceTrick) -> VoiceLesson { book.tricks[t.rawValue] ?? VoiceLesson() }
    func isLearned(_ t: VoiceTrick) -> Bool { lesson(t).learned }
    /// The bound word (the player's own, normalised) or nil.
    func word(for t: VoiceTrick) -> String? { let w = lesson(t).word; return w.isEmpty ? nil : w }
    /// Dots filled in the book (0...repsToLearn).
    func progress(_ t: VoiceTrick) -> Int { lesson(t).learned ? VoiceTuning.repsToLearn : min(lesson(t).reps, VoiceTuning.repsToLearn) }
    /// A taught trick keeps the reliability it earned; a known one that was never taught obeys at `knownReliability`; an unknown one at 0.
    func reliability(_ t: VoiceTrick) -> Float { lesson(t).learned ? lesson(t).reliability : (knows(t) ? VoiceTuning.knownReliability : 0) }
    /// He can do `t` (come is innate).
    func knows(_ t: VoiceTrick) -> Bool { t == .come || unlocked(t) }
    /// Every trick he can do.
    var learnedTricks: [VoiceTrick] { VoiceTrick.allCases.filter { knows($0) } }
    var nameLearned: Bool { true }
    /// Words to hand the recogniser as contextual strings: his name, every taught word and the command words of his tricks.
    var contextualWords: [String] { names.contextualWords + VoiceTrick.allCases.filter { unlocked($0) }.compactMap(word(for:)) + VoiceTrick.allCases.filter { unlocked($0) }.flatMap(\.commandWords) }

    /// The known trick a short command names by its plain word, if any (a taught word is matched separately).
    private func plainTrick(in rest: [String], known: Bool) -> VoiceTrick? {
        guard rest.count <= 3 else { return nil }
        let cands = Set(VoiceMatcher.candidates(rest))
        // longest matched command word wins ("show off" over a shorter word); ties keep declaration order. A place word ("hop ON the couch") spoils a match
        // unless it is part of the command word itself ("show OFF").
        var best: (t: VoiceTrick, len: Int)?
        for t in VoiceTrick.allCases where t != .come && knows(t) == known {
            for w in t.commandWords where cands.contains(w) {
                guard Set(rest).subtracting(w.split(separator: " ").map(String.init)).isDisjoint(with: VoiceTuning.placeWords) else { continue }
                if w.count > (best?.len ?? 0) { best = (t, w.count) }
            }
        }
        return best?.t
    }

    /// The highest listen-session id this book has handed out (the coordinator keeps ids unique ACROSS books).
    var sessionCounter: Int { book.sessionCounter }
    /// Raises this book's counter to `s` (a session id taken from the global maximum).
    func adoptSession(_ s: Int) { guard s > book.sessionCounter else { return }; book.sessionCounter = s; save() }

    /// A fresh listen-session id (persisted, so it stays distinct across launches).
    func newSession() -> Int {
        book.sessionCounter += 1
        save()
        return book.sessionCounter
    }

    // MARK: change

    /// Trick book "Forget word": the trick goes back to unlearned and unbound.
    func forget(_ t: VoiceTrick) {
        book.tricks[t.rawValue] = nil
        ensureCome()                       // come is innate: forgetting it puts "come here" back
        save()
    }

    func forgetAll() { book = VoiceBook(sessionCounter: book.sessionCounter); ensureCome(); ensureNameKnown(); save() }

    /// Debug / test aid (kept for the capture flags): names are always known, so this is a no-op.
    func debugLearnName() {}

    /// Debug / capture aid (`-VoiceLearned 1`): a trick counts as learned with this word and reliability.
    func debugLearn(_ t: VoiceTrick, word: String, reliability: Float = VoiceTuning.maxReliability) {
        var l = VoiceLesson()
        l.word = VoiceMatcher.normalise(word); l.reps = VoiceTuning.repsToLearn; l.sessions = [0, 1, 2]; l.learned = true; l.reliability = reliability
        book.tricks[t.rawValue] = l
        save()
    }

    // MARK: decide

    /// `runningMove`: the trick-able move he is DOING right now (nil if none), which a new word gets bound to.
    /// `session`: the id of this listen (see `newSession`).
    @discardableResult
    func decide(transcript: String, runningMove: VoiceTrick?, mood: BlobMood, session: Int) -> VoiceReaction {
        decideFull(transcript: transcript, runningMove: runningMove, mood: mood, session: session).reaction
    }

    /// The deterministic half of the pipeline (instant): names (+ pet forms, near-misses, nicknames) and "everyone" are stripped first and give the
    /// target; then taught words, the come aliases, the built-in social phrases, and last a new word taught as a rep. Nothing matched = `noMatch`.
    func decideFull(transcript: String, runningMove: VoiceTrick?, mood: BlobMood, session: Int) -> VoiceDecision {
        lastMiss = nil
        let toks = VoiceMatcher.tokens(transcript)
        guard !toks.isEmpty else { return VoiceDecision(reaction: .ignore) }
        defer { save() }

        let resolved = names.resolve(tokens: toks)
        let named = VoiceTarget.named(names.resolveIDs(tokens: toks))
        let (all, afterAll) = VoicePhrases.everyone(resolved.rest)
        let rest = named.isSeveral ? afterAll.filter { $0 != "and" } : afterAll          // "Pip and Moss": the joining "and" is not part of the command
        let target: VoiceTarget = all ? .everyone : (resolved.first.map { _ in named } ?? .selected)
        func out(_ r: VoiceReaction) -> VoiceDecision { VoiceDecision(reaction: r, target: target) }
        // a name (or "everyone") alone: attention
        if rest.isEmpty { return target == .selected ? VoiceDecision(reaction: .puzzled, noMatch: true) : out(mood == .grumpy ? .grumpyIgnore : .nameHeard) }

        // Does it match a word he has been taught?
        let bound = VoiceTrick.allCases.filter { unlocked($0) && lesson($0).learned }
        if let hit = VoiceMatcher.best(in: rest, among: bound.map { lesson($0).word }) { return out(command(bound[hit.index], mood: mood)) }

        // The plain word of a trick he knows (sit, spin, hop, ...), or of one he does not know: a small "don't know that" shrug
        if let t = plainTrick(in: rest, known: true) { return out(command(t, mood: mood)) }
        if let t = plainTrick(in: rest, known: false) { return out(mood == .grumpy ? .grumpyIgnore : .dontKnow(t)) }

        // Loose come variants ("come", "here boy") once come is learned
        if isLearned(.come), rest.count <= 3, VoiceTuning.comeAliases.contains(rest.joined(separator: " ")) { return out(command(.come, mood: mood)) }
        if isLearned(.come), rest.count <= 5, VoiceMatcher.looksLikeCome(rest) { return out(command(.come, mood: mood)) }

        // Built-in social commands: known from the start (reserved words, never taught as tricks)
        if let s = VoicePhrases.social(rest) {
            if mood == .grumpy, s == .play { return out(.grumpyIgnore) }
            return out(.social(s))
        }

        // Anything else is free phrasing (no word is ever bound by speaking; tricks are bought in the Shop)
        return VoiceDecision(reaction: .puzzled, target: target, noMatch: true)
    }

    /// What the language model picked, run through the same rules as a spoken command: a trick must already be learned (any word), else puzzled.
    func decide(model action: VoiceAction, target: VoiceTarget, mood: BlobMood) -> VoiceDecision {
        lastMiss = nil
        defer { save() }
        switch action {
        case .none: return VoiceDecision(reaction: .puzzled, target: target)
        case .come: return VoiceDecision(reaction: command(.come, mood: mood), target: target)
        case .trick(let t):
            guard t != .come else { return VoiceDecision(reaction: command(.come, mood: mood), target: target) }
            guard unlocked(t) else { return VoiceDecision(reaction: .dontKnow(t), target: target) }
            return VoiceDecision(reaction: command(t, mood: mood), target: target)
        case .social(let s):
            if mood == .grumpy, s == .play { return VoiceDecision(reaction: .grumpyIgnore, target: target) }
            return VoiceDecision(reaction: .social(s), target: target)
        }
    }

    /// Does `rest` (a transcript's tokens) name a trick this book has LEARNED (side-effect free)? Used by the room command.
    func learnedTrick(in tokens: [String]) -> VoiceTrick? {
        let resolved = names.resolve(tokens: tokens)
        let (_, rest) = VoicePhrases.everyone(resolved.rest)
        guard !rest.isEmpty else { return nil }
        let learned = VoiceTrick.allCases.filter { unlocked($0) && isLearned($0) && $0 != .come }
        if let hit = VoiceMatcher.best(in: rest, among: learned.map { lesson($0).word }) { return learned[hit.index] }
        return plainTrick(in: rest, known: true)
    }

    private func command(_ t: VoiceTrick, mood: BlobMood) -> VoiceReaction {
        // Come is ALWAYS obeyed: a grumpy Bob is grumpy because he wants love, so a refusal would lock him out of the one thing that cheers him up.
        // (Grumpy skips the reliability roll too; he comes sulky, and the close-up petting does the rest.) Other tricks are still refused.
        let grumpyCome = t == .come && mood == .grumpy
        if mood == .grumpy && t != .come { return .grumpyIgnore }
        var l = lesson(t)
        let taught = l.learned
        if !taught { l.reliability = VoiceTuning.knownReliability }
        if grumpyCome || roll() < Double(l.reliability) {
            if taught {
                l.reliability = min(l.reliability + VoiceTuning.perSuccess, VoiceTuning.maxReliability)
                book.tricks[t.rawValue] = l
            }
            return .perform(t)
        }
        lastMiss = t
        let others = learnedTricks.filter { $0 != t }
        if !others.isEmpty, roll() < VoiceTuning.wrongShare {
            return .wrongTrick(said: t, did: others[min(Int(roll() * Double(others.count)), others.count - 1)])
        }
        return .ignore
    }

    // MARK: persistence

    func save() {
        guard persists, let data = try? JSONEncoder().encode(book) else { return }
        defaults.set(data, forKey: key)
    }

    /// The tricks a saved lesson book has learned (the store-tricks migration reads the books of Jelbies who are not in the room too).
    static func savedLearnedTricks(defaults: UserDefaults, key: String) -> [VoiceTrick] {
        guard let data = defaults.data(forKey: key), let b = try? JSONDecoder().decode(VoiceBook.self, from: data) else { return [] }
        return VoiceTrick.allCases.filter { b.tricks[$0.rawValue]?.learned == true }
    }

    func load() {
        guard let data = defaults.data(forKey: key), let b = try? JSONDecoder().decode(VoiceBook.self, from: data) else { book = VoiceBook(); return }
        book = b
        book.tricks = book.tricks.filter { VoiceTrick(rawValue: $0.key) != nil }      // a retired trick (the old "yawn") is dropped
        ensureNameKnown()
    }
}
