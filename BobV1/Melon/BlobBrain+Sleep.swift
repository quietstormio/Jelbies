//
//  BlobBrain+Sleep.swift
//  Sleep (user 2026-10-19): a Jelly that gets sleepy yawns, rolls onto his BACK where he stands (on the rug / a clear floor spot, not in front of the
//  table or the bowls), shuts his eyes and sleeps belly-up, breathing slowly and snoring now and then. To wake he rolls back over onto his feet the
//  way he went down, stretches (a groggy yawn if somebody tapped him) and carries on.
//
//  PILE: when a Jelly goes to sleep and another one is already asleep (or on his way to sleep) he walks to him and lies down right beside him, so
//  the sleepers form one snuggled row (centre spacing `pileSpacing`, a hair over the body width: touching, never inside each other).
//
//  The roll over is NOT a physics roll: the pose attractor is ramped from upright to `lieAngle` (pitch back, about his x axis inside the heading)
//  with the anchor blended from the feet pivot to the grounded pose, so it is exactly reversible. The feet are the rigid foot beans (like the flip:
//  `driveBeansRigid`, no world foot targets) and the arms stay the rest nubs. Once he has settled the attractor never changes again, so
//  `SoftBody.isSettled` holds and a sleeping Jelly skips his sim step (`JellyActor.brainIsStill`); the breathing is a render-side jelly ripple
//  (`jellyKick`), not the attractor.
//
//  Stages: 0 walk to the spot, 1 turn + yawn, 2 lie down, 3 asleep, 4 roll back, 5 stretch (then `idleFinish`).
//

import Foundation
import simd

struct SleepState {
    var stage = 0
    var t: Float = 0                 // seconds in the stage
    var k: Float = 0                 // 0 standing ... 1 on his back
    var hold: Float = 60             // seconds asleep before he wakes on his own
    var minHold: Float = 14
    var spot = SIMD2<Float>.zero
    var lieYaw: Float = 0
    var wakeAsked = false
    var groggy = false
    var touchT: Float = 0            // seconds a finger has been on him while he sleeps (a tap wakes him gently, a hold lets go of the sleep)
    var breath: Float = 0
    var turned = false
    var joined = false               // lying beside another sleeper
    var stageStart = true
    var kStart: Float = 1
    var walkTries = 0
    /// Put to bed by voice: the room dims and the blanket goes on once everybody is down.
    var tucked = false
}

enum SleepTuning {
    /// Pitch (rad) of the body on his back: the face looks at the ceiling.
    static let lieAngle: Float = 1.50
    static let lieTime: Float = 1.25, rollBackTime: Float = 1.1
    /// Centre spacing of a snuggled row (body width 2R = 1.6, plus the squash widening: touching).
    static let pileSpacing: Float = 1.66
    /// Squash while lying (a little flatter and wider: relaxed).
    static let lieSquash: Float = 0.94
    static let breathPeriod: Float = 3.6
    /// A finger on him for less than this wakes him gently; longer = a real pick up (the sleep is dropped and the touch play takes over).
    static let tapTime: Float = 0.9
    /// Daytime nap hold / evening-night hold, seconds.
    static let napHold: ClosedRange<Float> = 14...26
    static let nightHold: ClosedRange<Float> = 70...110
}

extension BlobBrain {
    // MARK: state read by the stage, the audio hub, the needs and the sim sleep

    /// Settled asleep on his back (the hold stage): music, snores, the slower drain and the sim sleep read this.
    var isNapping: Bool { idleState.kind == .sleep && sleep.stage == 3 && !sleep.wakeAsked }
    /// Any part of the sleep: on the way, lying, waking.
    var isSleeping: Bool { idleState.kind == .sleep }
    /// Lying or rolling (the body is off its feet).
    var isLying: Bool { idleState.kind == .sleep && sleep.stage >= 2 && sleep.stage <= 4 }
    var napDrainScale: Float { isNapping ? NeedsTuning.napDrain : 1 }

