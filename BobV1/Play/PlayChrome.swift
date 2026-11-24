//
//  PlayChrome.swift
//  Play mode's screen furniture: the drag surface that lets the ball go (a flick), the Done pill (same cream capsule as Cancel / Let them go), a tiny first-time hint,
//  hearts rising from the hand when the ball is caught after a good rally. Opaque cream like the rest of the HUD (no glass over the game view).
//

import SwiftUI

struct PlayChrome: View {
    let care: GameCare
    private var play: PlayToss { care.play }
    @State private var hearts: [PlayHeart] = []
    @State private var seenCatch = 0
    @State private var thrown = false
    @State private var dragStart: CGPoint?
    @Environment(\.verticalSizeClass) private var vsc

    struct PlayHeart: Identifiable { let id = UUID(); var x: CGFloat; var born = Date() }

    var body: some View {
        ZStack {
            if play.phase == .toy { toySurface } else if play.active { surface }
        }
        .animation(.easeInOut(duration: 0.25), value: play.active)
        .onChange(of: play.active) { _, on in if on { thrown = false; hearts = []; seenCatch = play.catchSerial } }
    }

    private var surface: some View {
        ZStack {
            surfaceLayer
            // the Done pill respects the safe area (the status bar is above it)
            VStack { HStack { DonePill { withAnimation(CareMenu.spring) { care.endPlay() } }; Spacer() }.padding(.horizontal, 16).padding(.top, 8); Spacer() }
        }
    }

    /// A non-ball toy (the bubble wand): its own controls at the bottom and the same Done pill.
    private var toySurface: some View {
        ZStack {
            if BubbleWand.shared.active { BubbleWandControls() }
            VStack { HStack { DonePill { withAnimation(CareMenu.spring) { care.endPlay() } }; Spacer() }.padding(.horizontal, 16).padding(.top, 8); Spacer() }
        }
    }

    private var surfaceLayer: some View {
        GeometryReader { g in
            let size = CGSize(width: g.size.width + g.safeAreaInsets.leading + g.safeAreaInsets.trailing, height: g.size.height + g.safeAreaInsets.top + g.safeAreaInsets.bottom)
            ZStack {
                Color.clear.contentShape(Rectangle())
                    .gesture(DragGesture(minimumDistance: 0, coordinateSpace: .global)
                        .onChanged { v in
                            guard play.phase == .inHand else { return }
                            if dragStart == nil {
                                guard v.startLocation.y > size.height * 0.45 else { return }          // the lower half starts a throw
                                dragStart = v.startLocation
                            }
                            play.finger = v.location
                        }
                        .onEnded { v in
                            defer { dragStart = nil }
                            guard play.phase == .inHand, dragStart != nil else { play.finger = nil; return }
                            let moved = hypot(v.location.x - v.startLocation.x, v.location.y - v.startLocation.y)
                            if moved < 14, hypot(v.velocity.width, v.velocity.height) < 120 { play.finger = nil; return }          // a tap: the ball stays
                            play.flick(from: v.location, velocity: CGVector(dx: v.velocity.width, dy: v.velocity.height))
                            thrown = true
                        })
                    .accessibilityElement()
                    .accessibilityLabel("The \(play.toyTitle.lowercased()), in your hand")
                    .accessibilityHint("Swipe up to throw it to a Jelmiko")
                    .accessibilityAddTraits(.allowsDirectInteraction)
                    .accessibilityAction(named: "Throw to a Jelmiko") { throwToMiddle(size) }
                    .accessibilityAction(named: "Pass it back") { if play.keeping { play.recall() } }
                    .accessibilityIdentifier("play-surface")
                Color.clear.frame(width: 0, height: 0).allowsHitTesting(false).accessibilityHidden(true)
                    .onChange(of: play.phase == .inHand && !thrown && play.camBlend > 0.8, initial: true) { _, on in          // (the hint is a line on the one message bar)
                        if on { GameMessageCenter.shared.post("Flick the ball to a Jelmiko", priority: .chatty, identifier: "play-hint", sticky: GameMessageCenter.hintsSticky) }
                        else { GameMessageCenter.shared.dismiss(identifier: "play-hint") }          // (thrown, or the toy is away: the hint has done its job)
                    }
                // hearts from the hand
                TimelineView(.animation(minimumInterval: 1.0 / 30)) { tl in
                    Canvas { ctx, sz in
                        let now = tl.date
                        for h in hearts {
                            let a = now.timeIntervalSince(h.born) / 1.3
                            guard a >= 0, a < 1 else { continue }
                            var c = ctx
                            c.opacity = a < 0.12 ? a / 0.12 : min(1, (1 - a) / 0.4)
                            let hand = CGPoint(x: size.width * 0.5 + h.x, y: size.height * 0.82 - CGFloat(a) * size.height * 0.16)
                            c.translateBy(x: hand.x - (g.safeAreaInsets.leading), y: hand.y - g.safeAreaInsets.top)
                            let s = 0.7 + 0.3 * min(1, a * 5)
                            if let sym = c.resolveSymbol(id: 0) { c.scaleBy(x: s, y: s); c.draw(sym, at: .zero) }
                        }
                    } symbols: {
                        Image(systemName: "heart.fill").font(.system(size: 30, weight: .semibold)).foregroundStyle(FocusStyle.pink).tag(0)
                    }
                }
                .allowsHitTesting(false).accessibilityHidden(true)
                // play-ball-s3: while the Jelmiko keep the ball (a pass chain) the hand's place holds "Pass it back"; one tap asks for the next strike to come to you
                ZStack {
                    if play.keeping {
                        PassBackPill { play.recall() }
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                            .padding(.bottom, max(g.safeAreaInsets.bottom + 16, size.height * (HUDLayout.isLandscape(vsc: vsc, size: size) ? 0.085 : 0.10)))
                            .transition(.scale(scale: 0.8).combined(with: .opacity))
                    }
                }
                .frame(width: g.size.width, height: g.size.height)
                .animation(.spring(response: 0.3, dampingFraction: 0.82), value: play.keeping)
            }
            .frame(width: g.size.width, height: g.size.height)
        }
        .ignoresSafeArea()
        .onGeometryChange(for: CGSize.self) { $0.size } action: { play.viewSize = $0 }
        .onChange(of: play.catchSerial) { _, n in
            guard n != seenCatch else { return }
            seenCatch = n
            if play.shownRally >= 1 {
                let t = Date()
                for k in 0..<(play.shownRally >= 3 ? 5 : 3) { hearts.append(PlayHeart(x: CGFloat(k - 1) * 34 + CGFloat.random(in: -8...8), born: t.addingTimeInterval(Double(k) * 0.07))) }
                Task { try? await Task.sleep(nanoseconds: 1_800_000_000); hearts.removeAll { Date().timeIntervalSince($0.born) > 1.4 } }
            }
        }
    }

