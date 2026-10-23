//
//  VoiceCoordinator+Subject.swift
//  Tricks are per character (one VoiceTraining book per Jelly, JellyProfile.swift), but the coordinator used to read only slot 0's book and drive only slot 0's brain (W2, 2026-10-22).
//  The SUBJECT is the Jelly the voice teaching and the trick book are about now: the one in a one-Jelly close-up, else the selected / targeted one. A transcript that
//  names a Jelly makes that Jelly the subject of that one decision. `runSubject` carries a reaction out on the subject's own brain.
//

import Foundation
import simd
import QuartzCore

extension VoiceCoordinator {
    var subjectID: Int { care?.trainingSubject ?? 0 }
    func book(for id: Int) -> VoiceTraining { care?.jelly(id)?.training ?? training }
    var book: VoiceTraining { book(for: subjectID) }
    func subjectBrain(_ fallback: BlobBrain) -> BlobBrain { care?.brainFor(subjectID) ?? fallback }
    /// The Jelly a transcript is about: a name in it, else the subject.
    func subject(for transcript: String) -> Int {
        let toks = VoiceMatcher.tokens(transcript)
        if let id = training.names.resolve(tokens: toks).first?.id, presentIDs.contains(id) { return id }
        return subjectID
    }

    /// Carries a reaction out on Jelly `id`'s own brain (he is not slot 0). False = the existing path handles it (social, name heard, come, ...).
    func runSubject(_ r: VoiceReaction, id: Int, kind: VoiceFeedback.Kind?, care: GameCare) -> Bool {
        guard let b = care.brainFor(id) else { return false }
        let focused = care.focus.isActive
        switch r {
        case .perform(let t), .wrongTrick(_, let t):
            if t == .come { return false }
            emitFeedback(r, override: kind)
            switch t {
            case .run where focused: b.commandedNameHop = true
            case .flip:
                b.flipCompact = focused
                b.commandedFlipFail = rollFlipFail()
                b.commandedFlip = true
            default: b.commandedIdle = Self.idleKind(for: t)
            }
            return true
        case .learnedStep, .nicknameStep, .acknowledged:
            emitFeedback(r, override: kind)
            b.blinkRequested = true; perkLeft = 0.6
            return true
        case .trickLearned:
            emitFeedback(r, override: kind)
            b.blinkRequested = true
            care.touchPlay?.spawnHeart(now: CACurrentMediaTime())
            if !focused { b.commandedNameHop = true }
            return true
        case .puzzled, .ignore:
            emitFeedback(r, override: kind)
            if Self.running(b) == nil { b.commandedIdle = .look }
            return true
        case .grumpyIgnore:
            emitFeedback(r, override: kind)
            b.commandedIdle = .slump
            care.showNeedBubble()
            return true
        default:
            return false
        }
    }
}
