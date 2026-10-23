//
//  A11yEvents.swift
//  VoiceOver announcements from game state (round-1023 a11y). Everything goes through `A11yEvents.say`, which only speaks while VoiceOver runs
//  (tests force it with `forceActive`), then through the shared `A11yAnnounce.say` (de-dupe, the in-app "announce" setting, the test sink).
//  `GameCare.a11yEvents.poll(...)` watches the state that has no callback (needs, sleep, close-up, Drops); the flows (race, drill, show, bath, voice)
//  call the static helpers below from their existing events.
//

import Foundation
import UIKit

@MainActor
final class A11yEvents {
    /// Test seam: speak as if VoiceOver ran.
    static var forceActive = false
    static var isActive: Bool { forceActive || UIAccessibility.isVoiceOverRunning }

    static func say(_ text: String, _ priority: A11yAnnounce.Priority = .normal) {
        guard isActive else { return }
        A11yAnnounce.say(text, priority: priority)
    }

    // MARK: pure messages (tested)

    static func needAppeared(name: String, kind: NeedKind, tier: NeedTier) -> String { "\(name) is \(tier.word(kind).lowercased())" }
    static func needFixed(name: String, kind: NeedKind) -> String {
        switch kind {
        case .hunger: return "\(name) is full"
        case .thirst: return "\(name) is not thirsty any more"
        case .attention: return "\(name) feels loved"
        }
    }
    static func ordinal(_ p: Int) -> String { p == 1 ? "1st" : p == 2 ? "2nd" : p == 3 ? "3rd" : "\(p)th" }
    static func raceFinish(name: String, place: Int?, drops: Int) -> String {
        guard let place else { return "\(name) finished" }
        return "\(name) finished \(ordinal(place)). \(drops) Drops"
    }
    static func trickLearned(name: String, trick: String) -> String { "\(name) learned \(trick)" }

    // MARK: poll

    private weak var care: GameCare?
    private var seenWanted: [Int: NeedKind?] = [:]
    private var seenFixed: [Int: Int] = [:]
    private var seenAsleep: [Int: Bool] = [:]
    private var lastNeedSay: [Int: Double] = [:]
    private var lastSleepSay: [Int: Double] = [:]
    private var seenPhase: FocusPhase?
    private var lastDrops: Int?

    init(care: GameCare) { self.care = care }
    nonisolated deinit {}

    /// Call a few times a second while an assistive technology runs. `now`: seconds (the throttles).
    func poll(now: Double = CACurrentMediaTime()) {
        guard let care else { return }
        for j in care.jellies {
            let w = j.needs.wantedNeed
            if let prev = seenWanted[j.id], prev != w {
                if let w, now - (lastNeedSay[j.id] ?? -99) > 10 {
                    lastNeedSay[j.id] = now
                    Self.say(Self.needAppeared(name: j.name, kind: w, tier: j.needs.tier(w)))
                }
            }
            seenWanted[j.id] = w
            let fixed = j.needs.fixedCount
            if let prev = seenFixed[j.id], fixed != prev, let k = j.needs.lastFixed { Self.say(Self.needFixed(name: j.name, kind: k)) }
            seenFixed[j.id] = fixed
            let asleep = care.selectBrain(j.id)?.isSleeping ?? false
            if let prev = seenAsleep[j.id], prev != asleep, now - (lastSleepSay[j.id] ?? -99) > 10 {
                lastSleepSay[j.id] = now
                Self.say(asleep ? "\(j.name) fell asleep" : "\(j.name) woke up")
            }
            seenAsleep[j.id] = asleep
        }
        let phase = care.focus.phase
        if let prev = seenPhase, prev != phase {
            if phase == .focused, let id = care.focusGroup.ids.first {
                let n = care.focusGroup.ids.count
                Self.say(n > 1 ? "Close-up with everyone. Use the actions to pet" : "Close-up with \(care.jelly(id)?.name ?? "your Jelbie"). Use the actions to pet", .high)
            } else if phase == .roaming, prev == .leaving { Self.say("Back in the room") }
        }
        seenPhase = phase
        let drops = care.bath.wallet.count
        if let l = lastDrops, drops > l, !care.tripActive { Self.say("+\(drops - l) Drops") }
        lastDrops = drops
    }
}
