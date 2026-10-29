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
    struct Approach { var requested = false; var age: Float = 0; var calm: Float = 0; var retries = 0; var short = 0; var hopped = false }
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
    /// The close-up was asked for by the "Train" button: the trick book opens on arrival (`training` stays true for the rest of that close-up).
    var trainPending = false
    var training = false

    func begin(ids new: [Int], front: Int? = nil) {
        ids = new; arrived = []; saved = [:]; approach = [:]; came = []; evictT = [:]; koCache = nil; trainPending = false; training = false; touchID = new.first ?? 0; touchAnchor = nil; petOwed = 0; petClock = 0
        spots = [:]
        if new.count > 1 {
            let offs = GameCamera.focusRowSpots(count: new.count, anchor: .zero)
            let row = GameCamera.focusRowSpots(count: new.count, anchor: FreeFloor.nearest(to: GameCamera.callSpot, all: offs))
            let order = (front.flatMap { f in new.contains(f) ? f : nil } ?? new[0])
            for (k, id) in ([order] + new.filter { $0 != order }).enumerated() { spots[id] = row[k] }
            GameCamera.focusSpots = new.map { spots[$0]! }
        } else {
            let free = FreeFloor.nearest(to: GameCamera.callSpot)          // (decor may cover the usual spot)
            for id in new { spots[id] = free }
            GameCamera.focusSpots = new.isEmpty ? [] : [free]
        }
        rowOpen = new.count > 1
    }

    /// One Jelly has reached his spot; true when the last one has (the camera may go in).
    func markArrived(_ id: Int) -> Bool {
        arrived.insert(id)
        return ids.allSatisfy { arrived.contains($0) }
    }

    func clear() {
        ids = []; spots = [:]; arrived = []; saved = [:]; approach = [:]; evictT = [:]; koCache = nil; trainPending = false; training = false; rowOpen = false; touchAnchor = nil; touchID = 0
        GameCamera.focusSpots = []
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
        greeting = false
        select.cancel()
        // a close-up that has just ended hands the paused Jellies' wandering back one brain per step (`driveFocus`); a call landing inside that window used
        // to wipe `saved` in `begin` and leave them with autonomy off for good (2026-10-21: "the other ones are stuck"). Hand it back here first.
        for (id, a) in focusGroup.saved { brainFor(id)?.autonomy = a }
        focusGroup.begin(ids: ids, front: front)
        focus.beginApproach()
        approachIdle = 0; approachRetries = 0; approachShort = 0
        if ids.contains(0) { queued = [.come(to: focusGroup.spot(of: 0))] }
    }

    /// The close-up's per-step work for Jelly `id` (Jelly 0 from `tick`, the others from `tickOthers`): pause the Jellies that are not in it,
    /// run the ones that are to their spots, hop them when it ends, and credit the petting to the one being petted.
    func driveFocus(id: Int, brain: BlobBrain, sim: SoftBody?, dt: Float) {
        let g = focusGroup
        guard !g.ids.isEmpty || !g.saved.isEmpty else { return }
        let phase = focus.phase
        if phase == .roaming {                     // over: hand the wandering back, then forget the group once everybody has
            if let a = g.saved.removeValue(forKey: id) { brain.autonomy = a }
            if id != 0 { brain.onFinished = nil }
            if g.saved.isEmpty { g.clear() }
            return
        }
        guard g.ids.contains(id) else {            // not in it: he keeps his life; if he stands in the camera's wedge he walks out of it (W2: the others are neither frozen nor hidden)
            evictFromKeepOut(id: id, brain: brain, dt: dt)
            return
        }
        if phase == .focused, g.trainPending, g.arrived.contains(id) { g.trainPending = false; g.training = true; voice.startTrain(subject: id) }          // (the "Train" button's close-up: the Train card starts on arrival)
        guard id != 0 else { return }              // Jelly 0's own path is tickFocus
        var s = g.approach[id] ?? FocusGroup.Approach()
        defer { g.approach[id] = s }
        switch phase {
        case .approaching:
            if g.arrived.contains(id) { return }
            if !s.requested {
                s.requested = true; s.age = 0
                brain.onFinished = { [weak g] r in if case .come = r { g?.came.insert(id) } }
                brain.requestNow(.come(to: g.spot(of: id)))
                return
            }
            s.age += dt
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
                    if g.markArrived(id) { focus.arrive(); AudioHub.shared.chirp(jelly: id, .happy) }
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
