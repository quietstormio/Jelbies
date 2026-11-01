//
//  IntroView.swift
//  The launch intro: the full-screen Jelbies logo animation (paper background, its own sting) plays to its end, then fades to white (0.5 s) and the menu fades in from white (0.5 s).
//  A tap during the clip jumps to the fade. Reduce Motion shows the last frame, then the same fades.
//  Shown before the main menu on every cold launch (ContentView reads the gate once per process, so resuming from the background never replays it); -Intro 1 is accepted and changes nothing.
//  Swapping the clip: replace the files in Start/Resources (or change `IntroClip.resource(landscape:)`).
//

import SwiftUI
import AVFoundation
import QuartzCore

enum IntroClip {
    /// The full-screen logo animation (stars, the word puffing up, the jelly on the "i", the stomp, the letters pop, the jelly falls away; the old intro sting),
    /// about 7.9 s at 60 fps, Blue theme, ending on empty paper. Two renders: 1206x2622 for portrait, 2622x1206 for landscape (chosen when the intro opens).
    static func resource(landscape: Bool) -> String { landscape ? "jelbies_logo_intro_landscape" : "jelbies_logo_intro_portrait" }
    static let fileExtension = "mp4"
    /// The clip pauses here (8/3 s = the first frame of the clip's hold: the word is complete and the jelly has settled on the "i") and shows "Tap to play";
    /// a tap plays the rest (the hold, the stomp, the letters pop, the jelly falls away).
    static let pauseAt: Double = 8.0 / 3.0
    /// Seconds to fade to white after the clip (and the menu then fades in from white over the same time, see ContentView).
    static let fadeToWhite: Double = 0.5
}

enum IntroGate {
    static let seenKey = "IntroSeen.v1"
    /// The animation's own paper (#F0EFF0), so any letterbox edge is seamless.
    static let background = Color(red: 240 / 255, green: 239 / 255, blue: 240 / 255)
    static func shouldShow(_ d: UserDefaults = .standard) -> Bool {
        true          // every cold launch; seenKey / markSeen stay only so StartFlow's wipe keeps compiling
    }
    static func markSeen(_ d: UserDefaults = .standard) { d.set(true, forKey: seenKey) }
}

