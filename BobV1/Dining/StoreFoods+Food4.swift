//
//  StoreFoods+Food4.swift
//  Store sweep 4: eight more hand-held foods and treats (cheeseburger, ramen bowl, mac & cheese, dumplings, pancake stack, fruit cup, strawberry cake slice,
//  frosted cupcake). Each is a Blender mesh (tools/make_food4/foods4.py -> food_<id>.bin), one piece on the plate (three per Jelly), tossed into his mouth by
//  the finger-food flow like every other store food. `fallbackPiece` only draws if a bundled mesh is missing.
//

import simd
import Foundation

extension StoreFoodModels {
    /// A plain soft block in the food's colour: the stand-in when a bundled mesh does not load (never drawn in a normal build).
    static func fallbackPiece(_ b: B, _ c: SIMD3<Float>, _ j: Int, _ s: Float, _ p: ConsumablePalette) {
        b.roundedBox(centre: SIMD3(c.x, c.y + (floorOff + 0.03) * s, c.z), half: SIMD3(0.06, 0.03, 0.05) * s, radius: 0.02 * s, segments: 2, aoFloor: false, color: p.primary)
    }
}

extension Consumables {
    private static func food4(_ id: String, _ name: String, symbol: String = "fork.knife", _ pal: ConsumablePalette, perk: PerkKind, cond: [ConditionKey: Float]) -> Consumable {
        food(id, name, symbol: symbol, pal, perk: perk, cond: cond, piece: StoreFoodModels.fallbackPiece)
    }

    static let cheeseburger = food4("cheeseburger", "Cheeseburger", pal((0.96, 0.70, 0.36), (0.52, 0.80, 0.34), (0.90, 0.22, 0.20), (1.0, 0.80, 0.18)),
                                    perk: .fullBelly, cond: [.sporty: 0.10, .cool: 0.06])
    static let ramen = food4("ramen", "Ramen bowl", pal((0.97, 0.94, 0.88), (1.0, 0.86, 0.45), (0.80, 0.16, 0.18), (0.48, 0.78, 0.30)),
                             perk: .cozy, cond: [.cool: 0.08, .cute: 0.08])
    static let macncheese = food4("macncheese", "Mac & cheese", pal((0.62, 0.80, 0.94), (1.0, 0.76, 0.22), (1.0, 0.70, 0.14), (0.45, 0.72, 0.30)),
                                  perk: .social, cond: [.sweet: 0.08, .cute: 0.08])
    static let dumplings = food4("dumplings", "Dumplings", pal((0.88, 0.70, 0.42), (1.0, 0.96, 0.88), (0.62, 0.84, 0.42), (0.14, 0.12, 0.10)),
                                 perk: .focus, cond: [.cool: 0.08, .sparkle: 0.06])
    static let pancakestack = food4("pancakestack", "Pancake stack", pal((0.94, 0.72, 0.38), (0.82, 0.38, 0.09), (1.0, 0.92, 0.55), (0.92, 0.14, 0.22)),
                                    perk: .zoomies, cond: [.sweet: 0.12, .sporty: 0.06])
    static let fruitcup = food4("fruitcup", "Fruit cup", symbol: "birthday.cake.fill", pal((0.62, 0.84, 0.96), (1.0, 0.62, 0.14), (0.92, 0.14, 0.22), (0.30, 0.34, 0.74)),
                                perk: .shine, cond: [.sparkle: 0.10, .sweet: 0.06])
    static let cakeslice = food4("cakeslice", "Strawberry cake", symbol: "birthday.cake.fill", pal((1.0, 0.62, 0.72), (0.98, 0.84, 0.62), (0.92, 0.14, 0.22), (1.0, 0.97, 0.92)),
                                 perk: .cozy, cond: [.sweet: 0.14, .cute: 0.06])
    static let cupcake = food4("cupcake", "Frosted cupcake", symbol: "birthday.cake.fill", pal((1.0, 0.70, 0.80), (0.96, 0.58, 0.70), (0.85, 0.08, 0.16), (1.0, 0.9, 0.3)),
                               perk: .bouncy, cond: [.cute: 0.10, .sweet: 0.08])

