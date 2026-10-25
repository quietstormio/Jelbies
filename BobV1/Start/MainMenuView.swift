//
//  MainMenuView.swift
//  The title screen (Cloud Jelly): white sky with slowly drifting Mist bubbles, the Jelbies logo bobbing in the top third, and two jelly buttons.
//  Continue (only with a save) is the blue primary; New Game is the white secondary, confirmed on a white rimmed card when it would wipe a save.
//

import SwiftUI

struct MainMenuView: View {
    let flow: StartFlow
    private let hasSave = StartFlow.hasSave()
    @State private var confirmNew = false
    @State private var bob = false
    @State private var visible = true
    @Environment(\.verticalSizeClass) private var vsc
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var landscape: Bool { vsc == .compact }
    private var still: Bool { reduceMotion || A11ySettings.shared.reduceMotion }

    var body: some View {
        ZStack {
            CloudSky()
            if landscape {
                HStack {
                    title.frame(maxWidth: .infinity)
                    buttons.frame(width: 320)
                }
                .padding(.horizontal, 28).padding(.vertical, 12)
            } else {
                VStack {
                    title.padding(.top, 60)
                    Spacer()
                    buttons.frame(maxWidth: 340).padding(.bottom, 36)
                }
                .padding(.horizontal, 24)
            }
            if confirmNew { confirmCard.transition(.opacity) }
        }
        .animation(.easeInOut(duration: 0.2), value: confirmNew)
        .onAppear { bob = true; visible = true }
        .onDisappear { visible = false }
        .accessibilityElement(children: .contain).accessibilityIdentifier("main-menu")
    }

    private var title: some View {
        // The frame is ~16% wider than the logo inside it (logo = 86% of the frame width).
        SpinLogo(still: still, active: visible)
            .frame(maxWidth: (landscape ? 420 : 340) / 0.86 * 1.04)
            .aspectRatio(675.0 / 517.0, contentMode: .fit)
            .offset(y: bob && !still ? -6 : 0)
            .animation(still ? nil : .easeInOut(duration: 1.6).repeatForever(autoreverses: true), value: bob)
            .accessibilityElement().accessibilityLabel("Jelbies").accessibilityAddTraits(.isHeader)
    }

    private var buttons: some View {
        VStack(spacing: 16) {
            if hasSave {
                Button("Continue") { AudioHub.shared.uiTap(); flow.continueGame() }
                    .buttonStyle(JellyButtonStyle(.primary)).accessibilityIdentifier("menu-continue")
                Button("New Game") { AudioHub.shared.uiTap(); confirmNew = true }
                    .buttonStyle(JellyButtonStyle(.secondary)).accessibilityIdentifier("menu-new")
            } else {
                Button("New Game") { AudioHub.shared.uiTap(); flow.startOver() }
                    .buttonStyle(JellyButtonStyle(.primary)).accessibilityIdentifier("menu-start")
            }
        }
    }

    /// "Start over?" as the white card with the thick Jelly rim, over a pale veil.
    private var confirmCard: some View {
        ZStack {
            Color.white.opacity(0.6).ignoresSafeArea().onTapGesture { confirmNew = false }
            VStack(spacing: 12) {
                Text("Start over?").font(CloudTheme.font(26, .bold)).foregroundStyle(CloudTheme.ink).accessibilityAddTraits(.isHeader)
                Text("Your Jelbies, Drops and items will be gone.").font(CloudTheme.font(16, .medium)).foregroundStyle(CloudTheme.ink.opacity(0.8))
                    .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                Button("Keep playing") { confirmNew = false }
                    .buttonStyle(JellyButtonStyle(.primary, size: 20, minHeight: 48)).accessibilityIdentifier("menu-keep")
                Button("Start over") { confirmNew = false; flow.startOver() }
                    .buttonStyle(JellyButtonStyle(.secondary, size: 18, minHeight: 44)).accessibilityIdentifier("menu-start-over")
            }
            .padding(.horizontal, 22).padding(.vertical, 20)
            .frame(maxWidth: 340)
            .cloudCard(radius: 30)
            .padding(24)
            .accessibilityElement(children: .contain)
            .accessibilityAddTraits(.isModal)
        }
    }
}

/// Cached frames of the 2 s, 30 fps logo spin loop (menuspin_00...59), decoded once off the main thread.
@MainActor private enum SpinFrames {
    static var frames: [UIImage] = []
    static var loading = false
    static func load() async {
        guard frames.isEmpty, !loading else { return }
        loading = true
        let loaded: [UIImage] = await Task.detached(priority: .userInitiated) {
            (0..<60).compactMap { i -> UIImage? in
                let n = String(format: "menuspin_%02d", i)
                guard let u = Bundle.main.url(forResource: n, withExtension: "png") ?? Bundle.main.url(forResource: n, withExtension: "png", subdirectory: "MenuSpin"),
                      let img = UIImage(contentsOfFile: u.path) else { return nil }
                return img.preparingForDisplay() ?? img
            }
        }.value
        frames = loaded
        loading = false
    }
}

struct SpinLogo: View {
    let still: Bool
    let active: Bool
    @State private var ready = SpinFrames.frames.count == 60

    var body: some View {
        Group {
            if ready && !SpinFrames.frames.isEmpty {
                TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: still || !active)) { tl in
                    let n = SpinFrames.frames.count
                    let i = still ? 0 : Int(tl.date.timeIntervalSinceReferenceDate * 30) % n
                    Image(uiImage: SpinFrames.frames[i]).resizable().scaledToFit()
                }
            } else {
                Image("JelbiesLogo").resizable().scaledToFit().scaleEffect(0.86)
            }
        }
        .task { await SpinFrames.load(); ready = SpinFrames.frames.count == 60 }
    }
}
