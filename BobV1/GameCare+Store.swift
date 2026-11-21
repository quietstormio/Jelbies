//
//  GameCare+Store.swift
//  The store's effects on the room: a store food fed from the bag (one serving is used up when the first piece is eaten, so a Jelly who refuses
//  loses nothing), what eating does for him (his perk, his condition stats, sugar-rush zoomies), the perk flags on every brain, and the soaps used
//  with Clean. Drops come ONLY from competitions (races); nothing here earns or buys with real money.
//

import Foundation
import simd
import QuartzCore

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
        if !servingCharged, let id = c.storeID {
            servingCharged = true; store.use(id)
        }
        // his picked favourite snack (JellyTraits): once per serving, on HIS first bite (not the serving's first bite: at a group meal each diner who loves it
        // gets his own): a heart over his head, a burst of floating hearts and an excited face, and love (attention) goes up (FavouriteFood.loveGain)
        if !isPreview, prof.traits?.snack == c.id, favouriteCheered.insert(jelly).inserted { favouriteCheer(jelly) }
        let share = Float(pieces) / Float(DiningTiming.bitesPerServing)
        if !c.condition.isEmpty { prof.stats.nudge(c.condition.mapValues { $0 * share }, food: c.name) }
        if let perk = c.perk {
            let fresh = !prof.perks.isActive(perk)
            // his favourite food (the snack on his card): its power-up lasts twice as long; no serving cuts a longer time short (Store/FavouriteFood.swift)
            prof.perks.grant(perk, duration: FavouriteFood.grantSeconds(perk, favourite: !isPreview && prof.traits?.snack == c.id, left: prof.perks.remaining(perk)))
            if fresh { AudioHub.shared.play(.perkSparkle, volume: 0.9) }
            if perk == .zoomies { zoomiesDue.insert(jelly) }
        }
    }

    /// The favourite-food moment for Jelly `id`: a step of love now, the hearts (and the excited face) once he has straightened up from the first lean,
    /// all over his standing place (`FavouriteFood.heartWorld`), never over his leaning body: at the ends of the table that hangs over the middle diner.
    func favouriteCheer(_ id: Int) {
        let before = needs(for: id).level(.attention)
        needs(for: id).gain(.attention, FavouriteFood.loveGain)
        if DevArgs.enabled { NSLog("[favlove] jelly %d love %.3f -> %.3f", id, before, needs(for: id).level(.attention)) }
        let b = brainFor(id)
        let stand = b.map { $0.activity == .eating || $0.activity == .drinking ? $0.dine.place.stand : $0.position }
        let c = stand.map { FavouriteFood.standCentroid($0) } ?? (id == 0 ? headWorld : bubbleHub.heads[id] ?? headWorld) - SIMD3(0, BlobShape.H * 0.5, 0)
        favouriteWaiting[id] = (c, b == nil ? 0 : FavouriteFood.straightenWaitMax)
        tickFavouriteHearts(dt: 0)
    }
    private func favouriteHeart(_ id: Int, _ c: SIMD3<Float>) {
        bubbleHub.spawnHeart(for: id, now: CACurrentMediaTime(), fixed: c)
    }
    private func leaning(_ id: Int) -> Bool {
        guard let b = brainFor(id), b.activity == .eating || b.activity == .drinking else { return false }
        return b.dine.phase == .lean || b.dine.phase == .grab
    }
    /// Once per step: a waiting cheer starts when he is upright (or after the longest wait); then the later hearts of the burst, `heartGap` apart.
    func tickFavouriteHearts(dt: Float) {
        guard !favouriteWaiting.isEmpty || !favouriteHearts.isEmpty else { return }
        for (id, var w) in favouriteWaiting {
            w.wait -= dt
            if w.wait > 0, leaning(id) { favouriteWaiting[id] = w; continue }
            favouriteWaiting[id] = nil
            favouriteHeart(id, w.c)
            favouriteHearts[id] = (FavouriteFood.extraHearts, FavouriteFood.heartGap, w.c)
            brainFor(id)?.face(.excited, hold: 1.4)
        }
        for (id, var g) in favouriteHearts {
            g.t -= dt
            if g.t <= 0 { g.t = FavouriteFood.heartGap; g.left -= 1; favouriteHeart(id, g.c) }
            favouriteHearts[id] = g.left > 0 ? g : nil
        }
    }

    /// Once per fixed step for Jelly `id`: his perks reach his brain, and a sugar rush runs once he has finished eating.
    func syncPerks(id: Int, brain: BlobBrain) {
        // shoes keep the beans out for good (the same rule as `shoeLook`: no shoes drawn on a race rival or on the Jelly in the wash)
        let shod = store.worn(id, .feet) != nil && !(race.active && id != race.playerID && raceBook.onTrack.contains(id)) && !(showBook.roomAway && id != show.playerID) && !(bath.active && bath.targetID == id)
        if brain.shoesWorn != shod { brain.shoesWorn = shod }
        guard let p = jelly(id)?.perks else { return }
        let c = p.cache
        let f = PerkFlags(bouncy: c.any && p.isActive(.bouncy), social: c.any && p.isActive(.social), bedtime: c.any && p.isActive(.bedtime))
        if brain.perkFlags != f { brain.perkFlags = f }
        if zoomiesDue.contains(id), !tripActive, !(id == mealJelly && (meal != nil || wanted != nil)), !groupHolds(id), !brain.reserved, brain.activity != .eating, brain.activity != .drinking,
           !brain.commanded, brain.commandedIdle == nil, !brain.isSleeping, !bath.active {
            zoomiesDue.remove(id)
            brain.commandedIdle = .zoomies
        }
    }

    /// Is Jelly `id` still tied up in a group meal (a diner not yet released, a waiter for the next sitting, or the sitting about to form)? A diner who is
    /// done is released on his own, so his sugar rush does not wait for the others.
    func groupHolds(_ id: Int) -> Bool { groupWanted != nil || groupQueue.contains(id) || group.isHolding(id) }

    // MARK: supplies (soaps and sprays used with Clean)

    /// Arms the supply for the next Clean of `jelly` and starts it (a soap skips the pick card: it is the pick). Nothing is used up unless the clean-up finishes.
    @discardableResult
    func useSupply(_ itemID: String, on jelly: Int) -> Bool {
        guard let item = StoreCatalog.item(itemID), item.kind == .supply, store.count(itemID) > 0, canClean(jelly: jelly) else { return false }
        var ids = armedSupplies[jelly] ?? []
        if Soap.of(storeID: itemID) != nil { ids.removeAll { Soap.of(storeID: $0) != nil } }          // one soap per bath
        if !ids.contains(itemID) { ids.append(itemID) }
        armedSupplies[jelly] = ids
        clean(jelly: jelly)
        return true
    }

    // MARK: the soap pick (before a bath)

    /// The bought soaps the player has at least one bar of, in the soaps' order.
    var ownedSoaps: [Soap] { Soap.allCases.filter { s in s.storeID.map { store.count($0) > 0 } ?? false } }
    /// Any bought soap in the Bag (a cheap check: no soap art or model is touched until the card shows).
    var hasBoughtSoap: Bool { Soap.boughtIDs.contains { store.count($0) > 0 } }
    /// The tiles of the pick card: the free Jelly soap first, then the owned soaps (up to six).
    var soapChoices: [Soap] { [.jelly] + ownedSoaps }
    /// Bars of `soap` in the Bag (the free Jelly soap: nil).
    func soapCount(_ soap: Soap) -> Int? { soap.storeID.map { store.count($0) } }
    static let lastSoapKey = "BathLastSoap"
    /// The soap used last time, if it is still owned (else the Jelly soap): ringed on the card.
    var preselectedSoap: Soap {
        guard let id = UserDefaults.standard.string(forKey: Self.lastSoapKey), let s = Soap.of(storeID: id), ownedSoaps.contains(s) else { return .jelly }
        return s
    }
    /// A tile of the pick card was tapped: the bath starts with that soap (the Jelly soap is free and uses nothing).
    func chooseSoap(_ soap: Soap) {
        guard let who = soapPrompt else { return }
        if let sid = soap.storeID, store.count(sid) == 0 { return }
        soapPrompt = nil
        var ids = (armedSupplies[who] ?? []).filter { Soap.of(storeID: $0) == nil }
        if let sid = soap.storeID { ids.append(sid) }
        armedSupplies[who] = ids
        AudioHub.shared.uiTap()
        clean(jelly: who)
        if !bath.active { armedSupplies[who] = (armedSupplies[who] ?? []).filter { Soap.of(storeID: $0) == nil } }          // the bath could not start (the moment was gone): the pick does not stay armed, so the next Clean shows the card again
    }
    /// The card closes by itself when the moment is gone (a meal, a call, sleep, a trip, another bath).
    func soapCardTick() {
        guard let who = soapPrompt else { return }
        let asleep = brainFor(who)?.isSleeping ?? false
        if !canClean(jelly: who) || asleep || callRunning || meal != nil || wanted != nil || groupActive || bath.active || !hasBoughtSoap { soapPrompt = nil }
    }
    func dismissSoapCard() { soapPrompt = nil }

    /// The clean-up finished: the armed supplies for that Jelly are used up and give their perks (a soap: its power-up and, for Berry, a little love; the Spray: Tidy).
    func soapFinished() {
        let id = bath.targetID
        UserDefaults.standard.set(bath.soap.storeID ?? "", forKey: Self.lastSoapKey)
        guard let list = armedSupplies[id], let prof = jelly(id) else { armedSupplies[id] = nil; return }
        armedSupplies[id] = nil
        for sid in list {
            guard let item = StoreCatalog.item(sid), store.use(sid) else { continue }
            if let soap = Soap.of(storeID: sid) {
                for p in soap.grants { prof.perks.grant(p) }
                if soap.love > 0 { needs(for: id).gain(.attention, soap.love) }
            } else if let perk = item.perk { prof.perks.grant(perk) }
        }
    }

    // MARK: the room's numbers (UI)

    /// The perks of every Jelly in the room, for the badge and the bag: (Jelly id, name, perks with the time left).
    var perkRows: [(id: Int, name: String, perks: [(kind: PerkKind, left: TimeInterval)])] {
        jellies.map { j in (j.id, j.name, j.perks.active.map { ($0, j.perks.remaining($0)) }) }
    }
    var anyPerkActive: Bool { jellies.contains { !$0.perks.active.isEmpty } }
}
