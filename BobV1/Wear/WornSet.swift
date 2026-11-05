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
        /// Worn art id -> the variant art drawn instead (the hat Moss's daisy sits on; GameCare+Features sets it from the feature fit).
        var artOverride: [String: String] = [:]
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
    func slot(_ id: Int) -> Slot? { slots.indices.contains(id) ? slots[id] : nil }
    /// The variant art drawn for a worn piece on Jelly `id` (Features: the nopom / nobutton / short hats under Moss's daisy).
    func setArtOverride(_ id: Int, _ o: [String: String]) { while slots.count <= id { slots.append(Slot()) }; if slots[id].artOverride != o { slots[id].artOverride = o } }
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
        return false
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

    /// The body's pose RIGHT NOW, read after this frame's sim steps and just before the pieces are emitted. `tick` runs BEFORE the step (hopTick), so its
    /// carry is a step stale; rigid parts rode that stale pose while surface-bound parts read this frame's skin, and the two drifted apart in fast moves.
    func syncCarry(_ id: Int, sim: SoftBody) {
        guard slots.indices.contains(id) else { return }
        let pose = sim.bodyPose(iterations: 3)
        slots[id].carry = EyeMaskModel.Carry(centroid: pose.centroid, rotation: pose.rotation, squash: sim.attractor.squash, restCentroid: sim.restCentroid)
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
            // the limbs standing out of the egg right now, read from the same skin the pieces are bound to (see WearLimbs)
            var limbs: WearLimbs?
            if WearLimbs.enabled, let sk, let body, !body.limbBlocks.isEmpty, s.items.values.contains(where: { $0.scale > 0.001 }) || s.bib != nil {
                limbs = WearLimbs.build(blocks: body.limbBlocks) { i in SIMD3(sk[6 * i], sk[6 * i + 1], sk[6 * i + 2]) }
            }
            let first = op.vertices.count
            defer {
                if op.vertices.count > first {
                    var lo = SIMD3<Float>(repeating: .infinity), hi = SIMD3<Float>(repeating: -.infinity)
                    for v in op.vertices[first...] { let q = SIMD3(v.pos.x, v.pos.y, v.pos.z); lo = simd_min(lo, q); hi = simd_max(hi, q) }
                    lastBounds.append((lo, hi))
                }
            }
            for (slot, it) in s.items where it.scale > 0.001 {
                guard let look = it.look, let body, let p = WearMeshes.prepare(look, body: body, art: s.artOverride[look.art]) else { continue }
                if slot == .hands { Self.emitArms(p, into: &op, slot: s, scale: it.scale) }
                else { Self.emit(p, into: &op, slot: s, skin: sk, limbs: limbs, scale: it.scale, time: time) }
            }
            if let b = s.bib, let body, let p = WearMeshes.bib(team: b.team, number: b.number, body: body) {
                let sc: Float = s.role == .none ? (s.items[.body]?.scale ?? 0) : 1
                if sc > 0.001 { Self.emit(p, into: &op, slot: s, skin: sk, limbs: limbs, scale: sc, time: time) }
            }
        }
        if puffs.isActive {
            if sphereTint != theme.tint { puffSphere = DiningModels.puffSphere(theme: theme); sphereTint = theme.tint }
            puffs.append(to: tr, sphere: puffSphere)
        }
        return (op, tr.mesh)
    }

    nonisolated(unsafe) private static var scratchQ: [SIMD3<Float>] = [], scratchWall: [SIMD3<Float>] = []
    /// One rest-anchored piece (rigid + surface-bound + swinging parts) at `scale` about its pivot.
    static func emit(_ p: WearPrepared, into m: inout RoomMesh, slot s: Slot, skin: UnsafePointer<Float>?, limbs: WearLimbs? = nil, scale: Float, time: Float) {
        let c = s.carry
        let R = simd_float3x3(c.rotation)
        let sxz = 1 / c.squash.squareRoot()
        let M = R * simd_float3x3(diagonal: SIMD3(sxz, c.squash, sxz))
        let Minv = simd_float3x3(diagonal: SIMD3(1 / sxz, 1 / c.squash, 1 / sxz)) * R.transpose
        let wp = c.centroid + M * (p.pivot - c.restCentroid)
        let base = UInt32(m.vertices.count)
        m.vertices.reserveCapacity(m.vertices.count + p.rest.count)
        let spinA = time * WearTuning.spin
        let cs = cosf(spinA), sn = sinf(spinA)
        let swing = s.swing
        var lift: Float = 0, widen: Float = 1, seat: Float = 0
        if p.crownEnclosing, let skin { (lift, widen, seat) = CrownFit.fit(p, carry: c, skin: skin, body: WearBody.shared) }
        let mats = p.mat
        let lvOn = skin != nil && WearLevel.enabled && p.levelPiece && p.level.count == p.rest.count
        let zc = WearBody.shared.axisZ
        /// The outward direction of a levelled point in the world (the body-frame radial direction through the carry).
        var nodeRho: [Float] = []
        if lvOn, let skin { nodeRho = WearLevel.skinRadii(p, skin: skin, zc: zc, carry: c, M: M, Minv: Minv) }
        func radialW(_ d: SIMD2<Float>) -> SIMD3<Float> { simd_normalize(M * SIMD3(d.x, 0, d.y)) }
        let useLimbs = skin != nil && !(limbs?.isEmpty ?? true) && p.limbFree.count == p.rest.count
        if useLimbs { scratchQ.removeAll(keepingCapacity: true); scratchWall.removeAll(keepingCapacity: true) }
        /// One vertex: the carried, skinned and swung world position, and the wall normal under it when the limb push may move it.
        var clusterXf = [(c: SIMD3<Float>, R: simd_float3x3, wall: SIMD3<Float>)?](repeating: nil, count: p.hasClusters && skin != nil ? p.clusterRep.count : 0)
        func place(_ i: Int) -> (q: SIMD3<Float>, wall: SIMD3<Float>?) {
            var r = p.rest[i]
            if p.spin[i] {
                let o = r - WearTuning.propellerCentre
                r = WearTuning.propellerCentre + SIMD3(o.x * cs + o.z * sn, o.y, -o.x * sn + o.z * cs)
            }
            if lift != 0 || widen != 1 || seat != 0 { r = SIMD3(c.restCentroid.x + (r.x - c.restCentroid.x) * widen, r.y + seat + lift * CrownFit.liftWeight(r.y - p.pivot.y), c.restCentroid.z + (r.z - c.restCentroid.z) * widen) }
            var q = c.centroid + M * (r - c.restCentroid)
            let w = p.w[i]
            var wall: SIMD3<Float>?
            if w > 0.001, let skin {
                let k = Int(p.partOfVertex[i])
                if k < clusterXf.count, p.clusterRep[k] >= 0 {
                    // a small part rides its centre's skin frame as one rigid piece
                    if clusterXf[k] == nil {
                        if lvOn, p.clusterLevel[k] {
                            // a small part on a levelled loop: its centre keeps the loop's height, the part rides the BODY frame (a rigid pearl / knot on a level string)
                            let cw = WearLevel.position(rho: nodeRho[Int(p.clusterNode[k])] + p.clusterExcess[k], y: p.clusterY0[k], dir: p.clusterDir[k], zc: zc, carry: c, M: M)
                            clusterXf[k] = (cw, M, radialW(p.clusterDir[k]))
                        } else {
                            let (cw, f1) = WearBody.worldFrame(p.clusterBind[k], skin: skin)
                            clusterXf[k] = (cw, f1 * p.clusterFrame0[k].transpose, f1.columns.2)
                        }
                    }
                    let x = clusterXf[k]!
                    q = x.c + x.R * (p.rest[i] - p.clusterCentre[k])
                    if useLimbs, !(lvOn && p.clusterLevel[k]) { wall = x.wall }
                } else if lvOn, p.level[i] {
                    let yy = p.lvY0[i] + (r.y - p.rest[i].y)                            // (the crown fit's lift moves the whole loop level)
                    let lq = WearLevel.position(rho: nodeRho[Int(p.lvNode[i])] + p.lvExcess[i], y: yy, dir: p.lvDir[i], zc: zc, carry: c, M: M)
                    q += (lq - q) * w                                                    // (no wall: the limb push below does not slide a levelled vertex, it bulges it radially)
                } else {
                    let (wpos, wn) = WearBody.worldWithNormal(p.bind[i], skin: skin)
                    q += (wpos - q) * w
                    if useLimbs, p.limbFree[i] { wall = wn }
                }
            }
            if p.h[i] > 0 { q += swing * p.h[i] }
            return (q, wall)
        }
        if useLimbs, let limbs {
            // pass 1: where everything is before the limbs are considered; pass 2: small parts move rigidly out of a limb (they stay round), the rest vertex by vertex
            for i in 0..<p.rest.count { let (q, wall) = place(i); scratchQ.append(q); scratchWall.append(wall ?? .zero) }
            // levelled loops clear a limb by a smooth radial bulge (never by sliding up or down the wall)
            var lvDelta = [SIMD3<Float>](repeating: .zero, count: lvOn && WearLevel.bulge ? p.rest.count : 0)
            var lvClusterDelta = [SIMD3<Float>](repeating: .zero, count: lvOn && WearLevel.bulge ? p.clusterRep.count : 0)
            if lvOn, WearLevel.bulge {
                struct Unit { var pos: SIMD3<Float>, dirW: SIMD3<Float>, dir: SIMD2<Float>, y: Float, margin: Float, e: Float; var vertex: Int; var cluster: Int }
                var units: [Unit] = []
                func clearance(_ q: SIMD3<Float>, _ d: SIMD3<Float>, _ m: Float) -> Float {
                    var e: Float = 0
                    for _ in 0..<5 { let pen = limbs.penetration(q + d * e); if pen > -m { e += max(pen + m, 0.002) } else { break } }
                    return e * WearLevel.fade(e)
                }
                for i in 0..<p.rest.count where p.level[i] && p.limbFree[i] && !(p.clusterRep.indices.contains(Int(p.partOfVertex[i])) && p.clusterRep[Int(p.partOfVertex[i])] >= 0) && p.w[i] > 0.001 {
                    let d = radialW(p.lvDir[i])
                    units.append(Unit(pos: scratchQ[i], dirW: d, dir: p.lvDir[i], y: p.lvY0[i], margin: WearLimbs.margin, e: clearance(scratchQ[i], d, WearLimbs.margin) , vertex: i, cluster: -1))
                }
                for k in p.clusterRep.indices where p.clusterRep[k] >= 0 && p.clusterLevel[k] {
                    guard let x = clusterXf[k] else { continue }
                    let m = p.clusterRadius[k] + WearLimbs.margin
                    units.append(Unit(pos: x.c, dirW: x.wall, dir: p.clusterDir[k], y: p.clusterY0[k], margin: m, e: clearance(x.c, x.wall, m), vertex: -1, cluster: k))
                }
                var src = units.filter { $0.e > 0.0005 }
                if src.count > 160 { src.sort { $0.e > $1.e }; src = Array(src.prefix(160)) }
                for u in units {
                    var e: Float = 0
                    for s in src {
                        let az = atan2(u.dir.x * s.dir.y - u.dir.y * s.dir.x, u.dir.x * s.dir.x + u.dir.y * s.dir.y)
                        let k = WearLevel.bump(az, WearLevel.window)
                        if k <= 0 { continue }
                        let ky = WearLevel.bump(u.y - s.y, WearLevel.reachY)
                        e = max(e, s.e * k * ky)
                    }
                    let d = u.dirW * e
                    if u.vertex >= 0 { lvDelta[u.vertex] = d } else { lvClusterDelta[u.cluster] = d }
                }
            }
            // a pushed point goes back down onto the SKIN at its authored height (a slide along the wall's tangent plane would leave the curved wall: the piece would hang in the air)
            let body = WearBody.shared
            func rehug(_ q: SIMD3<Float>, _ h0: Float) -> SIMD3<Float> {
                guard WearLimbs.rehugBlend > 0, let skin, let nb = body.bind(Minv * (q - c.centroid) + c.restCentroid) else { return q }
                var b = nb; b.off = SIMD3(0, 0, h0)
                return WearBody.world(b, skin: skin)
            }
            // units: a small part moves by ONE displacement (its centre's), every other bound vertex by its own
            var delta = [SIMD3<Float>](repeating: .zero, count: p.clusterRep.count)
            var srcPos: [SIMD3<Float>] = [], srcDelta: [SIMD3<Float>] = []
            for k in p.clusterRep.indices where p.clusterRep[k] >= 0 && !(lvOn && p.clusterLevel[k]) {
                if let x = clusterXf[k] {
                    let m = p.clusterRadius[k] + WearLimbs.margin, h0 = p.clusterBind[k].off.z
                    var d = limbs.push(x.c, wallNormal: x.wall, margin: m) - x.c
                    if simd_length_squared(d) > 1e-5 {
                        if WearLimbs.rehugBlend > 0 {
                            let slid = x.c + d, down = rehug(slid, h0)
                            d = slid + (down - slid) * WearLimbs.rehugBlend - x.c
                        }
                    }
                    delta[k] = d
                    if simd_length_squared(d) > 1e-5 { srcPos.append(x.c); srcDelta.append(d) }
                }
            }
            var own = [SIMD3<Float>](repeating: .zero, count: p.rest.count)
            var pushed: [Int] = []
            for i in 0..<p.rest.count {
                let k = Int(p.partOfVertex[i])
                if k < p.clusterRep.count, p.clusterRep[k] >= 0 { continue }
                if scratchWall[i] != .zero {
                    let d = limbs.push(scratchQ[i], wallNormal: scratchWall[i], cap: WearLimbs.maxPushVertex) - scratchQ[i]
                    own[i] = d
                    if simd_length_squared(d) > 1e-5 {
                        pushed.append(i)
                        if srcPos.count < 600 { srcPos.append(scratchQ[i]); srcDelta.append(d) }
                    }
                }
            }
            // the biggest vertex pushes go back down towards the skin (a few only: each is a nearest-triangle query)
            if WearLimbs.rehugBlend > 0, p.look.slot == .neck, !pushed.isEmpty {
                pushed.sort { simd_length_squared(own[$0]) > simd_length_squared(own[$1]) }
                for i in pushed.prefix(WearLimbs.rehugVertexBudget) {
                    let slid = scratchQ[i] + own[i], down = rehug(slid, p.bind[i].off.z)
                    own[i] = slid + (down - slid) * WearLimbs.rehugBlend - scratchQ[i]
                }
            }
            // the push is spread along the strand: a neighbour within `reach` of a pushed point follows it by a falling share, so the string leaves and rejoins the wall in a smooth
            // curve instead of a V (WearLimbs.spread)
            if !srcPos.isEmpty {
                let R = WearLimbs.spread
                var lo = srcPos[0], hi = srcPos[0]
                for q in srcPos { lo = simd_min(lo, q); hi = simd_max(hi, q) }
                lo -= R; hi += R
                // sources hashed into cells of size R: a neighbour only looks at the 27 cells round it
                let dim = SIMD3<Int>(Int(((hi.x - lo.x) / R).rounded(.up)) + 1, Int(((hi.y - lo.y) / R).rounded(.up)) + 1, Int(((hi.z - lo.z) / R).rounded(.up)) + 1)
                var cells = [[Int32]](repeating: [], count: dim.x * dim.y * dim.z)
                func cell(_ q: SIMD3<Float>) -> SIMD3<Int> { let f = ((q - lo) / R).rounded(.down); return SIMD3(min(max(Int(f.x), 0), dim.x - 1), min(max(Int(f.y), 0), dim.y - 1), min(max(Int(f.z), 0), dim.z - 1)) }
                for j in srcPos.indices { let c = cell(srcPos[j]); cells[(c.z * dim.y + c.y) * dim.x + c.x].append(Int32(j)) }
                func share(_ q: SIMD3<Float>) -> SIMD3<Float> {
                    guard all(q .>= lo) && all(q .<= hi) else { return .zero }
                    let c0 = cell(q)
                    var best = SIMD3<Float>.zero, bestL: Float = 0
                    for z in max(c0.z - 1, 0)...min(c0.z + 1, dim.z - 1) { for y in max(c0.y - 1, 0)...min(c0.y + 1, dim.y - 1) { for x in max(c0.x - 1, 0)...min(c0.x + 1, dim.x - 1) {
                        for j32 in cells[(z * dim.y + y) * dim.x + x] {
                            let j = Int(j32), d = simd_distance(q, srcPos[j])
                            if d >= R { continue }
                            let f = (1 - d / R) * (1 - d / R)
                            var v = srcDelta[j] * f
                            let ln = simd_length(v)
                            if ln > WearLimbs.spreadMax { v *= WearLimbs.spreadMax / ln }          // a neighbour never leaves the wall by more than this on a push that is not its own
                            let l = simd_length_squared(v)
                            if l > bestL { bestL = l; best = v }
                        }
                    } } }
                    return best
                }
                for k in p.clusterRep.indices where p.clusterRep[k] >= 0 && !(lvOn && p.clusterLevel[k]) {
                    if let x = clusterXf[k], simd_length_squared(delta[k]) < 1e-5 { delta[k] = share(x.c) }
                }
                for i in 0..<p.rest.count where scratchWall[i] != .zero {
                    let k = Int(p.partOfVertex[i])
                    if k < p.clusterRep.count, p.clusterRep[k] >= 0 { continue }
                    let sh = share(scratchQ[i])
                    own[i] = simd_length_squared(sh) > simd_length_squared(own[i]) ? sh : own[i]
                }
            }
            for i in 0..<p.rest.count {
                let k = Int(p.partOfVertex[i])
                if k < p.clusterRep.count, p.clusterRep[k] >= 0 {
                    scratchQ[i] += lvOn && p.clusterLevel[k] ? (lvClusterDelta.isEmpty ? .zero : lvClusterDelta[k]) : delta[k]
                } else { scratchQ[i] += own[i] + (lvDelta.isEmpty ? .zero : lvDelta[i]) }
            }
        }
        for i in 0..<p.rest.count {
            var n = p.nrm[i]
            if p.spin[i] { n = SIMD3(n.x * cs + n.z * sn, n.y, -n.x * sn + n.z * cs) }
            var q = useLimbs ? scratchQ[i] : place(i).q
            if scale != 1 { q = wp + (q - wp) * scale }
            m.vertices.append(RoomVertex(pos: SIMD4(q, mats.isEmpty ? 0 : mats[i]), normal: SIMD4(R * n, p.ao[i]), color: SIMD4(p.col[i], 1)))
        }
        m.indices.reserveCapacity(m.indices.count + p.idx.count)
        for i in p.idx { m.indices.append(i + base) }
        if !p.sparkleSites.isEmpty { emitGlints(p, into: &m, base: Int(base), slot: s, scale: scale, time: time) }
    }

    /// Twinkles on jewellery: a handful of small 4-point star glints that pop and fade at the gems (each site on its own phase and period, busier while
    /// the Jelbie moves). Written into the mesh already being built: no allocation beyond the reserved capacity.
    static func emitGlints(_ p: WearPrepared, into m: inout RoomMesh, base: Int, slot s: Slot, scale: Float, time: Float) {
        let speed = min(1, simd_length(s.lastVel) * 0.25)
        let rate = 0.65 + 1.9 * speed
        m.vertices.reserveCapacity(m.vertices.count + 9 * 24)
        for (k, site) in p.sparkleSites.enumerated() {
            let h1 = Float((k &* 2654435761) & 1023) / 1023, h2 = Float((k &* 40503 &+ 7) & 255) / 255
            var u = time * rate * (0.65 + 0.7 * h2) + h1 * 7
            u -= u.rounded(.down)
            let duty = 0.22 + 0.12 * speed                      // more of them lit at once while he moves
            guard u < duty else { continue }
            let a = sinf(Float.pi * u / duty)
            let v = m.vertices[base + site]
            let c = SIMD3<Float>(v.pos.x, v.pos.y, v.pos.z), n = simd_normalize(SIMD3<Float>(v.normal.x, v.normal.y, v.normal.z))
            let ref: SIMD3<Float> = abs(n.y) > 0.9 ? SIMD3(1, 0, 0) : SIMD3(0, 1, 0)
            let r = simd_normalize(simd_cross(n, ref)), up = simd_cross(n, r)
            let L = 0.078 * scale * a, S = L * 0.16
            let centre = c + n * 0.020
            let col = SIMD4<Float>(2.2, 2.4, 2.9, 1)
            let first = UInt32(m.vertices.count)
            m.vertices.append(RoomVertex(pos: SIMD4(centre, 0), normal: SIMD4(n, 2), color: col))
            for q in 0..<8 {                                    // 8 rays round the normal (long on the axes, short on the diagonals): no temporary arrays
                let ang = Float(q) * (Float.pi / 4)
                let len = q % 2 == 0 ? L : S
                m.vertices.append(RoomVertex(pos: SIMD4(centre + (r * cosf(ang) + up * sinf(ang)) * len, 0), normal: SIMD4(n, 2), color: col))
            }
            for q in 0..<8 { m.indices.append(first); m.indices.append(first + 1 + UInt32(q)); m.indices.append(first + 1 + UInt32((q + 1) % 8)) }
        }
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
