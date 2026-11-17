//
//  BlobSocial+GroupCalm.swift
//  Seven CALM group emotes (2026-11-16, the owner: "Add more group emotes but not like jumping around and stuff"). Same shape as BlobSocial+Group.swift (one `SocialSession` for the
//  crew, every member drives only itself, the initiator keeps the clock), built ONLY from moves the Jelmiko already do: stand, sit, lie down, the wave, a sway overlay, turning to look,
//  a nod (the pitch overlay), the yawn, the chirp and singing voices, happy / excited / sleepy faces. No hop, no bounce, no run, no new body motion; nobody touches (a clear gap all through).
//    rowWave           3+  side by side in a row facing the camera: a wave passes along the row one by one, then back
//    singAlong         2+  a semicircle facing the camera, a shared sway, the singing voice (lala) one after another
//    storyTime         3+  one stands in the middle chirping with small gestures (look, nod, a little wave), the others sit facing it, nodding, happy at the end
//    lookAtThat        2+  one turns and looks up at something, the others turn the same way one after another, then excited faces
//    sitCircle         3+  a small circle, sitting facing in, a gentle sway
//    stargazeTogether  2+  EVENING / NIGHT, awake only: lie down side by side, starry eyes
//    yawnChain         2+  EVENING / NIGHT, awake only: one yawns, the others catch it one by one (the yawn move, a sleepy face)
//  Ending: the initiator moves the crew on (sitters and lie-downers get up with their normal get-up), then everybody is free. Any player action on a member (touch, command, meal, ...) ends it
//  through `socialTaken` / `abortAll` like the other groups; the sit / lie-down holds are a 0.6 s lease renewed every tick, so a cancelled session lets them stand up at once.
//  A night kind (or any calm kind) ends when a member reaches the deep night (`idleDeepNight`), so bedtime is never delayed.
//

import Foundation
import simd

enum CalmGroup {
    /// One line to switch a kind off (it is never picked, never starts).
    static let enabled: Set<SocialKind> = [.rowWave, .singAlong, .storyTime, .lookAtThat, .sitCircle, .stargazeTogether, .yawnChain]

    // ===================== CALM GROUP WEIGHTS (one block, for the merge) =====================
    /// Relative weights among the calm kinds. They are NOT absolute against `GroupTuning.weights`: at the roll the calm kinds that can start are scaled so that together they are
    /// `share` of the whole table, whatever the other weights are (hug 14 -> 5 changes nothing here). `yawnChain` is also times the night factor (zero by day).
    static let weights: [(SocialKind, Float)] = [(.rowWave, 1.0), (.singAlong, 1.2), (.storyTime, 0.9), (.lookAtThat, 1.0), (.sitCircle, 0.9), (.stargazeTogether, 1.0), (.yawnChain, 1.0)]
    /// The calm kinds together as a share of the group picks that can start (the owner wants the calm ones more than the jumpy ones).
    static let share: Float = 0.6
    // =========================================================================================

    /// Evening / night kinds start only when everybody is awake and it is not the deep night (bedtime): stargaze from the night factor 0.6, the yawn chain from 0.3.
    static func mayStart(_ k: SocialKind, _ crew: [BlobBrain]) -> Bool {
        guard enabled.contains(k) else { return false }
        switch k {
        case .stargazeTogether: return crew.allSatisfy { $0.idleNight > 0.6 && $0.idleDeepNight < 0.5 && $0.idleState.kind != .sleep }
        case .yawnChain: return crew.allSatisfy { $0.idleNight > 0.3 && $0.idleDeepNight < 0.5 && $0.idleState.kind != .sleep }
        default: return true
        }
    }

    /// Spacing (x peerGap) tried in turn for the planned places: a row, the arc / ring chord, the lying row.
    static let rowSpacing: [Float] = [1.3, 1.15, 1.0], ringChord: [Float] = [1.6, 1.4], lieSpacing: [Float] = [1.95, 1.7]
}

extension SocialKind {
    var isCalmGroup: Bool {
        switch self { case .rowWave, .singAlong, .storyTime, .lookAtThat, .sitCircle, .stargazeTogether, .yawnChain: return true; default: return false }
    }
    /// The fewest bodies (the initiator and the others) a group kind needs: 2 or 3. The roll in BlobSocial+Group.swift still wants 3 present; Main wires 2-body rolls from this at merge.
    var minBodies: Int {
        switch self { case .congaLine, .singAlong, .lookAtThat, .stargazeTogether, .yawnChain: return 2; default: return 3 }
    }
}

