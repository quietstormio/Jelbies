//
//  GroomRoom.swift
//  The Jelly Spa seen from the street, a real 3D scene built like the park's: a RoomDef applied under the white fade (nothing is saved), its camera, and the
//  scenery in code: a calm boutique in warm white plaster, sage, light wood, charcoal lettering and a touch of brass, a solid sage awning, a big round frosted
//  window, a wall-mounted "Jelly Spa" plate (letters are geometry) with a droplet mark, olive trees in stone pots, stone pavement. The animated bits (the door,
//  the window glow, subtle bubbles, dryer steam, sparkles) are one small mesh rebuilt every frame (`GroomScenery.fx`), drawn
//  as the room's "animating decor". The Jelbies are inside, so none are drawn until the door opens (GameCare+Groom.swift).
//
//  World: y up, floor = xz, +z toward the camera. The shop front face is at z = frontZ.
//

import simd
import Foundation

extension RoomCatalog {
    static let groom = RoomDef(
        id: .groom, title: "Jelly Spa", blurb: "The shop on the street.",
        theme: RoomTheme(tint: SIMD3(0.92, 0.88, 0.84), chromaScale: 0.8, lightnessShift: 0.03),
        couch: .init(centre: SIMD3(0, 0.45, -40), halfExtents: SIMD3(1.35, 0.45, 0.35), radius: 0.15), boxes: [],
        cylinders: [],
        lampTable: .init(centre: SIMD2(30, -40), radius: 1.0, height: 0.3), lamp: SIMD3(0, 1.5, -40),
        windows: RoomWindows(xs: [], halfW: 0, y0: 0, y1: 14, proceduralFrames: false),
        floor: .chevron, wall: .plain, rug: .rings, art: nil)
}

extension GameCamera {
    nonisolated(unsafe) static var groomOn = false
    static let groomElevation: Float = 17 * .pi / 180

    /// Looks at the shop front straight on from a little above: the whole facade (and the pavement the Jelbies stand on) fits the width of a portrait phone and the
    /// height of a landscape one.
    static func groomPose(aspect: Float) -> (eye: SIMD3<Float>, target: SIMD3<Float>) {
        let th = tanf(fovY / 2)
        let portrait = portraitAmount(aspect)
        let needW: Float = 9.2, needH: Float = 8.6 - 0.8 * portrait
        let dist = max(needW / (2 * th * max(aspect, 0.2)), needH / (2 * th))
        let ty: Float = 1.6 + 0.9 * portrait
        let t = SIMD3<Float>(0, ty, -3.2)
        let dir = SIMD3<Float>(0, sinf(groomElevation), cosf(groomElevation))
        return (t + dir * dist, t)
    }

    static func configureGroom() {
        roamFloor = nil; RoomLayout.setFront(z: RoomLayout.maxZ)
        roomWideScale = 1; roomWideLift = 0
        walkMaxZ = 4.5; arenaCenter = SIMD2(0, 0); arenaRadius = 80
        roamRect = (SIMD2(-4.0, -4.9), SIMD2(4.0, 3.2)); roamRectWide = roamRect
        groomOn = true
    }
    static func endGroom(count: Int) {
        groomOn = false
        configureRoom(count: count)
    }
}

enum GroomScenery {
    typealias PP = RoomMeshBuilder.ProfilePoint
    typealias V3 = SIMD3<Float>
    static func c(_ r: Float, _ g: Float, _ b: Float) -> V3 { ParkShapes.srgb(r, g, b) }

    static let frontZ: Float = -4.7
    static let doorX: Float = 1.7, doorW: Float = 0.62, doorH: Float = 1.05, doorY: Float = 1.2
    static let windowC = V3(-1.55, 1.3, frontZ + 0.03), windowR: Float = 0.72
    /// Where the Jelbies step out (just in front of the door) and the line-up in front of the shop.
    static let doorStep = SIMD2<Float>(doorX, frontZ + 0.9)
    static func lineUp(index k: Int, of n: Int) -> SIMD2<Float> {
        SIMD2((Float(k) - Float(n - 1) / 2) * GroomTuning.lineSpacing, -1.2)
    }

