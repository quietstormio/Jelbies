//
//  GameCare+Newcomer.swift
//  Bring-home moment ("when you buy a new one make them run in the room like a friend for a sleepover", then "love emotes and group emotes greeting the new one should
//  feel special").
//
//  FIRST Jelbie of a game (nobody else at home): as before. He is set down at the room's back edge, takes the existing come-to-front walk to the middle, then the
//  existing welcome-home (his hop + hearts) runs; the caption is StartFlow's WelcomeBanner. No new moves, no modal.
//
//  A Jelbie bought with others at home (`NewcomerWelcome`, the arrival is the friend's, generalised to drive a roster actor):
//    holding  behind the LaunchGate curtain he is put OFF-SCREEN at the entry point beyond the left edge (Park/GuestArrival.swift `guestArrivalEntry`), held still
//    arrival  once the curtain is gone: the doorbell, the cream card "Ding dong! / <name> is here" (the friend's ArrivalClock + GuestArrivalOverlay, no "getting the room
//             ready" step: his body exists), then he RUNS in (the run gait) and the household turns to look (`arrivalRunIn`, shared with the friend's arrival)
//    greet    each Jelbie at home, one at a time, greets him with a LOVE pair emote through `socialStart` (sway hug, spin hug, cuddle lean, cheek squish, high five, or the
//             shy wave then run), varied per Jelbie; retried 4 s, else happy hops + a heart; hearts rise over the pair
//    group    everybody in a group emote, he in the ring: the group hug (a soft haptic, hearts over everyone and the "Welcome home, <name>!" pill at its squish), then the
//             ring dance and the staggered hop finale (Park/GuestParty.swift, the friend's party, started at the hug / dance / finale as the house needs). A house of two
//             has no group (it takes three): a second pair emote is their "everyone" moment
//    then     autonomy on, nothing held, a small love bump for everyone. A sleeping house is not woken: no bell, no card, he runs in quietly, a hop, a heart, the pill.
//  Any interruption (a close-up, the Bag, an outing, the bath, a meal, a voice command, the app coming back from a long time away) ends it at once and leaves nobody frozen
//  or with autonomy off (an outing started while he was still held snapshots his autonomy as off: `healing` puts it right when the outing is over).
//  A friend's arrival waits for it (GameCare+Guest.swift) and it waits for a friend's.
//

import Foundation
import UIKit
import QuartzCore
import simd

extension GameCare {
    /// Set by StartFlow.bringHome; the next room's first steps consume it.
    nonisolated(unsafe) static var newcomerPending = false
    /// Set with it when others are at home: the launch curtain stays up until he has been put off-screen (`LaunchGate.evaluate`), so he is never seen at his spawn spot.
    nonisolated(unsafe) static var newcomerWithOthers = false
    static let newcomerEdge = SIMD2<Float>(1.1, -2.2)

    /// The autonomy a Jelbie gets back when a close-up, bath, race, outing or trip that snapshots it ends. A bought Jelbie still being welcomed (or healing) is held with
    /// autonomy off: he is saved as "on" so the restore never leaves him frozen.
    func autonomySnapshot(_ id: Int, _ b: BlobBrain) -> Bool { newcomerWelcome?.id == id ? true : b.autonomy }

