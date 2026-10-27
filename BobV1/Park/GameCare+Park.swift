//
//  GameCare+Park.swift
//  The park outing: the glue between the trip (Park/ParkTrip.swift), the park room (RoomCatalog.park, applied under the white fade WITHOUT moving in), the camera
//  (GameCamera.configurePark), the visitors (Park/ParkBook.swift; their bodies are the stage's `parkActors`) and the Jelbies that went.
//
//  Who is there: the Jelbies the player picked (1...3) and 2...4 visitors, never more than five. The other Jelbies stay home (hidden, still). Everybody roams with the
//  usual brains (variety, socials, greetings); the visitors' looks (a signature, a worn item) are ticked here with the same wardrobe and feature sets the Jelbies use.
//  Friendship: points for every second a Jelbie is near a visitor (faster while the two play together). Love: the Love need (the one petting fills) rises at twice the
//  petting rate while a Jelbie plays near a friend, with a daily cap. A best friend may bring a gift, once a day. All saved on the device (ParkBook); no network.
//

import Foundation
import QuartzCore
import simd

/// What GameCare keeps while the park trip is on.
@MainActor
final class ParkWork {
    var homes: [Int: SIMD2<Float>] = [:]
    var autonomy: [Int: Bool] = [:]
    var arena: [Int: Float] = [:]
    var owed: [Int: Float] = [:]
    /// The visit's gift (ParkGifts.swift): 0 none planned, 1 waiting to start, 2 the friend is walking over. Who gives (index in the cast), to whom (roster slot), timers.
    var giftState = 0
    var giftWait: Float = 0, giftT: Float = 0
    var giftGiver = 0, giftSlot = 0
    var giftNicer = false
    var saveT: Float = 0
    /// The friendly social last paid its start bonus, by Jelbie slot (the session's identity).
    var friendSession: [Int: ObjectIdentifier] = [:]
    nonisolated deinit {}
}

extension GameCare {
    func wirePark() {
        park.onSwap = { [weak self] dest in self?.parkSwap(dest) }
    }

    /// The bodies of the Jelbies that did not come along are away while the park is on.
    func parkHides(_ id: Int) -> Bool { (park.inScene && id < jellies.count && !parkBook.comers.contains(id)) || volleyHides(id) || groomHides(id) }

    // MARK: blockers and the request

    /// Why the park cannot be entered now (the friendly line); nil = it can.
    func parkBlocker() -> String? {
        if park.active { return CafeBlock.busy.message }
        guard let b = cafeBlocker(), b != .noDrops else { return nil }
        return b == .night ? "The park is closed at night. Come back in the morning!" : b.message
    }

    #if targetEnvironment(simulator)
    nonisolated(unsafe) static var startParkPending = UserDefaults.standard.integer(forKey: "StartPark") != 0
    nonisolated(unsafe) static var startParkFrames = 0
    #endif

    /// The Town's Park row: blocked = a friendly toast; else the picker (who comes along) opens.
    func requestPark() {
        if let why = parkBlocker() {
            park.say(why)
            AudioHub.shared.play(.notEnough)
            return
        }
        select.cancel(); queued.removeAll(); callRunning = false
        voice.cancel()
        parkBook.warmUp()
        park.openPicker(all: Array(jellies.indices))
    }

    /// The picker's "Go to the park".
    func startPark() {
        guard park.picking, !park.picked.isEmpty else { return }
        select.cancel()
        let who = park.picked
        park.cancelPicker()
        if outingGate(who, again: { [weak self] in self?.park.resume(picked: who) }) { return }
        park.resume(picked: who)
    }

    private var parkFadeBlocked: Bool {
        race.active || show.active || volley.active || raceWait != nil || bath.active || focus.isActive || trayOut || dining.phase != .absent || groupActive || arranging || cafe.active
            || parkBook.roster.contains { $0.brain?.isSleeping == true }
    }

    // MARK: per fixed step

