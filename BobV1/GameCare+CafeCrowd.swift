//
//  GameCare+CafeCrowd.swift
//  cafe-busy-r1: the café's other customers on their bodies (the schedule is Cafe/CafeCrowd.swift). Park-visitor bodies, made once per visit as a pool of four, parked far off the floor
//  until their group's turn. 1-2 tables are already seated when the player arrives; every 20...45 s a group (a pair or one customer) walks in from the entrance side with a soft door bell,
//  picks a free table, sits with a cup, stays 40...90 s and leaves the same way (the bell again). One group walks at a time, paths go round every seated body and table, followers wait
//  until the one ahead is 1.6 u away. A seated pair talks in place with the shared conversation (quiet voices); a single customer just sits. No customer ever uses the player's table.
//  Nothing new is persisted. Dev aids (dev arguments only): `-CafeSeed n`, `-CafeTable k` (the player's table), `-CafeCalmOff 1` (the old after-the-meal behaviour, for the A/B).
//

import Foundation
import simd

/// A customers' table of this visit: the ends table, two places facing each other (the far one first), and what sits at it.
final class CafeCustomerTable {
    let slot: Int
    let centre: SIMD2<Float>
    let table: DiningSet
    var stands: [SIMD2<Float>] = [], yaws: [Float] = [], placeOf: [Int] = []
    var door: SIMD2<Float> = .zero
    /// 2 = a pair may sit (both ends reachable at the keep-apart gap), 1 = one customer at the near end, 0 = unused this visit.
    var capacity = 2
    init(slot: Int, centre: SIMD2<Float>, table: DiningSet) { self.slot = slot; self.centre = centre; self.table = table }
    nonisolated deinit {}
}

final class CafeMember {
    enum State { case waiting, walking, seated, out }
    let actor: JellyActor
    let visitor: ParkVisitor
    var index: Int
    var state: State = .waiting
    var path: [SIMD2<Float>] = []
    var stuck: Float = 0
    var waitT: Float = 0
    var replan = false, replans = 0
    /// The waypoint last handed to goTo and how long ago; walks of the proximity guard.
    var reqWp: SIMD2<Float>?
    var reqT: Float = 0
    var guards = 0
    var guardAt: Float = -9
    /// The room's own resolve while the walk runs on the open (side-less) one; when the walk began; how long he has been (nearly) standing mid-route; stops counted.
    var savedResolve: ((SIMD3<Float>, Float) -> SIMD3<Float>)?
    var startedAt: Float = -9
    var slowT: Float = 0
    var slowCounted = false
    var prevPos: SIMD2<Float> = .zero
    var nudges = 0, spawn: SIMD2<Float> = .zero
    var warm = false, idleT: Float = 0
    var lastPos: SIMD2<Float> = .zero
    var held = false
    init(actor: JellyActor, visitor: ParkVisitor, index: Int) { self.actor = actor; self.visitor = visitor; self.index = index }
    nonisolated deinit {}
}

final class CafeLiveGroup {
    let id: Int
    let table: CafeCustomerTable
    var members: [CafeMember] = []
    var phase: CafeCrowdGroup.Phase
    var chat: CafeChatState
    var belled = false
    init(id: Int, table: CafeCustomerTable, phase: CafeCrowdGroup.Phase) { self.id = id; self.table = table; self.phase = phase; chat = CafeChatState(seed: UInt64(id) &* 0x9E3779B1 &+ 17) }
    nonisolated deinit {}
}

/// Everything the crowd keeps for one visit.
@MainActor
final class CafeCrowdState {
    var crowd: CafeCrowd?
    var tables: [CafeCustomerTable] = []
    var live: [Int: CafeLiveGroup] = [:]
    var pool: [CafeMember] = []
    var seed: UInt64 = 1
    var playerTable = -1
    var clock: Float = 0
    // numbers for the log and the proof
    var preseated = 0, entered = 0, left = 0, bells = 0, enterBells = 0, exitBells = 0, bellsPlayed = 0
    var minWalk: Float = .infinity, minAll: Float = .infinity, nextLog: Float = 0
    var tablesUsed: [Int] = []
    /// round 3: the closest approach split in two (a customer to the player's bodies / a customer to another customer), and the visible stops (speed under 0.15 u/s for 0.3 s mid-route).
    var minPlayer: Float = .infinity, minCust: Float = .infinity
    var hesitations = 0, guardReplans = 0
    func reset() { crowd = nil; tables = []; live = [:]; pool = []; clock = 0; preseated = 0; entered = 0; left = 0; bells = 0; bellsPlayed = 0; enterBells = 0; exitBells = 0; minWalk = .infinity; minAll = .infinity; nextLog = 0; tablesUsed = []; minPlayer = .infinity; minCust = .infinity; hesitations = 0; guardReplans = 0 }
    nonisolated deinit {}
}

