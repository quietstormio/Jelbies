//
//  GardenScenery.swift
//  The Garden's static meshes (built once per room switch, drawn in the room's cached pass), designed like the living room: a calm back wall (a rounded
//  hedge with a cream picket fence in front), a pastel sky, ONE even lawn with a very soft tonal drift, a round stone patio as the focal "rug", a few
//  chunky hero pieces (the veg-patch trough, the potting shed, the bird bath, the rose arch, one blossom tree, three sturdy sunflowers) and soft round
//  flower MOUNDS (puffy green with a few blossoms in one blush / butter / lilac / white palette) in bordered beds along the side fences and corners.
//  The middle and the front of the lawn stay clean for the Jelbies. Warm string lights (the lamp material, so they glow at night).
//  The plants of the four plots and everything that moves are in GardenPlants.swift. Colours are linear (OKLab.srgbToLinear of friendly sRGB values).
//

import simd
import Foundation

enum GardenScenery {
    typealias S = GardenShapes
    typealias V3 = SIMD3<Float>
    typealias PP = RoomMeshBuilder.ProfilePoint
    private static func c(_ r: Float, _ g: Float, _ b: Float) -> V3 { S.srgb(r, g, b) }

    // the garden palette: cream fence, warm wood, sage + lawn greens, stone, and four blossom colours
    static let white = c(0.97, 0.95, 0.89), sky = c(0.70, 0.83, 0.94), wood = c(0.78, 0.60, 0.42), terracotta = c(0.86, 0.58, 0.48)
    static let soil = c(0.40, 0.29, 0.21), stone = c(0.86, 0.82, 0.75), leafDeep = c(0.34, 0.60, 0.32), leafLight = c(0.48, 0.74, 0.38)
    static let blush = c(0.97, 0.72, 0.78), butter = c(0.99, 0.88, 0.52), lilac = c(0.78, 0.68, 0.93), cream = c(0.99, 0.97, 0.93)
    static let lawn = c(0.60, 0.79, 0.48)

    /// Blossom colours (the plots' daisies and everything else use this one palette).
    static let blossoms: [V3] = [blush, butter, lilac, cream]
    static let tulipColours: [V3] = blossoms
    static let daisyColours: [V3] = [cream, c(0.99, 0.95, 0.80), blush]

    static func build(theme: RoomTheme) -> RoomMesh {
        let b = RoomMeshBuilder()
        var r = ParkRandom(0x6A2D)
        skyAndGround(b)
        beyond(b, &r)
        fences(b)
        gateAndArch(b, &r)
        trough(b)
        shed(b)
        deck(b)
        birdBath(b, &r)
        patio(b)
        flowerBeds(b, &r)
        sunflowers(b, &r)
        frontCorners(b, &r)
        baskets(b)
        stringLights(b)
        return b.mesh
    }

    // MARK: sky, lawn

