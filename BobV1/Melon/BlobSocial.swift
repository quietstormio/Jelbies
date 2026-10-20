//
//  BlobSocial.swift
//  Jellies interact with each other (the user: "I want to see them interact with each other"). A brain-level layer that works with 1...3 brains and
//  does not care how the stage holds them: each brain gets `steerID` and `socialOthers` (the other brains; the steering keeps using `peers` only, whose ids are
//  not identities: a standing Jelly has a huge id); `SocialRoster.link` wires both.
//
//  Only existing moves and gaits: the walk (and the run: zoomies), the hop, the LOOK idle, the jelly kick (JellyJiggle), the pose overlays that
//  the touch play already uses for its annoyed reaction (a small forward pitch + narrowed eyes read as a frown with the flat brows) and squash
//  pulses. Body, face, walk, arms (stubby) and feet (attached) are untouched; a social is a SEQUENCER that sets the same scripts the
//  scheduler sets, so the foot / arm invariants are the existing moves' own.
//
//  Kinds (one session per pair at a time, brain-wide cooldown 12...25 s, pair cooldown 25...45 s, a roll of `pickChance` per autonomous pick):
//    look      the LOOK idle aims at a nearby Jelly; the other glances back a moment later
//    boop      one walks up to the other (stops at `boopGap`, a little under peerGap), a short bump: both squish / jiggle, a heart, a light haptic
//    follow    one follows the other's wander legs at a gap for 6...9 s, then both go on their way
//    zoomies   when one starts zoomies a nearby Jelly may join, running a loop around the point where the first one stops
//    greet     two that meet after being apart a while (20 s) turn to each other and both hop
//    squabble  (more often when one is grumpy) a face-off: puffy jiggle, narrowed eyes, a few small shove-bumps (lean in + recoil, nobody moves);
//              ends by itself after 5...8 s or at once on `stopFighting()`: both stop, step apart, a sheepish look (and, after a stop, a small
//              happy hop + hearts: making up)
//  Never during a meal, bath, focus close-up (`idleBlocked`), voice action (`commanded`...), a pending request or while the player touches him.
//  Voice hooks: `BlobBrain.stopFighting()`, `BlobBrain.stop()` (and the same on `SocialRoster`). Stage hooks: `onSocial` events.
//

import Foundation
import simd

enum SocialKind: String, CaseIterable, Sendable {
    case look, boop, follow, zoomies, greet, squabble
    // more play (2026-10-19), BlobSocial+Play.swift: all sequenced from the existing moves
    case chase          // tag: one runs, the other chases, a tag (a soft bump), the roles swap
    case bump           // belly bump: both lean in and bounce off each other (a jelly kick each), then a hop
    case nuzzle         // side by side, heads leaning together, eyes half shut
    case sitTogether    // side by side on the rug: both sit
    case dance          // synchronised: both do the jumping jacks (or happy bounces)
    case sneak          // one sneaks up behind the other and boops him: a startle hop
    case keepAway       // one keeps dodging (scoot hops) away from the other near the sofa
    case line           // follow the leader, a line of three (or two)
    // 2026-10-20 (more interaction): both from existing moves, BlobSocial+Pass.swift
    case pass           // ball pass: the ball is kicked to the partner, who kicks it back (2...4 passes)
    case bagSit         // sit together on the beanbag / cushion (a second piece each, else one on it and one beside it)
    // 2026-10-20 (batch 2): BlobSocial+Toss.swift
    case cuddle         // two Jellies on the two cushions of the loveseat: both settle, then lean toward each other
    case toss           // football: one throws (hug, squat, fling, or a fumble), the other tries to catch it by hugging it, or misses comically; then they swap
}

enum SocialEnd: Sendable { case done, brokenUp, stopped, aborted }

/// What the stage / care model reacts to (all optional).
enum SocialEvent {
    case began(SocialKind, partner: Int)
    case ended(SocialKind, partner: Int, SocialEnd)       // squabble: `.done` = it wore off, `.brokenUp` = stopFighting (a small attention / mood cost either way)
    case boop(partner: Int)                               // a heart above him + a light haptic if the player has him in focus
    case shove(partner: Int)                              // a squabble bump (light haptic)
    case makeUp(partner: Int)                             // small happy reaction after a stopFighting (hearts)
}

enum SocialTuning {
    /// (tests turn this up to make every pick a social)
    nonisolated(unsafe) static var pickChance: Float = 0.24
    static let brainCooldown: (Float, Float) = (6, 12.5)
    static let pairCooldown: (Float, Float) = (12.5, 22.5)
    /// While the player is watching the room (`BlobBrain.watching`): roughly twice the chance and half the waits.
    /// Rounds of tag / keep-away.
    static let chaseRounds = 3, keepAwayRounds = 2
    /// The social floor: a Jelly that has had no social for this long (seconds, drawn per Jelly) asks for one, whatever the pick chance (still never while another session is on).
    static let droughtRange: (Float, Float) = (36, 50)
    /// An invited (wandering) partner has this long to finish his leg.
    static let inviteWait: Float = 3.5
    /// Chance that a nearby free Jelly joins a zoomies, and how far he may be (the zoomies used to be solo most of the time).
    static let zoomJoin: Float = 0.8, zoomJoinRadius: Float = 6
    static let livelyChance: Float = 4.0, livelyWait: Float = 0.25
    static let lookCooldown: Float = 20
    /// The closer gap of the boop / squabble pair only (everybody else keeps `peerGap`).
    static let greetApart: Float = 20
    static let squabbleBase: Float = 0.35, squabbleGrumpy: Float = 3.0
}

