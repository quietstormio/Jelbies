//
//  BlobBrain+Touch.swift
//  Touch play in focus mode: the reaction side of PET (a sliding dent that follows the finger, then a happy Bob: closed eyes, a lean
//  into the finger, a slow jiggle, hearts) and the haptic hooks. The press contact itself lives in SoftBody (`setPress`: a fingertip sphere,
//  collision only, so it never drags him). Everything is released afterwards: with no finger down and the reactions faded, the brain's own
//  pose, the eyes and the sim contact are exactly as before.
//
//  `TouchPlay` is plain state driven once per frame by the stage controller (`petFrame`) and is also driven headless by the tests.
//

import Foundation
import QuartzCore
import simd

extension BlobBrain {
    /// After a throw: the run blend fades back out once he has arrived (nothing else ends it when the walk is the brain's own `.come`).
    func hurryUpdate(dt: Float) {
        if hurry, activity == .idle, pending == nil, case .none = script { hurry = false }
        if !hurry, runW != 0, idleState.kind != .run {
            runW = max(0, runW - dt / 0.6)
            if runW < 1e-3 { runW = 0 }
        }
    }

    /// He has just been righted by the touch play: skip the brain's own "wait until calm" recovery (he is already standing and still).
    func finishTouchRecovery(sim: SoftBody) {
        guard activity == .touched || activity == .recovering else { return }
        activity = .recovering
        settleDone(sim)
    }

    /// The lean / jiggle the touch reactions add to the idle pose (see `touchPitch`, `touchRoll`, `touchSquash`).
    func applyTouch(pitch: Float, roll: Float, squash: Float) {
        touchPitch = pitch; touchRoll = roll; touchSquash = squash
    }
    func clearTouch() { applyTouch(pitch: 0, roll: 0, squash: 1) }
}

extension SoftBody {
    /// Mean distance of the particles from the rigid fit of his rest shape (sim units): how far the jelly is bent out of shape
    /// right now (a stretch under a lifting finger, a squeeze). Exactly the fit's own residual, so a rigid move reads 0.
    func deformation() -> Float {
        let pose = bodyPose(iterations: 4)
        var sum: Float = 0
        for i in 0..<n {
            let w = pose.centroid + pose.rotation.act(restPosition(i) - restCentroid)
            sum += simd_length(SIMD3(x[3 * i] - w.x, x[3 * i + 1] - w.y, x[3 * i + 2] - w.z))
        }
        return sum / Float(n)
    }

    /// Average particle velocity within `radius` of a world point (the live surface motion under a finger).
    func meanVelocity(near c: SIMD3<Float>, radius: Float) -> SIMD3<Float> {
        var sum = SIMD3<Float>(0, 0, 0), k: Float = 0
        let r2 = radius * radius
        for i in 0..<n {
            let d = SIMD3(x[3 * i] - c.x, x[3 * i + 1] - c.y, x[3 * i + 2] - c.z)
            if simd_dot(d, d) < r2 { sum += SIMD3(v[3 * i], v[3 * i + 1], v[3 * i + 2]); k += 1 }
        }
        return k > 0 ? sum / k : sum
    }
}

/// The body as an ellipsoid in the world: where a finger ray meets the undisturbed surface (the dent never feeds back into the pick).
struct BodyEllipsoid {
    var center: SIMD3<Float>
    var rot: simd_quatf
    var radii: SIMD3<Float>

    /// Rest-frame centre of the body ellipsoid (x, z centred; y = middle of the egg above the feet).
    static let restCenterY: Float = 0.70
    static let restRadii = SIMD3<Float>(0.66, 0.68, 0.535)

    init(sim: SoftBody) {
        let pose = sim.bodyPose(iterations: 4)
        rot = pose.rotation
        center = pose.centroid + pose.rotation.act(SIMD3<Float>(0, Self.restCenterY, 0) - sim.restCentroid)
        radii = Self.restRadii
    }

    struct Hit { var point: SIMD3<Float>; var normal: SIMD3<Float>; var local: SIMD3<Float> }

    /// First hit of the ray on the front of the ellipsoid.
    func hit(origin o: SIMD3<Float>, dir d: SIMD3<Float>, inflate k: Float = 1) -> Hit? {
        let inv = rot.inverse
        let rr = radii * k
        let lo = inv.act(o - center) / rr, ld = inv.act(d) / rr
        let a = simd_dot(ld, ld), b = 2 * simd_dot(lo, ld), c = simd_dot(lo, lo) - 1
        let disc = b * b - 4 * a * c
        guard a > 1e-9, disc >= 0 else { return nil }
        let t = (-b - disc.squareRoot()) / (2 * a)
        guard t > 0 else { return nil }
        let pl = (lo + ld * t)                                  // on the unit sphere
        let local = pl * rr
        let nl = simd_normalize(pl / rr)                     // gradient of the ellipsoid: p / r^2
        return Hit(point: center + rot.act(local), normal: rot.act(nl), local: local)
    }
}

/// The undisturbed skin: the rest render mesh carried by the body's rigid fit. A finger ray meets this, never the dented skin,
/// so the press depth cannot feed back into the pick (the ellipsoid is only the fast pre-test and the fallback).
final class RestSurface {
    private var pos: [Float]          // xyz per vertex (rest frame)
    private var tri: [UInt32]
    let triangleCount: Int

    init(mesh rm: RenderMesh) {
        pos = rm.rest
        let end = min(rm.body.first + rm.body.count, rm.index.count)
        tri = Array(rm.index[rm.body.first..<end])
        triangleCount = tri.count / 3
    }
    nonisolated deinit {}

    /// The render vertices a cheek squeeze moves, with smooth gaussian weights (left cheek, right cheek, the face between them);
    /// rest-frame positions are taken relative to `restCentroid`. Eyes, glints and brows are left out.
    struct CheekField { var vertices: [Int32] = []; var local: [SIMD3<Float>] = []; var left: [Float] = []; var right: [Float] = []; var mid: [Float] = [] }

    func cheekField(restCentroid c: SIMD3<Float>, excluded: Set<Int32>) -> CheekField {
        var f = CheekField()
        let sg: Float = 0.15, mg: Float = 0.22
        let ay = TouchPlay.cheekRY - 0.636
        for v in 0..<(pos.count / 3) {
            let p = SIMD3(pos[3 * v], pos[3 * v + 1], pos[3 * v + 2]) - c
            if p.z < -0.05 || excluded.contains(Int32(v)) { continue }
            func g(_ ax: Float, _ s: Float) -> Float {
                let dx = p.x - ax, dy = p.y - ay, dz = (p.z - 0.3) * 0.6          // wide in depth: the whole front skin there
                return expf(-(dx * dx + dy * dy + dz * dz) / (2 * s * s))
            }
            let l = g(TouchPlay.cheekX, sg), r = g(-TouchPlay.cheekX, sg), m = g(0, mg)
            if max(l, r, m) < 0.02 { continue }
            f.vertices.append(Int32(v)); f.local.append(p); f.left.append(l); f.right.append(r); f.mid.append(m)
        }
        return f
    }

    /// The skin point in front of a rest-frame spot (relative to the rest centroid), seen from the front: where a cheek press belongs.
    func front(local l: SIMD3<Float>, sim: SoftBody, pose: BodyPose) -> BodyEllipsoid.Hit? {
        let o = pose.centroid + pose.rotation.act(SIMD3(l.x, l.y, 3))
        return hit(origin: o, dir: pose.rotation.act(SIMD3(0, 0, -1)), sim: sim, pose: pose)
    }

