//
//  HopscotchModel.swift
//  The hopscotch court's art (restyled 2026-11-06, less babyish): a dark warm asphalt patch with grain flecks, and the eight squares drawn on it as thin soft white chalk outlines
//  with chalk numbers (seven-segment strokes, a dusty halo and a slight brightness wobble per stroke so it reads as hand-drawn chalk). No fills. All flat quads a hair above the
//  lawn, no animation (nothing is rebuilt for it). Geometry (unchanged): HopscotchCourt.
//

import simd

extension DecorModels {
    private typealias S = ParkShapes

    /// A flat quad centred (cx, cz) with half extents, facing up, at height y.
    private static func hsQuad(_ b: RoomMeshBuilder, _ cx: Float, _ cz: Float, _ hx: Float, _ hz: Float, y: Float, _ col: SIMD3<Float>) {
        b.flatQuad(SIMD3(cx - hx, y, cz - hz), SIMD3(cx + hx, y, cz - hz), SIMD3(cx + hx, y, cz + hz), SIMD3(cx - hx, y, cz + hz), normal: SIMD3(0, 1, 0), colors: [col, col, col, col])
    }

    /// Which of the seven segments (a top, b upper right, c lower right, d bottom, e lower left, f upper left, g middle) draw each digit 1...8.
    private static let segments: [[Character]] = [
        ["b", "c"], ["a", "b", "g", "e", "d"], ["a", "b", "g", "c", "d"], ["f", "g", "b", "c"],
        ["a", "f", "g", "c", "d"], ["a", "f", "g", "e", "c", "d"], ["a", "b", "c"], ["a", "b", "c", "d", "e", "f", "g"],
    ]

    /// Deterministic 0...1 noise from two integers (no RNG state: the court looks the same every build).
    private static func hsNoise(_ a: Int, _ b: Int) -> Float {
        var x = UInt32(truncatingIfNeeded: a &* 73856093 ^ b &* 19349663)
        x = (x ^ (x >> 15)) &* 2246822519; x = (x ^ (x >> 13)) &* 3266489917; x ^= x >> 16
        return Float(x & 0xFFFF) / 65535
    }

    /// One chalk stroke: a faint wider halo (the dusty edge) under the stroke itself, whose brightness wobbles a little.
    private static func hsChalk(_ b: RoomMeshBuilder, _ cx: Float, _ cz: Float, _ hx: Float, _ hz: Float, y: Float, seed: Int, _ base: SIMD3<Float>, _ dust: SIMD3<Float>) {
        let k = 0.82 + 0.18 * hsNoise(seed, 1)
        hsQuad(b, cx, cz, hx + 0.008, hz + 0.008, y: y, dust)
        hsQuad(b, cx, cz, hx, hz, y: y + 0.002, base * k)
    }

    static func addHopscotchCourt(_ b: RoomMeshBuilder, at o: SIMD3<Float>) {
        let h = HopscotchCourt.slabHalf, half = HopscotchCourt.cell / 2
        // a dark, slightly warm asphalt patch with chalk on it (no pastel fills, no cream slab)
        // (2026-11-12: the user's pick, "look B" of the park palette pictures: the living room's one-tint brown, five value steps from the room theme's swatches 0 to 4)
        let asphalt = S.srgb(0.353, 0.240, 0.176), grainLo = S.srgb(0.297, 0.199, 0.144), grainHi = S.srgb(0.429, 0.294, 0.218), wornEdge = S.srgb(0.470, 0.337, 0.254)
        let chalk = S.srgb(0.935, 0.854, 0.784), numChalk = S.srgb(0.829, 0.688, 0.579), dust = S.srgb(0.640, 0.562, 0.505)
        b.roundedBox(centre: o + SIMD3(0, 0.02, 0), half: SIMD3(h.x, 0.02, h.y), radius: 0.05, segments: 3, aoFloor: false, color: asphalt)
        let top: Float = 0.041
        // a soft worn edge: a faded, lighter rim where the blacktop meets the grass
        for (sx, sz, ex, ez) in [(0, -1, h.x, 0.07), (0, 1, h.x, 0.07), (-1, 0, 0.07, h.y), (1, 0, 0.07, h.y)] as [(Float, Float, Float, Float)] {
            hsQuad(b, o.x + sx * (h.x - ex), o.z + sz * (h.y - ez), ex, ez, y: top + 0.0005, wornEdge)
        }
        // blacktop grain: a deterministic scatter of tiny darker and lighter flecks
        for i in 0..<140 {
            let gx = (hsNoise(i, 11) * 2 - 1) * (h.x - 0.08), gz = (hsNoise(i, 12) * 2 - 1) * (h.y - 0.08)
            let s = 0.008 + 0.014 * hsNoise(i, 13)
            hsQuad(b, o.x + gx, o.z + gz, s, s * (0.6 + 0.8 * hsNoise(i, 14)), y: top + 0.001, i % 3 == 0 ? grainHi : grainLo)
        }
        for (i, sq) in HopscotchCourt.squares.enumerated() {
            let cx = o.x + sq.x, cz = o.z + sq.y
            let wide: Float = i == 7 ? 0.03 : 0              // (home is a touch bigger)
            let e = half + wide, t: Float = 0.016, y0 = top + 0.004
            // the chalk outline: four strokes
            hsChalk(b, cx, cz - e + t, e, t, y: y0, seed: i * 10 + 1, chalk, dust)
            hsChalk(b, cx, cz + e - t, e, t, y: y0, seed: i * 10 + 2, chalk, dust)
            hsChalk(b, cx - e + t, cz, t, e, y: y0, seed: i * 10 + 3, chalk, dust)
            hsChalk(b, cx + e - t, cz, t, e, y: y0, seed: i * 10 + 4, chalk, dust)
            // the number: seven-segment strokes, top toward the far side so it reads from the camera
            let w: Float = 0.085, hh: Float = 0.15, st: Float = 0.026
            let y = top + 0.012
            for (n, sg) in segments[i].enumerated() {
                let sd = i * 10 + 5 + n
                switch sg {
                case "a": hsChalk(b, cx, cz - hh, w, st / 2, y: y, seed: sd, numChalk, dust)
                case "d": hsChalk(b, cx, cz + hh, w, st / 2, y: y, seed: sd, numChalk, dust)
                case "g": hsChalk(b, cx, cz, w, st / 2, y: y, seed: sd, numChalk, dust)
                case "b": hsChalk(b, cx + w, cz - hh / 2, st / 2, hh / 2 + st / 2, y: y, seed: sd, numChalk, dust)
                case "c": hsChalk(b, cx + w, cz + hh / 2, st / 2, hh / 2 + st / 2, y: y, seed: sd, numChalk, dust)
                case "f": hsChalk(b, cx - w, cz - hh / 2, st / 2, hh / 2 + st / 2, y: y, seed: sd, numChalk, dust)
                default: hsChalk(b, cx - w, cz + hh / 2, st / 2, hh / 2 + st / 2, y: y, seed: sd, numChalk, dust)          // "e"
                }
            }
        }
    }
}