    /// Once per fixed step (the stage calls it with every Jelbie of the room, after the others).
    func tickPark(_ actors: [JellyActor], dt: Float) {
        parkBook.roster = actors
        tickGuest(actors, dt: dt)          // a friend over at home (GameCare+Guest.swift)
        #if targetEnvironment(simulator)
        if Self.startParkPending, park.phase == .off {          // capture aid: `-StartPark 1` goes straight to the park once the room is up
            Self.startParkFrames += 1
            if Self.startParkFrames > 90 { Self.startParkPending = false; requestPark(); startPark() }
        }
        #endif
        if park.active { for a in actors { a.brain?.sleepLocked = true } }
        park.step(dt: dt, blocked: park.phase == .goOut && parkFadeBlocked)
        guard park.active else { return }
        guard park.inScene else { return }
        let book = parkBook, work = book.work
        for (k, a) in actors.enumerated() {
            guard let b = a.brain else { continue }
            if book.comers.contains(k) { b.idleMood = .happy }
            else { b.autonomy = false; b.idleBlocked = true }
        }
        guard park.phase == .playing || park.phase == .arriveIn else { return }
        tickVisitors(dt: dt)
        tickFriends(actors, dt: dt)
        work.saveT += dt
        if work.saveT >= ParkTuning.saveEvery { work.saveT = 0; book.save() }
        if park.phase == .playing, isBedtimeHours { park.say("It is getting late. Time to go home!"); park.goHome() }
    }

    /// The visitors: their mood, their signature and worn item (the same wardrobe / feature sets the Jelbies use, keyed by their body id).
    private func tickVisitors(dt: Float) {
        let book = parkBook
        for (a, vid) in zip(book.actors, book.cast) {
            guard let v = book.visitor(vid) else { continue }
            visitorLook(a, v, dt: dt)
        }
    }

    /// One visitor's looks for this step (the park's visitors, and the guest at home).
    func visitorLook(_ a: JellyActor, _ v: ParkVisitor, dt: Float, sleepLocked: Bool = true) {
        guard let b = a.brain else { return }
        b.idleMood = .happy
        b.sleepLocked = sleepLocked
        b.feature = v.signature
        var outfit: [WearSlot: WearLook] = [:]
        if let w = v.wear { outfit[w.slot] = w }
        wardrobe.tick(id: a.id, brain: b, sim: a.sim, outfit: outfit, role: .none, hideAll: false, dt: dt)
        features.tick(id: a.id, brain: b, sim: a.sim, feature: v.signature, worn: wornArt(a.id), hideAll: false, dt: dt)
        if let s = features.slot(a.id) {
            b.wingsFolded = v.signature == .wings && s.fit.folded
            b.wingFlapLimit = v.signature == .wings ? s.fit.flapMax : 75
            wardrobe.setArtOverride(a.id, s.fit.hatVariant)
        }
    }

    /// A visitor's looks are put away (the wardrobe and feature slots are by body id).
    func visitorPutAway(_ a: JellyActor) {
        guard let b = a.brain else { return }
        wardrobe.tick(id: a.id, brain: b, sim: a.sim, outfit: [:], role: .none, hideAll: true, dt: 1.0 / 60)
        features.tick(id: a.id, brain: b, sim: a.sim, feature: .none, worn: [], hideAll: true, dt: 1.0 / 60)
    }

