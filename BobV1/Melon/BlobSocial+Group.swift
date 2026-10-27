//
//  BlobSocial+Group.swift
//  Group socials (2026-10-26): when three or more free Jelbies are close (the home room with 3, the Park with up to 5, visitors included) every free one nearby joins one
//  session. One `SocialSession` holds the whole crew (`crew`, `crewIDs`; a / b / c are the first three); each member drives only itself from its own tick (its own sim),
//  and the initiator keeps the clock and moves the phase on. Everything is a sequencer over the locked moves (the walk, the in-place hop, the face-the-centre hold, the
//  pose overlays and jelly kicks), so arms stay stubby and feet attached. Anyone who is busy (eating, asleep, a toy, the bath, held) is never pulled in; if a member
//  gets taken away the group ends gently for the rest.
//    groupHug     all walk into a tight huddle facing the centre, squish together, sway gently, happy faces, hearts, then break apart with a little happy hop each
//    groupCheer   a loose circle: three synced cheer hops (a small crouch first), a last hearty one
//    conga        the first leads a short zig-zag walk, the others follow in a line; a wiggle runs down the line; a joy hop together at the end
//    circleDance  a tight ring that turns (everyone hops to the next place round the circle, facing the middle), then a joy hop
//  Frequency: the Jelby that has been among 2+ free ones for `GroupTuning.wait` seconds asks for one (a hug about every second time), then everybody in it has `cooldown`.
//

import Foundation
import simd

enum GroupTuning {
    /// Seconds spent together (3+ free and close) before a group move is asked for, drawn per Jelby.
    static let wait: (Float, Float) = (35, 95)
    /// Cooldown after any group move (per member).
    static let cooldown: (Float, Float) = (40, 75)
    /// How near a free Jelby must be (to the one who asks) to be pulled in, and the most that play together.
    static let radius: Float = 5.4
    static let maxCrew = 5
    /// Pick weights (the hug is the favourite).
    static let weights: [(SocialKind, Float)] = [(.groupHug, 4.5), (.groupCheer, 2.0), (.conga, 1.8), (.circleDance, 2.0)]
    /// Neighbouring bodies in a huddle / ring touch at this fraction of `peerGap`; a loose circle keeps this fraction.
    static let touch: Float = 0.78, loose: Float = 1.15
    static let steps = 8, stepAngle: Float = .pi / 4.5
    static let cheers = 3
}

extension SocialKind {
    var isGroup: Bool { self == .groupHug || self == .groupCheer || self == .conga || self == .circleDance }
}

extension BlobBrain {
    // MARK: choosing

    /// Free (or just out on an ordinary wander leg: he finishes it, then joins), calm, close Jelbies other than me (nearest first).
    func groupCandidates() -> [BlobBrain] {
        socialOthers().filter { $0 !== self && ($0.socialFree || $0.socialWandering) && $0.idleMood != .grumpy && $0.idleDeepNight < 0.5 && simd_distance($0.position, position) < GroupTuning.radius }
            .sorted { simd_distance($0.position, position) < simd_distance($1.position, position) }
    }

