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
    nonisolated(unsafe) static var on: Bool = flag("SocialMore")
    /// Group (hug, cheer, conga, circle) wait for a crowd + cooldown after one, scaled by this. The rare treats (congaLine / ringDance, EmoteTuning) keep their own minutes-long cooldown (GroupEmoteTests.testTreatsAreRareAndRespectBusy pins >= 170 s).
    static let homeGroupWait: Float = 0.2, parkGroupWait: Float = 0.2
    /// Pair sessions: the brain-wide and the pair cooldown after one (SocialTuning.brainCooldown / pairCooldown) scaled by this.
    static let homePairWait: Float = 0.2, parkPairWait: Float = 0.25
}

extension BlobBrain {
    var moreGroupWaitMul: Float { SocialMore.on ? (outingPlay ? SocialMore.parkGroupWait : SocialMore.homeGroupWait) : 1 }
    var morePairWaitMul: Float { SocialMore.on ? (outingPlay ? SocialMore.parkPairWait : SocialMore.homePairWait) : 1 }
}
