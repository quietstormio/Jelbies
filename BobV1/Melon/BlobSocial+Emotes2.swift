//
//  BlobSocial+Emotes2.swift
//  spinHug (batch 2, 2026-11-02, g-emotes3): two Jelbies meet (the social walk-up), stand side by side at about contact distance (`gap` x the room gap; the close-social floor keeps the roots >= 0.74 gap
//  apart, so the bodies touch and never sit inside each other), lean their cheeks together (a squish, the boop and a heart), then turn ONCE round their shared centre: a small ring (radius ~0.65 u,
//  re-planned from where they stand), each Jelbie walks his own half by pure pursuit with the locked walk (real steps, the two face opposite ways like a slow swing, leaning toward each other), the
//  crew choreographed so the steering does not push them apart. Then they part with a joy squash and hearts. Arms stay stubby (nothing is raised), feet attached (the walk's own).
//

import Foundation
import simd

enum SpinHugTuning {
    static let gap: Float = 0.84, radius: ClosedRange<Float> = 0.68...0.80, legs = 8
    static let swayMargin: Float = 0.20
}

extension BlobBrain {
    func socialStartSpinHug(with o: BlobBrain, _ sim: SoftBody) -> Bool {
        let d = simd_distance(position, o.position)
        guard d > 0.5, d < 5.5, fastOthers(except: [o]) == 0, let spot = sideSpot(of: o, gap: peerGap * SpinHugTuning.gap) else { return false }
        let s = newSession(.spinHug, with: o, duration: 0)
        s.crew = [CrewBox(b: self), CrewBox(b: o)]
        s.goal = spot; s.roles = rand() < 0.5 ? 0 : 1
        o.socialBook.hold = true; o.socialBook.faceYaw = o.faceCameraYaw()
        if simd_distance(position, spot) > 0.12 { socialWalk(to: spot, sim) } else { s.setPhase(1) }
        return true
    }

    /// Plans the circle on where the two stand NOW: the centre is the midpoint, the radius half their distance (kept within `radius`), A's angle is where A is (`s.goal` = (radius, A's angle), `s.home0` = the centre).
    /// False = the circle is not on the floor (the walls / furniture), so there is no spin.
    private func spinPlan(_ s: SocialSession, _ o: BlobBrain) -> Bool {
        s.home0 = (position + o.position) / 2
        let half = ringTouch(o) / 2          // (the ring's diameter is never under the widest touch of the pair)
        let r = half + SpinHugTuning.swayMargin          // (+ the sway: walking, each body's root swings +-12 cm round its path with the steps; measured gap 21 / -21 cm on a ring of half + 0.10)
        s.goal = SIMD2(r, atan2f(position.x - s.home0.x, position.y - s.home0.y))
        let was = socialBook.passThrough
        socialBook.passThrough = true          // (the floor rules only: the partner's own body is not an obstacle for the plan, he moves along the other half)
        defer { socialBook.passThrough = was }
        let strangers = socialOthers().filter { $0 !== self && $0 !== o }.map(\.position)
        return (0..<12).allSatisfy { k in
            let a = s.goal.y + Float(k) * .pi / 6
            let p = s.home0 + SIMD2(sinf(a), cosf(a)) * s.goal.x
            return simd_distance(closeFixed(p), p) < 0.08 && !strangers.contains { simd_distance($0, p) < peerGap * 1.05 }          // (the ring is on the floor and nobody else stands near it)
        }
    }
    /// The angle (about the circle's centre) of a brain now.
    private func spinAngle(_ s: SocialSession, _ b: BlobBrain) -> Float { atan2f(b.position.x - s.home0.x, b.position.y - s.home0.y) }
    /// The point `lookahead` rad further round the circle than brain `b` is now (pure pursuit on the circle: the walkers' paths stay on the ring, never cut across the middle).
    private func spinCarrot(_ s: SocialSession, _ b: BlobBrain, lookahead: Float = 1.0) -> SIMD2<Float> {
        let dir: Float = s.roles == 0 ? 1 : -1
        let a = spinAngle(s, b) + dir * lookahead
        return s.home0 + SIMD2(sinf(a), cosf(a)) * s.goal.x
    }

