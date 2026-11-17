//
//  BlobBrain+NightEmotes.swift
//  night-emotes-r1: five calm solo emotes for an awake Jelmiko in the evening / night, before bed ("Yeah add more nighttime emotes").
//  Every one is built from motions that exist (look / turn, sit, nod, sway, the sleepy / happy faces, the soft hum voice clip): no jump, no new body
//  motion, no new sound. They ride the existing machinery, so the feet / arms rules are the ones those already keep:
//    moonGaze    faces the window (a three-quarter turn, the face still shows), looks up with a soft dreamy face for a few seconds      [look machinery]
//    sleepySway  a slow side-to-side sway with heavy eyes (the sleepy face)                                                            [look machinery]
//    nodOff      sits; the head drops slowly, a small start, a blink, awake again                                                      [sit machinery]
//    lullabyHum  sits and hums softly (the hum clip, twice) with a slow sway                                                           [sit machinery]
//    starCount   looks up and gives small nods, as if counting                                                                         [look machinery]
//  They are picked by the idle table (`nightEmoteMix`): weighted by `idleNight`, exactly zero by day, and the share they take is TAKEN from the other
//  non-wander picks, so the wander share (how often something happens at all) and the pick timing never change. They are ordinary idle kinds: bedtime
//  (`commandedGoodnight` -> `startGoodnight`) aborts them like any other idle, the night song / meal / wake flows see an idle that yields in 0.2 s.
//  Dev only: `-NightForce <kind>` makes the scheduler pick that kind every time (the RunMove mechanism).
//

import Foundation
import simd

enum NightEmoteTuning {
    static let kinds: [IdleKind] = [.moonGaze, .sleepySway, .nodOff, .lullabyHum, .starCount]
    static let kindSet = Set(kinds)
    /// How the night share is divided between them (sums to 1).
    static let mix: [IdleKind: Float] = [.moonGaze: 0.24, .sleepySway: 0.22, .lullabyHum: 0.20, .nodOff: 0.18, .starCount: 0.16]
    /// The share of the NON-wander weight they take at full night (taken from the other kinds, so the total is unchanged).
    nonisolated(unsafe) static var share: Float = 0.40
    /// `idleNight` at which the full share is reached (a good share in the evening already).
    static let fullAtNight: Float = 0.4
    static func shareAt(night: Float) -> Float { night <= 0 ? 0 : share * min(1, night / fullAtNight) }
}

extension BlobBrain {
    /// The idle table's night hook: moves `share(night)` of the non-wander weight over to the five night solos. Calm moods only (not grumpy).
    static func nightEmoteMix(_ w: inout [(kind: IdleKind, weight: Float)], _ m: IdleMood, night: Float) {
        let s = NightEmoteTuning.shareAt(night: night)
        guard s > 0, m != .grumpy else { return }
        let total = w.reduce(0) { $0 + ($1.kind == .wander ? 0 : $1.weight) }
        guard total > 0 else { return }
        for i in w.indices where w[i].kind != .wander { w[i].weight *= 1 - s }
        for k in NightEmoteTuning.kinds { w.append((k, total * s * (NightEmoteTuning.mix[k] ?? 0))) }
    }

    /// `-NightForce <kind>` (DevArgs-gated): the scheduler picks that night kind every time.
    static func nightForceApply(_ b: BlobBrain, _ d: UserDefaults) {
        guard DevArgs.enabled, let n = d.string(forKey: "NightForce"), let k = IdleKind(rawValue: n), NightEmoteTuning.kindSet.contains(k) else { return }
        b.runMoveDemo = k; b.idleState.cooldown = 2
    }

    // MARK: start

    func nightEmoteBegin(_ kind: IdleKind, _ sim: SoftBody) -> Bool {
        idleBegin(kind)
        idleState.reps = 0; idleState.steps = 0; idleState.hop = 0
        idleState.baseYaw = yaw
        script = .idle; activity = .lookingAround
        let cam = faceCameraYaw()
        switch kind {
        case .moonGaze:
            idleState.hold = rand(5.0, 7.0)
            // walks to the nearest window (the window antic's walk) and turns to it, a little short of square so the dreamy face still shows to the player
            let here = SIMD2(px, pz)
            var spot = here, wx = Self.windowXs().min { abs($0 - px) < abs($1 - px) } ?? 0
            if let w = windowSpot(from: here) { spot = w.spot; wx = w.wx; idleState.windowGo = true; idleState.target = w.spot; script = .walk(target: w.spot, then: .none); activity = .walking }
            let wy = atan2f(wx - spot.x, RoomLayout.minZ - spot.y)
            idleState.goalYaw = abs(wrapAngle(wy + 1.1 - cam)) < abs(wrapAngle(wy - 1.1 - cam)) ? wy + 1.1 : wy - 1.1
        case .sleepySway: idleState.hold = rand(7.0, 9.0); idleState.goalYaw = cam + idleState.sign * 0.25
        case .starCount: idleState.hold = rand(5.5, 6.8); idleState.goalYaw = cam + idleState.sign * 0.45
        default: idleState.hold = rand(8.5, 10.5); idleState.goalYaw = cam + idleState.sign * 0.3 * rand(0.4, 1)          // nodOff, lullabyHum (the sit)
        }
        return true
    }

