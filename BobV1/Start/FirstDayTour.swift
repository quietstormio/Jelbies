//
//  FirstDayTour.swift
//  The "first day home" moment of a NEW game, played in the REAL home room (FirstDayStyle.room; the old illustrated screen, FirstDayHome.swift, stays behind
//  `FirstDayStyle.card`). After the first Jelmiko is brought home the room cross-fades in empty, the Jelmiko RUNS IN from the left edge (the bought-Jelmiko arrival run,
//  GameCare+Newcomer.swift), stops in the middle and hops (the welcome-home hop). Then, one at a time, tap to advance, with Skip always up:
//      1. "Welcome home, <name>!"                                      (the old screen's first caption)
//      2. how JellyCoins work (the old screen's second caption, word for word)
//      3. seven coach marks that point at the real HUD controls: the heart (care), the Jelmiko (cuddle), the coins pill, the bag, Go out, the mic, Settings.
//  Settings > Watch the opening replays it (the captions and the coach marks; nobody runs in, nothing is written to the save).
//
//  Holding the game: while the tour is armed or up, `GameCare.introHold` is true. Needs stop draining and the need bubbles stay out (GameCare.tickNeeds); the full-screen overlay
//  takes every touch, so nothing can be fed, called or opened. The meal code is not touched: a meal can only start from the player's own tap.
//  Reduce Motion: no run-in and no hop, the Jelmiko is simply there; plain fades. VoiceOver: the overlay is modal; focus moves to each step's text.
//

import SwiftUI
import Observation

/// Which first-day moment a new game gets. One line switches it back to the old illustrated card.
enum FirstDayStyle {
    case room, card
    static let defaultStyle: FirstDayStyle = .room
    /// `-FirstDayStyle room|card` forces either (developer builds and the simulator only).
    static var current: FirstDayStyle {
        if DevArgs.enabled, let s = UserDefaults.standard.string(forKey: "FirstDayStyle") {
            if s == "card" { return .card }
            if s == "room" { return .room }
        }
        return defaultStyle
    }
}

/// The real controls the coach marks point at. `jelmiko` is the Jelmiko himself (projected from the room), the rest are HUD views that report their frame.
enum FirstDayTarget: String, CaseIterable, Hashable {
    case care, jelmiko, coins, bag, goOut, mic, settings
}

enum FirstDayStep: Hashable {
    case arrive                       // the run-in: no caption, only Skip
    case welcome                      // "Welcome home, <name>!"
    case jellyCoins                   // how JellyCoins work
    case coach(FirstDayTarget)
}

@MainActor @Observable
final class FirstDayTour {
    static let shared = FirstDayTour()
    nonisolated static let doneKey = "Jelbies.firstDayTour.done.v1"          // set when a new game's tour has finished or been skipped (a wipe clears it with the rest)

    /// The old screen's captions, word for word.
    static func welcomeLine(_ name: String) -> String { "Welcome home, \(name)!" }
    static let coinsLine = "Take good care of them, earn JellyCoins around town, and one day you can adopt another friend from the Spring."
    /// The coach marks, in order, and their one sentence each (kids' reading level, no more than about 12 words).
    static let coachTargets: [FirstDayTarget] = [.care, .jelmiko, .coins, .bag, .goOut, .mic, .settings]
    static func sentence(_ t: FirstDayTarget, tapToTalk: Bool = false) -> String {
        switch t {
        case .care: return "Tap the heart to feed, give water, play or nap."
        case .jelmiko: return "Tap your Jelmiko, then Come here for a cuddle."
        case .coins: return "These are your JellyCoins. Earn more around town."
        case .bag: return "Your bag has clothes, toys and decor."
        case .goOut: return "Go out to the shop, the races and the park."
        case .mic: return tapToTalk ? "Double tap the mic to talk to your Jelmiko." : "Hold the mic and say a word to your Jelmiko."
        case .settings: return "Settings and sound are up here."
        }
    }
    /// The steps of a tour: the run-in first when somebody runs in, then the captions, then the coach marks.
    static func steps(run: Bool) -> [FirstDayStep] {
        (run ? [.arrive] : []) + [.welcome, .jellyCoins] + coachTargets.map { .coach($0) }
    }

