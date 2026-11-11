//
//  SeesawRide.swift
//  The Park seesaw's ride (2026-11-11, branch park-seesaw-r1): the Jelbies SIT on its two cushions facing each other across the plank, get on while it is level and still, ride a calm
//  plank motion that both seats share by construction (ONE angle for the piece), and get off while it is level and still again. Everything specific to the seesaw lives here:
//    SeesawTuning   the constants, the contract geometry (model units, the piece is drawn at DecorKind.scale 1.4), the derived amplitude A, the bumper press
//    SeesawRide     the plank's motion and the ride's state per seesaw uid (a small state machine fed by the riders' reports), the seat frame
//    BlobBrain+     the rider's side: getting on (stage 0 / the hop), the seated pose, getting off (stage 3), each with a hop that never travels over 0.8 m
//  The hooks in BlobBrain+Decor.swift (runBagSit, bagBodyTick) call straight in here; DecorField.tick advances the ride; DecorField.seatWorld reads the seat frame.
//

import Foundation
import simd

nonisolated enum SeesawTuning {
    // MARK: the look of the ride
    /// Each rider is turned this far from facing across the plank toward the camera, so his face reads (a constant: the lead compares 0 and 25 degrees in captures).
    static let faceTurn: Float = 25 * .pi / 180
    /// How much of the plank's angle the body leans with (about the world z axis, split into his own pitch and roll by the way he faces).
    static let leanShare: Float = 0.6
    /// Extra lift of the body's seat above the cushion's top (world units), the knob for the per-species seat height if the skin test asks for one.
    static let seatLift: Float = 0

    // MARK: the plank's motion
    /// One full swing (up and back down) in seconds.
    static let period: Float = 2.3
    /// theta = A * amp * s(phi), phi running with the period: a sine with a slightly flat top (a short dwell at each end). Max of s is 1.
    static func shape(_ phi: Float) -> Float { (sinf(phi) + sinf(3 * phi) / 9) * 9 / 8 }
    static func shapeRate(_ phi: Float) -> Float { (cosf(phi) + cosf(3 * phi) / 3) * 9 / 8 }

    // MARK: the timeline (seconds)
    static let settle: Float = 0.4            // seated alone: still this long before the gentle bounce
    static let soloAmp: Float = 0.25          // the gentle bounce alone
    static let soloRamp: Float = 1.0
    static let comerEase: Float = 0.5         // the seated one eases to level when a second rider is coming
    static let pairBeat: Float = 0.3          // after the second landing, before the ride ramps up
    static let rideRamp: Float = 1.5
    static let endRamp: Float = 2.0           // the plank arrives level and still within one period (2.3 s)
    static let endBeat: Float = 0.3
    static let hopGap: Float = 0.3            // the second rider hops off this long after the first
    static let callAwayEase: Float = 0.6      // one rider called away mid-ride: the plank eases to level this fast
    static let swings: ClosedRange<Float> = 5...8
    static let soloHold: ClosedRange<Float> = 7...12
    static let levelTol: Float = 0.01         // "level and still": |theta| below this (and amp exactly 0)
    /// No hop on or off this piece travels farther than this over the floor (metres).
    static let maxHop: Float = 0.8
    /// The brain's hold timer while on the seesaw: huge on purpose. The idle code sets `hold` to 0 to end a sit (come-here, feeding, a request): that is how a call-away is told.
    static let holdMarker: Float = 1e6
    /// How far the feet slide forward on the cushion when he sits down (world units; the beanbag's is 0.27: the handle is in front of him here).
    static let footReach: Float = 0.2
    /// The seated rider's turn toward a comer (rad, at most) and the pose's squash is the ordinary sit's.
    static let lookMax: Float = 0.3

    // MARK: the contract (model units; x along the plank, y up, z toward the camera)
    static let pivotY: Float = 0.34
    static let undersideBelowPivot: Float = 0.015          // beam underside y 0.325
    static let beamHalf = SIMD3<Float>(1.05, 0.045, 0.17)
    static let beamCentreY: Float = 0.37
    static let cushionX: Float = 0.62, cushionHalf = SIMD3<Float>(0.35, 0.03, 0.20), cushionCentreY: Float = 0.445          // x 0.27...0.97, flat top y 0.475
    static let seatX: Float = 0.66, seatTopY: Float = 0.475
    static let handleX: Float = 0.20, handleTopY: Float = 0.636, handleBarHalfZ: Float = 0.136, handleBarHalfX: Float = 0.035
    static let bumperX: Float = 0.96, bumperRadius: Float = 0.10, bumperRest: Float = 0.11
    /// The bumper's apex stays this far under the plank's underside while pressed: the dome's flank is not flat, so a tilted plank touches it a little off its centre line.
    static let bumperClearance: Float = 0.0015
    static let pressedFraction: Float = 0.77

    /// The plank's underside height (model units) straight above world x `xb` (model units, about the piece's centre) when the plank is tilted by `theta` (about z; positive raises +x).
    /// The underside line is 0.015 below the pivot line: a point (xl, -0.015) turned by theta about the pivot lands at x = xl cos t + 0.015 sin t, y = xl sin t - 0.015 cos t, so over
    /// world x = xb the underside is y = pivot + xb tan t - 0.015 / cos t. (For the +x end going down, t = -a: y = 0.34 - 0.96 tan a - 0.015 / cos a.)
    static func undersideY(atX xb: Float, theta t: Float) -> Float { pivotY + xb * tanf(t) - undersideBelowPivot / cosf(t) }

    /// The tilt at which the plank's underside first touches the bumper's rest top (0.11) over its centre line: about 0.220 rad.
    static let touchAngle: Float = solveAngle(height: bumperRest)
    /// A: the tilt at which the bumper is pressed down to 77 % of its height (0.0847): about 0.245 rad. The ride's amplitude, derived from the contract numbers above:
    /// y(a) = 0.34 - 0.96 tan a - 0.015 / cos a falls with a, so a bisection on y(a) = 0.77 * 0.11 finds it.
    static let amplitude: Float = solveAngle(height: pressedFraction * bumperRest)
    private static func solveAngle(height h: Float) -> Float {
        var lo: Float = 0, hi: Float = 0.6
        for _ in 0..<60 {
            let mid = (lo + hi) / 2
            if undersideY(atX: bumperX, theta: -mid) > h { lo = mid } else { hi = mid }
        }
        return (lo + hi) / 2
    }
    /// Bumper apex height (model units) for one end (side -1 = -x, +1 = +x) at plank angle `theta`: rest height, pressed down so the apex stays just under the plank.
    static func bumperTop(side: Float, theta: Float) -> Float {
        let under = undersideY(atX: side * bumperX, theta: theta)
        return max(0.02, min(bumperRest, under - bumperClearance))
    }

    /// The cushion's top at a seat, piece-local, WORLD units (the drawn piece is scaled by `DecorKind.seesaw.scale`): the seat point turned about the pivot by theta.
    static func seatLocal(seat: Int, theta t: Float) -> SIMD3<Float> {
        let k = DecorKind.seesaw.scale
        let sx: Float = seat == 0 ? -1 : 1
        let px = sx * seatX * k, py = (seatTopY - pivotY) * k
        let c = cosf(t), s = sinf(t)
        return SIMD3(px * c - py * s, pivotY * k + px * s + py * c + seatLift, 0)
    }
    /// A world point (piece-local x, y, z, world units) in the plank's own frame, model units: the inverse of the tilt about the pivot.
    static func toPlank(_ p: SIMD3<Float>, theta t: Float) -> SIMD3<Float> {
        let k = DecorKind.seesaw.scale
        let x = p.x / k, y = p.y / k - pivotY, z = p.z / k
        let c = cosf(-t), s = sinf(-t)
        return SIMD3(x * c - y * s, pivotY + x * s + y * c, z)
    }
}