    // palette: warm white plaster, sage, light wood, charcoal, a touch of brass (and stone for the ground)
    static let plaster = c(0.96, 0.94, 0.89), sage = c(0.60, 0.70, 0.60), sageDeep = c(0.50, 0.61, 0.52), wood = c(0.80, 0.65, 0.46)
    static let charcoal = c(0.20, 0.22, 0.23), brass = c(0.80, 0.65, 0.30), stone = c(0.80, 0.78, 0.73), stoneDark = c(0.70, 0.68, 0.63)
    static let white = c(1.0, 0.99, 0.97), warm = c(1.0, 0.86, 0.60)

    // MARK: helpers

    /// Surface of revolution about an axis parallel to z through `ctr`: `profile` = (radius, dz, normal radial, normal z).
    static func latheZ(_ b: RoomMeshBuilder, _ ctr: V3, _ profile: [(r: Float, dz: Float, nr: Float, nz: Float)], segments N: Int = 36, color: V3, ao: Float = 1) {
        var rows: [[UInt32]] = []
        for p in profile {
            var row: [UInt32] = []
            for j in 0...N {
                let t = Float(j) / Float(N) * 2 * .pi, ct = cosf(t), st = sinf(t)
                row.append(b.vertex(V3(ctr.x + p.r * ct, ctr.y + p.r * st, ctr.z + p.dz), simd_normalize(V3(p.nr * ct, p.nr * st, p.nz)), ao: ao, color: color))
            }
            rows.append(row)
        }
        for i in 0..<(rows.count - 1) { for j in 0..<N { b.quad(rows[i][j], rows[i][j + 1], rows[i + 1][j + 1], rows[i + 1][j]) } }
    }
    static func discZ(_ b: RoomMeshBuilder, _ ctr: V3, _ r: Float, color: V3, segments: Int = 32) {
        latheZ(b, ctr, [(0, 0, 0, 1), (r, 0, 0, 1)], segments: segments, color: color)
    }
    /// A round tube ring (front half) of mid radius `rm` and tube radius `s`.
    static func ringZ(_ b: RoomMeshBuilder, _ ctr: V3, rm: Float, s: Float, color: V3, segments: Int = 40) {
        var prof: [(r: Float, dz: Float, nr: Float, nz: Float)] = []
        for k in 0...6 { let a = Float.pi - Float.pi * Float(k) / 6; prof.append((rm + s * cosf(a), s * sinf(a), cosf(a), sinf(a))) }
        latheZ(b, ctr, prof, segments: segments, color: color)
    }
    /// Rotates the vertices added since `from` about the axis through `pivot` (right-handed).
    static func rotate(_ b: RoomMeshBuilder, from: Int, pivot: V3, axis: V3, angle: Float) {
        let q = simd_quatf(angle: angle, axis: simd_normalize(axis))
        for i in from..<b.mesh.vertices.count {
            let p = b.mesh.vertices[i].pos, n = b.mesh.vertices[i].normal
            let np = q.act(V3(p.x, p.y, p.z) - pivot) + pivot, nn = q.act(V3(n.x, n.y, n.z))
            b.mesh.vertices[i].pos = SIMD4(np, p.w); b.mesh.vertices[i].normal = SIMD4(nn, n.w)
        }
    }
    static func box(_ b: RoomMeshBuilder, _ ctr: V3, _ h: V3, r: Float, color: V3, seg: Int = 3) {
        b.roundedBox(centre: ctr, half: h, radius: r, segments: seg, aoFloor: false, color: color)
    }

    // MARK: letters (stroked geometry on the plaque)

