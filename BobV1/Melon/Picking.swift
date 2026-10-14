//
//  Picking.swift
//  Ray / screen-space picking against the skinned surface and sim particles (port of pick/pickNear).
//

import Foundation
import simd

/// Moeller-Trumbore against the first `bodyIndexCount` indices of `index`.
/// `dyn` holds 6 floats per vertex (pos xyz first). Returns the nearest hit point or nil.
func pickRay(origin o: SIMD3<Float>, dir d: SIMD3<Float>, dyn: UnsafePointer<Float>,
             index: [UInt32], bodyIndexCount: Int) -> SIMD3<Float>? {
    var best = Float.infinity
    index.withUnsafeBufferPointer { ix in
        var t = 0
        let end = min(bodyIndexCount, ix.count)
        while t + 2 < end {
            let a = 6 * Int(ix[t]), b = 6 * Int(ix[t + 1]), c = 6 * Int(ix[t + 2])
            t += 3
            let e1x = dyn[b] - dyn[a], e1y = dyn[b + 1] - dyn[a + 1], e1z = dyn[b + 2] - dyn[a + 2]
            let e2x = dyn[c] - dyn[a], e2y = dyn[c + 1] - dyn[a + 1], e2z = dyn[c + 2] - dyn[a + 2]
            let px = d.y * e2z - d.z * e2y, py = d.z * e2x - d.x * e2z, pz = d.x * e2y - d.y * e2x
            let det = e1x * px + e1y * py + e1z * pz
            if abs(det) < 1e-12 { continue }
            let inv = 1 / det
            let tx = o.x - dyn[a], ty = o.y - dyn[a + 1], tz = o.z - dyn[a + 2]
            let uu = (tx * px + ty * py + tz * pz) * inv
            if uu < 0 || uu > 1 { continue }
            let qx = ty * e1z - tz * e1y, qy = tz * e1x - tx * e1z, qz = tx * e1y - ty * e1x
            let vv = (d.x * qx + d.y * qy + d.z * qz) * inv
            if vv < 0 || uu + vv > 1 { continue }
            let tt = (e2x * qx + e2y * qy + e2z * qz) * inv
            if tt > 1e-4 && tt < best { best = tt }
        }
    }
    return best < .infinity ? o + d * best : nil
}

/// Forgiving fallback for grabs that land just outside the silhouette: nearest sim particle within
/// `maxPx` points of `screenPoint` (origin top-left, y down).
func pickNear(screenPoint: SIMD2<Float>, viewProj M: simd_float4x4, viewSize: SIMD2<Float>,
              x: [Float], maxPx: Float) -> SIMD3<Float>? {
    var best = -1
    var bd = maxPx * maxPx
    x.withUnsafeBufferPointer { p in
        for i in 0..<(p.count / 3) {
            let c = M * SIMD4<Float>(p[3 * i], p[3 * i + 1], p[3 * i + 2], 1)
            let w = c.w
            if w <= 0 { continue }   // behind the camera
            let sx = (c.x / w * 0.5 + 0.5) * viewSize.x
            let sy = (0.5 - c.y / w * 0.5) * viewSize.y
            let dx = sx - screenPoint.x, dy = sy - screenPoint.y
            let d = dx * dx + dy * dy - w * 1e-3   // prefer nearer particles on ties
            if d < bd { bd = d; best = i }
        }
    }
    return best < 0 ? nil : SIMD3(x[3 * best], x[3 * best + 1], x[3 * best + 2])
}

/// World-space ray through an NDC point (x, y in -1...1, y up). Clip z 0 and 1 (Metal / WebGPU depth range).
func unproject(ndc: SIMD2<Float>, invViewProj m: simd_float4x4) -> (o: SIMD3<Float>, d: SIMD3<Float>) {
    func un(_ z: Float) -> SIMD3<Float> {
        let p = m * SIMD4<Float>(ndc.x, ndc.y, z, 1)
        return SIMD3(p.x, p.y, p.z) / p.w
    }
    let a = un(0), b = un(1)
    return (a, simd_normalize(b - a))
}
