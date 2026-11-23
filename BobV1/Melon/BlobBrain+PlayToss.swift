//
//  BlobBrain+PlayToss.swift
//  The two moves of Play mode (Play/PlayToss.swift decides WHEN; these are HOW), both built from the locked moves, never an arm:
//    tossHeader   a hop on the spot with more air than the happy bounce (apex `tossApex`): the squash on take-off, the stretch in the air and the landing wobble are the
//                 hop machinery's own (`idleScootHop`, the bounce); the ball meets the crown at the top of the hop (the controller reads the head's height each step).
//    tossBump     walks round behind the ball (the far side from where it should go), turns onto the line and takes the soccer kick's STOMP STEP into it (the planted foot's
//                 forward step, `idleFootStep`) with a lean in and a squash dip, a body-bump; the ball leaves as the foot comes down (`tossFire`). No leg swings.
//  Started by the controller (`tossHeaderStart`, `tossBumpStart`) or, with no controller, by `idleStart` (the emote suites run them alone: a hop; a turn and a stomp at nothing).
//

import Foundation
import simd

/// The running bump's plan and progress (in `IdleState.toss`).
struct TossIdle {
    /// Walking round to the stand (the .walk script is the idle kind's own).
    var walking = false
    /// 0 turn onto the line, 1 the stomp (fires as the foot lands), 2 settle.
    var stage = 0
    var dir = SIMD2<Float>(0, 1)
    var stand = SIMD2<Float>.zero
    var fired = false
    /// How hard the stomp leans in (0...1).
    var lean: Float = 1
    var retries = 0
    /// play-ball-r1: a header's approach (walk to `stand`, turn onto the player, wait for the controller's go, crouch, jump) instead of a stomp.
    var header = false
    /// The controller says the ball is `tossCrouch + tossHeaderLead` from the crown: crouch now.
    var go = false
    /// Set by the controller when the ball has gone elsewhere: the header is given up.
    var abort = false
    /// The centroid's height standing (the jump is measured from it).
    var ground: Float = 0
    /// play-ball-s2: a kick that was PLANNED (the stand is held, stage 6, until the controller's `go`) and the readable wind-up / lunge look (soccer and beach kicks only; every other stomp is as before).
    var foot = false
    var lunge = false
    /// The ball was struck (by the controller, from outside the foot's own timing: it touched his body): the stomp that follows is only the follow-through.
    var struck = false
    /// How long the foot has been down waiting for the ball to come into reach (stage 1).
    var waitT: Float = 0
    /// The side the wind-up leans to (+1 / -1); the stomp snaps through to the other side.
    var leanSide: Float = 1
}

extension BlobBrain {
    /// The hop's apex: the happy bounce's 0.12 u, a little higher so the head meets the ball up in the air.
    /// (play-ball-r1: the header's jump is higher so the feet are visibly off the floor; `-BallReturnOld 1` = the old 0.16 hop)
    /// (the bubble wand's pop hop and the old play code keep `tossApex` 0.16 and `tossHeaderLead` 0.24; only the play header's own jump raises it, through `tossApexOverride`, around its one `idleScootHop` call)
    nonisolated(unsafe) static var tossApexOverride: Float?
    static var tossApex: Float { tossApexOverride ?? 0.16 }
    static let tossJumpApex: Float = 0.40
    /// Seconds from the start of a header hop to its apex (measured by PlayTossTests.testHeaderHopTiming; the controller starts the hop this long before the ball arrives).
    static let tossHeaderLead: Float = 0.24
    /// Seconds from the start of the play header's jump to its top (measured: BallReturnTests.testHeaderJumpNumbers).
    static let tossJumpLead: Float = 0.30
    /// The crouch before the jump (play-ball-r1) and how far the crown rises at the top of the jump (measured by PlayTossTests.testHeaderHopTiming / BallReturnTests).
    static let tossCrouch: Float = 0.20
    static let tossCrownRise: Float = 0.42
    /// The side lean of a planned kick's wind-up and snap (rad).
    static let tossLeanAmount: Float = 0.22

    var tossBusy: Bool { idleState.kind == .tossHeader || idleState.kind == .tossBump }

    // MARK: header

    @discardableResult
    func tossHeaderStart(_ sim: SoftBody, _ skinner: Skinner? = nil, jump: Bool = false) -> Bool {
        guard idleState.kind == nil else { return false }
        if case .none = script {} else {          // a waiting pose (a look, a step on the spot): stopped cleanly first
            guard let skinner, !feet.active else { return false }
            abortAll(sim, skinner)
        }
        currentPose(sim)
        idleBegin(.tossHeader)
        commanded = true
        idleState.target = SIMD2(px, pz)
        idleState.reps = 1
        idleState.hop = 0; idleState.landT = 0
        script = .idle; activity = .playing
        idleState.phase = 1; idleState.phaseT = 0
        if jump { Self.tossApexOverride = Self.tossJumpApex }          // (play-ball-r2: the late ball's hop is the same real jump as the planned header's)
        idleScootHop(sim)
        Self.tossApexOverride = nil
        tossFaceYaw = nil
        return true
    }