    /// Stroke fonts in a unit cell (x 0...~0.8, baseline 0, cap 1, x-height 0.6, descender -0.35). Each glyph = polylines + its advance.
    static let glyphs: [Character: (strokes: [[SIMD2<Float>]], advance: Float)] = [
        "J": ([[P(0.72, 1), P(0.72, 0.3), P(0.6, 0.08), P(0.38, 0), P(0.14, 0.1)]], 0.85),
        "e": ([[P(0.1, 0.32), P(0.7, 0.32), P(0.68, 0.46), P(0.56, 0.58), P(0.4, 0.62), P(0.22, 0.56), P(0.1, 0.4), P(0.08, 0.22), P(0.18, 0.06), P(0.38, 0), P(0.56, 0.04), P(0.68, 0.14)]], 0.82),
        "l": ([[P(0.22, 1), P(0.22, 0.06)]], 0.5),
        "y": ([[P(0.08, 0.6), P(0.4, 0.06)], [P(0.72, 0.6), P(0.3, -0.35)]], 0.85),
        "S": ([[P(0.7, 0.86), P(0.54, 1), P(0.3, 1), P(0.12, 0.88), P(0.12, 0.7), P(0.3, 0.55), P(0.52, 0.45), P(0.7, 0.3), P(0.7, 0.12), P(0.54, 0), P(0.3, 0), P(0.1, 0.12)]], 0.85),
        "p": ([[P(0.18, 0.6), P(0.18, -0.35)], [P(0.18, 0.5), P(0.4, 0.6), P(0.6, 0.5), P(0.7, 0.3), P(0.6, 0.1), P(0.4, 0), P(0.18, 0.1)]], 0.85),
        "a": ([[P(0.68, 0.4), P(0.52, 0.58), P(0.3, 0.62), P(0.12, 0.46), P(0.1, 0.22), P(0.24, 0.04), P(0.46, 0.02), P(0.68, 0.18)], [P(0.68, 0.62), P(0.68, 0)]], 0.85),
        " ": ([], 0.5)
    ]
    private static func P(_ x: Float, _ y: Float) -> SIMD2<Float> { SIMD2(x, y) }

    /// "Jelly Spa" centred on x = `cx`, baseline `y`, glyph cap height `h`, at depth `z`.
    static func text(_ b: RoomMeshBuilder, _ s: String, cx: Float, baseline y: Float, height h: Float, z: Float, color: V3) {
        let width = s.reduce(Float(0)) { $0 + (glyphs[$1]?.advance ?? 0.8) } * h
        var x0 = cx - width / 2
        let w = h * 0.13
        for ch in s {
            guard let g = glyphs[ch] else { continue }
            for st in g.strokes {
                for i in 0..<(st.count - 1) {
                    let a = V3(x0 + st[i].x * h, y + st[i].y * h, z), d = V3(x0 + st[i + 1].x * h, y + st[i + 1].y * h, z)
                    let dir = simd_normalize(d - a), perp = V3(-dir.y, dir.x, 0) * (w / 2)
                    b.flatQuad(a - perp, a + perp, d + perp, d - perp, normal: V3(0, 0, 1), colors: Array(repeating: color, count: 4))
                }
                for p in st { discZ(b, V3(x0 + p.x * h, y + p.y * h, z), w / 2, color: color, segments: 10) }
            }
            x0 += g.advance * h
        }
    }

    /// A four-point sparkle (two diamonds) facing the camera.
    static func star(_ b: RoomMeshBuilder, _ p: V3, _ r: Float, color: V3) {
        let n = V3(0, 0, 1), k = r * 0.28
        b.flatQuad(p + V3(0, r, 0), p + V3(-k, 0, 0), p + V3(0, -r, 0), p + V3(k, 0, 0), normal: n, colors: Array(repeating: color, count: 4))
        b.flatQuad(p + V3(r, 0, 0), p + V3(0, k, 0), p + V3(-r, 0, 0), p + V3(0, -k, 0), normal: n, colors: Array(repeating: color, count: 4))
    }

    // MARK: the static street

