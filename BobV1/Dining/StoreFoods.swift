//
//  StoreFoods.swift
//  The hand-held foods of the store: chicken nuggets, fries, a sushi roll, a sandwich, a mini pizza, a taco, a donut, an ice pop, an onigiri and a cookie.
//  Real 3D meshes in the dining style (RoomMeshBuilder, soft rounded, pastel), each ONE PIECE on the plate (three per Jelly), tossed into his mouth
//  by the existing finger-food flow like the berries. A piece is built around its centre (the berry's centre height, plate at y - 0.056 x scale).
//  They are fed from the inventory (StoreBook), not free: `stored = true` keeps them out of the free Feed picker.
//

import simd
import Foundation

nonisolated enum StoreFoodModels {
    typealias B = RoomMeshBuilder
    /// Plate surface below a piece's centre (berry lift 0.058, a hair of clearance).
    static let floorOff: Float = -0.056

    private static func srgb(_ r: Float, _ g: Float, _ b: Float) -> SIMD3<Float> { Consumables.srgb(r, g, b) }

    // MARK: helpers

    private static func box(_ b: B, _ c: SIMD3<Float>, _ h: SIMD3<Float>, r: Float, _ col: SIMD3<Float>) {
        b.roundedBox(centre: c, half: h, radius: r, segments: 2, aoFloor: false, color: col)
    }
    private static func disc(_ b: B, cx: Float, cz: Float, r: Float, y: Float, _ col: SIMD3<Float>, up: Bool = true) {
        let n: Float = up ? 1 : -1
        b.lathe(cx: cx, cz: cz, profile: [.init(r: 0, y: y, nr: 0, ny: n), .init(r: r, y: y, nr: 0, ny: n)], segments: 20, color: col)
    }
    /// Upright cylinder with softly rounded ends.
    private static func cylinder(_ b: B, cx: Float, cz: Float, r: Float, y0: Float, y1: Float, _ col: SIMD3<Float>, bevel: Float = 0.008) {
        let p: [DiningModels.PP] = [.init(r: 0, y: y0, nr: 0, ny: -1), .init(r: r - bevel, y: y0, nr: 0, ny: -1), .init(r: r, y: y0 + bevel, nr: 1, ny: 0),
                                    .init(r: r, y: y1 - bevel, nr: 1, ny: 0), .init(r: r - bevel, y: y1, nr: 0, ny: 1), .init(r: 0, y: y1, nr: 0, ny: 1)]
        b.lathe(cx: cx, cz: cz, profile: p, segments: 24, color: col)
    }
    /// A tube bent into a ring about y (a torus), or just a cap of it: tube angles `from...to` (0 = outside, pi/2 = top).
    private static func ring(_ b: B, cx: Float, cz: Float, big: Float, tube: Float, yc: Float, from: Float, to: Float, _ col: SIMD3<Float>) {
        let n = 14
        var p: [DiningModels.PP] = []
        for k in 0...n {
            let a = from + (to - from) * Float(k) / Float(n)
            p.append(.init(r: big + tube * cosf(a), y: yc + tube * sinf(a), nr: cosf(a), ny: sinf(a)))
        }
        b.lathe(cx: cx, cz: cz, profile: p, segments: 28, color: col)
    }

    // MARK: the pieces (c = piece centre, j = which of the three, s = serving scale)

    /// A chicken nugget: an irregular golden lump (five overlapping rounded lobes, each a touch different in tone) with crispy crumb bumps on top. No dots,
    /// no sauce: three different shapes for the three on a plate.
    static func nugget(_ b: B, _ c: SIMD3<Float>, _ j: Int, _ s: Float, _ p: ConsumablePalette) {
        let y = c.y + floorOff * s
        // (dx, dz, radius, height) of each lobe
        let shapes: [[(Float, Float, Float, Float)]] = [
            [(0, 0, 0.048, 0.032), (-0.036, 0.012, 0.030, 0.024), (0.034, -0.016, 0.032, 0.026), (0.004, 0.034, 0.026, 0.022), (-0.012, -0.034, 0.024, 0.020)],
            [(0, 0, 0.046, 0.030), (0.038, 0.010, 0.032, 0.025), (-0.032, -0.020, 0.030, 0.024), (-0.012, 0.036, 0.024, 0.020), (0.022, -0.036, 0.022, 0.019)],
            [(0, 0, 0.050, 0.031), (-0.034, -0.014, 0.031, 0.025), (0.030, 0.022, 0.029, 0.023), (0.032, -0.030, 0.024, 0.020), (-0.020, 0.034, 0.025, 0.021)]]
        let lobes = shapes[j % 3]
        let tones: [Float] = [1.0, 0.95, 1.05, 0.98, 1.03]
        for (i, l) in lobes.enumerated() {
            DiningModels.ellipsoid(b, centre: SIMD3(c.x + l.0 * s, y + l.3 * s, c.z + l.1 * s), rx: l.2 * s, ry: l.3 * s, color: p.primary * tones[i], rings: 5, segments: 12)
        }
        // crumb bumps: small crispy specks on the lobes' tops (darker), a few lighter ones
        for (i, l) in lobes.enumerated() {
            for k in 0..<3 {
                let ang = Float(i * 3 + k) * 2.4 + Float(j) * 1.1
                let off = l.2 * (0.25 + 0.22 * Float((i + k) % 3))
                let ox = cosf(ang) * off, oz = sinf(ang) * off
                let h = l.3 * (1 - (off / l.2) * (off / l.2)).squareRoot()
                let col = (i + k) % 4 == 0 ? p.accent : p.secondary
                DiningModels.ellipsoid(b, centre: SIMD3(c.x + (l.0 + ox) * s, y + (l.3 + h * 0.92) * s, c.z + (l.1 + oz) * s), rx: (0.0085 - 0.0015 * Float(k)) * s, ry: 0.0065 * s,
                                       color: col, rings: 3, segments: 7)
            }
        }
    }

    static func fries(_ b: B, _ c: SIMD3<Float>, _ j: Int, _ s: Float, _ p: ConsumablePalette) {
        let y = c.y + floorOff * s
        // paper carton: a trapezoid, red with a cream band
        DiningModels.extrudeRounded(b, poly: [SIMD2(c.x - 0.052 * s, c.z - 0.034 * s), SIMD2(c.x + 0.052 * s, c.z - 0.034 * s), SIMD2(c.x + 0.044 * s, c.z + 0.034 * s), SIMD2(c.x - 0.044 * s, c.z + 0.034 * s)],
                                    y0: y, y1: y + 0.04 * s, bevel: 0.01 * s, color: p.accent)
        box(b, SIMD3(c.x, y + 0.02 * s, c.z + 0.035 * s), SIMD3(0.034, 0.011, 0.004) * s, r: 0.003 * s, p.detail)
        // sticks standing out of the carton at slightly different heights
        let xs: [Float] = [-0.036, -0.018, 0, 0.018, 0.036], hs: [Float] = [0.05, 0.062, 0.056, 0.066, 0.048]
        for (i, x) in xs.enumerated() {
            let h = hs[(i + j) % 5]
            box(b, SIMD3(c.x + x * s, y + (0.04 + h * 0.5) * s, c.z + Float(i % 2 == 0 ? -0.008 : 0.008) * s), SIMD3(0.0085, h * 0.5, 0.0085) * s, r: 0.005 * s, i % 2 == 0 ? p.primary : p.secondary)
        }
    }

    static func sushi(_ b: B, _ c: SIMD3<Float>, _ j: Int, _ s: Float, _ p: ConsumablePalette) {
        let y0 = c.y + floorOff * s, y1 = y0 + 0.07 * s
        cylinder(b, cx: c.x, cz: c.z, r: 0.058 * s, y0: y0, y1: y1, p.primary)                              // nori wrap
        disc(b, cx: c.x, cz: c.z, r: 0.047 * s, y: y1 + 0.002 * s, p.secondary)                               // rice
        disc(b, cx: c.x, cz: c.z, r: 0.026 * s, y: y1 + 0.004 * s, p.accent)                                  // salmon
        disc(b, cx: c.x + 0.012 * s, cz: c.z - 0.006 * s, r: 0.012 * s, y: y1 + 0.006 * s, p.detail)           // cucumber
    }

    static func sandwich(_ b: B, _ c: SIMD3<Float>, _ j: Int, _ s: Float, _ p: ConsumablePalette) {
        let y = c.y + floorOff * s
        func tri(_ k: Float) -> [SIMD2<Float>] { [SIMD2(c.x, c.z + 0.075 * s * k), SIMD2(c.x - 0.075 * s * k, c.z - 0.052 * s * k), SIMD2(c.x + 0.075 * s * k, c.z - 0.052 * s * k)] }
        DiningModels.extrudeRounded(b, poly: tri(1), y0: y, y1: y + 0.024 * s, bevel: 0.01 * s, color: p.primary)
        DiningModels.extrudeRounded(b, poly: tri(1.06), y0: y + 0.024 * s, y1: y + 0.036 * s, bevel: 0.005 * s, color: p.secondary)      // lettuce, a little frilly
        DiningModels.extrudeRounded(b, poly: tri(0.97), y0: y + 0.036 * s, y1: y + 0.046 * s, bevel: 0.004 * s, color: p.accent)         // tomato
        DiningModels.extrudeRounded(b, poly: tri(1), y0: y + 0.046 * s, y1: y + 0.072 * s, bevel: 0.011 * s, color: p.primary)
        for (dx, dz) in [(Float(0), Float(0.015)), (-0.022, -0.012), (0.022, -0.012)] {                                               // seeds
            DiningModels.ellipsoid(b, centre: SIMD3(c.x + dx * s, y + 0.073 * s, c.z + dz * s), rx: 0.008 * s, ry: 0.004 * s, color: p.detail, rings: 2, segments: 6)
        }
    }

    static func minipizzaSlice(_ b: B, _ c: SIMD3<Float>, _ j: Int, _ s: Float, _ p: ConsumablePalette) {
        DiningModels.pizzaSlice(b, centre: c, yaw: 0, palette: p, scale: s)
    }

    static func taco(_ b: B, _ c: SIMD3<Float>, _ j: Int, _ s: Float, _ p: ConsumablePalette) {
        let R: Float = 0.056 * s, yc = c.y + floorOff * s + R
        // the shell: a half pipe of short rounded bars along z
        let n = 18
        for k in 0...n {
            let a = Float.pi + Float.pi * Float(k) / Float(n)
            box(b, SIMD3(c.x + R * cosf(a), yc + R * sinf(a), c.z), SIMD3(0.0175, 0.0175, 0.05) * s, r: 0.0165 * s, p.primary)
        }
        // fillings heaped in the opening
        for (i, z) in [Float(-0.034), -0.011, 0.011, 0.034].enumerated() {
            let col = [p.secondary, p.accent, p.secondary, p.detail][i]
            DiningModels.ellipsoid(b, centre: SIMD3(c.x + Float(i % 2 == 0 ? -0.012 : 0.012) * s, yc + 0.004 * s, c.z + z * s), rx: 0.034 * s, ry: 0.02 * s, color: col, rings: 3, segments: 8)
        }
    }

    static func donut(_ b: B, _ c: SIMD3<Float>, _ j: Int, _ s: Float, _ p: ConsumablePalette) {
        let t: Float = 0.027 * s, big: Float = 0.044 * s, yc = c.y + floorOff * s + t
        ring(b, cx: c.x, cz: c.z, big: big, tube: t, yc: yc, from: -.pi / 2, to: 1.5 * .pi, p.primary)                             // dough
        ring(b, cx: c.x, cz: c.z, big: big, tube: t + 0.004 * s, yc: yc + 0.002 * s, from: 0.12 * .pi, to: 0.88 * .pi, p.secondary)    // icing
        let cols = [p.accent, p.detail, SIMD3<Float>(1, 1, 1)]
        for k in 0..<9 {
            let a = Float(k) * 2 * .pi / 9 + Float(j) * 0.4
            let x = c.x + big * cosf(a) * 1.02, z = c.z + big * sinf(a) * 1.02
            let along = k % 2 == 0
            box(b, SIMD3(x, yc + t + 0.006 * s, z), SIMD3(along ? 0.011 : 0.004, 0.004, along ? 0.004 : 0.011) * s, r: 0.003 * s, cols[k % 3])
        }
    }

    static func popsicle(_ b: B, _ c: SIMD3<Float>, _ j: Int, _ s: Float, _ p: ConsumablePalette) {
        let y = c.y + floorOff * s + 0.022 * s
        box(b, SIMD3(c.x, y, c.z + 0.012 * s), SIMD3(0.044, 0.022, 0.048) * s, r: 0.02 * s, p.primary)                // the ice, two flavours
        box(b, SIMD3(c.x, y, c.z + 0.052 * s), SIMD3(0.044, 0.022, 0.03) * s, r: 0.02 * s, p.secondary)
        box(b, SIMD3(c.x, y - 0.002 * s, c.z - 0.06 * s), SIMD3(0.012, 0.008, 0.042) * s, r: 0.006 * s, p.detail)       // the stick
        DiningModels.ellipsoid(b, centre: SIMD3(c.x, y + 0.021 * s, c.z + 0.02 * s), rx: 0.022 * s, ry: 0.005 * s, color: p.accent, rings: 2, segments: 8)   // a drip of sheen
    }

    static func onigiri(_ b: B, _ c: SIMD3<Float>, _ j: Int, _ s: Float, _ p: ConsumablePalette) {
        let y = c.y + floorOff * s
        // a rounded rice triangle, its base toward the camera, a nori sash round the base
        DiningModels.extrudeRounded(b, poly: [SIMD2(c.x, c.z - 0.07 * s), SIMD2(c.x - 0.072 * s, c.z + 0.05 * s), SIMD2(c.x + 0.072 * s, c.z + 0.05 * s)],
                                    y0: y, y1: y + 0.07 * s, bevel: 0.026 * s, color: p.secondary)
        box(b, SIMD3(c.x, y + 0.026 * s, c.z + 0.05 * s), SIMD3(0.052, 0.026, 0.011) * s, r: 0.006 * s, p.primary)
        DiningModels.ellipsoid(b, centre: SIMD3(c.x, y + 0.072 * s, c.z - 0.005 * s), rx: 0.012 * s, ry: 0.006 * s, color: p.accent, rings: 2, segments: 6)    // a sesame/plum dot
    }

    static func cookie(_ b: B, _ c: SIMD3<Float>, _ j: Int, _ s: Float, _ p: ConsumablePalette) {
        let y0 = c.y + floorOff * s
        let pts: [DiningModels.PP] = [.init(r: 0, y: y0, nr: 0, ny: -1), .init(r: 0.05 * s, y: y0, nr: 0, ny: -1), .init(r: 0.062 * s, y: y0 + 0.008 * s, nr: 1, ny: -0.2),
                                      .init(r: 0.064 * s, y: y0 + 0.02 * s, nr: 1, ny: 0.3), .init(r: 0.05 * s, y: y0 + 0.03 * s, nr: 0.3, ny: 1), .init(r: 0, y: y0 + 0.032 * s, nr: 0, ny: 1)]
        b.lathe(cx: c.x, cz: c.z, profile: pts, segments: 24, color: p.primary)
        let chips: [(Float, Float)] = [(-0.03, 0.02), (0.02, 0.034), (0.036, -0.014), (-0.008, -0.03), (0.0, 0.0), (-0.04, -0.016)]
        for (i, q) in chips.enumerated() {
            DiningModels.ellipsoid(b, centre: SIMD3(c.x + q.0 * s, y0 + 0.032 * s, c.z + q.1 * s), rx: (0.011 + 0.002 * Float(i % 2)) * s, ry: 0.007 * s, color: p.accent, rings: 3, segments: 8)
        }
    }
}