extension CafeTuning {
    /// Customer bodies on screen at most (the player's own come on top: three + four = seven). Measured nowhere on a device yet.
    static let maxCustomerBodies = CafeCrowd.poolBodies
}

extension GameCare {
    /// A walking or seated customer keeps this far from every seated body: the room's keep-apart gap is `MelonController.jellyGap` (1.4), under which the stage pushes bodies apart and asks the free one to step aside,
    /// so a customer passing at 1.1 moved the player's Jelmiko (seen in the real app). 1.65 keeps every pass clear of that.
    static let crowdMinGap: Float = 1.65
    /// Dev capture aids.
    static var cafeSeedArg: UInt64? { DevArgs.enabled ? UserDefaults.standard.string(forKey: "CafeSeed").flatMap { UInt64($0) } : nil }
    static var cafeTableArg: Int? { DevArgs.enabled ? UserDefaults.standard.string(forKey: "CafeTable").flatMap { Int($0) } : nil }
    static var cafeCalmOff: Bool { DevArgs.enabled && UserDefaults.standard.integer(forKey: "CafeCalmOff") != 0 }

    /// The player's table for this visit: weighted from the candidates that are clear and on screen (`-CafeTable k` forces one). nil = none fits (the old first-clear fallback).
    static func cafePlayerTable(landscape: Bool, seed: UInt64, clear: (SIMD2<Float>) -> Bool) -> Int? {
        if let k = cafeTableArg, CafeTables.playerTables(landscape: landscape).indices.contains(k) { return k }
        var rng = CafeChatRNG(seed: seed &* 0xA24BAED4963EE407 &+ 3)
        return CafeTables.pickPlayer(landscape: landscape, roll: rng.next(), allowed: clear)
    }

    static func crowdLog(_ s: String) {
        #if targetEnvironment(simulator)
        NSLog("[cafecrowd] %@", s)
        #endif
    }

    /// The entrance, a whole body past the screen's right edge at depth `z` (the same off-screen rule as the home guest's exit: the visible half width at body height + 1.3).
    /// Landscape: the screen is much wider than the room (the right wall is ON screen, "off screen" would be 12 u away, outside the room), so there the entrance is the floor's right edge at the wall
    /// (4.5) - a door in that wall needs art; nothing is drawn.
    static func crowdEntry(z: Float) -> SIMD2<Float> {
        let off = GameCamera.visibleHalfWidthAtBody(z: z, aspect: GameCamera.aspect) + 1.3
        return SIMD2(GameCamera.aspect >= 1 ? min(off, 4.5) : off, z)
    }

    /// One customer table, set out at once and empty: places 1 and 2 of the ends table, the far one (from the entrance) first. nil when it does not fit the floor or crowds the player's table.
    func cafeMakeCustomerTable(slot: Int, at t: SIMD2<Float>, landscape: Bool) -> CafeCustomerTable? {
        let book = cafeBook
        let table = DiningSet()
        table.registersCollider = false
        table.tableSkin = { n in FoodMeshes.mesh(id: n == 3 ? "cafetable_ends" : "cafetable_\(n)") }
        let saved = (DiningLayout.ends, DiningLayout.sideX, DiningLayout.reachFood, DiningLayout.endsYaw)
        DiningLayout.ends = true; DiningLayout.sideX = Self.pairSideX; DiningLayout.reachFood = false; DiningLayout.endsYaw = DiningLayout.cafeEndsYaw
        AudioHub.hushTableSetup = true
        table.spawn(serving: CafePlate.emptyTable, n: 3, bobAt: SIMD2(99, 99), forcedOrigin: t)
        table.update(dt: 3); table.puffs.reset()
        AudioHub.hushTableSetup = false
        (DiningLayout.ends, DiningLayout.sideX, DiningLayout.reachFood, DiningLayout.endsYaw) = saved
        var ends = [1, 2].map { i -> (stand: SIMD2<Float>, yaw: Float) in
            let p = table.layout.places[i]
            return (t + p.rel + SIMD2(0, GameCare.eatCloser), p.yaw)
        }
        let player = Array(book.stands.values)
        let fits = ends.allSatisfy { e in
            player.allSatisfy { simd_distance($0, e.stand) >= Self.pairMargin } && simd_distance(e.stand, book.origin) >= 2.2
                && abs(e.stand.x) <= 4.0 && e.stand.y > -3.6 && e.stand.y < 2.2
                && !RoomCatalog.cafe.allBoxes.contains { b in abs(e.stand.x - b.centre.x) < b.halfExtents.x + 0.3 && abs(e.stand.y - b.centre.z) < b.halfExtents.z + 0.3 }
        }
        guard fits else { table.reset(); Self.crowdLog("table slot \(slot) at \(t) does not fit"); return nil }
        let door = Self.crowdEntry(z: CafeTables.door(landscape: landscape, table: t).y)          // (off screen, level with the table's entrance)
        ends.sort { simd_distance($0.stand, door) > simd_distance($1.stand, door) }          // (the first in takes the FAR end: the second never walks past the first)
        let ct = CafeCustomerTable(slot: slot, centre: t, table: table)
        ct.stands = ends.map(\.stand); ct.yaws = ends.map(\.yaw); ct.placeOf = ends.map { $0.yaw > 0 ? 1 : 2 }
        ct.door = door
        ct.capacity = CafeTables.capacity(table: t, stands: ct.stands, door: door, bodies: player, origin: book.origin, tables: CafeTables.customerTables(landscape: landscape), gap: Self.crowdMinGap)
        guard ct.capacity >= 1 else { table.reset(); Self.crowdLog("table slot \(slot) at \(t) has no clear way in (capacity 0)"); return nil }
        book.extraTables.append(table); book.extraFrames.append(nil)
        return ct
    }

