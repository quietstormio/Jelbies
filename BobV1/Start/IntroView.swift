//
//  IntroView.swift
//  The first-launch intro (Cloud Jelly): one finished white, square clip (logo, squish, sparkles and its own sound) plays once it is ready,
//  holds its last frame, "Tap to start" fades in, and a tap (or 2 s) fades through white to the menu. A tap during the clip jumps to the last frame.
//  Shown before the main menu until UserDefaults "IntroSeen.v1" is set; launch argument -Intro 1 forces it (for captures).
//  Swapping the clip: replace the file in Start/Resources (or change `IntroClip.resource`).
//

import SwiftUI
import AVFoundation

enum IntroClip {
    /// The clip recoloured for the current theme (one pre-rendered file per preset).
    @MainActor static var resource: String { ThemeStore.shared.currentPreset.introResource }
    static let fileExtension = "mp4"
    /// Seconds after the clip ends before it moves on by itself.
    static let autoAdvance: Double = 2.0
}

enum IntroGate {
    static let seenKey = "IntroSeen.v1"
    static let background = Color.white
    static func shouldShow(_ d: UserDefaults = .standard) -> Bool {
        d.integer(forKey: "Intro") != 0 || !d.bool(forKey: seenKey)
    }
    static func markSeen(_ d: UserDefaults = .standard) { d.set(true, forKey: seenKey) }
}

struct IntroView: View {
    var done: () -> Void
    @State private var player: AVPlayer?
    @State private var ready = false
    @State private var settled = false
    @State private var leaving = false
    @State private var finished = false
    @State private var volume: Float = 0
    @State private var statusObserver: NSKeyValueObservation?
    @State private var endObserver: NSObjectProtocol?
    @Environment(\.accessibilityReduceMotion) private var reduceMotionEnv
    private var still: Bool { reduceMotionEnv || A11ySettings.shared.reduceMotion }

    var body: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            ZStack {
                IntroGate.background
                if let player {
                    IntroPlayerView(player: player).frame(width: side, height: side)
                        .opacity(ready ? 1 : 0)
                }
                if A11ySettings.shared.captions, !settled, ready {
                    Text("Piano and strings, sparkles and pops")          // caption for the intro clip's sound
                        .font(CloudTheme.font(16, .semibold)).foregroundStyle(CloudTheme.ink)
                        .padding(.horizontal, 14).padding(.vertical, 6)
                        .background(Capsule().fill(CloudTheme.mist))
                        .frame(maxHeight: .infinity, alignment: .top).padding(.top, max(48, geo.size.height * 0.08))
                        .accessibilityHidden(true)
                }
                Text("Tap to start").font(CloudTheme.font(18, .semibold)).foregroundStyle(CloudTheme.caption)
                    .frame(maxHeight: .infinity, alignment: .bottom).padding(.bottom, max(28, geo.size.height * 0.08))
                    .opacity(settled ? 1 : 0)
                    .animation(.easeOut(duration: 0.4), value: settled)
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .opacity(leaving ? 0 : 1)
            .animation(.easeInOut(duration: 0.4), value: leaving)
        }
        .background(IntroGate.background)
        .ignoresSafeArea()
        .contentShape(Rectangle())
        .onTapGesture { tapped() }
        .onAppear { start(); A11yAnnounce.say("Jelbies. Double tap to start.", priority: .low) }
        .onDisappear { teardown() }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Jelbies. Intro animation: the logo squishes and sparkles with a soft chime.")
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("Starts the game")
        .accessibilityIdentifier("intro")
    }

    // MARK: flow

    private func start() {
        guard player == nil else { return }
        guard let url = Bundle.main.url(forResource: IntroClip.resource, withExtension: IntroClip.fileExtension) else { settle(); return }
        let item = AVPlayerItem(url: url)
        let p = AVPlayer(playerItem: item)
        p.actionAtItemEnd = .pause
        volume = AudioHub.shared.introVideoVolume()
        p.volume = volume
        p.isMuted = volume <= 0
        player = p
        endObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main) { _ in
            Task { @MainActor in settle() }
        }
        statusObserver = item.observe(\.status, options: [.initial, .new]) { it, _ in
            guard it.status == .readyToPlay else { return }
            Task { @MainActor in begin() }
        }
    }

    /// The first frame is decoded: show the clip and play it (Reduce Motion shows its last frame instead).
    private func begin() {
        guard let p = player, !ready, !finished else { return }
        if still {
            let end = p.currentItem?.duration ?? .zero
            p.seek(to: end, toleranceBefore: .zero, toleranceAfter: .zero) { _ in
                Task { @MainActor in ready = true; settle() }
            }
        } else {
            ready = true
            p.play()
        }
    }

    private func tapped() {
        if settled { finish(); return }
        guard let p = player, ready else { settle(); return }
        fadeOutAudio(p)
        p.pause()
        let end = p.currentItem?.duration ?? .zero
        p.seek(to: end, toleranceBefore: .zero, toleranceAfter: .zero) { _ in
            Task { @MainActor in settle() }
        }
    }

    /// Ramps the clip's audio to silence over 0.25 s.
    private func fadeOutAudio(_ p: AVPlayer) {
        let start = p.volume
        let steps = 5
        for i in 1...steps {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25 * Double(i) / Double(steps)) { p.volume = start * Float(steps - i) / Float(steps) }
        }
    }

    /// The clip is on its last frame: "Tap to start" fades in and the auto-advance starts.
    private func settle() {
        guard !settled else { return }
        player?.pause()
        settled = true
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(IntroClip.autoAdvance * 1_000_000_000))
            finish()
        }
    }

    private func finish() {
        guard !finished else { return }
        finished = true
        IntroGate.markSeen()
        leaving = true                                    // fade through white, then the menu
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 350_000_000)
            teardown()
            done()
        }
    }

    private func teardown() {
        player?.pause()
        statusObserver?.invalidate(); statusObserver = nil
        if let o = endObserver { NotificationCenter.default.removeObserver(o); endObserver = nil }
    }
}

/// An AVPlayerLayer with no controls, aspect fit.
private struct IntroPlayerView: UIViewRepresentable {
    let player: AVPlayer
    func makeUIView(context: Context) -> PlayerUIView {
        let v = PlayerUIView()
        v.playerLayer.player = player
        v.playerLayer.videoGravity = .resizeAspect
        v.backgroundColor = .clear
        return v
    }
    func updateUIView(_ v: PlayerUIView, context: Context) {}
    final class PlayerUIView: UIView {
        override class var layerClass: AnyClass { AVPlayerLayer.self }
        var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
    }
}