extension Consumables {
    static func food(_ id: String, _ name: String, symbol: String, _ pal: ConsumablePalette, perk: PerkKind?, cond: [ConditionKey: Float], chew: SFX = .chomp,
                             piece: @escaping PieceBuilder) -> Consumable {
        // The Blender mesh when its bundled resource loads, else the procedural builder (the fallback).
        let meshed: PieceBuilder = { b, c, j, s, p in
            if !FoodMeshes.append(b, id: id, centre: c, variant: j, scale: s) { piece(b, c, j, s, p) }
        }
        var c = Consumable(id: id, name: name, kind: .food, eatStyle: .finger, symbol: symbol, palette: pal, benefits: [.hunger: 0.3, .happy: 0.15],
                           serving: { b, st, p, lay in DiningModels.pieces(b, state: st, palette: p, layout: lay, piece: meshed) })
        if id == "minipizza" { c.serving = { b, st, p, lay in DiningModels.pizza(b, state: st, palette: p, layout: lay, piece: meshed) } }       // the pizza fan
        c.stored = true; c.pizzaLayout = (id == "minipizza"); c.piece = meshed; c.perk = perk; c.condition = cond; c.chew = chew; c.storeID = id
        return c
    }
    static func pal(_ a: (Float, Float, Float), _ b: (Float, Float, Float), _ c: (Float, Float, Float), _ d: (Float, Float, Float)) -> ConsumablePalette {
        ConsumablePalette(primary: srgb(a.0, a.1, a.2), secondary: srgb(b.0, b.1, b.2), accent: srgb(c.0, c.1, c.2), detail: srgb(d.0, d.1, d.2))
    }

