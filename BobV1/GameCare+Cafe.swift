//
//  GameCare+Cafe.swift
//  The café outing: the glue between the trip (Cafe/CafeTrip.swift), the room (RoomCatalog.cafe, a visiting room applied under the white fade WITHOUT moving in),
//  the group serving (the home dining code with the café's treats and table) and the Jelbies.
//
//  ALL the Jelbies of the room come along. At the café nobody roams and the room's decor is away. The player picks a treat for each (Drops are charged once, at Order);
//  the usual group dining runs: each walks to his place and tosses his treat into his mouth, piece by piece (never an arm to the mouth). Café treats are never refused,
//  fill hunger, nudge condition, start the treat's perk (a longer one than the store's) and a whole outing is love (attention). Then a cheer and "Head home".
//  Persisted: nothing new. Only Drops (DropsWallet), perks (JellyPerks), needs (BlobNeeds) and condition (JellyStats) change, in their own stores.
//

import Foundation
import QuartzCore
import simd

/// The callbacks the group serving takes while a café order is out (GameCare+Group.swift).
struct CafeServingHooks {
    var pay: (Int, Int) -> Void
    var seated: ([Int], [Int]) -> Void
}

/// What GameCare keeps while the café trip is on.
@MainActor
final class CafeBook {
    var actors: [JellyActor] = []
    var homes: [Int: SIMD2<Float>] = [:]
    var autonomy: [Int: Bool] = [:]
    var arena: [Int: Float] = [:]
    var hooks: CafeServingHooks?
    var plate: CafePlate?
    /// Pieces eaten this visit, by Jelbie.
    var ate: [Int: Int] = [:]
    /// What the order cost.
    var charged = 0
    /// Seconds until each Jelbie's arrival hop / cheer (by actor id).
    var hopIn: [Int: Float] = [:]
    var cheerIn: [Int: Float] = [:]
    var serial = 0
    nonisolated deinit {}
}

extension GameCare {
    func wireCafe() {
        cafe.onSwap = { [weak self] dest in self?.cafeSwap(dest) }
        let d = UserDefaults.standard
        if let s = d.string(forKey: "CafeSlowMo"), let v = Float(s), v > 0 { dining.timeScale = v }          // capture aid: slows the toss
    }

    // MARK: blockers and the request

    /// Why the café cannot be entered now (nil = it can). In order: see CafeBlock.
    func cafeBlocker() -> CafeBlock? {
        if cafe.active { return .busy }
        if isBedtimeHours { return .night }
        if raceBusy || show.active || raceBook.returner != nil { return .competition }
        if roomSwitch.active { return .moving }
        if let b = roomActivityBlocker() {
            switch b {
            case .trip: return .competition
            case .bath: return .bath
            case .focus: return .focus
            case .meal: return .meal
            case .arranging: return .arranging
            case .sleeping: return .sleeping
            default: return .busy
            }
        }
        if voice.mode.phase != .idle || voice.voiceGoing || voice.comingNow { return .listening }
        if bath.wallet.count < CafeMenu.cheapest { return .noDrops }
        return nil
    }

    /// The Go out menu's Café row. Blocked: a friendly toast and nothing else. Else the white fade starts (the swap happens between sim steps, in `tickCafe`).
    func requestCafe() {
        if let b = cafeBlocker() {
            cafe.showRefusal(b.message)
            AudioHub.shared.play(.notEnough)
            return
        }
        select.cancel(); queued.removeAll(); callRunning = false
        voice.cancel()
        cafe.begin()
    }

    /// Something that started under the fade out (the same checks as a room swap, less the café's own trip flag).
    private var cafeFadeBlocked: Bool {
        race.active || show.active || raceWait != nil || bath.active || focus.isActive || trayOut || dining.phase != .absent || groupActive || arranging
            || cafeBook.actors.contains { $0.brain?.isSleeping == true }
    }

    // MARK: per fixed step