/// A smooth change of a value that starts from the value AND its rate (a cubic Hermite to the target with zero end rate): the plank's angle and its rate stay continuous
/// through every change of mind, and the target is reached exactly.
nonisolated struct SeesawRamp {
    var a0: Float = 0, v0: Float = 0, a1: Float = 0, dur: Float = 0.001, t: Float = 0
    mutating func start(from value: Float, rate: Float, to target: Float, over d: Float) { a0 = value; v0 = rate; a1 = target; dur = max(d, 0.001); t = 0 }
    mutating func advance(_ dt: Float) { t = min(t + dt, dur) }
    var value: Float {
        if t >= dur { return a1 }
        let u = t / dur, u2 = u * u, u3 = u2 * u
        let h00 = 2 * u3 - 3 * u2 + 1, h10 = u3 - 2 * u2 + u, h01 = -2 * u3 + 3 * u2
        return min(max(h00 * a0 + h10 * dur * v0 + h01 * a1, 0), 1)
    }
    var rate: Float {
        if t >= dur { return 0 }
        let u = t / dur, u2 = u * u
        let d00 = 6 * u2 - 6 * u, d10 = 3 * u2 - 4 * u + 1, d01 = -6 * u2 + 6 * u
        return (d00 * a0 + d10 * dur * v0 + d01 * a1) / dur
    }
}

