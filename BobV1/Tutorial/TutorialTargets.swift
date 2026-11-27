//
//  TutorialTargets.swift
//  Where the controls are. A control marks itself with `.tutorialTarget("care")`; it reports its frame (window points) and its shape, and takes it back when it goes away. The tutorial's own window
//  reads these, so it works over sheets and in any orientation (nothing is hard-coded, nothing is read from the game's layout code).
//

import SwiftUI
import Observation

@MainActor @Observable
final class TutorialTargets {
    static let shared = TutorialTargets()
    private(set) var spots: [String: CoachSpot] = [:]
    /// The Jelmiko himself (he is a 3D body, not a view): the overlay asks for his circle in its own size.
    @ObservationIgnored var jelmiko: ((CGSize) -> CGRect?)?

    func set(_ id: String, rect: CGRect, shape: CoachShape) {
        guard rect.width > 1, rect.height > 1 else { return }
        let s = CoachSpot(rect: rect, shape: shape)
        if spots[id] != s { spots[id] = s }
    }
    func clear(_ id: String) { if spots[id] != nil { spots[id] = nil } }
    var ids: Set<String> { Set(spots.keys) }

    /// The circle the ring draws round the Jelmiko: about 42% of the short side, kept on screen (he wanders).
    func jelmikoSpot(size: CGSize) -> CoachSpot? {
        guard let p = jelmiko?(size) else { return nil }
        return CoachSpot(rect: p, shape: .capsule)
    }

    func spot(for step: TutorialStep, size: CGSize) -> CoachSpot? {
        guard let t = step.target else { return nil }
        if t == "jelmiko" { return jelmikoSpot(size: size) }
        guard var s = spots[t] else { return nil }
        s.shape = step.shape == .capsule ? s.shape : step.shape
        return s
    }
}

extension View {
    /// This control is something the tutorial can point at. `shape` is its outline (circle / capsule: `.capsule`; a rounded box: `.rounded(radius)`), so the ring can be concentric with it.
    func tutorialTarget(_ id: String, shape: CoachShape = .capsule) -> some View {
        onGeometryChange(for: CGRect.self, of: { $0.frame(in: .global) }, action: { r in TutorialTargets.shared.set(id, rect: r, shape: shape) })
            .onDisappear { TutorialTargets.shared.clear(id) }
    }
}

extension View {
    /// Same, for a control that is only a target some of the time (`nil` = not one).
    @ViewBuilder func tutorialTarget(_ id: String?, shape: CoachShape = .capsule) -> some View {
        if let id { tutorialTarget(id, shape: shape) } else { self }
    }
}

/// Two facts only the game screen's own state knows (the care menu and the Go out screens are `@State` there); it writes them here.
@MainActor @Observable
final class TutorialSignals {
    static let shared = TutorialSignals()
    var menuOpen = false
    var townOpen = false
}
