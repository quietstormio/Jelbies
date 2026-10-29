//
//  VolleyScene.swift
//  The beach court as a visiting room (like the park's): a RoomDef applied under the white fade WITHOUT moving in, a camera behind the player's baseline looking
//  down the court at the net (the TV view: your two Jelbies' backs at the bottom of the screen, the opponents facing you across the net, the sea and the sky
//  beyond them), the scenery built in code (soft sand, a lighter court with lines, the net, a sea and a sky, a few props), and the ball (a beach ball with a soft
//  shadow on the sand) rebuilt every frame as the "animating decor". On the screen: up = +x (toward the net), right = +z.
//

import simd
import Foundation

extension RoomCatalog {
    static let beach = RoomDef(
        id: .beach, title: "Beach", blurb: "A sandy court with a net and the sea behind.",
        theme: RoomTheme(tint: SIMD3(0.90, 0.80, 0.60), chromaScale: 0.7, lightnessShift: 0.03),
        couch: .init(centre: SIMD3(0, 0.45, -40), halfExtents: SIMD3(1.35, 0.45, 0.35), radius: 0.15), boxes: [],
        cylinders: [],
        lampTable: .init(centre: SIMD2(30, -40), radius: 1.0, height: 0.3), lamp: SIMD3(0, 1.5, -40),
        windows: RoomWindows(xs: [], halfW: 0, y0: 0, y1: 14, proceduralFrames: false),
        floor: .chevron, wall: .plain, rug: .rings, art: nil)
}

extension GameCamera {
    nonisolated(unsafe) static var beachOn = false
    /// A gentle sideways drift of the view toward the action (world z, which is the screen's right; a few centimetres; zero with Reduce Motion).
    nonisolated(unsafe) static var beachNudge: Float = 0
    /// The view looks down the court (+x) from behind the human baseline, this far above the sand.
    static let beachElevation: Float = 50 * .pi / 180
    /// Where your Jelbies' feet sit on the screen (NDC y: 0 centre, -1 bottom) in a portrait phone and on its side.
    static let beachFeetNDC: (portrait: Float, landscape: Float) = (-0.50, -0.62)
    /// What the frame must hold: half the width at your baseline (two Jelbies, their reach and a ball going out, with a TV-broadcast margin), the nearest the eye may come in a portrait phone
    /// (the size of the Jelbies on the screen), and the ball's highest point over the far baseline.
    static let beachHalfWidth: Float = 1.9, beachMinDist: Float = 0, beachFarX: Float = 3.4, beachBallTop: Float = 3.8, beachTopNDC: Float = 0.80

    /// Eye / target for the court: the whole court (and the sky the ball climbs into) fits the width of a portrait phone and the height of a landscape one, with your
    /// Jelbies' feet at `beachFeetNDC` (the target is slid along x until they are; it stays on the sand).
    static func beachPose(aspect: Float) -> (eye: SIMD3<Float>, target: SIMD3<Float>) {
        let th = tanf(fovY / 2), e = beachElevation
        let se = sinf(e), ce = cosf(e)
        let portrait = portraitAmount(aspect)
        let yN = beachFeetNDC.portrait * portrait + beachFeetNDC.landscape * (1 - portrait)
        let px = VolleyTuning.startX[0]          // (the near Jelbie's resting spot)
        // the target is `s` ahead of the feet along x; the feet land at yN when s = k * dist
        let k = yN * th / (se - yN * th * ce)
        let distW = beachHalfWidth / (th * max(aspect, 0.2) * 0.78 * (1 + k * ce))
        // the ball's top over the far baseline stays under beachTopNDC
        let qx = beachFarX - px
        let A = qx * se + beachBallTop * ce, B = qx * ce - beachBallTop * se
        let q = k * se - beachTopNDC * th * (k * ce + 1)
        let distH = q < -1e-4 ? (beachTopNDC * th * B - A) / q : 0
        let dist = max(distW, distH, beachMinDist * portrait)
        let t = SIMD3<Float>(px - k * dist, 0, 0)
        let dir = SIMD3<Float>(-ce, se, 0)
        let shift = SIMD3<Float>(0, 0, beachNudge)
        return (t + dir * dist + shift, t + shift)
    }

