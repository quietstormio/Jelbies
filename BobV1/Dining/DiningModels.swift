//
//  DiningModels.swift
//  The little serving TRAY and everything on it, built with RoomMeshBuilder in the room's soft rounded style: tray (short legs, raised
//  rim, two end handles, lighter top), plate + berries, cake + one fork per Blob, a plastic water bottle / a contour soda bottle (open necks), and one bendy
//  striped straw per Blob. Group meshes are built once in TRAY-LOCAL space (origin: floor under the tray centre, +z toward the camera)
//  and placed with a transform at draw time. N = number of Blobs (1...3); the serving scales 1.0 / 1.15 / 1.3.
//

import simd
import Foundation

/// Dimensions (world units; Bob is ~1.35 tall, base disc ~0.84 wide, widest ~1.4; his rest nub is a 0.15-radius ball centred at
/// (+-0.55, 0.46, 0.06), so its underside is at 0.31 and a forward pitch of ~25 degrees plus a small crouch brings it below the tray top).
nonisolated enum DiningDims {
    static let trayTop: Float = 0.25
    static let trayRim: Float = 0.04
    static let plateRadius: Float = 0.27
    static var plateFloorY: Float { trayTop + 0.024 }
    static let strawRadius: Float = 0.035
    /// Mouth anchor of a Blob standing at a place, leaning very slightly forward (finger / fork foods; a sip aims at the STRAW TIP instead).
    static let mouthHeight: Float = 0.64
    static let mouthForward: Float = 0.62
    /// Where his rest mouth is relative to his stand (the shader draws it on the front surface at y 0.665): the straw tips for N >= 2 sit
    /// `sipForward` in front of it, at that height.
    static var mouthRestForward: Float { DineGeometry.mouthRest.z }
    static let mouthRestHeight: Float = 0.665
    static let sipForward: Float = 0.03
    /// Vertical stretch of both bottles (1 = the full specified profiles; 0.48 leaves a visible slanted straw above the neck at his mouth height).
    static let bottleY: Float = 0.48
    /// N = 1 straw: ONE straight straw slanted out of the neck toward him (about 25-35 degrees from vertical), tip at this height and
    /// `sipForward` in front of his rest mouth. The bottle neck stands `strawLean` behind the tip (horizontal), so the lean follows from the
    /// bottle's height: water about 30 degrees, soda about 34.
    static let strawTipHeight: Float = 0.73
    /// Sideways: the neck stands this far to his RIGHT (-x, screen-left from the game camera) of the tip, and `strawBack` toward the camera so
    /// the bottle clears his belly, so the straw leans up and ACROSS (25-35 degrees, mostly in the screen plane) into his mouth.
    static let strawSide: Float = 0.12
    static let strawBack: Float = 0.05
    /// Floor radius one Blob needs at a place.
    static let standRadius: Float = 0.55
    /// Head-top height for the on-screen checks.
    static let headTop: Float = 1.4
    /// How far from his centre (floor distance) the stubby nub reaches by turning and leaning alone: the nearest piece must be inside it.
    static let reach: Float = 0.60
    /// The fork's grip point may sit a little farther (he leans in over it).
    static let forkReach: Float = 0.65
    /// Horizontal spacing of the berries of one Blob (centre to centre; a berry is 0.13 wide).
    static let berrySpacing: Float = 0.13
}

/// A place around the tray: where a Blob stands (relative to the tray centre) and which way he faces (yaw 0 = toward the camera, +z;
/// facing = (sin yaw, cos yaw)).
nonisolated struct TrayPlace: Equatable {
    var rel: SIMD2<Float>
    var yaw: Float
}

nonisolated struct TrayLayout {
    var n: Int
    var scale: Float
    var half: SIMD2<Float>                  // tray half extents (x, z) incl. rim
    var places: [TrayPlace]
    var colliderHalf: SIMD2<Float>
    /// Plate angle (rad, xz plane) of each place's berry group (ring layout, n >= 2).
    var berryAngles: [Float]
    /// One Blob: his three berries sit on an arc of this radius around his stand, in front of him, so ALL of them are the same distance away.
    var berryArcRadius: Float? = nil
    /// Where the drink container stands on the tray (tray-local xz): one Blob: to his right and a little toward the camera of the point 0.03 in front of his rest mouth, so his slanted straw runs up and across from the neck to it.
    var drinkCentre: SIMD2<Float> = .zero
    /// The tray mesh is shifted this far along z (one Blob: the tray is shorter on his side, so his belly clears it) and has no rim on his side.
    var trayCentreZ: Float = 0
    var openFront: Bool = false

    func mouthRel(_ i: Int) -> SIMD3<Float> {
        let p = places[i]
        return SIMD3(p.rel.x + sinf(p.yaw) * DiningDims.mouthForward, DiningDims.mouthHeight, p.rel.y + cosf(p.yaw) * DiningDims.mouthForward)
    }
    /// Where place `i`'s Blob has his mouth when standing at rest (tray-local), and where his straw tip sits for N >= 2 (a hair in front of it).
    func restMouthRel(_ i: Int) -> SIMD3<Float> {
        let p = places[i]
        return SIMD3(p.rel.x + sinf(p.yaw) * DiningDims.mouthRestForward, DiningDims.mouthRestHeight, p.rel.y + cosf(p.yaw) * DiningDims.mouthRestForward)
    }
    func sipTipXZ(_ i: Int) -> SIMD2<Float> {
        let p = places[i], r = DiningDims.mouthRestForward + DiningDims.sipForward
        return SIMD2(p.rel.x + sinf(p.yaw) * r, p.rel.y + cosf(p.yaw) * r)
    }
    /// Bounds of the whole set relative to the tray centre, stands included.
    var bounds: (minX: Float, maxX: Float, minZ: Float, maxZ: Float) {
        var x0 = -half.x - 0.18, x1 = half.x + 0.18, z0 = -half.y, z1 = half.y
        for p in places {
            x0 = min(x0, p.rel.x - DiningDims.standRadius); x1 = max(x1, p.rel.x + DiningDims.standRadius)
            z0 = min(z0, p.rel.y - DiningDims.standRadius); z1 = max(z1, p.rel.y + DiningDims.standRadius)
        }
        return (x0, x1, z0, z1)
    }
}