    /// First hit of a world ray; `restCentroid` / pose from the sim's rigid fit.
    func hit(origin o: SIMD3<Float>, dir d: SIMD3<Float>, sim: SoftBody, pose: BodyPose) -> BodyEllipsoid.Hit? {
        let inv = pose.rotation.inverse
        let ro = sim.restCentroid + inv.act(o - pose.centroid)
        let rd = inv.act(d)
        var best = Float.infinity
        var bn = SIMD3<Float>(0, 0, 1)
        pos.withUnsafeBufferPointer { P in
            tri.withUnsafeBufferPointer { T in
                var t = 0
                while t + 2 < T.count {
                    let a = 3 * Int(T[t]), b = 3 * Int(T[t + 1]), c = 3 * Int(T[t + 2]); t += 3
                    let e1 = SIMD3(P[b] - P[a], P[b + 1] - P[a + 1], P[b + 2] - P[a + 2])
                    let e2 = SIMD3(P[c] - P[a], P[c + 1] - P[a + 1], P[c + 2] - P[a + 2])
                    let pv = simd_cross(rd, e2)
                    let det = simd_dot(e1, pv)
                    if abs(det) < 1e-12 { continue }
                    let inv = 1 / det
                    let tv = ro - SIMD3(P[a], P[a + 1], P[a + 2])
                    let u = simd_dot(tv, pv) * inv
                    if u < 0 || u > 1 { continue }
                    let q = simd_cross(tv, e1)
                    let v = simd_dot(rd, q) * inv
                    if v < 0 || u + v > 1 { continue }
                    let tt = simd_dot(e2, q) * inv
                    if tt > 0, tt < best { best = tt; bn = simd_normalize(simd_cross(e1, e2)) }
                }
            }
        }
        guard best.isFinite else { return nil }
        if simd_dot(bn, rd) > 0 { bn = -bn }
        let pr = ro + rd * best
        let local = pr - sim.restCentroid
        return BodyEllipsoid.Hit(point: pose.centroid + pose.rotation.act(local), normal: pose.rotation.act(bn), local: local)
    }
}

/// The part of his body a finger is on (rest-frame position of the hit). Each zone has its own feel and reaction.
enum TouchZone: String, CaseIterable, Sendable {
    case none, body, head, belly, cheek, underarm

    /// `local` = hit point relative to the rest centroid (rest frame, +z = the face, y up from the floor = local.y + 0.636).
    static func classify(local l: SIMD3<Float>) -> TouchZone {
        let ry = l.y + 0.636, ax = abs(l.x)
        if ry > 1.05 { return .head }
        if ax > 0.42, ry > 0.25, ry < 0.75 { return .underarm }
        if l.z > 0.05, ax > 0.28, ry >= 0.75 { return .cheek }
        if l.z > 0.05, ax <= 0.42, ry < 0.75 { return .belly }
        return .body
    }
}

extension SoftBody {
    /// Top-to-bottom extent of the particles (sim units): the body's squash / stretch, which the jelly wobble swings.
    func heightExtent() -> Float {
        var lo = Float.infinity, hi = -Float.infinity
        for i in 0..<n { let y = x[3 * i + 1]; lo = min(lo, y); hi = max(hi, y) }
        return hi - lo
    }
    /// The same at rest.
    func restHeightExtent() -> Float {
        var lo = Float.infinity, hi = -Float.infinity
        for i in 0..<n { let y = restPosition(i).y; lo = min(lo, y); hi = max(hi, y) }
        return hi - lo
    }

    /// A bounce (throw only): the mean vertical velocity becomes `up`, the mean sideways velocity is scaled by `keepSideways`; the jelly's own
    /// motion around the mean (the wobble) is left alone.
    func bounce(up: Float, keepSideways: Float, spinLoss: Float = 0.5) {
        let m = meanVelocity()
        let dv = SIMD3<Float>(m.x * (keepSideways - 1), up - m.y, m.z * (keepSideways - 1))
        // each hit also takes a good part of the tumble out (a rigid spin estimate about the centroid: the wobble is left alone)
        let c = centroid()
        var L = SIMD3<Float>.zero, I: Float = 0
        for i in 0..<n {
            let r = SIMD3(x[3 * i] - c.x, x[3 * i + 1] - c.y, x[3 * i + 2] - c.z)
            L += simd_cross(r, SIMD3(v[3 * i], v[3 * i + 1], v[3 * i + 2]) - m)
            I += simd_dot(r, r) * (2.0 / 3.0)
        }
        let omega = I > 1e-6 ? L / I * spinLoss : .zero
        for i in 0..<n {
            let r = SIMD3(x[3 * i] - c.x, x[3 * i + 1] - c.y, x[3 * i + 2] - c.z)
            let w = simd_cross(omega, r)
            v[3 * i] += dv.x - w.x; v[3 * i + 1] += dv.y - w.y; v[3 * i + 2] += dv.z - w.z
        }
    }

    /// Per-axis extent of the particles.
    func bounds() -> (lo: SIMD3<Float>, hi: SIMD3<Float>) {
        var lo = SIMD3<Float>(repeating: .infinity), hi = SIMD3<Float>(repeating: -.infinity)
        for i in 0..<n { let p = SIMD3(x[3 * i], x[3 * i + 1], x[3 * i + 2]); lo = simd_min(lo, p); hi = simd_max(hi, p) }
        return (lo, hi)
    }
    /// Shift every particle by `d` (a soft wall holding the whole body back, never one stretched vertex).
    func translate(_ d: SIMD3<Float>) { for i in 0..<n { x[3 * i] += d.x; x[3 * i + 1] += d.y; x[3 * i + 2] += d.z } }
    /// Sideways landing squash against a wall: the body flattens along `axis` (0 x, 2 z) and bulges a little in y.
    func wallSquash(axis: Int, k: Float) {
        let c = centroid()
        for i in 0..<n {
            v[3 * i + axis] -= k * (x[3 * i + axis] - (axis == 0 ? c.x : c.z))
            v[3 * i + 1] += 0.3 * k * (x[3 * i + 1] - c.y)
        }
    }

    /// A landing squash: the top is pushed down toward the middle and the middle spreads, as a velocity kick that sums to zero
    /// momentum (the jelly then springs back by itself). `k` in 1/s.
    func squashKick(_ k: Float) {
        let c = centroid()
        for i in 0..<n {
            let dy = x[3 * i + 1] - c.y
            v[3 * i + 1] -= k * dy
            v[3 * i] += 0.4 * k * (x[3 * i] - c.x); v[3 * i + 2] += 0.4 * k * (x[3 * i + 2] - c.z)
        }
    }

    /// A sideways shove that grows with height above his middle (a sloshing jelly): `dv` in u/s at the crown.
    func shear(_ dv: SIMD2<Float>) {
        let cy = centroid().y
        for i in 0..<n {
            let k = max(-0.5, min(1, (x[3 * i + 1] - cy) / 0.7))
            v[3 * i] += dv.x * k; v[3 * i + 2] += dv.y * k
        }
    }
}

@MainActor
final class TouchPlay {
    // tuning
    static let fingerRadius: Float = 0.26       // sim units; Bob is about 1.35 tall
    static let dentDepth: Float = 0.10          // how far the fingertip sinks into him
    static let strokeSpeed: Float = 0.30        // u/s of finger speed that counts as stroking
    static let happyAfter: Float = 0.4          // seconds of stroking before the eyes close
    /// The firm jelly barely bends (a hanging Bob's mean residual is ~0.003 u): the lift haptic reads it scaled up to the squish range.
    static let liftDepthGain: Float = 80
    static let openAfter: Float = 0.7           // the beat after stroking stops before they open
    static let purrAfter: Float = 2.0           // seconds of good petting before the purr
    static let purrHz: Float = 2.6
    /// Where the cheeks are on the rest body (beside and a little below the eyes) and the softer, wider press that squeezes them.
    /// The squeeze is drawn as a smooth skin offset; the sim press under it creased the coarse mesh, so it is off.
    static let cheekSimAssist = false
    static let maxCheekOffset: Float = 0.08 * Float(BobForm.top)
    static let cheekX: Float = 0.42, cheekRY: Float = 0.80, cheekRadius: Float = 0.30

    let haptics: HapticDriver

    // pet state (read by tests / the log)
    private(set) var contact = false             // the fingertip is on his body
    private(set) var speed: Float = 0            // low-passed finger speed along his surface (u/s)
    private(set) var ramp: Float = 0             // dent engagement 0...1
    private(set) var love: Float = 0             // happiness 0...1 (eyes closed, lean, jiggle)
    private(set) var hitLocal: SIMD3<Float>?
    /// The same fingertip hit in the world (the clean-up draws its tool there).
    private(set) var hitWorld: SIMD3<Float>?
    private(set) var movingT: Float = 0
    private var gapT: Float = 0
    private var happyOn = false
    private var calmT: Float = 0
    private var prevLocal: SIMD3<Float>?
    private var easedCenter: SIMD3<Float>?
    private var lastHit: BodyEllipsoid.Hit?      // the dent lifts out where it last was when the finger leaves him
    private var lean = SIMD2<Float>(0, 0)        // (pitch, roll) eased
    private var jiggleT: Float = 0
    private var eyesTouched = false
    private var savedAutoBlink = true
    private var heartT: Float = 0
    static let rippleOn: Float = 0.25, rippleOff: Float = 0.1     // u/s of surface normal velocity under the finger
    private(set) var rippleV: Float = 0
    private var lastRipple: Double = -1
    private var prevA: Float = 0
    /// Ripple transients fired (tests / log).
    private(set) var ripples = 0

