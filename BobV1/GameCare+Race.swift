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
struct RaceWait { var id: Int; var seed: UInt64?; var age: Float = 0 }

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
    /// Temporary rival bodies (the stage's `parkActors`, ids after the roster's) while a roster of fewer than three races, with the spec each wears; gone when the trip is over.
    var extra: [JellyActor] = []
    var extraSpecs: [ParkVisitor] = []
    /// Bodies whose jersey the wear refresh has set (so it can clear it once they are gone).
    var jerseyBodies: Set<Int> = []
    /// The welcome home: who came back, whether he won, and how far it has got.
    var returner: Int?
    var won = false
    var homeAge: Float = 0
    var returnerHopped = false
    var celebrated = false
    /// The follow camera's smoothed state on a curved course (Race/RaceCamera.swift); nil until the track is up.
    var follow: RaceFollowPose?
    /// The Live Activities the race glue drives (the race card, the Pep countdown). Swap for a test double / nil headless.
    var live: LiveActivities? = LiveActivities.shared
    nonisolated deinit {}
}

extension RaceSim {
    /// The player's live standing for the race card: his place (final once he is over the line, else by distance) and 0...1 of the course run.
    var playerStanding: (position: Int, progress: Double) {
        let p = player
        let position = p.place ?? (1 + racers.dropFirst().filter { $0.place != nil || $0.dist > p.dist }.count)
        let progress = RaceTuning.length > 0 ? Double(min(max(p.dist / RaceTuning.length, 0), 1)) : 0
        return (position, progress)
    }
}

extension GameCare {
    /// The brain of Jelly `id` as the stage last gave it (nil in headless setups without a stage).
    func selectBrain(_ id: Int) -> BlobBrain? { raceBook.actors.indices.contains(id) ? raceBook.actors[id].brain : nil }

    func wireRace() {
        race.wallet = bath.wallet
        race.upgrades = upgrades
        race.onSwap = { [weak self] dest in self?.raceSwap(dest) }
        race.onReturned = { [weak self] id, won in self?.raceWelcomeHome(id, won: won) }
        let d = UserDefaults.standard
        if d.object(forKey: "RaceAuto") != nil { race.autoRate = Float(d.double(forKey: "RaceAuto")) > 0 ? Float(d.double(forKey: "RaceAuto")) : 4; race.autoReturnAfter = 7 }
        // capture aid: -RaceCourse puddle|ripple|splash|wave picks the course for the next race, with every course below it won (open); the ones above stay locked
        if let c = d.string(forKey: "RaceCourse"), let t = CourseTier(rawValue: c.lowercased()) {
            for b in CourseTier.allCases where b.index < t.index { race.progress.records[b] = CourseProgress.Record(races: 1, wins: 1, topTwo: 1) }
            race.courseTier = t
        }
    }

    /// The Live Activities (race card, Pep countdown); nil in headless setups that want none.
    var live: LiveActivities? { raceBook.live }

    /// Siri / the widget: "goodnight" goes through the voice goodnight flow (every Jelly to bed), with its guards.
    func goodnight() {
        bedtimeAll()
    }

    /// Why a race cannot start for this Jelly right now, in words for the Track panel (nil = it can). A stage that has not ticked yet (the panel was opened
    /// straight at launch, or the game is paused behind it) simply has no bodies listed: that is not a reason, the bodies exist as soon as the room runs.
    func raceBlocker(jelly id: Int) -> String? {
        guard jelly(id) != nil else { return "No such Jelbie." }
        if race.active { return "Jelly Race is already on." }
        if show.active { return "\(jelly(id)?.name ?? "Your Jelbie") is at the Jelly Show." }
        if volley.active || volleyWork.wait != nil { return "\(jelly(id)?.name ?? "Your Jelbie") is at the beach." }
        if trayOut || meal != nil || wanted != nil { return "A meal is out. Let \(jelly(id)?.name ?? "Your Jelbie") finish first." }
        if bath.active { return "The clean-up is going on." }
        if focus.isActive || focus.phase != .roaming { return "\(jelly(id)?.name ?? "Your Jelbie") is in the close-up. Let go first." }
        if raceWait != nil { return "Waking everybody up." }
        if raceBook.returner != nil { return "Welcome \(jelly(id)?.name ?? "Your Jelbie") home first." }
        if voice.mode.phase != .idle || voice.voiceGoing || voice.comingNow { return "\(jelly(id)?.name ?? "Your Jelbie") is listening to you." }
        if !raceBook.actors.isEmpty, !(raceBook.actors.indices.contains(id) && raceBook.actors[id].brain != nil) { return "\(jelly(id)?.name ?? "Your Jelbie") is not in the room." }
        return nil
    }
    /// The track meet is always three racers: the player and two rivals, whatever the size of the roster.
    static let raceRivalCount = 2
    /// How many temporary rival bodies a roster of `roster` Jelbies needs (the others of the roster race as rivals first).
    static func temporaryRivalBodies(roster: Int) -> Int { max(raceRivalCount - max(roster - 1, 0), 0) }

