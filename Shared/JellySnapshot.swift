//
//  JellySnapshot.swift
//  The widget's data, compiled into the app AND the widget extension.
//
//  The app writes a compact JSON snapshot (`jellies.json`) plus one portrait PNG per Jelly (`portrait-<id>.png`) into the App Group
//  container whenever needs / grime are saved and when it leaves `.active`. The widget never writes game state: it reads the snapshot and
//  PROJECTS it forward with the same away-decay math the app uses on return (AwayMath in NeedsCore.swift), so a Jelly that nobody has
//  looked at gets hungry on the Home Screen over the day.
//
//  Snapshot format (version 1):
//    { "version": 1, "savedAt": <seconds since 1970>, "jellies": [ { "id": 0, "name": "Bob", "color": "blue",
//        "levels": [hunger, thirst, attention] (0...1), "dirt": 0...1, "sparkle": 0...1, "mood": "happy|okay|grumpy",
//        "look": "<portrait look key>" } ] }       (1...3 Jellies; ids 0 / 1 / 2 = Bob / Pip / Moss)
//

import Foundation

// MARK: - App Group paths

nonisolated enum JellyShare {
    static let groupID = "group.io.mgsllc.BobV1"
    static let snapshotFile = "jellies.json"
    static let scheme = "jelbies"
    static let maxJellies = 3
    static func portraitFile(_ id: Int) -> String { "portrait-\(id).png" }
    /// The shared container, or nil when the App Group is not available to this process.
    static var containerURL: URL? { FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: groupID) }
}

// MARK: - Snapshot

nonisolated struct JellyRecord: Codable, Equatable, Identifiable, Sendable {
    var id: Int
    var name: String
    /// A PaletteKey raw value ("blue", "yellow", ...): picks the accent colour in the widget and the colour of the portrait.
    var color: String
    /// Hunger, thirst, attention (NeedKind order), 0...1.
    var levels: [Float]
    var dirt: Float
    var sparkle: Float
    var mood: String
    /// What the portrait PNG currently shows (colour + coat), so the app re-renders only when the look changes meaningfully.
    var look: String = ""
    /// His feature (JellyFeature raw value: "spines", "daisy", "wings"; "" / "none" = plain). Optional in the file: old snapshots have none.
    var feature: String = ""

    init(id: Int, name: String, color: String, levels: [Float], dirt: Float, sparkle: Float, mood: String, look: String = "", feature: String = "") {
        self.id = id; self.name = name; self.color = color; self.levels = levels; self.dirt = dirt; self.sparkle = sparkle; self.mood = mood; self.look = look
        self.feature = feature
    }
    /// Tolerant decoding: a missing / short field falls back instead of losing the whole snapshot.
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? "Jelbie"
        color = try c.decodeIfPresent(String.self, forKey: .color) ?? "blue"
        var l = try c.decodeIfPresent([Float].self, forKey: .levels) ?? []
        while l.count < NeedKind.allCases.count { l.append(1) }
        levels = Array(l.prefix(NeedKind.allCases.count)).map { min(max($0, 0), 1) }
        dirt = min(max(try c.decodeIfPresent(Float.self, forKey: .dirt) ?? 0, 0), 1)
        sparkle = min(max(try c.decodeIfPresent(Float.self, forKey: .sparkle) ?? 0, 0), 1)
        mood = try c.decodeIfPresent(String.self, forKey: .mood) ?? BlobMood.okay.rawValue
        look = try c.decodeIfPresent(String.self, forKey: .look) ?? ""
        feature = try c.decodeIfPresent(String.self, forKey: .feature) ?? ""
    }
}