nonisolated enum DiningLayout {
    static func make(n n0: Int) -> TrayLayout {
        let n = min(max(n0, 1), 3), s = DiningTiming.servingScale(n: n)
        switch n {
        case 1:
            // He stands 0.735 behind the tray centre; the tray spans z -0.32 ... +0.36 (shifted 0.02, no rim on his side) so his REAL skin
            // (belly front -0.296 at rim height) clears the bed by >= 0.01. His three berries
            // are all 0.595 from him, the collider is a thin bar (FlatBox rounds by 0.04) so boxDistance(stand) = 0.695 >= his 0.69 footprint.
            return TrayLayout(n: 1, scale: s, half: SIMD2(0.78, 0.34), places: [TrayPlace(rel: SIMD2(0, -0.735), yaw: 0)],
                              colliderHalf: SIMD2(0.42, 0.04), berryAngles: [-.pi / 2], berryArcRadius: 0.595, drinkCentre: SIMD2(-DiningDims.strawSide, -0.735 + DiningDims.mouthRestForward + DiningDims.sipForward + DiningDims.strawBack), trayCentreZ: 0.02, openFront: true)
        case 2:
            // 17 % wider than before (0.95 -> 1.11); the stands move out with it and back to clear the near rim by his real belly
            return TrayLayout(n: 2, scale: s, half: SIMD2(1.11, 0.46),
                              places: [TrayPlace(rel: SIMD2(-0.93, -0.96), yaw: 0.32), TrayPlace(rel: SIMD2(0.93, -0.96), yaw: -0.32)],
                              colliderHalf: SIMD2(0.5, 0.26), berryAngles: [.pi, 0])
        default:
            // 17.6 % wider than before (0.85 -> 1.00). All three Blobs now stand in a row on the far side of the wide tray (the portrait
            // screen cannot hold stands beside it), 1.11 apart, so no belly hangs over a corner: each clears the near rim by his real skin.
            return TrayLayout(n: 3, scale: s, half: SIMD2(1.0, 0.6),
                              places: [TrayPlace(rel: SIMD2(0, -1.07), yaw: 0), TrayPlace(rel: SIMD2(-1.11, -1.07), yaw: 0.25),
                                       TrayPlace(rel: SIMD2(1.11, -1.07), yaw: -0.25)],
                              colliderHalf: SIMD2(0.55, 0.3), berryAngles: [-.pi / 2, 150 * .pi / 180, 30 * .pi / 180])
        }
    }
}

