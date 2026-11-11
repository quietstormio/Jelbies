//
//  ParkVisitPlan.swift
//  Which of the park's two big toys the Jelbies use ON THEIR OWN during one park visit: the seesaw and the hopscotch court are each in play on about 62 % of visits
//  ("it doesn't have to be every time, maybe every other time"). Decided once at the start of a visit from a persisted counter (a small hash, not `random`), with two guards:
//  never both off on the same visit, and neither is off more than two visits in a row.
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
    /// Most visits in a row a toy may be off.
    static let maxOffInARow = 2

    /// The plan of the visit that is on now (everything in play until `begin` has run, and always at home / in tests).
    nonisolated(unsafe) static var current = Plan.all

    /// A test run or the `-ParkToys` capture aid: every toy is in play and the standard defaults are left alone.
    static var allInPlayAlways: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil || UserDefaults.standard.string(forKey: "ParkToys") != nil
    }

    // MARK: the draw (pure)

    /// A well-mixed 64-bit value of the visit number (splitmix64): the same visit always draws the same.
    static func mix(_ x: UInt64) -> UInt64 {
        var z = x &+ 0x9E37_79B9_7F4A_7C15
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// Visit number `visit` (1, 2, 3 ...) with the toys' current off-streaks: each toy is in play with 50 %; never both off; a toy that was off `maxOffInARow` visits is on.
    static func draw(visit: Int, seesawOff: Int, hopscotchOff: Int) -> (seesaw: Bool, hopscotch: Bool) {
        let h = mix(UInt64(bitPattern: Int64(visit)))
        var seesaw = h & 1 == 1
        var hopscotch = (h >> 17) & 1 == 1
        if seesawOff >= maxOffInARow { seesaw = true }
        if hopscotchOff >= maxOffInARow { hopscotch = true }
        if !seesaw && !hopscotch {          // (both off: one of them stays, which one by another bit of the same hash)
            if (h >> 33) & 1 == 1 { seesaw = true } else { hopscotch = true }
        }
        return (seesaw, hopscotch)
    }

    // MARK: a visit starts

    /// Starts a visit: advances the saved counter, draws, saves the streaks, makes it the current plan. (Tests and `-ParkToys`: everything in play, nothing written.)
    @discardableResult
    static func begin(defaults: UserDefaults = .standard) -> Plan {
        if defaults === UserDefaults.standard, allInPlayAlways { current = .all; return current }
        let saved = defaults.dictionary(forKey: key) ?? [:]
        let visit = max(0, saved["visit"] as? Int ?? 0) + 1
        let seesawOff = max(0, saved["seesawOff"] as? Int ?? 0), hopscotchOff = max(0, saved["hopscotchOff"] as? Int ?? 0)
        let d = draw(visit: visit, seesawOff: seesawOff, hopscotchOff: hopscotchOff)
        defaults.set(["visit": visit, "seesawOff": d.seesaw ? 0 : seesawOff + 1, "hopscotchOff": d.hopscotch ? 0 : hopscotchOff + 1], forKey: key)
        current = Plan(visit: visit, seesaw: d.seesaw, hopscotch: d.hopscotch)
        return current
    }

    /// May a Jelbie of its own accord use a piece of this kind? Always at home (`outing` false); in the park the seesaw and the hopscotch follow the plan, every other piece is open.
    static func allows(_ kind: DecorKind, outing: Bool) -> Bool {
        guard outing else { return true }
        switch kind {
        case .seesaw: return current.seesaw
        case .hopscotch: return current.hopscotch
        default: return true
        }
    }
}
