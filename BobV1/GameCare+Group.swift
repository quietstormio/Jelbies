//
//  GameCare+Group.swift
//  The GROUP serving: with several Jellies and nobody singled out, Feed / Drink bring ONE serving with a place per Jelly (a straw each for drinks) (DiningGroup over the shared
//  `dining` set). Every Jelly walks to his own place and drinks what HIS thirst tier asks (Quenched 0 = he comes over and shakes his head, Normal a
//  little, Thirsty more, Parched the most), is paid per gulp, and leaves when he is done; the drink goes when all are done.
//  One Jelly in the room, or one singled out (a name picked, a single close-up), keeps the single-Jelly flow of GameCare+Dining.swift.
//  Food and drink share this path (`serving.kind`): Full / Quenched shake their head, Normal takes 1 piece, Hungry 2, Famished 3 (faster).
//  The tray seats three (DiningGroup.maxDiners): with four Jellies the three who need it most sit first and the fourth waits where he stands
//  (reserved, like a diner) and eats at a second sitting of the same serving once the first tray has gone.
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
        for w in groupWaitSaved.values { if let b = w.brain { b.reserved = w.was; b.waitFocus = nil; b.idleBlocked = false } }
        groupWaitSaved = [:]
    }

    /// The ids of a sitting: at most `DiningGroup.maxDiners`, the ones who need it most first (lowest level, then the lower id); the rest wait.
    static func seating(_ ids: [Int], level: (Int) -> Float) -> (now: [Int], later: [Int]) {
        guard ids.count > DiningGroup.maxDiners else { return (ids.sorted(), []) }
        let order = ids.sorted { let a = level($0), b = level($1); return a != b ? a < b : $0 < $1 }
        return (Array(order.prefix(DiningGroup.maxDiners)).sorted(), Array(order.dropFirst(DiningGroup.maxDiners)).sorted())
    }

    /// Once per fixed step (end of `tickOthers`, which sees every Jelly): starts the wanted group serving, then runs the group.
    func tickGroup(_ actors: [JellyActor], dt: Float) {
        if let c = groupWanted {
            groupAge += dt
            let ready = actors.count == jellies.count && actors.allSatisfy { $0.brain != nil } && !callRunning && queued.isEmpty && dining.phase == .absent
            if focus.isActive || bath.active || groupAge > Self.mealTimeout { groupWanted = nil; groupQueueClear(); return }
            guard ready else { return }
            let kind: NeedKind = c.kind == .food ? .hunger : .thirst
            // who sits now: the queued ids (a second sitting), else everybody; three at most, the rest wait for the next sitting
            let candidates = groupQueue.isEmpty ? actors.map(\.id) : groupQueue
            let seats = Self.seating(candidates, level: { [weak self] id in self?.needs(for: id).level(kind) ?? 1 })
            groupQueue = seats.later; groupNext = seats.later.isEmpty ? nil : c
            let sorted = actors.filter { seats.now.contains($0.id) }.sorted { $0.id < $1.id }
            let brains = sorted.compactMap(\.brain)
            let floors: [() -> SIMD2<Float>] = sorted.map { a in { [weak b = a.brain, weak s = a.sim] in b.map { Self.floorPos($0, s) } ?? .zero } }
            group.eager = eagerWhenFamished
            group.tierOf = { [weak self] i in self?.needs(for: i).tier(kind) ?? .normal }
            group.pay = { [weak self] i, k in self?.needs(for: i).gain(kind, Float(k) * MealAppetite.gainPerPiece); self?.ate(jelly: i, c, pieces: k) }
            group.start(c, brains: brains, floor: { floors[$0]() }, ids: sorted.map(\.id))
            groupWanted = nil
            if !group.isActive { groupQueueClear() }
            return
        }
        guard group.isActive else {
            // a sitting just ended: the waiting Jellies get theirs next (the tray pops again once this one has gone)
            if let c = groupNext, !groupQueue.isEmpty {
                if group.gaveUp { groupQueueClear() } else { groupWanted = c; groupAge = 0 }
            }
            return
        }
        for a in actors {
            guard let b = a.brain else { continue }
            if group.memberIDs.contains(a.id) { b.idleBlocked = true; continue }
            if groupQueue.contains(a.id) {
                // he waits where he stands (look / step / bounce), like a diner, so he never walks into the tray corridor
                if groupWaitSaved[a.id] == nil { groupWaitSaved[a.id] = GroupWaiter(brain: b, was: b.reserved) }
                b.reserved = true; b.idleBlocked = true; b.waitFocus = DiningSpot.preferred
            }
            stepAsideGroup(id: a.id, brain: b, sim: a.sim, dt: dt)      // (a waiter, or a diner of the last sitting still on his place)
        }
        group.tick(dt: dt)
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
        let reach = MelonController.jellyGap + 0.1
        func near(_ p: SIMD2<Float>) -> Float { stands.map { min(simd_distance(p, $0), simd_distance(p, SIMD2($0.x, $0.y - Self.approachBack))) }.min() ?? 9 }
        guard near(here) < reach else { return }
        let centre = stands.reduce(SIMD2<Float>.zero, +) / Float(stands.count)
        let spots: [SIMD2<Float>] = [SIMD2(2.1, 0.3), SIMD2(-2.1, 0.3), SIMD2(1.5, -1.0), SIMD2(-1.5, -1.0), SIMD2(0, -2.0)].map { centre + $0 }
        var best: (d: Float, p: SIMD2<Float>)?
        for c in spots {
            let q = brain.resolve(SIMD3(c.x, 0, c.y), 0.6)
            let p = SIMD2(q.x, q.z)
            let d = near(p) - 0.2 * simd_distance(p, here)
            if best == nil || d > best!.d { best = (d, p) }
        }
        if let best { brain.requestNow(.goTo(best.p)) }
        clearCool[id] = 2
    }
}