    func tickNewcomer(_ actors: [JellyActor], dt: Float) {
        guard !isPreview else { return }          // (a showcase stage never takes the pending arrival, and never greets anybody)
        if let w = newcomerWelcome { tickNewcomerWelcome(w, actors, dt: dt); return }
        if var n = newcomer {
            n.age += dt
            guard actors.indices.contains(n.id), let b = actors[n.id].brain else { newcomer = nil; return }
            let calm = b.activity == .idle || b.activity == .lookingAround || b.activity == .steppingInPlace
            n.calm = (calm && n.age > 0.8) ? n.calm + dt : 0
            if n.calm > 0.3 || n.age > 14 || greetBlocked && n.age > 2 { newcomer = nil; raceWelcomeHome(n.id, won: false) } else { newcomer = n }
            return
        }
        guard Self.newcomerPending else { newcomerPendingT = 0; return }
        // a stale flag never fires later: whatever kept the room from taking him within a few seconds drops it (he is then just a housemate, nothing pops in)
        newcomerPendingT += dt
        if newcomerPendingT > 10 { Self.newcomerPending = false; Self.newcomerWithOthers = false; newcomerPendingT = 0; return }
        let rosterCount = max(jellies.count, 1)
        // (a sleepover / play friend's body is the actor after the roster: he is not the newcomer)
        guard actors.count >= rosterCount, actors.indices.contains(rosterCount - 1), let b = actors[rosterCount - 1].brain else { return }
        let last = actors[rosterCount - 1]
        if rosterCount > 1 {
            // others at home: the arrival + welcome. He is taken off-screen on the very first step that sees the roster (the curtain is held for it: `LaunchGate.evaluate`),
            // whether or not a friend is over; the arrival itself waits in `.holding` for a friend's own arrival / party to be over.
            Self.newcomerPending = false; Self.newcomerWithOthers = false; newcomerPendingT = 0
            select.cancel()
            beginNewcomerWelcome(actors, last, b)
            return
        }
        guard actors.count == 1, !LaunchGate.shared.visible else { return }
        Self.newcomerPending = false; Self.newcomerWithOthers = false; newcomerPendingT = 0
        rehome(last, at: Self.newcomerEdge)
        b.requestNow(.come(to: VoiceCoordinator.comeSpot))
        newcomer = NewcomerWalk(id: last.id)
    }

    // MARK: the arrival and welcome

    private func beginNewcomerWelcome(_ actors: [JellyActor], _ na: JellyActor, _ nb: BlobBrain) {
        let others = actors.filter { $0.id != na.id }          // (a friend over counts for where he stands and for a sleeping house, not for the greetings)
        let target = guestSpotNear(others)
        let w = NewcomerWelcome(id: na.id, name: jelly(na.id)?.name ?? "Your Jelbie", target: target, quiet: others.contains { $0.brain?.isSleeping == true })
        rehome(na, at: guestArrivalEntry(toward: target))          // off the left edge, behind the curtain: he is never seen standing in the room first
        nb.autonomy = false; nb.hurry = false
        newcomerWelcome = w
        NSLog("[newcomer] hold id=%d quiet=%d", na.id, w.quiet ? 1 : 0)
    }

    /// Something the player (or the day) is doing that the welcome must not fight.
    private var newcomerInterrupted: Bool {
        greetBlocked || tripActive || raceBusy || select.isSelecting || select.sheetOpen || arranging || greeting || roomSwitch.dest != nil || dining.phase != .absent
    }

