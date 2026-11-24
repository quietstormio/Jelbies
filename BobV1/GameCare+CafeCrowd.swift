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
    func reset() { crowd = nil; tables = []; live = [:]; pool = []; clock = 0; preseated = 0; entered = 0; left = 0; bells = 0; bellsPlayed = 0; enterBells = 0; exitBells = 0; minWalk = .infinity; minAll = .infinity; nextLog = 0; tablesUsed = [] }
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
        let door = CafeTables.door(landscape: landscape)
        ends.sort { simd_distance($0.stand, door) > simd_distance($1.stand, door) }          // (the first in takes the FAR end: the second never walks past the first)
        let ct = CafeCustomerTable(slot: slot, centre: t, table: table)
        ct.stands = ends.map(\.stand); ct.yaws = ends.map(\.yaw); ct.placeOf = ends.map { $0.yaw > 0 ? 1 : 2 }
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
            var crowd = CafeCrowd(slots: cs.tables.count, bodies: cs.pool.count, seed: cs.seed)
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
            Self.crowdLog(String(format: "STATUS t=%.0f seed=%llu playerTable=%d preseated=%d entered=%d left=%d bells=%d played=%d groups=%d minWalkApproach=%.2f minCustomerGap=%.2f tablesUsed=%@", cs.clock, cs.seed, cs.playerTable, cs.preseated, cs.entered, cs.left, cs.bells, cs.bellsPlayed, cs.live.count, cs.minWalk, cs.minAll, "\(cs.tablesUsed)"))
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
        for k in 0..<cg.size { let m = free[k]; m.index = k; m.state = seated ? .seated : .waiting; m.replan = false; m.replans = 0; m.waitT = 0; g.members.append(m) }
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
        let door = CafeTables.door(landscape: landscape)
        g.members.sort { simd_distance(g.table.stands[$0.index], door) < simd_distance(g.table.stands[$1.index], door) }          // (the one nearer the door first)
        for m in g.members { m.state = .waiting; m.path = []; m.held = false; m.replan = false; m.replans = 0 }
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

    private func tickCrowdGroup(_ g: CafeLiveGroup, dt: Float, landscape: Bool) {
        let book = cafeBook, cs = book.crowd
        let door = CafeTables.door(landscape: landscape)
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
                // the one ahead must be 1.6 u away from where this one starts (and walking); the first starts at once
                if i > 0 {
                    let a = g.members[i - 1]
                    if a.state == .waiting { continue }
                    if a.state == .walking {
                        let ap = Self.floorPos(a.actor.brain!, a.actor.sim)
                        let ref = g.phase == .leaving ? g.table.stands[a.index] : door
                        if simd_distance(ap, ref) < (g.phase == .leaving ? 1.7 : 1.9) { continue }
                    }
                }
                let from = m.replan ? pos : (g.phase == .leaving ? g.table.stands[m.index] : door)
                let to = g.phase == .leaving ? door : g.table.stands[m.index]
                // planning discs are bigger than the keep-apart gap (a walker cuts corners by up to 0.4 u); a disc that holds the start or the goal is shrunk to just clear it
                let base = crowdDiscs(for: g, excluding: m, landscape: landscape)
                var route: [SIMD2<Float>] = []
                for extra in [Float(0.4), 0.2, 0.0] where route.isEmpty {          // (the widest berth that still has a way through)
                    let discs = base.map { d -> CafeRoute.Disc in
                        let near = min(simd_distance(d.c, from), simd_distance(d.c, to))
                        return .init(c: d.c, r: max(min(d.r + extra, near - 0.02), min(d.r, near - 0.02)))
                    }
                    route = CafeRoute.path(from: from, to: to, discs: discs, inside: { abs($0.x) <= 4.6 && $0.y > -3.8 && $0.y < 2.9 })
                }
                if route.isEmpty {          // no way round the seated bodies yet: he waits (off the floor when coming in) and looks again; after 10 s he is simply seated
                    m.waitT += dt
                    if g.phase == .arriving, m.waitT > 10 { m.path = [to]; m.state = .walking; m.stuck = 6.1; rehome(m.actor, at: to); if i == 0 { crowdBell(g, entering: true); g.belled = true }; Self.crowdLog("no route for member \(m.actor.id): seated directly") }
                    else if g.phase == .leaving, m.waitT > 10 { m.path = [door]; m.state = .walking; m.stuck = 0 }
                    continue
                }
                m.waitT = 0
                m.path = route
                if g.phase == .arriving, !m.replan {          // (he appears at the entrance, the bell rings once for the group)
                    rehome(m.actor, at: door)
                    b.restTimer = 0.2; b.reserved = false; b.mealFaceYaw = nil
                    if i == 0 { crowdBell(g, entering: true); g.belled = true }
                }
                m.state = .walking; m.stuck = 0; m.lastPos = g.phase == .arriving && !m.replan ? door : pos; m.replan = false
                if g.phase == .leaving { b.reserved = false; b.mealFaceYaw = nil }
            case .walking:
                // yield: a follower stops while the one ahead of it in this group is closer than 1.3
                var hold = false
                for (j, o) in g.members.enumerated() where j < i && o.state == .walking {
                    if simd_distance(Self.floorPos(o.actor.brain!, o.actor.sim), pos) < 1.55 { hold = true }
                }
                if hold { if !m.held { m.held = true; b.requestNow(.goTo(pos)) }; continue }
                m.held = false
                guard idleNow else { continue }
                if let wp = m.path.first {
                    let lastLeg = m.path.count == 1
                    // leaving: the entrance itself may lie past the walkable floor, so the last leg counts as done within 1.3 u of it (or when he has stopped within 2 u of it)
                    let atDoor = g.phase == .leaving && lastLeg && (simd_distance(pos, wp) < 1.3 || (m.stuck > 2.5 && simd_distance(pos, wp) < 2.0))
                    if atDoor { m.path.removeAll(); crowdArrived(g, m, landscape: landscape); continue }
                    if simd_distance(pos, wp) < (lastLeg ? 0.45 : 0.35) {
                        m.path.removeFirst()
                        if let n = m.path.first { b.requestNow(.goTo(n)) } else { crowdArrived(g, m, landscape: landscape) }
                    } else { b.requestNow(.goTo(wp)) }
                } else { crowdArrived(g, m, landscape: landscape) }
                if simd_distance(pos, m.lastPos) < 0.01 { m.stuck += dt } else { m.stuck = 0; m.lastPos = pos }
                if m.stuck > 4, m.replans < 2 {          // (stopped for 4 s: look for a new way from where he stands)
                    m.replans += 1; m.replan = true; m.state = .waiting; m.waitT = 0; m.stuck = 0
                    Self.crowdLog("member \(m.actor.id) stopped at \(pos): new route (\(m.replans))")
                } else if m.stuck > 6, let last = m.path.last {          // (never stuck forever: set him at the end of the path)
                    Self.crowdLog("member \(m.actor.id) stuck at \(pos), placed at \(last)")
                    rehome(m.actor, at: last); m.path = [last]; m.stuck = 0
                }
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
        let cs = cafeBook.crowd
        var bodies: [(p: SIMD2<Float>, customer: Bool, walking: Bool)] = []
        for a in actors { if let b = a.brain { bodies.append((Self.floorPos(b, a.sim), false, false)) } }
        for m in cs.pool {
            guard let b = m.actor.brain else { continue }
            let p = Self.floorPos(b, m.actor.sim)
            if p.x > 30 { continue }
            bodies.append((p, true, m.state == .walking))
        }
        var lo: Float = .infinity, loW: Float = .infinity
        for i in bodies.indices { for j in bodies.indices where j > i {
            let d = simd_distance(bodies[i].p, bodies[j].p)
            if bodies[i].customer || bodies[j].customer { lo = min(lo, d) }
            if (bodies[i].walking || bodies[j].walking) { loW = min(loW, d) }
        } }
        if lo < cs.minAll { cs.minAll = lo }
        if loW < cs.minWalk { cs.minWalk = loW }
    }

    /// The visit's customers leave with the café (under the white): tables gone, bodies put away.
    func cafeCrowdLeave() {
        let cs = cafeBook.crowd
        CafeCalmProbe.shared.summary("FINAL"); CafeCalmProbe.shared.reset()
        if cs.crowd != nil {
            Self.crowdLog(String(format: "SUMMARY seed=%llu playerTable=%d preseated=%d entered=%d left=%d bells=%d played=%d (in %d out %d) minWalkApproach=%.2f minCustomerGap=%.2f tablesUsed=%@ clock=%.0f", cs.seed, cs.playerTable, cs.preseated, cs.entered, cs.left, cs.bells, cs.bellsPlayed, cs.enterBells, cs.exitBells, cs.minWalk, cs.minAll, "\(cs.tablesUsed)", cs.clock))
        }
        cs.reset()
    }
}
