//
//  TouchMode.swift
//  Shared by the focus-mode UI (worker A: dock, release button, camera) and the touch interactions (worker B: pointer modes, haptics).
//
//  Focus mode == the "Come here" command. Enter: Come here -> he walks to the front spot (`.approaching`) -> `.focused` (camera eased in,
//  dock visible, `mode` selects what a finger does). Exit: ONLY the "Let Bob go" release button -> `.leaving` (camera eases out, happy hop)
//  -> `.roaming`. There is no timeout and no swipe-out.
//
//  Readers (the stage's pointer handling, the haptics engine) read `care.focus` on the main thread:
//      focus.isFocused      touch play is live (the gesture decides: pet / pick up / cheeks, see TouchGesture.swift)
//      focus.phase          the full phase (haptics warm up on .approaching/.focused and stop on .roaming)
//

import Foundation
import Observation

enum FocusPhase: Equatable, Sendable {
    /// Free roaming (the normal game camera, care menu and gear visible).
    case roaming
    /// "Come here" was pressed: he walks to the front spot. The camera has not moved yet.
    case approaching
    /// He is at the front spot, the camera is (easing) in, the dock and the release button are shown.
    case focused
    /// "Let Bob go" was pressed: the camera eases out, he hops, then `.roaming`.
    case leaving
}

/// Focus-mode state. The brain/care flow in GameCare moves the phase; the stage reads `blend` for the camera each frame.
@MainActor
@Observable
final class BlobFocus {
    private(set) var phase: FocusPhase = .roaming

    /// Camera blend: 0 = the normal game camera, 1 = the close-up. A spring (see `step`), may overshoot a hair. Not observed (changes every frame).
    @ObservationIgnored private(set) var blend: Float = 0
    @ObservationIgnored private var vel: Float = 0
    @ObservationIgnored private var goal: Float = 0

    /// Spring tuning: ~0.7 s to settle, barely any overshoot.
    static let omega: Float = 9.0, zeta: Float = 0.9

    nonisolated deinit {}

    /// True while any part of the focus flow is on (the care menu and the gear hide; the release button shows).
    var isActive: Bool { phase != .roaming }
    /// Touch play is live: only when he is at the front spot and the release has not been pressed.
    var isFocused: Bool { phase == .focused }
    /// The camera is away from its home pose.
    var cameraActive: Bool { abs(blend) > 0.0005 || abs(goal) > 0 }
    /// The dock and the release button are on screen.
    var showsDock: Bool { phase == .focused }
    var showsRelease: Bool { phase == .focused }

    // MARK: transitions (GameCare drives these)

    func beginApproach() {
        guard phase == .roaming else { return }
        phase = .approaching
    }
    func arrive() {
        guard phase == .approaching else { return }
        phase = .focused; goal = 1
    }
    /// The only way out. From `.approaching` it just cancels the walk's focus (camera never moved).
    func release() {
        switch phase {
        case .focused: phase = .leaving; goal = 0
        case .approaching: phase = .roaming
        default: break
        }
    }
    /// Abandon focus without a camera move (the approach failed).
    func cancelApproach() { if phase == .approaching { phase = .roaming } }

    /// Advances the camera spring by `dt`; finishes `.leaving` once the camera is home. Returns true when focus has just ended.
    @discardableResult
    func step(dt: Float) -> Bool {
        let h = min(dt, 1.0 / 30)
        // semi-implicit Euler on x'' = w^2 (goal - x) - 2 z w x'
        let w = Self.omega
        vel += (w * w * (goal - blend) - 2 * Self.zeta * w * vel) * h
        blend += vel * h
        if phase == .leaving, abs(blend) < 0.004, abs(vel) < 0.05 {
            blend = 0; vel = 0; phase = .roaming
            return true
        }
        return false
    }

    /// Test/helper: jump straight to a phase with the camera settled.
    func force(_ p: FocusPhase) {
        phase = p
        goal = (p == .focused) ? 1 : 0
        blend = goal; vel = 0
    }
}
