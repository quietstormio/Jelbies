import SwiftUI

struct GameRootView<Stage: View>: View {
    var store: GameStore
    var events: CareEvents
    @ViewBuilder var stage: () -> Stage

    @Environment(\.scenePhase) private var scenePhase
    /// Keeps the kennel up through the "Welcome home" moment of the very first adoption.
    @State private var onboarding: Bool

    init(store: GameStore, events: CareEvents = CareEvents(), @ViewBuilder stage: @escaping () -> Stage) {
        self.store = store
        self.events = events
        self.stage = stage
        _onboarding = State(initialValue: store.blobs.isEmpty)
    }

    var body: some View {
        ZStack {
            if store.blobs.isEmpty || onboarding {
                KennelView(store: store, persist: save, onClose: { onboarding = false }, dismissible: false)
                    .transition(.opacity)
            } else {
                HomeView(store: store, events: events, persist: save, stage: stage)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.4), value: onboarding)
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active: store.applyElapsed(now: Date())
            case .inactive, .background: save()
            @unknown default: break
            }
        }
        .onAppear { store.applyElapsed(now: Date()) }
    }

    private func save() { try? store.persist() }
}

#Preview("Root, empty") {
    GameRootView(store: PreviewSupport.store(blobs: 0)) { HUDPlaceholderStage() }
}
#Preview("Root, home") {
    let s = PreviewSupport.store(blobs: 3)
    return GameRootView(store: s) { HUDPlaceholderStage(store: s) }
}
