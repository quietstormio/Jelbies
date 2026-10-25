//
//  GardenShapes.swift
//  Small mesh pieces the Garden is built from (RoomMeshBuilder, flat pastel colours, lit by the room's key light and the time of day): ellipsoids, discs,
//  stems, camera-facing petal fans, and the flowers made of them. Everything is static or built a few times (the plants), never per frame, except the
//  butterflies / fireflies in GardenLive.
//

import simd
import Foundation

enum GardenShapes {
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

    // MARK: flowers

    enum Bloom { case daisy, tulip, rose, poppy, lavender, sunflower, hydrangea }

    static let leafA = srgb(0.30, 0.56, 0.24), leafB = srgb(0.45, 0.72, 0.32)
    static let stemC = srgb(0.34, 0.58, 0.26)

    /// One flower standing at (x, z) on the ground `y0`, `h` tall, in `color`. Cheap: a stem, a couple of leaves and a head.
    static func flower(_ b: RoomMeshBuilder, _ kind: Bloom, x: Float, z: Float, y0: Float = 0, h: Float, color: V3, scale s: Float = 1, rng r: inout ParkRandom) {
        let top = y0 + h
        switch kind {
        case .daisy:
            stem(b, x: x, z: z, y0: y0, y1: top, r: 0.012 * s, color: stemC, segments: 4)
            let c = SIMD3<Float>(x, top + 0.02, z)
            fan(b, c, n: 8, r0: 0.01, r1: 0.085 * s, width: 0.026 * s, color: color, tip: color * 0.96, phase: r.unit() * 6)
            face(b, c + headN * 0.004, radius: 0.026 * s, color: srgb(0.96, 0.74, 0.14))
        case .poppy:
            stem(b, x: x, z: z, y0: y0, y1: top, r: 0.012 * s, color: stemC, segments: 4)
            let c = SIMD3<Float>(x, top + 0.02, z)
            fan(b, c, n: 5, r0: 0.0, r1: 0.075 * s, width: 0.04 * s, color: color * 1.05, tip: color * 0.9, phase: r.unit() * 6)
            face(b, c + headN * 0.004, radius: 0.016 * s, color: srgb(0.30, 0.20, 0.16))
        case .tulip:
            stem(b, x: x, z: z, y0: y0, y1: top, r: 0.014 * s, color: stemC, segments: 4)
            blob(b, SIMD3(x, top + 0.04 * s, z), rx: 0.042 * s, ry: 0.062 * s, rz: 0.042 * s, color: color, segments: 7, rings: 4)
            blob(b, SIMD3(x, top + 0.07 * s, z), rx: 0.024 * s, ry: 0.04 * s, rz: 0.024 * s, color: color * 1.18, segments: 6, rings: 3)
            b.leaf(base: SIMD3(x, y0, z), azimuth: r.unit() * 6.28, length: h * 0.7, width: 0.05 * s, lean: 0.7, colorBase: leafA, colorTip: leafB)
        case .rose:
            stem(b, x: x, z: z, y0: y0, y1: top, r: 0.014 * s, color: stemC, segments: 4)
            let c = SIMD3<Float>(x, top + 0.03 * s, z)
            ball(b, c, 0.05 * s, color, segments: 7, rings: 4)
            ball(b, c + SIMD3(0, 0.026 * s, 0.012 * s), 0.034 * s, color * 1.18, segments: 6, rings: 3)
            ball(b, c + SIMD3(0.005 * s, 0.045 * s, 0.018 * s), 0.018 * s, color * 0.8, segments: 5, rings: 3)
        case .lavender:
            stem(b, x: x, z: z, y0: y0, y1: top, r: 0.008 * s, color: srgb(0.46, 0.60, 0.40), segments: 4)
            for k in 0..<5 {
                let yy = top - 0.02 + Float(k) * 0.034 * s
                blob(b, SIMD3(x, yy, z), rx: 0.022 * s * (1 - Float(k) * 0.12), ry: 0.026 * s, rz: 0.022 * s * (1 - Float(k) * 0.12), color: color * (0.9 + 0.06 * Float(k)), segments: 5, rings: 3)
            }
        case .sunflower:
            stem(b, x: x, z: z, y0: y0, y1: top, r: 0.03 * s, color: srgb(0.34, 0.54, 0.22), segments: 5)
            b.leaf(base: SIMD3(x, y0 + h * 0.3, z), azimuth: 0.4, length: 0.4 * s, width: 0.2 * s, lean: 1.0, colorBase: leafA, colorTip: leafB)
            b.leaf(base: SIMD3(x, y0 + h * 0.5, z), azimuth: 2.7, length: 0.4 * s, width: 0.2 * s, lean: 1.0, colorBase: leafA, colorTip: leafB)
            let c = SIMD3<Float>(x, top + 0.05, z + 0.05)
            fan(b, c, n: 14, r0: 0.05, r1: 0.20 * s, width: 0.04 * s, color: srgb(1.0, 0.80, 0.16), tip: srgb(1.0, 0.70, 0.08), phase: r.unit() * 6)
            face(b, c + headN * 0.01, radius: 0.085 * s, color: srgb(0.36, 0.22, 0.12))
        case .hydrangea:
            let c = SIMD3<Float>(x, y0 + h, z)
            ball(b, c, 0.34 * s, color * 0.92, segments: 10, rings: 5)
            for k in 0..<10 {
                let a = Float(k) * 2.4 + r.unit(), e = 0.2 + r.unit() * 0.9
                let p = c + SIMD3(cosf(a) * cosf(e), sinf(e), sinf(a) * cosf(e)) * (0.30 * s)
                ball(b, p, 0.1 * s, color * (0.9 + 0.25 * r.unit()), segments: 6, rings: 3)
            }
        }
    }

    /// A leafy mound of foliage (bush) with optional blossom dots.
    static func bush(_ b: RoomMeshBuilder, x: Float, z: Float, scale s: Float, color: V3, bloom: V3? = nil, rng r: inout ParkRandom) {
        blob(b, SIMD3(x, 0.40 * s, z), rx: 0.80 * s, ry: 0.52 * s, rz: 0.70 * s, color: color, segments: 12, rings: 6, ao: 0.9)
        blob(b, SIMD3(x + 0.45 * s, 0.30 * s, z + 0.1 * s), rx: 0.5 * s, ry: 0.38 * s, rz: 0.45 * s, color: color * 1.1, segments: 10, rings: 5, ao: 0.9)
        guard let bloom else { return }
        for _ in 0..<9 {
            let a = r.unit() * 6.28, e = 0.1 + r.unit() * 0.9
            let p = SIMD3<Float>(x + cosf(a) * 0.74 * s * cosf(e), 0.40 * s + sinf(e) * 0.5 * s, z + sinf(a) * 0.64 * s * cosf(e))
            ball(b, p, 0.055 * s, bloom * (0.9 + 0.2 * r.unit()), segments: 5, rings: 3)
        }
    }
}
