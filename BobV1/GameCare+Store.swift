//
//  GameCare+Store.swift
//  The store's effects on the room: a store food fed from the bag (one serving is used up when the first piece is eaten, so a Jelly who refuses
//  loses nothing), what eating does for him (his perk, his condition stats, sugar-rush zoomies), the perk flags on every brain, and the soaps used
//  with Clean. Drops come ONLY from competitions (races); nothing here earns or buys with real money.
//

import Foundation
import simd

extension GameCare {
    /// Feeds the snack `itemID` (a store food or treat from the bag) to `jelly` (nil = nobody singled out: a group serving with several Jellies).
    func feedSnack(_ itemID: String, jelly: Int? = nil) {
        guard let item = StoreCatalog.item(itemID), let f = item.food, store.count(itemID) > 0 else { return }
        if item.kind == .drink { drink(f, jelly: jelly) } else { feed(f, jelly: jelly) }          // a drink is sipped, not tossed
    }

    /// A Jelly ate `pieces` more of `c` (single or group meal). Store foods use up one serving from the bag on the first bite of a serving, and
    /// each bite nudges his condition and starts his perk.
    func ate(jelly: Int, _ c: Consumable, pieces: Int) {
        guard pieces > 0, c.stored, let prof = self.jelly(jelly) else { return }
        if !servingCharged, let id = c.storeID { servingCharged = true; store.use(id) }
        let share = Float(pieces) / Float(DiningTiming.bitesPerServing)
        if !c.condition.isEmpty { prof.stats.nudge(c.condition.mapValues { $0 * share }, food: c.name) }
        if let perk = c.perk {
            let fresh = !prof.perks.isActive(perk)
            prof.perks.grant(perk)
            if fresh { AudioHub.shared.play(.perkSparkle, volume: 0.9) }
            if perk == .zoomies { zoomiesDue.insert(jelly) }
        }
    }

    /// Once per fixed step for Jelly `id`: his perks reach his brain, and a sugar rush runs once he has finished eating.
    func syncPerks(id: Int, brain: BlobBrain) {
        // shoes keep the beans out for good (the same rule as `shoeLook`: no shoes drawn on a race rival or on the Jelly in the wash)
        let shod = store.worn(id, .feet) != nil && !(race.active && id != race.playerID) && !(show.active && id != show.playerID) && !(bath.active && bath.targetID == id)
        if brain.shoesWorn != shod { brain.shoesWorn = shod }
        guard let p = jelly(id)?.perks else { return }
        let c = p.cache
        let f = PerkFlags(bouncy: c.any && p.isActive(.bouncy), social: c.any && p.isActive(.social), bedtime: c.any && p.isActive(.bedtime))
        if brain.perkFlags != f { brain.perkFlags = f }
        if zoomiesDue.contains(id), !tripActive, !(id == mealJelly && (meal != nil || wanted != nil)), !(groupActive), !brain.reserved, brain.activity != .eating, brain.activity != .drinking,
           !brain.commanded, brain.commandedIdle == nil, !brain.isSleeping, !bath.active {
            zoomiesDue.remove(id)
            brain.commandedIdle = .zoomies
        }
    }

    // MARK: supplies (soaps and sprays used with Clean)

    /// Arms the supply for the next Clean of `jelly` and starts it. Nothing is used up unless the clean-up finishes.
    @discardableResult
    func useSupply(_ itemID: String, on jelly: Int) -> Bool {
        guard let item = StoreCatalog.item(itemID), item.kind == .supply, store.count(itemID) > 0, canClean(jelly: jelly) else { return false }
        if !(armedSupplies[jelly] ?? []).contains(itemID) { armedSupplies[jelly, default: []].append(itemID) }
        clean(jelly: jelly)
        return true
    }
    /// The clean-up finished: the armed supplies for that Jelly are used up and give their perk.
    func soapFinished() {
        let id = bath.targetID
        guard let list = armedSupplies[id], let prof = jelly(id) else { armedSupplies[id] = nil; return }
        armedSupplies[id] = nil
        for sid in list {
            guard let item = StoreCatalog.item(sid), let perk = item.perk, store.use(sid) else { continue }
            prof.perks.grant(perk)
        }
    }

    // MARK: the room's numbers (UI)

    /// The perks of every Jelly in the room, for the badge and the bag: (Jelly id, name, perks with the time left).
    var perkRows: [(id: Int, name: String, perks: [(kind: PerkKind, left: TimeInterval)])] {
        jellies.map { j in (j.id, j.name, j.perks.active.map { ($0, j.perks.remaining($0)) }) }
    }
    var anyPerkActive: Bool { jellies.contains { !$0.perks.active.isEmpty } }
}
