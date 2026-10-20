//
//  WornSet.swift
//  What every Jelly wears on screen: the state machine (a piece poofs ON, stays, poofs OFF with a puff and a quiet pop, exactly like the sleep mask), the hide
//  rules, and the per-frame world mesh. Rigid pieces ride the body's fitted pose + squash (EyeMaskModel.Carry), surface-bound pieces follow the SKINNED
//  surface under them (WearBody.world, read from the CPU-skinned vertex buffer, so they move with the local jiggle), hanging parts add a cheap spring swing,
//  and the mitts / wristbands follow the posed arm capsule frame (A, B, r2).
//
//  Hide rules (WearRules.hide): hats and face items are off while he lies down to sleep and sleeps (the mask takes their place) and back when the roll
//  back is half done; sunglasses are off while he eats; tall hats, ears, the cape and the backpack are off during flips and rolls; everything is off in
//  the wash. Hats stay on in a race (the player's; the rivals wear only their numbered bib).
//
//  Arm gloves and ArmCap: a glove is a skin over the arm capsule's tip (at most 1.15x its radius, the axial extent clamped to the capsule's end), so it
//  never adds exposed arm length; the cap measures the capsule (ArmCapTests) and the glove has its own bound test (WearTests).
//

import simd
import Foundation

nonisolated enum WearTuning {
    static let popTime: Float = 0.25
    static let poofTime: Float = DiningCurve.poofDuration
    static let puffRadius: Float = 0.2
    static let soundVolume: Float = 0.22
    /// Hanging parts: spring (rad/s), damping ratio, how hard body acceleration pushes, the largest swing (world units).
    static let swingOmega: Float = 11, swingZeta: Float = 0.28, swingGain: Float = 0.012, swingMax: Float = 0.09
    /// Propeller spin (rad/s).
    static let spin: Float = 14
    static let propellerCentre = SIMD3<Float>(0, 1.4408, 0)
    /// Glove geometry never reaches further than this many arm radii from the capsule axis, nor past the tip.
    static let gloveRadiusLimit: Float = 1.15
}

/// Where the posed arm is: tip centre B, shoulder end A (world), tip radius, and the body's forward axis.
nonisolated struct ArmFrameWorld: Sendable {
    var a = SIMD3<Float>.zero, b = SIMD3<Float>.zero
    var r2: Float = 0.15
    var forward = SIMD3<Float>(0, 0, 1)
}

/// The Circuit role of a Jelly while a race trip is on.
nonisolated enum WearRaceRole: Equatable, Sendable {
    case none
    case player(team: WearTeam, number: Int)
    case rival(team: WearTeam, number: Int)
}

@MainActor
final class WornSet {
    enum Phase { case hidden, popIn, shown, poofOut }
    struct Item {
        var look: WearLook?
        var phase: Phase = .hidden
        var t: Float = 0
        var scale: Float = 0
        var from: Float = 1
    }
    struct Slot {
        var items: [WearSlot: Item] = [:]
        var carry = EyeMaskModel.Carry()
        var primed = false
        /// Hanging parts' world-space lag and its velocity.
        var swing = SIMD3<Float>.zero, swingV = SIMD3<Float>.zero
        var lastCentroid = SIMD3<Float>.zero, lastVel = SIMD3<Float>.zero
        var role = WearRaceRole.none
        /// The jersey (shader band) and the numbered bib this Jelly shows now.
        var jersey: WearTeam?
        var bib: (team: WearTeam, number: Int)?
        var hideAll = false
        var arms: [ArmFrameWorld] = [ArmFrameWorld(), ArmFrameWorld()]
    }
    private(set) var slots: [Slot] = []
    /// One world box per Jelly that wears something, from the last `frame` (the room cache re-shades them).
    private(set) var lastBounds: [(lo: SIMD3<Float>, hi: SIMD3<Float>)] = []
    let puffs = PuffEffect()
    var soundOn = true
    /// The fitting room shows the piece whatever the Jelly is doing.
    var ignoreHide = false
    private(set) var puffSpawns = 0, popIns = 0, poofOuts = 0
    private var puffSphere = RoomMesh()
    private var sphereTint: SIMD3<Float>?
    var body: WearBody?

    nonisolated deinit {}

    // MARK: queries

