//
//  GameCare+Training.swift
//  Voice-trick training happens in the close-up, one Jelly at a time (W2, 2026-10-22): the "Train" button (W3) calls `beginTraining(id)`, the camera comes in on that Jelly and,
//  on arrival, the Train card starts (TrainSession): pick a trick, he does it, the mic listens by itself, three reps teach it, then Try it. Tricks are per character (JellyKeys.words), so the voice teaching, the book and the Show all read that Jelly's book.
//

import Foundation

extension GameCare {
    /// W3's "Train" button: a close-up on `id` whose arrival opens that Jelly's trick book.
    func beginTraining(_ id: Int, preselect: VoiceTrick? = nil) {
        guard jellies.indices.contains(id) else { return }
        voice.trainPreselect = preselect
        if focus.isActive, focusGroup.ids == [id] {          // already in his close-up: the Train card starts now (or on arrival)
            if focus.phase == .focused { focusGroup.trainPending = false; focusGroup.training = true; voice.startTrain(subject: id) }
            else { focusGroup.trainPending = true }
            return
        }
        if focus.phase != .roaming { release(); return }          // (a different close-up: let go first; W3 disables the button until it is over)
        beginFocus(ids: [id])
        focusGroup.trainPending = focusGroup.ids == [id]
    }
    /// The Jelly the voice teaching and the trick book are about now: the one in a one-Jelly close-up, else the selected / targeted one.
    var trainingSubject: Int { (focus.isActive && focusGroup.ids.count == 1) ? focusGroup.ids[0] : targetJelly }
    var isTrainingCloseUp: Bool { focus.isActive && focusGroup.ids.count == 1 && focusGroup.training }
    /// Store-page locks for EVERY Jelly's book (slot 0's was the only one wired).
    func wireTrainingBooks() {
        for j in jellies { j.training.unlocked = { [weak self] t in self?.store.hasPage(t) ?? t.isStarter } }
        #if DEBUG
        if UserDefaults.standard.object(forKey: "TrainJelly") != nil {          // capture aid: `-TrainJelly 1` trains Jelly 1 a few seconds after launch
            let id = UserDefaults.standard.integer(forKey: "TrainJelly")
            Task { @MainActor [weak self] in
                while LaunchGate.shared.visible { try? await Task.sleep(for: .milliseconds(500)) }          // not under the launch curtain (a slow simulator keeps it up for a while)
                try? await Task.sleep(for: .seconds(UserDefaults.standard.object(forKey: "TrainDelay") != nil ? UserDefaults.standard.double(forKey: "TrainDelay") : 3))
                if let me = self, let p = me.jelly(id), UserDefaults.standard.object(forKey: "TrainReps") != nil { p.training.debugReps(.jacks, word: "boing", reps: UserDefaults.standard.integer(forKey: "TrainReps")) }
                self?.beginTraining(id)
            }
        }
        #endif
    }
}
