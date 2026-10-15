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
    private let blinkDuration: Float = 0.12
    /// Current eye height factors (closedHeight ... 1) after expression + blink (left, right).
    private(set) var eyeHeight: (left: Float, right: Float) = (1, 1)
    private var blinkOpen: Float = 1

    /// Animation hook (BlobBrain arm paths): additive world-space displacement of some render vertices, plus the AO value
    /// written to those vertices' mat channel (see `takeMatWrites`). Empty = off.
    var overrideVertices: [Int32] = []
    var overrideDelta: [SIMD3<Float>] = []
    var overrideMat: [Float] = []
    private var pendingRestore: [Int32] = []

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
            eyeIdx = e.eye; glintIdx = e.glint
            var ai = [Int32](repeating: 0, count: 16)
            for p in 0..<4 { let t = Int(e.anchorTet[p]); for k in 0..<4 { ai[4 * p + k] = Int32(simTets[4 * t + k]) } }
            anchorIdx = ai; anchorW = e.anchorW
            hasEyes = true
        } else {
            eyeIdx = [[], []]; glintIdx = [[], []]; anchorIdx = []; anchorW = []; hasEyes = false
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
                let fr = Self.frame(c, u, sd)
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

    private static func frame(_ c: SIMD3<Float>, _ u: SIMD3<Float>, _ s: SIMD3<Float>) -> (x: SIMD3<Float>, y: SIMD3<Float>, z: SIMD3<Float>) {
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
    func blinkNow(double: Bool = false) { blinking = true; blinkT = 0; doubleLeft = double ? 1 : 0; gap = 0 }

    /// Advance the automatic blink; call once per rendered frame with the frame time.
    func tickBlink(dt: Float) {
        frameDt = max(1e-4, min(dt, 0.1))
        if blinking {
            blinkT += dt
            if blinkT >= blinkDuration {
                blinking = false
                if doubleLeft > 0 { doubleLeft -= 1; gap = 0.1 } else { blinkWait = 2 + 4 * nextRand() }
            }
        } else if gap > 0 {
            gap -= dt
            if gap <= 0 { blinking = true; blinkT = 0 }
        } else if autoBlink {
            blinkWait -= dt
            if blinkWait <= 0 { blinking = true; blinkT = 0; doubleLeft = nextRand() < 0.2 ? 1 : 0 }
        }
        if blinking {
            let s = sinf(Float.pi * min(blinkT, blinkDuration) / blinkDuration)
            blinkOpen = 1 - min(1, 1.5 * s)
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
        if hasEyes { applyEyes(x, dyn) }
        if !antennae.isEmpty { applyAntennae(x, dyn) }
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
            let fr = Self.frame(pts.0, pts.1, pts.2)
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
