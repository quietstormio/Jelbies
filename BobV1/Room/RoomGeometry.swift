//
//  RoomGeometry.swift
//  Procedural meshes for the living room. Vertex = pos(xyz, w = material id), normal(xyz, w = baked AO), colour(rgb).
//  Material ids: 0 plain, 1 floor planks, 2 wall, 3 rug, 4 glowing window pane.
//

import simd
import Foundation

struct RoomVertex {
    var pos: SIMD4<Float>
    var normal: SIMD4<Float>
    var color: SIMD4<Float>
}

enum RoomMaterial: Float { case plain = 0, floor = 1, wall = 2, rug = 3, glow = 4, lamp = 5 }

struct RoomMesh {
    var vertices: [RoomVertex] = []
    var indices: [UInt32] = []
}

nonisolated final class RoomMeshBuilder {
    var mesh = RoomMesh()
    var material: RoomMaterial = .plain
    var color = SIMD3<Float>(repeating: 1)

    @discardableResult
    func vertex(_ p: SIMD3<Float>, _ n: SIMD3<Float>, ao: Float = 1, color c: SIMD3<Float>? = nil) -> UInt32 {
        mesh.vertices.append(RoomVertex(pos: SIMD4(p, material.rawValue), normal: SIMD4(n, ao), color: SIMD4(c ?? color, 1)))
        return UInt32(mesh.vertices.count - 1)
    }

    /// Adds a triangle, flipping the winding so the geometric normal agrees with the vertex normals (CCW front faces).
    func triangle(_ a: UInt32, _ b: UInt32, _ c: UInt32) {
        let pa = SIMD3(mesh.vertices[Int(a)].pos.x, mesh.vertices[Int(a)].pos.y, mesh.vertices[Int(a)].pos.z)
        let pb = SIMD3(mesh.vertices[Int(b)].pos.x, mesh.vertices[Int(b)].pos.y, mesh.vertices[Int(b)].pos.z)
        let pc = SIMD3(mesh.vertices[Int(c)].pos.x, mesh.vertices[Int(c)].pos.y, mesh.vertices[Int(c)].pos.z)
        let g = simd_cross(pb - pa, pc - pa)
        if simd_length_squared(g) < 1e-14 { return }                // degenerate
        func nrm(_ i: UInt32) -> SIMD3<Float> { let n = mesh.vertices[Int(i)].normal; return SIMD3(n.x, n.y, n.z) }
        // appended one by one: `+= [a, b, c]` heap-allocated an array per triangle (thousands per rebuild of an animating decor piece)
        if simd_dot(g, nrm(a) + nrm(b) + nrm(c)) >= 0 { mesh.indices.append(a); mesh.indices.append(b); mesh.indices.append(c) }
        else { mesh.indices.append(a); mesh.indices.append(c); mesh.indices.append(b) }
    }

    func quad(_ a: UInt32, _ b: UInt32, _ c: UInt32, _ d: UInt32) { triangle(a, b, c); triangle(a, c, d) }

    /// Flat quad with corners in any consistent order; `normal` picks the facing side.
    func flatQuad(_ p0: SIMD3<Float>, _ p1: SIMD3<Float>, _ p2: SIMD3<Float>, _ p3: SIMD3<Float>, normal n: SIMD3<Float>,
                  ao: Float = 1, colors: [SIMD3<Float>]? = nil) {
        let ps = [p0, p1, p2, p3]
        let ids = (0..<4).map { vertex(ps[$0], n, ao: ao, color: colors?[$0]) }
        quad(ids[0], ids[1], ids[2], ids[3])
    }

    /// Rounded box: each face is a grid whose points are clamped to the inner box and pushed out by `radius`.
    func roundedBox(centre c: SIMD3<Float>, half h: SIMD3<Float>, radius r0: Float, segments S: Int = 4,
                    aoFloor: Bool = true, color col: SIMD3<Float>? = nil) {
        let r = min(r0, min(h.x, min(h.y, h.z)) * 0.98)
        let inner = h - SIMD3(repeating: r)
        func coords(_ hh: Float) -> [Float] {
            var a: [Float] = []
            for k in 0...S { a.append(-hh + r * Float(k) / Float(S)) }
            for k in 0...S { a.append(hh - r * Float(S - k) / Float(S)) }
            return a
        }
        let cx = coords(h.x), cy = coords(h.y), cz = coords(h.z)
        let axes = [cx, cy, cz]
        for a in 0..<3 {
            for s in [Float(-1), 1] {
                let u = (a + 1) % 3, v = (a + 2) % 3
                let n = axes[u].count
                var ids: [UInt32] = []
                for j in 0..<axes[v].count {
                    for i in 0..<n {
                        var q = SIMD3<Float>(repeating: 0)
                        q[a] = s * h[a]; q[u] = axes[u][i]; q[v] = axes[v][j]
                        let cl = simd_clamp(q, -inner, inner)
                        let d = q - cl
                        let nn = simd_length(d) > 1e-7 ? simd_normalize(d) : { var e = SIMD3<Float>(repeating: 0); e[a] = s; return e }()
                        let p = cl + nn * r + c
                        let ao: Float = aoFloor ? (0.5 + 0.5 * smooth(0, 0.35, p.y)) : 1
                        ids.append(vertex(p, nn, ao: ao, color: col))
                    }
                }
                for j in 0..<(axes[v].count - 1) {
                    for i in 0..<(n - 1) {
                        quad(ids[j * n + i], ids[j * n + i + 1], ids[(j + 1) * n + i + 1], ids[(j + 1) * n + i])
                    }
                }
            }
        }
    }

    struct ProfilePoint { var r: Float; var y: Float; var nr: Float; var ny: Float; var ao: Float = 1 }

    /// Surface of revolution about the vertical axis through (cx, cz).
    func lathe(cx: Float, cz: Float, profile: [ProfilePoint], segments N: Int = 40, color col: SIMD3<Float>? = nil) {
        var rows: [[UInt32]] = []
        for pp in profile {
            var row: [UInt32] = []
            for j in 0...N {
                let t = Float(j) / Float(N) * 2 * .pi
                let ct = cosf(t), st = sinf(t)
                row.append(vertex(SIMD3(cx + pp.r * ct, pp.y, cz + pp.r * st), simd_normalize(SIMD3(pp.nr * ct, pp.ny, pp.nr * st)), ao: pp.ao, color: col))
            }
            rows.append(row)
        }
        for i in 0..<(rows.count - 1) {
            for j in 0..<N { quad(rows[i][j], rows[i][j + 1], rows[i + 1][j + 1], rows[i + 1][j]) }
        }
    }

    /// Two-sided curved leaf blade.
    func leaf(base: SIMD3<Float>, azimuth: Float, length L: Float, width W: Float, lean: Float, colorBase: SIMD3<Float>, colorTip: SIMD3<Float>) {
        let K = 7
        let out = SIMD3<Float>(cosf(azimuth), 0, sinf(azimuth))
        let side = SIMD3<Float>(-sinf(azimuth), 0, cosf(azimuth))
        var spine: [SIMD3<Float>] = [base]
        var tangents: [SIMD3<Float>] = []
        for k in 0..<K {
            let t = Float(k) / Float(K)
            let ang = 0.12 + (lean - 0.12) * t * t
            let dir = SIMD3<Float>(0, cosf(ang), 0) + out * sinf(ang)
            tangents.append(dir)
            spine.append(spine[k] + dir * (L / Float(K)))
        }
        tangents.append(tangents[K - 1])
        for face in [Float(1), -1] {
            var rows: [[UInt32]] = []
            for k in 0...K {
                let t = Float(k) / Float(K)
                let w = W * 0.5 * powf(max(1 - t, 0), 0.55) * min(1, 0.35 + t * 5)
                let nBase = simd_normalize(simd_cross(tangents[k], side)) * face
                let p = spine[k]
                let col = simd_mix(colorBase, colorTip, SIMD3(repeating: t))
                let ao = 0.45 + 0.55 * t
                let nL = simd_normalize(nBase - side * 0.45 * face), nR = simd_normalize(nBase + side * 0.45 * face)
                let lift = nBase * (0.18 * w)
                rows.append([vertex(p - side * w, nL, ao: ao, color: col),
                             vertex(p + lift, nBase, ao: ao, color: col),
                             vertex(p + side * w, nR, ao: ao, color: col)])
            }
            for k in 0..<K {
                for i in 0..<2 { quad(rows[k][i], rows[k][i + 1], rows[k + 1][i + 1], rows[k + 1][i]) }
            }
        }
    }
}