    static let storeFoods4: [Consumable] = [cheeseburger, ramen, macncheese, dumplings, pancakestack, fruitcup, cakeslice, cupcake]
}

// MARK: - Shop thumbnails for the new foods and the drinks

extension StoreThumb {
    /// A store food's thumbnail mesh: the mini pizza shows the WHOLE pie (the plate and the hand use single slices); a drink shows the full cup.
    static func foodMesh(_ c: Consumable) -> RoomMesh {
        if c.id == "minipizza", let whole = FoodMeshes.mesh(id: "minipizza_whole") { return whole }
        if c.id == "pizza" { return pizzaThumbMesh() }
        if c.id == "berries" { return DiningModels.berryCluster(palette: c.palette, scale: 1.5) }
        if c.kind == .drink { return DiningModels.containerModel(c, layout: DiningLayout.make(n: 1), palette: thumbPalette(c))?.opaque ?? RoomMesh() }
        return DiningModels.heldPiece(c, index: 0, scale: 1.25)
    }
    /// The translucent part of a drink's thumbnail (the glass and its contents).
    static func glassMesh(_ c: Consumable) -> RoomMesh? {
        guard c.kind == .drink else { return nil }
        return DiningModels.containerModel(c, layout: DiningLayout.make(n: 1), palette: thumbPalette(c))?.translucent
    }
    /// Water and soda are pale in the room (tiny, on a tray); on a card the glass needs a clearly coloured drink in it.
    static func thumbPalette(_ c: Consumable) -> ConsumablePalette? {
        func s(_ r: Float, _ g: Float, _ b: Float) -> SIMD3<Float> { Consumables.srgb(r, g, b) }
        switch c.id {
        case "water": return ConsumablePalette(primary: s(0.18, 0.55, 0.95), secondary: s(0.60, 0.82, 1.0), accent: s(0.25, 0.65, 1.0), detail: s(0.35, 0.65, 0.98))
        case "soda": return ConsumablePalette(primary: s(0.93, 0.25, 0.50), secondary: s(1.0, 0.70, 0.82), accent: s(0.80, 0.15, 0.40), detail: s(1.0, 0.92, 0.95))
        default: return nil
        }
    }
    /// A big warm slice for the card: golden crust, red sauce showing round the cheese, pepperoni (the mini pizza is the whole pie, so the two read differently).
    static func pizzaThumbMesh() -> RoomMesh {
        func s(_ r: Float, _ g: Float, _ b: Float) -> SIMD3<Float> { Consumables.srgb(r, g, b) }
        let pal = ConsumablePalette(primary: s(0.84, 0.52, 0.18), secondary: s(1.0, 0.76, 0.26), accent: s(0.80, 0.14, 0.12), detail: s(1.0, 0.9, 0.6))
        let sc: Float = 1.7
        let b = RoomMeshBuilder(); b.material = .plain
        let hl = DiningModels.sliceHalfLength, hw = DiningModels.sliceHalfWidth
        DiningModels.extrudeRounded(b, poly: [SIMD2(0, (hl + 0.016) * sc), SIMD2(-(hw + 0.016) * sc, -hl * sc), SIMD2((hw + 0.016) * sc, -hl * sc)],
                                    y0: -0.026 * sc, y1: 0.004 * sc, bevel: 0.016 * sc, color: s(0.78, 0.16, 0.10))
        DiningModels.pizzaSlice(b, centre: .zero, yaw: 0, palette: pal, scale: sc)
        // a plump slice: wider and a little thicker than the one in his hand, so the card is filled with cheese and pepperoni
        let out = RoomMeshBuilder(); out.material = .plain
        let fat = simd_float4x4(diagonal: SIMD4<Float>(1.55, 1.5, 1.0, 1))
        DiningModels.append(b.mesh, to: out, transform: fat)
        return out.mesh
    }
}
