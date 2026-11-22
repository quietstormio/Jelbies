//
//  BlobSocial+Pair2.swift
//  Four new pair emotes (pair-distinct-r1, 2026-11-20), each with a silhouette no other pair kind has, none with body-on-body contact (a clear gap the whole time) and none face to face with the faces close:
//    orbit         one walks a circle (a 240-degree arc) round the other, who turns in place to keep facing him; both end with a polite bow from a step apart
//    upDown        side on to the camera, face to face with a clear gap: one squats low while the other stretches tall, alternating four times in rhythm
//    jumpTurns     side by side at a line: they take turns doing a long hop forward (toward the camera), each a bit longer, the other watches and bounces a cheer; the last ends in a happy wobble
//    spinTogether  both spin in step (twirl's spin), stop on the same beat and finish back to back (a clear gap) with both arms up for a moment
//  Sounds: the existing chirps (happy / babble), `wobble` / `jump` clips and the squish-free hearts (finishHappy); the haptic is the kind's `socialSpec` cue. The pick weights are in `FriendTuning.newPair` (one table).
//

import Foundation
import simd

extension SocialKind {
    /// The four new pair kinds of this file.
    static let newPair: [SocialKind] = [.orbit, .upDown, .jumpTurns, .spinTogether]
    var isNewPair: Bool { SocialKind.newPair.contains(self) }
}

extension BlobBrain {
    /// The heading a side-by-side pair hops along: toward the camera from the pair's middle, the same for both (parallel hops keep the gap).
    func pairHopYaw(_ o: BlobBrain) -> Float { atan2f(cameraPosXZ.x - (px + o.px) / 2, cameraPosXZ.y - (pz + o.pz) / 2) }

    // MARK: starting

    func socialStartPair2(_ kind: SocialKind, with o: BlobBrain, _ sim: SoftBody) -> Bool {
        let me = position, you = o.position
        let d = simd_distance(me, you)
        if kind.isFast, fastOthers(except: [o]) > 0 { return false }
        switch kind {
        case .upDown:
            // along the floor's x axis (profile to the camera), a clear space between: the walker comes round to o's side
            guard d > 0.5, d < 5.5, let spot = sideSpot(of: o, gap: peerGap * 1.25) else { return false }
            let s = newSession(kind, with: o, duration: 0)
            s.goal = spot
            o.socialBook.hold = true; o.socialBook.faceYaw = o.yawTo(spot)
            if simd_distance(me, spot) > 0.12 { socialWalk(to: spot, sim) } else { s.setPhase(1) }
        case .jumpTurns, .spinTogether:
            guard d > 0.5, d < 5.5, let spot = sideSpot(of: o, gap: peerGap * (kind == .spinTogether ? 1.3 : 1.1)) else { return false }
            let s = newSession(kind, with: o, duration: 0)
            s.goal = spot
            o.socialBook.hold = true; o.socialBook.faceYaw = o.faceCameraYaw()
            if simd_distance(me, spot) > 0.12 { socialWalk(to: spot, sim) } else { s.setPhase(1) }
        case .orbit:
            // the ring: R round the partner, from where the walker is; the whole 240-degree arc must fit on the floor, either way round
            guard d > 1.0, d < 5.5 else { return false }
            let a0 = atan2f(me.x - you.x, me.y - you.y)
            func fits(_ dir: Float) -> Bool {
                for k in 0...Pair2Tuning.orbitLegs {
                    let a = a0 + dir * Pair2Tuning.orbitStep * Float(k)
                    let want = you + Pair2Tuning.orbitR * SIMD2(sinf(a), cosf(a))
                    if simd_distance(fixed(want), want) > 0.25 { return false }
                }
                return true
            }
            let first: Float = rand() < 0.5 ? 1 : -1
            let chosen: Float? = fits(first) ? first : (fits(-first) ? -first : nil)
            guard let dir = chosen else { return false }
            let s = newSession(kind, with: o, duration: 0)
            s.laneYaw = a0; s.roles = dir > 0 ? 0 : 1
            let p0 = you + Pair2Tuning.orbitR * SIMD2(sinf(a0), cosf(a0))
            s.goal = p0
            o.socialBook.hold = true; o.socialBook.faceYaw = o.yawTo(me)
            if simd_distance(me, p0) > 0.12 { socialWalk(to: p0, sim) } else { s.setPhase(1) }
        default: return false
        }
        return true
    }

    // MARK: driving

    func driveSocialPair2(_ s: SocialSession, _ o: BlobBrain, _ isA: Bool, _ sim: SoftBody) {
        switch s.kind {
        case .orbit: driveOrbit(s, o, isA, sim)
        case .upDown: driveUpDown(s, o, isA)
        case .jumpTurns: driveJumpTurns(s, o, isA, sim)
        case .spinTogether: driveSpinTogether(s, o, isA, sim)
        default: break
        }
    }

