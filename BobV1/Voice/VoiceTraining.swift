//
//  VoiceTraining.swift
//  Voice v1: the words the player has taught Bob (his name + six tricks), Nintendogs style. Pure model, persisted to UserDefaults.
//  Teaching: while he is DOING a move, the player says a word; it is bound to that move and counts a rep. Learned after 3 reps (`VoiceTuning.repsToLearn`), one per listen: saying the word repeatedly in one listen counts once.
//  Commanding: a learned word makes him do the move with probability `reliability` (0.35 at learn + 0.15 per rep beyond 4, +0.03 per success, cap 0.95).
//  A miss is half "wrong trick" (another learned trick) and half ignored. Grumpy always ignores.
//  `decide` is the single entry point: transcript in, a VoiceReaction out (GameCare executes it). The RNG is injectable so tests are deterministic.
//

import Foundation
import Observation

/// The tricks he can be taught; each reuses an existing move (the flip is the one new move: BlobBrain+Flip.swift). `rawValue` is the persisted id.
nonisolated enum VoiceTrick: String, CaseIterable, Codable, Sendable {
    case sit, jacks, run, flip, look, come

    /// Our UI name (the trick book), never the player's word.
    var title: String {
        switch self {
        case .sit: return "Sit"; case .jacks: return "Jumping jacks"; case .run: return "Run"
        case .flip: return "Flip"; case .look: return "Look"; case .come: return "Come"
        }
    }
    /// A word to suggest, in the tip text only.
    var suggestion: String {
        switch self {
        case .sit: return "sit"; case .jacks: return "jump"; case .run: return "run"
        case .flip: return "flip"; case .look: return "look"; case .come: return "come"
        }
    }
}

/// What the game should do with what was said.
nonisolated enum VoiceReaction: Equatable, Sendable {
    /// A rep was counted toward a word (dots filled so far, 1...repsToLearn): he nods / the book fills a dot.
    case learnedStep(VoiceTrick, reps: Int)
    /// That rep completed the lesson.
    case trickLearned(VoiceTrick)
    /// Do the trick.
    case perform(VoiceTrick)
    /// The player asked for `said`, he did `did` instead.
    case wrongTrick(said: VoiceTrick, did: VoiceTrick)
    /// Shrug: look away briefly.
    case ignore
    /// Grumpy: slump turn-away plus the need bubble.
    case grumpyIgnore
    /// Tilt "?" (unknown word, or a half-learned word with no move running).
    case puzzled
    /// His name was heard. `learned == false`: tilt "?" while the lesson goes on; true: perk up and walk toward the camera.
    case nameHeard(learned: Bool)
    /// This hearing completed the name lesson.
    case nameLearned
}

