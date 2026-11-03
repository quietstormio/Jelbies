//
//  PlayChrome.swift
//  Play mode's screen furniture: the drag surface that lets the ball go (a flick), the Done pill (same cream capsule as Cancel / Let them go), a tiny first-time hint,
//  hearts rising from the hand when the ball is caught after a good rally, and the small "x3" rally mark. Opaque cream like the rest of the HUD (no glass over the game view).
//

import SwiftUI

struct PlayChrome: View {
    let care: GameCare
    private var play: PlayToss { care.play }
    @State private var hearts: [PlayHeart] = []
    @State private var seenCatch = 0
    @State private var rallyShown = 0
    @State private var thrown = false
    @State private var dragStart: CGPoint?
    @Environment(\.verticalSizeClass) private var vsc

    struct PlayHeart: Identifiable { let id = UUID(); var x: CGFloat; var born = Date() }

    var body: some View {
        ZStack {
            if play.phase == .toy { toySurface } else if play.active { surface }
            if let note = play.stubNotice {
                Text(note).jFont(14, .semibold).foregroundStyle(FocusStyle.brown)
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    .background(Capsule().fill(FocusStyle.cream).shadow(color: FocusStyle.shadow.opacity(0.2), radius: 7, y: 3))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top).padding(.top, 70)
                    .allowsHitTesting(false)
                    .task(id: note) { try? await Task.sleep(nanoseconds: 2_600_000_000); play.stubNotice = nil }
                    .accessibilityIdentifier("play-stub-notice")
            }
        }
        .animation(.easeInOut(duration: 0.25), value: play.active)
        .onChange(of: play.active) { _, on in if on { thrown = false; hearts = []; rallyShown = 0; seenCatch = play.catchSerial } }
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
                    .accessibilityHint("Swipe up to throw it to a Jelbie")
                    .accessibilityAddTraits(.allowsDirectInteraction)
                    .accessibilityAction(named: "Throw to a Jelbie") { throwToMiddle(size) }
                    .accessibilityIdentifier("play-surface")
                VStack {
                    Spacer()
                    if play.phase == .inHand, !thrown, play.camBlend > 0.8 {
                        Text("Flick the ball to a Jelbie").jFont(15, .semibold).foregroundStyle(FocusStyle.brown)
                            .padding(.horizontal, 18).padding(.vertical, 10)
                            .background(Capsule().fill(FocusStyle.cream).shadow(color: FocusStyle.shadow.opacity(0.2), radius: 7, y: 3))
                            .overlay(Capsule().strokeBorder(Color.white.opacity(0.6), lineWidth: 1))
                            .padding(.bottom, size.height * (vsc == .compact ? 0.19 : 0.20))
                            .transition(.opacity).allowsHitTesting(false)
                            .accessibilityHidden(true)
                    }
                }
                .frame(width: g.size.width, height: g.size.height)
                // hearts from the hand, and the rally mark
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
                if rallyShown >= 2 {
                    HStack(spacing: 4) {
                        Image(systemName: "heart.fill").font(.system(size: 11, weight: .bold)).foregroundStyle(FocusStyle.pink)
                        Text("×\(rallyShown)").jFont(14, .bold).foregroundStyle(FocusStyle.brown)
                    }
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(Capsule().fill(FocusStyle.cream).shadow(color: FocusStyle.shadow.opacity(0.18), radius: 5, y: 2))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                    .padding(.bottom, size.height * (vsc == .compact ? 0.25 : 0.23))
                    .transition(.scale(scale: 0.7).combined(with: .opacity))
                    .allowsHitTesting(false)
                    .accessibilityLabel("\(rallyShown) in a row")
                    .accessibilityIdentifier("play-rally")
                }
            }
            .frame(width: g.size.width, height: g.size.height)
        }
        .ignoresSafeArea()
        .onGeometryChange(for: CGSize.self) { $0.size } action: { play.viewSize = $0 }
        .onChange(of: play.catchSerial) { _, n in
            guard n != seenCatch else { return }
            seenCatch = n
            if play.shownRally >= 2 { rallyShown = play.shownRally; Task { try? await Task.sleep(nanoseconds: 2_200_000_000); withAnimation { if rallyShown == play.shownRally { rallyShown = 0 } } } }
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
