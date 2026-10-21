//
//  SleepMask.swift
//  The little SLEEP EYE MASK (user 2026-10-19: "put a little eye mask on them when they're asleep that poofs away when they wake up").
//
//  A real 3D prop, like the dining tray: a soft padded band over the closed eyes with a thin strap round the head, built ONCE in the body's REST space
//  from the locked form (`BobForm`, read-only) and carried by the sim body's fitted pose (the same `bodyPointWorld` maths the fork uses), so it follows
//  him as he lies on his back and breathes. Colour per Jelly: navy on blue Bob, lavender on yellow Pip, rose on green Moss.
//
//  Lifecycle (`SleepMaskSet.tick`, once per fixed step, no change to the sleep code): the mask is wanted exactly while `brain.isNapping` (settled on
//  his back, eyes shut, not waking) and never in a race. A rising edge poofs it IN (the one `PuffEffect` + the tray's springy pop, 0.25 s); the falling
//  edge, which EVERY way out of sleep produces (tap, request, race wake, morning, abortAll / pick up), poofs it AWAY (puff + shrink).
//  The set lives on GameCare; `RoomRenderer.setMasks` draws its meshes (opaque band + translucent puffs).
//

import simd
import Foundation

nonisolated enum SleepMaskTuning {
    static let popTime: Float = 0.25
    static let poofTime: Float = DiningCurve.poofDuration
    static let puffRadius: Float = 0.24
    /// Quiet pop (the bath's bubble pop is 0.6).
    static let soundVolume: Float = 0.3
    /// The z's: one about every 1.5...2.5 s per sleeper, at most 3 alive, 3.4 s life; they fade 4x faster once he starts to wake.
    static let zInterval: ClosedRange<Float> = 1.5...2.5
    static let zMax = 3
    /// Fraction of the roll back at which the mask poofs away.
    static let holdRoll: Float = 0.5
    static let zLife: Float = 3.4
    static let zFastFade: Float = 4
}

/// The little Z: a soft, chunky, extruded letter (unit height, facing +z), built once and instanced by transform (one mesh, a few draws' worth of vertices).
nonisolated enum ZLetterModel {
    static let mesh: RoomMesh = {
        let b = RoomMeshBuilder()
        b.material = .plain
        let col = Consumables.srgb(0.97, 0.97, 1.0)
        func poly(_ up: [(Float, Float)]) -> [SIMD2<Float>] { up.map { SIMD2($0.0, -$0.1) } }      // (x, up) -> (x, z) with up = -z
        let parts: [[SIMD2<Float>]] = [
            poly([(-0.30, 0.30), (0.30, 0.30), (0.30, 0.50), (-0.30, 0.50)]),                       // top bar
            poly([(-0.30, -0.50), (0.30, -0.50), (0.30, -0.30), (-0.30, -0.30)]),                   // bottom bar
            poly([(0.06, 0.31), (0.30, 0.31), (-0.06, -0.31), (-0.30, -0.31)]),                     // the slash
        ]
        for p in parts { DiningModels.extrudeRounded(b, poly: p, y0: -0.1, y1: 0.1, bevel: 0.07, color: col) }
        // extrusion axis y -> depth z, letter "up" (-z) -> y
        var m = b.mesh
        for i in m.vertices.indices {
            let v = m.vertices[i]
            m.vertices[i].pos = SIMD4(v.pos.x, -v.pos.z, v.pos.y, v.pos.w)
            m.vertices[i].normal = SIMD4(v.normal.x, -v.normal.z, v.normal.y, v.normal.w)
        }
        return m
    }()
}