    /// Friendship and love, from who stands near whom.
    private func tickFriends(_ actors: [JellyActor], dt: Float) {
        let book = parkBook, work = book.work
        for k in book.comers {
            guard actors.indices.contains(k), let prof = jelly(k) else { continue }
            let me = actors[k]
            var nearest: ParkFriendLevel?
            for (a, vid) in zip(book.actors, book.cast) {
                guard simd_distance(me.floor, a.floor) < ParkTuning.nearRadius else { continue }
                var rate = ParkTuning.pointsPerSecond * dt
                let before = book.visitor(vid)?.level(with: prof.character) ?? .stranger
                // how close they are shapes how often they do the friendly socials (BlobSocial+Friends.swift), both ways
                let closeness = FriendTuning.closeMul[before.rawValue]
                me.brain?.socialBook.close[a.id] = closeness; a.brain?.socialBook.close[me.id] = closeness
                if let partner = me.brain?.socialPartnerID, partner == a.id {          // playing together
                    if let s = me.brain?.social, s.kind.isFriendly, s.end == nil {
                        rate *= ParkTuning.friendlyMul
                        if work.friendSession[k] != ObjectIdentifier(s) {          // a new friendly social: a bonus
                            work.friendSession[k] = ObjectIdentifier(s)
                            if let up = book.add(points: ParkTuning.friendlyStartBonus, visitor: vid, character: prof.character) { parkLevelUp(visitor: vid, slot: k, level: up, visitorBody: a) }
                        }
                    } else { rate *= ParkTuning.socialMul }
                }
                nearest = max(nearest ?? before, before)
                if let up = book.add(points: rate, visitor: vid, character: prof.character) { parkLevelUp(visitor: vid, slot: k, level: up, visitorBody: a) }
            }
            // love: twice the petting rate near a friend (less near a stranger), capped per day
            if let lvl = nearest, prof.needs.level(.attention) < 0.999 {
                work.owed[k, default: 0] += dt * ParkTuning.loveMul[lvl.rawValue] * NeedsTuning.petRate
                if work.owed[k, default: 0] >= ParkTuning.loveChunk {
                    let amount = min(work.owed[k, default: 0], book.loveLeft(prof.character))
                    work.owed[k] = 0
                    if amount > 0 { prof.needs.gain(.attention, amount); book.spendLove(amount, character: prof.character) }
                }
            }
        }
        tickGift(actors, dt: dt)
    }

    func parkLevelUp(visitor vid: Int, slot: Int, level: ParkFriendLevel, visitorBody: JellyActor) {
        let book = parkBook
        guard let v = book.visitor(vid), let prof = jelly(slot) else { return }
        let line = book.line(vid, level)
        let kind = level == .best ? "best friends" : level == .friend ? "friends" : "pals"
        park.say("\(prof.name) and \(v.name) are now \(kind)! \"\(line)\"")
        AudioHub.shared.chirp(jelly: slot, .happy)
        AudioHub.shared.chirp(jelly: visitorBody.id, .happy)
        touchPlay?.spawnHeart(now: CACurrentMediaTime())
        for brain in [parkBook.roster[slot].brain, visitorBody.brain] {
            guard let b = brain, b.commandedIdle == nil, b.idleState.kind == nil, case .none = b.script else { continue }
            b.face(.excited, hold: 2)
        }
        if let b = visitorBody.brain, b.commandedIdle == nil, b.idleState.kind == nil, case .none = b.script { b.startHopPlay(sim: visitorBody.sim, distance: 0.0001) }
    }

    /// Plans the visit's gift: due on about every other visit (the rhythm is saved in the ledger), the giver one of the visitors, the receiver one of the Jelbies that came.
    private func parkPlanGift() {
        let book = parkBook, work = book.work
        work.giftState = 0
        var rng = SystemRandomNumberGenerator()
        let was = book.lastVisitGifted
        if was { book.setLastVisitGifted(false); return }          // a gift last time: none this time
        guard !book.actors.isEmpty, !book.comers.isEmpty, ParkGifts.isDue(lastVisitGifted: was, using: &rng) else { return }
        work.giftState = 1; work.giftT = 0
        work.giftWait = Float.random(in: ParkTuning.giftWait)
        work.giftGiver = Int.random(in: 0..<book.actors.count)
        work.giftSlot = book.comers.randomElement() ?? 0
        work.giftNicer = Double.random(in: 0..<1) < ParkGifts.nicerShare
    }

    /// The friend waits a while into the visit, trots over to the Jelbie, then hands the present over.
    private func tickGift(_ actors: [JellyActor], dt: Float) {
        let book = parkBook, work = book.work
        guard work.giftState != 0, park.phase == .playing, book.actors.indices.contains(work.giftGiver), actors.indices.contains(work.giftSlot),
              let gb = book.actors[work.giftGiver].brain, let rb = actors[work.giftSlot].brain else { return }
        work.giftT += dt
        if work.giftState == 1 {
            guard work.giftT >= work.giftWait, gb.scriptIsNone, rb.scriptIsNone else { return }
            let spot = gb.fixed(rb.position + SIMD2<Float>(0.9, 0.5))
            gb.request(.goTo(spot))
            work.giftState = 2; work.giftT = 0
        } else if simd_distance(gb.position, rb.position) < 1.8 || work.giftT > ParkTuning.giftWalkTimeout {
            work.giftState = 0
            parkGift(giverIndex: work.giftGiver, slot: work.giftSlot)
        }
    }

