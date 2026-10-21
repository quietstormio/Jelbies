//
//  BlobBrain+FlapHop.swift
//  Lavender's chicken-like flap-hop (IdleKind.flapHop): the keyframes of lavender_flap_hop_s1.json (FeatureSpec.hop) played on the body the way the
//  jacks own it: a crouch, a springy launch, a short hover ~0.33 u up drifting 0.62 u forward, a plop and a settle. The wings' flap / spread come
//  from the same clock (FeatureSet reads `flapHop`); the feet dangle a little under him (beans lowered, kept fused to the belly by `attachBean`);
//  the arms stay the body-led nubs. Picked on its own urge every 25...40 s when he is happy / okay, awake, by day, not held / reserved / racing /
//  bedtime-locked, with floor room ahead; with the wings folded under a back item the plain happy bounce plays instead.
//

import Foundation
import simd

/// The running flap-hop (BlobBrain.flapHop): the clock, where it started and what the wings and feet do now.
struct FlapHopState {
    var active = false
    var t: Float = 0
    var from = SIMD2<Float>.zero, fwd = SIMD2<Float>(0, 1), yaw: Float = 0
    var flapDeg: Float = 0, spreadDeg: Float = 0
    var lift: Float = 0, dangle: Float = 0
    /// Seconds until the next flap-hop may start on its own.
    var urge: Float = 18
    var kicks = 0
    private(set) var count = 0
    mutating func began() { count += 1 }
}

extension BlobBrain {
    static let flapHopUrge: ClosedRange<Float> = 25...40
    /// The feet never dangle further than this below their stance (the attached-feet limits; the spec's 0.07 is clamped here).
    static let flapHopDangleMax: Float = 0.05

    /// Can a flap-hop start now (the scheduler and the reactions ask)?
    var flapHopAllowed: Bool {
        feature == .wings && !wingsFolded && (idleMood == .happy || idleMood == .okay) && idleNight < 0.5 && idleDeepNight < 0.5
            && !held && !race.active && !sleepLocked && attached && idleState.kind == nil
    }

    /// The scheduler hook (top of the idle pick): the urge timer (counted down every tick in `flapHopTick`); true = a flap-hop started.
    func flapHopMaybeStart(_ sim: SoftBody) -> Bool {
        guard feature == .wings else { return false }
        guard flapHop.urge <= 0, runMoveDemo == nil, flapHopAllowed, fastOthers() < 2 else { return false }
        let started = idleStart(.flapHop, sim)
        flapHop.urge = rand(Self.flapHopUrge.lowerBound, Self.flapHopUrge.upperBound)
        if started, anticsEnabled { kindCooldownStart(.flapHop) }
        return started
    }

    /// Starts the flap-hop from `idleStart`: faces where he is looking, needs the drift's worth of floor ahead. False = no room / the wings are folded.
    func flapHopBegin(_ sim: SoftBody) -> Bool {
        guard feature == .wings, !wingsFolded else { return false }
        let hop = FeatureSpec.shared.hop
        guard !hop.keyframes.isEmpty else { return false }
        let pose = sim.bodyPose(iterations: 6)
        let here = SIMD2(pose.centroid.x, pose.centroid.z)
        let u = SIMD2(sinf(yaw), cosf(yaw))
        let goal = here + u * hop.drift
        let rv = resolve(SIMD3(goal.x, 0, goal.y), footprint)
        let g2 = SIMD2(rv.x, rv.z)
        guard simd_distance(g2, goal) < 0.05, peerFree(g2), legClear(here, g2, margin: steerMargin) else { return false }
        idleBegin(.flapHop)
        sim.targets = []; beanHold = 0; feetInit = false; feet.reset(); stepLive = false
        gait.cancel(sim); gait.wander = false
        poseW = 0; poseOn = false
        flapHop.active = true; flapHop.t = 0; flapHop.from = here; flapHop.fwd = u; flapHop.yaw = yaw
        flapHop.flapDeg = 0; flapHop.spreadDeg = 0; flapHop.lift = 0; flapHop.dangle = 0; flapHop.kicks = 0
        flapHop.began()
        script = .idle; activity = .playing
        idleState.phase = 1; idleState.phaseT = 0
        AudioHub.shared.play(.jump, jelly: steerID, x: px, volume: 0.5)
        return true
    }

