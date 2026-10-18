//
//  BathModels.swift
//  Meshes for the Bath: the BATHROOM set (modern luxury, tone-on-tone warm grey: stone slabs, smoked wood, brushed nickel; soaking tub, rain shower, vanity with a round mirror, window, niche, towel rail, olive tree), Bob's own
//  shallow wash basin with its rippling water, and the small per-frame props: the held tool
//  (jelly soap / polishing cloth), sud bubbles and spray droplets.
//  Vertex = RoomVertex: pos (w = material), normal (w = baked AO), colour (a = alpha). Materials (see BathShaders.metal):
//    0 matte  1 glossy ceramic  2 fabric  3 emissive  4 jelly  5 water  6 sud bubble  7 water droplet  8 glitter  9 star  10 marble  11 porcelain  12 oak  13 metal
//  World frame: y up, floor is xz, +z toward the camera.
//

import simd
import Foundation

nonisolated enum BathMat: Float { case matte = 0, glossy = 1, fabric = 2, glow = 3, jelly = 4, water = 5, bubble = 6, droplet = 7, glitter = 8, star = 9, puff = 14, stone = 10, porcelain = 11, oak = 12, metal = 13 }

/// sRGB (0...1) to the linear colour the shaders use.
nonisolated func bathLin(_ r: Float, _ g: Float, _ b: Float) -> SIMD3<Float> { OKLab.srgbToLinear(SIMD3(r, g, b)) }

