//
//  ParkPairTuning.swift
//  The park-only play rules of round park-pairs-r1 (player, 2026-11-14: "they're getting on the seesaw and hopscotch too much, I want them interacting with each other more, those a little
//  more rare, and they only get on the seesaw in twos"). Three independent switches, each with a launch argument so old and new can be filmed on one build:
//    pairSeesaw  `-ParkPairSeesaw 0`   off = the old rule (one rider may sit and rock alone and invite a second)       default ON = nobody rides alone
//    toyRateNew  `-ParkToyRate old`    off = the old autonomous pick of the seesaw / hopscotch                           default ON = rarer + a per-creature cooldown
//    socialNew   `-ParkSocial old`     off = the old social rates                                                        default ON = more pair and group play
//  Only brains whose `outingPlay` is set (the park) read the toy-rate and social numbers; the room's rates are untouched. A use the player asked for (`commanded`) is never rolled away.
//

import Foundation

nonisolated enum ParkPairTuning {
    private static func flag(_ key: String) -> Bool {
        guard let v = UserDefaults.standard.string(forKey: key) else { return true }
        return !["0", "no", "false", "old", "off"].contains(v.lowercased())
    }
    nonisolated(unsafe) static var pairSeesaw: Bool = flag("ParkPairSeesaw")
    nonisolated(unsafe) static var toyRateNew: Bool = flag("ParkToyRate")
    nonisolated(unsafe) static var socialNew: Bool = flag("ParkSocial")

    // MARK: B. rarer toys (autonomous picks only; per creature, per decision)
    /// The chance that an autonomous pick of the seesaw / of a NEW hopscotch line goes ahead (the rest is "not now": the decision falls through to another pick). Today it is 1.0 (nothing rolls it away).
    static let seesawPickChance: Float = 1.0, hopscotchPickChance: Float = 0.4
    /// A roll that said no is not asked again for this long (else the next decision, a few seconds later, rolls again and the chance means little).
    static let rejectHold: ClosedRange<Float> = 25...40
    /// After a creature has used (or given up) a toy it does not pick that toy again for this long (seconds, drawn per use).
    static let seesawCooldown: ClosedRange<Float> = 15...30, hopscotchCooldown: ClosedRange<Float> = 40...70
    /// The visitor who opens the first hopscotch turn of a visit does it this many seconds in (was 15...30): the court is still used every visit, but not at once.
    static let hopHostAfter: ClosedRange<Float> = 40...80

    // MARK: A. the pair-only seesaw
    /// A partner must be a free creature this near the seesaw (metres) and agrees with this chance.
    static let partnerRadius: Float = 6.5
    nonisolated(unsafe) static var partnerAgree: Float = 1.0          // (a var only so a test can make the partner certain)
    /// The first one at the seesaw waits standing at his spot, not seated, until the partner is this near his own stand spot (or already there). Not smaller: a waiter standing in front of the plank blocks the partner's way along it to the far seat (measured: a partner stuck 2.6 m off gave up), so he hops up while the partner is still this far, and then counts as 'coming' out to this + 0.4 m.
    static let readyDist: Float = 3.0
    /// A waiter gives up after this long standing at the seesaw (seconds, counted from his arrival at the spot); and after this long when the partner is gone altogether (left, never came).
    static let waitCap: Float = 8.0, partnerGoneGrace: Float = 1.0
    /// A commanded waiter looks for a free partner this often (seconds).
    static let recruitEvery: Float = 0.8

    // MARK: C. more play together (park only)
    /// Multiplies the pick chance of a social (a probability: it only helps where the old value was under 1), and shortens every wait between socials (brain / pair cooldowns, the "no social for a
    /// while" floor, the group wait and the group cooldown) by `socialWaitMul`. Both together aim at about 1.5x the sessions started.
    static let socialPickMul: Float = 1.5, socialWaitMul: Float = 0.67
    /// Weights of the calm pair kinds (none of them a fast kind: `SocialKind.isFast`, so the feel does not turn hectic; the groups only get the shorter wait) are multiplied by `calmKindMul`; the hand-holding boop
    /// (the player called it too frequent in November) by `boopMul`.
    static let calmKindMul: Float = 1.35, boopMul: Float = 0.8
    static let calmKinds: Set<SocialKind> = [.sitTogether, .backToBack, .swayHug, .highFive, .cuddleLean, .line, .follow, .spinHug, .whisperGiggle]

    /// Counters for the soak test (why a pick did not go ahead): the roll said no, the cooldown, nobody free to ride with.
    struct Stats { var rollNo = 0, coolNo = 0, noPartner = 0, recruited = 0 }
    nonisolated(unsafe) static var stats = Stats()
}
