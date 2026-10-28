//
//  Consumable.swift
//  The food / drink catalogue (data only) and the ONE shared eating timing.
//  Adding a new food = one new entry here + one serving builder in DiningModels. No animation code changes.
//
//  Servings are SHARED and scaled for N Blobs (N = 1...3): one plate / pizza / drink on a little tray, with 3 bites per Blob
//  (berries: 3 berries each, pizza: 3 slices each) or one bendy straw per Blob (drinks).
//

import simd
import Foundation

nonisolated enum ConsumableKind: String { case food, drink }

/// How it reaches his mouth: `finger` (the piece sticks to the nub, then is flicked into his mouth: EVERY food), `sip` (his own bendy straw).
/// `fork` is RETIRED (user decision 2026-10-17): no catalogue food uses it; the code path is dead and unreachable.
nonisolated enum EatStyle: String { case finger, fork, sip }

nonisolated enum BenefitKey: String, CaseIterable { case hunger, thirst, happy, energy }

/// Shared timing for EVERY food and drink (the user wants one consumption rate). These are global constants, not per-item fields.
nonisolated enum DiningTiming {
    static let bitesPerServing = 3                  // per Blob
    static let gulpsPerDrink = 3                    // per Blob
    /// Style guide: beats run at about 1.5 per second.
    static let beatsPerSecond: Float = 1.5
    static var beatPeriod: Float { 1 / beatsPerSecond }
    /// One bite = grab/lift beat + chew beat.
    static let beatsPerBite = 2
    static var biteDuration: Float { Float(beatsPerBite) * beatPeriod }
    /// One gulp = one beat (a tip back and a squash pulse).
    static let beatsPerGulp = 1
    static var gulpDuration: Float { Float(beatsPerGulp) * beatPeriod }
    static var servingDuration: Float { Float(bitesPerServing) * biteDuration }
    static var drinkDuration: Float { Float(gulpsPerDrink) * gulpDuration }
    /// The serving grows a little with every extra Blob ("the bottle is a little bigger").
    static let servingScales: [Float] = [1.0, 1.15, 1.3]
    static func servingScale(n: Int) -> Float { servingScales[min(max(n, 1), 3) - 1] }
}

/// How much he eats or drinks, by how hungry / thirsty he is (Nintendogs style). The serving is 3 pieces (bites / gulps) per Blob.
/// Full / Quenched refuses (0), Normal takes a little (1), Hungry a lot (2), Famished / Parched the whole thing (3) and eagerly (`pace`).
nonisolated enum MealAppetite {
    static func pieces(_ t: NeedTier) -> Int {
        switch t { case .full: return 0; case .normal: return 1; case .hungry: return 2; case .famished: return DiningTiming.bitesPerServing }
    }
    /// Speed of the bite / gulp beats: 1 = the shared rate, eager = a shorter beat between bites.
    static func pace(_ t: NeedTier) -> Float { t == .famished ? 1.3 : 1 }
    /// Each piece eaten adds this to the need: a whole serving from Famished (< 0.2) ends at Full (>= 0.85 for sure), Normal + 1 bite lands 0.8...1.
    static let gainPerPiece: Float = 0.3
    static func refusalText(_ k: NeedKind) -> String { k == .thirst ? "Not thirsty" : "Not hungry" }
}

/// Everything a model builder needs. Colours are linear RGB.
nonisolated struct ConsumablePalette {
    var primary: SIMD3<Float>
    var secondary: SIMD3<Float>
    var accent: SIMD3<Float>
    var detail: SIMD3<Float>
}

/// What a food builder is asked to draw: N Blobs, bites left per Blob, pieces in hands (global index = place * 3 + j).
nonisolated struct ServingState {
    var n: Int
    var bitesLeft: [Int]
    var skipped: Set<Int> = []
    var scale: Float { DiningTiming.servingScale(n: n) }
    var totalLeft: Int { bitesLeft.reduce(0, +) }
}

/// Builds the shared food serving in TRAY-LOCAL coordinates (origin on the floor under the tray centre, tray top at DiningDims.trayTop).
typealias FoodServingBuilder = @Sendable (_ b: RoomMeshBuilder, _ state: ServingState, _ palette: ConsumablePalette, _ layout: TrayLayout) -> Void

/// A drink's container, in model space (origin at the bottom centre), plus where its opening is.
nonisolated struct ContainerModel {
    var opaque: RoomMesh
    var translucent: RoomMesh = RoomMesh()
    var openingY: Float                    // height of the opening above the container base
    var openingRadius: Float               // how far from the axis a straw can stand
}
/// `fill`: 1 = full ... 0 = empty (the drink level; the group passes bites left / (gulps x n)).
typealias ContainerBuilder = @Sendable (_ n: Int, _ palette: ConsumablePalette, _ fill: Float) -> ContainerModel

/// One piece of a plate food, built around its centre `c` (tray-local), `j` = which of a Jelly's three, `s` = the serving scale.
typealias PieceBuilder = @Sendable (_ b: RoomMeshBuilder, _ c: SIMD3<Float>, _ j: Int, _ s: Float, _ p: ConsumablePalette) -> Void
/// A mixed plate (the café): a piece builder chosen by PLACE (place, j = which of his three, s = the serving scale), built around the centre `c`.
typealias PlacePieceBuilder = @Sendable (_ b: RoomMeshBuilder, _ c: SIMD3<Float>, _ place: Int, _ j: Int, _ s: Float) -> Void