@MainActor
final class SeesawRide {
    static let shared = SeesawRide()
    nonisolated deinit {}          // (a main-actor deinit crashes the Release test host)

    /// What a rider reports each step. coming = walking to his stand spot / turning / waiting for his hop; boarding = the hop up and the sitting down; seated = settled on the cushion;
    /// leaving = getting up (the plank must be still unless he was called away); hopOff = in the hop down.
    enum Stage { case coming, boarding, seated, leaving, hopOff }
    enum Mode { case idle, solo, easing, pairBeat, pairRide, ending, endBeat, leaving, callAway }

    struct Rider {
        var stage: Stage = .coming
        var seatedT: Float = 0
        var hopT: Float = 0
        var forced = false
        var look: Float = 0
        var prevH: Float = 0, rising = false, topFlag = false
    }
    struct Ride {
        var phi: Float = 0
        var ramp = SeesawRamp()
        var amp: Float = 0, ampRate: Float = 0, target: Float = 0
        var theta: Float = 0, thetaRate: Float = 0
        var riders: [Int: Rider] = [:]
        var mode: Mode = .idle
        var modeT: Float = 0
        var swingsDone = 0, swingsTarget = 6
        var soloHold: Float = 9
        var order: [Int] = []
        var rng: UInt64 = 0x2545F4914F6CDD1D
        mutating func rnd(_ r: ClosedRange<Float>) -> Float {
            rng ^= rng << 13; rng ^= rng >> 7; rng ^= rng << 17
            return r.lowerBound + (r.upperBound - r.lowerBound) * Float(rng >> 40) / Float(1 << 24)
        }
    }
    private(set) var rides: [Int: Ride] = [:]

    func reset() { rides = [:] }
    func theta(_ uid: Int) -> Float { rides[uid]?.theta ?? 0 }
    func thetaRate(_ uid: Int) -> Float { rides[uid]?.thetaRate ?? 0 }
    func amp(_ uid: Int) -> Float { rides[uid]?.amp ?? 0 }
    func mode(_ uid: Int) -> Mode { rides[uid]?.mode ?? .idle }
    func stage(_ uid: Int, seat: Int) -> Stage? { rides[uid]?.riders[seat]?.stage }
    /// Level and still: nothing moves the seats.
    func still(_ uid: Int) -> Bool { guard let r = rides[uid] else { return true }; return r.amp == 0 && abs(r.theta) < SeesawTuning.levelTol }

    // MARK: the riders' side