    // MARK: orbit

    private func driveOrbit(_ s: SocialSession, _ o: BlobBrain, _ isA: Bool, _ sim: SoftBody) {
        let center = isA ? o.position : position
        switch s.phase {
        case 0:
            if !isA { faceEach(o); return }
            if s.t > 14 { s.finish(.aborted); return }
            if scriptIsNone, s.phaseT > 0.3 { s.setPhase(1); AudioHub.shared.chirp(jelly: steerID, .happy) }
        case 1:
            if !isA { faceEach(o); return }          // (the one in the middle turns in place after him, all the way round)
            if s.t > 40 { s.finish(.aborted); return }
            if scriptIsNone, !feet.active {
                if s.bumps >= Pair2Tuning.orbitLegs { s.setPhase(2); return }
                s.bumps += 1
                let dir: Float = s.roles == 0 ? 1 : -1
                let a = s.laneYaw + dir * Pair2Tuning.orbitStep * Float(s.bumps)
                let want = center + Pair2Tuning.orbitR * SIMD2(sinf(a), cosf(a))
                socialBook.hold = false; socialBook.faceYaw = nil
                socialWalk(to: fixed(want), sim)
            }
        default:    // the bow, a step apart
            faceEach(o)
            let t = s.phaseT
            let bow = pulse(t - 0.7, up: 0.45, down: 0.55)
            socialBook.wantPitch = 0.30 * bow * socialGentle
            socialBook.wantEyes = 1 - 0.5 * bow
            if isA {
                if !s.impacted, t > 0.7 { s.impacted = true; AudioHub.shared.chirp(jelly: steerID, .babble); AudioHub.shared.chirp(jelly: o.steerID, .happy) }
                if t > 2.1, scriptIsNone, o.scriptIsNone { finishHappy(s, o) } else if t > 6 { s.finish(.done) }
            }
        }
    }

    // MARK: up down

    private func driveUpDown(_ s: SocialSession, _ o: BlobBrain, _ isA: Bool) {
        if openFaceToFace(s, o, isA, settle: 0.5) { return }
        faceEach(o)
        let t = s.phaseT
        let period = Pair2Tuning.upDownPeriod, cycles = Pair2Tuning.upDownCycles
        let on = smooth01(t / 0.3) * (1 - smooth01((t - (period * Float(cycles) - 0.2)) / 0.3))
        let sw = sinf(2 * .pi * t / period) * on
        let mine = isA ? sw : -sw          // (+: squat, -: stretch tall)
        socialBook.wantSquash = mine > 0 ? 1 - 0.20 * smooth01(mine) : 1 + 0.13 * smooth01(-mine)
        socialBook.wantEyes = 1 - 0.3 * smooth01(max(0, mine))
        if isA {
            let beat = Int(t / (period / 2))
            if beat > s.bumps, t < period * Float(cycles) {
                s.bumps = beat
                jellyKick = max(jellyKick, 0.7); o.jellyKick = max(o.jellyKick, 0.7)
                AudioHub.shared.chirp(jelly: beat % 2 == 0 ? steerID : o.steerID, .happy)
            }
            if t > period * Float(cycles) + 0.4 { finishHappy(s, o) }
        }
    }

    // MARK: jump turns