    private static func skyAndGround(_ b: RoomMeshBuilder) {
        // the pane is emissive and the shader brightens it with height (x1.25 up to x1.9), so each band's colour is pre-divided by that to land on the
        // soft pastel target: warm peach at the horizon, through pale gold-pink, to a clear pastel blue overhead (night/clock tint is the shader's)
        b.material = .glow
        let stops: [(Float, V3)] = [(0, c(0.99, 0.87, 0.78)), (3, c(0.90, 0.86, 0.86)), (8, c(0.68, 0.82, 0.95)), (20, c(0.52, 0.74, 0.96)), (70, c(0.46, 0.68, 0.94))]
        func target(_ y: Float) -> V3 {
            for i in 1..<stops.count where y <= stops[i].0 {
                let t = (y - stops[i - 1].0) / (stops[i].0 - stops[i - 1].0)
                return simd_mix(stops[i - 1].1, stops[i].1, SIMD3(repeating: t))
            }
            return stops[stops.count - 1].1
        }
        func albedo(_ y: Float) -> V3 {
            let t = min(max(y / 14, 0), 1), sm = t * t * (3 - 2 * t)
            return target(y) / (1.25 * (1 + 0.5 * sm))
        }
        let ys: [Float] = [0, 2, 4, 6, 9, 12, 16, 22, 30, 45, 70]
        for i in 0..<(ys.count - 1) {
            let lo = albedo(ys[i]), hi = albedo(ys[i + 1])
            b.flatQuad(V3(-120, ys[i], -14), V3(120, ys[i], -14), V3(120, ys[i + 1], -14), V3(-120, ys[i + 1], -14), normal: V3(0, 0, 1), colors: [lo, lo, hi, hi])
        }
        b.material = .plain
        let far = c(0.46, 0.70, 0.38)
        b.flatQuad(V3(-80, 0, -13.5), V3(80, 0, -13.5), V3(80, 0, 50), V3(-80, 0, 50), normal: V3(0, 1, 0), colors: [far, far, lawn, lawn])
        // the yard: one lawn colour with a very soft, slow tonal drift (smooth vertex noise, no stripes)
        let nx = 20, nz = 14
        let x0: Float = -5.2, z0: Float = -5.2, dx: Float = 10.4 / Float(nx), dz: Float = 20.4 / Float(nz)
        func tone(_ x: Float, _ z: Float) -> V3 {
            let n = sinf(x * 0.9 + 1.3) * sinf(z * 0.7) * 0.5 + sinf(x * 0.31 + z * 0.53 + 2) * 0.5
            return lawn * (1 + 0.035 * n)
        }
        for i in 0..<nx {
            for j in 0..<nz {
                let xa = x0 + Float(i) * dx, xb = xa + dx, za = z0 + Float(j) * dz, zb = za + dz
                b.flatQuad(V3(xa, 0.004, za), V3(xb, 0.004, za), V3(xb, 0.004, zb), V3(xa, 0.004, zb), normal: V3(0, 1, 0), colors: [tone(xa, za), tone(xb, za), tone(xb, zb), tone(xa, zb)])
            }
        }
    }

    /// A calm backdrop beyond the fence: soft hills, ONE blossom tree, a few clouds.
    private static func beyond(_ b: RoomMeshBuilder, _ r: inout ParkRandom) {
        for (x, rx, ry) in [(-18 as Float, 14 as Float, 3.0 as Float), (2, 18, 2.4), (20, 14, 3.4)] {
            S.blob(b, V3(x, -0.4, -12.6), rx: rx, ry: ry, rz: 2.6, color: c(0.50, 0.74, 0.46), segments: 20, rings: 8)
        }
        // the rounded hedge wall behind the back fence, one even green
        var x: Float = -8.0
        var k = 0
        while x < 8.2 {
            let g: Float = k % 2 == 0 ? 0 : 0.035
            S.blob(b, V3(x, 0.55, -6.0), rx: 0.95, ry: 0.95, rz: 0.7, color: c(0.36 + g, 0.64 + g, 0.34 + g), segments: 14, rings: 8)
            x += 1.2; k += 1
        }
        ParkScenery.tree(b, x: -4.3, z: -10, height: 6.0, scale: 1.0, hue: c(0.98, 0.76, 0.84) * 0.9, rng: &r)
        for (cx, cy, s) in [(-9 as Float, 12 as Float, 1.0 as Float), (7, 10.5, 1.3), (13, 13, 1.1)] {
            for k in 0..<3 {
                S.blob(b, V3(cx + Float(k - 1) * 1.7 * s, cy + (k == 1 ? 0.5 : 0), -12.8), rx: 1.9 * s, ry: 0.75 * s, rz: 0.5, color: c(1.0, 0.96, 0.94), segments: 10, rings: 5)
            }
        }
    }

    // MARK: fences

