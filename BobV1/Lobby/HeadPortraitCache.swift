//
//  HeadPortraitCache.swift
//  The lobbies' Jelbie pictures (the picker tiles' heads and the Studio's action shot), kept across lobby opens. One entry per HeadPortraitKey, for the wardrobe / shop state it was drawn in
//  (`store.revision`) and the Jelbie's character, so a Dress up or an adoption draws a fresh one and nothing else does. A lobby asks for its picture synchronously first (a hit shows
//  in the very frame the lobby appears), and the Town (the stage is paused behind it) draws every roster head before any lobby is opened.
//  `-PortraitCacheOff 1` brings back the old behaviour (350 ms wait, 300 ms polling, no cache) for before / after timings.
//

import UIKit

@MainActor
final class HeadPortraitCache {
    static let shared = HeadPortraitCache()
    static var enabled: Bool { UserDefaults.standard.object(forKey: "PortraitCacheOff") == nil }

    private struct Entry: Hashable { var key: HeadPortraitKey; var revision: Int; var character: Int }
    private var images: [Entry: UIImage] = [:]
    private var warming: Task<Void, Never>?

    private func entry(_ key: HeadPortraitKey, _ care: GameCare) -> Entry {
        Entry(key: key, revision: care.store.revision, character: care.jelly(key.jelly)?.character ?? key.jelly)
    }

    /// The picture drawn earlier for this key in the current wardrobe state, if any.
    func cached(_ key: HeadPortraitKey, care: GameCare) -> UIImage? { Self.enabled ? images[entry(key, care)] : nil }

    /// Draws it now if the stage can (nil: not yet), and remembers it.
    func render(_ key: HeadPortraitKey, care: GameCare) -> UIImage? {
        let e = entry(key, care)
        if Self.enabled, let hit = images[e] { return hit }
        guard let img = care.headProvider?(key) else { return nil }
        if Self.enabled {
            if images.keys.contains(where: { $0.revision != e.revision }) { images = images.filter { $0.key.revision == e.revision } }
            images[e] = img
        }
        return img
    }

    /// The picture, waiting for the stage's first frame if it has to (a cache hit or a ready stage answers at once).
    func image(_ key: HeadPortraitKey, care: GameCare) async -> UIImage? {
        if !Self.enabled { try? await Task.sleep(nanoseconds: 350_000_000) }
        for _ in 0..<60 {
            await Task.yield()
            if Task.isCancelled { return nil }
            if let img = render(key, care: care) { return img }
            try? await Task.sleep(nanoseconds: Self.enabled ? 100_000_000 : 300_000_000)
        }
        return nil
    }

    /// Every roster head (and the Studio's front action shot), drawn one at a time while the Town is open so the lobbies find them waiting. Called when the Town opens.
    /// Cooperative: each render is its own main-actor turn with a pause before it (taps, lists and the lobbies' own pictures never queue behind more than one render), it never
    /// polls (a stage that is not ready yet ends the pass; the next Town open starts another), it stops after `budget` seconds, and `cancelPrewarm()` ends it at once.
    func prewarm(care: GameCare) {
        guard Self.enabled, warming == nil else { return }
        warming = Task { @MainActor [weak self] in
            let t0 = CACurrentMediaTime(), budget = 6.0
            var drawn = 0
            outer: for j in care.jellies.prefix(3) {
                for pose in [nil, 0] as [Int?] {
                    try? await Task.sleep(nanoseconds: 120_000_000)                 // let the run loop serve whatever the player just did
                    if Task.isCancelled || CACurrentMediaTime() - t0 > budget { break outer }
                    let key = HeadPortraitKey(jelly: j.id, colour: nil, wear: nil, pose: pose)
                    if self?.cached(key, care: care) != nil { continue }
                    guard self?.render(key, care: care) != nil else { break outer }        // stage not ready: stop, never retry in a loop
                    drawn += 1
                }
            }
            NSLog("[portrait] prewarmed %d pictures in %.0f ms", drawn, (CACurrentMediaTime() - t0) * 1000)
            self?.warming = nil
        }
    }

    /// The player touched something (or the Town closed): the rest of the pass is not worth a hitch.
    func cancelPrewarm() { warming?.cancel(); warming = nil }
}