    /// The hand-off: a real store item into the bag (never Drops), a short toast with the present and the item art, a hop and a heart.
    private func parkGift(giverIndex gi: Int, slot: Int) {
        let book = parkBook, work = book.work
        guard book.cast.indices.contains(gi), let v = book.visitor(book.cast[gi]), let prof = jelly(slot) else { return }
        var rng = SystemRandomNumberGenerator()
        guard let item = ParkGifts.pick(owns: { self.store.owns($0) }, count: { self.store.count($0.id) }, nicer: work.giftNicer, using: &rng) else { return }
        store.grant(item.id)
        book.setLastVisitGifted(true)
        AudioHub.shared.play(.perkSparkle, volume: 0.9); AudioHub.shared.play(.sparkle)
        park.showGift(friend: v.name, itemID: item.id)
        A11yAnnounce.say("Gift from \(v.name)! \(item.name). Added to your bag.")
        touchPlay?.spawnHeart(now: CACurrentMediaTime())
        AudioHub.shared.chirp(jelly: slot, .happy)
        if book.actors.indices.contains(gi), let b = book.actors[gi].brain { b.face(.joyArc, hold: 2.5); b.startHopPlay(sim: book.actors[gi].sim, distance: 0.0001) }
        if book.roster.indices.contains(slot), let rb = book.roster[slot].brain {          // the receiver cheers
            rb.face(.joyArc, hold: 2.5)
            if rb.scriptIsNone, rb.idleState.kind == nil { rb.startHopPlay(sim: book.roster[slot].sim, distance: 0.0001) }
        }
    }

    /// A tap in the park: a visitor's card (a body id), or nothing (closes it).
    func parkTapped(_ bodyID: Int?) {
        guard park.phase == .playing else { return }
        let book = parkBook
        guard let id = bodyID, let k = book.actors.firstIndex(where: { $0.id == id }), book.cast.indices.contains(k) else { park.card = nil; return }
        let vid = book.cast[k]
        AudioHub.shared.uiTap()
        park.card = park.card == vid ? nil : vid
        if let b = book.actors[k].brain { b.face(.happy, hold: 1.5) }
    }
    func parkOpenCard(_ vid: Int) { AudioHub.shared.uiTap(); park.card = park.card == vid ? nil : vid }

    // MARK: the world swaps (under the white)

