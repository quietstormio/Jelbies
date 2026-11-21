//
//  CafeFoods.swift
//  The six café-only treats as hand-held foods in the dining style, and the per-visit mixed plate. Each treat is the Blender mesh when its bundled
//  food_<id>.bin loads (FoodMeshes), else the procedural builder below (the fallback, only seen when a bin is missing). One piece = one toss; three pieces
//  per plate, flicked into his mouth by the existing finger-food flow.
//

import simd
import Foundation

nonisolated enum CafeFoodModels {
    typealias B = RoomMeshBuilder
    static let floorOff: Float = -0.056

    private static func cylinder(_ b: B, cx: Float, cz: Float, r: Float, y0: Float, y1: Float, _ col: SIMD3<Float>, bevel: Float = 0.008) {
        let p: [DiningModels.PP] = [.init(r: 0, y: y0, nr: 0, ny: -1), .init(r: r - bevel, y: y0, nr: 0, ny: -1), .init(r: r, y: y0 + bevel, nr: 1, ny: 0),
                                    .init(r: r, y: y1 - bevel, nr: 1, ny: 0), .init(r: r - bevel, y: y1, nr: 0, ny: 1), .init(r: 0, y: y1, nr: 0, ny: 1)]
        b.lathe(cx: cx, cz: cz, profile: p, segments: 24, color: col)
    }

    /// A mini cinnamon roll: a stack of dough, a darker spiral line on top and a cream glaze drizzle.
    static func swirl(_ b: B, _ c: SIMD3<Float>, _ j: Int, _ s: Float, _ p: ConsumablePalette) {
        let y0 = c.y + floorOff * s
        cylinder(b, cx: c.x, cz: c.z, r: 0.052 * s, y0: y0, y1: y0 + 0.04 * s, p.primary, bevel: 0.014 * s)
        for (i, r) in [Float(0.040), 0.026, 0.012].enumerated() {
            cylinder(b, cx: c.x, cz: c.z, r: r * s, y0: y0 + 0.036 * s, y1: y0 + (0.044 + 0.001 * Float(i)) * s, p.secondary, bevel: 0.002 * s)
            cylinder(b, cx: c.x, cz: c.z, r: (r - 0.006) * s, y0: y0 + 0.037 * s, y1: y0 + (0.0455 + 0.001 * Float(i)) * s, p.primary * 1.04, bevel: 0.002 * s)
        }
        for k in 0..<4 {
            let a = Float(k) * 1.7 + Float(j)
            DiningModels.ellipsoid(b, centre: SIMD3(c.x + cosf(a) * 0.026 * s, y0 + 0.047 * s, c.z + sinf(a) * 0.026 * s), rx: 0.016 * s, ry: 0.006 * s, color: p.accent, rings: 3, segments: 8)
        }
    }

    /// A macaron: two soft peach shells round a cream filling, sparkle-sugar crystals on top.
    static func fizzmac(_ b: B, _ c: SIMD3<Float>, _ j: Int, _ s: Float, _ p: ConsumablePalette) {
        let y0 = c.y + floorOff * s
        DiningModels.ellipsoid(b, centre: SIMD3(c.x, y0 + 0.014 * s, c.z), rx: 0.052 * s, ry: 0.014 * s, color: p.primary, rings: 4, segments: 14)
        cylinder(b, cx: c.x, cz: c.z, r: 0.046 * s, y0: y0 + 0.020 * s, y1: y0 + 0.032 * s, p.secondary, bevel: 0.004 * s)
        DiningModels.ellipsoid(b, centre: SIMD3(c.x, y0 + 0.038 * s, c.z), rx: 0.052 * s, ry: 0.016 * s, color: p.primary * 1.03, rings: 4, segments: 14)
        for k in 0..<6 {
            let a = Float(k) * 1.05 + Float(j) * 0.7, rr = 0.012 + 0.008 * Float(k % 3)
            DiningModels.ellipsoid(b, centre: SIMD3(c.x + cosf(a) * rr * s, y0 + 0.053 * s, c.z + sinf(a) * rr * s), rx: 0.0055 * s, ry: 0.004 * s, color: p.detail, rings: 2, segments: 5)
        }
    }

    /// A silver-dollar stack of three with a butter pat and a syrup drip.
    static func pancakes(_ b: B, _ c: SIMD3<Float>, _ j: Int, _ s: Float, _ p: ConsumablePalette) {
        let y0 = c.y + floorOff * s
        for k in 0..<3 {
            cylinder(b, cx: c.x + Float(k % 2 == 0 ? 0.002 : -0.002) * s, cz: c.z, r: (0.056 - 0.002 * Float(k)) * s, y0: y0 + Float(k) * 0.017 * s, y1: y0 + (Float(k) * 0.017 + 0.019) * s,
                     p.primary * (k == 2 ? 1.04 : 0.96), bevel: 0.007 * s)
        }
        DiningModels.ellipsoid(b, centre: SIMD3(c.x, y0 + 0.053 * s, c.z), rx: 0.04 * s, ry: 0.007 * s, color: p.secondary, rings: 3, segments: 12)
        b.roundedBox(centre: SIMD3(c.x, y0 + 0.063 * s, c.z), half: SIMD3(0.014, 0.006, 0.011) * s, radius: 0.003 * s, segments: 2, aoFloor: false, color: p.accent)
        DiningModels.ellipsoid(b, centre: SIMD3(c.x + 0.05 * s, y0 + 0.028 * s, c.z + 0.012 * s), rx: 0.008 * s, ry: 0.02 * s, color: p.secondary, rings: 3, segments: 8)
    }

    /// A tiny waffle cup with a vanilla scoop, a cocoa scoop and a cherry.
    static func sundae(_ b: B, _ c: SIMD3<Float>, _ j: Int, _ s: Float, _ p: ConsumablePalette) {
        let y0 = c.y + floorOff * s
        let cup: [DiningModels.PP] = [.init(r: 0, y: y0, nr: 0, ny: -1), .init(r: 0.026 * s, y: y0, nr: 0.3, ny: -1), .init(r: 0.04 * s, y: y0 + 0.034 * s, nr: 1, ny: 0.1),
                                      .init(r: 0.046 * s, y: y0 + 0.04 * s, nr: 1, ny: 0.4), .init(r: 0.0, y: y0 + 0.04 * s, nr: 0, ny: 1)]
        b.lathe(cx: c.x, cz: c.z, profile: cup, segments: 20, color: p.primary)
        DiningModels.ellipsoid(b, centre: SIMD3(c.x - 0.012 * s, y0 + 0.06 * s, c.z), rx: 0.034 * s, ry: 0.03 * s, color: p.secondary, rings: 5, segments: 12)
        DiningModels.ellipsoid(b, centre: SIMD3(c.x + 0.018 * s, y0 + 0.074 * s, c.z + 0.004 * s), rx: 0.028 * s, ry: 0.026 * s, color: p.accent, rings: 5, segments: 12)
        DiningModels.ellipsoid(b, centre: SIMD3(c.x + 0.004 * s, y0 + 0.104 * s, c.z), rx: 0.011 * s, ry: 0.011 * s, color: p.detail, rings: 4, segments: 8)
    }

    /// A pup cup: a small white paper cup with a tall swirl of whipped cream, a jelly-blue drizzle ringing the swirl and a few sprinkles.
    static func jellycup(_ b: B, _ c: SIMD3<Float>, _ j: Int, _ s: Float, _ p: ConsumablePalette) {
        let y0 = c.y + floorOff * s
        let h: Float = 0.046
        let cup: [DiningModels.PP] = [.init(r: 0, y: y0, nr: 0, ny: -1), .init(r: 0.022 * s, y: y0, nr: 0.3, ny: -1), .init(r: 0.026 * s, y: y0 + 0.004 * s, nr: 1, ny: -0.2),
                                      .init(r: 0.037 * s, y: y0 + (h - 0.004) * s, nr: 1, ny: 0.15), .init(r: 0.039 * s, y: y0 + h * s, nr: 0.7, ny: 0.7), .init(r: 0, y: y0 + h * s, nr: 0, ny: 1)]
        b.lathe(cx: c.x, cz: c.z, profile: cup, segments: 22, color: p.primary)
        cylinder(b, cx: c.x, cz: c.z, r: 0.0385 * s, y0: y0 + 0.028 * s, y1: y0 + 0.036 * s, p.accent, bevel: 0.002 * s)          // a jelly-blue band round the cup
        let top = y0 + h * s
        DiningModels.ellipsoid(b, centre: SIMD3(c.x, top + 0.008 * s, c.z), rx: 0.037 * s, ry: 0.016 * s, color: p.secondary, rings: 4, segments: 14)
        DiningModels.ellipsoid(b, centre: SIMD3(c.x, top + 0.024 * s, c.z), rx: 0.028 * s, ry: 0.014 * s, color: p.secondary * 1.01, rings: 4, segments: 14)
        DiningModels.ellipsoid(b, centre: SIMD3(c.x, top + 0.038 * s, c.z), rx: 0.018 * s, ry: 0.013 * s, color: p.secondary, rings: 4, segments: 12)
        DiningModels.ellipsoid(b, centre: SIMD3(c.x + 0.002 * s, top + 0.051 * s, c.z), rx: 0.007 * s, ry: 0.011 * s, color: p.secondary * 1.01, rings: 3, segments: 8)
        for k in 0..<7 {          // the drizzle: blue beads winding down the swirl
            let a = Float(k) * 0.9 + Float(j) * 0.8, t = Float(k) / 6
            let rr = (0.027 - 0.014 * t) * s
            DiningModels.ellipsoid(b, centre: SIMD3(c.x + cosf(a) * rr, top + (0.014 + 0.034 * t) * s, c.z + sinf(a) * rr), rx: 0.0062 * s, ry: 0.0036 * s, color: p.accent, rings: 2, segments: 6)
        }
        for k in 0..<4 {          // a few white-blue sprinkles
            let a = Float(k) * 1.6 + Float(j) * 0.5
            DiningModels.ellipsoid(b, centre: SIMD3(c.x + cosf(a) * 0.012 * s, top + (0.02 + 0.007 * Float(k)) * s, c.z + sinf(a) * 0.012 * s), rx: 0.0036 * s, ry: 0.0026 * s, color: p.detail, rings: 2, segments: 5)
        }
    }

    /// A baby latte: a small cream mug with a handle, a frothy top with a brown heart of latte art and a foam dollop.
    static func latte(_ b: B, _ c: SIMD3<Float>, _ j: Int, _ s: Float, _ p: ConsumablePalette) {
        let y0 = c.y + floorOff * s
        let h: Float = 0.044
        let mug: [DiningModels.PP] = [.init(r: 0, y: y0, nr: 0, ny: -1), .init(r: 0.024 * s, y: y0, nr: 0.3, ny: -1), .init(r: 0.032 * s, y: y0 + 0.008 * s, nr: 1, ny: -0.3),
                                      .init(r: 0.036 * s, y: y0 + (h - 0.006) * s, nr: 1, ny: 0), .init(r: 0.036 * s, y: y0 + h * s, nr: 0.7, ny: 0.7), .init(r: 0, y: y0 + h * s, nr: 0, ny: 1)]
        b.lathe(cx: c.x, cz: c.z, profile: mug, segments: 24, color: p.primary)
        b.roundedBox(centre: SIMD3(c.x + 0.044 * s, y0 + 0.026 * s, c.z), half: SIMD3(0.009, 0.0045, 0.0045) * s, radius: 0.002 * s, segments: 2, aoFloor: false, color: p.primary)          // the handle
        b.roundedBox(centre: SIMD3(c.x + 0.049 * s, y0 + 0.019 * s, c.z), half: SIMD3(0.0045, 0.009, 0.0045) * s, radius: 0.002 * s, segments: 2, aoFloor: false, color: p.primary)
        b.roundedBox(centre: SIMD3(c.x + 0.044 * s, y0 + 0.012 * s, c.z), half: SIMD3(0.009, 0.0045, 0.0045) * s, radius: 0.002 * s, segments: 2, aoFloor: false, color: p.primary)
        let top = y0 + h * s
        DiningModels.ellipsoid(b, centre: SIMD3(c.x, top, c.z), rx: 0.0335 * s, ry: 0.007 * s, color: p.secondary, rings: 3, segments: 16)          // the coffee-and-milk top
        DiningModels.ellipsoid(b, centre: SIMD3(c.x, top + 0.003 * s, c.z), rx: 0.026 * s, ry: 0.006 * s, color: p.accent, rings: 3, segments: 14)          // the foam
        for sgn: Float in [-1, 1] {          // the latte-art heart: two lobes and a point
            DiningModels.ellipsoid(b, centre: SIMD3(c.x - 0.005 * s, top + 0.0085 * s, c.z + sgn * 0.0075 * s), rx: 0.0075 * s, ry: 0.0022 * s, color: p.secondary, rings: 2, segments: 8)
        }
        DiningModels.ellipsoid(b, centre: SIMD3(c.x + 0.006 * s, top + 0.0085 * s, c.z), rx: 0.0075 * s, ry: 0.0022 * s, color: p.secondary, rings: 2, segments: 8)
        DiningModels.ellipsoid(b, centre: SIMD3(c.x - 0.01 * s, top + 0.012 * s + Float(j % 2) * 0.0005, c.z - 0.012 * s), rx: 0.006 * s, ry: 0.004 * s, color: p.detail, rings: 2, segments: 6)          // a foam dollop
    }

    /// Warm cocoa: a round rose mug with a handle, a dark chocolate top, three tiny marshmallows and a pinch of cinnamon.
    static func cocoa(_ b: B, _ c: SIMD3<Float>, _ j: Int, _ s: Float, _ p: ConsumablePalette) {
        let y0 = c.y + floorOff * s
        let h: Float = 0.046
        let mug: [DiningModels.PP] = [.init(r: 0, y: y0, nr: 0, ny: -1), .init(r: 0.025 * s, y: y0, nr: 0.3, ny: -1), .init(r: 0.035 * s, y: y0 + 0.008 * s, nr: 1, ny: -0.2),
                                      .init(r: 0.038 * s, y: y0 + (h - 0.006) * s, nr: 1, ny: 0), .init(r: 0.038 * s, y: y0 + h * s, nr: 0.7, ny: 0.7), .init(r: 0, y: y0 + h * s, nr: 0, ny: 1)]
        b.lathe(cx: c.x, cz: c.z, profile: mug, segments: 24, color: p.primary)
        cylinder(b, cx: c.x, cz: c.z, r: 0.0385 * s, y0: y0 + 0.026 * s, y1: y0 + 0.032 * s, p.detail, bevel: 0.002 * s)          // a cream stripe round the mug
        b.roundedBox(centre: SIMD3(c.x + 0.046 * s, y0 + 0.026 * s, c.z), half: SIMD3(0.009, 0.0045, 0.0045) * s, radius: 0.002 * s, segments: 2, aoFloor: false, color: p.primary)          // the handle
        b.roundedBox(centre: SIMD3(c.x + 0.051 * s, y0 + 0.019 * s, c.z), half: SIMD3(0.0045, 0.009, 0.0045) * s, radius: 0.002 * s, segments: 2, aoFloor: false, color: p.primary)
        b.roundedBox(centre: SIMD3(c.x + 0.046 * s, y0 + 0.012 * s, c.z), half: SIMD3(0.009, 0.0045, 0.0045) * s, radius: 0.002 * s, segments: 2, aoFloor: false, color: p.primary)
        let top = y0 + h * s
        DiningModels.ellipsoid(b, centre: SIMD3(c.x, top, c.z), rx: 0.0355 * s, ry: 0.006 * s, color: p.secondary, rings: 3, segments: 16)          // the cocoa
        for k in 0..<3 {          // marshmallows
            let a = Float(k) * 2.1 + Float(j) * 0.6
            DiningModels.ellipsoid(b, centre: SIMD3(c.x + cosf(a) * 0.014 * s, top + 0.008 * s, c.z + sinf(a) * 0.014 * s), rx: 0.0095 * s, ry: 0.0085 * s, color: p.accent, rings: 3, segments: 8)
        }
        DiningModels.ellipsoid(b, centre: SIMD3(c.x, top + 0.007 * s, c.z), rx: 0.006 * s, ry: 0.003 * s, color: p.detail * 0.7, rings: 2, segments: 6)
    }

    /// Berry juice: a tall clear tumbler of pink juice, a striped straw, an ice cube and a raspberry on the rim.
    static func juice(_ b: B, _ c: SIMD3<Float>, _ j: Int, _ s: Float, _ p: ConsumablePalette) {
        let y0 = c.y + floorOff * s
        let h: Float = 0.058
        let glass: [DiningModels.PP] = [.init(r: 0, y: y0, nr: 0, ny: -1), .init(r: 0.022 * s, y: y0, nr: 0.3, ny: -1), .init(r: 0.026 * s, y: y0 + 0.006 * s, nr: 1, ny: -0.2),
                                        .init(r: 0.033 * s, y: y0 + (h - 0.004) * s, nr: 1, ny: 0.1), .init(r: 0.034 * s, y: y0 + h * s, nr: 0.7, ny: 0.7), .init(r: 0, y: y0 + h * s, nr: 0, ny: 1)]
        b.lathe(cx: c.x, cz: c.z, profile: glass, segments: 24, color: p.secondary)          // the juice shows through the glass: a pale rim, a berry-pink body
        cylinder(b, cx: c.x, cz: c.z, r: 0.0325 * s, y0: y0 + 0.01 * s, y1: y0 + (h - 0.006) * s, p.primary, bevel: 0.003 * s)
        DiningModels.ellipsoid(b, centre: SIMD3(c.x, y0 + (h - 0.005) * s, c.z), rx: 0.0325 * s, ry: 0.004 * s, color: p.primary * 1.06, rings: 3, segments: 16)
        if s < 2 {          // (the baked straw is for the hand-size piece; the big cup at the table has the bendy straw to the mouth instead, `strawCups`)
            b.roundedBox(centre: SIMD3(c.x + 0.012 * s, y0 + (h + 0.012) * s, c.z - 0.004 * s), half: SIMD3(0.0035, 0.032, 0.0035) * s, radius: 0.0015 * s, segments: 2, aoFloor: false, color: p.detail)          // the straw
            b.roundedBox(centre: SIMD3(c.x + 0.012 * s, y0 + (h + 0.022) * s, c.z - 0.004 * s), half: SIMD3(0.0037, 0.006, 0.0037) * s, radius: 0.0015 * s, segments: 2, aoFloor: false, color: p.accent)
        }
        b.roundedBox(centre: SIMD3(c.x - 0.01 * s, y0 + (h - 0.008) * s, c.z + 0.006 * s), half: SIMD3(0.008, 0.007, 0.008) * s, radius: 0.003 * s, segments: 2, aoFloor: false, color: SIMD3(0.95, 0.98, 1.0))          // an ice cube
        DiningModels.ellipsoid(b, centre: SIMD3(c.x - 0.03 * s, y0 + (h - 0.004) * s, c.z), rx: 0.01 * s, ry: 0.009 * s, color: p.accent, rings: 3, segments: 8)          // a raspberry on the rim
        DiningModels.ellipsoid(b, centre: SIMD3(c.x - 0.03 * s, y0 + (h + 0.004) * s, c.z), rx: 0.005 * s, ry: 0.003 * s, color: SIMD3(0.45, 0.72, 0.4), rings: 2, segments: 6)
    }

    // MARK: cafe-straw-r1: drinks come in a cup of their own, with a bendy straw to the mouth

    /// The table cup is the café's own cup model drawn this much bigger (the hand-size piece is a bite-sized prop; a drink beside a Jelmiko is a real cup).
    static let cupScale: Float = 4.0
    static func cupHeight(_ t: CafeTreatID) -> Float { t == .juice ? 0.058 : (t == .cocoa ? 0.046 : 0.044) }
    /// Where place `i`'s cup stands (tray-local xz): on the table in front of him, toward the table's middle (an end place: just inside its near edge; the middle place: a little in front of him).
    static func cupCentre(_ L: TrayLayout, place i: Int) -> SIMD2<Float> {
        let p = L.places[i], f = SIMD2(sinf(p.yaw), cosf(p.yaw))
        let d: Float = abs(f.x) < 0.5 ? 0.75 : max(abs(p.rel.x) - 0.40, 0.3) / abs(f.x)
        return p.rel + f * d
    }
    /// The straw from the cup's rim to his mouth: one straight slanted straw that leaves the foam at the cup's centre line and ends exactly on the straw tip (`sipTipXZ`).
    static func mouthStraw(_ L: TrayLayout, place i: Int, rimHeight h: Float) -> [SIMD3<Float>] {
        let c = cupCentre(L, place: i), rimY = DiningDims.trayTop + h * cupScale * L.scale
        let tipXZ = L.sipTipXZ(i), tip = SIMD3<Float>(tipXZ.x, DiningDims.strawTipHeight, tipXZ.y)
        let dh = tipXZ - c, d = simd_length(dh)
        let tanT = d / max(tip.y - rimY, 0.05)
        let dirH = d > 1e-5 ? dh / d : SIMD2<Float>(0, -1)
        let y0 = rimY - 0.04
        let r0 = c - dirH * ((rimY - y0) * tanT)
        let start = SIMD3<Float>(r0.x, y0, r0.y)
        return (0..<24).map { k in k == 23 ? tip : simd_mix(start, tip, SIMD3(repeating: Float(k) / 23)) }
    }
    /// The resting straw (nobody sips from it now): up out of the cup, leaning a little toward his side.
    static func restStraw(_ L: TrayLayout, place i: Int, rimHeight h: Float) -> [SIMD3<Float>] {
        let c = cupCentre(L, place: i), rimY = DiningDims.trayTop + h * cupScale * L.scale
        let to = L.places[i].rel - c, n = simd_length(to), lean = n > 1e-5 ? to / n * 0.07 : SIMD2<Float>(0, -0.07)
        let a = SIMD3<Float>(c.x, DiningDims.trayTop + 0.05, c.y), b = SIMD3<Float>(c.x + lean.x, rimY + 0.15, c.y + lean.y)
        return (0..<12).map { k in simd_mix(a, b, SIMD3(repeating: Float(k) / 11)) }
    }
    static let strawColors: (SIMD3<Float>, SIMD3<Float>) = (Consumables.srgb(0.80, 0.56, 0.36), Consumables.srgb(1.0, 0.97, 0.90))          // (a caramel stripe on cream, the café's colours)
    /// One cup + straw for place `i`. `sipping`: the straw reaches his mouth; else it rests upright.
    static func strawCup(_ b: B, _ L: TrayLayout, place i: Int, treat t: CafeTreatID, sipping: Bool) {
        let c = cupCentre(L, place: i), s = cupScale * L.scale
        let food = Consumables.cafeFood(t)
        food.piece?(b, SIMD3(c.x, DiningDims.trayTop - floorOff * s, c.y), 0, s, food.palette)
        let h = cupHeight(t)
        DiningModels.appendTube(b, centre: sipping ? mouthStraw(L, place: i, rimHeight: h) : restStraw(L, place: i, rimHeight: h), radius: DiningDims.strawRadius * 0.4,
                                color: strawColors.0, stripe: strawColors.1, accordion: true)
    }

    static func procedural(_ id: CafeTreatID) -> PieceBuilder {
        switch id {
        case .cocoa: return cocoa; case .juice: return juice; case .swirl: return swirl; case .fizzmac: return fizzmac; case .pancakes: return pancakes; case .sundae: return sundae; case .jellycup: return jellycup; case .latte: return latte }
    }
}