    // MARK: choosing the spot

    /// Floor he may lie on at `p`: standable, on the rug, clear of the bowls, the call spot, the table and the tray.
    func sleepFloorOK(_ p: SIMD2<Float>) -> Bool {
        let q = fixed(p)
        guard simd_distance(q, p) < 0.12 else { return false }
        let L = RoomLayout.self
        guard simd_distance(p, L.rugCentre) < L.rugRadius - 0.35 else { return false }
        for s in [GameCamera.foodBowlSpot, GameCamera.waterBowlSpot] where simd_distance(p, s) < 1.0 { return false }
        if simd_distance(p, GameCamera.callSpot) < 1.3 { return false }
        if simd_distance(p, L.table.centre) < 1.6 { return false }
        for b in L.dynamicBoxes where L.boxDistanceXZ(p, b) < 1.1 { return false }
        return true
    }
    /// ... and not under another Jelly (`mates` may be close: they are the pile).
    func sleepSpotOK(_ p: SIMD2<Float>, mates: [BlobBrain] = []) -> Bool {
        guard sleepFloorOK(p) else { return false }
        for o in socialOthers() where o !== self && !mates.contains(where: { $0 === o }) && simd_distance(o.position, p) < peerGap * 0.9 { return false }
        return true
    }

    /// The other Jellies that sleep or are on their way to sleep (the pile).
    var sleepMates: [BlobBrain] { socialOthers().filter { $0 !== self && $0.idleState.kind == .sleep && $0.sleep.stage <= 4 } }

    /// Where he lies down: beside the pile if there is one, else here when this is a good spot, else the nearest good spot on the rug.
    func chooseSleepSpot() -> (spot: SIMD2<Float>, yaw: Float, joined: Bool) {
        let mates = sleepMates
        let here = position
        if let lead = mates.min(by: { $0.steerID < $1.steerID }) {
            let ly = lead.sleep.lieYaw
            // a snug place against the sleepers: a ring of spots one body width round each of them (a row, then a triangle); the one touching most and nearest wins
            var best: (SIMD2<Float>, Float)?
            for m in mates {
                for k in 0..<12 {
                    let a = Float(k) * (.pi / 6)
                    let p = m.sleep.spot + SIMD2(cosf(a), sinf(a)) * SleepTuning.pileSpacing
                    var touching = 0, clash = false
                    for o in mates {
                        let d = simd_distance(o.sleep.spot, p)
                        if d < SleepTuning.pileSpacing * 0.93 { clash = true }
                        if d < SleepTuning.pileSpacing * 1.12 { touching += 1 }
                    }
                    guard !clash, sleepSpotOK(p, mates: mates), reachable(here, p) else { continue }
                    let score = simd_distance(here, p) - 1.2 * Float(touching) + 0.4 * abs(sinf(a))          // (a row along x is the neatest)
                    if best == nil || score < best!.1 { best = (p, score) }
                }
            }
            if let b = best { return (b.0, ly, true) }
        }
        let ly = faceCameraYaw() + .pi * (sleepHeadToward ? 1 : 0)
        if sleepSpotOK(here) { return (here, ly, false) }
        var best: (SIMD2<Float>, Float)?
        for ix in -4...4 { for iz in -3...3 {
            let p = SIMD2(Float(ix) * 0.6, 0.25 + Float(iz) * 0.5)
            guard sleepSpotOK(p), reachable(here, p) else { continue }
            let d = simd_distance(here, p)
            if best == nil || d < best!.1 { best = (p, d) }
        } }
        return (best?.0 ?? here, ly, false)
    }
    /// True = he lies with his head toward the camera (feet away), false = feet toward the camera.
    var sleepHeadToward: Bool { true }

    // MARK: when

