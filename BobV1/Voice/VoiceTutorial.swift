//
//  VoiceTutorial.swift
//  RETIRED (2026-10-17): Bob now knows "come here" from the first launch, so the card is never mounted and `isDone` starts true. The code stays
//  (and still compiles) for the debug flags below. Original: the first-trick tutorial: teach Bob to come. A small card (flat pastel, Bob stays visible) walks the existing learning path and adds no
//  second learning system: "Call him" runs the same come move as the trick-book row, any phrase said while he comes is a rep through
//  `VoiceTraining.decide`, and the dots are `VoiceTraining.progress(.come)`. Learned -> "Try it": the next listen that makes him come ends it.
//  The phase is derived (training + coordinator + mood); only "done" is persisted ("VoiceTutorial.v1", cleared by -VoiceReset).
//  "Later" hides the card for this launch only. Debug: -VoiceTutorial 1 forces the card, -VoiceTutorialStep <n> jumps (0 call, 1 saying,
//  2 try it, 3 grumpy, 4 trick book), -VoiceTutorialReps <n> pre-fills n reps of "come here".
//

import Foundation
import Observation
import SwiftUI

nonisolated enum VoiceTutorialPhase: String, Sendable {
    case hidden
    case call          // "Call him"
    case again         // reps so far, he has finished the move: "Call him again"
    case saying        // he is coming: hold the mic and say it
    case tryIt         // learned: say it and he comes
    case grumpy        // too grumpy: waits
    case book          // the mic cannot be used: the trick book explains it
}

@MainActor
@Observable
final class VoiceTutorial {
    static let key = "VoiceTutorial.v1"
    static let trick = VoiceTrick.come

    private(set) var isDone: Bool
    /// "Later": hidden for this launch only.
    private(set) var dismissed = false
    @ObservationIgnored var forced: Bool
    @ObservationIgnored var stepOverride: Int?
    @ObservationIgnored weak var voice: VoiceCoordinator?
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let persists: Bool
    @ObservationIgnored private var tryBaseline: Int?

    nonisolated deinit {}

    init(defaults: UserDefaults = .standard, persists: Bool = true) {
        self.defaults = defaults; self.persists = persists
        isDone = true                          // RETIRED: he knows "come here" from the start (VoiceTraining.ensureCome), so there is nothing to teach
        if persists { defaults.set(true, forKey: Self.key) }
        forced = persists && defaults.integer(forKey: "VoiceTutorial") != 0
        if persists, defaults.object(forKey: "VoiceTutorialStep") != nil { stepOverride = defaults.integer(forKey: "VoiceTutorialStep") }
    }

    // MARK: derived state

    var reps: Int { voice?.training.progress(Self.trick) ?? 0 }
    var learned: Bool { voice?.training.isLearned(Self.trick) ?? false }

    var phase: VoiceTutorialPhase {
        guard let v = voice else { return .hidden }
        if !forced { if isDone || dismissed { return .hidden } }
        else if dismissed { return .hidden }
        if let n = stepOverride {
            switch n { case 1: return .saying; case 2: return .tryIt; case 3: return .grumpy; case 4: return .book; default: return .call }
        }
        if v.micUnusable { return .book }
        if v.care?.mood == .grumpy { return .grumpy }
        if learned { return .tryIt }
        if v.comingNow || v.listeningToCome { return .saying }
        return reps > 0 ? .again : .call
    }
    var isShown: Bool { phase != .hidden }
    /// The mic button pulses while he is coming and while "Try it" waits.
    var pulsingMic: Bool { phase == .saying || phase == .tryIt }

    // MARK: actions

    /// "Call him": the same come move as the trick-book row.
    func call() { voice?.show(Self.trick) }
    func dismiss() { dismissed = true }
    func finish() {
        isDone = true; forced = false; stepOverride = nil
        if persists { defaults.set(true, forKey: Self.key) }
    }
    /// Debug / test: back to the start.
    func reset() {
        isDone = false; dismissed = false; tryBaseline = nil
        defaults.removeObject(forKey: Self.key)
    }

    /// Every tick (coordinator): "Try it" ends with the next listen that makes him come.
    func update() {
        guard let v = voice, !isDone else { return }
        if phase == .tryIt {
            if let b = tryBaseline { if v.comeCommands > b { finish(); tryBaseline = nil } }
            else { tryBaseline = v.comeCommands }
        } else { tryBaseline = nil }
    }
}

