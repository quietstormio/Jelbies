//
//  GardenScenery.swift
//  The Garden's static meshes (built once per room switch, drawn in the room's cached pass): the pastel sky pane, the lawn with mowing stripes and a
//  stepping-stone path, picket fences on three sides with a gate under a rose arch, sunflowers along the back fence, dense flower beds (fence lines, two round
//  beds, the lavender-lined path, a hydrangea at each corner), hanging baskets, the veg-patch trough, a potting shed, a sunny deck, a bird bath and warm
//  string lights (the lamp material, so they glow at night). The plants of the four plots and everything that moves are in GardenPlants.swift.
//  Colours are linear (OKLab.srgbToLinear of friendly sRGB values) and brighter / warmer than the Park's, so the two places do not look alike.
//

import simd
import Foundation

enum GardenScenery {
    typealias S = GardenShapes
    typealias V3 = SIMD3<Float>
    typealias PP = RoomMeshBuilder.ProfilePoint
    private static func c(_ r: Float, _ g: Float, _ b: Float) -> V3 { S.srgb(r, g, b) }

    static let white = c(0.97, 0.96, 0.93), sky = c(0.70, 0.83, 0.94), wood = c(0.78, 0.60, 0.42), terracotta = c(0.82, 0.46, 0.34)
    static let soil = c(0.36, 0.25, 0.18), stone = c(0.80, 0.77, 0.73), leafDeep = c(0.26, 0.52, 0.24), leafLight = c(0.40, 0.68, 0.30)

    /// Flower colours per bloom (sRGB-friendly pastels and brights).
    static let tulipColours: [V3] = [c(0.92, 0.30, 0.34), c(0.97, 0.58, 0.72), c(0.98, 0.82, 0.28), c(0.66, 0.46, 0.84), c(0.98, 0.62, 0.28), c(0.99, 0.93, 0.88)]
    static let roseColours: [V3] = [c(0.96, 0.52, 0.64), c(0.97, 0.66, 0.58), c(0.99, 0.94, 0.90), c(0.88, 0.28, 0.38)]
    static let poppyColours: [V3] = [c(0.97, 0.45, 0.30), c(0.96, 0.62, 0.74), c(0.99, 0.80, 0.30), c(0.92, 0.36, 0.46)]
    static let daisyColours: [V3] = [c(0.99, 0.98, 0.95), c(0.99, 0.95, 0.80), c(0.98, 0.84, 0.90)]
    static let lavenderColours: [V3] = [c(0.66, 0.54, 0.88), c(0.74, 0.62, 0.92), c(0.58, 0.48, 0.84)]
    static let hydrangeaColours: [V3] = [c(0.58, 0.70, 0.96), c(0.96, 0.70, 0.84), c(0.76, 0.66, 0.94), c(0.70, 0.82, 0.98)]

    static func build(theme: RoomTheme) -> RoomMesh {
        let b = RoomMeshBuilder()
        var r = ParkRandom(0x6A2D)
        skyAndGround(b)
        beyond(b, &r)
        fences(b)
        gateAndArch(b, &r)
        trough(b)
        shed(b, &r)
        deck(b, &r)
        birdBath(b)
        pathAndLavender(b, &r)
        roundBeds(b, &r)
        fenceBeds(b, &r)
        sunflowers(b, &r)
        meadow(b, &r)
        baskets(b, &r)
        stringLights(b)
        return b.mesh
    }

    // MARK: sky, lawn

    private static func skyAndGround(_ b: RoomMeshBuilder) {
        b.material = .glow
        let lo = V3(0.86, 0.74, 0.70), hi = V3(0.42, 0.62, 0.86)
        b.flatQuad(V3(-80, 0, -14), V3(80, 0, -14), V3(80, 24, -14), V3(-80, 24, -14), normal: V3(0, 0, 1), colors: [lo, lo, hi, hi])
        b.material = .plain
        let far = c(0.38, 0.62, 0.30), near = c(0.52, 0.76, 0.38)
        b.flatQuad(V3(-80, 0, -13.5), V3(80, 0, -13.5), V3(80, 0, 50), V3(-80, 0, 50), normal: V3(0, 1, 0), colors: [far, far, near, near])
        // the yard: mowing stripes
        let a = c(0.56, 0.80, 0.40), d = c(0.51, 0.75, 0.36)
        var z: Float = -5.2
        var k = 0
        while z < 15 {
            let col = k % 2 == 0 ? a : d
            b.flatQuad(V3(-5.2, 0.004, z), V3(5.2, 0.004, z), V3(5.2, 0.004, z + 1.4), V3(-5.2, 0.004, z + 1.4), normal: V3(0, 1, 0), colors: [col, col, col, col])
            z += 1.4; k += 1
        }
    }