    /// Is it time for him to go to sleep now (asked at every autonomous pick): deep night, or another Jelly is asleep / going to sleep (a pile forms:
    /// at night he joins at once, by day only while the first one has just lain down).
    func sleepWanted() -> Bool {
        guard sleepEnabled, social == nil, idleState.kind == nil else { return false }
        if idleDeepNight > 0.5 { return true }
        let mates = sleepMates
        if mates.isEmpty { return false }
        if idleNight > 0.3 { return rand() < 0.8 }
        let fresh = mates.contains { $0.idleState.t < 20 && $0.sleep.stage <= 3 }
        return fresh && rand() < 0.3
    }

    // MARK: voice: goodnight

    /// "Goodnight": whatever he is doing stops, then the usual sleep (beside the others when somebody is already going to bed), asleep until morning.
    func startGoodnight(_ sim: SoftBody, _ skinner: Skinner) {
        if idleState.kind == .sleep { sleep.tucked = true; sleep.hold = max(sleep.hold, 240); return }
        var busy = idleState.kind != nil
        if case .none = script {} else { busy = true }
        if busy { abortAll(sim, skinner) }
        pending = nil
        commanded = true
        if idleStart(.sleep, sim) {
            sleep.tucked = true
            sleep.hold = max(sleep.hold, 240)
            restTimer = max(restTimer, 1)
        } else { commanded = false }
    }

    // MARK: starting

    /// `idleStart(.sleep)`.
    func sleepBegin(_ sim: SoftBody, night: Bool) -> Bool {
        let c = chooseSleepSpot()
        guard c.joined || sleepFloorOK(c.spot) else { return false }          // nowhere good to lie down that he can reach: not now
        idleBegin(.sleep)
        sleep = SleepState()
        sleep.spot = c.spot; sleep.lieYaw = c.yaw; sleep.joined = c.joined
        sleep.hold = night ? rand(SleepTuning.nightHold.lowerBound, SleepTuning.nightHold.upperBound) : rand(SleepTuning.napHold.lowerBound, SleepTuning.napHold.upperBound)
        if idleDeepNight > 0.5 { sleep.hold = 3600 }
        sleep.minHold = night ? 20 : 12
        if simd_distance(position, c.spot) > 0.25 {
            script = .walk(target: c.spot, then: .none); activity = .walking
            sleep.stage = 0
        } else {
            script = .idle; activity = .lookingAround
            sleep.stage = 1
        }
        return true
    }

    /// The walk to the spot is over (script .none). Short of it (the leg was given up: somebody stood in the way) he tries again, up to three times,
    /// then lies down where he is. On to the turn + yawn.
    func sleepArrived(_ sim: SoftBody, _ skinner: Skinner) {
        if simd_distance(position, sleep.spot) > 0.6, sleep.walkTries < 3 {
            sleep.walkTries += 1
            // re-plan: the pile may have moved on, so choose again
            let c = chooseSleepSpot()
            sleep.spot = c.spot; sleep.lieYaw = c.yaw; sleep.joined = c.joined
            if simd_distance(position, c.spot) > 0.25 {
                scriptT = 0; stuckT = 0; bestDist = .infinity; route = []; steerStall = 0; job = nil
                script = .walk(target: c.spot, then: .none); activity = .walking
                return
            }
        }
        guard sleepFloorOK(position) else { idleFinish(skinner); return }          // no way to a good spot: not here (in front of the table, on the call spot): try again later
        sleep.spot = position
        sleep.stage = 1; sleep.t = 0; sleep.stageStart = true
        idleState.phaseT = 0
        script = .idle; activity = .lookingAround
    }

    // MARK: waking