extension Consumables {
    private static func cafe(_ t: CafeTreatID, symbol: String, _ pal: ConsumablePalette) -> Consumable {
        let fallback = CafeFoodModels.procedural(t)
        let meshed: PieceBuilder = { b, c, j, s, p in
            if !FoodMeshes.append(b, id: t.rawValue, centre: c, variant: j, scale: s) { fallback(b, c, j, s, p) }
        }
        let m = CafeMenu.treat(t)
        var c = Consumable(id: "cafe-\(t.rawValue)", name: m.name, kind: .food, eatStyle: .finger, symbol: symbol, palette: pal, benefits: [.hunger: 0.3, .happy: 0.3],
                           serving: { b, st, p, lay in DiningModels.pieces(b, state: st, palette: p, layout: lay, piece: meshed) })
        c.piece = meshed; c.perk = m.perk; c.condition = m.condition
        return c
    }
    static let cafeSwirl = cafe(.swirl, symbol: "birthday.cake.fill", pal((0.86, 0.64, 0.40), (0.52, 0.30, 0.19), (0.99, 0.96, 0.90), (1, 1, 1)))
    static let cafeFizzmac = cafe(.fizzmac, symbol: "sparkles", pal((0.98, 0.76, 0.60), (1.0, 0.93, 0.82), (0.9, 0.6, 0.45), (1, 0.98, 0.94)))
    static let cafePancakes = cafe(.pancakes, symbol: "fork.knife", pal((0.93, 0.74, 0.46), (0.60, 0.33, 0.14), (1.0, 0.90, 0.55), (1, 1, 1)))
    static let cafeSundae = cafe(.sundae, symbol: "birthday.cake.fill", pal((0.88, 0.68, 0.40), (1.0, 0.95, 0.82), (0.45, 0.28, 0.20), (0.82, 0.16, 0.20)))
    static let cafeJellyCup = cafe(.jellycup, symbol: "cup.and.saucer.fill", pal((0.97, 0.96, 0.94), (1.0, 0.98, 0.95), (0.42, 0.66, 0.98), (0.80, 0.90, 1.0)))
    static let cafeCocoa = cafe(.cocoa, symbol: "mug.fill", pal((0.93, 0.60, 0.64), (0.34, 0.20, 0.14), (1.0, 0.97, 0.93), (0.99, 0.93, 0.84)))
    static let cafeJuice = cafe(.juice, symbol: "wineglass.fill", pal((0.92, 0.30, 0.46), (0.93, 0.96, 0.99), (0.86, 0.15, 0.30), (1.0, 0.82, 0.88)))
    static let cafeLatte = cafe(.latte, symbol: "mug.fill", pal((0.97, 0.93, 0.86), (0.55, 0.36, 0.22), (0.99, 0.93, 0.80), (1, 0.98, 0.92)))

