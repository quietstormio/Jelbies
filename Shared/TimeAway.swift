//
//  TimeAway.swift
//  The shared rules for time away from the game (cold launch and every return to the foreground use the same path):
//  negative elapsed time (clock changes) counts as nothing, anything longer than 14 days counts as 14 days.
//  Needs (BlobNeeds.applyAway) and grime (BlobGrime.applyAway) each apply their own curve to the clamped seconds.
//

import Foundation

nonisolated enum TimeAway {
    static let maxAway: TimeInterval = 14 * 86400
    /// Back after at least this long: Bob comes to the front happily to greet.
    static let greetAfter: TimeInterval = 30 * 60
    static func clamp(_ seconds: TimeInterval) -> TimeInterval {
        guard seconds.isFinite else { return 0 }
        return min(max(0, seconds), maxAway)
    }
}