    static func configureBeach() {
        roamFloor = nil; RoomLayout.setFront(z: RoomLayout.maxZ)
        roomWideScale = 1; roomWideLift = 0
        walkMaxZ = 4.5; arenaCenter = SIMD2(0, 0); arenaRadius = 80
        beachOn = true
    }
    static func endBeach(count: Int) {
        beachOn = false
        configureRoom(count: count)
    }
}

enum BeachScenery {
    typealias PP = RoomMeshBuilder.ProfilePoint
    typealias V3 = SIMD3<Float>
    static func c(_ r: Float, _ g: Float, _ b: Float) -> V3 { ParkShapes.srgb(r, g, b) }

    /// Where the sea's near edge (the foam) and far edge (the sky wall) stand along x. The sky stands close behind the foam: from a camera 50 degrees up the horizon
    /// has to fall inside the frame for the sea and the sky to show at all.
    static let seaNear0: Float = 5.0, seaEnd: Float = 8.4

    static func build(theme: RoomTheme) -> RoomMesh {
        let b = RoomMeshBuilder()
        var rng = ParkRandom(0xBEAC)

        // the view looks down the court (+x): the sea and the sky are beyond the opponents' baseline. `at` turns an old side-view spot (x right, z toward the viewer)
        // into this one (x toward the far end, z right).
        func at(_ x: Float, _ z: Float) -> (x: Float, z: Float) { (-z, x) }
        // sky (a glow pane, so dusk and night come for free)
        b.material = .glow
        let lo = V3(0.62, 0.80, 0.92), hi = V3(0.22, 0.52, 0.88)
        b.flatQuad(V3(seaEnd, 0, -160), V3(seaEnd, 0, 160), V3(seaEnd, 46, 160), V3(seaEnd, 46, -160), normal: V3(-1, 0, 0), colors: [lo, lo, hi, hi])

        b.material = .plain
        // the sea (far) with a foam line, wet sand, the dry sand (the sea ends where the sky stands: no gap to show the clear colour)
        let seaFar = c(0.16, 0.52, 0.70), seaNear = c(0.30, 0.74, 0.78)
        b.flatQuad(V3(seaEnd, 0, -160), V3(seaEnd, 0, 160), V3(seaNear0, 0, 160), V3(seaNear0, 0, -160), normal: V3(0, 1, 0), colors: [seaFar, seaFar, seaNear, seaNear])
        let foam = c(0.96, 0.98, 0.98)
        b.flatQuad(V3(seaNear0 - 0.4, 0.004, -160), V3(seaNear0 - 0.4, 0.004, 160), V3(seaNear0 + 0.3, 0.004, 160), V3(seaNear0 + 0.3, 0.004, -160), normal: V3(0, 1, 0), colors: [foam, foam, foam, foam])
        let sandFar = c(0.86, 0.74, 0.52), sandNear = c(0.93, 0.82, 0.60)
        b.flatQuad(V3(seaNear0, 0.002, -160), V3(seaNear0, 0.002, 160), V3(-60, 0.002, 160), V3(-60, 0.002, -160), normal: V3(0, 1, 0), colors: [sandFar, sandFar, sandNear, sandNear])
        let wet = c(0.74, 0.62, 0.42)
        b.flatQuad(V3(seaNear0 - 0.3, 0.003, -160), V3(seaNear0 - 0.3, 0.003, 160), V3(seaNear0 - 1.0, 0.003, 160), V3(seaNear0 - 1.0, 0.003, -160), normal: V3(0, 1, 0), colors: [wet, wet, wet, wet])
        // soft ripples in the sand (behind your baseline and beyond theirs)
        for k in 0..<39 {
            let row = k / 13
            let x: Float = row < 2 ? -(3.2 + Float(row) * 3.4 + rng.unit() * 2) : 4.4 + rng.unit() * 2.2
            let z = -14 + Float(k % 13) * 2.3 + rng.unit()
            ParkScenery.disc(b, cx: x, cz: z, radius: 0.5 + rng.unit() * 0.6, y: 0.006, color: c(0.90, 0.79, 0.57))
        }
        // the court: a firmer, lighter sand with white lines
        let court = c(0.97, 0.88, 0.66)
        b.flatQuad(V3(-3.4, 0.008, -1.9), V3(3.4, 0.008, -1.9), V3(3.4, 0.008, 1.9), V3(-3.4, 0.008, 1.9), normal: V3(0, 1, 0), colors: [court, court, court, court])
        let line = c(1.0, 0.99, 0.96)
        func strip(_ x0: Float, _ z0: Float, _ x1: Float, _ z1: Float) {
            b.flatQuad(V3(x0, 0.012, z0), V3(x1, 0.012, z0), V3(x1, 0.012, z1), V3(x0, 0.012, z1), normal: V3(0, 1, 0), colors: [line, line, line, line])
        }
        let lx: Float = 2.95, lz: Float = 1.55, w: Float = 0.035
        strip(-lx - w, -lz - w, lx + w, -lz + w); strip(-lx - w, lz - w, lx + w, lz + w)
        strip(-lx - w, -lz - w, -lx + w, lz + w); strip(lx - w, -lz - w, lx + w, lz + w)
        strip(-w, -lz, w, lz)

        // the net
        let pole = c(0.95, 0.94, 0.90), tape = c(0.99, 0.99, 0.99), stripe = c(0.95, 0.42, 0.40), mesh = c(0.86, 0.90, 0.94)
        let nd = VolleyTuning.netDepth, top = VolleyTuning.netTop
        for s: Float in [-1, 1] {
            b.lathe(cx: 0, cz: s * (nd + 0.05), profile: [PP(r: 0.0, y: 0.0, nr: 0, ny: -1), PP(r: 0.10, y: 0.0, nr: 1, ny: 0), PP(r: 0.07, y: 0.12, nr: 1, ny: 0.4), PP(r: 0.055, y: 0.3, nr: 1, ny: 0),
                                                         PP(r: 0.05, y: top + 0.1, nr: 1, ny: 0.2), PP(r: 0.0, y: top + 0.16, nr: 0, ny: 1)], segments: 12, color: pole)
        }
        b.roundedBox(centre: V3(0, top, 0), half: V3(0.03, 0.045, nd), radius: 0.025, segments: 2, aoFloor: false, color: tape)
        for k in 0..<5 { b.roundedBox(centre: V3(0.0, top - 0.05, -nd + 0.15 + Float(k) * (2 * nd - 0.3) / 4), half: V3(0.032, 0.02, 0.07), radius: 0.015, segments: 2, aoFloor: false, color: stripe) }
        b.roundedBox(centre: V3(0, 0.86, 0), half: V3(0.015, 0.015, nd), radius: 0.01, segments: 2, aoFloor: false, color: mesh)
        for k in 0..<7 { b.roundedBox(centre: V3(0, 0.98 + Float(k) * 0.11, 0), half: V3(0.008, 0.007, nd), radius: 0.006, segments: 1, aoFloor: false, color: mesh) }
        var z = -nd + 0.1
        while z < nd { b.roundedBox(centre: V3(0, 1.29, z), half: V3(0.008, 0.43, 0.007), radius: 0.006, segments: 1, aoFloor: false, color: mesh); z += 0.14 }

        // props, kept inside what the camera shows: a palm either side of the far baseline, an umbrella and towel, a sandcastle, a bucket, shells
        for (x, zz, h, lean) in [(4.0 as Float, -4.6 as Float, 4.6 as Float, 0.3 as Float), (4.2, 4.8, 5.4, -0.25)] { palm(b, x: x, z: zz, height: h, lean: lean, rng: &rng) }
        umbrella(b, x: 3.6, z: -3.4)
        b.flatQuad(V3(1.4, 0.014, -3.6), V3(2.7, 0.014, -3.6), V3(3.9, 0.014, -2.6), V3(2.6, 0.014, -2.6), normal: V3(0, 1, 0), colors: [c(0.96, 0.52, 0.55), c(0.96, 0.52, 0.55), c(0.99, 0.93, 0.80), c(0.99, 0.93, 0.80)])
        sandcastle(b, x: 4.3, z: 3.0)
        // a bucket
        b.lathe(cx: 3.3, cz: 2.8, profile: [PP(r: 0.0, y: 0.0, nr: 0, ny: -1), PP(r: 0.17, y: 0.0, nr: 1, ny: 0), PP(r: 0.23, y: 0.30, nr: 1, ny: 0), PP(r: 0.20, y: 0.30, nr: -1, ny: 0.3), PP(r: 0.0, y: 0.26, nr: 0, ny: 1)], segments: 16, color: c(0.35, 0.66, 0.90))
        for k in 0..<7 {
            ParkScenery.blob(b, V3(-3.0 + rng.unit() * 7.5, 0.03, -3.6 + Float(k) * 1.2 + rng.unit() * 0.5), rx: 0.11, ry: 0.06, rz: 0.1, color: c(0.99, 0.82 - 0.2 * rng.unit(), 0.78), segments: 8, rings: 4)
        }
        // clouds (low over the horizon: the camera looks down, so the sky is a band of the wall, and the top of it is under the score pill)
        for (z, y, s) in [(-3.4 as Float, 0.9 as Float, 0.45 as Float), (3.2, 1.2, 0.5)] {
            for k in 0..<3 { ParkScenery.blob(b, V3(seaEnd - 0.4, y + (k == 1 ? 0.2 : 0), z + Float(k - 1) * 0.9 * s), rx: 0.3, ry: 0.32 * s, rz: 0.9 * s, color: c(0.99, 0.99, 1.0), segments: 10, rings: 5) }
        }
        return b.mesh
    }

