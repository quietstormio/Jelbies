//
//  GardenModels.swift
//  The planting game of the Garden (Garden/): five plants, four plots, growth in REAL time while watered. Offline, saved under its own key
//  ("Garden.v1") so the store / roster saves are untouched. A plant never dies: an unwatered plot just pauses.
//
//  Growth: a plot has `progress` (watered seconds) and `wetUntil` (absolute time the soil stays wet). Watering wets the soil for `waterSeconds`, banked up
//  to `maxWetAhead`. `tick(now:)` adds the overlap of [last, now] with the wet window, so time away (the app closed) counts for exactly the time the soil
//  was wet, nothing more and nothing less.
//

import Foundation
import Observation
import simd

nonisolated enum GardenPlant: String, CaseIterable, Codable, Sendable {
    case daisy, tulip, rose, strawberry, blueberry

    var title: String {
        switch self {
        case .daisy: return "Daisy"; case .tulip: return "Tulip"; case .rose: return "Rose"; case .strawberry: return "Strawberry"; case .blueberry: return "Blueberry"
        }
    }
    var seedID: String { "seed-\(rawValue)" }
    var isFruit: Bool { self == .strawberry || self == .blueberry }
    /// Watered seconds from sprout to ripe.
    var growSeconds: Double {
        switch self {
        case .daisy: return 2 * 3600; case .tulip: return 3 * 3600; case .rose: return 4 * 3600; case .strawberry: return 4 * 3600; case .blueberry: return 5 * 3600
        }
    }
    var seedPrice: Int {
        switch self {
        case .daisy: return 6; case .tulip: return 8; case .rose: return 12; case .strawberry: return 10; case .blueberry: return 10
        }
    }
    var symbol: String { isFruit ? "leaf.circle.fill" : "camera.macro" }
    /// The Consumable the harvest feeds (fruit only).
    var harvestFood: String? { self == .strawberry ? "strawberry" : self == .blueberry ? "gardenberries" : nil }
    var blurb: String {
        switch self {
        case .daisy: return "Cheerful white daisies. Ready in 2 hours of watering."
        case .tulip: return "Bright tulips. Ready in 3 hours of watering."
        case .rose: return "Soft pink roses. Ready in 4 hours of watering."
        case .strawberry: return "Sweet strawberries to feed. Ready in 4 hours of watering."
        case .blueberry: return "Juicy blueberries to feed. Ready in 5 hours of watering."
        }
    }
}

nonisolated enum GardenTuning {
    static let plotCount = 4
    /// One watering keeps the soil wet this long; waterings bank up to `maxWetAhead` from now.
    static let waterSeconds: Double = 2 * 3600
    static let maxWetAhead: Double = 4 * 3600
    /// Share of the growth spent as a sprout (then bud until ripe).
    static let sproutShare = 0.34
    /// Servings of fruit one harvest puts in the bag.
    static let servings = 3
    /// How long a smelled bouquet keeps the Jelbies cozy.
    static let cozySeconds: TimeInterval = 3600
    static let seedPrices: [GardenPlant: Int] = Dictionary(uniqueKeysWithValues: GardenPlant.allCases.map { ($0, $0.seedPrice) })
}

@MainActor
@Observable
final class GardenBook {
    struct Plot: Codable, Equatable, Sendable {
        var plant: GardenPlant?
        var progress: Double = 0
        var wetUntil: Double = 0
    }
    struct Saved: Codable { var plots: [Plot]; var lastTick: Double }
    static let key = "Garden.v1"

    private(set) var plots: [Plot]
    /// Bumps whenever something the garden draws changes (planted, stage, wet, harvested).
    private(set) var revision = 0
    /// The plot whose seed picker is open.
    var pickerPlot: Int?
    /// A short line for the player ("Watered!", "Picked 3 strawberries").
    var note: String?
    @ObservationIgnored var noteUntil: Double = 0
    /// The watering can pours over this plot until `canUntil` (renderer reads it).
    @ObservationIgnored private(set) var canPlot: Int?
    @ObservationIgnored private(set) var canStart: Double = 0
    @ObservationIgnored private var lastTick: Double
    @ObservationIgnored private var shown: [Int]
    @ObservationIgnored private let persists: Bool
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var dirty = false
    /// Bookkeeping of the care layer (GameCare+Garden.swift): what the renderer last drew, the 1 s clock, the Jelbies' garden visits.
    @ObservationIgnored var drawnRevision = -1
    @ObservationIgnored var drawnShown = false
    @ObservationIgnored var clock: Float = 0
    @ObservationIgnored var life = GardenLifeState()

    nonisolated deinit {}