/// The mask mesh in the body's rest space (y up, face toward +z) and how it is carried to the world.
nonisolated enum EyeMaskModel {
    struct Rest {
        var pos: [SIMD3<Float>] = [], nrm: [SIMD3<Float>] = [], col: [SIMD3<Float>] = [], idx: [UInt32] = []
        /// Where it scales about / where the puff sits: just in front of the closed eyes.
        var pivot = SIMD3<Float>.zero
    }

    /// One mask palette per CHARACTER (JellyRoster.characterCount: Bob, Pip, Moss, Lavender); SleepMaskSet maps a slot to its character.
    static let paletteCount = 4
    /// Band and piping colours (linear) by Jelly id: contrast with the body (blue, yellow, green, lavender).
    static func palette(_ id: Int) -> (band: SIMD3<Float>, piping: SIMD3<Float>) {
        let c = Consumables.self
        switch ((id % paletteCount) + paletteCount) % paletteCount {
        case 0:  return (c.srgb(0.15, 0.19, 0.46), c.srgb(0.50, 0.58, 0.90))        // navy on blue Bob
        case 1:  return (c.srgb(0.60, 0.48, 0.90), c.srgb(0.85, 0.78, 0.98))        // lavender on yellow Pip
        case 2:  return (c.srgb(0.90, 0.40, 0.55), c.srgb(0.99, 0.78, 0.84))        // rose on green Moss
        default: return (c.srgb(0.86, 0.62, 0.22), c.srgb(0.99, 0.88, 0.62))        // honey on lavender Lavender
        }
    }

    static let eyeLine: Double = 0.82           // BobForm.eyeY
    static let padCentreY: Double = 0.828

    /// One rest mesh per palette (built once).
    static let rests: [Rest] = (0..<paletteCount).map { build(id: $0) }

    // MARK: rest-space helpers (egg only: the eyes and the head are on it, the arms are far below)

    private static func frontSurface(x: Double, y: Double) -> SIMD3<Double> {
        var lo = 0.0, hi = 1.2
        for _ in 0..<40 {
            let m = 0.5 * (lo + hi)
            if BobForm.bodySDF(SIMD3(x, y, m)) < 0 { lo = m } else { hi = m }
        }
        return SIMD3(x, y, 0.5 * (lo + hi))
    }
    private static func normal(_ p: SIMD3<Double>) -> SIMD3<Double> {
        let e = 0.0015
        let g = SIMD3(BobForm.bodySDF(p + SIMD3(e, 0, 0)) - BobForm.bodySDF(p - SIMD3(e, 0, 0)),
                      BobForm.bodySDF(p + SIMD3(0, e, 0)) - BobForm.bodySDF(p - SIMD3(0, e, 0)),
                      BobForm.bodySDF(p + SIMD3(0, 0, e)) - BobForm.bodySDF(p - SIMD3(0, 0, e)))
        return simd_length(g) > 1e-12 ? simd_normalize(g) : SIMD3(0, 0, 1)
    }
    private static func f(_ v: SIMD3<Double>) -> SIMD3<Float> { SIMD3(Float(v.x), Float(v.y), Float(v.z)) }
    private static func smooth(_ a: Float, _ b: Float, _ x: Float) -> Float { let t = min(max((x - a) / (b - a), 0), 1); return t * t * (3 - 2 * t) }

    static func build(id: Int) -> Rest {
        let pal = palette(id)
        let b = RoomMeshBuilder()
        b.material = .plain

        // ---- the pad: a two-lobed, rounded outline (narrow at the nose bridge) as a soft dome on the front of the head
        let K = 9, N = 52
        let ax = 0.38
        func uExp(_ v: Double) -> Double { (v < 0 ? -1 : 1) * pow(abs(v), 2.0 / 3.0) }
        func halfHeight(_ ux: Double) -> Double { 0.115 + 0.075 * ux * ux }
        func thick(_ rho: Double) -> Double { 0.014 + 0.075 * pow(max(0, 1 - rho * rho), 0.5) }
        var rows: [[UInt32]] = []
        func padVertex(rho: Double, phi: Double, extra: Double = 0, rimPush: Double = 0) -> UInt32 {
            let ux = uExp(cos(phi)), uy = uExp(sin(phi))
            let x = rho * ax * ux, y = padCentreY + rho * halfHeight(ux) * uy
            let s = frontSurface(x: x, y: y)
            let n = normal(s)
            let p = s + n * (thick(rho) + extra)
            let tx = simd_normalize(SIMD3(1, 0, 0) - n * n.x)
            let ty = simd_cross(n, tx)
            let slope = rho * rho * 0.8 + rimPush
            let nn = simd_normalize(n + (tx * cos(phi) + ty * sin(phi)) * slope)
            let piping = smooth(0.82, 0.9, Float(rho))
            return b.vertex(f(p), f(nn), ao: 1, color: simd_mix(pal.band, pal.piping, SIMD3(repeating: piping)))
        }
        for k in 0...K {
            let rho = sin(Double(k) / Double(K) * .pi / 2)
            rows.append((0..<N).map { padVertex(rho: rho, phi: Double($0) / Double(N) * 2 * .pi) })
        }
        for r in 0..<K { for i in 0..<N { b.quad(rows[r][i], rows[r][(i + 1) % N], rows[r + 1][(i + 1) % N], rows[r + 1][i]) } }
        // skirt: the rim drops into the skin so there is no gap under the edge
        let rimOut = (0..<N).map { padVertex(rho: 1, phi: Double($0) / Double(N) * 2 * .pi, rimPush: 0.5) }
        let rimIn = (0..<N).map { padVertex(rho: 1, phi: Double($0) / Double(N) * 2 * .pi, extra: -0.05, rimPush: 1.0) }
        for i in 0..<N { b.quad(rimOut[i], rimOut[(i + 1) % N], rimIn[(i + 1) % N], rimIn[i]) }

        // ---- the strap: a thin flat band round the head at the eye line, starting under the pad's sides
        let M = 56, th0 = 0.55
        let strapCol = pal.band * 0.82
        var strap: [[UInt32]] = []
        for v in [-1.0, -0.5, 0.0, 0.5, 1.0] {
            var row: [UInt32] = []
            for j in 0...M {
                let th = th0 + Double(j) / Double(M) * (2 * .pi - 2 * th0)
                let y = eyeLine + v * 0.045
                var lo = 0.0, hi = 1.3
                for _ in 0..<36 {
                    let m = 0.5 * (lo + hi)
                    if BobForm.bodySDF(SIMD3(sin(th) * m, y, cos(th) * m)) < 0 { lo = m } else { hi = m }
                }
                let r = 0.5 * (lo + hi)
                let p = SIMD3(sin(th) * r, y, cos(th) * r)
                let n = normal(p)
                let q = p + n * (0.014 + 0.012 * (1 - v * v))
                let nn = simd_normalize(n + SIMD3(0, v, 0) * 0.45)
                let edge = abs(v) > 0.9 ? 0.0 : 1.0
                row.append(b.vertex(f(q), f(nn), ao: 1, color: simd_mix(pal.piping * 0.9, strapCol, SIMD3(repeating: Float(edge)))))
            }
            strap.append(row)
        }
        for r in 0..<(strap.count - 1) { for j in 0..<M { b.quad(strap[r][j], strap[r][j + 1], strap[r + 1][j + 1], strap[r + 1][j]) } }

        var rest = Rest()
        for v in b.mesh.vertices {
            rest.pos.append(SIMD3(v.pos.x, v.pos.y, v.pos.z)); rest.nrm.append(SIMD3(v.normal.x, v.normal.y, v.normal.z))
            rest.col.append(SIMD3(v.color.x, v.color.y, v.color.z))
        }
        rest.idx = b.mesh.indices
        let s = frontSurface(x: 0, y: padCentreY)
        rest.pivot = f(s + normal(s) * 0.05)
        return rest
    }

    /// The body's pose as the fork / straw use it: rest point -> world through the fitted rigid pose and the crouch squash.
    struct Carry {
        var centroid = SIMD3<Float>.zero
        var rotation = simd_quatf(angle: 0, axis: SIMD3(0, 1, 0))
        var squash: Float = 1
        var restCentroid = SIMD3<Float>.zero
        func world(_ rest: SIMD3<Float>) -> SIMD3<Float> {
            let sxz = 1 / squash.squareRoot(), o = rest - restCentroid
            return centroid + simd_float3x3(rotation) * SIMD3(o.x * sxz, o.y * squash, o.z * sxz)
        }
    }

    /// Appends the mask at `scale` (about the pivot, in front of the eyes) to `b`.
    static func append(id: Int, to b: RoomMeshBuilder, scale s: Float, carry: Carry) {
        let r = rests[((id % paletteCount) + paletteCount) % paletteCount]
        let base = UInt32(b.mesh.vertices.count)
        let R = simd_float3x3(carry.rotation)
        b.mesh.vertices.reserveCapacity(b.mesh.vertices.count + r.pos.count)
        for i in 0..<r.pos.count {
            let p = carry.world(r.pivot + (r.pos[i] - r.pivot) * s)
            let n = R * r.nrm[i]
            b.mesh.vertices.append(RoomVertex(pos: SIMD4(p, RoomMaterial.plain.rawValue), normal: SIMD4(n, 1), color: SIMD4(r.col[i], 1)))
        }
        for i in r.idx { b.mesh.indices.append(i + base) }
    }
}

