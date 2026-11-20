//
//  ShowChrome.swift
//  The Jelly Show's screen furniture over the 3D stage (the mockups ShowLook / ShowDance / ShowTrick / ShowResults.dc.html): the round header
//  with its three pips, the Look round's judged walk-on and score card, the Dance round's Cheer meter, prompt lane, flash and foot buttons,
//  the Trick round's turn chips, meters, Glow Burst and trick menu, the results' podium, stacked bars, Drops, cup, stickers and
//  tip, the Studio drill's card, and the white fade. Portrait stacks under the Jelbie; a phone on its side puts the cards beside him.
//

import SwiftUI
import simd

struct ShowChrome: View {
    let care: GameCare
    private var show: ShowFlow { care.show }
    @Environment(\.verticalSizeClass) private var vsc
    private var compact: Bool { vsc == .compact }

    var body: some View {
        let _ = show.revision          // the rules live in the unobserved sim: every step of the show bumps this
        return ZStack {
            if show.onStage {
                switch show.round {
                case .look: LookRound(care: care)
                case .dance: DanceRound(care: care)
                case .trick: TrickRound(care: care)
                case .results: if show.trickStage != .pick { TrickRound(care: care) } else { ResultsScreen(care: care) }          // (the last turn's rivals still perform)
                }
            }
            ForfeitHomeCard(care: care)
            Color.white.opacity(Double(show.wipe)).ignoresSafeArea().allowsHitTesting(false)
        }
        .allowsHitTesting(show.active)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(show.active ? "show-screen" : "")
    }
}

// MARK: - shared

/// Where a stage spot lands on the screen (the show camera's projection), for the ring and the chips round the Jelbie.
enum StageProject {
    static func point(_ spot: SIMD2<Float>, y: Float, frame: ShowFrame, size: CGSize) -> CGPoint {
        let cam = GameCamera.camera(aspect: Float(size.width / max(size.height, 1)), show: 1, showFrame: frame)
        let c = cam.viewProj * SIMD4<Float>(spot.x, y, spot.y, 1)
        guard c.w > 1e-4 else { return CGPoint(x: size.width / 2, y: size.height / 2) }
        return CGPoint(x: CGFloat(c.x / c.w * 0.5 + 0.5) * size.width, y: CGFloat(1 - (c.y / c.w * 0.5 + 0.5)) * size.height)
    }
    /// The Jelbie's middle and his half width on screen.
    static func body(_ spot: SIMD2<Float>, frame: ShowFrame, size: CGSize) -> (centre: CGPoint, radius: CGFloat) {
        let c = point(spot, y: BobShape.H * 0.5, frame: frame, size: size)
        let r = point(SIMD2(spot.x + BobShape.R, spot.y), y: BobShape.H * 0.5, frame: frame, size: size)
        return (c, abs(r.x - c.x))
    }
}

struct RoundHeader: View {
    let care: GameCare
    var round: Int
    var title: String
    var kicker: String? = nil
    /// The Trick round counts TURNS, not rounds: how many are used and which one is up (nil = the pips count rounds).
    var turns: TurnPips? = nil
    var body: some View {
        let show = care.show
        HStack(spacing: 10) {
            if show.canForfeit { ForfeitHomePill(care: care) }          // (every round: the Home pill, then the "Go home?" card)
            VStack(alignment: .leading, spacing: 0) {
                Text(kicker ?? "ROUND \(round) OF 3 \u{00B7} \(show.rank.title.uppercased())").font(SK.font(12, .black)).foregroundStyle(ShowUI.gold).tracking(0.5)
                Text(title).font(SK.font(24, .black)).foregroundStyle(SK.cream)
            }
            .accessibilityElement(children: .combine).accessibilityIdentifier("show-round")
            Spacer()
            HStack(spacing: 6) {
                if let t = turns { TurnPipRow(pips: t) }
                else { ForEach(1...3, id: \.self) { k in Capsule().fill(k <= round ? ShowUI.gold : ShowUI.platform).frame(width: 26, height: 8) } }
            }
            .accessibilityLabel(turns.map { "Round \(round) of 3, turn \(min($0.current, 2) + 1) of 3" } ?? "Round \(round) of 3")
        }
    }
}

/// The Trick round's pips: `used` turns are over (gold), `current` is the one up now (outlined), the rest are still to come.
struct TurnPips: Equatable {
    var used: Int
    var current: Int
    var kicker: String { "ROUND 3 OF 3 \u{00B7} TURN \(min(current, 2) + 1) OF 3" }
}
struct TurnPipRow: View {
    var pips: TurnPips
    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<3, id: \.self) { k in
                Capsule().fill(k < pips.used ? ShowUI.gold : ShowUI.platform).frame(width: 26, height: 8)
                    .overlay(Capsule().strokeBorder(ShowUI.gold, lineWidth: 2).opacity(k == pips.current && k >= pips.used ? 1 : 0))
            }
        }
    }
}

/// A line over the stage: the theme or a hint.
struct StagePill: View {
    var text: String
    var scale: CGFloat = 1          // iPad: larger
    var body: some View {
        Text(text).font(SK.font(14 * scale, .black)).foregroundStyle(ShowUI.brownGold).lineLimit(1).minimumScaleFactor(0.7)
            .padding(.horizontal, 14).padding(.vertical, 6).background(Capsule().fill(ShowUI.light.opacity(0.95)))
    }
}

/// The cream card every round's numbers sit in.
struct ShowCard<Content: View>: View {
    var padding: CGFloat = 12
    @ViewBuilder var content: () -> Content
    var body: some View {
        content().padding(padding).frame(maxWidth: .infinity)
            .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(SK.cream.opacity(0.96)).shadow(color: .black.opacity(0.18), radius: 6, y: 3))
    }
}

/// The rivals without a borrowed body: silhouette cards on a side podium at the back of the stage.
struct RivalPodium: View {
    let care: GameCare
    var body: some View {
        let s = care.show.sim
        let missing = (s?.rivals ?? []).indices.filter { !care.showRivalsWithBodies.contains($0) }
        if !missing.isEmpty, let s {
            HStack(spacing: 14) {
                ForEach(missing, id: \.self) { i in
                    VStack(spacing: 2) {
                        RivalBlob(tint: s.rivals[i].tint, size: 46)
                        Text(s.rivals[i].name).font(SK.font(12, .black)).foregroundStyle(ShowUI.mist).lineLimit(1)
                    }
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(.black.opacity(0.22)))
                    .accessibilityElement(children: .combine).accessibilityLabel("\(s.rivals[i].name) on the side podium")
                }
            }
            .accessibilityIdentifier("show-podium-rivals")
        }
    }
}

// MARK: - Look

struct LookRound: View {
    let care: GameCare
    @Environment(\.verticalSizeClass) private var vsc
    private var compact: Bool { vsc == .compact }
    private var show: ShowFlow { care.show }

