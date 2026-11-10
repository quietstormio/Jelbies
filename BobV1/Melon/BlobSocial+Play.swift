//
//  BlobSocial+Play.swift
//  The new social kinds (user 2026-10-19: "they need to interact a lot more"). Each is a sequencer over the existing locked moves (the walk, the
//  run, the hop, the jumping jacks, the scoot, the sit, the LOOK pose, the boop's lean + jelly kick), like the older kinds in BlobSocial.swift:
//    chase       tag: one runs to a spot, the other runs after him, a tag (a soft bump), the roles swap; three rounds
//    bump        belly bump: both lean in at once, jelly-kick each other and bounce back, twice, then a hop each
//    nuzzle      side by side facing the room, heads leaning together, eyes half shut, a heart
//    sitTogether side by side on the rug: both sit
//    dance       both do the jumping jacks (or the happy bounce) in step
//    sneak       one walks round behind the other and boops him: a startle hop, a turn, a giggle hop
//    keepAway    one chases, the other keeps scooting away (three times)
//    line        follow the leader with three in a row
//  Never during a meal, bath, focus, a voice command or a touch (the base class's `socialTaken`), never with a sleeper, and chase / dance / keep-away
//  only when no OTHER Jelly is in a fast move (at most two at a time).
//

import Foundation
import simd

extension BlobBrain {
    // MARK: choosing

    /// A spot beside `o` (along the world x), on the side nearer to me, clear of everybody else.
    func sideSpot(of o: BlobBrain, gap: Float, extra: Float = 0) -> SIMD2<Float>? {
        // (formation 2026-11-09: the side with the SHORTER WALK from where I stand, not the one nearer by world x; a spot I already stand within 0.3 m of is taken at once)
        let dir: Float = position.x >= o.position.x ? 1 : -1
        var best: (p: SIMD2<Float>, cost: Float)?
        for sgn in [dir, -dir] {
            let p = o.position + SIMD2(sgn * (standGap(o, along: SIMD2(sgn, 0), gap) + extra), 0)          // (never inside him: the touch distance + the approach margin, ContactStance.swift)
            let q = closeFixed(p)
            guard simd_distance(p, q) < 0.2, spotFree(q, besides: [self, o]) else { continue }
            if Self.fmOff("side") { socialBook.sideSpotAt = q; return q }
            var cost = simd_distance(position, q)
            if cost < 0.3 { socialBook.sideSpotAt = q; return q }
            if !legClear(position, q, margin: steerMargin) { cost += 1.5 }
            if peerOnLeg(position, q) { cost += 1.5 }          // (the way to it passes him or a third one: the steering would wait there)
            if best == nil || cost < best!.cost { best = (q, cost) }
        }
        socialBook.sideSpotAt = best?.p
        return best?.p
    }
    /// A spot behind `o` (opposite to where he faces).
    func behindSpot(of o: BlobBrain, gap: Float) -> SIMD2<Float>? {
        let f = SIMD2(sinf(o.yaw), cosf(o.yaw))
        let p = o.position - f * standGap(o, along: -f, gap)
        let q = fixed(p)
        return simd_distance(p, q) < 0.2 && spotFree(q, besides: [self, o]) ? q : nil
    }
    func spotFree(_ p: SIMD2<Float>, besides: [BlobBrain]) -> Bool {
        !socialOthers().contains { o in !besides.contains { $0 === o } && simd_distance(o.position, p) < peerGap * 0.9 }
    }
    /// Others in a fast move, not counting `except` (the partner who is about to join in).
    func fastOthers(except: [BlobBrain]) -> Int { socialOthers().filter { b in b !== self && !except.contains { x in x === b } && b.isFastMove }.count }

    /// The table of the new kinds for a pick: mood, time of day, and no kind twice in a row between these two.
    func socialPlayWeights(base: [(SocialKind, Float)], partner o: BlobBrain, others: [BlobBrain], grumpy: Bool) -> [(SocialKind, Float)] {
        var w = base
        let fastOK = fastOthers(except: [o]) == 0
        let night = max(idleNight, o.idleNight)
        let playful: Float = grumpy ? 0.15 : (idleMood == .happy && o.idleMood == .happy ? 1.4 : 1)
        func add(_ k: SocialKind, _ x: Float, fast: Bool = false) {
            guard !fast || fastOK else { return }
            let tod: Float = fast ? 1 - 0.8 * night : 1 + 0.6 * night
            let nice: Float = (k == .nuzzle || k == .sitTogether) ? (grumpy ? 0.3 : 1) : playful
            if k == socialBook.lastKind || k == o.socialBook.lastKind { return }
            w.append((k, x * tod * nice))
        }
        add(.chase, 4.5, fast: true); add(.dance, 2.6, fast: true); add(.keepAway, 1.4, fast: true)
        add(.nuzzle, 2.2); add(.sitTogether, 1.5); add(.sneak, 2.0)
        add(.line, others.count >= 2 ? 2.4 : 1.6)          // follow the leader: a line of three, or two
        if freeBall() != nil { add(.pass, 2.4) }
        if freeSeat() != nil { add(.bagSit, 1.8) }
        if freeLoveseat() != nil { add(.cuddle, 2.0) }
        socialFriendWeights(into: &w, partner: o, grumpy: grumpy, night: night, fastOK: fastOK)          // the "we like each other" kinds (BlobSocial+Friends.swift)
        if socialBook.lastKind != nil || o.socialBook.lastKind != nil { w.removeAll { $0.0 == socialBook.lastKind || $0.0 == o.socialBook.lastKind } }
        return w
    }

    // MARK: starting

