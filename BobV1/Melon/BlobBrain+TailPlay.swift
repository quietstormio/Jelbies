//
//  BlobBrain+TailPlay.swift
//  Pip's tail life (2026-10-28, BobV1/Melon/TailMotion.swift moves the tail; this file decides what it does). Pip only (feature .spines): every other Jelbie's
//  `tailDrive` stays at its defaults and its tail is off anyway.
//    always     walking swish locked to the stride (livelier at a run), mood carriage (happy higher + slow wag, grumpy / sad flat and slower), the
//               happy wag, eager wag while food is on the way, hmph's two slow annoyed swishes, the turn trail (the tail lags a turn)
//    .tail      the existing spin "after his own tail", now with the tail LEADING the turn, then a dizzy wobble of the tail
//    .tailThump excited: stands, lifts the tail and thumps it on the floor 2...3 times (soft thump, a small squash and wobble)
//    .tailHug   calm / sleepy: curls the tail round to his side, holds the tip with his stubby arms, rests, lets go
//  Reduce Motion: the antics do not start and the swish / wag are small. The antics are scheduled like every other antic (cooldown, variety, not while held /
//  racing / in care), see `tailAnticAllowed`.
//

import Foundation
import simd

struct TailPlayState {
    /// Shaped values the emotes write (degrees); they ease back to 0 when no emote is running.
    var lift: Float = 0, liftTip: Float = 0, curl: Float = 0, curlPow: Float = 1.6
    /// The dizzy wobble after a tail chase: 1 -> 0.
    var dizzy: Float = 0
    /// Thump bookkeeping.
    var thumps = 0, thumpsDone = 0, impactT: Float = 9
    /// The hug: 0...1 curl blend and the side of the tail (+1 = +x).
    var hug: Float = 0
    /// How many times each emote has played (tests).
    var played: [IdleKind: Int] = [:]
}

extension BlobBrain {
    static let tailKinds: Set<IdleKind> = [.tailThump, .tailHug]
    /// Raise of the thumped tail (deg), thump cycle (s): raise, fast drop, rest.
    static let thumpLiftDeg: Float = 40, thumpRaise: Float = 0.34, thumpDrop: Float = 0.11, thumpCycle: Float = 0.64
    static let hugCurlDeg: Float = 110, hugLiftTip: Float = 45, hugIn: Float = 1.0, hugHold: Float = 2.3, hugOut: Float = 0.8

    /// Pip is the only one with a tail to play with.
    var hasTailToPlay: Bool { feature == .spines && !WornSet.sleepHides(self) && !WornSet.flipping(self) }

    /// Tail antics need a calm, free moment: awake, not held / racing / reserved / asleep, nobody else's request, and Reduce Motion off.
    var tailAnticAllowed: Bool {
        hasTailToPlay && !A11ySettings.shared.reduceMotion && !held && !race.active && !sleepLocked && attached && idleState.kind == nil && pending == nil
    }

    /// Eating, drinking or about to (a dine / sip / eat / drink request or the script): the eager wag.
    var foodComing: Bool {
        if let p = pending { switch p { case .dine, .sip, .eat, .drink: return true; default: break } }
        switch script { case .dine, .eat: return true; default: return false }
    }

