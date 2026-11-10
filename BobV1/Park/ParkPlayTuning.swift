//
//  ParkPlayTuning.swift
//  How much the park's pieces (the slide, the hopscotch court, the player's own toys) are used during a visit. Read only by brains whose `outingPlay` is set
//  (GameCare+Park.swift sets it for the Jelbies who came and the visitors while the park is playing), so the home room keeps its own ToyTuning / variety numbers.
//

import Foundation

nonisolated enum ParkPlayTuning {
    /// The direct "go and play with a piece" roll when a pick is due (home: ToyTuning.directChance 0.40 / directGap 20 s).
    static let directChance: Float = 0.80
    static let directGap: Float = 6
    /// The per-kind cooldown of the decor moves (25 s at home) is scaled by this.
    static let cooldownMul: Float = 0.3
    /// Extra decor tickets in the variety bag.
    static let bagBonus = 2
    /// Hopscotch: the chance a free Jelbie joins a line that has started (home value HopscotchTuning.joinChance).
    static let hopscotchJoin: Float = 0.7
    /// A visitor starts the first hopscotch turn this many seconds into the visit (if nobody has by then), so the court is never a long wait.
    static let hopHostAfter: ClosedRange<Float> = 15...30
}
