//
//  AmbientVoice.swift
//  2026-11-05, "they need to make 30% more Jelbie noises while at home": a silence filler ON TOP of the idle chirp / greetings / social voices (none of those change).
//  When a Jelbie is awake at home and has not voiced for `quietFor` seconds, the hub plays one of its normal chirp / babble voices (src tag "ambient") and the
//  brain opens its mouth for a moment. Plus the home-only loudness boost of the movement sounds (HomeMoveSoundTuning).
//

import Foundation
import QuartzCore

nonisolated enum AmbientVoiceTuning {
    /// Master switch (the soak test turns it off to measure the "before" on the same seeds).
    nonisolated(unsafe) static var enabled = true
    /// Seconds of silence (since any voice of that Jelbie) before the filler speaks; re-rolled after each fire. x(1 + nightExtra * night) in the evening / at night while awake.
    static let quietFor: ClosedRange<Double> = 20...28          // (the brief said 26...36: that gave only x1.26 on the busy soak, 22...30 x1.33 with the new voices; the soak needs a safe >= x1.3)
    static let nightExtra: Double = 0.5
    /// Nobody may have voiced in the whole room for this long (two never chirp on top of each other); else retry after `retry`.
    static let roomGap: Double = 3
    static let retry: ClosedRange<Double> = 1...2
    /// After a fire (played or hushed away) the same Jelbie waits this long before another attempt (a hushed attempt is retried soon).
    static let afterFire: Double = 2.3
    /// A Jelbie that was not eligible (asleep, held, away from home) waits this long after becoming eligible again.
    static let returnHoldoff: Double = 6
    /// The brain's little mouth-open pulse.
    static let mouthOpen: Float = 0.35, mouthSeconds: Double = 0.25
}

/// "Play more often" for the context voices (giggle, curious, ooh, hum ...): at home their chance x1.3 (AudioHub.contextVoice). `enabled` is the soak test's before / after switch.
nonisolated enum HomeVoiceTuning {
    nonisolated(unsafe) static var enabled = true
    static let contextChanceMul: Double = 1.3
    /// 2026-11-06: at home a context voice whose base chance is at least `floorFrom` plays with at least `contextFloor` (the wander lala / pfft at 0.05 stay at x1.3 only).
    nonisolated(unsafe) static var floorEnabled = true
    nonisolated(unsafe) static var contextFloor: Double = 0.45
    static let floorFrom: Double = 0.1
    static func homeChance(_ base: Double) -> Double {
        var p = base * contextChanceMul
        if floorEnabled, base >= floorFrom { p = max(p, contextFloor) }
        return min(1, p)
    }
}

/// 2026-11-09, "add 10% more Jelbie noises as they're just walking around": at home, awake (a) the wander pick (the brain just walks on, no special) now voices its lala / pfft
/// (before, the wander branch returned before idleBegin, so those two voices -- in the catalog since 11-05 -- were never played), with `wanderChance` as base chance (x1.3 at home like every
/// context voice; hushes as always), and (b) the silence filler waits only `quietScaleWalking` x as long while that Jelbie walks. Volumes, park / cafe / race and sleepers do not change.
/// `enabled` is the soak test's before / after switch.
nonisolated enum RoamVoiceBoost {
    nonisolated(unsafe) static var enabled = true
    nonisolated(unsafe) static var wanderChance: Double = 0.3
    nonisolated(unsafe) static var quietScaleWalking: Double = 0.6
}

