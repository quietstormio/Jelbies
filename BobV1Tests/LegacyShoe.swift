//
//  LegacyShoe.swift
//  The first shoe shell (before the paint specs, the subdivided hard-edged shell and the thicker sole), kept ONLY so the capture suite can show
//  "before" next to "after" (shoes_closeup.png). Not used by the game.
//

import simd
@testable import BobV1

enum LegacyShoe {
    private static func srgb(_ r: Float, _ g: Float, _ b: Float) -> SIMD3<Float> { OKLab.srgbToLinear(SIMD3(r, g, b)) }
    private static func smooth(_ a: Float, _ b: Float, _ x: Float) -> Float { let t = min(max((x - a) / (b - a), 0), 1); return t * t * (3 - 2 * t) }
    private static func mix(_ a: SIMD3<Float>, _ c: SIMD3<Float>, _ k: Float) -> SIMD3<Float> { a + (c - a) * min(max(k, 0), 1) }
    struct Pal { var upper, sole, cap, stripe, top, band: SIMD3<Float> }
    static func pal(_ l: WearLook) -> Pal? {
        let cream = srgb(0.99, 0.97, 0.92)
        switch l {
        case .sneakerMint: return Pal(upper: srgb(0.56, 0.84, 0.72), sole: srgb(0.20, 0.42, 0.38), cap: srgb(0.82, 0.96, 0.89), stripe: srgb(0.30, 0.62, 0.52), top: srgb(0.56, 0.84, 0.72), band: cream)
        case .sneakerSun: return Pal(upper: srgb(1.0, 0.82, 0.30), sole: srgb(0.74, 0.40, 0.13), cap: srgb(1.0, 0.94, 0.68), stripe: srgb(0.95, 0.55, 0.20), top: srgb(1.0, 0.82, 0.30), band: cream)
        case .sneakerCoral: return Pal(upper: srgb(0.98, 0.56, 0.52), sole: srgb(0.52, 0.18, 0.24), cap: srgb(1.0, 0.84, 0.82), stripe: srgb(0.74, 0.30, 0.36), top: srgb(0.98, 0.56, 0.52), band: cream)
        case .rainBoots: return Pal(upper: srgb(1.0, 0.84, 0.22), sole: srgb(0.22, 0.28, 0.48), cap: srgb(1.0, 0.84, 0.22), stripe: srgb(1.0, 0.94, 0.62), top: srgb(1.0, 0.90, 0.40), band: srgb(1.0, 0.94, 0.62))
        case .glitterShoes: return Pal(upper: srgb(0.78, 0.62, 0.96), sole: srgb(0.44, 0.30, 0.68), cap: srgb(0.93, 0.84, 1.0), stripe: srgb(0.99, 0.72, 0.88), top: srgb(0.78, 0.62, 0.96), band: cream)
        default: return nil
        }
    }
    static func build(_ look: WearLook, bean w: [SIMD3<Float>], floorY: Float, into b: RoomMeshBuilder) {
        guard let p = pal(look), w.count == FootBean.vertexCount else { return }
        let n = ShoeModel.normals(w)
        let base = UInt32(b.mesh.vertices.count)
        let st = ShoeModel.style
        for i in w.indices {
            let u = st.u[i], sole = 1 - smooth(0.09, 0.20, u)
            let th = 0.012 * (1 - smooth(0.55, 0.95, u)) + (0.022 - 0.012) * sole
            var q = w[i] + n[i] * th
            q.y = max(q.y, floorY)
            let v = st.v[i], sx = st.sx[i]
            var col = p.upper
            col = mix(col, p.top, smooth(0.62, 0.90, u))
            if look != .rainBoots { col = mix(col, p.cap, smooth(0.66, 0.74, v) * (1 - smooth(0.48, 0.58, u))) }
            col = mix(col, p.stripe, smooth(0.58, 0.72, sx) * smooth(0.20, 0.27, u) * (1 - smooth(0.50, 0.58, u)) * (0.4 < v && v < 0.85 ? 1 : 0))
            if look == .rainBoots { col = mix(col, p.stripe, smooth(0.42, 0.5, u) * (1 - smooth(0.5, 0.58, u)) * 0.8) }
            col = mix(col, p.band, smooth(0.11, 0.15, u) * (1 - smooth(0.19, 0.24, u)))
            col = mix(col, p.sole, 1 - smooth(0.06, 0.12, u))
            b.vertex(q, n[i], ao: 1, color: col)
        }
        var t = 0
        while t + 2 < ShoeModel.tris.count { b.triangle(base + ShoeModel.tris[t], base + ShoeModel.tris[t + 1], base + ShoeModel.tris[t + 2]); t += 3 }
    }
}
