//
//  Tutorial.swift
//  The tutorial engine's model (no views): the step list, what each step waits for, progress that survives a kill, Skip, and the first-hungry reminder.
//  The overlay is TutorialOverlay.swift (its own top window); the card is CoachCard.swift. A step waits for the REAL action: `tick(world:)` reads a plain `TutorialWorld`
//  snapshot (what is open, what is on screen) and moves on when the step's wait is true. The game's own code is never changed by the tutorial: it only looks.
//  Phase A content: the intro, Cuddle, the care heart, Go out; plus the first-hungry reminder (heart > Feed > food). Later phases add their chapters to `homeSteps`.
//

import Foundation
import Observation
import SwiftUI

/// What the game looks like right now, as far as the tutorial cares. Plain values so tests can build one.
struct TutorialWorld: Equatable {
    var menuOpen = false          // the care menu (heart) is open
    var townOpen = false          // the Go out screens
    var focusActive = false       // the cuddle close-up
    var hearts = false            // hearts are floating (a rub works)
    var hungry = false            // the Jelmiko wants food (the food bubble is due)
    var trayOut = false           // a meal is on
    var busy = false              // something else owns the game: a race, a show, a trip, a cut-scene, Settings...
    var targets: Set<String> = []          // controls on screen that registered a frame
}

enum TutorialWait: Equatable {
    case button               // a button on the card
    case arrival              // the run-in is over
    case menuOpen, menuClosed, townOpen, focusOpen, focusClosed, hearts, trayOut
    case target(String)
    case anyTarget([String])
}

struct TutorialStep: Equatable {
    enum Kind: Equatable { case arrival, intro, spot, card }
    enum Place: Equatable { case top, low }
    /// What a missing control does after a few seconds: move on, or go back to the step that shows it.
    enum Missing: Equatable { case advance, back(String) }
    let id: String
    let chapter: Int
    var kind: Kind
    var title: String? = nil
    var text: String? = nil
    var button: String? = nil
    var target: String? = nil
    var shape: CoachShape = .capsule
    var place: Place = .top
    var wait: TutorialWait
    var missing: Missing = .advance
    /// "Tap {name}." and friends: {name} is the Jelmiko's name.
    func line(_ name: String) -> String? { text?.replacingOccurrences(of: "{name}", with: name) }
    func head(_ name: String) -> String? { title?.replacingOccurrences(of: "{name}", with: name) }
}

@MainActor @Observable
final class Tutorial {
    static let shared = Tutorial()

    nonisolated static let stateKey = "Jelbies.tutorial.state.v1"          // "progress" | "done" | "skipped"
    nonisolated static let chapterKey = "Jelbies.tutorial.chapter.v1"      // the furthest chapter reached (resume goes to its start)
    nonisolated static let hungryKey = "Jelbies.tutorial.hungry.v1"        // the first-hungry reminder was shown
    nonisolated static var allKeys: [String] { [stateKey, chapterKey, hungryKey] }

    /// The chapters shown as dots (Phase A: Cuddle, Care, Go out).
    static let chapterTitles = ["Cuddle", "Care", "Go out"]
    static var chapterCount: Int { chapterTitles.count }

    // MARK: the content

    /// The home walkthrough. Chapter 0 is the intro; chapters 1... are the dots.
    static let homeSteps: [TutorialStep] = [
        TutorialStep(id: "arrive", chapter: 0, kind: .arrival, wait: .arrival),
        TutorialStep(id: "intro", chapter: 0, kind: .intro, title: "This is your Jelmiko, {name}.", text: "To take care of them, you can:", button: "Show me how", target: "jelmiko", wait: .button),
        // 1 Cuddle
        TutorialStep(id: "cuddle.tap", chapter: 1, kind: .spot, text: "Tap {name}.", target: "jelmiko", wait: .target("come")),
        TutorialStep(id: "cuddle.come", chapter: 1, kind: .spot, text: "Tap Come here.", target: "come", wait: .focusOpen, missing: .back("cuddle.tap")),
        TutorialStep(id: "cuddle.rub", chapter: 1, kind: .card, text: "Rub {name}'s head.", place: .low, wait: .hearts),
        TutorialStep(id: "cuddle.release", chapter: 1, kind: .spot, text: "Tap Let {name} go.", target: "release", wait: .focusClosed),
        // 2 Care menu
        TutorialStep(id: "care.heart", chapter: 2, kind: .spot, text: "Tap the heart.", target: "care", wait: .menuOpen),
        TutorialStep(id: "care.menu", chapter: 2, kind: .spot, text: "Feed, water and play are here. Tap the heart to close.", target: "care", wait: .menuClosed),
        // 3 Go out
        TutorialStep(id: "out.go", chapter: 3, kind: .spot, text: "Tap Go out.", target: "goout", wait: .townOpen),
        TutorialStep(id: "out.town", chapter: 3, kind: .card, title: "Shop, races, the park and more.", text: "Each one shows you how the first time.", button: "Got it", place: .top, wait: .button),
    ]

