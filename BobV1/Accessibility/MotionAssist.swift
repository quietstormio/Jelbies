//
//  MotionAssist.swift
//  Reduce Motion for the camera (round-1023 a11y). With `A11ySettings.shared.reduceMotion` on, a camera spring (the close-up's `BlobFocus.blend`)
//  does not glide: the screen fades to cream for ~0.12 s, the camera SNAPS to its goal under the veil, and the veil fades back out (a crossfade).
//  The Jelly's own wobble, walk, hops and flips are NOT touched (the jelly physics stays as designed).
//

import SwiftUI
import Observation

/// The cream veil a snap hides behind. Drawn by `MotionVeilView` (inside SelectionOverlay, above the stage).
@MainActor
@Observable
final class MotionVeil {
    static let shared = MotionVeil()
    private(set) var opacity: Double = 0
    @ObservationIgnored private var lastSet: Double = 0
    nonisolated deinit {}
    func set(_ v: Float) {
        let d = Double(v)
        if abs(d - lastSet) > 0.02 || d == 0 || d == 1 { lastSet = d; opacity = d }          // (no per-frame observation churn)
    }
    func reset() { lastSet = 0; opacity = 0 }
}

/// The pure state machine (tested): fade out, snap, fade in.
nonisolated struct CameraBlendAssist: Sendable {
    enum Stage: Equatable, Sendable { case idle, fadingOut, fadingIn }
    static let half: Float = 0.125
    private(set) var stage: Stage = .idle
    private(set) var veil: Float = 0
    private var t: Float = 0
    /// The veil reached full at least once (tests).
    private(set) var peaked = false

    /// Advances by `dt`. Returns true when the assist OWNS the blend this step (reduce motion on): the caller then skips its spring.
    /// `blend` / `vel` are set to `goal` / 0 at the moment the veil is opaque.
    mutating func step(blend: inout Float, vel: inout Float, goal: Float, dt: Float, reduce: Bool) -> Bool {
        guard reduce else {
            if stage != .idle { stage = .idle; veil = 0; t = 0 }
            return false
        }
        switch stage {
        case .idle:
            if abs(goal - blend) > 0.004 { stage = .fadingOut; t = 0; peaked = false }
            else { vel = 0 }
        case .fadingOut:
            t += dt
            veil = min(1, t / Self.half)
            if veil >= 1 { blend = goal; vel = 0; peaked = true; stage = .fadingIn; t = 0 }
        case .fadingIn:
            t += dt
            veil = max(0, 1 - t / Self.half)
            if veil <= 0 { veil = 0; stage = .idle }
        }
        return true
    }
}

/// The view: a cream sheet whose opacity is the veil. Never takes touches, never read by VoiceOver.
struct MotionVeilView: View {
    private let veil = MotionVeil.shared
    var body: some View {
        Color(red: 1.0, green: 0.97, blue: 0.94)
            .opacity(veil.opacity)
            .ignoresSafeArea()
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}
