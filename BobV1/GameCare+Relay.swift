//
//  GameCare+Relay.swift
//  Jelly Circuit RELAY: the glue between the relay (Race/RelayModel.swift, RaceFlow.beginRelay) and the bodies.
//
//  Three teams run side by side (the player's in the middle lane, two rival teams either side), three runners each, nine bodies on the track. The
//  player's team is the owned Jelbies in the lobby's leg order, then his Park friends (a friend must be a Pal or better; they are the visitor's real
//  colour and item). The rival teams are Park visitors from the same pool (so the species-signature rule holds), with stats from the rival source.
//
//  Bodies: the owned Jelbies are the room's own bodies; every other runner is a Park visitor body made by ONE `parkBook.spawn` call (the stage makes them;
//  the volleyball does the same) and let go when the trip ends. A waiting runner stands in his handoff box with no script, so his sim sleeps; he starts
//  bouncing when the runner before him is close. At the handoff the incoming runner takes the race script, the outgoing one coasts three small steps,
//  stands, and hops twice. Only 3 bodies run at once (the same as a solo race); the waiting ones cost nothing.
//

import Foundation
import QuartzCore
import simd

/// Relay asked while a Jelbie is asleep: the trip starts when everybody is upright.
struct RelayRequest { var order: [Int]; var friends: [Int]; var course: CourseTier }

/// The relay's bodies and effects while a trip is on.
@MainActor
final class RelayBodies {
    struct Coaster { var actor: JellyActor; var k = 0; var stride: Float; var rate: Float; var settled = false }
    struct Cheer { var actor: JellyActor; var delay: Float; var hops: Int }
    struct Baton { var from: JellyActor?; var to: JellyActor?; var age: Float = 1 }
    struct Tag { var world: SIMD3<Float>; var age: Float; var player: Bool }

    /// [team][leg]
    var teams: [[JellyActor]] = []
    var active = [0, 0, 0]
    var visitors: [(actor: JellyActor, visitor: ParkVisitor)] = []
    var coast: [Coaster] = []
    var cheers: [Cheer] = []
    var bounce = [Float](repeating: 0, count: 3)
    var batons = [Baton](repeating: Baton(), count: 3)
    var tags: [Tag] = []
    /// Seconds since the last handoff of the player's team (the camera eases slowly across it).
    var sinceHandoff: Float = 9
    var finishCheerArmed = [Bool](repeating: false, count: 3)
    nonisolated deinit {}

    func reset() {
        teams = []; active = [0, 0, 0]; visitors = []; coast = []; cheers = []; bounce = [0, 0, 0]
        batons = [Baton](repeating: Baton(), count: 3); tags = []; sinceHandoff = 9; finishCheerArmed = [false, false, false]
    }
}

extension GameCare {
    // MARK: who can run

    /// The owned Jelbies of an order: valid, once each, in order.
    func relayOwned(_ order: [Int]) -> [Int] {
        var seen = Set<Int>()
        return order.filter { jelly($0) != nil && seen.insert($0).inserted }
    }

    /// The Park friends that may run: a Pal or better with one of the player's Jelbies, once each, in the order given.
    func relayFriends(_ ids: [Int]) -> [Int] {
        let chars = jellies.map(\.character)
        var seen = Set<Int>()
        return ids.filter { id in
            guard let v = parkBook.visitor(id), v.bestLevel(among: chars) >= .pal else { return false }
            return seen.insert(id).inserted
        }
    }

    /// Why a relay cannot start now (nil = it can): fewer than three runners, or the usual reasons a race cannot.
    func relayBlocker(order: [Int], friends: [Int]) -> String? {
        let owned = relayOwned(order), fr = relayFriends(friends)
        if owned.isEmpty || owned.count + fr.count < RelayTuning.legCount { return "Relay needs 3 runners. Go to the Park and make friends!" }
        return raceBlocker(jelly: owned[0])
    }

