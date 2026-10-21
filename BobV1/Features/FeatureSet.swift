//
//  FeatureSet.swift
//  What every Jelly GROWS on screen: Pip's spines, Moss's daisy, Lavender's wings (Features/, the feature layer; rendered with the wardrobe meshes).
//  Per Jelly: the feature, its fit under what he wears (FeatureCompat), the pop on / off state (like a wearable: scale about the anchor), the
//  per-part animation and the per-frame world mesh.
//    spines   rigid per spine on its sunk base (surface-bound): a lagged two-axis wobble spring, driven by the body's acceleration and squash rate,
//             a travelling wave crown -> tail by each spine's phase lag; a spine under a hat shrinks away (0.25 s) and grows back.
//    daisy    stem + leaves sway about the stem root (a spring lagging the body's acceleration + a slow idle sway); the flower head lags the stem
//             by 0.08 s about the flower centre; asleep (or deep night) the petals close toward the flower normal and the stem droops forward.
//    wings    rigid per side on the hinge: spread (about y) x flap (about the flap axis), from the flap-hop while it runs, else a gentle idle
//             flutter; shifted by dy and clamped to the flap / spread range the worn items allow; folded flat when nothing fits.
//  Hide rules: everything off in the wash (hideAll); spines and wings off while he lies on his back (sleep stages 2...4, the hat rule) and during
//  flips / rolls (they would clip the floor); the daisy stays through sleep (it closes). A racer keeps his feature (rivals keep theirs too).
//

import simd
import Foundation

nonisolated enum FeatureTuning {
    static let popTime: Float = 0.25
    static let partFade: Float = 0.25
    /// Spine wobble: how hard body acceleration (u/s^2) and squash rate (1/s) push, in degrees.
    static let spineAccelGain: Float = 0.9, spineSquashGain: Float = 25
    /// Daisy sway: spring (Hz) and damping, acceleration push (deg per u/s^2), the largest sway (deg).
    static let swayHz: Float = 2.2, swayZeta: Float = 0.4, swayGain: Float = 1.6, swayMax: Float = 12
    /// Wing idle flutter (deg) and its rates (Hz); how fast the wing angles chase their targets (1/s).
    static let flutterA: Float = 2.5, flutterB: Float = 1.5, flutterHzA: Float = 1.1, flutterHzB: Float = 0.37, wingChase: Float = 18
    static let accelHistory = 30
}

@MainActor
final class FeatureSet {
    enum Phase { case hidden, popIn, shown, poofOut }
    struct Slot {
        var feature: JellyFeature = .none
        var fit = FeatureFit()
        var phase: Phase = .hidden
        var t: Float = 0
        var scale: Float = 0
        var from: Float = 1
        var primed = false
        var hideAll = false
        var carry = EyeMaskModel.Carry()
        // motion drive
        var lastCentroid = SIMD3<Float>.zero, lastVel = SIMD3<Float>.zero, lastSquash: Float = 1
        var accel: [SIMD3<Float>] = Array(repeating: .zero, count: FeatureTuning.accelHistory)      // ring, newest at `accelHead`
        var accelHead = 0
        var squashRate: Float = 0
        /// Spines: angle (deg) about (along, across) and its rate, per spine; the visible scale of each part (hidden under a hat -> 0).
        var spineA: [SIMD2<Float>] = [], spineV: [SIMD2<Float>] = []
        var partScale: [String: Float] = [:]
        /// Daisy: sway (deg about x = nod, z = side) and rate; the lagged head sway; the close blend 0...1; the idle clock.
        var sway = SIMD2<Float>.zero, swayV = SIMD2<Float>.zero, headSway = SIMD2<Float>.zero, close: Float = 0, clock: Float = 0
        /// Wings: the current flap / spread (deg) and the target.
        var flap: Float = 0, spread: Float = 0
        var folded = false
    }
    private(set) var slots: [Slot] = []
    private(set) var lastBounds: [(lo: SIMD3<Float>, hi: SIMD3<Float>)] = []
    var body: WearBody?
    /// The fitting room / captures: the feature shows whatever the Jelly is doing.
    var ignoreHide = false
    private(set) var popIns = 0, poofOuts = 0

    nonisolated deinit {}

