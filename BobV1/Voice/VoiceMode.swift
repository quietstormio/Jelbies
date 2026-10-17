//
//  VoiceMode.swift
//  Voice v1: the listen-mode state machine idle -> listening -> processing -> idle. Pure logic: the clock and the open/close ticks are injected
//  (no UIKit, no audio here); the glow overlay reads `isListening` / `glowLevel`, the speech input feeds `levelUpdate`.
//  A hold shorter than `minHold` (0.25 s) is a cancel: nothing is sent.
//

import Foundation
import Observation

nonisolated enum VoiceModeTuning {
    /// Holds shorter than this are accidents (a double-tap that did not hold): cancel, send nothing.
    static let minHold: Double = 0.25
    /// Glow smoothing per level update: quick up, slower down.
    static let attack: Float = 0.5
    static let release: Float = 0.2
}

@MainActor
@Observable
final class VoiceMode {
    enum Phase: Equatable, Sendable { case idle, listening, processing }
    enum Outcome: Equatable, Sendable { case cancelled, sent(String) }

    private(set) var phase: Phase = .idle
    /// Smoothed mic level 0...1 for the edge glow (0 whenever not listening).
    private(set) var glowLevel: Float = 0

    var isListening: Bool { phase == .listening }

    @ObservationIgnored private let now: () -> Double
    @ObservationIgnored private var openedAt: Double = 0
    /// Light haptic ticks (injected so the logic stays UIKit-free).
    @ObservationIgnored var onOpen: (() -> Void)?
    @ObservationIgnored var onClose: (() -> Void)?
    /// Called with the transcript when a hold was long enough.
    @ObservationIgnored var onSend: ((String) -> Void)?

    nonisolated deinit {}

    init(now: @escaping () -> Double = { Date.timeIntervalSinceReferenceDate }) { self.now = now }

    /// Seconds since `begin()` while listening, else 0.
    var heldFor: Double { isListening ? max(0, now() - openedAt) : 0 }
    /// True once the hold has lasted `minHold` (the host can skip waiting for the recogniser when it has not).
    var holdLongEnough: Bool { heldFor >= VoiceModeTuning.minHold }

    /// Starts listening; ignored unless idle. Returns whether it opened.
    @discardableResult
    func begin() -> Bool {
        guard phase == .idle else { return false }
        phase = .listening
        openedAt = now()
        glowLevel = 0
        onOpen?()
        return true
    }

    /// A raw mic level (0...1 RMS); the glow follows it smoothed. Ignored unless listening.
    func levelUpdate(_ level: Float) {
        guard phase == .listening else { return }
        let target = min(max(level.isFinite ? level : 0, 0), 1)
        let k = target > glowLevel ? VoiceModeTuning.attack : VoiceModeTuning.release
        glowLevel = min(max(glowLevel + (target - glowLevel) * k, 0), 1)
    }

    /// The finger lifted: the listening ends AT ONCE (glow off, close tick), before any transcript is ready. A long enough hold goes to
    /// `.processing` (then `send(_:)` delivers the transcript); a short one cancels and returns to idle. Returns whether the hold was long enough.
    @discardableResult
    func endHold() -> Bool {
        guard phase == .listening else { return false }
        let long = holdLongEnough
        glowLevel = 0
        phase = long ? .processing : .idle
        onClose?()
        return long
    }

    /// The transcript of a hold that `endHold()` moved to processing. Call `finish()` when the reaction is underway.
    func send(_ transcript: String) {
        guard phase == .processing else { return }
        onSend?(transcript)
    }

    /// Release in one step (tests and the debug script): a long enough hold goes to processing and sends the transcript (`onSend`); a short
    /// one cancels. Call `finish()` when the reaction is underway.
    @discardableResult
    func end(transcript: String) -> Outcome {
        guard phase == .listening else { return .cancelled }
        guard endHold() else { return .cancelled }
        onSend?(transcript)
        return .sent(transcript)
    }

    /// Abort (app backgrounded, mic error): nothing is sent.
    func cancel() {
        guard phase != .idle else { return }
        let wasListening = phase == .listening
        phase = .idle
        glowLevel = 0
        if wasListening { onClose?() }
    }

    /// Processing is done; ready for the next hold.
    func finish() {
        if phase == .processing { phase = .idle }
    }
}