    init(persists: Bool = true, defaults: UserDefaults = .standard, now: Double = Date().timeIntervalSince1970) {
        self.persists = persists; self.defaults = defaults
        var p = [Plot](repeating: Plot(), count: GardenTuning.plotCount), t = now
        if persists, let d = defaults.data(forKey: Self.key), let s = try? JSONDecoder().decode(Saved.self, from: d) {
            for (i, q) in s.plots.prefix(GardenTuning.plotCount).enumerated() { p[i] = q }
            t = s.lastTick
        }
        plots = p; lastTick = t
        shown = []
        shown = (0..<GardenTuning.plotCount).map { signature($0, now: t) }
    }

    // MARK: queries

    /// 0 empty, 1 sprout, 2 bud (green fruit), 3 ripe.
    func stage(_ i: Int) -> Int {
        guard plots.indices.contains(i), let k = plots[i].plant else { return 0 }
        let f = plots[i].progress / k.growSeconds
        return f >= 1 ? 3 : f >= GardenTuning.sproutShare ? 2 : 1
    }
    func isWet(_ i: Int, now: Double) -> Bool { plots.indices.contains(i) && plots[i].wetUntil > now }
    /// 0...1 growth of a planted plot.
    func fraction(_ i: Int) -> Double {
        guard plots.indices.contains(i), let k = plots[i].plant else { return 0 }
        return min(1, plots[i].progress / k.growSeconds)
    }
    var plantedCount: Int { plots.filter { $0.plant != nil }.count }
    func firstEmpty() -> Int? { plots.firstIndex { $0.plant == nil } }
    private func signature(_ i: Int, now: Double) -> Int {
        let k = plots[i].plant.map { GardenPlant.allCases.firstIndex(of: $0)! + 1 } ?? 0
        return k * 100 + stage(i) * 10 + (isWet(i, now: now) ? 1 : 0)
    }

    // MARK: actions

    func plant(_ k: GardenPlant, at i: Int, now: Double) {
        guard plots.indices.contains(i), plots[i].plant == nil else { return }
        plots[i] = Plot(plant: k, progress: 0, wetUntil: 0)
        changed(now: now)
    }
    /// Waters a plot; false when there is nothing planted or the soil is already as wet as it can be banked.
    @discardableResult
    func water(_ i: Int, now: Double) -> Bool {
        guard plots.indices.contains(i), plots[i].plant != nil, stage(i) < 3 else { return false }
        let base = max(plots[i].wetUntil, now)
        guard base - now < GardenTuning.maxWetAhead - 60 else { return false }
        plots[i].wetUntil = min(base + GardenTuning.waterSeconds, now + GardenTuning.maxWetAhead)
        canPlot = i; canStart = now
        changed(now: now)
        return true
    }
    /// Takes the ripe plant; nil when it is not ripe.
    func harvest(_ i: Int, now: Double) -> GardenPlant? {
        guard stage(i) == 3, let k = plots[i].plant else { return nil }
        plots[i] = Plot()
        changed(now: now)
        return k
    }

    /// Advances growth to `now` (time away included).
    func tick(now: Double) {
        if now < lastTick { lastTick = now; return }
        let from = lastTick
        guard now - from > 0.5 else { return }
        lastTick = now
        for i in plots.indices {
            guard let k = plots[i].plant, plots[i].progress < k.growSeconds else { continue }
            let wet = max(0, min(now, plots[i].wetUntil) - from)
            if wet > 0 { plots[i].progress = min(k.growSeconds, plots[i].progress + wet); dirty = true }
        }
        let sig = (0..<plots.count).map { signature($0, now: now) }
        if sig != shown { changed(now: now) }
        else if dirty, Int(now) % 30 == 0 { save() }
        if note != nil, now > noteUntil { note = nil }
    }
    func say(_ s: String, now: Double, for secs: Double = 2.8) { note = s; noteUntil = now + secs }
    func canActive(now: Double) -> (plot: Int, t: Float)? {
        guard let p = canPlot else { return nil }
        let t = Float(now - canStart)
        return t < 2.2 ? (p, t) : nil
    }

    private func changed(now: Double) {
        shown = (0..<plots.count).map { signature($0, now: now) }
        revision &+= 1
        save()
    }
    private func save() {
        dirty = false
        guard persists, let d = try? JSONEncoder().encode(Saved(plots: plots, lastTick: lastTick)) else { return }
        defaults.set(d, forKey: Self.key)
    }
    /// Capture / test aid: puts a plant at a stage.
    func debugSet(_ i: Int, _ k: GardenPlant, fraction f: Double, wet: Bool, now: Double) {
        guard plots.indices.contains(i) else { return }
        plots[i] = Plot(plant: k, progress: k.growSeconds * f, wetUntil: wet ? now + 3600 : 0)
        changed(now: now)
    }
}