    private func throwToMiddle(_ size: CGSize) {
        guard play.phase == .inHand else { return }
        play.viewSize = size
        let p = CGPoint(x: size.width * 0.5, y: size.height * 0.82)
        play.flick(from: p, velocity: CGVector(dx: 0, dy: -size.height * 1.8))
        thrown = true
    }
}

/// "Done": the way out of Play mode. The same cream capsule as Cancel / Let them go.
struct DonePill: View {
    let action: () -> Void
    var body: some View {
        Button {
            UIImpactFeedbackGenerator(style: .soft).impactOccurred(); AudioHub.shared.uiTap()
            action()
        } label: {
            HStack(spacing: 7) {
                Image(systemName: "checkmark").font(.system(size: 13, weight: .bold))
                Text("Done").jFont(16, .semibold)
            }
            .foregroundStyle(FocusStyle.brown)
            .padding(.horizontal, 18).padding(.vertical, 10).frame(minHeight: 44)
            .background(Capsule().fill(FocusStyle.cream).shadow(color: FocusStyle.shadow.opacity(0.2), radius: 6, y: 2))
            .overlay(Capsule().strokeBorder(Color.white.opacity(0.6), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("play-done")
        .accessibilityLabel("Done")
        .accessibilityHint("Stops playing and lets everyone roam")
        .keyboardShortcut(.escape, modifiers: [])
    }
}

/// "Pass it back": asks the Jelmiko to send the ball back to you while they are passing it among themselves. The same cream capsule as `DonePill`.
struct PassBackPill: View {
    let action: () -> Void
    var body: some View {
        Button {
            UIImpactFeedbackGenerator(style: .soft).impactOccurred(); AudioHub.shared.uiTap()
            action()
        } label: {
            HStack(spacing: 7) {
                Image(systemName: "arrow.uturn.down").font(.system(size: 13, weight: .bold))
                Text("Pass it back").jFont(16, .semibold).fixedSize(horizontal: false, vertical: true)
            }
            .foregroundStyle(FocusStyle.brown)
            .padding(.horizontal, 18).padding(.vertical, 10).frame(minHeight: 44)
            .background(Capsule().fill(FocusStyle.cream).shadow(color: FocusStyle.shadow.opacity(0.2), radius: 6, y: 2))
            .overlay(Capsule().strokeBorder(Color.white.opacity(0.6), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("play-pass-back")
        .accessibilityLabel("Pass it back")
        .accessibilityHint("Asks the Jelmiko to send the ball back to you")
    }
}
