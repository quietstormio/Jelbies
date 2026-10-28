//
//  GameCare+SeatDemo.swift
//  Capture aid, inert unless launched with `-SeatDemo <decor id>` (e.g. pouf, diningset, sandbox, swing, seesaw): that piece is placed near the centre of the room
//  (when the room lacks it) and ONE Jelbie (`-SeatDemoWho pip|moss|lavender|bob`, default pip) keeps using it through the brain's normal decorSit / hop-sit path.
//

import Foundation
import simd

/// The room is emptied once per launch (a seat demo shows one piece; earlier runs leave their pieces in the saved room). `-SeatDemoKeep 1` keeps the room as it is.
nonisolated(unsafe) private var seatDemoCleared = false

extension GameCare {
    func seatDemoTick() {
        let d = UserDefaults.standard
        guard let id = d.string(forKey: "SeatDemo"), let k = DecorKind(rawValue: id) else { return }
        guard let who = JellyRoster.characterID(named: d.string(forKey: "SeatDemoWho") ?? "pip") else { return }
        if !seatDemoCleared { seatDemoCleared = true; if d.integer(forKey: "SeatDemoKeep") == 0 { store.putAwayAll() } }
        if !store.seatDemoPlace(k, near: SIMD2(0, 0.4)) { return }
        for a in raceBook.actors where a.brain != nil {
            let b = a.brain!
            if JellyRoster.character(a.id) == who { if b.seatDemo != k { b.seatDemo = k; b.idleState.cooldown = 2 } } else { b.seatDemo = nil }
        }
    }
}