/// Per-brain bookkeeping and the render-side overlay state.
struct SocialBook {
    var enabled = true
    var cooldown: Float = 10                     // brain-wide, until the next social may start
    var pair: [Int: Float] = [:]                 // per partner
    var lookPair: [Int: Float] = [:]
    var apart: [Int: Float] = [:]                // seconds apart (far, or the other one away / busy) -> greeting
    var near: [Int: Float] = [:]
    var lookPeer: Int?                           // consumed by idleStart(.look)
    var lookAway = false
    var lookHold: Float = 0
    var glanceDelay: Float = 0
    var glanceDone = false
    var hold = false                             // stand and face `faceYaw` instead of the camera
    var faceYaw: Float?
    var pitch: Float = 0, roll: Float = 0, squash: Float = 1
    var wantPitch: Float = 0, wantRoll: Float = 0, wantSquash: Float = 1, wantEyes: Float = 1
    var squinting = false
    var stopAll = false
    var apartStarted = false, sheepishStarted = false, hopStarted = false, hopStarted2 = false
    var started: [SocialKind: Int] = [:]
    var lastKind: SocialKind?
    var roundSeen = -1
    /// Seconds since this Jelly's last social (counts only while he is awake and free to join): the floor asks for one past `droughtLimit`.
    var drought: Float = 0
    var droughtLimit: Float = 43
    /// A wandering partner was asked to stop; the social starts when his leg is over (or is dropped after `inviteWait`).
    var invite: (kind: SocialKind, id: Int, t: Float)?
    /// Wake-up greeting: a Jelly in the room woke (`greetWho`); after `wakeGreet` seconds this one looks at him and hops (`greetHop`).
    var wakeGreet: Float = -1
    var greetWho = -1
    var greetHop = false
}

final class SocialSession {
    let kind: SocialKind
    weak var a: BlobBrain?                       // the initiator (follow: the follower)
    weak var b: BlobBrain?                       // follow: the leader
    weak var c: BlobBrain?                       // line: the second follower (follows `a`)
    var idC = -1
    let idA: Int, idB: Int
    var phase = 0
    var t: Float = 0, phaseT: Float = 0
    var duration: Float = 0
    var end: SocialEnd?
    var broke = false                            // squabble: stopFighting() was called
    var bumpT: Float = -1, bumper = 0, bumpNext: Float = 1.2, impacted = false, bumps = 0
    var fightT: Float = 0
    var leaderWait: Float = 0
    var closeOK: Bool { kind == .boop || kind == .squabble || kind == .bump || kind == .sneak || kind == .nuzzle || kind == .sitTogether || kind == .bagSit || kind == .cuddle }
    var round = 0, roles = 0, fastMoves = 0
    /// Ball pass: the decor piece, the passes made / wanted.
    var uid = -1, passes = 0, passTarget = 3
    var goal = SIMD2<Float>.zero
    init(kind: SocialKind, a: BlobBrain, b: BlobBrain) { self.kind = kind; self.a = a; self.b = b; idA = a.steerID; idB = b.steerID }
    nonisolated deinit {}
    func involves(_ id: Int) -> Bool { id == idA || id == idB || id == idC }
    func setPhase(_ p: Int) { phase = p; phaseT = 0 }
    func finish(_ how: SocialEnd) { if end == nil { end = how } }
}

/// Wires N brains together for the social layer (steerID, the others). Positions for steering stay the stage's `peers` closure; the stage can wire `socialOthers` by hand.
final class SocialRoster {
    private struct Box { weak var b: BlobBrain? }
    private var boxes: [Box] = []
    nonisolated deinit {}
    var brains: [BlobBrain] { boxes.compactMap { $0.b } }

    @discardableResult
    static func link(_ list: [BlobBrain]) -> SocialRoster {
        let r = SocialRoster()
        r.boxes = list.map { Box(b: $0) }
        for (i, b) in list.enumerated() {
            b.steerID = i
            b.zoomUrge = IdleTuning.zoomUrgeFirst + 35 * Float(i)          // (the first zoomies urge: staggered, so they do not all go at once)
            b.socialOthers = { [weak r] in r.map { $0.brains.filter { $0 !== b } } ?? [] }
        }
        return r
    }
    /// Voice "stop fighting": true when a squabble was running.
    @discardableResult func stopFighting() -> Bool { brains.reduce(false) { $1.stopFighting() || $0 } }
    /// Voice "stop": every social ends now.
    func stop() { for b in brains { b.stop() } }
}

// MARK: - the brain's side

extension BlobBrain {
    // MARK: state the stage / voice can read
    var isSocial: Bool { social != nil }
    var socialKind: SocialKind? { social?.kind }
    var socialPartnerID: Int? { guard let s = social else { return nil }; return s.idA == steerID ? s.idB : s.idA }
    var isSquabbling: Bool { if let s = social, s.kind == .squabble, s.end == nil, s.phase <= 1 { return true }; return false }
    var socialStarts: [SocialKind: Int] { socialBook.started }

    /// Centre distance this brain keeps from `id` (the closer gap for his boop / squabble partner only).
    func socialGap(at pos: SIMD2<Float>) -> Float {
        if let s = social, s.closeOK, s.end == nil, let o = (s.a === self ? s.b : s.a), simd_distance(o.position, pos) < 0.05 { return peerGap * 0.92 }
        return peerGap
    }
    var followGap: Float { max(1.15, peerGap + 0.15) }

    // MARK: voice hooks

    /// Voice "stop fighting": the squabble stops NOW (both stop at once, step apart, a sheepish look, then a small happy reaction). True = one was on.
    @discardableResult
    func stopFighting() -> Bool {
        guard let s = social, s.kind == .squabble, s.end == nil else { return false }
        s.broke = true
        if s.phase < 2 { s.setPhase(2); s.bumpT = -1 }
        return true
    }
    /// Voice "stop": whatever social is on ends at once (handled on the next tick).
    func stop() { socialBook.stopAll = true }

    // MARK: availability

    var scriptIsNone: Bool { if case .none = script { return true }; return false }