    func report(_ uid: Int, _ seat: Int, _ stage: Stage, forced: Bool? = nil) {
        var r = rides[uid] ?? Ride()
        var rd = r.riders[seat] ?? Rider()
        if rd.stage != stage { rd.stage = stage; rd.seatedT = 0; rd.hopT = 0 }
        if let f = forced { rd.forced = f }
        r.riders[seat] = rd
        rides[uid] = r
    }
    /// His hop up may start: the plank is level and still, and nobody else is in a hop or getting up on it.
    func mayHopOn(_ uid: Int, _ seat: Int) -> Bool {
        guard let r = rides[uid] else { return true }
        if r.amp != 0 || abs(r.theta) >= SeesawTuning.levelTol { return false }
        switch r.mode { case .ending, .endBeat, .leaving, .callAway: return false; default: break }
        return !r.riders.contains { $0.key != seat && ($0.value.stage == .boarding || $0.value.stage == .leaving || $0.value.stage == .hopOff) }
    }
    /// A seated rider may get up now (normal end of the ride: the plank is still and the order and the 0.3 s gap are kept).
    func mayLeave(_ uid: Int, _ seat: Int) -> Bool {
        guard let r = rides[uid], let rd = r.riders[seat] else { return true }
        if rd.forced { return true }
        guard r.mode == .leaving, r.amp == 0, abs(r.theta) < SeesawTuning.levelTol, let i = r.order.firstIndex(of: seat) else { return false }
        return r.modeT >= (i == 0 ? 0 : SeesawTuning.hopGap)
    }
    /// The top of a swing for this seat happened since the last call (a small happy vocal).
    func takeTop(_ uid: Int, _ seat: Int) -> Bool {
        guard var r = rides[uid], var rd = r.riders[seat], rd.topFlag else { return false }
        rd.topFlag = false; r.riders[seat] = rd; rides[uid] = r
        return true
    }
    /// Eases the rider's look toward a comer (0...1) and returns it.
    func lookStep(_ uid: Int, _ seat: Int, want: Float, dt: Float) -> Float {
        guard var r = rides[uid], var rd = r.riders[seat] else { return 0 }
        rd.look += max(-dt / 0.5, min(dt / 0.5, want - rd.look))
        r.riders[seat] = rd; rides[uid] = r
        return rd.look
    }

    // MARK: the plank (called once per step by DecorField.tick)

