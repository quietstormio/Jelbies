//
//  Diary.swift
//  Each Jelly's diary: once a day (in the evening, or when the game opens on the next day) a 2-4 sentence, first-person, kid-friendly entry about
//  what really happened (from the EventLog only; never from what the player said). Tier A writes it with Apple Intelligence, guided by a one-line
//  personality hint; Tier B is the template writer, which must read nicely too. Both go through `DiarySafety`: a length cap and no names beyond
//  the roster (a rejected model entry falls back to the template). Entries persist for 7 days (`JellyDiary.v1`); `unread` drives the dot.
//

import Foundation
import Observation

/// A small table: how each Jelly sounds. Keyed by name so the roster can grow (Lavender is a planned starter).
nonisolated enum JellyPersonality: String, Codable, CaseIterable, Sendable {
    case calm, energetic, gentle, dreamy

    static func of(name: String) -> JellyPersonality {
        switch name.lowercased() {
        case "bob": return .calm
        case "pip": return .energetic
        case "moss": return .gentle
        case "lavender": return .dreamy
        default: return .calm
        }
    }
    /// The hint the model gets.
    var hint: String {
        switch self {
        case .calm: return "calm, cosy, easygoing; likes naps and quiet"
        case .energetic: return "energetic, bouncy, excited about everything"
        case .gentle: return "gentle, kind, notices small things, a little shy"
        case .dreamy: return "dreamy, wondering, head in the clouds"
        }
    }
    var word: String { rawValue.prefix(1).uppercased() + rawValue.dropFirst() }
}

nonisolated struct DiaryEntry: Codable, Equatable, Sendable, Identifiable {
    var id: String { "\(jelly)-\(day)" }
    var jelly: Int
    var day: String
    var text: String
    /// Written by Apple Intelligence (true) or the template writer.
    var smart: Bool
    var written: Date
}

// MARK: - safety

