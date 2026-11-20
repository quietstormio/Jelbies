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

/// The owner 2026-11-20: "Don't put any food on a plate just put it on the table". `.none` (the default) draws NO plate under the food, at home and in the café; the platter code stays for `-PlateStyle platter`
/// (dev arguments, a capture aid: the frozen look) and for the tests.
nonisolated enum PlateStyle: String { case none, platter }
nonisolated enum DiningPlatter {
    nonisolated(unsafe) static var style: PlateStyle = {
        guard DevArgs.enabled else { return .none }
        if UserDefaults.standard.string(forKey: "PlateStyle") == "platter" || ProcessInfo.processInfo.environment["PLATE_STYLE"] == "platter" { return .platter }
        return .none
    }()
}

nonisolated extension DiningModels {
    /// The platter of a layout (the pieces of every food of that layout lie inside it, see FoodOnPlateTests).
    static func platter(layout L: TrayLayout, pizza: Bool = false) -> Platter {
        if L.arcToCentre { return Platter(cx: 0, cz: -0.06, hx: 0.55, hz: 0.49, r: 0.10) }          // the ends layout: x to the tray's outer edge, z from the back rim's foot (-0.55) to 0.43 (the popsicle's stick, the longest piece, reaches 0.41)
        switch L.n {
        case 1:
            // his three pieces lie on the arc 0.595 in front of him; the platter stops short of his belly (the pizza's slices reach 0.09 closer to him, so its platter does too)
            return pizza ? Platter(cx: 0, cz: -0.13, hx: 0.28, hz: 0.22, r: 0.08) : Platter(cx: 0, cz: -0.095, hx: 0.26, hz: 0.17, r: 0.09)
        case 2: return pizza ? Platter(cx: 0, cz: -0.164, hx: 0.62, hz: 0.19, r: 0.06) : Platter(cx: 0, cz: 0.065, hx: 0.31, hz: 0.335, r: 0.08)
        default: return pizza ? Platter(cx: 0, cz: -0.2275, hx: 0.70, hz: 0.4275, r: 0.06) : Platter(cx: 0, cz: 0.0675, hx: 0.385, hz: 0.4425, r: 0.17)          // the wide row (-MealEnds 0)
        }
    }

    /// Outline of the flat area (counter-clockwise from +x) with the outward normal of every point.
    static func platterOutline(_ P: Platter) -> (pts: [SIMD2<Float>], outs: [SIMD2<Float>]) {
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
        return (pts, outs)
    }
    /// Rim height above the flat top (the crest), see `platterMesh`.
    static let platterRimHeight: Float = 0.021

    /// The platter mesh: flat top at `Platter.floorY` (the old plate's colour), a rounded rim OUTSIDE the flat area (crest 2.1 cm above the floor, 5 cm wide, a touch darker and
    /// warmer than the top, with a soft shade line where it meets the flat) and a rounded underside that rests on the tray. Reads as the old round plate's rim stretched to the platter shape.
    static func platterMesh(_ P: Platter, theme: RoomTheme) -> RoomMesh {
        let b = RoomMeshBuilder(); b.material = .plain
        let col = theme.swatches[4] * 1.08, y0 = Platter.floorY
        let rimCol = col * SIMD3<Float>(0.84, 0.76, 0.66)          // (about 20 % darker and warmer: it has to read as a rim at the size of the phone)
        let (pts, outs) = platterOutline(P)
        // (offset outward from the flat edge, height above the floor, outward normal part, upward normal part, ao, 0 = top colour ... 1 = rim colour)
        let prof: [(d: Float, h: Float, nr: Float, ny: Float, ao: Float, t: Float)] = [
            (0, 0, 0, 1, 1, 0), (0.005, 0.0015, 0.5, 0.85, 0.55, 0.8), (0.0125, 0.0085, 0.8, 0.6, 0.8, 1), (0.0225, 0.018, 0.45, 0.9, 1, 1), (0.0325, platterRimHeight, 0, 1, 1, 1),
            (0.0425, 0.0175, 0.7, 0.7, 1, 1), (0.049, 0.008, 1, 0.15, 0.95, 1), (0.050, -0.002, 1, -0.1, 0.9, 1), (0.046, -0.0135, 0.8, -0.6, 0.7, 0.9), (0.0375, -0.0185, 0.2, -0.98, 0.6, 0.8)]
        var rows: [[UInt32]] = []
        for p in prof {
            let nn = simd_normalize(SIMD2(p.nr, p.ny))
            let c = col + (rimCol - col) * p.t
            var row: [UInt32] = []
            for i in pts.indices {
                let q = pts[i] + outs[i] * p.d
                row.append(b.vertex(SIMD3(q.x, y0 + p.h, q.y), SIMD3(outs[i].x * nn.x, nn.y, outs[i].y * nn.x), ao: p.ao, color: c))
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

    /// A soft contact shadow round the platter's foot (translucent, alpha per vertex), on the tray's / table's top, so the platter reads as lying ON it. It fades to nothing where it would
    /// leave the tray / table (`halfX`, and z within `centreZ` +- `halfZ`): no shadow hangs in the air past the edge.
    static func platterShadow(_ P: Platter, halfX: Float, centreZ: Float, halfZ: Float, theme: RoomTheme) -> RoomMesh {
        let b = RoomMeshBuilder(); b.material = .plain
        let (pts, outs) = platterOutline(P)
        let col = theme.swatches[0], y = DiningDims.trayTop + 0.0035
        let rings: [(d: Float, a: Float)] = [(0.046, 0.30), (0.072, 0.15), (0.105, 0)]
        var rows: [[UInt32]] = []
        for r in rings {
            var row: [UInt32] = []
            for i in pts.indices {
                let q = pts[i] + outs[i] * r.d
                let id = b.vertex(SIMD3(q.x, y, q.y), SIMD3(0, 1, 0), ao: 1, color: col)
                let inside = abs(q.x) <= halfX && abs(q.y - centreZ) <= halfZ
                b.mesh.vertices[Int(id)].color.w = inside ? r.a : 0
                row.append(id)
            }
            rows.append(row)
        }
        let n = pts.count
        for r in 0..<(rows.count - 1) { for i in 0..<n { b.quad(rows[r][i], rows[r][(i + 1) % n], rows[r + 1][(i + 1) % n], rows[r + 1][i]) } }
        return b.mesh
    }
}