    /// Wake now: roll back and stretch. `groggy` = a tap (a slower, sleepier stretch); `fast` = something needs him (a meal, a command): no stretch.
    func sleepWake(groggy: Bool, fast: Bool = false) {
        guard idleState.kind == .sleep else { return }
        if sleep.stage <= 1 { idleState.yielding = true; return }          // not down yet: the usual yield ends it
        if sleep.stage >= 4 { return }
        sleep.wakeAsked = true
        sleep.groggy = groggy
        if sleep.stage == 3 || sleep.stage == 2 { sleep.kStart = sleep.k; sleep.stage = 4; sleep.t = 0; sleep.stageStart = true }
        _ = fast
    }

    // MARK: per-stage work in the normal flow (stages 1 and 5)

    func runSleep(_ sim: SoftBody, _ skinner: Skinner, _ dt: Float) {
        sleep.t += dt
        switch sleep.stage {
        case 1:
            // turn to the lying heading, then a big yawn, then down
            if !sleep.turned {
                let turning = turnSteps(goal: sleep.lieYaw, tol: 0.08)
                gaitPose(sway: 0.04, bob: 0.0, rock: 0.2)
                if !turning && !feet.active { sleep.turned = true; sleep.t = 0 }
                return
            }
            let t = sleep.t
            let k = smooth01(t / 0.8) * (1 - smooth01((t - 2.3) / 0.6))
            let m = smooth01((t - 0.8) / 0.45) * (1 - smooth01((t - 1.9) / 0.45))
            sleepYawnPose(skinner, k: k, mouth: 0.95 * m, shake: t > 0.8 && t < 1.9, sleepy: 0.5 * smooth01((t - 1.5) / 1.4))
            gaitPose(sway: 0.04, bob: 0.0, rock: 0.2)
            if t > 3.0 && !feet.active { sleepToLie(sim, skinner) }
        case 5:
            // the stretch after the roll back (groggy = slower and sleepier, eyes only half open)
            let slow: Float = sleep.groggy ? 1.5 : 1
            let t = sleep.t / slow
            let k = smooth01(t / 0.8) * (1 - smooth01((t - 1.7) / 0.6))
            let m = smooth01((t - 0.7) / 0.4) * (1 - smooth01((t - 1.35) / 0.4))
            sleepYawnPose(skinner, k: k, mouth: sleep.groggy ? 0.95 * m : 0, shake: false, sleepy: max(0.95 * (1 - smooth01(sleep.t / 0.6)), sleep.groggy ? 0.5 * (1 - smooth01((t - 1.6) / 1.2)) : 0))
            gaitPose(sway: 0.04, bob: 0.0, rock: 0.2)
            if t > 2.7 && !feet.active {
                skinner.setEyeOpenness(1); mouthOpen = 0; armDirW = 0; armDirOut = 0; armWalkWant = 0
                idleFinish(skinner)
            }
        default: break
        }
    }

    /// The yawn posture (the same numbers as the idle yawn: arms up as thumbs, the body elongates, a little tip back), eyes squeezed shut.
    private func sleepYawnPose(_ skinner: Skinner, k: Float, mouth: Float, shake: Bool, sleepy: Float) {
        armWalkWant = 1
        let t = sleep.t
        squash *= 1 + 0.15 * smooth01(k) + (shake ? 0.012 * sinf(2 * .pi * 7 * t) : 0)
        pitch += -0.06 * smooth01(k)
        armDirW = smooth01(k)
        armDirEl = [0.95, 0.95]; armDirSa = [0.12, 0.12]; armDirOut = 0.07
        skinner.setEyeOpenness(max(0.05, 1 - 0.85 * smooth01(k) - sleepy))
        mouthOpen = mouth
    }

    private func sleepToLie(_ sim: SoftBody, _ skinner: Skinner) {
        sleep.stage = 2; sleep.t = 0; sleep.k = 0; sleep.stageStart = true
        mouthOpen = 0; armDirW = 0; armDirOut = 0; armWalkWant = 0
        // the soles' world targets go: the rigid foot beans follow the body from here (like the flip)
        sim.targets = []; beanHold = 0; feetInit = false; feet.reset(); stepLive = false; walkFinal = false; pivotSide = nil
        gait.wander = false
    }