struct CalmPlan { var c: SIMD2<Float>; var spots: [Int: SIMD2<Float>]; var rank: [Int: Float] }

extension BlobBrain {
    // MARK: choosing

    /// Adds the calm kinds to the roll's table `w` (the roll in BlobSocial+Group.swift calls this once, after its own loop): the ones that can start now, scaled so together they are `CalmGroup.share` of the whole.
    func calmAppend(_ w: inout [(SocialKind, Float)], crew: [BlobBrain]) {
        let base = w.reduce(0) { $0 + $1.1 }
        let all = [self] + crew
        let night = max(idleNight, crew.map { $0.idleNight }.max() ?? 0)
        var cal: [(SocialKind, Float)] = []
        for (k, x) in CalmGroup.weights where all.count >= k.minBodies && CalmGroup.mayStart(k, all) {
            if k == socialBook.lastGroup || crew.contains(where: { $0.socialBook.lastGroup == k }) { continue }          // (no repeat of the last kind)
            cal.append((k, k == .yawnChain ? x * night : x))
        }
        let sum = cal.reduce(0) { $0 + $1.1 }
        guard sum > 0, base > 0 else { return }
        let scale = base * CalmGroup.share / (1 - CalmGroup.share) / sum
        for (k, x) in cal { w.append((k, x * scale)) }
    }

    // MARK: starting

    /// Plan the places for `kind` (the initiator first in `crew`) and open the session. nil = no room near.
    func calmStart(_ kind: SocialKind, crew: [BlobBrain]) -> SocialSession? {
        guard let plan = calmPlan(kind, crew) else { return nil }
        let dur: Float
        switch kind {
        case .rowWave: dur = 0
        case .singAlong: dur = vDur(8.5)
        case .storyTime: dur = vDur(8.6)
        case .lookAtThat: dur = 0
        case .sitCircle: dur = vDur(7.0)
        case .stargazeTogether: dur = vDur(5.5)
        default: dur = 0
        }
        let s = newGroupSession(kind, crew: crew, duration: dur)
        s.home0 = plan.c; s.slotSpot = plan.spots; s.slotAng = plan.rank
        s.roles = rand() < 0.5 ? 1 : -1          // (lookAtThat: which side the thing is on)
        return s
    }

    /// The places, left to right (x order) for the members, as offsets from an anchor. storyTime: slot 0 is the teller in the middle, the rest an arc behind him (away from the camera).
    private func calmOffsets(_ kind: SocialKind, n: Int, spacing sp: Float) -> [SIMD2<Float>] {
        switch kind {
        case .rowWave, .stargazeTogether:
            return (0..<n).map { SIMD2((Float($0) - Float(n - 1) / 2) * sp, 0) }
        case .singAlong, .lookAtThat, .yawnChain:          // a semicircle cupped toward the camera (+z): the ends are nearer to it
            let R = max(sp * 1.6, 1.9), d = 2 * asinf(min(1, sp / (2 * R)))
            return (0..<n).map { i in let a = (Float(i) - Float(n - 1) / 2) * d; return SIMD2(R * sinf(a), R - R * cosf(a)) }
        case .sitCircle:
            let r = max(sp / (2 * sinf(.pi / Float(n))), peerGap * 0.9)
            return (0..<n).map { i in let a = 2 * Float.pi * Float(i) / Float(n); return SIMD2(r * sinf(a), r * cosf(a)) }
        case .storyTime:
            let m = n - 1, R: Float = 1.8, d = 2 * asinf(min(1, sp / (2 * R)))
            return [SIMD2<Float>.zero] + (0..<m).map { i in let a = (Float(i) - Float(m - 1) / 2) * d; return SIMD2(R * sinf(a), -R * cosf(a)) }
        default: return []
        }
    }

