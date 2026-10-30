//
//  CafeFoods.swift
//  The four café-only treats as hand-held foods in the dining style, and the per-visit mixed plate. Each treat is the Blender mesh when its bundled
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

    static func procedural(_ id: CafeTreatID) -> PieceBuilder {
        switch id { case .swirl: return swirl; case .fizzmac: return fizzmac; case .pancakes: return pancakes; case .sundae: return sundae }
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

    /// The café's treat as a hand-held food (menu thumbnails and the plate). Not in `Consumables.all`: it is served only at the café.
    static func cafeFood(_ id: CafeTreatID) -> Consumable {
        switch id { case .swirl: return cafeSwirl; case .fizzmac: return cafeFizzmac; case .pancakes: return cafePancakes; case .sundae: return cafeSundae }
    }
}

/// One visit's plate: a treat per place. Its `consumable()` is the serving the dining set draws (a unique id per visit so the set's mesh caches never go stale).
nonisolated final class CafePlate: @unchecked Sendable {
    let serial: Int
    let order: CafeOrder
    /// Filled when the group is seated (place -> treat): the group decides who stands where.
    private let lock = NSLock()
    private var byPlace: [Int: CafeTreatID] = [:]

    init(order: CafeOrder, serial: Int) { self.order = order; self.serial = serial }

    var treatByPlace: [Int: CafeTreatID] {
        get { lock.lock(); defer { lock.unlock() }; return byPlace }
        set { lock.lock(); byPlace = newValue; lock.unlock() }
    }
    func treat(place: Int) -> CafeTreatID { treatByPlace[place] ?? order.forTable ?? order.picks.values.sorted { $0.rawValue < $1.rawValue }.first ?? .swirl }

    func consumable() -> Consumable {
        let plate = self
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