    func driveSpinHug(_ s: SocialSession, _ o: BlobBrain, _ isA: Bool, _ sim: SoftBody, _ dt: Float) {
        if openSideBySide(s, o, isA, settle: 0.6) { return }
        let g = socialGentle
        let t = s.phaseT
        let lean = leanSign(toward: o.position)
        switch s.phase {
        case 2:    // the cheeks press
            holdFacing(faceCameraYaw())
            let k = smooth01(t / 0.7)
            socialBook.wantRoll = lean * 0.09 * k * g
            socialBook.wantEyes = 1 - 0.55 * k
            socialBook.wantSquash = 1 - 0.03 * k
            if isA {
                if !s.impacted, t > 0.7 {
                    s.impacted = true
                    jellyKick = max(jellyKick, impactKick(1.8)); o.jellyKick = max(o.jellyKick, impactKick(1.8))
                    contactBoopFallback(o)
                    contactCueFallback(o, .emoteSpinHug, 1, haptic: .treat("spinHug.press"))
                    face(.joyArc, hold: 1.2); o.face(.joyArc, hold: 1.2)
                }
                if s.impacted, t > 1.2 {
                    let ok = spinPlan(s, o)
                    s.choreo = ok
                    s.setPhase(ok ? 5 : 4)
                } else if t > 9 { s.finish(.aborted) }
            }
        case 5:    // each squares up to his first leg while the cheeks stay together (they face opposite ways, like a slow swing), so every leg turns the same amount for both and they stay in step
            let me = isA ? 0 : 1
            holdFacing(yawTo(spinCarrot(s, self)))
            socialBook.wantRoll = lean * 0.09 * g
            socialBook.wantEyes = 0.5
            if isA {
                if t > 0.4, turnedTo(yawTo(spinCarrot(s, self)), tol: 0.25), o.turnedTo(o.yawTo(spinCarrot(s, o)), tol: 0.25) { s.setPhase(spinPlan(s, o) ? 3 : 4); s.slotAng = [:]; s.slotSpot = [:] }
                else if t > 5 { s.setPhase(spinPlan(s, o) ? 3 : 4); s.slotAng = [:]; s.slotSpot = [:] }
            }
        case 3:    // the turn: pure pursuit round the ring, each walks his own half with the locked walk; the one who gets ahead waits a beat for the other
            let dir: Float = s.roles == 0 ? 1 : -1
            let ang = spinAngle(s, self)
            let prev = s.slotSpot[steerID]?.x ?? ang
            s.slotAng[steerID, default: 0] += wrapAngle(ang - prev) * dir
            s.slotSpot[steerID] = SIMD2(ang, 0)
            let mine = s.slotAng[steerID] ?? 0, theirs = s.slotAng[o.steerID] ?? 0
            let around: Float = 2 * .pi - 0.25
            socialBook.wantRoll = lean * 0.06 * g
            socialBook.wantEyes = 0.5
            socialBook.wantSquash = 1 - 0.015 * g
            if mine >= around {
                if !socialBook.apartStarted {          // once round: walk the last bit to the starting point and stand
                    socialBook.apartStarted = true
                    let a0 = s.goal.y + (isA ? 0 : .pi)
                    socialWalk(to: s.home0 + SIMD2(sinf(a0), cosf(a0)) * s.goal.x, sim)
                }
            } else if !feet.active {
                let ahead = mine - theirs > 0.4
                if ahead { if case .walk = script { socialWalk(to: position, sim) } }          // (wait: a walk to where he stands is over at once)
                else { socialWalk(to: spinCarrot(s, self), sim) }
            }
            if isA {
                if t > 1.0, s.slotAng[steerID, default: 0] >= around, s.slotAng[o.steerID, default: 0] >= around, fxFree, o.fxFree { s.setPhase(4) }
                else if t > 22 { s.setPhase(4) }
                let beat = Int(t / 2.5)
                if beat != s.passes, t > 1 { s.passes = beat; treatHaptic("spinHug.step"); jellyKick = max(jellyKick, impactKick(0.5)); o.jellyKick = max(o.jellyKick, impactKick(0.5)) }
            }
        default:   // part: a joy squash, hearts
            s.choreo = false
            if t < 0.05 { startParting(from: o) }          // (the turn to the camera backs off first: BlobSocial+Part.swift)
            holdFacing(faceCameraYaw())
            socialBook.wantRoll = lean * 0.09 * g * (1 - smooth01(t / 0.35))
            socialBook.wantEyes = 1
            if isA, s.bumps == 0, t > 0.1 {
                s.bumps = 1
                jellyKick = max(jellyKick, 1.8); o.jellyKick = max(o.jellyKick, 1.8)
                AudioHub.shared.chirp(jelly: steerID, .happy); AudioHub.shared.chirp(jelly: o.steerID, .babble)
                treatHaptic("spinHug.part")
            }
            if isA, t > 0.9, fxFree, o.fxFree { finishHappy(s, o) }
        }
    }
}

extension SocialKind {
    /// The warm ones: a session of these that ends well gives each of them a small heart (the stage rate-limits it). Not the looks, the follow, the dashes, the tricks (sneak, keep-away) or the squabble.
    var isWarm: Bool {
        switch self {
        case .boop, .greet, .bump, .nuzzle, .sitTogether, .dance, .line, .pass, .bagSit, .cuddle, .chase: return true
        default: return isFriendly
        }
    }
}