    // mood (docs/Emotions.md): a grumpy Blob does not enjoy being touched, unless attention is exactly what he wants
    var mood: BlobMood = .happy
    var attentionWanted = false
    /// Touch lands as annoyed: grumpy, and the need he is missing is not attention.
    var annoyed: Bool { mood == .grumpy && !attentionWanted }
    private var annoyK: Float = 0                 // eased 0...1 while a touch is annoying him
    private var annoyPitch: Float = 0, annoyRoll: Float = 0, annoySquash: Float = 1
    private var hmphT: Float = 0
    private(set) var hmphs = 0
    static let hmphTime: Float = 0.35

    // zones
    private(set) var zone: TouchZone = .none
    private var zoneCand: TouchZone = .none
    private var zoneT: Float = 0
    private var trainPhase: Float = 0            // tap / flutter train phase
    private var boopT: Float = 0                 // the dimple pop after a boop (seconds left)
    private(set) var boops = 0
    private(set) var trainTicks = 0
    /// Seconds of touch per zone this session (mood memory hook: no UI yet).
    private(set) var zoneSeconds: [TouchZone: Float] = [:]
    var favouriteZone: TouchZone? {
        zoneSeconds.filter { $0.key != .none && $0.value > 1 }.max { $0.value < $1.value }?.key
    }
    func resetSession() { zoneSeconds = [:] }

    // purr
    private(set) var purrT: Float = 0
    private(set) var purrLevel: Float = 0
    private var purrGap: Float = 0
    private var purrOn = false
    private var purrPhase: Float = 0
    var isPurring: Bool { purrOn }

    // phone tilt / shake
    private var tiltRoll: Float = 0
    private var lastGX: Float = 0
    private var dizzy: Float = 0
    private var whoaT: Float = 0
    private var whoaPitch: Float = 0
    private var lastShake: Double = -1
    private(set) var shakes = 0
    private(set) var whoas = 0
    private var motionActive = false

    /// Levels other modes feed the squish channel with (pick-up stretch, cheeks press).
    var squishDepth: Float = 0
    var cheeksPinch: Float = 0

    /// A heart in a little thought bubble that pops out above his head (the overlay projects his head every frame, so only the birth time, a
    /// sideways drift and a start offset are kept; both in -1...1). Pruned after `heartLife`.
    struct Heart { var born: Double; var drift: Float; var start: Float; var side: Float }
    private(set) var hearts: [Heart] = []
    static let heartLife: Double = 1.2
    private var lastHeartNow: Double = -1
    private var heartSide: Float = 1
    /// Heart bubbles while he really enjoys it: petted into a happy squint, purring, or held up and happy (never when grumpy / annoyed).
    private var enjoying: Bool { !annoyed && !thrown && (love > 0.85 || purrLevel > 0.5 || excitement > 0.6) }
    func heartsFrame(dt: Float, now: Double) {
        guard now != lastHeartNow else { return }          // petFrame and heldFrame both call it: once per frame
        lastHeartNow = now
        if enjoying {
            heartT -= dt
            if heartT <= 0 {
                heartT = 0.6 + 0.4 * rand()
                heartSide = -heartSide                    // alternate beside his head: upper left, upper right
                hearts.append(Heart(born: now, drift: (rand() - 0.5) * 2, start: (rand() - 0.5) * 2, side: heartSide))
            }
        } else { heartT = min(heartT, 0.3) }
        if !hearts.isEmpty { hearts.removeAll { now - $0.born > Self.heartLife } }
    }
    /// Voice v1: one heart bubble beside his head now (a trick just learned), outside any touch; pruned here because no touch frame runs.
    func spawnHeart(now: Double) {
        hearts.removeAll { now - $0.born > Self.heartLife }
        heartSide = -heartSide
        hearts.append(Heart(born: now, drift: (rand() - 0.5) * 2, start: (rand() - 0.5) * 2, side: heartSide))
    }
    /// Voice v1: drop expired hearts when no touch frame is running.
    func pruneHearts(now: Double) { if !hearts.isEmpty { hearts.removeAll { now - $0.born > Self.heartLife } } }
    private var rng: UInt32 = 0x9E3779B1

    init(haptics: HapticDriver? = nil) { self.haptics = haptics ?? HapticDriver.makeDefault() }
    nonisolated deinit {}

    private func rand() -> Float { rng ^= rng << 13; rng ^= rng >> 17; rng ^= rng << 5; return Float(rng >> 8) / Float(1 << 24) }

    /// True while anything of the touch play is still showing (the stage skips the frame work otherwise).
    var isActive: Bool {
        cheekOn || pinch > 0 || visPinch != 0 || contact || ramp > 0 || love > 0 || speed > 0.001 || squishDepth > 0 || cheeksPinch > 0 || !hearts.isEmpty
            || purrLevel > 0 || annoyK > 0 || hmphT > 0 || motionActive || whoaT > 0 || boopT > 0 || excitement > 0 || happyKick > 0 || !tapQueue.isEmpty
    }

    // MARK: pet