    /// Per tick while no session is on him: the wait for a crowd, then the roll.
    func socialGroupWatch(_ sim: SoftBody, _ dt: Float) {
        guard anticsEnabled, socialBook.enabled, socialFree, idleDeepNight < 0.5, idleMood != .grumpy else { return }
        guard socialBook.groupCool <= 0 else { return }
        // the wait runs while there is company close by (awake, not held); the start needs them free (or just walking) at the moment it is time
        let company = socialOthers().filter { $0 !== self && !$0.held && $0.idleState.kind != .sleep && simd_distance($0.position, position) < GroupTuning.radius }
        guard company.count >= 2 else { socialBook.groupIdle = max(0, socialBook.groupIdle - 0.5 * dt); return }
        socialBook.groupIdle += dt * (watching ? 1.5 : 1) * (perkFlags.social ? 1.25 : 1)
        guard socialBook.groupIdle >= socialBook.groupLimit else { return }
        let near = groupCandidates()
        guard near.count >= 2 else { return }          // (somebody is busy: it is tried again every tick until the crowd is free)
        let crew = Array(near.prefix(GroupTuning.maxCrew - 1))
        let night = max(idleNight, crew.map { $0.idleNight }.max() ?? 0)
        var w: [(SocialKind, Float)] = []
        for (k, x) in GroupTuning.weights {
            if k == socialBook.lastGroup || crew.contains(where: { $0.socialBook.lastGroup == k }) { continue }
            if k.isFast, fastOthers(except: crew) > 0 { continue }
            w.append((k, k == .groupHug ? x * (1 + 0.8 * night) : (k.isFast ? x * (1 - 0.8 * night) : x)))
        }
        if w.isEmpty { w = [(.groupHug, 1)] }
        var x = rand() * w.reduce(0) { $0 + $1.1 }
        var kind = w[0].0
        for (k, wt) in w { if x < wt { kind = k; break }; x -= wt }
        socialBook.groupLimit = rand(GroupTuning.wait.0, GroupTuning.wait.1)
        socialBook.groupIdle = 0
        if !socialStartGroup(kind, with: crew, sim) { socialBook.groupIdle = socialBook.groupLimit * 0.7 }          // (no room right now: try again soon)
    }

    // MARK: starting

    /// Plan a ring for `members` (the initiator first): centre, a spot and an angle each. nil = no room anywhere near.
    private func groupPlan(_ members: [BlobBrain], chord: Float, packed: Bool) -> (c: SIMD2<Float>, r: Float, ang: [Int: Float], spots: [Int: SIMD2<Float>])? {
        let n = members.count
        let r = max(chord / (2 * sinf(.pi / Float(n))), peerGap * 0.4)
        let cen = members.reduce(SIMD2<Float>.zero) { $0 + $1.position } / Float(n)
        // the slots: members sorted round the centre take equally spaced angles (the base angle is the circular mean of their offsets)
        let phis = members.map { atan2f($0.position.x - cen.x, $0.position.y - cen.y) }
        let order = members.indices.sorted { phis[$0] < phis[$1] }
        var sx: Float = 0, sy: Float = 0
        for (k, i) in order.enumerated() { let d = phis[i] - 2 * .pi * Float(k) / Float(n); sx += sinf(d); sy += cosf(d) }
        let base = atan2f(sx, sy)
        var ang = [Int: Float]()
        for (k, i) in order.enumerated() { ang[members[i].steerID] = base + 2 * .pi * Float(k) / Float(n) }
        let wasPass = socialBook.passThrough
        socialBook.passThrough = true          // (the floor rules only: the members' own bodies are not obstacles for their places)
        defer { socialBook.passThrough = wasPass }
        let offs: [SIMD2<Float>] = [.zero] + (0..<8).flatMap { k -> [SIMD2<Float>] in
            let a = Float(k) * .pi / 4
            return [SIMD2(sinf(a), cosf(a)) * 0.5, SIMD2(sinf(a), cosf(a)) * 1.0]
        }
        for off in offs {
            let c = cen + off
            var spots = [Int: SIMD2<Float>](), ok = true
            for m in members {
                let a = ang[m.steerID]!
                let want = c + SIMD2(sinf(a), cosf(a)) * r
                let p = fixed(want)
                if simd_distance(p, want) > 0.12 || simd_distance(p, m.position) > 4.8 { ok = false; break }
                if socialOthers().contains(where: { x in !members.contains { $0 === x } && simd_distance(x.position, p) < peerGap * 0.9 }) { ok = false; break }
                spots[m.steerID] = p
            }
            if ok { return (c, r, ang, spots) }
        }
        return nil
    }

