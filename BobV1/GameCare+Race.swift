//
//  GameCare+Race.swift
//  Jelly Circuit "Waddle Sprint": the glue between the race (Race/RaceFlow.swift, RaceModel.swift) and the Jellies of the room.
//
//  "Race" on the care menu sends the Jelly that is picked (the selection, else Bob) to the track. The race needs three bodies, so the other
//  Jellies' bodies are BORROWED as the two rivals (a colour tint on the same body and rig), put back where they stood when the race is over;
//  the Jellies at home are the same ones who greet the winner on the way back. The race swaps worlds only under the white fade.
//

import Foundation
import QuartzCore
import simd

/// Race asked while a Jelly is asleep: the trip starts when everybody is upright.
struct RaceWait { var id: Int; var seed: UInt64?; var age: Float = 0; var drill = false }

/// What GameCare keeps while a race trip is on: the room's Jellies as the stage last gave them, who races in which lane, where everybody was
/// standing, and the welcome home that follows.
@MainActor
final class RaceBook {
    var actors: [JellyActor] = []
    /// Actor ids by racer index (0 = the player's Jelly, then the rivals).
    var racers: [Int] = []
    var homes: [Int: SIMD2<Float>] = [:]
    var autonomy: [Int: Bool] = [:]
    var arena: [Int: Float] = [:]
    /// Jellies that stay out of the picture while one practises alone (parked far off the track), by actor id.
    var parked: [Int] = []
    /// Rival body colours while they race, by actor id.
    var palettes: [Int: Palette] = [:]
    /// The welcome home: who came back, whether he won, and how far it has got.
    var returner: Int?
    var won = false
    var homeAge: Float = 0
    var returnerHopped = false
    var celebrated = false
    /// The follow camera's smoothed state on a curved course (Race/RaceCamera.swift); nil until the track is up.
    var follow: RaceFollowPose?
    nonisolated deinit {}
}

extension GameCare {
    /// The brain of Jelly `id` as the stage last gave it (nil in headless setups without a stage).
    func selectBrain(_ id: Int) -> BlobBrain? { raceBook.actors.indices.contains(id) ? raceBook.actors[id].brain : nil }

    func wireRace() {
        select.holdFor = { [weak self] id in self?.selectBrain(id)?.isSleeping ?? false }
        race.wallet = bath.wallet
        race.onSwap = { [weak self] dest in self?.raceSwap(dest) }
        race.onReturned = { [weak self] id, won in self?.raceWelcomeHome(id, won: won) }
        let d = UserDefaults.standard
        race.onLapReset = { [weak self] in self?.drillLapReset() }
        if d.object(forKey: "TrainAuto") != nil { race.drillAuto = true; race.autoReturnAfter = 7 }
        if d.object(forKey: "RaceAuto") != nil { race.autoRate = Float(d.double(forKey: "RaceAuto")) > 0 ? Float(d.double(forKey: "RaceAuto")) : 4; race.autoReturnAfter = 7 }
        // capture aid: -RaceCourse puddle|ripple|splash|wave picks the course for the next race, with every course below it won (open); the ones above stay locked
        if let c = d.string(forKey: "RaceCourse"), let t = CourseTier(rawValue: c.lowercased()) {
            for b in CourseTier.allCases where b.index < t.index { race.progress.records[b] = CourseProgress.Record(races: 1, wins: 1, topTwo: 1) }
            race.courseTier = t
        }
    }

    /// Why a race cannot start for this Jelly right now, in words for the Track panel (nil = it can). A stage that has not ticked yet (the panel was opened
    /// straight at launch, or the game is paused behind it) simply has no bodies listed: that is not a reason, the bodies exist as soon as the room runs.
    func raceBlocker(jelly id: Int) -> String? {
        guard jelly(id) != nil else { return "No such Jelly." }
        if race.active { return "A race is already on." }
        if trayOut || meal != nil || wanted != nil { return "A meal is out. Let him finish first." }
        if bath.active { return "The clean-up is going on." }
        if focus.isActive || focus.phase != .roaming { return "He is in the close-up. Let him go first." }
        if raceWait != nil { return "Waking everybody up." }
        if raceBook.returner != nil { return "Welcome him home first." }
        if voice.mode.phase != .idle || voice.voiceGoing || voice.comingNow { return "He is listening to you." }
        if !raceBook.actors.isEmpty, !(raceBook.actors.indices.contains(id) && raceBook.actors[id].brain != nil) { return "He is not in the room." }
        return nil
    }
    /// "Race" is available for this Jelly: nothing else is going on.
    func canRace(jelly id: Int) -> Bool { raceBlocker(jelly: id) == nil }

