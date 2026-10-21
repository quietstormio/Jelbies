//
//  ThoughtLines.swift
//  Tiny thought lines (3-6 words) that fit the moment: "zoomies time!", "so sleepy now", "that smelled like pizza". Rare: at most one every few
//  minutes across the room, never while a need bubble, a voice bubble, the close-up or the bath is up. Tier B picks from templates by moment;
//  Tier A fills a small cache per moment in the background (validated: 3-6 words, no names, no odd characters) and the tick only READS it,
//  so the frame loop never waits on the model.
//

import Foundation
import Observation
import QuartzCore

/// What a Jelly is up to right now (built by the recorder from the brain and needs; pure values).
nonisolated struct ThoughtMoment: Equatable, Sendable, Hashable {
    enum Scene: String, Sendable { case napping, zooming, playing, hungry, thirsty, lonely, justAte, justBathed, grumpy, night, morning, idle }
    var scene: Scene
    var personality: JellyPersonality
    var key: String { "\(scene.rawValue)-\(personality.rawValue)" }
    var description: String {
        switch scene {
        case .napping: return "settling into a cosy nap"
        case .zooming: return "running zoomies round the room"
        case .playing: return "playing with a friend"
        case .hungry: return "getting hungry, wishing for a snack"
        case .thirsty: return "a bit thirsty"
        case .lonely: return "wanting a cuddle"
        case .justAte: return "just finished a tasty meal"
        case .justBathed: return "fresh and sparkly after a bath"
        case .grumpy: return "feeling grumpy and neglected"
        case .night: return "a sleepy night-time in the room"
        case .morning: return "a fresh morning, stretching and waking"
        case .idle: return "wandering the living room, content"
        }
    }
}

nonisolated enum ThoughtTemplates {
    static func lines(_ m: ThoughtMoment) -> [String] {
        let bang = m.personality == .energetic
        switch m.scene {
        case .napping: return ["so sleepy now", "five more minutes", "cosy cosy cosy", "zzz", "dreaming of snacks", "nap time is best"]
        case .zooming: return bang ? ["zoomies time!", "faster faster faster!", "can't stop won't stop!", "wheee!"] : ["zoomies time", "look at me go", "whoosh", "my feet are fast"]
        case .playing: return ["best friends forever", "tag you're it!", "this is fun", "again again!", "playtime is the best"]
        case .hungry: return ["tummy says hello", "is it snack time?", "something smells yummy", "berries would be nice", "feed me please"]
        case .thirsty: return ["a sip would be nice", "so thirsty", "water please", "my straw is calling"]
        case .lonely: return ["where did you go?", "cuddle me please", "I miss you", "come back soon", "pet me?"]
        case .justAte: return ["yum, that was good", "full and happy", "that hit the spot", "still tasting it", "more please?"]
        case .justBathed: return ["so sparkly!", "fresh as a daisy", "look how shiny I am", "squeaky clean", "bubbles everywhere"]
        case .grumpy: return ["hmph", "nobody loves me", "not talking to you", "grumble grumble", "I want attention"]
        case .night: return ["the stars are out", "so quiet now", "almost bedtime", "cosy night", "one more wiggle then bed"]
        case .morning: return ["good morning world", "big stretch", "a brand new day", "what shall we do today?", "stretch stretch yawn"]
        case .idle:
            switch m.personality {
            case .calm: return ["this spot is mine", "nice and comfy here", "what a lovely room", "just wiggling", "all is well"]
            case .energetic: return ["what's next?!", "I love this room!", "let's do something!", "bounce bounce bounce", "so much energy!"]
            case .gentle: return ["the light is pretty", "everyone seems happy", "I like it here", "such a nice day", "hello little dust mote"]
            case .dreamy: return ["what are clouds made of?", "floaty floaty", "I wonder about things", "the ceiling is far", "daydreaming again"]
            }
        }
    }
}

nonisolated enum ThoughtSafety {
    /// 3-6 words, letters / apostrophes / one exclamation mark, no names outside the roster, no digits or odd symbols.
    static func check(_ raw: String, roster: [String]) -> String? {
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "\"“”'`*-.")).lowercased()
        let words = s.split(separator: " ").map(String.init)
        guard (3...6).contains(words.count), s.count <= 40 else { return nil }
        let ok = CharacterSet.letters.union(CharacterSet(charactersIn: " '!?,"))
        guard s.unicodeScalars.allSatisfy({ ok.contains($0) }), s.filter({ $0 == "!" }).count <= 1 else { return nil }
        let rosterLower = Set(roster.map { $0.lowercased() })
        let orig = raw.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: " ").map { $0.trimmingCharacters(in: .punctuationCharacters) }
        for (i, w) in orig.enumerated() where i > 0 && (w.first?.isUppercase ?? false) && w != "I" && !rosterLower.contains(w.lowercased()) { return nil }
        return s
    }
}

