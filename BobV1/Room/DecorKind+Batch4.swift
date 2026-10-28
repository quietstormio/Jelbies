//
//  DecorKind+Batch4.swift
//  The fourth batch of toys (2026-10-27, "store sweep: toys"): the numbers each new piece needs (footprint, height, spots, what a Jelly does with it, its words).
//  They are made in Blender (tools/make_decor_batch4, the same OBJ -> decor_<id>.bin pipeline as the rest) and posed in DecorModels+Batch4.swift.
//  Every piece uses a behaviour the Jellies already have: the beach ball is kicked and passed like the ball, the tunnel is peeked into like the toy box,
//  the rest are boops (the rocket rocks like the rocking horse, the dino wobbles like the plush bear, the rings wobble on their post, the scooter dings).
//

import simd
import Foundation

extension DecorKind {
    static let batch4Toys: [DecorKind] = [.beachball, .playtunnel, .ringstacker, .toyrocket, .plushdino, .kickscooter]
    static let batch4: [DecorKind] = batch4Toys

    /// Footprints are the exports' JSON `footprint_half` / `height` / `spots`.
    var batch4Spec: DecorSpec {
        switch self {
        case .beachball: return DecorSpec(half: SIMD2(0.34, 0.34), height: 0.68, solid: false, units: 1, corner: 0.34, reach: 1, box: true)
        case .playtunnel: return DecorSpec(half: SIMD2(0.86, 0.52), height: 1.0, solid: true, units: 2, corner: 0.3, reach: 1, box: true)
        case .ringstacker: return DecorSpec(half: SIMD2(0.38, 0.38), height: 0.96, solid: true, units: 1, corner: 0.38, reach: 1, box: true)
        case .toyrocket: return DecorSpec(half: SIMD2(0.86, 0.32), height: 1.36, solid: true, units: 2, corner: 0.15, reach: 1, box: true)
        case .plushdino: return DecorSpec(half: SIMD2(0.62, 0.62), height: 1.42, solid: true, units: 1, corner: 0.3, reach: 1, box: true)
        case .kickscooter: return DecorSpec(half: SIMD2(0.78, 0.57), height: 1.36, solid: true, units: 1, corner: 0.1, reach: 1, box: true)
        default: return parkSpec
        }
    }
    var batch4Interaction: IdleKind? {
        switch self {
        case .beachball: return .decorKick
        case .playtunnel: return .decorPeek
        case .ringstacker, .toyrocket, .plushdino, .kickscooter: return .decorBoop
        default: return nil
        }
    }
    var batch4Title: String {
        switch self {
        case .beachball: return "Beach ball"; case .playtunnel: return "Play tunnel"; case .ringstacker: return "Ring stacker"
        case .toyrocket: return "Toy rocket"; case .plushdino: return "Plush dino"; case .kickscooter: return "Kick scooter"
        default: return parkTitle
        }
    }
    var batch4Use: String {
        switch self {
        case .beachball: return "A big light beach ball. Jelbies kick it and it rolls, and friends pass it."
        case .playtunnel: return "A crawl tunnel. Jelbies lean in for a peek and it ripples."
        case .ringstacker: return "Boop the rainbow rings and they wobble on their post."
        case .toyrocket: return "A ride-on rocket. Boop it and it rocks, its flame flickering."
        case .plushdino: return "A squishy plush dino. A boop sets it wobbling and swishing its tail."
        case .kickscooter: return "Boop it, the bell dings and the handlebars twist."
        default: return parkUse
        }
    }
    /// The shop symbols (SF Symbols) and JellyCoins prices of the batch (earned currency; toys 30...85).
    static let batch4Shop: [(DecorKind, Int, String)] = [
        (.beachball, 30, "volleyball.fill"), (.ringstacker, 40, "circle.circle.fill"), (.plushdino, 45, "lizard.fill"),
        (.kickscooter, 55, "scooter"), (.playtunnel, 70, "arrow.left.and.right.circle.fill"), (.toyrocket, 85, "airplane"),
    ]
}