    /// Every tick from driveLimbs: tells the skinner what the tail is to do.
    func tailPlayTick(_ skinner: Skinner, _ dt: Float) {
        guard hasTailToPlay else { skinner.tailDrive = TailDrive(); tailPlay = TailPlayState(); skinner.tailSeatOn = false; return }
        tailSeatTick(skinner)
        var d = TailDrive()
        d.stride = stridePhase; d.strideLive = feet.active
        d.run = max(runW, zoomW)
        d.reduce = A11ySettings.shared.reduceMotion
        // mood carriage
        var mood: Float = idleMood == .happy ? 0.7 : (idleMood == .grumpy ? -1 : 0)
        switch expr.kind {
        case .happy, .excited, .joyArc: mood = max(mood, 1)
        case .worried, .sleepy, .grumpy: mood = min(mood, -0.7)
        default: break
        }
        if idleState.reaction == .cheer { mood = 1 }
        if foodComing { mood = 1; d.wagDeg = 16; d.wagHz = 3.0 }
        d.mood = mood
        let kind = idleState.kind
        // the dizzy wobble after the chase decays on its own
        tailPlay.dizzy = max(0, tailPlay.dizzy - dt / 1.9)
        if tailPlay.dizzy > 0 { d.wagDeg = max(d.wagDeg, 30 * tailPlay.dizzy); d.wagHz = 2.1 }
        switch kind {
        case .tail:                              // the chase: the tail leads the spin and swings out a little
            d.turnGain = 0.10; d.liftTip = 6
        case .hmph:                              // two slow annoyed swishes
            let t = idleState.phaseT
            d.wagDeg = max(d.wagDeg, 24 * smooth01(t / 0.2) * (1 - smooth01((t - 1.15) / 0.3))); d.wagHz = 1.5
        default: break
        }
        // the emotes' shaped values; with no emote they ease back to rest
        if kind != .tailThump { tailPlay.lift *= expf(-dt / 0.12); tailPlay.thumpsDone = 0 }
        if kind != .tailHug { tailPlay.curl *= expf(-dt / 0.2); tailPlay.hug *= expf(-dt / 0.2); if kind != .tailThump { tailPlay.liftTip *= expf(-dt / 0.2) } }
        d.liftRoot = tailPlay.lift
        d.liftTip += tailPlay.liftTip
        d.bendYaw = tailPlay.curl; d.bendPow = tailPlay.curlPow
        skinner.tailDrive = d
    }

    // MARK: start

    /// From `idleStart`: false = not Pip / no room for it.
    func tailEmoteBegin(_ kind: IdleKind, _ sim: SoftBody) -> Bool {
        guard hasTailToPlay, !A11ySettings.shared.reduceMotion else { return false }
        idleBegin(kind)
        script = .idle; activity = kind == .tailThump ? .playing : .lookingAround
        tailPlay.played[kind, default: 0] += 1
        tailPlay.impactT = 9
        if kind == .tailThump { tailPlay.thumps = 2 + (rand() < 0.5 ? 1 : 0); tailPlay.thumpsDone = 0 }
        else { tailPlay.hug = 0 }
        return true
    }

    // MARK: thump

    /// Stands square, a little anticipation squash, then lifts the tail and drops it on the floor 2...3 times (a soft thump each, a squash pulse and a wobble).
    func runTailThump(_ sim: SoftBody, _ skinner: Skinner, _ dt: Float) {
        let t = idleState.phaseT
        gaitPose(sway: 0.03, bob: 0.0, rock: 0.2)
        armWalkWant = 1
        if idleState.phase == 0 { idleState.phase = 1; face(.excited, hold: Float(tailPlay.thumps) * Self.thumpCycle + 0.9) }
        let start: Float = 0.25
        let ct = t - start
        let cyc = Self.thumpCycle
        var lift: Float = 0, tip: Float = 0
        if ct >= 0 {
            let idx = Int(ct / cyc)
            if idx < tailPlay.thumps {
                let l = ct - Float(idx) * cyc
                if l < Self.thumpRaise {
                    let u = smooth01(l / Self.thumpRaise); lift = Self.thumpLiftDeg * u; tip = 12 * u
                } else if l < Self.thumpRaise + Self.thumpDrop {
                    let u = (l - Self.thumpRaise) / Self.thumpDrop; lift = Self.thumpLiftDeg * (1 - u * u); tip = 12 * (1 - u)
                } else {
                    if tailPlay.thumpsDone <= idx {
                        tailPlay.thumpsDone = idx + 1; tailPlay.impactT = 0
                        AudioHub.shared.play(.footstep, jelly: steerID, x: px, volume: 0.85)
                        jellyKick = max(jellyKick, 0.9)
                    }
                }
            }
        } else {
            squash *= 1 - 0.03 * smooth01(t / start)          // a little crouch before the first lift
        }
        tailPlay.lift = lift; tailPlay.liftTip = tip
        tailPlay.impactT += dt
        squash *= 1 - 0.035 * max(0, 1 - tailPlay.impactT / 0.18)          // the thump shivers through him
        if ct > Float(tailPlay.thumps) * cyc + 0.35 && !feet.active { idleFinish(skinner) }
    }

