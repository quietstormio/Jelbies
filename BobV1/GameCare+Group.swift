//
//  GameCare+Group.swift
//  The GROUP serving: with several Jellies and nobody singled out, Feed / Drink bring ONE serving with a place per Jelly (a straw each for drinks) (DiningGroup over the shared
//  `dining` set). Every Jelly walks to his own place and drinks what HIS thirst tier asks (Quenched 0 = he comes over and shakes his head, Normal a
//  little, Thirsty more, Parched the most), is paid per gulp, and leaves when he is done; the drink goes when all are done.
//  One Jelly in the room, or one singled out (a name picked, a single close-up), keeps the single-Jelly flow of GameCare+Dining.swift.
//  Food and drink share this path (`serving.kind`): Full / Quenched shake their head, Normal takes 1 piece, Hungry 2, Famished 3 (faster).
//  The home tray seats two (DiningGroup.homeSeats, C6 2026-11-17; the café three, DiningGroup.maxDiners): the two who need it most sit first (the closer one on a tie)
//  and the others wait (reserved, like a diner) and eat at a second sitting of the same serving once the first tray has gone. A waiter waits calmly (he faces the
//  tray: no look-arounds, no steps) at a spot clear of every eater (`stepAsideGroup`, DiningGroup.waiterClear).
//

import Foundation
import simd

/// A Jelly waiting for the second sitting: his brain and what `reserved` was before.
@MainActor final class GroupWaiter {
    weak var brain: BlobBrain?
    let was: Bool
    init(brain: BlobBrain, was: Bool) { self.brain = brain; self.was = was }
}

extension GameCare {
    /// A group serving is asked for or running (menu, tests and the tray flag read it).
    var groupActive: Bool { groupWanted != nil || group.isActive || !groupQueue.isEmpty }
    /// Centre gap the diners keep from each other while they drink (nil = the room's usual gap; MelonStage.keepApart).
    var groupGap: Float? { group.peerGapNow }
    /// The Jelly the care action is for when the player singled one out (a selection, or the one Jelly in a close-up); nil = everybody.
    var singledOutJelly: Int? {
        if focus.isActive, focusGroup.ids.count == 1 { return focusGroup.ids[0] }
        return select.selectedID ?? select.confirmed
    }

    /// For the general Feed / Snack menus: everybody (a group serving) unless the player is in one Jelbie's close-up. A sticky selection does NOT single one out.
    var singledOutForFood: Int? { focus.isActive && focusGroup.ids.count == 1 ? focusGroup.ids[0] : nil }

    /// Drops a group serving (Come here): the drink poofs, the gulps already drunk stay paid.
    func cancelGroup() {
        groupWanted = nil
        group.cancel()
        groupQueueClear()
        notice = nil
    }

    /// The waiting Jellies are let go (the queue is dropped).
    func groupQueueClear() {
        groupQueue = []; groupNext = nil
        for w in groupWaitSaved.values { if let b = w.brain { b.reserved = w.was; b.waitFocus = nil; b.idleBlocked = false; b.mealFaceYaw = nil } }
        groupWaitSaved = [:]
    }

    /// The ids of a sitting: at most `seats`, the ones who need it most first (lowest level; levels within `seatTie` are a tie, then the nearer by `distance`,
    /// then the lower id); the rest wait.
    static let seatTie: Float = 0.1
    static func seating(_ ids: [Int], level: (Int) -> Float, seats: Int = DiningGroup.maxDiners, distance: ((Int) -> Float)? = nil) -> (now: [Int], later: [Int]) {
        guard ids.count > seats else { return (ids.sorted(), []) }
        let order = ids.sorted {
            let a = level($0), b = level($1)
            if abs(a - b) >= seatTie { return a < b }
            if let distance { let da = distance($0), db = distance($1); if da != db { return da < db } }
            return a != b ? a < b : $0 < $1
        }
        return (Array(order.prefix(seats)).sorted(), Array(order.dropFirst(seats)).sorted())
    }