    private static func fences(_ b: RoomMeshBuilder) {
        let gateGap = (GardenLayout.gateX - 0.62)...(GardenLayout.gateX + 0.62)
        let step: Float = 0.2
        // back (white), z = -5
        var x: Float = -5.15
        while x <= 5.15 {
            if !gateGap.contains(x) { S.box(b, V3(x, 0.47, GardenLayout.fenceZ), V3(0.05, 0.47, 0.014), r: 0.03, color: white) }
            x += step
        }
        S.box(b, V3(0, 0.30, GardenLayout.fenceZ - 0.03), V3(5.2, 0.035, 0.02), r: 0.015, color: white * 0.96)
        S.box(b, V3(0, 0.70, GardenLayout.fenceZ - 0.03), V3(5.2, 0.035, 0.02), r: 0.015, color: white * 0.96)
        // sides (soft blue), x = -5 and 5, from the back to well past the front
        for sx: Float in [-5.0, 5.0] {
            var z: Float = -5.0
            while z <= 9 {
                S.box(b, V3(sx, 0.47, z), V3(0.014, 0.47, 0.05), r: 0.03, color: white)
                z += step
            }
            S.box(b, V3(sx + (sx < 0 ? -0.03 : 0.03), 0.30, 2), V3(0.02, 0.035, 7.1), r: 0.015, color: white * 0.96)
            S.box(b, V3(sx + (sx < 0 ? -0.03 : 0.03), 0.70, 2), V3(0.02, 0.035, 7.1), r: 0.015, color: white * 0.96)
        }
        // posts with ball caps
        for px: Float in [-5.0, -4.2, -1.8, -0.6, 0.6, 1.8, 5.0] {
            S.box(b, V3(px, 0.58, GardenLayout.fenceZ), V3(0.06, 0.58, 0.06), r: 0.02, color: white)
            S.ball(b, V3(px, 1.2, GardenLayout.fenceZ), 0.075, white, segments: 8, rings: 4)
        }
        for sx: Float in [-5.0, 5.0] {
            for pz: Float in [-2.5, 0.5, 3.5, 6.5] {
                S.box(b, V3(sx, 0.7, pz), V3(0.06, 0.7, 0.06), r: 0.02, color: white)
                S.ball(b, V3(sx, 1.46, pz), 0.075, white, segments: 8, rings: 4)
            }
        }
    }

    private static func gateAndArch(_ b: RoomMeshBuilder, _ r: inout ParkRandom) {
        let gx = GardenLayout.gateX, z = GardenLayout.fenceZ - 0.01, w: Float = 0.62
        // two tall posts and a half-round top
        for sx: Float in [-w, w] { S.box(b, V3(gx + sx, 1.15, z), V3(0.07, 1.15, 0.07), r: 0.025, color: white) }
        let n = 11
        for k in 0...n {
            let a = Float(k) / Float(n) * .pi
            S.box(b, V3(gx - cosf(a) * w, 2.28 + sinf(a) * 0.5, z), V3(0.055, 0.055, 0.055), r: 0.025, color: white)
        }
        // the gate: a low leaf of pickets with two rails and a latch
        var px = gx - w + 0.1
        while px < gx + w - 0.05 {
            let up = 0.84 + 0.1 * (1 - abs(px - gx) / w)
            S.box(b, V3(px, up / 2, z + 0.02), V3(0.05, up / 2, 0.014), r: 0.03, color: c(0.99, 0.97, 0.90))
            px += 0.2
        }
        S.box(b, V3(gx, 0.28, z + 0.0), V3(w - 0.05, 0.035, 0.018), r: 0.015, color: white * 0.96)
        S.box(b, V3(gx, 0.66, z + 0.0), V3(w - 0.05, 0.035, 0.018), r: 0.015, color: white * 0.96)
        S.ball(b, V3(gx + 0.45, 0.62, z + 0.05), 0.03, c(0.30, 0.28, 0.28), segments: 6, rings: 3)
        // climbing roses: leafy balls and pink blooms up both posts and over the top
        let pink: [V3] = [blush, blush * 0.95, cream, butter]
        for k in 0..<34 {
            let t = Float(k) / 33
            var p: V3
            if t < 0.3 { p = V3(gx - w, 0.5 + t / 0.3 * 1.8, z + 0.07) }
            else if t < 0.7 { let a = (t - 0.3) / 0.4 * Float.pi; p = V3(gx - cosf(a) * w, 2.28 + sinf(a) * 0.5, z + 0.07) }
            else { p = V3(gx + w, 0.5 + (1 - (t - 0.7) / 0.3) * 1.8, z + 0.07) }
            p.x += (r.unit() - 0.5) * 0.14; p.y += (r.unit() - 0.5) * 0.1
            S.ball(b, p, 0.12 + 0.03 * r.unit(), simd_mix(leafDeep, leafLight, SIMD3(repeating: r.unit())), segments: 10, rings: 5)
            if k % 2 == 0 { S.ball(b, p + V3(0, 0.02, 0.07), 0.055, pink[k / 2 % pink.count], segments: 6, rings: 3) }
        }
    }

