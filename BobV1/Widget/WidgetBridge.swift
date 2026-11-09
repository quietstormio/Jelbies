//
//  WidgetBridge.swift
//  The app's side of the Home Screen / Lock Screen widget. It writes the compact JSON snapshot (Shared/JellySnapshot.swift) and the portrait
//  PNGs into the App Group container, and asks WidgetKit to reload, throttled:
//    - snapshot: written on every `publish` (cheap, atomic); `publish` runs when a Jelly's tiers / mood change (checked every 10 s while
//      playing), every 5 min as a heartbeat, and always when the app leaves `.active`.
//    - reloadAllTimelines: at most once a minute while playing (a throttled one is flushed by the next check); unconditional on leaving.
//    - portraits: re-rendered (JellyPortraitRenderer, the real Metal renderer) only when the look changes meaningfully (colour, coat tier,
//      dirt in steps of 0.1, shine), at most every 5 min, and ONLY while the app is active: the rig is built off the main thread / in short
//      slices, the GPU encode is one short main-thread step, the rig is cached and freed on a memory warning, and a render that overruns its
//      time budget is dropped (the previous PNG stays). Leaving `.active` (inactive / background) writes the snapshot JSON only, no render.
//  The widget is read-only; nothing here is read back into the game.
//

import Foundation
import UIKit
import WidgetKit

@MainActor
final class WidgetBridge {
    /// What the game knows about one Jelly. GameCare builds one per persisted Jelly (today: Bob; ids 0 / 1 / 2 = Bob / Pip / Moss).
    struct Input: Equatable {
        var id: Int
        var name: String
        /// "blue" / "yellow" / "green" (see `colorName`).
        var color: String
        /// Hunger, thirst, attention.
        var levels: [Float]
        var dirt: Float
        var sparkle: Float
        /// The Jelbie's INSTANCE id (a duplicate Bob has his own adopted colour); nil = the species of `color` (the old behaviour).
        var character: Int? = nil
    }

    static let reloadEvery: TimeInterval = 60
    static let portraitEvery: TimeInterval = 300
    static let heartbeat: TimeInterval = 300
    static let checkEvery: Float = 10
    /// Wall-clock budget of one portrait pass (rig build + all renders); an overrun keeps the previous PNGs.
    static let renderBudget: TimeInterval = 8

    /// The App Group container (nil when unavailable); tests point it at a temp folder.
    var directory: URL?
    var reload: () -> Void
    var now: () -> Date
    var rendersPortraits: Bool
    /// True while the app is `.active` (the only state a portrait may be rendered in); tests override it.
    var isForeground: () -> Bool
    private(set) var writes = 0, reloads = 0, portraitRenders = 0
    @ObservationIgnored private var acc: Float = 0
    private var lastReload: Date?, lastPublish: Date?, lastRender: Date?
    private var pendingReload = false
    private var stateKey = ""
    private var rendered: [Int: String] = [:]
    private var rendering = false
    private var renderer: JellyPortraitRenderer?
    private var renderTask: Task<Void, Never>?
    private var lastInputs: [Input] = []

