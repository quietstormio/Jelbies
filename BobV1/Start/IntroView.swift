//
//  IntroView.swift
//  The launch intro: the full-screen Jelbies logo animation (paper background, its own sting) plays all the way through with no tap needed, holds its last frame
//  (paused), then cross-fades to the menu over IntroClip.fadeSeconds and is torn down (IntroFlow.swift has the states). A tap jumps to the held last frame, never a replay.
//  Reduce Motion shows the last frame, then the same fade. Rotating during playback swaps in the other variant at the same timestamp.
//  Shown before the main menu on the very first launch only (the seen flag is set when it fades; an existing save counts as seen). Every later cold launch shows LogoMoment instead.
//  ContentView reads the gate once per process, so resuming from the background never replays either.
//  Swapping the clip: replace the files in Start/Resources (or change `IntroClip.resource(landscape:)`).
//

import SwiftUI
import AVFoundation
import QuartzCore

enum IntroClip {
    /// The full-screen logo animation (stars, the word puffing up, the jelly on the "i", the stomp, the letters pop, the jelly falls away; the old intro sting),
    /// about 6.2 s at 60 fps (the artifact's Play once mode: the full sequence once, the jelly falls away and it rests on clean paper; the stomp is at about 3.9 s and the sting's hit is aligned to it), Blue theme, ending on empty paper (#F0EFF0). Re-render with tools/render_intro/render_intro.py --mode end --tail-fade 0 --tail-hold 0 --audio <sting> --audio-offset 0.4. Two renders: 1206x2622 for portrait, 2622x1206 for landscape (chosen when the intro opens).
    static func resource(landscape: Bool) -> String { landscape ? "jelbies_logo_intro_landscape" : "jelbies_logo_intro_portrait" }
    static let fileExtension = "mp4"
    /// The last frame is held (paused) this long, then the intro cross-fades into the menu over `fadeSeconds` (-IntroHold / -IntroFade scale them on the simulator for captures).
    /// "Skip" shows this long after the clip starts; after a skip the last frame is held for the preloads for at most `loadWaitCap` seconds.
    static let skipAppearsAfter: Double = 1.0
    static let loadWaitCap: Double = 2.5          // (user 11-04: 0.6 s let the fade overlap the warm-up and the video stuttered: hold until it is done, up to 2.5 s)
    static var holdSeconds: Double { simOverride("IntroHold") ?? 0.3 }
    static var fadeSeconds: Double { simOverride("IntroFade") ?? 0.7 }
    private static func simOverride(_ key: String) -> Double? {
        #if targetEnvironment(simulator)
        if UserDefaults.standard.object(forKey: key) != nil { return UserDefaults.standard.double(forKey: key) }
        #endif
        return nil
    }
}

enum IntroGate {
    static let seenKey = "IntroSeen.v1"
    /// The animation's own paper (#F0EFF0), so any letterbox edge is seamless.
    static let background = Color(red: 240 / 255, green: 239 / 255, blue: 240 / 255)
    static func shouldShow(_ d: UserDefaults = .standard) -> Bool {
        #if targetEnvironment(simulator)
        if d.integer(forKey: "SkipIntro") != 0 { return false }          // capture aid (simulator only): -SkipIntro 1
        #endif
        let show = (d.bool(forKey: pendingKey) || !d.bool(forKey: seenKey)) && !StartFlow.hasSave(d)          // the full intro plays on the very first launch only (a player with a save has seen it)
        if show { shownThisProcess = true }
        return show
    }
    /// `-NewGame first` asks for the full intro on the NEXT launch: set by the reset, cleared only once the full intro has really been shown (the short logo of the reset launch does not count).
    static let pendingKey = "NewGame.firstIntro"
    nonisolated(unsafe) static var shownThisProcess = false
    static func markSeen(_ d: UserDefaults = .standard) {
        if d.bool(forKey: pendingKey), !shownThisProcess { return }
        d.set(true, forKey: seenKey); d.removeObject(forKey: pendingKey)
    }
}

struct IntroView: View {
    var done: () -> Void
    @State private var flow: IntroFlow
    @Environment(\.accessibilityReduceMotion) private var reduceMotionEnv
    @Environment(\.scenePhase) private var scenePhase

