//
//  BlobBrain+Race.swift
//  Jelly Circuit "Waddle Sprint": the race script. A racer takes ONE step of the locked walk gait for each step the race model commits (a tap of a foot
//  button, or a rival's AI tap); between steps he stands on the track (planted feet, the walking pose). Nothing else moves him.
//
//  The race has its OWN speed path: stride and step rate arrive with each committed step (RaceTuning, from the waddle stat). `stride`, `stepRate`,
//  `walkBoost` and `runStrideMul` are never read here, so racing and roaming never stack. The step itself is the walk's (`startStep`): swing lift,
//  waddle roll, bob, arm counter-swing and the foot beans are exactly the locked gait's.
//

import Foundation
import simd

/// The race state of one brain (the race model decides WHEN to step; this is how the body does it).
struct RaceDrive {
    var active = false
    /// Heading of the track (world yaw; 0 = toward +z, the camera) and the lane's x.
    var heading: Float = 0
    var laneX: Float = 0
    /// The committed step waiting for the feet to be free (at most one).
    var pendingFoot: Int?
    var pendingStride: Float = 0.34
    var pendingRate: Float = 3.6
    /// Squares the feet with this step (the last of the coast).
    var pendingFinal = false
    /// Seconds of stumble left (the body rocks, no steps).
    var stumbleT: Float = 0
    var stumbleLen: Float = 0
    /// Seconds since a step ended (the arms drop to rest when he has been standing a while).
    var idle: Float = 0
    var steps = 0
    var looks = 0
}

extension BlobBrain {
    /// He can take one more committed step: nothing is waiting (one step ahead is the most; the feet start it the tick the last one ends).
    var raceStepFree: Bool {
        guard race.active, case .race = script else { return false }
        return race.pendingFoot == nil && race.stumbleT <= 0
    }
    /// His feet are planted between two steps.
    var raceBetweenSteps: Bool {
        guard race.active, case .race = script else { return false }
        return !feet.active && race.pendingFoot == nil
    }
    /// He can start a look-around (a pause): racing, between steps.
    var raceCanLook: Bool {
        guard race.active, case .race = script else { return false }
        return !feet.active && race.pendingFoot == nil
    }
    /// Back on the track after a look-around (or never left).
    var raceBodyReady: Bool { race.active && idleState.kind == nil && !commanded }

    /// Takes the track: stands square on lane `x`, facing `heading` (0 = toward the camera).
    func startRace(sim: SoftBody, skinner: Skinner, heading: Float = 0, laneX x: Float) {
        abortScript(sim, skinner)
        pending = nil; interruptScript = false
        race = RaceDrive(active: true, heading: heading, laneX: x)
        autonomy = false; idleBlocked = false
        runW = 0; zoomW = 0; hurry = false
        currentPose(sim)
        yaw = heading
        nextSwing = 0
        script = .race; activity = .walking
    }

    /// Leaves the track: the race script ends and he stands (he turns to the camera by himself).
    func endRace() {
        guard race.active else { return }
        race = RaceDrive()
        if case .race = script { script = .none }
        restTimer = 1.0
    }

    /// The race model commits a step: the feet swing it as soon as they are free.
    func raceCommit(foot: Int, stride: Float, rate: Float, final: Bool = false) {
        guard race.active else { return }
        race.pendingFoot = foot; race.pendingStride = stride; race.pendingRate = rate; race.pendingFinal = final
    }

    /// The same foot twice: he stumbles (a rock and a wobble; the race model holds his steps for `RaceTuning.stumbleTime`).
    func raceStumble(_ seconds: Float) {
        guard race.active else { return }
        race.stumbleT = seconds; race.stumbleLen = seconds
        race.pendingFoot = nil
        jellyKick = 2.4
    }

    /// A focus pause: he stops and looks around (the existing look behaviour, shortened). False = not possible right now.
    @discardableResult
    func raceLook(_ sim: SoftBody) -> Bool {
        guard raceCanLook else { return false }
        commanded = true
        if idleStart(.look, sim) {
            idleState.hold = rand(0.5, 0.9)
            race.looks += 1
            return true
        }
        commanded = false
        return false
    }

    /// Per fixed step (the race flow): a look-around that has ended hands him back to the race script.
    func raceKeepAlive() {
        guard race.active, case .none = script, idleState.kind == nil, pending == nil else { return }
        script = .race; activity = .walking
        restTimer = 1.0
    }

    /// Puts a race event of this racer on the body (the race glue and the tests both use it).
    func raceApply(_ e: RaceEvent, sim: SoftBody) {
        switch e {
        case .step(_, let foot, let stride, let rate, let final): raceCommit(foot: foot, stride: stride, rate: rate, final: final)
        case .stumble, .trip: raceStumble(RaceTuning.stumbleTime)
        case .pauseBegan: raceLook(sim)
        default: break
        }
    }

    // MARK: the script

    /// `.race`, once per fixed step (BlobBrain.runScript): pose like the walk; start the committed step when the feet are free.
    func raceRun(_ sim: SoftBody, _ dt: Float) {
        poseOn = true; ensureFeet(sim)
        if feet.active { race.idle = 0 } else { race.idle += dt }
        if race.stumbleT > 0 { race.stumbleT = max(0, race.stumbleT - dt) }
        if !feet.active, race.stumbleT <= 0, let foot = race.pendingFoot {
            race.pendingFoot = nil
            raceStartStep(foot: foot, stride: race.pendingStride, rate: race.pendingRate, final: race.pendingFinal)
        }
        let standing = !feet.active
        gaitPose(sway: standing ? 0.6 * waddleRoll : waddleRoll, bob: standing ? 0.03 : 0.12, rock: standing ? 0.5 : 1)
        armWalkWant = (feet.active || race.idle < 0.4) ? 1 : 0.5
        if race.stumbleT > 0 { raceWobble() }
    }

    /// The stumble's rock: a quick roll, squash pulses and a twist that die out over the stumble.
    private func raceWobble() {
        let k = race.stumbleLen > 0 ? race.stumbleT / race.stumbleLen : 0        // 1 -> 0
        let s = (1 - k) * race.stumbleLen
        let env = k * k
        roll += 0.10 * env * sinf(2 * .pi * 4.5 * s)
        squash *= 1 - 0.06 * env * (0.5 - 0.5 * cosf(2 * .pi * 6.0 * s))
        twist = 0.08 * env * sinf(2 * .pi * 5.5 * s + 1)
        pitch += 0.05 * env
    }

    /// One step of the locked gait toward the track heading: the stance foot's lead plus half a stride ahead (the walk's regular step), with the
    /// stride, rate and foot given by the race.
    private func raceStartStep(foot: Int, stride L: Float, rate: Float, final: Bool) {
        let u = SIMD2<Float>(sinf(race.heading), cosf(race.heading))
        nextSwing = foot
        let stance = 1 - foot
        let root = SIMD2(px, pz)
        let s = simd_dot(feet.pos[stance] - (root + rotXZ(geom.off[stance], yaw)), u)
        var r = 0.5 * L, a: Float
        if final { a = max(0, s); r = 0 } else { a = min(max(s + r, 0.3 * L), 1.5 * L) }
        let m = turnRate * min(max(amplitude, 0.5), 1) * (1 / rate)
        let dyaw = max(-m, min(m, wrapAngle(race.heading - yaw)))
        let drift = max(-0.04, min(0.04, (race.laneX - px) * 0.5))
        race.steps += 1
        startStep(rootD: u * a + SIMD2(drift, 0), dyaw: dyaw, reach: u * r, peak: stepLift * amplitude, rate: rate, outScale: 0.6)
    }
}
