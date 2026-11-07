//
//  PlayAssist.swift
//  Timing assists for the Jelly Circuit race (round-1023 a11y), chosen in Settings > Accessibility (`A11ySettings.raceAssist`):
//
//      forgiving   two buttons; a repeated foot is forgiven in the race
//      oneButton   ONE "Step" button; the feet alternate by themselves (a stumble is impossible)
//      auto        he runs by himself at a steady pace; the player cheers. Pays HALF the Drops (the footnote says so)
//
//  Relaxed timing (`relaxedTiming`) widens every rhythm window x2.5. Nothing here changes the locked gait: it only decides which taps reach the existing models.
//

import Foundation
import UIKit
import SwiftUI

extension RaceFlow {
    /// Test seam: records the sides of the audio cues played before each dance prompt (ShowFlow.promptCues).
    nonisolated(unsafe) static var cueLog: [Int] = []

    /// Taps per second of the auto run (about an average player).
    static let autoAssistTapRate: Float = 4.5
    /// The payout share of an auto run.
    static let autoPayShare: Float = 0.5

    /// The auto run's tap rate (nil unless the assist is `auto` in a race).
    var autoAssistRate: Float? { assist == .auto ? Self.autoAssistTapRate : nil }

    /// Called by `begin`: reads the settings and prepares the sim.
    func applyAssistAtStart() {
        assist = A11ySettings.shared.raceAssist
        if assist != .off { sim?.setPlayerGrace(0.6) }          // a repeated finger bounce is forgiven (already supported by the tap model)
    }

    /// Drops after the assist (the auto run pays half).
    func assistedDrops(_ drops: Int) -> Int { assist == .auto ? Int((Float(drops) * Self.autoPayShare).rounded(.down)) : drops }

    /// The one big Step button: counts as the other foot than the last tap.
    @discardableResult
    func stepOne() -> RaceTapModel.Outcome {
        let foot = sim?.racers[0].tap.alternateFoot ?? 0
        return tap(foot: foot)
    }

    // MARK: announcements

    func announceRace(_ e: RaceEvent) {
        switch e {
        case .countdown(let n): A11yEvents.say("\(n)", .high)
        case .go: A11yEvents.say("Go!", .high)
        case .stumble(let r) where r == RaceSim.playerIndex: A11yEvents.say("Same foot. Stumble")
        case .trip(let r) where r == RaceSim.playerIndex: A11yEvents.say("Tripped. Keep going")
        default: break
        }
    }

    func announceRaceResult() {
        guard let s = sim else { return }
        A11yEvents.say(A11yEvents.raceFinish(name: playerName, place: s.playerPlace, drops: earned), .high)
    }
}

// MARK: - the Show

/// The assists the Jelly Show's models read (they are `nonisolated`, so these are plain globals set from the main actor when a show / practice starts).
nonisolated enum ShowAssist {
    nonisolated(unsafe) static var windowScale = 1.0
    nonisolated(unsafe) static var ringScale = 1.0
    nonisolated(unsafe) static var anyFoot = false
    nonisolated(unsafe) static var autoDance = false

    @MainActor static func refresh(_ s: A11ySettings = .shared) {
        windowScale = max(s.timingScale, s.raceAssist == .forgiving ? 2 : 1)
        ringScale = (s.relaxedTiming || s.raceAssist != .off) ? 2 : 1          // the ring closes at half speed
        anyFoot = s.raceAssist == .oneButton
        autoDance = s.raceAssist == .auto
    }
    @MainActor static func reset() { windowScale = 1; ringScale = 1; anyFoot = false; autoDance = false }
}

// MARK: - the foot buttons of the rhythm screens (Show dance / practice)

/// Portrait row: Left + Right, or one wide Step, or a Cheer button, by the chosen assist.
struct AssistFeetRow: View {
    let prefix: String
    let live: Bool
    let press: (Int) -> Void
    var body: some View {
        switch A11ySettings.shared.raceAssist {
        case .oneButton:
            FootButton(title: "Step", id: "\(prefix)-step", symbol: "shoeprints.fill", flip: false, live: live, key: .space) { press(0) }
        case .auto:
            FootButton(title: "Cheer", id: "\(prefix)-cheer", symbol: "hands.clap.fill", flip: false, live: true, key: .space) { AudioHub.shared.chirp(jelly: 0, .happy) }
        default:
            HStack(spacing: 14) {
                FootButton(title: "Left", id: "\(prefix)-left", symbol: "shoeprints.fill", flip: false, live: live, key: .leftArrow) { press(0) }
                FootButton(title: "Right", id: "\(prefix)-right", symbol: "shoeprints.fill", flip: true, live: live, key: .rightArrow) { press(1) }
            }
        }
    }
}

