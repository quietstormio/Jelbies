//
//  GameCare+Rooms.swift
//  Living in a bought room: `switchRoom(id)` queues a fade, swaps the room between sim steps (the store moves the decor lists, RoomLayout.apply points
//  the collision / roam / renderer at the new room, the Jelbies are set down on their spawn spots) and fades back in. Room/RoomSwitch.swift is the veil.
//

import Foundation
import simd

extension GameCare {
    /// The room the Jelbies live in.
    var roomID: RoomID { store.currentRoom }

    /// nil = a move to `id` can start now.
    func roomSwitchBlocker(_ id: RoomID) -> RoomSwitchBlock? {
        if !store.ownsRoom(id) { return .notOwned }
        if id == store.currentRoom { return .same }
        if roomSwitch.active { return .busy }
        return roomActivityBlocker()
    }

    /// Whatever else is going on that a room swap must not interrupt (checked at queue time, through the fade, and again just before the swap).
    func roomActivityBlocker() -> RoomSwitchBlock? {
        if tripActive { return .trip }
        if bath.active { return .bath }
        if focus.isActive { return .focus }
        if trayOut || dining.phase != .absent || groupActive { return .meal }
        if arranging { return .arranging }
        if raceBook.actors.contains(where: { $0.brain?.isSleeping == true }) { return .sleeping }
        return nil
    }

    /// Starts the move (a fade, the swap under it). Returns nil when it starts, else why not. Never swaps by itself: `tickRoomSwitch` does, between sim steps.
    @discardableResult
    func switchRoom(_ id: RoomID) -> RoomSwitchBlock? {
        if let b = roomSwitchBlocker(id) { return b }
        roomSwitch.begin(to: id)
        AudioHub.shared.play(.pageTurn)
        return nil
    }

    /// Once per fixed step, first in `tickDecor`.
    func tickRoomSwitch(dt: Float) {
        let r = roomSwitch
        switch r.phase {
        case .off: return
        case .out:
            if roomActivityBlocker() != nil { r.finish(); return }          // something started under the fade (a trip, a bath, a meal): stay put
            r.setWipe(r.wipe + dt / RoomSwitchTuning.fadeOut)
            if r.wipe >= 1 {
                r.set(.hold); r.holdFrames = 0
                performRoomSwap()
            }
        case .hold:
            r.holdFrames += 1
            if r.holdFrames >= RoomSwitchTuning.holdSteps { r.set(.into) }
        case .into:
            r.setWipe(r.wipe - dt / RoomSwitchTuning.fadeIn)
            if r.wipe <= 0 { r.finish() }
        }
    }

    /// The world swap, on the main thread between sim steps (never from a SwiftUI action: the sims may be mid-step).
    func performRoomSwap() {
        guard let dest = roomSwitch.dest, store.ownsRoom(dest), roomActivityBlocker() == nil else { roomSwitch.finish(); return }
        store.moveIn(dest)
        RoomLayout.apply(RoomCatalog.def(dest))
        if GameCamera.refreshRoam(aspect: GameCamera.aspect) != nil {
            for a in raceBook.actors where a.sim.arenaRadius.isFinite { a.sim.arenaCenter = GameCamera.arenaCenter; a.sim.arenaRadius = GameCamera.arenaRadius }
        }
        syncDecor()
        let spots = JellyRoster.spawnSpots(count: max(raceBook.actors.count, 1))
        for (i, a) in raceBook.actors.enumerated() where i < spots.count { rehome(a, at: spots[i]) }
        if select.phase != .none { select.cancel() }
    }

    /// Sets one Jelbie down at `p`, at rest (the same steps the Clean uses to place him in the tub).
    private func rehome(_ a: JellyActor, at p: SIMD2<Float>) {
        guard let brain = a.brain else { a.sim.teleport(toXZ: p); return }
        brain.abortScript(a.sim, a.skinner)
        brain.pending = nil
        brain.idleReset(a.skinner)
        brain.decorIgnore = nil
        a.sim.teleport(toXZ: p)
        brain.currentPose(a.sim)
        brain.runW = 0; brain.zoomW = 0
        a.skinner.jelly.reset()
    }

    /// At launch (GameCare.init): the saved room is the one the collision, roam floor and renderer use. `-Room loft` (capture aid) moves in at once.
    func applySavedRoom() {
        if let s = UserDefaults.standard.string(forKey: "Room"), let id = RoomID(rawValue: s) {
            if id != .home { store.grant("room-\(id.rawValue)") }
            store.moveIn(id)
        }
        RoomLayout.apply(RoomCatalog.def(store.currentRoom))
    }
}
