//
//  ContentView.swift
//  App root: the game screen by default; the studio (launch argument -MelonStudio 1) starts directly in MelonScreen.
//

import SwiftUI

struct ContentView: View {
    @State private var flow = StartFlow.shared
    @State private var introOn = IntroGate.shouldShow() && UserDefaults.standard.integer(forKey: "SkipIntro") == 0          // (-SkipIntro 1: capture aid)
    @State private var logoOn = !IntroGate.shouldShow() && UserDefaults.standard.integer(forKey: "SkipIntro") == 0          // every later cold launch: the ~1 s logo moment
    #if DEBUG
    private let startInStudio = UserDefaults.standard.integer(forKey: "MelonStudio") != 0          // debug builds only (the studio is a developer tool)
    #endif

    var body: some View {
        #if DEBUG
        if startInStudio { StudioHost() } else { gameRoot }
        #else
        gameRoot
        #endif
    }

    private var gameRoot: some View {
        Group {
            ZStack {
                if introOn {          // the menu's room is not built until the intro is done (it would starve the video)
                    IntroView { LaunchTiming.mark("intro done"); LaunchGate.shared.introCoveredLaunch(); withAnimation(.easeInOut(duration: IntroClip.fadeSeconds)) { introOn = false } }.transition(.opacity).zIndex(1)
                } else if logoOn {
                    LogoMoment { LaunchTiming.mark("logo moment done"); LaunchGate.shared.introCoveredLaunch(); withAnimation(.easeInOut(duration: 0.3)) { logoOn = false } }.transition(.opacity).zIndex(1)
                } else { phaseView }
                if let w = flow.welcome, flow.phase == .game, JellyRoster.savedIDs().count < 2 { WelcomeBanner(name: w) { flow.welcome = nil } }          // (with others at home the arrival moment says it: GameCare+Newcomer.swift)
            }
            .onAppear { OrientationForce.apply() }
            .overlay { if !introOn && !logoOn { LaunchCurtain(gate: LaunchGate.shared).allowsHitTesting(LaunchGate.shared.visible) } }          // no curtain over the intro clip
            .animation(.easeOut(duration: 0.45), value: LaunchGate.shared.visible)
        }
    }

    @ViewBuilder private var phaseView: some View {
        switch flow.phase {
        case .menu: MainMenuView(flow: flow)
        case .wiping: Color(hex: 0x070A2B).ignoresSafeArea()          // the night sky's colour: the opening starts from it (cream flashed for half a second between the menu and the night)
        case .opening:
            OpeningStoryView(replay: flow.replaying) { withAnimation(.easeInOut(duration: 1.0)) { flow.finishOpening() } }.transition(.opacity)
        case .adopt(let mode):
            AdoptionCenter(mode: mode, done: { flow.bringHome(character: $0, name: $1) }, cancel: { mode == .first ? flow.backToMenu() : flow.cancelAdoption() })
                .transition(.opacity)
        case .firstDay(let c, let n, let replay):
            FirstDayHomeView(character: c, name: n, replay: replay) { withAnimation(.easeInOut(duration: 0.8)) { flow.finishFirstDay() } }.transition(.opacity)
        case .game: GameHost(session: flow.session)
        }
    }

}

#if DEBUG
/// The developer studio. Its model is built here, only when the studio is shown (it used to be built at every launch, and built a second GameCare that consumed the away time).
struct StudioHost: View {
    @State private var model = StudioHost.makeModel()
    var body: some View {
        MelonScreen(model: model) { MelonStage(model: model) }
    }

    /// The studio's model, with the launch-argument overrides (-MelonPalette, -MelonMesh, ...).
    static func makeModel() -> MelonModel {
        let m = MelonModel()
        let d = UserDefaults.standard
        if let p = d.string(forKey: "MelonPalette"), let k = PaletteKey(rawValue: p) { m.palette = k }
        if d.integer(forKey: "MelonMesh") != 0 { m.showMesh = true }
        if d.integer(forKey: "MelonPaused") != 0 { m.paused = true }
        if d.integer(forKey: "MelonSlow") != 0 { m.slow = true }
        return m
    }
}
#endif

#Preview {
    ContentView()
}