@inline(__always) func smooth(_ a: Float, _ b: Float, _ x: Float) -> Float {
    let t = min(max((x - a) / (b - a), 0), 1); return t * t * (3 - 2 * t)
}

enum RoomGeometry {
    /// The windows of the current room (they follow `RoomLayout.current`).
    static var windowXs: [Float] { RoomLayout.current.windows.xs }
    static var windowHalfW: Float { RoomLayout.current.windows.halfW }
    static var windowY0: Float { RoomLayout.current.windows.y0 }
    static var windowY1: Float { RoomLayout.current.windows.y1 }
    static let insetDepth: Float = 0.18

    static func build(theme: RoomTheme, def: RoomDef = RoomLayout.current) -> RoomMesh {
        if def.id == .park { return ParkScenery.build(theme: theme) }          // the park: its own scenery (Park/ParkRoom.swift)
        let sw = theme.swatches
        let b = RoomMeshBuilder()
        let L = RoomLayout.self
        let windowXs = def.windows.xs, windowHalfW = def.windows.halfW, windowY0 = def.windows.y0, windowY1 = def.windows.y1

        // ---- floor: tessellated so we can bake contact AO around furniture / walls ----
        b.material = .floor; b.color = sw[RoomSwatch.floor]
        do {
            let step: Float = 0.125
            let nx = Int((L.maxX - L.minX) / step), nz = Int((L.renderMaxZ - L.minZ) / step)
            var ids: [UInt32] = []
            for j in 0...nz {
                for i in 0...nx {
                    let x = L.minX + Float(i) * step, z = L.minZ + Float(j) * step
                    ids.append(b.vertex(SIMD3(x, 0, z), SIMD3(0, 1, 0), ao: floorAO(x, z, def)))
                }
            }
            for j in 0..<nz { for i in 0..<nx {
                let w = nx + 1
                b.quad(ids[j * w + i], ids[(j + 1) * w + i], ids[(j + 1) * w + i + 1], ids[j * w + i + 1])
            } }
        }

        // ---- walls (back wall has window openings) ----
        b.material = .wall; b.color = sw[RoomSwatch.wall]
        let back = L.minZ, H = L.renderHeight, zf = L.renderMaxZ
        let n = SIMD3<Float>(0, 0, 1)
        func backQuad(_ x0: Float, _ x1: Float, _ y0: Float, _ y1: Float) {
            b.flatQuad(SIMD3(x0, y0, back), SIMD3(x1, y0, back), SIMD3(x1, y1, back), SIMD3(x0, y1, back), normal: n)
        }
        backQuad(L.minX, L.maxX, 0, windowY0)
        backQuad(L.minX, L.maxX, windowY1, H)
        var xCursor = L.minX
        for wx in windowXs {
            backQuad(xCursor, wx - windowHalfW, windowY0, windowY1)
            xCursor = wx + windowHalfW
        }
        backQuad(xCursor, L.maxX, windowY0, windowY1)
        // side walls
        b.flatQuad(SIMD3(L.minX, 0, L.minZ), SIMD3(L.minX, 0, zf), SIMD3(L.minX, H, zf), SIMD3(L.minX, H, L.minZ), normal: SIMD3(1, 0, 0))
        b.flatQuad(SIMD3(L.maxX, 0, L.minZ), SIMD3(L.maxX, H, L.minZ), SIMD3(L.maxX, H, zf), SIMD3(L.maxX, 0, zf), normal: SIMD3(-1, 0, 0))

        // ---- windows: reveal (inset), glowing pane, frame, mullions, sill ----
        for wx in windowXs {
            let x0 = wx - windowHalfW, x1 = wx + windowHalfW, y0 = windowY0, y1 = windowY1, zb = back - insetDepth
            b.material = .wall; b.color = sw[RoomSwatch.wall]
            b.flatQuad(SIMD3(x0, y0, back), SIMD3(x0, y0, zb), SIMD3(x0, y1, zb), SIMD3(x0, y1, back), normal: SIMD3(1, 0, 0), ao: 0.8)
            b.flatQuad(SIMD3(x1, y0, back), SIMD3(x1, y1, back), SIMD3(x1, y1, zb), SIMD3(x1, y0, zb), normal: SIMD3(-1, 0, 0), ao: 0.8)
            b.flatQuad(SIMD3(x0, y1, back), SIMD3(x0, y1, zb), SIMD3(x1, y1, zb), SIMD3(x1, y1, back), normal: SIMD3(0, -1, 0), ao: 0.7)
            b.flatQuad(SIMD3(x0, y0, back), SIMD3(x1, y0, back), SIMD3(x1, y0, zb), SIMD3(x0, y0, zb), normal: SIMD3(0, 1, 0), ao: 0.9)
            // pane: vertical gradient, brightest at the top (sky)
            b.material = .glow
            let lo = sw[3], hi = sw[4]
            b.flatQuad(SIMD3(x0, y0, zb), SIMD3(x1, y0, zb), SIMD3(x1, y1, zb), SIMD3(x0, y1, zb), normal: n,
                       colors: [lo, lo, hi, hi])
            // frame + mullions
            guard def.windows.proceduralFrames else { continue }
            b.material = .plain; b.color = sw[RoomSwatch.frame]
            let t: Float = 0.1, p: Float = 0.05
            b.roundedBox(centre: SIMD3(x0 - t / 2 + 0.02, (y0 + y1) / 2, back + p / 2 - 0.01), half: SIMD3(t / 2, (y1 - y0) / 2 + t, p / 2 + 0.01), radius: 0.015, segments: 2, aoFloor: false)
            b.roundedBox(centre: SIMD3(x1 + t / 2 - 0.02, (y0 + y1) / 2, back + p / 2 - 0.01), half: SIMD3(t / 2, (y1 - y0) / 2 + t, p / 2 + 0.01), radius: 0.015, segments: 2, aoFloor: false)
            b.roundedBox(centre: SIMD3(wx, y1 + t / 2 - 0.02, back + p / 2 - 0.01), half: SIMD3(windowHalfW + t, t / 2, p / 2 + 0.01), radius: 0.015, segments: 2, aoFloor: false)
            b.roundedBox(centre: SIMD3(wx, y0 + 0.02, back + 0.07), half: SIMD3(windowHalfW + t + 0.08, 0.04, 0.12), radius: 0.03, segments: 2, aoFloor: false)  // sill
            b.roundedBox(centre: SIMD3(wx, (y0 + y1) / 2, zb + 0.04), half: SIMD3(0.025, (y1 - y0) / 2, 0.03), radius: 0.01, segments: 1, aoFloor: false)
            b.roundedBox(centre: SIMD3(wx, y0 + (y1 - y0) * 0.62, zb + 0.04), half: SIMD3(windowHalfW, 0.025, 0.03), radius: 0.01, segments: 1, aoFloor: false)
        }

        // ---- baseboards ----
        b.material = .plain; b.color = sw[RoomSwatch.frame]
        b.roundedBox(centre: SIMD3((L.minX + L.maxX) / 2, 0.11, back + 0.03), half: SIMD3((L.maxX - L.minX) / 2, 0.11, 0.03), radius: 0.015, segments: 2, aoFloor: false)
        b.roundedBox(centre: SIMD3(L.minX + 0.03, 0.11, (L.minZ + zf) / 2), half: SIMD3(0.03, 0.11, (zf - L.minZ) / 2), radius: 0.015, segments: 2, aoFloor: false)
        b.roundedBox(centre: SIMD3(L.maxX - 0.03, 0.11, (L.minZ + zf) / 2), half: SIMD3(0.03, 0.11, (zf - L.minZ) / 2), radius: 0.015, segments: 2, aoFloor: false)

        // ---- rug: flat disc, soft rounded edge ----
        b.material = .rug; b.color = sw[RoomSwatch.rug]
        do {
            let R = L.rugRadius, h = L.rugHeight, e: Float = 0.02
            var prof: [RoomMeshBuilder.ProfilePoint] = [.init(r: 0, y: h, nr: 0, ny: 1)]
            prof.append(.init(r: R - 0.1, y: h, nr: 0, ny: 1))
            for k in 0...4 {
                let a = Float(k) / 4 * .pi / 2
                prof.append(.init(r: R - e + e * sinf(a), y: h - e + e * cosf(a), nr: sinf(a), ny: cosf(a), ao: 1))
            }
            prof.append(.init(r: R, y: 0.002, nr: 1, ny: 0, ao: 0.8))
            b.lathe(cx: L.rugCentre.x, cz: L.rugCentre.y, profile: prof, segments: 96)
        }

        // ---- the furniture: the Blender art of the room, or the procedural living room set ----
        if let art = def.art, RoomArt.emit(art, into: b) { return b.mesh }

        // ---- sofa ----
        b.material = .plain
        let s = def.couch.centre
        let zc = s.z
        b.color = sw[RoomSwatch.sofa]
        b.roundedBox(centre: SIMD3(0, 0.31, zc), half: SIMD3(1.8, 0.19, 0.65), radius: 0.12)              // base
        b.roundedBox(centre: SIMD3(-1.6, 0.5, zc), half: SIMD3(0.2, 0.34, 0.65), radius: 0.15)           // arms
        b.roundedBox(centre: SIMD3(1.6, 0.5, zc), half: SIMD3(0.2, 0.34, 0.65), radius: 0.15)
        b.roundedBox(centre: SIMD3(0, 0.72, zc - 0.4), half: SIMD3(1.4, 0.3, 0.25), radius: 0.15)        // back
        b.color = sw[RoomSwatch.cushion]
        b.roundedBox(centre: SIMD3(-0.7, 0.6, zc + 0.1), half: SIMD3(0.68, 0.1, 0.45), radius: 0.085)    // seat cushions
        b.roundedBox(centre: SIMD3(0.7, 0.6, zc + 0.1), half: SIMD3(0.68, 0.1, 0.45), radius: 0.085)
        b.roundedBox(centre: SIMD3(-0.7, 0.86, zc - 0.22), half: SIMD3(0.65, 0.28, 0.14), radius: 0.11) // back cushions
        b.roundedBox(centre: SIMD3(0.7, 0.86, zc - 0.22), half: SIMD3(0.65, 0.28, 0.14), radius: 0.11)

        // ---- side table (pedestal) ----
        do {
            let c = def.lampTable.centre
            b.color = sw[RoomSwatch.tableLeg]
            let base: [RoomMeshBuilder.ProfilePoint] = [
                .init(r: 0, y: 0.0, nr: 0, ny: -1), .init(r: 0.28, y: 0.0, nr: 0, ny: -1),
                .init(r: 0.3, y: 0.02, nr: 1, ny: 0), .init(r: 0.29, y: 0.07, nr: 0.5, ny: 1, ao: 0.9), .init(r: 0.07, y: 0.1, nr: 0, ny: 1, ao: 0.8),
                .init(r: 0.06, y: 0.14, nr: 1, ny: 0, ao: 0.7), .init(r: 0.06, y: 0.58, nr: 1, ny: 0, ao: 0.9)]
            b.lathe(cx: c.x, cz: c.y, profile: base, segments: 32)
            b.color = sw[RoomSwatch.tableTop]
            let top: [RoomMeshBuilder.ProfilePoint] = [
                .init(r: 0, y: 0.58, nr: 0, ny: -1, ao: 0.6), .init(r: 0.46, y: 0.58, nr: 0, ny: -1, ao: 0.6),
                .init(r: 0.5, y: 0.6, nr: 1, ny: -0.3), .init(r: 0.5, y: 0.65, nr: 1, ny: 0.3),
                .init(r: 0.46, y: 0.67, nr: 0.3, ny: 1), .init(r: 0, y: 0.67, nr: 0, ny: 1)]
            b.lathe(cx: c.x, cz: c.y, profile: top, segments: 40)
        }

        // ---- table lamp (on the side table; its shade glows with the time of day) ----
        do {
            let c = def.lampTable.centre
            let top: Float = 0.67
            b.material = .plain; b.color = sw[RoomSwatch.tableLeg]
            b.lathe(cx: c.x, cz: c.y, profile: [
                .init(r: 0, y: top, nr: 0, ny: -1), .init(r: 0.12, y: top, nr: 0, ny: -1),
                .init(r: 0.135, y: top + 0.02, nr: 1, ny: 0.2), .init(r: 0.10, y: top + 0.06, nr: 0.4, ny: 1, ao: 0.9),
                .init(r: 0.03, y: top + 0.09, nr: 0, ny: 1), .init(r: 0.03, y: top + 0.32, nr: 1, ny: 0, ao: 0.9)], segments: 24)
            b.material = .lamp; b.color = sw[RoomSwatch.rug]
            b.lathe(cx: c.x, cz: c.y, profile: [
                .init(r: 0.30, y: top + 0.26, nr: 1, ny: 0.12), .init(r: 0.18, y: top + 0.52, nr: 0.7, ny: 0.7),
                .init(r: 0.0, y: top + 0.53, nr: 0, ny: 1), .init(r: 0.0, y: top + 0.50, nr: 0, ny: -1),
                .init(r: 0.16, y: top + 0.49, nr: -0.6, ny: -0.8), .init(r: 0.28, y: top + 0.26, nr: -0.9, ny: -0.4)], segments: 32)
        }

        // ---- plant ----
        do {
            let c = def.cylinders[def.cylinders.count - 1].centre
            b.color = sw[RoomSwatch.pot]
            let pot: [RoomMeshBuilder.ProfilePoint] = [
                .init(r: 0, y: 0, nr: 0, ny: -1), .init(r: 0.2, y: 0, nr: 0, ny: -1),
                .init(r: 0.24, y: 0.03, nr: 1, ny: -0.2, ao: 0.7), .init(r: 0.33, y: 0.42, nr: 1, ny: -0.2, ao: 0.95),
                .init(r: 0.37, y: 0.44, nr: 1, ny: 0.5), .init(r: 0.37, y: 0.5, nr: 1, ny: 0),
                .init(r: 0.34, y: 0.51, nr: -0.3, ny: 1), .init(r: 0.31, y: 0.46, nr: -1, ny: 0.2, ao: 0.6)]
            b.lathe(cx: c.x, cz: c.y, profile: pot, segments: 32)
            b.color = sw[RoomSwatch.soil]
            b.lathe(cx: c.x, cz: c.y, profile: [.init(r: 0, y: 0.47, nr: 0, ny: 1), .init(r: 0.31, y: 0.46, nr: 0, ny: 1)], segments: 24)
            var seed: UInt32 = 7
            func rnd() -> Float { seed = seed &* 1664525 &+ 1013904223; return Float(seed >> 8) / Float(1 << 24) }
            let count = 11
            for i in 0..<count {
                let az = Float(i) / Float(count) * 2 * .pi + rnd() * 0.3
                let len = 0.9 + rnd() * 0.7
                let off = SIMD3<Float>(cosf(az), 0, sinf(az)) * 0.06
                b.leaf(base: SIMD3(c.x, 0.47, c.y) + off, azimuth: az, length: len, width: 0.2 + rnd() * 0.06, lean: 0.55 + rnd() * 0.7,
                       colorBase: sw[RoomSwatch.leaf], colorTip: sw[RoomSwatch.leafLight])
            }
        }
        return b.mesh
    }

    /// Baked contact occlusion on the floor (1 = open, lower = darker).
    static func floorAO(_ x: Float, _ z: Float, _ def: RoomDef = RoomLayout.current) -> Float {
        let L = RoomLayout.self
        var occ: Float = 0
        func add(_ d: Float, _ strength: Float, _ falloff: Float) { occ = 1 - (1 - occ) * (1 - strength * expf(-max(d, 0) / falloff)) }
        add(x - L.minX, 0.45, 0.30)
        add(L.maxX - x, 0.45, 0.30)
        add(z - L.minZ, 0.45, 0.30)
        var sd = L.boxDistance(SIMD2(x, z), def.couch)
        for bx in def.boxes { sd = min(sd, L.boxDistance(SIMD2(x, z), bx)) }
        add(sd, 0.65, 0.22)
        if sd < 0 { occ = max(occ, 0.7) }
        for c in def.cylinders { add(simd_length(SIMD2(x, z) - c.centre) - c.radius, 0.55, 0.16) }
        let rd = simd_length(SIMD2(x, z) - L.rugCentre) - L.rugRadius
        add(rd, 0.22, 0.07)
        return 1 - occ
    }
}