// MARK: - Card

/// The tutorial card, top centre under the HUD buttons.
struct VoiceTutorialCard: View {
    let tutorial: VoiceTutorial
    let voice: VoiceCoordinator
    var openBook: () -> Void

    var body: some View {
        let phase = tutorial.phase
        VStack {
            if phase != .hidden {
                card(phase)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
            Spacer()
        }
        .padding(.top, 60).padding(.horizontal, 24)
        .animation(CareMenu.spring, value: phase)
        .allowsHitTesting(phase != .hidden)
    }

    private func title(_ p: VoiceTutorialPhase) -> String {
        switch p {
        case .call: return "Teach Bob to come"
        case .again: return "Nearly there"
        case .saying: return "Hold the mic and say \u{201C}come here\u{201D}"
        case .tryIt: return "He knows it!"
        case .grumpy: return "He is too grumpy right now"
        case .book: return "Teach him in the trick book"
        case .hidden: return ""
        }
    }
    private func detail(_ p: VoiceTutorialPhase) -> String? {
        switch p {
        case .call: return "Call him, then say \u{201C}come here\u{201D} while he walks over."
        case .again: return "Call him again and say it the same way."
        case .saying: return "Say it while he is on his way."
        case .tryIt: return "Say \u{201C}come here\u{201D} any time. Try it now."
        case .grumpy: return "Feed him or play, then try again."
        case .book: return "The mic is off. Tap Come in the trick book, then say your word aloud when the mic is on."
        default: return nil
        }
    }

    private func card(_ p: VoiceTutorialPhase) -> some View {
        VStack(spacing: 8) {
            Text(title(p))
                .font(.system(size: 17, weight: .bold, design: .rounded)).foregroundStyle(FocusStyle.brown)
                .multilineTextAlignment(.center)
                .accessibilityIdentifier("voice-tutorial-title")
            if let d = detail(p) {
                Text(d)
                    .font(.system(size: 13, weight: .medium, design: .rounded)).foregroundStyle(FocusStyle.brown.opacity(0.85))
                    .multilineTextAlignment(.center)
            }
            if p == .call || p == .again || p == .saying {
                HStack(spacing: 6) {
                    ForEach(0..<VoiceTuning.repsToLearn, id: \.self) { i in
                        Circle().fill(i < tutorial.reps ? FocusStyle.pink : FocusStyle.brown.opacity(0.15)).frame(width: 10, height: 10)
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityIdentifier("voice-tutorial-dots")
                .accessibilityLabel("\(tutorial.reps) of \(VoiceTuning.repsToLearn) lessons")
                .accessibilityValue("\(tutorial.reps)")
            }
            HStack(spacing: 10) {
                switch p {
                case .call, .again:
                    pill(p == .call ? "Call him" : "Call him again", prominent: true, id: "voice-tutorial-call") {
                        UIImpactFeedbackGenerator(style: .soft).impactOccurred(); AudioHub.shared.uiTap()
                        tutorial.call()
                    }
                    .disabled(voice.isListening)
                    pill("Later", prominent: false, id: "voice-tutorial-later") { tutorial.dismiss() }
                case .book:
                    pill("Open tricks", prominent: true, id: "voice-tutorial-book") { openBook() }
                    pill("Got it", prominent: false, id: "voice-tutorial-done") { tutorial.finish() }
                default:
                    pill("Later", prominent: false, id: "voice-tutorial-later") { tutorial.dismiss() }
                }
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .frame(maxWidth: 340)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(FocusStyle.cream.opacity(0.96))
            .shadow(color: FocusStyle.shadow.opacity(0.2), radius: 8, y: 3))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(DT.line, lineWidth: 1))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("voice-tutorial")
        .accessibilityValue(p.rawValue)
    }

    private func pill(_ text: String, prominent: Bool, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(text)
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(prominent ? Color.white : FocusStyle.brown)
                .padding(.horizontal, 16).padding(.vertical, 8)
                .background(Capsule().fill(prominent ? FocusStyle.pink : FocusStyle.brown.opacity(0.1)))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(id)
    }
}
