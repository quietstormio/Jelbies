//
//  GardenLife.swift
//  The Jelbies' life in the Garden, only while it is their home: now and then one calm Jelbie walks to a spot, then does one of the existing moves there
//  (a sniff at the flowers = the look, a chase after a butterfly = the jump for joy, a splash at the bird bath = the happy bounce, a sunbathe on the deck
//  = the lie down). It rides on the brain's own `goTo` request and commanded idle (the way the voice commands and the decor exits do), so the arms stay
//  stubby and the feet stay attached; nothing new is posed. Never while anything else has the Jelbies' attention (meal, Clean, close-up, photo mode ...).
//

import Foundation
import simd

nonisolated enum GardenActivity: Sendable { case sniff, chase, splash, sunbathe, help }

nonisolated struct GardenLifeState {
    struct Visit {
        var actor: Int
        var spot: SIMD2<Float>
        var move: IdleKind
        var waited: Float = 0
    }
    var cooldown: Float = 18
    var visit: Visit?
    var last: GardenActivity?
}
