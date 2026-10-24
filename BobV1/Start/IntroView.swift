//
//  IntroView.swift
//  The first-launch intro (Cloud Jelly): a white, square logo clip draws the logo in, then the crisp logo crossfades in with a jelly settle and
//  three small sparkles, "Tap to start" fades in, and a tap (or 2.5 s) fades through white to the menu. A tap during the clip skips to the settled logo.
//  Shown before the main menu until UserDefaults "IntroSeen.v1" is set; launch argument -Intro 1 forces it (for captures).
//  Swapping the clip: replace the file in Start/Resources (or change `IntroClip.resource`); change `IntroClip.handoffTime` if the crossfade should
//  start before the clip's end (nil = at the clip's end).
//

import SwiftUI
import AVFoundation

enum IntroClip {
    static let resource = "jelbies_intro"
    static let fileExtension = "mp4"
    /// Seconds into the clip at which the crisp logo takes over; nil = when the clip ends.
    static let handoffTime: Double? = nil
    /// The clip's logo width as a share of the (square) clip's width; the crisp logo is drawn at the same size.
    static let logoWidthShare: CGFloat = 0.87
    /// Seconds after the logo settles before it moves on by itself.
    static let autoAdvance: Double = 2.5
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
    @State private var settled = false
    @State private var leaving = false
    @State private var finished = false
    @State private var boundary: Any?
    @State private var endObserver: NSObjectProtocol?
    @Environment(\.accessibilityReduceMotion) private var reduceMotionEnv
    private var still: Bool { reduceMotionEnv || A11ySettings.shared.reduceMotion }

    var body: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            let logoW = side * IntroClip.logoWidthShare
            ZStack {
                IntroGate.background
                if let player {
                    IntroPlayerView(player: player).frame(width: side, height: side)
                        .opacity(settled ? 0 : 1)
                        .animation(.easeOut(duration: 0.35), value: settled)
                }
                logo(width: logoW)
                sparkles(side: side, logoW: logoW)
                Text("Tap to start").font(CloudTheme.font(18, .semibold)).foregroundStyle(CloudTheme.jelly)
                    .frame(maxHeight: .infinity, alignment: .bottom).padding(.bottom, max(28, geo.size.height * 0.08))
                    .opacity(settled ? 1 : 0)
                    .animation(.easeOut(duration: 0.4).delay(settled ? 0.8 : 0), value: settled)
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .opacity(leaving ? 0 : 1)
            .animation(.easeInOut(duration: 0.4), value: leaving)
        }
        .background(IntroGate.background)
        .ignoresSafeArea()
        .contentShape(Rectangle())
        .onTapGesture { tapped() }
        .onAppear { start() }
        .onDisappear { teardown() }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Jelbies")
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("Starts the game")
        .accessibilityIdentifier("intro")
    }

    @ViewBuilder private func logo(width: CGFloat) -> some View {
        let img = Image("JelbiesLogo").resizable().scaledToFit().frame(width: width)
        if still {
            img.opacity(settled ? 1 : 0).animation(.easeInOut(duration: 0.35), value: settled)
        } else {
            img.opacity(settled ? 1 : 0)
                .keyframeAnimator(initialValue: LogoSettle(), trigger: settled) { v, s in
                    v.scaleEffect(x: settled ? s.x : 0.82, y: settled ? s.y : 0.82, anchor: .bottom)
                } keyframes: { _ in
                    KeyframeTrack(\.x) { CubicKeyframe(0.82, duration: 0.01); SpringKeyframe(1.08, duration: 0.32, spring: .bouncy); CubicKeyframe(0.96, duration: 0.22); SpringKeyframe(1.0, duration: 0.35, spring: .bouncy) }
                    KeyframeTrack(\.y) { CubicKeyframe(0.82, duration: 0.01); SpringKeyframe(0.90, duration: 0.32, spring: .bouncy); CubicKeyframe(1.05, duration: 0.22); SpringKeyframe(1.0, duration: 0.35, spring: .bouncy) }
                }
                .animation(.easeOut(duration: 0.2), value: settled)
        }
    }

    private struct LogoSettle { var x: CGFloat = 1; var y: CGFloat = 1 }

    private func sparkles(side: CGFloat, logoW: CGFloat) -> some View {
        let spots: [(CGFloat, CGFloat, Double)] = [(-0.36, -0.12, 0.15), (0.38, -0.10, 0.4), (0.02, 0.17, 0.5)]
        return ZStack {
            if !still {
                ForEach(0..<3, id: \.self) { i in
                    Sparkle(go: settled, delay: spots[i].2)
                        .frame(width: 16, height: 16)
                        .offset(x: spots[i].0 * logoW * 1.15, y: spots[i].1 * side)
                }
            }
        }
        .allowsHitTesting(false).accessibilityHidden(true)
    }

    // MARK: flow

    private func start() {
        guard player == nil else { return }
        if still { settled = true; scheduleAdvance(); return }
        guard let url = Bundle.main.url(forResource: IntroClip.resource, withExtension: IntroClip.fileExtension) else { settle(); return }
        let p = AVPlayer(url: url)
        p.isMuted = true
        p.actionAtItemEnd = .pause
        player = p
        endObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: p.currentItem, queue: .main) { _ in
            Task { @MainActor in settle() }
        }
        if let t = IntroClip.handoffTime {
            boundary = p.addBoundaryTimeObserver(forTimes: [NSValue(time: CMTime(seconds: t, preferredTimescale: 600))], queue: .main) {
                Task { @MainActor in settle() }
            }
        }
        p.play()
    }

    private func tapped() { if settled { finish() } else { settle() } }

    /// The crisp logo takes over (clip end, handoff time, or a tap during the clip).
    private func settle() {
        guard !settled else { return }
        player?.pause()
        settled = true
        scheduleAdvance()
    }

    private func scheduleAdvance() {
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
        if let b = boundary { player?.removeTimeObserver(b); boundary = nil }
        if let o = endObserver { NotificationCenter.default.removeObserver(o); endObserver = nil }
    }
}

/// A small 4-point blue sparkle: pops in, turns, and fades.
private struct Sparkle: View {
    var go: Bool
    var delay: Double
    private struct V { var scale: CGFloat = 0.2; var rot: Double = 0; var opacity: Double = 0; var lift: CGFloat = 0 }
    var body: some View {
        Image(systemName: "sparkle").resizable().scaledToFit()
            .foregroundStyle(CloudTheme.jelly)
            .keyframeAnimator(initialValue: V(), trigger: go) { v, s in
                v.scaleEffect(go ? s.scale : 0.2).rotationEffect(.degrees(s.rot)).opacity(go ? s.opacity : 0).offset(y: s.lift)
            } keyframes: { _ in
                KeyframeTrack(\.scale) { LinearKeyframe(0.2, duration: delay); CubicKeyframe(1.2, duration: 0.44); CubicKeyframe(0.6, duration: 0.66) }
                KeyframeTrack(\.rot) { LinearKeyframe(0, duration: delay); LinearKeyframe(90, duration: 1.1) }
                KeyframeTrack(\.opacity) { LinearKeyframe(0, duration: delay); CubicKeyframe(1, duration: 0.44); CubicKeyframe(0, duration: 0.66) }
                KeyframeTrack(\.lift) { LinearKeyframe(0, duration: delay); LinearKeyframe(-10, duration: 1.1) }
            }
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
