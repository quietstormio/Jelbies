//
//  MelonModel.swift
//  Observable UI state shared by the SwiftUI screen and the Metal stage controller.
//

import SwiftUI
import Observation

enum MelonStatus: Equatable {
    case starting
    case live
    case paused
    case unavailable(String)
}

@MainActor
@Observable
final class MelonModel {
    /// Game screen (living room, fixed camera) instead of the studio. Fixed for the lifetime of the stage.
    var gameMode: Bool = false
    /// Care actions of the game screen (feed / water / call); ticked by the stage controller.
    let care = GameCare()
    /// Touch play of focus mode (pet / pick up / bounce / cheeks reactions, hearts, haptics). See BlobBrain+Touch.swift.
    let touch = TouchPlay()

    // Controls
    var palette: PaletteKey = .blush
    /// The individual shown on the stage (breed, colours, markings, size). Read once when the stage is created.
    var appearance: BlobAppearance = .berry
    /// 0...1
    var firmness: Double = 0.95
    /// 0...1
    var damping: Double = 0.45
    var paused: Bool = false {
        didSet {
            // Keep the chip in step with the Pause/Resume button.
            if paused, status == .live { status = .paused }
            else if !paused, status == .paused { status = .live }
        }
    }
    var slow: Bool = false
    var showMesh: Bool = false
    /// Bob hops from spot to spot on his own.
    var hopping: Bool = false

    // Status
    var status: MelonStatus = .starting
    /// Set by the integrator when no Metal device / pipeline is available. Also flips `status`.
    var metalUnavailableReason: String? = nil {
        didSet { if let r = metalUnavailableReason { status = .unavailable(r) } }
    }
    var isUnavailable: Bool {
        if case .unavailable = status { return true }
        return metalUnavailableReason != nil
    }

    // Readouts (written by the stage controller, a few times per second)
    var mass: Double = 0               // grams
    var volumePct: Double = 100        // % of rest volume
    var kineticMicroJ: Double = 0      // µJ

    // Mesh counts
    var particles: Int = 0
    var tets: Int = 0
    var seeds: Int = 0

    /// Mirrors `accessibilityReduceMotion`; set by MelonScreen.
    private(set) var reduceMotion: Bool = false

    // One-shot commands: the button handlers only increment; the stage controller
    // compares against the last value it saw in its frame loop.
    var nudgeTick: Int = 0
    var resetTick: Int = 0

    init() {
        // `-MelonPalette <rawValue>` launch argument (screenshots / tests).
        if let raw = UserDefaults.standard.string(forKey: "MelonPalette"), let key = PaletteKey(rawValue: raw) { palette = key }
    }

    // Not isolated: with default MainActor isolation Swift 6.2 makes deinit an isolated deinit (swift_task_deinitOnExecutor), which
    // aborts on the iOS 26.2 runtime ("pointer being freed was not allocated") when the last release is outside a task.
    nonisolated deinit {}

    func nudge() { nudgeTick &+= 1 }
    func reset() { resetTick &+= 1 }

    /// Called by the screen. Raises damping to 0.65 when reduce motion is on (only while it is still the default).
    func applyReduceMotion(_ on: Bool) {
        guard on != reduceMotion else { return }
        reduceMotion = on
        if on, damping == 0.45 { damping = 0.65 }
        else if !on, damping == 0.65 { damping = 0.45 }
    }
}