    func socialStartPlay(_ kind: SocialKind, with o: BlobBrain, _ sim: SoftBody) -> Bool {
        let me = position, you = o.position
        let d = simd_distance(me, you)
        if kind.isFast, fastOthers(except: [o]) > 0 { return false }
        switch kind {
        case .sitTogether, .nuzzle:
            guard d > 0.5, d < 5.5, let spot = sideSpot(of: o, gap: peerGap * 0.95) else { return false }
            let s = newSession(kind, with: o, duration: kind == .sitTogether ? rand(4, 6) : rand(3.5, 4.5))
            s.goal = spot
            o.socialBook.hold = true; o.socialBook.faceYaw = o.faceCameraYaw()
            if simd_distance(me, spot) > 0.12 { socialWalk(to: spot, sim) } else { s.setPhase(1) }
        case .sneak:
            guard d > 1.2, d < 5.5, let spot = behindSpot(of: o, gap: peerGap * 0.92) else { return false }
            let s = newSession(.sneak, with: o, duration: 0)
            s.goal = spot
            o.socialBook.hold = true; o.socialBook.faceYaw = o.yaw           // he keeps looking where he was looking
            socialWalk(to: spot, sim)
        case .dance:
            guard d < 4.5 else { return false }
            let s = newSession(.dance, with: o, duration: 0)
            s.round = rand() < 0.5 ? 0 : 1                                    // 0: jumping jacks, 1: happy bounces
            for x in [self, o] { x.socialBook.hold = true; x.socialBook.faceYaw = x.faceCameraYaw() }
        case .chase:
            guard d > 1.0, d < 5 else { return false }
            let s = newSession(.chase, with: o, duration: 34)
            s.roles = rand() < 0.5 ? 0 : 1
            AudioHub.shared.play(.zoomies, jelly: steerID, x: px, volume: 0.6)
        case .keepAway:
            guard d > 1.0, d < 5 else { return false }
            let s = newSession(.keepAway, with: o, duration: 24)
            o.socialBook.hold = true; o.socialBook.faceYaw = o.yawTo(me)
            _ = s
        case .line:
            let cands = socialOthers().filter { $0 !== o && $0 !== self && $0.socialFree && simd_distance($0.position, me) < 5.2 }
            guard d > peerGap * 0.8, d < 5.5 else { return false }
            let c = cands.first          // (no third: follow the leader with two)
            let s = newSession(.line, with: o, duration: rand(5.5, 7.5), third: c)
            s.leaderWait = 0.2
            if let c { onSocial?(.began(.line, partner: c.steerID)); c.onSocial?(.began(.line, partner: steerID)); roomCue(.social(.line)) }
        case .pass, .bagSit, .cuddle:
            return socialStartPass(kind, with: o, sim)
        default: return false
        }
        return true
    }

    // MARK: driving

    func drivePlay(_ s: SocialSession, _ o: BlobBrain, _ isA: Bool, _ sim: SoftBody, _ skinner: Skinner, _ dt: Float) {
        switch s.kind {
        case .sitTogether: driveSitTogether(s, o, isA, sim, dt)
        case .nuzzle: driveNuzzle(s, o, isA, sim, dt)
        case .sneak: driveSneak(s, o, isA, sim, dt)
        case .dance: driveDance(s, o, isA, sim, dt)
        case .chase: driveChase(s, o, isA, sim, dt)
        case .keepAway: driveKeepAway(s, o, isA, sim, dt)
        case .line: driveLine(s, o, isA, sim, dt)
        case .pass: driveBallPass(s, o, isA, sim, dt)
        case .bagSit: driveBagSit(s, o, isA, sim, dt)
        case .cuddle: driveCuddle(s, o, isA, sim, dt)
        default: break
        }
    }

    /// Walking up to `goal`: the initiator's phase 0. True = still walking.
    /// A walk-up counts as arrived within this root distance (m): the standing distance `standGap` (>= 1.445) plus the walk's own stop radius.
    static let walkUpFar: Float = 2.2
    func walkUpPhase(_ s: SocialSession, _ o: BlobBrain, _ isA: Bool, faceBoth: Bool = true, near: Float = 0.5) -> Bool {
        if !isA { return true }
        if scriptIsNone && faceBoth { faceEach(o) }
        if s.t > 18 { s.finish(.aborted); return true }
        _ = formationWalkUp(s, o, near: near, facing: faceBoth)
        return true
    }