/// The masks of every Jelly: state per Jelly, the shared puffs, the sound and the meshes for the renderer.
@MainActor
final class SleepMaskSet {
    enum Phase { case hidden, popIn, shown, poofOut }
    struct Slot {
        var phase: Phase = .hidden
        var t: Float = 0
        var scale: Float = 0
        var from: Float = 1
        var carry = EyeMaskModel.Carry()
        var zs: [ZPuff] = []
        var zTimer: Float = 1
        var zSeed: UInt32 = 1
    }
    struct ZPuff {
        var age: Float = 0
        var origin = SIMD3<Float>.zero
        var phase: Float = 0
        var size: Float = 1
    }
    private(set) var slots: [Slot] = []
    let puffs = PuffEffect()
    /// Test / debug counters.
    private(set) var puffSpawns = 0, popIns = 0, poofOuts = 0, zSpawns = 0
    var soundOn = true
    private var puffSphere = RoomMesh()
    private var sphereTint: SIMD3<Float>?

    nonisolated deinit {}

    func phase(_ id: Int) -> Phase { slots.indices.contains(id) ? slots[id].phase : .hidden }
    func scale(_ id: Int) -> Float { slots.indices.contains(id) ? slots[id].scale : 0 }
    func isShown(_ id: Int) -> Bool { scale(id) > 0.001 }
    var anyShown: Bool { slots.contains { $0.scale > 0.001 } }
    func liveZ(_ id: Int) -> Int { slots.indices.contains(id) ? slots[id].zs.count : 0 }
    var anyZ: Bool { slots.contains { !$0.zs.isEmpty } }
    var isActive: Bool { anyShown || puffs.isActive || anyZ }