    // MARK: the body while he is down (stages 2...4), in place of the normal pose / limbs

    /// Ticked from `BlobBrain.tick` right after the idle gate; true = this tick is fully handled.
    func sleepBodyTick(_ sim: SoftBody, _ skinner: Skinner, _ dt: Float) -> Bool {
        guard idleState.kind == .sleep, case .idle = script, sleep.stage >= 2, sleep.stage <= 4 else { return false }
        activity = .lookingAround
        mouthOpen = 0
        sleep.t += dt
        poseOn = true
        switch sleep.stage {
        case 2:
            sleep.k = smooth01(sleep.t / SleepTuning.lieTime)
            if sleep.t >= SleepTuning.lieTime { sleep.stage = 3; sleep.t = 0; sleep.k = 1; sleep.breath = 0 }
        case 3:
            sleep.k = 1
            sleep.breath += dt
            if sleep.breath >= SleepTuning.breathPeriod { sleep.breath = 0; jellyKick = max(jellyKick, 0.5) }           // the slow breathing: a soft ripple under the skin
            let morning = idleDeepNight < 0.5 && idleNight < 0.3
            if sleep.wakeAsked || sleep.t >= sleep.hold || (morning && sleep.t >= sleep.minHold && sleep.hold > 600) {
                sleep.kStart = 1; sleep.stage = 4; sleep.t = 0
            }
        default:    // 4: roll back over the way he went down
            sleep.k = sleep.kStart * (1 - smooth01(sleep.t / SleepTuning.rollBackTime))
            if sleep.t >= SleepTuning.rollBackTime {
                sleep.k = 0
                sleepStand(sim, skinner)
                return false
            }
        }
        applyLie(sim, skinner, dt)
        return true
    }

    /// The attractor at lie blend `sleep.k`.
    private func applyLie(_ sim: SoftBody, _ skinner: Skinner, _ dt: Float) {
        let k = sleep.k
        let pitchAng = pitchBase * (1 - k) - SleepTuning.lieAngle * k
        let q = yawQuat(yaw) * simd_quatf(angle: pitchAng, axis: SIMD3(1, 0, 0))
        let sq = 1 - (1 - SleepTuning.lieSquash) * k
        sim.attractor.rotation = q
        sim.attractor.squash = sq
        var a: SIMD3<Float>
        if geom.valid {
            let m = geom.mid, w = SIMD2(px, pz) + rotXZ(geom.midOff, yaw)
            a = sim.pivotAnchor(rotation: q, squash: sq, pivot: m, world: SIMD3(w.x, sim.floorY + m.y, w.y))
        } else { a = SIMD3(px, sim.groundedAnchorY(rotation: q, squash: sq), pz) }
        // blend to the grounded pose over the body's centre: lying, his middle is over the spot and no part of him is under the floor
        let g = sim.groundedAnchorY(rotation: q, squash: sq)
        let kk = smooth01(k)
        a.x += (px - a.x) * kk; a.z += (pz - a.z) * kk
        a.y = max(a.y, g)
        sim.attractor.anchor = a
        sim.attractor.strength = kPose
        poseW = 1
        skinner.setEyeOpenness(1 - 0.96 * smooth01(min(1, k * 1.6)))
        // feet: the rigid beans ride the body, arms stay the rest nubs
        armWalkWant = 0; armDirW = 0
        driveBeansRigid(sim, skinner, dt, tuck: 0)
        driveArms(sim, skinner, dt)
    }

    /// Back on his feet: hand the body to the normal pose path (feet re-seeded square under the root).
    private func sleepStand(_ sim: SoftBody, _ skinner: Skinner) {
        sleep.stage = 5; sleep.t = 0
        feetInit = false; feet.reset(); stepLive = false; walkFinal = false
        idleState.phase = 0; idleState.phaseT = 0
    }
}