    /// Takes the team to the track. `order`: the owned Jelbies in leg order; `friends`: Park visitor ids, who fill the remaining legs in the order given.
    func startRelay(order: [Int], friends: [Int], course: CourseTier, seed: UInt64? = nil) {
        guard relayBlocker(order: order, friends: friends) == nil else { return }
        let req = RelayRequest(order: order, friends: friends, course: course)
        let lead = relayOwned(order)[0]
        select.cancel(); queued.removeAll(); callRunning = false
        voice.cancel()
        let sleepers = raceBook.actors.compactMap { $0.brain }.filter { $0.isSleeping }
        if !sleepers.isEmpty {
            for b in sleepers { b.commandedGoodnight = false; b.sleepWake(groggy: false, fast: true) }
            var w = RaceWait(id: lead, seed: seed); w.relay = req
            raceWait = w
            for a in raceBook.actors { a.brain?.sleepLocked = true }
            return
        }
        beginRelay(req, seed: seed)
    }

    func beginRelay(_ req: RelayRequest, seed: UInt64?) {
        let owned = relayOwned(req.order), fr = relayFriends(req.friends)
        guard owned.count + fr.count >= RelayTuning.legCount, let lead = owned.first else { return }
        if outingGate(owned, again: { [weak self] in self?.beginRelay(req, seed: seed) }) { return }
        let s = seed ?? Self.raceSeed
        var tier = req.course
        if !race.progress.unlocked(tier) { tier = .puddle }
        let course = RaceCourse.course(tier)
        let starts = RelayTuning.legs(length: course.length).starts
        // the player's team: owned Jelbies in order, then friends (three in all)
        var runners: [(id: Int?, friend: ParkVisitor?)] = owned.map { ($0, nil) } + fr.compactMap { parkBook.visitor($0) }.map { (nil, $0) }
        runners = Array(runners.prefix(RelayTuning.legCount))
        var team0: [RelayLeg] = []
        var stats: [JellyStats] = []
        for (j, r) in runners.enumerated() {
            if let id = r.id, let p = jelly(id) {
                team0.append(RelayLeg(name: p.name, stats: RacerStats(waddle: p.stats.waddle, focus: p.stats.focus), ai: false, startDist: starts[j]))
                stats.append(p.stats)
            } else if let v = r.friend {
                team0.append(RelayLeg(name: v.name, stats: RelayTuning.friendStats, ai: true, startDist: starts[j]))
            }
        }
        // the rival teams: six visitors from the pool (not the friends), shuffled by the seed
        let used = Set(runners.compactMap { $0.friend?.id })
        var pool = parkBook.visitors.filter { !used.contains($0.id) }
        var rng = ParkRandom(s &+ 311)
        for i in stride(from: pool.count - 1, to: 0, by: -1) { pool.swapAt(i, Int(rng.next() % UInt64(i + 1))) }
        let rivalVisitors = Array(pool.prefix(6))
        let avg = RacerStats(waddle: team0.map(\.stats.waddle).reduce(0, +) / Float(max(team0.count, 1)), focus: team0.map(\.stats.focus).reduce(0, +) / Float(max(team0.count, 1)))
        let rs = race.rivalSource.rivals(count: 6, player: avg, playerTint: JellyRoster.tint(jelly(lead)?.character ?? 0), seed: s, tier: tier)
        var teams: [[RelayLeg]] = [team0]
        var names = ["Your team"]
        for t in 0..<2 {
            teams.append((0..<3).map { j in RelayLeg(name: rivalVisitors[t * 3 + j].name, stats: rs[t * 3 + j].stats, ai: false, startDist: starts[j]) })
            names.append("Team \(rivalVisitors[t * 3].name)")
        }
        let plan = RelayPlan(teams: teams, teamNames: names, ownedIDs: runners.map(\.id), friendIDs: runners.compactMap { $0.friend?.id },
                             rivalVisitorIDs: rivalVisitors.map(\.id), course: course)
        race.stats = jelly(lead)?.stats
        race.playerCharacter = jelly(lead)?.character ?? 0
        race.beginRelay(playerID: lead, plan: plan, stats: stats, seed: s)
    }

