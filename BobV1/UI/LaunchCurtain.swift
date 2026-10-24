//
//  LaunchCurtain.swift
//  The short loading screen on a cold launch (and when the player comes back at night to Jelbies who are already asleep).
//  It reads the real clock, waits for the room to build and settle under it, then fades away into the room. Brand look, one title and three
//  bouncing jelly dots; no thought lines. Works in landscape (everything is centred and scales with the short side).
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

/// The picture itself (also rendered by the captures).
struct LaunchCurtainArt: View {
    let hour: Double
    var bounce: Bool

    var body: some View {
        let phase = DayPhase.of(hour: hour)
        let night = phase == .night
        let light = DayLight.at(hour: hour)
        GeometryReader { geo in
            let u = min(geo.size.width, geo.size.height) / 440
            ZStack {
                LinearGradient(colors: [top(light, night), bottom(light, night)], startPoint: .top, endPoint: .bottom)
                if light.sky0.w > 0.3 || night { stars(geo.size).opacity(night ? 1 : Double(light.sky0.w)) }
                VStack(spacing: 14 * u) {
                    Image(systemName: glyph(phase)).font(.system(size: 34 * u, weight: .bold))
                        .foregroundStyle(night ? SK.honey : SK.honeyDeep)
                    Text("Jelbies").font(.system(size: 54 * u, weight: .heavy, design: .rounded)).foregroundStyle(night ? SK.cream : SK.ink)
                    HStack(spacing: 14 * u) {
                        dot(Color(hex: 0x6EB3D1), 0, u)
                        dot(SK.honey, 1, u)
                        dot(SK.mint, 2, u)
                    }.padding(.top, 8 * u)
                }
                .position(x: geo.size.width / 2, y: geo.size.height / 2)
            }
        }
    }

    private func glyph(_ p: DayPhase) -> String {
        switch p { case .morning, .day: return "sun.max.fill"; case .evening: return "sunset.fill"; case .night: return "moon.stars.fill" }
    }
    // (DayLight's window sky is black by day, so the daytime backdrops are fixed brand tints per phase; night is the deep navy.)
    private func top(_ l: DayLight, _ night: Bool) -> Color {
        if night { return Color(hex: 0x1E2440) }
        switch DayPhase.of(hour: hour) { case .morning: return Color(hex: 0xFFE6C9); case .day: return Color(hex: 0xCFE8F3); case .evening: return Color(hex: 0xF7B98B); case .night: return Color(hex: 0x1E2440) }
    }
    private func bottom(_ l: DayLight, _ night: Bool) -> Color {
        if night { return Color(hex: 0x3A3F6B) }
        switch DayPhase.of(hour: hour) { case .morning: return SK.cream; case .day: return SK.cream; case .evening: return Color(hex: 0xF3D9B8); case .night: return Color(hex: 0x3A3F6B) }
    }
    private func dot(_ c: Color, _ i: Int, _ u: CGFloat) -> some View {
        Capsule().fill(c).frame(width: 26 * u, height: 26 * u)
            .overlay(Capsule().strokeBorder(Color.white.opacity(0.5), lineWidth: 1))
            .scaleEffect(x: bounce ? 1.12 : 0.92, y: bounce ? 0.86 : 1.1, anchor: .bottom)
            .offset(y: bounce ? 0 : -10 * u)
            .animation(.easeInOut(duration: 0.3).repeatForever(autoreverses: true).delay(Double(i) * 0.12), value: bounce)
    }
    private func stars(_ s: CGSize) -> some View {
        Canvas { ctx, size in
            let pts: [(CGFloat, CGFloat, CGFloat)] = [(0.12, 0.10, 2.2), (0.30, 0.22, 1.6), (0.52, 0.08, 2.0), (0.74, 0.18, 2.4), (0.90, 0.09, 1.6), (0.20, 0.36, 1.4), (0.64, 0.30, 1.8), (0.86, 0.34, 1.4), (0.40, 0.14, 1.4), (0.08, 0.28, 1.8)]
            for p in pts { ctx.fill(Path(ellipseIn: CGRect(x: p.0 * size.width, y: p.1 * size.height, width: p.2 * 2, height: p.2 * 2)), with: .color(.white.opacity(0.85))) }
        }
    }
}
