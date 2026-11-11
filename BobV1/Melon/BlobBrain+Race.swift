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
    /// Heading of the track at the start (world yaw; 0 = toward +z, the camera) and the lane's x there.
    var heading: Float = 0
    var laneX: Float = 0
    /// The course and his lane on it (Race/RaceCourse.swift): each step heads along the lane where he is. A straight from the start spot by default.
    var course = RaceCourse.puddle
    var lane = RaceTuning.playerLane
    /// His arc length along the course at the last step (the projection's starting guess).
    var lastS: Float = 0
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
    /// A hurdle jump was asked while a step was still under way: it starts the moment the feet are planted. `jumping`: the hop's apex / airtime are the race's.
    var jumpQueued = false
    var jumping = false
    // pull control (Race/RacePull.swift): none of this is touched by a taps race
    /// He has received a `.hop` event: his senses are the pull race's (a hop is crouch, air, landing; he may chain the next one from the landing).
    var pull = false
    /// He has crossed the line: no more hops; the coast steps are the taps race's.
    var pullDone = false
    /// A hop that arrived while a step was still under way (never at the start of a race): leaves when the feet are planted.
    var hopQueued: (length: Float, apex: Float, air: Float, crouch: Float)?
    /// A look-around asked while he was still in a landing: starts the moment he stands.
    var lookQueued = false
    /// Where the body really is while a hop carries it (the centroid read for the race's progress this tick); `spotLive` = valid.
    var spot = SIMD2<Float>.zero
    var spotLive = false
    /// The root's offset from the centroid at the first take-off from standing, eased out through the first hop (the camera's point must not jump).
    var spotOff = SIMD2<Float>.zero
}

extension BlobBrain {
    /// B1b (2026-11-11): while a pull racer's hop chain carries him, the brain's root (`px`, `pz`) follows the body each tick. The skin's jiggle (JellyJiggle.apply) displaces the skinned vertices by
    /// `twist x (vertex - root)` and `bulge x (vertex - root)`: with a root left behind at the first take-off (tens of metres by the end of a chain) the whole skin is pushed by decimetres, the
    /// skin's tail-landmark frame then disagrees with the brain's fit by up to 0.6 m / 1.1 rad, and the leash moves correctly placed feet. Taps races and the room are not touched.
    nonisolated(unsafe) static var raceChainRoot = true
    // (B1b tried "a chained hop takes off from the attractor's anchor on the lane" (takeoff: = anchor): no effect at all on the frame disagreement, the hits or the pace, so it is gone.)

    /// He can take one more committed step: nothing is waiting (one step ahead is the most; the feet start it the tick the last one ends).
    var raceStepFree: Bool {
        guard race.active else { return false }
        // pull control: a new hop can leave from the landing (the gait takes a hop in its land phase), not from the crouch or the air; none after the line
        if race.pull, case .hopPlay = script { return !race.pullDone && gait.phase == .land && race.stumbleT <= 0 }
        guard case .race = script else { return false }
        if race.pull, !race.pullDone, feet.active || race.lookQueued || race.hopQueued != nil { return false }
        return race.pendingFoot == nil && race.stumbleT <= 0
    }
    /// His feet are planted between two steps.
    var raceBetweenSteps: Bool {
        guard race.active else { return false }
        // pull control: on the ground the moment the hop touches down (the land phase), not when the landing is over
        if race.pull, case .hopPlay = script { return gait.phase == .land }
        guard case .race = script else { return false }
        return !feet.active && race.pendingFoot == nil && race.hopQueued == nil
    }
    /// He can start a look-around (a pause): racing, between steps.
    var raceCanLook: Bool {
        guard race.active, case .race = script else { return false }
        return !feet.active && race.pendingFoot == nil
    }
    /// Back on the track after a look-around (or never left).
    var raceBodyReady: Bool { race.active && idleState.kind == nil && !commanded && !race.lookQueued }

    /// Takes the track: stands square on lane `x`, facing `heading` (0 = toward the camera). With a `course` and `lane` his steps follow that lane
    /// round its bends; without, a straight along `heading` from where he stands (the drill, the parked Jellies, the tests).
    func startRace(sim: SoftBody, skinner: Skinner, heading: Float = 0, laneX x: Float, course: RaceCourse? = nil, lane: Int = RaceTuning.playerLane) {
        abortScript(sim, skinner)
        pending = nil; interruptScript = false
        race = RaceDrive(active: true, heading: heading, laneX: x)
        autonomy = false; idleBlocked = false
        runW = 0; zoomW = 0; hurry = false
        currentPose(sim)
        // the course after the pose: a straight from where he now STANDS (the pz the pre-course race measured progress from), so the straight's
        // progress is exactly pz - startZ
        if let course { race.course = course; race.lane = lane }
        else { race.course = RaceCourse.straight(from: SIMD2(x, pz), heading: heading, length: RaceTuning.length); race.lane = RaceTuning.playerLane }
        race.lastS = 0
        yaw = heading
        nextSwing = 0
        script = .race; activity = .walking
    }