    /// Once per fixed step (end of `tickOthers`, which sees every Jelly): starts the wanted group serving, then runs the group.
    func tickGroup(_ actors: [JellyActor], dt: Float) {
        traceWakeOne(actors, dt: dt)
        if let c = groupWanted {
            if groupAge == 0 { MealTrace.begin(groupQueue.isEmpty ? "order food/drink tap (first tickGroup)" : "order2 second sitting") }
            groupAge += dt
            if callRunning, Self.softMealWakeWatchdog(age: groupAge) { MealTrace.log("callRunning watchdog cleared (group)"); callRunning = false }
            let ready = actors.count == jellies.count && actors.allSatisfy { $0.brain != nil } && !callRunning && queued.isEmpty && (dining.phase == .absent || cafeBook.tableOut)
            if focus.isActive || bath.active || groupAge > Self.mealTimeout {
                if groupAge > Self.mealTimeout { noticeAtBob = true; notice = "The table couldn't be set — try again"; noticeSerial += 1; noticeAge = 0 }          // (was silent)
                groupWanted = nil; groupQueueClear(); return
            }
            if !ready { traceWaiting(actors) }
            guard ready else { return }
            MealTrace.log("group ready after \(groupAge) s")
            placeForTrace(actors)
            let kind: NeedKind = c.kind == .food ? .hunger : .thirst
            // who sits now: the queued ids (a second sitting), else everybody; three at most, the rest wait for the next sitting
            let candidates = groupQueue.isEmpty ? actors.map(\.id) : groupQueue
            let home = cafeBook.hooks == nil          // (C6: the home tray seats two per sitting; the café keeps its three)
            var floorOf: [Int: SIMD2<Float>] = [:]
            for a in actors { if let b = a.brain { floorOf[a.id] = Self.floorPos(b, a.sim) } }
            let seats = Self.seating(candidates, level: { [weak self] id in self?.needs(for: id).level(kind) ?? 1 }, seats: home ? DiningGroup.homeSeats : DiningGroup.maxDiners,
                                     distance: { id in simd_distance(floorOf[id] ?? DiningSpot.preferred, DiningSpot.preferred) })
            groupQueue = seats.later; groupNext = seats.later.isEmpty ? nil : c
            // (round E: where the SLEEPING waiters lie: they are never moved, so this sitting's places keep clear of them)
            group.keepClearOf = seats.later.compactMap { id in actors.first { $0.id == id }.flatMap { a in a.brain.flatMap { $0.isSleeping ? Self.floorPos($0, a.sim) : nil } } }
            let sorted = actors.filter { seats.now.contains($0.id) }.sorted { $0.id < $1.id }
            let brains = sorted.compactMap(\.brain)
            let floors: [() -> SIMD2<Float>] = sorted.map { a in { [weak b = a.brain, weak s = a.sim] in b.map { Self.floorPos($0, s) } ?? .zero } }
            if let cafeHooks = cafeBook.hooks {          // the café: everybody eats the whole treat, paid by the café's own hooks
                group.eager = false
                group.forcedOrigin = cafeBook.tableOut ? cafeBook.origin : nil; group.keepTable = cafeBook.tableOut
                group.tierOf = { _ in .famished }
                group.pay = cafeHooks.pay
            } else {
                group.forcedOrigin = nil; group.keepTable = false
                group.eager = eagerWhenFamished
                group.tierOf = { [weak self] i in self?.needs(for: i).tier(kind) ?? .normal }
                group.pay = { [weak self] i, k in self?.needs(for: i).gain(kind, Float(k) * MealAppetite.gainPerPiece); self?.ate(jelly: i, c, pieces: k) }
            }
            group.avoid = jellyFloors
            #if targetEnvironment(simulator)
            let bodies: [() -> SIMD2<Float>] = sorted.map { a in { [weak s = a.sim] in s.map { (b: SoftBody) -> SIMD2<Float> in let v = b.centroid(); return SIMD2(v.x, v.z) } ?? .zero } }
            group.traceBody = { bodies[$0]() }
            let skins: [SoftBody] = sorted.map { $0.sim }
            group.traceSkin = { i, box in
                let b = skins[i]; var m = Float.infinity
                for k in 0..<b.n where b.x[3 * k + 1] < b.floorY + box.height { m = min(m, RoomLayout.boxDistanceXZ(SIMD2(b.x[3 * k], b.x[3 * k + 2]), box)) }
                return m
            }          // (meal trace only: the pose line's body centroid)
            let mouths: [() -> SIMD3<Float>?] = sorted.map { a in { [weak b = a.brain, weak s = a.sim] in
                guard let b, let s, b.dineIsSipping, b.dinePhaseName == "chew" else { return nil }
                return b.mouthWorld(sim: s) } }
            group.traceMouth = { mouths[$0]() }          // (meal trace only: his mouth while he sips a gulp)
            group.traceWaiters = { [weak self] in self?.groupQueue ?? [] }          // (meal trace only: the waiters for the next sitting, C6)
            #endif
            group.start(c, brains: brains, floor: { floors[$0]() }, ids: sorted.map(\.id))
            if let cafeHooks = cafeBook.hooks, group.isActive { cafeHooks.seated(group.memberIDs, group.placeOf) }
            groupWanted = nil
            if !group.isActive { groupQueueClear() }
            return
        }
        if group.gaveUp { if !gaveUpShown { gaveUpShown = true; tapRefused("Couldn't get the food to the table — try again") } } else { gaveUpShown = false }          // (a serving the diners could not reach was given up silently)
        guard group.isActive else {
            // a sitting just ended: the waiting Jellies get theirs next (the tray pops again once this one has gone)
            if let c = groupNext, !groupQueue.isEmpty {
                if group.gaveUp { groupQueueClear() } else { groupWanted = c; groupAge = 0 }
            }
            return
        }
        group.bystanders = { actors.filter { !self.group.memberIDs.contains($0.id) && $0.brain != nil }.map { Self.floorPos($0.brain!, $0.sim) } }
        group.waitersPending = { [weak self] in !(self?.groupQueue.isEmpty ?? true) }
        #if targetEnvironment(simulator)
        group.traceWaiterFloor = { id in          // (meal trace only, T9: the pose line's ` wpos=`)
            guard let a = actors.first(where: { $0.id == id }), let b = a.brain else { return nil }
            return (Self.floorPos(b, a.sim), "\(b.activity)")
        }
        #endif
        // C7 (round E): the first waiter takes the first freed place of this sitting (the tray stays); `-MealRolling 0` = the next sitting as in round D
        if DiningGroup.rolling, let w = groupQueue.first, let slot = group.freeSlot(), let a = actors.first(where: { $0.id == w }), let b = a.brain {
            groupQueue.removeFirst(); groupWaitSaved[w] = nil
            if groupQueue.isEmpty { groupNext = nil }
            let floor: () -> SIMD2<Float> = { [weak b, weak s = a.sim] in b.map { Self.floorPos($0, s) } ?? .zero }
            #if targetEnvironment(simulator)
            let body: () -> SIMD2<Float> = { [weak s = a.sim] in s.map { (q: SoftBody) -> SIMD2<Float> in let v = q.centroid(); return SIMD2(v.x, v.z) } ?? .zero }
            let mouth: () -> SIMD3<Float>? = { [weak b, weak s = a.sim] in
                guard let b, let s, b.dineIsSipping, b.dinePhaseName == "chew" else { return nil }
                return b.mouthWorld(sim: s) }
            group.join(slot: slot, brain: b, id: w, floor: floor, body: body, mouth: mouth)
            #else
            group.join(slot: slot, brain: b, id: w, floor: floor)
            #endif
        }
        for a in actors {
            guard let b = a.brain else { continue }
            if group.memberIDs.contains(a.id) { if group.isHolding(a.id) { b.idleBlocked = true; continue } }          // (a diner who is done is released on his own: he is a free Jelly again)
            if groupQueue.contains(a.id) {
                // he waits where he stands (look / step / bounce), like a diner, so he never walks into the tray corridor
                if groupWaitSaved[a.id] == nil { groupWaitSaved[a.id] = GroupWaiter(brain: b, was: b.reserved) }
                b.reserved = true; b.idleBlocked = true; b.waitFocus = group.originNow ?? DiningSpot.preferred
                if DiningGroup.calmWait, let o = group.originNow { let p = Self.floorPos(b, a.sim); b.mealFaceYaw = atan2f(o.x - p.x, o.y - p.y) }          // (C6: he waits calmly, facing the tray)
            }
            stepAsideGroup(id: a.id, brain: b, sim: a.sim, dt: dt)      // (a waiter, or a diner of the last sitting still on his place)
        }
        group.tick(dt: dt)
    }