    /// A judged walk-on: he stands in the spotlight in what he wore into the Studio, the judges score it, and the show moves on by itself.
    var body: some View {
        let _ = show.revision
        return GeometryReader { g in
            let size = g.size
            VStack(spacing: 0) {
                RoundHeader(care: care, round: 1, title: "Look", kicker: "ROUND 1 OF 3")
                HStack { if !compact { Spacer() }; ThemePill(tag: show.theme.main, scale: PadLayout.isPad ? 1.2 : 1); Spacer() }.padding(.top, compact ? 10 : 20)
                Spacer(minLength: 0)
                if compact {
                    HStack(alignment: .bottom, spacing: 12) {
                        Spacer(minLength: 0)
                        VStack(spacing: 8) { score; cta }.frame(width: min(size.width * 0.52, 520))
                    }
                } else {
                    score
                    cta.padding(.top, 20)
                }
            }
            .padding(.horizontal, 16).padding(.top, 0).padding(.bottom, PadLayout.isPad ? 14 : 4)
        }
    }

    private var score: some View {
        let s = show.sim
        let parts = s?.lookParts ?? (outfit: 0, stats: 0, glow: 0)
        let total = Int((s?.lookScore ?? 0).rounded())
        let d: CGFloat = compact ? 84 : 104
        return ShowCard(padding: compact ? 12 : 16) {
            HStack(spacing: compact ? 14 : 16) {
                VStack(spacing: 0) {
                    Text("\(total)").font(SK.font(compact ? 32 : 40, .black)).foregroundStyle(SK.ink).monospacedDigit().contentTransition(.numericText())
                    Text("Look").font(SK.font(12, .black)).foregroundStyle(ShowUI.brownGold)
                }
                .frame(width: d, height: d).background(Circle().fill(ShowUI.gold)).overlay(Circle().strokeBorder(ShowUI.goldDeep, lineWidth: 4))
                .accessibilityElement(children: .combine).accessibilityLabel("Look \(total)").accessibilityIdentifier("look-score")
                VStack(spacing: compact ? 8 : 13) {
                    part("Outfit", parts.outfit, 40, SK.honeyDeep)
                    part(show.theme.main.title, parts.stats, 40, ShowUI.tag(show.theme.main))
                    part("Glow", parts.glow, 20, SK.sky)
                }
            }
        }
        .animation(.easeOut(duration: 0.3), value: total)
    }
    private func part(_ name: String, _ v: Float, _ max: Float, _ c: Color) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(name).font(SK.font(16, .black)).foregroundStyle(SK.ink).lineLimit(1)
            GeometryReader { g in ZStack(alignment: .leading) { Capsule().fill(ShowUI.bar); Capsule().fill(c).frame(width: Swift.max(4, g.size.width * CGFloat(Swift.min(v / max, 1)))) } }.frame(height: 12)
        }
        .accessibilityElement(children: .combine).accessibilityLabel("\(name) \(Int(v.rounded())) of \(Int(max))")
    }

    private var cta: some View {
        ShowCTA(title: "Next: Dance", symbol: nil, id: "look-next", height: compact ? 50 : 60) { show.finishLook() }
    }
}

// MARK: - Dance

struct DanceRound: View {
    let care: GameCare
    @Environment(\.verticalSizeClass) private var vsc
    private var compact: Bool { vsc == .compact }
    private var show: ShowFlow { care.show }
    private let light = UIImpactFeedbackGenerator(style: .light)
    private var done: Bool { show.beat == .danced }

    // The trimmed Dance screen (boards dance_count / dance_mid / dance_done / land_dance): one dancer, one thin Cheer strip, the flash in its own slot, the lane with the
    // count inside it, a song-progress line, the two foot buttons; after the song one card (score, cheer word, Perfect / Good / Slip once) and "Next: Trick".
    var body: some View {
        Group {
            if compact { landscape } else { portrait }
        }
        .animation(CareMenu.spring, value: show.beat)
    }

    /// Portrait (and iPad): header, then from the bottom up the buttons, the progress line, the lane, the flash slot and the Cheer strip.
    private var portrait: some View {
        VStack(spacing: 0) {
            RoundHeader(care: care, round: 2, title: "Dance", kicker: kicker)
            Spacer(minLength: 0)
            cheer.padding(.bottom, done ? 12 : 6)
            if done {
                doneCard.padding(.bottom, 16)
                next
            } else {
                Group {          // (these leave at once when the song ends: the score card never shares the screen with them)
                    flash.frame(height: 46).padding(.bottom, 6)
                    laneWithCount
                    progress.padding(.top, 10)
                    DanceFeet(live: show.buttonsLive, side: nil, press: press).frame(height: 148).padding(.top, 12)
                }
                .transition(.identity)
            }
        }
        .padding(.horizontal, 16).padding(.bottom, PadLayout.isPad ? 14 : 0)
    }

    /// Landscape: the dancer stays clear. Cheer strip top right with the flash under it; the lane and progress line between two foot buttons in the bottom corners;
    /// after the song the card and "Next: Trick" take that band.
    private var landscape: some View {
        ZStack(alignment: .top) {
            VStack(spacing: 0) {
                RoundHeader(care: care, round: 2, title: "Dance", kicker: kicker).padding(.top, 14)
                HStack {
                    Spacer(minLength: 0)
                    VStack(spacing: 6) {
                        cheer
                        if !done { flash.frame(height: 46) }
                    }
                    .frame(width: 312)
                }
                .padding(.top, 4)
                Spacer(minLength: 0)
                if done {
                    HStack(alignment: .bottom, spacing: 12) {
                        doneCard
                        next.frame(width: 250)
                    }
                    .padding(.bottom, 4)
                } else {
                    HStack(alignment: .bottom, spacing: 12) {
                        DanceFeet(live: show.buttonsLive, side: 0, press: press).frame(width: 152, height: 146)
                        VStack(spacing: 6) { progress; laneWithCount }
                        DanceFeet(live: show.buttonsLive, side: 1, press: press).frame(width: 152, height: 146)
                    }
                    .transition(.identity)
                }
            }
            .padding(.horizontal, 0).padding(.bottom, 0)
        }
    }

    private var kicker: String { "ROUND 2 OF 3" }

    private func press(_ foot: Int) { light.impactOccurred(intensity: 0.5); show.tap(foot: foot) }

    // MARK: Cheer, flash, lane, progress

    private var cheer: some View {
        let c = show.sim?.cheer ?? 0
        return CheerStrip(value: c, tick: ShowScoring.burstCheer)
            .accessibilityElement(children: .combine).accessibilityLabel("Cheer \(Int((c * 100).rounded())) percent").accessibilityIdentifier("dance-cheer")
    }

