//
//  BubbleWandStub.swift
//  The bubble wand's place in the picker until g-bubbleblow's `BubbleWand` lands (delete this file at that merge and register `BubbleWand.shared` in
//  `PlayToyRegistry.registerBuiltIns`). The store sells it (StoreCatalog.playToyItems, id "toy-bubbleWand"); picking it does nothing yet.
//

import Foundation

@MainActor
final class BubbleWandStub: PlayToy {
    static let shared = BubbleWandStub()
    var toyID: String { "bubbleWand" }
    var title: String { "Bubble wand" }
    var symbol: String { "wand.and.stars" }
    var price: Int { 40 }
    func activate(care: GameCare) { care.play.stubNotice = "The bubble wand is coming soon." }
    func deactivate() {}
}