    // MARK: the veg-patch trough

    private static func trough(_ b: RoomMeshBuilder) {
        let t = GardenLayout.troughCentre, h = GardenLayout.troughHalf
        S.box(b, t, h, r: 0.05, color: wood)
        // a lighter rim board and the dividers between plots
        S.box(b, V3(t.x, 0.305, t.z + h.z - 0.03), V3(h.x + 0.02, 0.018, 0.045), r: 0.012, color: wood * 1.12)
        S.box(b, V3(t.x, 0.305, t.z - h.z + 0.03), V3(h.x + 0.02, 0.018, 0.045), r: 0.012, color: wood * 1.12)
        for dx: Float in [-0.935, 0, 0.935] { S.box(b, V3(dx, 0.31, t.z), V3(0.025, 0.03, h.z - 0.04), r: 0.01, color: wood * 1.12) }
        for i in 0..<GardenLayout.plotXs.count {
            let p = GardenLayout.plotCentre(i)
            S.blob(b, V3(p.x, GardenLayout.soilY - 0.03, p.z), rx: 0.40, ry: 0.07, rz: 0.40, color: soil, segments: 12, rings: 4)
        }
    }

    // MARK: mounds

    /// A soft round flower mound: puffy green lobes dotted with round blossoms in two or three of the palette colours.
    static func mound(_ b: RoomMeshBuilder, x: Float, z: Float, radius s: Float, y0: Float = 0, cols: [V3], _ r: inout ParkRandom) {
        let green = leafDeep * (0.95 + 0.1 * r.unit())
        S.blob(b, V3(x, y0 + 0.62 * s * 0.55, z), rx: s, ry: 0.62 * s, rz: s * 0.92, color: green, segments: 16, rings: 8, ao: 0.9)
        S.blob(b, V3(x - 0.42 * s, y0 + 0.30 * s, z + 0.18 * s), rx: 0.62 * s, ry: 0.42 * s, rz: 0.58 * s, color: green * 1.07, segments: 14, rings: 7, ao: 0.9)
        S.blob(b, V3(x + 0.45 * s, y0 + 0.28 * s, z + 0.1 * s), rx: 0.58 * s, ry: 0.40 * s, rz: 0.55 * s, color: green * 1.04, segments: 14, rings: 7, ao: 0.9)
        let n = Int(14 * s / 0.4) + 6
        for k in 0..<n {
            let a = r.unit() * 2 * .pi, e = 0.15 + r.unit() * 0.85
            let rad = 0.95 * s
            let p = V3(x + cosf(a) * rad * cosf(e), y0 + 0.62 * s * 0.55 + sinf(e) * 0.62 * s * 0.92, z + sinf(a) * rad * 0.92 * cosf(e))
            // keep the blossoms on the camera-facing half and the top
            let q = V3(p.x, p.y, p.z < z ? z + (z - p.z) * 0.6 : p.z)
            S.ball(b, q, 0.065 + 0.012 * r.unit(), cols[k % cols.count], segments: 8, rings: 4)
        }
    }