    /// The café's treat as a hand-held food (menu thumbnails and the plate). Not in `Consumables.all`: it is served only at the café.
    static func cafeFood(_ id: CafeTreatID) -> Consumable {
        switch id { case .swirl: return cafeSwirl; case .fizzmac: return cafeFizzmac; case .pancakes: return cafePancakes; case .sundae: return cafeSundae; case .jellycup: return cafeJellyCup; case .latte: return cafeLatte; case .cocoa: return cafeCocoa; case .juice: return cafeJuice }
    }
}

/// One visit's plate: a treat per place. Its `consumable()` is the serving the dining set draws (a unique id per visit so the set's mesh caches never go stale).
nonisolated final class CafePlate: @unchecked Sendable {
    let serial: Int
    let order: CafeOrder
    /// Filled when the group is seated (place -> treat): the group decides who stands where.
    private let lock = NSLock()
    private var byPlace: [Int: CafeTreatID] = [:]

    /// The lounge: one cup in front of each place (a drinker keeps his own drink, a food eater gets cocoa). They "sip" at the table.
    static func cups(_ byPlace: [Int: CafeTreatID], straws: Bool = false) -> Consumable {
        let key = byPlace.sorted { $0.key < $1.key }.map { "\($0.key)\($0.value.rawValue)" }.joined(separator: "-") + (straws ? "-straws" : "")
        return Consumable(id: "cafe-cups-\(key)", name: "Café cups", kind: .food, eatStyle: .finger, symbol: "cup.and.saucer.fill", palette: Consumables.cafeCocoa.palette, benefits: [:],
                          serving: { b, _, _, L in
                              for i in 0..<L.n {
                                  let t = byPlace[i] ?? .cocoa
                                  let drink = CafeMenu.treat(t).category == .drink ? t : CafeTreatID.cocoa
                                  if straws { CafeFoodModels.strawCup(b, L, place: i, treat: drink, sipping: false); continue }          // (cafe-straw-r1: the lounge's cups stand on the table with their straws)
                                  let food = Consumables.cafeFood(drink)
                                  food.piece?(b, DiningModels.berryAnchor(layout: L, place: i, index: 1), 1, L.scale, food.palette)
                              }
                          })
    }

    private func sipConsumable() -> Consumable {
        let plate = self
        var c = Consumable(id: "cafe-sip-\(serial)", name: "Café drinks", kind: .drink, eatStyle: .sip, symbol: "cup.and.saucer.fill", palette: Consumables.cafeCocoa.palette,
                           benefits: [.thirst: 0.3, .happy: 0.3],
                           serving: { b, st, _, L in
                               for i in 0..<L.n { CafeFoodModels.strawCup(b, L, place: i, treat: plate.treat(place: i), sipping: st.bitesLeft.indices.contains(i) && st.bitesLeft[i] > 0) }
                           })
        c.placeServing = c.serving
        c.placeStraw = { L, i in CafeFoodModels.mouthStraw(L, place: i, rimHeight: CafeFoodModels.cupHeight(plate.treat(place: i))) }
        return c
    }

    /// The empty café table that is out from the moment the Jelbies arrive (the food is set down on it at Order).
    static let emptyTable = Consumable(id: "cafe-empty", name: "Café table", kind: .food, eatStyle: .finger, symbol: "cup.and.saucer.fill", palette: Consumables.cafeSwirl.palette,
                                       benefits: [:], serving: { _, _, _, _ in })

    init(order: CafeOrder, serial: Int) { self.order = order; self.serial = serial }

    var treatByPlace: [Int: CafeTreatID] {
        get { lock.lock(); defer { lock.unlock() }; return byPlace }
        set { lock.lock(); byPlace = newValue; lock.unlock() }
    }
    func treat(place: Int) -> CafeTreatID { treatByPlace[place] ?? order.forTable ?? order.picks.values.sorted { $0.rawValue < $1.rawValue }.first ?? .swirl }

    /// cafe-straw-r1: an order of drinks only is sipped through a straw from a cup in front of each place (the home drink pipeline: eatStyle .sip); a mixed order keeps the old serving.
    var allDrinks: Bool {
        let ts: [CafeTreatID] = order.forTable.map { [$0] } ?? Array(order.picks.values)
        return !ts.isEmpty && ts.allSatisfy { CafeMenu.treat($0).category == .drink }
    }

    func consumable() -> Consumable {
        let plate = self
        if allDrinks { return sipConsumable() }
        var c = Consumable(id: "cafe-\(serial)", name: "Café treats", kind: .food, eatStyle: .finger, symbol: "cup.and.saucer.fill", palette: Consumables.cafeSwirl.palette,
                           benefits: [.hunger: 0.3, .happy: 0.3],
                           serving: { b, st, _, L in
                               for i in 0..<L.n {
                                   let eaten = DiningTiming.bitesPerServing - st.bitesLeft[i]
                                   let food = Consumables.cafeFood(plate.treat(place: i))
                                   for j in 0..<3 where j >= eaten && !st.skipped.contains(i * 3 + j) {
                                       food.piece?(b, DiningModels.berryAnchor(layout: L, place: i, index: j), j, L.scale, food.palette)
                                   }
                               }
                           })
        c.placePiece = { b, centre, place, j, s in
            let food = Consumables.cafeFood(plate.treat(place: place))
            food.piece?(b, centre, j, s, food.palette)
        }
        c.piece = { b, centre, j, s, _ in
            let food = Consumables.cafeFood(plate.treat(place: 0))
            food.piece?(b, centre, j, s, food.palette)
        }
        return c
    }
}
