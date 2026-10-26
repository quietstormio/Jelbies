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
    func sideSpot(of o: BlobBrain, gap: Float) -> SIMD2<Float>? {
        let dir: Float = position.x >= o.position.x ? 1 : -1
        for sgn in [dir, -dir] {
            let p = o.position + SIMD2(sgn * gap, 0)
            let q = closeFixed(p)
            if simd_distance(p, q) < 0.2, spotFree(q, besides: [self, o]) { return q }
        }
        return nil
    }
    /// A spot behind `o` (opposite to where he faces).
    func behindSpot(of o: BlobBrain, gap: Float) -> SIMD2<Float>? {
        let f = SIMD2(sinf(o.yaw), cosf(o.yaw))
        let p = o.position - f * gap
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
        add(.bump, 2.6); add(.nuzzle, 2.2); add(.sitTogether, 1.5); add(.sneak, 2.0)
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
        case .bump:
            guard d > 0.5, d < 5.5 else { return false }
            let away = (me - you) / max(d, 1e-3)
            let spot = fixed(you + away * peerGap * 0.92)
            guard simd_distance(spot, you + away * peerGap * 0.92) < 0.12, spotFree(spot, besides: [self, o]) else { return false }
            let s = newSession(.bump, with: o, duration: 0)
            s.goal = spot
            o.socialBook.hold = true; o.socialBook.faceYaw = o.yawTo(me)
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
            if let c { onSocial?(.began(.line, partner: c.steerID)); c.onSocial?(.began(.line, partner: steerID)) }
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
        case .bump: driveBump(s, o, isA, sim, dt)
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
    func walkUpPhase(_ s: SocialSession, _ o: BlobBrain, _ isA: Bool, faceBoth: Bool = true, near: Float = 0.5) -> Bool {
        if !isA { return true }
        if scriptIsNone && faceBoth { faceEach(o) }
        if s.t > 18 { s.finish(.aborted); return true }
        if scriptIsNone && s.phaseT > 0.3 {
            if simd_distance(position, o.position) < peerGap + near { s.setPhase(1) } else { s.finish(.aborted) }
        }
        return true
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
                if isA { onSocial?(.boop(partner: o.steerID)); o.onSocial?(.boop(partner: steerID)) }
            }
            if isA, ft > s.duration { s.finish(.done) }
        }
    }

    // MARK: belly bump

    private func driveBump(_ s: SocialSession, _ o: BlobBrain, _ isA: Bool, _ sim: SoftBody, _ dt: Float) {
        switch s.phase {
        case 0:
            if !isA { socialBook.hold = true; socialBook.faceYaw = yawTo(o.position); return }
            _ = walkUpPhase(s, o, isA)
        case 1:
            faceEach(o)
            if isA, s.phaseT > 0.45 { s.setPhase(2); s.impacted = false }
        case 2, 3:
            faceEach(o)
            let t = s.phaseT
            let side: Float = isA ? 1 : -1
            socialBook.wantPitch = 0.22 * pulse(t, up: 0.14, down: 0.30) - 0.12 * pulse(t - 0.32, up: 0.12, down: 0.35)
            socialBook.wantRoll = side * 0.08 * pulse(t - 0.32, up: 0.12, down: 0.35)
            socialBook.wantSquash = 1 - 0.12 * pulse(t - 0.08, up: 0.08, down: 0.28)
            if isA {
                if !s.impacted, t >= 0.12 {
                    s.impacted = true
                    jellyKick = max(jellyKick, 2.8); o.jellyKick = max(o.jellyKick, 2.8)
                    onSocial?(.boop(partner: o.steerID)); o.onSocial?(.boop(partner: steerID))
                    AudioHub.shared.play(.boop, jelly: steerID, x: px, volume: 0.9)
                }
                if t > 0.95 { if s.phase == 2 { s.setPhase(3); s.impacted = false } else { s.setPhase(4) } }
            }
        default:    // bump-and-bounce: a couple of happy bounces each (b a beat later), a jelly kick on both
            if !socialBook.hopStarted, scriptIsNone, idleState.kind == nil, isA || s.phaseT >= 0.18 {
                socialBook.hopStarted = true
                socialBook.hold = false; socialBook.faceYaw = nil
                jellyKick = max(jellyKick, 2.0)
                if idleStart(.bounce, sim) { idleState.reps = 2 } else { startHopPlay(sim: sim, distance: 0.0001) }
            }
            if isA, socialBook.hopStarted, o.socialBook.hopStarted, s.phaseT > 0.4, scriptIsNone, o.scriptIsNone, idleState.kind == nil, o.idleState.kind == nil { s.finish(.done) }
            else if isA, s.phaseT > 7 { s.finish(.done) }
        }
    }

    // MARK: sneak

    private func driveSneak(_ s: SocialSession, _ o: BlobBrain, _ isA: Bool, _ sim: SoftBody, _ dt: Float) {
        switch s.phase {
        case 0:   // b stands, looking the other way; a walks round behind him
            if !isA { socialBook.hold = true; return }
            if s.t > 18 { s.finish(.aborted); return }
            if scriptIsNone, s.phaseT > 0.3 {
                if simd_distance(position, o.position) < peerGap + 0.4 { s.setPhase(1) } else { s.finish(.aborted) }
            }
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
                    jellyKick = max(jellyKick, 1.6); o.jellyKick = max(o.jellyKick, 3.0)
                    onSocial?(.boop(partner: o.steerID)); o.onSocial?(.boop(partner: steerID))
                    AudioHub.shared.play(.boop, jelly: steerID, x: px, volume: 0.9)
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
                    let spot = fixed(to + u * (peerGap * 0.95))
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
                    onSocial?(.boop(partner: o.steerID)); o.onSocial?(.boop(partner: steerID))
                    AudioHub.shared.play(.boop, jelly: steerID, x: px, volume: 0.9)
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