nonisolated enum VoiceTuning {
    /// The one rep count: a trick (or his name) is learned after this many listens that carry the word. Dots, docs and tests all read it.
    static let repsToLearn = 3
    static let baseReliability: Float = 0.35
    static let perExtraRep: Float = 0.15
    static let perSuccess: Float = 0.03
    static let maxReliability: Float = 0.95
    /// On a miss: this fraction is a wrong trick (when another is learned), the rest is ignored.
    static let wrongShare = 0.5
    /// A bound word keeps at most this many spoken words.
    static let maxWordTokens = 2
    static let defaultsKey = "BlobWords.v1"
    static let defaultName = "bob"
    /// "Come here" is innate: he knows it from the first launch. 0.92 (not the 0.95 cap) so successes still nudge it up, yet a miss is rare
    /// (about 1 in 12); the player never has to teach it, and a miss only shrugs.
    static let comeWord = "come here"
    static let comeReliability: Float = 0.92
    /// Loose spoken variants of the come command (exact phrases; the stored "come here" also takes the usual fuzzy match). The name is stripped
    /// first, so "come here bob" is "come here".
    static let comeAliases = ["come", "come on", "here boy", "come here boy", "come here now", "come to me"]
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
    /// His name, normalised ("bob").
    let name: String

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let key: String
    @ObservationIgnored private let persists: Bool
    /// Uniform 0..<1; every random choice goes through it.
    @ObservationIgnored private var roll: () -> Double
    /// The learned trick whose reliability roll failed in the last `decide` (nil otherwise): the host shows "he knew it but missed".
    @ObservationIgnored private(set) var lastMiss: VoiceTrick?

    nonisolated deinit {}

    /// `random` defaults to the system generator; pass `VoiceTraining.seededRoll(_:)` in tests. `-VoiceReset 1` clears the book.
    init(defaults: UserDefaults = .standard, key: String = VoiceTuning.defaultsKey, name: String = VoiceTuning.defaultName,
         persists: Bool = true, random: (() -> Double)? = nil) {
        self.defaults = defaults; self.key = key; self.persists = persists
        self.name = VoiceMatcher.normalise(name)
        self.roll = random ?? { Double.random(in: 0..<1) }
        if persists {
            if defaults.bool(forKey: "VoiceReset") { defaults.removeObject(forKey: key) }       // capture aid: -VoiceReset 1 forgets everything
            load()
        }
        ensureCome()
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
    func reliability(_ t: VoiceTrick) -> Float { lesson(t).learned ? lesson(t).reliability : 0 }
    var learnedTricks: [VoiceTrick] { VoiceTrick.allCases.filter(isLearned) }
    var nameLearned: Bool { book.name.learned }
    /// Words to hand the recogniser as contextual strings: his name plus every bound word.
    var contextualWords: [String] { [name] + VoiceTrick.allCases.compactMap(word(for:)) }

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

    func forgetAll() { book = VoiceBook(sessionCounter: book.sessionCounter); ensureCome(); save() }

    /// Debug / test aid: the name lesson counts as learned.
    func debugLearnName() { book.name.learned = true; book.name.reps = VoiceTuning.repsToLearn; save() }

    /// Debug / capture aid (`-VoiceLearned 1`): a trick counts as learned with this word and reliability.
    func debugLearn(_ t: VoiceTrick, word: String, reliability: Float = VoiceTuning.maxReliability) {
        var l = VoiceLesson()
        l.word = VoiceMatcher.normalise(word); l.reps = VoiceTuning.repsToLearn; l.sessions = [0, 1, 2]; l.learned = true; l.reliability = reliability
        book.tricks[t.rawValue] = l
        save()
    }

    /// Debug / capture aid (`-VoiceTutorialReps n`): n reps of a half-learned word on a trick (one listen session, so it never completes).
    func debugReps(_ t: VoiceTrick, word: String, reps: Int) {
        var l = VoiceLesson()
        l.word = VoiceMatcher.normalise(word); l.reps = min(reps, VoiceTuning.repsToLearn); l.sessions = [book.sessionCounter]
        book.tricks[t.rawValue] = reps > 0 ? l : nil
        save()
    }

    // MARK: decide

    /// `runningMove`: the trick-able move he is DOING right now (nil if none), which a new word gets bound to.
    /// `session`: the id of this listen (see `newSession`).
    @discardableResult
    func decide(transcript: String, runningMove: VoiceTrick?, mood: BlobMood, session: Int) -> VoiceReaction {
        lastMiss = nil
        let toks = VoiceMatcher.tokens(transcript)
        guard !toks.isEmpty else { return .ignore }
        defer { save() }

        // His name is stripped first: name + trick = the trick (the name just got his attention); the name alone = the name lesson.
        let (nameScore, rest) = VoiceMatcher.splitName(tokens: toks, name: name)
        if rest.isEmpty { return nameScore > 0 ? hearName(mood: mood, session: session) : .puzzled }

        // Does it match a word he has been taught?
        let bound = VoiceTrick.allCases.filter { lesson($0).started }
        if let hit = VoiceMatcher.best(in: rest, among: bound.map { lesson($0).word }) {
            let trick = bound[hit.index]
            if lesson(trick).learned { return command(trick, mood: mood) }
            // half-learned word
            if runningMove == trick { return rep(trick, session: session) }
            return runningMove == nil ? .puzzled : .ignore       // while he is doing another move the word is "bound elsewhere"
        }

        // Loose come variants ("come", "here boy") once come is learned
        if isLearned(.come), rest.count <= 3, VoiceTuning.comeAliases.contains(rest.joined(separator: " ")) { return command(.come, mood: mood) }
        if isLearned(.come), rest.count <= 5, VoiceMatcher.looksLikeCome(rest) { return command(.come, mood: mood) }

        // A new word: it is taught only while he is doing a move that is not already learned.
        guard let move = runningMove, !lesson(move).learned else { return .puzzled }
        var fresh = VoiceLesson()
        fresh.word = rest.prefix(VoiceTuning.maxWordTokens).joined(separator: " ")
        book.tricks[move.rawValue] = fresh                        // starts (or restarts a half-learned different word)
        return rep(move, session: session)
    }

    private func rep(_ t: VoiceTrick, session: Int) -> VoiceReaction {
        var l = lesson(t)
        let done = l.addRep(session: session)
        book.tricks[t.rawValue] = l
        return done ? .trickLearned(t) : .learnedStep(t, reps: l.reps)
    }

    private func hearName(mood: BlobMood, session: Int) -> VoiceReaction {
        if book.name.learned { return mood == .grumpy ? .grumpyIgnore : .nameHeard(learned: true) }
        book.name.word = name
        return book.name.addRep(session: session) ? .nameLearned : .nameHeard(learned: false)
    }

    private func command(_ t: VoiceTrick, mood: BlobMood) -> VoiceReaction {
        if mood == .grumpy { return .grumpyIgnore }
        var l = lesson(t)
        if roll() < Double(l.reliability) {
            l.reliability = min(l.reliability + VoiceTuning.perSuccess, VoiceTuning.maxReliability)
            book.tricks[t.rawValue] = l
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

    func load() {
        guard let data = defaults.data(forKey: key), let b = try? JSONDecoder().decode(VoiceBook.self, from: data) else { book = VoiceBook(); return }
        book = b
        book.tricks = book.tricks.filter { VoiceTrick(rawValue: $0.key) != nil }      // a retired trick (the old "yawn") is dropped
    }
}
