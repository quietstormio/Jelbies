//
//  MainMenuView.swift
//  The title screen on a cold launch: the Jelbies logo over the real 3D room (no characters).
//  Two buttons: New Game (confirmed when it would wipe a save) and Continue (only with a save).
//

import SwiftUI

struct MainMenuView: View {
    let flow: StartFlow
    private let hasSave = StartFlow.hasSave()
    @State private var confirmNew = false
    @Environment(\.verticalSizeClass) private var vsc
    private var landscape: Bool { vsc == .compact }

    var body: some View {
        ZStack {
            ShowcaseStage(roster: hasSave ? Array(JellyRoster.launchIDs().prefix(1)) : [0], empty: true)
            scrim.ignoresSafeArea().allowsHitTesting(false)
            if landscape {
                HStack {
                    title.frame(maxWidth: .infinity)
                    buttons.frame(width: 320)
                }
                .padding(.horizontal, 28).padding(.vertical, 12)
            } else {
                VStack {
                    title.padding(.top, 40)
                    Spacer()
                    buttons.frame(maxWidth: 360).padding(.bottom, 28)
                }
                .padding(.horizontal, 24)
            }
        }
        .alert("Start over?", isPresented: $confirmNew) {
            Button("Start over", role: .destructive) { flow.startOver() }
            Button("Keep playing", role: .cancel) {}
        } message: { Text("Your Jelbies, Drops and items will be gone.") }
        .accessibilityElement(children: .contain).accessibilityIdentifier("main-menu")
    }

    /// Day / night tint over the room: a darker, bluer wash at night, a warm one at dusk and dawn, a light cream veil by day.
    private var scrim: some View {
        let phase = DayPhase.of(hour: DayClock.shared.hour)
        let top: Color, bottom: Color
        switch phase {
        case .night: top = Color(hex: 0x1E2440).opacity(0.62); bottom = Color(hex: 0x1E2440).opacity(0.72)
        case .evening: top = Color(hex: 0xF7B98B).opacity(0.45); bottom = Color(hex: 0x4D331F).opacity(0.45)
        case .morning: top = Color(hex: 0xFFE6C9).opacity(0.5); bottom = Color(hex: 0x4D331F).opacity(0.35)
        case .day: top = Color(hex: 0xCFE8F3).opacity(0.4); bottom = Color(hex: 0x4D331F).opacity(0.38)
        }
        return LinearGradient(colors: [top, .clear, .clear, bottom], startPoint: .top, endPoint: .bottom)
    }

    private var title: some View {
        Image("JelbiesLogo").resizable().scaledToFit()
            .frame(maxWidth: landscape ? 420 : 340)
            .shadow(color: SK.ink.opacity(0.25), radius: 6, y: 3)
            .accessibilityLabel("Jelbies").accessibilityAddTraits(.isHeader)
    }

    private var buttons: some View {
        VStack(spacing: 12) {
            if hasSave { big("Continue", id: "menu-continue") { flow.continueGame() } }
            if hasSave { big("New Game", id: "menu-new") { confirmNew = true } }
            else { big("New Game", id: "menu-start") { flow.startOver() } }
        }
    }

    private func big(_ t: String, id: String, _ a: @escaping () -> Void) -> some View {
        Button { AudioHub.shared.uiTap(); a() } label: {
            Text(t).font(SK.font(26, .black)).foregroundStyle(SK.ink).frame(maxWidth: .infinity, minHeight: 64)
                .background(Capsule().fill(SK.honey).shadow(color: SK.shadow.opacity(0.3), radius: 6, y: 3))
                .overlay(Capsule().strokeBorder(SK.honeyDeep, lineWidth: 2.5))
        }
        .buttonStyle(.plain).accessibilityIdentifier(id)
    }
}
