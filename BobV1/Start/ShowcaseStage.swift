//
//  ShowcaseStage.swift
//  A real 3D room with the given characters in it (the same MelonStage the game uses), for the main menu and the Adoption Center.
//  `empty` shows the room alone (the main menu). `focusFirst` brings the first one to the camera close-up ("come here"), so the Adoption Center shows one Jelbie large.
//

import SwiftUI

struct ShowcaseStage: View {
    let roster: [Int]
    var focusFirst = false
    /// The room with nobody in it (the main menu): the one Jelly the stage needs is drawn hidden.
    var empty = false
    /// False inside a framed window (the species picker); the main menu and the old full-screen use fill the screen.
    var fullScreen = true
    /// Transparent, no room: only the Jelbie (the species picker draws its own stage and backdrop).
    var cutout = false
    /// Called once the focused Jelbie has walked to the front (`focusFirst`), with the model (so the picker can ask for moves).
    var onReady: ((MelonModel) -> Void)?
    @State private var model: MelonModel?

    var body: some View {
        ZStack {
            if !cutout { Color.black }
            if let model { MelonStage(model: model) }
        }
        .modifier(SafeAreaIf(on: fullScreen))
        .allowsHitTesting(false)
        .onAppear { build() }
        .onDisappear { model?.paused = true }
        .accessibilityHidden(true)
    }

    private func build() {
        guard model == nil else { return }
        JellyRoster.current = roster                       // the stage reads its characters from the process-wide roster
        DayClock.shared.snapToNow()
        let m = GameScreen.makeGameModel(jellyCount: roster.count)
        m.care.touchPlay = m.touch
        m.hideJellies = empty
        m.cutout = cutout
        model = m
        guard focusFirst else { return }
        Task { @MainActor in
            for _ in 0..<40 where m.status != .live { try? await Task.sleep(nanoseconds: 100_000_000) }
            try? await Task.sleep(nanoseconds: 900_000_000)
            if !m.paused { m.care.comeHere(jelly: 0) }
            for _ in 0..<50 where !m.paused && !m.care.focusGroup.arrived.contains(0) { try? await Task.sleep(nanoseconds: 100_000_000) }
            try? await Task.sleep(nanoseconds: 500_000_000)
            if !m.paused { onReady?(m) }
        }
    }
}

private struct SafeAreaIf: ViewModifier {
    let on: Bool
    func body(content: Content) -> some View { if on { content.ignoresSafeArea() } else { content } }
}
