//
//  WalkBoard.swift
//  move-board-r1 (movement plan, work order 1): the shared "walk board". Every creature PUBLISHES its movement intent here (where it is, where it is going, how fast it
//  really walks, which standing spot it claims, whether it is choreographed). In this order NOTHING READS the board: later orders (the step chooser, the arrival slots, the
//  floor-idleness scheduler) will. There is ONE instance per stage (MelonController.walkBoard, injected into every brain beside `peers`; the headless Lab owns its own), never a static.
//  The board code draws no random numbers and writes no game state. Switch for the proof only: `WalkBoard.publishOn` (env WALKBOARD_OFF=1 = false).
//

import Foundation
import simd

struct WalkIntent {
    enum State { case walking, standing, fixed }          // fixed = cannot step aside: sleeping, lying, perched on a toy, held, inside a session hold
    var id: Int = 0                                       // the brain's steerID
    var state: State = .standing
    var pos: SIMD2<Float> = .zero, yaw: Float = 0
    var points: [SIMD2<Float>] = []                       // the remaining route: queued waypoints, then the walk's final target (at most 4)
    var speed: Float = 0                                  // the REAL speed of the current gait, u/s (`roomWalkSpeed`)
    var slot: SIMD2<Float>?                               // the standing spot this body claims (a walker: its final target; a stander: where it stands)
    var slotHold: Float = 0                               // seconds the claim lasts after arrival (0 = unknown)
    var priority: Int = 1                                 // 3 = job / requested / commanded / meal, 2 = social, 1 = autonomous roam
    var owned: Bool = false                               // choreographed: never to be steered by generic avoidance
    var partners: Set<Int> = []                           // ids avoidance must be OFF against
    var stamp: Float = 0                                  // board time of the publish
    nonisolated init() {}
}

final class WalkBoard {
    /// The proof's kill switch: false = nothing is published (TEST_RUNNER_WALKBOARD_OFF=1 reaches the test host as WALKBOARD_OFF=1).
    nonisolated(unsafe) static var publishOn: Bool = ProcessInfo.processInfo.environment["WALKBOARD_OFF"] != "1"
    static let maxPoints = 4
    static let maxID = 64
    static let staleAfter: Float = 0.5
    static let idleCap: Float = 60
    static let gridN = 6

    nonisolated init() {}
    /// The board's own game clock: the stage / Lab advance it once per fixed step (a brain's clock stops when it is disabled).
    private(set) var now: Float = 0
    private var slots: [WalkIntent?] = []
    private var cells = [Float](repeating: -.infinity, count: WalkBoard.gridN * WalkBoard.gridN)
    private var lo = SIMD2<Float>(-3, -3), hi = SIMD2<Float>(3, 3)
    private var floorTick = 0

    func advance(dt: Float) {
        now += dt
        floorTick -= 1
        if floorTick <= 0 { floorTick = 60; refreshFloor() }
    }

    /// The grid follows the floor that is live: the roam polygon's bounds (home), else the roam rectangle (park / fallback). A new floor clears the cells.
    private func refreshFloor() {
        let b = GameCamera.roamFloor?.bounds ?? GameCamera.roamRect
        if b.min != lo || b.max != hi { lo = b.min; hi = b.max; for i in 0..<cells.count { cells[i] = -.infinity } }
    }

    // MARK: intents

    /// Copies into the board's own slot (arrays and sets are copied element by element, in place: no allocation in the steady state).
    func publish(_ i: WalkIntent) {
        guard i.id >= 0, i.id < Self.maxID else { return }
        while slots.count <= i.id { slots.append(nil) }
        if slots[i.id] == nil { slots[i.id] = WalkIntent(); slots[i.id]!.points.reserveCapacity(Self.maxPoints) }
        slots[i.id]!.copy(from: i)
    }
    func intent(_ id: Int) -> WalkIntent? { id >= 0 && id < slots.count ? slots[id] : nil }
    var all: [WalkIntent] { slots.compactMap { $0 } }

    /// Where the body will be `t` seconds from `now`: along `points` at `speed` from the published position (advanced by `now - stamp`), then standing at the last point.
    /// A standing / fixed body, or an intent older than 0.5 s, stays at its published position.
    func position(of id: Int, after t: Float, now: Float) -> SIMD2<Float>? {
        guard let i = intent(id) else { return nil }
        let age = max(0, now - i.stamp)
        guard i.state == .walking, !i.points.isEmpty, age <= Self.staleAfter else { return i.pos }
        var left = max(0, age + t) * i.speed
        var p = i.pos
        for q in i.points {
            let d = simd_distance(p, q)
            if d >= left { return d > 1e-5 ? p + (q - p) * (left / d) : q }
            left -= d; p = q
        }
        return p
    }
    func position(of id: Int, after t: Float) -> SIMD2<Float>? { position(of: id, after: t, now: now) }

