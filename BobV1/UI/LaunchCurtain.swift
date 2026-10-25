//
//  LaunchCurtain.swift
//  The short loading screen on a cold launch (and when the player comes back at night to Jelbies who are already asleep).
//  It reads the real clock, waits for the room to build and settle under it, then fades away into the room. Cloud Jelly look: the logo wobbling over white and
//  three hopping dots; no thought lines. Works in landscape (everything is centred and scales with the short side).
//

import SwiftUI
import Observation
import QuartzCore

/// When the curtain may go. Injected clock for the tests. Rules: at least `minShow` s, the stage has ticked, nothing is still settling
/// (or `settleCap` s passed), and never longer than `maxShow` s.
@Observable @MainActor
final class LaunchGate {
    static let shared = LaunchGate()
    enum Reason { case launch, resume }
    static let minShow: TimeInterval = 0.9, maxShow: TimeInterval = 4.0, settleCap: TimeInterval = 2.0, resumeMin: TimeInterval = 0.35

    private(set) var visible = true
    @ObservationIgnored var clock: () -> TimeInterval = { CACurrentMediaTime() }
    @ObservationIgnored private var shownAt: TimeInterval
    @ObservationIgnored private var minNow = LaunchGate.minShow
    @ObservationIgnored private var ticked = false
    @ObservationIgnored private var settleOK = true
    @ObservationIgnored private var settleStart: TimeInterval = 0

    nonisolated deinit {}          // (not an isolated deinit: see RoomSwitch)
    init(clock: (() -> TimeInterval)? = nil) {
        if let clock { self.clock = clock }
        shownAt = self.clock()
    }

    /// Show it again for the away-asleep arrival. A plain resume never calls this.
    func hold(_ r: Reason) {
        let t = clock()
        if visible {
            // The launch curtain is still up: keep its clock and its wait for the stage's first tick.
            settleStart = t; settleOK = false
            minNow = max(minNow, r == .launch ? Self.minShow : Self.resumeMin)
            return
        }
        shownAt = t; settleStart = t; ticked = true; settleOK = false
        minNow = r == .launch ? Self.minShow : Self.resumeMin
        visible = true
    }
    /// The stage ran a step (it has built and drawn).
    func stageTicked() {
        guard visible else { return }
        if !ticked { ticked = true; settleStart = clock() }
        evaluate()
    }
    /// The instant sleepers are down (true) or not yet (false).
    func settled(_ ok: Bool) {
        guard visible else { return }
        if ok != settleOK { settleOK = ok; if !ok { settleStart = clock() } }
        evaluate()
    }
    func evaluate() {
        guard visible else { return }
        let t = clock(), shown = t - shownAt
        if shown >= Self.maxShow || (shown >= minNow && ticked && (settleOK || t - settleStart >= Self.settleCap)) { visible = false }
    }
}

struct LaunchCurtain: View {
    var gate: LaunchGate
    /// Fixed hour for the captures; nil = the real clock.
    var hour: Double?

    @State private var bounce = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if gate.visible || hour != nil { content.transition(.opacity) }
        else { Color.clear.frame(width: 0, height: 0).onAppear { A11yAnnounce.say("Your Jelbies are ready", priority: .low) } }          // the curtain went: say so once
    }

    private var content: some View {
        let h = hour ?? DayClock.shared.hour
        return LaunchCurtainArt(hour: h, bounce: bounce && !(reduceMotion || A11ySettings.shared.reduceMotion))
            .ignoresSafeArea()
            .onAppear { bounce = true }
            .task { while !Task.isCancelled, gate.visible { gate.evaluate(); try? await Task.sleep(nanoseconds: 80_000_000) } }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Jelbies is loading")
            .accessibilityIdentifier("launch-curtain")
    }
}

/// The picture itself (also rendered by the captures). Cloud Jelly: white sky, drifting Mist circles, the real logo wobbling like jelly,
/// three hopping Jelly-blue dots and a small caption. (`hour` is kept for the captures' signature; the look no longer depends on the time of day.)
struct LaunchCurtainArt: View {
    let hour: Double
    var bounce: Bool
    private var theme = ThemeStore.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    init(hour: Double, bounce: Bool) { self.hour = hour; self.bounce = bounce }

    private struct Wobble { var x: CGFloat = 1; var y: CGFloat = 1 }

    var body: some View {
        GeometryReader { geo in
            let u = min(geo.size.width, geo.size.height) / 440
            let logoW = min(geo.size.width * 0.8, 360 * max(u, 0.8))
            ZStack {
                TitleBackdrop(still: reduceMotion || A11ySettings.shared.reduceMotion, size: geo.size, landscape: geo.size.width > geo.size.height, palette: theme.palette, extras: false)
                    .id(theme.palette.id).transition(.opacity)
                VStack(spacing: 18 * u) {
                    logo(width: logoW)
                    HStack(spacing: 12 * u) { ForEach(0..<3, id: \.self) { dot($0, u) } }.padding(.top, 4 * u)
                    Text("Waking up your Jelbies").font(CloudTheme.font(max(13, 14 * u), .medium)).foregroundStyle(theme.palette.continueText)
                        .padding(.horizontal, 14).padding(.vertical, 6).background(Capsule().fill(Color.white))
                }
                .position(x: geo.size.width / 2, y: geo.size.height / 2)
            }
        }
    }

    @ViewBuilder private func logo(width: CGFloat) -> some View {
        let img = Image("JelbiesLogo").resizable().scaledToFit().frame(width: width).shadow(color: theme.palette.shadow, radius: 0, x: 0, y: 7 * width / 364)
        if bounce {
            img.keyframeAnimator(initialValue: Wobble(), repeating: true) { v, w in v.scaleEffect(x: w.x, y: w.y, anchor: .bottom) } keyframes: { _ in
                KeyframeTrack(\.x) { CubicKeyframe(1.06, duration: 0.32); CubicKeyframe(0.96, duration: 0.32); CubicKeyframe(1.02, duration: 0.32); CubicKeyframe(1, duration: 0.32); CubicKeyframe(1, duration: 0.5) }
                KeyframeTrack(\.y) { CubicKeyframe(0.92, duration: 0.32); CubicKeyframe(1.05, duration: 0.32); CubicKeyframe(0.98, duration: 0.32); CubicKeyframe(1, duration: 0.32); CubicKeyframe(1, duration: 0.5) }
            }
        } else { img }
    }

    private func dot(_ i: Int, _ u: CGFloat) -> some View {
        Circle().fill(Color.white).frame(width: 13 * u + 4, height: 13 * u + 4)
            .scaleEffect(x: bounce ? 0.92 : 1.1, y: bounce ? 1.08 : 0.9, anchor: .bottom)
            .offset(y: bounce ? -10 * u : 0)
            .animation(.easeInOut(duration: 0.45).repeatForever(autoreverses: true).delay(Double(i) * 0.15), value: bounce)
    }
}
