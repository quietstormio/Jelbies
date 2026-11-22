//
//  GameCare+Bond.swift
//  The ONE funnel every relationship event goes through (the rules and numbers are Jelly/JellyBond.swift). It maps a slot (or a character) to the creature's character id,
//  leaves out previews, and writes the points. Nothing here is shown or announced: the Profile alone reads the result.
//

import Foundation

extension GameCare {
    /// One event for the Jelmiko in `slot`. Previews, preview ids and anybody who is not one of the player's own (Park visitors, guests) earn nothing.
    func bondEarn(_ kind: BondKind, slot: Int, favourite: Bool = false, win: Bool = false) {
        guard !isPreview, let j = jelly(slot) else { return }
        bondEarn(kind, character: j.character, favourite: favourite, win: win)
    }

    func bondEarn(_ kind: BondKind, character c: Int, favourite: Bool = false, win: Bool = false) {
        guard !isPreview, !JellyRoster.isPreview(c), jellies.contains(where: { $0.character == c }) else { return }
        let add = JellyBond.earn(kind, c, favourite: favourite, win: win)
        if DevArgs.enabled { NSLog("[bond] character %d %@ +%d -> %d points", c, kind.rawValue, add, JellyBond.points(c)) }
    }

    /// Every Jelmiko at home, once per kind-cap (the first open of a day).
    func bondDayOpen() { for j in jellies { bondEarn(.dayOpen, slot: j.id) } }

    /// A meal or a drink was eaten by `slot`: once per serving per diner (the first piece), more for his favourite food.
    func bondAte(slot: Int, _ c: Consumable) {
        guard bondFed.insert(slot).inserted else { return }
        let fav = jelly(slot)?.traits?.snack == c.id
        bondEarn(c.kind == .drink ? .drink : .meal, slot: slot, favourite: fav)
    }

    /// Stroking that gives hearts: `seconds` of it for `slot` (a refused, annoyed stroke is never passed in). Every `strokeSeconds` is one event.
    func bondTouch(slot: Int, seconds: Float) {
        let t = bondPetSeconds[slot, default: 0] + seconds
        if t >= BondTuning.strokeSeconds { bondPetSeconds[slot] = 0; bondEarn(.stroke, slot: slot) } else { bondPetSeconds[slot] = t }
    }

    /// A voice trick or a "come here" obeyed, for these slots.
    func bondObeyed(_ slots: [Int]) { for s in Set(slots) { bondEarn(.trick, slot: s) } }
}