nonisolated enum DiarySafety {
    static let maxChars = 320
    static let maxSentences = 4
    /// Words the model may capitalise that are not names (sentence starts are handled separately).
    static let allowedCapitals: Set<String> = ["I", "I'm", "I've", "I'll", "I'd", "Mum", "Dad", "Mom"]

    /// Trims, caps and checks a model entry. Nil = rejected (empty, too long after trimming to sentences, a name that is not in the roster, a URL, a
    /// quote block, or something that is not prose).
    static func check(_ raw: String, roster: [String]) -> String? {
        var s = raw.replacingOccurrences(of: "\n", with: " ").replacingOccurrences(of: "  ", with: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        s = s.trimmingCharacters(in: CharacterSet(charactersIn: "\"“”'`*#-"))
        guard s.count >= 12, !s.lowercased().contains("http"), !s.contains("@") else { return nil }
        // keep whole sentences, at most maxSentences / maxChars
        var sentences: [String] = []
        var cur = ""
        for ch in s {
            cur.append(ch)
            if ".!?".contains(ch) { sentences.append(cur.trimmingCharacters(in: .whitespaces)); cur = "" }
        }
        if !cur.trimmingCharacters(in: .whitespaces).isEmpty, sentences.isEmpty { sentences.append(cur.trimmingCharacters(in: .whitespaces) + ".") }
        var out = ""
        for sent in sentences.prefix(maxSentences) {
            if out.count + sent.count + 1 > maxChars { break }
            out += (out.isEmpty ? "" : " ") + sent
        }
        guard out.count >= 12 else { return nil }
        // names: any capitalised word that is not at a sentence start, not a roster name and not allowed = a made-up name
        let rosterLower = Set(roster.map { $0.lowercased() })
        var sentenceStart = true
        for word in out.split(separator: " ") {
            let w = word.trimmingCharacters(in: .punctuationCharacters)
            defer { sentenceStart = word.last.map { ".!?".contains($0) } ?? false }
            guard let f = w.first, f.isUppercase, !sentenceStart else { continue }
            if allowedCapitals.contains(w) || rosterLower.contains(w.lowercased()) { continue }
            if w.allSatisfy({ $0.isUppercase }) && w.count <= 3 { continue }         // "OK"
            return nil
        }
        return out
    }
}

// MARK: - Tier B: templates

nonisolated enum TemplateDiary {
    /// Small deterministic generator so the same day gives the same entry (and different days differ).
    struct Pick {
        var s: UInt64
        init(seed: UInt64) { s = seed &+ 0x9E37_79B9_7F4A_7C15 }
        mutating func next() -> UInt64 { s &+= 0x9E37_79B9_7F4A_7C15; var z = s; z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9; z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB; return z ^ (z >> 31) }
        mutating func one<T>(_ a: [T]) -> T { a[Int(next() % UInt64(max(a.count, 1)))] }
    }

    static func openers(_ p: JellyPersonality) -> [String] {
        switch p {
        case .calm: return ["Dear diary, today was a cosy one.", "Another gentle day in the room.", "Today felt slow and nice.", "What a comfy day.", "Dear diary, I took it easy today."]
        case .energetic: return ["Dear diary, today was SO fun!", "Best. Day. Ever!", "Whoa, what a day!", "Dear diary, I could not sit still today!", "Today was a zoomy one!"]
        case .gentle: return ["Dear diary, today was lovely.", "Hello diary. Today was sweet.", "Today I noticed lots of little things.", "Dear diary, a soft kind of day.", "Today was quiet and kind."]
        case .dreamy: return ["Dear diary, today floated by.", "I dreamed a little today.", "Today the room felt like a cloud.", "Dear diary, what a wondering day.", "Today drifted along nicely."]
        }
    }
    static func closers(_ p: JellyPersonality) -> [String] {
        switch p {
        case .calm: return ["Time for a snooze.", "That was plenty for one day.", "Goodnight, diary.", "Now, where did I put my comfy spot?", "A good day. Yawn."]
        case .energetic: return ["Can't wait for tomorrow!", "Tomorrow I'll go even faster!", "More fun tomorrow, please!", "Zoom zoom, goodnight!", "I'm still buzzing!"]
        case .gentle: return ["Thank you for today.", "Sleep well, everyone.", "I hope tomorrow is just as nice.", "Goodnight, little room.", "That made me smile."]
        case .dreamy: return ["Off to dreamland now.", "I wonder what tomorrow holds.", "Goodnight, stars.", "Maybe I'll dream about it.", "Floating off to sleep."]
        }
    }
    static func quiet(_ p: JellyPersonality) -> [String] {
        switch p {
        case .calm: return ["Nothing much happened and that suited me fine.", "I mostly watched the room and wiggled a bit."]
        case .energetic: return ["Nobody played with me, so I bounced around on my own!", "I waited by the door for something fun to happen."]
        case .gentle: return ["It was a quiet day, and quiet days are nice too.", "I sat by the window and watched the light move."]
        case .dreamy: return ["I spent the day thinking about clouds.", "Not much happened, so I made up stories in my head."]
        }
    }

    /// One sentence per event, phrased for the personality. `names` turns a partner id into a name.
    static func sentence(_ e: JellyEvent, count: Int, p: JellyPersonality, pick: inout Pick, names: (Int) -> String) -> String {
        let bang = p == .energetic ? "!" : "."
        let food = e.detail?.lowercased() ?? "a snack"
        let partner = e.partner.map(names) ?? "a friend"
        let times = count >= 3 ? " three times" : count == 2 ? " twice" : ""
        switch e.kind {
        case .ate:
            return pick.one(["I ate \(food)\(times) and it was yummy\(bang)", "Lunch was \(food)\(times). Delicious\(bang)", "I had \(food)\(times) and licked every crumb\(bang)", "\(food.prefix(1).uppercased() + food.dropFirst()) for dinner\(times)\(bang) My favourite\(bang)"])
        case .drank:
            return pick.one(["I slurped some \(food)\(times)\(bang)", "A big sip of \(food) hit the spot\(bang)", "I drank \(food) through my straw\(times)\(bang)"])
        case .napped:
            return pick.one(["I had a lovely nap\(times)\(bang)", "I curled up and snoozed for a while\(bang)", "Nap time was the best part\(bang)", "I fell asleep sitting up\(times)\(bang)"])
        case .played:
            return pick.one(["I played \(e.detail ?? "a game") with \(partner)\(bang)", "\(partner) and I played \(e.detail ?? "together")\(times)\(bang)"])
        case .raced:
            if let place = e.detail { return pick.one(["I raced today and came \(place)\(bang)", "Race day\(bang) I finished \(place)\(bang)"]) }
            return pick.one(["I raced today\(bang)", "I ran in a race\(bang) My feet are still buzzing\(bang)"])
        case .tripped:
            return pick.one(["I tripped over my own feet\(times) and got right back up\(bang)", "Oops, I fell over\(times)\(bang) Nobody saw. Probably\(bang)", "I took a tumble\(times) but I'm fine\(bang)"])
        case .outfit:
            return pick.one(["I wore \(e.detail ?? "something new") today and felt fancy\(bang)", "New look: \(e.detail ?? "a new outfit")\(bang)"])
        case .trained:
            return pick.one(["I learned a new word for \(e.detail ?? "a trick")\(bang)", "Practice paid off: I know \(e.detail ?? "a new trick") now\(bang)", "I'm getting good at \(e.detail ?? "my trick")\(bang)"])
        case .trick:
            return pick.one(["I did my \(e.detail ?? "trick") trick\(times) when asked\(bang)", "Showed off my \(e.detail ?? "trick")\(times)\(bang)"])
        case .bathed:
            return pick.one(["I had a bath and now I sparkle\(bang)", "Bath time\(bang) Bubbles everywhere\(bang)", "I got scrubbed clean\(bang)"])
        case .social:
            return pick.one(["I hung out with \(partner)\(times)\(bang)", "\(partner) and I \(e.detail ?? "played") together\(bang)", "I spent time with \(partner) today\(bang)"])
        case .cuddled:
            return pick.one(["I got cuddles\(times)\(bang)", "You petted me and I felt all warm\(bang)", "Cuddle time was lovely\(bang)"])
        case .obeyed:
            return pick.one(["I listened when you asked me to \(e.detail ?? "come")\(bang)", "You called and I came running\(bang)"])
        case .squabbled:
            return pick.one(["\(partner) and I had a little squabble, then made up\(bang)", "I got a bit cross with \(partner), but it's fine now\(bang)"])
        }
    }

    /// FNV-1a: the same text gives the same seed on every launch (Swift's Hasher is seeded per process).
    static func stableHash(_ s: String) -> UInt64 {
        var h: UInt64 = 0xcbf29ce484222325
        for b in s.utf8 { h ^= UInt64(b); h = h &* 0x100000001B3 }
        return h
    }

    /// The top 2-3 events (the most frequent kinds, ties by first appearance) become sentences between an opener and a closer.
    static func entry(name: String, personality p: JellyPersonality, events: [JellyEvent], day: String, names: (Int) -> String) -> String {
        var pick = Pick(seed: stableHash(day) ^ (stableHash(name) &* 0x100000001B3))
        _ = pick.next()
        var out = [pick.one(openers(p))]
        if events.isEmpty { out.append(pick.one(quiet(p))) }
        else {
            // group by kind + detail + partner, keep the first of each group with its count
            var groups: [(key: String, first: JellyEvent, count: Int)] = []
            for e in events {
                let k = "\(e.kind.rawValue)|\(e.detail ?? "")|\(e.partner ?? -1)"
                if let i = groups.firstIndex(where: { $0.key == k }) { groups[i].count += 1 } else { groups.append((k, e, 1)) }
            }
            let ranked = groups.enumerated().sorted { a, b in a.element.count != b.element.count ? a.element.count > b.element.count : a.offset < b.offset }.map(\.element)
            let n = ranked.count >= 3 ? (pick.next() % 2 == 0 ? 3 : 2) : ranked.count
            for g in ranked.prefix(n) { out.append(sentence(g.first, count: g.count, p: p, pick: &pick, names: names)) }
        }
        out.append(pick.one(closers(p)))
        return out.joined(separator: " ")
    }
}

// MARK: - the book

@MainActor
@Observable
final class DiaryBook {
    static let defaultsKey = "JellyDiary.v1"
    static let unreadKey = "JellyDiary.unread.v1"
    /// Evening: an entry for today may be written from this hour (24 h clock).
    static let eveningHour: Double = 18

    private(set) var entries: [DiaryEntry] = []
    /// Jellies with an entry the player has not opened yet.
    private(set) var unread: Set<Int> = []
    /// Tier A writer (nil = templates only).
    @ObservationIgnored var writer: AITextWriter?
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let persists: Bool
    @ObservationIgnored let now: () -> Date
    @ObservationIgnored private var inFlight: Set<String> = []
    /// Entries written by the model so far (tests / log).
    @ObservationIgnored private(set) var smartCount = 0
    @ObservationIgnored private(set) var fallbackCount = 0
    @ObservationIgnored private var checkT: Double = 99

    nonisolated deinit {}

    init(defaults: UserDefaults = .standard, persists: Bool = true, writer: AITextWriter? = nil, now: @escaping () -> Date = Date.init) {
        self.defaults = defaults; self.persists = persists; self.writer = writer; self.now = now
        if persists {
            if defaults.bool(forKey: "VoiceReset") || defaults.bool(forKey: "DiaryReset") { defaults.removeObject(forKey: Self.defaultsKey); defaults.removeObject(forKey: Self.unreadKey) }
            if let d = defaults.data(forKey: Self.defaultsKey), let e = try? JSONDecoder().decode([DiaryEntry].self, from: d) { entries = e }
            unread = Set(defaults.array(forKey: Self.unreadKey) as? [Int] ?? [])
        }
        prune()
    }

    func entry(jelly: Int, day: String) -> DiaryEntry? { entries.first { $0.jelly == jelly && $0.day == day } }
    /// Newest first.
    func entries(jelly: Int) -> [DiaryEntry] { entries.filter { $0.jelly == jelly }.sorted { $0.day > $1.day } }
    var hasUnread: Bool { !unread.isEmpty }
    func markRead(_ jelly: Int) { if unread.remove(jelly) != nil { save() } }

    func prune() {
        let cutoff = EventLog.dayKey(now().addingTimeInterval(-Double(EventLog.keepDays) * 86_400))
        entries.removeAll { $0.day < cutoff }
    }

    private func save() {
        guard persists else { return }
        if let d = try? JSONEncoder().encode(entries) { defaults.set(d, forKey: Self.defaultsKey) }
        defaults.set(Array(unread), forKey: Self.unreadKey)
    }

    /// The day that is due an entry for `jelly` right now, or nil: yesterday when the game opened on a new day without one; today once it is evening.
    /// A quiet day (no events) still gets today's evening entry; yesterday only if it had events.
    func dueDay(jelly: Int, log: EventLog, hour: Double) -> String? {
        let today = log.today, yesterday = log.yesterday
        if entry(jelly: jelly, day: yesterday) == nil, !log.events(jelly: jelly, day: yesterday).isEmpty { return yesterday }
        if hour >= Self.eveningHour, entry(jelly: jelly, day: today) == nil { return today }
        return nil
    }

    /// Called every step with the clock hour; checks once a second, writes what is due (the model off the main thread, the template at once).
    func tick(dt: Double, hour: Double, log: EventLog, jellies: [(id: Int, name: String)]) {
        checkT += dt
        guard checkT >= 1 else { return }
        checkT = 0
        for j in jellies {
            guard let day = dueDay(jelly: j.id, log: log, hour: hour) else { continue }
            write(jelly: j.id, name: j.name, day: day, log: log, names: { id in jellies.first { $0.id == id }?.name ?? "a friend" })
        }
    }

    /// Writes the entry for one Jelly and day (Tier A when available and allowed, else the template). Idempotent per (jelly, day).
    func write(jelly: Int, name: String, day: String, log: EventLog, names: @escaping (Int) -> String, force: Bool = false) {
        let key = "\(jelly)-\(day)"
        guard force || entry(jelly: jelly, day: day) == nil, !inFlight.contains(key) else { return }
        let events = log.events(jelly: jelly, day: day)
        let p = JellyPersonality.of(name: name)
        let roster = Array(Set([name] + events.compactMap { $0.partner.map(names) }))
        let template = TemplateDiary.entry(name: name, personality: p, events: events, day: day, names: names)
        guard let writer, writer.state.isAvailable else { store(DiaryEntry(jelly: jelly, day: day, text: template, smart: false, written: now())); fallbackCount += 1; return }
        inFlight.insert(key)
        let facts = EventLog.facts(events, names: names)
        Task { [weak self] in
            var text = template, smart = false
            do {
                let raw = try await VoiceCoordinator.withBudget(12) { try await writer.diary(name: name, personality: p.hint, facts: facts) }
                if let ok = DiarySafety.check(raw, roster: roster) { text = ok; smart = true }
            } catch {}
            guard let self else { return }
            self.inFlight.remove(key)
            if smart { self.smartCount += 1 } else { self.fallbackCount += 1 }
            self.store(DiaryEntry(jelly: jelly, day: day, text: text, smart: smart, written: self.now()))
        }
    }

    private func store(_ e: DiaryEntry) {
        entries.removeAll { $0.jelly == e.jelly && $0.day == e.day }
        entries.append(e)
        unread.insert(e.jelly)
        prune()
        save()
    }

    /// Debug / capture: write today's entry for every Jelly now (`-DiaryDemo 1`), from whatever the log has (seeded sample events when empty).
    func demo(log: EventLog, jellies: [(id: Int, name: String)]) {
        for j in jellies {
            if log.events(jelly: j.id, day: log.today).isEmpty {
                log.record(.ate, jelly: j.id, detail: j.id == 1 ? "Pizza" : "Berries")
                log.record(.napped, jelly: j.id)
                if jellies.count > 1 { log.record(.social, jelly: j.id, detail: "zoomies", partner: jellies[(j.id + 1) % jellies.count].id) }
                if j.id == 0 { log.record(.tripped, jelly: 0) }
            }
            write(jelly: j.id, name: j.name, day: log.today, log: log, names: { id in jellies.first { $0.id == id }?.name ?? "a friend" }, force: true)
        }
    }
}
