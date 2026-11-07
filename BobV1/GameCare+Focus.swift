//
//  GameCare+Focus.swift
//  "Come here" for ANY Jelly, and for everyone at once.
//  `comeHere(jelly:)`: that Jelly runs to the front spot and the close-up frames him; the others keep roaming, out of the camera's way (GameCare+FocusKeepOut.swift).
//  `comeHere(jellies:)`: the several named run to a row, the others keep roaming. `comeHereEveryone()`: all of them run to a row on the front line and the close-up widens to frame the row.
//  Jelly 0 keeps his own path in GameCare (the `queued` come, `tickFocus`); the others are driven here, once per fixed step (`driveFocus`).
//

import Foundation
import simd

/// Who the close-up is on, where each one stands, and the small per-Jelly bookkeeping of the approach and the touch.
@MainActor
final class FocusGroup {
    /// The Jellies the close-up is on (sorted ids). Empty = no focus has been asked for (or it is over).
    private(set) var ids: [Int] = []
    /// Their spots (x, z), by id.
    private(set) var spots: [Int: SIMD2<Float>] = [:]
    private(set) var arrived: Set<Int> = []
    /// Autonomy to hand back (Jellies whose wandering the focus paused), by id.
    var saved: [Int: Bool] = [:]
    /// The steering gap each row member had before the line-up (he keeps only the row's gap from the others while it is on: the slots are 1.15 apart, the room's gap is 1.4).
    var gapSaved: [Int: Float] = [:]
    static let rowSteerGap: Float = 1.05
    struct Approach { var requested = false; var age: Float = 0; var calm: Float = 0; var retries = 0; var short = 0; var hopped = false; var onSlot: Float = 0 }
    /// A come walk that ended SHORT of the spot (someone stood on it and the floor rules dragged the target over the gap: he turned to wave 1.4 u early) is
    /// re-asked at once, this many times at most, while the stander steps aside (`MelonController.clearWay`); not counted against the calm retries.
    static let shortRetries = 6
    var approach: [Int: Approach] = [:]
    /// Jellies whose `.come` walk has just finished (reported by their brain).
    var came: Set<Int> = []
    /// The Jelly under the finger in the close-up (set by the stage); his centroid anchors the hearts (`touchAnchor`).
    var touchID = 0
    var touchAnchor: SIMD3<Float>?
    /// Pet attention not yet credited to a non-Bob Jelly (credited in chunks so a saving profile does not write every step).
    var petOwed: Float = 0
    var petClock: Float = 0

    nonisolated deinit {}

    var isRow: Bool { ids.count > 1 }
    /// Jelly 0 is part of this focus (also true when no focus was asked for: the one-Jelly game and the old tests).
    func includes(_ id: Int) -> Bool { ids.isEmpty || ids.contains(id) }
    func spot(of id: Int) -> SIMD2<Float> { spots[id] ?? GameCamera.callSpot }
    /// The floor's visible sides do not hold the wide row: while it is on, the brains may walk past them.
    var rowOpen = false
    /// The keep-out wedge for the current close-up (GameCare+FocusKeepOut.swift), cached per aspect / group, and the walk-out request clocks.
    var koCache: FocusKeepOut?
    var koAspect: Float = 0
    var koKey: [Int] = []
    var evictT: [Int: Float] = [:]
    /// Seconds since the walk began, the Jelly who stands in the middle (he goes first: nobody has to pass between two standing ones), and Jelly 0's walk held back for him.
    var clock: Float = 0
    var front = 0
    var zeroPending = false
    /// Smart line-up: the row's slots (0 = the middle), who has which, who is settled (within `Lineup.commitDistance` of his slot, or arrived), and the re-plan clock.
    private(set) var slots: [SIMD2<Float>] = []
    private(set) var slotOf: [Int: Int] = [:]
    private var committed: Set<Int> = []
    private var replanClock: Float = 0
    private(set) var replans = 0
    /// The line-up is never stuck: after `softAccept` seconds a Jelly within `nearEnough` of his spot is taken as arrived where he stands, after `hardAccept` anyone is.
    nonisolated(unsafe) static var softAccept: Float = 5.5, hardAccept: Float = 8
    static let nearEnough: Float = 1.5, sidesWait: Float = 1.5
    /// Members the safety net had to accept where they stood (tests: a line-up that works needs none).
    var netAccepted = 0
    /// A side Jelly may set off once the middle one is (nearly) there, or after `sidesWait` seconds.
    func mayGo(_ id: Int, frontDistance: Float?) -> Bool {
        id == front || ids.count < 3 || arrived.contains(front) || clock > Self.sidesWait || (frontDistance ?? 99) < 2.4
    }