    /// A bevelled stone / wood border round a rectangle.
    private static func border(_ b: RoomMeshBuilder, x0: Float, x1: Float, z0: Float, z1: Float) {
        let t: Float = 0.07, h: Float = 0.07, col = stone * 0.96
        S.box(b, V3((x0 + x1) / 2, 0.012, (z0 + z1) / 2), V3((x1 - x0) / 2, 0.012, (z1 - z0) / 2), r: 0.01, color: soil)
        S.box(b, V3((x0 + x1) / 2, h, z0), V3((x1 - x0) / 2 + t, h, t), r: 0.05, color: col)
        S.box(b, V3((x0 + x1) / 2, h, z1), V3((x1 - x0) / 2 + t, h, t), r: 0.05, color: col)
        S.box(b, V3(x0, h, (z0 + z1) / 2), V3(t, h, (z1 - z0) / 2), r: 0.05, color: col)
        S.box(b, V3(x1, h, (z0 + z1) / 2), V3(t, h, (z1 - z0) / 2), r: 0.05, color: col)
    }

    private static func palette(_ i: Int) -> [V3] { [[blush, cream, butter], [lilac, cream, blush], [butter, blush, lilac], [cream, lilac, butter]][i % 4] }

    private static func flowerBeds(_ b: RoomMeshBuilder, _ r: inout ParkRandom) {
        // the two round beds (their colliders stay): a stone ring, one big mound in each
        for (i, p) in [GardenLayout.bedA, GardenLayout.bedB].enumerated() {
            let rad = GardenLayout.bedRadius
            S.disc(b, cx: p.x, cz: p.y, radius: rad, y: 0.012, color: soil, segments: 28)
            let ring: [PP] = [PP(r: rad - 0.1, y: 0.02, nr: 0, ny: 1), PP(r: rad - 0.04, y: 0.12, nr: 0.3, ny: 1), PP(r: rad + 0.04, y: 0.12, nr: 0.7, ny: 0.7), PP(r: rad + 0.08, y: 0.06, nr: 1, ny: 0.1), PP(r: rad + 0.08, y: 0, nr: 1, ny: 0)]
            b.lathe(cx: p.x, cz: p.y, profile: ring, segments: 28, color: stone * 0.96)
            mound(b, x: p.x, z: p.y, radius: 0.5, y0: 0.03, cols: palette(i), &r)
        }
        // the side-fence beds: a clean bordered strip with a mound every ~1.6
        let sides: [(Float, [Float])] = [(-1, [-0.2, 1.5, 3.2, 4.9, 6.6]), (1, [0.4, 2.1, 3.8, 5.5, 7.2])]
        for (sx, zs) in sides {
            let lo: Float = zs[0] - 0.9, hi: Float = zs[zs.count - 1] + 0.9
            let xa: Float = sx < 0 ? -4.85 : 4.05, xb: Float = sx < 0 ? -4.05 : 4.85
            border(b, x0: xa, x1: xb, z0: lo, z1: hi)
            for (k, z) in zs.enumerated() {
                let jitter: Float = (k % 2 == 0 ? -0.04 : 0.04) * sx
                let rad: Float = 0.36 + 0.04 * Float(k % 2)
                mound(b, x: (xa + xb) / 2 + jitter, z: z, radius: rad, y0: 0.03, cols: palette(k + (sx < 0 ? 0 : 2)), &r)
            }
        }
        // back-left corner, beside the gate
        border(b, x0: -4.85, x1: -3.95, z0: -4.85, z1: -4.05)
        mound(b, x: -4.4, z: -4.45, radius: 0.36, y0: 0.03, cols: palette(1), &r)
    }

    private static func frontCorners(_ b: RoomMeshBuilder, _ r: inout ParkRandom) {
        // two small round bushes that frame the view from the front corners, partly off-screen
        for (i, x) in ([-4.5, 4.5] as [Float]).enumerated() {
            mound(b, x: x, z: 9.4, radius: 0.6, cols: palette(i + 1), &r)
        }
    }

    // MARK: sunflowers

