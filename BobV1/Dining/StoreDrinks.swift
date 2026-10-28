//
//  StoreDrinks.swift
//  The store's drinks: boba milk tea, berry smoothie, pink lemonade and hot cocoa. Sipped through the same bendy straw as water and soda
//  (eatStyle .sip: the straw comes to his mouth, no arm ever reaches), but they are bought, kept in the bag, and give a perk.
//  The cup, the pearls, the ice, the marshmallows and the garnish are Blender meshes (tools/make_food4/drinks4.py, bundled as food_drink_<id>_<part>.bin);
//  only the liquid column is built here, because it has to drop with every sip. Heights are authored in game units (no stretch like the
//  bottles' 0.48): the cup stays the same height for 1...3 Jelbies and gets wider (the group scales by `servingScale`).
//

import simd
import Foundation

nonisolated enum StoreDrinkModels {
    struct Spec {
        /// Inner wall (radius, height) the liquid column follows; the first point is on the axis at the cup's inner floor.
        var wall: DiningModels.Wall
        var full: Float, empty: Float, top: Float, rim: Float
        /// An opaque liquid (the smoothie, the cocoa in its mug) is drawn with the solid parts; the others are seen through the glass.
        var opaque: Bool
        var color: SIMD3<Float>, surface: SIMD3<Float>
        var alpha: Float, shellAlpha: Float, iceAlpha: Float
    }
    private static func c(_ r: Float, _ g: Float, _ b: Float) -> SIMD3<Float> { Consumables.srgb(r, g, b) }

    static let specs: [String: Spec] = [
        "boba": Spec(wall: [(0, 0.014), (0.080, 0.014), (0.104, 0.29)], full: 0.25, empty: 0.05, top: 0.30, rim: 0.104, opaque: false,
                     color: c(0.86, 0.66, 0.44), surface: c(0.92, 0.74, 0.52), alpha: 0.82, shellAlpha: 0.30, iceAlpha: 0.75),
        "smoothie": Spec(wall: [(0, 0.02), (0.090, 0.02), (0.102, 0.034), (0.104, 0.27)], full: 0.235, empty: 0.055, top: 0.27, rim: 0.104, opaque: true,
                         color: c(0.92, 0.38, 0.58), surface: c(0.98, 0.52, 0.70), alpha: 1, shellAlpha: 0.30, iceAlpha: 1),
        "lemonade": Spec(wall: [(0, 0.032), (0.076, 0.032), (0.100, 0.27)], full: 0.23, empty: 0.065, top: 0.278, rim: 0.100, opaque: false,
                         color: c(1.0, 0.50, 0.64), surface: c(1.0, 0.70, 0.78), alpha: 0.80, shellAlpha: 0.36, iceAlpha: 0.62),
        "cocoa": Spec(wall: [(0, 0.022), (0.088, 0.022), (0.096, 0.04), (0.096, 0.20)], full: 0.175, empty: 0.055, top: 0.20, rim: 0.096, opaque: true,
                      color: c(0.42, 0.22, 0.14), surface: c(0.52, 0.30, 0.20), alpha: 1, shellAlpha: 1, iceAlpha: 1),
    ]

    private static func part(_ id: String, _ p: String) -> RoomMesh? { FoodMeshes.mesh(id: "drink_\(id)_\(p)") }

    /// The drink as the tray draws it. `fill` 1 = full ... 0 = empty; the level and everything riding it drops with it.
    static func container(_ id: String, n: Int, fill: Float) -> ContainerModel {
        guard let sp = specs[id] else { return ContainerModel(opaque: RoomMesh(), openingY: 0.25, openingRadius: 0.1) }
        let level = sp.empty + (sp.full - sp.empty) * min(max(fill, 0), 1)
        let dy = level - sp.full
        let o = RoomMeshBuilder(); o.material = .plain
        let t = RoomMeshBuilder(); t.material = .plain
        let id4 = matrix_identity_float4x4
        let lift = DiningModels.translation(SIMD3(0, dy, 0))
        // the liquid column (built here so it follows the sips)
        if fill > 0.001 {
            if sp.opaque {
                DiningModels.liquid(o, wall: sp.wall, inset: 0.008, y0: sp.wall[0].y, level: level, color: sp.color, surface: sp.surface)
            } else {
                let l = RoomMeshBuilder(); l.material = .plain
                DiningModels.liquid(l, wall: sp.wall, inset: 0.008, y0: sp.wall[0].y, level: level, color: sp.color, surface: sp.surface)
                DiningModels.append(l.mesh, to: t, transform: id4, alpha: sp.alpha)
            }
        }
        if let m = part(id, "deco") { DiningModels.append(m, to: o, transform: id4) }
        if fill > 0.001, let m = part(id, "float") { DiningModels.append(m, to: o, transform: lift) }
        if let m = part(id, "shell") { DiningModels.append(m, to: t, transform: id4, alpha: sp.shellAlpha) }
        if fill > 0.001, let m = part(id, "ice") { DiningModels.append(m, to: t, transform: lift, alpha: sp.iceAlpha) }
        // heights do NOT grow with N (the straw tips stay at his mouth height); widths do
        let k = 1 / DiningTiming.servingScale(n: n)
        return ContainerModel(opaque: DiningModels.stretchY(o.mesh, k), translucent: DiningModels.stretchY(t.mesh, k), openingY: sp.top * k, openingRadius: sp.rim)
    }
}