    func begin(ids new: [Int], front frontAsked: Int? = nil, floors: [Int: SIMD2<Float>] = [:]) {
        ids = new; arrived = []; clock = 0; netAccepted = 0; zeroPending = false; front = frontAsked.flatMap { new.contains($0) ? $0 : nil } ?? new.first ?? 0; saved = [:]; gapSaved = [:]; approach = [:]; came = []; evictT = [:]; koCache = nil; touchID = new.first ?? 0; touchAnchor = nil; petOwed = 0; petClock = 0
        spots = [:]; GameCamera.focusFramed = []
        if new.count > 1 {
            let offs = GameCamera.focusRowSpots(count: new.count, anchor: .zero)
            let row = GameCamera.focusRowSpots(count: new.count, anchor: FreeFloor.nearest(to: GameCamera.callSpot, all: offs))
            // no fixed spot per Jelly: whoever is nearest the middle takes it, the others the free slot on their side (`Lineup`), re-read while they come (`replan`)
            slots = row; slotOf = [:]; committed = []; replanClock = 0; replans = 0
            if floors.count == new.count {
                let plan = Lineup.best(from: new.map { floors[$0]! }, slots: row, locked: [Int?](repeating: nil, count: new.count), centre: 0)
                for (i, id) in new.enumerated() { slotOf[id] = plan[i] }
                front = new.first { slotOf[$0] == 0 } ?? front
            } else {
                let order = front
                for (k, id) in ([order] + new.filter { $0 != order }).enumerated() { slotOf[id] = k }
            }
            for id in new { spots[id] = row[slotOf[id]!] }
            GameCamera.focusSpots = new.map { spots[$0]! }
        } else {
            let free = FreeFloor.nearest(to: GameCamera.callSpot)          // (decor may cover the usual spot)
            for id in new { spots[id] = free }
            GameCamera.focusSpots = new.isEmpty ? [] : [free]
        }
        rowOpen = new.count > 1
    }

    /// Smart line-up, once per fixed step while approaching: settle whoever is near his slot, re-plan the rest. Returns the Jellies whose spot changed.
    func replan(dt: Float, floors: [Int: SIMD2<Float>]) -> [Int] {
        replanClock += dt
        guard ids.count > 1, slots.count == ids.count, replanClock >= Lineup.period else { return [] }
        replanClock = 0
        for id in ids where !committed.contains(id) {
            if arrived.contains(id) || (floors[id].map { simd_distance($0, spot(of: id)) < Lineup.commitDistance } ?? false) { committed.insert(id) }
        }
        guard committed.count < ids.count, ids.allSatisfy({ floors[$0] != nil }) else { return [] }
        let plan = Lineup.best(from: ids.map { floors[$0]! }, slots: slots, locked: ids.map { committed.contains($0) ? slotOf[$0] : nil }, centre: 0, current: ids.map { slotOf[$0] ?? -1 })
        var changed: [Int] = []
        for (i, id) in ids.enumerated() where slotOf[id] != plan[i] && !committed.contains(id) { slotOf[id] = plan[i]; spots[id] = slots[plan[i]]; changed.append(id); replans += 1 }
        if !changed.isEmpty {
            front = ids.first { slotOf[$0] == 0 } ?? front
            GameCamera.focusSpots = ids.map { spots[$0]! }
        }
        return changed
    }

    /// One Jelly has reached his spot; true when the last one has (the camera may go in).
    func markArrived(_ id: Int) -> Bool {
        arrived.insert(id)
        return ids.allSatisfy { arrived.contains($0) }
    }

    func clear() {
        ids = []; spots = [:]; slots = []; slotOf = [:]; committed = []; arrived = []; clock = 0; zeroPending = false; saved = [:]; approach = [:]; evictT = [:]; koCache = nil; rowOpen = false; touchAnchor = nil; touchID = 0
        GameCamera.focusSpots = []; GameCamera.focusFramed = []
    }
}

extension GameCare {
    /// The Jellies the close-up is on right now (empty while roaming). In a one-Jelly game this is `[0]` during a close-up.
    var focusedJellies: [Int] { focus.isActive ? focusGroup.ids : [] }

    /// The Jelly the touch goes to in the close-up (the one under the finger; the first focused one until a finger picks another).
    var touchPlayTarget: Int { focusGroup.touchID }

    /// Where a focused Jelly stands in the close-up.
    func focusSpot(for id: Int) -> SIMD2<Float> { focusGroup.spot(of: id) }

    /// "Everyone, come here": all of them run up side by side and the close-up frames the row.
    func comeHereEveryone() { beginFocus(ids: Array(0..<max(jellies.count, 1)), front: targetJelly) }

    /// "Pip and Moss, come here": just those run to the front row (the first named stands in front); the others keep roaming.
    func comeHere(jellies ids: [Int]) { beginFocus(ids: ids, front: ids.first) }