    init(directory: URL? = JellyShare.containerURL, now: @escaping () -> Date = Date.init, rendersPortraits: Bool = true, isForeground: @escaping () -> Bool = { UIApplication.shared.applicationState == .active }, reload: @escaping () -> Void = { WidgetCenter.shared.reloadAllTimelines() }) {
        self.directory = directory; self.now = now; self.rendersPortraits = rendersPortraits; self.isForeground = isForeground; self.reload = reload
        for r in JellySnapshot.read(from: directory)?.jellies ?? [] where !r.look.isEmpty { rendered[r.id] = r.look }
        NotificationCenter.default.addObserver(forName: UIApplication.didReceiveMemoryWarningNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.freeRenderer() }
        }
    }

    /// Drops the cached portrait rig (memory warning) and abandons a pass that is building one; the existing PNGs stay.
    func freeRenderer() { renderTask?.cancel(); renderer = nil }
    nonisolated deinit {}

    // MARK: building the snapshot

    /// SPECIES id -> colour name (Bob blue, Pip yellow, Moss green, Lavender lavender: JellyRoster.palette). Callers holding an instance id pass `JellyRoster.species(id)`.
    static func colorName(_ id: Int) -> String { ["blue", "yellow", "green", "lavender", "teddy", "pearl", "panda"][min(max(id, 0), 6)] }
    /// Colour name -> character (the inverse of `colorName`; the snapshot carries the colour, not the character).
    static func character(ofColor c: String) -> Int { ["blue", "yellow", "green", "lavender", "teddy", "pearl", "panda"].firstIndex(of: c) ?? (c == "purple" ? 3 : 0) }
    /// The body palette of a colour name (each Jelly's own colours).
    static func palette(_ id: Int) -> Palette { JellyRoster.palette(id) ?? PaletteKey.blue.palette }
    static func palette(color c: String) -> Palette { palette(character(ofColor: c)) }

    static func record(_ i: Input, look: String) -> JellyRecord {
        let lv = (0..<NeedKind.allCases.count).map { $0 < i.levels.count ? min(max(i.levels[$0], 0), 1) : 1 }
        return JellyRecord(id: i.id, name: i.name, color: i.color, levels: lv, dirt: min(max(i.dirt, 0), 1), sparkle: min(max(i.sparkle, 0), 1),
                           mood: AwayMath.mood(of: lv).rawValue, look: look, feature: JellyRoster.feature(character(ofColor: i.color)).rawValue)
    }
    static func snapshot(_ inputs: [Input], at date: Date, looks: [Int: String] = [:]) -> JellySnapshot {
        JellySnapshot(savedAt: date, jellies: inputs.prefix(JellyShare.maxJellies).map { record($0, look: looks[$0.id] ?? "") })
    }

    /// What the portrait shows: changes only when the picture would meaningfully change.
    static func lookKey(_ i: Input) -> String {
        let coat = JellyCoatTier.of(dirt: i.dirt, sparkle: i.sparkle)
        let who = (i.character ?? 0) >= JellyRoster.firstInstanceID ? "|i\(i.character ?? 0)" : ""          // a duplicate has his own colour; the first of a species keeps the old key
        return "\(i.color)\(who)|\(coat.rawValue)|\(Int((min(max(i.dirt, 0), 1) * 10).rounded(.down)))|\(Int((i.sparkle * 2).rounded()))"
    }
    /// The tiers + mood of every Jelly: when this changes, the widget has something new to say.
    static func stateKey(_ inputs: [Input]) -> String {
        inputs.map { i in
            let s = JellyState(record: record(i, look: ""), awaySeconds: 0)
            return "\(i.id)\(JellyCare.allCases.map { String(s.tier($0).rawValue) }.joined())\(s.mood.rawValue)"
        }.joined(separator: ",")
    }

    // MARK: publishing

    /// Writes the snapshot and reloads the widget (throttled unless `force`), then refreshes stale portraits.
    func publish(_ inputs: [Input], force: Bool, render: Bool = true) {
        lastInputs = inputs
        guard !inputs.isEmpty else { return }
        let t = now()
        if Self.snapshot(inputs, at: t, looks: rendered).write(to: directory) { writes += 1 }
        lastPublish = t
        stateKey = Self.stateKey(inputs)
        requestReload(force: force)
        if render { refreshPortraits(inputs) }
    }

    private func requestReload(force: Bool) {
        let t = now()
        if force || lastReload == nil || t.timeIntervalSince(lastReload!) >= Self.reloadEvery {
            lastReload = t; pendingReload = false; reloads += 1
            reload()
        } else { pendingReload = true }
    }

    /// Called every sim step: every 10 s checks whether anything the widget shows has changed.
    func tick(dt: Float, inputs: () -> [Input]) {
        acc += dt
        guard acc >= Self.checkEvery else { return }
        acc = 0
        let ins = inputs()
        let t = now()
        if Self.stateKey(ins) != stateKey || lastPublish.map({ t.timeIntervalSince($0) >= Self.heartbeat }) ?? true {
            publish(ins, force: false)
        } else {
            lastInputs = ins
            if pendingReload { requestReload(force: false) }
            refreshPortraits(ins)
        }
    }

    /// The app is leaving `.active` (inactive or background): the final snapshot and an unthrottled reload. No portrait is rendered here.
    func leftActive(_ inputs: [Input]) { publish(inputs, force: true, render: false) }

    // MARK: portraits

    private func portraitURL(_ id: Int) -> URL? { directory?.appendingPathComponent(JellyShare.portraitFile(id)) }

    private func refreshPortraits(_ inputs: [Input]) {
        guard rendersPortraits, !rendering, directory != nil, isForeground() else { return }
        let stale = inputs.filter { rendered[$0.id] != Self.lookKey($0) || !(portraitURL($0.id).map { FileManager.default.fileExists(atPath: $0.path) } ?? false) }
        guard !stale.isEmpty else { return }
        if let l = lastRender, now().timeIntervalSince(l) < Self.portraitEvery { return }
        rendering = true
        renderTask = Task { @MainActor [weak self] in
            await self?.renderNow(stale)
        }
    }

    private func renderNow(_ stale: [Input]) async {
        defer { rendering = false; lastRender = now(); renderTask = nil }
        let deadline = ContinuousClock.now + .seconds(Self.renderBudget)
        if renderer == nil {
            let built = await JellyPortraitRenderer.make(deadline: deadline)
            guard !Task.isCancelled else { return }          // a memory warning freed us while the rig was building
            renderer = built
        }
        guard let renderer else { return }
        var any = false
        for i in stale {
            await Task.yield()
            // GPU work only while active, and only inside the time budget: otherwise the previous PNG simply stays
            guard !Task.isCancelled, isForeground(), ContinuousClock.now < deadline, let url = portraitURL(i.id) else { break }
            guard let px = renderer.render(palette: i.character.map { Self.palette($0) } ?? Self.palette(color: i.color), look: JellyPortraitRenderer.look(dirt: i.dirt, sparkle: i.sparkle)) else {
                self.renderer = nil; break          // the GPU refused: rebuild the rig next time
            }
            let size = renderer.size
            guard await Task.detached(priority: .utility, operation: { JellyPortraitRenderer.writePNG(bgra: px, size: size, to: url) }).value else { continue }
            rendered[i.id] = Self.lookKey(i); portraitRenders += 1; any = true
        }
        guard any else { return }
        if !lastInputs.isEmpty, Self.snapshot(lastInputs, at: now(), looks: rendered).write(to: directory) { writes += 1 }
        requestReload(force: true)
    }
}
