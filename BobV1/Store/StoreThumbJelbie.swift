//
//  StoreThumbJelbie.swift
//  Shop thumbnails for wearables: the piece drawn ON a Jelbie (the locked rest body in the neutral blue, with his eyes and brows) instead of floating
//  alone, framed on where it is worn (head / face = a bust close-up, neck / body = the torso, mittens and wristbands = an arm). One mesh per item,
//  built once and rendered once (StoreThumb's cache); the other kinds' thumbnails are untouched. Shoes keep their own foot thumbnail.
//

import simd
import Foundation

@MainActor
extension StoreThumb {
    /// The rest body (egg, arms, feet) as a RoomMesh in the neutral Jelbie blue, built once.
    private static var bodyCache: RoomMesh?
    static func jelbieBody() -> RoomMesh {
        if let b = bodyCache { return b }
        let rm = JellyPortraitRenderer.renderMesh
        let flesh = JellyRoster.palette(0)?.flesh ?? OKLab.srgbToLinear(SIMD3(0.50, 0.68, 0.95))
        var m = RoomMesh()
        m.vertices.reserveCapacity(rm.vertexCount)
        for i in 0..<rm.vertexCount {
            let p = SIMD3<Float>(rm.rest[3 * i], rm.rest[3 * i + 1], rm.rest[3 * i + 2])
            let n = SIMD3<Float>(rm.restNormal[3 * i], rm.restNormal[3 * i + 1], rm.restNormal[3 * i + 2])
            m.vertices.append(RoomVertex(pos: SIMD4(p, 0), normal: SIMD4(n, 1), color: SIMD4(flesh, 1)))
        }
        var i = rm.body.first
        let tailFirst = UInt32(max(rm.armCapsule?.tailFirst ?? Int.max / 2, 0))          // Pip's tail bean lives in the shared mesh: leave it out
        while i + 2 < rm.body.first + rm.body.count {
            if rm.index[i] < tailFirst, rm.index[i + 1] < tailFirst, rm.index[i + 2] < tailFirst { m.indices += [rm.index[i], rm.index[i + 1], rm.index[i + 2]] }
            i += 3
        }
        // eyes and brows: dark beads on the front of the face (the real ones are drawn by the body shader)
        let ink = OKLab.srgbToLinear(SIMD3<Float>(0x3A, 0x26, 0x20) / 255)
        let b = RoomMeshBuilder(); b.material = .plain
        func frontZ(_ x: Float, _ y: Float) -> Float {
            var best: Float = 0, bd: Float = .infinity
            for k in 0..<rm.vertexCount {
                let dx = rm.rest[3 * k] - x, dy = rm.rest[3 * k + 1] - y, z = rm.rest[3 * k + 2]
                if z < 0.1 { continue }
                let d = dx * dx + dy * dy
                if d < bd { bd = d; best = z }
            }
            return best
        }
        func ellipsoid(_ c: SIMD3<Float>, _ r: SIMD3<Float>) {
            let seg = 14, ring = 8
            let base = UInt32(b.mesh.vertices.count)
            for j in 0...ring { for s in 0..<seg {
                let th = Float.pi * Float(j) / Float(ring), ph = 2 * Float.pi * Float(s) / Float(seg)
                let d = SIMD3<Float>(sinf(th) * cosf(ph), cosf(th), sinf(th) * sinf(ph))
                b.vertex(c + d * r, simd_normalize(d / r), ao: 1, color: ink)
            } }
            for j in 0..<ring { for s in 0..<seg {
                let a = base + UInt32(j * seg + s), bb = base + UInt32(j * seg + (s + 1) % seg)
                let c2 = base + UInt32((j + 1) * seg + (s + 1) % seg), d2 = base + UInt32((j + 1) * seg + s)
                b.triangle(a, bb, c2); b.triangle(a, c2, d2)
            } }
        }
        for sx: Float in [-1, 1] {
            let x = sx * Float(BobForm.eyeX), y = Float(BobForm.eyeY)
            let z = frontZ(x, y)
            ellipsoid(SIMD3(x, y, z - 0.004), SIMD3(Float(BobForm.eyeHalfW), Float(BobForm.eyeHalfH), 0.035))
            let bz = frontZ(x, 0.945)
            ellipsoid(SIMD3(x, 0.945, bz - 0.002), SIMD3(0.069, 0.0115, 0.02))
        }
        let base = UInt32(m.vertices.count)
        m.vertices += b.mesh.vertices
        m.indices += b.mesh.indices.map { $0 + base }
        bodyCache = m
        return m
    }