extension Consumables {
    private static func drink(_ id: String, _ name: String, symbol: String, _ pal: ConsumablePalette, straw: (SIMD3<Float>, SIMD3<Float>), perk: PerkKind,
                              cond: [ConditionKey: Float]) -> Consumable {
        Consumable(id: id, name: name, kind: .drink, eatStyle: .sip, symbol: symbol, palette: pal, benefits: [.thirst: 0.4, .happy: 0.1],
                   container: { n, _, fill in StoreDrinkModels.container(id, n: n, fill: fill) }, strawColors: straw,
                   stored: true, perk: perk, condition: cond, storeID: id)
    }

    static let boba = drink("boba", "Boba tea", symbol: "cup.and.saucer.fill", pal((0.86, 0.66, 0.44), (0.92, 0.74, 0.52), (1.0, 0.62, 0.76), (0.17, 0.10, 0.09)),
                            straw: (srgb(1.0, 0.62, 0.76), srgb(1, 1, 1)), perk: .social, cond: [.cute: 0.10, .sweet: 0.08])
    static let smoothie = drink("smoothie", "Berry smoothie", symbol: "cup.and.saucer.fill", pal((0.92, 0.38, 0.58), (0.98, 0.52, 0.70), (0.30, 0.34, 0.74), (0.38, 0.72, 0.30)),
                                straw: (srgb(0.60, 0.84, 0.70), srgb(1, 1, 1)), perk: .fullBelly, cond: [.sweet: 0.10, .sporty: 0.06])
    static let lemonade = drink("lemonade", "Pink lemonade", symbol: "cup.and.saucer.fill", pal((1.0, 0.62, 0.72), (1.0, 0.76, 0.84), (1.0, 0.92, 0.35), (0.30, 0.68, 0.34)),
                                straw: (srgb(1.0, 0.92, 0.45), srgb(1, 1, 1)), perk: .bouncy, cond: [.sparkle: 0.08, .cool: 0.08])
    static let cocoa = drink("cocoa", "Hot cocoa", symbol: "mug.fill", pal((0.42, 0.22, 0.14), (0.52, 0.30, 0.20), (0.99, 0.80, 0.86), (1.0, 0.97, 0.96)),
                             straw: (srgb(0.98, 0.70, 0.78), srgb(1, 1, 1)), perk: .bedtime, cond: [.cute: 0.10, .sweet: 0.06])

    /// The bought drinks (kept in the bag, offered in the care menu's drink picker next to water and soda).
    static let storeDrinks: [Consumable] = [boba, smoothie, lemonade, cocoa]
}
