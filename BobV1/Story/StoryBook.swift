//
//  StoryBook.swift
//  The cache and the schedule. One friendship note per (Jelmiko, housemate), each with the facts fingerprint and the day it was written.
//  Rules: the saved text is shown at once (never an empty spot, never a spinner; a first view writes a pre-written one on the spot, synchronously);
//  a note at most once a day when its facts changed or it is a week old. Writing is async and off the main thread at low priority, never during a
//  meal / Show / race / match and not in Low Power Mode. The saved text keeps its placeholders; the names are put in at display (a rename never leaves a stale name).
//

import Foundation

nonisolated struct StoryEntry: Codable, Equatable, Sendable {
    var template: String
    var fingerprint: String
    var day: Int
    /// Who wrote it ("template" / "model").
    var writer: String = "template"
    /// The fact keys the text states (nil in an older save: such a line is checked by shape only).
    var keys: [String]? = nil
    var byModel: Bool { writer == "model" }
}

nonisolated struct StorySaved: Codable, Equatable, Sendable {
    var about: [String: StoryEntry] = [:]
    var notes: [String: StoryEntry] = [:]
    var used: [String: [Int]] = [:]
    var counter: [String: Int] = [:]
    var salt: UInt64 = 0
    /// Fingerprints of texts the player chose not to see again ("Don't show this one"); no writer's answer with one of these is ever accepted.
    var hidden: [String]? = nil
    /// "Write another": per blurb / note key, [day, count]; at most `StoryBook.rewritesPerDay` a day.
    var rewrites: [String: [Int]]? = nil
    /// News events (StoryEvent.id) -> the day each was first used in a line: a news item is used for one day only.
    var news: [String: Int]? = nil
    /// News events the model has already been asked about once.
    var newsTried: [String]? = nil
    /// "<key>" -> "<day>|<fingerprint of the pre-written text>": the model was asked once to replace that pre-written text today.
    var modelTried: [String: String]? = nil
}

nonisolated enum StoryFingerprint {
    private static func hex(_ parts: [String]) -> String { String(StoryTemplates.fnv(parts), radix: 16) }
    /// A fingerprint of a text (placeholders in), for "Don't show this one" and the feedback lookup.
    static func text(_ template: String) -> String { hex(["t", template]) }
    static func note(_ f: StoryFacts, _ h: StoryFacts.Housemate) -> String {
        hex(["n", String(h.id), StoryTemplates.tier(h).rawValue, h.topEmote ?? "-", h.relationshipLevel ?? "-", h.mostPlayedWith ? "mp" : "-", h.sharedGroup ? "grp" : "-", h.sharedSpot ?? "-", h.napBuddies ? "nap" : "-"])
    }
}

/// What a writer thread may read of the main-actor world (set by the book before it asks the chain).
nonisolated final class StoryGateBox: @unchecked Sendable {
    private let lock = NSLock()
    private var _busy = false, _lowPower = false
    var busy: Bool { get { lock.lock(); defer { lock.unlock() }; return _busy } set { lock.lock(); _busy = newValue; lock.unlock() } }
    var lowPower: Bool { get { lock.lock(); defer { lock.unlock() }; return _lowPower } set { lock.lock(); _lowPower = newValue; lock.unlock() } }
    func input() -> StoryModelGate.Input {
        StoryModelGate.Input(modelAvailable: false, localeSupported: false, english: StoryModelGate.appIsEnglish, foreground: StoryAppState.foreground, busy: busy,
                             lowPower: lowPower || ProcessInfo.processInfo.isLowPowerModeEnabled, thermalOK: StoryModelGate.thermalOK(ProcessInfo.processInfo.thermalState), switchedOn: StorySettings.rawOn() || StoryAppState.devDump, crashDisabled: StoryModelSentinel.disabledStep() != nil, profileReady: StoryAppState.profileReady())
    }
}

/// The fingerprints of the texts the player hid, shared with the chain (any thread).
nonisolated final class StoryHiddenSet: @unchecked Sendable {
    private let lock = NSLock()
    private var set: Set<String>
    init(_ a: [String] = []) { set = Set(a) }
    func contains(_ k: String) -> Bool { lock.lock(); defer { lock.unlock() }; return set.contains(k) }
    func insert(_ k: String) { lock.lock(); set.insert(k); lock.unlock() }
    var all: [String] { lock.lock(); defer { lock.unlock() }; return set.sorted() }
}