    /// "Race" is available for this Jelly: nothing else is going on.
    func canRace(jelly id: Int) -> Bool { raceBlocker(jelly: id) == nil }

    /// The race seed: `-RaceSeed n`, else from the clock.
    static var raceSeed: UInt64 {
        let d = UserDefaults.standard
        if d.object(forKey: "RaceSeed") != nil { return UInt64(max(d.integer(forKey: "RaceSeed"), 0)) }
        return UInt64(Date().timeIntervalSince1970 * 1000) & 0xFFFFFF
    }

    /// Takes Jelly `id` to the track.
    func startRace(jelly id: Int, seed: UInt64? = nil) {
        guard canRace(jelly: id) else { return }
        // A Jelly that is asleep (or going to bed) rolls back up first; the trip starts once everybody is on their feet.
        let sleepers = raceBook.actors.compactMap { $0.brain }.filter { $0.isSleeping }
        if !sleepers.isEmpty {
            for b in sleepers { b.commandedGoodnight = false; b.sleepWake(groggy: false, fast: true) }
            raceWait = RaceWait(id: id, seed: seed)
            for a in raceBook.actors { a.brain?.sleepLocked = true }
            return
        }
        beginRace(jelly: id, seed: seed)
    }

    /// True from the moment Race is asked (even while a sleeper is still rolling up) until the trip is over: no bedtime, no sleep. The show's trip too.
    var raceBusy: Bool { race.active || raceWait != nil || show.active || volley.active || volleyWork.wait != nil }

    private func beginRace(jelly id: Int, seed: UInt64?) {
        guard let prof = jelly(id) else { return }
        select.cancel()
        queued.removeAll(); callRunning = false
        voice.cancel()
        if outingGate([id], again: { [weak self] in self?.beginRace(jelly: id, seed: seed) }) { return }          // he runs out of the room first (GameCare+Outing.swift)
        let rivals = Self.raceRivalCount          // always two rivals: a short roster borrows temporary bodies for them at the track (raceSwap)
        race.stats = prof.stats
        race.playerCharacter = prof.character
        race.begin(playerID: id, name: prof.name, player: RacerStats(waddle: prof.stats.waddle, focus: prof.stats.focus),
                   playerTint: JellyRoster.tint(prof.character), rivalCount: rivals, seed: seed ?? Self.raceSeed, boost: raceStartBoost(prof), course: race.courseTier)
        if race.active {           // the race Live Activity (one sprint: lap 1 of 1)
            live?.raceStarted(jellyID: id, name: prof.name, color: JelbieRoster.colorName(JellyRoster.species(prof.character)), racers: race.sim?.racers.count ?? rivals + 1, laps: 1, course: race.courseTier.title)
        }
    }

    /// What the race gets at its start: the eaten race perks (used up) together with the chosen Upgrade power-up (one Bag food, used up). The same perk twice is one boost, not two.
    /// A chosen food that is no longer in the Bag is quietly dropped (and the choice cleared).
    func raceStartBoost(_ prof: JellyProfile) -> RaceBoost {
        let eaten = prof.perks.consumeRaceBoost()
        var power = RaceBoost.none
        if let id = upgrades.chosen(.race, character: prof.character) {
            if let item = StoreCatalog.item(id), item.perk?.raceOnly == true, store.use(id) { power = .powerUp(item.perk) }
            else { upgrades.choose(nil, .race, character: prof.character) }
        }
        return eaten.merged(with: power)
    }

    /// Picks the course for the next race (the Track panel): only an open one.
    @discardableResult
    func chooseCourse(_ t: CourseTier) -> Bool {
        guard race.progress.unlocked(t) else { return false }
        race.courseTier = t
        return true
    }

    /// The body colour a Jelly wears on the track or the show's stage (nil = his own).
    func racePalette(for id: Int) -> Palette? { raceBook.palettes[id] ?? showBook.palettes[id] }

    // MARK: world swaps (under the white)

