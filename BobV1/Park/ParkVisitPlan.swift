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
        let even = visit % 2 == 0
        return (even, !even)
    }

    // MARK: a visit starts

    /// Starts a visit: advances the saved counter, draws (alternating), saves the streaks, makes it the current plan. (Tests and `-ParkToys`: everything in play, nothing written.)
    @discardableResult
    static func begin(defaults: UserDefaults = .standard) -> Plan {
        if defaults === UserDefaults.standard, allInPlayAlways { current = .all; return current }
        let saved = defaults.dictionary(forKey: key) ?? [:]
        let visit = max(0, saved["visit"] as? Int ?? 0) + 1
        let seesawOff = max(0, saved["seesawOff"] as? Int ?? 0), hopscotchOff = max(0, saved["hopscotchOff"] as? Int ?? 0)
        let d = draw(visit: visit)
        defaults.set(["visit": visit, "seesawOff": d.seesaw ? 0 : seesawOff + 1, "hopscotchOff": d.hopscotch ? 0 : hopscotchOff + 1], forKey: key)
        current = Plan(visit: visit, seesaw: d.seesaw, hopscotch: d.hopscotch)
        return current
    }

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
