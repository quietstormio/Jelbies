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

    // MARK: park-play-r1 (owner 2026-11-15: "remove the seesaw and make them play and interact more ... play but not as often but interact and make friends more")
    private static func flag(_ key: String) -> Bool {
        guard DevArgs.enabled, let v = UserDefaults.standard.string(forKey: key) else { return true }          // the old-behaviour switches act only where dev arguments are on
        return !["0", "no", "false", "old", "off"].contains(v.lowercased())
    }
    /// The seesaw is not placed in the park (ParkToys.placed). `-ParkSeesaw 1` puts it back for a before / after; under XCTest it is there for the seesaw's own suites (`ParkPlayTuning.seesawInPark = false` in a test checks the removal).
    nonisolated(unsafe) static var seesawInPark: Bool = (DevArgs.enabled && UserDefaults.standard.integer(forKey: "ParkSeesaw") != 0) || ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    /// `-ParkToyRate old`: the slide and the hopscotch are picked as before. `-ParkSocial old`: the social rates as before. (Park only; the room never reads them.)
    nonisolated(unsafe) static var toyRateNew: Bool = flag("ParkToyRate")
    nonisolated(unsafe) static var socialNew: Bool = flag("ParkSocial")

    // MARK: rarer slide and hopscotch (autonomous picks only, per creature, per decision)
    /// The chance that an autonomous pick of the slide / of a NEW hopscotch line goes ahead (today 1.0: nothing rolls it away). A roll that said no is not asked again for `rejectHold` seconds.
    static let slidePickChance: Float = 0.3, hopscotchPickChance: Float = 0.4
    static let rejectHold: ClosedRange<Float> = 25...40
    /// After a creature has used (or given up) the slide / the hopscotch it does not pick that toy again for this long (seconds, drawn per use).
    static let slideCooldown: ClosedRange<Float> = 90...150, hopscotchCooldown: ClosedRange<Float> = 90...150
    /// The visitor who opens the first hopscotch turn of a visit does it this many seconds in (was `hopHostAfter`).
    static let hopHostAfterNew: ClosedRange<Float> = 40...80

    // MARK: more play together (park only)
    /// Multiplies the pick chance of a social (a probability: it only helps where the old value was under 1) and shortens every wait between socials (brain / pair cooldowns, the "no social for a while" floor, the group wait
    /// and the group cooldown) by `socialWaitMul`. Weights of the calm pair kinds (no fast kind) are multiplied by `calmKindMul`, the hand-holding boop by `boopMul`.
    static let socialPickMul: Float = 2.0, socialWaitMul: Float = 0.5
    static let calmKindMul: Float = 1.35, boopMul: Float = 0.8
    static let calmKinds: Set<SocialKind> = [.sitTogether, .backToBack, .swayHug, .highFive, .cuddleLean, .line, .follow, .spinHug, .whisperGiggle]
    // MARK: a mixed park (`-ParkSpread old` = off)
    nonisolated(unsafe) static var spreadNew: Bool = flag("ParkSpread")
    /// A stranger whose body kind is already in this visit (while another kind is still available) is not picked; a friend of such a kind keeps this share of his weight. A stranger of one of the household's own kinds keeps this
    /// share (friends are not touched, so they still come back and friendship grows).
    static let spreadSeenFriendMul: Double = 0.3, spreadHouseholdMul: Double = 0.2
    /// A visit has at least this many different kinds when that many exist (the fourth visitor is free: with four kinds in the pool, forcing all four would put the household's own kinds in every full visit).
    static let spreadKinds = 3
    /// Counters for the soak (why a pick did not go ahead).
    struct Stats { var rollNo = 0, coolNo = 0 }
    nonisolated(unsafe) static var stats = Stats()
}