    // MARK: hug

    /// Calm: the tail curls round to his side (the tip lifts), his arms close on the tip (stubby, capped like every arm), a happy rest, then he lets go.
    func runTailHug(_ sim: SoftBody, _ skinner: Skinner, _ dt: Float) {
        let t = idleState.phaseT
        gaitPose(sway: 0.03, bob: 0.0, rock: 0.2)
        armWalkWant = 1
        // first turn so the tail side (his +x) faces the camera: the hug reads from the front of the room (the tail is behind him otherwise)
        if idleState.steps == 0 {
            let turning = turnSteps(goal: faceCameraYaw() - .pi / 2, tol: 0.08)
            if turning || feet.active { idleState.phaseT = 0; return }
            idleState.steps = 1
        }
        let total = Self.hugIn + Self.hugHold + Self.hugOut
        if idleState.phase == 0 { idleState.phase = 1; face(.happy, hold: total - 0.2) }
        let k = smooth01(t / Self.hugIn) * (1 - smooth01((t - Self.hugIn - Self.hugHold) / Self.hugOut))
        tailPlay.hug = k
        tailPlay.curl = -Self.hugCurlDeg * k          // (negative yaw = more curl toward the tail's own +x side)
        tailPlay.curlPow = 1.3
        tailPlay.liftTip = Self.hugLiftTip * k
        tailPlay.lift = 8 * k
        roll -= 0.07 * k                               // leans a little toward the tail
        pitch += 0.05 * k
        let breathe = idleState.phase == 1 && k > 0.95 ? 0.012 * sinf(2 * .pi * 0.7 * t) : 0
        squash *= 1 + breathe
        armDirW = k
        armDirEl = [0.55, 0.30]; armDirSa = [0.9, -0.35]; armDirOut = 0.05          // the far arm closes in front, the tail-side arm reaches back to the tip
        if t > total && !feet.active { idleFinish(skinner) }
    }
}

extension BlobBrain {
    /// The floor under the tail: the seat he stands on (a hop-on seat, the swing, the seesaw ... with its current height and, for the ones that move, its current spot).
    func tailSeatTick(_ skinner: Skinner) {
        // (hopping on: the floor he is about to land on, so the tail is already up there when he lands)
        let hopping = !bagFloorOn && idleState.kind == .decorSit && idleState.bagStage == 1 && gait.groundTo > 0.01
        let floorNow = hopping ? gait.groundTo : skinner.jelly.floorY
        if (bagFloorOn || hopping), floorNow > 0.01, idleState.kind == .decorSit, idleState.decorUID >= 0,
           let f = DecorField.shared.foot(idleState.decorUID), let sw = DecorField.shared.seatWorld(idleState.decorUID, seat: idleState.seat) {
            let h = f.spec.half
            // the piece's own centre, carried by however far the seat has moved from its resting spot (the swing, the seesaw's plank, the bunny)
            let rest = DecorModels.seatPoint(f.kind, seat: idleState.seat, anim: DecorAnim(), lift: f.lift), rw = f.turned(SIMD2(rest.x, rest.z))
            let shift = SIMD2(sw.x, sw.z) - (f.centre + rw)
            skinner.tailSeat = TailSeat(centre: f.centre + shift, half: h, corner: min(f.spec.corner, min(h.x, h.y)), y: floorNow, rimTop: f.kind == .sandbox ? 0.27 : 0, rimW: f.kind == .sandbox ? 0.22 : 0)
            skinner.tailSeatOn = true
        } else if idleState.kind == .decorSit && idleState.bagStage == 3 && skinner.tailSeat.y > 0.01 {
            skinner.tailSeatOn = true          // (hopping off: the tail keeps the seat's shape until he is down; the lift is capped by his own height)
        } else { skinner.tailSeatOn = false }
    }
}
