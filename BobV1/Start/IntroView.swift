//
//  IntroView.swift
//  The first-launch intro: the animated Jelbies logo (a square, background-matched mp4) played once on #F0EFF0, tap to skip.
//  Shown before the main menu until UserDefaults "IntroSeen.v1" is set; launch argument -Intro 1 forces it (for captures).
//

import SwiftUI
import AVFoundation

enum IntroGate {
    static let seenKey = "IntroSeen.v1"
    static let background = Color(red: 240 / 255, green: 239 / 255, blue: 240 / 255)
    static func shouldShow(_ d: UserDefaults = .standard) -> Bool {
        d.integer(forKey: "Intro") != 0 || !d.bool(forKey: seenKey)
    }
    static func markSeen(_ d: UserDefaults = .standard) { d.set(true, forKey: seenKey) }
}

struct IntroView: View {
    var done: () -> Void
    @State private var player: AVPlayer?
    @State private var finished = false

    var body: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            ZStack {
                IntroGate.background
                if let player { IntroPlayerView(player: player).frame(width: side, height: side) }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .ignoresSafeArea()
        .contentShape(Rectangle())
        .onTapGesture { finish() }
        .onAppear { start() }
        .onDisappear { player?.pause() }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Jelbies")
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("Skips the intro")
        .accessibilityIdentifier("intro")
    }

    private func start() {
        guard player == nil else { return }
        guard let url = Bundle.main.url(forResource: "jelbies_intro", withExtension: "mp4") else { finish(); return }
        let p = AVPlayer(url: url)
        p.isMuted = true
        p.actionAtItemEnd = .pause
        player = p
        NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: p.currentItem, queue: .main) { _ in
            Task { @MainActor in finish() }
        }
        p.play()
    }

    private func finish() {
        guard !finished else { return }
        finished = true
        player?.pause()
        IntroGate.markSeen()
        done()
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