nonisolated struct JellySnapshot: Codable, Equatable, Sendable {
    static let currentVersion = 1
    var version = JellySnapshot.currentVersion
    /// Seconds since 1970 (a plain number, so the format does not depend on a date coding strategy).
    var savedAt: Double
    var jellies: [JellyRecord]

    init(savedAt: Date, jellies: [JellyRecord]) { self.savedAt = savedAt.timeIntervalSince1970; self.jellies = Array(jellies.prefix(JellyShare.maxJellies)) }

    var date: Date { Date(timeIntervalSince1970: savedAt) }

    func encoded() -> Data? {
        let e = JSONEncoder()
        e.outputFormatting = [.sortedKeys]
        return try? e.encode(self)
    }
    static func decode(_ data: Data) -> JellySnapshot? { try? JSONDecoder().decode(JellySnapshot.self, from: data) }

    /// Reads / writes `jellies.json` in `directory` (the App Group container; tests pass a temp folder). Writes are atomic.
    static func read(from directory: URL? = JellyShare.containerURL) -> JellySnapshot? {
        guard let directory, let data = try? Data(contentsOf: directory.appendingPathComponent(JellyShare.snapshotFile)) else { return nil }
        return decode(data)
    }
    @discardableResult
    func write(to directory: URL? = JellyShare.containerURL) -> Bool {
        guard let directory, let data = encoded() else { return false }
        return (try? data.write(to: directory.appendingPathComponent(JellyShare.snapshotFile), options: .atomic)) != nil
    }

    /// Every Jelly as it will be at `date` (the saved levels with the away time since `savedAt` applied).
    func project(at date: Date) -> [JellyState] {
        let away = date.timeIntervalSince1970 - savedAt
        return jellies.map { JellyState(record: $0, awaySeconds: away) }
    }

    /// Like `project(at:)` but with the night hours (21:00-06:00) at half weight on the needs, exactly as `BlobNeeds.applyAway(endingAt:)` does
    /// when the player comes back: the Lock Screen / StandBy entries then match what the game will show on open, hours ahead.
    func projectNightAware(at date: Date, calendar: Calendar = .current) -> [JellyState] {
        let away = TimeAway.clamp(date.timeIntervalSince1970 - savedAt)
        let from = date.addingTimeInterval(-away)
        let needSeconds = AwayMath.needSeconds(from: from, to: date, calendar: calendar)
        return jellies.map { JellyState(record: $0, awaySeconds: away, needSeconds: needSeconds) }
    }
}

// MARK: - Care items and projected state

/// The four things a Jelly can want: food, water, love (heart), a wash (soap).
nonisolated enum JellyCare: Int, CaseIterable, Sendable {
    case food, water, heart, soap
    var need: NeedKind? { switch self { case .food: return .hunger; case .water: return .thirst; case .heart: return .attention; case .soap: return nil } }
    var systemImage: String { ["fork.knife", "drop.fill", "heart.fill", "bubbles.and.sparkles.fill"][rawValue] }
}

