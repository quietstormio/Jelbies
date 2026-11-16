//
//  GameCare+Camp.swift
//  The Jelmiko Camp visit as a MODE of the park trip (camp-yard-r1): `park.place == .camp`. Same white wipe, camera, hidden home bodies, tap routing and visitor bodies as the park, but nobody comes along,
//  there is no picker, no cast from the pool, no toys, no friendships / gifts / save, no night closure (Camp is open day and night) and no bedtime call. The yard holds ONLY the Camp creatures.
//  The home Jelmiko stay on the stage hidden and still, as at the park; a sleeping one stays asleep (it is neither woken nor moved: the park refuses to open with one asleep, Camp does not).
//  Everything the player does here is parkTrip-shaped: `requestCamp` -> the wipe -> `campSwap(.park)` (scenery, camera, bodies under the opaque white) -> play -> "Go home" -> `campSwap(.home)`.
//

import Foundation
import QuartzCore
import simd

extension GameCare {
    // MARK: entry

    /// Why Camp cannot be entered now (the friendly line); nil = it can. The park's rules minus the night closure and minus "a home creature is asleep".
    func campBlocker() -> String? {
        if park.active || cafe.active { return CafeBlock.busy.message }
        if raceBusy || show.active { return CafeBlock.competition.message }
        if roomSwitch.active { return CafeBlock.moving.message }
        if let b = roomActivityBlocker() {
            switch b {
            case .trip: return CafeBlock.competition.message
            case .bath: return CafeBlock.bath.message
            case .focus: return CafeBlock.focus.message
            case .meal: return CafeBlock.meal.message
            case .arranging: return CafeBlock.arranging.message
            case .sleeping: return CafeBlock.sleeping.message          // (a RACE rival asleep: not a home creature)
            default: return CafeBlock.busy.message
            }
        }
        if voice.mode.phase != .idle || voice.voiceGoing || voice.comingNow { return CafeBlock.listening.message }
        return nil
    }

    /// The Town's Camp tile (a later step) and `-StartCamp`: blocked = a friendly toast; else the white wipe starts at once (no picker, nobody goes along).
    func requestCamp() {
        if let why = campBlocker() {
            park.say(why)
            AudioHub.shared.play(.notEnough)
            return
        }
        select.cancel(); cutWelcomeHome(); queued.removeAll(); callRunning = false
        voice.cancel()
        if guestBook.actor != nil { guestRemove() }          // (a friend over at home goes first, as the Show does)
        park.beginCamp()
    }

    #if targetEnvironment(simulator)
    nonisolated(unsafe) static var startCampPending = UserDefaults.standard.integer(forKey: "StartCamp") != 0
    nonisolated(unsafe) static var startCampFrames = 0
    /// Capture aid: `-StartCamp 1` opens the Camp yard once the room is up (retried like `-StartPark 1`; simulator only).
    func tickCampStart() {
        guard Self.startCampPending else { return }
        if park.phase != .off { Self.startCampPending = false; return }
        Self.startCampFrames += 1
        if Self.startCampFrames > 90, Self.startCampFrames % 45 == 0, !outing.running, !park.picking {
            if let why = campBlocker() { NSLog("[startcamp] blocked at frame %d: %@", Self.startCampFrames, why) }
            else { Self.startCampPending = false; requestCamp() }
        }
    }
    #endif

    // MARK: per fixed step

    /// Once per fixed step while the yard is up (after the wipe-in has started).
    func tickCamp(dt: Float) {
        for a in parkBook.actors { a.brain?.idleMood = .happy; a.brain?.sleepLocked = true }
    }

    // MARK: the world swaps (under the white)

    func campSwap(_ dest: ParkTrip.Dest) {
        let book = parkBook, work = book.work
        let roster = book.roster
        switch dest {
        case .park:
            work.homes = [:]; work.autonomy = [:]; work.arena = [:]; work.owed = [:]; work.giftState = 0; work.saveT = 0; work.friendSession = [:]; work.shared.reset()
            work.ownToys = []; work.hopHost = nil
            book.comers = []; book.cast = []          // nobody comes along: every home body is hidden (`parkHides`)
            for a in roster {
                guard let brain = a.brain else { continue }
                work.homes[a.id] = a.floor; work.autonomy[a.id] = autonomySnapshot(a.id, brain); work.arena[a.id] = a.sim.arenaRadius
                if brain.isSleeping { continue }          // a sleeper stays exactly as it is
                brain.abortAll(a.sim, a.skinner)
                brain.commandedIdle = nil; brain.commandedDecor = nil; brain.commandedFlip = false
            }
            RoomLayout.apply(RoomCatalog.camp)
            GameCamera.configureCamp()
            if GameCamera.refreshRoam(aspect: GameCamera.aspect) != nil {
                for a in roster where a.sim.arenaRadius.isFinite { a.sim.arenaCenter = GameCamera.arenaCenter; a.sim.arenaRadius = GameCamera.arenaRadius }
            }
            syncDecor()
            book.actors = []
            if select.phase != .none { select.cancel() }
            park.card = nil
        case .home:
            book.clear?()
            book.actors = []; book.cast = []
            RoomLayout.apply(RoomCatalog.def(store.currentRoom))
            GameCamera.endPark(count: max(jellies.count, 1))
            if GameCamera.refreshRoam(aspect: GameCamera.aspect) != nil {
                for a in roster where (work.arena[a.id] ?? a.sim.arenaRadius).isFinite { a.sim.arenaCenter = GameCamera.arenaCenter; a.sim.arenaRadius = GameCamera.arenaRadius }
            }
            syncDecor()
            for a in roster {
                guard let brain = a.brain else { continue }
                brain.autonomy = work.autonomy[a.id] ?? true
                brain.idleBlocked = false
                if brain.isSleeping { continue }          // (asleep at home through the whole visit: not moved, not woken)
                if let spot = work.homes[a.id] { rehome(a, at: brain.fixed(spot)) }
                brain.restTimer = 2
            }
            work.homes = [:]; work.autonomy = [:]; work.arena = [:]; work.owed = [:]
            book.comers = []
            park.card = nil
        }
    }
}
