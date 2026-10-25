//
//  ParkShapes.swift
//  Small mesh pieces the Park is built from (RoomMeshBuilder, flat pastel colours, lit by the room's key light and the time of day): ellipsoids, discs,
//  cylinders and camera-facing petal fans (the lily blossoms). Static, built once.
//

import simd
import Foundation

enum ParkShapes {
    typealias PP = RoomMeshBuilder.ProfilePoint
    typealias V3 = SIMD3<Float>

    static func srgb(_ r: Float, _ g: Float, _ b: Float) -> V3 { OKLab.srgbToLinear(SIMD3(r, g, b)) }

    /// The way every flower head faces: toward the camera and up, so a bloom reads from the room's 3/4 view.
    static let headN: V3 = simd_normalize(SIMD3<Float>(0, 0.72, 0.69))
    static let headU: V3 = SIMD3<Float>(1, 0, 0)
    static var headV: V3 { simd_normalize(simd_cross(headN, headU)) }

    /// An ellipsoid centred at `c`.
    static func blob(_ b: RoomMeshBuilder, _ c: V3, rx: Float, ry: Float, rz: Float, color: V3, segments: Int = 8, rings: Int = 4, ao: Float = 1) {
        var prof: [PP] = []
        for k in 0...rings {
            let a = -Float.pi / 2 + Float.pi * Float(k) / Float(rings)
            let n = simd_normalize(SIMD2<Float>(cosf(a) / rx, sinf(a) / ry))
            prof.append(PP(r: rx * cosf(a), y: c.y + ry * sinf(a), nr: n.x, ny: n.y, ao: ao))
        }
        let first = b.mesh.vertices.count
        b.lathe(cx: c.x, cz: c.z, profile: prof, segments: segments, color: color)
        if abs(rz - rx) > 0.0005 {
            let k = rz / rx
            for i in first..<b.mesh.vertices.count { b.mesh.vertices[i].pos.z = c.z + (b.mesh.vertices[i].pos.z - c.z) * k }
        }
    }
    static func ball(_ b: RoomMeshBuilder, _ c: V3, _ r: Float, _ color: V3, segments: Int = 8, rings: Int = 4, ao: Float = 1) {
        blob(b, c, rx: r, ry: r, rz: r, color: color, segments: segments, rings: rings, ao: ao)
    }
    /// A flat disc lying on the ground.
    static func disc(_ b: RoomMeshBuilder, cx: Float, cz: Float, radius: Float, y: Float, color: V3, segments: Int = 24) {
        b.lathe(cx: cx, cz: cz, profile: [PP(r: 0, y: y, nr: 0, ny: 1), PP(r: radius, y: y, nr: 0, ny: 1)], segments: segments, color: color)
    }
    /// A short rounded post / stem between two heights.
    static func stem(_ b: RoomMeshBuilder, x: Float, z: Float, y0: Float, y1: Float, r: Float, color: V3, segments: Int = 5) {
        b.lathe(cx: x, cz: z, profile: [PP(r: r, y: y0, nr: 1, ny: 0, ao: 0.7), PP(r: r * 0.85, y: y1, nr: 1, ny: 0)], segments: segments, color: color)
    }
    /// A cylinder with a flat top.
    static func cylinder(_ b: RoomMeshBuilder, x: Float, z: Float, r: Float, y0: Float, y1: Float, color: V3, segments: Int = 16) {
        b.lathe(cx: x, cz: z, profile: [PP(r: 0, y: y0, nr: 0, ny: -1), PP(r: r, y: y0, nr: 0, ny: -1), PP(r: r, y: y0, nr: 1, ny: 0, ao: 0.7),
                                         PP(r: r, y: y1, nr: 1, ny: 0), PP(r: r, y: y1, nr: 0, ny: 1), PP(r: 0, y: y1, nr: 0, ny: 1)], segments: segments, color: color)
    }
    static func box(_ b: RoomMeshBuilder, _ c: V3, _ h: V3, r: Float = 0.02, color: V3) {
        b.roundedBox(centre: c, half: h, radius: r, segments: 2, aoFloor: false, color: color)
    }

    /// `n` petals (kite shapes) round `c`, from `r0` to `r1`, in the camera-facing plane. `tip` is the petal's outer colour.
    static func fan(_ b: RoomMeshBuilder, _ c: V3, n: Int, r0: Float, r1: Float, width w: Float, color: V3, tip: V3, phase: Float = 0, ao: Float = 1) {
        let U = headU, V = headV, N = headN
        for k in 0..<n {
            let a = phase + Float(k) / Float(n) * 2 * .pi
            let d = U * cosf(a) + V * sinf(a)
            let s = simd_cross(N, d)
            let rm = r0 + (r1 - r0) * 0.55
            let i0 = b.vertex(c + d * r0, N, ao: ao, color: color)
            let i1 = b.vertex(c + d * rm - s * w, N, ao: ao, color: simd_mix(color, tip, SIMD3(repeating: 0.5)))
            let i2 = b.vertex(c + d * r1, N, ao: ao, color: tip)
            let i3 = b.vertex(c + d * rm + s * w, N, ao: ao, color: simd_mix(color, tip, SIMD3(repeating: 0.5)))
            b.quad(i0, i1, i2, i3)
        }
    }
    /// A plain filled disc facing the camera (the heart of a daisy / sunflower), slightly domed.
    static func face(_ b: RoomMeshBuilder, _ c: V3, radius r: Float, color: V3, ao: Float = 1) {
        let U = headU, V = headV, N = headN
        let hub = b.vertex(c + N * (r * 0.35), N, ao: ao, color: color * 1.1)
        var ring: [UInt32] = []
        let n = 10
        for k in 0..<n {
            let a = Float(k) / Float(n) * 2 * .pi
            let d = U * cosf(a) + V * sinf(a)
            ring.append(b.vertex(c + d * r, simd_normalize(N + d * 0.5), ao: ao, color: color))
        }
        for k in 0..<n { b.triangle(hub, ring[k], ring[(k + 1) % n]) }
    }
}
