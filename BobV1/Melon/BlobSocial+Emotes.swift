//
//  BlobSocial+Emotes.swift
//  Two rare group treats (2026-11-02, user-approved) on top of the social layer, and the scheduler rules for them (the third, the high five, lives in BlobSocial+Friends.swift):
//    congaLine  the leader walks a gentle curved route (a polyline of 1.5 u legs, each turn <= 0.8 rad, planned on the floor rules), the others line up behind him on the straight
//               extension of the first leg (slots from `Lineup.best`, so the walks to them do not cross) and follow ~1 gap (1.15: the line is formed from where they stand, round a standing leader, so it cannot be closer) behind along the SAME waypoints, so the line is
//               in his wake whatever the curve. A shared side-to-side waddle roll + a small squash bounce ride on the locked walk as additive social overlays (the gait is not touched),
//               a soft tick on the beat. 8...14 s, then they stop, hop with a giggle each and scatter. Two Jelbies make a line of two.
//    ringDance  three gather on a small ring (`Lineup.best` over the ring's slots, chord >= 1.12 gap so the mid-step spacing stays above the steering floor), face the centre and
//               hop in rhythm, alternating (the middle one on the off-beat): bounce, bounce, a quarter-turn shuffle round the ring (a real walk leg of ~1.3 u: the feet walk, nothing
//               slides), bounce; then the same back the other way; a soft chime on each hop. Then a joy hop each and let go.
//  Both are sequencers over the locked moves (the walk, the in-place hop, the face-the-centre hold, pose overlays, jelly kicks): arms stay stubby, feet attached (GroupEmoteFeetTests).
//  They are ambient: the HUD stays, any touch / menu / voice command on any member ends the session and releases everybody (the walkers stop).
//  Rarity: a Jelbie asks for a treat after `treatWait` s with company (all awake housemates free and calm, never at night), then every member has `treatCooldown` (>= 4 min).
//

import Foundation
import simd

enum EmoteTuning {
    /// A high five: the pair's cooldown (s), a crossing (the partner is out on a wander leg) makes it likelier.
    static let fiveCooldown: (Float, Float) = (60, 90)
    static let fiveCrossingBoost: Float = 1.8, fiveWeight: Float = 1.2
    /// The two stand side by side this far apart (x the room gap) so the inner little arm nubs reach nub to nub.
    static let highFiveGap: Float = 0.97
    /// Per Jelbie after any treat (s); the first one is not before `treatFirst` s; the wait with company before one asks for a treat.
    static let treatCooldown: (Float, Float) = (240, 420)
    static let treatFirst: Float = 90
    static let treatWait: (Float, Float) = (40, 90)
    static let treatCrew = 3
    /// Conga: the gap between two in the line (x peerGap), the leg length (u), the longest route (legs), waddle frequency (Hz) and roll (rad).
    static let congaGap: Float = 1.15, congaLeg: Float = 1.5, maxLegs = 7, minLegs = 3
    static let waddleHz: Float = 1.8, waddleRoll: Float = 0.055, waddleSquash: Float = 0.03
    /// Ring: chord between neighbours (x peerGap), the plan of steps (0 = bounce, 1 = quarter-turn shuffle), the pitch of each member's chime.
    static let ringChord: Float = 1.25
    static let ringPlan: [Int] = [0, 0, 1, 0, 0, 0, 1, 0]
    static let ringPitch: [Float] = [1.0, 1.26, 1.5, 1.12, 1.33]
}

/// Haptics of the group emotes (2026-11-02, "subtle, soft, never buzzy"): single soft transients, requested through the brain's hook (the stage forwards them to the touch haptics, which
/// no-op until the engine is warm and honour the Settings toggle; the stage also gates them to ~2 per second and skips them while a race, volley or bath runs).
///   highFive   one light tap exactly at the nub bump, with the boop
///   congaLine  one gentle pulse when the line forms (it sets off) and one when they scatter - no rhythm haptic
///   ringDance  one pulse when the ring forms and one when they let go
enum EmoteHaptic {
    static let tap: (i: Float, s: Float) = (0.32, 0.22), pulse: (i: Float, s: Float) = (0.24, 0.15)
    /// The stage's global limit: at most one emote haptic per this many seconds (~2 per second).
    static let minGap: Double = 0.5
    /// Test seam: every request, "highFive.bump", "congaLine.form" ...
    nonisolated(unsafe) static var requestTap: ((String) -> Void)?
    /// When the stage last let one through (all Jelbies share the limit).
    nonisolated(unsafe) static var last: Double = -10
}

