//
//  SettingsScreen.swift
//  The gear's full Settings screen, in the themed title-screen style: Appearance (theme colour with a live mini title screen), Sound,
//  Accessibility, Voice and listening, Game (main menu, watch the opening, reset save) and About. One column in portrait, two in landscape.
//  Everything reuses what exists: AudioHub.settings, EarsSettingsRow, AccessibilitySettingsView, StartFlow.
//

import SwiftUI

struct SettingsScreen: View {
    #if DEBUG
    var openStudio: (() -> Void)? = nil          // developer studio: debug builds only
    #endif
    var mainMenu: () -> Void
    var resetSave: () -> Void
    var openPhoto: () -> Void = {}
    var watchOpening: () -> Void = {}
    var openShop: () -> Void = {}
    var close: () -> Void

    @Bindable private var hub = AudioHub.shared
    private var theme = ThemeStore.shared
    @State private var showA11y = false
    @State private var matchIcon = AppIconSwitcher.enabled
    @State private var confirmReset = false
    @State private var showPrivacy = false
    @State private var showSupport = false
    @State private var followReal = DayClock.shared.followReal
    @AppStorage(HapticSettings.key) private var hapticsOn = true
    @Environment(\.verticalSizeClass) private var vsc
    private var landscape: Bool { vsc == .compact }
    private let ink = CloudTheme.ink

    init(mainMenu: @escaping () -> Void, resetSave: @escaping () -> Void, openPhoto: @escaping () -> Void = {}, watchOpening: @escaping () -> Void = {}, openShop: @escaping () -> Void = {}, close: @escaping () -> Void) {
        self.mainMenu = mainMenu; self.resetSave = resetSave; self.openPhoto = openPhoto; self.watchOpening = watchOpening; self.openShop = openShop; self.close = close
    }

    var body: some View {
        let pal = theme.palette
        ZStack {
            pal.bg.ignoresSafeArea()
            VStack(spacing: 0) {
                header(pal)
                ScrollView {
                    if landscape {
                        HStack(alignment: .top, spacing: 16) {
                            VStack(spacing: 16) { appearance(pal); sound }.frame(maxWidth: .infinity)
                            VStack(spacing: 16) { accessibility; voice; game; about }.frame(maxWidth: .infinity)
                        }
                        .padding(16)
                    } else {
                        VStack(spacing: 16) { appearance(pal); sound; accessibility; voice; game; about }
                            .padding(16)
                    }
                }
            }
            if confirmReset { resetCard }
        }
        .animation(.easeInOut(duration: 0.4), value: theme.selection)
        .animation(.easeInOut(duration: 0.2), value: confirmReset)
        .sheet(isPresented: $showA11y) {
            AccessibilitySettingsView { showA11y = false }.presentationBackground(SK.cream)
        }
        .sheet(isPresented: $showPrivacy) { PrivacyPage { showPrivacy = false }.presentationBackground(SK.cream) }
        .sheet(isPresented: $showSupport) { SupportPage { showSupport = false }.presentationBackground(SK.cream) }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("settings-screen")
        .accessibilityAction(.escape) { close() }
    }

    // MARK: pieces

    private func header(_ pal: ThemePalette) -> some View {
        HStack {
            Text("Settings").font(CloudTheme.font(28, .heavy)).foregroundStyle(ink)
                .padding(.horizontal, 18).frame(minHeight: 44)
                .background(Capsule().fill(Color.white).shadow(color: pal.lip, radius: 0, y: 3))          // readable on every theme colour (white on the pastel themes was not)
                .accessibilityAddTraits(.isHeader)
            Spacer()
            Button { AudioHub.shared.uiTap(); close() } label: {
                Text("Done").font(CloudTheme.font(18, .heavy)).foregroundStyle(pal.continueText)
                    .padding(.horizontal, 20).frame(minHeight: 44)
                    .background(Capsule().fill(Color.white).shadow(color: pal.lip, radius: 0, y: 4))
            }
            .accessibilityIdentifier("settings-done")
        }
        .padding(.horizontal, 20).padding(.vertical, 10)
    }

    private func card<C: View>(_ title: String, _ symbol: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label { Text(title).font(CloudTheme.font(20, .bold)) } icon: { Image(systemName: symbol) }
                .foregroundStyle(ink).accessibilityAddTraits(.isHeader)
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cloudCard(radius: 26)
    }