    private func calmPlan(_ kind: SocialKind, _ members: [BlobBrain]) -> CalmPlan? {
        let n = members.count
        let cen = members.reduce(SIMD2<Float>.zero) { $0 + $1.position } / Float(n)
        let spacings: [Float] = (kind == .sitCircle ? CalmGroup.ringChord : (kind == .stargazeTogether ? CalmGroup.lieSpacing : CalmGroup.rowSpacing)).map { $0 * peerGap }
        let wasPass = socialBook.passThrough
        socialBook.passThrough = true          // (the floor rules only: the members' own bodies are not obstacles for their places)
        defer { socialBook.passThrough = wasPass }
        let anchors: [SIMD2<Float>] = [.zero] + (0..<8).flatMap { k -> [SIMD2<Float>] in
            let a = Float(k) * .pi / 4
            return [SIMD2(sinf(a), cosf(a)) * 0.5, SIMD2(sinf(a), cosf(a)) * 1.0]
        }
        for sp in spacings {
            let offs = calmOffsets(kind, n: n, spacing: sp)
            guard offs.count == n else { return nil }
            let ext = offs.map { simd_length($0) }.max() ?? 0
            // who takes which place: storyTime's teller is the member nearest the middle; the others (all, for the rest) go left to right in x
            var teller: BlobBrain?
            var rest = members
            if kind == .storyTime { teller = members.min { simd_distance($0.position, cen) < simd_distance($1.position, cen) }; rest = members.filter { $0 !== teller } }
            rest.sort { $0.position.x < $1.position.x }
            let slotOffs = kind == .storyTime ? Array(offs.dropFirst()).sorted { $0.x < $1.x } : offs.sorted { $0.x < $1.x }
            for an in anchors {
                let c = ParkClearSpot.clear(cen + an, radius: footprint + ext)
                var spots = [Int: SIMD2<Float>](), rank = [Int: Float](), ok = true
                func place(_ m: BlobBrain, _ off: SIMD2<Float>, _ r: Float) -> Bool {
                    let want = c + off
                    let p = fixed(want)
                    if simd_distance(p, want) > 0.12 || simd_distance(p, m.position) > GroupTuning.walkMax { return false }
                    if socialOthers().contains(where: { x in !members.contains { $0 === x } && simd_distance(x.position, p) < peerGap * 0.9 }) { return false }
                    spots[m.steerID] = p; rank[m.steerID] = r
                    return true
                }
                if let t = teller { ok = place(t, .zero, 0) }
                if ok { for (i, m) in rest.enumerated() { if !place(m, slotOffs[i], Float(i + (teller == nil ? 0 : 1))) { ok = false; break } } }
                if ok { return CalmPlan(c: c, spots: spots, rank: rank) }
            }
        }
        return nil
    }

    // MARK: driving

    var calmRank: Int { Int(social?.slotAng[steerID] ?? 0) }
    /// Where I face while I stand in my place.
    private func calmYaw(_ s: SocialSession) -> Float {
        switch s.kind {
        case .sitCircle: return yawTo(s.home0)
        case .storyTime: return calmRank == 0 ? yawTo(s.home0 + SIMD2(0, -1)) : yawTo(s.home0)
        default: return faceCameraYaw()
        }
    }
    private func calmSitting(_ s: SocialSession) -> Bool { s.kind == .storyTime ? calmRank != 0 : s.kind == .sitCircle }

    func driveCalm(_ s: SocialSession, _ mem: [BlobBrain], _ isA: Bool, _ sim: SoftBody) {
        // bedtime is never delayed: the deep night (or anybody gone to sleep) ends it at once, everybody gets up by himself
        if isA, mem.contains(where: { $0.idleDeepNight >= 0.5 || $0.idleState.kind == .sleep }) { s.finish(.aborted); return }
        if s.phase < 2 { calmGather(s, mem, isA, sim); return }
        let t = s.phaseT, g = socialGentle
        if s.phase == 2 { calmLease() }
        switch s.phase {
        case 2:
            switch s.kind {
            case .rowWave: calmRowWave(s, mem, isA, sim, t)
            case .singAlong: calmSing(s, mem, isA, t, g)
            case .storyTime: calmStory(s, mem, isA, sim, t)
            case .lookAtThat: calmLook(s, mem, isA, t)
            case .sitCircle: calmSitCircle(s, mem, isA, sim, t, g)
            case .stargazeTogether: calmStargaze(s, mem, isA, sim, t)
            case .yawnChain: calmYawnChain(s, mem, isA, sim, t)
            default: break
            }
        default: calmFinish(s, mem, isA)
        }
    }

