//
//  VoiceCoordinator+A11y.swift
//  Accessibility for the voice teaching (round-1023): tap-to-talk (a tap starts, a tap or 6 s stops; for VoiceOver, Switch Control, Voice Control and
//  anyone who cannot hold), the Jelbie's NAME in the labels, and the announcements ("Moss learned Sit", "Sit: 2 of 3 lessons").
//  Typed teaching (`typed(_:)`) lives in VoiceCoordinator.swift beside the transcript step it shares.
//

import UIKit

extension VoiceCoordinator {
    /// How long a tap-to-talk listen lasts if nobody taps again.
    static let tapListenLimit: UInt64 = 6_000_000_000

    /// The mic is a toggle, not a hold: the setting (Voice Control users turn it on: a spoken "tap" cannot hold), or VoiceOver / Switch Control.
    static var tapMode: Bool {
        A11ySettings.shared.tapToTalk || UIAccessibility.isVoiceOverRunning || UIAccessibility.isSwitchControlRunning
    }

    /// The Jelbie the voice is about now (the trick-book subject), for labels.
    var subjectName: String { care?.jelly(subjectID)?.name ?? "your Jelbie" }

    /// Tap-to-talk: starts a listen, or ends the one running. Returns true if it started one.
    @discardableResult
    func toggleListening() -> Bool {
        if isListening { release(); return false }
        guard begin() else { return false }
        let n = openCount
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: Self.tapListenLimit)
            if let self, self.isListening, self.openCount == n { self.release() }
        }
        return true
    }

    /// VoiceOver / the voice-feedback bubble: what he understood, in words.
    func announceFeedback(_ kind: VoiceFeedback.Kind) {
        let n = subjectName
        switch kind {
        case .learned(let t, _): A11yEvents.say(A11yEvents.trickLearned(name: n, trick: t.title), .high)
        case .rep(let t, let reps): A11yEvents.say("\(t.title): \(reps) of \(VoiceTuning.repsToLearn) lessons", .normal)
        case .unknown: A11yEvents.say("\(n) did not understand", .normal)
        case .nameLearned: A11yEvents.say("\(n) learned the nickname", .high)
        default: break
        }
    }
}