nonisolated enum DiningModels {
    typealias PP = RoomMeshBuilder.ProfilePoint

    // MARK: Helpers

    /// Ellipsoid of revolution about y (soft low-poly sphere when rx == ry).
    static func ellipsoid(_ b: RoomMeshBuilder, centre c: SIMD3<Float>, rx: Float, ry: Float, color: SIMD3<Float>,
                          rings: Int = 6, segments: Int = 12, ao: Float = 1) {
        var prof: [PP] = []
        for k in 0...rings {
            let phi = -Float.pi / 2 + Float(k) / Float(rings) * .pi
            let n = simd_normalize(SIMD2<Float>(cosf(phi) / rx, sinf(phi) / ry))
            prof.append(PP(r: rx * cosf(phi), y: c.y + ry * sinf(phi), nr: n.x, ny: n.y, ao: ao))
        }
        b.lathe(cx: c.x, cz: c.z, profile: prof, segments: segments, color: color)
    }

    static func profile(_ pts: [(r: Float, y: Float, ao: Float)]) -> [PP] {
        var out: [PP] = []
        for i in 0..<pts.count {
            let a = pts[max(i - 1, 0)], c = pts[min(i + 1, pts.count - 1)]
            let t = SIMD2<Float>(c.r - a.r, c.y - a.y)
            let n = simd_normalize(SIMD2<Float>(t.y, -t.x))
            out.append(PP(r: pts[i].r, y: pts[i].y, nr: n.x, ny: n.y, ao: pts[i].ao))
        }
        return out
    }

    /// Convex polygon extruded between y0 and y1 with a rounded (quarter circle) bevel top and bottom and soft averaged side normals.
    static func extrudeRounded(_ b: RoomMeshBuilder, poly: [SIMD2<Float>], y0: Float, y1: Float, bevel bv: Float, color: SIMD3<Float>, ao: Float = 1) {
        let n = poly.count
        guard n >= 3 else { return }
        let c = poly.reduce(SIMD2<Float>.zero, +) / Float(n)
        let outs = poly.map { simd_normalize($0 - c) }
        let bev = min(bv, (y1 - y0) * 0.45)
        let steps = 3
        var rows: [[UInt32]] = []
        func ring(inset: Float, y: Float, nOut: Float, nUp: Float) {
            var r: [UInt32] = []
            for i in 0..<n {
                let p = poly[i] - outs[i] * inset
                let nn = simd_normalize(SIMD3<Float>(outs[i].x * nOut, nUp, outs[i].y * nOut))
                r.append(b.vertex(SIMD3(p.x, y, p.y), nn, ao: ao, color: color))
            }
            rows.append(r)
        }
        for k in 0...steps {                                   // bottom bevel
            let th = Float(k) / Float(steps) * .pi / 2
            ring(inset: bev * (1 - sinf(th)), y: y0 + bev * (1 - cosf(th)), nOut: sinf(th), nUp: -cosf(th))
        }
        for k in (0...steps).reversed() {                      // top bevel
            let th = Float(k) / Float(steps) * .pi / 2
            ring(inset: bev * (1 - sinf(th)), y: y1 - bev * (1 - cosf(th)), nOut: sinf(th), nUp: cosf(th))
        }
        for r in 0..<(rows.count - 1) {
            for i in 0..<n { b.quad(rows[r][i], rows[r][(i + 1) % n], rows[r + 1][(i + 1) % n], rows[r + 1][i]) }
        }
        for (rowIdx, up) in [(0, Float(-1)), (rows.count - 1, Float(1))] {
            let y = rowIdx == 0 ? y0 : y1
            let cv = b.vertex(SIMD3(c.x, y, c.y), SIMD3(0, up, 0), ao: ao, color: color)
            for i in 0..<n { b.triangle(cv, rows[rowIdx][i], rows[rowIdx][(i + 1) % n]) }
        }
    }

    /// Appends a mesh transformed by `t` (uniform scale + rotation + translation). Normals use the rotation part.
    static func append(_ m: RoomMesh, to b: RoomMeshBuilder, transform t: simd_float4x4, alpha: Float? = nil) {
        let base = UInt32(b.mesh.vertices.count)
        let r0 = SIMD3(t.columns.0.x, t.columns.0.y, t.columns.0.z), r1 = SIMD3(t.columns.1.x, t.columns.1.y, t.columns.1.z)
        let r2 = SIMD3(t.columns.2.x, t.columns.2.y, t.columns.2.z)
        let s = max(simd_length(r0), 1e-6)
        let n0 = r0 / s, n1 = r1 / s, n2 = r2 / s
        b.mesh.vertices.reserveCapacity(b.mesh.vertices.count + m.vertices.count)
        for v in m.vertices {
            let p = t * SIMD4(v.pos.x, v.pos.y, v.pos.z, 1)
            let n = n0 * v.normal.x + n1 * v.normal.y + n2 * v.normal.z
            var c = v.color
            if let a = alpha { c.w *= a }
            b.mesh.vertices.append(RoomVertex(pos: SIMD4(p.x, p.y, p.z, v.pos.w), normal: SIMD4(n, v.normal.w), color: c))
        }
        b.mesh.indices.reserveCapacity(b.mesh.indices.count + m.indices.count)
        for i in m.indices { b.mesh.indices.append(i + base) }
    }

    static func translation(_ p: SIMD3<Float>, scale s: Float = 1, yaw: Float = 0) -> simd_float4x4 {
        let c = cosf(yaw) * s, sn = sinf(yaw) * s
        return simd_float4x4(columns: (SIMD4(c, 0, -sn, 0), SIMD4(0, s, 0, 0), SIMD4(sn, 0, c, 0), SIMD4(p.x, p.y, p.z, 1)))
    }


    // MARK: Layout of things on the tray (tray-local coordinates) - the motion phase aims at these

    /// Resting centre of berry `j` (0...2) of place `i`.
    static func berryAnchor(layout L: TrayLayout, place i: Int, index j: Int) -> SIMD3<Float> {
        let s = L.scale
        if let R = L.berryArcRadius {
            let p = L.places[i], a = p.yaw + Float(j - 1) * DiningDims.berrySpacing * s / R
            return SIMD3(p.rel.x + sinf(a) * R, DiningDims.plateFloorY + 0.058 * s, p.rel.y + cosf(a) * R)
        }
        let ring = (0.125 + 0.065 * Float(L.n - 1))
        let step = 2 * Float.pi / Float(3 * L.n)
        let a = L.berryAngles[i] + Float(j - 1) * step
        return SIMD3(cosf(a) * ring, DiningDims.plateFloorY + 0.058 * s, sinf(a) * ring)
    }

    /// Where a fork lies on the tray for place `i` (tray-local position + yaw; tines point along (sin yaw, cos yaw)): beside the plate,
    /// on the side nearest the place, clear of the plate and inside the rim.
    static func forkRest(layout L: TrayLayout, place i: Int) -> (pos: SIMD3<Float>, yaw: Float) {
        let y = DiningDims.trayTop + 0.018
        switch (L.n, i) {
        case (1, _): return (SIMD3(0.36, y, -0.2), .pi / 2)               // beside the plate, tines out toward the right handle, grip 0.645 from him
        case (2, 0): return (SIMD3(-0.64, y, -0.02), 0)
        case (2, _): return (SIMD3(0.64, y, -0.02), 0)
        case (_, 0): return (SIMD3(0, y, -0.46), .pi / 2)
        case (_, 1): return (SIMD3(-0.6, y, 0.0), 0)
        default: return (SIMD3(0.6, y, 0.0), 0)
        }
    }

    // MARK: Tray (origin: floor under the centre)

    static func tray(layout L: TrayLayout, theme: RoomTheme) -> RoomMesh {
        let sw = theme.swatches, b = RoomMeshBuilder()
        b.material = .plain
        let D = DiningDims.self, hx = L.half.x, hz = L.half.y
        // short rounded legs
        b.color = sw[RoomSwatch.tableLeg]
        for sx in [Float(-1), 1] { for sz in [Float(-1), 1] {
            b.roundedBox(centre: SIMD3(sx * (hx - 0.16), 0.1, sz * (hz - 0.12)), half: SIMD3(0.055, 0.1, 0.055), radius: 0.04, segments: 2)
        } }
        // bed (room shade), lighter top panel, raised rim, two end handles
        b.color = sw[2]
        b.roundedBox(centre: SIMD3(0, D.trayTop - 0.04, 0), half: SIMD3(hx, 0.04, hz), radius: 0.035, segments: 3, aoFloor: false)
        b.color = sw[4] * 0.97
        b.roundedBox(centre: SIMD3(0, D.trayTop - 0.01, 0), half: SIMD3(hx - 0.07, 0.012, hz - 0.07), radius: 0.011, segments: 2, aoFloor: false)   // top panel: 2 mm proud of the bed
        b.color = sw[3]
        let ry = D.trayTop + D.trayRim / 2 - 0.008
        for sz in [Float(-1), 1] where !(L.openFront && sz < 0) {
            b.roundedBox(centre: SIMD3(0, ry, sz * (hz - 0.032)), half: SIMD3(hx, D.trayRim / 2 + 0.004, 0.032), radius: 0.028, segments: 2, aoFloor: false)
        }
        for sx in [Float(-1), 1] {
            b.roundedBox(centre: SIMD3(sx * (hx - 0.032), ry, 0), half: SIMD3(0.032, D.trayRim / 2 + 0.004, hz - 0.03), radius: 0.028, segments: 2, aoFloor: false)
            b.color = sw[2]
            b.roundedBox(centre: SIMD3(sx * (hx + 0.085), D.trayTop - 0.035, 0), half: SIMD3(0.1, 0.03, 0.12), radius: 0.03, segments: 3, aoFloor: false)
            b.color = sw[3]
        }
        var m = b.mesh
        if L.trayCentreZ != 0 { for i in m.vertices.indices { m.vertices[i].pos.z += L.trayCentreZ } }
        return m
    }

    static func plate(layout L: TrayLayout, theme: RoomTheme) -> RoomMesh {
        let sw = theme.swatches, b = RoomMeshBuilder()
        b.material = .plain
        let R = DiningDims.plateRadius * L.scale, y = DiningDims.plateFloorY, s = L.scale
        let pts: [(r: Float, y: Float, ao: Float)] = [
            (0, y - 0.004, 0.9), (R * 0.62, y - 0.004, 0.95), (R * 0.82, y + 0.008 * s, 1), (R * 0.95, y + 0.026 * s, 1),
            (R, y + 0.034 * s, 1), (R * 0.985, y + 0.026 * s, 1), (R * 0.9, y - 0.004, 0.8), (R * 0.7, y - 0.022, 0.6), (R * 0.55, y - 0.022, 0.5)]
        b.lathe(cx: 0, cz: 0, profile: profile(pts), segments: 36, color: sw[4] * 1.08)
        return b.mesh
    }

    // MARK: Foods (tray-local; shared serving scaled for N)

    static func berries(_ b: RoomMeshBuilder, state st: ServingState, palette p: ConsumablePalette, layout L: TrayLayout) {
        let cols = [p.primary, p.secondary, p.accent]
        for i in 0..<L.n {
            let eaten = DiningTiming.bitesPerServing - st.bitesLeft[i]
            for j in 0..<3 where j >= eaten && !st.skipped.contains(i * 3 + j) {
                berry(b, centre: berryAnchor(layout: L, place: i, index: j), color: cols[(j + i) % 3], leaf: p.detail, scale: L.scale)
            }
        }
    }

    /// One berry centred on `c` with a little leaf cap.
    static func berry(_ b: RoomMeshBuilder, centre c: SIMD3<Float>, color: SIMD3<Float>, leaf: SIMD3<Float>, scale s: Float = 1) {
        ellipsoid(b, centre: c, rx: 0.065 * s, ry: 0.06 * s, color: color, rings: 6, segments: 12, ao: 1)
        ellipsoid(b, centre: c + SIMD3(0, 0.054 * s, 0), rx: 0.032 * s, ry: 0.013 * s, color: leaf, rings: 3, segments: 8)
    }

    /// Standalone berry for a held item (centred on the origin).
    static func heldBerry(color i: Int, scale s: Float) -> RoomMesh {
        let b = RoomMeshBuilder(); b.material = .plain
        let p = Consumables.berries.palette
        berry(b, centre: .zero, color: [p.primary, p.secondary, p.accent][i % 3], leaf: p.detail, scale: s)
        return b.mesh
    }

    static func cakePolygon(radius R: Float, halfAngle half: Float, grow g: Float = 1) -> [SIMD2<Float>] {
        var pts: [SIMD2<Float>] = [SIMD2(0, 0)]
        for j in 0...8 {
            let a = -half + Float(j) / 8 * 2 * half
            pts.append(SIMD2(sinf(a), cosf(a)) * R)
        }
        return pts.map { $0 * g }
    }

    /// ONE bigger layered cake (sponge / cream / sponge / frosting + a berry) for N Blobs; it shrinks with every forkful taken.
    static func cake(_ b: RoomMeshBuilder, state st: ServingState, palette p: ConsumablePalette, layout L: TrayLayout) {
        let total = st.totalLeft
        guard total > 0 else { return }
        let frac = Float(total) / Float(DiningTiming.bitesPerServing * L.n)
        let k = 0.4 + 0.6 * frac
        let half = [Float(28), 40, 52][L.n - 1] * .pi / 180
        let R = 0.3 * L.scale * k
        let y = DiningDims.plateFloorY
        let off = SIMD2<Float>(0, -0.14 * L.scale)                                     // apex toward the far side, arc toward the camera
        func shifted(_ poly: [SIMD2<Float>]) -> [SIMD2<Float>] { poly.map { $0 + off } }
        let layers: [(Float, Float, SIMD3<Float>, Float)] = [
            (0.004, 0.054, p.primary, 1.0), (0.054, 0.074, p.detail, 1.035), (0.074, 0.124, p.primary, 1.0), (0.124, 0.152, p.secondary, 1.035)]
        for l in layers {
            extrudeRounded(b, poly: shifted(cakePolygon(radius: R, halfAngle: half, grow: l.3)), y0: y + l.0 * L.scale, y1: y + l.1 * L.scale,
                           bevel: 0.016 * L.scale, color: l.2)
        }
        let mid = SIMD2<Float>(0, 0.55 * R) + off
        ellipsoid(b, centre: SIMD3(mid.x, y + 0.152 * L.scale + 0.03 * L.scale, mid.y), rx: 0.042 * L.scale, ry: 0.04 * L.scale, color: p.accent, rings: 5, segments: 10)
    }

    /// A little cake chunk (the bite on the fork tines).
    static func cakeBite(_ b: RoomMeshBuilder, centre c: SIMD3<Float>) {
        let p = Consumables.cake.palette
        b.roundedBox(centre: c, half: SIMD3(0.04, 0.026, 0.045), radius: 0.02, segments: 2, aoFloor: false, color: p.primary)
        b.roundedBox(centre: c + SIMD3(0, 0.03, 0), half: SIMD3(0.04, 0.012, 0.045), radius: 0.011, segments: 2, aoFloor: false, color: p.secondary)
    }

    // MARK: Fork (origin: grip point on the handle; tines toward +z, flat in the xz plane)

    static func fork(withBite: Bool) -> RoomMesh {
        let b = RoomMeshBuilder(); b.material = .plain
        let metal = SIMD3<Float>(0.62, 0.64, 0.70)
        b.color = metal
        b.roundedBox(centre: SIMD3(0, 0, 0.01), half: SIMD3(0.026, 0.015, 0.15), radius: 0.014, segments: 2, aoFloor: false)      // short handle (-0.14 ... 0.16)
        b.roundedBox(centre: SIMD3(0, 0, 0.19), half: SIMD3(0.058, 0.015, 0.03), radius: 0.014, segments: 2, aoFloor: false)      // head
        for x in [Float(-0.04), 0, 0.04] {
            b.roundedBox(centre: SIMD3(x, 0, 0.27), half: SIMD3(0.014, 0.013, 0.065), radius: 0.012, segments: 2, aoFloor: false)
        }
        if withBite { cakeBite(b, centre: SIMD3(0, 0.04, 0.27)) }
        return b.mesh
    }
    /// Tip of the tines in fork space (where the bite sticks).
    static let forkTip = SIMD3<Float>(0, 0.04, 0.27)

    // MARK: Drink containers (model space: bottom centre at the origin, scale 1; the group scales them by the serving scale)
    //
    // Two OPEN-NECKED bottles (no cap): the neck holds a 0.035-radius straw per Blob (inner radius 0.058 for one Blob, 0.078 for 2-3). Walls are translucent
    // pastel plastic / glass over an opaque liquid column whose level follows `fill` (1 = full ... 0 = empty); matte, no gloss.

    /// Wall profile (radius, height) of the body part of a bottle, ascending in y.
    typealias Wall = [(r: Float, y: Float)]

    static func wallR(_ w: Wall, at y: Float) -> Float {
        guard let first = w.first, let last = w.last else { return 0 }
        if y <= first.y { return first.r }
        for i in 1..<w.count where y <= w[i].y {
            let a = w[i - 1], c = w[i], u = (y - a.y) / max(c.y - a.y, 1e-6)
            return a.r + (c.r - a.r) * u
        }
        return last.r
    }

    /// Opaque liquid column inside `wall` from y0 up to `level` (flat, slightly lighter surface). Returns the surface radius.
    @discardableResult
    static func liquid(_ b: RoomMeshBuilder, wall w: Wall, inset: Float, y0: Float, level: Float, color: SIMD3<Float>, surface: SIMD3<Float>) -> Float {
        var pts: [(r: Float, y: Float, ao: Float)] = [(0, y0, 0.7)]
        for q in w where q.y > y0 && q.y < level { pts.append((max(q.r - inset, 0.001), q.y, 0.92)) }
        let rTop = max(wallR(w, at: level) - inset, 0.001)
        pts.append((rTop, level, 1))
        b.lathe(cx: 0, cz: 0, profile: profile(pts), segments: 24, color: color)
        b.lathe(cx: 0, cz: 0, profile: [PP(r: 0, y: level + 0.002, nr: 0, ny: 1), PP(r: rTop, y: level + 0.002, nr: 0, ny: 1)], segments: 24, color: surface)
        return rTop
    }

    /// A thin band wrapped around the wall between two heights (a label), with a stripe at each edge.
    static func band(_ b: RoomMeshBuilder, wall w: Wall, y0: Float, y1: Float, color: SIMD3<Float>, edge: SIMD3<Float>) {
        let off: Float = 0.005
        var pts: [(r: Float, y: Float, ao: Float)] = []
        let steps = 6
        for k in 0...steps {
            let y = y0 + (y1 - y0) * Float(k) / Float(steps)
            pts.append((wallR(w, at: y) + off, y, 1))
        }
        b.lathe(cx: 0, cz: 0, profile: profile(pts), segments: 24, color: color)
        for (ya, yb) in [(y0, y0 + 0.012), (y1 - 0.012, y1)] {
            b.lathe(cx: 0, cz: 0, profile: profile([(wallR(w, at: ya) + off + 0.001, ya, 1), (wallR(w, at: (ya + yb) / 2) + off + 0.001, (ya + yb) / 2, 1),
                                                     (wallR(w, at: yb) + off + 0.001, yb, 1)]), segments: 24, color: edge)
        }
    }

    /// The open lip: a soft ring (outer bead, the opening, a dark inside wall).
    static func lip(_ b: RoomMeshBuilder, y: Float, rOut: Float, rIn: Float, color: SIMD3<Float>) {
        b.lathe(cx: 0, cz: 0, profile: profile([(rOut - 0.008, y - 0.02, 1), (rOut, y - 0.008, 1), (rOut, y, 1), (rOut - 0.01, y + 0.006, 1), (rIn + 0.004, y + 0.006, 1),
                                                (rIn, y - 0.004, 0.6), (rIn, y - 0.05, 0.3)]), segments: 24, color: color)
    }

    static func tint(_ m: RoomMesh, alpha: Float) -> RoomMesh {
        var m = m
        for i in m.vertices.indices { m.vertices[i].color.w = alpha }
        return m
    }

    /// Stretches a mesh vertically about y = 0 (normals follow).
    static func stretchY(_ m: RoomMesh, _ k: Float) -> RoomMesh {
        guard k != 1 else { return m }
        var m = m
        for i in m.vertices.indices {
            m.vertices[i].pos.y *= k
            var nn = SIMD3(m.vertices[i].normal.x, m.vertices[i].normal.y / k, m.vertices[i].normal.z)
            nn = simd_length(nn) > 1e-6 ? simd_normalize(nn) : nn
            m.vertices[i].normal = SIMD4(nn, m.vertices[i].normal.w)
        }
        return m
    }
    private static func container(_ o: RoomMeshBuilder, _ t: RoomMeshBuilder, alpha: Float, n: Int, H: Float, rIn: Float) -> ContainerModel {
        // heights do NOT grow with N (the straw tips must stay at his mouth height); widths do (the group scales by servingScale)
        let k = DiningDims.bottleY / DiningTiming.servingScale(n: n)
        return ContainerModel(opaque: stretchY(o.mesh, k), translucent: stretchY(tint(t.mesh, alpha: alpha), k), openingY: H * k, openingRadius: rIn)
    }

    /// Catmull-Rom smoothing of a coarse (radius, height) profile (the first point, on the axis, stays put) for a round, readable silhouette.
    static func smoothWall(_ pts: Wall, per: Int = 5) -> Wall {
        guard pts.count > 3 else { return pts }
        var out: Wall = [pts[0]]
        for i in 1..<(pts.count - 1) {
            let p0 = pts[max(i - 1, 1)], p1 = pts[i], p2 = pts[i + 1], p3 = pts[min(i + 2, pts.count - 1)]
            for k in 0..<per {
                let t = Float(k) / Float(per), t2 = t * t, t3 = t2 * t
                // cardinal spline with a low tension (0.3): round, with almost no overshoot past the specified points
                func cr(_ a: Float, _ b: Float, _ c: Float, _ d: Float) -> Float {
                    let m1 = 0.3 * (c - a), m2 = 0.3 * (d - b)
                    return (2 * t3 - 3 * t2 + 1) * b + (t3 - 2 * t2 + t) * m1 + (-2 * t3 + 3 * t2) * c + (t3 - t2) * m2
                }
                out.append((max(cr(p0.r, p1.r, p2.r, p3.r), 0), cr(p0.y, p1.y, p2.y, p3.y)))
            }
        }
        out.append(pts[pts.count - 1])
        return out
    }

    /// WATER BOTTLE (smooth plastic, pale blue): rounded foot, straight body, a sloping shoulder, a narrow neck with a lip ring, open top (no cap).
    /// Two subtle grip grooves (radius -0.006) at y 0.12 and 0.16, a pale label band at 0.18-0.28, water to y 0.36. 0.52 tall, 0.23 wide.
    static let waterCoarse: Wall = [(0, 0), (0.105, 0), (0.115, 0.02), (0.115, 0.095), (0.109, 0.12), (0.115, 0.14), (0.109, 0.16), (0.115, 0.18), (0.115, 0.30),
                                    (0.108, 0.34), (0.075, 0.40), (0.048, 0.44), (0.048, 0.50)]
    static let waterWall: Wall = smoothWall(waterCoarse)
    static let waterLevels: (empty: Float, full: Float) = (0.02, 0.36)
    static let waterHeight: Float = 0.52

    static func waterBottle(n: Int, palette pal: ConsumablePalette, fill: Float = 1) -> ContainerModel {
        let H = waterHeight, w = waterWall, rIn: Float = 0.042
        let o = RoomMeshBuilder(); o.material = .plain
        if fill > 0.001 {
            let level = waterLevels.empty + (waterLevels.full - waterLevels.empty) * min(fill, 1)
            liquid(o, wall: w, inset: 0.01, y0: 0.012, level: level, color: pal.primary, surface: pal.primary * 1.15)
        }
        band(o, wall: w, y0: 0.18, y1: 0.28, color: pal.detail, edge: pal.primary * 0.92)
        lip(o, y: H - 0.004, rOut: 0.056, rIn: rIn, color: pal.detail)
        let t = RoomMeshBuilder(); t.material = .plain
        t.lathe(cx: 0, cz: 0, profile: profile(w.map { ($0.r, $0.y, 1) }), segments: 24, color: pal.secondary)
        return container(o, t, alpha: 0.28, n: n, H: H, rIn: rIn)
    }

    /// SODA BOTTLE (classic contoured glass, pastel pink): rounded foot, pinched waist at 0.16, a bulge at 0.24, a long sloping shoulder into a tall
    /// narrow neck with a lip ring, open top (no cap). A cream label band at 0.22-0.28, soda to y 0.44 with a few tiny bubbles. 0.60 tall, 0.19 wide.
    static let sodaCoarse: Wall = [(0, 0), (0.085, 0), (0.095, 0.03), (0.095, 0.10), (0.075, 0.16), (0.092, 0.24), (0.085, 0.30), (0.060, 0.40), (0.046, 0.48), (0.044, 0.58)]
    static let sodaWall: Wall = smoothWall(sodaCoarse)
    static let sodaLevels: (empty: Float, full: Float) = (0.02, 0.44)
    static let sodaHeight: Float = 0.60

    static func sodaBottle(n: Int, palette pal: ConsumablePalette, fill: Float = 1) -> ContainerModel {
        let H = sodaHeight, w = sodaWall, rIn: Float = 0.040
        let o = RoomMeshBuilder(); o.material = .plain
        if fill > 0.001 {
            let level = sodaLevels.empty + (sodaLevels.full - sodaLevels.empty) * min(fill, 1)
            let rTop = liquid(o, wall: w, inset: 0.008, y0: 0.012, level: level, color: pal.primary, surface: pal.primary * 1.12 + SIMD3(0.03, 0.02, 0.03))
            let foam = pal.detail * 0.95
            // 7 tiny bubbles: four on the surface, three floating just above it
            for (x, z, r) in [(Float(0), Float(0), Float(0.011)), (0.55, 0.3, 0.008), (-0.5, 0.35, 0.008), (0.1, -0.6, 0.008)] {
                ellipsoid(o, centre: SIMD3(x * rTop * 0.8, level + r * 0.6, z * rTop * 0.8), rx: r, ry: r, color: foam, rings: 4, segments: 8)
            }
            for (x, z, up, r) in [(Float(0.3), Float(0.1), Float(0.035), Float(0.007)), (-0.35, -0.2, 0.065, 0.006), (0.1, -0.3, 0.095, 0.006)] where level + up < 0.55 {
                ellipsoid(o, centre: SIMD3(x * rTop * 0.5, level + up, z * rTop * 0.5), rx: r, ry: r, color: foam, rings: 3, segments: 6)
            }
        }
        band(o, wall: w, y0: 0.22, y1: 0.28, color: pal.detail, edge: pal.accent)
        lip(o, y: H - 0.004, rOut: 0.052, rIn: rIn, color: pal.accent)
        let t = RoomMeshBuilder(); t.material = .plain
        t.lathe(cx: 0, cz: 0, profile: profile(w.map { ($0.r, $0.y, 1) }), segments: 24, color: pal.secondary)
        return container(o, t, alpha: 0.34, n: n, H: H, rIn: rIn)
    }

    // MARK: Bendy straws

    /// Centreline of a bendy straw standing in the container (from deep in the drink), leaving its opening straight up, bending over at the
    /// elbow and ending EXACTLY on `target`.
    static func strawCentreline(root: SIMD3<Float>, rimY: Float, target: SIMD3<Float>, fan: Float = 0, samples n: Int = 36) -> [SIMD3<Float>] {
        let up = SIMD3<Float>(0, 1, 0)
        let base = SIMD3<Float>(root.x, rimY + 0.16, root.z)
        var pts: [SIMD3<Float>] = []
        for i in 0..<5 { pts.append(simd_mix(root, base, SIMD3(repeating: Float(i) / 5))) }                      // straight stub (5 samples, base is the next)
        var tg = target
        if simd_length(tg - base) < 0.05 { tg = base + SIMD3(0.05, 0, 0) }
        let d = simd_length(tg - base)
        let k1 = min(max(0.5 * d, 0.06), 0.4)
        let elbow = base + up * max(0.1, min(d * 0.55, 0.3))
        var endDir = tg - elbow
        endDir = simd_length(endDir) > 1e-5 ? simd_normalize(endDir) : -up
        let k2 = min(max(0.5 * d, 0.06), 0.5)
        let rel = tg - base
        var side = rel - up * simd_dot(rel, up)
        let horiz = simd_length(side)
        side = horiz > 1e-4 ? side / horiz : SIMD3(1, 0, 0)
        let below = max(0, -simd_dot(rel, up) / max(d, 1e-4))
        let bow = side * (0.16 * below * max(0, 1 - horiz / 0.3))
        let p0 = base, p1 = base + up * k1 + bow + side * fan, p2 = tg - endDir * k2 + bow, p3 = tg
        let m = n - pts.count
        for i in 0..<m {
            let u = Float(i) / Float(m - 1), v = 1 - u
            var p = v * v * v * p0 + 3 * v * v * u * p1 + 3 * v * u * u * p2 + u * u * u * p3
            if i == m - 1 { p = target }
            pts.append(p)
        }
        return pts
    }

    /// N >= 2 (the formation the user picked): straight up out of the neck, ONE rounded ~90 degree elbow just above the lip, then a long, nearly
    /// horizontal arm out to `target` (xz) with the tip a hair above the bend. The centre straw's arm points away from the camera (it reads as
    /// "straight up"), the side straws run out to each side.
    static func strawLongPath(root: SIMD3<Float>, elbowY: Float, target: SIMD2<Float>) -> [SIMD3<Float>] {
        let up = SIMD3<Float>(0, 1, 0)
        let c = SIMD3<Float>(root.x, elbowY, root.z)
        let tip = SIMD3<Float>(target.x, elbowY + 0.01, target.y)
        let dir2 = simd_normalize(tip - c)
        let rf = min(0.09, 0.4 * simd_length(tip - c), 0.4 * (elbowY - root.y))
        let p0 = c - up * rf, p2 = c + dir2 * rf
        var pts: [SIMD3<Float>] = []
        let nv = 8, nb = 8, ns = 20
        for i in 0..<nv { pts.append(simd_mix(root, p0, SIMD3(repeating: Float(i) / Float(nv)))) }
        for i in 0..<nb {
            let u = Float(i) / Float(nb), v = 1 - u
            pts.append(v * v * p0 + 2 * v * u * c + u * u * p2)
        }
        for i in 1...ns {
            var p = simd_mix(p2, tip, SIMD3(repeating: Float(i) / Float(ns)))
            if i == ns { p = tip }
            pts.append(p)
        }
        return pts
    }

    /// Thick, cute bendy straw tube: parallel-transport frames, an accordion section around the sharpest bend, soft stripes and a flat tip.
    static func appendTube(_ b: RoomMeshBuilder, centre: [SIMD3<Float>], radius r: Float, color: SIMD3<Float>, stripe: SIMD3<Float>, sides: Int = 10, accordion: Bool = true) {
        guard centre.count >= 2 else { return }
        let n = centre.count
        var tangents: [SIMD3<Float>] = []
        for i in 0..<n {
            let a = centre[max(i - 1, 0)], c = centre[min(i + 1, n - 1)]
            let d = c - a
            tangents.append(simd_length(d) > 1e-7 ? simd_normalize(d) : SIMD3(0, 1, 0))
        }
        var arc: [Float] = [0]
        for i in 1..<n { arc.append(arc[i - 1] + simd_length(centre[i] - centre[i - 1])) }
        var elbow = n / 2, best: Float = -1
        for i in 1..<(n - 1) {
            let turn = 1 - simd_dot(tangents[i - 1], tangents[i + 1])
            if turn > best { best = turn; elbow = i }
        }
        let period: Float = 0.06, half: Float = 0.17
        func ridge(_ i: Int) -> Float {
            let d = abs(arc[i] - arc[elbow])
            let w = smooth(half, half * 0.5, d)
            return w * (0.5 + 0.5 * cosf(2 * .pi * (arc[i] - arc[elbow]) / period))
        }
        let radii: [Float] = (0..<n).map { accordion ? r * (1 + 0.32 * ridge($0)) : r }
        var nrm = abs(tangents[0].y) < 0.9 ? simd_normalize(simd_cross(tangents[0], SIMD3(0, 1, 0))) : SIMD3<Float>(1, 0, 0)
        var rows: [[UInt32]] = []
        for i in 0..<n {
            if i > 0 {
                let axis = simd_cross(tangents[i - 1], tangents[i])
                if simd_length(axis) > 1e-6 { nrm = simd_act(simd_quatf(angle: asinf(min(simd_length(axis), 1)), axis: simd_normalize(axis)), nrm) }
            }
            let bin = simd_cross(tangents[i], nrm)
            var col = color
            if Int(arc[i] / 0.085) % 2 == 1 { col = stripe }
            if i >= n - 2 { col = SIMD3(repeating: 1) }
            let i0 = max(i - 1, 0), i1 = min(i + 1, n - 1)
            let slope = (radii[i1] - radii[i0]) / max(arc[i1] - arc[i0], 1e-5)
            var row: [UInt32] = []
            for s in 0..<sides {
                let a = Float(s) / Float(sides) * 2 * .pi
                let dir = nrm * cosf(a) + bin * sinf(a)
                row.append(b.vertex(centre[i] + dir * radii[i], simd_normalize(dir - tangents[i] * slope), ao: 1, color: col))
            }
            rows.append(row)
        }
        for i in 0..<(n - 1) { for s in 0..<sides { b.quad(rows[i][s], rows[i][(s + 1) % sides], rows[i + 1][(s + 1) % sides], rows[i + 1][s]) } }
        let last = n - 1
        let cv = b.vertex(centre[last], tangents[last], ao: 1, color: SIMD3(repeating: 1))
        let bin = simd_cross(tangents[last], nrm)
        var cap: [UInt32] = []
        for s in 0..<sides {
            let a = Float(s) / Float(sides) * 2 * .pi
            cap.append(b.vertex(centre[last] + (nrm * cosf(a) + bin * sinf(a)) * radii[last], tangents[last], ao: 1, color: SIMD3(repeating: 1)))
        }
        for s in 0..<sides { b.triangle(cv, cap[s], cap[(s + 1) % sides]) }
    }

    /// Container placement on the tray, and the straw roots / paths for every place (tray-local).
    static func containerModel(_ d: Consumable, layout L: TrayLayout, palette: ConsumablePalette? = nil, fill: Float = 1) -> ContainerModel? {
        d.container?(L.n, palette ?? d.palette, fill)
    }

    /// Direction (tray-local xz, unit) from the bottle toward place `i`.
    static func placeDir(layout L: TrayLayout, place i: Int) -> SIMD2<Float> {
        let d = L.places[i].rel - L.drinkCentre
        return simd_length(d) > 1e-4 ? simd_normalize(d) : SIMD2<Float>(0, -1)
    }

    /// Where place `i`'s straw stands in the neck, relative to the bottle axis (tray-local xz): one Blob, in the middle; several straws crowd
    /// toward their own Blob.
    static func strawRootOffset(layout L: TrayLayout, place i: Int, neckRadius: Float = 0.04) -> SIMD2<Float> {
        L.n == 1 ? .zero : placeDir(layout: L, place: i) * max(neckRadius * L.scale - DiningDims.strawRadius, 0)
    }
    /// Centreline of place `i`'s straw in tray-local coordinates. One Blob: straight up out of the neck to 0.10 above the lip, ONE rounded elbow of
    /// 65 degrees from vertical, a short arm toward the place. N >= 2: see `strawLongPath`. The last point is the straw TIP (`DiningSet.strawTip`).
    static func strawPath(layout L: TrayLayout, drink d: Consumable, place i: Int) -> [SIMD3<Float>] {
        guard let cm = containerModel(d, layout: L) else { return [] }
        let s = L.scale
        let off = strawRootOffset(layout: L, place: i, neckRadius: cm.openingRadius) + L.drinkCentre
        let rimY = DiningDims.trayTop + cm.openingY * s
        let root = SIMD3<Float>(off.x, DiningDims.trayTop + 0.1 * s, off.y)
        if L.n > 1 {
            return strawLongPath(root: root, elbowY: max(rimY + 0.012, DiningDims.mouthRestHeight - 0.005), target: L.sipTipXZ(i))
        }
        // one Blob: one straight straw slanted out of the neck toward his mouth (passes through the neck axis at the rim)
        let tipXZ = L.sipTipXZ(0)
        let tip = SIMD3<Float>(tipXZ.x, DiningDims.strawTipHeight, tipXZ.y)
        let axis = SIMD2<Float>(off.x, off.y)
        let dh = tipXZ - axis, d = simd_length(dh)
        let tanT = d / max(tip.y - rimY, 0.05)
        let dirH = d > 1e-5 ? dh / d : SIMD2<Float>(0, -1)
        let y0 = rimY - 0.015
        let r0 = axis - dirH * ((rimY - y0) * tanT)
        let start = SIMD3<Float>(r0.x, y0, r0.y)
        return (0..<24).map { k in k == 23 ? tip : simd_mix(start, tip, SIMD3(repeating: Float(k) / 23)) }
    }

    // MARK: PREVIEW ONLY: stand-in Blobs (the locked rest body mesh, drawn again at places 1...n-1; place 0 is the real Bob)

    #if DEBUG || DINING_PREVIEW
    nonisolated(unsafe) static var previewGhosts = false

    /// One rest Blob in body coordinates (feet on y = 0, facing +z): the locked rest mesh, flat pastel pink, two eyes, a dot at his rest mouth.
    static let ghostBlob: RoomMesh = {
        let rm = buildRenderMesh()
        let b = RoomMeshBuilder(); b.material = .plain
        let pink = Consumables.srgb(0.98, 0.80, 0.80)
        for i in 0..<rm.vertexCount {
            b.vertex(SIMD3(rm.rest[3 * i], rm.rest[3 * i + 1], rm.rest[3 * i + 2]), SIMD3(rm.restNormal[3 * i], rm.restNormal[3 * i + 1], rm.restNormal[3 * i + 2]), color: pink)
        }
        var m = b.mesh
        m.indices = Array(rm.index[0..<rm.body.count])
        let e = RoomMeshBuilder(); e.material = .plain
        let dark = Consumables.srgb(0.36, 0.22, 0.20)
        func front(_ x: Double, _ y: Double) -> Float {
            var lo = 0.0, hi = 1.5
            for _ in 0..<40 { let mid = 0.5 * (lo + hi); if BobForm.bodySDF(SIMD3(x, y, mid)) < 0 { lo = mid } else { hi = mid } }
            return Float(0.5 * (lo + hi))
        }
        for sx in [Double(-0.17), 0.17] { ellipsoid(e, centre: SIMD3(Float(sx), 0.86, front(sx, 0.86) - 0.015), rx: 0.035, ry: 0.05, color: dark, rings: 5, segments: 10) }
        ellipsoid(e, centre: SIMD3(0, DiningDims.mouthRestHeight, DiningDims.mouthRestForward - 0.01), rx: 0.03, ry: 0.03, color: Consumables.srgb(0.85, 0.40, 0.45), rings: 4, segments: 8)
        let base = UInt32(m.vertices.count)
        m.vertices += e.mesh.vertices
        m.indices += e.mesh.indices.map { $0 + base }
        return m
    }()

    static func ghostBlobs(layout L: TrayLayout) -> RoomMesh {
        let b = RoomMeshBuilder(); b.material = .plain
        for i in 1..<L.n {
            let p = L.places[i]
            append(ghostBlob, to: b, transform: translation(SIMD3(p.rel.x, 0, p.rel.y), yaw: p.yaw))
        }
        return b.mesh
    }
    #endif

    // MARK: The whole tray group (tray-local)

    /// Opaque and translucent meshes of the tray with its serving: food (plate, pieces, resting forks) or a drink (glass / can + a straw per Blob).
    static func trayGroup(layout L: TrayLayout, serving f: Consumable, state: ServingState, forksResting: Set<Int> = [], theme: RoomTheme)
        -> (opaque: RoomMesh, translucent: RoomMesh) {
        let b = RoomMeshBuilder(); b.material = .plain
        let t = RoomMeshBuilder(); t.material = .plain
        append(tray(layout: L, theme: theme), to: b, transform: matrix_identity_float4x4)
        #if DEBUG || DINING_PREVIEW
        if previewGhosts, L.n > 1 { append(ghostBlobs(layout: L), to: b, transform: matrix_identity_float4x4) }
        #endif
        if f.kind == .food {
            append(plate(layout: L, theme: theme), to: b, transform: matrix_identity_float4x4)
            let fb = RoomMeshBuilder(); fb.material = .plain
            f.serving?(fb, state, f.palette, L)
            append(fb.mesh, to: b, transform: matrix_identity_float4x4)
            // fork foods: NO fork on the tray; the fork poofs straight into his hand (DiningSet draws `fork(withBite:)` at the held pose)
        } else if let cm = containerModel(f, layout: L, fill: Float(state.totalLeft) / Float(DiningTiming.gulpsPerDrink * L.n)) {
            let s = L.scale
            let m = translation(SIMD3(L.drinkCentre.x, DiningDims.trayTop, L.drinkCentre.y), scale: s)
            append(cm.opaque, to: b, transform: m)
            let colors = f.strawColors ?? (f.palette.accent, SIMD3(repeating: 1))
            for i in 0..<L.n {
                appendTube(b, centre: strawPath(layout: L, drink: f, place: i), radius: DiningDims.strawRadius, color: colors.0, stripe: colors.1, accordion: L.n > 1)
            }
            append(cm.translucent, to: t, transform: m)
        }
        return (b.mesh, t.mesh)
    }


    // MARK: Soft translucent contact shadow on the floor (alpha written per vertex)

    static func contactShadow(halfX: Float, halfZ: Float, strength: Float, color: SIMD3<Float>) -> RoomMesh {
        let b = RoomMeshBuilder(); b.material = .plain
        let y = RoomLayout.rugHeight + 0.004
        let segs = 28
        let radii: [(Float, Float)] = [(0, 1), (0.55, 0.85), (0.8, 0.45), (1.0, 0.0)]       // (scale, alpha factor)
        var rows: [[UInt32]] = []
        for (s, a) in radii {
            var row: [UInt32] = []
            for j in 0...segs {
                let t = Float(j) / Float(segs) * 2 * .pi
                let cx = cosf(t), sz = sinf(t)
                // superellipse (rounded rectangle) footprint
                let e: Float = 4
                let k = powf(powf(abs(cx), e) + powf(abs(sz), e), 1 / e)
                let q = k > 1e-5 ? 1 / k : 1
                let p = SIMD3<Float>(cx * q * halfX * s * 1.12, y, sz * q * halfZ * s * 1.12)
                let id = b.vertex(p, SIMD3(0, 1, 0), ao: 1, color: color)
                b.mesh.vertices[Int(id)].color.w = strength * a
                row.append(id)
            }
            rows.append(row)
        }
        for i in 0..<(rows.count - 1) { for j in 0..<segs { b.quad(rows[i][j], rows[i][j + 1], rows[i + 1][j + 1], rows[i + 1][j]) } }
        return b.mesh
    }

    /// Soft round puff sphere (centre at the origin, radius 1): 16 rings x 24 segments, normals leaned toward up for a soft, pillowy look.
    static func puffSphere(theme: RoomTheme) -> RoomMesh {
        let b = RoomMeshBuilder(); b.material = .plain
        let cream = theme.swatches[4] * SIMD3<Float>(1.75, 1.7, 1.55)         // a touch brighter and warmer than the rug
        ellipsoid(b, centre: .zero, rx: 1, ry: 1, color: cream, rings: 16, segments: 24, ao: 1)
        for i in b.mesh.vertices.indices {
            let n = SIMD3(b.mesh.vertices[i].normal.x, b.mesh.vertices[i].normal.y, b.mesh.vertices[i].normal.z)
            let soft = simd_normalize(n * 0.55 + SIMD3<Float>(0, 0.45, 0))
            b.mesh.vertices[i].normal = SIMD4(soft, 1)
        }
        return b.mesh
    }

    static func bubbleSphere() -> RoomMesh {
        let b = RoomMeshBuilder(); b.material = .plain
        ellipsoid(b, centre: .zero, rx: 1, ry: 1, color: SIMD3(1.0, 0.95, 0.97) * 1.4, rings: 5, segments: 8, ao: 1)
        return b.mesh
    }
}
