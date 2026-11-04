//
//  GameCare+SocialLove.swift
//  When two Jelbies start a warm interaction (a hug, a bump, play ...), each one's love (the attention need) goes up a little, and now and then
//  (not every time) a small heart floats over him. Watches the brains' session state from GameCare's own per-step tick: the social code itself
//  (BlobSocial*, MelonStage's onSocial) is untouched.
//

import Foundation
import QuartzCore

enum SocialLoveTuning {
    /// Attention gained by each Jelbie when a warm session begins.
    static let gain: Float = 0.04
    /// Chance of a heart over each of them at that moment (the stage already shows hearts on bumps and at the end of a session).
    static let heartChance: Float = 0.3
}

extension GameCare {
    /// Once per fixed step (top of `tickOthers`): a Jelbie whose warm social session just began.
    func tickSocialLove(_ actors: [JellyActor]) {
        for a in actors {
            guard let b = a.brain else { continue }
            let warm = b.social?.kind.isWarm == true && b.social?.end == nil
            let was = socialLoveActive.contains(a.id)
            if warm && !was {
                socialLoveActive.insert(a.id)
                guard let j = jelly(a.id), !parkHides(a.id) else { continue }
                j.needs.gain(.attention, SocialLoveTuning.gain)
                if Float.random(in: 0..<1) < SocialLoveTuning.heartChance, !focus.isActive, !a.selected, !race.active, !volley.active, !bath.active {
                    bubbleHub.spawnHeart(for: a.id, now: CACurrentMediaTime())
                }
            } else if !warm && was {
                socialLoveActive.remove(a.id)
            }
        }
    }
}