    /// Once per fixed step (the stage calls it with every Jelbie, after the others).
    func tickCafe(_ actors: [JellyActor], dt: Float) {
        cafeBook.actors = actors
        if cafe.active { for a in actors { a.brain?.sleepLocked = true } }
        cafe.step(dt: dt, blocked: cafe.phase == .goOut && cafeFadeBlocked)
        guard cafe.active else { return }
        let book = cafeBook
        if cafe.inScene {
            for a in actors { guard let b = a.brain else { continue }; b.autonomy = false; b.idleBlocked = true }
        }
        switch cafe.phase {
        case .arriveIn, .menu:
            for a in actors {
                guard var t = book.hopIn[a.id] else { continue }
                t -= dt
                if t <= 0 {
                    book.hopIn[a.id] = nil
                    if let b = a.brain, b.commandedIdle == nil, b.idleState.kind == nil, case .none = b.script { b.startHopPlay(sim: a.sim, distance: 0.0001) }
                } else { book.hopIn[a.id] = t }
            }
        case .eating:
            if actors.count == 1 { tickGroup(actors, dt: dt) }     // the stage only runs tickOthers (and so tickGroup) with 2+ Jelbies
            let finished = groupWanted == nil && !group.isActive && groupQueue.isEmpty && dining.phase == .absent
            if finished { cafeServingFinished() }
        case .cheer:
            for a in actors {
                guard var t = book.cheerIn[a.id] else { continue }
                t -= dt
                if t <= 0 { book.cheerIn[a.id] = nil; cafeCheer(a) } else { book.cheerIn[a.id] = t }
            }
        default: break
        }
    }

    // MARK: the world swaps (under the white)

    private func cafeSwap(_ dest: CafeTrip.Dest) {
        let book = cafeBook
        let actors = book.actors
        switch dest {
        case .cafe:
            book.homes = [:]; book.autonomy = [:]; book.arena = [:]; book.ate = [:]; book.hopIn = [:]; book.cheerIn = [:]; book.charged = 0
            for a in actors {
                guard let brain = a.brain else { continue }
                book.homes[a.id] = a.floor; book.autonomy[a.id] = brain.autonomy; book.arena[a.id] = a.sim.arenaRadius
                brain.abortAll(a.sim, a.skinner)
                brain.commandedIdle = nil; brain.commandedDecor = nil; brain.commandedFlip = false
            }
            RoomLayout.apply(RoomCatalog.cafe)
            if GameCamera.refreshRoam(aspect: GameCamera.aspect) != nil {
                for a in actors where a.sim.arenaRadius.isFinite { a.sim.arenaCenter = GameCamera.arenaCenter; a.sim.arenaRadius = GameCamera.arenaRadius }
            }
            syncDecor()
            dining.tableSkin = { n in FoodMeshes.mesh(id: "cafetable_\(n)") }
            let spots = JellyRoster.spawnSpots(count: max(actors.count, 1))
            for (k, a) in actors.enumerated() where k < spots.count {
                rehome(a, at: spots[k])
                guard let brain = a.brain else { continue }
                brain.autonomy = false; brain.idleBlocked = true; brain.restTimer = 0.4
                brain.startTurn(to: 0, sim: a.sim)
                brain.face(.excited, hold: 1.5)
                book.hopIn[a.id] = 0.35 + Float(k) * CafeTuning.arriveHopStagger
            }
            if select.phase != .none { select.cancel() }
        case .home:
            RoomLayout.apply(RoomCatalog.def(store.currentRoom))
            if GameCamera.refreshRoam(aspect: GameCamera.aspect) != nil {
                for a in actors where (book.arena[a.id] ?? a.sim.arenaRadius).isFinite { a.sim.arenaCenter = GameCamera.arenaCenter; a.sim.arenaRadius = GameCamera.arenaRadius }
            }
            dining.tableSkin = nil
            syncDecor()
            var taken: [SIMD2<Float>] = []
            for a in actors {
                guard let brain = a.brain else { continue }
                brain.abortAll(a.sim, a.skinner)
                brain.commandedIdle = nil
                var spot = book.homes[a.id] ?? Self.greetSpot(a.id)
                if taken.contains(where: { simd_distance($0, spot) < 1.5 }) {
                    spot = [SIMD2<Float>(-1.6, 0.4), SIMD2(1.6, 0.4), SIMD2(0, -1.0), SIMD2(-1.8, -1.2)].first { s in !taken.contains { simd_distance($0, s) < 1.5 } } ?? spot
                }
                spot = brain.fixed(spot)
                taken.append(spot)
                rehome(a, at: spot)
                brain.autonomy = book.autonomy[a.id] ?? true
                brain.idleBlocked = false
                brain.restTimer = 2
            }
            book.homes = [:]; book.autonomy = [:]; book.arena = [:]; book.hopIn = [:]; book.cheerIn = [:]; book.hooks = nil; book.plate = nil; book.ate = [:]; book.charged = 0
        }
    }

