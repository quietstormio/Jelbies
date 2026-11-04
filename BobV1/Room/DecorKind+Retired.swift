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
    ]
    static let retired: Set<DecorKind> = Set(retiredPrices.keys)
    var isRetired: Bool { Self.retired.contains(self) }
}
