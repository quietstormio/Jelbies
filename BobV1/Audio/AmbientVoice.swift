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
    static let quietFor: ClosedRange<Double> = 22...30          // (the brief said 26...36: that gave only x1.26 on the busy soak, which already voices 3 per Jelbie-minute; the soak needs >= x1.3)
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

nonisolated struct AmbientVoiceScheduler: Sendable {
    private(set) var quiet: [Double] = [0, 0, 0]
    private(set) var notBefore: [Double] = [0, 0, 0]

    /// The slots that should voice now. `since[i]`: seconds since slot i last voiced (any kind); `night` 0...1.
    mutating func due(eligible: [Bool], since: [Double], now: Double, night: Double, random: (ClosedRange<Double>) -> Double) -> [Int] {
        var out: [Int] = []
        let roomRecent = (since.min() ?? 999) < AmbientVoiceTuning.roomGap
        for i in eligible.indices where i < quiet.count && i < since.count {
            guard eligible[i] else { quiet[i] = 0; notBefore[i] = now + AmbientVoiceTuning.returnHoldoff; continue }
            guard now >= notBefore[i] else { continue }
            if quiet[i] == 0 { quiet[i] = random(AmbientVoiceTuning.quietFor) * (1 + AmbientVoiceTuning.nightExtra * night) }
            guard since[i] >= quiet[i] else { continue }
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