    func slot(_ id: Int) -> Slot? { slots.indices.contains(id) ? slots[id] : nil }
    func shown(_ id: Int) -> JellyFeature? { slot(id).flatMap { $0.scale > 0.001 ? $0.feature : nil } }
    var anyShown: Bool { slots.contains { $0.scale > 0.001 && $0.feature != .none } }
    func reset() { slots = slots.map { _ in Slot() } }

    // MARK: hide rules

    /// Spines and wings lie on his back: off while he lies down (the hats' rule) and in flips / rolls.
    static func hidden(_ f: JellyFeature, _ b: BlobBrain) -> Bool {
        switch f {
        case .spines, .wings: return WornSet.sleepHides(b) || WornSet.flipping(b)
        default: return false
        }
    }
    /// The daisy closes: asleep on his back, or deep in the night.
    static func closes(_ b: BlobBrain) -> Bool { b.isLying || b.isNapping || b.idleDeepNight > 0.5 }

    // MARK: tick

    /// Once per fixed step for Jelly `id`. `worn` = the wearable art ids the wardrobe SHOWS on him now (FeatureCompat reads them).
    func tick(id: Int, brain: BlobBrain, sim: SoftBody, feature: JellyFeature, worn: [String], hideAll: Bool, dt: Float, spec: FeatureSpec = .shared) {
        while slots.count <= id { slots.append(Slot()) }
        var s = slots[id]
        let pose = sim.bodyPose(iterations: 3)
        s.carry = EyeMaskModel.Carry(centroid: pose.centroid, rotation: pose.rotation, squash: sim.attractor.squash, restCentroid: sim.restCentroid)
        s.feature = feature; s.hideAll = hideAll
        s.fit = FeatureCompat.solve(feature, worn: worn, spec: spec)
        s.folded = s.fit.folded
        stepDrive(&s, dt: dt)
        let hide = hideAll || (!ignoreHide && (Self.hidden(feature, brain) || s.fit.hidden))
        let desired = feature != .none && !hide
        if hideAll || !s.primed {
            s.phase = desired ? .shown : .hidden; s.scale = desired ? 1 : 0; s.t = 0
        } else {
            switch s.phase {
            case .hidden: if desired { s.phase = .popIn; s.t = 0; s.scale = 0; popIns += 1 }
            case .popIn:
                s.t += dt
                if !desired { s.phase = .poofOut; s.t = 0; s.from = max(s.scale, 0.001); poofOuts += 1 }
                else if s.t >= FeatureTuning.popTime { s.phase = .shown; s.scale = 1 }
                else { s.scale = DiningCurve.pop(s.t / FeatureTuning.popTime) }
            case .shown: if !desired { s.phase = .poofOut; s.t = 0; s.from = 1; poofOuts += 1 } else { s.scale = 1 }
            case .poofOut:
                s.t += dt
                if desired { s.phase = .popIn; s.t = 0 }
                else if s.t >= FeatureTuning.popTime { s.phase = .hidden; s.scale = 0 }
                else { s.scale = s.from * (1 - s.t / FeatureTuning.popTime) }
            }
        }
        s.primed = true
        // the animation
        switch feature {
        case .spines: stepSpines(&s, spec: spec, dt: dt)
        case .daisy: stepDaisy(&s, brain: brain, spec: spec, dt: dt)
        case .wings: stepWings(&s, brain: brain, dt: dt)
        case .none: break
        }
        slots[id] = s
    }

    /// The body's acceleration history (for the lagged drives) and squash rate.
    private func stepDrive(_ s: inout Slot, dt: Float) {
        let v = (s.carry.centroid - s.lastCentroid) / max(dt, 1e-4)
        var acc = (v - s.lastVel) / max(dt, 1e-4)
        let sq = (s.carry.squash - s.lastSquash) / max(dt, 1e-4)
        s.lastCentroid = s.carry.centroid; s.lastVel = v; s.lastSquash = s.carry.squash
        if !s.primed { acc = .zero; s.squashRate = 0 } else { s.squashRate = max(-12, min(12, sq)) }
        let l = simd_length(acc)
        if l > 60 { acc *= 60 / l }
        s.accelHead = (s.accelHead + 1) % FeatureTuning.accelHistory
        s.accel[s.accelHead] = acc
    }
    private func accel(_ s: Slot, lag: Float, dt: Float) -> SIMD3<Float> {
        let n = min(FeatureTuning.accelHistory - 1, max(0, Int((lag / max(dt, 1e-4)).rounded())))
        return s.accel[((s.accelHead - n) % FeatureTuning.accelHistory + FeatureTuning.accelHistory) % FeatureTuning.accelHistory]
    }