@MainActor
final class StoryBook {
    static let shared = StoryBook()
    static let defaultsKey = "StoryBook.v1"
    static let noteMinAgeDays = 7

    private(set) var saved: StorySaved
    let memory: StoryMemory
    var defaults: UserDefaults
    // injected for the tests and the machine's real state
    var today: () -> Int = { Int(Date().timeIntervalSince1970 / 86400) }
    var busy: () -> Bool = { false }
    var lowPower: () -> Bool = { ProcessInfo.processInfo.isLowPowerModeEnabled }
    /// `-StoryForce 1`: ignore the schedule.
    var force = false
    var chain: StoryChain { didSet { chain.hidden = hidden } }
    let hidden: StoryHiddenSet
    let gateBox = StoryGateBox()
    /// "Write another" is limited to this many a day, per blurb or note.
    static let rewritesPerDay = 3
    /// Files the model's feedback for a text the player hid (set to the model client's `fileFeedback`).
    var feedback: (String) -> Void = { _ in }
    private var inFlight: Set<String> = []

    init(defaults: UserDefaults = .standard, chain: StoryChain? = nil) {
        if defaults === UserDefaults.standard { StoryModelSentinel.launchCheckOnce() }
        self.defaults = defaults
        var s = Self.load(defaults)
        if s.salt == 0 { s.salt = UInt64.random(in: 1...UInt64.max); defaults.set(try? JSONEncoder().encode(s), forKey: Self.defaultsKey) }
        saved = s
        memory = StoryMemory(salt: s.salt, used: s.used, counter: s.counter)
        hidden = StoryHiddenSet(s.hidden ?? [])
        self.chain = chain ?? StoryChain(Self.defaultWriters(memory: memory, box: gateBox))
        self.chain.hidden = hidden
        feedback = Self.defaultFeedback
        force = DevArgs.enabled && UserDefaults.standard.integer(forKey: "StoryForce") != 0
    }

    nonisolated static func load(_ d: UserDefaults) -> StorySaved {
        guard let data = d.data(forKey: defaultsKey), let s = try? JSONDecoder().decode(StorySaved.self, from: data) else { return StorySaved() }
        return s
    }
    func persist() {
        let m = memory.snapshot()
        saved.used = m.used; saved.counter = m.counter; saved.hidden = hidden.all
        if let data = try? JSONEncoder().encode(saved) { defaults.set(data, forKey: Self.defaultsKey) }
    }

