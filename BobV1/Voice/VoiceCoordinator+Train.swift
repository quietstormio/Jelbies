//
//  VoiceCoordinator+Train.swift
//  The close-up's Train session (TrainSession.swift) and the room command. In a Train session the mic opens by itself after the demo, a word counts as a rep
//  whatever the body is doing (the demo already showed the move), a different word never silently restarts a lesson, and the learned trick gets a no-demo
//  "Try it". Outside a session NO word is ever bound to a trick (no accidental lessons); a learned word said in the room goes to the named or highlighted
//  Jelbie, else to every Jelbie who knows it.
//

import Foundation
import UIKit

extension VoiceCoordinator {
    // MARK: session

    /// A listen-session id unique across EVERY book (each Jelbie keeps its own lessons, so a per-book counter could repeat another book's id and drop a rep).
    func nextSession() -> Int {
        let books = [training] + (care?.jellies.map(\.training) ?? [])
        let s = (books.map(\.sessionCounter).max() ?? 0) + 1
        for b in books { b.adoptSession(s) }
        return s
    }

    /// The Train close-up arrived (or Train was tapped again): a fresh session on `id`, optionally already on a trick.
    func startTrain(subject id: Int, preselect: VoiceTrick? = nil) {
        if mode.isListening { cancel() }
        endTrain()
        let session = TrainSession(subject: id)
        session.gateObserver = NotificationCenter.default.addObserver(forName: UIAccessibility.announcementDidFinishNotification, object: nil, queue: .main) { [weak session] note in
            let said = note.userInfo?[UIAccessibility.announcementStringValueUserInfoKey] as? String
            MainActor.assumeIsolated { if let session, session.openGate > 0, said == nil || said == session.gateText { session.openGate = 0 } }
        }
        train = session
        let name = book(for: id).names.displayName(id)
        announce(TrainSession.headline(.pick, name: name, word: { _ in "" }, reps: { _ in 0 }))
        if let p = preselect ?? trainPreselect, book(for: id).unlocked(p), p != .come { trainPick(p) }
        trainPreselect = nil
    }

    func endTrain() {
        if train?.step.isListening == true, mode.isListening { cancel() }
        if let o = train?.gateObserver { NotificationCenter.default.removeObserver(o) }
        train = nil
    }

    /// The trick book (or a chip) picked a trick to teach.
    func teach(_ t: VoiceTrick) {
        if train != nil { trainPick(t); return }
        care?.beginTraining(subjectID, preselect: t)
    }

    func trainPick(_ t: VoiceTrick) {
        guard let tr = train, t != .come else { return }
        if mode.isListening { cancel() }
        if book(for: tr.subject).isLearned(t) { enterListen(.tryIt(t)) } else { trainDemo(t) }
    }

    /// He does the move; the listen opens when it is under way.
    func trainDemo(_ t: VoiceTrick) {
        guard let tr = train else { return }
        if mode.isListening { cancel() }
        enqueue(.perform(t), .silent, ids: [tr.subject])
        setStep(.demo(t))
    }

    func trainRetry() {
        guard let tr = train else { return }
        switch tr.step {
        case .missed(let t, _): trainDemo(t)
        case .tried(let t, _, _): enterListen(.tryIt(t))
        default: break
        }
    }

    /// "Use that word instead": drops the half-learned word and teaches the one just heard.
    func trainUseInstead() {
        guard let tr = train, case .missed(let t, .otherWord) = tr.step else { return }
        let res = book(for: tr.subject).rebind(t, transcript: tr.lastTranscript, session: session)
        applyTeach(res, trick: t, tr: tr, bk: book(for: tr.subject), transcript: tr.lastTranscript)
    }

    func trainPickAgain() { guard let tr = train else { return }; if mode.isListening { cancel() }; setStep(.pick); _ = tr }
    func trainDone() { endTrain(); care?.release() }

    /// The card's own "Done" while listening: a hold long enough is submitted like a release; a short one (under the minimum hold, which `release()` would
    /// silently abort) goes back to a retryable step.
    func trainStopListening() {
        guard let tr = train else { return }
        if mode.isListening, mode.holdLongEnough { release(); return }
        if mode.isListening { cancel() }
        trainListenEnded(tr)
    }

    /// A listen step whose mic closed with no transcript on its way (cancelled, backgrounded, failed to open): the step moves on to a retry.
    private func trainListenEnded(_ tr: TrainSession) {
        guard let t = tr.step.trick else { return }
        tr.wantsOpen = false; tr.autoLeft = 0
        if micUnusable { tr.noMic = true; return }
        switch tr.step {
        case .listen: tr.heardText = ""; setStep(.missed(t, why: .nothing))
        case .tryIt: tr.heardText = ""; setStep(.tried(t, ok: false, heard: ""))
        default: break
        }
    }

    private func enterListen(_ s: TrainStep) {
        guard let tr = train else { return }
        setStep(s)
        tr.wantsOpen = true
        tr.noMic = false
        if TrainSession.voiceOverRunning() { tr.openGate = TrainSession.voiceOverGate; tr.gateText = currentHeadline(tr) }        // let VoiceOver finish "Say sit now" first
        else { tr.openGate = 0 }
    }

    func setStep(_ s: TrainStep) {
        guard let tr = train else { return }
        tr.go(s)
        let bk = book(for: tr.subject)
        announce(TrainSession.headline(s, name: bk.names.displayName(tr.subject), word: { bk.word(for: $0) ?? $0.suggestion }, reps: { bk.progress($0) }))
    }

    private func currentHeadline(_ tr: TrainSession) -> String {
        let bk = book(for: tr.subject)
        return TrainSession.headline(tr.step, name: bk.names.displayName(tr.subject), word: { bk.word(for: $0) ?? $0.suggestion }, reps: { bk.progress($0) })
    }