    /// `-MealAwake <id>` (simulator only): once all are asleep, that one Jelbie is woken (the plain quick wake) so a meal can be asked with two asleep and one awake.
    private func traceWakeOne(_ actors: [JellyActor], dt: Float) {
        #if targetEnvironment(simulator)
        if let k = MealTrace.awakeID, MealTrace.awakeDone, let b = actors.first(where: { $0.id == k })?.brain { b.idleBlocked = true; b.sleepEnabled = false; b.commandedGoodnight = false }          // (he stays up)
        guard let k = MealTrace.awakeID, !MealTrace.awakeDone, !actors.isEmpty, actors.allSatisfy({ $0.brain?.isNapping ?? false }) else { return }
        MealTrace.awakeT += dt
        guard MealTrace.awakeT > 4, let a = actors.first(where: { $0.id == k }), let b = a.brain else { return }
        MealTrace.awakeDone = true
        b.sleepEnabled = false          // (he stays up: the night's retry loop does not send him back to bed)
        b.commandedGoodnight = false
        nightRest.wanted.remove(k); nightRest.dayOnce.remove(k); nightRest.nightWoken.insert(k)          // (the night's retry loop does not send him back to bed for 120 s)
        b.requestNow(.goTo(b.position))
        NSLog("[mealtrace] MealAwake: woke jelly %d", k)
        MealTrace.log("MealAwake: woke jelly \(k)")
        #endif
    }