    private func raceSwap(_ dest: RaceFlow.Dest) {
        let book = raceBook
        switch dest {
        case .track:
            guard let sim = race.sim else { return }
            let player = race.playerID
            let others = book.actors.indices.filter { $0 != player }
            raceSpawnExtras(missing: max(sim.racers.count - 1 - others.count, 0), from: race.rivals.count - max(sim.racers.count - 1 - others.count, 0))
            book.racers = ([player] + others + book.extra.map(\.id)).prefix(sim.racers.count).map { $0 }
            book.palettes = [:]; book.homes = [:]; book.autonomy = [:]; book.arena = [:]
            book.parked = book.actors.indices.filter { !book.racers.contains($0) }
            let all = book.actors + book.extra          // (bodies are indexed by id: the roster's, then the temporary rivals')
            for aid in book.parked {                 // practising alone: the others wait far off the track, and come back where they stood
                let a = book.actors[aid]
                guard let brain = a.brain else { continue }
                book.homes[aid] = a.floor; book.autonomy[aid] = autonomySnapshot(aid, brain); book.arena[aid] = a.sim.arenaRadius
                a.sim.arenaRadius = .infinity
                let px = 40 + Float(aid) * 4
                a.sim.teleport(toXZ: SIMD2(px, RaceTuning.startZ))
                brain.startRace(sim: a.sim, skinner: a.skinner, heading: 0, laneX: px)          // (the race script keeps the room's floor rules off him, and he just stands there)
                a.skinner.jelly.reset()
            }
            let course = sim.course
            book.follow = nil
            for (k, aid) in book.racers.enumerated() where all.indices.contains(aid) {
                let a = all[aid]
                guard let brain = a.brain else { continue }
                let r = sim.racers[k]
                book.homes[aid] = a.floor
                book.autonomy[aid] = autonomySnapshot(aid, brain)
                book.arena[aid] = a.sim.arenaRadius
                a.sim.arenaRadius = .infinity
                let spot = course.lanePoint(r.lane, at: 0)                  // on the start line of his lane, facing down the course
                a.sim.teleport(toXZ: spot)
                brain.startRace(sim: a.sim, skinner: a.skinner, heading: course.pose(at: 0).heading, laneX: spot.x, course: course, lane: r.lane)
                a.skinner.jelly.reset()
                if k > 0, k - 1 < race.rivals.count { book.palettes[aid] = LocalRivalSource.palette(for: race.rivals[k - 1].tint, name: race.rivals[k - 1].name) }
            }
        case .room:
            raceRemoveExtras()
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

    /// A short roster races with temporary rival bodies: the park's visitor bodies (the stage's `parkActors`, like the café regulars and the beach opponents), named and tinted from
    /// the race's rivals `first...` and given the species signature of their colour (purple = wings, yellow = tail + spikes, green = daisy, else none). Removed by `raceRemoveExtras`.
    private func raceSpawnExtras(missing: Int, from first: Int) {
        let book = raceBook
        guard missing > 0, book.extra.isEmpty, let spawn = parkBook.spawn, race.rivals.indices.contains(first) else { return }
        let specs: [ParkVisitor] = (first..<min(first + missing, race.rivals.count)).map { i -> ParkVisitor in
            let r = race.rivals[i]
            if i == first, let g = guestBook.visit, g.arrived, var v = parkBook.visitor(g.visitor) {          // a friend is over: his body is the first temporary rival (his own feature, the rival's name, tint and jersey); he walks in again at home afterwards, the visit untouched
                v = ParkVisitor(id: 9000 + i, name: r.name, colour: v.colour, signature: v.signature, wear: nil, style: v.style, blurb: "", greeting: "")
                return v
            }
            return ParkVisitor(id: 9000 + i, name: r.name, colour: .cream, signature: LocalRivalSource.signature(forTint: r.tint), wear: nil, style: .balanced, blurb: "", greeting: "")
        }
        if guestBook.actor != nil { guestRemove() }          // (the guest's body is normally gone already: an outing puts it away the moment the race is asked)
        let bodies = spawn(specs, specs.indices.map { SIMD2<Float>(40 + Float($0) * 3, 0) })
        guard bodies.count == specs.count, bodies.enumerated().allSatisfy({ $0.element.id == book.actors.count + $0.offset }) else { parkBook.clear?(); return }
        book.extra = bodies; book.extraSpecs = specs
        for a in bodies { a.sim.arenaRadius = .infinity }
    }

    /// The temporary rival bodies go (the swap home, under the white): looks put away, bodies hidden, nothing left at home.
    func raceRemoveExtras() {
        let book = raceBook
        guard !book.extra.isEmpty else { return }
        for a in book.extra { a.brain?.endRace(); a.brain?.abortScript(a.sim, a.skinner); visitorPutAway(a) }
        parkBook.clear?()
        book.racers.removeAll { id in book.extra.contains { $0.id == id } }
        book.palettes = book.palettes.filter { k, _ in !book.extra.contains { $0.id == k } }
        book.extra = []; book.extraSpecs = []
    }

    /// The follow camera of a curved course this frame (nil: the Puddle's fixed frame, the drill's own follow, or no race): the leader and the
    /// player framed together from a little way down the track, smoothed by `dt`. See Race/RaceCamera.swift.
    func raceFollow(_ actors: [JellyActor], dt: Float) -> RaceFollowPose? {
        let book = raceBook
        guard race.active, race.trackVisible, let sim = race.sim, !sim.course.isStraight, !A11ySettings.shared.reduceMotion else { book.follow = nil; return nil }          // (Reduce Motion: the wide fixed frame, no banking follow camera)
        var spots: [RaceFollowPose.Racer] = []
        let actors = book.extra.isEmpty ? actors : actors + book.extra
        for (k, aid) in book.racers.enumerated() where actors.indices.contains(aid) && sim.racers.indices.contains(k) {
            guard let b = actors[aid].brain else { continue }
            spots.append(RaceFollowPose.Racer(pos: b.raceSpot, s: sim.racers[k].dist, isPlayer: k == 0))
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
                beginRace(jelly: w.id, seed: w.seed)
            } else { raceWait = w }
        }
        tickNewcomer(actors, dt: dt)
        raceHome(actors, dt: dt)
        if !race.active, let l = live, l.raceLive { l.raceFinished(place: 0, drops: 0) }          // a trip that ended without results (abort): the card goes quietly
        guard race.active else { return }
        let book = raceBook
        let all = book.extra.isEmpty ? actors : actors + book.extra          // (the temporary rivals' ids continue after the roster's)
        func body(_ i: Int) -> JellyActor? { book.racers.indices.contains(i) && all.indices.contains(book.racers[i]) ? all[book.racers[i]] : nil }
        for (a, v) in zip(book.extra, book.extraSpecs) { visitorLook(a, v, dt: dt, role: wearRole(for: a.id)) }          // their species signature and team jersey
        if race.phase == .racing, race.sim != nil {
            for i in book.racers.indices {
                guard let a = body(i), let b = a.brain else { continue }
                b.raceKeepAlive()
                do { race.setMeasured(i, dist: b.raceProgress(sim: a.sim)) }          // his arc length along his lane (pz - startZ on the straight)
            }
        }
        let events = race.tick(dt: dt, bodyFree: { body($0)?.brain?.raceStepFree ?? true }, bodyReady: { body($0)?.brain?.raceBodyReady ?? true },
                               bodyBetween: { body($0)?.brain?.raceBetweenSteps ?? true })
        for e in events {
            if let i = e.racer, let a = body(i), let b = a.brain { b.raceApply(e, sim: a.sim) }
            switch e {
            case .stumble(let i), .trip(let i):
                if i == 0 { touchPlay?.haptics.transient(now: CACurrentMediaTime(), intensity: 0.5, sharpness: 0.2); AudioHub.shared.raceStumble() }
            case .hurdleCleared(let i): if i == 0 { touchPlay?.haptics.transient(now: CACurrentMediaTime(), intensity: 0.4, sharpness: 0.7); AudioHub.shared.chirp(jelly: race.playerID, .happy) }
            case .finished(let i, _): if i == 0 { touchPlay?.haptics.transient(now: CACurrentMediaTime(), intensity: 0.8, sharpness: 0.5) }
            case .results: do { live?.raceFinished(place: race.sim?.playerPlace ?? 0, drops: race.earned) }          // (settled by the flow before the event reaches us)
            default: break
            }
        }
        if race.phase == .racing, let sim = race.sim, sim.phase != .results {
            let st = sim.playerStanding
            live?.raceProgress(position: st.position, progress: st.progress, lap: 1)          // the policy only publishes a change of place / a quarter of the course
        }
    }

    // MARK: welcome home

    /// Back in the room: the other Jellies waddle over to the returner, who hops (everybody bounces together if he won).
    func raceWelcomeHome(_ id: Int, won: Bool) {
        let book = raceBook
        if won { AudioHub.shared.contextVoice(jelly: id, .yay, chance: 1); selectBrain(id)?.proudStrutCue() }       // (batch-2 emote: he struts when he is next free)
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
            for a in actors {
                guard let b = a.brain else { continue }
                if b.feature == .wings, !b.wingsFolded, b.idleState.kind == nil { b.commandedIdle = .flapHop } else { b.startHopPlay(sim: a.sim, distance: 0.0001) }
                AudioHub.shared.chirp(jelly: a.id, .happy)
            }
            for a in actors where a.id > 0 { startGreetHearts(a.id) }
            touchPlay?.spawnHeart(now: CACurrentMediaTime())
        }
        if (arrived && (book.celebrated || !book.won) && book.homeAge > 2) || book.homeAge > 25 { book.returner = nil }
    }
}