    /// Free to start / join a social: idle, autonomous, nothing else owns him.
    var socialFree: Bool {
        social == nil && socialBook.enabled && attached && (autonomy || idleForced) && !idleBlocked && !commanded && pending == nil && job == nil
            && commandedIdle == nil && !commandedFlip && !commandedNameHop && !interruptScript && !hurry
            && activity != .touched && activity != .recovering && scriptIsNone && idleState.kind == nil
    }
    /// Out on an ordinary wander leg: autonomous, nothing owns him, no behaviour running. He can be invited to a social (his leg is ended at the next stretch of the walk).
    var socialWandering: Bool {
        guard social == nil, socialBook.enabled, attached, autonomy || idleForced, !idleBlocked, !commanded, pending == nil, job == nil, commandedIdle == nil,
              !commandedFlip, !commandedNameHop, !interruptScript, !hurry, !race.active, idleState.kind == nil, activity == .walking else { return false }
        if case .walk = script { return true }
        return false
    }
    /// Invited: the wander leg ends a few steps on, straight ahead (a new target on the line he is already walking: no curve, no mid-stride re-aim of the feet).
    @discardableResult
    func socialBeckonStop() -> Bool {
        guard case .walk(let t0, _) = script else { return false }
        let here = position
        let w = route.first ?? t0
        let d = simd_distance(w, here)
        guard d > 0.5 else { return true }          // (nearly there: the leg ends by itself)
        let t = here + (w - here) / d * 0.4
        let q = fixed(t)
        guard simd_distance(q, t) < 0.08, peerFree(q) else { return false }          // (a stop spot the floor rules or a neighbour would move: leave the leg alone, no invite)
        route = []
        script = .walk(target: q, then: .none)
        return true
    }
    /// Something took one of the pair away (touch, meal, bath, focus, voice, a request).
    var socialTaken: Bool {
        pending != nil || idleBlocked || commanded || commandedIdle != nil || commandedFlip || commandedNameHop || interruptScript || job != nil
            || activity == .touched || activity == .recovering
    }

    func socialBrain(_ id: Int) -> BlobBrain? { socialOthers().first { $0.steerID == id } }

    func yawTo(_ p: SIMD2<Float>) -> Float { atan2f(p.x - px, p.y - pz) }

    func socialWalk(to t: SIMD2<Float>, _ sim: SoftBody) {
        currentPose(sim)
        scriptT = 0; stuckT = 0; bestDist = .infinity; route = []; steerStall = 0; job = nil
        script = .walk(target: t, then: .none); activity = .walking
    }

    // MARK: starting

    func newSession(_ kind: SocialKind, with o: BlobBrain, duration: Float, third: BlobBrain? = nil) -> SocialSession {
        let s = SocialSession(kind: kind, a: self, b: o)
        s.duration = duration
        social = s; o.social = s
        if let c = third { s.c = c; s.idC = c.steerID; c.social = s; c.socialBook.glanceDone = false }
        socialBook.started[kind, default: 0] += 1
        socialBook.drought = 0; o.socialBook.drought = 0; socialBook.invite = nil; o.socialBook.invite = nil
        socialBook.droughtLimit = rand(SocialTuning.droughtRange.0, SocialTuning.droughtRange.1); o.socialBook.droughtLimit = rand(SocialTuning.droughtRange.0, SocialTuning.droughtRange.1)
        socialBook.wakeGreet = -1; o.socialBook.wakeGreet = -1
        s.fastMoves = 0
        socialBook.glanceDone = false; o.socialBook.glanceDone = false
        socialBook.apartStarted = false; o.socialBook.apartStarted = false
        socialBook.sheepishStarted = false; o.socialBook.sheepishStarted = false
        socialBook.hopStarted = false; o.socialBook.hopStarted = false
        onSocial?(.began(kind, partner: o.steerID)); o.onSocial?(.began(kind, partner: steerID))
        return s
    }

    /// Start `kind` with `o` now (the scheduler's autonomous pick calls this; tests call it directly). False = not possible right now
    /// (either one is busy / blocked, too far or too near for this kind, no room).
    @discardableResult
    func socialStart(_ kind: SocialKind, with o: BlobBrain, _ sim: SoftBody) -> Bool {
        guard socialFree, o.socialFree, o !== self else { return false }
        currentPose(sim)          // (his own body only: the partner has a sim of his own, and re-seeding HIS root from THIS sim teleported him onto the initiator)
        let me = position, you = o.position
        let d = simd_distance(me, you)
        switch kind {
        case .boop, .squabble:
            guard d > 0.5, d < 5.5 else { return false }
            let gap = peerGap
            let away = (me - you) / max(d, 1e-3)
            let spot = fixed(you + away * gap)
            guard simd_distance(spot, you) < gap + 0.3 else { return false }
            let s = newSession(kind, with: o, duration: kind == .squabble ? rand(5, 8) : 0)
            o.socialBook.hold = true; o.socialBook.faceYaw = o.yawTo(me)
            if simd_distance(me, spot) > 0.12 { socialWalk(to: spot, sim) } else { s.setPhase(1) }
        case .follow:
            guard d > peerGap * 0.8, d < 5.5 else { return false }
            let s = newSession(.follow, with: o, duration: anticsEnabled ? rand(4.5, 7) : rand(6, 9))
            s.leaderWait = 0.2
        case .greet:
            guard d < 2.6 else { return false }
            _ = newSession(.greet, with: o, duration: 0)
            for x in [self, o] { x.socialBook.hold = true }
            socialBook.faceYaw = yawTo(you); o.socialBook.faceYaw = o.yawTo(me)
        case .look:
            guard d < 5.5 else { return false }
            let s = newSession(.look, with: o, duration: 12)
            _ = s
            socialBook.lookPeer = o.steerID
            socialBook.lookHold = rand(1.4, 2.2)
            o.socialBook.glanceDelay = rand(0.5, 1.1)
            if !idleStart(.look, sim) { social = nil; o.social = nil; return false }
        case .chase, .bump, .nuzzle, .sitTogether, .dance, .sneak, .keepAway, .line, .pass, .bagSit, .cuddle, .toss:
            return socialStartPlay(kind, with: o, sim)
        case .zoomies:
            guard d < 6 else { return false }
            guard idleState.kind == nil else { return false }
            guard idleStart(.zoomies, sim) else { return false }
            guard let pts = o.zoomLoop(around: idleState.target) else { return false }       // (he runs alone)
            _ = newSession(.zoomies, with: o, duration: 22)
            _ = o.socialRunLoop(pts, sim)
        }
        return true
    }

