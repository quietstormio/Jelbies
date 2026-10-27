//
//  ParkBook.swift
//  What the Park keeps: the visitors (the pool, their friendship with each of the player's Jelbies, their text), saved as JSON in UserDefaults on the device,
//  and the daily ledger that caps the love a visit can give and allows one gift a day. While a visit is on it also holds the cast (bodies, who came along).
//

import Foundation
import Observation

@MainActor
@Observable
final class ParkBook {
    static let key = "ParkVisitors.v1", ledgerKey = "ParkLedger.v1"

    /// The visitors change every step while friends play (points), so they are not observed: views read `revision`, which bumps when a card would look different.
    @ObservationIgnored private(set) var visitors: [ParkVisitor]
    /// Bumps when something a card shows changed (a level, the text, a name).
    private(set) var revision = 0
    /// The visit now: who is in the park (pool ids, in the order of `actors`), the bodies, and which of the player's slots came along.
    var cast: [Int] = []
    @ObservationIgnored var actors: [JellyActor] = []
    @ObservationIgnored var comers: [Int] = []
    /// The room's own Jelbies (set by the park tick each step), what the park keeps while a trip is on, and the stage's hooks for the visitor bodies.
    @ObservationIgnored var roster: [JellyActor] = []
    @ObservationIgnored let work = ParkWork()
    @ObservationIgnored var spawn: (([ParkVisitor], [SIMD2<Float>]) -> [JellyActor])?
    @ObservationIgnored var clear: (() -> Void)?
    @ObservationIgnored var soloWired = false
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var writing = false
    @ObservationIgnored private var dirty = false