    /// "Perfect!" / "Good" / "Slip": its own slot above the lane; the old word goes at once, the new one scales in.
    private var flash: some View {
        Group {
            switch show.flash {
            case .perfect?: Text("Perfect!").foregroundStyle(ShowUI.gold)
            case .good?: Text("Good").foregroundStyle(.white)
            case .miss?: Text("Slip").foregroundStyle(ShowUI.mist)
            case nil: Text(" ")
            }
        }
        .font(SK.font(30, .black)).shadow(color: .black.opacity(0.4), radius: 4, y: 2)
        .id(show.flashSerial).transition(.asymmetric(insertion: .scale(scale: 1.4).combined(with: .opacity), removal: .identity))
        .frame(maxWidth: .infinity).frame(height: 46)
        .animation(.easeOut(duration: 0.12), value: show.flashSerial)
        .allowsHitTesting(false)
        .accessibilityIdentifier("dance-flash")
    }

    /// The lane; the 3-2-1 and GO! sit inside it (it is empty until the first step comes).
    private var laneWithCount: some View {
        PromptLane(care: care).accessibilityIdentifier("dance-prompts")
            .overlay {
                // a TimelineView: `showsGo` depends on the dance clock, which the observation system does not track, so the word is re-evaluated every frame (else it stays until some other state changes)
                TimelineView(.animation(minimumInterval: 1.0 / 30)) { _ in
                    ZStack {
                        if show.showsCountdown { count("\(show.countdown)") }
                        else if show.showsGo { count("GO!") }
                    }
                }
            }
    }
    private func count(_ s: String) -> some View {
        Text(s).font(.system(size: 84, weight: .heavy, design: .rounded)).foregroundStyle(.white).minimumScaleFactor(0.5).lineLimit(1)
            .shadow(color: SK.pink.opacity(0.9), radius: 0, x: 0, y: 3).shadow(color: .black.opacity(0.35), radius: 6, y: 3)
            .id(show.cueSerial).transition(.asymmetric(insertion: .scale(scale: 1.6).combined(with: .opacity), removal: .identity)).allowsHitTesting(false)          // (the old number goes at once: never two words in the lane)
            .accessibilityIdentifier("show-count")
    }

    /// A thin line under the lane: how far into the song (no count of steps, so it is right for any pattern); VoiceOver gets the steps as its value.
    private var progress: some View {
        let d = show.sim?.dance
        return TimelineView(.animation(minimumInterval: 1.0 / 30)) { _ in
            let f = CGFloat(show.danceProgress)
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(ShowUI.platform)
                    Capsule().fill(ShowUI.gold).frame(width: g.size.width * f)
                }
            }
            .frame(height: 6)
        }
        .padding(.horizontal, PadLayout.isPad ? 0 : (compact ? 0 : 24))
        .accessibilityElement().accessibilityLabel("Song progress").accessibilityValue("\(min((d?.judged ?? 0) + 1, show.dancePromptTotal)) of \(show.dancePromptTotal)")
        .accessibilityIdentifier("dance-progress")
    }

    // MARK: after the song

    private var doneCard: some View {
        let s = show.sim?.danceScore ?? 0
        let d = show.sim?.dance
        let circle = VStack(spacing: 0) {
            Text("\(Int(s.rounded()))").font(SK.font(compact ? 28 : 40, .black)).foregroundStyle(SK.ink).monospacedDigit()
            Text("Dance").font(SK.font(compact ? 10 : 13, .black)).foregroundStyle(ShowUI.brownGold)
        }
        .frame(width: compact ? 64 : 95, height: compact ? 64 : 95).background(Circle().fill(ShowUI.gold)).overlay(Circle().strokeBorder(ShowUI.goldDeep, lineWidth: 4))
        .accessibilityIdentifier("dance-score")
        let word = Text(ShowFlow.danceCheerWord(score: s)).font(SK.font(compact ? 22 : 30, .black)).foregroundStyle(SK.ink).jLine(2, scale: 0.7)
        let tallies = HStack(spacing: 8) {
            tally("Perfect \(d?.perfects ?? 0)", bg: Color(hex: 0xE3F4DD), fg: Color(hex: 0x2E6B26))
            tally("Good \(d?.goods ?? 0)", bg: Color(hex: 0xFFE7A8), fg: ShowUI.brownGold)
            tally("Slip \(d?.misses ?? 0)", bg: Color(hex: 0xF2ECE6), fg: SK.muted)
        }
        .accessibilityElement(children: .combine).accessibilityIdentifier("dance-stats")
        return ShowCard(padding: compact ? 8 : 16) {
            if compact {
                // landscape: one low row (the band under the dancer's feet, between where the foot buttons were)
                HStack(spacing: 14) { circle; VStack(alignment: .leading, spacing: 6) { word; tallies } }
            } else {
                VStack(spacing: 14) { HStack(spacing: 18) { circle; word }; tallies }
            }
        }
        .transition(.scale(scale: 0.9).combined(with: .opacity))
    }
    private func tally(_ s: String, bg: Color, fg: Color) -> some View {
        Text(s).font(SK.font(compact ? 13 : 16, .black)).foregroundStyle(fg).monospacedDigit().padding(.horizontal, 12).padding(.vertical, 6).background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(bg))
    }

    private var next: some View {
        ShowCTA(title: "Next: Trick", id: "dance-next", height: compact ? 52 : 60) { show.finishDance() }
            .transition(.scale(scale: 0.9).combined(with: .opacity))
    }
}

/// The one thin Cheer strip: the word, a bar with the Glow Burst mark (an ink tick and a small sparkle) at 75%; the bar turns gold once the mark is passed. No number, no sentence.
struct CheerStrip: View {
    var value: Float
    var tick: Float
    var body: some View {
        HStack(spacing: 12) {
            Text("Cheer").font(SK.font(16, .black)).foregroundStyle(SK.ink)
            GeometryReader { g in
                let w = g.size.width, h = g.size.height
                ZStack(alignment: .leading) {
                    Capsule().fill(ShowUI.bar)
                    Capsule().fill(value >= tick ? ShowUI.gold : SK.pink).frame(width: max(0, w * CGFloat(min(max(value, 0), 1))))
                    RoundedRectangle(cornerRadius: 2).fill(SK.ink).frame(width: 3, height: 24).offset(x: w * CGFloat(tick) - 1.5, y: 0)
                    CheerSparkle().fill(SK.cream).overlay(CheerSparkle().stroke(SK.ink, lineWidth: 1.4)).frame(width: 22, height: 22)
                        .offset(x: w * CGFloat(tick) + 12, y: -(h / 2) - 4)
                }
                .frame(height: h)
            }
            .frame(height: 14)
            .animation(.easeOut(duration: 0.25), value: value)
        }
        .padding(.horizontal, 16).frame(height: 46).frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 23, style: .continuous).fill(SK.cream.opacity(0.96)).shadow(color: .black.opacity(0.18), radius: 6, y: 3))
    }
}