    init(done: @escaping () -> Void) {
        self.done = done
        _flow = State(initialValue: IntroFlow(onFadeBegins: done))
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                IntroGate.background
                if let player = flow.player {
                    IntroPlayerView(player: player).frame(width: geo.size.width, height: geo.size.height).accessibilityIgnoresInvertColors()
                        .opacity(flow.shown ? 1 : 0)
                        .animation(.easeInOut(duration: 0.5), value: flow.shown)
                }
                if A11ySettings.shared.captions, flow.stage == .playing, flow.shown {
                    Text("Soft music and sparkles")          // caption for the intro clip's sound
                        .font(CloudTheme.font(HUDLayout.isPad ? 20 : 16, .semibold)).foregroundStyle(CloudTheme.ink)
                        .frame(maxWidth: HUDLayout.isPad ? 560 : .infinity)
                        .padding(.horizontal, 14).padding(.vertical, 6)
                        .background(Capsule().fill(CloudTheme.mist))
                        .frame(maxHeight: .infinity, alignment: .top).padding(.top, max(48, geo.size.height * 0.08))
                        .accessibilityHidden(true)
                }
            }
            .overlay(alignment: .bottomTrailing) {
                Text("Skip").font(SK.font(HUDLayout.isPad ? 19 : 15, .bold)).foregroundStyle(SK.ink)
                    .padding(.horizontal, 18).padding(.vertical, 8)
                    .background(Capsule().fill(SK.cream))          // the HUD's opaque cream pill (no glass / blur)
                    .padding(.trailing, 22).padding(.bottom, 34)
                    .opacity(flow.skipVisible ? 1 : 0)
                    .animation(.easeOut(duration: 0.4), value: flow.skipVisible)
                    .accessibilityHidden(true)
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .onChange(of: geo.size.width > geo.size.height) { _, land in flow.rotated(landscape: land) }
            .onAppear {
                flow.reduceMotion = reduceMotionEnv || A11ySettings.shared.reduceMotion
                IntroWarmup.begin()          // quiet start-up work runs while the clip plays
                flow.start(landscape: geo.size.width > geo.size.height)
                A11yAnnounce.say("Jelbies. Intro animation. Double tap to skip intro.", priority: .low)
            }
        }
        .background(IntroGate.background)
        .ignoresSafeArea()
        .contentShape(Rectangle())
        .onTapGesture { flow.tap() }
        .onChange(of: scenePhase) { _, ph in if ph == .active { flow.sceneActive() } }
        .onDisappear { flow.teardown() }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(flow.skipVisible ? "Skip intro" : "Jelbies. Intro animation: the Jelbies logo builds with stars and soft music.")
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("Jumps to the end of the intro")
        .accessibilityIdentifier("intro")
    }
}

/// Every cold launch after the first: the still official logo over the title backdrop for about a second, then straight on (a quick fade).
struct LogoMoment: View {
    static let holdSeconds: Double = 0.7
    var done: () -> Void
    private var theme = ThemeStore.shared
    init(done: @escaping () -> Void) { self.done = done }

    var body: some View {
        GeometryReader { geo in
            let u = min(geo.size.width, geo.size.height) / 440
            let w = min(geo.size.width * 0.8, 360 * max(u, 0.8), HUDLayout.isPad ? 560 : .infinity)
            ZStack {
                TitleBackdrop(still: true, size: geo.size, landscape: geo.size.width > geo.size.height, palette: theme.palette, extras: false)
                Image("JelbiesLogo").resizable().scaledToFit().themedLogo().frame(width: w)
                    .shadow(color: theme.palette.shadow, radius: 0, x: 0, y: 7 * w / 364)
                    .position(x: geo.size.width / 2, y: geo.size.height / 2)
                    .accessibilityLabel("Jelbies")
            }
        }
        .ignoresSafeArea()
        .task {
            try? await Task.sleep(nanoseconds: UInt64(Self.holdSeconds * 1e9))
            done()
        }
        .accessibilityIdentifier("logo-moment")
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