    static func build(theme: RoomTheme) -> RoomMesh {
        let b = RoomMeshBuilder()
        var rng = ParkRandom(0x59A5)
        let Z = frontZ

        // sky: a calm gradient from pale warm haze to a soft sage-blue (the dawn / dusk / night colours come from the room's daylight)
        b.material = .glow
        let lo = c(0.93, 0.92, 0.86), hi = c(0.52, 0.68, 0.74)
        b.flatQuad(V3(-80, 0, -14), V3(80, 0, -14), V3(80, 26, -14), V3(-80, 26, -14), normal: V3(0, 0, 1), colors: [lo, lo, hi, hi])

        b.material = .plain
        // ground: stone pavement all the way to the camera, with slab joints
        let ground = c(0.78, 0.76, 0.71)
        b.flatQuad(V3(-80, 0, -14), V3(80, 0, -14), V3(80, 0, 45), V3(-80, 0, 45), normal: V3(0, 1, 0), colors: [ground, ground, ground, ground])
        box(b, V3(0, 0.05, 1.5), V3(12, 0.05, 6.6), r: 0.04, color: stone)
        let joint = c(0.69, 0.67, 0.62)
        for k in -12...12 { box(b, V3(Float(k) * 1.0, 0.102, 1.5), V3(0.012, 0.004, 6.6), r: 0.003, color: joint, seg: 1) }
        for k in 0..<13 { box(b, V3(0, 0.102, -4.4 + Float(k) * 1.0), V3(12, 0.004, 0.012), r: 0.003, color: joint, seg: 1) }
        box(b, V3(0, 0.05, 10), V3(12, 0.05, 0.08), r: 0.03, color: stoneDark, seg: 1)

        // backdrop: soft sage hills, a muted terrace either side, olive-ish trees
        ParkScenery.blob(b, V3(-13, -0.5, -12), rx: 14, ry: 3.0, rz: 2.5, color: c(0.66, 0.74, 0.64), segments: 28, rings: 10)
        ParkScenery.blob(b, V3(14, -0.5, -12), rx: 15, ry: 3.5, rz: 2.5, color: c(0.62, 0.71, 0.62), segments: 28, rings: 10)
        box(b, V3(-8.0, 1.7, -8.4), V3(2.6, 1.7, 1.8), r: 0.4, color: c(0.90, 0.88, 0.82))
        box(b, V3(-8.0, 3.55, -8.4), V3(2.85, 0.26, 2.05), r: 0.24, color: c(0.72, 0.78, 0.70))
        box(b, V3(8.4, 2.2, -8.4), V3(2.5, 2.2, 1.8), r: 0.4, color: c(0.92, 0.90, 0.84))
        box(b, V3(8.4, 4.55, -8.4), V3(2.75, 0.26, 2.05), r: 0.24, color: c(0.72, 0.78, 0.70))
        for (wx, wy) in [(-9.0 as Float, 2.1 as Float), (-7.0, 2.1), (7.6, 2.8), (9.4, 2.8)] {
            discZ(b, V3(wx, wy, wx < 0 ? -6.55 : -6.58), 0.5, color: c(0.97, 0.93, 0.82), segments: 20)
        }
        let leaf = c(0.55, 0.66, 0.55), leaf2 = c(0.60, 0.70, 0.58)
        var tx: Float = -16
        var kk = 0
        while tx <= 16 {
            if abs(tx) > 5 { ParkScenery.roundTree(b, x: tx, z: -12.5, trunk: 0.8, radius: 1.8 + 0.25 * Float(kk % 3), canopy: kk % 2 == 0 ? leaf : leaf2, rng: &rng) }
            tx += 3.6; kk += 1
        }
        ParkScenery.roundTree(b, x: -5.6, z: -6.6, trunk: 1.1, radius: 1.5, canopy: leaf2, rng: &rng)
        ParkScenery.roundTree(b, x: 5.4, z: -6.8, trunk: 1.0, radius: 1.4, canopy: leaf, rng: &rng)

        // a few quiet clouds
        for (x, y, s) in [(-9 as Float, 12 as Float, 0.8 as Float), (9, 11, 1.0)] {
            for k in 0..<3 {
                ParkScenery.blob(b, V3(x + Float(k - 1) * 1.6 * s, y + (k == 1 ? 0.5 : 0), -12.6), rx: 1.8 * s, ry: 0.6 * s, rz: 0.5, color: c(0.97, 0.97, 0.96), segments: 14, rings: 6)
            }
        }

        // the shop: a clean plaster block, a low flat roof with a slim wood-and-sage cap, a stone plinth
        box(b, V3(0, 2.2, -6.5), V3(3.1, 2.2, 1.8), r: 0.3, color: plaster)
        box(b, V3(0, 0.12, -6.4), V3(3.2, 0.12, 1.9), r: 0.08, color: stone)
        box(b, V3(0, 4.5, -6.4), V3(3.3, 0.2, 2.0), r: 0.16, color: sageDeep)
        box(b, V3(0, 4.76, -6.3), V3(3.0, 0.08, 1.8), r: 0.06, color: plaster)
        ParkShapes.cylinder(b, x: 2.1, z: -6.0, r: 0.3, y0: 4.8, y1: 5.5, color: plaster)
        box(b, V3(2.1, 5.55, -6.0), V3(0.38, 0.06, 0.38), r: 0.05, color: sageDeep)
        ParkShapes.cylinder(b, x: -2.0, z: -6.0, r: 0.24, y0: 4.8, y1: 5.2, color: plaster)
        box(b, V3(-2.0, 5.24, -6.0), V3(0.31, 0.05, 0.31), r: 0.04, color: sageDeep)

        // the sign: a slim charcoal-lettered plate on the wall, a tiny brass droplet mark to the left of the name
        box(b, V3(0, 3.6, Z + 0.1), V3(1.9, 0.5, 0.05), r: 0.06, color: wood)
        box(b, V3(0, 3.6, Z + 0.16), V3(1.82, 0.42, 0.04), r: 0.05, color: plaster)
        text(b, "Jelly Spa", cx: 0.22, baseline: 3.46, height: 0.46, z: Z + 0.3, color: charcoal)
        droplet(b, V3(-1.52, 3.6, Z + 0.3), 0.15, color: brass)

        // the solid sage awning (a clean sloping canopy over the window and door, plain front lip)
        let from = b.mesh.vertices.count
        box(b, V3(0, 2.8, Z + 0.55), V3(2.95, 0.05, 0.52), r: 0.04, color: sage, seg: 2)
        rotate(b, from: from, pivot: V3(0, 2.8, Z + 0.55), axis: V3(1, 0, 0), angle: 0.5)
        box(b, V3(0, 2.52, Z + 1.0), V3(2.95, 0.09, 0.07), r: 0.06, color: sageDeep, seg: 2)

        // the big round window: a wood frame, frosted warm glass (the animated glow draws over it), no relief
        let wc = windowC
        ringZ(b, wc + V3(0, 0, -0.02), rm: windowR + 0.08, s: 0.1, color: wood)
        b.material = .glow
        discZ(b, wc + V3(0, 0, 0.0), windowR, color: warm)
        b.material = .plain
        box(b, V3(wc.x, wc.y, wc.z + 0.04), V3(windowR, 0.02, 0.02), r: 0.015, color: wood, seg: 1)            // a slim mullion
        box(b, V3(wc.x, 0.2, Z + 0.1), V3(windowR + 0.3, 0.1, 0.12), r: 0.06, color: stone)                      // a stone sill

        // the door: a light wood frame, the warm hall behind it (the door itself swings in the animated mesh), a stone step
        box(b, V3(doorX, doorY, Z - 0.02), V3(doorW + 0.1, doorH + 0.08, 0.08), r: 0.3, color: wood)
        b.material = .glow
        box(b, V3(doorX, doorY, Z + 0.025), V3(doorW, doorH, 0.02), r: 0.3, color: warm * 0.92, seg: 4)
        b.material = .plain
        box(b, V3(doorX, 0.18, Z + 0.45), V3(0.95, 0.08, 0.45), r: 0.05, color: stoneDark)

        // a wall lamp (brass) beside the door
        box(b, V3(2.75, 1.85, Z + 0.1), V3(0.03, 0.14, 0.03), r: 0.02, color: brass, seg: 1)
        ParkShapes.ball(b, V3(2.75, 1.7, Z + 0.17), 0.1, c(1.0, 0.93, 0.72), segments: 12, rings: 6)
        ParkShapes.cylinder(b, x: 2.75, z: Z + 0.1, r: 0.045, y0: 1.8, y1: 1.98, color: brass)

        // two olive trees in stone pots either side
        planter(b, x: -3.3, z: Z + 0.8, rng: &rng)
        planter(b, x: 3.5, z: Z + 0.8, rng: &rng)
        return b.mesh
    }