    /// The race seed: `-RaceSeed n`, else from the clock.
    static var raceSeed: UInt64 {
        let d = UserDefaults.standard
        if d.object(forKey: "RaceSeed") != nil { return UInt64(max(d.integer(forKey: "RaceSeed"), 0)) }
        return UInt64(Date().timeIntervalSince1970 * 1000) & 0xFFFFFF
    }

    /// Takes Jelly `id` to the track.
    func startRace(jelly id: Int, seed: UInt64? = nil, drill: Bool = false) {
        guard canRace(jelly: id) else { return }
        // A Jelly that is asleep (or going to bed) rolls back up first; the trip starts once everybody is on their feet.
        let sleepers = raceBook.actors.compactMap { $0.brain }.filter { $0.isSleeping }
        if !sleepers.isEmpty {
            for b in sleepers { b.commandedGoodnight = false; b.sleepWake(groggy: false, fast: true) }
            raceWait = RaceWait(id: id, seed: seed, drill: drill)
            for a in raceBook.actors { a.brain?.sleepLocked = true }
            return
        }
        beginRace(jelly: id, seed: seed, drill: drill)
    }

    /// "Train": Jelly `id` practises Rhythm Steps alone on the track.
    func startDrill(jelly id: Int, seed: UInt64? = nil) { startRace(jelly: id, seed: seed, drill: true) }

    /// True from the moment Race is asked (even while a sleeper is still rolling up) until the trip is over: no bedtime, no sleep.
    var raceBusy: Bool { race.active || raceWait != nil }

    private func beginRace(jelly id: Int, seed: UInt64?, drill: Bool = false) {
        guard let prof = jelly(id) else { return }
        select.cancel()
        queued.removeAll(); callRunning = false
        voice.cancel()
        if drill {
            race.stats = prof.stats
            race.beginDrill(playerID: id, name: prof.name, player: RacerStats(waddle: prof.stats.waddle, focus: prof.stats.focus), seed: seed ?? Self.raceSeed)
            return
        }
        let rivals = max(min(raceBook.actors.count, 3) - 1, 0)
        race.stats = prof.stats
        race.begin(playerID: id, name: prof.name, player: RacerStats(waddle: prof.stats.waddle, focus: prof.stats.focus),
                   playerTint: JellyRoster.tint(id), rivalCount: rivals, seed: seed ?? Self.raceSeed, boost: prof.perks.consumeRaceBoost(), course: race.courseTier)
    }

    /// Picks the course for the next race (the Track panel): only an open one.
    @discardableResult
    func chooseCourse(_ t: CourseTier) -> Bool {
        guard race.progress.unlocked(t) else { return false }
        race.courseTier = t
        return true
    }

    /// The body colour a Jelly wears on the track (nil = his own).
    func racePalette(for id: Int) -> Palette? { raceBook.palettes[id] }

    // MARK: world swaps (under the white)