    private func crowdDiscs(for group: CafeLiveGroup?, excluding me: CafeMember?, landscape: Bool) -> [CafeRoute.Disc] {
        let book = cafeBook, cs = book.crowd
        var d: [CafeRoute.Disc] = book.stands.values.map { .init(c: $0, r: Self.crowdMinGap) }
        d.append(.init(c: book.origin, r: 1.0))
        for t in cs.tables { d.append(.init(c: t.centre, r: 0.6)) }
        for g in cs.live.values {
            for m in g.members where m !== me && m.state == .seated {
                d.append(.init(c: Self.floorPos(m.actor.brain!, m.actor.sim), r: Self.crowdMinGap))
            }
        }
        return d
    }

    /// Where a customer waits, far off the floor.
    private func crowdParkSpot(_ k: Int) -> SIMD2<Float> { SIMD2(40 + Float(k) * 3, 0) }

    private func crowdBell(_ g: CafeLiveGroup, entering: Bool) {
        let before = AudioHub.shared._playLog
        AudioHub.shared.play(.cafeDoorBell)
        let cs = cafeBook.crowd
        if AudioHub.shared._playLog.last == SFX.cafeDoorBell.rawValue, AudioHub.shared._playLog != before { cs.bellsPlayed += 1 }          // (the played path: a muted / gated play never counts)
        cs.bells += 1; if entering { cs.enterBells += 1 } else { cs.exitBells += 1 }
        Self.crowdLog(String(format: "t=%.1f BELL %@ group %d (bells %d)", cs.clock, entering ? "in" : "out", g.id, cs.bells))
    }

