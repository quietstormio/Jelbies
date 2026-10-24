//
//  ParkRoom.swift
//  The park as a visiting room (like the café's): a RoomDef applied with `RoomLayout.apply` under the white fade WITHOUT `store.moveIn`, so nothing is saved.
//  It is not in `RoomCatalog.all`. The scenery is built here in code (ParkScenery: lawn, path, pond, flower bed, bench, trees, hills and a sky pane that follows the
//  time of day); the colliders below are the bench, the flower bed and the pond at the back. Also the park's camera: higher and further back than the room's, so
//  five Jelbies fit in portrait and landscape.
//

import simd
import Foundation

extension RoomCatalog {
    static let park = RoomDef(
        id: .park, title: "Park", blurb: "A lawn, a pond and a bench to play on.",
        theme: RoomTheme(tint: SIMD3(0.56, 0.74, 0.44), chromaScale: 0.7, lightnessShift: 0.02),
        couch: .init(centre: SIMD3(0, 0.45, -4.55), halfExtents: SIMD3(1.35, 0.45, 0.35), radius: 0.15),
        boxes: [.init(centre: SIMD3(-3.5, 0.25, -4.35), halfExtents: SIMD3(1.1, 0.25, 0.55), radius: 0.2)],
        cylinders: [.init(centre: SIMD2(3.5, -4.2), radius: 1.0, height: 0.3)],
        lampTable: .init(centre: SIMD2(3.5, -4.2), radius: 1.0, height: 0.3), lamp: SIMD3(0, 1.5, -40),
        windows: RoomWindows(xs: [], halfW: 0, y0: 0, y1: 14, proceduralFrames: false),
        floor: .chevron, wall: .plain, rug: .rings, art: nil)
}

extension GameCamera {
    /// The play zone's depth: the roaming floor is cut here so five Jelbies stay near each other on a tall portrait screen.
    nonisolated(unsafe) static var parkRoamMaxZ: Float?
    static let parkLookZ: Float = 1.0

    /// The park's pose: the 3-Jelbie room pose pushed out another ~15% and raised 8 degrees; the portrait widening applies on top as in the room.
    static func configurePark() {
        roamFloor = nil; RoomLayout.setFront(z: RoomLayout.maxZ)
        let v = baseEye - baseTarget, L = simd_length(v), e = atan2f(v.y, v.z) + 8 * .pi / 180
        let t = SIMD3<Float>(0, 0, parkLookZ)
        let p = t + SIMD3<Float>(0, sinf(e), cosf(e)) * (L * 1.38)
        eye = p; target = t; roomEye = p; roomTarget = t
        roomWideScale = wideScale(2); roomWideLift = wideLift(2)
        walkMaxZ = 4.5; arenaCenter = SIMD2(0, 0.2); arenaRadius = 6.5
        roamRect = (SIMD2(-3.5, -3.4), SIMD2(3.5, 4.5)); roamRectWide = (SIMD2(-4.2, -3.6), SIMD2(4.2, 4.5))
        parkRoamMaxZ = 4.5
    }

    /// Back to the room's camera and floor for `count` Jelbies (what the stage set up at launch).
    static func endPark(count: Int) {
        parkRoamMaxZ = nil
        configureRoom(count: count)
    }
}

/// The park's meshes. Colours are linear and flat (the room's `plain` material), lit by the room's key light and the time of day; the sky is the room's glow pane,
/// so the dusk / night sky and the stars come for free.
enum ParkScenery {
    typealias PP = RoomMeshBuilder.ProfilePoint
    /// The pond's centre (x, z): the park's cylinder collider.
    static let pondCentre = SIMD2<Float>(3.5, -4.2)