    nonisolated deinit {}

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let d = defaults.data(forKey: Self.key), let v = try? JSONDecoder().decode([ParkVisitor].self, from: d), v.count == ParkTuning.poolSize { visitors = v }
        else { visitors = ParkPool.generate() }
    }

    func visitor(_ id: Int) -> ParkVisitor? { visitors.indices.contains(id) ? visitors[id] : nil }
    func save() {
        guard dirty else { return }
        dirty = false
        if let d = try? JSONEncoder().encode(visitors) { defaults.set(d, forKey: Self.key) }
    }
    private func touch() { dirty = true; revision &+= 1 }

    // MARK: friendship

    /// Adds points to a pair; returns the level now when it went up.
    @discardableResult
    func add(points: Float, visitor id: Int, character: Int) -> ParkFriendLevel? {
        guard visitors.indices.contains(id) else { return nil }
        let before = visitors[id].points(with: character)
        let after = min(before + points, 100)
        guard after != before else { return nil }
        visitors[id].friendship[String(character)] = after
        dirty = true
        let was = ParkFriendLevel.of(before), now = ParkFriendLevel.of(after)
        if now > was { revision &+= 1; return now }
        return nil
    }
    func markSeen(_ ids: [Int], at now: Double) {
        for id in ids where visitors.indices.contains(id) { visitors[id].lastSeen = now; visitors[id].introduced = true }
        touch(); save()
    }
    /// The line for a level: the cached one, else the hand-written one.
    func line(_ id: Int, _ level: ParkFriendLevel) -> String {
        guard let v = visitor(id) else { return "" }
        return v.levelLines[String(level.rawValue)] ?? ParkWords.levelLine(v.name, level)
    }
    func setLine(_ id: Int, _ level: ParkFriendLevel, _ text: String) {
        guard visitors.indices.contains(id) else { return }
        visitors[id].levelLines[String(level.rawValue)] = text
        touch(); save()
    }

    // MARK: who comes

    func chooseCast(count: Int, characters: [Int], now: Double) -> [ParkVisitor] {
        var rng = SystemRandomNumberGenerator()
        return ParkPool.pickCast(from: visitors, count: count, characters: characters, now: now, using: &rng)
    }

    // MARK: the on-device writer (optional)

    /// Asks the on-device model, one visitor at a time in the background, to write the text of every visitor not written yet. Does nothing without the model.
    func warmUp() {
        guard !writing, ParkText.available, visitors.contains(where: { !$0.written }) else { return }
        writing = true
        Task { [weak self] in
            guard let self else { return }
            defer { self.writing = false }
            for id in self.visitors.indices where !self.visitors[id].written {
                let v = self.visitors[id]
                let t = await ParkText.write(colour: v.colour.title.lowercased(), style: v.style.word.lowercased(), signature: Self.words(v.signature))
                guard self.visitors.indices.contains(id) else { continue }
                if let t {
                    if !self.visitors[id].introduced { self.visitors[id].name = t.name }          // a name never changes once the player has met them
                    self.visitors[id].blurb = t.blurb; self.visitors[id].greeting = t.greeting
                }
                self.visitors[id].written = true          // (once: a failed ask is not repeated this session either)
                self.touch(); self.save()
            }
        }
    }
    /// Writes (one at a time, in the background) the level-up lines of these visitors that are not cached yet, so the lines are ready when a friendship grows.
    func warmLines(_ ids: [Int]) {
        guard !writingLines, ParkText.available else { return }
        writingLines = true
        Task { [weak self] in
            guard let self else { return }
            defer { self.writingLines = false }
            for id in ids {
                for level in [ParkFriendLevel.pal, .friend, .best] {
                    guard let v = self.visitor(id), v.levelLines[String(level.rawValue)] == nil else { continue }
                    if let text = await ParkText.levelLine(name: v.name, style: v.style.word.lowercased(), level: level) { self.setLine(id, level, text) }
                }
            }
        }
    }
    @ObservationIgnored private var writingLines = false

    private static func words(_ f: JellyFeature) -> String {
        switch f { case .none: return ""; case .spines: return "spikes on its back"; case .daisy: return "a daisy on its head"; case .wings: return "little wings" }
    }

    /// A level-up line from the model, kept for next time (the hand-written one shows now).
    func writeLevelLine(_ id: Int, _ level: ParkFriendLevel, onReady: @escaping (String) -> Void) {
        guard let v = visitor(id), v.levelLines[String(level.rawValue)] == nil, ParkText.available else { return }
        Task { [weak self] in
            guard let self, let text = await ParkText.levelLine(name: v.name, style: v.style.word.lowercased(), level: level) else { return }
            self.setLine(id, level, text)
            onReady(text)
        }
    }

    // MARK: the daily ledger (love given, the gift)

    struct Ledger: Codable { var day = ""; var love: [String: Float] = [:]; var giftDay = ""; var lastVisitGifted: Bool? }
    @ObservationIgnored private var ledgerCache: Ledger?
    static func dayString(_ d: Date = Date()) -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: d)
        return "\(c.year ?? 0)-\(c.month ?? 0)-\(c.day ?? 0)"
    }
    var ledger: Ledger {
        get {
            var l = ledgerCache ?? (defaults.data(forKey: Self.ledgerKey).flatMap { try? JSONDecoder().decode(Ledger.self, from: $0) } ?? Ledger())
            if l.day != Self.dayString() { l.day = Self.dayString(); l.love = [:] }
            return l
        }
        set { ledgerCache = newValue; if let d = try? JSONEncoder().encode(newValue) { defaults.set(d, forKey: Self.ledgerKey) } }
    }
    /// Love still allowed today for a character.
    func loveLeft(_ character: Int) -> Float { max(ParkTuning.loveDailyCap - (ledger.love[String(character)] ?? 0), 0) }
    func spendLove(_ amount: Float, character: Int) { var l = ledger; l.love[String(character), default: 0] += amount; ledger = l }
    /// The every-other-visit rhythm (kept across launches): did the last visit that planned for a gift give one?
    var lastVisitGifted: Bool { ledger.lastVisitGifted ?? false }
    func setLastVisitGifted(_ v: Bool) { var l = ledger; l.lastVisitGifted = v; if v { l.giftDay = Self.dayString() }; ledger = l }
}