    static func palm(_ b: RoomMeshBuilder, x: Float, z: Float, height: Float, lean: Float, rng: inout ParkRandom) {
        var prof: [PP] = []
        let n = 8
        // a gently bending trunk, built as stacked frusta along a lean
        var prev = V3(x, 0, z)
        for k in 0..<n {
            let t0 = Float(k) / Float(n), t1 = Float(k + 1) / Float(n)
            let r0 = 0.20 - 0.09 * t0, r1 = 0.20 - 0.09 * t1
            let p0 = V3(x + lean * t0 * t0 * height * 0.5, t0 * height, z), p1 = V3(x + lean * t1 * t1 * height * 0.5, t1 * height, z)
            _ = prev
            let first = b.mesh.vertices.count
            b.lathe(cx: 0, cz: 0, profile: [PP(r: r0, y: 0, nr: 1, ny: 0), PP(r: r1, y: p1.y - p0.y, nr: 1, ny: 0)], segments: 10, color: c(0.58 - 0.05 * Float(k % 2), 0.42, 0.28))
            for i in first..<b.mesh.vertices.count { b.mesh.vertices[i].pos.x += p0.x; b.mesh.vertices[i].pos.y += p0.y; b.mesh.vertices[i].pos.z += p0.z }
            prev = p1
        }
        _ = prof; prof = []
        for k in 0..<8 {
            let az = Float(k) / 8 * 2 * .pi + rng.unit() * 0.3
            b.leaf(base: prev, azimuth: az, length: 2.3 + rng.unit() * 0.5, width: 0.7, lean: 1.2 + rng.unit() * 0.3, colorBase: c(0.20, 0.50, 0.22), colorTip: c(0.42, 0.74, 0.34))
        }
        ParkScenery.blob(b, prev + V3(0.1, -0.15, 0), rx: 0.16, ry: 0.16, rz: 0.16, color: c(0.45, 0.30, 0.18), segments: 8, rings: 4)
    }