    /// The header's jump after its approach and crouch: the same hop `tossHeaderStart` begins, from where he stands now.
    func tossHeaderJump(_ sim: SoftBody) {
        idleState.kind = .tossHeader
        idleState.target = SIMD2(px, pz)
        idleState.reps = 1
        idleState.hop = 0; idleState.landT = 0
        script = .idle; activity = .playing
        idleState.phase = 1; idleState.phaseT = 0
        Self.tossApexOverride = Self.tossJumpApex; defer { Self.tossApexOverride = nil }
        idleScootHop(sim)
        tossFaceYaw = nil
    }

    /// Is a header's jump under way and the body off the ground (the strike counts only then).
    func tossAirborne(_ sim: SoftBody) -> Bool { idleState.kind == .tossHeader && idleState.phase >= 1 && idleState.toss.ground > 0 && sim.centroid().y - idleState.toss.ground > 0.10 }
    /// Is he standing ready for a header (approach done, facing the player).
    var tossHeaderReady: Bool { idleState.kind == .tossBump && idleState.toss.header && idleState.toss.stage >= 3 }
    /// The controller lets a header stand go (the ball is not coming to him any more): a stand not yet crouched is stopped at once between steps (the same clean stop `tossHeaderStart` uses), so whoever is nearest the loose ball can do the loose-ball job.
    func tossHeaderRelease(_ sim: SoftBody, _ skinner: Skinner) {
        guard idleState.kind == .tossBump, idleState.toss.header, idleState.toss.stage < 4 else { return }
        idleState.toss.abort = true
        guard !feet.active else { return }
        abortAll(sim, skinner)
        tossFaceYaw = nil
    }
    /// Has a planned kick going and not yet struck (held in stage 6, winding up in 5, or the stomp's foot not yet down).
    var tossFootApproach: Bool { idleState.kind == .tossBump && idleState.toss.foot && !idleState.toss.struck && !idleState.toss.fired }
    var tossFootReady: Bool { idleState.kind == .tossBump && idleState.toss.foot && idleState.toss.stage == 6 }
    /// The controller says the ball is `lead` away: wind up now.
    func tossFootGo() { if idleState.kind == .tossBump, idleState.toss.foot { idleState.toss.go = true } }
    /// The planned kick is given up (the ball went elsewhere): held / winding-up stands finish at once.
    func tossFootRelease(_ sim: SoftBody, _ skinner: Skinner) {
        guard tossFootApproach, idleState.toss.stage != 1 else { return }
        idleState.toss.abort = true
        guard !feet.active else { return }
        abortAll(sim, skinner)
        tossFaceYaw = nil
    }
    /// The ball touched his body before the foot was ready: the stomp starts at once as the follow-through of the strike.
    func tossStrikeNow() {
        guard idleState.kind == .tossBump, idleState.toss.foot, !idleState.toss.struck else { return }
        idleState.toss.struck = true
        if idleState.toss.stage == 1 { return }
        guard !feet.active else { idleState.toss.stage = 1; idleState.phaseT = 0; return }
        idleState.toss.stage = 1; idleState.phaseT = 0
        idleFootStep(reach: SoccerTuning.stompReach, rate: SoccerTuning.stompRate, peak: SoccerTuning.stompPeak)
    }
    /// Has a header approach going (walking, turning, ready or crouching): the controller may re-aim or release it.
    var tossHeaderApproach: Bool { idleState.kind == .tossBump && idleState.toss.header }

    // MARK: bump

    /// Walk to `stand`, line up on `dir` (unit, toward where the ball should go), stomp. False = busy.
    @discardableResult
    func tossBumpStart(_ sim: SoftBody, _ skinner: Skinner? = nil, stand: SIMD2<Float>, dir: SIMD2<Float>, lean: Float = 1, header: Bool = false, foot: Bool = false, lunge: Bool = false) -> Bool {
        guard idleState.kind == nil else { return false }
        if case .none = script {} else {
            guard let skinner, !feet.active else { return false }
            abortAll(sim, skinner)
        }
        currentPose(sim)
        idleBegin(.tossBump)
        commanded = true
        var t = idleState.toss
        t = TossIdle(); t.dir = dir; t.stand = stand; t.lean = lean; t.header = header; t.foot = foot; t.lunge = lunge
        if lunge { tossLeanSide = -tossLeanSide; t.leanSide = tossLeanSide }
        idleState.toss = t
        idleState.target = stand
        idleState.goalYaw = atan2f(dir.x, dir.y)
        if simd_distance(position, stand) < 0.18 {
            tossBumpArrived()
        } else {
            idleState.toss.walking = true
            idleState.decorGo = false
            scriptT = 0; stuckT = 0; bestDist = .infinity; route = []; steerStall = 0
            script = .walk(target: stand, then: .none); activity = .walking
        }
        return true
    }

