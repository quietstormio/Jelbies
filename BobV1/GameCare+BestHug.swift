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
        if DevArgs.enabled && UserDefaults.standard.integer(forKey: "BestHugUnlocked") != 0 { return true }          // (dev override)
        return bestFriends(id)
    }
    /// The top Relationship stage ("Best friends": all five hearts full, Jelly/JellyBond.swift). Read straight from the save, never seeding it (an unseeded creature is at most `seedCap`, far from the top).
    static func bestFriends(_ id: Int, _ d: UserDefaults = .standard) -> Bool {
        ((d.dictionary(forKey: JellyBond.key(id))?["p"] as? Int) ?? 0) >= (BondTuning.heartFull.last ?? Int.max)
    }
    /// What a locked Hug chip says.
    static let hint = "Reach Best friends to unlock Bond"
    static func message(name: String) -> String { "\(name) and you are best friends! New trick: Bond" }

    static func revealKey(_ id: Int) -> String { "BestHug.revealShown.\(id)" }
    static func revealShown(_ id: Int, _ d: UserDefaults = .standard) -> Bool { d.bool(forKey: revealKey(id)) }
    static func markRevealShown(_ id: Int, _ d: UserDefaults = .standard) { d.set(true, forKey: revealKey(id)) }
    static func purge(_ id: Int, _ d: UserDefaults = .standard) { d.removeObject(forKey: revealKey(id)) }
    /// Capture aid (dev only): `-BestHugReveal 0` keeps the reveal from firing so a `-GameAction hug` take is the only hug.
    static var revealAllowed: Bool { !(DevArgs.enabled && UserDefaults.standard.object(forKey: "BestHugReveal") != nil && UserDefaults.standard.integer(forKey: "BestHugReveal") == 0) }
}

/// A Bond that brings him to the front first: the close-up's own approach and camera ease, the hug in place, then the close-up's own release.
struct BondRunState {
    var slot: Int
    /// 0 coming to the front (the close-up's approach), 1 settling on the spot, 2 hugging.
    var stage = 0
    var t: Float = 0
    var seenHug = false
}

extension GameCare {
    /// The player asked for Bond (the Tricks row, voice, the reveal) for the Jelmiko in `slot`. His camera is the cuddle close-up: it eases in while he comes to the front, holds for the
    /// hug, eases out at the release. Already in HIS close-up: the hug in place, no extra move. Asleep, or the close-up cannot start (a bath, a trip): the hug where he stands.
    func startBond(slot id: Int) {
        guard let b = brainFor(id), bondRun == nil else { return }
        if b.isSleeping { b.commandBestHug(inPlace: false); return }
        if focus.phase == .focused, focusGroup.includes(id) {
            if GameMessageCenter.shared.current?.identifier == "focus-hint" { GameMessageCenter.shared.dismiss(identifier: "focus-hint"); bondHintRestore = true; bondHugSeen = false }          // (the cuddle hint is off for the length of the hug and comes back after it)
            b.commandBestHug(inPlace: true); return
        }
        if focus.phase == .roaming, !bath.active, !tripActive {
            FocusHint.suppressed = true          // (the close-up's first-visits hint stays off for a Bond that brings him to the front)
            beginFocus(ids: [id])
            if focus.phase == .approaching { bondRun = BondRunState(slot: id); return }
            FocusHint.suppressed = false
        }
        b.commandBestHug(inPlace: false)
    }
    func startBond(brain b: BlobBrain) {
        guard let id = jellies.indices.first(where: { brainFor($0) === b }) else { b.commandBestHug(inPlace: false); return }
        startBond(slot: id)
    }