    func item(_ id: Int, _ s: WearSlot) -> Item? { slots.indices.contains(id) ? slots[id].items[s] : nil }
    /// The piece of this slot that is on screen (scale > 0) now.
    func shown(_ id: Int, _ s: WearSlot) -> WearLook? { item(id, s).flatMap { $0.scale > 0.001 ? $0.look : nil } }
    func jersey(_ id: Int) -> WearTeam? { slots.indices.contains(id) ? slots[id].jersey : nil }
    var anyShown: Bool { slots.contains { $0.items.values.contains { $0.scale > 0.001 } || $0.bib != nil } }
    var isActive: Bool { anyShown || puffs.isActive }
    func reset() { slots = slots.map { _ in Slot() }; puffs.reset() }

    // MARK: hide rules

    /// He is lying down to sleep, asleep, or the roll back is not yet half done: hats and face items stay off (the mask takes their place).
    static func sleepHides(_ b: BlobBrain) -> Bool {
        guard b.idleState.kind == .sleep else { return false }
        let st = b.sleep.stage
        if st == 2 || st == 3 { return true }
        return st == 4 && b.sleep.t < SleepTuning.rollBackTime * SleepMaskTuning.holdRoll
    }
    static func eating(_ b: BlobBrain) -> Bool {
        switch b.script { case .dine, .eat: return true; default: return false }
    }
    static func flipping(_ b: BlobBrain) -> Bool {
        if b.isFlipping { return true }
        if case .rollPlay = b.script { return true }
        return b.idleState.kind == .roll
    }
    /// Does a hide rule hide `look` for this Jelly right now (the wash is handled by `hideAll`)?
    static func hidden(_ look: WearLook, _ b: BlobBrain) -> Bool {
        let h = WearRules.hide(look)
        if h.contains(.asleep), sleepHides(b) { return true }
        if h.contains(.eating), eating(b) { return true }
        if h.contains(.flip), flipping(b) { return true }
        return false
    }

    // MARK: tick

    /// Once per fixed step for Jelly `id`.
    func tick(id: Int, brain: BlobBrain, sim: SoftBody, outfit: [WearSlot: WearLook], role: WearRaceRole, hideAll: Bool, dt: Float) {
        while slots.count <= id { slots.append(Slot()) }
        var s = slots[id]
        let pose = sim.bodyPose(iterations: 3)
        s.carry = EyeMaskModel.Carry(centroid: pose.centroid, rotation: pose.rotation, squash: sim.attractor.squash, restCentroid: sim.restCentroid)
        s.role = role; s.hideAll = hideAll
        stepSwing(&s, dt: dt)
        var burst = false
        var jerseyTeam: WearTeam?
        for slot in WearSlot.allCases where slot != .feet {
            var want = outfit[slot]
            switch role {
            case .rival: want = nil
            case .player: if slot == .body { want = nil }
            case .none: break
            }
            var it = s.items[slot] ?? Item()
            let hide = hideAll || (!ignoreHide && (want.map { Self.hidden($0, brain) } ?? false))
            let desired = hide ? nil : want
            if hideAll || !s.primed {                                // the wash / the first frame: no puff, just there or not
                it.look = desired; it.phase = desired == nil ? .hidden : .shown; it.scale = desired == nil ? 0 : 1; it.t = 0
            } else {
                step(&it, desired: desired, dt: dt, spawn: { [self] in spawnPuff(id: id, look: $0, carry: s.carry); burst = true })
            }
            s.items[slot] = it
            if slot == .body, let l = it.look, it.scale > 0.001 { jerseyTeam = Self.jerseyTeam(of: l) }
        }
        switch role {
        case .player(let team, let n): s.jersey = team; s.bib = (team, n)
        case .rival(let team, let n): s.jersey = team; s.bib = (team, n)
        case .none:
            s.jersey = jerseyTeam
            if let t = jerseyTeam, let l = s.items[.body]?.look, Self.isBib(l) { s.bib = (t, WearTeam.playerNumber(roster: id)) } else { s.bib = nil }
        }
        if hideAll { s.jersey = nil; s.bib = nil }
        s.primed = true
        slots[id] = s
        if burst, soundOn { AudioHub.shared.play(.bubblepop, jelly: id, x: brain.px, volume: WearTuning.soundVolume) }
    }