extension AmbientVoiceTuning {
    /// What the filler says: chirp / babble stay the most common. By day: happy 3, babble 3 (as before: add, never displace), then giggle 1.5, curious 2, hum 1.2, ooh 1. Evening / awake at night (night >= 0.3):
    /// hum 2, yawn 1.5, happy 1.5, babble 1.5 (soft and sleepy). A grumpy one: sad 3, babble 2, hum 1 (no giggles).
    /// (the soak test's "before" switch: false = the 2230db85 day set)
    nonisolated(unsafe) static var newDaySet = true
    static func pick(night: Double, grumpy: Bool, random: (ClosedRange<Double>) -> Double) -> JellyVoice {
        let table: [(JellyVoice, Double)]
        if grumpy { table = [(.sad, 3), (.babble, 2), (.hum, 1)] }
        else if night >= 0.3 { table = [(.hum, 2), (.yawn, 1.5), (.happy, 1.5), (.babble, 1.5)] }
        else if newDaySet { table = [(.happy, 3), (.babble, 3), (.giggle, 1.5), (.curious, 2.0), (.hum, 1.2), (.ooh, 1)] }          // (2026-11-06: happy / babble keep their weight 3; the new voices sit on top)
        else { table = [(.happy, 3), (.babble, 3), (.giggle, 1.2), (.curious, 1), (.hum, 1), (.ooh, 0.8)] }
        var x = random(0...table.reduce(0) { $0 + $1.1 })
        for (v, w) in table { if x < w { return v }; x -= w }
        return table[0].0
    }
}

nonisolated struct AmbientVoiceScheduler: Sendable {
    private(set) var quiet: [Double] = [0, 0, 0]
    private(set) var notBefore: [Double] = [0, 0, 0]

    /// The slots that should voice now. `since[i]`: seconds since slot i last voiced (any kind); `night` 0...1.
    mutating func due(eligible: [Bool], walking: [Bool] = [], since: [Double], now: Double, night: Double, random: (ClosedRange<Double>) -> Double) -> [Int] {
        var out: [Int] = []
        let roomRecent = (since.min() ?? 999) < AmbientVoiceTuning.roomGap
        for i in eligible.indices where i < quiet.count && i < since.count {
            guard eligible[i] else { quiet[i] = 0; notBefore[i] = now + AmbientVoiceTuning.returnHoldoff; continue }
            guard now >= notBefore[i] else { continue }
            if quiet[i] == 0 { quiet[i] = random(AmbientVoiceTuning.quietFor) * (1 + AmbientVoiceTuning.nightExtra * night) }
            let scale = RoamVoiceBoost.enabled && i < walking.count && walking[i] ? RoamVoiceBoost.quietScaleWalking : 1
            guard since[i] >= quiet[i] * scale else { continue }
            if roomRecent || !out.isEmpty { notBefore[i] = now + random(AmbientVoiceTuning.retry); continue }
            out.append(i)
            quiet[i] = 0
            notBefore[i] = now + AmbientVoiceTuning.afterFire
        }
        return out
    }
}

extension BlobBrain {
    /// Awake, free and standing about: not held / dragged, not in the sleep idle or lying down, not napping.
    var ambientVoiceOK: Bool {
        if held || isNapping { return false }
        switch idleState.kind { case .sleep?, .lieDown?, .floorNapFlop?: return false; default: return true }
    }
    /// The mouth for the renderer: the brain's own, or the ambient pulse.
    var mouthShown: Float { (AmbientMouthTable.until[ObjectIdentifier(self)] ?? 0) > CACurrentMediaTime() ? max(mouthOpen, AmbientVoiceTuning.mouthOpen) : mouthOpen }
    func ambientPulse() { AmbientMouthTable.until[ObjectIdentifier(self)] = CACurrentMediaTime() + AmbientVoiceTuning.mouthSeconds }
}

/// Where each brain's ambient mouth pulse ends (kept here, not in BlobBrain's stored properties).
nonisolated enum AmbientMouthTable {
    nonisolated(unsafe) static var until: [ObjectIdentifier: Double] = [:]
}

/// The home room's movement sounds are louder (the user: "more sound when they're just walking around and running in the house"). Home only (AudioHub.atHome:
/// not the park, cafe, groomer, race, volley, show, outing, bath or a town screen); the catalog gains stay as they are for everywhere else.
nonisolated enum HomeMoveSoundTuning {
    static let gainMul: Float = 1.3
    static let sounds: Set<SFX> = [.footstep, .zoomies, .squish, .wobble, .jump, .boop]
}