    /// Once per step during the café (replaces the old regulars' tick).
    func tickCafeCrowd(_ actors: [JellyActor], dt: Float) {
        let book = cafeBook, cs = book.crowd
        let landscape = GameCamera.aspect >= 1
        // 1. make the pool and the tables once the world is ready
        if book.regularsPending {
            guard guestBook.actor == nil, parkBook.spawn != nil, !actors.isEmpty, actors.allSatisfy({ $0.brain != nil }) else { return }
            book.regularsPending = false
            cs.reset(); book.guests.reset()
            let cast = cafeRegularCast(count: CafeTuning.maxCustomerBodies)
            guard !cast.isEmpty, let bodies = parkBook.spawn?(cast, cast.indices.map { crowdParkSpot($0) }), bodies.count == cast.count else { return }
            parkBook.actors = bodies; parkBook.cast = cast.map(\.id)
            book.regulars = bodies; book.regularVisitors = cast
            for (k, (a, v)) in zip(bodies, cast).enumerated() {
                a.sim.arenaRadius = .infinity
                guard let b = a.brain else { continue }
                b.autonomy = false; b.idleBlocked = true
                cs.pool.append(CafeMember(actor: a, visitor: v, index: k))
            }
            for (i, c) in CafeTables.customerTables(landscape: landscape).enumerated() {
                if let t = cafeMakeCustomerTable(slot: i, at: c, landscape: landscape) { cs.tables.append(t) }
            }
            // the crowd indexes the tables that fit
            var crowd = CafeCrowd(slots: cs.tables.count, capacity: cs.tables.map(\.capacity), bodies: cs.pool.count, seed: cs.seed)
            for g in crowd.seatInitial() { cafeCrowdStart(g, seated: true, landscape: landscape) }
            cs.preseated = crowd.groups.count
            cs.crowd = crowd
            Self.crowdLog("visit seed=\(cs.seed) aspect=\(landscape ? "landscape" : "portrait") playerTable=\(cs.playerTable) at \(book.origin) tables=\(cs.tables.map { $0.centre }) preseated=\(cs.preseated) pool=\(cs.pool.count)")
            return
        }
        guard cs.crowd != nil else { return }
        cs.clock += dt
        for m in cs.pool { visitorLook(m.actor, m.visitor, dt: dt); m.actor.brain?.autonomy = false; m.actor.brain?.idleBlocked = true }
        // 2. the schedule: entrances and exits (only while the player's visit is on, not in the cheer's first seconds)
        let events = cs.crowd?.tick(dt: dt) ?? []
        for e in events {
            switch e {
            case .enter(let g): cafeCrowdStart(g, seated: false, landscape: landscape); cs.entered += 1
            case .leave(let id): cafeCrowdLeave(id, landscape: landscape)
            }
        }
        // 3. the bodies
        for g in cs.live.values { tickCrowdGroup(g, dt: dt, landscape: landscape) }
        for t in book.extraTables { t.update(dt: dt) }
        // 4. the closest approach (any customer walking vs anybody)
        crowdMeasure(actors)
        if cs.clock >= cs.nextLog {
            cs.nextLog += 10
            Self.crowdLog(String(format: "STATUS t=%.0f seed=%llu playerTable=%d preseated=%d entered=%d left=%d bells=%d played=%d groups=%d minWalkApproach=%.2f minCustomerGap=%.2f toPlayer=%.2f toCustomer=%.2f hesit=%d guards=%d tablesUsed=%@", cs.clock, cs.seed, cs.playerTable, cs.preseated, cs.entered, cs.left, cs.bells, cs.bellsPlayed, cs.live.count, cs.minWalk, cs.minAll, cs.minPlayer, cs.minCust, cs.hesitations, cs.guardReplans, "\(cs.tablesUsed)"))
        }
    }

    /// A group takes its table: seated at once (already there) or the first member appears at the entrance with the bell.
    private func cafeCrowdStart(_ cg: CafeCrowdGroup, seated: Bool, landscape: Bool) {
        let cs = cafeBook.crowd
        guard cs.tables.indices.contains(cg.slot) else { return }
        let table = cs.tables[cg.slot]
        let free = cs.pool.filter { m in !cs.live.values.contains { $0.members.contains { $0 === m } } }
        guard free.count >= cg.size else { return }
        let g = CafeLiveGroup(id: cg.id, table: table, phase: seated ? .seated : .arriving)
        for k in 0..<cg.size { let m = free[k]; m.index = cg.size == 1 ? 1 : k;          // (one customer sits at the NEAR end)
             m.state = seated ? .seated : .waiting; m.replan = false; m.replans = 0; m.waitT = 0; m.guards = 0; m.reqWp = nil; g.members.append(m) }
        cs.live[cg.id] = g
        cs.tablesUsed.append(table.slot)
        if seated {
            for m in g.members {
                let b = m.actor.brain!
                rehome(m.actor, at: table.stands[m.index])
                b.startTurn(to: table.yaws[m.index], sim: m.actor.sim)
                b.reserved = true; b.mealFaceYaw = table.yaws[m.index]
            }
            crowdSetCups(g, quiet: true)
        }
        Self.crowdLog(String(format: "t=%.1f %@ group %d size %d table slot %d%@", cs.clock, seated ? "PRESEATED" : "ENTER", g.id, cg.size, table.slot, seated ? String(format: " stay %.0f", cg.stay) : ""))
    }

    private func cafeCrowdLeave(_ id: Int, landscape: Bool) {
        guard let g = cafeBook.crowd.live[id] else { return }
        g.phase = .leaving
        let door = Self.crowdEntry(z: g.table.door.y)
        g.members.sort { simd_distance(g.table.stands[$0.index], door) < simd_distance(g.table.stands[$1.index], door) }          // (the one nearer the door first)
        for m in g.members { m.state = .waiting; m.path = []; m.held = false; m.replan = false; m.replans = 0; m.guards = 0; m.reqWp = nil }
        g.belled = false
        Self.crowdLog(String(format: "t=%.1f LEAVE group %d", cafeBook.crowd.clock, id))
    }