/// A growable triangle soup in RoomVertex layout. Reusable: `clear()` keeps capacity, so the per-frame props allocate nothing once warm.
nonisolated struct BathSoup {
    var v: [RoomVertex] = []
    var i: [UInt32] = []
    mutating func clear() { v.removeAll(keepingCapacity: true); i.removeAll(keepingCapacity: true) }

    @discardableResult
    mutating func vert(_ p: SIMD3<Float>, _ n: SIMD3<Float>, _ c: SIMD3<Float>, mat: BathMat, ao: Float = 1, alpha: Float = 1) -> UInt32 {
        v.append(RoomVertex(pos: SIMD4(p, mat.rawValue), normal: SIMD4(n, ao), color: SIMD4(c, alpha)))
        return UInt32(v.count - 1)
    }
    /// Triangle whose winding is flipped to agree with the vertex normals (front faces are CCW).
    mutating func tri(_ a: UInt32, _ b: UInt32, _ c: UInt32) {
        func p(_ k: UInt32) -> SIMD3<Float> { SIMD3(v[Int(k)].pos.x, v[Int(k)].pos.y, v[Int(k)].pos.z) }
        func n(_ k: UInt32) -> SIMD3<Float> { SIMD3(v[Int(k)].normal.x, v[Int(k)].normal.y, v[Int(k)].normal.z) }
        let g = simd_cross(p(b) - p(a), p(c) - p(a))
        if simd_length_squared(g) < 1e-14 { return }
        if simd_dot(g, n(a) + n(b) + n(c)) >= 0 { i.append(contentsOf: [a, b, c]) } else { i.append(contentsOf: [a, c, b]) }
    }
    mutating func quad(_ a: UInt32, _ b: UInt32, _ c: UInt32, _ d: UInt32) { tri(a, b, c); tri(a, c, d) }

    /// Copies a RoomMesh in with a new material (and alpha).
    mutating func append(_ m: RoomMesh, mat: BathMat, alpha: Float = 1) {
        let base = UInt32(v.count)
        for var x in m.vertices { x.pos.w = mat.rawValue; x.color.w = alpha; v.append(x) }
        for k in m.indices { i.append(base + k) }
    }

    /// Ellipsoid with arbitrary (scaled, orthogonal) axes.
    mutating func ellipsoid(_ c: SIMD3<Float>, ax: SIMD3<Float>, ay: SIMD3<Float>, az: SIMD3<Float>, color: SIMD3<Float>, mat: BathMat,
                            alpha: Float = 1, rings: Int = 5, segs: Int = 8, ao: Float = 1) {
        let lx = max(simd_length_squared(ax), 1e-10), ly = max(simd_length_squared(ay), 1e-10), lz = max(simd_length_squared(az), 1e-10)
        var grid: [[UInt32]] = []
        grid.reserveCapacity(rings + 1)
        for k in 0...rings {
            let phi = -Float.pi / 2 + Float(k) / Float(rings) * .pi
            var row: [UInt32] = []
            row.reserveCapacity(segs + 1)
            let cp = cosf(phi), sp = sinf(phi)
            for j in 0...segs {
                let th = Float(j) / Float(segs) * 2 * .pi
                let x = cp * cosf(th), z = cp * sinf(th)
                let p = c + ax * x + ay * sp + az * z
                let n = simd_normalize(ax * (x / lx) + ay * (sp / ly) + az * (z / lz))
                row.append(vert(p, n, color, mat: mat, ao: ao, alpha: alpha))
            }
            grid.append(row)
        }
        for k in 0..<rings { for j in 0..<segs { quad(grid[k][j], grid[k][j + 1], grid[k + 1][j + 1], grid[k + 1][j]) } }
    }
    mutating func sphere(_ c: SIMD3<Float>, _ r: Float, color: SIMD3<Float>, mat: BathMat, alpha: Float = 1, rings: Int = 5, segs: Int = 8) {
        ellipsoid(c, ax: SIMD3(r, 0, 0), ay: SIMD3(0, r, 0), az: SIMD3(0, 0, r), color: color, mat: mat, alpha: alpha, rings: rings, segs: segs)
    }

    /// Surface of revolution about an axis through `o` (unit `up`), profile of (radius, height) points with outward (nr, ny) normals.
    mutating func revolve(_ o: SIMD3<Float>, up: SIMD3<Float>, side: SIMD3<Float>, profile: [(r: Float, y: Float)], color: SIMD3<Float>,
                          mat: BathMat, alpha: Float = 1, segs: Int = 10) {
        let fwd = simd_cross(side, up)
        var grid: [[UInt32]] = []
        for (k, pp) in profile.enumerated() {
            let a = profile[max(k - 1, 0)], b = profile[min(k + 1, profile.count - 1)]
            let t = SIMD2<Float>(b.r - a.r, b.y - a.y)
            let nn = simd_normalize(SIMD2<Float>(t.y, -t.x))
            var row: [UInt32] = []
            for j in 0...segs {
                let th = Float(j) / Float(segs) * 2 * .pi
                let radial = side * cosf(th) + fwd * sinf(th)
                row.append(vert(o + radial * pp.r + up * pp.y, simd_normalize(radial * nn.x + up * nn.y), color, mat: mat, alpha: alpha))
            }
            grid.append(row)
        }
        for k in 0..<(grid.count - 1) { for j in 0..<segs { quad(grid[k][j], grid[k][j + 1], grid[k + 1][j + 1], grid[k + 1][j]) } }
    }

    /// Capped tube (cone frustum) between two points.
    mutating func tube(_ a: SIMD3<Float>, _ b: SIMD3<Float>, r0: Float, r1: Float, color: SIMD3<Float>, mat: BathMat, alpha: Float = 1, segs: Int = 8) {
        let d = b - a
        let len = simd_length(d)
        guard len > 1e-6 else { return }
        let up = d / len
        let ref: SIMD3<Float> = abs(up.y) < 0.95 ? SIMD3(0, 1, 0) : SIMD3(1, 0, 0)
        let side = simd_normalize(simd_cross(ref, up))
        revolve(a, up: up, side: side, profile: [(0, 0), (r0, 0), (r0, 0.0001), (r1, len - 0.0001), (r1, len), (0, len)], color: color, mat: mat, alpha: alpha, segs: segs)
    }
}

// MARK: - Bob's wash basin and the bathroom

