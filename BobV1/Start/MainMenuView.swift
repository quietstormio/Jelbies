//
//  MainMenuView.swift
//  The title screen on a cold launch: "Jelbies" over a real 3D room with the player's Jelbies (three of the four for a new player).
//  Continue (with a save), New game / Start (confirmed when it would wipe a save), Photos (once Photo mode registers its album), Settings.
//

import SwiftUI

struct MainMenuView: View {
    let flow: StartFlow
    private let hasSave = StartFlow.hasSave()
    @State private var confirmNew = false
    @State private var settingsOpen = false
    @State private var albumOpen = false
    @Environment(\.verticalSizeClass) private var vsc
    private var landscape: Bool { vsc == .compact }

    var body: some View {
        ZStack {
            ShowcaseStage(roster: hasSave ? JellyRoster.launchIDs() : [0, 1, 3])
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
        .sheet(isPresented: $settingsOpen) { MenuSettingsSheet { settingsOpen = false } }
        .fullScreenCover(isPresented: $albumOpen) {
            ZStack(alignment: .topTrailing) {
                StartFlow.albumView?() ?? AnyView(SK.cream)
                GameCircleButton(systemName: "xmark", label: "Close album") { albumOpen = false }.padding(.trailing, 16).padding(.top, 8)
            }
        }
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
        VStack(spacing: 4) {
            Text("Jelbies").font(.system(size: landscape ? 56 : 68, weight: .heavy, design: .rounded)).foregroundStyle(SK.cream)
                .shadow(color: SK.ink.opacity(0.65), radius: 5, y: 3)
                .accessibilityAddTraits(.isHeader)
            Text("baby jellies, come play").font(SK.font(17, .bold)).foregroundStyle(SK.cream).shadow(color: SK.ink.opacity(0.6), radius: 3, y: 1)
        }
    }

    private var buttons: some View {
        VStack(spacing: 10) {
            if hasSave {
                big("Continue", id: "menu-continue") { flow.continueGame() }
                HStack(spacing: 10) {
                    small("New game", "plus", id: "menu-new") { confirmNew = true }
                    if StartFlow.albumView != nil { small("Photos", "photo.on.rectangle", id: "menu-photos") { albumOpen = true } }
                    small("Settings", "gearshape", id: "menu-settings") { settingsOpen = true }
                }
            } else {
                big("Start", id: "menu-start") { flow.startOver() }
                HStack(spacing: 10) {
                    if StartFlow.albumView != nil { small("Photos", "photo.on.rectangle", id: "menu-photos") { albumOpen = true } }
                    small("Settings", "gearshape", id: "menu-settings") { settingsOpen = true }
                }
            }
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

    private func small(_ t: String, _ symbol: String, id: String, _ a: @escaping () -> Void) -> some View {
        Button { AudioHub.shared.uiTap(); a() } label: {
            HStack(spacing: 5) {
                Image(systemName: symbol).font(.system(size: 14, weight: .heavy))
                Text(t).font(SK.font(15, .heavy)).lineLimit(1).minimumScaleFactor(0.8)
            }
            .foregroundStyle(SK.ink).frame(maxWidth: .infinity, minHeight: 48)
            .background(Capsule().fill(Color.white.opacity(0.9)).shadow(color: SK.shadow.opacity(0.2), radius: 4, y: 2))
        }
        .buttonStyle(.plain).accessibilityIdentifier(id)
    }
}

/// Menu Settings: the sound panel and the Accessibility sheet.
private struct MenuSettingsSheet: View {
    var close: () -> Void
    @State private var a11yOpen = false
    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                SoundSettingsPanel(hub: AudioHub.shared) { close() }
                Button { a11yOpen = true } label: {
                    HStack { Image(systemName: "accessibility"); Text("Accessibility").font(SK.font(17, .heavy)); Spacer(); Image(systemName: "chevron.right") }
                        .foregroundStyle(SK.ink).padding(14).background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Color.white.opacity(0.85)))
                }
                .buttonStyle(.plain).accessibilityIdentifier("menu-accessibility")
            }
            .padding(16)
        }
        .background(SK.cream.ignoresSafeArea())
        .presentationDetents([.large])
        .sheet(isPresented: $a11yOpen) { AccessibilitySettingsView { a11yOpen = false }.presentationBackground(SK.cream) }
    }
}
