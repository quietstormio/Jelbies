//
//  BlobBrain+Antics.swift
//  Solo antics (user 2026-10-19: "they need to do more random stuff while I'm watching"), all built from the existing moves and poses (no new gait):
//    tail     spin in place 1...3 turns (the existing spin script) and a dizzy wobble
//    flop     plops down flat (squash + a lean over) and wobbles back up (the sit / wave postures)
//    window   turns to the back wall and looks out of the nearest window (the LOOK posture)
//    peek     walks to the end of the sofa, ducks, and peeks out (a walk, then the duck / lean postures)
//    stretch  the yawn's stretch without the yawn
//    bounce   3...5 happy hops on the spot (the scoot's hop machinery, no travel)
//    roll     the existing roll a short way sideways
//    sway     sits and sways to the music (the sit)
//  plus the pacing: per-behaviour cooldowns and the cap of two Jellies in fast moves at once.
//

import Foundation
import simd

extension BlobBrain {
    /// Behaviours that move him fast (or off the floor). At most two Jellies do one at a time.
    static let fastKinds: Set<IdleKind> = [.run, .stumble, .zoomies, .slide, .scoot, .jacks, .bounce, .tail, .roll, .decorKick, .decorHop, .flapHop]
    /// How long a behaviour stays out of the pick after it ran.
    static func kindCooldown(_ k: IdleKind) -> Float {
        switch k {
        case .jacks, .zoomies, .slide, .tail, .roll, .flop, .peek: return 30
        case .sit, .look, .wander: return 8
        case .decorSit, .decorBoop, .decorKick, .decorHop, .decorPeek, .decorSlide, .decorThrow: return 25
        case .sleep: return 0
        default: return 20
        }
    }

    func kindCooldownStart(_ k: IdleKind) {
        if k == .flapHop { kindCool[k] = rand(Self.flapHopUrge.lowerBound, Self.flapHopUrge.upperBound); return }
        let c = Self.kindCooldown(k); if c > 0 { kindCool[k] = c }
    }
    /// Kinds that may not be picked now: on their own cooldown, or what the others are doing this moment (two Jellies do not do the same thing at once).
    var kindCooling: Set<IdleKind> {
        var s = Set(kindCool.keys)
        for o in socialOthers() {
            guard let k = o.idleState.kind, k != .wander, k != .look, k != .sleep else { continue }
            // (a second seat of the same sofa / swing / table is a friend joining in, not a repeat)
            if k == .decorSit, o.idleState.decorUID >= 0, (DecorField.shared.foot(o.idleState.decorUID)?.kind.sitPoints.count ?? 0) > 1 { continue }
            s.insert(k)
        }
        return s
    }

    /// In a fast move right now (the cap counts these).
    var isFastMove: Bool {
        if let k = idleState.kind, Self.fastKinds.contains(k) { return true }
        switch script { case .hopPlay, .rollPlay, .spin, .flipPlay: return true; default: break }
        if let s = social, s.kind.isFast, s.end == nil { return true }
        return false
    }
    /// How many of the OTHER Jellies are in a fast move.
    func fastOthers() -> Int { socialOthers().reduce(0) { $0 + ($1 !== self && $1.isFastMove ? 1 : 0) } }

    // MARK: tail

    /// The spin ended: another turn, or the dizzy wobble and done.
    func tailNext(_ skinner: Skinner) {
        if idleState.reps > 0 {
            idleState.reps -= 1
            script = .spin(t: 0); activity = .playing
        } else {
            jellyKick = max(jellyKick, 2.6)
            AudioHub.shared.play(.wobble, jelly: steerID, x: px, volume: 0.6)
            idleFinish(skinner)
        }
    }

    // MARK: peek