    private func crowdSetCups(_ g: CafeLiveGroup, quiet: Bool) {
        let drinks: [CafeTreatID] = [.cocoa, .latte, .juice]
        var picks: [Int: CafeTreatID] = [:]
        for m in g.members where m.state == .seated { picks[g.table.placeOf[m.index]] = drinks[(m.index + m.actor.id) % drinks.count] }
        AudioHub.hushTableSetup = quiet
        g.table.table.restock(serving: picks.isEmpty ? CafePlate.emptyTable : Self.guestCups(picks))
        AudioHub.hushTableSetup = false
    }

    /// A route from `from` to `to` clear of every seated body and table, the widest berth that has a way through (the room's side is open: x up to the off-screen entrance).
    private func crowdRoute(_ g: CafeLiveGroup, _ m: CafeMember, from: SIMD2<Float>, to: SIMD2<Float>, landscape: Bool) -> [SIMD2<Float>] {
        let base = crowdDiscs(for: g, excluding: m, landscape: landscape)
        for extra in [Float(0.5), 0.3, 0.1, 0.0] {
            let discs = base.map { d -> CafeRoute.Disc in
                let near = min(simd_distance(d.c, from), simd_distance(d.c, to))
                return .init(c: d.c, r: max(min(d.r + extra, near - 0.02), min(d.r, near - 0.02)))
            }
            let r = CafeRoute.path(from: from, to: to, discs: discs, inside: { $0.x >= -3.9 && $0.x <= 7.5 && $0.y > -3.8 && $0.y < 2.9 })
            if !r.isEmpty { return r }
        }
        return []
    }
    /// The walk may run past the screen's side (as the home guest's exit does); the furniture still counts. `crowdClose` gives him the room's own rules back.
    private func crowdOpen(_ m: CafeMember) {
        guard m.savedResolve == nil, let b = m.actor.brain else { return }
        m.savedResolve = b.resolve
        m.actor.sim.arenaRadius = .infinity
        b.resolve = { p, r in GameCamera.constrain(p, radius: r, lowPropScale: RoomLayout.lowPropRadiusScale, openSides: true) }
    }
    private func crowdClose(_ m: CafeMember) {
        guard let b = m.actor.brain, let r = m.savedResolve else { return }
        b.resolve = r; m.savedResolve = nil
    }