    private(set) var steps: [FirstDayStep] = []
    private(set) var index = 0
    /// Armed by StartFlow; the room takes it when it appears (`roomReady`).
    private(set) var armed = false
    /// On screen.
    private(set) var active = false
    private(set) var name = ""
    private(set) var replay = false
    /// Bumped on every step (the overlay moves VoiceOver focus on it).
    private(set) var serial = 0
    /// What the room's first step still has to do for a brand-new first Jelmiko: run him in, or just put him there (Reduce Motion). Taken once (`takeArrival`).
    enum Arrival { case run, place }
    private var arrival: Arrival?
    private var defaults: UserDefaults = .standard

    var step: FirstDayStep? { active && steps.indices.contains(index) ? steps[index] : nil }
    /// True from arming until the tour ends: the game's needs and bubbles wait.
    var holdsGame: Bool { armed || active }
    var isLast: Bool { index == steps.count - 1 }
    var coachCount: Int { Self.coachTargets.count }
    /// 1-based number of the current coach mark (nil on a caption).
    var coachNumber: Int? { if case .coach(let t)? = step { return (Self.coachTargets.firstIndex(of: t) ?? 0) + 1 }; return nil }

    /// A new game's first Jelmiko is home (`replay` false), or Settings > Watch the opening (`replay` true). False = nothing armed (a new game's tour only ever runs once).
    @discardableResult
    func arm(name: String, replay: Bool, reduceMotion: Bool, defaults d: UserDefaults = .standard) -> Bool {
        if !replay, d.bool(forKey: Self.doneKey) { return false }
        defaults = d
        let run = !replay && !reduceMotion
        self.name = name; self.replay = replay
        steps = Self.steps(run: run)
        index = 0; active = false; armed = true
        arrival = replay ? nil : (run ? .run : .place)
        sync()
        return true
    }

    /// The room is on screen: the tour shows (the first step is the run-in when somebody runs in).
    func roomReady() {
        guard armed else { return }
        armed = false; active = true; index = 0; serial += 1
        sync()
    }

    /// GameCare's first step for a brand-new first Jelmiko asks once what to do with him.
    func takeArrival() -> Arrival? { defer { arrival = nil }; return arrival }

    /// The Jelmiko is in the middle of the room and calm: the welcome caption comes up.
    func arrived() {
        guard step == .arrive else { return }
        advance()
    }

    /// Tap anywhere / Next. The run-in is not tappable.
    func next() {
        guard active, step != .arrive else { return }
        advance()
    }

    private func advance() {
        if index + 1 < steps.count { index += 1; serial += 1 } else { finish() }
    }

    func skip() { finish() }

    /// Ends it (finished or skipped). A new game's tour is then done for good; a replay changes nothing.
    func finish() {
        let wasLive = active || armed
        active = false; armed = false; arrival = nil
        if wasLive, !replay { defaults.set(true, forKey: Self.doneKey) }
        sync()
    }

    /// Back to nothing (start over, back to the menu): never leaves the game held.
    func reset() { active = false; armed = false; arrival = nil; steps = []; index = 0; sync() }

    /// Capture aid (`-FirstDayStep <i>`): start on that step.
    func jump(to i: Int) { if steps.indices.contains(i) { index = i; serial += 1 } }

    private func sync() { GameCare.introHold = holdsGame }
}

// MARK: pointing at the real controls

/// A HUD control reports its frame under its target; the overlay resolves it in its own space (landscape, iPad and a Split View window all follow, nothing is hard-coded).
struct FirstDayAnchorKey: PreferenceKey {
    static let defaultValue: [FirstDayTarget: Anchor<CGRect>] = [:]
    static func reduce(value: inout [FirstDayTarget: Anchor<CGRect>], nextValue: () -> [FirstDayTarget: Anchor<CGRect>]) { value.merge(nextValue()) { $1 } }
}