    /// Advances the ride one step; true while the piece needs its mesh rebuilt (it moves, or somebody is on it).
    @discardableResult
    func tick(_ uid: Int, dt: Float, field: DecorField) -> Bool {
        rides = rides.filter { field.anim[$0.key] != nil }
        var r = rides[uid] ?? Ride()
        let occ = Set((field.seatOccupant[uid] ?? [:]).keys)
        r.riders = r.riders.filter { occ.contains($0.key) }
        for s in occ where r.riders[s] == nil { r.riders[s] = Rider() }
        for s in Array(r.riders.keys) {
            if r.riders[s]!.stage == .seated { r.riders[s]!.seatedT += dt }
            if r.riders[s]!.stage == .hopOff { r.riders[s]!.hopT += dt }
        }
        r.modeT += dt
        let seated = r.riders.filter { $0.value.stage == .seated }.keys.sorted()
        let comers = r.riders.filter { $0.value.stage == .coming || $0.value.stage == .boarding }
        let leavers = r.riders.filter { $0.value.stage == .leaving || $0.value.stage == .hopOff }
        let forced = leavers.contains { $0.value.forced }
        let level = r.amp == 0 && abs(r.theta) < SeesawTuning.levelTol

        func want(_ a: Float, _ d: Float) {
            if abs(r.target - a) > 1e-4 { r.ramp.start(from: r.amp, rate: r.ampRate, to: a, over: d); r.target = a }
        }
        func go(_ m: Mode) { if r.mode != m { r.mode = m; r.modeT = 0 } }

        if forced {
            // one rider called away: the leaver goes at once; the plank eases level (0.6 s)
            go(.callAway); want(0, SeesawTuning.callAwayEase)
        } else {
            if r.mode == .callAway { go(.idle) }
            switch r.mode {
            case .ending:
                want(0, SeesawTuning.endRamp)
                if level { go(.endBeat) }
            case .endBeat:
                if r.modeT >= SeesawTuning.endBeat {
                    go(.leaving)
                    r.order = seated
                    if r.order.count == 2, r.rnd(0...1) < 0.5 { r.order.reverse() }
                }
            case .leaving:
                // (over when nobody is seated or on his way out: a rider who has taken a seat meanwhile is a comer for the next ride)
                if !r.riders.values.contains(where: { $0.stage == .seated || $0.stage == .leaving || $0.stage == .hopOff }) { go(.idle) }
            default:
                if r.riders.isEmpty { go(.idle); want(0, SeesawTuning.callAwayEase) }
                else if !comers.isEmpty && !seated.isEmpty { go(.easing); want(0, SeesawTuning.comerEase) }
                else if seated.count == 2 {
                    if r.mode != .pairBeat && r.mode != .pairRide { go(.pairBeat) }
                    if r.mode == .pairBeat, r.modeT >= SeesawTuning.pairBeat, level, r.riders.values.allSatisfy({ $0.seatedT >= SeesawTuning.pairBeat }) {
                        go(.pairRide); r.swingsDone = 0; r.swingsTarget = Int(r.rnd(SeesawTuning.swings).rounded())
                        want(1, SeesawTuning.rideRamp)
                    }
                    if r.mode == .pairRide, r.swingsDone >= r.swingsTarget { go(.ending); want(0, SeesawTuning.endRamp) }
                } else if seated.count == 1 && comers.isEmpty && leavers.isEmpty {
                    if r.mode != .solo { go(.solo); r.soloHold = r.rnd(SeesawTuning.soloHold); r.swingsDone = 0 }
                    if r.modeT >= SeesawTuning.settle, r.riders[seated[0]]!.seatedT >= SeesawTuning.settle { want(SeesawTuning.soloAmp, SeesawTuning.soloRamp) }
                    if r.modeT >= r.soloHold { go(.ending); want(0, SeesawTuning.endRamp) }
                } else if seated.isEmpty { want(0, SeesawTuning.comerEase) }
            }
        }

        // the motion
        r.phi += 2 * .pi / SeesawTuning.period * dt
        if r.phi >= 2 * .pi { r.phi -= 2 * .pi; if r.mode == .pairRide { r.swingsDone += 1 } }
        r.ramp.advance(dt)
        r.amp = r.ramp.value; r.ampRate = r.ramp.rate
        let A = SeesawTuning.amplitude, w = 2 * Float.pi / SeesawTuning.period
        let sv = SeesawTuning.shape(r.phi)
        r.theta = r.amp == 0 ? 0 : A * r.amp * sv
        r.thetaRate = A * (r.ampRate * sv + r.amp * SeesawTuning.shapeRate(r.phi) * w)

        // the top of a swing for each seated rider (his end is up when sign * theta peaks)
        for s in seated {
            var rd = r.riders[s]!
            let h = (s == 0 ? -1 : 1) * r.theta
            let rising = h > rd.prevH
            if rd.rising && !rising && r.amp > 0.5 && h > 0.6 * A * r.amp { rd.topFlag = true }
            rd.rising = rising; rd.prevH = h
            r.riders[s] = rd
        }
        rides[uid] = r
        return r.amp > 0 || r.theta != 0 || !r.riders.isEmpty
    }
}

// MARK: - the rider (BlobBrain)