    /// How far (m) the skin gap may still be above the stance's own target when a touching walk-up counts as arrived (the phase-1 settle closes the rest), and how close to its spot a walk counts as arrived.
    static let formationSlack: Float = Float(ProcessInfo.processInfo.environment["FORMATION_SLACK"] ?? "") ?? 0.10
    /// The kinds of the newcomer welcome (GameCare+Newcomer): swayHug, spinHug, cuddleLean, cheekSquish, highFive (the groups: groupHug, ringDance, have their own gather).
    static let newcomerKinds: Set<SocialKind> = [.swayHug, .spinHug, .cuddleLean, .cheekSquish, .highFive]
    /// FORMATION (2026-11-09, "they get stuck or take a long time getting into formation"): the initiator's phase 0, one call per tick. While the walk script runs nothing happens (the walk is locked: only
    /// where and when it starts / re-targets is decided here). When it has ended: arrived (touching kinds: the skin gap is within `formationSlack` of the stance's target; the others: the old rule, closer than
    /// `walkUpFar`; side by side: the walk ended where it was going, and once in the pose the gap decides too) = phase 1. Short of it: the walk is issued AGAIN - a try that got somewhere (root moved > 25 cm) is free, three
    /// in a row that went nowhere cancel; from the second the spot is re-planned from where both stand now (the other side, a recomputed away-axis) and the walk gets a corner round whatever is in the way - inside the budget
    /// (3 s + the distance at 1.1 m/s, + 2.5 s for the last stance walk). Out of budget = the session is cancelled (`.aborted`): a touching emote never plays apart (the newcomer-welcome kinds keep the old fallback: they start
    /// from where they stand when close, so their abort counts do not rise). True = phase 1 was just entered.
    /// Debug knobs (env FORMATION_DISABLE, comma list: all, gate, reissue, land, swap, plan, side): each switches one formation part back to the old behaviour for A/B runs.
    static let fmDisabled: Set<String> = Set((ProcessInfo.processInfo.environment["FORMATION_DISABLE"] ?? "").split(separator: ",").map(String.init))
    static func fmOff(_ k: String) -> Bool { fmDisabled.contains(k) || fmDisabled.contains("all") }
    @discardableResult
    func formationWalkUp(_ s: SocialSession, _ o: BlobBrain, near: Float, facing: Bool) -> Bool {
        if Self.fmDisabled.contains("all") {          // (the old rule: when the walk is over, close enough = phase 1, else cancel)
            guard scriptIsNone, s.phaseT > 0.3 else { return false }
            if simd_distance(position, o.position) < max(peerGap + near, Self.walkUpFar) { s.setPhase(1); return true }
            s.finish(.aborted); return false
        }
        s.fmTicks += 1
        // after the first try that got nowhere the PARTNER walks (to the mirrored spot beside / in front of the walker, who now stands still); same rules, roles swapped
        if s.swapped { return o.formationCore(s, self, near: near, facing: facing) }
        return formationCore(s, o, near: near, facing: facing)
    }

    /// The partner takes over the walk-up: he walks to the spot the walker would have given him (side by side: the free side of the walker with the shorter walk; face to face: on the line from the walker to him, at the
    /// same stand-off). False = not possible (a kind whose anchor must not move or whose spot is tied to the partner's facing: sneak, peekaboo; he is busy; no free spot) and the walker carries on as before.
    func formationSwap(_ s: SocialSession, _ o: BlobBrain) -> Bool {
        guard !Self.fmOff("swap"), !s.swapped, s.kind != .sneak, s.kind != .peekaboo, !o.socialTaken, o.scriptIsNone, !o.feet.active, o.idleState.kind == nil, let osim = o.contactSim else { return false }
        let dg = s.dg > 0 ? s.dg : (s.goal == .zero ? peerGap : max(simd_distance(s.goal, o.position), 1.0))
        var best: (p: SIMD2<Float>, cost: Float)?
        if s.sideKind {
            for sgn: Float in [1, -1] {
                let p = position + SIMD2(sgn * dg, 0), q = o.closeFixed(p)
                guard simd_distance(p, q) < 0.2, o.spotFree(q, besides: [o, self]) else { continue }
                let cost = simd_distance(o.position, q) + (o.legClear(o.position, q, margin: o.steerMargin) ? 0 : 1.5) + (o.peerOnLeg(o.position, q) ? 1.5 : 0)
                if best == nil || cost < best!.cost { best = (q, cost) }
            }
        } else {
            let away = simd_normalize(o.position - position + SIMD2(1e-6, 0)), want = position + away * dg, q = o.closeFixed(want)
            if simd_distance(want, q) < 0.14, o.spotFree(q, besides: [o, self]) { best = (q, 0) }
        }
        guard let b = best else { return false }
        s.swapped = true; s.swapT = s.t; s.goal = b.p; s.walkTo = nil; s.stalls = 0; s.tried = []; s.landedT = -1; s.retryAt = s.t + 0.2; s.issuePos = o.position
        s.walkBudget = s.t + 3 + simd_distance(o.position, b.p) / 1.1
        script = .none; scriptT = 0; route = []; restTimer = 1          // (the walker stands where he is)
        o.socialWalk(to: b.p, osim)
        return true
    }

    /// MEET IN THE MIDDLE (round 3): at the start of a walk-up that is long, both walk - to the two stance spots round the midpoint of the pair - instead of one standing frozen while the other crosses the room (the
    /// travel is halved; the stance's own meeting logic, `contactStanceWalk`, already re-targets two walkers to the point between them). Face to face: on the line between them, `dg` apart (the first plan's stand-off);
    /// side by side: on the pair's mean line, each on his own side. Not for kinds whose spot is tied to the partner's facing (sneak, peekaboo), when he is busy, when a spot is not free, or when he would walk less than 0.6 m.
    /// Anything that goes wrong (either walk is given up, the budget) hands back to the old plan: he stays where he is and the initiator walks the rest (`formationMeetRevert`).
    func formationMeet(_ s: SocialSession, _ o: BlobBrain) {
        guard !Self.fmOff("meet"), !Self.newcomerKinds.contains(s.kind), s.kind != .sneak, s.kind != .peekaboo, s.dg > 0, !o.socialTaken, o.scriptIsNone, !o.feet.active, o.idleState.kind == nil,
              let sim = contactSim, let osim = o.contactSim else { return }
        let me = position, you = o.position, D = simd_distance(me, you)
        guard D > s.dg + 1.0 else { return }
        var wSpot: SIMD2<Float>, pSpot: SIMD2<Float>
        let mid = (me + you) / 2
        if s.sideKind {
            var sgn: Float = me.x >= you.x ? 1 : -1
            if abs(me.x - you.x) < 0.3, s.goal.x != you.x { sgn = s.goal.x > you.x ? 1 : -1 }
            wSpot = SIMD2(mid.x + sgn * s.dg / 2, mid.y); pSpot = SIMD2(mid.x - sgn * s.dg / 2, mid.y)
        } else {
            let u = simd_normalize(me - you + SIMD2(1e-6, 0))
            wSpot = mid + u * (s.dg / 2); pSpot = mid - u * (s.dg / 2)
        }
        let wq = closeFixed(wSpot), pq = o.closeFixed(pSpot)
        guard simd_distance(wq, wSpot) < 0.12, simd_distance(pq, pSpot) < 0.12, simd_distance(you, pq) > 0.6,
              spotFree(wq, besides: [self, o]), o.spotFree(pq, besides: [o, self]) else { return }
        s.meet = true; s.meetUsed = true; s.goal0 = s.goal; s.partnerGoal = pq; s.goal = wq; s.walkTo = nil
        socialWalk(to: wq, sim)
        o.socialWalk(to: pq, osim)
    }