    /// One keyframe sample of the hop at `t` (smoothstep between keys).
    static func flapHopSample(_ hop: FeatureSpec.Hop, t: Float) -> FeatureSpec.HopKey {
        let k = hop.keyframes
        guard let first = k.first, let last = k.last else { return FeatureSpec.HopKey(t: 0, lift: 0, drift: 0, sy: 1, pitchDeg: 0, flap: 0, spread: 0, dangle: 0) }
        if t <= first.t { return first }
        if t >= last.t { return last }
        var i = 0
        while i + 1 < k.count && k[i + 1].t <= t { i += 1 }
        let a = k[i], b = k[min(i + 1, k.count - 1)]
        let span = max(b.t - a.t, 1e-4)
        let u = smooth01((t - a.t) / span)
        func mix(_ x: Float, _ y: Float) -> Float { x + (y - x) * u }
        return FeatureSpec.HopKey(t: t, lift: mix(a.lift, b.lift), drift: mix(a.drift, b.drift), sy: mix(a.sy, b.sy), pitchDeg: mix(a.pitchDeg, b.pitchDeg),
                                  flap: mix(a.flap, b.flap), spread: mix(a.spread, b.spread), dangle: mix(a.dangle, b.dangle))
    }

    /// The wing flap (deg) at `t`: the keyframe envelope with the stroke oscillation of the phase (lift / hover / decay), the pre-launch flutter,
    /// scaled to the range the worn items allow.
    static func flapHopFlap(_ hop: FeatureSpec.Hop, t: Float, env: Float, flapMax: Float) -> Float {
        let scale = max(0, min(1, flapMax / 75))
        var f = env
        if t >= hop.oscFrom && t <= hop.oscTo {
            let o: FeatureSpec.Osc = t < 0.9 ? hop.lift : (t < 2.6 ? hop.hover : hop.decay)
            // the down-stroke is faster than the up (60 / 40): a skewed cosine, +1 (tip up) -> -1 over 60 % of the stroke, back over 40 %
            let ph = (t * o.hz).truncatingRemainder(dividingBy: 1)
            let wave = ph < 0.6 ? cosf(.pi * ph / 0.6) : -cosf(.pi * (ph - 0.6) / 0.4)
            f = o.mean + o.amp * wave
        } else if t >= 0.1 && t <= 0.22 {
            f = env + 12 * sinf(2 * .pi * 12 * (t - 0.1))
        }
        return f * scale
    }