extension BlobBrain {
    /// His yaw on seat `idleState.seat`: facing across the plank, turned `faceTurn` toward the camera.
    func seesawFacing(_ f: DecorFoot) -> Float {
        let sp = f.kind.sitPoints[min(idleState.seat, f.kind.sitPoints.count - 1)]
        let base = (sp.x < 0 ? 1 : -1) * Float.pi / 2 + f.yaw
        let d = wrapAngle(faceCameraYaw() - base)
        return wrapAngle(base + (d >= 0 ? 1 : -1) * min(SeesawTuning.faceTurn, abs(d)))
    }
    /// The seat's neutral spot (xz) and the seat's height now (the plank is level when he hops on).
    func seesawNeutral(_ f: DecorFoot) -> (xz: SIMD2<Float>, y: Float) {
        let sp = f.kind.sitPoints[min(idleState.seat, f.kind.sitPoints.count - 1)]
        let sw = DecorField.shared.seatWorld(f.uid, seat: idleState.seat) ?? SIMD3(f.centre.x, f.spec.height, f.centre.y)
        return (f.centre + f.turned(SIMD2(sp.x, sp.z)), sw.y)
    }
    /// The spots in front of his seat he hops from and to: straight in front first, then a little to either side. Every one is within `maxHop` of the seat point
    /// (the footprint's half depth is 0.28, the stand gap 0.42: 0.70 straight in front, 0.73 at 0.2 to the side).
    func seesawStandSpots(_ f: DecorFoot, seat: Int) -> [SIMD2<Float>] {
        let sp = f.kind.sitPoints[min(seat, f.kind.sitPoints.count - 1)]
        let dz = f.kind.spec.half.y - sp.z + Self.bagHopGap
        return [Float(0), 0.2, -0.2].map { f.centre + f.turned(SIMD2(sp.x + $0, sp.z + dz)) }
    }
    /// The first of those a body can stand on and no friend stands near, nearest to the seat first.
    func seesawFreeSpot(_ f: DecorFoot, seat: Int, from here: SIMD2<Float>) -> SIMD2<Float>? {
        let ignore = decorIgnore
        defer { decorIgnore = ignore }
        let sp = f.kind.sitPoints[min(seat, f.kind.sitPoints.count - 1)]
        let seatXZ = f.centre + f.turned(SIMD2(sp.x, sp.z))
        for p in seesawStandSpots(f, seat: seat) where simd_distance(p, seatXZ) <= SeesawTuning.maxHop - 0.02 {
            let q = fixed(p)
            if simd_distance(p, q) < 0.05, peerFree(q) { return p }
        }
        return nil
    }

    /// `runBagSit` for the seesaw: stage 0 (turn across the plank, wait for the plank to be still, hop up) and stage 2 (sit down, ride, get up, hop off).
    func seesawRunBagSit(_ sim: SoftBody, _ skinner: Skinner, _ dt: Float, _ f: DecorFoot) {
        let R = SeesawRide.shared, uid = f.uid, seat = idleState.seat
        if idleState.bagStage >= 1, poseW <= 0 { let cen = sim.centroid(); px = cen.x; pz = cen.z }
        switch idleState.bagStage {
        case 0:
            R.report(uid, seat, .coming)
            idleState.goalYaw = seesawFacing(f)
            let turning = turnSteps(goal: idleState.goalYaw, tol: 0.08)
            gaitPose(sway: 0.04, bob: 0.0, rock: 0.2)
            guard !turning, !feet.active, idleState.phaseT > 0.1 else { return }
            let g = seesawNeutral(f)
            // a hop never travels over maxHop: from farther (a walk that ended short, or the far side spot the generic stand picker may give) he walks to the near spot first
            if simd_distance(position, g.xz) > SeesawTuning.maxHop {
                if idleState.decorRetry < Self.standRetries + 3, let spot = seesawFreeSpot(f, seat: seat, from: position) {
                    idleState.decorRetry += 1
                    idleState.target = spot; idleState.decorGo = true
                    scriptT = 0; stuckT = 0; bestDist = .infinity; route = []; steerStall = 0
                    script = .walk(target: spot, then: .none); activity = .walking
                } else if idleState.phaseT > 6 { idleFinish(skinner) }
                return
            }
            // the plank must be level and still (and nobody else in a hop), else he waits at his spot (up to 14 s)
            guard R.mayHopOn(uid, seat) else { if idleState.phaseT > 14 { idleFinish(skinner) }; return }
            // the seat must be clear of anyone walking past (the other seat's rider, seated or on his way, and a sit-together partner do not count)
            let here = position
            let others = socialOthers().filter { o in o !== self && !(o.idleState.kind == .decorSit && o.idleState.decorUID == f.uid) && !(social.map { $0.a === o || $0.b === o } ?? false) }
            let crowded = others.contains { o in
                if simd_distance(o.position, g.xz) < peerGap { return true }
                let d = g.xz - here, l2 = simd_length_squared(d)
                let t = l2 > 1e-6 ? max(0, min(1, simd_dot(o.position - here, d) / l2)) : 0
                return simd_distance(o.position, here + d * t) < peerGap * 0.6
            }
            if crowded { if idleState.phaseT > 3 { idleFinish(skinner) }; return }
            idleState.bagStage = 1; idleState.phaseT = 0; idleState.decorBooped = false
            R.report(uid, seat, .boarding)
            bagHop(sim, to: g.xz, ground: g.y, apex: Self.bagApexUp, facing: idleState.goalYaw)
        case 2:
            seesawSeated(sim, skinner, dt, f)
        default: break
        }
    }