@MainActor
@Observable
final class ThoughtLines {
    struct Line: Equatable, Sendable { var jelly: Int; var text: String; var born: Double; var wall: Double = CACurrentMediaTime() }
    /// The line on screen (nil = none).
    private(set) var current: Line?
    /// Seconds between two lines (randomised 1x-1.6x); "rarely" per the design.
    var minGap: Double = 180
    static let life: Double = 3.6
    @ObservationIgnored var writer: AITextWriter?
    @ObservationIgnored private var cache: [String: [String]] = [:]
    @ObservationIgnored private var fetching: Set<String> = []
    @ObservationIgnored private var clock: Double = 0
    @ObservationIgnored private var nextAt: Double
    @ObservationIgnored private var rng = VoiceSeededRNG(seed: 0x7E0A)
    @ObservationIgnored private var lastKey = ""
    /// Lines shown so far (tests).
    @ObservationIgnored private(set) var shown: [Line] = []
    @ObservationIgnored private(set) var fromModel = 0

    nonisolated deinit {}
    init(writer: AITextWriter? = nil, firstAfter: Double = 45) { self.writer = writer; nextAt = firstAfter }

    private func roll() -> Double { Double(rng.next() >> 11) / Double(1 << 53) }

    /// One step. `moments`: who is doing what; `blocked`: something else owns the screen (bubble, voice, close-up, bath). Returns true when a line
    /// appeared this step.
    @discardableResult
    func tick(dt: Double, moments: [(jelly: Int, moment: ThoughtMoment, name: String)], blocked: Bool, roster: [String]) -> Bool {
        clock += dt
        if let c = current, clock - c.born > Self.life { current = nil }
        guard current == nil, !blocked, clock >= nextAt, !moments.isEmpty else { return false }
        // the most interesting Jelly: a scene other than idle wins; ties go to a roll
        let ranked = moments.sorted { ($0.moment.scene == .idle ? 1 : 0) < ($1.moment.scene == .idle ? 1 : 0) }
        let top = ranked.filter { $0.moment.scene == ranked[0].moment.scene }
        let pick = top[Int(roll() * Double(top.count)) % top.count]
        let text = line(for: pick.moment, name: pick.name, roster: roster)
        current = Line(jelly: pick.jelly, text: text, born: clock)
        shown.append(current!); if shown.count > 50 { shown.removeFirst() }
        nextAt = clock + minGap * (1 + 0.6 * roll())
        return true
    }

    /// A line for the moment: a cached model line when there is one, else a template (and a background fetch for next time).
    func line(for m: ThoughtMoment, name: String, roster: [String]) -> String {
        let key = m.key
        if var c = cache[key], !c.isEmpty {
            let l = c.removeFirst(); cache[key] = c; fromModel += 1
            return l
        }
        fetch(m, name: name, roster: roster)
        var pool = ThoughtTemplates.lines(m)
        if pool.count > 1, let last = shown.last, lastKey == key { pool.removeAll { $0 == last.text } }
        lastKey = key
        return pool[Int(roll() * Double(pool.count)) % pool.count]
    }

    /// Fills the cache for a moment once per launch, in the background; the result is only read by a later tick.
    private func fetch(_ m: ThoughtMoment, name: String, roster: [String]) {
        guard let writer, writer.state.isAvailable, cache[m.key] == nil, !fetching.contains(m.key) else { return }
        fetching.insert(m.key)
        let key = m.key, desc = m.description, hint = m.personality.hint
        Task { [weak self] in
            var lines: [String] = []
            if let raw = try? await VoiceCoordinator.withBudget(20) { try await writer.thoughts(name: name, personality: hint, moment: desc, count: 4) } {
                lines = raw.compactMap { ThoughtSafety.check($0, roster: roster) }
            }
            guard let self else { return }
            self.cache[key] = lines            // empty = the model gave nothing usable: templates for this moment from now on
        }
    }

    /// Tests: pre-fill the model cache.
    func seedCache(_ key: String, _ lines: [String]) { cache[key] = lines }
    func debugShowNow() { nextAt = 0 }
}
