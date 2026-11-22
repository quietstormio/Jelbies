//
//  BlobBrain+BestHug.swift
//  The HUG: a hug aimed at the PLAYER (the glass), about 4 s. Unlocked by the best-friends stage (`BestHug.isUnlocked`), done only when asked (the Tricks row, "<name> hug" by voice)
//  plus once by itself as the reveal (GameCare+BestHug.swift). Never in a random pool.
//
//  CARRIER: it runs as a flagged HULA (`IdleKind.hula` + `idleState.trick.flags & BestHug.flagBit`, set by `trickBegin`, dispatched by `runHula`) so the scheduler files
//  (BlobBrain+Idle.swift, BlobSocial*) are untouched: the Show never sets the flag, so a Show hula is the same as before.
//  SEQUENCE (the player asks -> `commandBestHug`):  0 walk 2-3 normal steps toward the front of the room (`hugSpot`: floor, clear of the furniture, the others and the HUD rail,
//  skipped in the close-up / when asleep), then the hula's turn to the camera;  1 a small dip;  2 both arms open wide and up;  3 he leans to the glass, the arms close in a hugging arc,
//  the body presses a little (squash), eyes in the happy curve, a slow sway for 1.5 s, hearts the whole squeeze, a purr of haptic pulses and the happy chirp;  4 release: arms down,
//  a pleased wiggle, one bigger heart, a clean hand-back to idle (the feet stay planted: only pose channels move, like every standing emote).
//

import Foundation
import simd

nonisolated enum BestHugTuning {
    /// Seconds from the end of the turn: the dip, the arms open, the arms close (the squeeze starts), the squeeze, the release.
    static let dip: Float = 0.30, rise: Float = 0.45, hold: Float = 1.0, close: Float = 0.45
    /// The arms are up and open from `dip + rise` and held for `hold` ("come here"), then close.
    static var openEnd: Float { dip + rise + hold }
    static var squeezeStart: Float { openEnd + close }
    static let squeeze: Float = 1.5, release: Float = 0.95
    static var squeezeEnd: Float { squeezeStart + squeeze }
    static var total: Float { squeezeEnd + release }
    /// Arms: elevation / sweep (rad) wide open and up, then closed round the front; the lean to the glass (rad of pitch), the press (squash), the sway (rad of roll).
    nonisolated(unsafe) static var openEl: Float = 1.05, openSa: Float = 1.05
    nonisolated(unsafe) static var closeEl: Float = 0.30, closeSa: Float = 0.60
    nonisolated(unsafe) static var lean: Float = 0.38, press: Float = 0.09, sway: Float = 0.17
    /// A heart every this many seconds of the squeeze (a normal cuddle: one per 0.6 to 1.0 s).
    static let heartGap: Float = 0.22
    /// The walk: how far toward the camera (u), and the least that is worth a walk.
    nonisolated(unsafe) static var walkDistance: Float = 0.42
    static let walkLeast: Float = 0.18
    static let walkGiveUp: Float = 7
}

/// The brain-side state of the hug: the request, the walk, and what GameCare has to draw / feel (hearts, buzz).
struct BestHugState {
    var want = false          // a hug was asked (consumed by `bestHugTick`)
    var inPlace = false       // the close-up: no walk
    var afterWalk = false     // walking to the front first
    var walkT: Float = 0
    var go = false            // the next hula that starts is the hug
    var hearts = 0            // hearts GameCare still has to float up from him
    var bigHeart = false
    var burst = 0             // the fuller burst at the peak of the squeeze
    var buzz: Float = 0       // a haptic pulse (intensity) for GameCare to play (0 = none)
    var heartT: Float = 0
    var buzzT: Float = 0
    var started = false
}

extension BestHug {
    /// `IdleState.trick.flags` bit of a running hug (the moonwalk uses bit 1).
    static let flagBit = 1 << 20
}

