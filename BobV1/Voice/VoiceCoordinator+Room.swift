//
//  VoiceCoordinator+Room.swift
//  The room command: a trick word said with no name and no highlight reaches every Jelbie who knows it (tricks are bought in the Shop, Store/TrickCatalog.swift);
//  named or highlighted keeps the single-target path. Also the listen-session ids.
//

import Foundation

extension VoiceCoordinator {
    /// A listen-session id unique across EVERY book (each Jelbie keeps its own book, so a per-book counter could repeat another book's id).
    func nextSession() -> Int {
        let books = [training] + (care?.jellies.map(\.training) ?? [])
        let s = (books.map(\.sessionCounter).max() ?? 0) + 1
        for b in books { b.adoptSession(s) }
        return s
    }

    /// A trick word said with no name and no highlight reaches every Jelbie who knows it (in a plain room; "everyone" too, the rest shrug).
    /// Named or highlighted keeps the old single-target path. True = handled.
    func roomCommand(_ transcript: String) -> Bool {
        guard let care, !care.focus.isActive else { return false }
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
                enqueue(.dontKnow(.sit), VoiceFeedback.Kind.unknown, ids: [id], target: .jelly(id))
            }
        }
        recordParseRoom()
        return true
    }
}