    /// Hedge and trees beyond the fences, soft hills, clouds.
    private static func beyond(_ b: RoomMeshBuilder, _ r: inout ParkRandom) {
        for (x, rx, ry) in [(-18 as Float, 14 as Float, 3.0 as Float), (2, 18, 2.4), (20, 14, 3.4)] {
            S.blob(b, V3(x, -0.4, -12.6), rx: rx, ry: ry, rz: 2.6, color: c(0.46, 0.70, 0.46), segments: 20, rings: 8)
        }
        var x: Float = -7.4
        while x < 7.6 {
            let g = r.unit()
            S.blob(b, V3(x, 0.62, -6.1), rx: 0.95, ry: 0.78, rz: 0.62, color: c(0.30 + 0.06 * g, 0.58 + 0.06 * g, 0.28), segments: 9, rings: 5)
            x += 1.5
        }
        let blossom = c(0.98, 0.76, 0.84), green = c(0.40, 0.68, 0.34), green2 = c(0.34, 0.62, 0.32)
        let trees: [(Float, Float, Float, V3)] = [(-7.4, -7.4, 5.2, blossom), (7.6, -7.8, 5.6, green), (-12, -4.5, 5.4, green2), (12.5, -3.5, 5.0, blossom),
                                                  (-3.2, -10, 6.0, green), (3.0, -10.5, 5.6, blossom), (-9.5, 4.0, 4.8, green), (10, 5.5, 5.0, green2)]
        for t in trees { tree(b, x: t.0, z: t.1, height: t.2, crown: t.3, rng: &r) }
        for (cx, cy, s) in [(-9 as Float, 12 as Float, 1.0 as Float), (7, 10.5, 1.3), (-1, 14, 0.9), (13, 13, 1.1)] {
            for k in 0..<3 {
                S.blob(b, V3(cx + Float(k - 1) * 1.7 * s, cy + (k == 1 ? 0.5 : 0), -12.8), rx: 1.9 * s, ry: 0.75 * s, rz: 0.5, color: c(1.0, 0.96, 0.94), segments: 10, rings: 5)
            }
        }
    }