/// The four-point sparkle of the boards (24 x 24 viewBox).
struct CheerSparkle: SwiftUI.Shape {
    func path(in r: CGRect) -> Path {
        let k = r.width / 24
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: r.minX + x * k, y: r.minY + y * k) }
        var s = Path()
        s.move(to: p(12, 1.5))
        s.addCurve(to: p(22.5, 12), control1: p(12.8, 7.1), control2: p(16.9, 11.2 + 0))
        s.addCurve(to: p(12, 22.5), control1: p(16.9, 12.8), control2: p(12.8, 16.9))
        s.addCurve(to: p(1.5, 12), control1: p(11.2, 16.9), control2: p(7.1, 12.8))
        s.addCurve(to: p(12, 1.5), control1: p(7.1, 11.2), control2: p(11.2, 7.1))
        s.closeSubpath()
        return s
    }
}

/// Left / Right with the feet in the steps' colours (sky = L, pink = R). `side` nil = both in a row (portrait); 0 / 1 = one corner button (landscape). The one-button and
/// auto assists keep their own buttons.
struct DanceFeet: View {
    let live: Bool
    let side: Int?
    let press: (Int) -> Void
    var body: some View {
        switch A11ySettings.shared.raceAssist {
        case .oneButton, .auto:
            if let side { AssistFoot(side: side, prefix: "show", live: live, press: press) } else { AssistFeetRow(prefix: "show", live: live, press: press) }
        default:
            if let side { DanceFootButton(foot: side, live: live, press: press) }
            else { HStack(spacing: 14) { DanceFootButton(foot: 0, live: live, press: press); DanceFootButton(foot: 1, live: live, press: press) } }
        }
    }
}

struct DanceFootButton: View {
    let foot: Int
    let live: Bool
    let press: (Int) -> Void
    @State private var down = false
    private var color: Color { foot == 0 ? SK.sky : SK.pink }
    private var plate: some View {
        let fill: Color = down ? FocusStyle.pink.opacity(0.55) : SK.cream
        let shadow: Color = Color.black.opacity(down ? 0.12 : 0.28)
        return RoundedRectangle(cornerRadius: 36, style: .continuous).fill(fill).shadow(color: shadow, radius: down ? 4 : 6, y: down ? 1 : 3)
    }
    var body: some View {
        VStack(spacing: 4) {
            Footprints().fill(color).frame(width: 58, height: 50)
            Text(foot == 0 ? "Left" : "Right").font(SK.font(26, .black)).foregroundStyle(SK.ink)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(plate)
        .overlay(RoundedRectangle(cornerRadius: 36, style: .continuous).strokeBorder(Color.white.opacity(0.55), lineWidth: 1.5))
        .scaleEffect(down ? 0.96 : 1).opacity(live ? 1 : 0.55)
        .animation(.easeOut(duration: 0.08), value: down)
        .contentShape(RoundedRectangle(cornerRadius: 36, style: .continuous))
        .gesture(DragGesture(minimumDistance: 0).onChanged { _ in if !down { down = true; press(foot) } }.onEnded { _ in down = false })      // fires on touch DOWN
        .background { Button("") { press(foot) }.keyboardShortcut(foot == 0 ? .leftArrow : .rightArrow, modifiers: []).frame(width: 0, height: 0).opacity(0).accessibilityHidden(true) }
        .accessibilityElement().accessibilityLabel("\(foot == 0 ? "Left" : "Right") foot").accessibilityValue(live ? "" : "waiting")
        .accessibilityIdentifier(foot == 0 ? "show-left" : "show-right").accessibilityAddTraits(.isButton).accessibilityAction { press(foot) }
    }
}

/// The footprint of the boards: heel and toe pads of two feet in a 58 x 50 box.
struct Footprints: SwiftUI.Shape {
    func path(in r: CGRect) -> Path {
        let kx = r.width / 58, ky = r.height / 50
        var p = Path()
        func e(_ cx: CGFloat, _ cy: CGFloat, _ rx: CGFloat, _ ry: CGFloat, rot: Double = 0) {
            var q = Path(ellipseIn: CGRect(x: -rx, y: -ry, width: 2 * rx, height: 2 * ry))
            q = q.applying(CGAffineTransform(rotationAngle: CGFloat(rot * .pi / 180)).concatenating(CGAffineTransform(translationX: cx, y: cy)))
            p.addPath(q.applying(CGAffineTransform(scaleX: kx, y: ky)).applying(CGAffineTransform(translationX: r.minX, y: r.minY)))
        }
        e(17, 16, 10, 14); e(17, 38, 7, 6); e(41, 20, 10, 14, rot: 8); e(42, 42, 7, 6)
        return p
    }
}

/// The Cheer / Glow meter: a bar with a threshold tick and its label.
struct CheerMeter: View {
    var value: Float
    var tick: Float
    var color: Color
    var label: String
    var body: some View {
        VStack(spacing: PadLayout.isPad ? 7 : 2) {
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(ShowUI.bar)
                    Capsule().fill(color).frame(width: max(0, g.size.width * CGFloat(min(max(value, 0), 1))))
                    RoundedRectangle(cornerRadius: 2).fill(SK.ink).frame(width: 3, height: g.size.height + 8).offset(x: g.size.width * CGFloat(tick) - 1.5)
                }
            }
            .frame(height: 16)
            .animation(.easeOut(duration: 0.25), value: value)
            GeometryReader { g in
                Text(label).font(SK.font(11, .black)).foregroundStyle(ShowUI.brownGold).fixedSize()
                    .position(x: min(max(g.size.width * CGFloat(tick), 70), g.size.width - 70), y: 8)
            }
            .frame(height: 16)
        }
    }
}

/// The L / R prompts scrolling toward the ring, on the music's clock. 96 pt per beat, chips 40 pt and only the NEXT step grows to 52 pt (a half-beat double is 48 pt
/// apart against 46 pt of radii, so two chips never touch, also at the ring); a rest is simply a gap.
struct PromptLane: View {
    let care: GameCare
    static let pointsPerBeat: CGFloat = 96
    var body: some View {
        let show = care.show
        TimelineView(.animation(minimumInterval: 1.0 / 60)) { _ in
            let song = show.danceNow()
            let items = show.sim?.dance?.visible(at: song) ?? []
            let next = items.map(\.prompt.index).min()
            ZStack(alignment: .leading) {
                Capsule().fill(Color(red: 0.08, green: 0.05, blue: 0.13).opacity(0.6))
                Circle().strokeBorder(Color(hex: 0xFFF6EC), lineWidth: 4).frame(width: 60, height: 60).padding(.leading, 14)
                ForEach(items, id: \.prompt.index) { it in
                    let big = it.prompt.index == next
                    let size: CGFloat = big ? 52 : 40
                    Text(it.prompt.foot == 0 ? "L" : "R").font(SK.font(big ? 22 : 17, .black)).foregroundStyle(.white)
                        .frame(width: size, height: size)
                        .background(Circle().fill(it.prompt.foot == 0 ? SK.sky : SK.pink))
                        .opacity(max(0.4, 1 - 0.13 * max(it.ahead, 0)))
                        .offset(x: 14 + 30 - size / 2 + CGFloat(max(it.ahead, -0.3)) * Self.pointsPerBeat)
                }
            }
            .frame(height: 84)
            .clipShape(Capsule())
        }
        .accessibilityElement().accessibilityLabel("Prompts")
    }
}