    private func stepSpines(_ s: inout Slot, spec: FeatureSpec, dt: Float) {
        let n = spec.spines.count
        if s.spineA.count != n { s.spineA = Array(repeating: .zero, count: n); s.spineV = Array(repeating: .zero, count: n) }
        let Rinv = simd_float3x3(s.carry.rotation).transpose
        for (k, sp) in spec.spines.enumerated() {
            let a = Rinv * accel(s, lag: sp.lag, dt: dt)                    // body frame
            let axis = sp.axis.v3
            // push: lateral (across = x) and along-spine (the tangent in the sagittal plane) acceleration tips the spine the other way; squash rate nods it
            let along = simd_normalize(SIMD3<Float>(0, -axis.z, axis.y))      // sagittal tangent, perpendicular to the spine axis
            let push = SIMD2<Float>(-simd_dot(a, along) * FeatureTuning.spineAccelGain + s.squashRate * FeatureTuning.spineSquashGain * 0.15,
                                    -a.x * FeatureTuning.spineAccelGain)
            let w = 2 * .pi * sp.hz, z = sp.damping
            s.spineV[k] += (-w * w * s.spineA[k] - 2 * z * w * s.spineV[k] + push * w * w * 0.02) * dt
            s.spineA[k] += s.spineV[k] * dt
            let l = simd_length(s.spineA[k])
            if l > sp.maxDeg { s.spineA[k] *= sp.maxDeg / l }
            if !l.isFinite { s.spineA[k] = .zero; s.spineV[k] = .zero }
            // a spine under a hat shrinks away
            let want: Float = s.fit.hiddenParts.contains(sp.part) ? 0 : 1
            let cur = s.partScale[sp.part] ?? want
            s.partScale[sp.part] = s.primed ? cur + max(-dt / FeatureTuning.partFade, min(dt / FeatureTuning.partFade, want - cur)) : want
        }
    }

    private func stepDaisy(_ s: inout Slot, brain: BlobBrain, spec: FeatureSpec, dt: Float) {
        let d = s.fit.onHat ? spec.daisyOnHat : spec.daisy
        s.clock += dt
        let Rinv = simd_float3x3(s.carry.rotation).transpose
        let a = Rinv * accel(s, lag: 0.03, dt: dt)
        // the flower lags: it tips away from the acceleration (nod about x from z accel, side about z from x accel)
        let push = SIMD2<Float>(a.z, -a.x) * FeatureTuning.swayGain * 0.01
        let w = 2 * .pi * FeatureTuning.swayHz, z = FeatureTuning.swayZeta
        s.swayV += (-w * w * s.sway - 2 * z * w * s.swayV + push * w * w) * dt
        s.sway += s.swayV * dt
        let l = simd_length(s.sway)
        if l > FeatureTuning.swayMax { s.sway *= FeatureTuning.swayMax / l }
        if !l.isFinite { s.sway = .zero; s.swayV = .zero }
        let lag = max(d.headLag, 1e-3)
        s.headSway += (s.sway - s.headSway) * min(1, dt / lag)
        let wantClose: Float = Self.closes(brain) ? 1 : 0
        s.close = s.primed ? s.close + max(-dt / d.closeTime, min(dt / d.closeTime, wantClose - s.close)) : wantClose
    }