    /// The scheduler's roll (top of pickAutonomous). True = a social started.
    func socialMaybeStart(_ sim: SoftBody) -> Bool {
        guard socialBook.enabled, social == nil, socialBook.cooldown <= 0, socialFree, idleDeepNight < 0.5 else { return false }
        if socialBook.invite != nil { return true }          // waiting for the invited partner's leg to end
        let ps = socialOthers().map { (id: $0.steerID, pos: $0.position, b: $0) }
        if ps.isEmpty { return false }
        // the social floor: nobody has had one for ~45 s and none is on now -> ask for one (never stacked on a running session)
        let starved = anticsEnabled && socialBook.drought > socialBook.droughtLimit && ps.allSatisfy { $0.b.social == nil }
        var cands: [(BlobBrain, Float)] = []
        for p in ps {
            let o = p.b
            guard o.socialFree || (anticsEnabled && o.socialWandering), (socialBook.pair[p.id] ?? 0) <= 0, (o.socialBook.pair[steerID] ?? 0) <= 0, o.socialBook.cooldown <= 6 else { continue }
            let d = simd_distance(p.pos, position)
            if d > peerGap * 0.8 && d < 4.8 { cands.append((o, d)) }
        }
        if cands.isEmpty { return false }
        guard starved || rand() < SocialTuning.pickChance * (watching ? SocialTuning.livelyChance : 1) * (perkFlags.social ? PerkTuning.socialBoost : 1) else { return false }
        let o = cands[min(cands.count - 1, Int(rand() * Float(cands.count)))].0
        let grumpy = idleMood == .grumpy || o.idleMood == .grumpy
        var w: [(SocialKind, Float)] = [(.boop, 3), (.follow, 2), (.squabble, grumpy ? SocialTuning.squabbleGrumpy : SocialTuning.squabbleBase)]
        if anticsEnabled { w = socialPlayWeights(base: w, partner: o, others: cands.map { $0.0 }, grumpy: grumpy) }
        let total = w.reduce(0) { $0 + $1.1 }
        var x = rand() * total
        var kind = w[0].0
        for (k, wt) in w { if x < wt { kind = k; break }; x -= wt }
        if anticsEnabled { socialBook.lastKind = kind }
        if !o.socialFree {          // he is out on a wander leg: ask him to stop; the social starts when he has (socialInviteTick)
            guard o.socialBeckonStop() else { socialBook.cooldown = max(socialBook.cooldown, 3); return false }
            socialBook.invite = (kind, o.steerID, 0)
            return true
        }
        return socialStart(kind, with: o, sim)
    }

    /// idleMaybeStart picked LOOK: sometimes at a nearby Jelly (who glances back).
    func socialPrepareLook(_ sim: SoftBody) {
        guard socialBook.enabled, socialFree else { return }
        let ps = socialOthers().map { (id: $0.steerID, pos: $0.position, b: $0) }
        if ps.isEmpty { return }
        var cands: [BlobBrain] = []
        for p in ps {
            let o = p.b
            guard o.socialFree, (socialBook.lookPair[p.id] ?? 0) <= 0 else { continue }
            if simd_distance(p.pos, position) < 4.2 { cands.append(o) }
        }
        if cands.isEmpty || rand() > 0.6 {
            // nobody to glance back: tiptoe a look at a sleeper instead
            if let z = socialOthers().filter({ $0.idleState.kind == .sleep && simd_distance($0.position, position) < 5.5 }).min(by: { simd_distance($0.position, position) < simd_distance($1.position, position) }), rand() < 0.6 {
                socialBook.lookPeer = z.steerID; socialBook.lookHold = rand(1.6, 2.6)
            }
            return
        }
        let o = cands[min(cands.count - 1, Int(rand() * Float(cands.count)))]
        let s = newSession(.look, with: o, duration: 12)
        _ = s
        socialBook.lookPeer = o.steerID
        socialBook.lookHold = rand(1.4, 2.2)
        o.socialBook.glanceDelay = rand(0.5, 1.1)
    }

    /// idleStart(.look) reads this: aim at the Jelly (or, sheepish, a little away from him).
    func socialLookAim() -> (yaw: Float, hold: Float)? {
        guard let id = socialBook.lookPeer else { return nil }
        socialBook.lookPeer = nil
        guard let o = socialBrain(id) else { return nil }
        let to = yawTo(o.position)
        if socialBook.lookAway {
            socialBook.lookAway = false
            return (wrapAngle(to + idleState.sign * 1.1), 1.5)
        }
        return (to, socialBook.lookHold > 0 ? socialBook.lookHold : 1.6)
    }

    /// idleMaybeStart started zoomies: a nearby Jelly may join, running a loop around where this one stops.
    func socialOfferZoomies(_ sim: SoftBody) {
        guard socialBook.enabled, social == nil, !commanded, runMoveDemo == nil else { return }
        let ps = socialOthers().map { (id: $0.steerID, pos: $0.position, b: $0) }
        if ps.isEmpty { return }
        var cands: [BlobBrain] = []
        for p in ps {
            let o = p.b
            guard o.socialFree, (socialBook.pair[p.id] ?? 0) <= 0, simd_distance(p.pos, position) < SocialTuning.zoomJoinRadius else { continue }
            cands.append(o)
        }
        if cands.isEmpty || rand() > SocialTuning.zoomJoin { return }
        let o = cands[min(cands.count - 1, Int(rand() * Float(cands.count)))]
        guard let pts = o.zoomLoop(around: idleState.target) else { return }
        _ = newSession(.zoomies, with: o, duration: 22)
        _ = o.socialRunLoop(pts, sim)
    }