    /// The Jelbie wearing `look` (nil for pieces with no art).
    static func wornMesh(_ look: WearLook) -> RoomMesh? {
        guard var piece = WearMeshes.restMesh(look) else { return nil }
        var m = jelbieBody()
        if look.slot == .hands {
            // Mitts / wristbands on both rest arms, fitted the way the worn body fits them (WornSet.emitArms): the art is a ring about its own y axis (inner radius 0.098, middle at y 0.060),
            // set 0.83 of the way from the arm's tip toward the shoulder and pushed out to the arm's skin there (round cone of the tip sphere and the root sphere) plus its wall. The old
            // placement hung the ring at the tip centre at its authored radius (about 0.10), inside the 0.15 bulb of the rest arm: the band was hidden in the arm.
            let a0 = SIMD3<Float>(Float(BobForm.armTop.x), Float(BobForm.armTop.y), Float(BobForm.armTop.z))
            let b0 = SIMD3<Float>(Float(BobForm.armTip.x), Float(BobForm.armTip.y), Float(BobForm.armTip.z))
            let rTip = Float(BobForm.armTipR), rTop = Float(BobForm.armTopR)
            let station: Float = 0.83, bandInner: Float = 0.098, bandMid: Float = 0.060, bandSquash: Float = 0.90, gap: Float = 0.004
            var out = RoomMesh()
            for sigma: Float in [1, -1] {
                let A = SIMD3(sigma * a0.x, a0.y, a0.z), B = SIMD3(sigma * b0.x, b0.y, b0.z)
                let L = simd_length(A - B), Y = (A - B) / L
                var Z0 = SIMD3<Float>(0, 0, 1); Z0 -= Y * simd_dot(Z0, Y)
                Z0 = simd_normalize(Z0)
                let X = simd_normalize(simd_cross(Y, Z0)), Z = simd_cross(X, Y)
                let sc = L * (1 - station), centre = B + Y * sc
                func skin(_ s: Float) -> Float { max(sqrtf(max(rTip * rTip - s * s, 0)), sqrtf(max(rTop * rTop - (L - s) * (L - s), 0)), 0.02) }
                let base = UInt32(out.vertices.count)
                for v in piece.vertices {
                    let l = SIMD3<Float>(v.pos.x, v.pos.y, v.pos.z)
                    let rho = (l.x * l.x + (l.z / bandSquash) * (l.z / bandSquash)).squareRoot()
                    let cs = rho > 1e-6 ? l.x / rho : 1, sn = rho > 1e-6 ? l.z / bandSquash / rho : 0
                    let axial = sc + (l.y - bandMid)
                    let dir = X * (sigma * cs) + Z * sn
                    let R = skin(axial) + gap + max(rho - bandInner, 0)
                    let q = centre + Y * (axial - sc) + dir * R
                    let n0 = SIMD3<Float>(v.normal.x, v.normal.y, v.normal.z)
                    let n = simd_normalize(X * (sigma * n0.x) + Y * n0.y + Z * n0.z)
                    out.vertices.append(RoomVertex(pos: SIMD4(q, 0), normal: SIMD4(n, v.normal.w), color: v.color))
                }
                var t = 0
                while t + 2 < piece.indices.count {
                    if sigma > 0 { out.indices += [piece.indices[t] + base, piece.indices[t + 1] + base, piece.indices[t + 2] + base] }
                    else { out.indices += [piece.indices[t] + base, piece.indices[t + 2] + base, piece.indices[t + 1] + base] }
                    t += 3
                }
            }
            piece = out
        }
        let base = UInt32(m.vertices.count)
        m.vertices += piece.vertices
        m.indices += piece.indices.map { $0 + base }
        if look == .diamondJ {
            // two or three frozen twinkles on the pendant and the chain (the shop picture is a still)
            let b = RoomMeshBuilder(); b.material = .plain
            let col = SIMD3<Float>(2.2, 2.4, 2.9)
            for (c, L) in [(SIMD3<Float>(-0.10, 0.475, 0.60), Float(0.085)), (SIMD3<Float>(0.115, 0.30, 0.50), 0.065), (SIMD3<Float>(0.22, 0.465, 0.52), 0.05)] {
                let n = simd_normalize(SIMD3<Float>(c.x * 0.4, 0.1, 1))
                let r = simd_normalize(simd_cross(n, SIMD3(0, 1, 0))), up = simd_cross(n, r)
                let first = b.vertex(c, n, ao: 1, color: col)
                let dirs: [SIMD3<Float>] = [r, (r + up) * 0.7071, up, (up - r) * 0.7071, -r, (-r - up) * 0.7071, -up, (r - up) * 0.7071]
                var ids: [UInt32] = []
                for (q, d) in dirs.enumerated() { ids.append(b.vertex(c + d * (q % 2 == 0 ? L : L * 0.2), n, ao: 1, color: col)) }
                for q in 0..<8 { b.triangle(first, ids[q], ids[(q + 1) % 8]) }
            }
            let gb = UInt32(m.vertices.count)
            m.vertices += b.mesh.vertices
            m.indices += b.mesh.indices.map { $0 + gb }
        }
        return m
    }

    /// (centre, radius) of the part of the Jelbie a piece is framed on.
    static func wornFocus(_ look: WearLook) -> (SIMD3<Float>, Float) {
        switch look.slot {
        case .head: return (SIMD3(0, 1.02, 0.05), 0.78)
        case .face: return (SIMD3(0, 0.86, 0.30), 0.80)
        case .neck: return look == .diamondJ ? (SIMD3(0, 0.36, 0.25), 0.50) : (SIMD3(0, 0.52, 0.2), 0.80)
        case .hands: return (SIMD3(0, 0.45, 0.10), 0.98)
        default: return look.anchor == .back ? (SIMD3(0, 0.55, -0.2), 1.1) : (SIMD3(0, 0.50, 0.1), 0.90)
        }
    }
}