    /// Stage 2: sit down (the ordinary sit, a little shorter reach), ride, get up, hop off.
    private func seesawSeated(_ sim: SoftBody, _ skinner: Skinner, _ dt: Float, _ f: DecorFoot) {
        let R = SeesawRide.shared, uid = f.uid, seat = idleState.seat
        var k = idleState.k
        let phT = idleState.phaseT
        let forced = idleState.hold < SeesawTuning.holdMarker * 0.5          // (the idle code zeroed the hold: a request, a feeding, a come-here, a yield)
        switch idleState.phase {
        case 1:
            R.report(uid, seat, .boarding)
            k = smooth01(phT / 1.15)
            if !feet.active && idleState.steps < 2 && phT > Float(idleState.steps) * 0.35 { idleFootStep(reach: SeesawTuning.footReach); idleState.steps += 1 }
            if forced { idleState.phase = 3; idleState.phaseT = 0; idleState.steps = 0 }
            else if phT >= 1.15 && !feet.active { idleState.phase = 2; idleState.phaseT = 0 }
        case 2:
            k = 1
            R.report(uid, seat, .seated, forced: false)
            if forced { R.report(uid, seat, .leaving, forced: true); idleState.phase = 3; idleState.phaseT = 0; idleState.steps = 0 }
            else if R.mayLeave(uid, seat) { R.report(uid, seat, .leaving); idleState.phase = 3; idleState.phaseT = 0; idleState.steps = 0 }
        default:
            R.report(uid, seat, .leaving, forced: forced ? true : nil)
            let dur: Float = forced ? 0.5 : 0.9
            k = min(k, 1 - smooth01(phT / dur))
            if !feet.active && idleState.steps < 2 && phT > Float(idleState.steps) * 0.25 { idleFootStep(reach: 0); idleState.steps += 1 }
            if phT >= dur && !feet.active && idleState.steps >= 2 {
                // a spot within maxHop of where he is, nobody near it; a called-away one waits at most 2 s for one, then takes the front spot
                var goal = seesawFreeSpot(f, seat: seat, from: position)
                if goal == nil, forced, phT > dur + 2 { goal = seesawStandSpots(f, seat: seat)[0] }
                if let goal {
                    idleState.k = 0; sitPose(skinner, 0, slump: false)
                    idleState.bagStage = 3; idleState.phaseT = 0
                    R.report(uid, seat, .hopOff)
                    bagHop(sim, to: goal, ground: 0, apex: Self.bagApexDown + max(0, seesawNeutral(f).y - 0.45) * 0.3)
                    return
                }
            }
        }
        idleState.k = k
        gaitPose(sway: 0.04, bob: 0.0, rock: 0.2)
        sitPose(skinner, k, slump: false)
        pitch += 0.13 * k          // (the ordinary sit leans back into a backrest: here he sits upright)
        skinner.setEyeOpenness(1 - 0.1 * k)
        seesawRidePose(f, k: k)
    }

