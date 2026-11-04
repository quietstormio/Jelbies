//
//  DecorKind+Batch5.swift
//  The fifth batch of toys (2026-11-04, "toys are too baby"): a hacky sack, a frisbee, a mini skateboard and a basketball hoop. Made in Blender
//  (tools/make_decor_batch5, the same OBJ -> decor_<id>.bin pipeline) and posed in DecorModels+Batch5.swift. Every one reuses an interaction the Jellies already have:
//  the hacky sack and the frisbee are kicked, headed and passed like the balls (and flicked in Play), the skateboard is kicked and rolls along like the toy car,
//  the hoop is booped (backboard rattles, net swings).
//

import simd
import Foundation

extension DecorKind {
    static let batch5Toys: [DecorKind] = [.footbag, .frisbee, .skateboard, .hoop]
    static let batch5: [DecorKind] = batch5Toys
    /// Rolls along like the toy car: heads the way it travels and turns its wheels.
    var carLike: Bool { self == .toycar || self == .skateboard }
    /// Radius of a car-like piece's wheels (the wheel turn per metre rolled).
    var wheelRadius: Float { self == .skateboard ? 0.106 : 0.17 }

    /// Footprints are the exports' JSON `footprint_half` / `height` / `spots`.
    var batch5Spec: DecorSpec {
        switch self {
        case .footbag: return DecorSpec(half: SIMD2(0.17, 0.17), height: 0.34, solid: false, units: 1, corner: 0.17, reach: 1, box: true)
        case .frisbee: return DecorSpec(half: SIMD2(0.34, 0.34), height: 0.13, solid: false, units: 1, corner: 0.34, reach: 1, box: true)
        case .skateboard: return DecorSpec(half: SIMD2(0.35, 0.70), height: 0.36, solid: false, units: 1, corner: 0.2, reach: 1, box: true)
        case .hoop: return DecorSpec(half: SIMD2(0.52, 0.50), height: 2.1, solid: true, units: 1, corner: 0.5, reach: 1, box: true)
        default: return parkSpec
        }
    }
    var batch5Interaction: IdleKind? {
        switch self {
        case .footbag, .frisbee, .skateboard: return .decorKick
        case .hoop: return .decorBoop
        default: return nil
        }
    }
    var batch5Title: String {
        switch self {
        case .footbag: return "Hacky sack"; case .frisbee: return "Frisbee"; case .skateboard: return "Mini skateboard"; case .hoop: return "Basketball hoop"
        default: return parkTitle
        }
    }
    var batch5Use: String {
        switch self {
        case .footbag: return "A footbag. Jelbies kick it up, keep it going and pass it between them."
        case .frisbee: return "A flying disc. Jelbies boot it across the room and toss it back to each other."
        case .skateboard: return "A mini skateboard. Kick it and it rolls away on its wheels."
        case .hoop: return "A free-standing hoop. Jelbies boop the backboard and the net swings."
        default: return parkUse
        }
    }
    /// The shop symbols (SF Symbols) and JellyCoins prices of the batch (earned currency).
    static let batch5Shop: [(DecorKind, Int, String)] = [
        (.footbag, 30, "circle.hexagongrid.fill"), (.frisbee, 35, "figure.disc.sports"), (.skateboard, 60, "figure.skateboarding"), (.hoop, 80, "basketball.fill"),
    ]
}