extension BlobBrain {
    func emoteHaptic(_ tag: String, _ level: (i: Float, s: Float)) {
        EmoteHaptic.requestTap?(tag)
        onEmoteHaptic?(level.i, level.s)
    }

    // MARK: the scheduler

    /// Per tick while no session is on him: the wait with company, then the roll for a treat. Everybody awake must be free and calm (a meal, bath, trip, nap, toy or a
    /// pending request anywhere means no treat); two free Jelbies make a conga line, three also a ring dance.
    func socialTreatWatch(_ sim: SoftBody, _ dt: Float) {
        guard anticsEnabled, socialBook.enabled, social == nil, !held, autonomy || idleForced, idleState.kind != .sleep, idleDeepNight < 0.5, idleNight < 0.5, idleMood != .grumpy,
              socialBook.treatCool <= 0 else { return }
        let others = socialOthers().filter { $0 !== self }
        let awake = others.filter { $0.idleState.kind != .sleep && !$0.sleepLocked }
        guard !awake.isEmpty, awake.allSatisfy({ !$0.held && simd_distance($0.position, position) < GroupTuning.radius }) else { socialBook.treatIdle = max(0, socialBook.treatIdle - 0.5 * dt); return }
        socialBook.treatIdle += dt * (watching ? 1.5 : 1) * (perkFlags.social ? 1.25 : 1)
        guard socialBook.treatIdle >= socialBook.treatLimit, socialFree else { return }
        let near = groupCandidates()
        guard near.count == awake.count, near.allSatisfy({ $0.socialBook.treatCool <= 0 && $0.anticsEnabled && $0.idleNight < 0.5 }) else { return }          // (somebody is busy: tried again every tick until all are free)
        let crew = Array(near.prefix(EmoteTuning.treatCrew - 1))
        var kinds: [SocialKind] = crew.count >= 2 ? [.congaLine, .ringDance] : [.congaLine]
        let repeated = ([socialBook.lastTreat] + crew.map { $0.socialBook.lastTreat }).compactMap { $0 }
        let fresh = kinds.filter { k in !repeated.contains(k) }
        if !fresh.isEmpty { kinds = fresh }
        let kind = kinds[min(kinds.count - 1, Int(rand() * Float(kinds.count)))]
        socialBook.treatLimit = rand(EmoteTuning.treatWait.0, EmoteTuning.treatWait.1)
        socialBook.treatIdle = 0
        if !socialStartGroup(kind, with: crew, sim) { socialBook.treatIdle = socialBook.treatLimit * 0.7 }          // (no room right now: soon again)
    }

    // MARK: planning

    private func floorSpotOK(_ p: SIMD2<Float>) -> Bool {
        let r = resolve(SIMD3(p.x, 0, p.y), footprint + steerMargin)
        return simd_distance(SIMD2(r.x, r.z), p) < 0.06
    }
    private func floorLegOK(_ a: SIMD2<Float>, _ b: SIMD2<Float>) -> Bool {
        let d = b - a, n = max(2, Int(simd_length(d) / 0.1))
        for i in 1...n where !floorSpotOK(a + d * (Float(i) / Float(n))) { return false }
        return true
    }
    private func segDist(_ p: SIMD2<Float>, _ a: SIMD2<Float>, _ b: SIMD2<Float>) -> Float {
        let ab = b - a, l2 = simd_dot(ab, ab)
        let t = l2 > 1e-6 ? min(max(simd_dot(p - a, ab) / l2, 0), 1) : 0
        return simd_distance(p, a + ab * t)
    }

    /// The session of a treat (the initiator is the leader / first of the ring); nil = no room for it.
    func emoteSetup(_ kind: SocialKind, crew: [BlobBrain]) -> SocialSession? {
        let was = socialBook.passThrough
        socialBook.passThrough = true          // (the floor rules only: the crew's own bodies are not obstacles for the plan)
        defer { socialBook.passThrough = was }
        return kind == .congaLine ? congaPlan(crew) : ringPlan(crew)
    }