    func tickNewcomerWelcome(_ w: NewcomerWelcome, _ all: [JellyActor], dt: Float) {
        let rosterCount = max(jellies.count, 1)
        guard all.count >= rosterCount, all.indices.contains(w.id), let nb = all[w.id].brain else { endNewcomerWelcome(w, all, interrupted: false); return }
        let na = all[w.id]
        let actors = Array(all.prefix(rosterCount))          // the household: the roster only (a friend over is a watcher, he is not pulled into the hellos, the hug or the dance)
        if w.stage == .healing {
            // Heal until nothing that snapshots / restores autonomy is going on (a close-up that began while he was held saved "off" and gives it back when it ends, an
            // outing likewise) AND his autonomy has stayed on for a full second: it is put right every step until then.
            let restoring = focus.phase != .roaming || focusGroup.saved[w.id] != nil || bath.active
            if newcomerInterrupted || restoring { w.healT = 0; return }
            nb.autonomy = true; nb.hurry = false
            w.healT += dt
            if w.healT >= 1 { newcomerWelcome = nil }
            return
        }
        w.t += dt; w.stageT += dt
        // interruptions (not while the curtain is up: nothing can be tapped there)
        if w.stage != .holding {
            w.blockedT = newcomerInterrupted ? w.blockedT + dt : 0
            if w.blockedT > 0.4 { endNewcomerWelcome(w, actors, interrupted: true); return }
        }
        let g = guestBook
        let household = actors.filter { $0.id != w.id }
        // the house went to bed mid-way (a long time in the background): it ends here, nobody is woken
        if !w.quiet, w.stage != .holding, w.stage != .card, w.stage != .runIn, household.contains(where: { $0.brain?.isSleeping == true }) { endNewcomerWelcome(w, actors, interrupted: false); return }
        // queued hearts (the bursts)
        if w.hearts.contains(where: { $0.at <= w.t }) {          // (the bursts are queued out of time order: every one that is due, not just the head)
            let due = w.hearts.filter { $0.at <= w.t }
            w.hearts.removeAll { $0.at <= w.t }
            for h in due { newcomerHeart(h.id) }
        }

        switch w.stage {
        case .holding:
            let friendBusy = g.arrival.active || g.party.active || g.arrivalCard != .hidden          // (a friend's own arrival / party: the card and the room are theirs first)
            if (!LaunchGate.shared.visible || w.t > 8) && (!friendBusy || w.t > 40) {
                if w.quiet { startRunIn(w, na, all) }
                else { _ = w.clock.start(); w.go(.card) }
            }
        case .card:
            for e in w.clock.advance(dt) {
                switch e {
                case .doorbell: AudioHub.shared.play(.doorbell)
                case .showCard: g.arrivalName = w.name; g.arrivalDim = true; g.arrivalCard = .hello          // (the overlay announces "<name> is here" to VoiceOver)
                case .hideCard: g.arrivalCard = .hidden; g.arrivalDim = false
                case .runIn: startRunIn(w, na, all)
                default: break
                }
            }
        case .runIn:
            let calm = nb.activity == .idle || nb.activity == .lookingAround || nb.activity == .steppingInPlace
            w.calm = (calm && w.stageT > 0.8) ? w.calm + dt : 0
            guard w.calm > 0.3 || w.stageT > 12 else { return }
            nb.hurry = false; nb.autonomy = true          // he is a housemate again from here
            if w.quiet {
                nb.startHopPlay(sim: na.sim, distance: 0.0001)
                nb.face(.happy, hold: 2)
                newcomerHeart(w.id)
                showHomecomingPill(na, w)
                w.go(.quiet)
            } else {
                w.greeters = household.filter { $0.brain != nil && $0.brain?.isSleeping == false }
                    .sorted { simd_distance($0.floor, na.floor) < simd_distance($1.floor, na.floor) }.map(\.id)
                w.go(.greet)
            }
        case .quiet:
            if (nb.fxFree && w.stageT > 1.2) || w.stageT > 4 { endNewcomerWelcome(w, actors, interrupted: false) }
        case .greet:
            tickNewcomerGreet(w, actors, na, nb, dt: dt)
        case .group:
            tickNewcomerGroup(w, actors, na, nb, dt: dt)
        case .party:
            tickNewcomerParty(w, actors, na, nb, dt: dt)
        case .healing: break
        }
    }

    private func startRunIn(_ w: NewcomerWelcome, _ na: JellyActor, _ everyone: [JellyActor]) {
        arrivalRunIn(na, to: w.target, household: everyone, voice: !w.quiet)
        if w.quiet { UIAccessibility.post(notification: .announcement, argument: "\(w.name) is here") }
        w.go(.runIn)
    }

    // MARK: greeting (love pairs, one at a time)