    /// A sit / lie-down hold is a short lease the session renews every tick: a cancelled session lets him get up at once with the normal get-up.
    private func calmLease() {
        if idleState.kind == .sit || idleState.kind == .lieDown { idleState.hold = idleState.phaseT + 0.6 }
    }

    /// Phase 0: walk to my place; phase 1: turn to face the way this kind faces.
    private func calmGather(_ s: SocialSession, _ mem: [BlobBrain], _ isA: Bool, _ sim: SoftBody) {
        if s.phase == 0 {
            let spot = slot(s)
            if !socialBook.hopStarted, fxFree {
                socialBook.hopStarted = true
                letGo()
                if simd_distance(position, spot) > 0.12 { socialWalk(to: spot, sim) }
            }
            if socialBook.hopStarted, fxFree, simd_distance(position, spot) > 0.15, simd_distance(position, spot) < 1.4, !socialBook.hopStarted2 {
                socialBook.hopStarted2 = true          // (the walk stopped short of the place: the same small step-in the other groups use)
                startHopTo(sim, spot)
            }
            if fxFree { holdFacing(calmYaw(s)) }
            if isA {
                let arrived = everyone(mem) { $0.socialBook.hopStarted && $0.fxFree && simd_distance($0.position, $0.slot(s)) < 0.45 }
                if arrived, s.phaseT > 0.3 { s.setPhase(1) } else if s.phaseT > 16 { s.finish(.aborted) }
            }
            return
        }
        holdFacing(calmYaw(s))
        if isA, s.phaseT > 0.4, everyone(mem, { $0.turnedTo($0.calmYawNow(s), tol: 0.2) }) || s.phaseT > 3 { s.setPhase(2) }
    }
    fileprivate func calmYawNow(_ s: SocialSession) -> Float { calmYaw(s) }

    /// The end (phase 3): the sitters and lie-downers are let go (the normal get-up), a happy face, then the initiator ends the session when everybody is free again.
    private func calmFinish(_ s: SocialSession, _ mem: [BlobBrain], _ isA: Bool) {
        if idleState.kind == .sit || idleState.kind == .lieDown { idleState.hold = 0 }
        if fxFree { holdFacing(calmYaw(s)) }
        if !socialBook.apartStarted {
            socialBook.apartStarted = true
            let night = s.kind == .stargazeTogether || s.kind == .yawnChain
            if s.kind != .yawnChain { face(night ? .happy : .joyArc, hold: 1.4) }
            if myIndex < 2 && !night { AudioHub.shared.chirp(jelly: steerID, myIndex == 0 ? .happy : .babble) }
        }
        if isA {
            if everyone(mem, { $0.fxFree }), s.phaseT > 0.8 { endGroup(s, mem) }
            else if s.phaseT > 7 { endGroup(s, mem) }
        }
    }

    /// Start a sit (the normal one) with a lease hold and the given facing. False = it did not start.
    private func calmSit(_ sim: SoftBody, facing: Float) -> Bool {
        socialBook.hold = false; socialBook.faceYaw = nil
        guard idleStart(.sit, sim) else { return false }
        idleState.hold = 0.6; idleState.goalYaw = facing
        return true
    }

    private func calmWave(_ sim: SoftBody, outward: SIMD2<Float>) {
        currentPose(sim)
        let local = rotXZ(outward, -yaw)
        armSide = local.x >= 0 ? 1 : -1
        scriptT = 0
        socialBook.hold = false; socialBook.faceYaw = nil
        script = .wave(t: 0, side: armSide, then: .none); activity = .waving
    }

    // MARK: rowWave

    private func calmRowWave(_ s: SocialSession, _ mem: [BlobBrain], _ isA: Bool, _ sim: SoftBody, _ t: Float) {
        let n = mem.count, r = calmRank
        let order = Array(0..<n) + (n >= 2 ? Array((0..<(n - 1)).reversed()) : [])          // (along the row and back)
        let t0: Float = 0.5, step: Float = 1.05
        let mine = order.indices.filter { order[$0] == r }
        let done = s.calmCue[steerID] ?? 0
        if done < mine.count, t >= t0 + Float(mine[done]) * step, fxFree {
            s.calmCue[steerID] = done + 1
            calmWave(sim, outward: SIMD2(r * 2 < n - 1 ? -1 : 1, 0))
            AudioHub.shared.chirp(jelly: steerID, r % 2 == 0 ? .happy : .babble)
            face(.happy, hold: 2.2)
        } else if fxFree { holdFacing(faceCameraYaw()) }
        if isA, t > t0 + Float(order.count - 1) * step + WaveScript.duration + 0.3, everyone(mem, { $0.fxFree }) { s.setPhase(3) }
        else if isA, t > 20 { s.setPhase(3) }
    }