    static func umbrella(_ b: RoomMeshBuilder, x: Float, z: Float) {
        b.lathe(cx: x, cz: z, profile: [PP(r: 0.03, y: 0, nr: 1, ny: 0), PP(r: 0.03, y: 2.3, nr: 1, ny: 0)], segments: 8, color: c(0.96, 0.94, 0.88))
        let n = 10
        for k in 0..<n {
            // alternating wedges of the canopy
            let a0 = Float(k) / Float(n) * 2 * .pi, a1 = Float(k + 1) / Float(n) * 2 * .pi
            let col = k % 2 == 0 ? c(0.96, 0.46, 0.50) : c(0.99, 0.96, 0.92)
            let ctr = b.vertex(V3(x, 2.65, z), V3(0, 1, 0), color: col)
            let v0 = b.vertex(V3(x + 1.45 * cosf(a0), 2.15, z + 1.45 * sinf(a0)), simd_normalize(V3(0.5 * cosf(a0), 1, 0.5 * sinf(a0))), color: col)
            let v1 = b.vertex(V3(x + 1.45 * cosf(a1), 2.15, z + 1.45 * sinf(a1)), simd_normalize(V3(0.5 * cosf(a1), 1, 0.5 * sinf(a1))), color: col)
            b.triangle(ctr, v1, v0)
        }
    }