    /// The run's per-step work: wait for the close-up, settle, hug, then let him go (the close-up's own release). Anything that ends the close-up on the way ends the run.
    private func tickBondRun(dt: Float) {
        defer { FocusHint.suppressed = bondRun != nil }
        guard var r = bondRun else { return }
        r.t += dt
        guard let b = brainFor(r.slot), r.t < 40 else { bondRun = nil; if focus.phase == .focused || focus.phase == .approaching { release() }; return }
        switch r.stage {
        case 0:
            if focus.phase == .focused, focusGroup.includes(r.slot) { r.stage = 1; r.t = 0 }
            else if focus.phase == .roaming || focus.phase == .leaving { bondRun = nil; return }
        case 1:
            guard focus.phase == .focused else { bondRun = nil; return }
            if r.t > 0.9 { b.commandBestHug(inPlace: true); r.stage = 2; r.t = 0 }
        default:
            if focus.phase != .focused { bondRun = nil; return }
            if b.isBestHugging { r.seenHug = true }
            if (r.seenHug && !b.isBestHugging && !b.bestHug.want && !b.bestHug.go) || r.t > 12 { bondRun = nil; release(); return }
        }
        bondRun = r
    }

    /// Dev captures only: `-BestHugBondSetAll <points>` sets every Jelmiko's Relationship points once (the day's table is cleared, so the next earning counts);
    /// `-BestHugEarnAfter <s>` then earns one stroke event for each of them after that many seconds (the honest way across the line).
    private func bestHugDevTick(dt: Float) {
        guard DevArgs.enabled else { return }
        let d = UserDefaults.standard
        bestHugDevT += dt
        if bestHugDevFlags & 1 == 0, bestHugDevT > 0.5, d.object(forKey: "BestHugBondSetAll") != nil {
            bestHugDevFlags |= 1
            for j in jellies { d.set(["p": max(d.integer(forKey: "BestHugBondSetAll"), 0), "d": 0, "t": [String: Int]()] as [String: Any], forKey: JellyBond.key(j.character)) }
        }
        if bestHugDevFlags & 2 == 0, d.double(forKey: "BestHugEarnAfter") > 0, bestHugDevT > Float(d.double(forKey: "BestHugEarnAfter")) {
            bestHugDevFlags |= 2
            for j in jellies { bondEarn(.stroke, slot: j.id) }
        }
    }

    /// Once per fixed step: the hearts and buzz the hugging brains raised, the Bond run, and the reveal check.
    func tickBestHug(dt: Float) {
        bestHugDevTick(dt: dt)
        tickBondRun(dt: dt)
        let now = CACurrentMediaTime()
        for id in jellies.indices {
            guard let b = brainFor(id) else { continue }
            while b.bestHug.hearts > 0 {
                b.bestHug.hearts -= 1
                bubbleHub.spawnHeart(for: id, now: now, top: true)          // (the hub's hearts for every slot, Bob too: the touch play's own list is wiped every frame it has no finger on him)
            }
            while b.bestHug.burst > 0 { b.bestHug.burst -= 1; bubbleHub.spawnHeart(for: id, now: now, top: true) }
            if b.bestHug.bigHeart {
                b.bestHug.bigHeart = false
                bubbleHub.spawnHeart(for: id, now: now, big: true, top: true)
            }
            if b.bestHug.buzz > 0 {
                let i = b.bestHug.buzz; b.bestHug.buzz = 0
                touchPlay?.haptics.transient(now: now, intensity: i, sharpness: 0.22)          // (the cuddle's own driver: it also plays in the close-up, where the room cues are refused)
            }
        }
        if bondHintRestore {          // the hug is over and he is still in the close-up: the hint comes back exactly as it was
            let hugging = jellies.indices.contains { id in brainFor(id).map { $0.isBestHugging || $0.bestHug.want || $0.bestHug.go } ?? false }
            if hugging { bondHugSeen = true }
            else if bondHugSeen || !focus.isActive {
                bondHintRestore = false; bondHugSeen = false
                if focus.phase == .focused { GameMessageCenter.shared.post(FocusHint.hintText, priority: .chatty, identifier: "focus-hint", sticky: GameMessageCenter.hintsSticky) }
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
