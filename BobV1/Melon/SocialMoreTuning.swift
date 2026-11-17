//
//  SocialMoreTuning.swift
//  social-more-r1 (owner 2026-11-16: "more group emotes at park and amongst each other"): group emotes about 2x as often, pair emotes about 1.5x, at home and at the park.
//  Only the waits between socials change (no body motion, no new emote): a multiplier < 1 shortens the wait, so the time comes out of idle standing / wandering.
//  Home and park have their own constants (the park's are on top of ParkPlayTuning.socialWaitMul). `SocialMore.on = false` (`-SocialMore old`) gives the previous rates for a before / after.
//

import Foundation

nonisolated enum SocialMore {
    private static func flag(_ key: String) -> Bool {
        guard DevArgs.enabled, let v = UserDefaults.standard.string(forKey: key) else { return true }
        return !["0", "no", "false", "old", "off"].contains(v.lowercased())
    }
    nonisolated(unsafe) static var on: Bool = flag("SocialMore") && ProcessInfo.processInfo.environment["SOCIAL_MORE_OFF"] == nil          // (SOCIAL_MORE_OFF=1 in the test environment: the previous rates, to tell which red test is red without this round)
    /// Group (hug, cheer, conga, circle) wait for a crowd + cooldown after one, scaled by this. The rare treats (congaLine / ringDance, EmoteTuning) keep their own minutes-long cooldown (GroupEmoteTests.testTreatsAreRareAndRespectBusy pins >= 170 s).
    static let homeGroupWait: Float = 0.3, parkGroupWait: Float = 0.13
    /// Pair sessions: the brain-wide and the pair cooldown after one (SocialTuning.brainCooldown / pairCooldown) scaled by this.
    static let homePairWait: Float = 0.45, parkPairWait: Float = 0.5
    /// Extra pair rolls: a standing, free Jelmiko rolls the ordinary pair pick (SocialTuning.pickChance, cooldowns and partner rules all unchanged) this often (seconds, drawn each time) besides the scheduler's own picks.
    /// The scheduler's pick cadence, not the waits, limited the pair rate: a group takes the three of them for ~25 s. Only how often the existing pair emotes are asked for.
    static let homePairRoll: (Float, Float) = (4, 8), parkPairRoll: (Float, Float) = (4, 8)
}

extension BlobBrain {
    var moreGroupWaitMul: Float { SocialMore.on ? (outingPlay ? SocialMore.parkGroupWait : SocialMore.homeGroupWait) : 1 }
    var morePairWaitMul: Float { SocialMore.on ? (outingPlay ? SocialMore.parkPairWait : SocialMore.homePairWait) : 1 }
}

extension BlobBrain {
    /// Per tick while no session is on him (BlobSocial.swift socialTick): the extra pair roll above.
    func socialPairWatch(_ sim: SoftBody, _ dt: Float) {
        guard SocialMore.on, anticsEnabled, socialFree, !reserved, toy.waitUID < 0, toy.chaseSpot == nil, idleDeepNight < 0.5 else { return }
        socialBook.pairRoll += dt
        guard socialBook.pairRoll >= socialBook.pairRollLimit else { return }
        let r = outingPlay ? SocialMore.parkPairRoll : SocialMore.homePairRoll
        socialBook.pairRoll = 0; socialBook.pairRollLimit = rand(r.0, r.1)
        _ = socialMaybeStart(sim)
    }
}
