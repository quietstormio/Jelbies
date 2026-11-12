//
//  ParkRoom.swift
//  The park as a visiting room (like the café's): a RoomDef applied with `RoomLayout.apply` under the white fade WITHOUT `store.moveIn`, so nothing is saved.
//  It is not in `RoomCatalog.all`. The scenery is built here in code (ParkScenery: a tessellated lawn, a gravel path, pond, bench, trees, shrubs and a sky pane that follows the
//  time of day; redesigned 2026-11-09 as a stylised-natural town park: see ParkNature.swift); the colliders below are the bench, the flower bed and the pond at the back. Also the park's camera: higher and further back than the room's, so
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

    /// Where the roam floor's front edge (x 0, z `parkRoamMaxZ`) sits on the screen, as a fraction of the screen height from the top, in every aspect (2026-11-09: the front third was bare lawn).
    /// (0.79 on a phone / tablet in portrait; 0.685 from a phone's landscape up (round 8 follow-up: at 0.73 the last three roam rows fell under the Go home + Play cut-out, whose top is at 72.3% of a phone's landscape height).)
    static func parkFrontFraction(aspect: Float) -> Float { 0.79 - 0.105 * poseBlend(aspect) }

    /// The park's landscape pull-in (fraction of the distance to the target removed) and elevation drop (radians), blended by `poseBlend`: exactly (0, 0) for every aspect <= 1.0 (a phone / tablet in
    /// portrait), full from 1.2 up. The phone's landscape floor (x +-4.05) filled a third of the width and the Jelbies were 0.8x their portrait size; this closes the lawn in on the short screen.
    static let parkLandscapePull: Float = 0.35
    static let parkLandscapeLower: Float = 12 * .pi / 180
    static func parkLandscapeFrame(aspect: Float) -> (pull: Float, lower: Float) {
        let w = poseBlend(aspect)
        return (parkLandscapePull * w, parkLandscapeLower * w)
    }
    /// The eye moved toward `target` by `pull` of its distance and rotated down by `lower` radians about the target (same side, same target).
    static func parkLandscapeEye(eye: SIMD3<Float>, target: SIMD3<Float>, pull: Float, lower: Float) -> SIMD3<Float> {
        let v = eye - target, h = sqrtf(v.x * v.x + v.z * v.z), d = simd_length(v) * (1 - pull), e = atan2f(v.y, h) - lower
        let hn = h > 1e-5 ? SIMD2<Float>(v.x, v.z) / h : SIMD2<Float>(0, 1)
        return target + SIMD3<Float>(hn.x * cosf(e) * d, sinf(e) * d, hn.y * cosf(e) * d)
    }

    /// The park pan: eye and target move together along the camera's own up vector (same elevation, same distance, so on-screen widths and the look do not change) by the amount that puts
    /// the front edge at `parkFrontFraction` of the screen height. Computed from the pose in use (`eye`, `target` after the portrait widening), so it is aspect-aware by construction.
    static func parkPan(aspect: Float) -> SIMD3<Float> {
        guard let zf = parkRoamMaxZ else { return .zero }
        let fw = simd_normalize(target - eye), rt = simd_normalize(simd_cross(fw, SIMD3<Float>(0, 1, 0))), up = simd_cross(rt, fw)
        let p = SIMD3<Float>(0, 0, zf) - eye
        let depth = simd_dot(p, fw), yc = simd_dot(p, up)
        let want = (1 - 2 * parkFrontFraction(aspect: aspect)) * depth * tanf(fovY / 2)
        return up * (yc - want)
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

        // ---- sky: a glow pane behind everything (its colours become the dawn / dusk / night sky through the room's daylight): clear blue, paler at the horizon ----
        b.material = .glow
        // (the glow pane is drawn at albedo x 1.25 ... 1.875 by height up to y 14, so the baked colours are the wanted sky divided by that)
        let lo = S.srgb(0.74, 0.87, 0.96) / 1.25, hi = S.srgb(0.30, 0.56, 0.90) / 1.875
        b.flatQuad(SIMD3(-70, 0, -9.6), SIMD3(70, 0, -9.6), SIMD3(70, 14, -9.6), SIMD3(-70, 14, -9.6), normal: SIMD3(0, 0, 1), colors: [lo, lo, hi, hi])
        b.flatQuad(SIMD3(-70, 14, -9.6), SIMD3(70, 14, -9.6), SIMD3(70, 30, -9.6), SIMD3(-70, 30, -9.6), normal: SIMD3(0, 0, 1), colors: [hi, hi, hi, hi])
        b.material = .plain

        // ---- distance: three overlapping ridges fading with haze, a few cumulus ----
        hills(b)
        clouds(b)

        // ---- the forest edge and the planted trees: natural greens, jittered spacing, gaps where the sky shows ----
        var shadows: [ParkShadow] = []
        let leaf = S.srgb(0.24, 0.45, 0.17), leaf2 = leaf, hazy = leaf, pine = leaf          // (round 8: one canopy colour; the assets carry the one green family)
        // far row: hazier, taller, mixed spruces / beeches / oaks / birches standing right behind the fence; sizes and gaps vary so the sky and haze show between crowns
        var tx: Float = -13.5
        var k = 0
        while tx <= 13.5 {
            let conifer = r.unit() < 0.32
            let rad = 1.35 + 0.9 * r.unit()
            let z = -8.5 - 0.5 * r.unit()
            if r.unit() > 0.22 { roundTree(b, x: tx, z: z, trunk: 0.8, radius: rad, canopy: conifer ? pine : hazy, shape: conifer ? .conifer : .round, species: k % 3, far: true, rng: &r) }
            tx += 3.0 + 2.2 * r.unit(); k += 1
        }
        // nearer row: oak / beech / birch mixed, leaving breaks
        tx = -13; k = 0
        while tx <= 13 {
            let conifer = r.unit() < 0.22
            let rad = 0.75 + 0.35 * r.unit()
            let x = tx + (r.unit() - 0.5) * 0.8, z = -7.3 + (r.unit() - 0.5) * 0.8
            if r.unit() > 0.15 {
                roundTree(b, x: x, z: z, trunk: 0.7, radius: rad, canopy: r.unit() < 0.5 ? leaf : leaf2, shape: conifer ? .conifer : .round, species: (k + Int(r.unit() * 2)) % 3, far: abs(x) > 3.2 || conifer, rng: &r)
                shadows.append(ParkShadow(x: x, z: z, r: 1.7 * rad, h: 3.4 * rad))
            }
            tx += 3.3 + 2.2 * r.unit(); k += 1
        }
        // three feature trees in the portrait window behind the fence so the tree line always reads: a beech, a birch, a far oak
        roundTree(b, x: 2.5, z: -7.7, trunk: 0.8, radius: 0.95, canopy: leaf, shape: .round, species: 1, far: false, rng: &r)
        roundTree(b, x: 5.3, z: -7.4, trunk: 0.8, radius: 1.0, canopy: leaf2, shape: .round, species: 2, far: false, rng: &r)
        roundTree(b, x: -0.2, z: -8.9, trunk: 0.8, radius: 1.0, canopy: hazy, shape: .round, species: 0, far: true, rng: &r)
        // two hero trees at the edges: a broad oak left, a beech right (full detail, standing on the lawn)
        roundTree(b, x: -6.4, z: -3.2, trunk: 1.0, radius: 1.0, canopy: leaf2, shape: .round, species: 0, far: false, rng: &r)
        shadows.append(ParkShadow(x: -6.4, z: -3.2, r: 2.4, h: 2.8))
        roundTree(b, x: 6.9, z: -1.4, trunk: 1.0, radius: 1.15, canopy: leaf, shape: .round, species: 1, far: false, rng: &r)
        shadows.append(ParkShadow(x: 6.9, z: -1.4, r: 2.1, h: 4.4))
        // a clipped hedge and a post-and-rail fence along the back of the lawn, in front of the tree line
        hedge(b, x: -2.4, z: -6.0, scale: 1.5, yaw: 0, rng: &r); hedge(b, x: 0.8, z: -6.05, scale: 1.5, yaw: 0, rng: &r)
        fence(b, z: -6.45, x0: -14, x1: 14, skip: -4.0...2.4)

        // ---- natural shrubs at the edges, a few garden-flower patches ----
        let white = S.srgb(0.95, 0.92, 0.82), gold = S.srgb(0.93, 0.86, 0.58), violet = S.srgb(0.74, 0.68, 0.84)          // (muted: cream, pale yellow, soft lavender)
        floweringBush(b, x: -3.7, z: -4.5, scale: 1.2, bloom: white, rng: &r); shadows.append(ParkShadow(x: -3.7, z: -4.5, r: 1.5, h: 1.2))
        floweringBush(b, x: -5.6, z: 1.6, scale: 1.0, bloom: gold, rng: &r); shadows.append(ParkShadow(x: -5.6, z: 1.6, r: 1.3, h: 1.1))
        floweringBush(b, x: 5.6, z: 3.4, scale: 1.0, bloom: violet, rng: &r); shadows.append(ParkShadow(x: 5.6, z: 3.4, r: 1.3, h: 1.1))
        floweringBush(b, x: -5.2, z: 6.4, scale: 0.9, bloom: white, rng: &r); shadows.append(ParkShadow(x: -5.2, z: 6.4, r: 1.2, h: 1.0))
        flowerPatch(b, x: 7.0, z: 0.4, scale: 0.8, bloom: white, rng: &r)          // (round 8: only along the edges, none by the hopscotch, slide or seesaw)
        flowerPatch(b, x: -7.0, z: 3.6, scale: 0.8, bloom: violet, rng: &r)

        // ---- the ground: a tessellated lawn that carries mowing bands, sun patches, soft tree shadows and worn earth; the gravel path ----
        lawn(b, shadows: shadows)
        gravelPath(b, rng: &r)

        // ---- the pond (right, at the back): irregular stones, deep teal water, reeds, lily pads ----
        pond(b, rng: &r)

        // ---- the entrance border below the roam floor's front edge ----
        entrance(b, rng: &r)

        // ---- the bench (back centre): timber slats on cast-iron frames, and a park lamp post beside it ----
        bench(b)
        lampPost(b, x: 1.72, z: -4.85)
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
