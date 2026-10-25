//
//  GardenStore.swift
//  The Garden's goods: five seed packets (cheap, in the Shop's Seeds tab and the bag; counts live in the store's `counts` like every stacked good, so no
//  save format changes) and the two harvest foods (strawberries, garden blueberries). The harvest foods are earned by growing them, never sold, and feed
//  through the normal hand-held food flow (three pieces per Jelbie, group serving rules, perks) like the store's other snacks.
//

import simd
import Foundation

extension StoreCatalog {
    static let gardenItems: [StoreItem] = GardenPlant.allCases.map { k in
        StoreItem(id: k.seedID, name: "\(k.title) seeds", kind: .seed, price: k.seedPrice, perk: nil, description: k.blurb + " Plant them in the Garden.", symbol: k.symbol)
    } + [
        StoreItem(id: "strawberry", name: "Garden strawberries", kind: .food, price: 0, perk: .cozy, description: "Sweet, home-grown. Stays happy longer for 4 hours.",
                  symbol: "fork.knife", food: "strawberry", awarded: true),
        StoreItem(id: "gardenberries", name: "Garden blueberries", kind: .food, price: 0, perk: .bouncy, description: "Juicy, home-grown. More bouncing for an hour.",
                  symbol: "fork.knife", food: "gardenberries", awarded: true),
    ]
}

nonisolated enum GardenFoodModels {
    private static let floorOff = StoreFoodModels.floorOff

    /// A strawberry: a plump red cone-ish body with yellow seeds and a green leafy top.
    static func strawberry(_ b: RoomMeshBuilder, _ c: SIMD3<Float>, _ j: Int, _ s: Float, _ p: ConsumablePalette) {
        let y = c.y + floorOff * s + 0.05 * s
        DiningModels.ellipsoid(b, centre: SIMD3(c.x, y, c.z), rx: 0.046 * s, ry: 0.052 * s, color: p.primary, rings: 5, segments: 12)
        DiningModels.ellipsoid(b, centre: SIMD3(c.x, y - 0.03 * s, c.z), rx: 0.03 * s, ry: 0.03 * s, color: p.primary * 0.95, rings: 4, segments: 10)
        for k in 0..<7 {
            let a = Float(k) * 0.9 + Float(j)
            let h = Float(k % 3) * 0.025 - 0.02
            DiningModels.ellipsoid(b, centre: SIMD3(c.x + cosf(a) * 0.043 * s, y + h * s, c.z + sinf(a) * 0.043 * s), rx: 0.006 * s, ry: 0.007 * s, color: p.detail, rings: 2, segments: 5)
        }
        for k in 0..<5 {
            let a = Float(k) / 5 * 2 * .pi
            DiningModels.ellipsoid(b, centre: SIMD3(c.x + cosf(a) * 0.026 * s, y + 0.05 * s, c.z + sinf(a) * 0.026 * s), rx: 0.02 * s, ry: 0.006 * s, color: p.secondary, rings: 2, segments: 6)
        }
    }

    /// A little cluster of blueberries (three plump ones, a dusty bloom on each).
    static func berries(_ b: RoomMeshBuilder, _ c: SIMD3<Float>, _ j: Int, _ s: Float, _ p: ConsumablePalette) {
        let y = c.y + floorOff * s
        let spots: [(Float, Float, Float)] = [(0, 0, 0.036), (0.05, 0.012, 0.032), (-0.03, 0.045, 0.03), (-0.04, -0.03, 0.028)]
        for (i, o) in spots.enumerated() {
            let r = o.2 * s
            DiningModels.ellipsoid(b, centre: SIMD3(c.x + o.0 * s, y + r, c.z + o.1 * s), rx: r, ry: r * 0.95, color: p.primary * (0.92 + 0.08 * Float((i + j) % 3)), rings: 4, segments: 10)
            DiningModels.ellipsoid(b, centre: SIMD3(c.x + o.0 * s, y + r * 1.85, c.z + o.1 * s), rx: r * 0.3, ry: r * 0.08, color: p.accent, rings: 2, segments: 6)
        }
    }
}

extension Consumables {
    static let strawberry = food("strawberry", "Garden strawberries", symbol: "fork.knife", pal((0.94, 0.28, 0.32), (0.36, 0.64, 0.30), (0.99, 0.90, 0.50), (0.99, 0.90, 0.50)),
                                 perk: .cozy, cond: [.sweet: 0.12, .cute: 0.08], piece: GardenFoodModels.strawberry)
    static let gardenberries = food("gardenberries", "Garden blueberries", symbol: "fork.knife", pal((0.38, 0.46, 0.84), (0.40, 0.66, 0.34), (0.78, 0.82, 0.96), (1, 1, 1)),
                                    perk: .bouncy, cond: [.sparkle: 0.08, .sporty: 0.06], piece: GardenFoodModels.berries)
    static let gardenFoods: [Consumable] = [strawberry, gardenberries]
}