/// One Jelly projected to a moment in time.
nonisolated struct JellyState: Identifiable, Equatable, Sendable {
    let id: Int
    let name: String
    let color: String
    /// Hunger, thirst, attention after the away time.
    let levels: [Float]
    let dirt: Float
    let sparkle: Float
    let mood: BlobMood

    /// `needSeconds`: the away seconds the NEEDS feel (night hours at half weight); defaults to the wall-clock away time.
    init(record r: JellyRecord, awaySeconds: TimeInterval, needSeconds: TimeInterval? = nil) {
        id = r.id; name = r.name; color = r.color
        let away = TimeAway.clamp(awaySeconds)
        let lv = AwayMath.needLevels(r.levels, seconds: needSeconds ?? away)
        let c = AwayMath.coat(dirt: r.dirt, sparkle: r.sparkle, awaySeconds: away)
        levels = lv; dirt = c.dirt; sparkle = c.sparkle
        mood = AwayMath.mood(of: lv)
    }

    var coat: JellyCoatTier { JellyCoatTier.of(dirt: dirt, sparkle: sparkle) }

    /// The named tier of an item (soap: Clean / Beautiful read as Full, Normal as Normal, Dirty as Hungry, Filthy as Famished).
    func tier(_ c: JellyCare) -> NeedTier {
        if let n = c.need { return NeedTier.of(level: levels[n.rawValue]) }
        switch coat { case .beautiful, .clean: return .full; case .normal: return .normal; case .dirty: return .hungry; case .filthy: return .famished }
    }
    /// 0...1, how well off (soap: cleanliness).
    func level(_ c: JellyCare) -> Float { c.need.map { levels[$0.rawValue] } ?? (1 - dirt) }

    /// The item he needs most: worst tier, then lowest level, then food / water / heart / soap order.
    var neediest: (care: JellyCare, tier: NeedTier) {
        var best = JellyCare.food
        for c in JellyCare.allCases where Self.worse(self, c, than: best) { best = c }
        return (best, tier(best))
    }
    private static func worse(_ s: JellyState, _ a: JellyCare, than b: JellyCare) -> Bool {
        let ta = s.tier(a).rawValue, tb = s.tier(b).rawValue
        if ta != tb { return ta > tb }
        return s.level(a) < s.level(b)
    }
    /// Any item at Hungry or worse.
    var needsAttention: Bool { neediest.tier.rawValue >= NeedTier.hungry.rawValue }

    /// "Bob is hungry!" for the neediest item; "Bob is sparkling!" / "Bob is happy!" / "Bob is doing fine." otherwise.
    var headline: String {
        let (c, t) = neediest
        if t.rawValue >= NeedTier.hungry.rawValue {
            let word: String
            switch c {
            case .food: word = t.word(.hunger).lowercased()
            case .water: word = t.word(.thirst).lowercased()
            case .heart: word = t.word(.attention).lowercased()
            case .soap: word = coat.word.lowercased()
            }
            return "\(name) is \(word)!"
        }
        if coat == .beautiful { return "\(name) is sparkling!" }
        return mood == .happy ? "\(name) is happy!" : "\(name) is doing fine."
    }
    /// A short word for an item ("Hungry", "Quenched", "Content", "Dirty", ...).
    func word(_ c: JellyCare) -> String {
        if let n = c.need { return tier(c).word(n) }
        return coat.word
    }

    /// The Jelly that needs the most care: worst item tier, then lowest level, then the lowest id. Nil for an empty list.
    static func neediest(in states: [JellyState]) -> JellyState? {
        var best: JellyState?
        for s in states.sorted(by: { $0.id < $1.id }) {
            guard let b = best else { best = s; continue }
            let (sc, st) = s.neediest, (bc, bt) = b.neediest
            if st.rawValue > bt.rawValue || (st == bt && s.level(sc) < b.level(bc)) { best = s }
        }
        return best
    }
}

// MARK: - Timeline

nonisolated enum JellyTimeline {
    /// Entries every 30 min for 12 h (25 entries: now, +30 min, ... +12 h).
    static let step: TimeInterval = 30 * 60
    static let horizon: TimeInterval = 12 * 3600
    static func entryDates(from now: Date) -> [Date] {
        (0...Int(horizon / step)).map { now.addingTimeInterval(Double($0) * step) }
    }
}

// MARK: - Deep link

/// `jelbies://jelly/<id>` opens the game and selects that Jelly.
nonisolated enum JellyLink {
    static func url(for id: Int) -> URL { URL(string: "\(JellyShare.scheme)://jelly/\(id)")! }
    /// The Jelly id of a deep link, or nil when it is not one of ours (wrong scheme / host, missing, non-numeric or out-of-range id).
    static func parse(_ url: URL) -> Int? {
        guard url.scheme?.lowercased() == JellyShare.scheme, url.host?.lowercased() == "jelly" else { return nil }
        let parts = url.pathComponents.filter { $0 != "/" }
        guard parts.count == 1, let id = Int(parts[0]), (0..<JellyShare.maxJellies).contains(id) else { return nil }
        return id
    }
}
