//
//  HopscotchModel.swift
//  The hopscotch court's art: a cream paving slab with soft seams, eight pastel squares each with a white chalk border and a chalk number (seven-segment strokes with rounded
//  feel from their thickness), the home square a sunny yellow. All flat quads a hair above the lawn, no animation (nothing is rebuilt for it). Geometry: HopscotchCourt.
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

    static func addHopscotchCourt(_ b: RoomMeshBuilder, at o: SIMD3<Float>) {
        let h = HopscotchCourt.slabHalf, half = HopscotchCourt.cell / 2
        let slab = S.srgb(0.95, 0.91, 0.82), seam = S.srgb(0.88, 0.83, 0.72), chalk = S.srgb(0.995, 0.985, 0.95)
        let pastel = [S.srgb(0.98, 0.80, 0.85), S.srgb(0.74, 0.88, 0.97), S.srgb(0.99, 0.92, 0.68), S.srgb(0.77, 0.93, 0.83),
                      S.srgb(0.87, 0.81, 0.96), S.srgb(0.99, 0.84, 0.72), S.srgb(0.74, 0.88, 0.97), S.srgb(1.0, 0.88, 0.45)]
        // the slab (a low rounded paving stone) with two soft seams
        b.roundedBox(centre: o + SIMD3(0, 0.02, 0), half: SIMD3(h.x, 0.02, h.y), radius: 0.05, segments: 3, aoFloor: false, color: slab)
        let top: Float = 0.041
        for zz: Float in [-0.9, 0.9] { hsQuad(b, o.x, o.z + zz * h.y * 0.55, h.x - 0.05, 0.006, y: top, seam) }
        for (i, sq) in HopscotchCourt.squares.enumerated() {
            let cx = o.x + sq.x, cz = o.z + sq.y
            let wide: Float = i == 7 ? 0.03 : 0              // (home is a touch bigger)
            hsQuad(b, cx, cz, half + wide, half + wide, y: top + 0.006, chalk)          // the chalk border
            hsQuad(b, cx, cz, half - 0.035 + wide, half - 0.035 + wide, y: top + 0.012, pastel[i])
            // the number: seven-segment strokes, top toward the far side so it reads from the camera
            let w: Float = 0.085, hh: Float = 0.15, t: Float = 0.026
            let y = top + 0.018
            for s in segments[i] {
                switch s {
                case "a": hsQuad(b, cx, cz - hh, w, t / 2, y: y, chalk)
                case "d": hsQuad(b, cx, cz + hh, w, t / 2, y: y, chalk)
                case "g": hsQuad(b, cx, cz, w, t / 2, y: y, chalk)
                case "b": hsQuad(b, cx + w, cz - hh / 2, t / 2, hh / 2 + t / 2, y: y, chalk)
                case "c": hsQuad(b, cx + w, cz + hh / 2, t / 2, hh / 2 + t / 2, y: y, chalk)
                case "f": hsQuad(b, cx - w, cz - hh / 2, t / 2, hh / 2 + t / 2, y: y, chalk)
                default: hsQuad(b, cx - w, cz + hh / 2, t / 2, hh / 2 + t / 2, y: y, chalk)          // "e"
                }
            }
        }
    }
}