    private func congaPlan(_ crew: [BlobBrain]) -> SocialSession? {
        let n = crew.count
        let strangers = socialOthers().filter { x in !crew.contains { $0 === x } }.map(\.position)
        let gapBehind = peerGap * EmoteTuning.congaGap
        let want = min(EmoteTuning.maxLegs, max(EmoteTuning.minLegs, Int((rand(8, 14)) * 0.55)))
        var best: (score: Float, leader: Int, h: Float, path: [SIMD2<Float>], slots: [SIMD2<Float>])?
        let cam = faceCameraYaw()
        // whoever of the crew can lead a line that the others can walk into (from where they stand) leads it
        for li in crew.indices {
            let p0 = crew[li].position
            let followersNow = crew.enumerated().filter { $0.offset != li }.map(\.element)
            for k in 0..<12 {
                let h0 = cam + Float(k) * .pi / 6
                let u = SIMD2(sinf(h0), cosf(h0))
                var slots: [SIMD2<Float>] = []
                var ok = true
                for i in 1..<n {
                    let w = p0 - u * gapBehind * Float(i)
                    guard floorSpotOK(w), !strangers.contains(where: { simd_distance($0, w) < peerGap * 0.95 }) else { ok = false; break }
                    slots.append(w)
                }
                guard ok else { continue }
                let so = Lineup.best(from: followersNow.map(\.position), slots: slots, locked: followersNow.map { _ in nil }, centre: nil, bystanders: strangers)
                guard followersNow.indices.allSatisfy({ i in
                    let a = followersNow[i].position, b = slots[so[i]]
                    return simd_distance(a, b) < GroupTuning.walkMax && floorLegOK(a, b) && segDist(p0, a, b) >= peerGap * 0.8 && !strangers.contains(where: { segDist($0, a, b) < peerGap * 0.9 })
                }) else { continue }          // (a straight walk to each place: past neither the leader nor anybody else)
                var pts = [p0], h = h0, sgn: Float = k % 2 == 0 ? 1 : -1
                for leg in 0..<want {
                    let turns: [Float] = leg == 0 ? [0] : [sgn * 0.4, 0, -sgn * 0.4, sgn * 0.8, -sgn * 0.8]
                    var next: (SIMD2<Float>, Float)?
                    for dh in turns {
                        let h1 = h + dh
                        let a = pts.last!, w = a + SIMD2(sinf(h1), cosf(h1)) * EmoteTuning.congaLeg
                        guard floorSpotOK(w), floorLegOK(a, w), !strangers.contains(where: { segDist($0, a, w) < peerGap * 0.97 }) else { continue }
                        if pts.count >= 2, pts.dropLast().contains(where: { simd_distance($0, w) < peerGap }) { continue }          // (not back over itself: nobody walks through the tail)
                        next = (w, h1); break
                    }
                    guard let nx = next else { break }
                    pts.append(nx.0); h = nx.1
                    if leg % 2 == 1 { sgn = -sgn }
                }
                let legs = pts.count - 1
                guard legs >= EmoteTuning.minLegs else { continue }
                let sideways = abs(sinf(h0 - cam))          // (prefers a line that crosses the screen)
                let score = min(Float(legs), 6) + 3.0 * sideways - (li == 0 ? 0 : 0.3)
                if best == nil || score > best!.score { best = (score, li, h0, pts, slots) }
            }
        }
        guard let b = best else { return nil }
        // the followers' places in the line: the assignment whose walks do not cross
        let leader = crew[b.leader]
        let followers = crew.enumerated().filter { $0.offset != b.leader }.map(\.element)
        let slotOf = Lineup.best(from: followers.map(\.position), slots: b.slots, locked: followers.map { _ in nil }, centre: nil, bystanders: strangers)
        let order = followers.indices.sorted { slotOf[$0] < slotOf[$1] }
        let ordered = [leader] + order.map { followers[$0] }
        let s = newGroupSession(.congaLine, crew: ordered, duration: vDur(rand(8, 14)))
        s.path = b.path; s.laneYaw = b.h; s.home0 = leader.position
        for i in order { s.slotSpot[followers[i].steerID] = b.slots[slotOf[i]] }
        return s
    }