    /// Leaves the track: the race script ends and he stands (he turns to the camera by himself).
    func endRace() {
        guard race.active else { return }
        if race.jumping { gait.hopApex = 0.10; gait.hopDuration = 0.26 }
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

    /// The hurdle jump: the EXISTING hop gait (crouch, air, land; the same squash, tuck and landing wobble as every other hop), made a little higher and
    /// longer (HurdleTuning), forward along the way he faces. It is the roaming hop's own start (`startHop`) minus its room-floor clamp: the track lies
    /// outside the room's walls, and the clamp would pull the hop back into the room. Nothing about the body's shape is new.
    func raceJump(_ sim: SoftBody) {
        guard race.active, case .race = script else { return }
        if feet.active { race.jumpQueued = true; return }
        race.jumpQueued = false
        AudioHub.shared.play(.jump, jelly: steerID, x: px, volume: 0.8)
        if Self.raceHopFeet, let sk = skinnerRef, sk.beansActive, sk.beanPos[0].count == FootBean.vertexCount, sk.beanPos[1].count == FootBean.vertexCount {          // (the drawn beans now: the hop's first frame must not pop them)
            raceCarryFrom = (0..<2).map { k in sk.beanPos[k].reduce(SIMD2<Float>.zero) { $0 + SIMD2($1.x, $1.z) } / Float(FootBean.vertexCount) }
            raceCarryT = Self.raceCarryTime
        }
        let takeoff = hopTakeoff()          // (before the feet are released: the root that stands him over the soles that are planted now)
        sim.targets = []; beanHold = 0; feetInit = false; feet.reset(); stepLive = false          // (as startHop: the planted soles are let go before the hop owns the body)
        gait.wander = false
        gait.facingYaw = yaw
        gait.home = SIMD2(px, pz)
        gait.hopApex = HurdleTuning.apex; gait.hopDuration = HurdleTuning.airTime
        race.jumping = true
        poseW = 0
        gait.hop(sim, to: (takeoff ?? SIMD2(px, pz)) + SIMD2(sinf(yaw), cosf(yaw)) * HurdleTuning.hopDistance, reduceMotion: amplitude < 0.7, takeoff: takeoff)
        script = .hopPlay; activity = .playing
    }

    /// Pull control: one hop of the race's chain. The EXISTING hop (`raceJump`'s: same feet release, bean carry, `.hopPlay`), with the numbers of the model's event:
    /// it lands on HIS LANE `length` further along than where the race measures him now, facing along the lane there; the crouch, flight and height are the event's.
    /// From a landing (the gait's land phase) the next hop starts right there: no return to the walk script, no second bean carry.
    func raceHop(_ sim: SoftBody, length: Float, apex: Float, air: Float, crouch: Float, sound: Bool = true) {
        guard race.active, !race.pullDone else { return }
        race.pull = true
        let chain: Bool
        if case .hopPlay = script, gait.phase == .land { chain = true }
        else if case .race = script {
            chain = false
            if feet.active || raceHopNeedsTurn(sim, length: length) { race.hopQueued = (length, apex, air, crouch); return }          // (`raceRun` starts it)
        } else { return }
        race.hopQueued = nil
        let s = raceProgress(sim: sim)          // (the progress the race was given this tick)
        let reduce = amplitude < 0.7
        let to = race.course.lanePoint(race.lane, at: s + length)
        if sound { AudioHub.shared.play(.jump, jelly: steerID, x: px, volume: 0.45) }
        var takeoff: SIMD2<Float>? = nil
        if !chain {
            if Self.raceHopFeet, let sk = skinnerRef, sk.beansActive, sk.beanPos[0].count == FootBean.vertexCount, sk.beanPos[1].count == FootBean.vertexCount {
                raceCarryFrom = (0..<2).map { k in sk.beanPos[k].reduce(SIMD2<Float>.zero) { $0 + SIMD2($1.x, $1.z) } / Float(FootBean.vertexCount) }
                raceCarryT = Self.raceCarryTime
            }
            takeoff = hopTakeoff()
            sim.targets = []; beanHold = 0; feetInit = false; feet.reset(); stepLive = false
            gait.wander = false
            poseW = 0; poseOn = false          // (poseOn too: from `raceRun` the same tick still runs `drivePose`, which would lift poseW again and `endHopPose` would not re-seat the root: the camera and the coast then run back to the stale root)
            race.jumping = true
            let c0 = sim.centroid()
            race.spotOff = SIMD2(px, pz) - SIMD2(c0.x, c0.z)          // (the camera's point eases from the root to the centroid)
        }
        gait.facingYaw = race.course.pose(at: s + length).heading          // (he stands facing along the lane at the landing point)
        gait.home = to                                                         // (the gait's own chained re-hop toward `home` has nowhere to go)
        // the gait's flight is `hopDuration` x 1.25 under Reduce Motion: divide it back so the body is in the air as long as the model says; a quarter of a step less,
        // because the gait counts whole steps (it lands on the first step at or after its time)
        gait.hopApex = apex; gait.hopDuration = air / (reduce ? 1.25 : 1) - 0.004
        // a short crouch (the gait's chained one: 0.4 x 0.13 = 0.052 s) when the model's is short
        gait.hop(sim, to: to, reduceMotion: reduce, chained: crouch < 0.1, takeoff: takeoff)
        script = .hopPlay; activity = .playing
    }

    /// On a curved course, from standing, he faces more than 0.5 rad away from the lane where the hop goes.
    private func raceHopNeedsTurn(_ sim: SoftBody, length: Float) -> Bool {
        guard !race.course.isStraight else { return false }
        let s = raceProgress(sim: sim)
        return abs(wrapAngle(race.course.pose(at: s + 0.5 * length).heading - yaw)) > 0.5
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
    func raceKeepAlive(dt: Float = 1.0 / 60) {
        // pull control: the stumble runs through the landing too (the hop script owns the pose then, `raceRun` does not run): the timer is counted here, and the
        // wobble's pulses go to the jelly's skin (`jellyKick`) while the landing lasts
        if race.active, race.pull, race.stumbleT > 0 {
            let before = race.stumbleT
            race.stumbleT = max(0, before - dt)
            if case .hopPlay = script, race.stumbleLen > 0 {
                let period: Float = 0.22, a = race.stumbleLen - before, b = race.stumbleLen - race.stumbleT
                if Int(b / period) > Int(a / period) { jellyKick = max(jellyKick, 1.8 * race.stumbleT / race.stumbleLen) }
            }
        }
        guard race.active, case .none = script, idleState.kind == nil, pending == nil else { return }
        if race.jumping { race.jumping = false; gait.hopApex = 0.10; gait.hopDuration = 0.26 }          // (the jump is over: the roaming hop's numbers again)
        script = .race; activity = .walking
        restTimer = 1.0
    }

    /// Puts a race event of this racer on the body (the race glue and the tests both use it).
    func raceApply(_ e: RaceEvent, sim: SoftBody) {
        switch e {
        case .step(_, let foot, let stride, let rate, let final): raceCommit(foot: foot, stride: stride, rate: rate, final: final)
        case .stumble, .trip: raceStumble(RaceTuning.stumbleTime)
        case .pauseBegan: if !raceLook(sim), race.pull { race.lookQueued = true }          // (in a landing: it starts when he stands)
        case .jump: raceJump(sim)
        case .hop(let r, let length, let apex, let air, let crouch, _, _): raceHop(sim, length: length, apex: apex, air: air, crouch: crouch, sound: r == RaceSim.playerIndex)
        case .finished: if race.pull { race.pullDone = true; race.hopQueued = nil; race.lookQueued = false }          // (the flight is finished, then he coasts with ordinary steps)
        default: break
        }
    }

    // MARK: the script

    /// `.race`, once per fixed step (BlobBrain.runScript): pose like the walk; start the committed step when the feet are free.
    func raceRun(_ sim: SoftBody, _ dt: Float) {
        if race.jumpQueued, !feet.active, race.pendingFoot == nil { raceJump(sim); return }
        if race.pull, race.lookQueued, raceCanLook, raceLook(sim) { race.lookQueued = false; return }
        poseOn = true; ensureFeet(sim)
        if feet.active { race.idle = 0 } else { race.idle += dt }
        if race.stumbleT > 0, !race.pull { race.stumbleT = max(0, race.stumbleT - dt) }          // (a pull racer's is counted in raceKeepAlive: it runs through the landing too)
        if !feet.active, race.stumbleT <= 0, let foot = race.pendingFoot {
            race.pendingFoot = nil
            raceStartStep(foot: foot, stride: race.pendingStride, rate: race.pendingRate, final: race.pendingFinal)
        }
        // pull control: a queued hop leaves when the feet are planted (on a bend, after turning on the spot until he faces within ~30 degrees of the lane: a hop
        // from the look-around's facing would swing the whole body round in 0.4 s)
        if race.pull, let q = race.hopQueued, !feet.active, race.pendingFoot == nil {
            if raceHopNeedsTurn(sim, length: q.length) {
                raceStartStep(foot: 1 - nextSwing, stride: 0.34, rate: 3.6, final: false)
            } else {
                raceHop(sim, length: q.length, apex: q.apex, air: q.air, crouch: q.crouch, sound: false)
                if race.hopQueued == nil { return }
            }
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

    /// One step of the locked gait along the lane: the stance foot's lead plus half a stride ahead (the walk's regular step), with the stride, rate
    /// and foot given by the race. Only the HEADING comes from the course: the lane's direction half a stride ahead of where he is, and a small
    /// drift back onto the lane's line. On a straight this is exactly the pre-course step (heading 0, drift toward laneX).
    private func raceStartStep(foot: Int, stride L: Float, rate: Float, final: Bool) {
        let root = SIMD2(px, pz)
        let at = race.course.progress(of: root, lane: race.lane, near: race.lastS)
        race.lastS = at
        let heading = race.course.pose(at: at + 0.5 * L).heading
        let u = SIMD2<Float>(sinf(heading), cosf(heading))
        let right = RaceCourse.right(race.course.pose(at: at).heading)
        nextSwing = foot
        let stance = 1 - foot
        let s = simd_dot(feet.pos[stance] - (root + rotXZ(geom.off[stance], yaw)), u)
        let m = turnRate * min(max(amplitude, 0.5), 1) * (1 / rate)
        let err = wrapAngle(heading - yaw)
        // a curved course only (the straight keeps the pre-course step to the bit): back from a look-around in a bend he can face far from the
        // lane (on the straight a look faces the camera, which IS the way he runs); a stride then would plant the swing foot out to his side, off
        // the body. So he turns on the spot first, feet under him, then strides.
        if !race.course.isStraight, abs(err) > 0.5 {
            race.steps += 1
            startStep(dyaw: max(-1.5 * m, min(1.5 * m, err)), peak: turnLift * amplitude, rate: rate)
            return
        }
        let dyaw = max(-m, min(m, err))
        // in a bend the reach and the sideways swing shorten a little with the turn of the step, so the feet stay fused to the egg (the body turns
        // under a foot in flight); zero on the straight, so its step is exactly the pre-course one
        let turnK: Float = race.course.isStraight ? 0 : min(1, abs(dyaw) / 0.1)
        var r = 0.5 * L * (1 - 0.2 * turnK), a: Float
        if final { a = max(0, s); r = 0 } else { a = min(max(s + r, 0.3 * L), 1.5 * L) }
        let drift = max(-0.04, min(0.04, -race.course.lateral(of: root, lane: race.lane, at: at) * 0.5))
        race.steps += 1
        startStep(rootD: u * a + right * drift, dyaw: dyaw, reach: u * r, peak: stepLift * amplitude, rate: rate, outScale: 0.6 * (1 - 0.6 * turnK))
    }

    /// How far he is along his lane now (arc length), and how far off its line (positive = to the right). For the glue's progress and the tests.
    var raceProgress: Float { race.course.progress(of: SIMD2(px, pz), lane: race.lane, near: race.lastS) }
    /// The same, measured for the race flow: through a hurdle jump (take-off to the end of the landing) the brain's own root (px, pz) is not moved by the hop
    /// (the hop carries the body, not the root), so the arc length is read from the body itself. Without this the race's distance stood still for the whole
    /// flight, the bar was "reached" only after the landing and every jump (rivals' too) counted as a hit.
    func raceProgress(sim: SoftBody) -> Float {
        guard race.jumping else {
            race.spotLive = false; race.spotOff = .zero
            let s = raceProgress
            if race.pull { race.lastS = s }
            return s
        }
        let c = sim.centroid()
        if race.pull, Self.raceChainRoot { px = c.x; pz = c.z }          // (see `raceChainRoot`)
        race.spotOff *= 0.9
        race.spot = SIMD2(c.x, c.z) + race.spotOff; race.spotLive = true
        let s = race.course.progress(of: race.spot, lane: race.lane, near: race.lastS)
        if race.pull { race.lastS = s }          // (a hop is a long way for the projection's tie-break: keep it current)
        return s
    }
    /// Where the body really is on the ground (the camera follows it): the centroid read for the race's progress while a hop carries it (the root `px`, `pz` is not moved by a hop), else the root.
    var raceSpot: SIMD2<Float> { race.spotLive && race.jumping ? race.spot : SIMD2(px, pz) }
    var raceLateral: Float { race.course.lateral(of: SIMD2(px, pz), lane: race.lane, at: raceProgress) }
}