    /// One pet frame. `ray` = the finger's world ray (nil = no finger down); `screen` is unused now (the hearts moved above his head).
    func petFrame(dt: Float, now: Double, ray: (o: SIMD3<Float>, d: SIMD3<Float>)?, screen: SIMD2<Float>?,
                  sim: SoftBody, brain: BlobBrain?, skinner: Skinner, surface: RestSurface? = nil) {
        // 1. where is the fingertip on him
        var hit: BodyEllipsoid.Hit?
        if let ray {
            let egg = BodyEllipsoid(sim: sim)
            if let rs = surface, egg.hit(origin: ray.o, dir: ray.d, inflate: 1.5) != nil {
                hit = rs.hit(origin: ray.o, dir: ray.d, sim: sim, pose: sim.bodyPose(iterations: 4))
            } else if surface == nil { hit = egg.hit(origin: ray.o, dir: ray.d) }
        }
        let wasContact = contact
        contact = hit != nil
        hitLocal = hit?.local
        hitWorld = hit?.point

        // zone (stable for 0.1 s before it changes; a fresh touch is classified at once)
        if let h = hit {
            let z = TouchZone.classify(local: h.local)
            if !wasContact { zone = z; zoneCand = z; zoneT = 0 }
            else if z == zone { zoneCand = z; zoneT = 0 }
            else if z == zoneCand { zoneT += dt; if zoneT > 0.1 { zone = z; zoneT = 0 } }
            else { zoneCand = z; zoneT = 0 }
            zoneSeconds[zone, default: 0] += dt
        } else if wasContact { zone = .none }

        // 2. surface speed (relative to his body), low-passed over ~50 ms so a still finger decays to silence
        var raw: Float = 0
        if let h = hit, let p = prevLocal, dt > 0 { raw = simd_length(h.local - p) / dt }
        prevLocal = hit?.local
        speed += (raw - speed) * (1 - expf(-dt / 0.05))
        if speed < 0.002 { speed = 0 }

        // 3. the dent: a fingertip sphere that sinks in, slides, and lets go (a boop pops it deeper for a moment)
        if contact && !wasContact && annoyed { hmph(now: now) }
        else if contact && !wasContact && zone == .cheek {
            boops += 1; boopT = 0.18
            haptics.transient(now: now, intensity: 0.9, sharpness: 0.9)       // the crisp "boop"
        }
        boopT = max(0, boopT - dt)
        if wasContact && !contact && ramp > 0.6 && !annoyed { jellyLetGo(now: now) }          // the finger lets go: the dent springs back
        let rampRate: Float = contact ? 1 / 0.12 : 1 / 0.10
        ramp = max(0, min(1, ramp + (contact ? 1 : -1) * rampRate * dt))
        if let h = hit { lastHit = h }
        if let h = hit ?? lastHit, ramp > 0 {
            // the sphere's centre is eased so it never jumps into particles; the depth is the commanded dimple (the skin it is
            // measured against is the undisturbed one, so nothing feeds back)
            let pop = 1 + 1.2 * sinf(.pi * min(1, boopT / 0.18))
            let depth = Self.dentDepth * ramp * ramp * (3 - 2 * ramp) * (boopT > 0 ? pop : 1)
            let target = h.point + h.normal * (Self.fingerRadius - depth)
            if let e = easedCenter, sim.pressing { easedCenter = e + (target - e) * (1 - expf(-dt * (boopT > 0 ? 80 : 28))) } else { easedCenter = target }
            sim.setPress(center: easedCenter!, radius: Self.fingerRadius)
        } else if sim.pressing && ramp <= 0 {
            sim.endPress(); lastHit = nil; easedCenter = nil
        }
        if contact && !wasContact && zone != .cheek && !annoyed { haptics.transient(now: now, intensity: 0.30, sharpness: 0.20) }

        // 4. happiness: eyes close after ~0.4 s of stroking, open a beat after it stops (belly and tickles are quicker)
        let quick = contact && (zone == .belly || zone == .underarm)
        if speed > Self.strokeSpeed { movingT += dt; gapT = 0 } else { gapT += dt; if gapT > 0.25 { movingT = 0 } }
        happyKick = max(0, happyKick - dt)
        if annoyed { happyOn = false; happyKick = 0; movingT = 0 }
        flushTaps(now: now)
        if happyKick > 0 { happyOn = true; calmT = 0 }
        if movingT > (quick ? 0.12 : Self.happyAfter) { happyOn = true; calmT = 0 }
        else if happyOn { calmT += dt; if calmT > Self.openAfter { happyOn = false } }
        let loveRate: Float = happyOn ? 1 / 0.25 : 1 / 0.35
        love = max(0, min(1, love + (happyOn ? 1 : -1) * loveRate * dt))

        // purr: ~2 s of continuous good petting (not rough); stops when the finger stops or goes rough
        let good = contact && speed > 0.25 && speed < 4.5
        if contact && speed > 5 { purrT = 0; purrOn = false; purrGap = 0 }
        else if good { purrT += dt; purrGap = 0 }
        else { purrGap += dt; if purrGap > 0.5 { purrT = 0; purrOn = false } }
        if annoyed { purrT = 0; purrOn = false }
        if purrT > Self.purrAfter { purrOn = true }
        purrLevel = max(0, min(1, purrLevel + (purrOn ? 1 / 0.5 : -1 / 0.3) * dt))
        purrPhase += dt * Self.purrHz
        if purrPhase > 1 { purrPhase -= 1 }

        skinner.normalSmoothing = ramp > 0 ? ramp : 0          // the dent reads as a soft dimple: skin relaxed + normals blurred around it
        if let h = hit ?? lastHit { skinner.smoothCenter = h.point }
        react(dt: dt, now: now, brain: brain, skinner: skinner, screen: screen)

        // a wobble wave passing under the finger: the surface there swings in and out; each swing past a threshold is one ripple tick
        if let h = hit ?? lastHit, ramp > 0.4 {
            let vn = simd_dot(sim.meanVelocity(near: h.point, radius: 0.3), h.normal)
            rippleV += (vn - rippleV) * (1 - expf(-dt / 0.02))
            let a = abs(rippleV)
            if a > Self.rippleOn, prevA <= Self.rippleOn, now - lastRipple > 0.09, !annoyed {
                lastRipple = now
                haptics.transient(now: now, intensity: min(0.65, 0.18 + 0.30 * a), sharpness: 0.25)
                ripples += 1
            }
            prevA = a
        } else { rippleV = 0; prevA = 0 }

        // 5. haptics by zone
        let onBody = contact && ramp > 0.4
        let prog = HapticMap.petProgress(speed: speed)
        let depthK = HapticMap.clamp01(sim.pressDepth / 0.2)      // the live dent: a deeper press under the stroke swells the texture
        var pi: Float = 0, ps = HapticMap.petSharpness(speed: speed)
        if onBody && annoyed {
            // short and stiff: a sharp tick every so often while the hand moves, no texture, no purr
            if prog > 0 { train(dt: dt, hz: 4, now: now, intensity: 0.35, sharpness: 0.92) }
        } else if onBody {
            switch zone {
            case .head:
                // tap-tap: a light pat texture, six taps a second while the hand moves
                pi = 0
                if prog > 0 { train(dt: dt, hz: 6, now: now, intensity: 0.30 + 0.3 * prog, sharpness: 0.55) }
            case .belly:
                // deep, soft, low rumble
                pi = min(1, HapticMap.bellyIntensity(speed: speed) * (0.85 + 0.3 * depthK))
                ps = HapticMap.bellySharpness(speed: speed)
            case .underarm:
                // quick fluttery ticks, even when the finger is held there
                train(dt: dt, hz: 16, now: now, intensity: 0.22 + 0.3 * max(prog, 0.35), sharpness: 0.75)
            default:
                pi = min(1, HapticMap.petIntensity(speed: speed) * (0.85 + 0.3 * depthK))
            }
        }
        if purrLevel > 0 {
            // the purr: a slow 2.6 Hz swell underneath whatever else is felt
            let pulse = 0.5 + 0.5 * sinf(2 * .pi * purrPhase)
            pi = min(1, pi + purrLevel * (0.12 + 0.28 * pulse))
            ps = min(ps, 0.12)
        }
        let sd = max(squishDepth, 0)
        var si = cheeksPinch > 0 ? HapticMap.cheeksIntensity(pinch: cheeksPinch) : HapticMap.squishIntensity(depth: sd)
        var ss = cheeksPinch > 0 ? HapticMap.cheeksSharpness(pinch: cheeksPinch) : HapticMap.squishSharpness(depth: sd)
        if onBody, !annoyed, cheeksPinch == 0 {
            // jelly under the finger: a soft, low texture that follows how far he is REALLY squashed (the dent and the body's own deformation)
            let jd = max(sim.pressDepth * 1.5, min(0.5, sim.deformation() * Self.liftDepthGain))
            si = max(si, 0.55 * HapticMap.squishIntensity(depth: jd)); ss = min(ss, HapticMap.squishSharpness(depth: jd))
        }
        haptics.update(now: now, petIntensity: pi, petSharpness: ps, squishIntensity: si, squishSharpness: ss)
    }

    /// A train of transients at `hz` (taps, flutter).
    private func train(dt: Float, hz: Float, now: Double, intensity: Float, sharpness: Float) {
        trainPhase += dt * hz
        if trainPhase >= 1 {
            trainPhase -= floorf(trainPhase)
            trainTicks += 1
            haptics.transient(now: now, intensity: intensity, sharpness: sharpness)
        }
    }

    /// Test hook: false = no lean / jiggle / breathing, so only the contact itself acts on the body.
    var bodyReactions = true

    private func react(dt: Float, now: Double, brain: BlobBrain?, skinner: Skinner, screen: SIMD2<Float>?) {
        updateEyes(skinner)
        if !bodyReactions { outPitch = 0; outRoll = 0; outSquash = 1; compose(brain); return }
        // lean into the finger (toward the side it is on, a little forward) + a slow happy jiggle; the zones add their own
        var wantPitch: Float = 0, wantRoll: Float = 0
        if let l = hitLocal, love > 0 {
            let side = max(-1, min(1, l.x / 0.66))
            wantRoll = -0.22 * side * love        // roll about +z: negative leans toward +x (the viewer's right)
            wantPitch = 0.07 * love
            if zone == .head { wantPitch = -0.03 * love; wantRoll *= 0.4 }      // a head pat ducks him a little
        }
        lean += (SIMD2(wantPitch, wantRoll) - lean) * (1 - expf(-dt * 5))
        if love <= 0, abs(lean.x) < 1e-4, abs(lean.y) < 1e-4 { lean = .zero }
        jiggleT += dt
        let jig = love * love
        var roll = 0.03 * jig * sinf(2 * .pi * 2.0 * jiggleT)
        var sq = 0.025 * jig * sinf(2 * .pi * 4.0 * jiggleT)
        if contact {
            switch zone {
            case .belly:     // a giggle: a quicker wiggle, and the belly jiggles more
                roll += 0.05 * jig * sinf(2 * .pi * 5.0 * jiggleT)
                sq += 0.045 * jig * sinf(2 * .pi * 7.0 * jiggleT)
            case .underarm:  // squirming
                roll += 0.06 * jig * sinf(2 * .pi * 8.0 * jiggleT)
                sq += 0.03 * jig * sinf(2 * .pi * 11.0 * jiggleT)
            default: break
            }
        }
        // purr: soft breathing in step with the haptic pulse
        sq += 0.016 * purrLevel * sinf(2 * .pi * purrPhase)
        outRoll = lean.y + roll; outPitch = lean.x; outSquash = 1 + sq
        var side: Float = 0
        if let l = hitLocal { side = max(-1, min(1, l.x / 0.66)) }
        annoyUpdate(dt: dt, active: contact, side: side)
        compose(brain)
        heartsFrame(dt: dt, now: now)           // heart bubbles above his head (the old hearts at the finger are gone)
    }