    static func jerseyTeam(of l: WearLook) -> WearTeam? {
        switch l { case .bibSky, .sashSky: return .sky; case .bibPink, .sashPink: return .pink; default: return nil }
    }
    static func isBib(_ l: WearLook) -> Bool { l == .bibSky || l == .bibPink }

    private func step(_ it: inout Item, desired: WearLook?, dt: Float, spawn: (WearLook) -> Void) {
        switch it.phase {
        case .hidden:
            if let d = desired { it.look = d; it.phase = .popIn; it.t = 0; it.scale = 0; popIns += 1; spawn(d) }
        case .popIn:
            it.t += dt
            if desired != it.look { startOut(&it, spawn) }
            else if it.t >= WearTuning.popTime { it.phase = .shown; it.scale = 1 }
            else { it.scale = DiningCurve.pop(it.t / WearTuning.popTime) }
        case .shown:
            if desired != it.look { startOut(&it, spawn) } else { it.scale = 1 }
        case .poofOut:
            it.t += dt
            if it.t >= WearTuning.poofTime { it.phase = .hidden; it.scale = 0; it.look = nil }
            else { it.scale = it.from * DiningCurve.poof(it.t / WearTuning.poofTime) }
        }
    }
    private func startOut(_ it: inout Item, _ spawn: (WearLook) -> Void) {
        it.phase = .poofOut; it.t = 0; it.from = max(it.scale, 0.001); poofOuts += 1
        if let l = it.look { spawn(l) }
    }
    private func spawnPuff(id: Int, look: WearLook, carry: EyeMaskModel.Carry) {
        puffs.spawn(at: carry.world(look.row.anchorRest == .zero ? SIMD3(0, 0.5, 0) : look.row.anchorRest), radius: WearTuning.puffRadius)
        puffSpawns += 1
    }
    func stepPuffs(dt: Float) { puffs.update(dt: dt) }

    /// A critically-ish damped spring chasing "no lag"; the body's acceleration pushes it the other way (a hanging scarf tail trails the walk).
    private func stepSwing(_ s: inout Slot, dt: Float) {
        let v = (s.carry.centroid - s.lastCentroid) / max(dt, 1e-4)
        let acc = (v - s.lastVel) / max(dt, 1e-4)
        s.lastCentroid = s.carry.centroid; s.lastVel = v
        guard s.primed else { return }
        let w = WearTuning.swingOmega, z = WearTuning.swingZeta
        let push = -acc * WearTuning.swingGain * 0.05
        s.swingV += (-w * w * s.swing - 2 * z * w * s.swingV + push * w * w) * dt
        s.swing += s.swingV * dt
        let l = simd_length(s.swing)
        if l > WearTuning.swingMax { s.swing *= WearTuning.swingMax / l }
        if !(l.isFinite) { s.swing = .zero; s.swingV = .zero }
    }

    /// Stores the posed arm frames of Jelly `id` (world), from the brain (GameCare+Wear).
    func setArms(_ id: Int, _ f: [ArmFrameWorld]) { if slots.indices.contains(id) { slots[id].arms = f } }

    // MARK: frame

    /// Everything worn, in world space. `skin(id)` = the Jelly's CPU-skinned vertex stream (6 floats per vertex), nil = rigid only.
    func frame(theme: RoomTheme, hidden: Bool = false, time: Float, skin: (Int) -> UnsafePointer<Float>?) -> (opaque: RoomMesh, translucent: RoomMesh) {
        var op = RoomMesh()
        let tr = RoomMeshBuilder(); tr.material = .plain
        lastBounds = []
        guard !hidden else { return (op, tr.mesh) }
        for (id, s) in slots.enumerated() {
            let sk = skin(id)
            let first = op.vertices.count
            defer {
                if op.vertices.count > first {
                    var lo = SIMD3<Float>(repeating: .infinity), hi = SIMD3<Float>(repeating: -.infinity)
                    for v in op.vertices[first...] { let q = SIMD3(v.pos.x, v.pos.y, v.pos.z); lo = simd_min(lo, q); hi = simd_max(hi, q) }
                    lastBounds.append((lo, hi))
                }
            }
            for (slot, it) in s.items where it.scale > 0.001 {
                guard let look = it.look, let body, let p = WearMeshes.prepare(look, body: body) else { continue }
                if slot == .hands { Self.emitArms(p, into: &op, slot: s, scale: it.scale) }
                else { Self.emit(p, into: &op, slot: s, skin: sk, scale: it.scale, time: time) }
            }
            if let b = s.bib, let body, let p = WearMeshes.bib(team: b.team, number: b.number, body: body) {
                let sc: Float = s.role == .none ? (s.items[.body]?.scale ?? 0) : 1
                if sc > 0.001 { Self.emit(p, into: &op, slot: s, skin: sk, scale: sc, time: time) }
            }
        }
        if puffs.isActive {
            if sphereTint != theme.tint { puffSphere = DiningModels.puffSphere(theme: theme); sphereTint = theme.tint }
            puffs.append(to: tr, sphere: puffSphere)
        }
        return (op, tr.mesh)
    }