    /// He wears it exactly while he is settled asleep on his back (eyes shut, not waking), never in a race.
    static func wanted(_ brain: BlobBrain) -> Bool { brain.isNapping && !brain.race.active }
    /// While waking, a mask that is on stays until the roll back is about half done (not in a race; not for a pick up / abort, which end the sleep at once).
    static func lingers(_ brain: BlobBrain) -> Bool {
        brain.idleState.kind == .sleep && brain.sleep.stage == 4 && brain.sleep.kStart > 0.99 && brain.sleep.t < SleepTuning.rollBackTime * SleepMaskTuning.holdRoll && !brain.race.active
    }

    func reset() { slots = slots.map { _ in Slot() }; puffs.reset() }

    /// Once per fixed step for Jelly `id`. `raceBusy`: the Circuit is on (nothing is put on, whatever he is doing).
    func tick(id: Int, brain: BlobBrain, sim: SoftBody, raceBusy: Bool = false, dt: Float) {
        while slots.count <= id { slots.append(Slot()) }
        let strict = Self.wanted(brain) && !raceBusy
        let on = slots[id].phase == .popIn || slots[id].phase == .shown
        let want = strict || (on && Self.lingers(brain) && !raceBusy)
        var s = slots[id]
        switch s.phase {
        case .hidden:
            if want { s.phase = .popIn; s.t = 0; s.scale = 0; popIns += 1; carry(&s, sim); poof(id, brain, s) }
        case .popIn:
            s.t += dt
            if !want { startOut(&s, id, brain, sim) }
            else if s.t >= SleepMaskTuning.popTime { s.phase = .shown; s.scale = 1 }
            else { s.scale = DiningCurve.pop(s.t / SleepMaskTuning.popTime) }
        case .shown:
            if !want { startOut(&s, id, brain, sim) } else { s.scale = 1 }
        case .poofOut:
            s.t += dt
            if s.t >= SleepMaskTuning.poofTime { s.phase = .hidden; s.scale = 0 }
            else { s.scale = s.from * DiningCurve.poof(s.t / SleepMaskTuning.poofTime) }
        }
        if s.phase != .hidden { carry(&s, sim) }
        if raceBusy || brain.race.active { s.zs = [] }          // never a z in a race
        tickZ(&s, id: id, want: strict, dt: dt, wasShown: slots[id].phase == .shown)
        slots[id] = s
    }