    /// The walk to the stand is over (or was not needed).
    func tossBumpArrived() {
        idleState.toss.walking = false
        idleState.toss.stage = 0; idleState.toss.fired = false
        idleState.goalYaw = atan2f(idleState.toss.dir.x, idleState.toss.dir.y)
        idleState.phase = 0; idleState.phaseT = 0; idleState.steps = 0
        script = .idle; activity = .lookingAround
    }

    /// The running bump (the .idle script): turn onto the line, stomp, settle.
    func runTossBump(_ sim: SoftBody, _ skinner: Skinner, _ dt: Float) {
        var s = idleState.toss
        let t = idleState.phaseT
        gaitPose(sway: 0.04, bob: 0.0, rock: 0.2)
        switch s.stage {
        case 0:
            if idleState.yielding { idleFinish(skinner); return }
            let turning = turnSteps(goal: idleState.goalYaw, tol: 0.08)
            if !turning && !feet.active && t > 0.12 {
                if s.header {
                    s.stage = 3; idleState.phaseT = 0; s.ground = sim.centroid().y
                } else if s.foot {
                    s.stage = 6; idleState.phaseT = 0          // (a planned kick: stands ready on the line until the controller's go)
                } else {
                    s.stage = 5; idleState.phaseT = 0          // (a small wind-up first: the body rocks back over the planted foot)
                }
            }
        case 1:
            let k = sinf(.pi * min(1, t / 0.4))
            if s.lunge {          // (play-ball-s2: the lunge into the ball: a deep forward lean and a squash dip that peaks as the foot lands)
                let l = sinf(.pi * min(1, t / 0.32))
                squash *= 1 - 0.10 * l; pitch += 0.34 * l
                // the side lean the front camera can see (pitch is foreshortened): from the wind-up's side it snaps through to the other as the foot lands, then settles
                let q = min(1, t / 0.2), eq = q * q * (3 - 2 * q), settle = 1 - min(1, max(0, (t - 0.2) / 0.3))
                roll += s.leanSide * Self.tossLeanAmount * (t < 0.2 ? (1 - 2 * eq) : -settle)
            } else {
                squash *= 1 - 0.07 * k * s.lean
                pitch += 0.20 * k * s.lean
            }
            if !s.fired, !s.struck, feet.stepU > 0.7 || !feet.active {
                s.waitT += dt
                if tossFireReady?(self) ?? true {
                    s.fired = true
                    jellyKick = max(jellyKick, 1.6)
                    tossFire?(self)
                }
            }
            if !feet.active, t > 0.3, s.fired || s.struck || s.waitT > 0.4 { s.stage = 2; idleState.phaseT = 0; idleState.steps = 0 }
        case 5:
            let wind: Float = s.lunge ? 0.18 : 0.16
            let k = min(1, t / wind), e = k * k * (3 - 2 * k)
            pitch -= (s.lunge ? 0.26 : 0.14) * e          // (play-ball-s2: the planned kick leans back and squashes further: it reads from the camera)
            squash *= 1 - (s.lunge ? 0.09 : 0.05) * e
            if s.lunge { roll += s.leanSide * Self.tossLeanAmount * e }
            if s.foot, s.abort || idleState.yielding { idleState.toss = s; idleFinish(skinner); return }
            if t >= wind, !feet.active {
                s.stage = 1; s.fired = false; idleState.phaseT = 0
                idleFootStep(reach: SoccerTuning.stompReach, rate: SoccerTuning.stompRate, peak: SoccerTuning.stompPeak)
            }
        case 6:          // a planned kick: stands ready on the line facing where it will go (held with turn steps) until the ball is nearly here
            if idleState.yielding || s.abort || t > 3.5 { idleState.toss = s; idleFinish(skinner); return }
            _ = turnSteps(goal: idleState.goalYaw, tol: 0.10)
            if s.go, !feet.active { s.stage = 5; idleState.phaseT = 0 }
        case 3:          // a header: stands ready on the player's line (held on it with turn steps) until the ball is nearly here
            if idleState.yielding || s.abort || t > 3.5 { idleState.toss = s; idleFinish(skinner); return }
            _ = turnSteps(goal: idleState.goalYaw, tol: 0.10)
            if s.go, !feet.active { s.stage = 4; idleState.phaseT = 0 }
        case 4:          // the crouch, then the jump (the hop machinery: kind .tossHeader from here on)
            let k = min(1, t / Self.tossCrouch), e = k * k * (3 - 2 * k)
            squash *= 1 - 0.16 * e
            pitch -= 0.08 * e
            if t >= Self.tossCrouch, !feet.active {
                idleState.toss = s
                tossHeaderJump(sim)
                return
            }
        default:
            pitch += 0.12 * max(0, 1 - t / 0.35)          // (the follow-through eases out)
            if !feet.active, idleState.steps < 1, t > 0.25 { idleFootStep(reach: 0); idleState.steps += 1 }
            if (idleState.yielding && t > 0.4) || t > 0.9 { idleState.toss = s; idleFinish(skinner); return }
        }
        idleState.toss = s
    }
}