    /// Back to the old plan: the partner stands where he is (his walk is stopped once his foot is down), the initiator's goal is the first plan's stand-off from where he stands now.
    func formationMeetRevert(_ s: SocialSession, _ o: BlobBrain) {
        s.meet = false
        if case .walk = o.script {          // (only his walk is stopped - the same three fields BlobBrain.step(after:giveUp:) clears; any other script is left alone)
            if o.feet.active { s.meet = true; return }
            o.script = .none; o.scriptT = 0; o.route = []
        }
        s.goal = replanGoal(s, o) ?? s.goal0
        s.walkTo = nil; s.issuePos = position; s.stalls = 0; s.retryAt = s.t + 0.05; s.walkBudget = max(s.walkBudget, s.t + 3 + simd_distance(position, s.goal) / 1.1)
        if let sim = contactSim { socialWalk(to: s.goal, sim) }
    }

    func formationCore(_ s: SocialSession, _ o: BlobBrain, near: Float, facing: Bool) -> Bool {
        if s.walkBudget == 0 {
            s.walkBudget = 3 + simd_distance(position, s.goal == .zero ? o.position : s.goal) / 1.1; s.issuePos = position
            if let at = socialBook.sideSpotAt, s.goal != .zero, simd_distance(at, s.goal) < 0.01 { s.sideKind = true }
            s.dg = s.goal == .zero ? 0 : max(simd_distance(s.goal, o.position), 1.0)
            if !s.swapped { formationMeet(s, o) }
        }
        let st = ContactStance.entry(s.kind)
        let touching = st?.cls == .touching
        let newcomer = Self.newcomerKinds.contains(s.kind)          // (the newcomer welcome waits for `social == nil` and counts aborts: these kinds keep the old fallback - start from where they stand when close - instead of being cancelled)
        guard scriptIsNone, s.phaseT > 0.3 else {
            if case .walk(let t, _) = script {
                s.walkTo = t          // (where this walk is going: the stance may have re-targeted it)
                // boxed in: waiting for the steering with no step made. The blocker is usually the partner himself when he is near: then do not wait out the patience (0.4 s / 0.6 s instead of 0.8 s / 1.2 s)
                let partnerNear = simd_distance(position, o.position) < 2.4
                if !s.swapped, steerWait > (partnerNear ? 0.4 : 0.8), s.t > (partnerNear ? 0.6 : 1.2), simd_distance(position, s.issuePos) < 0.25 {
                    if s.meet { formationMeetRevert(s, o); return false }
                    if formationSwap(s, o) { return false }
                }
            }
            if touching, !newcomer, s.t > s.walkBudget + 2.5 { s.finish(.aborted) }          // (still walking, long past the budget: a walk that never lands)
            return false
        }
        if s.meet, !s.swapped {          // (meeting in the middle: wait for the partner's walk; if it ended far from his spot, or the budget is gone, he stays where he is and I walk the rest)
            if !o.scriptIsNone || o.feet.active {
                if s.t > s.walkBudget { formationMeetRevert(s, o) }
                return false
            }
            if s.partnerDoneT < 0 { s.partnerDoneT = s.t }
            if simd_distance(o.position, s.partnerGoal) > 0.45 { formationMeetRevert(s, o); return false }
            let want = facing ? o.yawTo(position) : o.faceCameraYaw()
            if abs(wrapAngle(o.yaw - want)) > 0.3, s.t < s.partnerDoneT + 0.8 { return false }          // (he is still turning into the pose: the gap is read once he stands in it)
        }
        let d = simd_distance(position, o.position)
        // Arrived? FACE TO FACE the posture does not change after the walk, so the stance's own skin gap decides (within `formationSlack` of its phase-0 target). SIDE BY SIDE the body still turns to the camera after the
        // walk (the outline - and so the gap - changes by up to 20 cm while it does), so the judge is the walk itself: it ended within 15 cm of the destination it was going to (a walk that was given up on the way did not).
        var need: Float?
        let stanceWalks = st?.steps.first?.walks == true          // (only the stances that own the walk-up - walk0 - are judged by their gap; the rest by the walk's own destination)
        let inPose = facing || abs(wrapAngle(yaw - faceCameraYaw())) < 0.3          // (side by side: the walk turns into the pose on its last steps)
        if touching, inPose, let st, stanceWalks, ContactField.enabled, let g = ContactField.gap(steerID, o.steerID, features: st.features) { need = g - (st.steps.first?.target ?? ContactStance.near) }
        let ref = s.walkTo ?? (s.goal == .zero ? nil : s.goal)
        let short: Bool
        if Self.fmOff("gate") { short = d >= max(peerGap + near, Self.walkUpFar) }
        else if let need { short = need > Self.formationSlack }
        else if touching, let ref {
            short = simd_distance(position, ref) > 0.15
            if !short {
                if s.landedT < 0 { s.landedT = s.t }
                if !facing, stanceWalks, !Self.fmOff("land"), s.t < s.landedT + 0.6 { s.fmLand += 1; return false }          // (landed, but still turning into the pose: the gap is read once it stands in it - for at most 1 s)
            }
        }
        else { short = d >= max(peerGap + near, Self.walkUpFar) }
        guard short else { s.setPhase(1); return true }
        let over = s.t > s.walkBudget + (touching ? 2.5 : 0)
        guard !over, s.stalls < 3, !Self.fmOff("reissue"), let sim = contactSim else {
            // out of budget / out of tries: a touching emote is cancelled (never plays apart); the others may start in place when they stand near him (the old rule)
            if !touching || newcomer, d < Self.walkUpFar { s.setPhase(1); return true }
            s.finish(.aborted); return false
        }
        guard Self.fmOff("feet") || !feet.active else { return false }          // (a walk is issued from a standing foot: never mid-stride)
        guard s.t >= s.retryAt else { s.fmBeat += 1; return false }          // (a beat between two tries)
        // a try that got somewhere (the root moved more than 25 cm since the last one) does not count against the three that are allowed; three in a row that went nowhere cancel the session
        s.stalls = simd_distance(position, s.issuePos) > 0.25 ? 0 : s.stalls + 1
        s.issuePos = position
        if s.stalls >= 1 || s.rewalks >= 2, formationSwap(s, o) { return false }          // (the first try that got nowhere - or the second try at all, e.g. a spot behind a wall margin: the partner walks instead)
        guard s.stalls < 3 else {
            if !touching || newcomer, d < Self.walkUpFar { s.setPhase(1); return true }          // (three tries that went nowhere: the same fallback as above)
            s.finish(.aborted); return false
        }
        s.rewalks += 1
        s.retryAt = s.t + 0.15
        if s.goal == .zero || s.stalls >= 1 { if let g2 = replanGoal(s, o) { s.goal = g2; s.walkTo = nil } }
        var aim = s.stalls >= 1 ? s.goal : (s.walkTo ?? s.goal)
        if aim == .zero || (simd_distance(position, aim) < 0.12 && (need ?? 0) > Self.formationSlack) {          // (standing at the spot and still far from him: close the gap along the line to him)
            let u = simd_normalize(o.position - position + SIMD2(1e-6, 0))
            aim = closeFixed(position + u * min(max(need ?? 0.3, 0.1), 0.6))
            if simd_distance(aim, position) < 0.06 { s.rewalks -= 1; s.stalls = max(0, s.stalls - 1); s.retryAt = s.t + 0.5; return false }          // (the floor / his wall keeps it where it is: nothing to walk now; try again in a beat, the budget ends it)
        }
        socialWalk(to: aim, sim)
        // a re-issue that is the second or third try: the first one got nowhere, usually boxed in between him and a third Jelbie - give the walk a corner round them (the steering found none)
        if let wp = detourWaypoint(to: aim, around: o, avoiding: s.tried) { route = [wp]; s.tried.append(wp) }
        return false
    }