    static func build(theme: RoomTheme) -> RoomMesh {
        let b = RoomMeshBuilder()
        var r = ParkRandom(0x7A11)

        // ---- sky: a glow pane behind everything (its colours become the dawn / dusk / night sky through the room's daylight) ----
        b.material = .glow
        let lo = SIMD3<Float>(0.40, 0.60, 0.76), hi = SIMD3<Float>(0.15, 0.38, 0.76)
        b.flatQuad(SIMD3(-70, 0, -9.6), SIMD3(70, 0, -9.6), SIMD3(70, 22, -9.6), SIMD3(-70, 22, -9.6), normal: SIMD3(0, 0, 1), colors: [lo, lo, hi, hi])

        // ---- the ground: one big quad that darkens towards the horizon, then lighter lawn patches and the path ----
        b.material = .plain
        let far = SIMD3<Float>(0.06, 0.19, 0.05), near = SIMD3<Float>(0.11, 0.29, 0.07)
        b.flatQuad(SIMD3(-70, 0, -9.5), SIMD3(70, 0, -9.5), SIMD3(70, 0, 45), SIMD3(-70, 0, 45), normal: SIMD3(0, 1, 0), colors: [far, far, near, near])
        disc(b, cx: 0, cz: 0.5, radius: 7.6, y: 0.006, color: SIMD3(0.14, 0.35, 0.08))
        disc(b, cx: -7.5, cz: 2.5, radius: 4.2, y: 0.010, color: SIMD3(0.13, 0.33, 0.08))
        disc(b, cx: 7.8, cz: 4.0, radius: 3.8, y: 0.010, color: SIMD3(0.15, 0.37, 0.09))
        disc(b, cx: 0, cz: 0.5, radius: 4.6, y: 0.014, color: SIMD3(0.16, 0.38, 0.09))
        // a sandy path from the front to the bench
        let pathCol = SIMD3<Float>(0.55, 0.42, 0.26)
        var z: Float = 13
        while z > -3.5 {
            let z2 = z - 0.5
            func px(_ zz: Float) -> Float { 1.1 * sinf(zz * 0.42) }
            let w: Float = 0.8 + 0.12 * sinf(z * 1.3)
            let c = pathCol * (0.94 + 0.06 * Float(Int(z * 2) & 1))
            b.flatQuad(SIMD3(px(z) - w, 0.02, z), SIMD3(px(z) + w, 0.02, z), SIMD3(px(z2) + w, 0.02, z2), SIMD3(px(z2) - w, 0.02, z2), normal: SIMD3(0, 1, 0), colors: [c, c, c, c])
            z = z2
        }

        // ---- hills and the tree line (in front of the sky) ----
        for (x, rx, ry) in [(-15 as Float, 13 as Float, 3.4 as Float), (1, 15, 2.6), (16, 13, 3.8)] {
            blob(b, SIMD3(x, -0.4, -8.6), rx: rx, ry: ry, rz: 2.2, color: SIMD3(0.05, 0.17, 0.07), segments: 20, rings: 8)
        }
        for x in stride(from: Float(-16), through: 16, by: 3.4) {
            tree(b, x: x + r.unit() * 1.4, z: -7.6 - r.unit() * 0.8, height: 5.4 + r.unit() * 2.2, scale: 1.1 + r.unit() * 0.4, rng: &r)
        }
        // nearer trees behind the bench and around the lawn
        for (x, zz, h) in [(-5.6 as Float, -6.0 as Float, 4.6 as Float), (5.9, -6.2, 5.0), (-7.4, -2.2, 4.4), (7.8, -1.5, 4.8), (-9.0, 3.0, 4.2), (9.4, 4.5, 4.6),
                           (-12.0, -3.5, 5.6), (12.5, -4.0, 5.4), (-13.0, 4.5, 4.8), (13.5, 1.5, 4.4)] {
            tree(b, x: x, z: zz, height: h, scale: 1.0 + r.unit() * 0.25, rng: &r)
        }
        // bushes
        for (x, zz, s) in [(-5.9 as Float, 0.5 as Float, 0.8 as Float), (6.1, -0.2, 0.9), (-6.3, 5.5, 0.7), (6.4, 7.0, 0.8), (-2.6, -5.9, 0.9), (2.4, -6.0, 0.8), (-8.6, 7.0, 0.9), (9.0, 8.5, 1.0)] {
            bush(b, x: x, z: zz, scale: s, rng: &r)
        }

        // ---- the pond (right, at the back) ----
        let pond = pondCentre
        disc(b, cx: pond.x, cz: pond.y, radius: 1.5, y: 0.012, color: SIMD3(0.30, 0.22, 0.12))          // the muddy edge
        disc(b, cx: pond.x, cz: pond.y, radius: 1.22, y: 0.03, color: SIMD3(0.18, 0.42, 0.60))
        disc(b, cx: pond.x + 0.35, cz: pond.y + 0.2, radius: 0.55, y: 0.034, color: SIMD3(0.22, 0.50, 0.68))
        for k in 0..<16 {
            let a = Float(k) / 16 * 2 * .pi + r.unit() * 0.15
            let rr: Float = 1.38 + r.unit() * 0.08
            blob(b, SIMD3(pond.x + rr * cosf(a), 0.05, pond.y + rr * sinf(a)), rx: 0.2 + r.unit() * 0.06, ry: 0.13, rz: 0.2, color: SIMD3(0.40, 0.38, 0.35) * (0.85 + 0.3 * r.unit()), segments: 8, rings: 4)
        }
        disc(b, cx: pond.x - 0.4, cz: pond.y + 0.35, radius: 0.22, y: 0.04, color: SIMD3(0.12, 0.34, 0.08))          // lily pads
        disc(b, cx: pond.x + 0.2, cz: pond.y - 0.45, radius: 0.18, y: 0.04, color: SIMD3(0.14, 0.38, 0.09))
        // reeds
        for k in 0..<6 {
            let a = 2.3 + Float(k) * 0.16
            let rr: Float = 1.5
            let base = SIMD3<Float>(pond.x + rr * cosf(a), 0, pond.y + rr * sinf(a) - 0.1)
            b.lathe(cx: base.x, cz: base.z, profile: [PP(r: 0.03, y: 0, nr: 1, ny: 0), PP(r: 0.02, y: 0.8 + 0.2 * r.unit(), nr: 1, ny: 0.2), PP(r: 0, y: 0.95 + 0.2 * r.unit(), nr: 0, ny: 1)],
                     segments: 5, color: SIMD3(0.16, 0.34, 0.10))
        }

        // ---- the flower bed (left, at the back) ----
        let bed = SIMD3<Float>(-3.5, 0, -4.35)
        b.roundedBox(centre: SIMD3(bed.x, 0.12, bed.z), half: SIMD3(1.1, 0.12, 0.55), radius: 0.1, segments: 3, aoFloor: false, color: SIMD3(0.20, 0.11, 0.06))
        let petals: [SIMD3<Float>] = [SIMD3(0.80, 0.18, 0.32), SIMD3(0.92, 0.70, 0.10), SIMD3(0.85, 0.84, 0.78), SIMD3(0.50, 0.24, 0.72), SIMD3(0.95, 0.40, 0.12)]
        for i in 0..<6 {
            for j in 0..<3 {
                let fx = bed.x - 0.9 + Float(i) * 0.36 + (r.unit() - 0.5) * 0.12, fz = bed.z - 0.36 + Float(j) * 0.36 + (r.unit() - 0.5) * 0.1
                let h = 0.22 + r.unit() * 0.2
                b.lathe(cx: fx, cz: fz, profile: [PP(r: 0.016, y: 0.22, nr: 1, ny: 0), PP(r: 0.012, y: 0.24 + h, nr: 1, ny: 0)], segments: 4, color: SIMD3(0.12, 0.30, 0.08))
                blob(b, SIMD3(fx, 0.26 + h, fz), rx: 0.09, ry: 0.07, rz: 0.09, color: petals[(i + j * 2) % petals.count], segments: 7, rings: 4)
                blob(b, SIMD3(fx, 0.29 + h, fz), rx: 0.03, ry: 0.03, rz: 0.03, color: SIMD3(0.9, 0.7, 0.1), segments: 5, rings: 3)
            }
        }
        // a few wild flowers on the lawn
        for _ in 0..<26 {
            let a = r.unit() * 2 * .pi, rr = 5.2 + r.unit() * 3.4
            let fx = rr * cosf(a) * 1.3, fz = 1.0 + rr * sinf(a) * 0.9
            if abs(fx) < 5.1, fz < 6 { continue }
            blob(b, SIMD3(fx, 0.08, fz), rx: 0.07, ry: 0.06, rz: 0.07, color: petals[Int(r.next() % UInt64(petals.count))], segments: 6, rings: 3)
        }

        // ---- the bench (back centre) ----
        let wood = SIMD3<Float>(0.36, 0.20, 0.09), iron = SIMD3<Float>(0.07, 0.07, 0.08)
        b.roundedBox(centre: SIMD3(0, 0.47, -4.48), half: SIMD3(1.28, 0.04, 0.27), radius: 0.03, segments: 2, aoFloor: false, color: wood)
        b.roundedBox(centre: SIMD3(0, 0.86, -4.78), half: SIMD3(1.28, 0.2, 0.035), radius: 0.03, segments: 2, aoFloor: false, color: wood)
        b.roundedBox(centre: SIMD3(0, 0.62, -4.78), half: SIMD3(1.28, 0.04, 0.03), radius: 0.02, segments: 2, aoFloor: false, color: wood)
        for sx: Float in [-1.12, 1.12] {
            b.roundedBox(centre: SIMD3(sx, 0.23, -4.40), half: SIMD3(0.035, 0.23, 0.04), radius: 0.02, segments: 2, aoFloor: false, color: iron)
            b.roundedBox(centre: SIMD3(sx, 0.40, -4.62), half: SIMD3(0.035, 0.40, 0.04), radius: 0.02, segments: 2, aoFloor: false, color: iron)
            b.roundedBox(centre: SIMD3(sx, 0.66, -4.55), half: SIMD3(0.04, 0.03, 0.25), radius: 0.02, segments: 2, aoFloor: false, color: iron)
        }

        // ---- a few clouds ----
        for (x, y, s) in [(-9 as Float, 11 as Float, 1.0 as Float), (7, 9.5, 1.3), (-1, 13, 0.9), (13, 12, 1.1)] {
            for k in 0..<3 {
                blob(b, SIMD3(x + Float(k - 1) * 1.6 * s, y + (k == 1 ? 0.5 : 0), -9.2), rx: 1.8 * s, ry: 0.7 * s, rz: 0.5, color: SIMD3(0.85, 0.88, 0.90), segments: 10, rings: 5)
            }
        }
        return b.mesh
    }