    /// One rest-anchored piece (rigid + surface-bound + swinging parts) at `scale` about its pivot.
    static func emit(_ p: WearPrepared, into m: inout RoomMesh, slot s: Slot, skin: UnsafePointer<Float>?, scale: Float, time: Float) {
        let c = s.carry
        let R = simd_float3x3(c.rotation)
        let sxz = 1 / c.squash.squareRoot()
        let M = R * simd_float3x3(diagonal: SIMD3(sxz, c.squash, sxz))
        let wp = c.centroid + M * (p.pivot - c.restCentroid)
        let base = UInt32(m.vertices.count)
        m.vertices.reserveCapacity(m.vertices.count + p.rest.count)
        let spinA = time * WearTuning.spin
        let cs = cosf(spinA), sn = sinf(spinA)
        let swing = s.swing
        for i in 0..<p.rest.count {
            var r = p.rest[i]
            var n = p.nrm[i]
            if p.spin[i] {
                let o = r - WearTuning.propellerCentre
                r = WearTuning.propellerCentre + SIMD3(o.x * cs + o.z * sn, o.y, -o.x * sn + o.z * cs)
                n = SIMD3(n.x * cs + n.z * sn, n.y, -n.x * sn + n.z * cs)
            }
            var q = c.centroid + M * (r - c.restCentroid)
            let w = p.w[i]
            if w > 0.001, let skin {
                let sp = WearBody.world(p.bind[i], skin: skin)
                q += (sp - q) * w
            }
            if p.h[i] > 0 { q += swing * p.h[i] }
            if scale != 1 { q = wp + (q - wp) * scale }
            m.vertices.append(RoomVertex(pos: SIMD4(q, 0), normal: SIMD4(R * n, p.ao[i]), color: SIMD4(p.col[i], 1)))
        }
        m.indices.reserveCapacity(m.indices.count + p.idx.count)
        for i in p.idx { m.indices.append(i + base) }
    }

    /// Mitts and wristbands on both arms: the arm-local mesh in the posed capsule frame (origin B, +y toward the shoulder, +z body forward, +x outward),
    /// scaled by r2 / 0.15, the axial extent clamped to the capsule's tip, mirrored for the -x arm.
    static func emitArms(_ p: WearPrepared, into m: inout RoomMesh, slot s: Slot, scale: Float) {
        for side in 0..<2 {
            let f = s.arms[side]
            let sigma: Float = side == 1 ? 1 : -1
            let Y = simd_normalize(f.a - f.b)
            var Z0 = f.forward
            Z0 -= Y * simd_dot(Z0, Y)
            let X = simd_normalize(simd_cross(Y, Z0))
            let Z = simd_cross(X, Y)
            let k = f.r2 / 0.15 * scale
            let base = UInt32(m.vertices.count)
            for i in 0..<p.rest.count {
                let v = p.rest[i]
                let y = max(v.y, -0.15)                                  // never past the capsule's tip sphere
                let q = f.b + (X * (sigma * v.x) + Y * y + Z * v.z) * k
                let n = simd_normalize(X * (sigma * p.nrm[i].x) + Y * p.nrm[i].y + Z * p.nrm[i].z)
                m.vertices.append(RoomVertex(pos: SIMD4(q, 0), normal: SIMD4(n, p.ao[i]), color: SIMD4(p.col[i], 1)))
            }
            if sigma > 0 { for i in p.idx { m.indices.append(i + base) } }
            else { var t = 0; while t + 2 < p.idx.count { m.indices.append(p.idx[t] + base); m.indices.append(p.idx[t + 2] + base); m.indices.append(p.idx[t + 1] + base); t += 3 } }
        }
    }
}