    /// Three sturdy sunflowers along the back fence: a thick stem, two big leaves, a big round head.
    private static func sunflowers(_ b: RoomMeshBuilder, _ r: inout ParkRandom) {
        for (i, x) in ([-4.55, -1.2, 2.05] as [Float]).enumerated() {
            let h: Float = 1.55 + 0.15 * Float(i % 2), z = GardenLayout.fenceZ + 0.28
            S.stem(b, x: x, z: z, y0: 0, y1: h, r: 0.055, color: c(0.40, 0.62, 0.30), segments: 8)
            for (k, a) in ([0.5, 2.9] as [Float]).enumerated() {
                b.leaf(base: V3(x, h * (0.3 + 0.18 * Float(k)), z), azimuth: a + Float(i), length: 0.5, width: 0.3, lean: 1.0, colorBase: S.leafA, colorTip: S.leafB)
            }
            let hc = V3(x, h + 0.08, z + 0.1)
            S.fan(b, hc, n: 16, r0: 0.08, r1: 0.30, width: 0.065, color: butter * 1.02, tip: c(1.0, 0.78, 0.30), phase: Float(i))
            S.face(b, hc + S.headN * 0.012, radius: 0.13, color: c(0.46, 0.31, 0.20))
        }
    }

    // MARK: patio, path

    /// A round stone patio in the middle (the focal point, like the living-room rug) and five stepping stones from the gate.
    private static func patio(_ b: RoomMeshBuilder) {
        let cx: Float = 0, cz: Float = 1.7
        let prof: [PP] = [PP(r: 0, y: 0.03, nr: 0, ny: 1), PP(r: 1.78, y: 0.03, nr: 0, ny: 1), PP(r: 1.9, y: 0.02, nr: 0.7, ny: 0.7), PP(r: 1.94, y: 0.008, nr: 1, ny: 0.1), PP(r: 1.94, y: 0, nr: 1, ny: 0)]
        b.lathe(cx: cx, cz: cz, profile: prof, segments: 40, color: stone)
        S.disc(b, cx: cx, cz: cz, radius: 1.45, y: 0.032, color: stone * 1.025, segments: 36)
        S.disc(b, cx: cx, cz: cz, radius: 0.95, y: 0.034, color: stone * 0.98, segments: 32)
        let stones: [(Float, Float)] = [(-2.8, -3.55), (-2.65, -2.65), (-2.4, -1.75), (-2.05, -0.9), (-1.6, -0.15)]
        for (i, p) in stones.enumerated() {
            S.cylinder(b, x: p.0, z: p.1, r: 0.3, y0: 0.004, y1: 0.03, color: stone * (i % 2 == 0 ? 1.0 : 0.96), segments: 20)
        }
    }

    // MARK: shed

    private static func shed(_ b: RoomMeshBuilder) {
        let s = GardenLayout.shed
        let cx = (s.min.x + s.max.x) / 2, cz = (s.min.y + s.max.y) / 2, hx = (s.max.x - s.min.x) / 2, hz = (s.max.y - s.min.y) / 2
        let wall = c(0.80, 0.88, 0.80)
        S.box(b, V3(cx, s.height / 2, cz), V3(hx, s.height / 2, hz), r: 0.07, color: wall)
        let roof = c(0.88, 0.60, 0.54)
        let x0 = s.min.x - 0.14, x1 = s.max.x + 0.14, zf = s.max.y + 0.16, zb = s.min.y - 0.1, zr = cz, ye = s.height - 0.02, yr = s.height + 0.5
        let nf = simd_normalize(V3(0, zf - zr, yr - ye)), nb = simd_normalize(V3(0, zr - zb, -(yr - ye)))
        b.flatQuad(V3(x0, ye, zf), V3(x1, ye, zf), V3(x1, yr, zr), V3(x0, yr, zr), normal: nf, colors: [roof, roof, roof * 1.1, roof * 1.1])
        b.flatQuad(V3(x0, ye, zb), V3(x1, ye, zb), V3(x1, yr, zr), V3(x0, yr, zr), normal: nb, colors: [roof * 0.9, roof * 0.9, roof, roof])
        for ex in [x0, x1] {
            let nx: V3 = V3(ex < cx ? -1 : 1, 0, 0)
            let a = b.vertex(V3(ex, ye, zf), nx, color: wall), bb = b.vertex(V3(ex, ye, zb), nx, color: wall), tt = b.vertex(V3(ex, yr, zr), nx, color: wall)
            b.triangle(a, bb, tt)
        }
        S.box(b, V3(cx, yr + 0.02, zr), V3(hx + 0.15, 0.03, 0.05), r: 0.015, color: roof * 0.85)
        // a warm wood door with a round knob, a window with a flower box
        S.box(b, V3(s.min.x + 0.62, 0.8, s.max.y + 0.02), V3(0.34, 0.8, 0.02), r: 0.03, color: wood)
        S.ball(b, V3(s.min.x + 0.82, 0.8, s.max.y + 0.06), 0.035, c(0.97, 0.88, 0.55), segments: 8, rings: 4)
        S.box(b, V3(s.min.x + 0.62, 0.03, s.max.y + 0.22), V3(0.4, 0.03, 0.2), r: 0.025, color: stone)
        let wx = s.max.x - 0.6
        S.box(b, V3(wx, 1.3, s.max.y + 0.015), V3(0.34, 0.3, 0.018), r: 0.02, color: white)
        S.box(b, V3(wx, 1.3, s.max.y + 0.026), V3(0.29, 0.25, 0.012), r: 0.01, color: c(0.80, 0.92, 1.0))
        S.box(b, V3(wx, 1.3, s.max.y + 0.034), V3(0.012, 0.25, 0.01), r: 0.004, color: white)
        S.box(b, V3(wx, 0.95, s.max.y + 0.09), V3(0.4, 0.07, 0.08), r: 0.03, color: wood)
        for k in 0..<4 { S.ball(b, V3(wx - 0.27 + Float(k) * 0.18, 1.04, s.max.y + 0.09), 0.08, [blush, cream, lilac, butter][k], segments: 8, rings: 4) }
    }