    private func rnd(_ s: inout Slot) -> Float { s.zSeed = s.zSeed &* 1664525 &+ 1013904223; return Float(s.zSeed >> 8) / Float(1 << 24) }

    /// The z's: spawned only while he sleeps fully (the mask is on and he is not waking), each one rises, drifts, grows and fades.
    private func tickZ(_ s: inout Slot, id: Int, want: Bool, dt: Float, wasShown: Bool) {
        if s.zs.isEmpty, s.phase == .hidden { s.zTimer = 0.9 + 0.7 * Float(id); s.zSeed = UInt32(truncatingIfNeeded: id &* 7919 &+ 17) }
        let sleeping = s.phase == .shown && want
        let rate: Float = sleeping ? 1 : SleepMaskTuning.zFastFade
        for i in s.zs.indices { s.zs[i].age += dt * rate }
        s.zs.removeAll { $0.age >= SleepMaskTuning.zLife }
        guard sleeping else { if !want && s.phase != .popIn { s.zTimer = max(s.zTimer, 0.8) }; return }
        s.zTimer -= dt
        if s.zTimer <= 0 {
            if s.zs.count < SleepMaskTuning.zMax { spawnZ(&s, id: id, size: 1) }
            s.zTimer = SleepMaskTuning.zInterval.lowerBound + rnd(&s) * (SleepMaskTuning.zInterval.upperBound - SleepMaskTuning.zInterval.lowerBound)
        }
    }
    private func spawnZ(_ s: inout Slot, id: Int, size: Float) {
        let pivot = EyeMaskModel.rests[((id % EyeMaskModel.paletteCount) + EyeMaskModel.paletteCount) % EyeMaskModel.paletteCount].pivot
        let o = s.carry.world(pivot) + SIMD3(0.04 * Float(id % 3 - 1), 0.1, 0)
        s.zs.append(ZPuff(age: 0, origin: o, phase: rnd(&s) * 6.28, size: size * (0.85 + 0.3 * rnd(&s))))
        zSpawns += 1
    }
    /// A snore: a slightly bigger z rides it (the audio hub calls this for the Jelly that snores).
    func snore(_ id: Int) {
        guard slots.indices.contains(id), slots[id].phase == .shown, slots[id].zs.count < SleepMaskTuning.zMax else { return }
        var s = slots[id]
        spawnZ(&s, id: id, size: 1.2)
        s.zTimer = max(s.zTimer, 1.2)
        slots[id] = s
    }
    /// Once per fixed step after every Jelly's `tick`: the puffs age.
    func stepPuffs(dt: Float) { puffs.update(dt: dt) }

