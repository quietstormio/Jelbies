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
    var giftNear: Float = 0
    var saveT: Float = 0
    nonisolated deinit {}
}

extension GameCare {
    func wirePark() {
        park.onSwap = { [weak self] dest in self?.parkSwap(dest) }
    }

    /// The bodies of the Jelbies that did not come along are away while the park is on.
    func parkHides(_ id: Int) -> Bool { park.inScene && id < jellies.count && !parkBook.comers.contains(id) }

    // MARK: blockers and the request

    /// Why the park cannot be entered now (the friendly line); nil = it can.
    func parkBlocker() -> String? {
        if park.active { return CafeBlock.busy.message }
        guard let b = cafeBlocker(), b != .noDrops else { return nil }
        return b == .night ? "The park is closed at night. Come back in the morning!" : b.message
    }

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
        park.begin()
    }

    private var parkFadeBlocked: Bool {
        race.active || show.active || raceWait != nil || bath.active || focus.isActive || trayOut || dining.phase != .absent || groupActive || arranging || cafe.active
            || parkBook.roster.contains { $0.brain?.isSleeping == true }
    }

    // MARK: per fixed step

    /// Once per fixed step (the stage calls it with every Jelbie of the room, after the others).
    func tickPark(_ actors: [JellyActor], dt: Float) {
        parkBook.roster = actors
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
            guard let b = a.brain, let v = book.visitor(vid) else { continue }
            b.idleMood = .happy
            b.sleepLocked = true
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
    }

    /// Friendship, love and the daily gift, from who stands near whom.
    private func tickFriends(_ actors: [JellyActor], dt: Float) {
        let book = parkBook, work = book.work
        var giftPair: (visitor: Int, slot: Int)?
        for k in book.comers {
            guard actors.indices.contains(k), let prof = jelly(k) else { continue }
            let me = actors[k]
            var nearest: ParkFriendLevel?
            for (a, vid) in zip(book.actors, book.cast) {
                guard simd_distance(me.floor, a.floor) < ParkTuning.nearRadius else { continue }
                var rate = ParkTuning.pointsPerSecond * dt
                if let partner = me.brain?.socialPartnerID, partner == a.id { rate *= ParkTuning.socialMul }          // playing together
                let before = book.visitor(vid)?.level(with: prof.character) ?? .stranger
                nearest = max(nearest ?? before, before)
                if let up = book.add(points: rate, visitor: vid, character: prof.character) { parkLevelUp(visitor: vid, slot: k, level: up, visitorBody: a) }
                if before == .best, giftPair == nil { giftPair = (vid, k) }
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
        // a gift from a best friend, once a day, after a while playing near
        if let g = giftPair, !book.giftGivenToday {
            work.giftNear += dt
            if work.giftNear >= ParkTuning.giftNearSeconds { work.giftNear = 0; parkGift(visitor: g.visitor, slot: g.slot) }
        } else { work.giftNear = 0 }
    }

    private func parkLevelUp(visitor vid: Int, slot: Int, level: ParkFriendLevel, visitorBody: JellyActor) {
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

    /// A few Drops or a snack, from a best friend.
    private func parkGift(visitor vid: Int, slot: Int) {
        let book = parkBook
        guard let v = book.visitor(vid), let prof = jelly(slot) else { return }
        var text: String
        let snacks = StoreCatalog.items.filter { $0.kind == .food && $0.price > 0 }.sorted { $0.price < $1.price }
        if Bool.random() || snacks.isEmpty {
            let n = Int.random(in: ParkTuning.giftDrops)
            bath.wallet.add(n)
            text = "\(v.name) brought \(prof.name) a gift: \(n) Drops!"
        } else {
            let item = snacks[Int.random(in: 0..<min(3, snacks.count))]
            store.grant(item.id)
            AudioHub.shared.play(.perkSparkle, volume: 0.9)
            text = "\(v.name) brought \(prof.name) a gift: \(item.name)!"
        }
        book.markGift()
        park.say(text)
        touchPlay?.spawnHeart(now: CACurrentMediaTime())
        if let i = book.cast.firstIndex(of: vid), book.actors.indices.contains(i), let b = book.actors[i].brain { b.face(.joyArc, hold: 2.5); b.startHopPlay(sim: book.actors[i].sim, distance: 0.0001) }
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
            work.homes = [:]; work.autonomy = [:]; work.arena = [:]; work.owed = [:]; work.giftNear = 0; work.saveT = 0
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
            // who is there: the Jelbies that came and 2...4 visitors, five at most
            let comers = book.comers
            let n = min(max(ParkTuning.maxTotal - comers.count, ParkTuning.minVisitors), ParkTuning.maxVisitors)
            let characters = comers.compactMap { jelly($0)?.character }
            let cast = book.chooseCast(count: n, characters: characters, now: Date().timeIntervalSince1970)
            let spots = ParkLayout.spots(count: comers.count + cast.count)
            book.cast = cast.map(\.id)
            book.actors = book.spawn?(cast, Array(spots.dropFirst(comers.count))) ?? []
            if book.actors.count != cast.count { book.cast = Array(book.cast.prefix(book.actors.count)) }
            book.markSeen(book.cast, at: Date().timeIntervalSince1970)
            book.warmLines(book.cast)
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
            for a in book.actors {
                guard let b = a.brain else { continue }
                wardrobe.tick(id: a.id, brain: b, sim: a.sim, outfit: [:], role: .none, hideAll: true, dt: 1.0 / 60)
                features.tick(id: a.id, brain: b, sim: a.sim, feature: .none, worn: [], hideAll: true, dt: 1.0 / 60)
            }
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