    // MARK: deck

    /// One soft wooden platform with a sun cushion for napping.
    private static func deck(_ b: RoomMeshBuilder) {
        let d = GardenLayout.deck
        let cx = (d.min.x + d.max.x) / 2, cz = (d.min.y + d.max.y) / 2, hx = (d.max.x - d.min.x) / 2, hz = (d.max.y - d.min.y) / 2
        S.box(b, V3(cx, 0.03, cz), V3(hx, 0.03, hz), r: 0.03, color: c(0.87, 0.73, 0.57))
        S.box(b, V3(d.min.x + 1.0, 0.1, d.min.y + 1.2), V3(0.55, 0.04, 0.38), r: 0.035, color: blush)
        S.box(b, V3(d.min.x + 1.0, 0.135, d.min.y + 1.2), V3(0.5, 0.014, 0.33), r: 0.012, color: cream)
    }

    // MARK: bird bath

    private static func birdBath(_ b: RoomMeshBuilder, _ r: inout ParkRandom) {
        let p = GardenLayout.birdBath
        let prof: [PP] = [PP(r: 0, y: 0, nr: 0, ny: -1), PP(r: 0.30, y: 0, nr: 0, ny: -1), PP(r: 0.30, y: 0.07, nr: 1, ny: 0.2, ao: 0.7), PP(r: 0.14, y: 0.14, nr: 0.5, ny: 1),
                          PP(r: 0.10, y: 0.2, nr: 1, ny: 0), PP(r: 0.09, y: 0.62, nr: 1, ny: 0), PP(r: 0.16, y: 0.70, nr: 0.7, ny: -0.6), PP(r: 0.40, y: 0.78, nr: 0.7, ny: -0.5),
                          PP(r: 0.50, y: 0.90, nr: 1, ny: 0.2), PP(r: 0.46, y: 0.96, nr: 0, ny: 1), PP(r: 0.42, y: 0.90, nr: -0.8, ny: 0.5)]
        b.lathe(cx: p.x, cz: p.y, profile: prof, segments: 28, color: stone)
        S.disc(b, cx: p.x, cz: p.y, radius: 0.40, y: 0.905, color: c(0.62, 0.82, 0.96), segments: 24)
        S.blob(b, V3(p.x + 0.40, 1.03, p.y + 0.12), rx: 0.075, ry: 0.065, rz: 0.06, color: c(0.62, 0.74, 0.94), segments: 10, rings: 5)
        S.ball(b, V3(p.x + 0.34, 1.10, p.y + 0.14), 0.045, c(0.62, 0.74, 0.94), segments: 8, rings: 4)
        S.ball(b, V3(p.x + 0.29, 1.10, p.y + 0.15), 0.014, c(0.98, 0.76, 0.40), segments: 6, rings: 3)
        S.blob(b, V3(p.x - 0.12, 0.915, p.y + 0.1), rx: 0.07, ry: 0.01, rz: 0.04, color: leafLight, segments: 8, rings: 2)
        mound(b, x: p.x - 0.65, z: p.y + 0.55, radius: 0.2, cols: [butter, cream], &r)
        mound(b, x: p.x + 0.55, z: p.y + 0.7, radius: 0.18, cols: [blush, cream], &r)
    }