    static func sandcastle(_ b: RoomMeshBuilder, x: Float, z: Float) {
        let sand = c(0.88, 0.72, 0.46)
        b.roundedBox(centre: V3(x, 0.22, z), half: V3(0.62, 0.22, 0.42), radius: 0.12, segments: 3, aoFloor: false, color: sand)
        for (dx, dz) in [(-0.5 as Float, -0.3 as Float), (0.5, -0.3), (-0.5, 0.3), (0.5, 0.3)] {
            b.lathe(cx: x + dx, cz: z + dz, profile: [PP(r: 0.17, y: 0.3, nr: 1, ny: 0), PP(r: 0.15, y: 0.62, nr: 1, ny: 0), PP(r: 0.0, y: 0.82, nr: 0.4, ny: 1)], segments: 10, color: sand)
        }
        b.roundedBox(centre: V3(x, 0.55, z), half: V3(0.28, 0.16, 0.2), radius: 0.08, segments: 3, aoFloor: false, color: sand)
        b.roundedBox(centre: V3(x, 0.92, z), half: V3(0.012, 0.16, 0.012), radius: 0.008, segments: 1, aoFloor: false, color: c(0.9, 0.9, 0.85))
        b.flatQuad(V3(x, 1.0, z), V3(x + 0.22, 0.94, z), V3(x + 0.22, 0.86, z), V3(x, 0.9, z), normal: V3(0, 0, 1), colors: [c(0.96, 0.4, 0.4), c(0.96, 0.4, 0.4), c(0.96, 0.4, 0.4), c(0.96, 0.4, 0.4)])
    }
}

/// The beach ball and its shadow, rebuilt every frame.
enum VolleyBallMesh {
    typealias V3 = SIMD3<Float>
    typealias PP = RoomMeshBuilder.ProfilePoint
    static let panels: [V3] = [ParkShapes.srgb(0.96, 0.40, 0.42), ParkShapes.srgb(0.99, 0.98, 0.95), ParkShapes.srgb(0.28, 0.62, 0.95), ParkShapes.srgb(0.99, 0.98, 0.95),
                               ParkShapes.srgb(1.00, 0.82, 0.28), ParkShapes.srgb(0.99, 0.98, 0.95)]