    /// Start `kind` with me and `with` (+ the other free Jelbies close by, up to five). False = fewer than three free, or no room.
    @discardableResult
    func socialStartGroup(_ kind: SocialKind, with others: [BlobBrain], _ sim: SoftBody) -> Bool {
        guard socialFree else { return false }
        var crew: [BlobBrain] = [self]
        for o in others where o !== self && (o.socialFree || o.socialWandering) && !crew.contains(where: { $0 === o }) { crew.append(o) }
        for o in groupCandidates() where crew.count < GroupTuning.maxCrew && !crew.contains(where: { $0 === o }) { crew.append(o) }
        guard crew.count >= 3, crew.count <= GroupTuning.maxCrew else { return false }
        if kind.isFast, fastOthers(except: crew) > 0 { return false }
        currentPose(sim)
        for m in crew where !m.socialFree { guard m.socialBeckonStop() else { return false } }          // (out on a wander leg: it ends a few steps on, then he joins)
        let s: SocialSession
        switch kind {
        case .groupHug, .circleDance, .groupCheer:
            let packed = kind != .groupCheer
            guard let plan = groupPlan(crew, chord: peerGap * (packed ? GroupTuning.touch : GroupTuning.loose), packed: packed) else { return false }
            s = newGroupSession(kind, crew: crew, duration: kind == .groupHug ? vDur(5.8) : 0)
            s.home0 = plan.c; s.ringR = plan.r; s.slotAng = plan.ang
            s.slotSpot = plan.spots
        case .conga:
            s = newGroupSession(kind, crew: crew, duration: vDur(8.5))
            s.leaderWait = 0.2; s.home0 = position
        default: return false
        }
        for m in crew { m.socialBook.passThrough = (kind == .groupHug || kind == .circleDance); m.socialBook.hold = true; m.socialBook.faceYaw = m.yawTo(s.home0) }
        for m in crew { m.varietyNoteSocial(kind, with: nil) }
        return true
    }

    private func newGroupSession(_ kind: SocialKind, crew: [BlobBrain], duration: Float) -> SocialSession {
        let s = SocialSession(kind: kind, a: crew[0], b: crew[1])
        s.duration = duration
        s.crew = crew.map { CrewBox(b: $0) }; s.crewIDs = crew.map { $0.steerID }
        if crew.count > 2 { s.c = crew[2]; s.idC = crew[2].steerID }
        for m in crew {
            m.social = s
            m.socialBook.started[kind, default: 0] += 1
            m.socialBook.drought = 0; m.socialBook.invite = nil
            m.socialBook.droughtLimit = rand(SocialTuning.droughtRange.0, SocialTuning.droughtRange.1)
            m.socialBook.wakeGreet = -1
            m.socialBook.glanceDone = false; m.socialBook.apartStarted = false; m.socialBook.sheepishStarted = false; m.socialBook.hopStarted = false; m.socialBook.hopStarted2 = false
            m.socialBook.roundSeen = -1
            m.socialBook.groupIdle = 0
            if let x = crew.first(where: { $0 !== m }) { m.onSocial?(.began(kind, partner: x.steerID)) }
        }
        return s
    }

    // MARK: driving

    func driveGroup(_ s: SocialSession, _ mem: [BlobBrain], _ isA: Bool, _ sim: SoftBody, _ dt: Float) {
        switch s.kind {
        case .groupHug: driveHug(s, mem, isA, sim)
        case .groupCheer: driveCheer(s, mem, isA, sim)
        case .conga: driveConga(s, mem, isA, sim, dt)
        case .circleDance: driveCircle(s, mem, isA, sim)
        default: break
        }
    }

    private var myIndex: Int { social?.crewIDs.firstIndex(of: steerID) ?? 0 }
    private func slot(_ s: SocialSession) -> SIMD2<Float> { s.slotSpot[steerID] ?? position }
    private func faceCentre(_ s: SocialSession) { holdFacing(yawTo(s.home0)) }
    private func everyone(_ mem: [BlobBrain], _ f: (BlobBrain) -> Bool) -> Bool { mem.allSatisfy(f) }