    /// The loop for a joiner: waypoints on a circle (r 1.15, or 1.0) around `c`, the arc inside the room that is nearest to him. A full lap when
    /// the whole octagon fits, else the longest arc that does (>= 135 degrees: the room is small and the leader often stops near a wall). nil = no room.
    func zoomLoop(around c: SimdF2) -> [SimdF2]? {
        let here = position
        let n = 8          // an octagon: the corners are 45 degrees, so the walker turns on the spot there (a validated move) and runs straight sides; a smooth circle would make a curving walk, whose feet detach
        let theta0 = atan2f(here.x - c.x, here.y - c.y)
        for r: Float in [peerGap + 0.15, peerGap + 0.05] {
            var pt = [SimdF2](), ok = [Bool]()
            for k in 0..<n {
                let th = theta0 + Float(k) * 2 * .pi / Float(n)
                let p = c + SIMD2(sinf(th), cosf(th)) * r
                let q = fixed(p)
                pt.append(q); ok.append(simd_distance(p, q) < 0.25)
            }
            let dir: Float = rand() < 0.5 ? 1 : -1
            if ok.allSatisfy({ $0 }) {
                // the whole circle: one lap and a bit, from the point nearest to him (index 0), either way round
                return (0...n).map { pt[(($0 * (dir > 0 ? 1 : -1)) % n + n) % n] }
            }
            // longest run of valid points (circular), walked in the direction `dir`
            var best: [Int] = [], k = 0
            while k < n {
                guard ok[k] else { k += 1; continue }
                var run = [Int](), m = k
                while ok[m % n] && run.count < n { run.append(m % n); m += 1 }
                if run.count > best.count { best = run }
                k = max(k + 1, m)
            }
            if best.count >= 4 {
                if dir < 0 { best.reverse() }
                // start at the end nearer to him
                if simd_distance(pt[best.first!], here) > simd_distance(pt[best.last!], here) { best.reverse() }
                return best.map { pt[$0] }
            }
        }
        return nil
    }

    /// Run the loop (the run gait: its turns keep the feet attached, the zoomies' cadence does not) through the waypoints (the route), ending at the last one.
    func socialRunLoop(_ pts: [SimdF2], _ sim: SoftBody) -> Bool {
        currentPose(sim)
        socialWalk(to: pts.last!, sim)
        route = Array(pts.dropLast())
        return true
    }

    // MARK: per tick

    /// Every tick (after the idle gate, before the scripts run): cooldowns, greeting watch, the running session, the overlay easing.
    func socialTick(_ sim: SoftBody, _ skinner: Skinner, _ dt: Float) {
        let blocked = idleBlocked || !autonomy
        if !blocked { socialBook.cooldown -= dt }
        if !socialBook.pair.isEmpty { for k in socialBook.pair.keys { socialBook.pair[k]! -= dt } }
        if !socialBook.lookPair.isEmpty { for k in socialBook.lookPair.keys { socialBook.lookPair[k]! -= dt } }
        socialBook.wantPitch = 0; socialBook.wantRoll = 0; socialBook.wantSquash = 1; socialBook.wantEyes = 1

        if socialBook.stopAll {
            socialBook.stopAll = false
            if let s = social { s.finish(.stopped); abortAll(sim, skinner) }
        }
        if idleState.kind == .sleep { socialBook.drought = 0 } else if !blocked && social == nil { socialBook.drought += dt }
        if let s = social {
            socialDrive(s, sim, skinner, dt)
        } else {
            socialInviteTick(sim, dt)
            if social == nil { socialWakeGreetTick(sim, dt) }
            if social == nil { socialWatch(sim, dt) }
        }
        // ease the overlays (exactly neutral when nothing asks for them)
        let k = min(1, 16 * dt), b = socialBook
        socialBook.pitch += (b.wantPitch - b.pitch) * k
        socialBook.roll += (b.wantRoll - b.roll) * k
        socialBook.squash += (b.wantSquash - b.squash) * k
        if abs(socialBook.pitch) < 1e-4 && b.wantPitch == 0 { socialBook.pitch = 0 }
        if abs(socialBook.roll) < 1e-4 && b.wantRoll == 0 { socialBook.roll = 0 }
        if abs(socialBook.squash - 1) < 1e-4 && b.wantSquash == 1 { socialBook.squash = 1 }
        if b.wantEyes < 1 { skinner.setEyeOpenness(b.wantEyes); socialBook.squinting = true }
        else if socialBook.squinting { socialBook.squinting = false; skinner.setEyeOpenness(1) }
    }

    /// Hard stop of this brain's side (abortAll, touch, request): nothing of the social is left on him.
    func socialAbort(_ skinner: Skinner?) {
        socialBook.invite = nil; socialBook.wakeGreet = -1; socialBook.greetHop = false
        guard social != nil || socialBook.hold || socialBook.pitch != 0 || socialBook.roll != 0 || socialBook.squash != 1 || socialBook.squinting else { return }
        if let s = social { s.finish(.aborted) }
        socialRelease(skinner, hard: true)
    }