    // MARK: the world swaps

    /// The track is up (under the white): every runner on his spot.
    func relayEnter() {
        guard let sim = race.sim, let plan = race.relayPlan else { return }
        let book = raceBook, rb = book.relay
        rb.reset()
        let course = sim.course
        let starts = RelayTuning.legs(length: course.length).starts
        // the bodies: owned Jelbies are the room's; every other runner is a visitor body (ONE spawn call: the next would clear the first)
        let friendSpecs = plan.friendIDs.compactMap { parkBook.visitor($0) }
        let rivalSpecs = plan.rivalVisitorIDs.compactMap { parkBook.visitor($0) }
        let specs = friendSpecs + rivalSpecs
        let spawned = specs.isEmpty ? [] : (parkBook.spawn?(specs, specs.indices.map { SIMD2<Float>(40 + Float($0) * 3, 0) }) ?? [])
        guard spawned.count == specs.count else { race.abort(); return }
        for (a, v) in zip(spawned, specs) { rb.visitors.append((a, v)) }
        var fi = 0
        var team0: [JellyActor] = []
        for id in plan.ownedIDs {
            if let id, book.actors.indices.contains(id) { team0.append(book.actors[id]) } else { team0.append(spawned[fi]); fi += 1 }
        }
        rb.teams = [team0, Array(spawned[friendSpecs.count..<friendSpecs.count + 3]), Array(spawned[friendSpecs.count + 3..<friendSpecs.count + 6])]
        let ownedOnTeam = Set(plan.ownedIDs.compactMap { $0 })
        book.racers = Array(ownedOnTeam).sorted()
        book.palettes = [:]; book.homes = [:]; book.autonomy = [:]; book.arena = [:]
        book.parked = book.actors.indices.filter { !ownedOnTeam.contains($0) }
        for aid in book.parked {                 // a Jelbie not in the team waits far off the track and comes back where he stood
            let a = book.actors[aid]
            guard let brain = a.brain else { continue }
            book.homes[aid] = a.floor; book.autonomy[aid] = brain.autonomy; book.arena[aid] = a.sim.arenaRadius
            a.sim.arenaRadius = .infinity
            let px = 40 + Float(aid) * 4
            a.sim.teleport(toXZ: SIMD2(px, RaceTuning.startZ))
            brain.startRace(sim: a.sim, skinner: a.skinner, heading: 0, laneX: px)
            a.skinner.jelly.reset()
        }
        book.follow = nil
        for t in 0..<3 {
            let lane = RelayTuning.lanes[t]
            for j in 0..<3 {
                let a = rb.teams[t][j]
                guard let brain = a.brain else { continue }
                if ownedOnTeam.contains(a.id), !spawned.contains(where: { $0 === a }) {
                    book.homes[a.id] = a.floor; book.autonomy[a.id] = brain.autonomy; book.arena[a.id] = a.sim.arenaRadius
                }
                a.sim.arenaRadius = .infinity
                let spot = course.lanePoint(lane, at: starts[j])
                a.sim.teleport(toXZ: spot)
                brain.startRace(sim: a.sim, skinner: a.skinner, heading: course.pose(at: starts[j]).heading, laneX: spot.x, course: course, lane: lane)
                brain.race.lastS = starts[j]
                brain.autonomy = false
                a.skinner.jelly.reset()
                if j > 0 { brain.relayStand() }
            }
        }
        RaceModels.relayMarkers = true
        for (a, v) in rb.visitors { visitorLook(a, v, dt: 1.0 / 60) }
    }

    /// Back in the room (under the white): the visitor bodies are let go; the roster is put back by the usual swap.
    func relayLeave() {
        let rb = raceBook.relay
        guard !rb.teams.isEmpty else { RaceModels.relayMarkers = false; return }
        for (a, _) in rb.visitors { a.brain?.endRace(); visitorPutAway(a) }
        parkBook.clear?()
        rb.reset()
        RaceModels.relayMarkers = false
    }

    // MARK: camera