// MARK: - Trick

struct TrickRound: View {
    let care: GameCare
    @Environment(\.verticalSizeClass) private var vsc
    private var compact: Bool { vsc == .compact }
    private var show: ShowFlow { care.show }
    /// iPad only: the chips, cards and the trick menu are drawn ~1.35x; 1 on iPhone.
    private var sc: CGFloat { PadLayout.isPad ? 1.35 : 1 }

    var body: some View {
        let _ = show.revision
        return GeometryReader { g in
            let size = g.size
            let full = CGSize(width: size.width + g.safeAreaInsets.leading + g.safeAreaInsets.trailing, height: size.height + g.safeAreaInsets.top + g.safeAreaInsets.bottom)
            let body = StageProject.body(ShowStage.playerSpot, frame: show.frame, size: size)
            ZStack(alignment: .top) {
                if show.burstFlash > 0 { Confetti(serial: show.burstFlash, at: body.centre).allowsHitTesting(false) }
                if compact {
                    // a phone on its side: the performer has the left half (the camera frame), the right column holds the turn chips and, at the bottom, the toast, the scoreboard strip
                    // and the menu (or Skip); the title and the round pips sit at the top left
                    HStack(alignment: .top, spacing: 12) {
                        VStack(alignment: .leading, spacing: 8) {
                            SideHeader(round: 3, title: "Trick", kicker: turnPips.kicker, turns: turnPips)
                            Spacer(minLength: 0)
                        }
                        Spacer(minLength: 0)
                        VStack(spacing: 8) {
                            turns
                            Spacer(minLength: 0)
                            bottomStack(full: full, rowCap: 3, burstHeight: 40)
                        }
                        .frame(width: size.width * 0.5)
                    }
                    .padding(.top, 14).padding(.bottom, 4)
                } else if PadLayout.isPad && size.width > size.height {
                    // iPad landscape: the stage fills the left ~55% (the camera frame puts the Jelmiko there); chips, toast, strip and the menu / Skip are a clear right column
                    VStack(spacing: 8) {
                        RoundHeader(care: care, round: 3, title: "Trick", kicker: turnPips.kicker, turns: turnPips)
                        HStack(alignment: .top, spacing: 24) {
                            Color.clear.frame(width: size.width * 0.55 - 16)
                            VStack(spacing: 10) {
                                turns
                                Spacer(minLength: 0)
                                bottomStack(full: full, rowCap: 6, burstHeight: 48 * sc)
                            }
                            .frame(maxWidth: 560)
                        }
                    }
                    .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 24 + g.safeAreaInsets.bottom)
                } else {
                    VStack(spacing: 10) {
                        RoundHeader(care: care, round: 3, title: "Trick", kicker: turnPips.kicker, turns: turnPips)
                        turns.padReadable(760)
                        Spacer(minLength: 0)
                        bottomStack(full: full, rowCap: nil, burstHeight: 40 * sc).padReadable(760)
                    }
                    .padding(.horizontal, 16).padding(.top, 0).padding(.bottom, PadLayout.isPad ? 24 + g.safeAreaInsets.bottom : 10)
                }
            }
        }
    }

    // MARK: the bottom of the screen (the stage owns everything above it)

    /// What sits low on the screen, bottom up: the action (Skip while the entrants perform, the trick menu while he picks, a clear slot otherwise so nothing moves), the scoreboard strip,
    /// and the toast (his result, or the entrant's trick) just above the strip, with the Glow Burst button on the same row while it is ready.
    private func bottomStack(full: CGSize, rowCap: Int?, burstHeight: CGFloat) -> some View {
        let picking = show.trickStage == .pick && !(show.sim?.tricksDone ?? true)
        return VStack(spacing: 8 * sc) {
            ZStack {
                if let s = show.sim, s.burstReady, picking { burst(height: burstHeight) }
                else { toast }
            }
            .frame(minHeight: toastHeight)
            ScoreStrip(care: care, scale: sc, compact: compact)
            if rivalsOn { skipButton }
            else if picking { menuBox(rowCap: rowCap) }
            else { Color.clear.frame(height: (compact ? 46 : 50) * sc) }          // (the action slot: kept so the strip stays where it is while nothing is asked of him)
        }
    }
    private var toastHeight: CGFloat { (compact ? 36 : 40) * sc }

    private var skipButton: some View {
        Button { UIImpactFeedbackGenerator(style: .soft).impactOccurred(); AudioHub.shared.uiConfirm(); show.skipRivals() } label: {
            HStack(spacing: 8) {
                Image(systemName: "forward.fill").font(.system(size: 18 * sc, weight: .black))
                Text("Skip").font(SK.font(19 * sc, .black))
            }
            .foregroundStyle(SK.ink).frame(maxWidth: .infinity, minHeight: (compact ? 46 : 50) * sc)
            .background(Capsule().fill(ShowUI.gold))
            .overlay(Capsule().strokeBorder(ShowUI.light, lineWidth: 3))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Skip").accessibilityIdentifier("rivals-skip")
    }

    private var rivalsOn: Bool { show.trickStage == .rivals }

    /// ONE line, 36 to 44 pt tall, never wider than the screen: his result ("Corkscrew jump! +24"), or the entrant on stage with her trick, stars and points (tap: skip just her).
    @ViewBuilder private var toast: some View {
        if rivalsOn, let n = show.rivalNow, let s = show.sim {
            let r = s.rivals[n.rival], t = n.turn, stars = ShowTrickInfo.difficulty(t.trick)
            Button { AudioHub.shared.uiTap(); show.skipCurrentRival() } label: {
                HStack(spacing: 8 * sc) {
                    Text(r.name).font(SK.font(16 * sc, .black)).foregroundStyle(SK.ink).lineLimit(1).minimumScaleFactor(0.6)
                    Text(t.trick.title).font(SK.font(14 * sc, .heavy)).foregroundStyle(SK.ink).lineLimit(1).minimumScaleFactor(0.6).layoutPriority(-1)
                    StarRow(n: stars, size: 11 * sc)
                    Spacer(minLength: 2)
                    Text(show.rivalScored ? "+\(t.points)" : "\u{2026}").font(SK.font(20 * sc, .black)).foregroundStyle(SK.ink).monospacedDigit().lineLimit(1).fixedSize().layoutPriority(2)
                }
                .padding(.horizontal, 14 * sc).frame(maxWidth: .infinity).frame(height: toastHeight)
                .background(Capsule().fill(SK.cream.opacity(0.97)))
                .overlay(Capsule().strokeBorder(ShowUI.lilac, lineWidth: 2))
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(rivalToastLabel)
            .accessibilityHint("Skips just this turn")
            .accessibilityAddTraits(.isButton)
            .accessibilityIdentifier("rival-banner")
        } else if let h = hint {
            Text(h).font(SK.font(17 * sc, .black)).foregroundStyle(ShowUI.brownGold).lineLimit(1).minimumScaleFactor(0.6)
                .padding(.horizontal, 16 * sc).frame(maxWidth: .infinity).frame(height: toastHeight)
                .background(Capsule().fill(ShowUI.light.opacity(0.97)))
                .accessibilityIdentifier("trick-hint")
        }
    }
    private var rivalToastLabel: String {
        guard let n = show.rivalNow, let s = show.sim else { return "" }
        let t = n.turn, stars = ShowTrickInfo.difficulty(t.trick)
        let tail = show.rivalScored ? (t.success ? ", \(t.points) points" : ", a cute flop, \(t.points) points") : ""
        return "\(s.rivals[n.rival].name), \(t.trick.title), \(stars) star\(stars == 1 ? "" : "s")\(tail)"
    }

    /// The flash over the stage while he performs ("Jumping jacks! +24"); nothing otherwise.
    private var hint: String? {
        guard show.sim != nil, show.trickStage == .performing, let t = show.lastTurn else { return show.sim?.tricksDone == true && show.trickStage == .pick ? "All three done!" : nil }
        return t.success ? "\(t.trick.title)! +\(t.points)\(t.burst ? " and Glow Burst +10" : "")" : "A cute flop. +\(t.points)"
    }

    /// Three small capsules: which of the three turns it is (gold = the turn under way: "Your go", his result, or the entrant who is up) and what he scored in the ones done.
    /// The turn pips of the header: turns used so far, and the one up now.
    private var turnPips: TurnPips {
        let done = show.sim?.turns.count ?? 0
        return TurnPips(used: done, current: show.trickStage == .performing ? max(done - 1, 0) : done)
    }
    private var turns: some View {
        let s = show.sim
        let done = s?.turns.count ?? 0
        let stage = show.trickStage
        return HStack(spacing: 8) {
            ForEach(0..<3, id: \.self) { k in
                let turn = done > k ? s?.turns[k] : nil
                let playerBack = stage == .rivals && show.rivalStep == .playerBack          // (the last entrant is back: his next go is next)
                let entrantNow = stage == .rivals && show.rivalRound == k && !playerBack
                let nextGo = playerBack && k == show.rivalRound + 1 && k < 3
                let now: Bool = entrantNow || nextGo || (stage == .performing && k == done - 1) || (stage == .pick && !(s?.tricksDone ?? false) && k == done)
                let text: String = {
                    let tag = "Turn \(k + 1)"
                    if entrantNow {
                        if let i = show.rivalTurn, let s { return "\(tag) \u{00B7} \(ScoreStrip.shortName(s.rivals[i].name))" }
                        return "\(tag) \u{00B7} Rivals"
                    }
                    if let turn { return "\(tag) \u{00B7} +\(turn.points)" }
                    return now ? "\(tag) \u{00B7} Your go" : tag
                }()
                TurnChip(text: text, now: now, scale: sc, height: 34, font: 15)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("\(text.replacingOccurrences(of: "\u{00B7}", with: ",")) \(now ? ", now" : "")")
            }
        }
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        .accessibilityIdentifier("trick-turns")
    }

    /// The Glow Burst: only while it can be used (Cheer and Glow high enough, not used yet); gone after the Burst.
    @ViewBuilder private func burst(height: CGFloat) -> some View {
        if let s = show.sim, s.burstReady {
            Button { AudioHub.shared.uiConfirm(); show.armBurst() } label: {
                HStack(spacing: 10) {
                    Image(systemName: "sparkles").font(.system(size: 22 * sc, weight: .black)).foregroundStyle(SK.ink)
                    Text("Glow Burst +10").font(SK.font((compact ? 19 : 21) * sc, .black)).foregroundStyle(SK.ink)
                }
                .frame(maxWidth: .infinity, minHeight: height)
                .background(Capsule().fill(ShowUI.gold))
                .overlay(Capsule().strokeBorder(ShowUI.light, lineWidth: 3))
                .shadow(color: ShowUI.gold.opacity(0.7), radius: 7)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Glow Burst. Plus 10 points").accessibilityIdentifier("trick-burst")
        }
    }

    /// The trick menu: one row per trick this Jelmiko knows (icon, name, stars, theme tag where it matches, points). Tap a row and he performs it.
    /// `rowCap`: the most rows shown before the list scrolls (nil = four, as the board); a soft fade at the bottom hints at more.
    private func menuBox(rowCap: Int?) -> some View {
        let s = show.sim
        let known = s?.knownTricks ?? []
        let live = show.trickStage == .pick && !(s?.tricksDone ?? true)
        let cap = rowCap ?? 4
        return ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: compact ? 5 : 6) { ForEach(known, id: \.rawValue) { t in row(t, live: live) } }.padding(.vertical, 2)
        }
        .scrollBounceBehavior(.basedOnSize)
        .frame(maxHeight: Self.menuHeight(rows: min(known.count, cap), compact: compact, scale: sc))
        .modifier(SoftBottomFade(on: known.count > cap))
        .accessibilityIdentifier("trick-cards")
    }
    /// The rows' height (54 pt, 48 on a phone on its side, 6 / 5 pt gaps: the trick menu is as low and as small as it can be, the stage keeps the screen above it).
    static func menuHeight(rows: Int, compact: Bool, scale: CGFloat = 1) -> CGFloat {
        let row: CGFloat = (compact ? 48 : 54) * scale, gap: CGFloat = compact ? 5 : 6
        let shown = CGFloat(max(rows, 1))
        return shown * row + (shown - 1) * gap + 4
    }
    private func row(_ t: VoiceTrick, live: Bool) -> some View {
        let s = show.sim!
        let used = s.usedTricks.contains(t), pts = s.points(t), stars = ShowTrickInfo.difficulty(t)
        let tag = ShowTrickInfo.tags(t).first { $0 == show.theme.main } ?? ShowTrickInfo.tags(t).first { $0 == show.theme.friend }
        return Button { if live { AudioHub.shared.uiTap(); show.pick(t) } } label: {
            HStack(spacing: 12 * sc) {
                Image(systemName: ShowTrickInfo.symbol(t)).font(.system(size: 22 * sc, weight: .heavy)).foregroundStyle(SK.ink).frame(width: 30 * sc)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(t.title).font(SK.font(19 * sc, .black)).foregroundStyle(SK.ink).lineLimit(1).minimumScaleFactor(0.7)
                        if used { Image(systemName: "checkmark.circle.fill").font(.system(size: 14 * sc, weight: .black)).foregroundStyle(SK.muted) }
                    }
                    StarRow(n: stars, size: 13 * sc)
                }
                Spacer(minLength: 4)
                if let tag { Text(tag.title).font(SK.font(13 * sc, .black)).foregroundStyle(SK.ink).padding(.horizontal, 10 * sc).padding(.vertical, 3 * sc).background(Capsule().fill(ShowUI.tag(tag))) }
                Text("+\(pts)").font(SK.font(24 * sc, .black)).foregroundStyle(SK.ink).monospacedDigit().frame(minWidth: 52 * sc, alignment: .trailing)
            }
            .padding(.horizontal, 16 * sc).frame(maxWidth: .infinity, minHeight: (compact ? 48 : 54) * sc)
            .background(RoundedRectangle(cornerRadius: 20 * sc, style: .continuous).fill(SK.cream.opacity(0.97)))
            .opacity(used ? 0.6 : 1)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain).disabled(!live)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(t.title), \(stars) star\(stars == 1 ? "" : "s"), \(pts) points\(tag.map { ", matches \($0.title)" } ?? "")\(used ? ", shown already" : "")")
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("trick-\(t.rawValue)")
    }
}