struct IntroView: View {
    var done: () -> Void
    @State private var player: AVPlayer?
    @State private var ready = false          // the item can play
    @State private var shown = false          // the clip is visible: playback has really advanced (or the last frame is up)
        @State private var settledAny = false
    @State private var awaitingTap = false     // paused on the finished logo with the "Tap to play" pill up
    @State private var pausedOnce = false
    @State private var pauseObserver: Any?
    @State private var leaving = false
    @State private var finished = false
    @State private var volume: Float = 0
    @State private var statusObserver: NSKeyValueObservation?
    @State private var endObserver: NSObjectProtocol?
    @State private var lagProbe: Any?          // times the clip against the wall clock (the warm-up must not make it stutter)
    @State private var lagWorst = 0.0
    @Environment(\.accessibilityReduceMotion) private var reduceMotionEnv
    private var still: Bool { reduceMotionEnv || A11ySettings.shared.reduceMotion }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                IntroGate.background
                if let player {
                    IntroPlayerView(player: player).frame(width: geo.size.width, height: geo.size.height)
                        .opacity(shown ? 1 : 0)
                        .animation(.easeInOut(duration: 0.5), value: shown)
                }
                if A11ySettings.shared.captions, !settledAny, shown {
                    Text("Soft music and sparkles")          // caption for the intro clip's sound
                        .font(CloudTheme.font(16, .semibold)).foregroundStyle(CloudTheme.ink)
                        .padding(.horizontal, 14).padding(.vertical, 6)
                        .background(Capsule().fill(CloudTheme.mist))
                        .frame(maxHeight: .infinity, alignment: .top).padding(.top, max(48, geo.size.height * 0.08))
                        .accessibilityHidden(true)
                }
                Text("Tap to play").font(SK.font(18, .bold)).foregroundStyle(SK.ink)
                    .padding(.horizontal, 26).padding(.vertical, 12)
                    .background(Capsule().fill(SK.cream))          // the HUD's opaque cream pill, brown text
                    .frame(maxHeight: .infinity, alignment: .bottom).padding(.bottom, 28)
                    .padding(.bottom, 34)          // above the home indicator's safe area
                    .opacity(awaitingTap ? 1 : 0)
                    .animation(.easeOut(duration: 0.3), value: awaitingTap)
                    .accessibilityHidden(true)
                Color.white.opacity(leaving ? 1 : 0)          // the clip ends (or is skipped): fade to white, then the menu fades in from white
                    .animation(.easeInOut(duration: IntroClip.fadeToWhite), value: leaving)
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .background(IntroGate.background)
        .ignoresSafeArea()
        .contentShape(Rectangle())
        .onTapGesture { tapped() }
        .onAppear { start(UIScreen.main.bounds.width > UIScreen.main.bounds.height); A11yAnnounce.say("Jelbies. Double tap to play.", priority: .low) }
        .onDisappear { teardown() }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(awaitingTap ? "Tap to play" : "Jelbies. Intro animation: the Jelbies logo builds with stars and soft music.")
        .accessibilityAddTraits(.isButton)
        .accessibilityHint(awaitingTap ? "Plays the rest of the intro" : "Skips the intro")
        .accessibilityIdentifier("intro")
    }

    // MARK: flow

    private func start(_ landscape: Bool) {
        guard player == nil else { return }
        IntroWarmup.begin()          // quiet start-up work runs while the clip plays
        guard let url = Bundle.main.url(forResource: IntroClip.resource(landscape: landscape), withExtension: IntroClip.fileExtension) else { settle(); return }
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
            if it.status == .failed { Task { @MainActor in settle() } }          // no clip: straight to "Tap to start"
            guard it.status == .readyToPlay else { return }
            Task { @MainActor in begin() }
        }
        Task { @MainActor in          // never ready within 3 s: don't leave a blank screen
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            if !ready { settle() }
        }
    }

    /// The first frame is decoded: play the clip, still white until playback advances (Reduce Motion shows its last frame instead).
    private func begin() {
        guard let p = player, !ready, !settledAny, !finished else { return }
        if still {
            p.seek(to: CMTime(seconds: IntroClip.pauseAt, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero) { _ in
                Task { @MainActor in          // Reduce Motion: the finished logo with the pill; a tap goes straight to the fade
                    ready = true; shown = true; pausedOnce = true; awaitingTap = true
                    LaunchTiming.mark("intro: clip ready")
                }
            }
        } else {
            ready = true
            LaunchTiming.mark("intro: clip ready")
            p.play()
            pauseObserver = p.addBoundaryTimeObserver(forTimes: [NSValue(time: CMTime(seconds: IntroClip.pauseAt, preferredTimescale: 600))], queue: .main) {
                MainActor.assumeIsolated { pauseOnLogo(p) }
            }
            Task { @MainActor in          // playback never advanced: fade in anyway
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                reveal()
            }
            var base: Double?          // wall minus clip time at the first tick; growth beyond it is playback falling behind
            lagProbe = p.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.05, preferredTimescale: 600), queue: .main) { t in
                MainActor.assumeIsolated {
                    guard p.rate > 0, !pausedOnce else { return }
                    if t.seconds >= 1.0 / 30 { reveal() }
                    let off = CACurrentMediaTime() - t.seconds
                    if base == nil { base = off }
                    lagWorst = max(lagWorst, off - (base ?? off))
                }
            }
        }
    }

    /// Fades the clip in from white (once).
    private func reveal() {
        guard !shown else { return }
        shown = true
        LaunchTiming.mark("intro: clip shown")
    }

    /// The clip reached the finished logo: video and its sting pause together and the pill appears.
    private func pauseOnLogo(_ p: AVPlayer) {
        guard !pausedOnce, !settledAny, !finished else { return }
        pausedOnce = true
        p.pause()
        awaitingTap = true
        LaunchTiming.mark("intro: paused on the logo")
    }

    /// Tap 1 (on the pill, or earlier in the clip) plays / jumps to the second half; a tap during the second half skips to the fade (audio ramps out).
    private func tapped() {
        guard !settledAny else { return }
        if awaitingTap {
            awaitingTap = false
            guard let p = player, !still else { settledAny = true; finish(); return }
            p.play()
            return
        }
        if !pausedOnce, let p = player, ready, !still {          // first half: jump to the finished logo and its pill
            p.seek(to: CMTime(seconds: IntroClip.pauseAt, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero) { _ in
                Task { @MainActor in pauseOnLogo(p) }
            }
            return
        }
        settledAny = true
        if let p = player, ready { fadeOutAudio(p) }
        finish()
    }

    /// Ramps the clip's audio to silence over 0.25 s.
    private func fadeOutAudio(_ p: AVPlayer) {
        let start = p.volume
        let steps = 5
        for i in 1...steps {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25 * Double(i) / Double(steps)) { p.volume = start * Float(steps - i) / Float(steps) }
        }
    }

    /// The clip is on its last frame (empty paper), or there is no clip: straight to the fade.
    private func settle() {
        guard !settledAny else { return }
        player?.pause()
        shown = true
        settledAny = true
        finish()
    }

    private func finish() {
        guard !finished else { return }
        finished = true
        IntroGate.markSeen()
        leaving = true                                    // fade through white, then the menu
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(IntroClip.fadeToWhite * 1_000_000_000))
            teardown()
            done()
        }
    }

    private func teardown() {
        if let o = pauseObserver, let p = player { p.removeTimeObserver(o); pauseObserver = nil }
        if let o = lagProbe, let p = player { p.removeTimeObserver(o); lagProbe = nil; NSLog("%@", String(format: "[melon] launch: intro playback: worst lag behind the wall clock %.0f ms", lagWorst * 1000)) }
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