    private func startOut(_ s: inout Slot, _ id: Int, _ brain: BlobBrain, _ sim: SoftBody) {
        s.phase = .poofOut; s.t = 0; s.from = max(s.scale, 0.001); poofOuts += 1
        carry(&s, sim); poof(id, brain, s)
    }
    private func carry(_ s: inout Slot, _ sim: SoftBody) {
        let p = sim.bodyPose(iterations: 3)
        s.carry = EyeMaskModel.Carry(centroid: p.centroid, rotation: p.rotation, squash: sim.attractor.squash, restCentroid: sim.restCentroid)
    }
    private func poof(_ id: Int, _ brain: BlobBrain, _ s: Slot) {
        let pivot = EyeMaskModel.rests[((id % EyeMaskModel.paletteCount) + EyeMaskModel.paletteCount) % EyeMaskModel.paletteCount].pivot
        puffs.spawn(at: s.carry.world(pivot), radius: SleepMaskTuning.puffRadius)
        puffSpawns += 1
        if soundOn { AudioHub.shared.play(.bubblepop, jelly: id, x: brain.px, volume: SleepMaskTuning.soundVolume) }
    }

    /// The live z's of one Jelly (world space, translucent): rise, drift sideways with a sway, grow a little, fade in and out; always facing the camera.
    static func appendZ(_ s: Slot, to b: RoomMeshBuilder) {
        for z in s.zs {
            let u = min(z.age / SleepMaskTuning.zLife, 1)
            let rise = 1 - powf(1 - u, 1.6)
            let sway = 0.07 * sinf(z.phase + u * 5.5)
            let p = z.origin + SIMD3(0.30 * u + sway, 0.85 * rise, 0)
            let fadeIn = min(u / 0.15, 1), o = min(max((u - 0.5) / 0.5, 0), 1)
            let a = 0.92 * fadeIn * (1 - o * o * (3 - 2 * o))
            guard a > 0.01 else { continue }
            let h = 0.2 * z.size * (0.55 + 0.6 * u)
            let yaw = atan2f(GameCamera.eye.x - p.x, GameCamera.eye.z - p.z)
            let tilt = 0.14 * sinf(z.phase + u * 3)
            let rz = simd_float4x4(columns: (SIMD4(cosf(tilt), sinf(tilt), 0, 0), SIMD4(-sinf(tilt), cosf(tilt), 0, 0), SIMD4(0, 0, 1, 0), SIMD4(0, 0, 0, 1)))
            DiningModels.append(ZLetterModel.mesh, to: b, transform: DiningModels.translation(p, scale: h, yaw: yaw) * rz, alpha: a)
        }
    }

    /// The opaque masks and the translucent puffs (world space). Empty while `hidden` (the race track, the bathroom).
    func frame(theme: RoomTheme, hidden: Bool = false) -> (opaque: RoomMesh, translucent: RoomMesh) {
        let op = RoomMeshBuilder(), tr = RoomMeshBuilder()
        op.material = .plain; tr.material = .plain
        guard !hidden else { return (op.mesh, tr.mesh) }
        for (i, s) in slots.enumerated() where s.scale > 0.001 { EyeMaskModel.append(id: JellyRoster.character(i), to: op, scale: s.scale, carry: s.carry) }     // the mask palette is the character's
        for s in slots { Self.appendZ(s, to: tr) }
        if puffs.isActive {
            if sphereTint != theme.tint { puffSphere = DiningModels.puffSphere(theme: theme); sphereTint = theme.tint }
            puffs.append(to: tr, sphere: puffSphere)
        }
        return (op.mesh, tr.mesh)
    }
}
