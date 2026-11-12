//
//  GameCare+Tricks.swift
//  What each Jelbie knows (Store/TrickCatalog.swift). The one-time move from the old lesson books runs here once the profiles exist: every trick a Jelbie
//  had learned becomes owned by THAT Jelbie, every owned page (spin, hop) by every Jelbie in the room.
//

import Foundation

extension GameCare {
    /// Runs the store-tricks migration (once; StoreBook.tricksMigrated). Also reads the saved books of characters who are not in the room right now.
    func migrateTricks(defaults: UserDefaults) {
        guard store.saved.tricksMigrated != true else { return }
        var learned: [Int: [VoiceTrick]] = [:]
        for j in jellies { learned[j.character] = VoiceTrick.allCases.filter { j.training.isLearned($0) } }
        for c in 0..<JellyRoster.knownCount where learned[c] == nil {
            learned[c] = VoiceTraining.savedLearnedTricks(defaults: defaults, key: JellyKeys.words(c))
        }
        store.migrateTricks(learned: learned, roster: jellies.map(\.character))
    }

    /// The Jelbie the voice and the trick book are about now: the one in a one-Jelbie close-up, else the selected / targeted one.
    var voiceSubject: Int { (focus.isActive && focusGroup.ids.count == 1) ? focusGroup.ids[0] : targetJelly }

    /// Does the Jelbie in room slot `id` know `t`?
    func knows(_ t: VoiceTrick, jelly id: Int) -> Bool { store.knows(t, character: jelly(id)?.character ?? id) }

    // MARK: the Tricks button (selected-Jelbie menu)

    /// One chip of the Tricks row.
    struct TrickChip: Identifiable, Equatable {
        let trick: VoiceTrick
        /// False = locked: the chip shows the price and opens the Shop's Tricks tab.
        let known: Bool
        let price: Int
        var id: String { trick.rawValue }
    }

    /// The row for this Jelbie: what he knows (defaults + bought) in stage order, then what he does not (locked, in Shop order).
    func trickMenu(jelly id: Int) -> [TrickChip] {
        let known = ShowTrickInfo.stageTricks.filter { knows($0, jelly: id) }.map { TrickChip(trick: $0, known: true, price: 0) }
        let locked = TrickCatalog.forSale.filter { ShowTrickInfo.stageTricks.contains($0.trick) && !knows($0.trick, jelly: id) }.map { TrickChip(trick: $0.trick, known: false, price: $0.price) }
        return known + locked
    }

    /// Why he cannot do a trick right now, in a few words (nil = he can).
    func trickBlocker(jelly id: Int) -> String? {
        guard let b = brainFor(id) else { return "Not in the room" }
        let name = jelly(id)?.name ?? "He"
        if b.isSleeping { return "\(name) is asleep" }
        if trayOut || meal != nil || wanted != nil || b.activity == .eating || b.activity == .drinking { return "Not while eating" }
        if bath.active { return "Not while cleaning" }
        if tripActive || raceBusy || cafe.active { return "Not while away" }
        if b.activity == .touched || b.held { return "Not while you're holding him" }
        return nil
    }

    /// The player's tap on a known trick chip: that Jelbie does it at once. Always succeeds (no reliability roll). False = blocked or not his trick.
    @discardableResult
    func performTrick(_ t: VoiceTrick, jelly id: Int) -> Bool {
        guard trickBlocker(jelly: id) == nil, knows(t, jelly: id), let b = brainFor(id) else { return false }
        b.idleState.trickFailNext = false          // (the button always succeeds: a flop flag left over from the Show must not turn this into a flop)
        if t == .flip {
            b.flipCompact = focus.isActive
            b.commandedFlipFail = false
            b.commandedFlip = true
        } else if let k = VoiceCoordinator.idleKind(for: t) {
            if t == .superSpring || t == .corkscrew { b.flipCompact = focus.isActive }
            b.commandedIdle = k
        } else { return false }
        b.face(.excited, hold: 1.2)
        AudioHub.shared.uiConfirm()
        return true
    }
}
