//
//  ContentView.swift
//  BobV1
//
//  Hosts the editorial Bob screen with the Metal stage.
//

import SwiftUI

struct ContentView: View {
    @State private var model = ContentView.makeModel()

    var body: some View {
        MelonScreen(model: model) {
            MelonStage(model: model)
        }
    }

    private static func makeModel() -> MelonModel {
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