    /// A corner for a walk to `goal` round whatever stands in the way (the Jelbie nearest to the straight leg: the partner, or a third one; `o` when nobody is near it): a free floor point on a ring round him, reachable from here and
    /// with a clear leg on to the goal, the shortest way, and not one that was tried already. Corners whose two legs pass nobody come first; when there is none the legs may pass within the usual gap (the walk then squeezes by:
    /// the room's wall keeps the bodies apart). nil = none.
    func detourWaypoint(to goal: SIMD2<Float>, around o: BlobBrain, avoiding tried: [SIMD2<Float>]) -> SIMD2<Float>? {
        var blocker = o.position, nearest: Float = .infinity
        let leg = goal - position, L2 = max(simd_length_squared(leg), 1e-4)
        for p in steerPeers() {
            let u = max(0, min(1, simd_dot(p.pos - position, leg) / L2))
            let d = simd_distance(p.pos, position + leg * u)
            if d < nearest { nearest = d; blocker = p.pos }
        }
        if nearest > 1.6 { blocker = o.position }
        for strict in [true, false] {
            var best: (cost: Float, p: SIMD2<Float>)?
            for k in 0..<16 {
                let a = Float(k) * .pi / 8
                for r: Float in [1.5, 1.9] {
                    let p = blocker + SIMD2(sinf(a), cosf(a)) * r
                    let q = fixed(p)
                    guard simd_distance(p, q) < 0.1, steerPeers().allSatisfy({ simd_distance($0.pos, q) >= peerGap * 0.8 }), !tried.contains(where: { simd_distance($0, q) < 0.6 }), legClear(position, q, margin: steerMargin), legClear(q, goal, margin: steerMargin) else { continue }
                    if strict { if peerOnLeg(position, q) || peerOnLeg(q, goal) { continue } }
                    else if !softLegClear(position, q, r: peerGap * 0.8) || !softLegClear(q, goal, r: peerGap * 0.8) { continue }
                    let cost = simd_distance(position, q) + simd_distance(q, goal)
                    if best == nil || cost < best!.cost { best = (cost, q) }
                }
            }
            if let b = best { return b.p }
        }
        return nil
    }

