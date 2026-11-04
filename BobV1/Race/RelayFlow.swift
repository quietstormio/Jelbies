//
//  RelayFlow.swift
//  The relay's settlement (RaceFlow.settle's twin): the team's prize into the wallet and a small training gain for every OWNED runner, like a solo race.
//  No course progress and no ribbons or trophies: those are for solo races (a relay has no single winner to credit).
//

import Foundation

extension RaceFlow {
    /// The relay's results card rows: team name, place, finish time.
    var relayRows: [(place: Int, team: String, time: Float?, isPlayer: Bool)] {
        guard let plan = relayPlan else { return [] }
        return ui.placings.map { p in (p.place, plan.teamNames.indices.contains(p.racer) ? plan.teamNames[p.racer] : p.name, p.time, p.isPlayer) }
    }

    func settleRelay() {
        guard !settled, let s = sim else { return }
        settled = true
        if let place = s.playerPlace {
            earned = assistedDrops(RelayTuning.prize(place: place))
            wallet?.add(earned)
            var first: Float?
            for st in relayStats {
                let g = st.afterRace(place: place)
                if first == nil { first = g }
            }
            waddleGain = first ?? 0
            relayGained = true
            drillCue(.jingle(win: place <= 2))
            if let plan = relayPlan { A11yEvents.say("\(plan.teamNames[0]) finished \(place). \(earned) JellyCoins", .high) }
        }
        cueSerial += 1
        refreshUI()
    }
}
