//
//  DiningPlatter.swift
//  food-on-plate-r1 (the owner 2026-11-19, with a screenshot: "The foods not on the plate what's the point of it"): the meal-reach rounds put each place's pieces on an arc at the
//  end diners' reach, past the old round centre plate, so the food lay on the bare tray. The serving surface is now ONE rounded-rectangle platter that lies under every
//  place's pieces (same colour and material as the old plate, floor at the old plate's floor height so nothing about the pieces' height changes), with a low lip outside the
//  area the pieces use. Swift geometry like the tray itself (the pieces are the .bin meshes; the layout decides where the platter is, so it is built per layout).
//

import simd
import Foundation

/// The flat serving area of a platter: a rounded rectangle (tray-local xz) whose top lies at `DiningDims.plateFloorY - 0.004`. Pieces stand inside it with a small margin;
/// the lip rises only OUTSIDE it.
nonisolated struct Platter: Equatable {
    var cx: Float, cz: Float
    var hx: Float, hz: Float
    var r: Float
    static var floorY: Float { DiningDims.plateFloorY - 0.004 }

    /// Signed distance of (x, z) from the flat area's edge: negative inside.
    func distance(x: Float, z: Float) -> Float {
        let qx = abs(x - cx) - (hx - r), qz = abs(z - cz) - (hz - r)
        return hypotf(max(qx, 0), max(qz, 0)) + min(max(qx, qz), 0) - r
    }
}

nonisolated extension DiningModels {
    /// The platter of a layout (the pieces of every food of that layout lie inside it, see FoodOnPlateTests).
    static func platter(layout L: TrayLayout, pizza: Bool = false) -> Platter {
        if L.arcToCentre { return Platter(cx: 0, cz: -0.13, hx: 0.55, hz: 0.405, r: 0.10) }          // the ends layout: x to the tray's outer edge, z from just short of the back rim to past the front pieces
        return Platter(cx: 0, cz: 0, hx: 0.3, hz: 0.3, r: 0.15)
    }

    /// The platter mesh: flat top at `Platter.floorY`, a low lip (crest 7.5 mm above the floor, outside the flat area) and a rounded underside that rests on the tray.
    static func platterMesh(_ P: Platter, theme: RoomTheme) -> RoomMesh {
        let b = RoomMeshBuilder(); b.material = .plain
        let col = theme.swatches[4] * 1.08, y0 = Platter.floorY
        // outline of the flat area (counter-clockwise from +x), with the outward normal of every point
        var pts: [SIMD2<Float>] = [], outs: [SIMD2<Float>] = []
        let steps = 8
        for (k, sgn) in [(SIMD2<Float>(1, 1)), SIMD2(-1, 1), SIMD2(-1, -1), SIMD2(1, -1)].enumerated() {
            let c = SIMD2(P.cx + sgn.x * (P.hx - P.r), P.cz + sgn.y * (P.hz - P.r))
            for s in 0...steps {
                let a = (Float(k) + Float(s) / Float(steps)) * .pi / 2
                let d = SIMD2(cosf(a), sinf(a))
                pts.append(c + d * P.r); outs.append(d)
            }
        }
        // (offset outward from the flat edge, height above the floor, outward normal part, upward normal part, ao)
        let prof: [(d: Float, h: Float, nr: Float, ny: Float, ao: Float)] = [
            (0, 0, 0, 1, 1), (0.010, 0.0006, 0.12, 0.99, 1), (0.020, 0.0045, 0.4, 0.92, 1), (0.028, 0.0075, 0, 1, 1), (0.035, 0.0055, 0.7, 0.7, 1),
            (0.039, -0.002, 1, 0, 0.9), (0.037, -0.014, 0.9, -0.4, 0.7), (0.030, -0.0185, 0.3, -0.95, 0.6)]
        var rows: [[UInt32]] = []
        for p in prof {
            let nn = simd_normalize(SIMD2(p.nr, p.ny))
            var row: [UInt32] = []
            for i in pts.indices {
                let q = pts[i] + outs[i] * p.d
                row.append(b.vertex(SIMD3(q.x, y0 + p.h, q.y), SIMD3(outs[i].x * nn.x, nn.y, outs[i].y * nn.x), ao: p.ao, color: col))
            }
            rows.append(row)
        }
        let n = pts.count
        for r in 0..<(rows.count - 1) { for i in 0..<n { b.quad(rows[r][i], rows[r][(i + 1) % n], rows[r + 1][(i + 1) % n], rows[r + 1][i]) } }
        let top = b.vertex(SIMD3(P.cx, y0, P.cz), SIMD3(0, 1, 0), ao: 1, color: col)
        for i in 0..<n { b.triangle(top, rows[0][i], rows[0][(i + 1) % n]) }
        let bot = b.vertex(SIMD3(P.cx, y0 - 0.0185, P.cz), SIMD3(0, -1, 0), ao: 0.5, color: col)
        for i in 0..<n { b.triangle(bot, rows[rows.count - 1][i], rows[rows.count - 1][(i + 1) % n]) }
        return b.mesh
    }
}