    // MARK: composing the reactions

    private var outPitch: Float = 0, outRoll: Float = 0, outSquash: Float = 1

    /// The brain gets the sum of every reaction (pet lean / jiggle, purr, phone tilt, whoa).
    private func compose(_ brain: BlobBrain?) {
        guard let brain else { return }
        let p = outPitch + whoaPitch + annoyPitch, r = outRoll + tiltRoll + annoyRoll, q = outSquash * annoySquash
        if p == 0 && r == 0 && q == 1 { brain.clearTouch() } else { brain.applyTouch(pitch: p, roll: r, squash: q) }
    }

    /// Eyes: the smallest of the happy squint / close, the cheek squeeze and the dizzy half-open.
    private func updateEyes(_ skinner: Skinner) {
        let k = love * love * (3 - 2 * love)
        let close = zone == .head ? 0.55 * k : k
        var want = 1 - close
        want = min(want, 1 - 0.55 * pinch)
        if whoaT > 0 { want = min(want, 0.35) }
        if excitement > 0 { let e = excitement; want = min(want, 1 - e * e * (3 - 2 * e)) }       // held and happy: the same closed happy eyes as petting
        if annoyK > 0.02 { want = min(want, 1 - 0.55 * annoyK) }        // a grumpy squint (with the head down the flat brows read angry)          // happy to be picked up
        if want < 0.999 {
            if !eyesTouched { eyesTouched = true; savedAutoBlink = skinner.autoBlink }
            skinner.autoBlink = false
            skinner.setEyeOpenness(want)
        } else if eyesTouched {
            eyesTouched = false
            skinner.setEyeOpenness(1)
            skinner.autoBlink = savedAutoBlink
        }
    }

    // MARK: phone tilt and shake (CoreMotion on the device; the tests feed the numbers)

    static let maxTilt: Float = 0.18

    /// `gravityX` = the device's gravity x component (-1...1, tilt to the right = +), `shake` = the user acceleration magnitude in g.
    /// Tilting makes him lean the other way and slosh; a shake makes him jiggle with a wobble rumble; too much and he gets dizzy ("whoa").
    func motionFrame(dt: Float, now: Double, gravityX: Float, shake: Float, sim: SoftBody, brain: BlobBrain?, skinner: Skinner) {
        let gx = max(-1, min(1, gravityX))
        // tilt: lean away from the low side, eased; slosh with the change
        let want = -gx * 0.30
        tiltRoll += (max(-Self.maxTilt, min(Self.maxTilt, want)) - tiltRoll) * (1 - expf(-dt * 6))
        if abs(tiltRoll) < 1e-4, abs(want) < 1e-3 { tiltRoll = 0 }
        let dgx = (gx - lastGX) / max(dt, 1e-3)
        lastGX = gx
        if abs(dgx) > 0.8 { sim.shear(SIMD2(max(-0.7, min(0.7, dgx * 0.25)), 0)) }
        // shake
        if shake > 1.4, now - lastShake > 0.25 {
            lastShake = now; shakes += 1
            let a = min(shake, 3.5)
            sim.shear(SIMD2((shakes % 2 == 0 ? 1 : -1) * min(1.0, 0.35 * a), 0))
            haptics.wobble(now: now, peak: min(0.85, 0.3 + 0.2 * a))
            dizzy += 0.18 * a
        }
        dizzy = max(0, dizzy - 0.35 * dt)
        if dizzy > 1.0, whoaT <= 0 { whoaT = 1.3; whoas += 1; dizzy = 0.4 }
        if whoaT > 0 {
            whoaT -= dt
            // a "whoa" lean back and a sway
            let env = HapticMap.clamp01(min(whoaT / 0.3, (1.3 - whoaT) / 0.15))
            whoaPitch = -0.14 * env
            tiltRoll += 0.05 * env * sinf(2 * .pi * 2.0 * whoaT)
            if whoaT <= 0 { whoaPitch = 0 }
        }
        motionActive = abs(tiltRoll) > 0 || whoaT > 0 || dizzy > 0.01
        updateEyes(skinner)
        compose(brain)
    }

    /// Only the haptic levels (nothing is touching him): for the squish channel while he is lifted.
    func petFrameIdle(dt: Float, now: Double) {
        let sd = max(squishDepth, 0)
        haptics.update(now: now, petIntensity: heldPulse, petSharpness: 0.1,
                       squishIntensity: HapticMap.squishIntensity(depth: sd), squishSharpness: HapticMap.squishSharpness(depth: sd))
    }

    // MARK: grumpy touch

    /// The annoyed "hmph": a short, stiff haptic (high sharpness, one tick) and a quick squash puff.
    private func hmph(now: Double) {
        hmphT = Self.hmphTime; hmphs += 1
        haptics.transient(now: now, intensity: 0.65, sharpness: 0.95)
    }

    /// Eases the annoyed pose: he leans away from the finger (`side` = which side of him it is on, -1...1; 0 = from the front, he ducks his head
    /// instead), heads down so the flat brows read angry, a squint, and the hmph squash. All zero again when the touch ends.
    private func annoyUpdate(dt: Float, active: Bool, side: Float) {
        annoyK += ((active && annoyed ? 1 : 0) - annoyK) * (1 - expf(-dt * 6))
        if annoyK < 0.003 { annoyK = 0 }
        hmphT = max(0, hmphT - dt)
        annoyRoll = 0.18 * side * annoyK                    // roll about +z: positive leans toward -x, away from a finger on the +x side
        annoyPitch = 0.09 * annoyK
        annoySquash = hmphT > 0 ? 1 - 0.07 * sinf(.pi * (1 - hmphT / Self.hmphTime)) : 1
    }

    // MARK: taps (a zone tap: head pat, cheek boop, belly poke, tickle poke)

    private var happyKick: Float = 0
    private var tapQueue: [(t: Double, i: Float, s: Float)] = []
    private(set) var taps = 0

    /// A quick tap on the zone the finger is on (the dent is held for a moment by the stage).
    func tap(now: Double) {
        taps += 1
        if annoyed { hmph(now: now); return }
        switch zone {
        case .head:     // pat-pat
            haptics.transient(now: now, intensity: 0.45, sharpness: 0.55); tapQueue.append((now + 0.09, 0.38, 0.55)); happyKick = 0.7
        case .belly:    // a poke: a soft thump and a giggle
            haptics.transient(now: now, intensity: 0.55, sharpness: 0.2); haptics.wobble(now: now, peak: 0.3); happyKick = 0.9
        case .underarm: // a tickle poke: a quick flutter
            for k in 0..<6 { tapQueue.append((now + Double(k) * 0.06, 0.4, 0.75)) }; happyKick = 0.9
        case .cheek:    // the boop already fired on touchdown
            happyKick = 0.5
        default:
            haptics.transient(now: now, intensity: 0.35, sharpness: 0.3)
        }
    }

    private func flushTaps(now: Double) {
        guard !tapQueue.isEmpty else { return }
        for t in tapQueue where t.t <= now { haptics.transient(now: now, intensity: t.i, sharpness: t.s) }
        tapQueue.removeAll { $0.t <= now }
    }

    // MARK: held-up happiness (pick up)

    private(set) var excitement: Float = 0
    private var excitedPhase: Float = 0
    private var liftedT: Float = 0
    private var heldT: Float = 0
    private var releasedT: Float = 99
    private var impactsAtRelease = 0
    /// The soft warm pulse that is felt while he is held (read by `petFrameIdle`, a slow swell, never a flutter).
    private(set) var heldPulse: Float = 0
    /// A gentle ~1 Hz roll (rad) the stage adds to the grab rotation so he sways like a happy pendulum while he is held.
    private(set) var heldSway: Float = 0
    static let heldHz: Float = 1.0
    static let heldSwayAmp: Float = 0.06