    private func appearance(_ pal: ThemePalette) -> some View {
        card("Appearance", "paintpalette") {
            HStack(alignment: .top, spacing: 16) {
                ThemeMiniPreview(palette: pal).frame(width: 96, height: 210).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 10) {
                        Text("Theme colour").font(CloudTheme.font(15, .semibold)).foregroundStyle(ink.opacity(0.8))
                        Spacer(minLength: 4)
                        ThemeIconView(preset: theme.currentPreset).frame(width: 56, height: 56)
                            .shadow(color: .black.opacity(0.18), radius: 3, y: 2)
                            .accessibilityLabel("App icon preview")
                    }
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 52), spacing: 10)], spacing: 10) {
                        ForEach(ThemePreset.allCases) { p in swatch(p) }
                    }
                    Toggle(isOn: $matchIcon) {
                        Text("Match app icon to theme").font(CloudTheme.font(15, .semibold)).foregroundStyle(ink)
                    }
                    .tint(pal.newGame)
                    .onChange(of: matchIcon) { _, on in AppIconSwitcher.enabled = on; if on { AppIconSwitcher.apply(theme.currentPreset) } }
                    .accessibilityIdentifier("theme-match-icon")
                }
            }
        }
    }

    private func swatch(_ p: ThemePreset) -> some View {
        let on = theme.preset == p
        return Button { AudioHub.shared.uiTap(); theme.choose(p) } label: {
            Circle().fill(Color(hex: p.hex)).frame(width: 44, height: 44)
                .overlay(Circle().strokeBorder(Color.white, lineWidth: 3))
                .overlay(Circle().strokeBorder(ink, lineWidth: on ? 3 : 0).padding(-3))
                .overlay { if on { Image(systemName: "checkmark").font(.system(size: 16, weight: .black)).foregroundStyle(.white).shadow(radius: 1) } }
                .frame(minWidth: 52, minHeight: 52)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(p.title)
        .accessibilityAddTraits(on ? [.isSelected] : [])
        .accessibilityIdentifier("theme-\(p.rawValue)")
    }

    private var sound: some View {
        card("Sound", "speaker.wave.2.fill") {
            slider("Music", on: $hub.settings.musicOn, volume: $hub.settings.musicVolume, id: "music")
            HStack {
                Label(hub.nowPlaying.line, systemImage: "music.note").font(CloudTheme.font(14, .medium)).foregroundStyle(ink.opacity(0.8)).lineLimit(2)
                Spacer(minLength: 8)
                Button { hub.skipTrack() } label: {
                    Label("Skip", systemImage: "forward.fill").font(CloudTheme.font(14, .bold)).foregroundStyle(.white)
                        .padding(.horizontal, 12).frame(minHeight: 36).background(Capsule().fill(CloudTheme.deepJelly))
                }
                .buttonStyle(.plain).disabled(!hub.nowPlaying.canSkip).opacity(hub.nowPlaying.canSkip ? 1 : 0.4)
                .accessibilityLabel("Skip song").accessibilityIdentifier("settings-skip")
            }
            slider("Sound effects", on: $hub.settings.sfxOn, volume: $hub.settings.sfxVolume, id: "sfx")
            Text("Jelbie voices follow the sound effects volume.").font(CloudTheme.font(12, .regular)).foregroundStyle(ink.opacity(0.65))
            Toggle("Haptics", isOn: $hapticsOn)
                .font(CloudTheme.font(16, .semibold)).foregroundStyle(ink).tint(theme.controlAccent).frame(minHeight: 44)
                .accessibilityIdentifier("settings-haptics-toggle")
        }
    }

    private func slider(_ title: String, on: Binding<Bool>, volume: Binding<Float>, id: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Toggle(title, isOn: on).font(CloudTheme.font(16, .semibold)).foregroundStyle(ink).tint(theme.controlAccent)
                .accessibilityIdentifier("settings-\(id)-toggle")
            Slider(value: volume, in: 0...1).tint(theme.controlAccent).disabled(!on.wrappedValue)
                .accessibilityLabel("\(title) volume").accessibilityIdentifier("settings-\(id)-volume")
        }
    }

    private var accessibility: some View {
        card("Accessibility", "accessibility") {
            Button { AudioHub.shared.uiTap(); showA11y = true } label: {
                HStack { Text("Accessibility settings"); Spacer(); Image(systemName: "chevron.right") }
                    .font(CloudTheme.font(16, .semibold)).foregroundStyle(ink).frame(minHeight: 44)
            }
            .buttonStyle(.plain).accessibilityIdentifier("settings-accessibility")
        }
    }

    private var voice: some View {
        card("Voice and listening", "ear.fill") {
            EarsSettingsRow(ears: .shared, tight: false, goShop: openShop)
        }
    }

    private var game: some View {
        card("Game", "gamecontroller") {
            actionRow("Photo mode", "camera", id: "photo-button", action: openPhoto)
            actionRow("Main menu", "house", id: "settings-main-menu", action: mainMenu)
            actionRow("Watch the opening", "sparkles", id: "settings-watch-opening", action: watchOpening)
            #if DEBUG
            if let openStudio { actionRow("Studio", "slider.horizontal.3", id: "settings-studio", action: openStudio) }
            #endif
            Toggle("Follow real clock", isOn: Binding(get: { followReal }, set: { followReal = $0; DayClock.shared.setFollowReal($0) }))
                .font(CloudTheme.font(16, .semibold)).foregroundStyle(ink).tint(theme.controlAccent).frame(minHeight: 44)
                .accessibilityIdentifier("settings-follow-real-clock")
            Text(followReal ? "Day and night follow your phone's clock." : "One game hour is one real minute. Day \(DayClock.shared.day) so far. You can also skip the night with the moon button.")
                .font(CloudTheme.font(13, .medium)).foregroundStyle(ink.opacity(0.75)).fixedSize(horizontal: false, vertical: true)
            Button { AudioHub.shared.uiTap(); confirmReset = true } label: {
                Label("Reset save", systemImage: "trash").font(CloudTheme.font(16, .bold)).foregroundStyle(Color(hex: 0xB3261E))
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .background(Capsule().strokeBorder(Color(hex: 0xB3261E), lineWidth: 2))
            }
            .buttonStyle(.plain).accessibilityIdentifier("settings-reset")
        }
    }

    private func actionRow(_ title: String, _ symbol: String, id: String, action: @escaping () -> Void) -> some View {
        Button { AudioHub.shared.uiTap(); action() } label: {
            HStack { Image(systemName: symbol); Text(title); Spacer(); Image(systemName: "chevron.right") }
                .font(CloudTheme.font(16, .semibold)).foregroundStyle(ink).frame(minHeight: 44)
        }
        .buttonStyle(.plain).accessibilityIdentifier(id)
    }

    private var about: some View {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return card("About", "info.circle") {
            Text("Jelbies").font(CloudTheme.font(18, .heavy)).foregroundStyle(ink)
            Text("Version \(v) (\(b))").font(CloudTheme.font(14, .medium)).foregroundStyle(ink.opacity(0.75))
            if DayClock.shared.showsDay { Text("Day \(DayClock.shared.day)").font(CloudTheme.font(14, .medium)).foregroundStyle(ink.opacity(0.75)) }
            actionRow("Privacy", "hand.raised", id: "settings-privacy") { showPrivacy = true }
            actionRow("Help & Support", "questionmark.circle", id: "settings-support") { showSupport = true }
            Text("Made with love.").font(CloudTheme.font(14, .medium)).foregroundStyle(ink.opacity(0.75))
            Text("Everything stays on this phone. No accounts, no internet.").font(CloudTheme.font(14, .medium)).foregroundStyle(ink.opacity(0.75))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var resetCard: some View {
        ZStack {
            Color.black.opacity(0.35).ignoresSafeArea().onTapGesture { confirmReset = false }
            ScrollView {
            VStack(spacing: 12) {
                Text("Reset your save?").font(CloudTheme.font(24, .bold)).foregroundStyle(ink).accessibilityAddTraits(.isHeader)
                Text("Your Jelbies, JellyCoins and items will be gone for good. Press and hold the red button to confirm.")
                    .font(CloudTheme.font(15, .medium)).foregroundStyle(ink.opacity(0.85)).multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                HoldToConfirm(title: "Hold to reset") { confirmReset = false; resetSave() }
                Button("Keep my save") { confirmReset = false }
                    .buttonStyle(JellyButtonStyle(.primary, size: 18, minHeight: 48)).accessibilityIdentifier("settings-reset-cancel")
            }
            .padding(20).frame(maxWidth: 340).cloudCard(radius: 30).padding(24)
            .accessibilityElement(children: .contain).accessibilityAddTraits(.isModal)
            .frame(maxWidth: .infinity)
            }
            .scrollBounceBehavior(.basedOnSize)          // large text / landscape: the card scrolls instead of clipping its buttons
        }
        .transition(.opacity)
    }
}

#if DEBUG
extension SettingsScreen {
    /// Debug builds only: adds the developer Studio row.
    func developerStudio(_ open: @escaping () -> Void) -> SettingsScreen { var c = self; c.openStudio = open; return c }
}
#endif

/// A small live picture of the title screen in the given palette.
struct ThemeMiniPreview: View {
    let palette: ThemePalette
    var body: some View {
        let k: CGFloat = 96 / 440
        ZStack {
            TitleBackdrop(still: true, size: CGSize(width: 440, height: 956), landscape: false, palette: palette)
                .frame(width: 440, height: 956)
                .scaleEffect(k, anchor: .topLeading)
                .frame(width: 96, height: 956 * k, alignment: .topLeading)
            Image("JelbiesLogo").resizable().scaledToFit().themedLogo().frame(width: 364 * k)
                .shadow(color: palette.shadow, radius: 0, y: 7 * k)
                .position(x: 48, y: 250 * k)
            VStack(spacing: 6 * k) {
                Capsule().fill(Color.white).frame(width: 300 * k, height: 74 * k).shadow(color: palette.lip, radius: 0, y: 8 * k)
                Capsule().fill(palette.newGame).overlay(Capsule().strokeBorder(Color.white.opacity(0.7), lineWidth: 1))
                    .frame(width: 300 * k, height: 62 * k).shadow(color: palette.lip, radius: 0, y: 6 * k)
            }
            .position(x: 48, y: 500 * k)
        }
        .frame(width: 96, height: 956 * k)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(CloudTheme.jelly, lineWidth: 2))
    }
}