    /// Phase 0 (all kinds with a ring): walk to my place. Phase 1: turn to the centre and settle. Returns true while still gathering.
    private func gather(_ s: SocialSession, _ mem: [BlobBrain], _ isA: Bool, _ sim: SoftBody, settle: Float) -> Bool {
        switch s.phase {
        case 0:
            let spot = slot(s)
            if !socialBook.hopStarted, fxFree {
                socialBook.hopStarted = true
                letGo()
                if simd_distance(position, spot) > 0.12 { socialWalk(to: spot, sim) }
            }
            if socialBook.hopStarted, fxFree, simd_distance(position, spot) > 0.15, simd_distance(position, spot) < 1.4, socialBook.hopStarted2 == false {
                socialBook.hopStarted2 = true          // (the walk stopped short of the place: a small hop to it)
                startHopTo(sim, spot)
            }
            if scriptIsNone, idleState.kind == nil { faceCentre(s) }
            if isA {
                let arrived = everyone(mem) { $0.socialBook.hopStarted && $0.fxFree && simd_distance($0.position, $0.slot(s)) < 0.45 }
                if arrived, s.phaseT > 0.3 { s.setPhase(1) }
                else if s.phaseT > 12 { s.finish(.aborted) }
            }
            return true
        case 1:
            faceCentre(s)
            socialBook.wantSquash = 1 - 0.04 * smooth01(s.phaseT / 0.4) * socialGentle
            if isA, s.phaseT > settle, everyone(mem, { $0.turnedTo($0.yawTo(s.home0), tol: 0.2) }) || s.phaseT > settle + 2.5 { s.setPhase(2) }
            return true
        default: return false
        }
    }

    /// A joy hop for each member at its own beat (`stagger` seconds apart); true when everyone has hopped and landed.
    private func joyHop(_ s: SocialSession, _ mem: [BlobBrain], _ sim: SoftBody, key: Int, stagger: Float, face f: Bool = true) -> Bool {
        stepKey(key)
        if !socialBook.apartStarted, fxFree, s.phaseT >= Float(myIndex) * stagger {
            socialBook.apartStarted = true
            hopJoy(sim, joy: f)
            AudioHub.shared.chirp(jelly: steerID, myIndex % 2 == 0 ? .happy : .babble)
        }
        if !socialBook.apartStarted { faceCentre(s) }
        return everyone(mem) { $0.socialBook.apartStarted && $0.fxFree } && s.phaseT > 0.5
    }

    private func endGroup(_ s: SocialSession, _ mem: [BlobBrain]) {
        s.finish(.done)
        for m in mem { for x in mem where x !== m { m.onSocial?(.makeUp(partner: x.steerID)); break } }
    }

    // MARK: group hug

    private func driveHug(_ s: SocialSession, _ mem: [BlobBrain], _ isA: Bool, _ sim: SoftBody) {
        if gather(s, mem, isA, sim, settle: 0.5) { return }
        let g = socialGentle, n = Float(mem.count)
        switch s.phase {
        case 2:    // the huddle: lean in, squish together, a gentle shared sway, eyes soft
            let ft = s.phaseT
            faceCentre(s)
            let lean = smooth01(ft / 0.9) * (1 - smooth01((ft - (s.duration - 0.7)) / 0.7))
            let sway = sinf(2 * .pi * (ft - 0.9) / 2.6) * smooth01((ft - 0.9) / 0.9)          // (all sway the same way in the world: one big soft body)
            socialBook.wantPitch = 0.09 * lean * g
            socialBook.wantRoll = worldLean(1) * 0.07 * lean * sway * g
            socialBook.wantEyes = 1 - 0.6 * lean
            socialBook.wantSquash = 1 - (0.035 + 0.012 * n / 5) * lean - 0.012 * lean * abs(sway)
            if isA {
                if !s.impacted, ft > 0.7 {          // the squish, and the first heart burst
                    s.impacted = true
                    for m in mem {
                        m.jellyKick = max(m.jellyKick, 2.0 + 0.3 * n / 5)
                        m.face(.joyArc, hold: 1.6)
                        for x in mem where x !== m { m.onSocial?(.boop(partner: x.steerID)); break }
                        for x in mem where x !== m { m.onSocial?(.makeUp(partner: x.steerID)); break }
                    }
                    AudioHub.shared.play(.squish, jelly: steerID, x: px, volume: 0.7)
                    AudioHub.shared.chirp(jelly: steerID, .happy)
                }
                if s.passes == 0, ft > 2.2 {          // a squeeze and an "aww"
                    s.passes = 1
                    for (i, m) in mem.enumerated() { m.jellyKick = max(m.jellyKick, 1.4); if i < 2 { AudioHub.shared.chirp(jelly: m.steerID, i == 0 ? .babble : .happy) } }
                    AudioHub.shared.play(.squish, jelly: steerID, x: px, volume: 0.45)
                }
                if s.passes == 1, ft > s.duration - 1.6 {          // the last heart burst
                    s.passes = 2
                    for m in mem { for x in mem where x !== m { m.onSocial?(.makeUp(partner: x.steerID)); break } }
                }
                if ft > s.duration { s.setPhase(3) }
            }
        default:   // break apart with a little happy hop each
            socialBook.passThrough = false
            if joyHop(s, mem, sim, key: 1500, stagger: 0.12), isA { endGroup(s, mem) }
            else if isA, s.phaseT > 6 { endGroup(s, mem) }
        }
    }

