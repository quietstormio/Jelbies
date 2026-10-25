//
//  TrophyShelfGeometry.swift
//  The room's trophy shelf: two small planks on the back wall in the gap between two windows, filled from what the Jelbies have won (TrophyShelfSpec).
//  It is a RoomProp (Room/RoomProps.swift), so it rides the room's static cache and is rebuilt only when a trophy is earned. Nothing is drawn until the
//  first ribbon or cup exists, so a new player's wall is as it was.
//
//    lower plank   one cup per course tier (Puddle ... Tsunami), gold / silver / bronze for the best place any Jelbie took there
//    upper plank   the contest rosette (best Show placing), then the 5, 10 and 25 win trophies and the Champion cup
//
//  Placement: the widest gap between two windows of the current room that is at least 1.0 wide (home: between the middle and right windows). A room with
//  no such gap (the café, the park) gets no shelf.
//

import simd
import Foundation

nonisolated enum TrophyShelfGeometry {
    static let gold = RaceModels.srgb(0.97, 0.78, 0.26), silver = RaceModels.srgb(0.84, 0.87, 0.92), bronze = RaceModels.srgb(0.80, 0.52, 0.32)
    static let ink = RaceModels.srgb(0.40, 0.30, 0.26)

    static func metal(_ place: UInt8) -> SIMD3<Float> { place == 1 ? gold : place == 2 ? silver : bronze }

    /// Where the shelf hangs: x of its centre, its width, and the y of the lower plank's top. nil = no room for it.
    static func spot(_ def: RoomDef = RoomLayout.current) -> (x: Float, width: Float, y: Float)? {
        guard def.id == .home || def.id == .loft || def.id == .cabin else { return nil }
        let w = def.windows
        let xs = w.xs.sorted()
        var best: (x: Float, width: Float)?
        for k in 0..<max(xs.count - 1, 0) {
            let lo = xs[k] + w.halfW, hi = xs[k + 1] - w.halfW
            if hi - lo >= 1.0, hi - lo >= (best?.width ?? 0) { best = ((lo + hi) / 2, hi - lo) }
        }
        guard let b = best else { return nil }
        return (b.x, min(b.width - 0.2, 1.3), w.y0 + 0.30 * (w.y1 - w.y0))
    }

    static func add(_ spec: TrophyShelfSpec, swatches sw: [SIMD3<Float>], to b: RoomMeshBuilder) {
        guard !spec.isEmpty, let sp = spot() else { return }
        let back = RoomLayout.minZ
        b.material = .plain
        let wood = sw[RoomSwatch.frame]
        let depth: Float = 0.12
        let zc = back + depth + 0.01
        let upperY = sp.y + 0.62
        for y in [sp.y, upperY] {
            b.roundedBox(centre: SIMD3(sp.x, y - 0.025, zc), half: SIMD3(sp.width / 2, 0.025, depth), radius: 0.02, segments: 2, aoFloor: false, color: wood)
            for s in [Float(-1), 1] {          // two little brackets under each plank
                b.roundedBox(centre: SIMD3(sp.x + s * (sp.width / 2 - 0.1), y - 0.11, back + 0.05), half: SIMD3(0.018, 0.06, 0.05), radius: 0.012, segments: 2, aoFloor: false, color: wood * 0.85)
            }
        }
        // lower plank: five tier cups
        let n = spec.cups.count
        let slot = sp.width / Float(n)
        for k in 0..<n where spec.cups[k] != 0 {
            let x = sp.x - sp.width / 2 + slot * (Float(k) + 0.5)
            cup(b, x: x, y: sp.y, z: zc, scale: 0.85, color: metal(spec.cups[k]), lid: false)
        }
        // upper plank: the contest rosette, then 5 / 10 / 25 and the Champion cup
        let n2 = 5, slot2 = sp.width / Float(n2)
        func x2(_ k: Int) -> Float { sp.x - sp.width / 2 + slot2 * (Float(k) + 0.5) }
        if spec.contest != 0 { rosette(b, x: x2(0), y: upperY, z: zc, color: metal(spec.contest)) }
        for (k, col) in [(0, bronze), (1, silver), (2, gold)] where spec.milestones[k] {
            cup(b, x: x2(k + 1), y: upperY, z: zc, scale: 0.8 + 0.12 * Float(k), color: col, lid: false)
        }
        if spec.milestones[3] { cup(b, x: x2(4), y: upperY, z: zc, scale: 1.2, color: gold, lid: true) }
    }

    /// A goblet: foot, stem, bowl with a rim, two small handles; the Champion's has a lid and a ball on top.
    private static func cup(_ b: RoomMeshBuilder, x: Float, y: Float, z: Float, scale k: Float, color: SIMD3<Float>, lid: Bool) {
        typealias PP = RoomMeshBuilder.ProfilePoint
        func pp(_ r: Float, _ h: Float, _ nr: Float, _ ny: Float, _ ao: Float = 1) -> PP { PP(r: r * k, y: y + h * k, nr: nr, ny: ny, ao: ao) }
        var prof: [PP] = [
            pp(0.0, 0.0, 0, -1, 0.7), pp(0.075, 0.0, 0.3, -0.9, 0.7), pp(0.08, 0.012, 1, 0.2, 0.8), pp(0.06, 0.03, 0.4, 0.9, 0.9),        // foot
            pp(0.018, 0.05, 1, 0, 1), pp(0.018, 0.09, 1, 0, 1), pp(0.03, 0.105, 0.6, 0.8, 1),                                          // stem and its collar
            pp(0.07, 0.125, 1, -0.2, 1), pp(0.095, 0.17, 1, 0, 1), pp(0.10, 0.215, 1, 0.1, 1),                                         // the bowl
        ]
        prof.append(pp(0.094, 0.222, 0.2, 1, 1))                                                                                       // rim
        if lid { prof.append(pp(0.05, 0.245, 0.3, 1, 1)); prof.append(pp(0.0, 0.255, 0, 1, 1)) }
        else { prof.append(pp(0.085, 0.205, -1, 0.1, 0.8)); prof.append(pp(0.0, 0.195, 0, 1, 0.8)) }                                    // the hollow
        b.lathe(cx: x, cz: z, profile: prof, segments: 16, color: color)
        for s in [Float(-1), 1] {          // handles
            b.roundedBox(centre: SIMD3(x + s * 0.112 * k, y + 0.165 * k, z), half: SIMD3(0.014 * k, 0.03 * k, 0.012 * k), radius: 0.012 * k, segments: 2, aoFloor: false, color: color)
        }
        if lid { b.roundedBox(centre: SIMD3(x, y + 0.285 * k, z), half: SIMD3(repeating: 0.03 * k), radius: 0.03 * k, segments: 3, aoFloor: false, color: color) }
    }

    /// A rosette standing on the plank: a ring of eight round petals around a darker button, on a short stand, with two ribbon tails.
    private static func rosette(_ b: RoomMeshBuilder, x: Float, y: Float, z: Float, color: SIMD3<Float>) {
        let cy = y + 0.2
        b.roundedBox(centre: SIMD3(x, y + 0.04, z), half: SIMD3(0.05, 0.04, 0.035), radius: 0.02, segments: 2, aoFloor: false, color: ink)          // little stand
        for s in [Float(-1), 1] {           // the two ribbon tails
            b.roundedBox(centre: SIMD3(x + s * 0.03, cy - 0.13, z - 0.004), half: SIMD3(0.022, 0.05, 0.008), radius: 0.006, segments: 2, aoFloor: false, color: RaceModels.banner)
        }
        for k in 0..<8 {
            let a = Float(k) / 8 * 2 * .pi
            b.roundedBox(centre: SIMD3(x + 0.07 * cosf(a), cy + 0.07 * sinf(a), z), half: SIMD3(0.03, 0.03, 0.02), radius: 0.02, segments: 3, aoFloor: false, color: color)
        }
        b.roundedBox(centre: SIMD3(x, cy, z + 0.006), half: SIMD3(0.055, 0.055, 0.026), radius: 0.026, segments: 3, aoFloor: false, color: color * 0.8)
    }
}