    func beginFocus(ids requested: [Int], front: Int? = nil) {
        guard focus.phase == .roaming, !bath.active, !tripActive else { return }
        var ids = Array(Set(requested.filter { jellies.indices.contains($0) })).sorted()
        if ids.isEmpty { ids = [0] }                  // an id outside the roster (a selection of a Jelly this game does not have): Bob
        for id in ids { AudioHub.shared.contextVoice(jelly: id, .mmhmm, chance: 0.5) }          // (the player called)
        greeting = false
        select.cancel()
        // a close-up that has just ended hands the paused Jellies' wandering back one brain per step (`driveFocus`); a call landing inside that window used
        // to wipe `saved` in `begin` and leave them with autonomy off for good (2026-10-21: "the other ones are stuck"). Hand it back here first.
        for (id, a) in focusGroup.saved { brainFor(id)?.autonomy = a }
        focusGroup.begin(ids: ids, front: front, floors: Dictionary(uniqueKeysWithValues: ids.compactMap { id in floorOf(id).map { (id, $0) } }))
        if ids.count > 1 { for id in ids { if let b = brainFor(id) { focusGroup.gapSaved[id] = b.peerGap; b.peerGap = min(b.peerGap, FocusGroup.rowSteerGap) } } }
        focus.beginApproach()
        approachIdle = 0; approachRetries = 0; approachShort = 0
        if ids.contains(0) {
            if focusGroup.mayGo(0, frontDistance: nil) { queued = [.come(to: focusGroup.spot(of: 0))] } else { focusGroup.zeroPending = true }
        }
    }

    /// Where Jelly `id` stands on the floor now (nil = not in the room).
    func floorOf(_ id: Int) -> SIMD2<Float>? {
        guard let b = brainFor(id) else { return nil }
        return Self.floorPos(b, id == 0 ? lastSim : bathPlug.actors[id]?.actor?.sim)
    }

    /// Smart line-up: re-plan who takes which slot while they come, and send the ones whose slot changed to the new one.
    func focusReplan(dt: Float) {
        let g = focusGroup
        guard focus.phase == .approaching, g.isRow else { return }
        var floors: [Int: SIMD2<Float>] = [:]
        for id in g.ids { if let f = floorOf(id) { floors[id] = f } }
        for id in g.replan(dt: dt, floors: floors) {
            if id == 0 {
                if !g.zeroPending { queued = [.come(to: g.spot(of: 0))]; approachIdle = 0 }
            } else if g.approach[id]?.requested == true, let b = brainFor(id) {
                g.approach[id]?.age = 0; g.approach[id]?.short = 0
                b.requestNow(.come(to: g.spot(of: id)))
            }
        }
    }

    /// The group close-up frames the bodies where they REALLY stand (eased, so a sway or a settle never jitters the camera), not the slots they were sent to.
    func focusFrame(dt: Float) {
        let g = focusGroup
        guard g.ids.count > 1, focus.phase == .focused else { return }          // (frozen while leaving: the camera eases out on the last frame)
        let now = g.ids.map { floorOf($0) ?? g.spot(of: $0) }
        if GameCamera.focusFramed.count != now.count { GameCamera.focusFramed = g.ids.map { g.spot(of: $0) } }
        let k = 1 - expf(-dt * 2.5)
        for i in now.indices { GameCamera.focusFramed[i] += (now[i] - GameCamera.focusFramed[i]) * k }
    }

    /// Distance of the middle Jelly from his spot (nil = he is the asker or gone).
    func frontDistance(except id: Int) -> Float? {
        let g = focusGroup
        guard g.front != id, let b = brainFor(g.front) else { return nil }
        return simd_length(Self.floorPos(b, g.front == 0 ? lastSim : bathPlug.actors[g.front]?.actor?.sim) - g.spot(of: g.front))
    }

    /// Never stuck: past `softAccept` seconds a Jelly near his spot, past `hardAccept` anyone, is accepted where he stands so the line-up completes
    /// (a body pinned between two standing ones, pushed by the separation rule, never "arrives"). Called once per fixed step from `tickFocus`.
    func focusSafetyNet(dt: Float) {
        let g = focusGroup
        guard focus.phase == .approaching, !g.ids.isEmpty else { return }
        g.clock += dt
        guard g.clock > min(FocusGroup.softAccept, FocusGroup.hardAccept) else { return }
        for id in g.ids where !g.arrived.contains(id) {
            guard let b = brainFor(id) else { if g.markArrived(id) { focus.arrive() }; continue }
            let sim = id == 0 ? lastSim : bathPlug.actors[id]?.actor?.sim
            let d = simd_length(Self.floorPos(b, sim) - g.spot(of: id))
            guard d < FocusGroup.nearEnough || g.clock > FocusGroup.hardAccept else { continue }
            b.pending = nil; b.interruptScript = true; g.netAccepted += 1
            if id == 0 {
                queued.removeAll { if case .come = $0 { return true }; return false }; callRunning = false
                g.zeroPending = false
                enterFocus(brain: b)
            } else {
                g.saved[id] = b.autonomy; b.autonomy = false; b.onFinished = nil
                if g.markArrived(id) { focus.arrive(); AudioHub.shared.chirp(jelly: id, .happy, src: "group") }
            }
            if !focus.isActive { return }
        }
    }

