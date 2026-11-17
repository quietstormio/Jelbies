//
//  DecorKind+Retired.swift
//  2026-11-04: the sit-on furniture is retired (buggy, slow, clunky on the phone). The enum cases stay (old saves decode, the sit engine still serves the Park's
//  seesaw / spring rider / sandbox, and files owned elsewhere reference .loveseat), but these pieces are no longer sold or placeable. A save that owns one has it
//  removed from the bag and from every room and its price refunded once (StoreBook+RetiredDecor.swift).
//

import Foundation

extension DecorKind {
    /// Every retired home piece (the sit-on furniture, then the babyest toys), with the price it was sold at (the refund).
    static let retiredPrices: [DecorKind: Int] = [
        .beanbag: 70, .cushion: 25, .pouf: 40, .armchair: 70, .loveseat: 120, .rockingchair: 80, .swing: 100, .diningset: 85,
        .cushionpile: 45, .rockinghorse: 75, .toyrocket: 85,
        // the babyest toys (2026-11-04, "toys are too baby")
        .duck: 25, .ringstacker: 40, .jackinbox: 45, .toypiano: 65,
        // 2026-11-15 (the user's ask: "Remove rc car, scooter, frisbee, and bubble machine"). StoreBook+RetiredDecor.swift's pass runs once per save, so it
        // cannot see a kind retired after it ran: a save that owns one of these is cleared and refunded by StoreBook+RetiredToys.swift
        .toycar: 50, .kickscooter: 55, .frisbee: 35, .bubblemachine: 60,
        // 2026-11-16 (the user's ask: "The tunnel too small remove this toy"): cleared and refunded by the same pass (StoreBook+RetiredToys.swift)
        .playtunnel: 70,
    ]
    static let retired: Set<DecorKind> = Set(retiredPrices.keys)
    var isRetired: Bool { Self.retired.contains(self) }
}