extension BlobBrain {
    /// A hug was asked (Tricks row, voice, the reveal). `inPlace`: the close-up, he does it where he stands.
    func commandBestHug(inPlace: Bool) {
        bestHug.want = true; bestHug.inPlace = inPlace
    }

    var isBestHugging: Bool { idleState.kind == .hula && idleState.trick.flags & BestHug.flagBit != 0 }

    /// Every tick, before the commands are read: starts the walk to the front, then the hug itself.
    func bestHugTick(_ dt: Float) {
        if bestHug.want {
            bestHug.want = false
            var spot: SIMD2<Float>?
            if !bestHug.inPlace, !isSleeping { spot = hugSpot() }
            if let s = spot {
                bestHug.afterWalk = true; bestHug.walkT = 0
                requestNow(.goTo(s))
            } else {
                bestHug.afterWalk = false; bestHug.go = true; commandedIdle = .hula
            }
        }
        guard bestHug.afterWalk else { return }
        bestHug.walkT += dt
        var walkEnded = false
        if case .none = script, idleState.kind == nil, pending == nil, !interruptScript { walkEnded = true }
        if activity == .touched || isSleeping { bestHug.afterWalk = false; return }          // (picked up / put to sleep on the way: no hug)
        if walkEnded || bestHug.walkT > BestHugTuning.walkGiveUp { bestHug.afterWalk = false; bestHug.go = true; commandedIdle = .hula }
    }

    /// The floor spot two or three steps toward the camera, inside the wander area, clear of the furniture and of the other Jelmiko; nil = no room (he hugs where he stands).
    func hugSpot() -> SIMD2<Float>? {
        let here = SIMD2(px, pz)
        let toCam = cameraPosXZ - here
        guard simd_length(toCam) > 0.5 else { return nil }
        let dir = simd_normalize(toCam)
        let fwd = simd_normalize(SIMD2(-here.x * 0.5, 1))          // (straight to the front, drawn a little toward the middle: never into a corner)
        _ = dir
        var want = here + fwd * BestHugTuning.walkDistance
        if let r = wanderRect { want = SIMD2(min(max(want.x, r.min.x), r.max.x), min(max(want.y, r.min.y), r.max.y)) }
        let got = resolve(SIMD3(want.x, 0, want.y), footprint)
        var p = SIMD2(got.x, got.z)
        if simd_length(p - here) < BestHugTuning.walkLeast { return nil }
        for o in peers() where simd_distance(o.pos, p) < peerGap * 0.75 { return nil }
        // never closer to the camera than he is allowed to wander (the front edge is where the HUD's rail and the heart button start)
        if let r = wanderRect, p.y > r.max.y { p.y = r.max.y }
        return p
    }