    private func parkSwap(_ dest: ParkTrip.Dest) {
        let book = parkBook, work = book.work
        let roster = book.roster
        switch dest {
        case .park:
            work.homes = [:]; work.autonomy = [:]; work.arena = [:]; work.owed = [:]; work.giftState = 0; work.saveT = 0; work.friendSession = [:]
            book.comers = park.picked.filter { roster.indices.contains($0) && $0 < jellies.count }
            if book.comers.isEmpty { book.comers = Array(roster.indices) }
            for a in roster {
                guard let brain = a.brain else { continue }
                work.homes[a.id] = a.floor; work.autonomy[a.id] = brain.autonomy; work.arena[a.id] = a.sim.arenaRadius
                brain.abortAll(a.sim, a.skinner)
                brain.commandedIdle = nil; brain.commandedDecor = nil; brain.commandedFlip = false
            }
            RoomLayout.apply(RoomCatalog.park)
            GameCamera.configurePark()
            if GameCamera.refreshRoam(aspect: GameCamera.aspect) != nil {
                for a in roster where a.sim.arenaRadius.isFinite { a.sim.arenaCenter = GameCamera.arenaCenter; a.sim.arenaRadius = GameCamera.arenaRadius }
            }
            syncDecor()
            // who is there: the Jelbies that came and 1...4 visitors (a different number each visit), five at most
            let comers = book.comers
            var countRNG = SystemRandomNumberGenerator()
            let n = ParkVisit.visitorCount(playerCount: comers.count, using: &countRNG)
            let characters = comers.compactMap { jelly($0)?.character }
            let cast = book.chooseCast(count: n, characters: characters, now: Date().timeIntervalSince1970)
            let spots = ParkLayout.spots(count: comers.count + cast.count)
            book.cast = cast.map(\.id)
            book.actors = book.spawn?(cast, Array(spots.dropFirst(comers.count))) ?? []
            if book.actors.count != cast.count { book.cast = Array(book.cast.prefix(book.actors.count)) }
            book.markSeen(book.cast, at: Date().timeIntervalSince1970)
            book.warmLines(book.cast)
            parkPlanGift()
            for (k, slot) in comers.enumerated() where roster.indices.contains(slot) {
                let a = roster[slot]
                rehome(a, at: spots[k])
                guard let brain = a.brain else { continue }
                brain.autonomy = UserDefaults.standard.integer(forKey: "BlobNoWander") == 0; brain.idleBlocked = false; brain.restTimer = 1.2
                brain.startTurn(to: 0, sim: a.sim)
                brain.face(.excited, hold: 1.5)
            }
            for a in book.actors { a.brain?.face(.excited, hold: 1.5) }
            if select.phase != .none { select.cancel() }
            park.card = nil
        case .home:
            // the visitors go: their looks are put away first (the wardrobe and feature slots are by body id), the Jelbies let go of any play with them
            for a in book.actors { visitorPutAway(a) }
            for a in roster { a.brain?.abortAll(a.sim, a.skinner); a.brain?.commandedIdle = nil }
            book.clear?()
            book.actors = []; book.cast = []
            book.save()
            RoomLayout.apply(RoomCatalog.def(store.currentRoom))
            GameCamera.endPark(count: max(jellies.count, 1))
            if GameCamera.refreshRoam(aspect: GameCamera.aspect) != nil {
                for a in roster where (work.arena[a.id] ?? a.sim.arenaRadius).isFinite { a.sim.arenaCenter = GameCamera.arenaCenter; a.sim.arenaRadius = GameCamera.arenaRadius }
            }
            syncDecor()
            var taken: [SIMD2<Float>] = []
            for a in roster {
                guard let brain = a.brain else { continue }
                var spot = work.homes[a.id] ?? Self.greetSpot(a.id)
                if taken.contains(where: { simd_distance($0, spot) < 1.5 }) {
                    spot = [SIMD2<Float>(-1.6, 0.4), SIMD2(1.6, 0.4), SIMD2(0, -1.0), SIMD2(-1.8, -1.2)].first { s in !taken.contains { simd_distance($0, s) < 1.5 } } ?? spot
                }
                spot = brain.fixed(spot)
                taken.append(spot)
                rehome(a, at: spot)
                brain.autonomy = work.autonomy[a.id] ?? true
                brain.idleBlocked = false
                brain.restTimer = 2
            }
            work.homes = [:]; work.autonomy = [:]; work.arena = [:]; work.owed = [:]
            book.comers = []
            park.card = nil
        }
    }
}

/// Where everybody starts in the park: spread over the play zone (the roaming floor of the park's camera), the Jelbies who came in front.
enum ParkLayout {
    /// (x as a share of the half width, z as a share of the depth) for up to five.
    static let slots: [(Float, Float)] = [(-0.35, 0.62), (0.40, 0.72), (0.0, 0.46), (-0.60, 0.26), (0.62, 0.30)]

    static func spots(count: Int) -> [SIMD2<Float>] {
        (0..<max(count, 0)).map { k in
            let s = slots[k % slots.count]
            guard let f = GameCamera.roamFloor else { return SIMD2(s.0 * 3, -2 + s.1 * 5) }
            let z = f.minZ + s.1 * (f.maxZ - f.minZ)
            let q = GameCamera.constrain(SIMD3(s.0 * f.halfWidth(at: z), 0, z), radius: 0.8)
            return SIMD2(q.x, q.z)
        }
    }
}