    // MARK: pieces

    /// A flat disc (a lawn patch, the water) just above the ground.
    private static func disc(_ b: RoomMeshBuilder, cx: Float, cz: Float, radius R: Float, y: Float, color: SIMD3<Float>) {
        b.lathe(cx: cx, cz: cz, profile: [PP(r: 0, y: y, nr: 0, ny: 1), PP(r: R, y: y, nr: 0, ny: 1)], segments: 40, color: color)
    }

    /// An ellipsoid (a bush, a crown, a hill) centred at `c`; `rz` squashes it front to back by scaling the lathe's z about its centre.
    private static func blob(_ b: RoomMeshBuilder, _ c: SIMD3<Float>, rx: Float, ry: Float, rz: Float, color: SIMD3<Float>, segments: Int, rings: Int) {
        var prof: [PP] = []
        for k in 0...rings {
            let a = -Float.pi / 2 + Float.pi * Float(k) / Float(rings)
            let n = simd_normalize(SIMD2<Float>(cosf(a) / rx, sinf(a) / ry))
            prof.append(PP(r: rx * cosf(a), y: c.y + ry * sinf(a), nr: n.x, ny: n.y, ao: 0.7 + 0.3 * Float(k) / Float(rings)))
        }
        let first = b.mesh.vertices.count
        b.lathe(cx: c.x, cz: c.z, profile: prof, segments: segments, color: color)
        if abs(rz - rx) > 0.001 {
            let k = rz / rx
            for i in first..<b.mesh.vertices.count {
                b.mesh.vertices[i].pos.z = c.z + (b.mesh.vertices[i].pos.z - c.z) * k
            }
        }
    }