    /// Ticked each step while the flap-hop runs (true = this tick is fully handled).
    func flapHopTick(_ sim: SoftBody, _ skinner: Skinner, _ dt: Float) -> Bool {
        if flapHop.active, idleState.kind != .flapHop { flapHop.active = false }
        if feature == .wings, autonomy, !held, idleState.kind == nil, flapHop.urge > 0 { flapHop.urge -= dt }
        guard idleState.kind == .flapHop, flapHop.active, case .idle = script else { return false }
        let hop = FeatureSpec.shared.hop
        activity = .playing
        mouthOpen = 0
        flapHop.t += dt
        idleState.phaseT += dt
        let t = flapHop.t
        var k = Self.flapHopSample(hop, t: t)
        // the hover bobs a little
        if t > 0.9 && t < 2.6 { k.lift += 0.02 * sinf(2 * .pi * 2.6 * (t - 0.9)) * smooth01((t - 0.9) / 0.3) * smooth01((2.6 - t) / 0.3) }
        k.lift = max(0, min(hop.maxLift, k.lift))
        // body: the attractor like a hop (upright + the keyframe pitch, forward lean while lifted), squash sy, anchor on the floor + lift
        let hopGoal = -hopTipBack * attentionPitch * amplitude
        pitchBase += max(-1.2 * dt, min(1.2 * dt, hopGoal - pitchBase))
        let pitch = pitchBase + k.pitchDeg * .pi / 180
        let q = simd_quatf(angle: flapHop.yaw, axis: SIMD3<Float>(0, 1, 0)) * simd_quatf(angle: pitch, axis: SIMD3<Float>(1, 0, 0))
        let xz = flapHop.from + flapHop.fwd * k.drift
        sim.attractor.rotation = q
        sim.attractor.squash = k.sy
        sim.attractor.anchor = SIMD3(xz.x, sim.restCentroid.y * k.sy + k.lift + sim.floorY, xz.y)
        sim.attractor.strength = gait.kHop
        px = xz.x; pz = xz.y
        flapHop.lift = k.lift
        // wings and feet
        let fl = Self.flapHopFlap(hop, t: t, env: k.flap, flapMax: wingFlapMax)
        flapHop.flapDeg = fl
        flapHop.spreadDeg = max(k.spread * max(0, min(1, wingFlapMax / 75)), 0.4 * max(fl, 0))
        let dangle = min(k.dangle, Self.flapHopDangleMax) * (k.lift > 0.01 ? 1 : 0)
        flapHop.dangle = dangle
        flapHopFeet(sim, skinner, dt, dangle: dangle, lift: k.lift)
        armWalkWant = 0; armDirW = 0; armDirOut = 0
        driveArms(sim, skinner, dt)
        // beats: the plop and the settle wobble
        if flapHop.kicks == 0, t >= 3.33 { flapHop.kicks = 1; jellyKick = max(jellyKick, 2.4); AudioHub.shared.play(.squish, jelly: steerID, x: px, volume: 0.6) }
        if t >= hop.total {
            sim.attractor.strength = 0
            sim.targets = []
            gait.basePitch = 0
            flapHop.active = false; flapHop.flapDeg = 0; flapHop.spreadDeg = 0
            currentPose(sim)
            idleFinish(skinner)
        }
        return true
    }

    /// The largest flap the worn items allow now (GameCare sets `wingFlapMax` from the fit; 75 = free).
    var wingFlapMax: Float { wingFlapLimit }

    /// Feet in the air: the sim foot slab stays with the body (particle targets, as a hop's tuck does) and the rendered beans hang `dangle` below
    /// their stance, kept fused to the belly.
    private func flapHopFeet(_ sim: SoftBody, _ skinner: Skinner, _ dt: Float, dangle: Float, lift: Float) {
        let q = sim.attractor.rotation, sy = sim.attractor.squash, sxz = 1 / sy.squareRoot()
        let R = simd_float3x3(q), c0 = sim.restCentroid
        var list: [ParticleTarget] = []
        let simDrop = min(dangle, 0.03)
        for a in sim.appendages where a.kind == .foot {
            for p in a.particles {
                let o = sim.restPosition(p) - c0
                var w = sim.attractor.anchor + R * SIMD3<Float>(o.x * sxz, o.y * sy, o.z * sxz) + SIMD3<Float>(0, -simDrop, 0)
                w.y = max(w.y, sim.floorY)
                list.append(ParticleTarget(index: p, pos: w, stiffness: 60000))
            }
        }
        sim.targets = list
        guard beanFirstIdx.count == 2, geom.valid || { if !geom.valid { geom = FootGeom(sim: sim) }; return geom.valid }() else { return }
        prepareBeans(sim, skinner)
        guard footSkin.valid else { return }
        if beanScratch[0].count != FootBean.vertexCount { beanScratch = [[SIMD3<Float>](repeating: .zero, count: FootBean.vertexCount), [SIMD3<Float>](repeating: .zero, count: FootBean.vertexCount)] }
        footShift = [.zero, .zero]
        fillBeansRigid(sim, into: &beanScratch, tuck: -dangle)
        if lift > 0.01 {
            let pose = sim.bodyPose(iterations: 3)
            for s in 0..<2 { attachBean(sim, pose, lifted: true, &beanScratch[s]) }
        }
        commitBeans(sim, skinner, dt, want: true)
    }
}
