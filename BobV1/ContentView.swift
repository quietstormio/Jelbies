//
//  ContentView.swift
//  App root: the game screen by default; the studio (launch argument -MelonStudio 1) starts directly in MelonScreen.
//

import SwiftUI

struct ContentView: View {
    @State private var flow = StartFlow.shared
    @State private var studioModel = ContentView.makeStudioModel()
    private let startInStudio = UserDefaults.standard.integer(forKey: "MelonStudio") != 0

    var body: some View {
        if startInStudio {
            MelonScreen(model: studioModel) {
                MelonStage(model: studioModel)
            }
        } else {
            ZStack {
                switch flow.phase {
                case .menu: MainMenuView(flow: flow)
                case .wiping: SK.cream.ignoresSafeArea()
                case .adopt(let mode):
                    AdoptionCenter(mode: mode, done: { flow.bringHome(character: $0, name: $1) }, cancel: { flow.cancelAdoption() })
                case .game: GameHost(session: flow.session)
                }
                if let w = flow.welcome, flow.phase == .game { WelcomeBanner(name: w) { flow.welcome = nil } }
            }
            .onAppear { OrientationForce.apply() }
            .overlay { LaunchCurtain(gate: LaunchGate.shared).allowsHitTesting(LaunchGate.shared.visible) }
            .animation(.easeOut(duration: 0.45), value: LaunchGate.shared.visible)
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