    private static func bush(_ b: RoomMeshBuilder, x: Float, z: Float, scale s: Float, rng r: inout ParkRandom) {
        let g = [SIMD3<Float>(0.08, 0.26, 0.07), SIMD3<Float>(0.11, 0.31, 0.08), SIMD3<Float>(0.14, 0.35, 0.10)]
        blob(b, SIMD3(x, 0.45 * s, z), rx: 0.95 * s, ry: 0.62 * s, rz: 0.85 * s, color: g[Int(r.next() % 3)], segments: 12, rings: 6)
        blob(b, SIMD3(x + 0.55 * s, 0.35 * s, z + 0.15 * s), rx: 0.6 * s, ry: 0.45 * s, rz: 0.55 * s, color: g[Int(r.next() % 3)], segments: 10, rings: 5)
    }

    private static func tree(_ b: RoomMeshBuilder, x: Float, z: Float, height h: Float, scale s: Float, rng r: inout ParkRandom) {
        b.lathe(cx: x, cz: z, profile: [PP(r: 0.34 * s, y: 0, nr: 1, ny: 0, ao: 0.6), PP(r: 0.26 * s, y: h * 0.25, nr: 1, ny: 0.05), PP(r: 0.20 * s, y: h * 0.55, nr: 1, ny: 0.05)],
                 segments: 10, color: SIMD3(0.20, 0.11, 0.06))
        let g = [SIMD3<Float>(0.07, 0.24, 0.06), SIMD3<Float>(0.10, 0.30, 0.07), SIMD3<Float>(0.13, 0.34, 0.09)]
        blob(b, SIMD3(x, h * 0.62, z), rx: 1.7 * s, ry: 1.4 * s, rz: 1.6 * s, color: g[Int(r.next() % 3)], segments: 14, rings: 7)
        blob(b, SIMD3(x - 0.9 * s, h * 0.52, z + 0.3 * s), rx: 1.2 * s, ry: 1.0 * s, rz: 1.1 * s, color: g[Int(r.next() % 3)], segments: 12, rings: 6)
        blob(b, SIMD3(x + 0.8 * s, h * 0.55, z - 0.2 * s), rx: 1.2 * s, ry: 1.0 * s, rz: 1.1 * s, color: g[Int(r.next() % 3)], segments: 12, rings: 6)
        blob(b, SIMD3(x + 0.1 * s, h * 0.86, z), rx: 1.1 * s, ry: 0.9 * s, rz: 1.0 * s, color: g[Int(r.next() % 3)], segments: 12, rings: 6)
    }
}