    private func stepWings(_ s: inout Slot, brain: BlobBrain, dt: Float) {
        s.clock += dt
        var flap: Float, spread: Float
        if brain.flapHop.active, !s.folded {
            flap = brain.flapHop.flapDeg; spread = brain.flapHop.spreadDeg
        } else {
            flap = FeatureTuning.flutterA * sinf(2 * .pi * FeatureTuning.flutterHzA * s.clock) + FeatureTuning.flutterB * sinf(2 * .pi * FeatureTuning.flutterHzB * s.clock + 1.3)
            spread = 0.4 * max(flap, 0)
        }
        if s.folded { flap = 0; spread = 0 }
        flap = min(max(flap, s.fit.flapMin), s.fit.flapMax)
        spread = min(max(spread, 0), s.fit.spreadMax)
        let k = min(1, FeatureTuning.wingChase * dt)
        s.flap += (flap - s.flap) * k; s.spread += (spread - s.spread) * k
        if !s.primed { s.flap = flap; s.spread = spread }
    }

    // MARK: frame

    /// Every feature, in world space. `skin(id)` = the Jelly's CPU-skinned vertex stream (6 floats per vertex), nil = carried rigidly.
    func frame(hidden: Bool = false, skin: (Int) -> UnsafePointer<Float>?, spec: FeatureSpec = .shared) -> RoomMesh {
        var m = RoomMesh()
        lastBounds = []
        guard !hidden, let body else { return m }
        for (id, s) in slots.enumerated() where s.scale > 0.001 && s.feature != .none {
            var pl = FeatureMeshes.Placement()
            if s.feature == .daisy { pl.onHat = s.fit.onHat; pl.anchor = s.fit.anchor; pl.tilt = s.fit.tilt; pl.sink = s.fit.sink }
            if s.feature == .wings { pl.dy = s.fit.wingDY }
            guard let p = FeatureMeshes.prepare(s.feature, placement: pl, body: body, spec: spec) else { continue }
            let first = m.vertices.count
            Self.emit(p, into: &m, slot: s, skin: skin(id), spec: spec)
            if m.vertices.count > first {
                var lo = SIMD3<Float>(repeating: .infinity), hi = SIMD3<Float>(repeating: -.infinity)
                for v in m.vertices[first...] { let q = SIMD3(v.pos.x, v.pos.y, v.pos.z); lo = simd_min(lo, q); hi = simd_max(hi, q) }
                lastBounds.append((lo, hi))
            }
        }
        return m
    }

    /// The part rotations of a slot's feature (rest frame, about each part's pivot): the animation.
    static func partRotation(_ p: FeaturePrepared, _ part: FeaturePrepared.Part, slot s: Slot, spec: FeatureSpec) -> simd_float3x3 {
        switch s.feature {
        case .spines:
            guard s.spineA.indices.contains(part.side) else { return matrix_identity_float3x3 }
            let sp = spec.spines[part.side], a = s.spineA[part.side]
            let axis = sp.axis.v3
            let across = SIMD3<Float>(1, 0, 0)
            let along = simd_normalize(simd_cross(across, axis))             // sagittal tangent
            // tip along the spine's sagittal tangent: rotate about `across`; tip sideways: rotate about `along`
            let q = simd_quatf(angle: a.x * .pi / 180, axis: across) * simd_quatf(angle: a.y * .pi / 180, axis: along)
            return simd_float3x3(q)
        case .daisy:
            let d = s.fit.onHat ? spec.daisyOnHat : spec.daisy
            let idle = SIMD2<Float>(d.idleDeg.count > 1 ? d.idleDeg[1] : 0, d.idleDeg.first ?? 0) * SIMD2(sinf(2 * .pi * d.idleHz * s.clock + 0.7), sinf(2 * .pi * d.idleHz * s.clock))
            if part.group == 1 {
                // the flower head: only its own lag behind the stem (it is carried by the stem's rotation at emission)
                let lag = (s.headSway - s.sway) * 0.7
                let q = simd_quatf(angle: lag.x * .pi / 180, axis: SIMD3(1, 0, 0)) * simd_quatf(angle: lag.y * .pi / 180, axis: SIMD3(0, 0, 1))
                return simd_float3x3(q)
            }
            let sw = s.sway + idle
            let droop = d.droopDeg * s.close
            let q = simd_quatf(angle: (sw.x + droop) * .pi / 180, axis: SIMD3(1, 0, 0)) * simd_quatf(angle: sw.y * .pi / 180, axis: SIMD3(0, 0, 1))
            return simd_float3x3(q)
        case .wings:
            guard let side = spec.wings.sides[part.side == 1 ? "l" : "r"] else { return matrix_identity_float3x3 }
            let sgn: Float = part.side == 1 ? -1 : 1
            let q = simd_quatf(angle: sgn * s.spread * .pi / 180, axis: simd_normalize(side.spreadAxis.v3)) * simd_quatf(angle: sgn * s.flap * .pi / 180, axis: simd_normalize(side.flapAxis.v3))
            return simd_float3x3(q)
        case .none: return matrix_identity_float3x3
        }
    }

