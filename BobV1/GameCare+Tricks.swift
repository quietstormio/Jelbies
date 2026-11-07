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
        for c in 0..<JellyRoster.characterCount where learned[c] == nil {
            learned[c] = VoiceTraining.savedLearnedTricks(defaults: defaults, key: JellyKeys.words(c))
        }
        store.migrateTricks(learned: learned, roster: jellies.map(\.character))
    }

    /// Does the Jelbie in room slot `id` know `t`?
    func knows(_ t: VoiceTrick, jelly id: Int) -> Bool { store.knows(t, character: jelly(id)?.character ?? id) }
}