    /// The pair emotes that suit a first meeting, in the order tried, varied per Jelbie (the first fitting one that can start is used). Round 2 = a house of two's "everyone" moment.
    static func newcomerKinds(place i: Int, round2: Bool) -> [SocialKind] {
        if round2 { return [.hopAlong, .twirl, .danceOff] }
        switch i % 3 {
        case 0: return [.shyWave, .swayHug, .cuddleLean, .cheekSquish]          // (the shy wave from afar then the run to each other, when the two stand far enough apart)
        case 1: return [.spinHug, .highFive, .cheekSquish, .swayHug]
        default: return [.cuddleLean, .swayHug, .highFive, .spinHug]
        }
    }

    private func tickNewcomerGreet(_ w: NewcomerWelcome, _ actors: [JellyActor], _ na: JellyActor, _ nb: BlobBrain, dt: Float) {
        guard w.greetIndex < w.greeters.count else {
            // everyone has said hello: the group moment (a house of two: a second pair emote)
            let awake = actors.filter { $0.brain?.isSleeping == false }
            if awake.count >= 3 || w.round2 { w.go(.group) }
            else if let only = w.greeters.first(where: { actors.indices.contains($0) && actors[$0].brain?.isSleeping == false }) { w.round2 = true; w.greeters = [only]; w.greetIndex = 0; w.greetPhase = .gap; w.phaseT = 0 }
            else { w.go(.group) }
            return
        }
        let gid = w.greeters[w.greetIndex]
        guard actors.indices.contains(gid), let gb = actors[gid].brain, !gb.isSleeping else { w.nextGreeter(); return }
        w.phaseT += dt
        switch w.greetPhase {
        case .gap:
            if w.phaseT > (w.greetIndex == 0 && !w.round2 ? 0.2 : 0.5) {
                // a welcome that has run long: the later housemates say hello with the quick hop and a heart instead of a whole pair emote (about 25-35 s in all)
                if w.t > Self.newcomerHelloBudget, !w.round2 { quickHello(w, actors, gid, gb, nb); return }
                w.greetPhase = .starting; w.phaseT = 0; w.attempt = 0; w.attemptT = 0
            }
        case .starting:
            w.attemptT -= dt
            if w.attemptT <= 0 {
                w.attemptT = 0.2
                let kinds = Self.newcomerKinds(place: w.greetIndex, round2: w.round2)
                let k = kinds[w.attempt % kinds.count]; w.attempt += 1
                if gb.socialFree, nb.socialFree, gb.socialStart(k, with: nb, actors[gid].sim) {
                    w.greetPhase = .running; w.phaseT = 0
                    NSLog("[newcomer] greet %d -> %@", gid, k.rawValue)
                    return
                }
            }
            if w.phaseT > 2 { quickHello(w, actors, gid, gb, nb) }          // no pair emote fits right now: a little welcome of their own
        case .running:
            let over = gb.social == nil && nb.social == nil && w.phaseT > 0.4
            if over || w.phaseT > Self.newcomerPairCap {          // (a pair emote that runs past the cap is wound down)
                if !over { gb.stop(); nb.stop() }
                // the pair is done: hearts over both, a happy voice each, a small love bump
                w.beatHearts(gid, w.id, at: w.t)
                AudioHub.shared.chirp(jelly: gid, .happy)
                AudioHub.shared.contextVoice(jelly: w.id, .aww, chance: 0.7)
                w.nextGreeter()
            }
        }
    }

    /// The short hello: both look happy, the housemate hops once, a chirp, hearts over the pair.
    private func quickHello(_ w: NewcomerWelcome, _ actors: [JellyActor], _ gid: Int, _ gb: BlobBrain, _ nb: BlobBrain) {
        gb.face(.excited, hold: 2); nb.face(.excited, hold: 2)
        if gb.fxFree, gb.social == nil, !gb.held { gb.startHopPlay(sim: actors[gid].sim, distance: 0.0001) }
        AudioHub.shared.chirp(jelly: gid, .happy)
        w.beatHearts(gid, w.id, at: w.t)
        w.nextGreeter()
    }