    // MARK: hanging baskets, lights

    /// Two round baskets at the gate (the only hanging ones).
    private static func baskets(_ b: RoomMeshBuilder) {
        let gx = GardenLayout.gateX
        var r = ParkRandom(0x51A3)
        for (i, sx) in ([-0.9, 0.9] as [Float]).enumerated() {
            let x = gx + sx, y: Float = 1.45, z = GardenLayout.fenceZ + 0.2
            S.box(b, V3(gx + sx * 0.8, 1.7, GardenLayout.fenceZ + 0.09), V3(0.005, 0.005, 0.1), r: 0.003, color: c(0.30, 0.30, 0.32))
            S.blob(b, V3(x, y, z), rx: 0.19, ry: 0.12, rz: 0.19, color: wood * 0.9, segments: 14, rings: 6)
            S.blob(b, V3(x, y + 0.09, z), rx: 0.2, ry: 0.11, rz: 0.2, color: leafDeep, segments: 14, rings: 6)
            for k in 0..<6 {
                let a = Float(k) / 6 * 2 * .pi + Float(i)
                S.ball(b, V3(x + cosf(a) * 0.14, y + 0.15 + 0.02 * r.unit(), z + sinf(a) * 0.14), 0.055, palette(i)[k % 3], segments: 8, rings: 4)
            }
            S.box(b, V3(x - 0.08, y + 0.22, z), V3(0.006, 0.12, 0.006), r: 0.003, color: c(0.30, 0.30, 0.32))
            S.box(b, V3(x + 0.08, y + 0.22, z), V3(0.006, 0.12, 0.006), r: 0.003, color: c(0.30, 0.30, 0.32))
        }
    }

    private static func stringLights(_ b: RoomMeshBuilder) {
        // poles for the long strings
        S.box(b, V3(-4.95, 1.0, -4.9), V3(0.04, 1.0, 0.04), r: 0.015, color: white)
        let warm = c(1.0, 0.86, 0.55)
        func string(_ p0: V3, _ p1: V3, sag: Float, spacing: Float) {
            let n = max(2, Int(simd_distance(p0, p1) / spacing))
            for k in 0...n {
                let t = Float(k) / Float(n)
                var p = simd_mix(p0, p1, SIMD3(repeating: t))
                p.y -= sag * 4 * t * (1 - t)
                b.material = .lamp
                S.ball(b, p, 0.045, warm, segments: 6, rings: 3)
                b.material = .plain
                S.ball(b, p + V3(0, 0.05, 0), 0.015, c(0.25, 0.25, 0.25), segments: 4, rings: 2)
            }
        }
        let gx = GardenLayout.gateX
        string(V3(gx, 2.85, GardenLayout.fenceZ + 0.1), V3(-4.95, 1.95, -4.85), sag: 0.35, spacing: 0.34)
        string(V3(gx, 2.85, GardenLayout.fenceZ + 0.1), V3(GardenLayout.shed.min.x - 0.1, 2.2, GardenLayout.shed.max.y + 0.1), sag: 0.7, spacing: 0.36)
        string(V3(GardenLayout.shed.min.x - 0.1, 2.2, GardenLayout.shed.max.y + 0.1), V3(4.95, 2.1, GardenLayout.shed.max.y + 0.1), sag: 0.2, spacing: 0.36)
    }
}