    /// While he is held (lifted, or dragged for a moment) he is happy: closed happy eyes, a slow ~1 Hz sway, his feet dangling and swinging
    /// softly and a small arm lift, with a slow warm haptic swell. It goes when he lands (or 1.5 s after the letting go, or at once when he is
    /// thrown). `liftHeight` = how far the grab has been raised (world units). Grumpy: a stiff hmph instead, no happiness.
    func heldFrame(dt: Float, now: Double, grabbing: Bool, liftHeight: Float, sim: SoftBody, brain: BlobBrain?, skinner: Skinner) {
        if grabbing {
            liftedT = liftHeight > 0.04 ? liftedT + dt : 0
            heldT += dt
            releasedT = 0; impactsAtRelease = impacts
        } else { liftedT = 0; heldT = 0; releasedT += dt }
        if grabbing { skinner.normalSmoothing = 0 }
        let happyHold = grabbing && (liftedT > 0.2 || heldT > 0.5)
        let want = !annoyed && !thrown && (happyHold || (!grabbing && excitement > 0 && releasedT < 1.5 && impacts == impactsAtRelease))
        if grabbing && annoyed && liftHeight > 0.04 && liftedT <= dt + 0.0001 { hmph(now: now) }
        annoyUpdate(dt: dt, active: grabbing && liftHeight > 0.04, side: 0)
        if grabbing, annoyed, annoyK > 0.5 { train(dt: dt, hz: 3, now: now, intensity: 0.3, sharpness: 0.92) }
        if excitement == 0, annoyK > 0 || annoyPitch != 0 || eyesTouched { compose(brain); updateEyes(skinner) }
        excitement = max(0, min(1, excitement + (want ? 1 / 0.35 : -1 / 0.3) * dt))
        if excitement > 0 {
            excitedPhase += dt * 2 * .pi * Self.heldHz
            if excitedPhase > 2 * .pi { excitedPhase -= 2 * .pi }
            brain?.driveExcited(sim: sim, skinner: skinner, dt: dt, level: excitement, phase: excitedPhase)
            heldSway = Self.heldSwayAmp * excitement * sinf(excitedPhase)
            // a slow, soft, warm swell (like the purr, but slower): never the old 11 Hz flutter
            heldPulse = grabbing ? excitement * (0.07 + 0.20 * (0.5 + 0.5 * sinf(excitedPhase - .pi / 2))) : 0
            updateEyes(skinner)
        } else {
            heldPulse = 0; heldSway = 0; excitedPhase = 0
            if brain?.excitedOn == true { brain?.endExcited(); updateEyes(skinner) }
        }
        if !grabbing {
            if heldPulseSent > 0 { heldPulseSent = 0; haptics.update(now: now, petIntensity: 0, petSharpness: 0.1, squishIntensity: 0, squishSharpness: 0.5) }
        } else { heldPulseSent = heldPulse }
        heartsFrame(dt: dt, now: now)
        jellyFrame(dt: dt, now: now, sim: sim)
    }
    private var heldPulseSent: Float = 0

    // MARK: getting back up (after a throw, or when he is left lying)

    enum GetUpPhase: Equatable { case off, righting }
    private(set) var getUpPhase: GetUpPhase = .off
    /// Set by the stage when he was thrown: the brain stays hands-off while he bounces, tumbles and lies still. Bouncing (a jelly ball) is
    /// ONLY on while this is set; hop and walk landings are never touched.
    var thrown = false { didSet { if thrown && !oldValue { bounces = 0; wallBounces = 0; floorBounces = 0; hearts.removeAll() } } }
    private var floorBounces = 0
    /// Bounces given since the throw (tests / the log).
    private(set) var bounces = 0
    /// Rebound speed as a fraction of the impact speed, per bounce: a jelly ball bouncing two or three times, lower each time.
    static let bounceRestitution: [Float] = [0.5, 0.45, 0.4]
    /// Below this impact speed (u/s) it just lands (and the wobble does the rest).
    static let bounceMinSpeed: Float = 1.3
    private var stillT: Float = 0
    private var getUpT: Float = 0
    private var gq0 = simd_quatf(ix: 0, iy: 0, iz: 0, r: 1)
    private var gu: Float = 0, guv: Float = 0
    private var gxz = SIMD2<Float>(0, 0)
    private(set) var getUps = 0
    /// The brain is kept hands-off (the stage passes it as `touched`): set by `getUpFrame` each frame.
    var holdsBrain = false
    static let stillBeforeGetUp: Float = 0.06         // a short calm window after the last bounce, then he rights himself
    static let getUpDuration: Float = 0.4

    /// One frame. Returns true while the brain must stay hands-off (the stage passes it as `touched`). Once he has bounced to rest (a calm window of
    /// 0.35 s on the floor) he rights himself in under 0.8 s (a wobble-roll up onto his feet, a little shake-off), then he RUNS (the idle run blend)
    /// back to `focusSpot` and faces the camera. With no spot (he is lying somewhere outside focus) he just gets up where he is.
    func getUpFrame(dt: Float, now: Double, held: Bool, focusSpot: SIMD2<Float>?, sim: SoftBody, brain: BlobBrain?) -> Bool {
        if held {
            stillT = 0
            if getUpPhase == .righting { getUpPhase = .off; sim.attractor.strength = 0 }
            return false
        }
        switch getUpPhase {
        case .off:
            if let brain { brain.hurryUpdate(dt: dt) }
            if let brain, brain.isFlipping { stillT = 0; return false }      // the flip's faceplant lies face-down ON PURPOSE and gets up by itself
            let pose = sim.bodyPose(iterations: 4)
            let lying = pose.tilt > 1.0
            guard thrown || lying else { stillT = 0; return false }
            // on the floor (the apex of a bounce is not) and slow: the bouncing is over; a lying jelly keeps rocking a little, so the energy limit is loose
            sinceImpact += dt
            // not while a rebound is still due (the instant of landing is slow too): the last landing was too weak to bounce, all bounces are used, or it has been quiet
            let spent = floorBounces >= Self.bounceRestitution.count || (floorBounces >= 1 && lastImpactSpeed < Self.bounceMinSpeed) || sinceImpact > 0.35
            let calm = spent && sim.kineticEnergy() / sim.totalMass < 1.0 && simd_length(sim.meanVelocity()) < 1.0 && sim.minY() < 0.12
            stillT = calm ? stillT + dt : max(0, stillT - 0.5 * dt)
            if stillT >= Self.stillBeforeGetUp, let brain {
                getUpPhase = .righting; getUpT = 0; getUps += 1
                gq0 = pose.rotation; gu = 0; guv = 0; gxz = SIMD2(pose.centroid.x, pose.centroid.z)
                brain.clearTouch()
            }
            return thrown
        case .righting:
            guard let brain else { getUpPhase = .off; return false }
            getUpT += dt
            let t = getUpT
            // a wobbly spring from the lying pose to standing (overshoots a little: the wobble-roll)
            let om: Float = 16, ze: Float = 0.5
            guv += (om * om * (1 - gu) - 2 * ze * om * guv) * dt
            gu += guv * dt
            let cam = brain.cameraPosXZ
            var yaw = atan2f(cam.x - gxz.x, cam.y - gxz.y)
            if let spot = focusSpot, simd_length(spot - gxz) > 0.5 { yaw = atan2f(spot.x - gxz.x, spot.y - gxz.y) }      // up already facing the way home: the run starts at once
            let up = simd_quatf(angle: yaw, axis: SIMD3(0, 1, 0)) * simd_quatf(angle: -brain.attentionPitch * brain.amplitude, axis: SIMD3(1, 0, 0))
            var q = simd_slerp(gq0, up, gu)
            // the shake-off: a quick decaying roll and squash once he is up
            let ts = max(0, t - 0.3), env = expf(-ts * 10)
            var sq: Float = 1
            if t > 0.3 {
                q = q * simd_quatf(angle: 0.22 * env * sinf(2 * .pi * 8 * ts), axis: SIMD3(0, 0, 1))
                sq = 1 + 0.06 * env * sinf(2 * .pi * 11 * ts)
            }
            sim.attractor.rotation = q
            sim.attractor.squash = sq
            sim.attractor.anchor = SIMD3(gxz.x, sim.groundedAnchorY(rotation: q, squash: sq), gxz.y)
            let k = min(1, t / 0.2)
            sim.attractor.strength = 900 * k * k * (3 - 2 * k)
            if t >= Self.getUpDuration {
                getUpPhase = .off; thrown = false; stillT = 0
                brain.finishTouchRecovery(sim: sim)            // no 0.5 s "calm" wait on top: he is already up
                if let spot = focusSpot {
                    brain.request(.come(to: spot))
                    brain.hurry = true                         // runs back (the idle run blend), not the plain walk
                }
                return false
            }
            return true
        }
    }