extension View {
    /// Marks this view as a coach-mark target.
    func firstDayTarget(_ t: FirstDayTarget) -> some View {
        anchorPreference(key: FirstDayAnchorKey.self, value: .bounds) { [t: $0] }
    }
}

// MARK: the overlay

struct FirstDayTourOverlay: View {
    let care: GameCare
    let anchors: [FirstDayTarget: Anchor<CGRect>]
    private let tour = FirstDayTour.shared
    @AccessibilityFocusState private var textFocus: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotionEnv
    private var motion: Bool { !(reduceMotionEnv || A11ySettings.shared.reduceMotion) }

    var body: some View {
        if let step = tour.step {
            GeometryReader { geo in
                content(step, geo)
            }
            .ignoresSafeArea()
            .accessibilityAddTraits(.isModal)
            .transition(.opacity)
        }
    }

    private func content(_ step: FirstDayStep, _ geo: GeometryProxy) -> some View {
        let size = geo.size
        let hole = holeRect(step, geo)
        return ZStack {
            if case .coach = step, let hole {
                dim(size: size, hole: hole)
                Color.clear.contentShape(Rectangle()).onTapGesture { tour.next() }.accessibilityHidden(true)
                coachCard(step, size: size, hole: hole)
            } else if step != .arrive {
                Color.clear.contentShape(Rectangle()).onTapGesture { tour.next() }.accessibilityHidden(true)
                captionCard(step, size: size)
            }
            skipPill(size: size)
        }
        .frame(width: size.width, height: size.height)
        .animation(.easeInOut(duration: 0.25), value: tour.serial)
        .task(id: tour.serial) {
            if step == .arrive {          // never stuck if the arrival is not reported: the welcome comes up anyway
                try? await Task.sleep(nanoseconds: 25_000_000_000)
                if !Task.isCancelled { tour.arrived() }
            }
        }
        .onChange(of: hole == nil) { _, missing in          // a control that is not on screen has nothing to point at: on to the next
            if missing, case .coach = step { tour.next() }
        }
    }

    // MARK: pieces

    private func holeRect(_ step: FirstDayStep, _ geo: GeometryProxy) -> CGRect? {
        guard case .coach(let t) = step else { return nil }
        if t == .jelmiko {
            let mid = care.headWorld - SIMD3(0, BlobShape.H * 0.5, 0)
            guard let p = ThoughtBubbleView.project(mid, size: geo.size, focus: care.focus.blend) else { return nil }
            let d = min(geo.size.width, geo.size.height) * 0.42
            let x = min(max(p.x - d / 2, 8), max(geo.size.width - d - 8, 8)), y = min(max(p.y - d / 2, 8), max(geo.size.height - d - 8, 8))          // (kept on screen: he may stand at an edge)
            return CGRect(x: x, y: y, width: d, height: d)
        }
        guard let a = anchors[t] else { return nil }
        return geo[a].insetBy(dx: -7, dy: -7)
    }