    /// The follow camera of a relay: the runners now on the track (the player's team's in front of the frame), eased slowly across a handoff.
    func relayFollow(_ dt: Float) -> RaceFollowPose? {
        let book = raceBook, rb = book.relay
        guard let sim = race.sim, rb.teams.count == 3 else { book.follow = nil; return nil }
        var spots: [RaceFollowPose.Racer] = []
        for t in 0..<3 {
            let a = rb.teams[t][min(rb.active[t], 2)]
            guard let b = a.brain else { continue }
            spots.append(RaceFollowPose.Racer(pos: SIMD2(b.px, b.pz), s: sim.racers[t].dist, isPlayer: t == 0))
        }
        guard !spots.isEmpty else { return book.follow }
        let want = RaceFollowPose.aim(course: sim.course, racers: spots)
        let k: Float = rb.sinceHandoff < 1.2 ? 0.45 : 1
        book.follow = book.follow.map { $0.smoothed(toward: want, dt: dt * k) } ?? want
        return book.follow
    }

    // MARK: per fixed step

    func tickRelay(_ actors: [JellyActor], dt: Float) {
        let book = raceBook, rb = book.relay
        guard race.sim != nil, let plan = race.relayPlan, rb.teams.count == 3 else { return }
        func body(_ t: Int) -> JellyActor? { rb.teams.indices.contains(t) ? rb.teams[t][min(rb.active[t], 2)] : nil }
        rb.sinceHandoff += dt
        for (a, v) in rb.visitors { visitorLook(a, v, dt: dt) }
        let course = race.sim!.course
        if race.phase == .racing {
            for t in 0..<3 {
                guard let b = body(t)?.brain else { continue }
                b.raceKeepAlive()
                race.setMeasured(t, dist: b.raceProgress)
            }
        }
        let events = race.tick(dt: dt, bodyFree: { body($0)?.brain?.raceStepFree ?? true }, bodyReady: { body($0)?.brain?.raceBodyReady ?? true },
                               bodyBetween: { body($0)?.brain?.raceBetweenSteps ?? true })
        for e in events {
            switch e {
            case .handoff(let t, let leg): relayHandoff(t, leg, plan: plan, course: course)
            case .stumble(let i), .trip(let i):
                if let a = body(i), let b = a.brain { b.raceApply(e, sim: a.sim) }
                if i == 0 { touchPlay?.haptics.transient(now: CACurrentMediaTime(), intensity: 0.5, sharpness: 0.2); AudioHub.shared.raceStumble() }
            case .finished(let i, _):
                if let a = body(i), let b = a.brain { b.raceApply(e, sim: a.sim) }
                if i == 0 { touchPlay?.haptics.transient(now: CACurrentMediaTime(), intensity: 0.8, sharpness: 0.5) }
                if let a = body(i) { rb.cheers.append(RelayBodies.Cheer(actor: a, delay: 1.6, hops: 2)) }
            case .hurdleCleared(let i):
                if let a = body(i), let b = a.brain { b.raceApply(e, sim: a.sim) }
                if i == 0 { touchPlay?.haptics.transient(now: CACurrentMediaTime(), intensity: 0.4, sharpness: 0.7); AudioHub.shared.chirp(jelly: race.playerID, .happy) }
            default:
                if let i = e.racer, let a = body(i), let b = a.brain { b.raceApply(e, sim: a.sim) }
            }
        }
        guard race.phase == .racing, let sim = race.sim else { return }
        // the outgoing runners coast three small steps, stand, and cheer
        var k = 0
        while k < rb.coast.count {
            var c = rb.coast[k]
            guard let b = c.actor.brain else { rb.coast.remove(at: k); continue }
            b.raceKeepAlive()
            if c.k < RaceTuning.coastSteps {
                if b.raceStepFree {
                    b.raceCommit(foot: 1 - b.nextSwing, stride: RaceTuning.coastStride(c.k) * c.stride, rate: c.rate * 0.8, final: c.k == RaceTuning.coastSteps - 1)
                    c.k += 1
                }
                rb.coast[k] = c; k += 1
            } else if b.raceBetweenSteps {
                b.relayStand()
                rb.cheers.append(RelayBodies.Cheer(actor: c.actor, delay: 0.25, hops: 2))
                rb.coast.remove(at: k)
            } else { rb.coast[k] = c; k += 1 }
        }
        // cheers
        k = 0
        while k < rb.cheers.count {
            var c = rb.cheers[k]
            c.delay -= dt
            if c.delay <= 0, let b = c.actor.brain {
                if case .race = b.script, b.raceBetweenSteps { b.relayStand() }          // (the last runner past the line: his coast is over)
                if b.relayCanHop { b.relayHop(c.actor.sim); c.hops -= 1; c.delay = 0.5 }
            }
            if c.hops <= 0 { rb.cheers.remove(at: k) } else { rb.cheers[k] = c; k += 1 }
        }
        // the waiting runner bounces while the runner before him comes in
        for t in 0..<3 {
            let leg = rb.active[t]
            guard leg < 2, !sim.racers[t].finished else { continue }
            let waiter = rb.teams[t][leg + 1]
            rb.bounce[t] -= dt
            if plan.lines[leg] - sim.racers[t].dist < RelayTuning.bounceAhead, rb.bounce[t] <= 0, let b = waiter.brain, b.relayCanHop {
                b.relayHop(waiter.sim); rb.bounce[t] = RelayTuning.bounceEvery
            }
        }
        // the effects age
        for t in 0..<3 where rb.batons[t].age < 1 { rb.batons[t].age += dt / 0.45 }
        for i in rb.tags.indices { rb.tags[i].age += dt }
        rb.tags.removeAll { $0.age > 0.9 }
    }