    private func raceSwap(_ dest: RaceFlow.Dest) {
        let book = raceBook
        switch dest {
        case .track:
            guard let sim = race.sim else { return }
            let player = race.playerID
            let others = book.actors.indices.filter { $0 != player }
            book.racers = ([player] + others).prefix(sim.racers.count).map { $0 }
            book.palettes = [:]; book.homes = [:]; book.autonomy = [:]; book.arena = [:]
            book.parked = book.actors.indices.filter { !book.racers.contains($0) }
            for aid in book.parked {                 // practising alone: the others wait far off the track, and come back where they stood
                let a = book.actors[aid]
                guard let brain = a.brain else { continue }
                book.homes[aid] = a.floor; book.autonomy[aid] = brain.autonomy; book.arena[aid] = a.sim.arenaRadius
                a.sim.arenaRadius = .infinity
                let px = 40 + Float(aid) * 4
                a.sim.teleport(toXZ: SIMD2(px, RaceTuning.startZ))
                brain.startRace(sim: a.sim, skinner: a.skinner, heading: 0, laneX: px)          // (the race script keeps the room's floor rules off him, and he just stands there)
                a.skinner.jelly.reset()
            }
            let course = sim.course
            book.follow = nil
            for (k, aid) in book.racers.enumerated() where book.actors.indices.contains(aid) {
                let a = book.actors[aid]
                guard let brain = a.brain else { continue }
                let r = sim.racers[k]
                book.homes[aid] = a.floor
                book.autonomy[aid] = brain.autonomy
                book.arena[aid] = a.sim.arenaRadius
                a.sim.arenaRadius = .infinity
                let spot = course.lanePoint(r.lane, at: 0)                  // on the start line of his lane, facing down the course
                a.sim.teleport(toXZ: spot)
                brain.startRace(sim: a.sim, skinner: a.skinner, heading: course.pose(at: 0).heading, laneX: spot.x, course: course, lane: r.lane)
                a.skinner.jelly.reset()
                if k > 0, k - 1 < race.rivals.count { book.palettes[aid] = LocalRivalSource.palette(for: race.rivals[k - 1].tint, name: race.rivals[k - 1].name) }
            }
        case .room:
            let c = VoiceCoordinator.comeSpot
            var taken: [SIMD2<Float>] = [c]
            for aid in book.racers + book.parked where book.actors.indices.contains(aid) {
                let a = book.actors[aid]
                guard let brain = a.brain else { continue }
                brain.endRace()
                brain.abortScript(a.sim, a.skinner)          // his pose root is the old spot until the script is gone (currentPose reads the body only when he is not driven)
                a.sim.arenaRadius = book.arena[aid] ?? a.sim.arenaRadius
                var spot = aid == race.playerID ? c : (book.homes[aid] ?? Self.greetSpot(aid))
                if aid != race.playerID, taken.contains(where: { simd_distance($0, spot) < 1.5 }) {
                    spot = [SIMD2<Float>(-1.6, 0.4), SIMD2(1.6, 0.4), SIMD2(0, -1.0), SIMD2(-1.8, -1.2)].first { s in !taken.contains { simd_distance($0, s) < 1.5 } } ?? spot
                }
                spot = brain.fixed(spot)          // never back inside a piece of decor put down while he was away (the floor rules push him out)
                taken.append(spot)
                a.sim.teleport(toXZ: spot)
                brain.currentPose(a.sim)
                a.skinner.jelly.reset()
                brain.autonomy = book.autonomy[aid] ?? true
                brain.idleBlocked = false
                brain.restTimer = 2
            }
            book.parked = []
            book.palettes = [:]
            book.follow = nil
        }
    }

    /// The follow camera of a curved course this frame (nil: the Puddle's fixed frame, the drill's own follow, or no race): the leader and the
    /// player framed together from a little way down the track, smoothed by `dt`. See Race/RaceCamera.swift.
    func raceFollow(_ actors: [JellyActor], dt: Float) -> RaceFollowPose? {
        let book = raceBook
        guard race.active, race.trackVisible, race.kind == .race, let sim = race.sim, !sim.course.isStraight else { book.follow = nil; return nil }
        var spots: [RaceFollowPose.Racer] = []
        for (k, aid) in book.racers.enumerated() where actors.indices.contains(aid) && sim.racers.indices.contains(k) {
            guard let b = actors[aid].brain else { continue }
            spots.append(RaceFollowPose.Racer(pos: SIMD2(b.px, b.pz), s: sim.racers[k].dist, isPlayer: k == 0))
        }
        guard !spots.isEmpty else { return book.follow }
        let want = RaceFollowPose.aim(course: sim.course, racers: spots)
        book.follow = book.follow.map { $0.smoothed(toward: want, dt: dt) } ?? want
        return book.follow
    }

    // MARK: per fixed step (the stage calls it every step, with every Jelly)

    func tickRace(_ actors: [JellyActor], dt: Float) {
        raceBook.actors = actors
        for a in actors { a.brain?.sleepLocked = raceBusy }
        if var w = raceWait {
            w.age += dt
            let sleeping = actors.filter { $0.brain?.isSleeping ?? false }
            if w.age > 1.5 && w.age.truncatingRemainder(dividingBy: 1) < dt { for a in sleeping { a.brain?.sleepWake(groggy: false, fast: true) } }
            if w.age > 8 { for a in sleeping { if let b = a.brain { b.abortAll(a.sim, a.skinner); b.idleReset(a.skinner) } } }       // gave up waiting: stand him up
            if sleeping.isEmpty || w.age > 8.5 {
                raceWait = nil
                beginRace(jelly: w.id, seed: w.seed, drill: w.drill)
            } else { raceWait = w }
        }
        raceHome(actors, dt: dt)
        guard race.active else { return }
        let book = raceBook
        func body(_ i: Int) -> JellyActor? { book.racers.indices.contains(i) && actors.indices.contains(book.racers[i]) ? actors[book.racers[i]] : nil }
        if race.phase == .racing, race.sim != nil {
            for i in book.racers.indices {
                guard let a = body(i), let b = a.brain else { continue }
                b.raceKeepAlive()
                if race.kind == .race { race.setMeasured(i, dist: b.raceProgress) }          // his arc length along his lane (pz - startZ on the straight)
            }
        }
        let events = race.tick(dt: dt, bodyFree: { body($0)?.brain?.raceStepFree ?? true }, bodyReady: { body($0)?.brain?.raceBodyReady ?? true },
                               bodyBetween: { body($0)?.brain?.raceBetweenSteps ?? true })
        for e in events {
            if let i = e.racer, let a = body(i), let b = a.brain { b.raceApply(e, sim: a.sim) }
            switch e {
            case .stumble(let i), .trip(let i):
                if i == 0 { touchPlay?.haptics.transient(now: CACurrentMediaTime(), intensity: 0.5, sharpness: 0.2); AudioHub.shared.raceStumble() }
            case .finished(let i, _): if i == 0 { touchPlay?.haptics.transient(now: CACurrentMediaTime(), intensity: 0.8, sharpness: 0.5) }
            default: break
            }
        }
    }

