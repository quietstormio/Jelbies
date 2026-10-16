//
//  Skinning.swift
//  Every render vertex (body, seeds, bubbles) follows its embedding tetrahedron.
//  Output layout per vertex: pos xyz + normalized normal xyz (6 floats). Port of skin().
//  Also owns the eyes' blink: after skinning, each eye (and its glint) is flattened toward the eye's skinned centre
//  along the eye's current local up axis. `setEyeOpenness` is the hook for expressions (squints, sleepy, wide).
//

import Foundation
import simd

nonisolated final class Skinner {
    let vertexCount: Int
    private let skinIdx: [Int32]    // 4 sim particle indices per vertex
    private let skinW: [Float]      // 4 barycentric weights per vertex

    // eyes
    private let eyeIdx: [[Int32]]
    private let glintIdx: [[Int32]]
    private let browIdx: [[Int32]]
    private let anchorIdx: [Int32]  // 4 particles per virtual point: [centre0, up0, centre1, up1]
    private let anchorW: [Float]
    private let hasEyes: Bool

    /// Closed eyes are this fraction of full height: reads as a lid line.
    static let closedHeight: Float = 0.08
    /// Expression openness per eye, 0 (shut) ... 1 (open). Combined with the automatic blink.
    private(set) var openness: (left: Float, right: Float) = (1, 1)
    /// Automatic blinking (random 2-6 s apart, ~120 ms, sometimes a double blink). Turn off for scripted expressions.
    var autoBlink = true
    private var blinking = false
    private var blinkT: Float = 0             // seconds into the current blink
    private var gap: Float = 0                // pause between the two blinks of a double blink
    private var blinkWait: Float = 2.5
    private var doubleLeft = 0
    private var rng: UInt32 = 0x2F6E2B1
    /// Current eye height factors (closedHeight ... 1) after expression + blink (left, right).
    private(set) var eyeHeight: (left: Float, right: Float) = (1, 1)
    private var blinkOpen: Float = 1

    /// Animation hook (BlobBrain arm paths): additive world-space displacement of some render vertices, plus the AO value
    /// written to those vertices' mat channel (see `takeMatWrites`). Empty = off.
    var overrideVertices: [Int32] = []
    var overrideDelta: [SIMD3<Float>] = []
    var overrideMat: [Float] = []
    /// Touch play (cheek squeeze): additive world-space displacement of some render vertices, applied after skinning. Empty = off.
    var extraVertices: [Int32] = []
    var extraDelta: [SIMD3<Float>] = []
    /// Vertices of the eyes, glints and brows (a skin offset must not drag the face features around).
    var faceFeatureVertices: Set<Int32> { Set(eyeIdx.joined()).union(glintIdx.joined()).union(browIdx.joined()) }
    private var pendingRestore: [Int32] = []

    // MARK: foot beans
    // Each foot is a closed bean (FootBean) in the render mesh, hidden inside the belly at rest. While he moves his feet the brain hands over
    // the bean's world-space vertices (`beanPos`) and a blend 0...1: the bean grows from its hidden skinned shape to the working shape, and the
    // embedded foot's skin (`retractVertices`) is pushed (rest-space deltas, rotated by `retractMatrix`) onto the footless egg at the same time.
    // blend = 0: nothing is touched and the render is bit-identical to the plain skinning.
    var beanFirst: [Int] = []
    nonisolated(unsafe) static var dbgNoArmRetract = UserDefaults.standard.integer(forKey: "ArmNoRetract") != 0
    nonisolated(unsafe) static var dbgNoRetract = UserDefaults.standard.integer(forKey: "LegNoRetract") != 0
    var beanPos: [[SIMD3<Float>]] = [[], []]
    var beanStart: [[SIMD3<Float>]] = [[], []]         // the inset bean in the body-rigid foot pose: where each bean starts from at blend 0
    var beanBlend: Float = 0
    var retractVertices: [Int32] = []
    var retractRest: [SIMD3<Float>] = []              // rest-space delta of each retracting vertex onto the footless egg (sunk a little)
    var retractWeight: [Float] = []
    var retractSide: [Int8] = []                      // 0 / 1 = skinned to that foot's sim slab, -1 = belly skin
    var retractMatrix = matrix_identity_float3x3      // body-rigid pose (rotation * squash) that carries a rest delta into the world
    var retractShift: [SIMD3<Float>] = [.zero, .zero]  // how far each sim foot slab sits from the body-rigid pose (world): removed from its vertices
    func clearBeans() { beanBlend = 0; beanPos = [[], []]; beanStart = [[], []] }
    var beansActive: Bool { beanBlend > 0 && beanPos[0].count == FootBean.vertexCount && beanStart[0].count == FootBean.vertexCount && beanFirst.count == 2 }

    // MARK: walking arm capsules
    // The same scheme for the arms: while the walking arm is active the brain poses the closed ArmCapsule of each side in world space (`armPos`,
    // blended from `armStart` = the rest nub by `armBlend`) and the rest nub's skin (`armRetract*`, rest-space deltas onto the ARMLESS egg, sunk a
    // little, rotated by `armRetractMatrix`) retracts under it at the same time, so the junction is a crease, not a fillet. blend = 0: untouched.
    var armFirst: [Int] = []
    var armPos: [[SIMD3<Float>]] = [[], []]
    var armStart: [[SIMD3<Float>]] = [[], []]
    var armBlend: Float = 0
    var armRetractVertices: [Int32] = []
    var armRetractRest: [SIMD3<Float>] = []
    var armRetractWeight: [Float] = []
    var armRetractMatrix = matrix_identity_float3x3
    func clearArmCapsules() { armBlend = 0; armPos = [[], []]; armStart = [[], []] }
    // W1d: render-side skin offsets (the physics version of the shear was eaten by the tets). `skinVerts` = body skin + face decals (not the capsules / beans);
    // `shearW` = (1 - y/Htop)^2 of the rest height, `lobeW[s]` = the lobe weight of leg s (Gaussian in the xz distance to that leg's rest footprint x a height falloff).
    // Per frame the brain sets `shearVec` (world offset at the floor) and `lobeD[s]` (world offset of the skin over foot s: the body 'picks up' with the foot).
    var skinVerts: [Int32] = []
    var shearW: [Float] = []
    var lobeW: [[Float]] = [[], []]
    var shearVec = SIMD3<Float>(0, 0, 0)
    var lobeD: [SIMD3<Float>] = [.zero, .zero]
    var armCapsulesActive: Bool { armBlend > 0 && armPos[0].count == ArmCapsule.vertexCount && armStart[0].count == ArmCapsule.vertexCount && armFirst.count == 2 }

    /// Render vertices embedded in a tet that touches any of `particles` (e.g. the foot slab prisms, whose corners are the sole particles).
    func vertices(touching particles: Set<Int32>) -> [Int32] {
        var out: [Int32] = []
        for v in 0..<vertexCount {
            let i4 = 4 * v
            if particles.contains(skinIdx[i4]) || particles.contains(skinIdx[i4 + 1]) || particles.contains(skinIdx[i4 + 2]) || particles.contains(skinIdx[i4 + 3]) { out.append(Int32(v)) }
        }
        return out
    }

    /// Switch the override off; the mat values written so far are restored by the next `takeMatWrites`.
    func clearOverride() {
        if !overrideVertices.isEmpty { pendingRestore = overrideVertices }
        overrideVertices = []; overrideDelta = []; overrideMat = []
    }

    /// What the renderer must write into its static mat channel now: the current AO values while an override runs, then
    /// (once) `values == nil` = restore the baked values of the vertices just released. nil = nothing to do.
    func takeMatWrites() -> (vertices: [Int32], values: [Float]?)? {
        if !overrideVertices.isEmpty { return (overrideVertices, overrideMat) }
        if !pendingRestore.isEmpty { let v = pendingRestore; pendingRestore = []; return (v, nil) }
        return nil
    }

    // antennae (Honey): rigid crown frame + spring-follow wobble
    private struct Antenna {
        var first: Int, count: Int
        var anchorIdx: [Int32]      // 3 points x 4 particles
        var anchorW: [Float]        // 3 points x 4 weights
        var local: [Float]          // per vertex, coordinates in the rest crown frame (3 each)
        var weights: [Float]
        var tipLocal: SIMD3<Float>
        var p = SIMD3<Float>(0, 0, 0), v = SIMD3<Float>(0, 0, 0)
        var started = false
    }
    private var antennae: [Antenna] = []
    private var frameDt: Float = 1.0 / 60

    init(simTets: [UInt32], embedding: (tetOf: [UInt32], w: [Float]), vertexCount: Int, eyes: EyeRig? = nil,
         antennae rig: AntennaRig? = nil) {
        self.vertexCount = vertexCount
        var idx = [Int32](repeating: 0, count: vertexCount * 4)
        for v in 0..<vertexCount {
            let t = Int(embedding.tetOf[v])
            for k in 0..<4 { idx[4 * v + k] = Int32(simTets[4 * t + k]) }
        }
        skinIdx = idx
        skinW = embedding.w
        if let e = eyes {
            eyeIdx = e.eye; glintIdx = e.glint; browIdx = e.brow
            var ai = [Int32](repeating: 0, count: 16)
            for p in 0..<4 { let t = Int(e.anchorTet[p]); for k in 0..<4 { ai[4 * p + k] = Int32(simTets[4 * t + k]) } }
            anchorIdx = ai; anchorW = e.anchorW
            hasEyes = true
        } else {
            eyeIdx = [[], []]; glintIdx = [[], []]; browIdx = [[], []]; anchorIdx = []; anchorW = []; hasEyes = false
        }
        if let r = rig {
            for (k, info) in r.info.enumerated() {
                var ai = [Int32](repeating: 0, count: 12), aw = [Float](repeating: 0, count: 12)
                for p in 0..<3 {
                    let t = Int(r.anchorTet[3 * k + p])
                    for j in 0..<4 { ai[4 * p + j] = Int32(simTets[4 * t + j]); aw[4 * p + j] = r.anchorW[4 * (3 * k + p) + j] }
                }
                let bp = info.basePoints
                let c = SIMD3(bp[0], bp[1], bp[2]), u = SIMD3(bp[3], bp[4], bp[5]), sd = SIMD3(bp[6], bp[7], bp[8])
                let fr = Self.faceFrame(c, u, sd)
                var loc = [Float](repeating: 0, count: 3 * info.vertexCount)
                for i in 0..<info.vertexCount {
                    let v = info.firstVertex + i
                    let d = SIMD3(r.restVerts[3 * v], r.restVerts[3 * v + 1], r.restVerts[3 * v + 2]) - c
                    loc[3 * i] = simd_dot(d, fr.x); loc[3 * i + 1] = simd_dot(d, fr.y); loc[3 * i + 2] = simd_dot(d, fr.z)
                }
                let td = info.tip - c
                antennae.append(Antenna(first: info.firstVertex, count: info.vertexCount, anchorIdx: ai, anchorW: aw,
                                        local: loc, weights: info.weights,
                                        tipLocal: SIMD3(simd_dot(td, fr.x), simd_dot(td, fr.y), simd_dot(td, fr.z))))
            }
        }
    }

    private static func faceFrame(_ c: SIMD3<Float>, _ u: SIMD3<Float>, _ s: SIMD3<Float>) -> (x: SIMD3<Float>, y: SIMD3<Float>, z: SIMD3<Float>) {
        let y = simd_normalize(u - c)
        var x = s - c; x -= y * simd_dot(x, y)
        x = simd_length(x) < 1e-6 ? SIMD3(1, 0, 0) : simd_normalize(x)
        return (x, y, simd_cross(x, y))
    }

    // MARK: eye controls

    /// Expression hook: 0 = shut (lid line), 1 = fully open. Independent per eye (winks, squints).
    func setEyeOpenness(left: Float, right: Float) {
        openness = (max(0, min(1, left)), max(0, min(1, right)))
        refreshEyeHeight()
    }
    func setEyeOpenness(_ both: Float) { setEyeOpenness(left: both, right: both) }

    /// Start a blink now (optionally a quick double blink).
    func blinkNow(double: Bool = false, duration: Float = 0.12) {
        blinking = true; blinkT = 0; doubleLeft = double ? 1 : 0; gap = 0; blinkDur = duration; autoHold = 1.0
    }
    // W1c: while he walks the brows are kept RIGID to the face frame (the eye pair's frame) instead of following the jelly's local skin deformation,
    // which tilted the two brows differently (non-parallel) as the belly shears. `browsRigid` is set by the brain; the blend eases in / out over ~0.3 s.
    var browsRigid = false
    /// Dining only: while true, each brow whose slant as the fixed game camera sees it (inner end up, rad) falls below `browFloor` is turned in the
    /// screen plane (about the view axis, through its centre) up to that floor, so a leaning / turned head never reads angry. Eases in / out; off = the
    /// rest face, untouched.
    var browCounterOn = false
    static let browFloor: Float = 0.08          // a little friendly: the measured slant is only matched to ~0.13 rad on a heavily turned head
    private var browCW: Float = 0
    private static let gameViewProj: simd_float4x4 = M4.mul(M4.perspective(fovy: GameCamera.fovY, aspect: GameCamera.aspect, near: 0.3, far: 60),
                                                           M4.lookAt(eye: GameCamera.eye, at: GameCamera.target, up: SIMD3(0, 1, 0)))
    private var browW: Float = 0
    private var browRest: [[SIMD3<Float>]] = [[], []]
    private var browMidRest = SIMD3<Float>(0, 0, 0)
    private var browFrameRest = simd_float3x3(1)
    private var browEyeRest: [SIMD3<Float>] = [SIMD3(0, 0, 0), SIMD3(0, 0, 0)]
    var browsPrepared: Bool { !browRest[0].isEmpty }
    /// Orthonormal frame (columns x, y, z) of the face: x along the eye line, y toward the brows (perpendicular to x), z = x cross y.
    private static func browFaceFrame(_ e0: SIMD3<Float>, _ e1: SIMD3<Float>, _ bm: SIMD3<Float>) -> simd_float3x3 {
        let xa = simd_normalize(e1 - e0)
        var y = bm - (e0 + e1) / 2; y -= xa * simd_dot(y, xa)
        let ya = simd_length(y) > 1e-6 ? simd_normalize(y) : SIMD3<Float>(0, 1, 0)
        return simd_float3x3(columns: (xa, ya, simd_cross(xa, ya)))
    }
    func prepareBrows(rest: [Float]) {
        guard hasEyes, browIdx[0].count > 0, browIdx[1].count > 0, eyeIdx[0].count > 0, eyeIdx[1].count > 0 else { return }
        func p(_ v: Int32) -> SIMD3<Float> { SIMD3(rest[3 * Int(v)], rest[3 * Int(v) + 1], rest[3 * Int(v) + 2]) }
        var m = SIMD3<Float>(0, 0, 0); var n: Float = 0
        for e in 0..<2 { for v in eyeIdx[e] { m += p(v); n += 1 } }
        browMidRest = m / max(n, 1)
        browRest = (0..<2).map { s in browIdx[s].map { p($0) } }
        func mean(_ a: [SIMD3<Float>]) -> SIMD3<Float> { a.reduce(SIMD3<Float>(0, 0, 0), +) / Float(max(1, a.count)) }
        let e0 = mean(eyeIdx[0].map { p($0) }), e1 = mean(eyeIdx[1].map { p($0) })
        let bm = (mean(browRest[0]) + mean(browRest[1])) / 2
        browEyeRest = [e0, e1]
        browFrameRest = Self.browFaceFrame(e0, e1, bm)
    }
    /// While he walks (set by the brain): a short 0.08 s blink about every 2 s, never a double blink, never two within 1 s.
    var walkingBlinks = false
    private var blinkDur: Float = 0.12
    private var autoHold: Float = 0

    /// Advance the automatic blink; call once per rendered frame with the frame time.
    func tickBlink(dt: Float) {
        frameDt = max(1e-4, min(dt, 0.1))
        if blinking {
            blinkT += dt
            if blinkT >= blinkDur {
                blinking = false
                if walkingBlinks { doubleLeft = 0 }
                if doubleLeft > 0 { doubleLeft -= 1; gap = 0.1 } else { blinkWait = walkingBlinks ? 1.7 + 0.6 * nextRand() : 2 + 4 * nextRand() }
            }
        } else if gap > 0 {
            gap -= dt
            if gap <= 0 { blinking = true; blinkT = 0 }
        } else if autoBlink {
            autoHold = max(0, autoHold - dt)
            blinkWait -= dt
            if blinkWait <= 0 && autoHold <= 0 { blinking = true; blinkT = 0; blinkDur = walkingBlinks ? 0.112 : 0.12; doubleLeft = (!walkingBlinks && nextRand() < 0.2) ? 1 : 0 }
        }
        if blinking {
            // trapezoid: 12 ms to close, held closed, 12 ms to open (a 0.105 s walking blink is closed 0.081 s: two consecutive 24 fps frames)
            let ramp: Float = 0.012
            let k = min(1, max(0, min(blinkT, blinkDur - blinkT) / ramp))
            blinkOpen = 1 - k * k * (3 - 2 * k)
        } else { blinkOpen = 1 }
        refreshEyeHeight()
    }

    private func nextRand() -> Float {
        rng ^= rng << 13; rng ^= rng >> 17; rng ^= rng << 5
        return Float(rng >> 8) / Float(1 << 24)
    }

    private func refreshEyeHeight() {
        let c = Self.closedHeight
        eyeHeight = (c + (1 - c) * openness.left * blinkOpen, c + (1 - c) * openness.right * blinkOpen)
    }

    // MARK: skinning

    /// `dst` must hold `vertexCount * 6` floats.
    func update(x: [Float], index: [UInt32], into dst: UnsafeMutablePointer<Float>) {
        x.withUnsafeBufferPointer { xb in
            update(x: xb.baseAddress!, index: index, into: dst)
        }
    }

    func update(x: UnsafePointer<Float>, index: [UInt32], into dyn: UnsafeMutablePointer<Float>) {
        skinIdx.withUnsafeBufferPointer { si in
            skinW.withUnsafeBufferPointer { sw in
                for v in 0..<vertexCount {
                    let i4 = 4 * v, o = 6 * v
                    let a = 3 * Int(si[i4]), b = 3 * Int(si[i4 + 1]), c = 3 * Int(si[i4 + 2]), d = 3 * Int(si[i4 + 3])
                    let w0 = sw[i4], w1 = sw[i4 + 1], w2 = sw[i4 + 2], w3 = sw[i4 + 3]
                    dyn[o] = x[a] * w0 + x[b] * w1 + x[c] * w2 + x[d] * w3
                    dyn[o + 1] = x[a + 1] * w0 + x[b + 1] * w1 + x[c + 1] * w2 + x[d + 1] * w3
                    dyn[o + 2] = x[a + 2] * w0 + x[b + 2] * w1 + x[c + 2] * w2 + x[d + 2] * w3
                    dyn[o + 3] = 0; dyn[o + 4] = 0; dyn[o + 5] = 0
                }
            }
        }
        if !overrideVertices.isEmpty {
            for (k, vi) in overrideVertices.enumerated() {
                let o = 6 * Int(vi), t = overrideDelta[k]
                dyn[o] += t.x; dyn[o + 1] += t.y; dyn[o + 2] += t.z
            }
        }
        if !extraVertices.isEmpty {                         // touch play: a smooth additive skin offset (cheek squeeze); empty = exactly the plain skin
            for (k, vi) in extraVertices.enumerated() {
                let o = 6 * Int(vi), t = extraDelta[k]
                dyn[o] += t.x; dyn[o + 1] += t.y; dyn[o + 2] += t.z
            }
        }
        if beansActive {
            let bl = beanBlend
            for s in 0..<2 {
                let f = beanFirst[s]
                for i in 0..<FootBean.vertexCount {
                    let o = 6 * (f + i), t = beanPos[s][i], a = beanStart[s][i]
                    dyn[o] = a.x + (t.x - a.x) * bl; dyn[o + 1] = a.y + (t.y - a.y) * bl; dyn[o + 2] = a.z + (t.z - a.z) * bl
                }
            }
            let M = retractMatrix
            for (k, vi) in retractVertices.enumerated() where !Skinner.dbgNoRetract {
                var d = M * retractRest[k]
                let sd = retractSide[k]
                if sd >= 0 { d -= retractShift[Int(sd)] }
                let o = 6 * Int(vi), w = retractWeight[k] * bl
                dyn[o] += d.x * w; dyn[o + 1] += d.y * w; dyn[o + 2] += d.z * w
            }
        }
        if armCapsulesActive {
            let bl = armBlend
            for s in 0..<2 {
                let f = armFirst[s]
                for i in 0..<ArmCapsule.vertexCount {
                    let o = 6 * (f + i), t = armPos[s][i], a = armStart[s][i]
                    dyn[o] = a.x + (t.x - a.x) * bl; dyn[o + 1] = a.y + (t.y - a.y) * bl; dyn[o + 2] = a.z + (t.z - a.z) * bl
                }
            }
            let M = armRetractMatrix
            for (k, vi) in armRetractVertices.enumerated() where !Skinner.dbgNoArmRetract {
                let d = M * armRetractRest[k], o = 6 * Int(vi), w = armRetractWeight[k] * bl
                dyn[o] += d.x * w; dyn[o + 1] += d.y * w; dyn[o + 2] += d.z * w
            }
        }
        if hasEyes { applyEyes(x, dyn) }
        if !antennae.isEmpty { applyAntennae(x, dyn) }
        let hasShear = shearVec.x != 0 || shearVec.y != 0 || shearVec.z != 0, hasLobe = lobeD[0] != .zero || lobeD[1] != .zero
        if (hasShear || hasLobe) && lobeW[0].count == skinVerts.count && shearW.count == skinVerts.count {
            for (k, vi) in skinVerts.enumerated() {
                var d = SIMD3<Float>(0, 0, 0)
                if hasShear { d += shearVec * shearW[k] }
                if hasLobe { d += lobeD[0] * lobeW[0][k] + lobeD[1] * lobeW[1][k] }
                let o = 6 * Int(vi)
                dyn[o] += d.x; dyn[o + 1] += d.y; dyn[o + 2] += d.z
            }
        }
        index.withUnsafeBufferPointer { ix in
            var t = 0
            while t < ix.count {
                let a = 6 * Int(ix[t]), b = 6 * Int(ix[t + 1]), c = 6 * Int(ix[t + 2])
                let e1x = dyn[b] - dyn[a], e1y = dyn[b + 1] - dyn[a + 1], e1z = dyn[b + 2] - dyn[a + 2]
                let e2x = dyn[c] - dyn[a], e2y = dyn[c + 1] - dyn[a + 1], e2z = dyn[c + 2] - dyn[a + 2]
                let nx = e1y * e2z - e1z * e2y, ny = e1z * e2x - e1x * e2z, nz = e1x * e2y - e1y * e2x
                dyn[a + 3] += nx; dyn[a + 4] += ny; dyn[a + 5] += nz
                dyn[b + 3] += nx; dyn[b + 4] += ny; dyn[b + 5] += nz
                dyn[c + 3] += nx; dyn[c + 4] += ny; dyn[c + 5] += nz
                t += 3
            }
        }
        var o = 0
        let total = vertexCount * 6
        while o < total {
            var l = (dyn[o + 3] * dyn[o + 3] + dyn[o + 4] * dyn[o + 4] + dyn[o + 5] * dyn[o + 5]).squareRoot()
            if l == 0 { l = 1 }
            dyn[o + 3] /= l; dyn[o + 4] /= l; dyn[o + 5] /= l
            o += 6
        }
    }

    /// Carry each antenna rigidly with its crown frame, then add a damped spring-follow lag that grows toward the bobble.
    private func applyAntennae(_ x: UnsafePointer<Float>, _ dyn: UnsafeMutablePointer<Float>) {
        for k in 0..<antennae.count {
            var pts = (SIMD3<Float>.zero, SIMD3<Float>.zero, SIMD3<Float>.zero)   // no per-frame heap allocation
            for p in 0..<3 {
                var q = SIMD3<Float>(0, 0, 0)
                for j in 0..<4 {
                    let i = 3 * Int(antennae[k].anchorIdx[4 * p + j]), w = antennae[k].anchorW[4 * p + j]
                    q += SIMD3(x[i], x[i + 1], x[i + 2]) * w
                }
                if p == 0 { pts.0 = q } else if p == 1 { pts.1 = q } else { pts.2 = q }
            }
            let fr = Self.faceFrame(pts.0, pts.1, pts.2)
            let tip = pts.0 + fr.x * antennae[k].tipLocal.x + fr.y * antennae[k].tipLocal.y + fr.z * antennae[k].tipLocal.z
            // spring (semi-implicit, substepped): the bobble mass chases the rigidly carried tip
            if !antennae[k].started { antennae[k].p = tip; antennae[k].v = .zero; antennae[k].started = true }
            let sub = 4, h = frameDt / Float(sub), kS: Float = 380, cD: Float = 7
            for _ in 0..<sub {
                let a = (tip - antennae[k].p) * kS - antennae[k].v * cD
                antennae[k].v += a * h
                antennae[k].p += antennae[k].v * h
            }
            var D = antennae[k].p - tip
            let dl = simd_length(D)
            if dl > 0.3 { D *= 0.3 / dl; antennae[k].p = tip + D }
            let a = antennae[k]
            for i in 0..<a.count {
                let o = 6 * (a.first + i)
                let l = SIMD3(a.local[3 * i], a.local[3 * i + 1], a.local[3 * i + 2])
                let p = pts.0 + fr.x * l.x + fr.y * l.y + fr.z * l.z + D * a.weights[i]
                dyn[o] = p.x; dyn[o + 1] = p.y; dyn[o + 2] = p.z
            }
        }
    }

    /// Flatten each eye and its glint toward the eye's skinned centre along its current local up axis.
    private func applyEyes(_ x: UnsafePointer<Float>, _ dyn: UnsafeMutablePointer<Float>) {
        anchorIdx.withUnsafeBufferPointer { ai in
            anchorW.withUnsafeBufferPointer { aw in
                @inline(__always) func point(_ p: Int) -> (Float, Float, Float) {
                    var px: Float = 0, py: Float = 0, pz: Float = 0
                    for k in 0..<4 {
                        let i = 3 * Int(ai[4 * p + k]), w = aw[4 * p + k]
                        px += x[i] * w; py += x[i + 1] * w; pz += x[i + 2] * w
                    }
                    return (px, py, pz)
                }
                // rigid brows (W1c): the eye pair's frame carries the rest brows
                browW += ((browsRigid ? 1 : 0) - browW) * 0.12
                if browW > 0.002 && browsPrepared {
                    // frame: the two eyes' SURFACE centres (mean of their skinned vertices; the anchor points sit inside the body) and the anchors' up direction
                    func mean(_ ids: [Int32]) -> SIMD3<Float> {
                        var a = SIMD3<Float>(0, 0, 0)
                        for vi in ids { let o = 6 * Int(vi); a += SIMD3(dyn[o], dyn[o + 1], dyn[o + 2]) }
                        return a / Float(max(1, ids.count))
                    }
                    let e0 = mean(eyeIdx[0]), e1 = mean(eyeIdx[1])
                    // brow centres of the SKINNED brows: their symmetric mean fixes the face's up direction (a shear that tilts one brow cancels in the pair)
                    let b0 = mean(browIdx[0]), b1 = mean(browIdx[1])
                    let m = (e0 + e1) / 2
                    let cur = Self.browFaceFrame(e0, e1, (b0 + b1) / 2)
                    let R = cur * browFrameRest.transpose
                    do {
                        for sd in 0..<2 {
                            for (k, vi) in browIdx[sd].enumerated() {
                                let off: SIMD3<Float> = browRest[sd][k] - (browEyeRest[0] + browEyeRest[1]) / 2
                                let t: SIMD3<Float> = m + R * off
                                let o = 6 * Int(vi)
                                dyn[o] += (t.x - dyn[o]) * browW; dyn[o + 1] += (t.y - dyn[o + 1]) * browW; dyn[o + 2] += (t.z - dyn[o + 2]) * browW
                            }
                        }
                    }
                }

                browCW += ((browCounterOn ? 1 : 0) - browCW) * (browCounterOn ? 0.35 : 0.12)
                if browCW > 0.002 && browIdx[0].count > 0 && browIdx[1].count > 0 {
                    let vp = Self.gameViewProj
                    let view = simd_normalize(GameCamera.target - GameCamera.eye)
                    for sd in 0..<2 {
                        // a thick, steeply slanted brow is measured by its extreme screen points, so turn it in two passes (the second removes what is left)
                        for _ in 0..<2 {
                            var c = SIMD3<Float>(0, 0, 0)
                            var lo = SIMD2<Float>(.infinity, 0), hi = SIMD2<Float>(-.infinity, 0)
                            for vi in browIdx[sd] {
                                let o = 6 * Int(vi), p = SIMD3(dyn[o], dyn[o + 1], dyn[o + 2])
                                c += p
                                let q = vp * SIMD4(p, 1), sc = SIMD2(q.x / q.w * GameCamera.aspect, q.y / q.w)
                                if sc.x < lo.x { lo = sc }
                                if sc.x > hi.x { hi = sc }
                            }
                            c /= Float(browIdx[sd].count)
                            let inner = sd == 0 ? hi : lo, outer = sd == 0 ? lo : hi
                            let raw = atan2f(inner.y - outer.y, abs(inner.x - outer.x))
                            let ang = max(0, Self.browFloor - raw) * browCW * (sd == 0 ? 1 : -1)
                            if ang == 0 { break }
                            let q = simd_quatf(angle: ang, axis: -view)
                            for vi in browIdx[sd] {
                                let o = 6 * Int(vi)
                                let p = c + q.act(SIMD3(dyn[o], dyn[o + 1], dyn[o + 2]) - c)
                                let n = q.act(SIMD3(dyn[o + 3], dyn[o + 4], dyn[o + 5]))
                                dyn[o] = p.x; dyn[o + 1] = p.y; dyn[o + 2] = p.z; dyn[o + 3] = n.x; dyn[o + 4] = n.y; dyn[o + 5] = n.z
                            }
                        }
                    }
                }
                for e in 0..<2 {
                    let k = e == 0 ? eyeHeight.left : eyeHeight.right
                    if k >= 0.999 { continue }
                    let c = point(2 * e), u = point(2 * e + 1)
                    var ux = u.0 - c.0, uy = u.1 - c.1, uz = u.2 - c.2
                    let ul = (ux * ux + uy * uy + uz * uz).squareRoot()
                    if ul < 1e-6 { continue }
                    ux /= ul; uy /= ul; uz /= ul
                    let squash = 1 - k
                    // glints vanish as the eye closes (scaled into the eyeball, behind its front surface)
                    let gt = min(1, max(0, (k - 0.3) / 0.25)), g = gt * gt * (3 - 2 * gt)
                    eyeIdx[e].withUnsafeBufferPointer { vs in
                        for vi in vs {
                            let o = 6 * Int(vi)
                            let dx = dyn[o] - c.0, dy = dyn[o + 1] - c.1, dz = dyn[o + 2] - c.2
                            let s = (dx * ux + dy * uy + dz * uz) * squash
                            dyn[o] -= s * ux; dyn[o + 1] -= s * uy; dyn[o + 2] -= s * uz
                        }
                    }
                    glintIdx[e].withUnsafeBufferPointer { vs in
                        for vi in vs {
                            let o = 6 * Int(vi)
                            let dx = dyn[o] - c.0, dy = dyn[o + 1] - c.1, dz = dyn[o + 2] - c.2
                            let s = (dx * ux + dy * uy + dz * uz) * squash
                            dyn[o] = c.0 + (dx - s * ux) * g; dyn[o + 1] = c.1 + (dy - s * uy) * g; dyn[o + 2] = c.2 + (dz - s * uz) * g
                        }
                    }
                }
            }
        }
    }
}