    // MARK: jelly release wobble (the haptic follows the real squash oscillation)

    /// A pulse of the let-go wobble: when it fired (the frame time of the squash peak it follows) and how far the squash swung.
    struct JellyPulse { var t: Double; var amplitude: Float }
    private(set) var jellyPulses: [JellyPulse] = []
    static let jellyWindow: Double = 0.6
    private var jellyArmedAt: Double = -1, jellyFirst: Double = 0
    static let jellyMaxRing: Double = 1.0           // never longer than a second in all: it is a settle, not a buzz
    private var jellyH: [Float] = []                 // the last three heights
    private var jellyT: [Double] = []
    private var jellyRest: Float = 0
    /// He was let go (or a press / pinch let go of him): for ~0.5 s the haptic is a few soft pulses, one at each squash peak of the body's
    /// own jiggle, fading as the jiggle does. Not for a grumpy touch (that stays a short stiff tick).
    func jellyLetGo(now: Double) {
        guard !annoyed else { return }
        if jellyArmedAt < 0 || now - jellyArmedAt > Self.jellyWindow { jellyH = []; jellyT = []; jellyFirst = now }          // already ringing (the landing after a drop): keep following it
        jellyArmedAt = now
    }

    /// Every frame: watches the body's height; at each local minimum (a squash peak) past a hair it fires one soft pulse.
    func jellyFrame(dt: Float, now: Double, sim: SoftBody) {
        guard jellyArmedAt >= 0 else { return }
        if now - jellyArmedAt > Self.jellyWindow || now - jellyFirst > Self.jellyMaxRing { jellyArmedAt = -1; return }
        if jellyRest == 0 { jellyRest = sim.restHeightExtent() }
        let h = sim.heightExtent()
        jellyH.append(h); jellyT.append(now)
        if jellyH.count > 3 { jellyH.removeFirst(); jellyT.removeFirst() }
        guard jellyH.count == 3 else { return }
        // a squash peak: the middle sample is the lowest and below the (slowly tracked) resting height
        if jellyH[1] < jellyH[0], jellyH[1] <= jellyH[2] {
            let a = jellyRest - jellyH[1]
            if a > 0.012 {
                let p = HapticMap.jellyPulse(amplitude: a)
                haptics.transient(now: now, intensity: p.intensity, sharpness: p.sharpness)
                jellyPulses.append(JellyPulse(t: jellyT[1], amplitude: a))
            }
        }
    }

    // MARK: soft walls at the edges of the close-up frame (a throw bounces off them, he never leaves the picture)

    /// World limits his whole body must stay inside while thrown (the stage derives them from the camera frustum at his depth).
    struct FrameLimits { var xMin: Float, xMax: Float, zMin: Float, zMax: Float, yMax: Float }
    private(set) var wallBounces = 0
    private var wallCool: Double = -1

    /// Keeps the thrown body inside `lim`: the whole body is shifted back and, if it was moving into the wall, it rebounds like a jelly ball
    /// (rebound 0.6 of the speed, a squash against the wall, a thump and the wobble). Counts as a bounce. No-op unless thrown.
    func wallsFrame(now: Double, sim: SoftBody, limits lim: FrameLimits) {
        guard thrown else { return }
        var b = sim.bounds()
        let m0 = sim.meanVelocity()
        let lead = m0 * 0.03                              // look one frame ahead: what is drawn after the next step is already inside
        b.hi += simd_max(lead, .zero); b.lo += simd_min(lead, .zero)
        var shift = SIMD3<Float>.zero
        var hits: [(axis: Int, sign: Float)] = []
        if b.hi.x > lim.xMax { shift.x = lim.xMax - b.hi.x; hits.append((0, 1)) }
        if b.lo.x < lim.xMin { shift.x = lim.xMin - b.lo.x; hits.append((0, -1)) }
        if b.hi.z > lim.zMax { shift.z = lim.zMax - b.hi.z; hits.append((2, 1)) }
        if b.lo.z < lim.zMin { shift.z = lim.zMin - b.lo.z; hits.append((2, -1)) }
        if b.hi.y > lim.yMax { shift.y = lim.yMax - b.hi.y; hits.append((1, 1)) }
        guard !hits.isEmpty else { return }
        if b.hi.x > lim.xMax && b.lo.x < lim.xMin { shift.x = 0.5 * (lim.xMin + lim.xMax) - 0.5 * (b.lo.x + b.hi.x) }      // wider than the frame: centre
        sim.translate(shift)
        let m = sim.meanVelocity()
        var dv = SIMD3<Float>.zero
        var strongest: Float = 0
        for h in hits {
            let vin = h.sign * m[h.axis]            // speed into the wall
            if vin > 0 { dv[h.axis] -= (1 + 0.6) * vin * h.sign; strongest = max(strongest, vin) }
        }
        if dv != .zero { for i in 0..<sim.n { sim.v[3 * i] += dv.x; sim.v[3 * i + 1] += dv.y; sim.v[3 * i + 2] += dv.z } }
        if strongest > 0.5, now - wallCool > 0.25 {
            wallCool = now
            wallBounces += 1; bounces += 1
            for h in hits where h.axis != 1 { sim.wallSquash(axis: h.axis, k: min(5, 1.6 * strongest + 1)) }
            haptics.impact(now: now, speed: max(1.2, strongest))
            haptics.wobble(now: now, peak: min(0.5, 0.15 + 0.08 * strongest))
        }
    }

    // MARK: landings (the drop after a pick up or a throw)

    private var fallMin: Float = 0
    private var sinceImpact: Float = 0
    private(set) var impacts = 0
    private(set) var lastImpactSpeed: Float = 0

    /// Watches his vertical speed: a hard stop after a fall is a landing -> a thump scaled by the impact speed, then the wobble rumble.
    func trackImpacts(now: Double, sim: SoftBody) {
        let vy = sim.meanVelocity().y
        if vy < fallMin { fallMin = vy }
        if fallMin < -0.9, vy > fallMin * 0.5 {
            let sp = -fallMin
            impacts += 1; lastImpactSpeed = sp; sinceImpact = 0
            haptics.impact(now: now, speed: sp)
            if thrown { haptics.wobble(now: now, peak: min(0.6, 0.2 + 0.08 * sp)) } else { jellyLetGo(now: now) }      // a plain landing: soft pulses on the real wobble
            sim.squashKick(min(4, 0.55 * sp))                     // a visible landing squash
            if thrown, getUpPhase == .off, floorBounces < Self.bounceRestitution.count, sp >= Self.bounceMinSpeed {
                // a jelly ball: rebound at a fraction of the impact speed (lower each time) and shed some sideways speed
                sim.bounce(up: Self.bounceRestitution[floorBounces] * sp, keepSideways: 0.55)
                floorBounces += 1; bounces += 1
            }
            fallMin = 0
        } else if vy > 0.2 { fallMin = 0 }
    }

    // MARK: cheeks

    private(set) var pinch: Float = 0
    /// The drawn squeeze: a spring toward `pinch`, so letting go pops the cheeks back with a little overshoot (a wobble).
    private(set) var visPinch: Float = 0
    private var visVel: Float = 0
    private var field: RestSurface.CheekField?
    private var cheekOn = false
    private var gap0: Float = 0
    private(set) var cheekReleases = 0
    private var cheekSlots = [false, false]