    // MARK: group cheer

    private func driveCheer(_ s: SocialSession, _ mem: [BlobBrain], _ isA: Bool, _ sim: SoftBody) {
        if gather(s, mem, isA, sim, settle: 0.5) { return }
        let g = socialGentle
        switch s.phase {
        case 2:    // everybody crouches a hair, then hops together (in sync), three times
            let t = s.phaseT
            stepKey(1600 + s.round)
            if !socialBook.hopStarted { faceCentre(s) }
            socialBook.wantSquash = 1 - 0.08 * g * smooth01(t / 0.35) * (socialBook.hopStarted ? 0 : 1)
            if !socialBook.hopStarted, fxFree, t >= 0.4 {
                socialBook.hopStarted = true
                hopJoy(sim)
                if myIndex < 2 { AudioHub.shared.chirp(jelly: steerID, myIndex == 0 ? .happy : .babble) }
                jellyKick = max(jellyKick, 1.4 + 0.5 * Float(s.round))
            }
            if isA {
                if everyone(mem, { $0.socialBook.hopStarted && $0.fxFree }), t > 1.2 {
                    s.round += 1
                    if s.round >= GroupTuning.cheers { s.setPhase(3) } else { s.setPhase(2) }
                    if s.round == GroupTuning.cheers - 1 { for m in mem { for x in mem where x !== m { m.onSocial?(.makeUp(partner: x.steerID)); break } } }
                } else if t > 6 { s.finish(.aborted) }
            }
        default:
            socialBook.wantPitch = 0
            if joyHop(s, mem, sim, key: 1650, stagger: 0.0), isA { endGroup(s, mem) }
            else if isA, s.phaseT > 6 { endGroup(s, mem) }
        }
    }

    // MARK: conga

    /// The next wiggly leg of the leader: left, then right of the way it was going.
    private func congaGoal(_ s: SocialSession) -> SIMD2<Float>? {
        let here = position
        let heading: Float = s.laneYaw == 0 && s.round == 0 ? yaw : s.laneYaw
        let sgn: Float = s.round % 2 == 0 ? 1 : -1
        for dev: Float in [0.9, 0.55, 1.3, 0.25] {
            for sg in [sgn, -sgn] {
                let a = heading + sg * dev
                let g = here + SIMD2(sinf(a), cosf(a)) * 1.5
                let q = fixed(g)
                if simd_distance(q, g) < 0.06, legClear(here, q, margin: steerMargin), !socialOthers().contains(where: { x in !(s.members.contains { $0 === x }) && simd_distance(x.position, q) < peerGap }) {
                    s.laneYaw = atan2f(q.x - here.x, q.y - here.y)
                    return q
                }
            }
        }
        return nil
    }

    private func followAhead(_ L: BlobBrain, _ sim: SoftBody) {
        let p = L.position, me = position
        let d = simd_distance(p, me)
        if d > followGap + 0.3 {
            socialBook.hold = false
            let u = (p - me) / d
            if scriptIsNone && idleState.kind == nil { socialWalk(to: fixed(p - u * followGap), sim) }
        } else if scriptIsNone { holdFacing(yawTo(p)) }
    }