    /// A new lap of the drill: the Jelly is back square on the start line (the lap dip is fully white).
    func drillLapReset() {
        let book = raceBook
        guard let aid = book.racers.first, book.actors.indices.contains(aid), let brain = book.actors[aid].brain else { return }
        let a = book.actors[aid]
        let x = RaceTuning.laneX(RaceTuning.playerLane)
        brain.endRace()
        a.sim.teleport(toXZ: SIMD2(x, RaceTuning.startZ))
        brain.startRace(sim: a.sim, skinner: a.skinner, heading: 0, laneX: x, course: .puddle, lane: RaceTuning.playerLane)          // the drill is always on the straight
        a.skinner.jelly.reset()
    }

    // MARK: welcome home

    /// Back in the room: the other Jellies waddle over to the returner, who hops (everybody bounces together if he won).
    func raceWelcomeHome(_ id: Int, won: Bool) {
        let book = raceBook
        if won { store.awardMedal() }                     // a first place on the Circuit earns the winner medal (wearable from the Bag; never sold)
        book.returner = id; book.won = won; book.homeAge = 0; book.returnerHopped = false; book.celebrated = false
        greetPending = Set((0..<max(jellies.count, 1)).filter { $0 != id && $0 > 0 })
        greetOthers = [:]
        bubbleHub.greetClock = 0; bubbleHub.greetHearts = [:]
        if id != 0 {                               // Bob is one of the greeters: the usual come-to-front walk, then his hop and hearts
            greeting = true; greetHop = false
            queued = [.come(to: greetSpotNow(0))]
        }
    }

    /// Where a Jelly stands for the greeting: the usual spots, except that after a race the RETURNER takes the front spot and the others fan out behind him.
    func greetSpotNow(_ id: Int) -> SIMD2<Float> {
        guard let r = raceBook.returner else { return Self.greetSpot(id) }
        let c = VoiceCoordinator.comeSpot
        if id == r { return c }
        let rest = (0..<max(jellies.count, 1)).filter { $0 != r }
        return (rest.firstIndex(of: id) ?? 0) == 0 ? c + SIMD2(-0.9, -1.5) : c + SIMD2(0.9, -1.5)
    }

    private func raceHome(_ actors: [JellyActor], dt: Float) {
        let book = raceBook
        guard let r = book.returner, !race.active else { return }
        book.homeAge += dt
        // the returner's own hop and hearts
        if !book.returnerHopped, book.homeAge > 0.3, actors.indices.contains(r) {
            book.returnerHopped = true
            if r == 0 { greetHop = true }
            else if let b = actors[r].brain { b.startHopPlay(sim: actors[r].sim, distance: 0.0001); startGreetHearts(r) }
        }
        let arrived = greetPending.isEmpty && greetOthers.isEmpty && !greeting && !greetHop && book.homeAge > 1
        if arrived, book.won, !book.celebrated {      // a win: everybody bounces together once
            book.celebrated = true
            for a in actors { if let b = a.brain { b.startHopPlay(sim: a.sim, distance: 0.0001); AudioHub.shared.chirp(jelly: a.id, .happy) } }
            for a in actors where a.id > 0 { startGreetHearts(a.id) }
            touchPlay?.spawnHeart(now: CACurrentMediaTime())
        }
        if (arrived && (book.celebrated || !book.won) && book.homeAge > 2) || book.homeAge > 25 { book.returner = nil }
    }
}