    /// Two fingers that both started on him. `rays` = the two finger rays (nil = not both down), `gap` = their screen distance.
    /// Each finger presses a sphere into a cheek; as they come together the presses deepen (the cheeks squeeze toward each other).
    func cheeksFrame(dt: Float, now: Double, rays: [(o: SIMD3<Float>, d: SIMD3<Float>)]?, gap: Float,
                     sim: SoftBody, brain: BlobBrain?, skinner: Skinner, surface: RestSurface?) {
        var target: Float = 0
        if let rays, rays.count == 2 {
            let g = gap.isFinite ? max(0, gap) : 0                 // a NaN / negative gap from a bad touch event reads as 0
            if !cheekOn { cheekOn = true; gap0 = max(g, 1); if annoyed { hmph(now: now) } }
            let pose = sim.bodyPose(iterations: 4)
            // the presses belong on the CHEEKS (beside and a little below the eyes), whatever height the fingers are at: each finger
            // picks a side from where it is on the face, then its press sits at that cheek and pushes inward and slightly forward
            var side: [Float] = [0, 0]
            for k in 0..<2 {
                let egg = BodyEllipsoid(sim: sim)
                var hit: BodyEllipsoid.Hit?
                if let rs = surface, egg.hit(origin: rays[k].o, dir: rays[k].d, inflate: 1.5) != nil {
                    hit = rs.hit(origin: rays[k].o, dir: rays[k].d, sim: sim, pose: pose)
                } else if surface == nil { hit = egg.hit(origin: rays[k].o, dir: rays[k].d) }
                side[k] = hit.map { $0.local.x >= 0 ? 1 : -1 } ?? 0
            }
            let hitSides = side
            // the squeeze only counts while BOTH fingers are really on his body (a ray that misses him pinches nothing)
            let bothOn = hitSides[0] != 0 && hitSides[1] != 0 && gap.isFinite
            target = bothOn ? HapticMap.clamp01((1 - g / gap0) / 0.5) : 0
            if side[0] == 0 { side[0] = side[1] == 0 ? 1 : -side[1] }
            if side[1] == 0 || side[1] == side[0] { side[1] = -side[0] }
            let right = pose.rotation.act(SIMD3<Float>(1, 0, 0))
            for k in 0..<2 {
                let l = SIMD3<Float>(side[k] * Self.cheekX, Self.cheekRY - 0.636, 0)
                if let h = surface?.front(local: l, sim: sim, pose: pose) {
                    let depth = 0.012 + 0.02 * pinch                   // the sim press is only a light assist; the squeeze itself is the skin offset
                    let inward = -right * side[k] * (0.03 * pinch)
                    if Self.cheekSimAssist { sim.setPress(center: h.point + h.normal * (Self.cheekRadius - depth) + inward, radius: Self.cheekRadius, slot: k); cheekSlots[k] = true }
                } else if cheekSlots[k] { sim.endPress(slot: k); cheekSlots[k] = false }
            }
        } else if cheekOn {
            // let go: the presses are gone at once, the cheeks pop back (the sim does the wobble); a bloop and a rumble
            cheekOn = false; cheekReleases += 1
            for k in 0..<2 where cheekSlots[k] { sim.endPress(slot: k); cheekSlots[k] = false }
            if annoyed { hmph(now: now) } else {
                let b = HapticMap.bloop(pinch: pinch)
                haptics.transient(now: now, intensity: b.intensity, sharpness: b.sharpness)
                jellyLetGo(now: now)               // the cheeks pop back: soft pulses on the real wobble
            }
        }
        pinch += (target - pinch) * (1 - expf(-dt * 12))
        if pinch < 0.004, !cheekOn { pinch = 0 }
        cheeksPinch = pinch
        // the drawn squeeze (underdamped spring: pops back with a wobble), as a smooth skin offset that is exactly 0 at rest
        // (sub-stepped: the explicit spring is only stable for omega * h < 2, and a hitched frame has dt up to 0.1 s, which used to blow
        // the offset up to many times the body size: the long skin streaks on the phone)
        let omega: Float = 24, zeta: Float = 0.30
        let steps = max(1, Int((min(max(dt, 0), 0.25) / (1.0 / 240)).rounded(.up)))
        let h = min(max(dt, 0), 0.25) / Float(steps)
        for _ in 0..<steps {
            visVel += (omega * omega * (pinch - visPinch) - 2 * zeta * omega * visVel) * h
            visPinch += visVel * h
        }
        if !visPinch.isFinite || !visVel.isFinite { visPinch = 0; visVel = 0 }
        visPinch = max(-0.4, min(1.3, visPinch)); visVel = max(-30, min(30, visVel))
        applyCheekSkin(sim: sim, skinner: skinner, surface: surface)
        updateEyes(skinner)
        annoyUpdate(dt: dt, active: cheekOn, side: 0)
        compose(brain)
        let sq = annoyed ? 0 : HapticMap.cheeksIntensity(pinch: pinch)       // grumpy: no soft press, just the stiff ticks
        if annoyed, cheekOn, pinch > 0.1 { train(dt: dt, hz: 3, now: now, intensity: 0.3, sharpness: 0.92) }
        haptics.update(now: now, petIntensity: 0, petSharpness: 0.1, squishIntensity: sq, squishSharpness: HapticMap.cheeksSharpness(pinch: pinch))
    }

    private func applyCheekSkin(sim: SoftBody, skinner: Skinner, surface: RestSurface?) {
        if abs(visPinch) < 0.002, abs(visVel) < 0.02, pinch == 0 {
            visPinch = 0; visVel = 0
            if !skinner.extraVertices.isEmpty { skinner.extraVertices = []; skinner.extraDelta = [] }
            return
        }
        guard let rs = surface else { return }
        if field == nil { field = rs.cheekField(restCentroid: sim.restCentroid, excluded: skinner.faceFeatureVertices) }
        guard let f = field else { return }
        let rot = sim.bodyPose(iterations: 4).rotation
        let k = visPinch
        var d = [SIMD3<Float>](repeating: .zero, count: f.vertices.count)
        for i in 0..<f.vertices.count {
            // each cheek moves inward, forward and a little down; the face between them puffs forward
            let inward = SIMD3<Float>(-(f.left[i] - f.right[i]) * 0.11, -(f.left[i] + f.right[i]) * 0.03, (f.left[i] + f.right[i]) * 0.06)
            let puff = SIMD3<Float>(0, -0.012, 0.05) * f.mid[i]
            var o = rot.act((inward + puff) * k)
            // never more than a small fraction of his height, and never NaN: the drawn skin cannot leave his body
            let m = simd_length(o), cap = Self.maxCheekOffset
            if !m.isFinite { o = .zero } else if m > cap { o *= cap / m }
            d[i] = o
        }
        skinner.extraVertices = f.vertices
        skinner.extraDelta = d
    }

    /// The finger's dent ends at once (the press turned out to be a pick up or a pinch, which have their own contacts).
    func releaseContact(sim: SoftBody) {
        sim.endPress()
        contact = false; ramp = 0; speed = 0; prevLocal = nil; lastHit = nil; easedCenter = nil; hitLocal = nil; zone = .none
    }

    /// Focus ended (or the mode changed): drop every contact and reaction at once.
    func cancel(sim: SoftBody, brain: BlobBrain?, skinner: Skinner) {
        guard isActive || sim.pressing else { return }
        sim.endPress()
        contact = false; ramp = 0; speed = 0; love = 0; movingT = 0; gapT = 0; happyOn = false; calmT = 0
        prevLocal = nil; hitLocal = nil; lastHit = nil; easedCenter = nil; lean = .zero; outRoll = 0; outPitch = 0; outSquash = 1; tiltRoll = 0; whoaT = 0; whoaPitch = 0; dizzy = 0; purrT = 0; purrOn = false; purrLevel = 0; zone = .none; boopT = 0; motionActive = false; squishDepth = 0; cheeksPinch = 0; pinch = 0; visPinch = 0; visVel = 0; cheekOn = false; cheekSlots = [false, false]; fallMin = 0; excitement = 0; heldPulse = 0; heldSway = 0; heldPulseSent = 0; heldT = 0; happyKick = 0; tapQueue = []; annoyK = 0; annoyPitch = 0; annoyRoll = 0; annoySquash = 1; hmphT = 0; hearts.removeAll()
        brain?.clearTouch()
        brain?.endExcited()
        brain?.hurry = false
        skinner.extraVertices = []; skinner.extraDelta = []; skinner.normalSmoothing = 0
        if eyesTouched { eyesTouched = false; skinner.setEyeOpenness(1); skinner.autoBlink = savedAutoBlink }
        haptics.update(now: CACurrentMediaTime(), petIntensity: 0, petSharpness: 0.1, squishIntensity: 0, squishSharpness: 0.5)
    }
}