    /// A small droplet (a ball with a pointed top) facing the camera.
    static func droplet(_ b: RoomMeshBuilder, _ p: V3, _ r: Float, color: V3) {
        discZ(b, p + V3(0, -r * 0.25, 0), r * 0.75, color: color, segments: 20)
        b.flatQuad(p + V3(0, r * 1.25, 0), p + V3(-r * 0.7, -r * 0.05, 0), p + V3(0, -r * 0.1, 0), p + V3(r * 0.7, -r * 0.05, 0), normal: V3(0, 0, 1), colors: Array(repeating: color, count: 4))
    }

    private static func planter(_ b: RoomMeshBuilder, x: Float, z: Float, rng: inout ParkRandom) {
        ParkShapes.cylinder(b, x: x, z: z, r: 0.42, y0: 0.1, y1: 0.72, color: stone)
        ParkShapes.cylinder(b, x: x, z: z, r: 0.47, y0: 0.64, y1: 0.8, color: c(0.86, 0.84, 0.79))
        ParkShapes.cylinder(b, x: x, z: z, r: 0.035, y0: 0.8, y1: 1.6, color: c(0.45, 0.38, 0.30))
        let leaf = c(0.52, 0.63, 0.52), leaf2 = c(0.58, 0.69, 0.57)
        for (dx, dy, rx, ry) in [(0 as Float, 1.75 as Float, 0.5 as Float, 0.4 as Float), (-0.3, 1.45, 0.34, 0.26), (0.3, 1.5, 0.34, 0.26), (0.05, 2.1, 0.3, 0.24)] {
            ParkScenery.blob(b, V3(x + dx, dy, z), rx: rx, ry: ry, rz: rx, color: dy > 1.6 ? leaf : leaf2, segments: 14, rings: 6)
        }
    }