    private func socialRelease(_ skinner: Skinner?, hard: Bool) {
        let s = social
        socialBook.hold = false; socialBook.faceYaw = nil
        socialBook.wantPitch = 0; socialBook.wantRoll = 0; socialBook.wantSquash = 1; socialBook.wantEyes = 1
        if hard { socialBook.pitch = 0; socialBook.roll = 0; socialBook.squash = 1 }
        if socialBook.squinting { socialBook.squinting = false; skinner?.setEyeOpenness(1) }
        socialBook.lookPeer = nil; socialBook.lookAway = false
        social = nil
        socialBook.drought = 0
        guard let s else { return }
        if (s.kind == .pass || s.kind == .toss), s.uid >= 0 {          // (the ball is free again; a hugged one is let go)
            if DecorField.shared.occupant[s.uid] == s.idA || DecorField.shared.occupant[s.uid] == s.idB { DecorField.shared.occupant[s.uid] = nil }
            if DecorField.shared.anim[s.uid]?.held == true { DecorField.shared.fling(s.uid, vh: SIMD2(sinf(yaw), cosf(yaw)) * 0.8, vy: 0, kind: 2) }
        }
        let pid = s.idA == steerID ? s.idB : s.idA
        if s.kind == .look { socialBook.lookPair[pid] = SocialTuning.lookCooldown; socialBook.cooldown = max(socialBook.cooldown, 4) }
        else {
            let wait = (watching ? SocialTuning.livelyWait : 1) * (perkFlags.social ? 0.6 : 1)
            socialBook.cooldown = rand(SocialTuning.brainCooldown.0, SocialTuning.brainCooldown.1) * wait
            socialBook.pair[pid] = rand(SocialTuning.pairCooldown.0, SocialTuning.pairCooldown.1) * (s.kind == .squabble ? 1.4 : 1) * wait
            if s.idC >= 0, s.idC != steerID, let c = socialBrain(s.idC) { _ = c; socialBook.pair[s.idC] = socialBook.pair[pid] }
        }
        if scriptIsNone { restTimer = max(restTimer, rand(1.0, 2.5)) }
        onSocial?(.ended(s.kind, partner: pid, s.end ?? .aborted))
    }

    /// An invited partner (he was out on a wander leg): the social starts the moment his leg is over; dropped when he is taken or the wait runs out.
    private func socialInviteTick(_ sim: SoftBody, _ dt: Float) {
        guard var inv = socialBook.invite else { return }
        inv.t += dt
        socialBook.invite = inv
        guard let o = socialBrain(inv.id), socialFree else { socialBook.invite = nil; return }
        if o.socialFree {
            socialBook.invite = nil
            if !socialStart(inv.kind, with: o, sim) { socialBook.cooldown = max(socialBook.cooldown, 5) }
        } else if inv.t > SocialTuning.inviteWait || !o.socialWandering {
            socialBook.invite = nil
            socialBook.cooldown = max(socialBook.cooldown, 5)
        }
    }

    /// A Jelly in the room woke up (BlobBrain+Sleep `sleepStand`): this one looks at him and hops, a beat later (a cheerful "good morning").
    func socialWakeGreetStart(from waker: BlobBrain) {
        guard socialBook.enabled, social == nil, socialBook.wakeGreet < 0, !waker.sleepLocked, !race.active, idleDeepNight < 0.5 else { return }
        socialBook.wakeGreet = rand(0.3, 0.9); socialBook.greetWho = waker.steerID
    }
    private func socialWakeGreetTick(_ sim: SoftBody, _ dt: Float) {
        if socialBook.greetHop, idleState.kind == nil, scriptIsNone, !feet.active, socialFree {
            socialBook.greetHop = false
            startHopPlay(sim: sim, distance: 0.0001)
            jellyKick = max(jellyKick, 1.2)
        }
        guard socialBook.wakeGreet >= 0 else { return }
        socialBook.wakeGreet -= dt
        guard socialBook.wakeGreet < 0 else { return }
        socialBook.wakeGreet = -1
        guard socialFree, let w = socialBrain(socialBook.greetWho), w.idleState.kind == .sleep, simd_distance(w.position, position) < 6 else { return }
        socialBook.lookPeer = w.steerID; socialBook.lookHold = 1.5
        if idleStart(.look, sim) { socialBook.greetHop = true } else { socialBook.lookPeer = nil }
    }

    /// Greeting watch + the glance back, while no session is on him.
    private func socialWatch(_ sim: SoftBody, _ dt: Float) {
        let ps = socialOthers().map { (id: $0.steerID, pos: $0.position, b: $0) }
        if ps.isEmpty { return }
        for p in ps {
            let o = p.b
            let d = simd_distance(p.pos, position)
            if d > peerGap + 0.8 || o.idleBlocked || (!o.autonomy && !o.idleForced) { socialBook.apart[p.id, default: 0] += dt; socialBook.near[p.id] = 0 }
            else if d < peerGap + 0.4 {
                let n = (socialBook.near[p.id] ?? 0) + dt
                socialBook.near[p.id] = n
                if steerID < p.id, (socialBook.apart[p.id] ?? 0) >= SocialTuning.greetApart, socialFree, o.socialFree, !blockedForGreet(o) {
                    socialBook.apart[p.id] = 0
                    if socialStart(.greet, with: o, sim) { return }
                }
                if n > 3 { socialBook.apart[p.id] = 0 }
            }
        }
    }
    private func blockedForGreet(_ o: BlobBrain) -> Bool { (socialBook.pair[o.steerID] ?? 0) > 0 }

    // MARK: the running session

