//
//  DecorKind+Batch3.swift
//  The third batch of furniture and toys (2026-10-24, "more shop items"): the numbers each new piece needs (footprint, height, spots, what a Jelly does with it,
//  its words). They are made in Blender (tools/make_decor_batch3, the same OBJ -> decor_<id>.bin pipeline as the rest) and posed in DecorModels+Batch3.swift.
//  Every piece works in any room (nothing here knows which room it is in) and uses a behaviour the Jellies already have: boop, peek, hop-sit.
//

import simd
import Foundation

extension DecorKind {
    static let batch3Furniture: [DecorKind] = [.roundtable, .cushionpile, .aquarium, .plantstand, .easel, .mirror, .clock]
    static let batch3Toys: [DecorKind] = [.bubblemachine, .rockinghorse, .jackinbox, .plushbear, .toypiano, .pinwheel]
    static let batch3: [DecorKind] = batch3Furniture + batch3Toys
    /// Pieces with a front only (he stands in front of the glass / the mirror, not behind it).
    static let batch3FrontOnly: Set<DecorKind> = [.aquarium, .mirror]

    /// Footprints are the exports' JSON `footprint_half` / `height` / `spots` (the sub-mesh bounds may stick out: fern fronds, the horse's runners, the mirror's props).
    var batch3Spec: DecorSpec {
        switch self {
        case .roundtable: return DecorSpec(half: SIMD2(0.64, 0.64), height: 1.30, solid: true, units: 1, corner: 0.64, reach: 1, box: true)
        case .cushionpile: return DecorSpec(half: SIMD2(0.72, 0.62), height: 0.66, solid: true, units: 1, corner: 0.3, reach: 1, box: true)
        case .aquarium: return DecorSpec(half: SIMD2(0.62, 0.34), height: 1.42, solid: true, units: 2, corner: 0.05, reach: 1, box: true)
        case .plantstand: return DecorSpec(half: SIMD2(0.33, 0.33), height: 1.72, solid: true, units: 1, corner: 0.33, reach: 1, box: true)
        case .easel: return DecorSpec(half: SIMD2(0.55, 0.48), height: 1.56, solid: true, units: 1, corner: 0.1, reach: 1, box: true)
        case .mirror: return DecorSpec(half: SIMD2(0.40, 0.42), height: 1.70, solid: true, units: 1, corner: 0.05, reach: 1, box: true)
        case .clock: return DecorSpec(half: SIMD2(0.38, 0.28), height: 1.70, solid: true, units: 1, corner: 0.05, reach: 1, box: true)
        case .bubblemachine: return DecorSpec(half: SIMD2(0.38, 0.30), height: 0.86, solid: true, units: 1, corner: 0.1, reach: 1, box: true)
        case .rockinghorse: return DecorSpec(half: SIMD2(0.78, 0.30), height: 1.40, solid: true, units: 2, corner: 0.15, reach: 1, box: true)
        case .jackinbox: return DecorSpec(half: SIMD2(0.31, 0.31), height: 0.78, solid: true, units: 1, corner: 0.1, reach: 1, box: true)
        case .plushbear: return DecorSpec(half: SIMD2(0.44, 0.40), height: 1.18, solid: true, units: 1, corner: 0.3, reach: 1, box: true)
        case .toypiano: return DecorSpec(half: SIMD2(0.56, 0.32), height: 0.98, solid: true, units: 1, corner: 0.05, reach: 1, box: true)
        case .pinwheel: return DecorSpec(half: SIMD2(0.30, 0.30), height: 1.55, solid: true, units: 1, corner: 0.3, reach: 1, box: true)
        default: return DecorSpec(half: SIMD2(0.4, 0.4), height: 1, solid: true, units: 1, corner: 0.2, reach: 1, box: true)
        }
    }
    /// The cushion pile is hopped onto and sat on (its soft top, 0.60 up).
    var batch3SitPoints: [SIMD3<Float>] { self == .cushionpile ? [SIMD3(0, 0.60, 0)] : [] }
    var batch3Interaction: IdleKind? {
        switch self {
        case .cushionpile: return .decorSit
        case .plantstand, .clock, .bubblemachine, .rockinghorse, .jackinbox, .plushbear, .toypiano, .pinwheel: return .decorBoop
        case .easel, .mirror, .aquarium: return .decorPeek
        default: return nil
        }
    }
    var batch3Title: String {
        switch self {
        case .roundtable: return "Round table"; case .cushionpile: return "Cushion pile"; case .aquarium: return "Aquarium"; case .plantstand: return "Fern stand"
        case .easel: return "Art easel"; case .mirror: return "Standing mirror"; case .clock: return "Grandfather clock"
        case .bubblemachine: return "Bubble machine"; case .rockinghorse: return "Rocking horse"; case .jackinbox: return "Jack-in-the-box"
        case .plushbear: return "Plush bear"; case .toypiano: return "Toy piano"; case .pinwheel: return "Pinwheel"
        default: return rawValue.capitalized
        }
    }
    var batch3Use: String {
        switch self {
        case .roundtable: return "A little round table with a vase of flowers."
        case .cushionpile: return "A squashy stack of cushions. Jelbies hop on and sit."
        case .aquarium: return "A fish tank. Jelbies lean in to watch, and the fish dart about."
        case .plantstand: return "A fern on a stand. Jelbies boop it and the fronds sway."
        case .easel: return "A painting on an easel. Jelbies step up to look."
        case .mirror: return "A tall mirror. Jelbies lean in for a look at themselves."
        case .clock: return "A grandfather clock. Boop it and the pendulum swings."
        case .bubblemachine: return "Boop it and the fan whirrs, blowing a stream of bubbles."
        case .rockinghorse: return "Boop it and it rocks back and forth."
        case .jackinbox: return "Boop it, the crank turns and a clown springs out."
        case .plushbear: return "A big squishy bear. A boop sets it wobbling."
        case .toypiano: return "Boop the keys and they ripple up the scale."
        case .pinwheel: return "Boop it and the pinwheel spins and spins."
        default: return ""
        }
    }
    /// The shop symbols (SF Symbols) and Drops prices of the batch (earned currency; furniture 45...110, toys 35...75).
    static let batch3Shop: [(DecorKind, Int, String)] = [
        (.roundtable, 55, "circle.circle"), (.cushionpile, 45, "square.stack.3d.up.fill"), (.aquarium, 110, "fish.fill"), (.plantstand, 50, "leaf.fill"),
        (.easel, 55, "paintbrush.pointed.fill"), (.mirror, 65, "mirror.side.left"), (.clock, 90, "clock.fill"),
        (.bubblemachine, 60, "bubbles.and.sparkles.fill"), (.rockinghorse, 75, "figure.equestrian.sports"), (.jackinbox, 45, "gift.fill"),
        (.plushbear, 40, "teddybear.fill"), (.toypiano, 65, "pianokeys"), (.pinwheel, 35, "fanblades.fill"),
    ]
}
