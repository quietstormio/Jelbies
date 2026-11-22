//
//  GameCare+BestHug.swift
//  The hug's gate, its memory and its show (the motion is BlobBrain+BestHug.swift).
//  GATE   `BestHug.isUnlocked(for: character)`: the best-friends stage. Until the Relationship level lands, the launch argument `-BestHugUnlocked 1` (DevArgs only) opens it for everyone;
//         the Relationship work swaps `BestHug.provider` (one line). Keyed by CHARACTER id, like every per-Jelmiko save.
//  REVEAL the first time it is open for a Jelmiko: the next time he is awake, free and the player is watching the room, he comes forward and hugs once, with ONE message in the game's
//         message bar. Remembered per character (`BestHug.revealKey`), purged with the creature's other data (StartFlow.resetCharacterState).
//  SHOW   hearts / haptics: the brain raises counters, this drains them once per step through the cuddle's own heart effect (touchPlay for slot 0, bubbleHub for the others).
//

import Foundation
import QuartzCore

nonisolated enum BestHug {
    /// The unlock. nil = the dev launch argument; the Relationship level replaces it with `{ id in level(of: id) == .bestFriends }`.
    nonisolated(unsafe) static var provider: ((Int) -> Bool)?
    static func isUnlocked(for id: Int) -> Bool {
        if let p = provider { return p(id) }
        return DevArgs.enabled && UserDefaults.standard.integer(forKey: "BestHugUnlocked") != 0
    }
    /// What a locked Hug chip says.
    static let hint = "Reach Best friends to unlock"
    static func message(name: String) -> String { "\(name) and you are best friends! New trick: Hug" }

    static func revealKey(_ id: Int) -> String { "BestHug.revealShown.\(id)" }
    static func revealShown(_ id: Int, _ d: UserDefaults = .standard) -> Bool { d.bool(forKey: revealKey(id)) }
    static func markRevealShown(_ id: Int, _ d: UserDefaults = .standard) { d.set(true, forKey: revealKey(id)) }
    static func purge(_ id: Int, _ d: UserDefaults = .standard) { d.removeObject(forKey: revealKey(id)) }
    /// Capture aid (dev only): `-BestHugReveal 0` keeps the reveal from firing so a `-GameAction hug` take is the only hug.
    static var revealAllowed: Bool { !(DevArgs.enabled && UserDefaults.standard.object(forKey: "BestHugReveal") != nil && UserDefaults.standard.integer(forKey: "BestHugReveal") == 0) }
}

extension GameCare {
    /// Once per fixed step: the hearts and buzz the hugging brains raised, and the reveal check.
    func tickBestHug(dt: Float) {
        let now = CACurrentMediaTime()
        for id in jellies.indices {
            guard let b = brainFor(id) else { continue }
            while b.bestHug.hearts > 0 {
                b.bestHug.hearts -= 1
                bubbleHub.spawnHeart(for: id, now: now)          // (the hub's hearts for every slot, Bob too: the touch play's own list is wiped every frame it has no finger on him)
            }
            if b.bestHug.bigHeart {
                b.bestHug.bigHeart = false
                bubbleHub.spawnHeart(for: id, now: now, big: true)
            }
            if b.bestHug.buzz > 0 {
                let i = b.bestHug.buzz; b.bestHug.buzz = 0
                touchPlay?.haptics.transient(now: now, intensity: i, sharpness: 0.22)          // (the cuddle's own driver: it also plays in the close-up, where the room cues are refused)
            }
        }
        revealCheck(dt: dt)
    }

    /// The reveal: one Jelmiko at a time, at most once per character, never in the close-up, a meal, a bath, a show ...
    private func revealCheck(dt: Float) {
        guard BestHug.revealAllowed, !focus.isActive, focus.phase == .roaming, !greeting, !callRunning else { return }
        revealClock -= dt
        guard revealClock <= 0 else { return }
        revealClock = 0.5
        for id in jellies.indices {
            let c = jellies[id].character
            guard BestHug.isUnlocked(for: c), !BestHug.revealShown(c), let b = brainFor(id), b.watching, !b.isSleeping, !b.bestHug.want, !b.bestHug.afterWalk,
                  b.idleState.kind == nil, case .none = b.script, b.pending == nil, trickBlocker(jelly: id) == nil else { continue }
            BestHug.markRevealShown(c)
            GameMessageCenter.shared.post(BestHug.message(name: jellies[id].name), icon: "heart.fill", priority: .important, identifier: "best-hug-reveal")
            _ = performTrick(.hug, jelly: id)
            return
        }
    }
}