    private func announce(_ text: String) {
        guard TrainSession.voiceOverRunning() else { return }
        UIAccessibility.post(notification: .announcement, argument: text)
    }

    // MARK: tick

    /// Called from `tick` every step.
    func trainTick(care: GameCare, brain: BlobBrain, dt: Float) {
        guard let tr = train else { return }
        guard care.isTrainingCloseUp, care.trainingSubject == tr.subject else { endTrain(); return }
        tr.age += dt
        switch tr.step {
        case .demo(let t):
            let b = subjectBrain(brain)
            if (Self.running(b) == t && tr.age > 0.3) || tr.age > TrainSession.demoCap { enterListen(.listen(t)) }
        case .heard(let t, let reps):
            if reps >= VoiceTuning.repsToLearn { setStep(.learned(t)) }
            else if tr.age > TrainSession.againBeat { trainDemo(t) }
        case .learned(let t):
            if tr.age > TrainSession.learnedBeat { enterListen(.tryIt(t)) }
        default: break
        }
        if tr.step.isListening {
            if tr.wantsOpen {
                if tr.openGate > 0 { tr.openGate -= dt }
                if micUnusable { tr.noMic = true; tr.wantsOpen = false }
                else if mode.phase == .idle, tr.age > 0.05, tr.openGate <= 0, begin() { tr.wantsOpen = false; tr.autoLeft = TrainSession.listenWindow }
            } else if tr.autoLeft > 0 {
                tr.autoLeft -= dt
                if tr.autoLeft <= 0, mode.isListening { release() }
            }
            if !tr.wantsOpen, !tr.noMic, mode.phase == .idle, !stopping { trainListenEnded(tr) }          // the listen ended with no transcript coming
        }
    }

    // MARK: a heard word

    /// A listen ended inside a session that is waiting for the word. True = handled (the normal command path is skipped).
    func trainHandle(_ transcript: String) -> Bool {
        guard let tr = train, tr.step.isListening else { return false }
        let bk = book(for: tr.subject)
        lastBook = bk
        let trimmed = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        tr.heardText = trimmed
        tr.lastTranscript = trimmed
        tr.autoLeft = 0
        switch tr.step {
        case .listen(let t):
            applyTeach(bk.teachRep(t, transcript: transcript, session: session), trick: t, tr: tr, bk: bk, transcript: transcript)
        case .tryIt(let t):
            let toks = VoiceMatcher.tokens(transcript)
            if !toks.isEmpty, bk.learnedTrick(in: toks) == t {
                bk.creditSuccess(t)                                    // the try-it always works (the dice are for the room)
                enqueue(.perform(t), nil, ids: [tr.subject])
                care?.noteInteraction(jelly: tr.subject)
                setStep(.tried(t, ok: true, heard: trimmed))
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            } else {
                setStep(.tried(t, ok: false, heard: toks.isEmpty ? "" : trimmed))
            }
        default: return false
        }
        return true
    }

    private func applyTeach(_ res: VoiceTraining.TeachResult, trick t: VoiceTrick, tr: TrainSession, bk: VoiceTraining, transcript: String) {
        switch res {
        case .rep(let r):
            lastBook = bk
            enqueue(r, nil, ids: [tr.subject])
            switch r {
            case .trickLearned:
                setStep(.learned(t))
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            case .learnedStep(_, let n):
                setStep(.heard(t, reps: n))
                UIImpactFeedbackGenerator(style: .soft).impactOccurred()
            default: break
            }
        case .nothing: setStep(.missed(t, why: .nothing))
        case .nameOnly: setStep(.missed(t, why: .wasName))
        case .otherWord(let heard): setStep(.missed(t, why: .otherWord(expected: bk.word(for: t) ?? t.suggestion, heard: heard)))
        case .reserved(let heard): setStep(.missed(t, why: .reserved(heard: heard)))
        }
    }

    // MARK: the room command

    /// A learned trick word said with no name and no highlight reaches every Jelbie who knows it (in a plain room; "everyone" too, the rest shrug).
    /// Named or highlighted keeps the old single-target path. True = handled.
    func roomCommand(_ transcript: String) -> Bool {
        guard let care, !care.focus.isActive, train == nil else { return false }
        let toks = VoiceMatcher.tokens(transcript)
        guard !toks.isEmpty else { return false }
        let resolved = training.names.resolve(tokens: toks)
        guard resolved.first == nil else { return false }                          // named: that Jelbie only (the existing path)
        let (all, _) = VoicePhrases.everyone(resolved.rest)
        if !all, care.select.selectedID != nil || care.select.confirmed != nil { return false }       // highlighted: only him
        let knowers = presentIDs.filter { book(for: $0).learnedTrick(in: toks) != nil }
        guard !knowers.isEmpty else { return false }
        for id in presentIDs {
            let bk = book(for: id)
            if knowers.contains(id) {
                lastBook = bk
                let d = bk.decideFull(transcript: transcript, runningMove: nil, mood: care.needs(for: id).mood, session: session)
                var kind: VoiceFeedback.Kind?
                if d.reaction == .ignore, let m = bk.lastMiss { kind = .missed(m, pct: Int((bk.reliability(m) * 100).rounded())) }
                care.wakeSleeper(id)
                care.noteInteraction(jelly: id)
                enqueue(d.reaction, kind, ids: [id], target: .jelly(id))
            } else if all {
                enqueue(.ignore, VoiceFeedback.Kind.unknown, ids: [id], target: .jelly(id))
            }
        }
        recordParseRoom()
        return true
    }
}