    private func ringPlan(_ crew: [BlobBrain]) -> SocialSession? {
        let n = crew.count
        guard n == 3 else { return nil }
        let chord = peerGap * EmoteTuning.ringChord
        let r = chord / (2 * sinf(.pi / Float(n)))
        let cen = crew.reduce(SIMD2<Float>.zero) { $0 + $1.position } / Float(n)
        let strangers = socialOthers().filter { x in !crew.contains { $0 === x } }.map(\.position)
        let offs: [SIMD2<Float>] = [.zero] + (0..<8).flatMap { k -> [SIMD2<Float>] in
            let a = Float(k) * .pi / 4
            return [SIMD2(sinf(a), cosf(a)) * 0.5, SIMD2(sinf(a), cosf(a)) * 1.0]
        }
        var best: (cost: Float, c: SIMD2<Float>, base: Float, dir: Float, slotOf: [Int], spots: [SIMD2<Float>])?
        for off in offs {
            let c = cen + off
            for bk in 0..<12 {
                let base = Float(bk) * .pi / 6
                let spots = (0..<n).map { c + SIMD2(sinf(base + 2 * .pi * Float($0) / Float(n)), cosf(base + 2 * .pi * Float($0) / Float(n))) * r }
                guard spots.allSatisfy({ sp in floorSpotOK(sp) && !strangers.contains(where: { q in simd_distance(q, sp) < peerGap * 0.95 }) }) else { continue }
                // the shuffle: a quarter turn one way (and back): the points at +45 and +90 degrees from every slot must be floor too
                var dir: Float = 0
                for d: Float in [1, -1] {
                    let pts = (0..<n).flatMap { i -> [SIMD2<Float>] in
                        let a = base + 2 * .pi * Float(i) / Float(n)
                        return [c + SIMD2(sinf(a + d * .pi / 4), cosf(a + d * .pi / 4)) * r, c + SIMD2(sinf(a + d * .pi / 2), cosf(a + d * .pi / 2)) * r]
                    }
                    if pts.allSatisfy({ sp in floorSpotOK(sp) && !strangers.contains(where: { q in simd_distance(q, sp) < peerGap * 0.9 }) }) { dir = d; break }
                }
                guard dir != 0 else { continue }
                let from = crew.map(\.position)
                let slotOf = Lineup.best(from: from, slots: spots, locked: crew.map { _ in nil }, centre: nil, bystanders: strangers)
                guard !slotOf.contains(-1), crew.indices.allSatisfy({ simd_distance(from[$0], spots[slotOf[$0]]) < GroupTuning.walkMax }) else { continue }
                let cost = Lineup.cost(from: from, slots: spots, slotOf: slotOf, centre: nil, bystanders: strangers) + 0.3 * simd_length(off)
                if best == nil || cost < best!.cost { best = (cost, c, base, dir, slotOf, spots) }
            }
        }
        guard let b = best else { return nil }
        let s = newGroupSession(.ringDance, crew: crew, duration: 0)
        s.home0 = b.c; s.ringR = r; s.roles = b.dir > 0 ? 0 : 1; s.laneYaw = 0
        for (i, m) in crew.enumerated() {
            s.slotSpot[m.steerID] = b.spots[b.slotOf[i]]
            s.slotAng[m.steerID] = b.base + 2 * .pi * Float(b.slotOf[i]) / Float(n)
        }
        return s
    }

    // MARK: conga line

    /// `path` with its last `d` units cut off (along the polyline): where a follower `d` behind the leader's last point stands.
    func trimmedPath(_ path: [SIMD2<Float>], by d: Float) -> [SIMD2<Float>] {
        var pts = path, rem = d
        while pts.count >= 2 {
            let a = pts[pts.count - 2], b = pts[pts.count - 1]
            let l = simd_distance(a, b)
            if l > rem + 0.05 { pts[pts.count - 1] = b + (a - b) / l * rem; return pts }
            rem -= l; pts.removeLast()
        }
        return pts
    }