    // MARK: the group moment

    private func tickNewcomerGroup(_ w: NewcomerWelcome, _ actors: [JellyActor], _ na: JellyActor, _ nb: BlobBrain, dt: Float) {
        let pairs = actors.compactMap { a in a.brain.map { (a, $0) } }
        let awake = pairs.filter { !$0.1.isSleeping }
        guard awake.count >= 3 else {          // a house of two: they have had their second emote; straight to the hops
            w.party.begin(at: .finale); announceWelcoming(w); w.go(.party); return
        }
        w.phaseT += dt; w.attemptT -= dt
        if w.attemptT <= 0 {
            w.attemptT = 0.3
            // he is the one the ring forms round: the starter, the housemates join
            if nb.socialFree, nb.socialStartGroup(.groupHug, with: awake.map(\.1).filter { $0 !== nb }, na.sim) {
                w.party.begin()          // the hug is on: the party carries on from it (the dance, the hops)
                NSLog("[newcomer] group hug")
                w.go(.party); return
            }
        }
        if w.phaseT > 4 { w.party.begin(at: .dance); announceWelcoming(w); w.go(.party) }          // no hug fits: the dance is tried, then the hops
    }

    private func tickNewcomerParty(_ w: NewcomerWelcome, _ actors: [JellyActor], _ na: JellyActor, _ nb: BlobBrain, dt: Float) {
        let pairs = actors.compactMap { a in a.brain.map { (a, $0) } }
        w.party.step(brains: pairs.map(\.1), sims: pairs.map { $0.0.sim }, dt: dt) { i, v in
            guard pairs.indices.contains(i) else { return }
            let id = pairs[i].0.id
            if v.isContext { AudioHub.shared.contextVoice(jelly: id, v) } else { AudioHub.shared.chirp(jelly: id, v) }
        }
        // the hug's peak (its squish): the homecoming touch. A party that never hugged marks the moment when its dance / hops begin.
        if !w.peaked {
            if let s = nb.social, s.kind == .groupHug, s.impacted { homecomingPeak(w, actors, na) }
            else if w.party.stage == .dance || w.party.stage == .finale { homecomingPeak(w, actors, na) }
        }
        if w.t > Self.newcomerBudget { w.party.skipToFinale() }          // about 25-35 s in all: the dance is dropped when the hellos ran long
        if !w.party.active { endNewcomerWelcome(w, actors, interrupted: false, finished: true) }
    }
    /// Seconds into the welcome after which the ring dance is skipped.
    static let newcomerBudget: Float = 22
    /// Past this many seconds into the welcome the next housemate gets the quick hop + heart; a pair emote is wound down after `newcomerPairCap` s.
    static let newcomerHelloBudget: Float = 14
    static let newcomerPairCap: Float = 10

    /// The soft haptic, the burst of hearts over everyone, the pill and the VoiceOver line.
    private func homecomingPeak(_ w: NewcomerWelcome, _ actors: [JellyActor], _ na: JellyActor) {
        w.peaked = true
        announceWelcoming(w)
        let now = CACurrentMediaTime()
        touchPlay?.haptics.transient(now: now, intensity: 0.4, sharpness: 0.2)          // one soft pulse through the one haptic engine
        for (k, a) in actors.enumerated() {
            newcomerHeart(a.id)
            w.hearts.append((w.t + 0.35 + Float(k) * 0.12, a.id)); w.hearts.append((w.t + 0.9 + Float(k) * 0.12, a.id))
        }
        showHomecomingPill(na, w)
        AudioHub.shared.chirp(jelly: na.id, .happy)
    }

    private func announceWelcoming(_ w: NewcomerWelcome) {
        guard !w.announced else { return }
        w.announced = true
        UIAccessibility.post(notification: .announcement, argument: "Everyone is welcoming \(w.name) home")
    }

