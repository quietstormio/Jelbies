//
//  FirstDayTour.swift
//  The arrival handshake of a NEW game's first day (the tutorial itself is Tutorial/Tutorial.swift, drawn by Tutorial/TutorialOverlay.swift; the old 9-step captions and coach marks are gone).
//  After the first Jelmiko is brought home the room cross-fades in empty, the Jelmiko RUNS IN from the left edge (the bought-Jelmiko arrival run, GameCare+Newcomer.swift), stops in the middle and hops
//  (the welcome-home hop); then the tutorial begins (intro card, Cuddle, the care heart, Go out). Settings > Watch the opening and Settings > Replay tutorial play it again (nothing is written to the save).
//
//  Holding the game: while the tutorial is armed or up, `GameCare.introHold` is true. Needs stop draining and the need bubbles stay out (GameCare.tickNeeds); the tutorial window only takes touches where the
//  step says so, so a meal can only start from the player's own tap. The meal code is not touched.
//  Reduce Motion: no run-in and no hop, the Jelmiko is simply there; plain fades.
//

import SwiftUI
import Observation

/// Which first-day moment a new game gets. One line switches it back to the old illustrated card.
enum FirstDayStyle {
    case room, card
    static let defaultStyle: FirstDayStyle = .room
    /// `-FirstDayStyle room|card` forces either (developer builds and the simulator only).
    static var current: FirstDayStyle {
        if DevArgs.enabled, let s = UserDefaults.standard.string(forKey: "FirstDayStyle") {
            if s == "card" { return .card }
            if s == "room" { return .room }
        }
        return defaultStyle
    }
}

@MainActor @Observable
final class FirstDayTour {
    static let shared = FirstDayTour()
    nonisolated static let doneKey = "Jelbies.firstDayTour.done.v1"          // set when a new game's tutorial has finished or been skipped (a wipe clears it with the rest)

    /// Armed by StartFlow; the room takes it when it appears (`roomReady`).
    private(set) var armed = false
    private(set) var name = ""
    private(set) var replay = false
    /// What the room's first step still has to do for a brand-new first Jelmiko: run him in, or just put him there (Reduce Motion). Taken once (`takeArrival`).
    enum Arrival { case run, place }
    private var arrival: Arrival?
    private var defaults: UserDefaults = .standard
    private var pendingJump: String?

    /// True from arming until the tutorial ends: the game's needs, bubbles and tip cards wait.
    var holdsGame: Bool { armed || Tutorial.shared.holdsGame }

    /// A new game's first Jelmiko is home (`replay` false), or Settings > Watch the opening (`replay` true). False = nothing armed (a new game's tutorial only ever runs once).
    @discardableResult
    func arm(name: String, replay: Bool, reduceMotion: Bool, defaults d: UserDefaults = .standard) -> Bool {
        if !replay, d.bool(forKey: Self.doneKey) { return false }
        defaults = d
        let run = !replay && !reduceMotion
        self.name = name; self.replay = replay
        armed = true
        arrival = replay ? nil : (run ? .run : .place)
        sync()
        return true
    }

    /// The room is on screen: the tutorial begins (the first step is the run-in when somebody runs in). Otherwise a tutorial the app was killed in resumes, and a finished one starts watching for the first hunger.
    func roomReady(name current: String? = nil) {
        guard armed else {
            let n = current ?? name
            if !n.isEmpty { Tutorial.shared.resumeIfNeeded(name: n); Tutorial.shared.name = n }
            Tutorial.shared.startWatching()
            return
        }
        armed = false
        let t = Tutorial.shared
        t.defaults = defaults
        t.begin(name: name, replay: replay, run: arrival == .run)
        if let j = pendingJump { t.jump(toID: j); pendingJump = nil }
        sync()
    }

    /// GameCare's first step for a brand-new first Jelmiko asks once what to do with him.
    func takeArrival() -> Arrival? { defer { arrival = nil }; return arrival }

    /// The Jelmiko is in the middle of the room and calm: the intro card comes up.
    func arrived() { Tutorial.shared.arrivalDone() }

    func skip() { finish() }
    func finish() { armed = false; arrival = nil; Tutorial.shared.finish(completed: false); sync() }

    /// Back to nothing (start over, back to the menu): never leaves the game held.
    func reset() { armed = false; arrival = nil; Tutorial.shared.reset(); sync() }

    /// Capture aid (`-FirstDayStep <step id>`): start on that step.
    func jump(to id: String) { pendingJump = id; if Tutorial.shared.active { Tutorial.shared.jump(toID: id) } }

    private func sync() { GameCare.introHold = holdsGame && !(Tutorial.shared.active && Tutorial.shared.isHint) }
}