    static let nuggets = food("nuggets", "Chicken nuggets", symbol: "fork.knife", pal((0.95, 0.74, 0.34), (0.80, 0.52, 0.20), (0.99, 0.87, 0.55), (1, 1, 1)),
                              perk: .fullBelly, cond: [.sporty: 0.12], chew: .crunchNugget, piece: StoreFoodModels.nugget)
    static let fries = food("fries", "Fries", symbol: "fork.knife", pal((0.99, 0.84, 0.40), (0.98, 0.90, 0.58), (0.93, 0.40, 0.40), (1.0, 0.96, 0.82)),
                            perk: .bouncy, cond: [.cool: 0.10, .sporty: 0.05], chew: .crunchFries, piece: StoreFoodModels.fries)
    static let sushi = food("sushi", "Sushi roll", symbol: "fork.knife", pal((0.20, 0.26, 0.24), (0.99, 0.98, 0.94), (0.98, 0.58, 0.46), (0.58, 0.82, 0.50)),
                            perk: .cozy, cond: [.sparkle: 0.10, .cute: 0.08], piece: StoreFoodModels.sushi)
    static let sandwich = food("sandwich", "Sandwich", symbol: "fork.knife", pal((0.96, 0.84, 0.58), (0.60, 0.82, 0.48), (0.94, 0.45, 0.42), (1.0, 0.96, 0.82)),
                               perk: .focus, cond: [.cool: 0.10, .sporty: 0.06], piece: StoreFoodModels.sandwich)
    static let minipizza = food("minipizza", "Mini pizza", symbol: "triangle.fill", pal((0.93, 0.74, 0.50), (1.0, 0.89, 0.58), (0.50, 0.78, 0.42), (1.0, 0.96, 0.78)),
                                perk: .social, cond: [.sweet: 0.10, .cute: 0.06], piece: StoreFoodModels.minipizzaSlice)
    static let taco = food("taco", "Taco", symbol: "fork.knife", pal((0.99, 0.82, 0.46), (0.58, 0.82, 0.46), (0.94, 0.44, 0.40), (1.0, 0.93, 0.62)),
                           perk: .zoomies, cond: [.sporty: 0.10, .cool: 0.06], piece: StoreFoodModels.taco)
    static let donut = food("donut", "Donut", symbol: "birthday.cake.fill", pal((0.94, 0.76, 0.52), (0.98, 0.62, 0.74), (0.60, 0.78, 0.98), (1.0, 0.92, 0.50)),
                            perk: .zoomies, cond: [.sweet: 0.14, .cute: 0.06], piece: StoreFoodModels.donut)
    static let popsicle = food("popsicle", "Ice pop", symbol: "birthday.cake.fill", pal((0.98, 0.62, 0.40), (0.96, 0.52, 0.66), (1.0, 0.90, 0.90), (0.92, 0.78, 0.56)),
                               perk: .cozy, cond: [.sweet: 0.08, .cool: 0.08], piece: StoreFoodModels.popsicle)
    static let onigiri = food("onigiri", "Onigiri", symbol: "birthday.cake.fill", pal((0.18, 0.24, 0.22), (1.0, 0.99, 0.95), (0.92, 0.46, 0.50), (1, 1, 1)),
                              perk: .fullBelly, cond: [.cute: 0.10, .sparkle: 0.05], piece: StoreFoodModels.onigiri)
    static let cookie = food("cookie", "Bedtime cookie", symbol: "moon.zzz.fill", pal((0.88, 0.67, 0.42), (0.95, 0.80, 0.58), (0.42, 0.28, 0.22), (1, 1, 1)),
                             perk: .bedtime, cond: [.sweet: 0.10, .cute: 0.06], piece: StoreFoodModels.cookie)

    static let storeFoods: [Consumable] = [nuggets, fries, sushi, sandwich, minipizza, taco, donut, popsicle, onigiri, cookie]
}
