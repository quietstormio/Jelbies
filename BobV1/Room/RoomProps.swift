//
//  RoomProps.swift
//  Small movable props drawn with the room's own pipeline: the food and water bowls of the care menu.
//  Rebuilt on the CPU only when a prop changes (a few hundred vertices).
//

import simd
import Foundation

nonisolated struct RoomProp: Equatable {
    enum Kind { case food, water }
    var kind: Kind
    var pos: SIMD2<Float>          // floor (x, z) of the bowl centre
    var scale: Float = 1           // 0...1 appear / disappear
    var level: Float = 1           // 1 = full, 0 = empty
}

nonisolated enum RoomPropGeometry {
    static let radius: Float = 0.42
    static let height: Float = 0.23
    /// Base height: the rug sits at RoomLayout.rugHeight, so lift a hair above it.
    static let baseY: Float = RoomLayout.rugHeight + 0.004

    static func build(props: [RoomProp], theme: RoomTheme) -> RoomMesh {
        let sw = theme.swatches
        let b = RoomMeshBuilder()
        b.material = .plain
        for p in props where p.scale > 0.01 { add(p, sw, b) }
        return b.mesh
    }

    private static func add(_ p: RoomProp, _ sw: [SIMD3<Float>], _ b: RoomMeshBuilder) {
        let s = p.scale
        let R = radius * s, H = height * s
        let cx = p.pos.x, cz = p.pos.y
        let y0 = baseY
        typealias PP = RoomMeshBuilder.ProfilePoint

        // soft place mat under the bowl
        do {
            let mr = 0.64 * s
            let mat: [PP] = [PP(r: 0, y: y0 + 0.004, nr: 0, ny: 1, ao: 1), PP(r: mr * 0.9, y: y0 + 0.012 * s, nr: 0, ny: 1, ao: 1),
                             PP(r: mr, y: y0 + 0.012 * s, nr: 0.7, ny: 0.7, ao: 0.85), PP(r: mr + 0.01, y: y0, nr: 1, ny: 0, ao: 0.7)]
            b.lathe(cx: cx, cz: cz, profile: mat, segments: 36, color: sw[3] * 0.93)
        }

        // bowl: outer wall up, rounded rim, inner wall down, floor
        var prof: [(r: Float, y: Float, ao: Float)] = []
        let n = 7
        for k in 0...n {
            let a = Float(k) / Float(n) * .pi / 2
            prof.append((0.14 * s + (R - 0.14 * s) * sinf(a), y0 + H * 0.88 * (1 - cosf(a)), 0.5 + 0.5 * Float(k) / Float(n)))
        }
        let rc = R - 0.03 * s, rho = 0.03 * s, yc = y0 + H * 0.88
        for k in 1..<6 {
            let f = Float(k) / 6 * .pi
            prof.append((rc + rho * cosf(f), yc + rho * sinf(f), 1))
        }
        for k in 0...n {
            let bb = Float(k) / Float(n) * .pi / 2
            prof.append((0.08 * s + (R - 0.14 * s) * cosf(bb), y0 + H * 0.14 + H * 0.74 * (1 - sinf(bb)), 0.7 + 0.15 * (1 - Float(k) / Float(n))))
        }
        prof.append((0, y0 + H * 0.14, 0.8))
        var pp: [PP] = []
        for i in 0..<prof.count {
            let a = prof[max(i - 1, 0)], c = prof[min(i + 1, prof.count - 1)]
            let t = SIMD2<Float>(c.r - a.r, c.y - a.y)
            let nn = simd_normalize(SIMD2<Float>(t.y, -t.x))
            pp.append(PP(r: prof[i].r, y: prof[i].y, nr: nn.x, ny: nn.y, ao: prof[i].ao))
        }
        // the first outer point sits on the floor with a downward-ish normal; keep it out of the light
        b.lathe(cx: cx, cz: cz, profile: pp, segments: 40, color: sw[3])

        // contents
        let floorY = y0 + H * 0.14
        switch p.kind {
        case .food:
            let lv = max(p.level, 0)
            guard lv > 0.02 else { return }
            let rm = (R - 0.07 * s) * (0.55 + 0.45 * lv), hm = 0.15 * s * lv
            var dome: [PP] = []
            for k in 0...8 {
                let a = Float(k) / 8 * .pi / 2
                let nrm = simd_normalize(SIMD2<Float>(sinf(a) / max(rm, 1e-3), cosf(a) / max(hm, 1e-3)))
                dome.append(PP(r: rm * sinf(a), y: floorY - 0.004 + hm * cosf(a), nr: nrm.x, ny: nrm.y, ao: 0.75 + 0.25 * cosf(a)))
            }
            let food = SIMD3<Float>(0.30, 0.14, 0.055)
            b.lathe(cx: cx, cz: cz, profile: dome, segments: 28, color: food)
            // a few kibbles on top
            let kib: [(Float, Float)] = [(0.0, 0.0), (0.45, 0.8), (0.5, 2.3), (0.55, 3.9), (0.3, 5.2), (0.7, 1.5), (0.68, 3.1), (0.72, 4.7)]
            for (i, k) in kib.enumerated() {
                let rr = rm * k.0 * 0.85
                let px = cx + rr * cosf(k.1), pz = cz + rr * sinf(k.1)
                let hh = hm * max(0, 1 - (rr / max(rm, 1e-3)) * (rr / max(rm, 1e-3)))
                let c = SIMD3(px, floorY - 0.004 + hh + 0.012 * s, pz)
                let sh: Float = 0.032 * s * (0.8 + 0.1 * Float(i % 3))
                let col = food * (1.25 + 0.15 * Float(i % 3))
                b.roundedBox(centre: c, half: SIMD3(sh, sh * 0.8, sh), radius: sh * 0.8, segments: 2, aoFloor: false, color: col)
            }
        case .water:
            let lv = max(p.level, 0)
            guard lv > 0.02 else { return }
            let yw = floorY + H * 0.52 * lv + 0.004
            // inner radius at that height from the inner profile (1 - sin b = (yw - floorY) / (0.74 H))
            let q = min(max((yw - floorY) / (0.74 * H), 0), 1)
            let rw = 0.08 * s + (R - 0.14 * s) * cosf(asinf(1 - q)) - 0.004
            let water = SIMD3<Float>(0.50, 0.74, 0.92)
            let disc: [PP] = [PP(r: 0, y: yw, nr: 0, ny: 1, ao: 1), PP(r: rw, y: yw, nr: 0, ny: 1, ao: 1)]
            b.lathe(cx: cx, cz: cz, profile: disc, segments: 32, color: water)
        }
    }
}