    /// The park's layered tree (Park/ParkNature.swift), tinted by `crown`.
    private static func tree(_ b: RoomMeshBuilder, x: Float, z: Float, height h: Float, crown: V3, rng r: inout ParkRandom) {
        ParkScenery.tree(b, x: x, z: z, height: h, scale: 1.0, hue: crown * 0.9, rng: &r)
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
                S.box(b, V3(sx, 0.47, z), V3(0.014, 0.47, 0.05), r: 0.03, color: sky)
                z += step
            }
            S.box(b, V3(sx + (sx < 0 ? -0.03 : 0.03), 0.30, 2), V3(0.02, 0.035, 7.1), r: 0.015, color: sky * 0.96)
            S.box(b, V3(sx + (sx < 0 ? -0.03 : 0.03), 0.70, 2), V3(0.02, 0.035, 7.1), r: 0.015, color: sky * 0.96)
        }
        // posts with ball caps
        for px: Float in [-5.0, -4.2, -1.8, -0.6, 0.6, 1.8, 5.0] {
            S.box(b, V3(px, 0.58, GardenLayout.fenceZ), V3(0.06, 0.58, 0.06), r: 0.02, color: white)
            S.ball(b, V3(px, 1.2, GardenLayout.fenceZ), 0.075, white, segments: 8, rings: 4)
        }
        for sx: Float in [-5.0, 5.0] {
            for pz: Float in [-2.5, 0.5, 3.5, 6.5] {
                S.box(b, V3(sx, 0.7, pz), V3(0.06, 0.7, 0.06), r: 0.02, color: sky)
                S.ball(b, V3(sx, 1.46, pz), 0.075, sky, segments: 8, rings: 4)
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
        let pink: [V3] = [c(0.96, 0.50, 0.62), c(0.98, 0.68, 0.74), c(0.90, 0.36, 0.50), c(0.99, 0.90, 0.88)]
        for k in 0..<34 {
            let t = Float(k) / 33
            var p: V3
            if t < 0.3 { p = V3(gx - w, 0.5 + t / 0.3 * 1.8, z + 0.07) }
            else if t < 0.7 { let a = (t - 0.3) / 0.4 * Float.pi; p = V3(gx - cosf(a) * w, 2.28 + sinf(a) * 0.5, z + 0.07) }
            else { p = V3(gx + w, 0.5 + (1 - (t - 0.7) / 0.3) * 1.8, z + 0.07) }
            p.x += (r.unit() - 0.5) * 0.14; p.y += (r.unit() - 0.5) * 0.1
            S.ball(b, p, 0.1 + 0.03 * r.unit(), simd_mix(leafDeep, leafLight, SIMD3(repeating: r.unit())), segments: 6, rings: 3)
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

    // MARK: shed

    private static func shed(_ b: RoomMeshBuilder, _ r: inout ParkRandom) {
        let s = GardenLayout.shed
        let cx = (s.min.x + s.max.x) / 2, cz = (s.min.y + s.max.y) / 2, hx = (s.max.x - s.min.x) / 2, hz = (s.max.y - s.min.y) / 2
        let wall = c(0.78, 0.86, 0.78)
        S.box(b, V3(cx, s.height / 2, cz), V3(hx, s.height / 2, hz), r: 0.03, color: wall)
        // a plank line every 0.3 on the front
        var px = s.min.x + 0.15
        while px < s.max.x { S.box(b, V3(px, s.height / 2, s.max.y + 0.006), V3(0.008, s.height / 2 - 0.03, 0.004), r: 0.003, color: wall * 0.88); px += 0.3 }
        // gabled roof (ridge along x)
        let roof = c(0.84, 0.50, 0.46)
        let x0 = s.min.x - 0.14, x1 = s.max.x + 0.14, zf = s.max.y + 0.16, zb = s.min.y - 0.1, zr = cz, ye = s.height - 0.02, yr = s.height + 0.5
        let nf = simd_normalize(V3(0, zf - zr, yr - ye)), nb = simd_normalize(V3(0, zr - zb, -(yr - ye)))
        b.flatQuad(V3(x0, ye, zf), V3(x1, ye, zf), V3(x1, yr, zr), V3(x0, yr, zr), normal: nf, colors: [roof, roof, roof * 1.1, roof * 1.1])
        b.flatQuad(V3(x0, ye, zb), V3(x1, ye, zb), V3(x1, yr, zr), V3(x0, yr, zr), normal: nb, colors: [roof * 0.9, roof * 0.9, roof, roof])
        for ex in [x0, x1] {
            let nx: V3 = V3(ex < cx ? -1 : 1, 0, 0)
            let a = b.vertex(V3(ex, ye, zf), nx, color: wall), bb = b.vertex(V3(ex, ye, zb), nx, color: wall), tt = b.vertex(V3(ex, yr, zr), nx, color: wall)
            b.triangle(a, bb, tt)
        }
        S.box(b, V3(cx, yr + 0.02, zr), V3(hx + 0.15, 0.03, 0.05), r: 0.015, color: roof * 0.8)
        // door, window with a flower box, a doorstep
        S.box(b, V3(s.min.x + 0.62, 0.8, s.max.y + 0.02), V3(0.34, 0.8, 0.02), r: 0.015, color: sky)
        S.ball(b, V3(s.min.x + 0.82, 0.8, s.max.y + 0.06), 0.03, c(0.95, 0.80, 0.40), segments: 6, rings: 3)
        S.box(b, V3(s.min.x + 0.62, 0.03, s.max.y + 0.22), V3(0.4, 0.03, 0.2), r: 0.015, color: stone)
        let wx = s.max.x - 0.6
        S.box(b, V3(wx, 1.3, s.max.y + 0.015), V3(0.34, 0.3, 0.018), r: 0.012, color: white)
        S.box(b, V3(wx, 1.3, s.max.y + 0.026), V3(0.29, 0.25, 0.012), r: 0.01, color: c(0.80, 0.92, 1.0))
        S.box(b, V3(wx, 1.3, s.max.y + 0.034), V3(0.012, 0.25, 0.01), r: 0.004, color: white)
        S.box(b, V3(wx, 0.95, s.max.y + 0.09), V3(0.4, 0.07, 0.08), r: 0.02, color: wood)
        for k in 0..<7 {
            let fx = wx - 0.34 + Float(k) * 0.113
            S.ball(b, V3(fx, 1.04, s.max.y + 0.09), 0.065, tulipColours[k % tulipColours.count], segments: 6, rings: 3)
        }
        // a greenhouse lean-to window on the left side face is skipped: the camera cannot see it
        // a terracotta pot and a watering can by the door
        S.cylinder(b, x: s.min.x - 0.22, z: s.max.y + 0.12, r: 0.13, y0: 0, y1: 0.24, color: terracotta, segments: 12)
        S.ball(b, V3(s.min.x - 0.22, 0.34, s.max.y + 0.12), 0.17, leafDeep, segments: 8, rings: 4)
        S.ball(b, V3(s.min.x - 0.18, 0.42, s.max.y + 0.16), 0.07, c(0.97, 0.55, 0.68), segments: 6, rings: 3)
    }

    // MARK: deck

    private static func deck(_ b: RoomMeshBuilder, _ r: inout ParkRandom) {
        let d = GardenLayout.deck
        let cx = (d.min.x + d.max.x) / 2, hx = (d.max.x - d.min.x) / 2
        var z = d.min.y + 0.1
        var k = 0
        while z < d.max.y {
            let col = k % 2 == 0 ? c(0.82, 0.66, 0.48) : c(0.78, 0.62, 0.45)
            S.box(b, V3(cx, 0.03, z), V3(hx, 0.028, 0.098), r: 0.012, color: col)
            z += 0.2; k += 1
        }
        S.box(b, V3(cx, 0.015, d.max.y + 0.005), V3(hx, 0.02, 0.02), r: 0.01, color: wood * 0.85)
        // pots at the front corner and the near corner
        for (px, pz) in [(d.min.x + 0.25, d.max.y - 0.25), (d.max.x - 0.3, d.max.y - 0.3)] {
            S.cylinder(b, x: px, z: pz, r: 0.18, y0: 0.05, y1: 0.40, color: terracotta, segments: 12)
            S.ball(b, V3(px, 0.62, pz), 0.27, leafDeep, segments: 8, rings: 4)
            for j in 0..<5 {
                let a = Float(j) * 1.3
                S.ball(b, V3(px + cosf(a) * 0.17, 0.66 + 0.06 * Float(j % 2), pz + sinf(a) * 0.17 + 0.04), 0.06, tulipColours[(j + 1) % tulipColours.count], segments: 6, rings: 3)
            }
        }
        // a sun cushion for napping
        S.box(b, V3(d.min.x + 1.0, 0.085, d.min.y + 1.2), V3(0.55, 0.035, 0.38), r: 0.03, color: c(0.98, 0.84, 0.88))
        S.box(b, V3(d.min.x + 1.0, 0.115, d.min.y + 1.2), V3(0.5, 0.012, 0.33), r: 0.01, color: c(0.99, 0.93, 0.82))
    }

    // MARK: bird bath

    private static func birdBath(_ b: RoomMeshBuilder) {
        let p = GardenLayout.birdBath
        let prof: [PP] = [PP(r: 0, y: 0, nr: 0, ny: -1), PP(r: 0.30, y: 0, nr: 0, ny: -1), PP(r: 0.30, y: 0.07, nr: 1, ny: 0.2, ao: 0.7), PP(r: 0.14, y: 0.14, nr: 0.5, ny: 1),
                          PP(r: 0.10, y: 0.2, nr: 1, ny: 0), PP(r: 0.09, y: 0.62, nr: 1, ny: 0), PP(r: 0.16, y: 0.70, nr: 0.7, ny: -0.6), PP(r: 0.40, y: 0.78, nr: 0.7, ny: -0.5),
                          PP(r: 0.50, y: 0.90, nr: 1, ny: 0.2), PP(r: 0.46, y: 0.96, nr: 0, ny: 1), PP(r: 0.42, y: 0.90, nr: -0.8, ny: 0.5)]
        b.lathe(cx: p.x, cz: p.y, profile: prof, segments: 22, color: stone)
        S.disc(b, cx: p.x, cz: p.y, radius: 0.40, y: 0.905, color: c(0.58, 0.80, 0.95), segments: 20)
        // a small bird on the rim, and a leaf in the water
        S.blob(b, V3(p.x + 0.40, 1.03, p.y + 0.12), rx: 0.075, ry: 0.065, rz: 0.06, color: c(0.55, 0.68, 0.92), segments: 8, rings: 4)
        S.ball(b, V3(p.x + 0.34, 1.10, p.y + 0.14), 0.045, c(0.55, 0.68, 0.92), segments: 7, rings: 3)
        S.ball(b, V3(p.x + 0.29, 1.10, p.y + 0.15), 0.014, c(0.98, 0.70, 0.30), segments: 5, rings: 3)
        S.blob(b, V3(p.x - 0.12, 0.915, p.y + 0.1), rx: 0.07, ry: 0.01, rz: 0.04, color: leafLight, segments: 8, rings: 2)
        // flowers around the foot
        var rr = ParkRandom(0x8B17)
        for k in 0..<9 {
            let a = Float(k) / 9 * 2 * .pi
            S.flower(b, k % 3 == 0 ? .daisy : .poppy, x: p.x + cosf(a) * 0.6, z: p.y + sinf(a) * 0.55, h: 0.2 + 0.1 * rr.unit(), color: k % 3 == 0 ? daisyColours[0] : poppyColours[k % 4], rng: &rr)
        }
    }

    // MARK: path and lavender

    /// Centre of the path at depth z (from the gate toward the front, bending once).
    static func pathX(_ z: Float) -> Float { GardenLayout.gateX + (z + 3.6) / 9.0 * 2.6 + 0.45 * sinf((z + 3.6) * 0.55) }

    private static func pathAndLavender(_ b: RoomMeshBuilder, _ r: inout ParkRandom) {
        var z: Float = -3.55
        var k = 0
        while z < 6.5 {
            let x = pathX(z) + (r.unit() - 0.5) * 0.14
            let rad = 0.27 + 0.07 * r.unit()
            let col = stone * (0.9 + 0.14 * r.unit())
            S.cylinder(b, x: x, z: z, r: rad, y0: 0.004, y1: 0.03, color: col, segments: 12)
            // lavender clumps along both sides
            for side: Float in [-1, 1] {
                for j in 0..<3 {
                    let lx = x + side * (0.5 + 0.12 * Float(j)) + (r.unit() - 0.5) * 0.1, lz = z + (r.unit() - 0.5) * 0.4 + 0.1 * Float(j)
                    S.flower(b, .lavender, x: lx, z: lz, h: 0.26 + 0.1 * r.unit(), color: lavenderColours[(k + j) % 3], rng: &r)
                }
            }
            z += 0.72 + 0.1 * r.unit(); k += 1
        }
    }

    // MARK: round beds

    private static func roundBeds(_ b: RoomMeshBuilder, _ r: inout ParkRandom) {
        for (i, p) in [GardenLayout.bedA, GardenLayout.bedB].enumerated() {
            S.disc(b, cx: p.x, cz: p.y, radius: GardenLayout.bedRadius, y: 0.06, color: soil, segments: 24)
            for k in 0..<14 {
                let a = Float(k) / 14 * 2 * .pi
                S.blob(b, V3(p.x + cosf(a) * (GardenLayout.bedRadius + 0.02), 0.07, p.y + sinf(a) * (GardenLayout.bedRadius + 0.02)), rx: 0.13, ry: 0.1, rz: 0.13,
                       color: stone * (0.88 + 0.14 * r.unit()), segments: 6, rings: 3)
            }
            // a rose bush at the heart, tulips and daisies round it
            S.blob(b, V3(p.x, 0.36, p.y), rx: 0.26, ry: 0.28, rz: 0.26, color: leafDeep, segments: 9, rings: 5)
            for j in 0..<6 {
                let a = Float(j) * 1.1
                S.ball(b, V3(p.x + cosf(a) * 0.2, 0.46 + 0.07 * Float(j % 3), p.y + sinf(a) * 0.2 + 0.05), 0.06, roseColours[(i + j) % roseColours.count], segments: 6, rings: 3)
            }
            for k in 0..<26 {
                let a = r.unit() * 2 * .pi, rad = 0.3 + r.unit() * 0.36
                let kind: S.Bloom = k % 3 == 0 ? .daisy : (k % 3 == 1 ? .tulip : .poppy)
                let col: V3 = kind == .daisy ? daisyColours[k % 3] : (kind == .tulip ? tulipColours[(k + i) % tulipColours.count] : poppyColours[k % 4])
                S.flower(b, kind, x: p.x + cosf(a) * rad, z: p.y + sinf(a) * rad, y0: 0.06, h: 0.2 + 0.18 * r.unit(), color: col, rng: &r)
            }
        }
    }

    // MARK: fence beds

    /// A scatter of flowers over a rectangle on a low mulch bed.
    private static func strip(_ b: RoomMeshBuilder, x0: Float, x1: Float, z0: Float, z1: Float, perSquareMetre: Float, tall: Bool, _ r: inout ParkRandom) {
        let area = (x1 - x0) * (z1 - z0)
        S.box(b, V3((x0 + x1) / 2, 0.025, (z0 + z1) / 2), V3((x1 - x0) / 2, 0.025, (z1 - z0) / 2), r: 0.02, color: soil)
        let n = Int(area * perSquareMetre)
        for _ in 0..<n {
            let x = x0 + (x1 - x0) * r.unit(), z = z0 + (z1 - z0) * r.unit()
            let pick = Int(r.next() % 10)
            switch pick {
            case 0, 1: S.flower(b, .tulip, x: x, z: z, y0: 0.05, h: 0.28 + 0.2 * r.unit(), color: r.pick(tulipColours), rng: &r)
            case 2, 3: S.flower(b, .daisy, x: x, z: z, y0: 0.05, h: 0.22 + 0.2 * r.unit(), color: r.pick(daisyColours), rng: &r)
            case 4: S.flower(b, .rose, x: x, z: z, y0: 0.05, h: 0.3 + 0.25 * r.unit(), color: r.pick(roseColours), rng: &r)
            case 5, 6: S.flower(b, .poppy, x: x, z: z, y0: 0.05, h: 0.25 + 0.25 * r.unit(), color: r.pick(poppyColours), rng: &r)
            case 7: S.flower(b, .lavender, x: x, z: z, y0: 0.05, h: 0.3 + 0.2 * r.unit(), color: r.pick(lavenderColours), rng: &r)
            case 8: S.flower(b, .tulip, x: x, z: z, y0: 0.05, h: (tall ? 0.5 : 0.3) + 0.15 * r.unit(), color: r.pick(tulipColours), rng: &r)
            default: S.flower(b, .daisy, x: x, z: z, y0: 0.05, h: 0.3 + 0.15 * r.unit(), color: r.pick(daisyColours), rng: &r)
            }
        }
    }

    private static func fenceBeds(_ b: RoomMeshBuilder, _ r: inout ParkRandom) {
        // down both side fences (the left starts past the bird bath, the right past the deck)
        strip(b, x0: -4.85, x1: -3.95, z0: -2.2, z1: 8.0, perSquareMetre: 16, tall: true, &r)
        strip(b, x0: 3.95, x1: 4.85, z0: -0.7, z1: 8.0, perSquareMetre: 16, tall: true, &r)
        // back corners and beside the trough
        strip(b, x0: -4.85, x1: -3.6, z0: -4.75, z1: -3.75, perSquareMetre: 18, tall: true, &r)
        strip(b, x0: 2.05, x1: 2.45, z0: -4.75, z1: -3.9, perSquareMetre: 18, tall: false, &r)
        strip(b, x0: -2.05, x1: -1.0, z0: -3.55, z1: -3.2, perSquareMetre: 20, tall: false, &r)
        // hydrangea puffs at the corners of the beds and the foot of the arch
        let hy: [(Float, Float)] = [(-4.55, -1.4), (4.5, 0.2), (-4.5, 3.0), (4.5, 3.4), (-4.55, 6.0), (4.5, 6.4), (-3.45, -4.2), (-2.05, -4.3)]
        for (i, h) in hy.enumerated() {
            S.flower(b, .hydrangea, x: h.0, z: h.1, h: 0.4, color: hydrangeaColours[i % hydrangeaColours.count], scale: 0.95, rng: &r)
        }
        // foliage mounds in the beds' backs
        for (x, z) in [(-4.6, 1.5), (4.6, 1.7), (-4.6, 4.5), (4.6, 5.0)] as [(Float, Float)] {
            S.bush(b, x: x, z: z, scale: 0.6, color: leafDeep, bloom: roseColours[Int(r.next() % 4)], rng: &r)
        }
    }

    private static func sunflowers(_ b: RoomMeshBuilder, _ r: inout ParkRandom) {
        var x: Float = -4.8
        while x < 3.1 {
            if x > GardenLayout.gateX - 0.9 && x < GardenLayout.gateX + 0.9 { x += 0.8; continue }
            let h = 1.4 + 0.5 * r.unit()
            S.flower(b, .sunflower, x: x + (r.unit() - 0.5) * 0.2, z: GardenLayout.fenceZ + 0.2 + 0.1 * r.unit(), h: h, color: .zero, scale: 0.9 + 0.2 * r.unit(), rng: &r)
            x += 0.8 + 0.2 * r.unit()
        }
    }

    /// Low wild flowers dotted over the lawn edges (small enough for a Jelbie to walk through).
    private static func meadow(_ b: RoomMeshBuilder, _ r: inout ParkRandom) {
        for _ in 0..<150 {
            let side: Float = r.unit() < 0.5 ? -1 : 1
            let x = side * (3.6 + r.unit() * 1.2), z = -2.0 + r.unit() * 9.5
            let da = simd_distance(SIMD2(x, z), GardenLayout.bedA), db = simd_distance(SIMD2(x, z), GardenLayout.bedB)
            if da < GardenLayout.bedRadius + 0.3 || db < GardenLayout.bedRadius + 0.3 { continue }
            if x > GardenLayout.deck.min.x - 0.2 && z < GardenLayout.deck.max.y + 0.2 { continue }
            let daisy = r.unit() < 0.6
            S.flower(b, daisy ? .daisy : .poppy, x: x, z: z, h: 0.1 + 0.07 * r.unit(), color: daisy ? r.pick(daisyColours) : r.pick(poppyColours), scale: 0.8, rng: &r)
        }
    }

    // MARK: hanging baskets, lights

    private static func basket(_ b: RoomMeshBuilder, x: Float, y: Float, z: Float, _ r: inout ParkRandom) {
        S.blob(b, V3(x, y, z), rx: 0.17, ry: 0.11, rz: 0.17, color: c(0.58, 0.40, 0.28), segments: 9, rings: 4)
        for k in 0..<9 {
            let a = Float(k) / 9 * 2 * .pi
            let col = k % 3 == 0 ? r.pick(tulipColours) : (k % 3 == 1 ? r.pick(poppyColours) : r.pick(roseColours))
            S.ball(b, V3(x + cosf(a) * 0.13, y + 0.1 + 0.03 * r.unit(), z + sinf(a) * 0.13), 0.06, col, segments: 6, rings: 3)
        }
        S.ball(b, V3(x, y + 0.13, z), 0.1, leafLight, segments: 7, rings: 3)
        // trailing greenery
        for k in 0..<3 { S.blob(b, V3(x + (Float(k) - 1) * 0.12, y - 0.14 - 0.04 * Float(k % 2), z + 0.1), rx: 0.04, ry: 0.1, rz: 0.04, color: leafDeep, segments: 5, rings: 3) }
        // two chains up to the hook
        S.box(b, V3(x - 0.08, y + 0.22, z), V3(0.006, 0.12, 0.006), r: 0.003, color: c(0.30, 0.30, 0.32))
        S.box(b, V3(x + 0.08, y + 0.22, z), V3(0.006, 0.12, 0.006), r: 0.003, color: c(0.30, 0.30, 0.32))
    }

    private static func baskets(_ b: RoomMeshBuilder, _ r: inout ParkRandom) {
        let gx = GardenLayout.gateX
        for sx: Float in [-0.9, 0.9] {
            S.box(b, V3(gx + sx * 0.8, 1.7, GardenLayout.fenceZ + 0.09), V3(0.005, 0.005, 0.1), r: 0.003, color: c(0.30, 0.30, 0.32))
            basket(b, x: gx + sx, y: 1.45, z: GardenLayout.fenceZ + 0.2, &r)
        }
        for sx: Float in [-1, 1] {
            for pz: Float in [-2.5, 0.5, 3.5, 6.5] {
                // an arm from the post, and the basket hung inside the fence
                S.box(b, V3(sx * 4.85, 1.36, pz), V3(0.14, 0.012, 0.012), r: 0.005, color: c(0.30, 0.30, 0.32))
                basket(b, x: sx * 4.72, y: 1.08, z: pz, &r)
            }
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