    /// The first-hungry reminder: heart, Feed, then the food (or, with an empty bag, the way to the Shop).
    static let hungrySteps: [TutorialStep] = [
        TutorialStep(id: "hungry.heart", chapter: 1, kind: .spot, text: "{name} is hungry! Tap the heart.", target: "care", wait: .menuOpen),
        TutorialStep(id: "hungry.feed", chapter: 1, kind: .spot, text: "Tap Feed.", target: "feed", wait: .anyTarget(["food", "feed-empty"]), missing: .back("hungry.heart")),
    ]
    static let hungryFood = TutorialStep(id: "hungry.food", chapter: 1, kind: .spot, text: "Tap a food.", target: "food", shape: .rounded(16), wait: .trayOut, missing: .advance)
    static let hungryNoFood = TutorialStep(id: "hungry.nofood", chapter: 1, kind: .spot, text: "No food yet! Tap Go out to visit the Shop.", target: "goout", wait: .townOpen)

    /// Every line a player reads (the text rules apply to all of them).
    static var allLines: [String] {
        (homeSteps + hungrySteps + [hungryFood, hungryNoFood]).flatMap { [$0.title, $0.text, $0.button].compactMap { $0 } } + introRows.map(\.text)
    }

    static let introRows: [CoachRow] = [
        CoachRow(symbol: "fork.knife", color: 0xF29B4B, text: "Feed them yummy food."),
        CoachRow(symbol: "drop.fill", color: 0x4BA8E8, text: "Give them water."),
        CoachRow(symbol: "heart.fill", color: 0xA8405F, text: "Cuddle them. Love makes them happy."),
        CoachRow(symbol: "soccerball", color: 0x5DBB6A, text: "Play with balls and toys."),
        CoachRow(symbol: "moon.zzz.fill", color: 0x8E7CE0, text: "Let them sleep at night."),
        CoachRow(symbol: "coin", color: 0xE8B83A, text: "Earn JellyCoins around town."),
    ]

    // MARK: state

    private(set) var steps: [TutorialStep] = []
    private(set) var index = 0
    private(set) var active = false
    /// The first-hungry reminder is up (it does not freeze the needs).
    private(set) var isHint = false
    var name = ""
    private(set) var replay = false
    /// Bumped on every step (the overlay refocuses VoiceOver on it).
    private(set) var serial = 0
    private(set) var world = TutorialWorld()
    /// Frames the card sits on, set by the overlay (window points); the window's hit test reads it.
    @ObservationIgnored var cardFrame: CGRect = .zero
    @ObservationIgnored var defaults: UserDefaults = .standard
    @ObservationIgnored var now: () -> Date = { Date() }
    @ObservationIgnored private var stepStart = Date.distantPast
    @ObservationIgnored private var missingSince: Date?
    /// Seconds a step stays before the next one may take over (a card never flashes past), and how long a missing control is waited for.
    static let minDwell: TimeInterval = 0.7
    static let missingWait: TimeInterval = 6
    @ObservationIgnored private var loop: Task<Void, Never>?
    @ObservationIgnored var worldProvider: (() -> TutorialWorld)?
    @ObservationIgnored var onChange: (() -> Void)?

    var step: TutorialStep? { active && steps.indices.contains(index) ? steps[index] : nil }
    var holdsGame: Bool { active }
    /// The game's needs and bubbles wait while the home walkthrough runs (not for the hungry reminder).
    var freezesNeeds: Bool { active && !isHint }
    var chapterCount: Int { Self.chapterCount }

    var isDone: Bool { defaults.string(forKey: Self.stateKey) == "done" }
    var wasSkipped: Bool { defaults.string(forKey: Self.stateKey) == "skipped" }
    var inProgress: Bool { defaults.string(forKey: Self.stateKey) == "progress" }
    var furthestChapter: Int { defaults.integer(forKey: Self.chapterKey) }

    // MARK: starting

    /// Index of the first step of a chapter.
    static func chapterStart(_ chapter: Int, in steps: [TutorialStep] = homeSteps) -> Int {
        steps.firstIndex { $0.chapter == chapter && $0.kind != .arrival } ?? 0
    }

    /// A new game's first day (`run`: the Jelmiko runs in first), or a replay (Settings): the whole walkthrough from the intro.
    func begin(name: String, replay: Bool, run: Bool) {
        self.name = name; self.replay = replay
        steps = run ? Self.homeSteps : Self.homeSteps.filter { $0.kind != .arrival }
        isHint = false
        if !replay { defaults.set("progress", forKey: Self.stateKey); defaults.set(0, forKey: Self.chapterKey) }
        go(to: 0)
        active = true
        startLoop()
        sync()
    }

    /// The app was killed mid-tutorial: back to the start of the chapter it had reached. Returns whether it resumed.
    @discardableResult
    func resumeIfNeeded(name: String) -> Bool {
        guard !active, inProgress else { return false }
        self.name = name; replay = false; isHint = false
        steps = Self.homeSteps.filter { $0.kind != .arrival }
        go(to: Self.chapterStart(furthestChapter, in: steps))
        active = true
        startLoop()
        sync()
        return true
    }