    func driveCongaLine(_ s: SocialSession, _ mem: [BlobBrain], _ isA: Bool, _ sim: SoftBody, _ dt: Float) {
        let idx = myIndex, n = mem.count
        switch s.phase {
        case 0:    // the line forms: the leader stands facing along the first leg, the followers walk to their places behind him
            if idx == 0 {
                if fxFree { holdFacing(s.laneYaw) }
            } else {
                let spot = slot(s)
                if fxFree {
                    // (a walk that was given up on the way - a crossing walker in the way - is simply started again)
                    socialBook.hopStarted = true; letGo()
                    if simd_distance(position, spot) > 0.15 { socialWalk(to: spot, sim) } else { holdFacing(s.laneYaw) }
                }
            }
            if isA {
                let ready = mem.indices.allSatisfy { i in
                    let m = mem[i]
                    return m.fxFree && m.turnedTo(s.laneYaw, tol: 0.2) && (i == 0 || (m.socialBook.hopStarted && simd_distance(m.position, m.slot(s)) < 0.3))
                }
                if ready, s.phaseT > 0.5 { s.setPhase(1); s.choreo = true; s.moveT = 0; s.passes = 0; emoteHaptic("congaLine.form", EmoteHaptic.pulse) }
                else if s.phaseT > 14 { s.finish(.aborted) }
            }
        case 1:    // off they go along the same waypoints; the waddle rides on the walk
            if isA { s.moveT += dt }
            let t = s.moveT
            if !socialBook.apartStarted, fxFree, t >= 0 {
                socialBook.apartStarted = true; letGo()
                // (the same waypoints; each stops his own gap short of the leader's last point, so the line does not bunch up when the leader stops)
                let pts = trimmedPath(s.path, by: Float(idx) * peerGap * EmoteTuning.congaGap)
                if let last = pts.last, pts.count >= 2 {
                    socialWalk(to: last, sim)
                    route = Array(pts.dropFirst().dropLast())
                }
            }
            let ramp = smooth01(t / 0.7)
            let ph = 2 * Float.pi * EmoteTuning.waddleHz * t
            socialBook.wantRoll = EmoteTuning.waddleRoll * ramp * socialGentle * sinf(ph)
            socialBook.wantSquash = 1 - EmoteTuning.waddleSquash * ramp * socialGentle * abs(sinf(ph))
            let beat = Int(floorf(2 * EmoteTuning.waddleHz * t))          // (a beat at each step of the waddle: both feet of the line go down together)
            if isA, beat != s.passes, t > 0.3 {
                s.passes = beat
                for (i, m) in mem.enumerated() {
                    m.jellyKick = max(m.jellyKick, 0.55)
                    if i == beat % n { AudioHub.shared.play(.congaTick, jelly: m.steerID, x: m.px, volume: 0.5) }
                }
            }
            if isA {
                let leaderDone = mem[0].socialBook.apartStarted && mem[0].fxFree
                if leaderDone, t > 1.0 { s.setPhase(2) }
                else if t > s.duration + 8 { s.setPhase(2) }
            }
        case 2:    // the line stops: everybody ends their own walk where it is, then the joy
            socialBook.wantRoll = 0; socialBook.wantSquash = 1
            if fxFree { holdFacing(yaw) }
            if isA, everyone(mem, { $0.fxFree }), s.phaseT > 0.4 { s.home0 = mem.reduce(SIMD2<Float>.zero) { $0 + $1.position } / Float(n); s.setPhase(3); emoteHaptic("congaLine.scatter", EmoteHaptic.pulse) }
            else if isA, s.phaseT > 8 { s.setPhase(3); emoteHaptic("congaLine.scatter", EmoteHaptic.pulse) }
        default:   // scatter, giggling: a joy hop each (one after another), then a short walk away from the others
            stepKey(2100)
            if !socialBook.apartStarted, fxFree, s.phaseT >= Float(idx) * 0.14 {
                socialBook.apartStarted = true
                hopJoy(sim)
                AudioHub.shared.chirp(jelly: steerID, idx % 2 == 0 ? .happy : .babble)
                jellyKick = max(jellyKick, 1.0)
            }
            if socialBook.apartStarted, !socialBook.sheepishStarted, fxFree {
                socialBook.sheepishStarted = true
                var away = position - s.home0
                if simd_length(away) < 0.2 { let a = 2 * Float.pi * Float(idx) / Float(n) + 0.7; away = SIMD2(sinf(a), cosf(a)) }
                away = simd_normalize(away)
                for len: Float in [1.1, 0.8, 0.5] {
                    let q = fixed(position + away * len)
                    if simd_distance(q, position) > 0.3, peerFree(q), legClear(position, q, margin: steerMargin) { socialWalk(to: q, sim); break }
                }
            }
            if !socialBook.apartStarted { holdFacing(yawTo(s.home0)) }
            if isA {
                if everyone(mem, { $0.socialBook.sheepishStarted }), s.phaseT > 0.6 { endGroup(s, mem) }
                else if s.phaseT > 7 { endGroup(s, mem) }
            }
        }
    }