nonisolated struct Consumable {
    let id: String
    let name: String
    let kind: ConsumableKind
    let eatStyle: EatStyle
    /// SF Symbol for the menu.
    let symbol: String
    let palette: ConsumablePalette
    /// Stored but unused until stats exist.
    let benefits: [BenefitKey: Float]
    /// Foods: the shared serving builder (N, bites left).
    var serving: FoodServingBuilder? = nil
    /// Drinks: the container builder (N) and the straw's stripe colours.
    var container: ContainerBuilder? = nil
    var strawColors: (SIMD3<Float>, SIMD3<Float>)? = nil
    /// Store foods: fed from the inventory (not in the free Feed picker), one piece builder for the plate and the hand, the pizza fan layout or the
    /// berry ring, what it does for him (perk) and his condition, and the sound of a bite.
    var stored = false
    var pizzaLayout = false
    var piece: PieceBuilder? = nil
    /// The café's mixed plate: a different treat per place (set with `piece`; the held piece and the plate use it when present).
    var placePiece: PlacePieceBuilder? = nil
    var perk: PerkKind? = nil
    var condition: [ConditionKey: Float] = [:]
    var chew: SFX = .chomp
    var storeID: String? = nil
    /// Drinks: the straw's thickness relative to the standard straw (the bought drinks use a slim one), and how far (tray-local x, one Jelbie) the cup stands
    /// to his right of the standard bottle spot: a big cup beside the mouth would hide it.
    var thinStraw: Float = 1
    var cupSide: Float = 0
}

nonisolated enum Consumables {
    static func srgb(_ r: Float, _ g: Float, _ b: Float) -> SIMD3<Float> { OKLab.srgbToLinear(SIMD3(r, g, b)) }

    static let berries = Consumable(
        id: "berries", name: "Berries", kind: .food, eatStyle: .finger, symbol: "circle.hexagongrid.fill",
        palette: ConsumablePalette(primary: srgb(0.96, 0.58, 0.66), secondary: srgb(0.74, 0.62, 0.92), accent: srgb(0.60, 0.74, 0.96),
                                   detail: srgb(0.62, 0.84, 0.62)),
        benefits: [.hunger: 0.3, .happy: 0.1],
        serving: { b, st, pal, lay in DiningModels.berries(b, state: st, palette: pal, layout: lay) })

    static let pizza = Consumable(
        id: "pizza", name: "Pizza", kind: .food, eatStyle: .finger, symbol: "triangle.fill",
        palette: ConsumablePalette(primary: srgb(0.93, 0.74, 0.50), secondary: srgb(1.0, 0.88, 0.55), accent: srgb(0.92, 0.50, 0.46),
                                   detail: srgb(1.0, 0.96, 0.78)),
        benefits: [.hunger: 0.3, .happy: 0.2],
        serving: { b, st, pal, lay in DiningModels.pizza(b, state: st, palette: pal, layout: lay) })

    static let water = Consumable(
        id: "water", name: "Water", kind: .drink, eatStyle: .sip, symbol: "waterbottle.fill",
        palette: ConsumablePalette(primary: srgb(0.52, 0.76, 0.96), secondary: srgb(0.86, 0.94, 1.0), accent: srgb(0.70, 0.88, 1.0),
                                   detail: srgb(1.0, 1.0, 1.0)),
        benefits: [.thirst: 0.4],
        container: { n, pal, fill in DiningModels.waterBottle(n: n, palette: pal, fill: fill) },
        strawColors: (srgb(0.98, 0.70, 0.78), srgb(1.0, 1.0, 1.0)))

    static let soda = Consumable(
        id: "soda", name: "Soda", kind: .drink, eatStyle: .sip, symbol: "bubbles.and.sparkles.fill",
        palette: ConsumablePalette(primary: srgb(0.96, 0.60, 0.74), secondary: srgb(1.0, 0.84, 0.90), accent: srgb(0.86, 0.42, 0.62),
                                   detail: srgb(1.0, 0.97, 0.94)),
        benefits: [.thirst: 0.25, .happy: 0.3, .energy: 0.2],
        container: { n, pal, fill in DiningModels.sodaBottle(n: n, palette: pal, fill: fill) },
        strawColors: (srgb(0.62, 0.84, 0.96), srgb(1.0, 1.0, 1.0)))

    /// Menu order.
    static let all: [Consumable] = [berries, pizza, water, soda] + storeFoods + storeDrinks
    /// The FREE foods of the Feed picker (store foods are fed from the inventory).
    static var foods: [Consumable] { all.filter { $0.kind == .food && !$0.stored } }
    /// The FREE drinks (water, soda). The store's drinks (`storeDrinks`) are offered from the bag: `GameCare.drinkChoices`.
    static var drinks: [Consumable] { all.filter { $0.kind == .drink && !$0.stored } }
    static func with(id: String) -> Consumable? { all.first { $0.id == id } }
}
