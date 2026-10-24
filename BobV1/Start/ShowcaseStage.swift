//
//  ShowcaseStage.swift
//  A real 3D room with the given characters in it (the same MelonStage the game uses), for the main menu and the Adoption Center.
//  `focusFirst` brings the first one to the camera close-up ("come here"), so the Adoption Center shows one Jelbie large.
//

import SwiftUI

struct ShowcaseStage: View {
    let roster: [Int]
    var focusFirst = false
    @State private var model: MelonModel?

    var body: some View {
        ZStack {
            Color.black
            if let model { MelonStage(model: model) }
        }
        .ignoresSafeArea()
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
        model = m
        guard focusFirst else { return }
        Task { @MainActor in
            for _ in 0..<40 where m.status != .live { try? await Task.sleep(nanoseconds: 100_000_000) }
            try? await Task.sleep(nanoseconds: 900_000_000)
            if !m.paused { m.care.comeHere(jelly: 0) }
        }
    }
}
