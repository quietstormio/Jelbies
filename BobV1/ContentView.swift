//
//  ContentView.swift
//  App root: the game screen by default; the studio (launch argument -MelonStudio 1) starts directly in MelonScreen.
//

import SwiftUI

struct ContentView: View {
    @State private var studioModel = ContentView.makeStudioModel()
    private let startInStudio = UserDefaults.standard.integer(forKey: "MelonStudio") != 0

    var body: some View {
        if startInStudio {
            MelonScreen(model: studioModel) {
                MelonStage(model: studioModel)
            }
        } else {
            GameScreen()
        }
    }

    /// The studio's model, with the DEBUG launch-argument overrides (-MelonPalette, -MelonMesh, ...).
    static func makeStudioModel() -> MelonModel {
        let m = MelonModel()
        #if DEBUG
        let d = UserDefaults.standard
        if let p = d.string(forKey: "MelonPalette"), let k = PaletteKey(rawValue: p) { m.palette = k }
        if d.integer(forKey: "MelonMesh") != 0 { m.showMesh = true }
        if d.integer(forKey: "MelonPaused") != 0 { m.paused = true }
        if d.integer(forKey: "MelonSlow") != 0 { m.slow = true }
        #endif
        return m
    }
}

#Preview {
    ContentView()
}