    /// The meeting spot again, from where both stand NOW, at the stand-off distance of the first plan: side by side = the free side with the shorter walk, face to face = on the line from him to me, behind (sneak) / the peekaboo spot unchanged.
    func replanGoal(_ s: SocialSession, _ o: BlobBrain) -> SIMD2<Float>? {
        if s.kind == .sneak || s.kind == .peekaboo { return nil }
        let dg = s.dg > 0 ? s.dg : (s.goal == .zero ? peerGap : simd_distance(s.goal, o.position))
        guard dg > 0.4 else { return nil }
        if s.sideKind, s.goal != .zero {
            var best: (p: SIMD2<Float>, cost: Float)?
            for sgn: Float in [1, -1] {
                let p = o.position + SIMD2(sgn * dg, 0), q = closeFixed(p)
                guard simd_distance(p, q) < 0.2, spotFree(q, besides: [self, o]) else { continue }
                let cost = simd_distance(position, q) + (legClear(position, q, margin: steerMargin) ? 0 : 1.5)
                if best == nil || cost < best!.cost { best = (q, cost) }
            }
            if let b = best { socialBook.sideSpotAt = b.p; return b.p }
            return nil
        }
        let away = simd_normalize(position - o.position + SIMD2(1e-6, 0))
        let want = o.position + away * dg, q = closeFixed(want)
        return simd_distance(want, q) < 0.14 && spotFree(q, besides: [self, o]) ? q : nil
    }

    func leanSign(toward p: SIMD2<Float>) -> Float {
        let local = rotXZ(p - position, -yaw)
        return local.x >= 0 ? -1 : 1          // (a positive roll tips his crown toward his -x side)
    }

    // MARK: sit together

    private func driveSitTogether(_ s: SocialSession, _ o: BlobBrain, _ isA: Bool, _ sim: SoftBody, _ dt: Float) {
        switch s.phase {
        case 0:
            if !isA { socialBook.hold = true; socialBook.faceYaw = faceCameraYaw(); return }
            if scriptIsNone { socialBook.hold = true; socialBook.faceYaw = faceCameraYaw() }
            _ = walkUpPhase(s, o, isA, faceBoth: false, near: 0.55)
        case 1:
            if !socialBook.hopStarted, scriptIsNone, idleState.kind == nil, isA || s.phaseT > 0.25 {
                socialBook.hold = false; socialBook.faceYaw = nil
                if idleStart(.sit, sim) { idleState.hold = s.duration; socialBook.hopStarted = true }
                else { s.finish(.aborted) }
            }
            if isA, socialBook.hopStarted, o.socialBook.hopStarted, s.phaseT > 0.5 { s.setPhase(2) }
            else if isA, s.phaseT > 8 { s.finish(.aborted) }
        default:
            if idleState.kind == .sit || idleState.kind == .sleep { socialBook.wantRoll = leanSign(toward: o.position) * 0.05 }
            if isA, idleState.kind == nil, o.idleState.kind == nil, s.phaseT > 1 { s.finish(.done) }
            else if isA, s.phaseT > s.duration + 8 { s.finish(.done) }
        }
    }

    // MARK: nuzzle

    private func driveNuzzle(_ s: SocialSession, _ o: BlobBrain, _ isA: Bool, _ sim: SoftBody, _ dt: Float) {
        switch s.phase {
        case 0:
            if !isA { socialBook.hold = true; socialBook.faceYaw = faceCameraYaw(); return }
            if scriptIsNone { socialBook.hold = true; socialBook.faceYaw = faceCameraYaw() }
            _ = walkUpPhase(s, o, isA, faceBoth: false, near: 0.55)
        case 1:
            socialBook.hold = true; socialBook.faceYaw = faceCameraYaw()
            if isA, s.phaseT > 0.7, !feet.active, !o.feet.active { s.setPhase(2) }
            else if isA, s.phaseT > 3 { s.setPhase(2) }
        default:
            socialBook.hold = true; socialBook.faceYaw = faceCameraYaw()
            let ft = s.phaseT
            let lean = smooth01(ft / 0.9) * (1 - smooth01((ft - (s.duration - 0.8)) / 0.8))
            socialBook.wantRoll = leanSign(toward: o.position) * 0.12 * lean
            socialBook.wantSquash = 1 - 0.03 * lean * (0.6 + 0.4 * sinf(2 * .pi * ft / 2.2))
            socialBook.wantEyes = 1 - 0.5 * lean
            if lean > 0.85, !socialBook.hopStarted {
                socialBook.hopStarted = true
                jellyKick = max(jellyKick, 1.0)
                if isA { contactBoopFallback(o) }
            }
            if isA, ft > s.duration { s.finish(.done) }
        }
    }

    // MARK: sneak

