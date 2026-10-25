//
//  ParkRoom.swift
//  The park as a visiting room (like the café's): a RoomDef applied with `RoomLayout.apply` under the white fade WITHOUT `store.moveIn`, so nothing is saved.
//  It is not in `RoomCatalog.all`. The scenery is built here in code (ParkScenery: one even lawn, a gentle path, pond, bench, round trees, flowering bushes and a sky pane that follows the
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
        typealias S = ParkShapes

        // ---- sky: a glow pane behind everything (its colours become the dawn / dusk / night sky through the room's daylight) ----
        b.material = .glow
        let lo = S.srgb(0.78, 0.89, 0.97), hi = S.srgb(0.55, 0.77, 0.95)
        b.flatQuad(SIMD3(-70, 0, -9.6), SIMD3(70, 0, -9.6), SIMD3(70, 22, -9.6), SIMD3(-70, 22, -9.6), normal: SIMD3(0, 0, 1), colors: [lo, lo, hi, hi])

        // ---- the ground: ONE even lawn colour ----
        b.material = .plain
        let lawn = S.srgb(0.60, 0.80, 0.50)
        b.flatQuad(SIMD3(-70, 0, -9.5), SIMD3(70, 0, -9.5), SIMD3(70, 0, 45), SIMD3(-70, 0, 45), normal: SIMD3(0, 1, 0), colors: [lawn, lawn, lawn, lawn])
        // a gentle curved path from the front to the bench, one soft sand colour
        let pathCol = S.srgb(0.95, 0.89, 0.74)
        func px(_ zz: Float) -> Float { 0.7 * sinf(zz * 0.34) }
        var z: Float = 13
        while z > -3.7 {
            let z2 = z - 0.5, w: Float = 0.62
            b.flatQuad(SIMD3(px(z) - w, 0.012, z), SIMD3(px(z) + w, 0.012, z), SIMD3(px(z2) + w, 0.012, z2), SIMD3(px(z2) - w, 0.012, z2), normal: SIMD3(0, 1, 0), colors: [pathCol, pathCol, pathCol, pathCol])
            z = z2
        }

        // ---- a calm back: two soft hills and a tree line of smooth round canopies ----
        for (x, rx, ry) in [(-14 as Float, 14 as Float, 2.8 as Float), (14, 15, 3.2)] {
            blob(b, SIMD3(x, -0.5, -8.8), rx: rx, ry: ry, rz: 2.2, color: S.srgb(0.52, 0.74, 0.46), segments: 28, rings: 10)
        }
        let leaf = S.srgb(0.40, 0.68, 0.40), leaf2 = S.srgb(0.46, 0.72, 0.44)
        var tx: Float = -15
        var k = 0
        while tx <= 15 {
            roundTree(b, x: tx, z: -7.8, trunk: 0.7, radius: 1.7 + 0.25 * Float(k % 3), canopy: k % 2 == 0 ? leaf : leaf2, rng: &r)
            tx += 3.4; k += 1
        }
        // two hero trees at the edges (one soft blush)
        roundTree(b, x: -6.4, z: -3.2, trunk: 1.0, radius: 1.5, canopy: leaf2, rng: &r)
        roundTree(b, x: 6.8, z: -1.2, trunk: 1.0, radius: 1.4, canopy: S.srgb(0.97, 0.74, 0.80), rng: &r)

        // ---- flowering bushes at the edges, a couple of low blossom patches ----
        let blush = S.srgb(0.98, 0.72, 0.80), butter = S.srgb(0.99, 0.90, 0.55), cream = S.srgb(0.99, 0.96, 0.88), lilac = S.srgb(0.80, 0.70, 0.95)
        floweringBush(b, x: -3.5, z: -4.3, scale: 1.25, bloom: blush, rng: &r)
        floweringBush(b, x: -5.6, z: 1.6, scale: 1.0, bloom: butter, rng: &r)
        floweringBush(b, x: 5.6, z: 3.4, scale: 1.0, bloom: lilac, rng: &r)
        floweringBush(b, x: -5.2, z: 6.4, scale: 0.9, bloom: cream, rng: &r)
        flowerPatch(b, x: 4.3, z: -0.6, scale: 1.0, bloom: cream, rng: &r)
        flowerPatch(b, x: -3.6, z: 3.8, scale: 1.0, bloom: blush, rng: &r)

        // ---- the pond (right, at the back): a cream stone rim, soft water, a few lily pads ----
        let pond = pondCentre
        disc(b, cx: pond.x, cz: pond.y, radius: 1.42, y: 0.010, color: S.srgb(0.96, 0.92, 0.82))
        disc(b, cx: pond.x, cz: pond.y, radius: 1.24, y: 0.03, color: S.srgb(0.52, 0.80, 0.90))
        disc(b, cx: pond.x + 0.3, cz: pond.y + 0.2, radius: 0.55, y: 0.034, color: S.srgb(0.60, 0.85, 0.93))
        lilyPads(b, centre: pond, rng: &r)

        // ---- the bench (back centre): chunky, rounded, honey wood on cream legs ----
        let wood = S.srgb(0.94, 0.76, 0.44), leg = S.srgb(0.97, 0.93, 0.84)
        b.roundedBox(centre: SIMD3(0, 0.50, -4.48), half: SIMD3(1.28, 0.07, 0.30), radius: 0.06, segments: 3, aoFloor: false, color: wood)
        b.roundedBox(centre: SIMD3(0, 0.88, -4.80), half: SIMD3(1.28, 0.20, 0.06), radius: 0.06, segments: 3, aoFloor: false, color: wood)
        for sx: Float in [-1.08, 1.08] {
            b.roundedBox(centre: SIMD3(sx, 0.24, -4.50), half: SIMD3(0.10, 0.24, 0.26), radius: 0.08, segments: 3, aoFloor: false, color: leg)
            b.roundedBox(centre: SIMD3(sx, 0.62, -4.78), half: SIMD3(0.07, 0.40, 0.05), radius: 0.04, segments: 3, aoFloor: false, color: leg)
        }

        // ---- three soft clouds ----
        for (x, y, s) in [(-9 as Float, 11 as Float, 1.0 as Float), (8, 10, 1.2), (0, 13, 0.8)] {
            for k in 0..<3 {
                blob(b, SIMD3(x + Float(k - 1) * 1.6 * s, y + (k == 1 ? 0.5 : 0), -9.2), rx: 1.8 * s, ry: 0.7 * s, rz: 0.5, color: S.srgb(0.99, 0.99, 1.0), segments: 14, rings: 6)
            }
        }
        return b.mesh
    }

    // MARK: pieces

    /// A flat disc (a lawn patch, the water) just above the ground.
    static func disc(_ b: RoomMeshBuilder, cx: Float, cz: Float, radius R: Float, y: Float, color: SIMD3<Float>) {
        b.lathe(cx: cx, cz: cz, profile: [PP(r: 0, y: y, nr: 0, ny: 1), PP(r: R, y: y, nr: 0, ny: 1)], segments: 40, color: color)
    }

    /// An ellipsoid (a bush, a crown, a hill) centred at `c`; `rz` squashes it front to back by scaling the lathe's z about its centre.
    static func blob(_ b: RoomMeshBuilder, _ c: SIMD3<Float>, rx: Float, ry: Float, rz: Float, color: SIMD3<Float>, segments: Int, rings: Int) {
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
}