    // MARK: singAlong

    private func calmSing(_ s: SocialSession, _ mem: [BlobBrain], _ isA: Bool, _ t: Float, _ g: Float) {
        if fxFree { holdFacing(faceCameraYaw()) }
        let fade = 1 - smooth01((t - (s.duration - 0.9)) / 0.9)
        let sway = sinf(2 * .pi * (t - 0.4) / 2.6) * smooth01((t - 0.4) / 0.8) * fade
        socialBook.wantRoll = worldLean(1) * 0.07 * sway * g          // (everybody leans the same way in the world: one soft row)
        let r = calmRank
        let done = s.calmCue[steerID] ?? 0
        let start = 1.0 + Float(r) * 0.7 + Float(done) * 3.4          // (the voices come one after another; a second round after the 3 s gate of the voice)
        if done < 2, t >= start {
            s.calmCue[steerID] = done + 1
            AudioHub.shared.sing(jelly: steerID, x: px)
            face(.happy, hold: 2.6)
        }
        if isA, t > s.duration { s.setPhase(3) }
    }

    // MARK: sitCircle

    private func calmSitCircle(_ s: SocialSession, _ mem: [BlobBrain], _ isA: Bool, _ sim: SoftBody, _ t: Float, _ g: Float) {
        if (s.calmCue[steerID] ?? 0) == 0 {
            s.calmCue[steerID] = 1
            if !calmSit(sim, facing: yawTo(s.home0)) { s.finish(.aborted); return }
        }
        if idleState.kind == .sit {
            let sway = sinf(2 * .pi * (t - 1.8) / 3.0) * smooth01((t - 1.8) / 1.0) * (1 - smooth01((t - (s.duration - 0.8)) / 0.8))
            socialBook.wantRoll = worldLean(1) * 0.06 * sway * g
        }
        if (s.calmCue[steerID] ?? 0) == 1, t > s.duration - 1.3 { s.calmCue[steerID] = 2; face(.happy, hold: 1.6) }
        if isA, t > s.duration { s.setPhase(3) }
        else if isA, t > 20 { s.setPhase(3) }
    }

    // MARK: storyTime

    private func calmStory(_ s: SocialSession, _ mem: [BlobBrain], _ isA: Bool, _ sim: SoftBody, _ t: Float) {
        let g = socialGentle
        let cue = s.calmCue[steerID] ?? 0
        if calmRank != 0 {          // a listener: sits facing the teller, nods now and then, happy at the end
            if cue == 0 {
                s.calmCue[steerID] = 1
                if !calmSit(sim, facing: yawTo(s.home0)) { s.finish(.aborted); return }
            }
            let r = Float(calmRank)
            var nod: Float = 0
            for k in 0..<3 { nod += pulse(t - (2.6 + 1.6 * Float(k) + 0.3 * r), up: 0.3, down: 0.45) }
            socialBook.wantPitch = 0.07 * min(1, nod) * g
            if cue == 1, t > s.duration - 1.0 { s.calmCue[steerID] = 2; face(.joyArc, hold: 1.4); if calmRank == 1 { AudioHub.shared.chirp(jelly: steerID, .happy) } }
            else if cue == 1, t > 3.4, !socialBook.sheepishStarted { socialBook.sheepishStarted = true; face(.curious, hold: 1.0) }
        } else {          // the teller: chirps, a nod, a look to the side, a little wave at the camera, back to the listeners
            let toward = yawTo(s.home0 + SIMD2(0, -1)), cam = faceCameraYaw()
            let side = toward + 0.7
            var want: Float = toward
            if t > 2.6, t < 3.5 { want = side }
            if t > 4.6, t < 7.9 { want = cam }
            if fxFree { holdFacing(want) }
            var nod: Float = 0
            for tk: Float in [2.0, 4.0] { nod += pulse(t - tk, up: 0.25, down: 0.4) }
            socialBook.wantPitch = 0.07 * min(1, nod) * g
            for (k, tc) in [1.6, 3.8, 6.2, 7.8].enumerated() where cue == k && t >= Float(tc) {
                s.calmCue[steerID] = k + 1
                AudioHub.shared.chirp(jelly: steerID, k % 2 == 0 ? .babble : .happy)
                if k == 1 { face(.happy, hold: 1.2) }
            }
            if t >= 5.4, !socialBook.glanceDone, fxFree, turnedTo(cam, tol: 0.25) {          // the little wave, at the camera
                socialBook.glanceDone = true
                calmWave(sim, outward: SIMD2(1, 0))
            }
        }
        if isA, t > s.duration { s.setPhase(3) }
        else if isA, t > 20 { s.setPhase(3) }
    }

