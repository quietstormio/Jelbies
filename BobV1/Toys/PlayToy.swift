//
//  PlayToy.swift
//  The play mode's toy registry (Play row -> the toy picker). A toy is ONE registry entry: an id, a title, its picture (the store item), and what happens when it
//  comes out. The picker lists a toy only once it is OWNED (bought with JellyCoins): `PlayToyRegistry.offered`.
//    balls   the bouncy / soccer / beach ball (the store's decor toys): `BallToy` -> `PlayToss` (Play/PlayToss.swift): flick it, the Jelbies header / bump it back.
//    wand    the bubble wand (Toys/BubbleWand.swift): its own entry, the `register` line below.
//  (Shared with g-bubbleblow: the protocol and the registry keep the shape it first wrote; `isOwned` / `storeID` are added with defaults so its wand compiles unchanged.)
//

import Foundation

/// One toy of the play mode.
@MainActor
protocol PlayToy: AnyObject {
    /// Stable id; also the store key (`StoreBook.toyKey`) unless `storeID` says otherwise.
    var toyID: String { get }
    var title: String { get }
    var symbol: String { get }
    /// JellyCoins price in the store.
    var price: Int { get }
    /// The store item that sells it (its picture and its owned count).
    var storeID: String { get }
    /// Does the player own it?
    func isOwned(_ book: StoreBook) -> Bool
    /// The toy comes out (play mode on): show its controls, start its sim.
    func activate(care: GameCare)
    /// Put away: everything it made disappears.
    func deactivate()
}

extension PlayToy {
    var storeID: String { StoreBook.toyKey(toyID) }
    func isOwned(_ book: StoreBook) -> Bool { book.count(storeID) > 0 }
}

@MainActor
enum PlayToyRegistry {
    private(set) static var entries: [PlayToy] = []
    static func register(_ t: PlayToy) {
        entries.removeAll { $0.toyID == t.toyID }
        entries.append(t)
    }
    /// The toys the picker shows: only the ones the player owns.
    static func offered(book: StoreBook) -> [PlayToy] { registerBuiltIns(); return entries.filter { $0.isOwned(book) } }
    static func toy(_ id: String) -> PlayToy? { registerBuiltIns(); return entries.first { $0.toyID == id } }
    private static var registered = false
    /// The registrations (idempotent; called on first use).
    static func registerBuiltIns() {
        guard !registered else { return }
        registered = true
        for k in BallToy.kinds { register(BallToy(kind: k)) }
        register(BubbleWand.shared)
    }
}

/// The thrown balls: the store's bouncy, soccer and beach balls (the decor items; owned = bought, placed in the room or not).
@MainActor
final class BallToy: PlayToy {
    static let kinds: [DecorKind] = [.ball, .soccerball, .beachball]
    let kind: DecorKind
    init(kind: DecorKind) { self.kind = kind }
    var toyID: String { "ball-" + kind.rawValue }
    var title: String { kind.title }
    var symbol: String { StoreCatalog.item(storeID)?.symbol ?? "circle.fill" }
    var price: Int { StoreCatalog.item(storeID)?.price ?? 30 }
    var storeID: String { kind.storeID }
    func activate(care: GameCare) { care.beginPlay(ball: kind) }
    func deactivate() {}
}
