//
//  WidgetBridge.swift
//  The app's side of the Home Screen / Lock Screen widget. It writes the compact JSON snapshot (Shared/JellySnapshot.swift) and the portrait
//  PNGs into the App Group container, and asks WidgetKit to reload, throttled:
//    - snapshot: written on every `publish` (cheap, atomic); `publish` runs when a Jelly's tiers / mood change (checked every 10 s while
//      playing), every 5 min as a heartbeat, and always when the app leaves `.active`.
//    - reloadAllTimelines: at most once a minute while playing (a throttled one is flushed by the next check); unconditional on leaving.
//    - portraits: re-rendered (JellyPortraitRenderer, the real Metal renderer) only when the look changes meaningfully (colour, coat tier,
//      dirt in steps of 0.1, shine). A changed look is rendered when leaving `.active` (the `.inactive` step still has the GPU; it is not
//      allowed once backgrounded, and nobody sees the hitch); while playing only a MISSING portrait (first run) is rendered, at most every 5 min.
//  The widget is read-only; nothing here is read back into the game.
//

import Foundation
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
    }

    static let reloadEvery: TimeInterval = 60
    static let portraitEvery: TimeInterval = 300
    static let heartbeat: TimeInterval = 300
    static let checkEvery: Float = 10

    /// The App Group container (nil when unavailable); tests point it at a temp folder.
    var directory: URL?
    var reload: () -> Void
    var now: () -> Date
    var rendersPortraits: Bool
    private(set) var writes = 0, reloads = 0, portraitRenders = 0
    @ObservationIgnored private var acc: Float = 0
    private var lastReload: Date?, lastPublish: Date?, lastRender: Date?
    private var pendingReload = false
    private var stateKey = ""
    private var rendered: [Int: String] = [:]
    private var rendering = false
    private var lastInputs: [Input] = []

    init(directory: URL? = JellyShare.containerURL, now: @escaping () -> Date = Date.init, rendersPortraits: Bool = true, reload: @escaping () -> Void = { WidgetCenter.shared.reloadAllTimelines() }) {
        self.directory = directory; self.now = now; self.rendersPortraits = rendersPortraits; self.reload = reload
        for r in JellySnapshot.read(from: directory)?.jellies ?? [] where !r.look.isEmpty { rendered[r.id] = r.look }
    }
    nonisolated deinit {}

    // MARK: building the snapshot

    /// Roster id -> colour name (Bob blue, Pip yellow, Moss green, Lavender lavender: JellyRoster.palette).
    static func colorName(_ id: Int) -> String { ["blue", "yellow", "green", "lavender"][min(max(id, 0), 3)] }
    /// The body palette of a roster id (each Jelly's own colours).
    static func palette(_ id: Int) -> Palette { JellyRoster.palette(id) ?? PaletteKey.blue.palette }

    static func record(_ i: Input, look: String) -> JellyRecord {
        let lv = (0..<NeedKind.allCases.count).map { $0 < i.levels.count ? min(max(i.levels[$0], 0), 1) : 1 }
        return JellyRecord(id: i.id, name: i.name, color: i.color, levels: lv, dirt: min(max(i.dirt, 0), 1), sparkle: min(max(i.sparkle, 0), 1),
                           mood: AwayMath.mood(of: lv).rawValue, look: look, feature: JellyRoster.feature(i.id).rawValue)
    }
    static func snapshot(_ inputs: [Input], at date: Date, looks: [Int: String] = [:]) -> JellySnapshot {
        JellySnapshot(savedAt: date, jellies: inputs.prefix(JellyShare.maxJellies).map { record($0, look: looks[$0.id] ?? "") })
    }

    /// What the portrait shows: changes only when the picture would meaningfully change.
    static func lookKey(_ i: Input) -> String {
        let coat = JellyCoatTier.of(dirt: i.dirt, sparkle: i.sparkle)
        return "\(i.color)|\(coat.rawValue)|\(Int((min(max(i.dirt, 0), 1) * 10).rounded(.down)))|\(Int((i.sparkle * 2).rounded()))"
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
    func publish(_ inputs: [Input], force: Bool) {
        lastInputs = inputs
        guard !inputs.isEmpty else { return }
        let t = now()
        if Self.snapshot(inputs, at: t, looks: rendered).write(to: directory) { writes += 1 }
        lastPublish = t
        stateKey = Self.stateKey(inputs)
        requestReload(force: force)
        refreshPortraits(inputs, force: force)
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
            refreshPortraits(ins, force: false)
        }
    }

    /// The app is leaving `.active` (still allowed to use the GPU in `.inactive`): the final snapshot, an unthrottled reload, a fresh portrait if stale.
    func leftActive(_ inputs: [Input]) { publish(inputs, force: true) }

    // MARK: portraits

    private func portraitURL(_ id: Int) -> URL? { directory?.appendingPathComponent(JellyShare.portraitFile(id)) }

    private func refreshPortraits(_ inputs: [Input], force: Bool) {
        guard rendersPortraits, !rendering, directory != nil else { return }
        let stale = inputs.filter { rendered[$0.id] != Self.lookKey($0) || !(portraitURL($0.id).map { FileManager.default.fileExists(atPath: $0.path) } ?? false) }
        guard !stale.isEmpty else { return }
        // While playing, only a MISSING portrait is rendered (a first run): building the rig is a few hundred ms to seconds on the main thread, so a
        // changed look waits for the app to leave `.active` (its `.inactive` step still has the GPU), where nobody sees the hitch.
        let missing = stale.contains { !(portraitURL($0.id).map { FileManager.default.fileExists(atPath: $0.path) } ?? false) }
        if !force && !missing { return }
        if !force, let l = lastRender, now().timeIntervalSince(l) < Self.portraitEvery { return }
        rendering = true
        Task { @MainActor [weak self] in
            await Task.yield()
            self?.renderNow(stale)
        }
    }

    private func renderNow(_ stale: [Input]) {
        defer { rendering = false; lastRender = now() }
        guard let renderer = JellyPortraitRenderer() else { return }
        var any = false
        for i in stale {
            guard let url = portraitURL(i.id),
                  let px = renderer.render(palette: Self.palette(i.id), look: JellyPortraitRenderer.look(dirt: i.dirt, sparkle: i.sparkle)),
                  JellyPortraitRenderer.writePNG(bgra: px, size: renderer.size, to: url) else { continue }
            rendered[i.id] = Self.lookKey(i); portraitRenders += 1; any = true
        }
        guard any else { return }
        if !lastInputs.isEmpty, Self.snapshot(lastInputs, at: now(), looks: rendered).write(to: directory) { writes += 1 }
        requestReload(force: true)
    }
}