nonisolated enum BathModels {
    /// Basin geometry (world, y up). Bob stands at the centre; the water is ankle height.
    static let basinCentre = SIMD2<Float>(0, 1.0)
    static let basinOuterR: Float = 1.12
    static let basinInnerR: Float = 0.93
    static let rimTop: Float = 0.37
    static let waterY: Float = 0.17
    static let waterR: Float = 0.915

    static let roomX: Float = 3.4, backZ: Float = -2.0, frontZ: Float = 14.5, ceilingY: Float = 8.0

    // MARK: palette (modern luxury: warm stone, white porcelain, oak / walnut, brushed brass and matte black)
    static let marble = bathLin(0.64, 0.62, 0.59)
    static let porcelain = bathLin(0.47, 0.45, 0.43)
    static let tubWhite = bathLin(0.93, 0.92, 0.90)
    static let brass = bathLin(0.70, 0.70, 0.70)          // brushed nickel / soft pewter (name kept)
    static let matteBlack = bathLin(0.10, 0.10, 0.10)      // soft black
    static let walnut = bathLin(0.30, 0.27, 0.25)           // smoked taupe wood
    static let greige = bathLin(0.66, 0.64, 0.60)           // grey linen

    static func hash(_ a: Int, _ b: Int) -> Float {
        var h = UInt32(truncatingIfNeeded: a &* 374761393 &+ b &* 668265263)
        h = (h ^ (h >> 13)) &* 1274126177
        return Float((h ^ (h >> 16)) & 0xFFFF) / 65535
    }
    static func smooth(_ a: Float, _ b: Float, _ x: Float) -> Float { let t = min(max((x - a) / (b - a), 0), 1); return t * t * (3 - 2 * t) }

    /// A subdivided flat plane (so the baked occlusion can vary across it). `n` faces into the room.
    static func plane(_ s: inout BathSoup, origin o: SIMD3<Float>, u: SIMD3<Float>, v: SIMD3<Float>, nu: Int, nv: Int, n: SIMD3<Float>,
                      mat: BathMat, color: SIMD3<Float>, ao: (SIMD3<Float>) -> Float) {
        var grid: [[UInt32]] = []
        for j in 0...nv {
            var row: [UInt32] = []
            for i in 0...nu {
                let p = o + u * (Float(i) / Float(nu)) + v * (Float(j) / Float(nv))
                row.append(s.vert(p, n, color, mat: mat, ao: ao(p)))
            }
            grid.append(row)
        }
        for j in 0..<nv { for i in 0..<nu { s.quad(grid[j][i], grid[j][i + 1], grid[j + 1][i + 1], grid[j + 1][i]) } }
    }

    static func floorAO(_ p: SIMD3<Float>) -> Float {
        let dx = roomX - abs(p.x), dz = p.z - backZ
        var ao = 0.66 + 0.34 * smooth(0, 0.9, min(dx, dz))
        let r = simd_length(SIMD2(p.x - basinCentre.x, p.z - basinCentre.y))
        ao *= 0.74 + 0.26 * smooth(basinOuterR, basinOuterR + 0.5, r)
        return ao
    }
    static func wallAO(_ p: SIMD3<Float>) -> Float {
        (0.72 + 0.28 * smooth(0, 1.0, p.y)) * (0.86 + 0.14 * smooth(0, 0.9, ceilingY - p.y)) * (0.86 + 0.14 * smooth(0, 0.7, min(roomX - abs(p.x), p.z - backZ + 1)))
    }

    /// Frosted bottle / jar standing at `base` (rest on a shelf).
    private static func bottle(_ s: inout BathSoup, base: SIMD3<Float>, r: Float, h: Float, color: SIMD3<Float>, cap: SIMD3<Float>, mat: BathMat = .glossy) {
        s.revolve(base, up: SIMD3(0, 1, 0), side: SIMD3(1, 0, 0), profile: [(0, 0), (r, 0), (r, h * 0.62), (r * 0.62, h * 0.82), (r * 0.42, h * 0.95), (0, h * 0.95)], color: color, mat: mat, segs: 14)
        s.revolve(base + SIMD3(0, h * 0.93, 0), up: SIMD3(0, 1, 0), side: SIMD3(1, 0, 0), profile: [(0, 0), (r * 0.48, 0), (r * 0.48, h * 0.16), (0, h * 0.16)], color: cap, mat: .metal, segs: 12)
    }

    /// The whole static bathroom + Bob's basin (everything opaque): a calm, modern spa-style room.
    static func buildSet() -> RoomMesh {
        var s = BathSoup()
        let H = ceilingY, X = roomX, Z0 = backZ, Z1 = frontZ

        // large-format stone slabs (veining and slab seams are drawn by the shader)
        plane(&s, origin: SIMD3(-X, 0, Z0), u: SIMD3(2 * X, 0, 0), v: SIMD3(0, H, 0), nu: 14, nv: 8, n: SIMD3(0, 0, 1), mat: .stone, color: marble, ao: wallAO)
        for sx in [Float(-1), 1] {
            plane(&s, origin: SIMD3(sx * X, 0, Z0), u: SIMD3(0, 0, Z1 - Z0), v: SIMD3(0, H, 0), nu: 20, nv: 6, n: SIMD3(-sx, 0, 0), mat: .stone, color: marble, ao: wallAO)
        }
        plane(&s, origin: SIMD3(-X, 0, Z0), u: SIMD3(2 * X, 0, 0), v: SIMD3(0, 0, Z1 - Z0), nu: 14, nv: 28, n: SIMD3(0, 1, 0), mat: .porcelain, color: porcelain, ao: floorAO)
        plane(&s, origin: SIMD3(-X, H, Z0), u: SIMD3(2 * X, 0, 0), v: SIMD3(0, 0, Z1 - Z0), nu: 2, nv: 4, n: SIMD3(0, -1, 0), mat: .matte, color: bathLin(0.85, 0.84, 0.82), ao: { _ in 0.9 })
        // slim matte-black skirting
        do {
            let b = RoomMeshBuilder()
            b.roundedBox(centre: SIMD3(0, 0.05, Z0 + 0.02), half: SIMD3(X, 0.05, 0.02), radius: 0.01, segments: 1, aoFloor: false, color: matteBlack)
            s.append(b.mesh, mat: .matte)
        }

        // --- freestanding oval soaking tub (behind, left of centre) ---
        do {
            let cx: Float = -0.55, cz: Float = -1.0
            func oval(_ rx: Float, _ rz: Float) -> [SIMD2<Float>] { (0..<40).map { let a = Float($0) / 40 * 2 * .pi; return SIMD2(cx + rx * cosf(a), cz + rz * sinf(a)) } }
            let t = RoomMeshBuilder()
            DiningModels.extrudeRounded(t, poly: oval(1.12, 0.46), y0: 0.04, y1: 0.28, bevel: 0.04, color: bathLin(0.62, 0.60, 0.57))          // recessed plinth
            DiningModels.extrudeRounded(t, poly: oval(1.34, 0.64), y0: 0.2, y1: 0.86, bevel: 0.16, color: tubWhite)                            // shell
            s.append(t.mesh, mat: .glossy)
            let inner = RoomMeshBuilder()
            DiningModels.extrudeRounded(inner, poly: oval(1.22, 0.52), y0: 0.80, y1: 0.875, bevel: 0.02, color: bathLin(0.74, 0.72, 0.70))     // thin-rim inside
            s.append(inner.mesh, mat: .glossy)
            let w = RoomMeshBuilder()
            DiningModels.extrudeRounded(w, poly: oval(1.2, 0.5), y0: 0.84, y1: 0.89, bevel: 0.01, color: bathLin(0.76, 0.80, 0.82))             // bath water
            s.append(w.mesh, mat: .glossy)
            // floor-standing brass tub filler
            var f = BathSoup()
            let xb = cx + 1.46
            f.tube(SIMD3(xb, 0, cz - 0.1), SIMD3(xb, 1.15, cz - 0.1), r0: 0.03, r1: 0.03, color: brass, mat: .metal, segs: 10)
            f.tube(SIMD3(xb, 1.15, cz - 0.1), SIMD3(xb - 0.22, 1.28, cz - 0.1), r0: 0.03, r1: 0.03, color: brass, mat: .metal, segs: 10)
            f.tube(SIMD3(xb - 0.22, 1.28, cz - 0.1), SIMD3(xb - 0.42, 1.12, cz - 0.1), r0: 0.03, r1: 0.025, color: brass, mat: .metal, segs: 10)
            f.sphere(SIMD3(xb, 0.78, cz - 0.1), 0.05, color: brass, mat: .metal)
            f.tube(SIMD3(xb, 0.78, cz - 0.1), SIMD3(xb + 0.1, 0.78, cz - 0.1), r0: 0.015, r1: 0.015, color: brass, mat: .metal, segs: 8)
            let base = UInt32(s.v.count); s.v += f.v; for k in f.i { s.i.append(base + k) }
        }

        // --- tall window with soft daylight (left) ---
        do {
            let cx: Float = -1.12, hw: Float = 0.36, y0: Float = 1.75, y1: Float = 3.55, z = Z0 + 0.02
            let n = SIMD3<Float>(0, 0, 1)
            let top = bathLin(0.97, 0.97, 0.97), bot = bathLin(0.86, 0.87, 0.88)
            let a = s.vert(SIMD3(cx - hw, y0, z), n, bot, mat: .glow), b = s.vert(SIMD3(cx + hw, y0, z), n, bot, mat: .glow)
            let c = s.vert(SIMD3(cx + hw, y1, z), n, top, mat: .glow), d = s.vert(SIMD3(cx - hw, y1, z), n, top, mat: .glow)
            s.quad(a, b, c, d)
            let fr = RoomMeshBuilder()
            let t: Float = 0.028
            for (x, y, hx, hy) in [(cx - hw - t, (y0 + y1) / 2, t, (y1 - y0) / 2 + t), (cx + hw + t, (y0 + y1) / 2, t, (y1 - y0) / 2 + t),
                                   (cx, y0 - t, hw + 2 * t, t), (cx, y1 + t, hw + 2 * t, t), (cx, (y0 + y1) / 2, 0.012, (y1 - y0) / 2), (cx, y0 + (y1 - y0) * 0.66, hw, 0.012)] as [(Float, Float, Float, Float)] {
                fr.roundedBox(centre: SIMD3(x, y, z + 0.025), half: SIMD3(hx, hy, 0.03), radius: 0.008, segments: 1, aoFloor: false, color: matteBlack)
            }
            s.append(fr.mesh, mat: .matte)
        }

        // --- brass rain shower head on a wall arm (spray starts below it) ---
        do {
            var r = BathSoup()
            r.tube(SIMD3(0, 3.0, Z0), SIMD3(0, 3.0, Z0 + 0.62), r0: 0.025, r1: 0.025, color: brass, mat: .metal, segs: 10)
            r.revolve(SIMD3(0, 3.0, Z0 + 0.04), up: SIMD3(0, 0, 1), side: SIMD3(1, 0, 0), profile: [(0, 0), (0.05, 0), (0.05, 0.02), (0, 0.02)], color: brass, mat: .metal, segs: 14)
            r.revolve(SIMD3(0, 2.97, Z0 + 1.0), up: SIMD3(0, -1, 0), side: SIMD3(1, 0, 0), profile: [(0, 0), (0.36, 0), (0.38, 0.015), (0.38, 0.045), (0.3, 0.07), (0, 0.075)], color: brass, mat: .metal, segs: 28)
            r.tube(SIMD3(0, 3.0, Z0 + 0.62), SIMD3(0, 2.98, Z0 + 1.0), r0: 0.025, r1: 0.04, color: brass, mat: .metal, segs: 10)
            let base = UInt32(s.v.count); s.v += r.v; for k in r.i { s.i.append(base + k) }
        }

        // --- wall niche with a warm strip light and a few minimal bottles (centre-right) ---
        do {
            let cx: Float = 0.42, cy: Float = 2.28, hw: Float = 0.30, hh: Float = 0.26, z = Z0 + 0.012
            let inner = RoomMeshBuilder()
            inner.roundedBox(centre: SIMD3(cx, cy, z + 0.01), half: SIMD3(hw + 0.02, hh + 0.02, 0.012), radius: 0.006, segments: 1, aoFloor: false, color: matteBlack)
            s.append(inner.mesh, mat: .matte)
            let n = SIMD3<Float>(0, 0, 1)
            let back = bathLin(0.36, 0.34, 0.32)
            let a = s.vert(SIMD3(cx - hw, cy - hh, z + 0.025), n, back, mat: .matte, ao: 0.8), b = s.vert(SIMD3(cx + hw, cy - hh, z + 0.025), n, back, mat: .matte, ao: 0.8)
            let c = s.vert(SIMD3(cx + hw, cy + hh, z + 0.025), n, bathLin(0.60, 0.57, 0.53), mat: .matte, ao: 1), d = s.vert(SIMD3(cx - hw, cy + hh, z + 0.025), n, bathLin(0.60, 0.57, 0.53), mat: .matte, ao: 1)
            s.quad(a, b, c, d)
            let glow = s.vert(SIMD3(cx - hw, cy + hh - 0.012, z + 0.03), n, bathLin(1.0, 0.95, 0.88), mat: .glow), glow2 = s.vert(SIMD3(cx + hw, cy + hh - 0.012, z + 0.03), n, bathLin(1.0, 0.95, 0.88), mat: .glow)
            let glow3 = s.vert(SIMD3(cx + hw, cy + hh - 0.035, z + 0.03), n, bathLin(1.0, 0.95, 0.88), mat: .glow), glow4 = s.vert(SIMD3(cx - hw, cy + hh - 0.035, z + 0.03), n, bathLin(1.0, 0.95, 0.88), mat: .glow)
            s.quad(glow4, glow3, glow2, glow)
            let shelf = RoomMeshBuilder()
            shelf.roundedBox(centre: SIMD3(cx, cy - hh + 0.012, z + 0.07), half: SIMD3(hw, 0.012, 0.05), radius: 0.006, segments: 1, aoFloor: false, color: bathLin(0.82, 0.81, 0.79))
            s.append(shelf.mesh, mat: .glossy)
            let y = cy - hh + 0.024, zz = z + 0.07
            bottle(&s, base: SIMD3(cx - 0.18, y, zz), r: 0.045, h: 0.22, color: bathLin(0.30, 0.29, 0.28), cap: matteBlack)               // smoked glass
            bottle(&s, base: SIMD3(cx - 0.04, y, zz), r: 0.05, h: 0.16, color: bathLin(0.84, 0.83, 0.81), cap: brass)                       // frosted
            bottle(&s, base: SIMD3(cx + 0.1, y, zz), r: 0.04, h: 0.27, color: bathLin(0.20, 0.19, 0.19), cap: brass)                         // tall dark smoked
            bottle(&s, base: SIMD3(cx + 0.22, y, zz), r: 0.032, h: 0.14, color: bathLin(0.48, 0.47, 0.45), cap: matteBlack)                  // mid smoked
        }

        // --- floating walnut vanity, vessel sink and a big round backlit mirror (right) ---
        do {
            let cx: Float = 1.3, z: Float = Z0 + 0.3
            let v = RoomMeshBuilder()
            v.roundedBox(centre: SIMD3(cx, 0.72, z), half: SIMD3(0.62, 0.15, 0.27), radius: 0.025, segments: 2, aoFloor: false, color: walnut)
            s.append(v.mesh, mat: .oak)
            let top = RoomMeshBuilder()
            top.roundedBox(centre: SIMD3(cx, 0.9, z), half: SIMD3(0.66, 0.025, 0.29), radius: 0.012, segments: 2, aoFloor: false, color: bathLin(0.88, 0.87, 0.85))
            s.append(top.mesh, mat: .glossy)
            // drawer line + brass pull
            var d = BathSoup()
            d.tube(SIMD3(cx - 0.14, 0.72, z + 0.28), SIMD3(cx + 0.14, 0.72, z + 0.28), r0: 0.011, r1: 0.011, color: brass, mat: .metal, segs: 8)
            // vessel bowl
            d.revolve(SIMD3(cx, 0.92, z + 0.02), up: SIMD3(0, 1, 0), side: SIMD3(1, 0, 0),
                      profile: [(0, 0), (0.1, 0), (0.17, 0.05), (0.21, 0.12), (0.22, 0.15), (0.2, 0.152), (0.19, 0.14), (0.16, 0.07), (0.0, 0.03)], color: tubWhite, mat: .glossy, segs: 28)
            // brass faucet
            d.tube(SIMD3(cx, 0.93, z - 0.2), SIMD3(cx, 1.28, z - 0.2), r0: 0.022, r1: 0.022, color: brass, mat: .metal, segs: 10)
            d.tube(SIMD3(cx, 1.28, z - 0.2), SIMD3(cx, 1.28, z - 0.02), r0: 0.02, r1: 0.017, color: brass, mat: .metal, segs: 10)
            // mirror: backlit halo, brass ring, silvered glass
            let my: Float = 2.0, mr: Float = 0.52, mz = Z0 + 0.03
            d.revolve(SIMD3(cx, my, Z0 + 0.01), up: SIMD3(0, 0, 1), side: SIMD3(1, 0, 0), profile: [(mr + 0.1, 0.0), (0, 0.0)], color: bathLin(1.0, 0.95, 0.88), mat: .glow, segs: 40)
            d.revolve(SIMD3(cx, my, mz), up: SIMD3(0, 0, 1), side: SIMD3(1, 0, 0), profile: [(mr, 0.012), (0, 0.012)], color: bathLin(0.84, 0.85, 0.86), mat: .metal, segs: 40)
            d.revolve(SIMD3(cx, my, mz), up: SIMD3(0, 0, 1), side: SIMD3(1, 0, 0), profile: [(mr + 0.02, 0), (mr + 0.02, 0.02), (mr, 0.024), (mr - 0.004, 0.012)], color: brass, mat: .metal, segs: 40)
            let base = UInt32(s.v.count); s.v += d.v; for k in d.i { s.i.append(base + k) }
        }

        // --- heated brass towel rail with a folded plush towel (left, under the window) ---
        do {
            let z = Z0 + 0.1
            var r = BathSoup()
            r.tube(SIMD3(-1.55, 1.38, z), SIMD3(-0.62, 1.38, z), r0: 0.016, r1: 0.016, color: brass, mat: .metal, segs: 8)
            r.tube(SIMD3(-1.55, 1.52, z), SIMD3(-0.62, 1.52, z), r0: 0.016, r1: 0.016, color: brass, mat: .metal, segs: 8)
            for x: Float in [-1.55, -0.62] { r.tube(SIMD3(x, 1.38, Z0), SIMD3(x, 1.38, z), r0: 0.02, r1: 0.02, color: brass, mat: .metal, segs: 8)
                                            r.tube(SIMD3(x, 1.52, Z0), SIMD3(x, 1.52, z), r0: 0.02, r1: 0.02, color: brass, mat: .metal, segs: 8) }
            let base = UInt32(s.v.count); s.v += r.v; for k in r.i { s.i.append(base + k) }
            let tw = RoomMeshBuilder()
            tw.roundedBox(centre: SIMD3(-1.08, 1.64, z + 0.045), half: SIMD3(0.36, 0.2, 0.05), radius: 0.04, segments: 3, aoFloor: false, color: greige)
            tw.roundedBox(centre: SIMD3(-1.08, 1.5, z + 0.05), half: SIMD3(0.365, 0.02, 0.055), radius: 0.015, segments: 2, aoFloor: false, color: bathLin(0.76, 0.74, 0.70))
            s.append(tw.mesh, mat: .fabric)
        }

        // --- olive tree in a stone planter (left, behind the basin) ---
        do {
            let cx: Float = -1.42, cz: Float = -0.15
            var p = BathSoup()
            p.revolve(SIMD3(cx, 0, cz), up: SIMD3(0, 1, 0), side: SIMD3(1, 0, 0), profile: [(0, 0), (0.2, 0), (0.24, 0.1), (0.23, 0.46), (0.25, 0.5), (0.2, 0.5), (0.0, 0.46)], color: bathLin(0.62, 0.60, 0.57), mat: .porcelain, segs: 24)
            let trunk = bathLin(0.32, 0.30, 0.28), leaf1 = bathLin(0.50, 0.53, 0.48), leaf2 = bathLin(0.60, 0.63, 0.58)
            p.tube(SIMD3(cx, 0.46, cz), SIMD3(cx + 0.05, 1.05, cz), r0: 0.035, r1: 0.022, color: trunk, mat: .matte, segs: 7)
            p.tube(SIMD3(cx + 0.04, 0.85, cz), SIMD3(cx - 0.18, 1.25, cz + 0.05), r0: 0.016, r1: 0.01, color: trunk, mat: .matte, segs: 6)
            p.tube(SIMD3(cx + 0.05, 0.95, cz), SIMD3(cx + 0.24, 1.3, cz - 0.04), r0: 0.016, r1: 0.01, color: trunk, mat: .matte, segs: 6)
            let blobs: [(Float, Float, Float, Float)] = [(0.05, 1.45, 0, 0.2), (-0.2, 1.3, 0.05, 0.16), (0.26, 1.35, -0.04, 0.17), (0.0, 1.2, 0.12, 0.15), (-0.08, 1.65, -0.05, 0.14), (0.16, 1.58, 0.08, 0.13)]
            for (k, b) in blobs.enumerated() {
                p.ellipsoid(SIMD3(cx + b.0, b.1, cz + b.2), ax: SIMD3(b.3 * 1.25, 0, 0), ay: SIMD3(0, b.3 * 0.7, 0), az: SIMD3(0, 0, b.3), color: k % 2 == 0 ? leaf1 : leaf2, mat: .matte, rings: 4, segs: 8)
            }
            let base = UInt32(s.v.count); s.v += p.v; for k in p.i { s.i.append(base + k) }
        }

        // --- Bob's wash basin: low, wide polished white stone bowl with a brushed-brass rim ---
        do {
            let b = RoomMeshBuilder()
            let pro = DiningModels.profile([
                (0.0, 0.0, 0.5), (0.86, 0.0, 0.6), (1.0, 0.0, 0.7), (1.08, 0.08, 0.9), (1.115, 0.2, 1.0), (1.1, 0.32, 1.0), (1.05, 0.355, 1.0),
                (0.96, 0.355, 1.0), (0.93, 0.34, 1.0), (0.915, 0.25, 0.95), (0.895, 0.14, 0.9), (0.85, 0.06, 0.82), (0.7, 0.028, 0.8), (0.0, 0.02, 0.8)])
            b.lathe(cx: basinCentre.x, cz: basinCentre.y, profile: pro, segments: 64, color: bathLin(0.93, 0.92, 0.90))
            s.append(b.mesh, mat: .glossy)
            var ring = BathSoup()
            ring.revolve(SIMD3(basinCentre.x, 0, basinCentre.y), up: SIMD3(0, 1, 0), side: SIMD3(1, 0, 0),
                         profile: [(0.925, 0.336), (0.935, 0.372), (0.985, 0.384), (1.05, 0.376), (1.075, 0.35), (1.06, 0.33)], color: brass, mat: .metal, segs: 64)
            let base = UInt32(s.v.count); s.v += ring.v; for k in ring.i { s.i.append(base + k) }
        }

        // neutral linen bath mat in front of the basin
        do {
            let m = RoomMeshBuilder()
            m.roundedBox(centre: SIMD3(0, 0.014, 3.0), half: SIMD3(1.1, 0.014, 0.5), radius: 0.012, segments: 2, aoFloor: false, color: bathLin(0.60, 0.58, 0.54))
            m.roundedBox(centre: SIMD3(0, 0.03, 3.0), half: SIMD3(1.06, 0.006, 0.46), radius: 0.005, segments: 1, aoFloor: false, color: bathLin(0.68, 0.66, 0.62))
            s.append(m.mesh, mat: .fabric)
        }
        return RoomMesh(vertices: s.v, indices: s.i)
    }

    /// The translucent water disc (normal up). `ao` carries the basin inner radius for the shader's pale edge.
    static func buildWater() -> RoomMesh {
        var s = BathSoup()
        let rings = 5, segs = 48
        var grid: [[UInt32]] = []
        for k in 0...rings {
            let r = waterR * Float(k) / Float(rings)
            var row: [UInt32] = []
            for j in 0...segs {
                let a = Float(j) / Float(segs) * 2 * .pi
                row.append(s.vert(SIMD3(basinCentre.x + r * cosf(a), waterY, basinCentre.y + r * sinf(a)), SIMD3(0, 1, 0), bathLin(0.6, 0.82, 0.95), mat: .water, ao: waterR, alpha: 0.6))
            }
            grid.append(row)
        }
        for k in 0..<rings { for j in 0..<segs { s.quad(grid[k][j], grid[k][j + 1], grid[k + 1][j + 1], grid[k + 1][j]) } }
        return RoomMesh(vertices: s.v, indices: s.i)
    }
}