    /// The run-in is over.
    func arrivalDone() {
        guard step?.kind == .arrival else { return }
        advance()
    }

    // MARK: moving

    private func go(to i: Int) {
        index = i; serial += 1; stepStart = now(); missingSince = nil
        if let s = step, !replay, !isHint, s.chapter > furthestChapter { defaults.set(s.chapter, forKey: Self.chapterKey) }
    }

    private func advance() {
        if index + 1 < steps.count { go(to: index + 1) } else { finish(completed: true) }
    }

    /// The button on a card.
    func buttonTapped() {
        guard let s = step, s.wait == .button else { return }
        advance()
    }

    func skip() { finish(completed: false) }

    /// Ends it. A finished or skipped home walkthrough is done for good (a replay writes nothing).
    func finish(completed: Bool) {
        guard active else { return }
        let hint = isHint
        active = false; isHint = false; loop?.cancel(); loop = nil; cardFrame = .zero
        if hint { defaults.set(true, forKey: Self.hungryKey) }
        else if !replay {
            defaults.set(completed ? "done" : "skipped", forKey: Self.stateKey)
            defaults.set(true, forKey: FirstDayTour.doneKey)
        }
        sync()
    }

    /// Back to nothing (start over, back to the menu): never leaves the game held.
    func reset() { active = false; isHint = false; steps = []; index = 0; loop?.cancel(); loop = nil; cardFrame = .zero; sync() }

    /// Settings > Replay tutorial: every flag stays; the walkthrough plays again from the intro.
    func replayFromSettings(name: String) { begin(name: name, replay: true, run: false) }

    /// Capture aid (`-TutorialStep <id>`): start on that step.
    func jump(toID id: String) { if let i = steps.firstIndex(where: { $0.id == id }) { go(to: i) } }

    // MARK: waiting

    static func satisfied(_ w: TutorialWait, _ world: TutorialWorld) -> Bool {
        switch w {
        case .button, .arrival: return false
        case .menuOpen: return world.menuOpen
        case .menuClosed: return !world.menuOpen
        case .townOpen: return world.townOpen
        case .focusOpen: return world.focusActive
        case .focusClosed: return !world.focusActive
        case .hearts: return world.hearts
        case .trayOut: return world.trayOut
        case .target(let t): return world.targets.contains(t)
        case .anyTarget(let ts): return ts.contains { world.targets.contains($0) }
        }
    }

    /// Reads the world and moves on when the step's wait is true. One step per call, never before `minDwell`.
    func tick(world w: TutorialWorld) {
        world = w
        guard let s = step else { maybeStartHungry(world: w); return }
        let t = now()
        guard t.timeIntervalSince(stepStart) >= Self.minDwell else { return }
        // a control the step points at that is not on screen: wait a little, then move on (or go back to the step that shows it)
        if let target = s.target, s.kind == .spot, target != "jelmiko", !w.targets.contains(target) {
            if missingSince == nil { missingSince = t }
            if t.timeIntervalSince(missingSince!) >= Self.missingWait {
                switch s.missing {
                case .advance: advance()
                case .back(let id): if let i = steps.firstIndex(where: { $0.id == id }) { go(to: i) }
                }
            }
            return
        }
        missingSince = nil
        if Self.satisfied(s.wait, w) {
            if s.id == "hungry.feed" {          // the bag decides what comes next
                steps.append(w.targets.contains("food") ? Self.hungryFood : Self.hungryNoFood)
            }
            advance()
        }
    }

    // MARK: the first-hungry reminder

    /// Once, the first time the Jelmiko is hungry after the walkthrough was finished (never after Skip: a skipped tutorial is not shown again).
    func maybeStartHungry(world w: TutorialWorld) {
        guard !active, isDone, !defaults.bool(forKey: Self.hungryKey), w.hungry, !w.busy, !w.menuOpen, !w.townOpen, !w.focusActive, !w.trayOut else { return }
        steps = Self.hungrySteps; isHint = true; replay = false
        go(to: 0)
        active = true
        startLoop()
        sync()
    }

    // MARK: plumbing

    private func startLoop() {
        loop?.cancel()
        loop = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 200_000_000)
                guard let self, self.active else { return }
                if let w = self.worldProvider?() { self.tick(world: w) }
            }
        }
    }

    /// The idle watcher: the hungry reminder needs a look at the world even when no step is up.
    func startWatching() {
        guard !active, loop == nil, isDone, !defaults.bool(forKey: Self.hungryKey) else { return }
        loop = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard let self else { return }
                if self.active { return }
                if let w = self.worldProvider?() { self.maybeStartHungry(world: w) }
                if self.active { return }
            }
        }
    }

    private func sync() {
        GameCare.introHold = freezesNeeds || FirstDayTour.shared.armed
        TutorialWindowHost.setVisible(active)
        onChange?()
        if !active, loop == nil { startWatching() }
    }

    /// Wipe / start over: every tutorial flag goes.
    func resetFlags() { for k in Self.allKeys { defaults.removeObject(forKey: k) } }
}