    private func relayHandoff(_ t: Int, _ leg: Int, plan: RelayPlan, course: RaceCourse) {
        let rb = raceBook.relay
        guard rb.teams.indices.contains(t), leg >= 1, leg <= 2 else { return }
        let out = rb.teams[t][leg - 1], inn = rb.teams[t][leg]
        rb.active[t] = leg
        let st = plan.teams[t][leg - 1].stats
        rb.coast.append(RelayBodies.Coaster(actor: out, stride: RaceTuning.stride(waddle: st.waddle), rate: RaceTuning.maxRate(waddle: st.waddle)))
        inn.brain?.relayGo(sim: inn.sim)
        rb.batons[t] = RelayBodies.Baton(from: out, to: inn, age: 0)
        let p = course.lanePoint(RelayTuning.lanes[t], at: plan.lines[leg - 1])
        rb.tags.append(RelayBodies.Tag(world: SIMD3(p.x, 0.55, p.y), age: 0, player: t == 0))
        if t == 0 {
            rb.sinceHandoff = 0
            AudioHub.shared.chirp(jelly: race.playerID, .happy)
            touchPlay?.haptics.transient(now: CACurrentMediaTime(), intensity: 0.6, sharpness: 0.6)
            A11yEvents.say("Tag! \(plan.teams[0][leg].name) runs", .normal)
        }
    }
}

extension GameCare {
    /// Capture aid (`-RelayStart 1`): the whole roster in order, then Park friends (seeded as Pals on the simulator when none is) up to three runners.
    func relayCaptureStart(auto: Bool) {
        let order = Array(jellies.indices)
        var friends = parkBook.visitors.map(\.id).filter { relayFriends([$0]).count == 1 }
        #if targetEnvironment(simulator)
        if order.count + friends.count < RelayTuning.legCount, let c = jellies.first?.character {
            for v in parkBook.visitors where !friends.contains(v.id) && friends.count + order.count < RelayTuning.legCount {
                parkBook.add(points: ParkTuning.palAt + 1, visitor: v.id, character: c)
                friends.append(v.id)
            }
        }
        #endif
        if auto { race.autoRate = 4.5; race.autoReturnAfter = 12 }
        startRelay(order: order, friends: friends, course: race.courseTier)
    }
}
