//
//  WearFittingCache.swift
//  The shop item sheet's "On <name>" picture, kept across sheet opens. One entry per (look, Jelbie), for the wardrobe / shop state and the Jelbie's character it was drawn in
//  (`store.revision`, `character`), so buying or wearing something, or an adoption, draws a fresh one and nothing else does. Same pattern as Lobby/HeadPortraitCache.swift: the
//  sheet asks synchronously first (a hit is in the very first frame, no spinner), and a miss is drawn by the stage's own snapshot call (main actor, between two frames: the
//  renderer's rule) after a short settle for the sheet's slide-up, then polled every 100 ms until the stage can answer.
//  `-WearPreviewOld 1` brings back the old behaviour (700 ms wait, 300 ms polling, no cache, spinner until the first answer) for before / after timings.
//

import UIKit

@MainActor
final class WearFittingCache {
    static let shared = WearFittingCache()
    static var enabled: Bool { UserDefaults.standard.object(forKey: "WearPreviewOld") == nil }

    private struct Entry: Hashable { var look: WearLook; var who: Int; var revision: Int; var character: Int }
    private var images: [Entry: UIImage] = [:]

    private func entry(_ look: WearLook, _ who: Int, _ care: GameCare) -> Entry {
        Entry(look: look, who: who, revision: care.store.revision, character: care.jelly(who)?.character ?? who)
    }

    /// The picture drawn earlier for this item on this Jelbie in the current wardrobe state, if any.
    func cached(_ look: WearLook, who: Int, care: GameCare) -> UIImage? { Self.enabled ? images[entry(look, who, care)] : nil }

    /// Draws it now if the stage can (nil: not yet), and remembers it.
    func render(_ look: WearLook, who: Int, care: GameCare) -> UIImage? {
        let e = entry(look, who, care)
        if Self.enabled, let hit = images[e] { return hit }
        guard let img = care.fittingProvider?(look, who) else { return nil }
        if Self.enabled {
            if images.keys.contains(where: { $0.revision != e.revision }) { images = images.filter { $0.key.revision == e.revision } }
            images[e] = img
        }
        return img
    }
}