    private func driveJumpTurns(_ s: SocialSession, _ o: BlobBrain, _ isA: Bool, _ sim: SoftBody) {
        if openSideBySide(s, o, isA, settle: 0.6) { return }
        let t = s.phaseT
        if Pair2Tuning.armsIn { socialBook.handWant = HandReach.armsIn(side: handSide(toward: o)) }          // (the arms stay in during the hops)
        switch s.phase {
        case 2:
            let k = s.round
            stepKey(2000 + k)
            let jumper = ((k % 2 == 0) == isA) ? self : o
            let dist = Pair2Tuning.jumpBase + Pair2Tuning.jumpStep * Float(k)
            if jumper === self {
                if !socialBook.hopStarted, fxFree, t >= 0.4, turnedTo(pairHopYaw(o), tol: 0.25) || t > 2.0 {
                    yaw = pairHopYaw(o)          // (exactly along the shared heading: see hopAlong)
                    socialBook.hopStarted = true
                    socialBook.hold = false; socialBook.faceYaw = nil
                    startHopPlay(sim: sim, distance: dist)
                    face(.joyArc, hold: 0.9)
                    AudioHub.shared.play(.jump, jelly: steerID, x: px, volume: 0.7)
                } else if fxFree { holdFacing(pairHopYaw(o)) }
            } else {
                holdFacing(pairHopYaw(o))
                // the watcher cheers when the jumper lands: a small bounce and a chirp
                if jumper.socialBook.hopStarted, jumper.fxFree, !socialBook.apartStarted {
                    socialBook.apartStarted = true; s.bumpT = t
                    jellyKick = max(jellyKick, 0.8)
                    AudioHub.shared.chirp(jelly: steerID, .babble)
                }
                if socialBook.apartStarted { socialBook.wantSquash = 1 - 0.07 * pulse(t - s.bumpT, up: 0.12, down: 0.3) }
            }
            if isA, jumper.socialBook.hopStarted, jumper.fxFree, fxFree || o.fxFree, t > 1.5 {
                s.round += 1
                s.setPhase(s.round >= Pair2Tuning.jumpCount ? 3 : 2)
            } else if isA, t > 9 { s.finish(.aborted) }
        default:    // the happy wobble (both), then done
            stepKey(2100)
            if fxFree { holdFacing(faceCameraYaw()) }
            let w = smooth01(t / 0.2) * (1 - smooth01((t - 1.4) / 0.4))
            socialBook.wantRoll = 0          // (no roll wobble: it slid the planted soles 21 - 24 mm; the happy wobble is the squash pulses and the kicks)
            socialBook.wantSquash = 1 - 0.03 * w * abs(sinf(2 * .pi * 2.25 * t))
            if isA {
                if !s.impacted, t > 0.1 { s.impacted = true; jellyKick = max(jellyKick, 1.2); o.jellyKick = max(o.jellyKick, 1.2); AudioHub.shared.chirp(jelly: steerID, .happy); AudioHub.shared.chirp(jelly: o.steerID, .happy) }
                if t > 1.9, scriptIsNone, o.scriptIsNone { finishHappy(s, o) } else if t > 6 { s.finish(.done) }
            }
        }
    }

    // MARK: spin together

    private func driveSpinTogether(_ s: SocialSession, _ o: BlobBrain, _ isA: Bool, _ sim: SoftBody) {
        if openSideBySide(s, o, isA, settle: 0.6) { return }
        let t = s.phaseT
        switch s.phase {
        case 2:    // both spin on the same beat, twice
            stepKey(2200 + s.round)
            if !socialBook.hopStarted, fxFree, t > 0.25 {
                socialBook.hopStarted = true; socialBook.hold = false; socialBook.faceYaw = nil
                startSpin(sim: sim)
                AudioHub.shared.play(.wobble, jelly: steerID, x: px, volume: 0.5)
            } else if fxFree { holdFacing(faceCameraYaw()) }
            if isA {
                if socialBook.hopStarted, o.socialBook.hopStarted, fxFree, o.fxFree, t > 0.8 {
                    s.round += 1
                    s.setPhase(s.round >= 2 ? 3 : 2)
                } else if t > 8 { s.finish(.aborted) }
            }
        case 3:    // stop on the same beat and turn away from each other: back to back
            stepKey(2300)
            let away = yawTo(position - simd_normalize(o.position - position + SIMD2(1e-6, 0)))
            if fxFree { holdFacing(away) }
            if isA {
                if t > 0.5, turnedTo(away, tol: 0.2), o.turnedTo(o.yawTo(o.position - simd_normalize(position - o.position + SIMD2(1e-6, 0))), tol: 0.2) { s.setPhase(4) }
                else if t > 4 { s.setPhase(4) }
            }
        default:    // arms up, a cheer
            stepKey(2400)
            let away = yawTo(position - simd_normalize(o.position - position + SIMD2(1e-6, 0)))
            if fxFree { holdFacing(away) }
            let up = smooth01(t / 0.35) * (1 - smooth01((t - 1.5) / 0.3))
            if up > 0.01 { socialBook.handWant = HandReach.armsUp(side: handSide(toward: o)) }
            socialBook.wantSquash = 1 + 0.05 * up
            if isA {
                if !s.impacted, t > 0.35 { s.impacted = true; jellyKick = max(jellyKick, 1.2); o.jellyKick = max(o.jellyKick, 1.2); AudioHub.shared.chirp(jelly: steerID, .happy); AudioHub.shared.chirp(jelly: o.steerID, .happy) }
                if t > 2.1, scriptIsNone, o.scriptIsNone { finishHappy(s, o) } else if t > 6 { s.finish(.done) }
            }
        }
    }
}

enum Pair2Tuning {
    static let orbitR: Float = 1.65, orbitStep: Float = 0.70, orbitLegs = 6          // (6 legs of 40 degrees = 240 degrees; the chord of a leg stays >= 1.55 from the middle)
    static let upDownPeriod: Float = 1.1, upDownCycles = 4
    nonisolated(unsafe) static var jumpBase: Float = 0.35
    static let jumpStep: Float = 0.2, jumpCount = 4
    /// hopAlong / jumpTurns: the hop distance, and whether the arms are held in during the hops (test seams of the sweep: PairSweepTests).
    nonisolated(unsafe) static var hopDist: Float = 0.45
    nonisolated(unsafe) static var armsIn = false
}