    private func driveSneak(_ s: SocialSession, _ o: BlobBrain, _ isA: Bool, _ sim: SoftBody, _ dt: Float) {
        switch s.phase {
        case 0:   // b stands, looking the other way; a walks round behind him
            if !isA { socialBook.hold = true; return }
            if s.t > 18 { s.finish(.aborted); return }
            _ = formationWalkUp(s, o, near: 0.4, facing: true)
        case 1:   // a creeps the last bit: stands, squashes a little, face to his back
            if !isA { socialBook.hold = true; return }
            socialBook.hold = true; socialBook.faceYaw = yawTo(o.position)
            socialBook.wantSquash = 1 - 0.05 * smooth01(s.phaseT / 0.4)
            if s.phaseT > 0.7 { s.setPhase(2); s.impacted = false }
        case 2:   // the boop from behind: b startles (a hop, big wobble)
            let t = s.phaseT
            if isA {
                socialBook.hold = true; socialBook.faceYaw = yawTo(o.position)
                socialBook.wantPitch = 0.20 * pulse(t, up: 0.14, down: 0.30)
                if !s.impacted, t >= 0.12 {
                    s.impacted = true
                    jellyKick = max(jellyKick, impactKick(1.6)); o.jellyKick = max(o.jellyKick, impactKick(3.0))
                    contactBoopFallback(o)
                    contactCueFallback(o, .boop, 0.9)
                }
                if t > 0.7 { s.setPhase(3) }
            } else if s.impacted, !socialBook.hopStarted, scriptIsNone {
                socialBook.hopStarted = true
                socialBook.hold = false; socialBook.faceYaw = nil
                startHopPlay(sim: sim, distance: 0.0001)
                AudioHub.shared.play(.jump, jelly: steerID, x: px, volume: 0.8)
            }
        default:  // b turns round; a giggles (a hop)
            if !isA {
                if scriptIsNone { socialBook.hold = true; socialBook.faceYaw = yawTo(o.position) }
                return
            }
            socialBook.hold = true; socialBook.faceYaw = yawTo(o.position)
            if !socialBook.apartStarted, s.phaseT > 0.5, scriptIsNone, o.scriptIsNone {
                socialBook.apartStarted = true
                socialBook.hold = false; socialBook.faceYaw = nil
                startHopPlay(sim: sim, distance: 0.0001)
            }
            if socialBook.apartStarted, s.phaseT > 1.0, scriptIsNone, o.scriptIsNone { s.finish(.done) }
            else if s.phaseT > 8 { s.finish(.done) }
        }
    }

    // MARK: dance

    private func driveDance(_ s: SocialSession, _ o: BlobBrain, _ isA: Bool, _ sim: SoftBody, _ dt: Float) {
        switch s.phase {
        case 0:
            socialBook.hold = true; socialBook.faceYaw = faceCameraYaw()
            if isA, s.phaseT > 0.5, !feet.active, !o.feet.active, scriptIsNone, o.scriptIsNone { s.setPhase(1) }
            else if isA, s.phaseT > 3.5 { s.setPhase(1) }
        case 1:
            if !socialBook.hopStarted, scriptIsNone, idleState.kind == nil {
                socialBook.hold = false; socialBook.faceYaw = nil
                let kind: IdleKind = s.round == 0 ? .jacks : .bounce
                if idleStart(kind, sim) {
                    socialBook.hopStarted = true
                    idleState.reps = kind == .jacks ? 3 : 4
                } else { s.finish(.aborted) }
            }
            if isA, socialBook.hopStarted, o.socialBook.hopStarted, s.phaseT > 0.3 { s.setPhase(2) }
            else if isA, s.phaseT > 6 { s.finish(.aborted) }
        default:
            if isA, idleState.kind == nil, o.idleState.kind == nil, scriptIsNone, o.scriptIsNone, s.phaseT > 0.3 { s.finish(.done) }
            else if isA, s.phaseT > 16 { s.finish(.aborted) }
        }
    }

    // MARK: chase / tag

    private func driveChase(_ s: SocialSession, _ o: BlobBrain, _ isA: Bool, _ sim: SoftBody, _ dt: Float) {
        let chaserIsA = s.roles == 0
        let iChase = (chaserIsA == isA)
        let key = s.round * 2 + s.roles
        if socialBook.roundSeen != key { socialBook.roundSeen = key; socialBook.hopStarted = false }
        switch s.phase {
        case 0:   // the runner picks a spot and goes; the chaser follows a beat later
            if !iChase {
                if !socialBook.hopStarted, scriptIsNone, idleState.kind == nil {
                    let g = awayGoal(from: o.position)
                    if let g, idleStart(.run, sim, goal: g) {
                        socialBook.hopStarted = true; socialBook.hold = false
                        s.goal = g; s.impacted = true
                    } else { s.finish(.aborted) }
                }
            } else {
                socialBook.hold = true; socialBook.faceYaw = yawTo(o.position)
                if !socialBook.hopStarted, s.impacted, s.phaseT > 0.35, scriptIsNone, idleState.kind == nil {
                    let to = s.goal
                    var u = position - to; let L = simd_length(u); u = L > 1e-3 ? u / L : SIMD2(0, 1)
                    let spot = fixed(to + u * (touchRadius(o, along: u).map { $0 + ContactStance.approach } ?? peerGap * 0.95))
                    if simd_distance(position, spot) > 1.0, idleStart(.run, sim, goal: spot) { socialBook.hopStarted = true; socialBook.hold = false }
                    else if simd_distance(position, spot) <= 1.0 { socialBook.hopStarted = true; socialBook.hold = false; socialWalk(to: spot, sim) }
                    else { s.finish(.aborted) }
                }
            }
            if isA, socialBook.hopStarted, o.socialBook.hopStarted, s.phaseT > 0.5 { s.setPhase(1) }
            else if isA, s.phaseT > 6 { s.finish(.aborted) }
        case 1:   // running
            if isA, s.phaseT > 0.6, idleState.kind == nil, o.idleState.kind == nil, scriptIsNone, o.scriptIsNone { s.setPhase(2); s.impacted = false }
            else if isA, s.phaseT > 14 { s.finish(.aborted) }
        case 2:   // the tag: the chaser leans in, the runner takes the bump
            faceEach(o)
            let t = s.phaseT
            if iChase { socialBook.wantPitch = 0.20 * pulse(t, up: 0.14, down: 0.30) }
            else { socialBook.wantPitch = -0.10 * pulse(t - 0.12, up: 0.10, down: 0.35); socialBook.wantRoll = 0.08 * pulse(t - 0.12, up: 0.10, down: 0.35) }
            if isA {
                if !s.impacted, t >= 0.12 {
                    s.impacted = true
                    let chaser = chaserIsA ? self : o, runner = chaserIsA ? o : self
                    chaser.jellyKick = max(chaser.jellyKick, 1.4); runner.jellyKick = max(runner.jellyKick, 2.8)
                    contactBoopFallback(o)
                    contactCueFallback(o, .boop, 0.9)
                }
                if t > 0.95 {
                    s.round += 1; s.roles = 1 - s.roles
                    if s.round >= SocialTuning.chaseRounds { s.setPhase(3) } else { s.setPhase(0); s.impacted = false }
                }
            }
        default:  // good game: a hop each
            socialBook.hold = false
            if !socialBook.apartStarted, scriptIsNone, isA || s.phaseT >= 0.18 {
                socialBook.apartStarted = true
                startHopPlay(sim: sim, distance: 0.0001)
            }
            if isA, socialBook.apartStarted, o.socialBook.apartStarted, s.phaseT > 0.4, scriptIsNone, o.scriptIsNone { s.finish(.done) }
            else if isA, s.phaseT > 5 { s.finish(.done) }
        }
        if isA, s.t > s.duration { s.finish(.aborted) }
    }

