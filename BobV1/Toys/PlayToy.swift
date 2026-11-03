//
//  PlayToy.swift
//  A tiny stand-in for the play mode's toy registry, so the bubble wand plugs in through ONE entry. (g-playtoss builds the real PLAY -> toy picker, the
//  generalised food picker, and the thrown ball; at merge the picker should read `PlayToyRegistry.entries`, or this file is replaced by its registry
//  and `BubbleWandToy` keeps its one `register` line.) A toy is listed in the picker only once it is OWNED (bought with JellyCoins): `PlayToyRegistry.offered`.
//

import Foundation

/// One toy of the play mode.
@MainActor
protocol PlayToy: AnyObject {
    /// Stable id; also the store key (`StoreBook.toyKey`).
    var toyID: String { get }
    var title: String { get }
    var symbol: String { get }
    /// JellyCoins price in the store.
    var price: Int { get }
    /// The toy comes out (play mode on): show its controls, start its sim.
    func activate(care: GameCare?)
    /// Put away: everything it made disappears.
    func deactivate()
}

@MainActor
enum PlayToyRegistry {
    private(set) static var entries: [PlayToy] = []
    static func register(_ t: PlayToy) {
        entries.removeAll { $0.toyID == t.toyID }
        entries.append(t)
    }
    /// The toys the picker shows: only the ones the player owns.
    static func offered(book: StoreBook) -> [PlayToy] { entries.filter { book.ownsToy($0.toyID) } }
    static func toy(_ id: String) -> PlayToy? { entries.first { $0.toyID == id } }
    /// The registrations (idempotent; called once at launch).
    static func registerBuiltIns() { register(BubbleWand.shared) }
}