/// One side button of the landscape layout (both sides are the same Step / Cheer under those assists).
struct AssistFoot: View {
    let side: Int
    let prefix: String
    let live: Bool
    let press: (Int) -> Void
    var body: some View {
        switch A11ySettings.shared.raceAssist {
        case .oneButton:
            FootButton(title: "Step", id: "\(prefix)-step\(side == 0 ? "" : "-2")", symbol: "shoeprints.fill", flip: side == 1, live: live, key: side == 0 ? .space : nil) { press(0) }
        case .auto:
            FootButton(title: "Cheer", id: "\(prefix)-cheer\(side == 0 ? "" : "-2")", symbol: "hands.clap.fill", flip: false, live: true, key: side == 0 ? .space : nil) { AudioHub.shared.chirp(jelly: 0, .happy) }
        default:
            FootButton(title: side == 0 ? "Left" : "Right", id: "\(prefix)-\(side == 0 ? "left" : "right")", symbol: "shoeprints.fill", flip: side == 1, live: live, key: side == 0 ? .leftArrow : .rightArrow) { press(side) }
        }
    }
}

// MARK: - arranging the room without a drag

enum ArrangeDirection: String, CaseIterable, Sendable {
    case left, right, forward, back
    /// A step on the floor (x, z): forward is toward the camera.
    var delta: SIMD2<Float> {
        switch self { case .left: return SIMD2(-ArrangeAssist.step, 0); case .right: return SIMD2(ArrangeAssist.step, 0)
        case .forward: return SIMD2(0, ArrangeAssist.step); case .back: return SIMD2(0, -ArrangeAssist.step) }
    }
    var symbol: String { switch self { case .left: return "arrow.left"; case .right: return "arrow.right"; case .forward: return "arrow.down"; case .back: return "arrow.up" } }
    var title: String { switch self { case .left: return "Move left"; case .right: return "Move right"; case .forward: return "Move closer"; case .back: return "Move back" } }
}

@MainActor
enum ArrangeAssist {
    static let step: Float = 0.35

    /// Moves piece `uid` one step (the same drag + drop the finger makes, so the snap and obstacle rules are the finger's). True when it moved.
    @discardableResult
    static func move(_ uid: Int, _ dir: ArrangeDirection, care: GameCare) -> Bool {
        guard let p = care.store.placedDecor.first(where: { $0.uid == uid }) else { return false }
        let moved = care.dragDecor(uid, to: p.at + dir.delta)
        if moved { care.dropDecor(uid) }
        let name = p.kind.title
        A11yAnnounce.say(moved ? "\(name) moved \(dir.rawValue == "forward" ? "closer" : dir.rawValue)" : "\(name) can't go there", priority: .high)
        return moved
    }

    /// Selects the next piece (wrapping); nil when the room has none.
    @discardableResult
    static func next(care: GameCare) -> Int? {
        let ids = care.store.placedDecor.map(\.uid)
        guard !ids.isEmpty else { return nil }
        let i = care.arrangingUID.flatMap { ids.firstIndex(of: $0) }.map { ($0 + 1) % ids.count } ?? 0
        care.arrangingUID = ids[i]
        let title = care.store.placedDecor[i].kind.title
        A11yAnnounce.say("\(title) selected", priority: .normal)
        return ids[i]
    }
}

extension ShowFlow {
    /// The left / right audio cue half a beat before each dance prompt (under relaxed timing or VoiceOver), before the beat.
    func promptCues(now: Double) {
        guard A11ySettings.shared.relaxedTiming || UIAccessibility.isVoiceOverRunning || A11yEvents.forceActive else { return }
        let prompts = sim?.dance?.prompts ?? []
        let lead = ShowBeat.stage.period * 0.5
        while danceCued < prompts.count {
            let p = prompts[danceCued]
            if p.time - lead > now - ShowDanceSim.latencyOffset { break }
            danceCued += 1
            if p.grade == nil {
                RaceFlow.cueLog.append(p.foot)
                AudioHub.shared.play(.tick, x: p.foot == 0 ? -5 : 5, volume: 0.8, rate: p.foot == 0 ? 1.25 : 1.7)
            }
        }
    }
}