    // MARK: ring dance

    func driveRingDance(_ s: SocialSession, _ mem: [BlobBrain], _ isA: Bool, _ sim: SoftBody, _ dt: Float) {
        if gather(s, mem, isA, sim, settle: 0.6) { return }
        let idx = myIndex
        let plan = EmoteTuning.ringPlan
        switch s.phase {
        case 2:    // the dance
            s.choreo = true
            if isA, s.fastMoves == 0 { s.fastMoves = 1; emoteHaptic("ringDance.form", EmoteHaptic.pulse) }
            let step = min(s.round, plan.count - 1)
            stepKey(2200 + s.round)
            let t = s.phaseT
            let centre = yawTo(s.home0)
            if fxFree { holdFacing(centre) }
            if plan[step] == 0 {
                // a bounce: the first and last stand on the beat, the middle one on the off-beat (alternating)
                let off: Float = idx % 2 == 1 ? 0.33 : 0
                if !socialBook.hopStarted, fxFree, t >= 0.2 + off, turnedTo(centre, tol: 0.25) {
                    socialBook.hopStarted = true
                    letGo()
                    startHopPlay(sim: sim, distance: 0.0001)
                    jellyKick = max(jellyKick, 1.1)
                    AudioHub.shared.play(.ringChime, jelly: steerID, x: px, volume: 0.45, rate: EmoteTuning.ringPitch[idx % EmoteTuning.ringPitch.count])
                    if s.round == 3 || s.round == 7, idx == 0 { AudioHub.shared.chirp(jelly: steerID, .happy) }
                }
                if isA {
                    if everyone(mem, { $0.socialBook.hopStarted && $0.fxFree }), t > 1.0 { s.round += 1; s.setPhase(s.round >= plan.count ? 3 : 2) }
                    else if t > 6 { s.finish(.aborted) }
                }
            } else {
                // a quarter-turn shuffle round the ring: a real walk leg to the point 90 degrees on (the other way the second time)
                let dir: Float = (s.roles == 0 ? 1 : -1) * (s.round < 4 ? 1 : -1)
                if !socialBook.hopStarted, fxFree, s.impacted {          // (all go on the same beat: the three paths shrink and turn together, never one into another)
                    socialBook.hopStarted = true
                    letGo()
                    let a = (s.slotAng[steerID] ?? 0) + s.laneYaw + dir * .pi / 2
                    let spot = s.home0 + SIMD2(sinf(a), cosf(a)) * s.ringR
                    socialWalk(to: spot, sim)
                    AudioHub.shared.play(.ringChime, jelly: steerID, x: px, volume: 0.35, rate: EmoteTuning.ringPitch[(idx + 3) % EmoteTuning.ringPitch.count])
                }
                if isA {
                    if !s.impacted, t >= 0.3, everyone(mem, { $0.fxFree && $0.turnedTo($0.yawTo(s.home0), tol: 0.2) }) { s.impacted = true }
                    else if s.impacted, everyone(mem, { $0.socialBook.hopStarted && $0.fxFree && $0.turnedTo($0.yawTo(s.home0), tol: 0.3) }), t > 1.0 {
                        s.laneYaw += dir * .pi / 2
                        s.impacted = false
                        s.round += 1; s.setPhase(s.round >= plan.count ? 3 : 2)
                        for m in mem { for x in mem where x !== m { m.onSocial?(.makeUp(partner: x.steerID)); break } }
                    } else if t > 12 { s.finish(.aborted) }
                }
            }
        default:   // let go: a joy hop each, one after another
            s.choreo = false
            if isA, s.fastMoves < 2 { s.fastMoves = 2; emoteHaptic("ringDance.scatter", EmoteHaptic.pulse) }
            if joyHop(s, mem, sim, key: 2290, stagger: 0.12), isA { endGroup(s, mem) }
            else if isA, s.phaseT > 6 { endGroup(s, mem) }
        }
    }
}