    /// The writers in order: the on-device model first where the framework and the system have it, then the pre-written bank.
    static func defaultWriters(memory: StoryMemory, box: StoryGateBox) -> [StoryWriter] {
        var w: [StoryWriter] = []
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) { w.append(ModelWriter(client: AppleModelClient.shared, gate: { box.input() })) }
        #endif
        w.append(TemplateWriter(memory: memory))
        return w
    }
    static let defaultFeedback: (String) -> Void = { t in
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            if let data = AppleModelClient.shared.fileFeedback(forTemplate: t), DevArgs.enabled,
               let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?.appendingPathComponent("story_feedback_\(Int(Date().timeIntervalSince1970)).json") { try? data.write(to: url) }
        }
        #endif
    }

    // MARK: news

    /// True while a news item may still be used: never used, or first used today.
    func newsAvailable(_ e: StoryEvent) -> Bool { let u = saved.news?[e.id]; return u == nil || u == today() }

    // MARK: showing (synchronous, never empty)

    struct Line: Equatable { var text: String; var byModel: Bool }

    /// The opening words of the notes ABOVE this one on the same Profile: two notes on one page never start with the same word (the row order decides, so the first row never moves for the second).
    private func earlierOpenings(_ f: StoryFacts, before h: StoryFacts.Housemate) -> Set<String> {
        var out: Set<String> = []
        for p in f.housemates {
            if p.id == h.id { break }
            if let l = noteLine(f, with: p) { out.insert(StoryTemplates.firstWord(l.text)) }
        }
        return out
    }

    func noteLine(_ f: StoryFacts, with h: StoryFacts.Housemate) -> Line? {
        guard StoryTemplates.noteAllowed(f, h) else { return nil }          // not enough sampled time together to say anything true: the row shows its calm placeholder
        let key = "\(f.id)>\(h.id)"
        let values = StoryFill.values(f, with: h), offered = Set(values.keys)
        let avoid = earlierOpenings(f, before: h)
        if let e = saved.notes[key], !hidden.contains(StoryFingerprint.text(e.template)) {
            let fin = StoryFill.apply(e.template, values)
            if !avoid.contains(StoryTemplates.firstWord(fin)),
               StoryGuard.check(template: e.template, final: fin, kind: .friendship, offered: offered, values: values, keys: e.keys, available: e.keys == nil ? nil : StoryFill.facts(f, with: h)).passed { return Line(text: fin, byModel: e.byModel) }
        }
        let pre = TemplateWriter(memory: memory)
        guard let t = pre.writeNote(f, h, avoid: avoid) ?? pre.writeNote(f, h) else { return nil }
        saved.notes[key] = StoryEntry(template: t.template, fingerprint: StoryFingerprint.note(f, h), day: today(), writer: "template", keys: t.keys)
        persist()
        return Line(text: StoryFill.apply(t.template, values), byModel: false)
    }

    // MARK: the schedule

    nonisolated static func noteDue(_ e: StoryEntry?, fingerprint: String, today: Int, rotate: Bool = true) -> Bool {
        guard let e else { return true }
        if e.day >= today { return false }
        if e.fingerprint != fingerprint { return true }
        return rotate && today - e.day >= noteMinAgeDays
    }

    /// A model writer that can really answer right now (framework, system, language, the player's switch). The simulator and unsupported phones are false.
    var hasModel: Bool { chain.writers.contains { $0.name != "template" && $0.isUsable } }
    var mayWriteNow: Bool { !busy() && !lowPower() }
    func syncGate() { gateBox.busy = busy(); gateBox.lowPower = lowPower() }

    /// Asks the chain for new housemate notes where the schedule says so. Never blocks the main thread (the chain runs off it) and never touches what is on screen until it has an answer.
    /// While a Profile is open (`rotate: false`) a note changes only when its facts changed; the model's turn replaces a PRE-WRITTEN note only with a model line that passed
    /// the guard, once per text per day. A model that gives no answer changes nothing.
    @discardableResult
    func refresh(_ f: StoryFacts, rotate: Bool = true) async -> [String] {
        guard force || mayWriteNow else { return [] }
        syncGate()
        var done: [String] = []
        let day = today()
        let chain = self.chain
        let modelOnly = StoryChain(chain.writers.filter { $0.name != "template" && $0.isUsable }); var mo = modelOnly; mo.hidden = hidden
        for h in f.housemates {
            let nk = "\(f.id)>\(h.id)", nfp = StoryFingerprint.note(f, h)
            if hasModel, let e = saved.notes[nk], !e.byModel, !inFlight.contains("n" + nk) {
                let tag = "\(day)|\(StoryFingerprint.text(e.template))"
                if (saved.modelTried ?? [:])[nk] != tag {
                    var t = saved.modelTried ?? [:]; t[nk] = tag; saved.modelTried = t
                    inFlight.insert("n" + nk); defer { inFlight.remove("n" + nk) }
                    let m = mo
                    let r = await Task.detached(priority: .utility) { await m.friendship(f, with: h) }.value
                    if let r, saved.notes[nk]?.template == e.template { saved.notes[nk] = StoryEntry(template: r.template, fingerprint: nfp, day: day, writer: r.writer, keys: r.keys); done.append("note:\(nk)") }
                    persist()
                }
            }
            guard force || (Self.noteDue(saved.notes[nk], fingerprint: nfp, today: day, rotate: rotate) && !inFlight.contains("n" + nk)) else { continue }
            inFlight.insert("n" + nk); defer { inFlight.remove("n" + nk) }
            let r = await Task.detached(priority: .utility) { await chain.friendship(f, with: h) }.value
            if let r { saved.notes[nk] = StoryEntry(template: r.template, fingerprint: nfp, day: day, writer: r.writer, keys: r.keys); done.append("note:\(nk)"); persist() }
        }
        return done
    }

    // MARK: the player's two actions (phase 3 puts them behind a long-press)

    enum Another: Equatable { case written(Line), limit, nothing }

    private func rewriteKey(_ f: StoryFacts, _ h: StoryFacts.Housemate) -> String { "n\(f.id)>\(h.id)" }
    func rewritesLeft(_ f: StoryFacts, _ h: StoryFacts.Housemate) -> Int {
        let r = saved.rewrites?[rewriteKey(f, h)] ?? []
        return r.count == 2 && r[0] == today() ? max(0, Self.rewritesPerDay - r[1]) : Self.rewritesPerDay
    }

    /// "Write another": asks the chain again (at most 3 a day per text; the once-a-day schedule does not apply). The old text is never the answer.
    func writeAnother(_ f: StoryFacts, with h: StoryFacts.Housemate) async -> Another {
        guard rewritesLeft(f, h) > 0 else { return .limit }
        syncGate()
        let day = today(), k = rewriteKey(f, h)
        let oldKey = saved.notes["\(f.id)>\(h.id)"]
        var rw = saved.rewrites ?? [:]
        let used = (rw[k]?.first == day ? rw[k]![1] : 0) + 1
        rw[k] = [day, used]; saved.rewrites = rw
        let chain = self.chain
        for _ in 0..<3 {
            let r: StoryResult? = await Task.detached(priority: .userInitiated) { await chain.friendship(f, with: h) }.value
            guard let r else { break }
            if r.template == oldKey?.template { continue }
            saved.notes["\(f.id)>\(h.id)"] = StoryEntry(template: r.template, fingerprint: StoryFingerprint.note(f, h), day: day, writer: r.writer, keys: r.keys)
            persist()
            return .written(Line(text: r.final, byModel: r.writer == "model"))
        }
        persist()
        return .nothing
    }

    /// "Don't show this one": the text is replaced at once by a pre-written one, its fingerprint is remembered so no writer can bring it back, and the model's feedback is filed.
    @discardableResult
    func dontShow(_ f: StoryFacts, with h: StoryFacts.Housemate) -> Line? {
        let old = saved.notes["\(f.id)>\(h.id)"]
        if let old {
            hidden.insert(StoryFingerprint.text(old.template))
            if old.byModel { feedback(old.template) }
        }
        let pre = TemplateWriter(memory: memory)
        var line: Line?
        for _ in 0..<6 {
            guard let ans = pre.writeNote(f, h), !hidden.contains(StoryFingerprint.text(ans.template)), ans.template != old?.template else { continue }
            let t = ans.template
            saved.notes["\(f.id)>\(h.id)"] = StoryEntry(template: t, fingerprint: StoryFingerprint.note(f, h), day: today(), writer: "template", keys: ans.keys); line = Line(text: StoryFill.apply(t, StoryFill.values(f, with: h)), byModel: false)
            break
        }
        persist()
        return line
    }

    // MARK: purge

    /// Removes the blurb of `id` and every note that names it (both directions), and the pattern memory for them. Works on any defaults (the let-go purge calls it).
    nonisolated static func purge(_ id: Int, _ d: UserDefaults) {
        var s = load(d)
        guard !s.about.isEmpty || !s.notes.isEmpty || !s.used.isEmpty else { return }
        let sid = String(id)
        s.about.removeValue(forKey: sid)
        func involves(_ k: String) -> Bool { k.split(separator: ">").contains { $0 == Substring(sid) } }
        for k in s.notes.keys where involves(k) { s.notes.removeValue(forKey: k) }
        for k in s.used.keys where k == "about.\(sid)" || (k.hasPrefix("note.") && involves(String(k.dropFirst(5)))) { s.used.removeValue(forKey: k) }
        for k in s.counter.keys where k == "about.\(sid)" || (k.hasPrefix("note.") && involves(String(k.dropFirst(5)))) { s.counter.removeValue(forKey: k) }
        if let data = try? JSONEncoder().encode(s) { d.set(data, forKey: defaultsKey) }
    }

    /// Re-reads from defaults (after a purge) and drops the in-memory copies.
    func reload() {
        saved = Self.load(defaults)
        memory.replace(used: saved.used, counter: saved.counter)
    }
}