/// A short burst of confetti from a point (the Glow Burst).
struct Confetti: View {
    var serial: Int
    var at: CGPoint
    @State private var start = Date()
    var body: some View {
        if A11ySettings.shared.reduceMotion { glowText } else { confetti }
    }

    /// Reduce Motion: a still "Glow Burst!" that fades, in place of the confetti.
    private var glowText: some View {
        TimelineView(.animation(minimumInterval: 0.1)) { ctx in
            let t = ctx.date.timeIntervalSince(start)
            Text("Glow Burst!").playFont(26, .black).foregroundStyle(ShowUI.gold)
                .shadow(color: .black.opacity(0.35), radius: 3, y: 2)
                .opacity(max(0, 1 - t / 1.8))
                .position(x: at.x, y: at.y - 40)
        }
        .allowsHitTesting(false).accessibilityHidden(true)
        .id(serial)
        .onAppear { start = Date() }
        .onChange(of: serial) { _, _ in start = Date() }
    }

    private var confetti: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30)) { ctx in
            let t = ctx.date.timeIntervalSince(start)
            Canvas { g, _ in
                guard t < 1.8 else { return }
                var rng = RaceRNG(seed: UInt64(serial) &* 97 &+ 5)
                for i in 0..<42 {
                    let a = Double(rng.next()) * 2 * .pi, sp = 120 + Double(rng.next()) * 220, k = Double(i % 5)
                    let x = at.x + CGFloat(cos(a) * sp * t), y = at.y + CGFloat(sin(a) * sp * t + 180 * t * t)
                    let c: Color = [ShowUI.gold, SK.pink, SK.sky, SK.mint, .white][Int(k)]
                    g.opacity = max(0, 1 - t / 1.8)
                    g.fill(Path(roundedRect: CGRect(x: x, y: y, width: 7, height: 10), cornerRadius: 2), with: .color(c))
                }
            }
        }
        .ignoresSafeArea()
        .id(serial)
        .onAppear { start = Date() }
        .onChange(of: serial) { _, _ in start = Date() }
    }
}