    private func socialDrive(_ s: SocialSession, _ sim: SoftBody, _ skinner: Skinner, _ dt: Float) {
        let isA = s.idA == steerID
        let o = isA ? s.b : s.a
        // over (by the other side, a stop, a touch): let go
        if s.end != nil {
            let how = s.end!
            socialRelease(skinner, hard: false)
            if how == .stopped, !(scriptIsNone && idleState.kind == nil) { abortAll(sim, skinner) }
            return
        }
        guard let o else { s.finish(.aborted); socialRelease(skinner, hard: true); return }
        if socialTaken || o.socialTaken || (s.c?.socialTaken ?? false) || s.t > 90 { s.finish(.aborted); socialRelease(skinner, hard: false); return }
        if isA { s.t += dt; s.phaseT += dt }          // the initiator keeps the session clock (one tick per frame)
        switch s.kind {
        case .boop: driveBoop(s, o, isA, sim, skinner, dt)
        case .squabble: driveSquabble(s, o, isA, sim, skinner, dt)
        case .follow: driveFollow(s, o, isA, sim, dt)
        case .zoomies: driveZoomies(s, o, isA)
        case .greet: driveGreet(s, o, isA, sim, dt)
        case .look: driveLook(s, o, isA, sim, dt)
        case .chase, .bump, .nuzzle, .sitTogether, .dance, .sneak, .keepAway, .line, .pass, .bagSit, .cuddle, .toss: drivePlay(s, o, isA, sim, skinner, dt)
        }
        if let e = s.end, isA { _ = e }
    }

    /// 0...1...0 pulse: rises over `up`, falls over `down`.
    func pulse(_ t: Float, up: Float, down: Float) -> Float {
        if t <= 0 { return 0 }
        if t < up { return smooth01(t / up) }
        return 1 - smooth01((t - up) / down)
    }

    func faceEach(_ o: BlobBrain) { socialBook.hold = true; socialBook.faceYaw = yawTo(o.position) }

    // MARK: boop

    private func driveBoop(_ s: SocialSession, _ o: BlobBrain, _ isA: Bool, _ sim: SoftBody, _ skinner: Skinner, _ dt: Float) {
        let d = simd_distance(position, o.position)
        if !isA { // the one being visited stands and watches him come
            socialBook.hold = true; socialBook.faceYaw = yawTo(o.position)
        }
        switch s.phase {
        case 0: // walking up
            if !isA { return }
            if scriptIsNone { faceEach(o) }
            if s.t > 16 { s.finish(.aborted); return }
            if scriptIsNone && s.phaseT > 0.3 {
                if d < peerGap + 0.35 { s.setPhase(1) } else { s.finish(.aborted) }
            }
        case 1: // squaring up
            faceEach(o)
            if isA && s.phaseT > 0.5 { s.setPhase(2); s.impacted = false }
        default: // the bump
            faceEach(o)
            let t = s.phaseT
            if isA { // a (leaning in)
                socialBook.wantPitch = 0.20 * pulse(t, up: 0.14, down: 0.30)
            } else { // b (taking it)
                socialBook.wantPitch = -0.10 * pulse(t - 0.12, up: 0.10, down: 0.35)
                socialBook.wantRoll = 0.07 * pulse(t - 0.12, up: 0.10, down: 0.35)
            }
            socialBook.wantSquash = 1 - 0.08 * pulse(t - 0.10, up: 0.08, down: 0.30)
            if isA {
                if !s.impacted && t >= 0.12 {
                    s.impacted = true
                    jellyKick = max(jellyKick, 1.8); o.jellyKick = max(o.jellyKick, 2.6)
                    onSocial?(.boop(partner: o.steerID)); o.onSocial?(.boop(partner: steerID))
                }
                if t > 1.1 { s.finish(.done) }
            }
        }
    }

    // MARK: squabble

    private func driveSquabble(_ s: SocialSession, _ o: BlobBrain, _ isA: Bool, _ sim: SoftBody, _ skinner: Skinner, _ dt: Float) {
        let d = simd_distance(position, o.position)
        switch s.phase {
        case 0: // marching up, narrowed
            socialBook.wantEyes = 0.7
            if !isA { socialBook.hold = true; socialBook.faceYaw = yawTo(o.position); return }
            if scriptIsNone { faceEach(o) }
            if s.t > 16 { s.finish(.aborted); return }
            if scriptIsNone && s.phaseT > 0.3 {
                if d < peerGap + 0.4 { s.setPhase(1); s.fightT = 0 } else { s.finish(.aborted) }
            }
        case 1: // the face-off + shove-bumps
            faceEach(o)
            if isA { s.fightT += dt }
            let ft = s.fightT
            let puff = smooth01(ft / 0.5)
            let w = 2 * Float.pi
            socialBook.wantEyes = 1 - 0.45 * puff
            socialBook.wantPitch = 0.09 * puff
            socialBook.wantRoll = 0.04 * puff * sinf(w * 2.3 * ft + (isA ? 0 : 1.7))
            socialBook.wantSquash = 1 + 0.05 * puff * sinf(w * 3.6 * ft + (isA ? 0 : 1.1))
            if isA {
                // a little jelly kick now and then, and the shove-bumps (nobody's root moves: a lean in + a recoil)
                s.bumpNext -= dt
                if s.bumpT < 0 && ft > 1.0 && s.bumpNext <= 0 { s.bumpT = 0; s.bumper = s.bumps % 2; s.impacted = false; s.bumps += 1 }
                if s.bumpT >= 0 {
                    s.bumpT += dt
                    if !s.impacted && s.bumpT >= 0.12 {
                        s.impacted = true
                        jellyKick = max(jellyKick, 1.4); o.jellyKick = max(o.jellyKick, 2.4)
                        onSocial?(.shove(partner: o.steerID)); o.onSocial?(.shove(partner: steerID))
                    }
                    if s.bumpT > 0.7 { s.bumpT = -1; s.bumpNext = rand(0.8, 1.4) }
                }
                if ft > s.duration { s.setPhase(2) }
            }
            if s.bumpT >= 0 {
                let bt = s.bumpT
                let mine = (s.bumper == 0) == isA
                if mine { socialBook.wantPitch += 0.16 * pulse(bt, up: 0.12, down: 0.30) }
                else {
                    let r = pulse(bt - 0.12, up: 0.08, down: 0.35)
                    socialBook.wantPitch -= 0.12 * r
                    socialBook.wantRoll += (isA ? 0.1 : -0.1) * r
                }
            }
        case 2: // stop, step apart
            if !socialBook.apartStarted {
                socialBook.apartStarted = true
                s.bumpT = -1
                socialBook.hold = false; socialBook.faceYaw = nil
                let away = d > 1e-3 ? (position - o.position) / d : SIMD2(sinf(yaw + .pi), cosf(yaw + .pi))
                socialWalk(to: fixed(position + away * 0.4), sim)
            }
            socialBook.wantEyes = 0.85
            if isA, s.phaseT > 0.4, scriptIsNone, o.scriptIsNone || s.phaseT > 5, d >= peerGap + 0.05 || s.phaseT > 7 { s.setPhase(3) }
        case 3: // sheepish
            if !socialBook.sheepishStarted {
                socialBook.sheepishStarted = true
                socialBook.lookPeer = o.steerID; socialBook.lookAway = true
                if !(scriptIsNone && idleState.kind == nil && idleStart(.look, sim)) { socialBook.lookPeer = nil; socialBook.lookAway = false }
            }
            if idleState.kind == .look { socialBook.wantEyes = 0.7; socialBook.wantPitch = 0.05 }
            if isA && s.phaseT > 0.5 && idleState.kind == nil && o.idleState.kind == nil {
                if s.broke { s.setPhase(4) } else { s.finish(.done) }
            } else if isA && s.phaseT > 8 { s.finish(.done) }
        default: // making up: a small happy hop each (b a beat later) and hearts
            if !socialBook.hopStarted && idleState.kind == nil && scriptIsNone && (isA || s.phaseT >= 0.18) {
                socialBook.hopStarted = true
                socialBook.hold = false
                startHopPlay(sim: sim, distance: 0.0001)
                jellyKick = max(jellyKick, 1.6)
                onSocial?(.makeUp(partner: o.steerID))
            }
            if isA && s.phaseT > 0.5 && socialBook.hopStarted && o.socialBook.hopStarted && scriptIsNone && o.scriptIsNone { s.finish(.done) }
            else if isA && s.phaseT > 5 { s.finish(.done) }
        }
    }