    /// A run goal 2.2...4 u away from where I stand that is as far as possible from `from` (the chaser).
    func awayGoal(from: SIMD2<Float>, minD: Float = 2.2, maxD: Float = 4.0) -> SIMD2<Float>? {
        var best: (SIMD2<Float>, Float)?
        for _ in 0..<7 {
            guard let g = pickRunGoal(from: position, minD: minD, maxD: maxD) else { continue }
            let d = simd_distance(g, from)
            if best == nil || d > best!.1 { best = (g, d) }
        }
        return best?.0
    }

    // MARK: keep-away

    private func driveKeepAway(_ s: SocialSession, _ o: BlobBrain, _ isA: Bool, _ sim: SoftBody, _ dt: Float) {
        // a chases (walks), b dodges (scoots away, three times)
        let key = s.round
        if socialBook.roundSeen != key { socialBook.roundSeen = key; socialBook.hopStarted = false }
        switch s.phase {
        case 0:   // a closes in
            if !isA { socialBook.hold = true; socialBook.faceYaw = yawTo(o.position); return }
            if s.t > s.duration { s.finish(.aborted); return }
            let d = simd_distance(position, o.position)
            if d < 2.1, s.phaseT > 0.4 { s.setPhase(1); return }
            if scriptIsNone, idleState.kind == nil {
                socialBook.hold = false
                var u = position - o.position; let L = simd_length(u); u = L > 1e-3 ? u / L : SIMD2(0, 1)
                socialWalk(to: fixed(o.position + u * 1.5), sim)
            }
        case 1:   // b dodges
            if isA {
                socialBook.hold = true; socialBook.faceYaw = yawTo(o.position)
                if scriptIsNone, s.phaseT > 0.5, o.socialBook.hopStarted, o.idleState.kind == nil, o.scriptIsNone {
                    s.round += 1
                    if s.round >= SocialTuning.keepAwayRounds { s.setPhase(2) } else { s.setPhase(0) }
                } else if s.phaseT > 8 { s.finish(.aborted) }
            } else if !socialBook.hopStarted, scriptIsNone, idleState.kind == nil {
                socialBook.hold = false; socialBook.faceYaw = nil
                var best: (SIMD2<Float>, Float)?
                for _ in 0..<7 {
                    guard let g = pickRunGoal(from: position, minD: 1.3, maxD: 2.0) else { continue }
                    let score = simd_distance(g, o.position) - 0.25 * g.y            // away from the chaser, a little toward the sofa
                    if best == nil || score > best!.1 { best = (g, score) }
                }
                if let g = best?.0, idleStart(.scoot, sim, goal: g) { socialBook.hopStarted = true } else { s.finish(.aborted) }
            }
        default:  // good game: a hop each
            socialBook.hold = false
            if !socialBook.apartStarted, scriptIsNone, idleState.kind == nil, isA || s.phaseT >= 0.18 {
                socialBook.apartStarted = true
                startHopPlay(sim: sim, distance: 0.0001)
            }
            if isA, socialBook.apartStarted, o.socialBook.apartStarted, s.phaseT > 0.4, scriptIsNone, o.scriptIsNone { s.finish(.done) }
            else if isA, s.phaseT > 5 { s.finish(.done) }
        }
    }

    // MARK: follow the leader, a line of three

    private func followLeader(_ L: BlobBrain, _ sim: SoftBody) {
        let p = L.position, me = position
        let d = simd_distance(p, me)
        if d > followGap + 0.3 {
            socialBook.hold = false
            let u = (p - me) / d
            if scriptIsNone && idleState.kind == nil { socialWalk(to: fixed(p - u * followGap), sim) }
        } else if scriptIsNone { socialBook.hold = true; socialBook.faceYaw = yawTo(p) }
    }

    private func driveLine(_ s: SocialSession, _ o: BlobBrain, _ isA: Bool, _ sim: SoftBody, _ dt: Float) {
        if isA, s.t > s.duration { s.finish(.done); return }
        if let c = s.c, c === self { followLeader(s.a ?? o, sim); return }          // the last in the line follows the middle one
        if isA { followLeader(o, sim); return }                                      // the middle follows the leader
        // the leader wanders on
        if scriptIsNone && idleState.kind == nil {
            s.leaderWait -= dt
            if s.leaderWait <= 0 {
                if let g = pickRunGoal(from: position, minD: 1.3, maxD: 2.6) { socialWalk(to: g, sim); s.leaderWait = rand(0.3, 0.9) } else { s.finish(.done) }
            }
        }
    }
}