    private func showHomecomingPill(_ na: JellyActor, _ w: NewcomerWelcome) {
        let g = guestBook
        g.welcomeLine = "Welcome home, \(w.name)!"; g.welcomeSpan = 2.8; g.welcomeActor = na
        g.welcomeAt = CACurrentMediaTime()
    }

    /// A heart over a Jelbie: Bob's are the touch hearts, the others' the bubble hearts (the guest cheer's paths).
    private func newcomerHeart(_ id: Int) {
        let now = CACurrentMediaTime()
        if id == 0 { touchPlay?.spawnHeart(now: now) } else { bubbleHub.spawnHeart(for: id, now: now) }
    }

    // MARK: the end

    /// `finished`: the welcome played to its end (a small love bump for everyone). `interrupted`: the player or the day took over; an outing that began while he was held
    /// snapshotted his autonomy as off, so the object stays (`healing`) until nothing is going on any more and then puts it right.
    func endNewcomerWelcome(_ w: NewcomerWelcome, _ actors: [JellyActor], interrupted: Bool, finished: Bool = false) {
        let g = guestBook
        g.arrivalCard = .hidden; g.arrivalDim = false
        if interrupted { g.welcomeAt = 0 }
        w.clock.cancel(); w.party.cancel()
        for a in actors { if let b = a.brain, b.social?.involves(w.id) == true { b.stop() } }          // (a session of his, if any, winds down by itself)
        if actors.indices.contains(w.id), let nb = actors[w.id].brain {
            nb.hurry = false; nb.autonomy = true
            if interrupted, w.stage == .holding || w.stage == .card || w.stage == .runIn { rehome(actors[w.id], at: w.target) }          // (still off the floor: put him where he was going)
        }
        if finished {
            for a in actors {          // a small love bump for everyone involved (the same attention need the warm socials raise)
                jelly(a.id)?.needs.gain(.attention, 0.05)
                a.brain?.face(.happy, hold: 2)
            }
        }
        NSLog("[newcomer] end interrupted=%d finished=%d t=%.1f", interrupted ? 1 : 0, finished ? 1 : 0, w.t)
        if interrupted { w.stage = .healing; w.blockedT = 0 } else { newcomerWelcome = nil }
    }
}

struct NewcomerWalk { let id: Int; var age: Float = 0; var calm: Float = 0 }

/// The state of one bought Jelbie's arrival and welcome (no engine in it: `GameCare.tickNewcomerWelcome` drives it).
@MainActor
final class NewcomerWelcome {
    enum Stage { case holding, card, runIn, quiet, greet, group, party, healing }
    enum GreetPhase { case gap, starting, running }
    let id: Int
    let name: String
    let target: SIMD2<Float>
    let quiet: Bool
    var stage: Stage = .holding
    var t: Float = 0, stageT: Float = 0, phaseT: Float = 0, calm: Float = 0, blockedT: Float = 0
    var clock = ArrivalClock(plan: ArrivalClock.newcomerSchedule)
    var party = GuestParty()
    var greeters: [Int] = [], greetIndex = 0, greetPhase: GreetPhase = .gap, attempt = 0, attemptT: Float = 0
    var round2 = false, peaked = false, announced = false
    var healT: Float = 0
    var hearts: [(at: Float, id: Int)] = []

    init(id: Int, name: String, target: SIMD2<Float>, quiet: Bool) { self.id = id; self.name = name; self.target = target; self.quiet = quiet }

    func go(_ s: Stage) { stage = s; stageT = 0; phaseT = 0; attempt = 0; attemptT = 0 }
    func nextGreeter() { greetIndex += 1; greetPhase = .gap; phaseT = 0; attempt = 0; attemptT = 0 }
    /// Two hearts each, a beat apart.
    func beatHearts(_ a: Int, _ b: Int, at now: Float) {
        hearts.append((now, a)); hearts.append((now + 0.1, b)); hearts.append((now + 0.55, a)); hearts.append((now + 0.65, b))
    }
}