    /// Some other body claims a standing spot within `radius` of `p`.
    func claimed(near p: SIMD2<Float>, radius: Float, except id: Int) -> Bool {
        for case let i? in slots where i.id != id { if let s = i.slot, simd_distance(s, p) < radius { return true } }
        return false
    }

    func remove(_ id: Int) { if id >= 0, id < slots.count { slots[id] = nil } }
    /// Drops every entry with an id of `n` or more (a visitor left, the roster shrank).
    func prune(fromID n: Int) { if n < slots.count { for k in max(n, 0)..<slots.count { slots[k] = nil } } }
    func reset() { slots.removeAll(); for i in 0..<cells.count { cells[i] = -.infinity }; now = 0; floorTick = 0 }

    // MARK: floor idleness (6 x 6 cells over the live floor)

    private func cell(_ p: SIMD2<Float>) -> Int {
        let n = Float(Self.gridN), s = hi - lo
        let u = min(max((p.x - lo.x) / max(s.x, 0.01), 0), 0.9999), v = min(max((p.y - lo.y) / max(s.y, 0.01), 0), 0.9999)
        return Int(v * n) * Self.gridN + Int(u * n)
    }
    func noteBody(at p: SIMD2<Float>, now: Float) { cells[cell(p)] = now }
    /// Seconds since a body centre was last in the cell holding `p`, capped at 60.
    func idleness(at p: SIMD2<Float>, now: Float) -> Float { min(Self.idleCap, max(0, now - cells[cell(p)])) }
}

private extension WalkIntent {
    mutating func copy(from o: WalkIntent) {
        id = o.id; state = o.state; pos = o.pos; yaw = o.yaw; speed = o.speed; slot = o.slot; slotHold = o.slotHold
        priority = o.priority; owned = o.owned; stamp = o.stamp
        points.removeAll(keepingCapacity: true); for p in o.points { points.append(p) }
        if partners != o.partners { partners.removeAll(keepingCapacity: true); for p in o.partners { partners.insert(p) } }
    }
}

// MARK: the brain's side: what it publishes (pure reads of state it already has; no random numbers, nothing written back)

extension BlobBrain {
    /// Fills `boardIntent` (reused: no allocation) from the brain's current state and hands it to the board. `pos` = the body's floor position.
    func publishToBoard(pos: SIMD2<Float>) {
        guard WalkBoard.publishOn, let board else { return }
        boardIntent.id = steerID; boardIntent.pos = pos; boardIntent.yaw = yaw; boardIntent.stamp = board.now
        boardIntent.points.removeAll(keepingCapacity: true)
        boardIntent.partners.removeAll(keepingCapacity: true)
        let session: SocialSession? = (social?.end == nil) ? social : nil
        var then: After = .none
        if case .walk(let target, let after) = script {
            boardIntent.state = .walking; then = after
            var n = 0
            for w in route where n < WalkBoard.maxPoints - 1 { boardIntent.points.append(w); n += 1 }
            boardIntent.points.append(target)
            boardIntent.speed = roomWalkSpeed
            boardIntent.slot = target
        } else {
            boardIntent.state = (isSleeping || isPerched || (session != nil && socialBook.hold)) ? .fixed : .standing
            boardIntent.speed = 0
            boardIntent.slot = pos
        }
        boardIntent.slotHold = 0
        var prio = 1
        if session != nil { prio = 2 }
        if job != nil || commanded || pending != nil { prio = 3 }
        switch then { case .eat, .doEat, .dineTurn, .dineGo: prio = 3; default: break }
        boardIntent.priority = prio
        boardIntent.owned = race.active || stanceStepFree || (session != nil && (session!.choreo || inCloseSocial))
        if let s = session {
            if s.idA >= 0, s.idA != steerID { boardIntent.partners.insert(s.idA) }
            if s.idB >= 0, s.idB != steerID { boardIntent.partners.insert(s.idB) }
            if s.idC >= 0, s.idC != steerID { boardIntent.partners.insert(s.idC) }
            if s.kind.isGroup { for id in s.crewIDs where id >= 0 && id != steerID { boardIntent.partners.insert(id) } }
        }
        board.publish(boardIntent)
    }
}

extension WalkBoard {
    /// The regular peer publish, one body: a body that is not walking publishes here (a walker publishes at its walk's start and once per step); every body notes the cell it is in.
    func tickBody(_ b: BlobBrain, pos: SIMD2<Float>) {
        guard WalkBoard.publishOn else { return }
        if !b.isWalkScript { b.publishToBoard(pos: pos) }
        noteBody(at: pos, now: now)
    }
}