    // MARK: the animated bits

    struct FxState {
        var time: Float = 0            // wall clock seconds
        var shopT: Float = 0
        var phase: GroomTrip.Phase = .shop
        var doorOpen: Float = 0        // 0...1
        var cheerT: Float = 0
        var dryerOn = false
        var reduce = false
    }

    /// Window glow envelope: a bump on the bell, a gentle beat with the washing, a flicker with the dryer, bright when the door opens. 0...~1.
    static func pulse(_ s: FxState) -> Float {
        if s.reduce { return 0.2 }
        var p: Float = 0
        if s.phase == .arriveIn || s.phase == .shop {
            p += 0.9 * expf(-s.shopT * 3.0) * max(0, cosf(s.shopT * 9))                       // the bell
            p += 0.22 + 0.2 * sinf(s.time * 5.2) * (s.shopT > 0.8 ? 1 : 0)                  // the splashing
            if s.dryerOn { p += 0.12 * sinf(s.time * 23) }
        } else { p = 0.9 }
        return min(max(p, 0), 1.2)
    }

    static func fx(_ s: FxState) -> RoomMesh {
        let b = RoomMeshBuilder()
        let Z = frontZ
        let t = s.reduce ? 0 : s.time
        // the window glow
        b.material = .glow
        let p = pulse(s)
        discZ(b, windowC + V3(0, 0, 0.012), windowR, color: warm * (0.92 + 0.28 * p))
        discZ(b, windowC + V3(0, 0, 0.016), windowR * 0.55, color: c(1.0, 0.93, 0.74) * (0.9 + 0.5 * p))
        // the door (swings open on its left hinge toward the camera)
        b.material = .plain
        let nudge: Float = (s.phase == .shop || s.phase == .arriveIn) && !s.reduce ? 0.12 * expf(-s.shopT * 2.4) * max(0, sinf(s.shopT * 8)) : 0
        let open = s.reduce ? (s.doorOpen > 0.5 ? 1.75 : 0) : s.doorOpen * s.doorOpen * (3 - 2 * s.doorOpen) * 1.75 + nudge
        let hinge = V3(doorX - doorW, doorY, Z + 0.07)
        let from = b.mesh.vertices.count
        box(b, V3(doorX, doorY, Z + 0.07), V3(doorW - 0.02, doorH - 0.02, 0.06), r: 0.52, color: wood, seg: 4)
        box(b, V3(doorX, doorY + 0.35, Z + 0.135), V3(doorW - 0.2, doorH * 0.5, 0.012), r: 0.38, color: c(0.86, 0.74, 0.57), seg: 3)
        ParkShapes.ball(b, V3(doorX + 0.42, doorY - 0.05, Z + 0.15), 0.055, brass, segments: 8, rings: 4)
        rotate(b, from: from, pivot: hinge, axis: V3(0, 1, 0), angle: -open)

        // bubbles: a stream from the roof vent and a puff out of the door, all pure functions of time
        b.material = .glow
        let bub = c(0.97, 0.99, 1.0)
        func bubbles(_ n: Int, src: V3, rise: Float, spread: Float, size: Float, speed: Float) {
            for i in 0..<n {
                let f = Float(i)
                let ph = s.reduce ? (f + 1) / Float(n + 1) : fmodf(t * (speed + 0.012 * Float((i * 7) % 5)) + f * 0.37, 1)
                let x = src.x + sinf(t * 1.3 + f * 1.9) * spread * (s.reduce ? 0 : 1) + Float((i * 5) % 7 - 3) * spread * 0.25 + ph * spread * 0.8
                let y = src.y + ph * rise
                let sc = sinf(ph * .pi)
                let r = size * (0.55 + 0.1 * Float((i * 3) % 5)) * (0.25 + 0.75 * sc)
                ParkShapes.ball(b, V3(x, y, src.z + 0.04 * f), r, bub, segments: 8, rings: 4)
            }
        }
        bubbles(5, src: V3(2.1, 5.7, -5.9), rise: 3.0, spread: 0.4, size: 0.16, speed: 0.07)
        if s.phase == .shop || s.phase == .arriveIn || s.phase == .reveal {
            bubbles(4, src: V3(doorX, 0.7, Z + 0.55), rise: 1.7, spread: 0.5, size: 0.12, speed: 0.09)
        }
        // dryer steam from the left vent
        if s.dryerOn {
            let white = c(0.95, 0.96, 0.96)
            for i in 0..<5 {
                let ph = s.reduce ? Float(i) / 6 : fmodf(t * 0.22 + Float(i) * 0.2, 1)
                let r = 0.14 + 0.38 * ph
                ParkShapes.ball(b, V3(-2.0 - 0.5 * ph + sinf(t * 2 + Float(i)) * 0.06, 5.55 + 2.8 * ph, -5.9), r * (1 - 0.6 * ph * ph), white, segments: 8, rings: 4)
            }
        }
        // sparkles round the door once it opens
        if s.phase == .reveal || s.phase == .leaveOut {
            let k = s.phase == .leaveOut ? 1 : min(s.cheerT / 1.6, 1)
            for i in 0..<18 {
                let f = Float(i)
                let a = f * 2.399 + 0.4, ph = s.reduce ? 0.6 : fmodf(t * 0.7 + f * 0.173, 1)
                let rr = (0.5 + 1.6 * fmodf(f * 0.618, 1)) * (0.6 + 0.6 * ph)
                let pos = V3(doorX + cosf(a) * rr * 1.1, doorY + 0.6 + sinf(a) * rr * 0.9, Z + 1.0 + 0.04 * f)
                let sz = 0.2 * sinf(ph * .pi) * k * (i % 3 == 0 ? 1.3 : 0.8)
                if sz > 0.01 { star(b, pos, sz, color: i % 2 == 0 ? c(0.98, 0.92, 0.72) : white) }
            }
        }
        return b.mesh
    }
}