    /// Trace aid: why the group start is still waiting (a line only when the reason changes).
    private func traceWaiting(_ actors: [JellyActor]) {
        #if targetEnvironment(simulator)
        MealTrace.logOnChange("group waiting callRunning=\(callRunning) queued=\(queued.count) tray=\(dining.phase) actors=\(actors.count)/\(jellies.count)")
        #endif
    }

    /// `-MealStart` (simulator only, once): puts the Jelbies, in id order, on the given floor points right before the group starts.
    private func placeForTrace(_ actors: [JellyActor]) {
        #if targetEnvironment(simulator)
        guard let pts = MealTrace.takeStarts() else { return }
        for (k, a) in actors.sorted(by: { $0.id < $1.id }).enumerated() where k < pts.count {
            guard let brain = a.brain else { continue }
            if let sk = brain.skinnerRef { brain.abortScript(a.sim, sk) } else { brain.pending = nil; brain.feet.reset(); brain.feetInit = false; brain.poseW = 0 }
            brain.pending = nil
            a.sim.teleport(toXZ: pts[k])
            brain.currentPose(a.sim)
            brain.runW = 0; brain.zoomW = 0
            brain.skinnerRef?.jelly.reset()
            MealTrace.log("MealStart: jelly \(a.id) placed at (\(pts[k].x),\(pts[k].y))")
        }
        #endif
    }

    /// A Jelly who is not at this sitting and stands on one of its places (or its approach point) moves off it: the single flow's `stepAside`,
    /// for the group's places (the diners of the first sitting are still standing on them when the second one forms).
    func stepAsideGroup(id: Int, brain: BlobBrain, sim: SoftBody?, dt: Float) {
        clearCool[id, default: 0] -= dt
        guard clearCool[id, default: 0] <= 0, !brain.commanded, !(id == 0 && (focus.isActive || bath.active)) else { return }
        let act = brain.activity
        guard act == .idle || act == .lookingAround || act == .steppingInPlace else { return }
        let stands = group.standsNow
        guard !stands.isEmpty else { return }
        let here = Self.floorPos(brain, sim)
        // (C6: a waiter for the next sitting keeps `waiterClear` from every eater, their catch lean included; anybody else the old body-and-margin)
        let waiter = groupQueue.contains(id)
        if waiter, brain.isSleeping { return }          // (a sleeper waiting for the next sitting is never woken just to step aside: he is woken for his own sitting)
        let reach = waiter ? DiningGroup.waiterClear : MelonController.jellyGap + 0.1
        func near(_ p: SIMD2<Float>) -> Float { stands.map { min(simd_distance(p, $0), simd_distance(p, SIMD2($0.x, $0.y - Self.approachBack))) }.min() ?? 9 }
        guard near(here) < reach || group.trayDistance(here) < DiningGroup.trayClearance else { return }          // (or on the rectangle the tray is about to be drawn on)
        let centre = stands.reduce(SIMD2<Float>.zero, +) / Float(stands.count)
        var rel: [SIMD2<Float>] = [SIMD2(2.1, 0.3), SIMD2(-2.1, 0.3), SIMD2(1.5, -1.0), SIMD2(-1.5, -1.0), SIMD2(0, -2.0)]
        if waiter {          // (beside the row, the tray's front corners, far behind; round E: a ring of 12 at 2.2 and 3.0 too, for walls that push the near ones in)
            rel += [SIMD2(2.6, 0), SIMD2(-2.6, 0), SIMD2(1.7, 2.0), SIMD2(-1.7, 2.0), SIMD2(0, -2.6)]
            for k in 0..<12 { let a = Float(k) * .pi / 6; for r in [Float(2.2), 3.0] { rel.append(SIMD2(sinf(a), cosf(a)) * r) } }
        }
        let spots = rel.map { centre + $0 }
        var best: (d: Float, p: SIMD2<Float>)?
        for c in spots {
            let q = brain.resolve(SIMD3(c.x, 0, c.y), 0.6)
            let p = SIMD2(q.x, q.z)
            var d = min(near(p), group.trayDistance(p) + 0.5) - 0.2 * simd_distance(p, here)
            if waiter, near(p) >= reach, group.trayDistance(p) >= DiningGroup.trayClearance { d = 100 - simd_distance(p, here) }          // (any clear spot beats every unclear one; the nearest clear one wins)
            if best == nil || d > best!.d { best = (d, p) }
        }
        if let best {
            brain.requestNow(.goTo(best.p))
            if waiter { MealTrace.log("waiter \(id) steps aside to " + String(format: "(%.2f,%.2f) near=%.2f tray=%.2f", best.p.x, best.p.y, near(best.p), group.trayDistance(best.p)) + " clear=\(best.d >= 50)") }
        }
        clearCool[id] = 2
    }
}