    /// One feature: every part carried on its bound pivot, rotated by its animation, scaled by the pop and the part's own fade.
    static func emit(_ p: FeaturePrepared, into m: inout RoomMesh, slot s: Slot, skin: UnsafePointer<Float>?, spec: FeatureSpec) {
        let c = s.carry
        let R = simd_float3x3(c.rotation)
        let sxz = 1 / c.squash.squareRoot()
        let M = R * simd_float3x3(diagonal: SIMD3(sxz, c.squash, sxz))
        let anchorW = c.world(p.anchor)
        let base = UInt32(m.vertices.count)
        m.vertices.reserveCapacity(m.vertices.count + p.rest.count)
        var keep = [Bool](repeating: true, count: p.parts.count)
        let d = s.fit.onHat ? spec.daisyOnHat : spec.daisy
        let flowerC = p.parts.first { $0.group == 1 }?.pivot ?? .zero
        for (pi, part) in p.parts.enumerated() {
            let ps = (s.partScale[part.name] ?? 1) * s.scale
            if ps <= 0.001 { keep[pi] = false }
            var pivotW = c.world(part.pivot)
            if let skin, part.bind.tri != .zero { pivotW = WearBody.world(part.bind, skin: skin) }
            // for the flower parts the pivot (flower centre) is carried on the stem: the stem's rotation about the stem root moves it
            let rot = partRotation(p, part, slot: s, spec: spec)
            var stemRot = matrix_identity_float3x3
            var stemPivotW = pivotW
            if s.feature == .daisy, part.group == 1, let stem = p.parts.first(where: { $0.name == "stem" }) {
                stemRot = partRotation(p, stem, slot: s, spec: spec)
                stemPivotW = c.world(stem.pivot)
                if let skin, stem.bind.tri != .zero { stemPivotW = WearBody.world(stem.bind, skin: skin) }
            }
            // petals close about their root hinge toward the flower normal (rest frame, before the sway)
            var petalRot = matrix_identity_float3x3
            if part.isPetal, s.close > 0.001 {
                petalRot = simd_float3x3(simd_quatf(angle: d.closeDeg * s.close * .pi / 180, axis: part.hingeAxis))
            }
            for i in part.first..<(part.first + part.count) {
                var o = p.off[i]
                var n = p.nrm[i]
                if part.isPetal, s.close > 0.001 {
                    let rel = p.rest[i] - part.hinge
                    o = (part.hinge + petalRot * rel) - part.pivot
                    n = petalRot * n
                }
                var q: SIMD3<Float>
                if s.feature == .daisy, part.group == 1 {
                    // flower: head rotation about the flower centre, carried by the stem's rotation about the stem root
                    let headLocal = rot * o                                   // about the flower centre (rest frame)
                    let fromStem = (flowerC - (p.parts.first { $0.name == "stem" }?.pivot ?? flowerC)) + headLocal
                    q = stemPivotW + M * (stemRot * fromStem)
                    n = R * (stemRot * (rot * n))
                } else {
                    q = pivotW + M * (rot * o)
                    n = R * (rot * n)
                }
                if ps != 1 { q = anchorW + (q - anchorW) * ps }
                m.vertices.append(RoomVertex(pos: SIMD4(q, 0), normal: SIMD4(n, p.ao[i]), color: SIMD4(p.col[i], 1)))
            }
        }
        m.indices.reserveCapacity(m.indices.count + p.idx.count)
        var t = 0
        while t + 2 < p.idx.count {
            let i0 = p.idx[t]
            if keep[p.partOfVertex[Int(i0)]] { m.indices.append(i0 + base); m.indices.append(p.idx[t + 1] + base); m.indices.append(p.idx[t + 2] + base) }
            t += 3
        }
    }
}