    /// A one-shot inside the run (bit `b` of `reps`, which these kinds own).
    private func nightOnce(_ b: Int) -> Bool {
        guard idleState.reps & (1 << b) == 0 else { return false }
        idleState.reps |= 1 << b
        return true
    }

    // MARK: look-based (called at the end of runLook, after its own lean / pitch)

    func nightLookPose(_ skinner: Skinner, _ k: Float) {
        guard let kind = idleState.kind, NightEmoteTuning.kindSet.contains(kind), !idleState.yielding || k > 0 else { return }
        let ease = smooth01(k), t = idleState.t, pt = idleState.phaseT
        let hold = idleState.hold
        let inHold = idleState.phase == 1
        switch kind {
        case .moonGaze:
            pitch -= 0.14 * ease                                          // the head back: looking up at the moon
            roll -= idleState.sign * 0.05 * k                             // (half of the look's lean: a soft tilt)
            roll += 0.025 * ease * sinf(2 * .pi * t / 3.2)
            if inHold, nightOnce(0) { face(.happy, hold: hold + 0.8) }
        case .starCount:
            pitch -= 0.12 * ease
            roll -= idleState.sign * 0.06 * k
            if inHold {
                if nightOnce(0) { face(.hopeful, hold: hold + 0.8) }
                // small nods, as if counting: a short dip every 0.9 s, five of them
                let u = (pt - 0.8) / 0.9
                if u >= 0, u < 5 {
                    let f = u - floorf(u)
                    let dip = min(1, f / 0.5)
                    pitch += 0.09 * sinf(.pi * dip) * ease
                }
            }
        case .sleepySway:
            roll -= idleState.sign * 0.10 * k                             // (cancels the look's one-sided lean: the sway is symmetric)
            roll += 0.095 * ease * sinf(2 * .pi * t / 3.6)               // slow, side to side
            twist = 0.03 * ease * sinf(2 * .pi * t / 3.6 + 1.0)
            pitch += 0.07 * ease                                          // a heavy head
            squash *= 1 - 0.012 * ease * (0.5 + 0.5 * sinf(2 * .pi * t / 3.6))
            if inHold, nightOnce(0) { face(.sleepy, hold: hold + 0.8) }
        default: break
        }
        _ = skinner
    }

    // MARK: sit-based (called at the end of sitPose, after its own squash / pitch / eyes)

    func nightSitPose(_ skinner: Skinner, _ k: Float) {
        guard let kind = idleState.kind, kind == .nodOff || kind == .lullabyHum else { return }
        let ph = idleState.phase
        let T: Float = ph == 2 ? idleState.phaseT : (ph > 2 ? 99 : -1)          // seconds into the held sit
        let base = 1 - 0.5 * k
        switch kind {
        case .nodOff:
            guard T >= 0 else { return }
            let startAt: Float = 3.9
            // the head drops slowly (heavy eyes), a small start (a quick jerk up, the eyes pop wide, a squash pulse, a little "huh"), a slow blink, awake again
            let drop = smooth01(T / 3.6) * (1 - smooth01((T - startAt) / 0.22))
            pitch += 0.24 * drop * k
            var eyes = base * (1 - 0.8 * drop)
            if T >= startAt {
                if nightOnce(0), !voiceMuted { AudioHub.shared.contextVoice(jelly: steerID, .huh, chance: 0.7, x: px) }
                let wide = 1 - smooth01((T - startAt) / 0.7)
                eyes = min(1, eyes + 0.5 * wide)
                squash *= 1 + 0.03 * sinf(.pi * min(1, max(0, (T - startAt) / 0.35)))
                let b = sinf(.pi * min(1, max(0, (T - 4.7) / 0.6)))          // the slow blink
                eyes *= 1 - 0.9 * b
            }
            skinner.setEyeOpenness(max(0.05, eyes))
        default:        // lullabyHum
            roll += 0.085 * k * sinf(2 * .pi * idleState.t / 3.4)
            squash *= 1 + 0.01 * k * sinf(2 * .pi * idleState.t / 3.4 + 0.6)
            var eyes = 1 - 0.62 * k
            if T >= 0.6, T < 3.0 || (T >= 4.8 && T < 7.2) {
                let w = T < 3.0 ? T - 0.6 : T - 4.8
                if T < 3.0 ? nightOnce(0) : nightOnce(1) { if !voiceMuted { AudioHub.shared.contextVoice(jelly: steerID, .hum, chance: 1, x: px) } }
                mouthOpen = 0.09 + 0.05 * sinf(2 * .pi * w * 1.1)          // (a small mouth, closed-ish: a hum)
                eyes *= 0.95
            } else { mouthOpen = 0 }
            skinner.setEyeOpenness(max(0.05, eyes))
        }
    }
}