    private func driveConga(_ s: SocialSession, _ mem: [BlobBrain], _ isA: Bool, _ sim: SoftBody, _ dt: Float) {
        let t = s.t
        if s.phase == 0 {          // an excited hop together, then off they go
            stepKey(1700)
            if !socialBook.apartStarted, fxFree, s.phaseT >= Float(myIndex) * 0.1 {
                socialBook.apartStarted = true
                hopJoy(sim)
                AudioHub.shared.chirp(jelly: steerID, .happy)
            }
            if isA, everyone(mem, { $0.socialBook.apartStarted && $0.fxFree }), s.phaseT > 0.5 { s.setPhase(1); s.leaderWait = 0 }
            else if isA, s.phaseT > 5 { s.setPhase(1); s.leaderWait = 0 }
            if !socialBook.apartStarted { holdFacing(faceCameraYaw()) }
            return
        }
        if s.phase == 1 {
            if myIndex == 0 {          // the leader zig-zags, leg after leg
                if isA, t > s.duration { s.setPhase(2); return }
                if fxFree {
                    s.leaderWait -= dt
                    if s.leaderWait <= 0 {
                        if let g = congaGoal(s) { letGo(); socialWalk(to: g, sim); s.leaderWait = rand(0.15, 0.4); s.round += 1 }
                        else { s.setPhase(2) }
                    }
                }
            } else {
                followAhead(mem[myIndex - 1], sim)
                // a wiggle runs down the line: a soft kick, one after another
                let beat = t * 1.7 - Float(myIndex) * 0.35
                if beat > 0, Int(beat) != Int(beat - 1.7 * dt) { jellyKick = max(jellyKick, 0.9); if myIndex == 1 { AudioHub.shared.chirp(jelly: steerID, .babble) } }
            }
            if myIndex == 0 { let beat = t * 1.7; if Int(beat) != Int(beat - 1.7 * dt) { jellyKick = max(jellyKick, 0.9) } }
            return
        }
        // the end: everybody stops, a joy hop together
        if s.phase == 2 { stepKey(1710); if isA { s.home0 = mem[0].position; s.setPhase(3) }; return }
        if joyHop(s, mem, sim, key: 1720, stagger: 0.1), isA { endGroup(s, mem) }
        else if isA, s.phaseT > 7 { endGroup(s, mem) }
    }

    // MARK: circle dance

    private func driveCircle(_ s: SocialSession, _ mem: [BlobBrain], _ isA: Bool, _ sim: SoftBody) {
        if gather(s, mem, isA, sim, settle: 0.5) { return }
        let t = s.phaseT
        switch s.phase {
        case 2:    // everyone hops to the next place round the ring, facing the middle (the ring turns)
            socialBook.passThrough = true
            stepKey(1800 + s.round)
            if !socialBook.hopStarted { if fxFree { faceCentre(s) } }
            if !socialBook.hopStarted, fxFree, t > (s.round == 0 ? 0.3 : 0.1), turnedTo(yawTo(s.home0), tol: 0.2) {
                socialBook.hopStarted = true
                let dir: Float = s.round < GroupTuning.steps / 2 ? 1 : -1          // (round one way, then back the other)
                let k = Float(s.round < GroupTuning.steps / 2 ? s.round + 1 : GroupTuning.steps - s.round - 1)
                let ang = (s.slotAng[steerID] ?? 0) + dir * k * GroupTuning.stepAngle
                letGo()
                startHopTo(sim, s.home0 + SIMD2(sinf(ang), cosf(ang)) * s.ringR)
                if myIndex == 0 { jellyKick = max(jellyKick, 0.6); if s.round % 3 == 0 { AudioHub.shared.chirp(jelly: steerID, .happy) } }
                if myIndex == 1, s.round % 3 == 1 { AudioHub.shared.chirp(jelly: steerID, .babble) }
            }
            if isA {
                if everyone(mem, { $0.socialBook.hopStarted && $0.fxFree }), t > 0.45 {
                    s.round += 1
                    if s.round >= GroupTuning.steps { s.setPhase(3) } else { s.setPhase(2) }
                } else if t > 4 { s.finish(.aborted) }
            }
        default:    // let go: a joy hop each, hearts
            socialBook.passThrough = false
            if joyHop(s, mem, sim, key: 1850, stagger: 0.1), isA { endGroup(s, mem) }
            else if isA, s.phaseT > 6 { endGroup(s, mem) }
        }
    }
}