    /// The two ends of the sofa (just outside its arms, on the floor he can use).
    func peekSpot(from here: SIMD2<Float>) -> SIMD2<Float>? {
        let sofa = RoomLayout.sofa
        var best: (SIMD2<Float>, Float)?
        for sgn: Float in [-1, 1] {
            let p = SIMD2(sgn * (sofa.halfExtents.x + 0.95), RoomLayout.minZ + 2.7)
            let q = fixed(p)
            guard simd_distance(p, q) < 0.35, peerFree(q), simd_distance(here, q) > 1.2, reachable(here, q) else { continue }
            let d = simd_distance(here, q)
            if best == nil || d < best!.1 { best = (q, d) }
        }
        return best?.0
    }
    func peekArrived() {
        idleState.phase = 1; idleState.phaseT = 0; idleState.t = 0; idleState.steps = 0
        script = .idle; activity = .lookingAround
    }

    // MARK: flop / peek postures (feet planted under him, like the sit)

    func runPosePlay(_ sim: SoftBody, _ skinner: Skinner, _ dt: Float) {
        let kind = idleState.kind ?? .flop
        if kind == .peek, idleState.steps == 0 {
            // face the room first
            let turning = turnSteps(goal: faceCameraYaw(), tol: 0.08)
            gaitPose(sway: 0.04, bob: 0.0, rock: 0.2)
            if turning || feet.active { idleState.t = 0; return }
            idleState.steps = 1
        }
        let t = idleState.t
        let side = idleState.sign
        var k: Float = 0, lean: Float = 0, wob: Float = 0, eyes: Float = 1, done = false
        if kind == .flop {
            k = smooth01(t / 0.3) * (1 - smooth01((t - 1.5) / 0.5))
            lean = k
            let env = expf(-max(0, t - 2.1) / 0.3) * (t > 2.1 ? 1 : 0)
            wob = env * cosf(2 * .pi * 5.5 * (t - 2.1))
            eyes = 1 - 0.8 * k
            if flopKicks == 0, t >= 0.3 { flopKicks = 1; jellyKick = max(jellyKick, 2.2); AudioHub.shared.play(.squish, jelly: steerID, x: px, volume: 0.7) }
            if flopKicks == 1, t >= 1.9 { flopKicks = 2; jellyKick = max(jellyKick, 2.8); AudioHub.shared.play(.boop, jelly: steerID, x: px, volume: 0.6) }
            done = t > 2.9
            gaitPose(sway: 0.04, bob: 0.0, rock: 0.2)
            squash *= 1 - 0.36 * k + 0.09 * wob
            pitch += 0.20 * k
            roll += side * 0.30 * lean + 0.05 * wob * side
        } else {
            let duck1 = smooth01(t / 0.5) * (1 - smooth01((t - 1.1) / 0.5))
            let duck2 = smooth01((t - 3.0) / 0.5) * (1 - smooth01((t - 3.5) / 0.5))
            k = max(duck1, duck2)
            lean = smooth01((t - 1.1) / 0.6) * (1 - smooth01((t - 3.0) / 0.5))
            eyes = 1
            done = t > 4.2
            if flopKicks == 0, t >= 1.3 { flopKicks = 1; jellyKick = max(jellyKick, 1.2); AudioHub.shared.play(.boop, jelly: steerID, x: px, volume: 0.35) }
            gaitPose(sway: 0.04, bob: 0.0, rock: 0.2)
            squash *= 1 - 0.30 * k
            pitch += -0.07 * lean
            // lean out from the sofa end toward the room: toward the middle of the floor
            let toward: Float = px < 0 ? -1 : 1
            roll += toward * 0.24 * lean * (1 + 0.12 * sinf(2 * .pi * t * 1.4))
        }
        skinner.setEyeOpenness(max(0.15, eyes))
        if done && !feet.active { skinner.setEyeOpenness(1); flopKicks = 0; idleFinish(skinner) }
    }
}

extension SocialKind {
    /// The kinds that are fast play (counted by the cap on fast moves).
    var isFast: Bool {
        switch self { case .chase, .dance, .keepAway, .zoomies: return true; default: return false }
    }
}