    /// The seated rider's motion with the plank: carried by the seat (no lag), leaning with it, a happy face, a happy chirp at the top, a look toward a comer.
    private func seesawRidePose(_ f: DecorFoot, k: Float) {
        let R = SeesawRide.shared, uid = f.uid, seat = idleState.seat
        seatFollow(f)
        // the plank turns about the world z axis; for a body facing `yaw` that is pitch = -share * theta * sin(yaw), roll = share * theta * cos(yaw)
        let th = R.theta(uid)
        pitch += -SeesawTuning.leanShare * th * sinf(yaw) * k
        roll += SeesawTuning.leanShare * th * cosf(yaw) * k
        // looks toward a comer (the other seat's rider on his way) a little
        var want: Float = 0, bearing: Float = 0
        if let o = socialOthers().first(where: { $0 !== self && $0.idleState.kind == .decorSit && $0.idleState.decorUID == uid && ($0.idleState.bagStage < 2 || ($0.idleState.bagStage == 2 && $0.idleState.phase == 1)) }) {
            want = 1
            bearing = max(-SeesawTuning.lookMax, min(SeesawTuning.lookMax, wrapAngle(atan2f(o.px - px, o.pz - pz) - yaw)))
        }
        twist = bearing * R.lookStep(uid, seat, want: want, dt: runDt) * k
        // happy while riding
        idleState.slideS -= runDt
        if idleState.slideS <= 0, idleState.phase == 2, R.amp(uid) > 0.05 { face(.happy, hold: 2.0); idleState.slideS = 1.8 }
        if R.takeTop(uid, seat), !voiceMuted, rand() < 0.6 { AudioHub.shared.chirp(jelly: steerID, .happy, x: px, src: "seesaw") }
    }

    /// `bagBodyTick` for the seesaw: the two hops (up, down) own the body like the bounce. Same as the ordinary tick, with the ride's reports and no seat kick.
    func seesawBodyTick(_ sim: SoftBody, _ skinner: Skinner, _ dt: Float) -> Bool {
        guard isBagSit, idleState.bagStage == 1 || idleState.bagStage == 3, case .idle = script else { return false }
        let uid = idleState.decorUID, seat = idleState.seat
        activity = .playing
        mouthOpen = 0
        idleState.phaseT += dt
        let hopGoal: Float = -hopTipBack * attentionPitch * amplitude
        pitchBase += max(-1.2 * dt, min(1.2 * dt, hopGoal - pitchBase))
        gait.basePitch = pitchBase
        gait.tick(sim, held: false, reduce: amplitude < 0.7)
        if poseW <= 0 { let cen = sim.centroid(); px = cen.x; pz = cen.z }
        if idleState.bagStage == 1 {
            SeesawRide.shared.report(uid, seat, .boarding)
            if gait.phase == .land, !bagFloorOn {
                // landed ON the level seat: his floor is the seat's top from now on
                bagFloorOn = true
                applyBagFloor(sim, skinner)
                if !idleState.decorBooped { idleState.decorBooped = true; AudioHub.shared.play(.beanbagSit, jelly: steerID, x: px) }
            }
            if bagFloorOn { decorSitPress(uid, 0.5) }
        } else {
            SeesawRide.shared.report(uid, seat, .hopOff)
            decorSitPress(uid, gait.phase == .crouch ? 1 : 0)
            if gait.phase == .air || gait.phase == .land { bagFloorOn = false; applyBagFloor(sim, skinner) }
        }
        armWalkWant = 1
        let flap = sinf(2 * .pi * 5 * idleState.phaseT)
        armDirW = 1; armDirEl = [0.45 + 0.1 * flap, 0.45 - 0.1 * flap]; armDirSa = [0.1, 0.1]; armDirOut = 0.05
        driveBeansRigid(sim, skinner, dt, tuck: gait.tuck)
        driveArms(sim, skinner, dt)
        if !gait.isBusy {
            gait.basePitch = 0
            gait.hopApex = 0.10; gait.hopDuration = 0.26
            currentPose(sim)
            armDirW = 0; armDirOut = 0
            if idleState.bagStage == 1 {
                idleState.bagStage = 2; idleState.phaseT = 0; idleState.phase = 1; idleState.steps = 0; idleState.k = 0
                idleState.seatShift = .zero
                script = .idle; activity = .lookingAround
                idleState.hold = SeesawTuning.holdMarker
                idleState.slideS = 0
            } else {
                idleFinish(skinner)
            }
        }
        return true
    }
}