    /// The close-up's per-step work for Jelly `id` (Jelly 0 from `tick`, the others from `tickOthers`): pause the Jellies that are not in it,
    /// run the ones that are to their spots, hop them when it ends, and credit the petting to the one being petted.
    func driveFocus(id: Int, brain: BlobBrain, sim: SoftBody?, dt: Float) {
        let g = focusGroup
        guard !g.ids.isEmpty || !g.saved.isEmpty else { return }
        let phase = focus.phase
        if phase == .roaming {                     // over: hand the wandering back, then forget the group once everybody has
            if let a = g.saved.removeValue(forKey: id) { brain.autonomy = a }
            if let gp = g.gapSaved.removeValue(forKey: id) { brain.peerGap = gp }
            if id != 0 { brain.onFinished = nil }
            if g.saved.isEmpty { g.clear() }
            return
        }
        guard g.ids.contains(id) else {            // not in it: he keeps his life; if he stands in the camera's wedge he walks out of it (W2: the others are neither frozen nor hidden)
            evictFromKeepOut(id: id, brain: brain, dt: dt)
            return
        }
        guard id != 0 else { return }              // Jelly 0's own path is tickFocus
        var s = g.approach[id] ?? FocusGroup.Approach()
        defer { g.approach[id] = s }
        switch phase {
        case .approaching:
            if g.arrived.contains(id) { return }
            if !s.requested {
                guard g.mayGo(id, frontDistance: frontDistance(except: id)) else { return }
                s.requested = true; s.age = 0
                brain.onFinished = { [weak g] r in if case .come = r { g?.came.insert(id) } }
                brain.requestNow(.come(to: g.spot(of: id)))
                return
            }
            s.age += dt
            // standing on his slot and still = arrived (the turn and the wave play AFTER arrival, they do not gate it)
            if simd_length(Self.floorPos(brain, sim) - g.spot(of: id)) < 0.25 { s.onSlot += dt } else { s.onSlot = 0 }
            if s.onSlot > 0.3 {
                g.saved[id] = brain.autonomy; brain.autonomy = false; brain.onFinished = nil
                if g.markArrived(id) { focus.arrive(); AudioHub.shared.chirp(jelly: id, .happy, src: "group") }
                return
            }
            let act = brain.activity
            let calm = act == .idle || act == .lookingAround || act == .steppingInPlace
            s.calm = (calm && s.age > 0.5) ? s.calm + dt : 0
            // the walk is over (he is turning / waving) but short of the spot: ask again now, the spot re-reads the floor once the stander has moved
            if s.age > 0.3, brain.isCome, !brain.isWalkScript, s.short < FocusGroup.shortRetries, simd_length(Self.floorPos(brain, sim) - g.spot(of: id)) > 0.5 {
                s.short += 1; s.age = 0; g.came.remove(id); brain.requestNow(.come(to: g.spot(of: id))); return
            }
            if g.came.contains(id) || s.calm > 0.3 {
                s.calm = 0; g.came.remove(id)
                let here = Self.floorPos(brain, sim)
                if simd_length(here - g.spot(of: id)) < 0.5 {
                    g.saved[id] = brain.autonomy; brain.autonomy = false
                    brain.onFinished = nil
                    if g.markArrived(id) { focus.arrive(); AudioHub.shared.chirp(jelly: id, .happy, src: "group") }
                } else if s.retries < 2 { s.retries += 1; s.age = 0; brain.requestNow(.come(to: g.spot(of: id))) }
                else { focus.cancelApproach() }
            }
        case .focused:
            if id == g.touchID, let tp = touchPlay {                 // petting Pip fills Pip's attention (Bob's goes through tickNeeds)
                let petting = tp.contact && tp.speed > TouchPlay.strokeSpeed * 0.5
                if petting || tp.isPurring { g.petOwed += dt * (tp.isPurring ? NeedsTuning.purrRate : NeedsTuning.petRate) }
            }
            g.petClock += dt
            if g.petClock >= 0.5 {
                g.petClock = 0
                if g.petOwed > 0 { needs(for: g.touchID).gain(.attention, g.petOwed); g.petOwed = 0 }
            }
        case .leaving:
            if !s.hopped {
                s.hopped = true
                if let a = g.saved.removeValue(forKey: id) { brain.autonomy = a }
                if let sim { brain.startHopPlay(sim: sim, distance: 0.25) }
            }
        default: break
        }
    }
}