    // MARK: ordering

    /// The Jelbies at the table (roster ids), in order.
    var cafeDinerIDs: [Int] {
        let ids = cafeBook.actors.filter { $0.brain != nil }.map(\.id)
        return ids.isEmpty ? jellies.map(\.id) : ids
    }

    /// Order for the table. Returns the friendly refusal when the Drops are short (nothing is charged, the card shows it); nil = ordered (or ignored: not at the menu).
    @discardableResult
    func orderCafe(_ o: CafeOrder) -> String? {
        guard cafe.phase == .menu else { return nil }
        let ids = Array(cafeDinerIDs.prefix(DiningGroup.maxDiners))
        guard o.isComplete(jellies: ids) else { return nil }
        let total = o.total(jellies: ids)
        if let why = CafeOrder.refusal(total: total, wallet: bath.wallet.count) { AudioHub.shared.play(.notEnough); return why }
        guard bath.wallet.spend(total) else { return nil }
        AudioHub.shared.play(.buyCoins)
        let book = cafeBook
        book.serial += 1
        book.charged = total; book.ate = [:]
        let plate = CafePlate(order: o, serial: book.serial)
        book.plate = plate
        book.hooks = CafeServingHooks(
            pay: { [weak self] id, k in
                guard let self else { return }
                self.needs(for: id).gain(.hunger, Float(k) * MealAppetite.gainPerPiece)
                if let t = o.treat(for: id) { self.cafeAte(jelly: id, treat: t, pieces: k) }
            },
            seated: { ids, placeOf in
                var by: [Int: CafeTreatID] = [:]
                for (i, id) in ids.enumerated() where placeOf.indices.contains(i) { if let t = o.treat(for: id) { by[placeOf[i]] = t } }
                plate.treatByPlace = by
            })
        beginCafeServing(plate.consumable())
        cafe.ordered(o)
        return nil
    }

    /// A Jelbie ate `pieces` more of `treat`: condition, the perk (a longer one than the store's) and, for sugar-rush zoomies, the run once he is home. Never touches the bag.
    func cafeAte(jelly id: Int, treat: CafeTreatID, pieces: Int) {
        guard pieces > 0, let prof = jelly(id) else { return }
        let t = CafeMenu.treat(treat)
        let first = cafeBook.ate[id, default: 0] == 0
        cafeBook.ate[id, default: 0] += pieces
        let share = Float(pieces) / Float(CafeTuning.piecesPerTreat)
        prof.stats.nudge(t.condition.mapValues { $0 * share }, food: t.name)
        if first {
            let fresh = !prof.perks.isActive(t.perk)
            prof.perks.grant(t.perk, duration: t.perk.raceOnly ? nil : t.perk.duration * CafeTuning.perkDurationMul)
            if fresh { AudioHub.shared.play(.perkSparkle, volume: 0.9) }
            if t.perk == .zoomies { zoomiesDue.insert(id) }
        }
    }

    // MARK: the end of the serving, the cheer

    private func cafeServingFinished() {
        let book = cafeBook
        let atePieces = book.ate.values.reduce(0, +)
        for (id, n) in book.ate where n > 0 { needs(for: id).gain(.attention, CafeTuning.attentionBonus) }
        if CafeTuning.refundIfNothingEaten, atePieces == 0, book.charged > 0 { bath.wallet.add(book.charged, silent: true) }
        book.hooks = nil; book.plate = nil
        cafe.servingEnded()
        book.cheerIn = [:]
        for (k, a) in book.actors.enumerated() where a.brain != nil { book.cheerIn[a.id] = Float(k) * CafeTuning.cheerStagger }
    }

    /// A happy reaction: the jump for joy, a blush, an excited face, a heart and a chirp (existing moves only).
    private func cafeCheer(_ a: JellyActor) {
        guard let b = a.brain else { return }
        b.abortAll(a.sim, a.skinner)
        b.commandedIdle = .joy
        b.blushBump(hold: 3, peak: 0.8)
        b.face(.excited, hold: 2.5)
        b.postEvent(.joyJump)
        touchPlay?.spawnHeart(now: CACurrentMediaTime())
        AudioHub.shared.chirp(jelly: a.id, .happy)
    }
}
