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
        // The logo fills ~96% of the swing frame's width.
        SpinLogo(still: still, active: visible)
            .frame(maxWidth: (landscape ? 420 : 340) / 0.96 * 1.04)
            .aspectRatio(620.0 / 307.0, contentMode: .fit)
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

/// Swing + jumps loop: 210 frames, 30 fps, 7 s seamless (menuswing_000...209). Decoded frames are ~760 KB each,
/// so only a small sliding window is kept in memory and decoded ahead on a background queue.
@MainActor private final class SwingFrames {
    static let shared = SwingFrames()
    static let count = 210
    static let fps: Double = 30
    private let ahead = 20, behind = 3
    private var cache: [Int: UIImage] = [:]
    private var pending = Set<Int>()

    nonisolated private static func decode(_ i: Int) -> UIImage? {
        let n = String(format: "menuswing_%03d", i)
        guard let u = Bundle.main.url(forResource: n, withExtension: "png") ?? Bundle.main.url(forResource: n, withExtension: "png", subdirectory: "MenuSwing"),
              let img = UIImage(contentsOfFile: u.path) else { return nil }
        return img.preparingForDisplay() ?? img
    }

    /// Returns frame i if decoded (else the nearest earlier decoded one) and prefetches the window ahead.
    func frame(_ i: Int) -> UIImage? {
        let want = (-behind...ahead).map { (i + $0 + Self.count) % Self.count }
        let keep = Set(want)
        for k in cache.keys where !keep.contains(k) { cache[k] = nil }
        for k in want where cache[k] == nil && !pending.contains(k) {
            pending.insert(k)
            Task.detached(priority: .userInitiated) {
                let img = SwingFrames.decode(k)
                await MainActor.run { [self] in
                    pending.remove(k)
                    if let img { cache[k] = img }
                }
            }
        }
        if let f = cache[i] { return f }
        for d in 1..<behind + 1 { if let f = cache[(i - d + Self.count) % Self.count] { return f } }
        return nil
    }
}

struct SpinLogo: View {
    let still: Bool
    let active: Bool
    @State private var start = Date()

    var body: some View {
        Group {
            if still || !active {
                Image(uiImage: SwingFrames.shared.frame(0) ?? UIImage()).resizable().scaledToFit()
                    .overlay { if SwingFrames.shared.frame(0) == nil { Image("JelbiesLogo").resizable().scaledToFit() } }
            } else {
                TimelineView(.animation(minimumInterval: 1.0 / SwingFrames.fps)) { tl in
                    let i = Int(tl.date.timeIntervalSince(start) * SwingFrames.fps) % SwingFrames.count
                    if let img = SwingFrames.shared.frame(i) {
                        Image(uiImage: img).resizable().scaledToFit()
                    } else {
                        Image("JelbiesLogo").resizable().scaledToFit()
                    }
                }
            }
        }
        .onChange(of: active) { _, _ in start = Date() }
    }
}