// MARK: - Results

struct ResultsScreen: View {
    let care: GameCare
    @Environment(\.verticalSizeClass) private var vsc
    private var compact: Bool { vsc == .compact }
    private var show: ShowFlow { care.show }
    @State private var grown = false

    var body: some View {
        let s = show.sim
        let place = s?.playerPlace ?? 4
        return GeometryReader { g in
            let ins = g.safeAreaInsets
            let full = CGSize(width: g.size.width + ins.leading + ins.trailing, height: g.size.height + ins.top + ins.bottom)
            // the creature's feet on screen (the stage camera's projection): the place ribbon sits right under her, the cards under that, nothing over her
            let feet = StageProject.point(ShowStage.playerSpot, y: 0, frame: .results(pad: PadLayout.isPad), size: full)
            let feetX = feet.x - ins.leading, feetY = feet.y - ins.top
            let ribbon = ribbonView(place)
            ZStack(alignment: .topLeading) {
                header
                if compact {
                    ribbon.position(x: feetX, y: feetY + 34)
                    HStack {
                        Spacer(minLength: 0)
                        ScrollView { VStack(spacing: 6) { podium(0.7); chips; rewards; tip; buttons }.padding(.vertical, 10) }.scrollBounceBehavior(.basedOnSize).frame(width: g.size.width * 0.5)
                    }
                } else {
                    VStack(spacing: 0) {
                        ScrollView {
                            VStack(spacing: 12) {
                                ribbon.padding(.bottom, -10)
                                podium(1)
                                chips
                                rewards
                                tip
                            }
                        }
                        .scrollBounceBehavior(.basedOnSize)
                        buttons.padding(.top, 12)
                    }
                    .padReadable(560)          // iPad: the same 560 pt card width as the Race and Volleyball results
                    .padding(.top, max(52, feetY + 10)).padding(.bottom, PadLayout.isPad ? 14 : 4)
                }
            }
            .padding(.horizontal, compact ? 0 : 16)
            .padding(.top, 0)
        }
        .onAppear { withAnimation(.spring(response: 0.8, dampingFraction: 0.7).delay(0.3)) { grown = true } }
        .accessibilityElement(children: .contain).accessibilityIdentifier("results-screen")
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("\(show.theme.title.uppercased()) \u{00B7} \(show.rank.title.uppercased())").font(SK.font(12, .black)).foregroundStyle(ShowUI.gold).tracking(0.5)
            Text("Results").font(SK.font(24, .black)).foregroundStyle(SK.cream)
        }
        .accessibilityElement(children: .combine)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, compact ? 14 : 0)
    }

    /// The place, said once, as a ribbon under the creature.
    private func ribbonView(_ place: Int) -> some View {
        Text(place == 1 ? "\(show.playerName) wins!" : "\(show.playerName) comes \(ShowUI.ordinal(place))")
            .font(SK.font(24, .black)).foregroundStyle(SK.ink).lineLimit(1).minimumScaleFactor(0.6)
            .padding(.horizontal, 26).padding(.vertical, 8)
            .background(Capsule().fill(ShowUI.gold)).overlay(Capsule().strokeBorder(ShowUI.goldDeep, lineWidth: 3))
            .accessibilityIdentifier("results-place")
    }

    private func podium(_ k: CGFloat) -> some View {
        let list = show.sim?.standings ?? []
        let heights: [CGFloat] = [72, 54, 42, 34]
        let colours: [Color] = [ShowUI.goldDeep, Color(hex: 0xC9CFD8), Color(hex: 0xC98B55), ShowUI.lilac]
        let tint = JellyRoster.tint(show.character)
        // the podium order: 2nd, 1st, 3rd, 4th (the winner in the middle)
        let order = list.count == 4 ? [list[1], list[0], list[2], list[3]] : list
        return HStack(alignment: .bottom, spacing: 6) {
            ForEach(Array(order.enumerated()), id: \.offset) { _, e in
                VStack(spacing: 3) {
                    if e.isPlayer {
                        EntrantBubble(tint: tint, size: 34 * k).overlay(Circle().strokeBorder(ShowUI.gold, lineWidth: 3)).shadow(color: ShowUI.gold.opacity(0.8), radius: 6)
                    } else { EntrantBubble(tint: e.tint, size: 34 * k) }
                    Text(e.name).font(SK.font(13, .black)).foregroundStyle(e.isPlayer ? ShowUI.gold : ShowUI.mist).lineLimit(1).minimumScaleFactor(0.6)
                    VStack(spacing: 1) {
                        Text(ShowUI.ordinal(e.place)).font(SK.font(20, .black)).foregroundStyle(SK.ink)
                        Text("\(e.scores.totalPts)").font(SK.font(12, .black)).foregroundStyle(SK.ink)
                    }
                    .frame(maxWidth: .infinity, minHeight: grown ? heights[min(max(e.place - 1, 0), 3)] * k : 20)
                    .background(UnevenRoundedRectangle(topLeadingRadius: 12, topTrailingRadius: 12).fill(colours[min(max(e.place - 1, 0), 3)]))
                }
                .accessibilityElement(children: .combine).accessibilityLabel("\(e.name) \(ShowUI.ordinal(e.place)) with \(e.scores.totalPts)")
            }
        }
        .padding(.horizontal, 8)
        .overlay(alignment: .bottom) { Capsule().fill(ShowUI.platform).frame(height: 4).offset(y: 4) }
        .padding(.bottom, 4)
        .accessibilityIdentifier("results-podium")
    }

    /// The player's own three scores (the chart of all four is gone).
    private var chips: some View {
        let sc = show.sim?.playerScores ?? ShowScores()
        return HStack(spacing: 8) {
            scoreChip("Look", sc.lookPts, SK.pink); scoreChip("Dance", sc.dancePts, Color(hex: 0xB58BDB)); scoreChip("Trick", sc.trickPts, SK.honeyDeep)
        }
        .accessibilityIdentifier("results-scores")
    }
    private func scoreChip(_ name: String, _ v: Int, _ c: Color) -> some View {
        HStack(spacing: 6) { Circle().fill(c).frame(width: 11, height: 11); Text("\(name) \(v)").font(SK.font(15, .black)).foregroundStyle(SK.ink) }
            .padding(.horizontal, 12).padding(.vertical, 6).background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(SK.cream.opacity(0.96)))
            .accessibilityElement(children: .combine)
    }

    private var rewards: some View {
        let a = show.awards
        return VStack(spacing: 12) {
            HStack(spacing: 10) {
                HStack(spacing: 10) {
                    JellyCoinIcon(size: 40)
                    Text("+\(show.earned.coinText)").font(SK.font(28, .black)).foregroundStyle(SK.ink).lineLimit(1).minimumScaleFactor(0.6)
                }
                .padding(.horizontal, 14).frame(maxWidth: .infinity, minHeight: compact ? 60 : 72, alignment: .leading).background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(SK.sky))
                .accessibilityElement(children: .combine).accessibilityLabel("\(show.earned.coinText) JellyCoins").accessibilityIdentifier("results-drops")
                HStack(spacing: 10) {
                    Image(systemName: "trophy.fill").font(.system(size: 30, weight: .black)).foregroundStyle(a?.cup == 1 ? ShowUI.goldDeep : a?.cup == 2 ? Color(hex: 0x9AA3B2) : a?.cup == 3 ? Color(hex: 0xC98B55) : SK.muted.opacity(0.35))
                    VStack(alignment: .leading, spacing: 1) {
                        Text(a?.cup.map { $0 == 1 ? "Gold cup" : $0 == 2 ? "Silver cup" : "Bronze cup" } ?? (show.sim?.playerPlace ?? 4 <= 3 ? "Cup kept" : "No cup this time")).font(SK.font(18, .black)).foregroundStyle(SK.ink).lineLimit(2).minimumScaleFactor(0.7)
                        Text(a?.unlocked.map { "\($0.title) is open!" } ?? (show.rank.above.map { show.progress.requirement($0) ?? "\($0.title) is open" } ?? "Top rank!")).font(SK.font(14, .heavy)).foregroundStyle(ShowUI.brownGold).lineLimit(2).minimumScaleFactor(0.7)
                    }
                }
                .padding(.horizontal, 14).frame(maxWidth: .infinity, minHeight: compact ? 60 : 72, alignment: .leading).background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Color(hex: 0xFFE7A8)))
                .accessibilityElement(children: .combine).accessibilityIdentifier("results-cup")
            }
            if let a, !(a.stickers.isEmpty && a.rosette == nil) {
                let chips = Group {
                    ForEach(a.stickers, id: \.rawValue) { s in Text("\u{2605} \(s.title)").font(SK.font(11, .black)).foregroundStyle(ShowUI.brownGold).lineLimit(1).fixedSize().padding(.horizontal, 7).padding(.vertical, 5).background(Capsule().fill(ShowUI.light)) }
                    if let r = a.rosette { Text("\u{2605} \(r.title)").font(SK.font(11, .black)).foregroundStyle(Color(hex: 0x2E6B26)).lineLimit(1).fixedSize().padding(.horizontal, 7).padding(.vertical, 5).background(Capsule().fill(Color(hex: 0xE3F4DD))) }
                }
                ViewThatFits(in: .horizontal) {          // (one row when they fit, as the board; else they wrap)
                    HStack(spacing: 4) { chips }
                    FlowLayout(spacing: 6) { chips }
                }
                .frame(maxWidth: .infinity)
                .accessibilityIdentifier("results-stickers")
            }
        }
    }

    private var tip: some View {
        let t = ShowShortTip.parts(show.sim, theme: show.theme)
        return ShowCard(padding: 10) {
            HStack(spacing: 10) {
                Image(systemName: "lightbulb.fill").font(.system(size: 22, weight: .black)).foregroundStyle(SK.honeyDeep)
                (Text(t.head).font(SK.font(17, .black)) + (t.stars ? Text("\u{2605}\u{2605}\u{2605}").font(SK.font(17, .black)).foregroundColor(ShowUI.goldDeep) : Text("")) + Text(t.tail).font(SK.font(17, .black)))
                    .foregroundStyle(SK.ink).lineLimit(1).minimumScaleFactor(0.7)
                Spacer(minLength: 0)
            }
            .frame(minHeight: compact ? 28 : 36)
        }
        .accessibilityElement(children: .ignore).accessibilityLabel(ShowShortTip.text(show.sim, theme: show.theme))
        .accessibilityIdentifier("results-tip")
    }

    private var buttons: some View {
        HStack(spacing: 10) {
            Button { AudioHub.shared.uiTap(); show.goHome(again: true) } label: {
                Text("Again").font(SK.font(20, .black)).foregroundStyle(SK.ink).frame(maxWidth: .infinity, minHeight: compact ? 50 : 60).background(Capsule().fill(SK.cream))
            }.buttonStyle(.plain).accessibilityIdentifier("results-again")
            ShowCTA(title: "Done", id: "results-done", height: compact ? 50 : 60) { show.goHome() }
        }
    }
}