    static func build(centre: V3, spin: Float, squash: V3 = V3(1, 1, 1)) -> RoomMesh {
        let b = RoomMeshBuilder()
        b.material = .plain
        let R = VolleyTuning.ballR
        let rings = 9, segs = 18
        let cs = cosf(spin), sn = sinf(spin)
        var rows: [[UInt32]] = []
        for i in 0...rings {
            let lat = -Float.pi / 2 + Float.pi * Float(i) / Float(rings)
            var row: [UInt32] = []
            for j in 0...segs {
                let lon = Float(j) / Float(segs) * 2 * .pi
                // the panels run pole to pole around the spin axis (z): the direction in the ball's own frame
                let d = V3(cosf(lat) * cosf(lon), sinf(lat), cosf(lat) * sinf(lon))
                let col = abs(lat) > 1.30 ? panels[1] : panels[(j * 6 / max(segs, 1)) % 6]
                let rx = d.x * cs - d.y * sn, ry = d.x * sn + d.y * cs
                let n = V3(rx, ry, d.z)
                let p = centre + V3(n.x * squash.x, n.y * squash.y, n.z * squash.z) * R
                row.append(b.vertex(p, n, ao: 1, color: col))
            }
            rows.append(row)
        }
        for i in 0..<rings { for j in 0..<segs { b.quad(rows[i][j], rows[i][j + 1], rows[i + 1][j + 1], rows[i + 1][j]) } }
        return b.mesh
    }

    /// A soft dark disc on the sand under the ball: smaller and darker the closer the ball is.
    static func shadow(x: Float, z: Float = VolleyTuning.ballZ, height: Float, into b: RoomMeshBuilder) {
        b.material = .plain
        let k = min(1, max(0, height / 4))
        let r = VolleyTuning.ballR * (1.45 - 0.45 * k)          // (a little wider and darker than the side view needed: from behind it is how you judge where the ball lands)
        let col = ParkShapes.srgb(0.50 + 0.20 * k, 0.40 + 0.20 * k, 0.26 + 0.16 * k)
        ParkScenery.disc(b, cx: x, cz: z, radius: r * 1.5, y: 0.02, color: simd_mix(col, ParkShapes.srgb(0.84, 0.72, 0.50), SIMD3(repeating: 0.5)))
        ParkScenery.disc(b, cx: x, cz: z, radius: r, y: 0.024, color: col)
    }

    /// A flat ring on the sand (an annulus of quads).
    static func annulus(_ b: RoomMeshBuilder, cx: Float, cz: Float, r0: Float, r1: Float, y: Float, color: V3, segs: Int = 28) {
        b.material = .plain
        for k in 0..<segs {
            let a0 = Float(k) / Float(segs) * 2 * .pi, a1 = Float(k + 1) / Float(segs) * 2 * .pi
            let p0 = V3(cx + r0 * cosf(a0), y, cz + r0 * sinf(a0)), p1 = V3(cx + r1 * cosf(a0), y, cz + r1 * sinf(a0))
            let p2 = V3(cx + r1 * cosf(a1), y, cz + r1 * sinf(a1)), p3 = V3(cx + r0 * cosf(a1), y, cz + r0 * sinf(a1))
            b.flatQuad(p0, p1, p2, p3, normal: V3(0, 1, 0), colors: [color, color, color, color])
        }
    }

    /// Where the ball will land, and the ring that shrinks onto it as the ball falls: tap when the ring meets the marker. Gold in the Perfect window.
    static func timingRing(_ r: VolleyRing, time: Float, into b: RoomMeshBuilder) {
        let e = r.tau - r.lead
        let inPerfect = abs(e) <= r.perfect, inGood = abs(e) <= r.good
        let late = e < -r.good
        ParkScenery.disc(b, cx: r.x, cz: r.z, radius: 0.30, y: 0.03, color: ParkShapes.srgb(0.50, 0.66, 0.78))   // your side's marker is cool blue
        annulus(b, cx: r.x, cz: r.z, r0: 0.27, r1: 0.31, y: 0.034, color: ParkShapes.srgb(1.0, 0.99, 0.95))
        let k = min(1, max(0, e / 1.1))
        let rad = 0.31 + 0.95 * k          // the ring's inner edge meets the marker's rim exactly at the ideal moment
        let col: V3 = inPerfect ? ParkShapes.srgb(1.0, 0.80, 0.18) : late ? ParkShapes.srgb(0.95, 0.48, 0.44) : inGood ? ParkShapes.srgb(0.99, 0.96, 0.78) : ParkShapes.srgb(1.0, 1.0, 1.0)
        let w: Float = inPerfect ? 0.085 : 0.05
        annulus(b, cx: r.x, cz: r.z, r0: rad, r1: rad + w, y: 0.038, color: col, segs: 36)
    }