    /// The flagged hula's tick (from `runHula`).
    func runBestHug(_ sim: SoftBody, _ skinner: Skinner, _ dt: Float) {
        typealias T = BestHugTuning
        let a = amplitude
        let calm = A11ySettings.shared.reduceMotion
        if idleState.phase == 0 {
            let turning = turnSteps(goal: idleState.goalYaw, tol: 0.1)
            gaitPose(sway: 0.04, bob: 0, rock: 0.2)
            armWalkWant = 1
            if turning || feet.active { idleState.phaseT = 0; return }
            idleState.phase = 1; idleState.phaseT = 0
            bestHug.started = false; bestHug.heartT = 0; bestHug.buzzT = 0
        }
        armWalkWant = 1          // (the arms stand out as capsules: the belly drum's way; at 0 they stay the rest nubs and armDir shows nothing)
        mouthOpen = 0
        let t = idleState.phaseT
        if !bestHug.started {
            bestHug.started = true
            skinner.setEyeOpenness(0.35); face(.happy, hold: 1.0)
        }
        // envelopes
        let dipK = t < T.dip ? sinf(.pi * t / T.dip) : 0
        let armW = smooth01((t - 0.12) / 0.30) * (1 - smooth01((t - (T.squeezeEnd + 0.50)) / 0.30))          // (the arms open again at the release, a beat, then down)
        let closed = smooth01((t - T.openEnd) / T.close) * (1 - smooth01((t - T.squeezeEnd) / 0.25))
        let leanK = smooth01((t - T.openEnd) / T.close) * (1 - smooth01((t - T.squeezeEnd) / 0.30))
        let sq = smooth01((t - T.squeezeStart + 0.15) / 0.25) * (1 - smooth01((t - T.squeezeEnd) / 0.2))
        let upK = smooth01((t - 0.2) / 0.35) * (1 - smooth01((t - T.openEnd) / 0.3))
        let burstAt = T.squeezeStart + 0.7
        // the body: a dip of anticipation, a little rise as the arms go up, the lean to the glass, the press, the slow sway
        squash *= (1 - 0.06 * dipK * a) * (1 + 0.035 * upK * a)
        pitch += T.lean * leanK * a
        squash *= 1 - T.press * sq * a * (1 + 0.12 * sinf(2 * .pi * 2.6 * (t - T.squeezeStart)))
        if !calm { roll += T.sway * sq * sinf(2 * .pi * (t - T.squeezeStart) / T.squeeze) * a }          // (Reduce Motion: hearts, no sway)
        // the arms: open wide and up, then closed round the front in an arc
        armDirW = armW
        for s in 0..<2 {
            let side: Float = s == 0 ? 1 : -1
            armDirEl[s] = T.openEl + (T.closeEl - T.openEl) * closed
            armDirSa[s] = side * (T.openSa + (T.closeSa - T.openSa) * closed)
        }
        armDirOut = 0.05
        // the face: the happy curve from the arms-up on, a blush at the squeeze
        if t >= T.openEnd, idleState.steps & 1 == 0 { idleState.steps |= 1; skinner.setEyeOpenness(0.2); face(.joyArc, hold: T.squeeze + T.close + 0.3); blushBump(hold: 3.0, peak: 0.5) }
        // the squeeze: the chirp, the purr of pulses, hearts all along
        if t >= T.squeezeStart - 0.1, t < T.squeezeEnd {
            if idleState.steps & 2 == 0 { idleState.steps |= 2; AudioHub.shared.chirp(jelly: steerID, .happy, x: px); jellyKick = max(jellyKick, 1.0); bestHug.buzz = 0.45 }
            bestHug.heartT -= dt
            if bestHug.heartT <= 0 { bestHug.heartT = T.heartGap; bestHug.hearts += 1 }
            if idleState.steps & 8 == 0, t >= burstAt { idleState.steps |= 8; bestHug.burst = 4 }          // (the fuller burst at the peak)
            bestHug.buzzT -= dt
            if bestHug.buzzT <= 0 { bestHug.buzzT = 1 / 2.6; bestHug.buzz = max(bestHug.buzz, 0.16 + 0.12 * sq) }
        }
        // the release: a pleased wiggle, one bigger heart, a happy voice
        if t >= T.squeezeEnd {
            let u = t - T.squeezeEnd
            if idleState.steps & 4 == 0 { idleState.steps |= 4; bestHug.bigHeart = true; jellyKick = max(jellyKick, 1.5); bestHug.buzz = 0.3; AudioHub.shared.contextVoice(jelly: steerID, .aww, chance: 0.8, x: px) }
            if !calm { roll += 0.08 * expf(-u / 0.4) * sinf(2 * .pi * 3 * u) * a }
            squash *= 1 + 0.03 * expf(-u / 0.25) * sinf(2 * .pi * 4 * u) * a
        }
        if t >= T.total, !feet.active {
            armDirW = 0; armDirOut = 0
            skinner.setEyeOpenness(1)
            idleState.trick.flags &= ~BestHug.flagBit
            idleFinish(skinner)
        }
    }
}