    private func tickCrowdGroup(_ g: CafeLiveGroup, dt: Float, landscape: Bool) {
        let book = cafeBook, cs = book.crowd
        // the entrance is worked out NOW: the café camera is still settling when the tables are made (the visible width at that moment was narrower than a minute later, which put the
        // "off screen" entrance on screen in the logs of round 4)
        let door = Self.crowdEntry(z: g.table.door.y)
        // each member in turn
        for (i, m) in g.members.enumerated() {
            guard let b = m.actor.brain else { continue }
            let pos = Self.floorPos(b, m.actor.sim)
            let idleNow = b.commandedIdle == nil && b.idleState.kind == nil && { if case .none = b.script { return true } else { return false } }() && (b.activity == .idle || b.activity == .lookingAround || b.activity == .steppingInPlace)
            switch m.state {
            case .out: continue
            case .seated:
                if g.phase != .leaving { b.reserved = true; b.mealFaceYaw = g.table.yaws[m.index] }
                continue
            case .waiting:
                // the follower of a pair starts about a second after the one ahead, once that one is 1.2 u on (never shoulder to shoulder); the first starts at once
                if i > 0 {
                    let a = g.members[i - 1]
                    if a.state == .waiting { continue }
                    if !m.warm, g.phase == .arriving, a.state == .walking { m.warm = true; b.abortAll(m.actor.sim, m.actor.skinner); b.commandedIdle = nil }          // (an abort leaves the brain resting 2-4 s and a goTo asked in that rest is dropped: the rest runs out here, off the floor, before he is asked to walk)
                    if a.state == .walking {
                        let ap = Self.floorPos(a.actor.brain!, a.actor.sim)
                        let ref = g.phase == .leaving ? g.table.stands[a.index] : door
                        // coming in, the one ahead must be fully ON the floor (0.6 u inside the visible edge) and 1.3 u from the entrance before the next appears; going out, 1.3 u from his seat
                        let onFloor = g.phase == .leaving || ap.x <= GameCamera.visibleHalfWidthAtBody(z: ap.y, aspect: GameCamera.aspect) - 0.6
                        if cs.clock - a.startedAt < 1.0 || simd_distance(ap, ref) < 1.3 || !onFloor { continue }
                    }
                }
                let from = m.replan ? pos : (g.phase == .leaving ? g.table.stands[m.index] : door)
                let to = g.phase == .leaving ? door : g.table.stands[m.index]
                let route = crowdRoute(g, m, from: from, to: to, landscape: landscape)
                if route.isEmpty {          // no way round the seated bodies yet: he waits (off the floor when coming in) and looks again; after 10 s he is simply seated
                    m.waitT += dt
                    if g.phase == .arriving, m.waitT > 10 { m.path = [to]; m.state = .walking; m.stuck = 6.1; rehome(m.actor, at: to); if i == 0 { crowdBell(g, entering: true); g.belled = true }; Self.crowdLog("no route for member \(m.actor.id): seated directly") }
                    else if g.phase == .leaving, m.waitT > 10 { m.path = [door]; m.state = .walking; m.stuck = 0 }
                    continue
                }
                m.waitT = 0
                m.path = route
                crowdOpen(m)          // (the walk runs past the screen's side: the entrance and the exit lie off screen)
                if g.phase == .arriving, !m.replan {          // (he appears off screen at the entrance, the bell rings once for the group)
                    rehome(m.actor, at: door)
                    b.restTimer = 0; b.reserved = false; b.mealFaceYaw = nil
                    if i == 0 { crowdBell(g, entering: true); g.belled = true }
                }
                // round 4 (found with the stall log): a body that has sat or been parked can be left in a rest the brain will not walk out of ("idle, script none, restTimer 2-3 s" with a goTo asked and ignored,
                // until an abort and a fresh ask). So every walk starts the way the re-ask did: abort, no commanded idle, then the goTo.
                if !m.warm { b.abortAll(m.actor.sim, m.actor.skinner) }
                b.commandedIdle = nil; b.restTimer = 0; m.warm = false
                m.state = .walking; m.stuck = 0; m.lastPos = g.phase == .arriving && !m.replan ? door : pos; m.prevPos = m.lastPos; m.replan = false
                m.startedAt = cs.clock; m.slowT = 0; m.slowCounted = false; m.spawn = m.lastPos; m.nudges = 0
                if g.phase == .leaving { b.reserved = false; b.mealFaceYaw = nil }
            case .walking:
                // yield: a follower stops while the one ahead of it in this group is closer than 1.15
                var hold = false
                for (j, o) in g.members.enumerated() where j < i && o.state == .walking {
                    if simd_distance(Self.floorPos(o.actor.brain!, o.actor.sim), pos) < 1.15 { hold = true }
                }
                // a visible stop mid-route: speed under 0.15 u/s for 0.3 s, not at the start (1.5 s: a turn on the spot before the first step is not a stop) and not within 0.8 u of the end of the path
                let speed = dt > 0 ? simd_distance(pos, m.prevPos) / dt : 1
                m.prevPos = pos
                // a goTo asked while the brain was resting is dropped (idle, script none, nothing moves, on or off screen): ask again with the rest cleared, after half a second, six times at most
                if idleNow, speed < 0.05, m.path.first != nil { m.idleT += dt } else { m.idleT = 0 }
                if m.idleT > 0.5, m.nudges < 6, let wp = m.path.first, simd_distance(pos, wp) > 0.45 {
                    m.nudges += 1; m.idleT = 0
                    b.commandedIdle = nil; b.restTimer = 0
                    m.reqWp = wp; m.reqT = 0; b.requestNow(.goTo(wp))
                    Self.crowdLog("member \(m.actor.id) did not set off: asked again (\(m.nudges))")
                }
                let lastPt = m.path.last ?? pos
                let onScreen = abs(pos.x) < GameCamera.visibleHalfWidthAtBody(z: pos.y, aspect: GameCamera.aspect) + 0.4
                if speed < 0.15, onScreen, cs.clock - m.startedAt > 1.5, simd_distance(pos, lastPt) > 0.8 {
                    m.slowT += dt
                    if m.slowT > 0.3, !m.slowCounted {
                        m.slowCounted = true; cs.hesitations += 1
                        let fx = m.path.first.map { b.fixed($0) }
                        let others = g.members.filter { $0 !== m }.map { o in String(format: "m%d %@ (%.2f,%.2f)", o.actor.id, "\(o.state)", Self.floorPos(o.actor.brain!, o.actor.sim).x, Self.floorPos(o.actor.brain!, o.actor.sim).y) }.joined(separator: "; ")
                        Self.crowdLog(String(format: "t=%.1f HESITATION member %d at (%.2f,%.2f) held=%d idleNow=%d act=%@ script=%@ restT=%.2f path=%@ firstWpResolved=%@ reqWp=%@ others=[%@]", cs.clock, m.actor.id, pos.x, pos.y, hold ? 1 : 0, idleNow ? 1 : 0, "\(b.activity)", String("\(b.script)".prefix(60)), b.restTimer, m.path.map { String(format: "(%.2f,%.2f)", $0.x, $0.y) }.joined(separator: ">"), fx.map { String(format: "(%.2f,%.2f)", $0.x, $0.y) } ?? "-", m.reqWp.map { String(format: "(%.2f,%.2f)", $0.x, $0.y) } ?? "-", others))
                    }
                } else if speed >= 0.15 { m.slowT = 0; m.slowCounted = false }
                if hold { if !m.held { m.held = true; b.requestNow(.goTo(pos)) }; continue }
                m.held = false
                // no progress for 4 s (a walk that pushes against something counts too): a new route from here, twice; then he is simply set at the end of his path
                if simd_distance(pos, m.lastPos) < 0.01 { m.stuck += dt } else { m.stuck = 0; m.lastPos = pos }
                if m.stuck > 4, m.replans < 2 {
                    m.replans += 1; m.replan = true; m.state = .waiting; m.waitT = 0; m.stuck = 0
                    b.requestNow(.goTo(pos))
                    Self.crowdLog("member \(m.actor.id) stopped at \(pos): new route (\(m.replans))")
                    continue
                } else if m.stuck > 6, let last = m.path.last {
                    Self.crowdLog("member \(m.actor.id) stuck at \(pos), placed at \(last)")
                    rehome(m.actor, at: last); m.path = [last]; m.stuck = 0
                    continue
                }
                m.reqT += dt
                // the proximity guard: never nearer than 1.6 u to a player's body or a seated customer. A new route is planned from here and followed at once, without stopping (three times at most).
                var nearest: Float = .infinity, who = ""
                for a in book.actors where book.stands[a.id] != nil { if let ob = a.brain { let d = simd_distance(Self.floorPos(ob, a.sim), pos); if d < nearest { nearest = d; who = "player \(a.id)" } } }
                var playerNear = nearest
                var custNear: Float = .infinity
                for og in cs.live.values where og !== g { for om in og.members where om.state == .seated { let d = simd_distance(Self.floorPos(om.actor.brain!, om.actor.sim), pos); if d < custNear { custNear = d; if d < nearest { who = "seated customer \(om.actor.id)" } } } }
                nearest = min(playerNear, custNear)
                // (the player's bodies: 1.6; another table's seated customers: 1.3; his own table's mates never)
                if playerNear < 1.6 || custNear < 1.3, m.guards < 3, cs.clock - m.guardAt > 2, let goal = m.path.last {
                    m.guards += 1; m.guardAt = cs.clock; cs.guardReplans += 1
                    let route = crowdRoute(g, m, from: pos, to: goal, landscape: landscape)
                    Self.crowdLog(String(format: "member %d is %.2f from %@ at (%.2f,%.2f): new route %@ (guard %d)", m.actor.id, nearest, who, pos.x, pos.y, route.isEmpty ? "none" : "followed", m.guards))
                    if let first = route.first { m.path = route; m.reqWp = first; m.reqT = 0; b.requestNow(.goTo(first)) }
                    continue
                }
                // a waypoint that is not the last is taken while he is still walking (0.6 u before it): the next leg starts without a stop
                if let wp = m.path.first, m.path.count > 1, simd_distance(pos, wp) < 0.6 {
                    m.path.removeFirst()
                    if let n = m.path.first { m.reqWp = n; m.reqT = 0; b.requestNow(.goTo(n)) }
                    continue
                }
                guard idleNow else { continue }
                if let wp = m.path.first {
                    let lastLeg = m.path.count == 1
                    let d = simd_distance(pos, wp)
                    // he walked to this spot and stopped short of it (the walkable floor clamps it): that counts as there
                    let stoppedShort = m.reqWp == wp && m.reqT > 0.8
                    // leaving: the last leg is the entrance, off screen: he walks all the way out, never vanishes at his seat
                    let atDoor = g.phase == .leaving && lastLeg && (d < 0.6 || (stoppedShort && d < 2.0))
                    if atDoor { m.path.removeAll(); crowdArrived(g, m, landscape: landscape); continue }
                    if d < 0.45 || (stoppedShort && (!lastLeg || d < 0.9)) {
                        m.path.removeFirst(); m.reqWp = nil
                        if let n = m.path.first { m.reqWp = n; m.reqT = 0; b.requestNow(.goTo(n)) } else { crowdArrived(g, m, landscape: landscape) }
                    } else if m.reqWp != wp { m.reqWp = wp; m.reqT = 0; b.requestNow(.goTo(wp)) }
                } else { crowdArrived(g, m, landscape: landscape) }
            }
        }
        // the group's phase
        if g.phase == .arriving, g.members.allSatisfy({ $0.state == .seated }) {
            g.phase = .seated; cs.crowd?.seated(g.id)
            Self.crowdLog(String(format: "t=%.1f SEATED group %d", cs.clock, g.id))
        }
        if g.phase == .leaving, g.members.allSatisfy({ $0.state == .out }) {
            cs.live[g.id] = nil; cs.crowd?.gone(g.id); cs.left += 1
            crowdSetCups(g, quiet: true)
            Self.crowdLog(String(format: "t=%.1f GONE group %d", cs.clock, g.id))
            return
        }
        // a seated pair talks in place
        if g.phase == .seated, g.members.count == 2, g.members.allSatisfy({ $0.state == .seated }) {
            let seats = g.members.map { m in CafeChatSeat(id: m.actor.id, brain: m.actor.brain!, sim: m.actor.sim, skinner: m.actor.skinner, stand: g.table.stands[m.index], yaw: g.table.yaws[m.index]) }
            let voices = Dictionary(uniqueKeysWithValues: g.members.map { ($0.actor.id, Self.regularVoiceCharacter($0.visitor)) })
            tickCafeChat(seats, state: g.chat, dt: dt) { s, v in AudioHub.shared.chirp(character: voices[s.id] ?? 0, v, quiet: true) }
        }
    }