    // MARK: lookAtThat

    private func calmLook(_ s: SocialSession, _ mem: [BlobBrain], _ isA: Bool, _ t: Float) {
        let g = socialGentle, i = Float(myIndex)
        let start = 0.4 + 0.9 * i, all = 0.4 + 0.9 * Float(mem.count - 1) + 0.8
        let aim = faceCameraYaw() + Float(s.roles) * 1.05
        let upT = (t - start - 0.3) / 0.6
        var up = smooth01(upT) * (1 - smooth01((t - (all + 2.4)) / 0.6))
        if t < start { up = 0 }
        if fxFree {
            if t >= start, t < all + 2.4 { holdFacing(aim) } else { holdFacing(faceCameraYaw()) }
        }
        socialBook.wantPitch = -0.12 * up * g          // (the head back: looking up, as the stargazing does)
        if (s.calmCue[steerID] ?? 0) == 0, t >= start { s.calmCue[steerID] = 1; face(i == 0 ? .curious : .surprised, hold: 1.2) }
        if (s.calmCue[steerID] ?? 0) == 1, t >= all + 0.5 + 0.18 * i {          // everybody is looking: excited faces, a little voice each
            s.calmCue[steerID] = 2
            face(.excited, hold: 1.6)
            if myIndex < 3 { AudioHub.shared.chirp(jelly: steerID, myIndex % 2 == 0 ? .happy : .babble) }
        }
        if isA, t > all + 3.2 { s.setPhase(3) }
        else if isA, t > 20 { s.setPhase(3) }
    }

    // MARK: stargazeTogether

    private func calmStargaze(_ s: SocialSession, _ mem: [BlobBrain], _ isA: Bool, _ sim: SoftBody, _ t: Float) {
        let cue = s.calmCue[steerID] ?? 0
        if cue == 0, t >= 0.25 * Float(calmRank), fxFree {
            s.calmCue[steerID] = 1
            socialBook.hold = false; socialBook.faceYaw = nil
            if idleStart(.lieDown, sim) { idleState.hold = 0.6 } else { s.finish(.aborted); return }
        }
        if cue == 1, idleState.kind == .lieDown, idleState.phase == 2 { s.calmCue[steerID] = 2; face(.starry, hold: 5) }
        if isA {
            if s.round == 0 {
                if everyone(mem, { $0.idleState.kind == .lieDown && $0.idleState.phase == 2 }) { s.round = 1; s.leaderWait = t }
                else if t > 12 { s.setPhase(3) }
            } else {
                if t - s.leaderWait > s.duration { s.setPhase(3) }
            }
        }
    }

    // MARK: yawnChain

    private func calmYawnChain(_ s: SocialSession, _ mem: [BlobBrain], _ isA: Bool, _ sim: SoftBody, _ t: Float) {
        let cue = s.calmCue[steerID] ?? 0
        let start = 0.6 + 1.5 * Float(myIndex)
        if cue == 0, t >= start, fxFree {
            s.calmCue[steerID] = 1
            socialBook.hold = false; socialBook.faceYaw = nil
            if idleStart(.yawn, sim) { face(.sleepy, hold: 3.4) } else { s.calmCue[steerID] = 2 }
        } else if fxFree { holdFacing(faceCameraYaw()) }
        if cue == 1, fxFree { s.calmCue[steerID] = 2 }          // (the yawn is over)
        if isA {
            if everyone(mem, { ($0.social?.calmCue[$0.steerID] ?? 0) == 2 && $0.fxFree }), t > 0.6 + 1.5 * Float(mem.count - 1) { s.setPhase(3) }
            else if t > 20 { s.setPhase(3) }
        }
    }
}
