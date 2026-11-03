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
}

extension BlobBrain {
    /// The hop's apex: the happy bounce's 0.12 u, a little higher so the head meets the ball up in the air.
    static let tossApex: Float = 0.16
    /// Seconds from the start of a header hop to its apex (measured by PlayTossTests.testHeaderHopTiming; the controller starts the hop this long before the ball arrives).
    static let tossHeaderLead: Float = 0.24

    var tossBusy: Bool { idleState.kind == .tossHeader || idleState.kind == .tossBump }

    // MARK: header

    @discardableResult
    func tossHeaderStart(_ sim: SoftBody, _ skinner: Skinner? = nil) -> Bool {
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
        idleScootHop(sim)
        return true
    }

    // MARK: bump

    /// Walk to `stand`, line up on `dir` (unit, toward where the ball should go), stomp. False = busy.
    @discardableResult
    func tossBumpStart(_ sim: SoftBody, _ skinner: Skinner? = nil, stand: SIMD2<Float>, dir: SIMD2<Float>, lean: Float = 1) -> Bool {
        guard idleState.kind == nil else { return false }
        if case .none = script {} else {
            guard let skinner, !feet.active else { return false }
            abortAll(sim, skinner)
        }
        currentPose(sim)
        idleBegin(.tossBump)
        commanded = true
        var t = idleState.toss
        t = TossIdle(); t.dir = dir; t.stand = stand; t.lean = lean
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
                s.stage = 1; s.fired = false; idleState.phaseT = 0
                idleFootStep(reach: SoccerTuning.stompReach, rate: SoccerTuning.stompRate, peak: SoccerTuning.stompPeak)
            }
        case 1:
            let k = sinf(.pi * min(1, t / 0.4))
            squash *= 1 - 0.07 * k * s.lean
            pitch += 0.12 * k * s.lean
            if !s.fired, feet.stepU > 0.7 || !feet.active {
                s.fired = true
                jellyKick = max(jellyKick, 1.6)
                tossFire?(self)
            }
            if !feet.active, t > 0.3 { s.stage = 2; idleState.phaseT = 0; idleState.steps = 0 }
        default:
            if !feet.active, idleState.steps < 1, t > 0.25 { idleFootStep(reach: 0); idleState.steps += 1 }
            if (idleState.yielding && t > 0.4) || t > 0.9 { idleState.toss = s; idleFinish(skinner); return }
        }
        idleState.toss = s
    }
}