    /// A fading string of small balls behind a fast ball.
    static func trail(_ pts: [SIMD3<Float>], into b: RoomMeshBuilder) {
        b.material = .plain
        for (k, p) in pts.enumerated() {
            let f = Float(k + 1) / Float(pts.count + 1)
            b.roundedBox(centre: p, half: SIMD3(repeating: VolleyTuning.ballR * (0.25 + 0.5 * f)), radius: VolleyTuning.ballR * 0.2, segments: 2, aoFloor: false,
                         color: simd_mix(ParkShapes.srgb(0.62, 0.80, 0.96), ParkShapes.srgb(1, 1, 1), SIMD3(repeating: f)))
        }
    }

    /// A puff of sand: a few soft discs that widen and sink as it ages (0...1).
    static func puff(x: Float, z: Float, age: Float, size: Float, into b: RoomMeshBuilder) {
        b.material = .plain
        let a = min(1, max(0, age))
        let col = simd_mix(ParkShapes.srgb(0.98, 0.90, 0.70), ParkShapes.srgb(0.90, 0.78, 0.55), SIMD3(repeating: a))
        for k in 0..<4 {
            let ang = Float(k) * 1.57 + size * 3
            let r = size * (0.15 + 0.5 * a)
            ParkScenery.disc(b, cx: x + cosf(ang) * r, cz: z + sinf(ang) * r * 0.7, radius: size * 0.22 * (1 - 0.6 * a), y: 0.04 + 0.28 * size * (1 - a) * (1 - a) * 0.0 + 0.10 * size * (1 - a), color: col)
        }
    }

    /// The ring at the feet of the Jelbie you steer, and a bobbing arrow over his head.
    static func controlMark(x: Float, z: Float, top: Float, time: Float, into b: RoomMeshBuilder) {
        let col = ParkShapes.srgb(0.28, 0.78, 0.96)
        let pulse = 0.04 * sinf(time * 5)
        annulus(b, cx: x, cz: z, r0: 0.66 + pulse, r1: 0.74 + pulse, y: 0.045, color: col)
        b.material = .plain
        let first = b.mesh.vertices.count
        b.lathe(cx: 0, cz: 0, profile: [PP(r: 0.0, y: 0.0, nr: 0, ny: -1), PP(r: 0.13, y: 0.24, nr: 1, ny: 0.3), PP(r: 0.0, y: 0.24, nr: 0, ny: 1)], segments: 10, color: col)
        let dy = top + 0.42 + 0.06 * sinf(time * 5)
        for i in first..<b.mesh.vertices.count { b.mesh.vertices[i].pos.x += x; b.mesh.vertices[i].pos.y += dy; b.mesh.vertices[i].pos.z += z }
    }

    static func frame(ball: VolleyBall) -> RoomMesh {
        let sb = RoomMeshBuilder()
        shadow(x: ball.pos.x, z: ball.z, height: ball.pos.y, into: sb)
        var m = build(centre: V3(ball.pos.x, ball.pos.y, ball.z), spin: ball.spin)
        let off = UInt32(sb.mesh.vertices.count)
        sb.mesh.vertices.append(contentsOf: m.vertices)
        sb.mesh.indices.append(contentsOf: m.indices.map { $0 + off })
        m = RoomMesh()
        return sb.mesh
    }
}