    private func crowdArrived(_ g: CafeLiveGroup, _ m: CafeMember, landscape: Bool) {
        guard let b = m.actor.brain else { return }
        let cs = cafeBook.crowd
        crowdClose(m)
        if g.phase == .leaving {
            m.state = .out
            if !g.belled { crowdBell(g, entering: false); g.belled = true }
            if let k = cs.pool.firstIndex(where: { $0 === m }) { rehome(m.actor, at: crowdParkSpot(k)) }
            b.reserved = false; b.mealFaceYaw = nil
        } else {
            m.state = .seated
            b.startTurn(to: g.table.yaws[m.index], sim: m.actor.sim)
            b.reserved = true; b.mealFaceYaw = g.table.yaws[m.index]
            crowdSetCups(g, quiet: false)
        }
    }

    private func crowdMeasure(_ actors: [JellyActor]) {
        let cs = cafeBook.crowd, book = cafeBook
        var players: [SIMD2<Float>] = []
        for a in actors where book.stands[a.id] != nil { if let b = a.brain { players.append(Self.floorPos(b, a.sim)) } }
        var custs: [(p: SIMD2<Float>, walking: Bool)] = []
        for m in cs.pool {
            guard let b = m.actor.brain else { continue }
            let p = Self.floorPos(b, m.actor.sim)
            if p.x > 30 { continue }
            custs.append((p, m.state == .walking))
        }
        var loP: Float = .infinity, loC: Float = .infinity
        for c in custs { for p in players { loP = min(loP, simd_distance(c.p, p)) } }
        for i in custs.indices { for j in custs.indices where j > i { loC = min(loC, simd_distance(custs[i].p, custs[j].p)) } }
        cs.minPlayer = min(cs.minPlayer, loP); cs.minCust = min(cs.minCust, loC)
        let lo = min(loP, loC)
        if lo < cs.minAll { cs.minAll = lo }
        if custs.contains(where: { $0.walking }) { if lo < cs.minWalk { cs.minWalk = lo } }
    }

    /// The visit's customers leave with the café (under the white): tables gone, bodies put away.
    func cafeCrowdLeave() {
        let cs = cafeBook.crowd
        for m in cs.pool { crowdClose(m) }
        CafeCalmProbe.shared.summary("FINAL"); CafeCalmProbe.shared.reset()
        if cs.crowd != nil {
            Self.crowdLog(String(format: "SUMMARY seed=%llu playerTable=%d preseated=%d entered=%d left=%d bells=%d played=%d (in %d out %d) minWalkApproach=%.2f minCustomerGap=%.2f toPlayer=%.2f toCustomer=%.2f hesit=%d tablesUsed=%@ clock=%.0f", cs.seed, cs.playerTable, cs.preseated, cs.entered, cs.left, cs.bells, cs.bellsPlayed, cs.enterBells, cs.exitBells, cs.minWalk, cs.minAll, cs.minPlayer, cs.minCust, cs.hesitations, "\(cs.tablesUsed)", cs.clock))
        }
        cs.reset()
    }
}
