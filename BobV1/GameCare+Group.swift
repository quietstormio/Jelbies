//
//  GameCare+Group.swift
//  The GROUP serving: with several Jellies and nobody singled out, Feed / Drink bring ONE serving with a place per Jelly (a straw each for drinks) (DiningGroup over the shared
//  `dining` set). Every Jelly walks to his own place and drinks what HIS thirst tier asks (Quenched 0 = he comes over and shakes his head, Normal a
//  little, Thirsty more, Parched the most), is paid per gulp, and leaves when he is done; the drink goes when all are done.
//  One Jelly in the room, or one singled out (a name picked, a single close-up), keeps the single-Jelly flow of GameCare+Dining.swift.
//  Food and drink share this path (`serving.kind`): Full / Quenched shake their head, Normal takes 1 piece, Hungry 2, Famished 3 (faster).
//

import Foundation
import simd

extension GameCare {
    /// A group serving is asked for or running (menu, tests and the tray flag read it).
    var groupActive: Bool { groupWanted != nil || group.isActive }
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
        notice = nil
    }

    /// Once per fixed step (end of `tickOthers`, which sees every Jelly): starts the wanted group serving, then runs the group.
    func tickGroup(_ actors: [JellyActor], dt: Float) {
        if let c = groupWanted {
            groupAge += dt
            let ready = actors.count == jellies.count && actors.allSatisfy { $0.brain != nil } && !callRunning && queued.isEmpty && dining.phase == .absent
            if focus.isActive || bath.active || groupAge > Self.mealTimeout { groupWanted = nil; return }
            guard ready else { return }
            let sorted = actors.sorted { $0.id < $1.id }
            let brains = sorted.compactMap(\.brain)
            let floors: [() -> SIMD2<Float>] = sorted.map { a in { [weak b = a.brain, weak s = a.sim] in b.map { Self.floorPos($0, s) } ?? .zero } }
            let kind: NeedKind = c.kind == .food ? .hunger : .thirst
            group.eager = eagerWhenFamished
            group.tierOf = { [weak self] i in self?.needs(for: i).tier(kind) ?? .normal }
            group.pay = { [weak self] i, k in self?.needs(for: i).gain(kind, Float(k) * MealAppetite.gainPerPiece); self?.ate(jelly: i, c, pieces: k) }
            group.start(c, brains: brains, floor: { floors[$0]() })
            groupWanted = nil
            return
        }
        guard group.isActive else { return }
        for a in actors { if let b = a.brain, a.id < group.blobCount { b.idleBlocked = true } }
        group.tick(dt: dt)
    }
}
