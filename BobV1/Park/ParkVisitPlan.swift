//
//  ParkVisitPlan.swift
//  Which of the park's two big toys the Jelbies use ON THEIR OWN during one park visit: one of them per visit, alternating (the seesaw on one visit, the hopscotch court on the next,
//  decided from the persisted visit counter so it survives a relaunch), so the lawn never has both in play beside the slide (2026-11-11, "seems cluttered").
//  Only the Jelbies' and visitors' own picks are gated (`BlobBrain.decorStart`, the `wanted` filter): a use the player asks for (`commanded`) always works, and the slide
//  and the player's own toys are never gated. Under XCTest (and with the capture argument `-ParkToys`) everything is in play and nothing is written.
//

import Foundation

nonisolated enum ParkVisitPlan {
    /// What is in play during one visit.
    struct Plan: Equatable, Sendable {
        var visit = 0
        var seesaw = true
        var hopscotch = true
        static let all = Plan()
    }

    /// The one saved key: `["visit": n, "seesawOff": streak, "hopscotchOff": streak]`.
    static let key = "park.visitPlan.v1"

    /// The plan of the visit that is on now (everything in play until `begin` has run, and always at home / in tests).
    nonisolated(unsafe) static var current = Plan.all

    /// A test run or the `-ParkToys` capture aid: every toy is in play and the standard defaults are left alone.
    static var allInPlayAlways: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil || UserDefaults.standard.string(forKey: "ParkToys") != nil
    }

    // MARK: the draw (pure)

    /// Visit number `visit` (1, 2, 3 ...): the seesaw on the even visits, the hopscotch court on the odd ones; never both, never neither. The off-streaks are ignored (the saved dictionary keeps its shape).
    static func draw(visit: Int, seesawOff: Int = 0, hopscotchOff: Int = 0) -> (seesaw: Bool, hopscotch: Bool) {
        return (true, true)          // user 2026-11-12: the hopscotch (and the seesaw) stay at every visit; the de-clutter is the pond, not a toy
    }

    // MARK: a visit starts

    /// Starts a visit: advances the saved counter, draws (alternating), saves the streaks, makes it the current plan. (Tests and `-ParkToys`: everything in play, nothing written.)
    @discardableResult
    static func begin(defaults: UserDefaults = .standard) -> Plan {
        if defaults === UserDefaults.standard, allInPlayAlways { current = .all; return current }
        let saved = defaults.dictionary(forKey: key) ?? [:]
        var visit = max(0, saved["visit"] as? Int ?? 0) + 1
        #if targetEnvironment(simulator)
        if defaults === UserDefaults.standard, UserDefaults.standard.object(forKey: "ParkVisit") != nil { visit = max(1, UserDefaults.standard.integer(forKey: "ParkVisit")) }          // capture aid: `-ParkVisit n` is visit number n (odd: hopscotch, even: seesaw); each capture run starts on a fresh simulator clone, whose counter would always be 1
        #endif
        let seesawOff = max(0, saved["seesawOff"] as? Int ?? 0), hopscotchOff = max(0, saved["hopscotchOff"] as? Int ?? 0)
        let d = draw(visit: visit)
        defaults.set(["visit": visit, "seesawOff": d.seesaw ? 0 : seesawOff + 1, "hopscotchOff": d.hopscotch ? 0 : hopscotchOff + 1], forKey: key)
        current = Plan(visit: visit, seesaw: d.seesaw, hopscotch: d.hopscotch)
        return current
    }

    /// Is a piece of this kind DRAWN and placed in the park on this visit? The seesaw only on the seesaw visits, the hopscotch court only on the hopscotch visits (the plan that lets the
    /// Jelbies use a piece is the plan that shows it); every other piece is always there. `current` is `.all` until a visit has begun, in tests and with `-ParkToys`, so those show both.
    static func shows(_ kind: DecorKind) -> Bool {
        switch kind {
        case .seesaw: return current.seesaw
        case .hopscotch: return current.hopscotch
        default: return true
        }
    }

    /// The park's own pieces for this visit (`ParkToys.placed` without the big toy that is not in today's plan).
    static var placedToday: [PlacedDecor] { ParkToys.placed.filter { shows($0.kind) } }

    /// The pure decision: may a Jelbie of its own accord use a piece of this kind? Always at home (`outing` false); in the park the seesaw and the hopscotch follow the plan, or are
    /// open while the piece is already in use (only a use the player asked for can have started it, so a friend may join it); every other piece is open.
    static func allows(_ kind: DecorKind, outing: Bool, inUse: Bool) -> Bool {
        guard outing else { return true }
        switch kind {
        case .seesaw: return current.seesaw || inUse
        case .hopscotch: return current.hopscotch || inUse
        default: return true
        }
    }

    /// The same, reading whether the piece is in use now from the shared state (the hopscotch line, the seesaw's seats). Main actor: `DecorField` and `HopscotchLine` live there, and
    /// its only caller is `BlobBrain.decorStart`.
    @MainActor
    static func allows(_ kind: DecorKind, outing: Bool) -> Bool {
        guard outing else { return true }
        let inUse: Bool
        switch kind {
        case .hopscotch: inUse = HopscotchLine.shared.active
        case .seesaw: inUse = DecorField.shared.feet.contains { $0.kind == .seesaw && (DecorField.shared.occupant[$0.uid] != nil || !(DecorField.shared.seatOccupant[$0.uid]?.isEmpty ?? true)) }
        default: inUse = false
        }
        return allows(kind, outing: outing, inUse: inUse)
    }
}