    // MARK: follow

    private func driveFollow(_ s: SocialSession, _ o: BlobBrain, _ isA: Bool, _ sim: SoftBody, _ dt: Float) {
        if isA && s.t > s.duration { s.finish(.done); return }
        if isA { // the follower
            let L = o.position, me = position
            let d = simd_distance(L, me)
            if d > followGap + 0.3 {
                socialBook.hold = false
                let u = (L - me) / d
                let target = fixed(L - u * followGap)
                // straight legs only (a new leg when the last one ended): re-aiming a walk in mid-stride makes a curving walk whose feet come off the belly
                if scriptIsNone && idleState.kind == nil { socialWalk(to: target, sim) }
            } else if scriptIsNone { socialBook.hold = true; socialBook.faceYaw = yawTo(L) }
        } else { // the leader wanders on
            if scriptIsNone && idleState.kind == nil {
                s.leaderWait -= dt
                if s.leaderWait <= 0 {
                    if let g = pickRunGoal(from: position, minD: 1.3, maxD: 2.6) { socialWalk(to: g, sim); s.leaderWait = rand(0.3, 0.9) }
                    else { s.finish(.done) }
                }
            }
        }
    }

    // MARK: zoomies

    private func driveZoomies(_ s: SocialSession, _ o: BlobBrain, _ isA: Bool) {
        guard isA else { return }
        if s.t > 0.8 && idleState.kind == nil && o.idleState.kind == nil && scriptIsNone && o.scriptIsNone { s.finish(.done) }
        else if s.t > s.duration { s.finish(.aborted) }
    }

    // MARK: greet

    private func driveGreet(_ s: SocialSession, _ o: BlobBrain, _ isA: Bool, _ sim: SoftBody, _ dt: Float) {
        switch s.phase {
        case 0:
            faceEach(o)
            if isA && s.phaseT > 0.5 && !feet.active && !o.feet.active { s.setPhase(1) }
            else if isA && s.phaseT > 3 { s.setPhase(1) }
        case 1: // both hop (b a beat later)
            if !socialBook.hopStarted && (isA || s.phaseT >= 0.2) && scriptIsNone {
                socialBook.hopStarted = true
                socialBook.hold = false; socialBook.faceYaw = nil
                startHopPlay(sim: sim, distance: 0.0001)
            }
            if isA && socialBook.hopStarted && o.socialBook.hopStarted && s.phaseT > 0.4 && scriptIsNone && o.scriptIsNone { s.setPhase(2); jellyKick = max(jellyKick, 1.5); o.jellyKick = max(o.jellyKick, 1.5) }
            else if isA && s.phaseT > 6 { s.finish(.done) }
        default:
            if isA && s.phaseT > 0.4 { s.finish(.done) }
        }
    }

    // MARK: look

    private func driveLook(_ s: SocialSession, _ o: BlobBrain, _ isA: Bool, _ sim: SoftBody, _ dt: Float) {
        if !isA {
            // the glance back, a moment after he looked
            if !socialBook.glanceDone {
                socialBook.glanceDelay -= dt
                if socialBook.glanceDelay <= 0 {
                    if scriptIsNone && idleState.kind == nil && !feet.active {
                        socialBook.glanceDone = true
                        socialBook.lookPeer = o.steerID
                        socialBook.lookHold = rand(0.9, 1.5)
                        if !idleStart(.look, sim) { socialBook.lookPeer = nil }
                    } else if s.t > 7 { socialBook.glanceDone = true }
                }
            }
            return
        }
        if s.t > 0.4 && idleState.kind == nil && (o.socialBook.glanceDone && o.idleState.kind == nil || s.t > 9) { s.finish(.done) }
        else if s.t > s.duration { s.finish(.done) }
    }
}

typealias SimdF2 = SIMD2<Float>
