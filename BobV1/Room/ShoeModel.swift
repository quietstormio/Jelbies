//
//  ShoeModel.swift
//  Shoes (store, cosmetic only: NO effect on speed). A real 3D shell built FROM the foot bean's own vertices every frame: each bean vertex is pushed out
//  along its surface normal by a small thickness (a chunky sole at the bottom, fading to nothing toward the top where the foot sinks into the belly),
//  coloured by where it is on the foot (sole, toe cap, side stripe, upper). So a shoe is attached by construction (every shoe vertex is within
//  `maxThickness` of the bean surface) in every move, and it needs no body slot: rivals on the track keep their three tinted bodies.
//
//  `WearLook` carries the slot, so hats / bows / glasses can add `head` / `face` models the same way later (GameCare+Shoes.swift feeds the renderer).
//

import simd
import Foundation

nonisolated enum ShoeModel {
    /// Greatest distance of any shoe vertex from the bean vertex it grew from (the sole is the thickest part).
    static let maxThickness: Float = 0.03
    static let soleThickness: Float = 0.028, upperThickness: Float = 0.016

    /// Where each bean vertex sits on the foot (from the planted rest shape): u = 0 sole ... 1 crown, v = 0 heel ... 1 toe, sx = 0 centre ... 1 outer side.
    struct Style { var u: [Float] = [], v: [Float] = [], sx: [Float] = [] }
    static let style: Style = {
        let p = FootBean.localF
        let y0 = p.map(\.y).min() ?? 0, y1 = p.map(\.y).max() ?? 1
        let z0 = p.map(\.z).min() ?? 0, z1 = p.map(\.z).max() ?? 1
        let xm = p.map { abs($0.x) }.max() ?? 1
        var s = Style()
        for q in p {
            s.u.append((q.y - y0) / max(y1 - y0, 1e-5)); s.v.append((q.z - z0) / max(z1 - z0, 1e-5)); s.sx.append(abs(q.x) / max(xm, 1e-5))
        }
        return s
    }()
    static let tris: [UInt32] = FootBean.triangles(firstVertex: 0)

    /// ONE midpoint subdivision of the shell (every triangle -> 4, 418 + midpoints vertices), built from the same bean vertices (the sim bean is untouched).
    /// The shell is painted per TRIANGLE (flat colour at its centroid, hard-edged windows) so the colour bands have crisp edges at twice the resolution
    /// instead of smearing across the coarse triangles, and the laces / tongue / stitching (Tier B) have room to exist.
    struct Sub {
        var mids: [(a: Int32, b: Int32)] = []
        var tris: [UInt32] = []                      // 3 per triangle, indices into [bean vertices] + [midpoints], oriented outward
        var u: [Float] = [], v: [Float] = [], sx: [Float] = []              // per triangle centroid
        var vu: [Float] = [], vv: [Float] = [], vs: [Float] = []            // per vertex (bean vertices, then the midpoints)
        var triCount: Int { tris.count / 3 }
    }
    static let sub: Sub = {
        var sb = Sub()
        let n0 = FootBean.vertexCount
        var edge: [UInt64: Int32] = [:]
        func mid(_ a: UInt32, _ b: UInt32) -> UInt32 {
            let lo = min(a, b), hi = max(a, b)
            let key = UInt64(lo) << 32 | UInt64(hi)
            if let m = edge[key] { return UInt32(m) }
            let m = Int32(n0 + sb.mids.count)
            sb.mids.append((Int32(lo), Int32(hi))); edge[key] = m
            return UInt32(m)
        }
        let rest = FootBean.localF
        let rn = normals(rest)
        var t = 0
        var all: [UInt32] = []
        while t + 2 < tris.count {
            let a = tris[t], b = tris[t + 1], c = tris[t + 2]
            let ab = mid(a, b), bc = mid(b, c), ca = mid(c, a)
            all += [a, ab, ca, ab, b, bc, ca, bc, c, ab, bc, ca]
            t += 3
        }
        // positions of the midpoints at rest, to orient every triangle outward
        var p = rest, nn = rn
        for m in sb.mids { p.append((rest[Int(m.a)] + rest[Int(m.b)]) * 0.5); nn.append(simd_normalize(rn[Int(m.a)] + rn[Int(m.b)])) }
        var k = 0
        while k + 2 < all.count {
            let i0 = Int(all[k]), i1 = Int(all[k + 1]), i2 = Int(all[k + 2])
            let g = simd_cross(p[i1] - p[i0], p[i2] - p[i0])
            if simd_dot(g, nn[i0] + nn[i1] + nn[i2]) < 0 { all.swapAt(k + 1, k + 2) }
            k += 3
        }
        sb.tris = all
        // the (u, v, sx) of the midpoints are the means of their parents'; a triangle's coordinates are the mean of its corners'
        var uu = style.u, vv = style.v, ss = style.sx
        for m in sb.mids {
            uu.append((uu[Int(m.a)] + uu[Int(m.b)]) * 0.5); vv.append((vv[Int(m.a)] + vv[Int(m.b)]) * 0.5); ss.append((ss[Int(m.a)] + ss[Int(m.b)]) * 0.5)
        }
        sb.vu = uu; sb.vv = vv; sb.vs = ss
        k = 0
        while k + 2 < all.count {
            let a = Int(all[k]), b = Int(all[k + 1]), c = Int(all[k + 2])
            sb.u.append((uu[a] + uu[b] + uu[c]) / 3); sb.v.append((vv[a] + vv[b] + vv[c]) / 3); sb.sx.append((ss[a] + ss[b] + ss[c]) / 3)
            k += 3
        }
        return sb
    }()

    private static func srgb(_ r: Float, _ g: Float, _ b: Float) -> SIMD3<Float> { OKLab.srgbToLinear(SIMD3(r, g, b)) }
    private static func smooth(_ a: Float, _ b: Float, _ x: Float) -> Float { let t = min(max((x - a) / (b - a), 0), 1); return t * t * (3 - 2 * t) }

    /// The shell palette the tests and thumbnails speak of, read off the artist's paint spec (ShoePaint): `sole` the outsole, `band` the midsole line,
    /// `cap` the toe cap, `stripe` the side flash, `upper` / `top` the base colour.
    struct Palette {
        var upper: SIMD3<Float>, sole: SIMD3<Float>, cap: SIMD3<Float>, stripe: SIMD3<Float>, top: SIMD3<Float>, band: SIMD3<Float>
    }
    static func palette(_ l: WearLook) -> Palette {
        let base = ShoePaint.style(l)?.base ?? SIMD3(0.7, 0.7, 0.7)
        func layer(_ n: String) -> SIMD3<Float> { ShoePaint.layerColour(l, n) ?? base }
        return Palette(upper: base, sole: layer("outsole").or(layer("suede_sole")), cap: layer("toe_cap"), stripe: layer("side_flash"), top: base, band: layer("midsole"))
    }

    /// Thickness of the shell at bean vertex `i`.
    static func thickness(_ i: Int) -> Float {
        let u = style.u[i]
        let sole = 1 - smooth(0.09, 0.20, u)
        let upper = upperThickness * (1 - smooth(0.55, 0.95, u))
        return upper + (soleThickness - upperThickness) * sole
    }

    /// Smooth vertex normals of the deformed bean (area weighted), turned outward from its centre.
    static func normals(_ w: [SIMD3<Float>]) -> [SIMD3<Float>] {
        var n = [SIMD3<Float>](repeating: .zero, count: w.count)
        var c = SIMD3<Float>.zero
        for p in w { c += p }
        c /= Float(max(w.count, 1))
        var t = 0
        while t + 2 < tris.count {
            let a = Int(tris[t]), b = Int(tris[t + 1]), d = Int(tris[t + 2])
            let g = simd_cross(w[b] - w[a], w[d] - w[a])
            n[a] += g; n[b] += g; n[d] += g
            t += 3
        }
        var s: Float = 0
        for i in w.indices { s += simd_dot(n[i], w[i] - c) }
        let sign: Float = s < 0 ? -1 : 1
        return n.map { simd_length_squared($0) > 1e-14 ? simd_normalize($0) * sign : SIMD3(0, 1, 0) }
    }

    /// The shoe of one foot as a world-space mesh. `bean` = the foot's 418 world vertices; `floorY` keeps the sole off the floor; `time` twinkles the glitter.
    static func build(_ look: WearLook, bean w: [SIMD3<Float>], floorY: Float, time: Float, side: Int, body: SIMD3<Float> = SIMD3(0.35, 0.5, 0.9), gpuPaint: Bool = false, into b: RoomMeshBuilder) {
        guard w.count == FootBean.vertexCount else { return }
        buildShell(look, bean: w, floorY: floorY, body: body, time: time, gpuPaint: gpuPaint, into: b)
        if look == .glitterShoes { sparkles(b, w: w, n: normals(w), time: time, side: side) }
    }

    /// The shell alone (no twinkling sparkles): what the room caches while a foot is not deforming. `body` = the Jelly's own colour (linear; the ballet flats'
    /// opening shows it); `time` drives the light-up sneakers' glow (they are never cached).
    /// `gpuPaint`: the vertices carry the paint coordinates (u, v, sx), the look and the body colour and the room FRAGMENT shader paints the look per
    /// pixel (ShoeGPU); false = the per-vertex colours (store thumbnails, tests).
    static func buildShell(_ look: WearLook, bean w: [SIMD3<Float>], floorY: Float, body: SIMD3<Float> = SIMD3(0.35, 0.5, 0.9), time: Float = 0,
                           gpuPaint: Bool = false, into b: RoomMeshBuilder) {
        guard w.count == FootBean.vertexCount else { return }
        let n = normals(w)
        let sb = sub
        let paint: (col: [SIMD3<Float>], glow: [Float]) = gpuPaint ? ([], []) : ShoePaint.paintVertices(look, body: body)
        let glowing = look == .sneakerLightup
        let ph = 0.5 + 0.5 * sinf(time * 2.6)           // the light-up sneakers cycle cyan <-> pink
        let glowCol = mix(srgb(0.25, 0.92, 1.0), srgb(1.0, 0.45, 0.78), ph)
        var P = [SIMD3<Float>](), N = [SIMD3<Float>]()
        P.reserveCapacity(w.count + sb.mids.count); N.reserveCapacity(w.count + sb.mids.count)
        for i in w.indices {
            var p = w[i] + n[i] * thickness(i)
            p.y = max(p.y, floorY)
            P.append(p); N.append(n[i])
        }
        for m in sb.mids { P.append((P[Int(m.a)] + P[Int(m.b)]) * 0.5); N.append(simd_normalize(N[Int(m.a)] + N[Int(m.b)])) }
        // vertex i stays "bean vertex i" (the first 418; attachment tests and the sparkles index them), followed by the edge midpoints
        let base = UInt32(b.mesh.vertices.count)
        b.mesh.vertices.reserveCapacity(b.mesh.vertices.count + P.count)
        if gpuPaint {
            let mat = ShoeGPU.material(look), pack = ShoeGPU.packBody(body)
            let phase: Float = glowing ? ph : 0
            for i in P.indices {
                b.mesh.vertices.append(RoomVertex(pos: SIMD4(P[i], mat), normal: SIMD4(N[i], pack), color: SIMD4(sb.vu[i], sb.vv[i], sb.vs[i], phase)))
            }
            b.mesh.indices.reserveCapacity(b.mesh.indices.count + sb.tris.count)
            for i in sb.tris { b.mesh.indices.append(base + i) }
            return
        }
        for i in P.indices {
            var col = paint.col[i], ao: Float = 1
            if glowing, paint.glow[i] > 0.02 { col = mix(col, glowCol, paint.glow[i]); ao = 1 + paint.glow[i] * (0.65 + 0.35 * ph) }
            b.mesh.vertices.append(RoomVertex(pos: SIMD4(P[i], 0), normal: SIMD4(N[i], ao), color: SIMD4(col, 1)))
        }
        b.mesh.indices.reserveCapacity(b.mesh.indices.count + sb.tris.count)
        for i in sb.tris { b.mesh.indices.append(base + i) }
    }

    /// The glitter shoes' twinkle on top of the (cached) shell.
    static func addSparkles(_ b: RoomMeshBuilder, bean w: [SIMD3<Float>], time: Float, side: Int) {
        guard w.count == FootBean.vertexCount else { return }
        sparkles(b, w: w, n: normals(w), time: time, side: side)
    }

    private static func mix(_ a: SIMD3<Float>, _ c: SIMD3<Float>, _ k: Float) -> SIMD3<Float> { a + (c - a) * min(max(k, 0), 1) }

    /// Little twinkling diamonds on the shoe.
    private static func sparkles(_ b: RoomMeshBuilder, w: [SIMD3<Float>], n: [SIMD3<Float>], time: Float, side: Int) {
        let gold = srgb(1.0, 0.92, 0.55), white = srgb(1, 1, 1)
        for k in 0..<14 {
            let ring = 2 + (k * 5) % 9, j = (k * 11 + side * 7) % FootBean.around
            let i = 1 + FootBean.around * ring + j
            guard i < w.count - 1, style.u[i] > 0.2 else { continue }
            let tw = 0.5 + 0.5 * sinf(time * 4.2 + Float(k) * 1.7 + Float(side))
            let r = 0.011 + 0.009 * tw
            let c = w[i] + n[i] * (thickness(i) + 0.003)
            let col = k % 2 == 0 ? gold : white
            let ids = [SIMD3<Float>(1, 0, 0), SIMD3(-1, 0, 0), SIMD3(0, 1, 0), SIMD3(0, -1, 0), SIMD3(0, 0, 1), SIMD3(0, 0, -1)].map { d in
                b.vertex(c + d * r * (d.y != 0 ? 1.5 : 1), d, ao: 1, color: col)
            }
            for (a, bb, cc) in [(0, 2, 4), (4, 2, 1), (1, 2, 5), (5, 2, 0), (0, 4, 3), (4, 1, 3), (1, 5, 3), (5, 0, 3)] { b.triangle(ids[a], ids[bb], ids[cc]) }
        }
    }
}

private extension SIMD3 where Scalar == Float {
    /// self, or `other` when self is black (a missing layer reads as zero).
    func or(_ other: SIMD3<Float>) -> SIMD3<Float> { simd_length(self) > 1e-6 ? self : other }
}