    private func dim(size: CGSize, hole: CGRect) -> some View {
        let radius = abs(hole.width - hole.height) < 4 ? min(hole.width, hole.height) / 2 : min(26, min(hole.width, hole.height) / 2)
        return TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !motion)) { tl in
            let pulse = motion ? 0.5 + 0.5 * sin(tl.date.timeIntervalSinceReferenceDate * 3.2) : 0.5
            Canvas { ctx, sz in
                var p = Path(CGRect(origin: .zero, size: sz))
                p.addRoundedRect(in: hole, cornerSize: CGSize(width: radius, height: radius))
                ctx.fill(p, with: .color(Color(red: 0.16, green: 0.10, blue: 0.08).opacity(0.58)), style: FillStyle(eoFill: true))
                let ring = hole.insetBy(dx: -3 - 3 * pulse, dy: -3 - 3 * pulse)
                ctx.stroke(Path(roundedRect: ring, cornerRadius: radius + 3 + 3 * pulse), with: .color(.white.opacity(0.55 + 0.4 * pulse)), lineWidth: 3)
            }
        }
        .allowsHitTesting(false).accessibilityHidden(true)
    }

    private func jelmikoPoint(_ size: CGSize) -> CGPoint? {
        let mid = care.headWorld - SIMD3(0, BlobShape.H * 0.5, 0)
        return ThoughtBubbleView.project(mid, size: size, focus: care.focus.blend)
    }

    private func cardWidth(_ size: CGSize) -> CGFloat { min(size.width - 32, 340) }

    private func coachCard(_ step: FirstDayStep, size: CGSize, hole: CGRect) -> some View {
        guard case .coach(let t) = step else { return AnyView(EmptyView()) }
        let w = cardWidth(size)
        let cardH: CGFloat = 132, safeTop = Self.topInset + 58
        let roomAbove = hole.minY - 20 - safeTop, roomBelow = size.height - hole.maxY - 20 - 12
        // above or below the control when it fits (a pointer shows which one); else beside it (a Jelmiko in the middle of a short landscape screen)
        let placement: Int = {          // 0 above, 1 below, 2 beside
            let preferAbove = hole.midY > size.height / 2
            if preferAbove, roomAbove >= cardH { return 0 }
            if !preferAbove, roomBelow >= cardH { return 1 }
            if roomAbove >= cardH { return 0 }
            if roomBelow >= cardH { return 1 }
            return 2
        }()
        let above = placement == 0
        var x = placement == 2 ? (hole.midX < size.width / 2 ? min(hole.maxX + 16, size.width - w - 16) : max(hole.minX - 16 - w, 16))
                               : min(max(hole.midX - w / 2, 16), size.width - w - 16)
        // never over the Jelmiko (he wanders): if the card would sit on him, try the screen's left and right edges and the control's side
        if t != .jelmiko, placement != 2, let j = jelmikoPoint(size) {
            let top = above ? hole.minY - 20 - cardH : hole.maxY + 20
            func hitsHim(_ cx: CGFloat) -> Bool { CGRect(x: cx - 8, y: top - 8, width: w + 16, height: cardH + 16).insetBy(dx: -40, dy: -50).contains(j) }
            if hitsHim(x) {
                let tries = [16, size.width - w - 16, hole.midX - w / 2].map { min(max($0, 16), size.width - w - 16) }
                if let ok = tries.first(where: { !hitsHim($0) }) { x = ok }
            }
        }
        let text = FirstDayTour.sentence(t, tapToTalk: VoiceCoordinator.tapMode)
        let card = VStack(alignment: .leading, spacing: 12) {
            Text(text)
                .font(SK.font(19, .heavy)).foregroundStyle(SK.ink)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
                .accessibilityFocused($textFocus)
            HStack {
                Text("\(tour.coachNumber ?? 1) of \(tour.coachCount)").font(SK.font(14, .bold)).foregroundStyle(SK.muted)
                Spacer()
                nextButton
            }
        }
        .padding(16)
        .frame(width: w, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(SK.cream).shadow(color: Color(hex: 0x5A3A2A).opacity(0.3), radius: 10, y: 4))
        .overlay(alignment: above ? .bottomLeading : .topLeading) {
            if placement != 2 {
                Triangle(up: !above).fill(SK.cream)
                    .frame(width: 22, height: 12)
                    .offset(x: min(max(hole.midX - x - 11, 22), w - 44), y: above ? 11 : -11)
            }
        }
        .id(tour.serial)
        .onAppear { focusSoon() }
        return AnyView(
            Group {
                switch placement {
                case 0:
                    VStack { Spacer(minLength: 0); card.padding(.leading, x) }
                        .frame(width: size.width, height: max(hole.minY - 20, 0), alignment: .bottomLeading)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                case 1:
                    card.padding(.leading, x).padding(.top, hole.maxY + 20)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                default:
                    card.padding(.leading, x).padding(.top, min(max(hole.midY - cardH / 2, safeTop), max(size.height - cardH - 12, safeTop)))
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }
            }
        )
    }

    private func captionCard(_ step: FirstDayStep, size: CGSize) -> AnyView {
        let welcome = step == .welcome
        let text = welcome ? FirstDayTour.welcomeLine(tour.name) : FirstDayTour.coinsLine
        let landscape = size.width > size.height * 1.2
        let w = landscape ? min(size.width * 0.4, welcome ? 330 : 360) : min(size.width - 32, welcome ? 420 : 360)
        // a short wide screen: the card stands on the side away from the Jelmiko (he wanders), never over him
        let mid = care.headWorld - SIMD3(0, BlobShape.H * 0.5, 0)
        let jx = ThoughtBubbleView.project(mid, size: size, focus: care.focus.blend)?.x ?? size.width / 2
        let leading: CGFloat = jx < size.width / 2 ? size.width - w - 96 : 110
        let card = VStack(spacing: 12) {
            Text(text)
                .font(SK.font(welcome ? 28 : 19, welcome ? .black : .heavy)).foregroundStyle(SK.ink)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
                .accessibilityFocused($textFocus)
            nextButton
        }
        .padding(.horizontal, 20).padding(.vertical, 16)
        .frame(maxWidth: w)
        .background(RoundedRectangle(cornerRadius: 26, style: .continuous).fill(SK.cream).shadow(color: Color(hex: 0x5A3A2A).opacity(0.3), radius: 10, y: 4))
        .id(tour.serial)
        .onAppear { focusSoon() }
        if landscape {
            return AnyView(card.padding(.leading, leading).padding(.top, Self.topInset + 62).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading))
        }
        return AnyView(card
            .padding(.top, Self.topInset + 62)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top))
    }

    private var nextButton: some View {
        Button { tour.next() } label: {
            Text(tour.isLast ? "Let's play!" : "Next").font(SK.font(17, .heavy)).foregroundStyle(.white)
                .padding(.horizontal, 22).frame(minHeight: 44)
                .background(Capsule().fill(SK.pinkStrong))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(tour.isLast ? "Let's play" : "Next").accessibilityIdentifier("first-day-next")
    }

    /// Skip: the old screen's pill, kept in view on every step. Top centre (the corners hold the gear, the coins and the roster the coach marks point at).
    private func skipPill(size: CGSize) -> some View {
        Color.clear.allowsHitTesting(false).frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay(alignment: .top) { skipButton.padding(.top, max(Self.topInset, 14) + 6) }
    }

    private var skipButton: some View {
        Button { tour.skip() } label: {
            HStack(spacing: 5) {
                Text("Skip").font(SK.font(17, .heavy))
                Image(systemName: "forward.fill").font(.system(size: 12, weight: .bold))
            }
            .foregroundStyle(SK.ink)
            .padding(.horizontal, 16).frame(minWidth: 72, minHeight: 44)
            .background(Capsule().fill(Color.white.opacity(0.92)).shadow(color: Color(hex: 0x5A3A2A).opacity(0.25), radius: 6, y: 2))
            .overlay(Capsule().strokeBorder(Color.white.opacity(0.9), lineWidth: 1.2))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Skip").accessibilityHint("Skips the welcome").accessibilityIdentifier("first-day-skip")
    }

    private func focusSoon() {
        guard UIAccessibility.isVoiceOverRunning else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { textFocus = true }
    }

    static var topInset: CGFloat {
        (UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap(\.windows).first { $0.isKeyWindow })?.safeAreaInsets.top ?? 0
    }
}

/// A small pointer: the tip points up (`up`) or down.
private struct Triangle: SwiftUI.Shape {
    let up: Bool
    func path(in r: CGRect) -> Path {
        var p = Path()
        if up { p.move(to: CGPoint(x: r.minX, y: r.maxY)); p.addLine(to: CGPoint(x: r.midX, y: r.minY)); p.addLine(to: CGPoint(x: r.maxX, y: r.maxY)) }
        else { p.move(to: CGPoint(x: r.minX, y: r.minY)); p.addLine(to: CGPoint(x: r.midX, y: r.maxY)); p.addLine(to: CGPoint(x: r.maxX, y: r.minY)) }
        p.closeSubpath()
        return p
    }
}
