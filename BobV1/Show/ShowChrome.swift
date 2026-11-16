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
    var quits = true
    var body: some View {
        let show = care.show
        HStack(spacing: 10) {
            if quits {
                Button { AudioHub.shared.uiTap(); show.goHome() } label: {
                    Image(systemName: "xmark").font(.system(size: 17, weight: .black)).foregroundStyle(SK.ink)
                        .frame(width: 44, height: 44).background(Circle().fill(SK.cream))
                }.buttonStyle(.plain).accessibilityLabel("Leave the Jelly Show").accessibilityIdentifier("show-quit")
            }
            VStack(alignment: .leading, spacing: 0) {
                Text(kicker ?? "ROUND \(round) OF 3 \u{00B7} \(show.rank.title.uppercased())").font(SK.font(12, .black)).foregroundStyle(ShowUI.gold).tracking(0.5)
                Text(title).font(SK.font(24, .black)).foregroundStyle(SK.cream)
            }
            .accessibilityElement(children: .combine).accessibilityIdentifier("show-round")
            Spacer()
            HStack(spacing: 6) {
                ForEach(1...3, id: \.self) { k in Capsule().fill(k <= round ? ShowUI.gold : ShowUI.platform).frame(width: 26, height: 8) }
            }
            .accessibilityLabel("Round \(round) of 3")
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
            VStack(spacing: 10) {
                RoundHeader(care: care, round: 1, title: "Look")
                HStack { if !compact { Spacer() }; StagePill(text: "\(show.theme.title): \(show.theme.main.title), friend \(show.theme.friend.title)"); Spacer() }
                Spacer(minLength: 0)
                if compact {
                    HStack(alignment: .bottom, spacing: 12) {
                        Spacer(minLength: 0)
                        VStack(spacing: 8) { score; cta }.frame(width: min(size.width * 0.52, 520))
                    }
                } else {
                    Text("The judges are looking at \(show.playerName)\u{2019}s outfit").font(SK.font(12, .heavy)).foregroundStyle(ShowUI.mist)
                    score
                    cta
                }
            }
            .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 14)
        }
    }

    private var score: some View {
        let s = show.sim
        let parts = s?.lookParts ?? (outfit: 0, stats: 0, glow: 0)
        let total = Int((s?.lookScore ?? 0).rounded())
        let sum = s?.outfitSum ?? 0
        let main = s?.player.stat(show.theme.main) ?? 0, friend = s?.player.stat(show.theme.friend) ?? 0
        let glow = s?.player.glow ?? 0, dirt = s?.player.dirt ?? 0
        return ShowCard {
            HStack(spacing: 14) {
                VStack(spacing: 0) {
                    Text("\(total)").font(SK.font(32, .black)).foregroundStyle(SK.ink).monospacedDigit().contentTransition(.numericText())
                    Text("Look / 100").font(SK.font(11, .black)).foregroundStyle(ShowUI.brownGold)
                }
                .frame(width: 84, height: 84).background(Circle().fill(ShowUI.gold)).overlay(Circle().strokeBorder(ShowUI.goldDeep, lineWidth: 4))
                .accessibilityIdentifier("look-score")
                VStack(spacing: 7) {
                    part("Outfit match", parts.outfit, 40, SK.honeyDeep, "\(String(format: "%g", (sum * 2).rounded() / 2)) of \(show.rank.slots) slots match")
                    part("Stats", parts.stats, 40, SK.pink, "\(show.theme.main.title) \(ShowUI.pts(main)) counts 70%, \(show.theme.friend.title) \(ShowUI.pts(friend)) 30%")
                    part("Glow", parts.glow, 20, SK.sky, "Glow \(ShowUI.glowOf5(glow)) of 5\(dirt > 0.3 ? ", a little lint" : "")")
                }
            }
        }
        .animation(.easeOut(duration: 0.3), value: total)
    }
    private func part(_ name: String, _ v: Float, _ max: Float, _ c: Color, _ note: String) -> some View {
        VStack(spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(name).font(SK.font(14, .black)).foregroundStyle(SK.ink); Spacer()
                (Text("\(Int(v.rounded()))").font(SK.font(14, .black)) + Text(" / \(Int(max))").font(SK.font(11, .heavy)).foregroundColor(SK.muted)).foregroundStyle(SK.ink)
            }
            GeometryReader { g in ZStack(alignment: .leading) { Capsule().fill(ShowUI.bar); Capsule().fill(c).frame(width: Swift.max(4, g.size.width * CGFloat(v / max))) } }.frame(height: 10)
            Text(note).font(SK.font(11, .bold)).foregroundStyle(SK.muted).frame(maxWidth: .infinity, alignment: .leading).lineLimit(1).minimumScaleFactor(0.7)
        }
        .accessibilityElement(children: .combine)
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
            RoundHeader(care: care, round: 2, title: "Dance", kicker: kicker, quits: false)
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
                RoundHeader(care: care, round: 2, title: "Dance", kicker: kicker, quits: false).padding(.top, 14)
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
                if show.showsCountdown { count("\(show.countdown)") }
                else if show.showsGo { count("GO!") }
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
            let body = StageProject.body(ShowStage.playerSpot, frame: .trick(pad: PadLayout.isPad), size: size)
            ZStack(alignment: .top) {
                if show.burstFlash > 0 { Confetti(serial: show.burstFlash, at: body.centre).allowsHitTesting(false) }
                VStack(spacing: 8) {
                    RoundHeader(care: care, round: 3, title: "Trick", quits: false)
                    if compact {
                        HStack(alignment: .top, spacing: 12) {
                            VStack(alignment: .leading) { StagePill(text: hint); Spacer(minLength: 0) }
                            VStack(spacing: 8) { turns; if rivalsOn { rivalPanel } else { meters; burst; menu } }.frame(width: min(size.width * 0.52, 520))
                        }
                    } else if PadLayout.isPad && size.width > size.height {
                        // iPad landscape: the stage fills the left ~55% (the camera frame puts the Jelbies there); chips, hint and the menu / rival card are a clear right column
                        HStack(alignment: .top, spacing: 24) {
                            Color.clear.frame(width: size.width * 0.55 - 16)
                            VStack(spacing: 10) {
                                turns
                                StagePill(text: hint, scale: sc)
                                Spacer(minLength: 0)
                                if rivalsOn { rivalPanel } else {
                                    meters
                                    burst
                                    menuBox(rowCap: 6)
                                }
                            }
                            .frame(maxWidth: 560)
                        }
                    } else {
                        turns.padReadable(760)
                        HStack { Spacer(); StagePill(text: hint, scale: sc); Spacer() }
                        Spacer(minLength: 0)
                        VStack(spacing: 8) {
                            if rivalsOn { rivalPanel } else {
                                meters
                                burst
                                menu
                            }
                        }
                        .padReadable(760)
                    }
                }
                .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, PadLayout.isPad ? 24 + g.safeAreaInsets.bottom : 14)
            }
        }
    }

    private var hint: String {
        guard let s = show.sim else { return "" }
        switch show.trickStage {
        case .pick: return s.tricksDone ? "All three done!" : "Turn \(s.turnIndex + 1) of 3 \u{00B7} pick a trick"
        case .performing:
            guard let t = show.lastTurn else { return "" }
            return t.success ? "\(t.trick.title)! +\(t.points)\(t.burst ? " and Glow Burst +10" : "")" : "A cute flop. +\(t.points)"
        case .rivals: return "Rival's turn \(show.rivalRound + 1) of 3"
        }
    }

    private var rivalsOn: Bool { show.trickStage == .rivals }

    /// The rivals' turn: who is up with her trick, stars and points (tap it to skip just her), and the big Skip for the rest of this turn.
    private var rivalPanel: some View {
        VStack(spacing: (compact ? 8 : 12) * sc) {
            Button { AudioHub.shared.uiTap(); show.skipCurrentRival() } label: { rivalBanner }
                .buttonStyle(.plain)
                .accessibilityIdentifier("rival-banner")
            Button { UIImpactFeedbackGenerator(style: .soft).impactOccurred(); AudioHub.shared.uiConfirm(); show.skipRivals() } label: {
                HStack(spacing: 8) {
                    Image(systemName: "forward.fill").font(.system(size: 20 * sc, weight: .black))
                    Text("Skip").font(SK.font(20 * sc, .black))
                }
                .foregroundStyle(SK.ink).frame(maxWidth: .infinity, minHeight: (compact ? 50 : 60) * sc)
                .background(Capsule().fill(ShowUI.gold))
                .overlay(Capsule().strokeBorder(ShowUI.light, lineWidth: 3))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Skip rivals' tricks").accessibilityIdentifier("rivals-skip")
        }
    }
    private var rivalBanner: some View {
        let n = show.rivalNow, s = show.sim
        return VStack(alignment: .leading, spacing: 4) {
            if let n, let s {
                let r = s.rivals[n.rival], t = n.turn, stars = ShowTrickInfo.difficulty(t.trick)
                HStack(alignment: .firstTextBaseline) {
                    Text("Rival's turn").font(SK.font(11 * sc, .heavy)).foregroundStyle(SK.muted)
                    Spacer()
                    Text(r.persona.title).font(SK.font(11 * sc, .black)).foregroundStyle(SK.ink)
                }
                HStack(spacing: 8) {
                    RivalBlob(tint: r.tint, size: (compact ? 30 : 38) * sc)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(r.name).font(SK.font((compact ? 16 : 19) * sc, .black)).foregroundStyle(SK.ink).lineLimit(1).minimumScaleFactor(0.7)
                        HStack(spacing: 6) {
                            Text(t.trick.title).font(SK.font(14 * sc, .heavy)).foregroundStyle(SK.ink)
                            HStack(spacing: 2) { ForEach(0..<3, id: \.self) { k in Image(systemName: k < stars ? "star.fill" : "star").font(.system(size: 10 * sc, weight: .black)).foregroundStyle(k < stars ? ShowUI.goldDeep : SK.muted.opacity(0.5)) } }
                        }
                    }
                    Spacer(minLength: 4)
                    Text(show.rivalScored ? (t.success ? "+\(t.points)" : "Cute flop +\(t.points)") : "\u{2026}").font(SK.font((show.rivalScored && !t.success ? 15 : 22) * sc, .black)).foregroundStyle(SK.ink).monospacedDigit()
                }
            } else {
                Text("Your turn next").font(SK.font(18 * sc, .black)).foregroundStyle(SK.ink).frame(maxWidth: .infinity, alignment: .center)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 10).frame(maxWidth: .infinity, minHeight: (compact ? 54 : 68) * sc)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(SK.cream.opacity(0.97)))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(ShowUI.lilac, lineWidth: 3))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(rivalBannerLabel)
        .accessibilityHint("Skips just this rival")
        .accessibilityAddTraits(.isButton)
    }
    private var rivalBannerLabel: String {
        guard let n = show.rivalNow, let s = show.sim else { return "Your turn next" }
        let t = n.turn, stars = ShowTrickInfo.difficulty(t.trick)
        let tail = show.rivalScored ? (t.success ? ", \(t.points) points" : ", a cute flop, \(t.points) points") : ""
        return "Rival's turn: \(s.rivals[n.rival].name), \(t.trick.title), \(stars) star\(stars == 1 ? "" : "s")\(tail)"
    }

    private var turns: some View {
        let s = show.sim
        return HStack(spacing: 6) {
            ForEach(0..<3, id: \.self) { k in
                let t = (s?.turns.count ?? 0) > k ? s?.turns[k] : nil
                let rivalsNow = show.trickStage == .rivals && show.rivalRound == k
                let now = ((s?.turns.count ?? 0) == k && !(s?.tricksDone ?? false)) || rivalsNow
                HStack(spacing: 6) {
                    Text(t.map { "\(k + 1) \($0.trick.title)" } ?? "Turn \(k + 1)").font(SK.font(11 * sc, .black)).opacity(0.8)
                        .lineLimit(PadLayout.isPad ? 1 : nil).minimumScaleFactor(PadLayout.isPad ? 0.6 : 1)
                    Text(rivalsNow ? "Rivals" : (t.map { "+\($0.points)" } ?? (now ? "Your go" : "\u{2014}"))).font(SK.font(15 * sc, .black))
                        .lineLimit(PadLayout.isPad ? 1 : nil).minimumScaleFactor(PadLayout.isPad ? 0.6 : 1)
                }
                .foregroundStyle(SK.ink).frame(maxWidth: .infinity, minHeight: 44 * sc)
                .background(Capsule().fill(now ? ShowUI.gold : SK.cream.opacity(0.95)))
                .overlay(Capsule().strokeBorder(now ? ShowUI.goldDeep : .clear, lineWidth: 3))
                .accessibilityElement(children: .combine)
            }
        }
        .accessibilityIdentifier("trick-turns")
    }

    private var meters: some View {
        let s = show.sim
        let c = s?.cheer ?? 0, glow = s?.player.glow ?? 0
        return ShowCard(padding: 10) {
            HStack(spacing: 16) {
                meter("Cheer", c, SK.pink, ShowScoring.burstCheer, "Needs 75% for Burst")
                meter("Glow", glow, SK.sky, ShowScoring.burstGlow, "Needs 50% for Burst")
            }
        }
        .accessibilityIdentifier("trick-meters")
    }
    private func meter(_ name: String, _ v: Float, _ c: Color, _ tick: Float, _ note: String) -> some View {
        VStack(spacing: 3) {
            HStack(alignment: .firstTextBaseline) { Text(name).font(SK.font(15 * sc, .black)).foregroundStyle(SK.ink); Spacer(); Text("\(Int((v * 100).rounded()))%").font(SK.font(18 * sc, .black)).foregroundStyle(SK.ink).monospacedDigit() }
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(ShowUI.bar)
                    Capsule().fill(c).frame(width: max(0, g.size.width * CGFloat(min(max(v, 0), 1))))
                    RoundedRectangle(cornerRadius: 2).fill(SK.ink).frame(width: 3, height: 20).offset(x: g.size.width * CGFloat(tick) - 1.5)
                }
            }.frame(height: 14)
            Text(note).font(SK.font(11 * sc, .heavy)).foregroundStyle(SK.muted).frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine).accessibilityLabel("\(name) \(Int((v * 100).rounded())) percent. \(note)")
    }

    @ViewBuilder private var burst: some View {
        if let s = show.sim, s.burstUnlocked || s.burstUsed {
            let ready = s.burstReady, armed = !ready && !s.burstUsed
            Button { if ready { AudioHub.shared.uiConfirm(); show.armBurst() } } label: {
                HStack(spacing: 10) {
                    Image(systemName: "sparkles").font(.system(size: 24, weight: .black)).foregroundStyle(.white).shadow(color: SK.ink, radius: 1)
                    Text("Glow Burst \u{00B7} +10").font(SK.font(20 * sc, .black)).foregroundStyle(SK.ink)
                    Text(s.burstUsed ? "Used" : armed ? "Armed" : "Ready").font(SK.font(12, .heavy)).foregroundStyle(ShowUI.gold).padding(.horizontal, 8).padding(.vertical, 3).background(Capsule().fill(SK.ink))
                }
                .frame(maxWidth: .infinity, minHeight: 56 * sc)
                .background(Capsule().fill(s.burstUsed ? ShowUI.gold.opacity(0.4) : ShowUI.gold))
                .overlay(Capsule().strokeBorder(ShowUI.light, lineWidth: 3))
                .shadow(color: ShowUI.gold.opacity(s.burstUsed ? 0 : 0.7), radius: 6)
            }
            .buttonStyle(.plain).disabled(!ready)
            .accessibilityLabel("Glow Burst, \(s.burstUsed ? "used" : armed ? "armed for this trick" : "ready"). Plus 10 points").accessibilityIdentifier("trick-burst")
        } else if let s = show.sim {
            Text("Glow Burst needs Cheer 75% and Glow 50%\(s.player.glow < ShowScoring.burstGlow ? " (a Clean before the Jelly Show)" : "")").font(SK.font(12, .heavy)).foregroundStyle(ShowUI.lilacPale)
        }
    }

    /// The trick menu, like a restaurant: one row per trick this Jelbie knows (icon, name, stars, points, theme tag). Tap a row and he performs it.
    private var menu: some View { menuBox(rowCap: nil) }
    /// `rowCap` (iPad landscape's right column): show at most this many rows before it scrolls; nil = the usual.
    private func menuBox(rowCap: Int?) -> some View {
        let s = show.sim
        let known = s?.knownTricks ?? []
        let live = show.trickStage == .pick && !(s?.tricksDone ?? true)
        return VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text("Trick menu").font(SK.font(16 * sc, .black)).foregroundStyle(SK.cream)
                Spacer()
                Text("More stars, more points").font(SK.font(12 * sc, .heavy)).foregroundStyle(ShowUI.lilacPale)
            }
            ScrollView(.vertical, showsIndicators: known.count > 4) {
                VStack(spacing: 6) { ForEach(known, id: \.rawValue) { t in row(t, live: live) } }.padding(.vertical, 2)
            }
            .scrollBounceBehavior(.basedOnSize)
            .frame(maxHeight: Self.menuHeight(rows: rowCap.map { min(known.count, $0) } ?? known.count, compact: compact, scale: sc, cap: rowCap))
            .mask(alignment: .top) {
                // iPad landscape column: a soft bottom fade hints that more rows scroll (only when the list is longer than the cap)
                if let cap = rowCap, known.count > cap {
                    VStack(spacing: 0) { Rectangle(); LinearGradient(colors: [.black, .black.opacity(0.1)], startPoint: .top, endPoint: .bottom).frame(height: 22) }
                } else { Rectangle() }
            }
        }
        .accessibilityIdentifier("trick-cards")
    }
    /// Four rows show at once (a phone on its side fewer); more scroll.
    static func menuHeight(rows: Int, compact: Bool, scale: CGFloat = 1, cap: Int? = nil) -> CGFloat {
        let row: CGFloat = (compact ? 46 : 56) * scale, gap: CGFloat = 6
        let shown = CGFloat(min(max(rows, 1), cap ?? (compact ? 3 : (scale > 1 ? 5 : 4))))
        return shown * row + (shown - 1) * gap + 4
    }
    private func row(_ t: VoiceTrick, live: Bool) -> some View {
        let s = show.sim!
        let used = s.usedTricks.contains(t), pts = s.points(t), stars = ShowTrickInfo.difficulty(t)
        let tag = ShowTrickInfo.tags(t).first { $0 == show.theme.main } ?? ShowTrickInfo.tags(t).first { $0 == show.theme.friend }
        let scope = care.store.trickScope(t, character: show.character)          // nil = a default every Jelbie has
        return Button { if live { AudioHub.shared.uiTap(); show.pick(t) } } label: {
            HStack(spacing: 10) {
                Image(systemName: ShowTrickInfo.symbol(t)).font(.system(size: 20 * sc, weight: .heavy)).foregroundStyle(SK.ink).frame(width: 30 * sc)
                VStack(alignment: .leading, spacing: 1) {
                    Text(t.title).font(SK.font(16 * sc, .black)).foregroundStyle(SK.ink).lineLimit(1).minimumScaleFactor(0.7)
                    HStack(spacing: 2) {
                        ForEach(0..<3, id: \.self) { k in Image(systemName: k < stars ? "star.fill" : "star").font(.system(size: 10 * sc, weight: .black)).foregroundStyle(k < stars ? ShowUI.goldDeep : SK.muted.opacity(0.5)) }
                        if used { Text("shown already").font(SK.font(10.5 * sc, .heavy)).foregroundStyle(SK.muted).padding(.leading, 4) }
                        if let scope { Text(scope == .everyone ? "Everyone" : "\(show.playerName)'s own").font(SK.font(10.5 * sc, .heavy)).foregroundStyle(SK.muted).lineLimit(1).minimumScaleFactor(0.7).padding(.leading, 4) }
                    }
                }
                Spacer(minLength: 4)
                if let tag { Text(tag.title).font(SK.font(11 * sc, .black)).foregroundStyle(SK.ink).padding(.horizontal, 8).padding(.vertical, 3).background(Capsule().fill(ShowUI.tag(tag))) }
                Text("+\(pts)").font(SK.font(20 * sc, .black)).foregroundStyle(SK.ink).monospacedDigit().frame(minWidth: 44 * sc, alignment: .trailing)
            }
            .padding(.horizontal, 12).frame(maxWidth: .infinity, minHeight: (compact ? 46 : 56) * sc)
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(SK.cream.opacity(live ? 0.97 : 0.7)))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(tag == show.theme.main ? ShowUI.gold : .clear, lineWidth: 3))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain).disabled(!live)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(t.title), \(stars) star\(stars == 1 ? "" : "s"), \(pts) points\(tag.map { ", matches \($0.title)" } ?? "")\(used ? ", shown already" : "")\(scope.map { $0 == .everyone ? ", a trick for everyone" : ", one Jelmiko's own trick" } ?? "")")
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
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 0) {
                    Text("\(show.theme.title.uppercased()) \u{00B7} \(show.rank.title.uppercased())").font(SK.font(12, .black)).foregroundStyle(ShowUI.gold).tracking(0.5)
                    Text("Results").font(SK.font(24, .black)).foregroundStyle(SK.cream)
                }
                Spacer()
                Text(place == 1 ? "\(show.playerName) wins!" : "\(show.playerName) comes \(ShowUI.ordinal(place))").font(SK.font(15, .black)).foregroundStyle(SK.ink)
                    .padding(.horizontal, 14).padding(.vertical, 6).background(Capsule().fill(ShowUI.gold))
                    .accessibilityIdentifier("results-place")
            }
            Spacer(minLength: 0)
            if compact {
                HStack(alignment: .top, spacing: 12) {
                    VStack(spacing: 8) { podium; bars }
                    ScrollView { VStack(spacing: 8) { rewards; tip; buttons } }.scrollBounceBehavior(.basedOnSize).frame(width: 330)
                }
            } else {
                ScrollView {
                    VStack(spacing: 8) { podium; bars; rewards; tip }
                }
                .scrollBounceBehavior(.basedOnSize)
                buttons
            }
        }
        .padReadable(560)          // iPad: the same 560 pt card width as the Race and Volleyball results
        .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 14)
        .onAppear { withAnimation(.spring(response: 0.8, dampingFraction: 0.7).delay(0.3)) { grown = true } }
        .accessibilityElement(children: .contain).accessibilityIdentifier("results-screen")
    }

    private var podium: some View {
        let list = show.sim?.standings ?? []
        let heights: [CGFloat] = [96, 72, 54, 40]
        let colours: [Color] = [ShowUI.goldDeep, Color(hex: 0xC9CFD8), Color(hex: 0xC98B55), ShowUI.lilac]
        let tint = JellyRoster.tint(show.character)
        // the podium order: 2nd, 1st, 3rd, 4th (the winner in the middle)
        let order = list.count == 4 ? [list[1], list[0], list[2], list[3]] : list
        return HStack(alignment: .bottom, spacing: 6) {
            ForEach(Array(order.enumerated()), id: \.offset) { _, e in
                VStack(spacing: 3) {
                    if e.isPlayer {
                        ZStack {
                            Circle().fill(Color(red: Double(tint.x), green: Double(tint.y), blue: Double(tint.z)))
                            Image(systemName: "face.smiling.fill").font(.system(size: 26, weight: .black)).foregroundStyle(.white.opacity(0.85))
                        }
                        .frame(width: 52, height: 52).overlay(Circle().strokeBorder(ShowUI.gold, lineWidth: 3)).shadow(color: ShowUI.gold.opacity(0.7), radius: 6)
                    } else { RivalBlob(tint: e.tint, size: 50) }
                    Text(e.name).font(SK.font(e.name.count > 9 ? 10 : 13, .black)).foregroundStyle(e.isPlayer ? ShowUI.gold : ShowUI.mist).lineLimit(1).minimumScaleFactor(0.6)
                    VStack(spacing: 2) {
                        Text(ShowUI.ordinal(e.place)).font(SK.font(24, .black)).foregroundStyle(SK.ink)
                        Text("\(e.scores.totalPts)").font(SK.font(13, .black)).foregroundStyle(SK.ink)
                    }
                    .frame(maxWidth: .infinity, minHeight: grown ? heights[min(max(e.place - 1, 0), 3)] : 20)
                    .background(UnevenRoundedRectangle(topLeadingRadius: 14, topTrailingRadius: 14).fill(colours[min(max(e.place - 1, 0), 3)]))
                }
                .accessibilityElement(children: .combine).accessibilityLabel("\(e.name) \(ShowUI.ordinal(e.place)) with \(e.scores.totalPts)")
            }
        }
        .padding(.horizontal, 10).padding(.top, 10)
        .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(ShowUI.stage.opacity(0.7)))
        .accessibilityIdentifier("results-podium")
    }

    private var bars: some View {
        let list = show.sim?.standings ?? []
        return ShowCard {
            VStack(spacing: 6) {
                HStack(spacing: 10) {
                    Text("Round by round").font(SK.font(15, .black)).foregroundStyle(SK.ink); Spacer()
                    legend("Look", SK.pink); legend("Dance", Color(hex: 0xB58BDB)); legend("Trick", SK.honeyDeep)
                }
                ForEach(Array(list.enumerated()), id: \.offset) { _, e in
                    HStack(spacing: 8) {
                        Text(e.name).font(SK.font(13, .black)).foregroundStyle(SK.ink).frame(width: 60, alignment: .leading).lineLimit(1).minimumScaleFactor(0.6)
                        GeometryReader { g in
                            HStack(spacing: 0) {
                                seg(e.scores.lookPts, SK.pink, g.size.width); seg(e.scores.dancePts, Color(hex: 0xB58BDB), g.size.width); seg(e.scores.trickPts, SK.honeyDeep, g.size.width)
                                Spacer(minLength: 0)
                            }
                            .background(Capsule().fill(ShowUI.bar)).clipShape(Capsule())
                        }
                        .frame(height: 22)
                        Text("\(e.scores.totalPts)").font(SK.font(14, .black)).foregroundStyle(SK.ink).monospacedDigit().frame(width: 34, alignment: .trailing)
                    }
                    .accessibilityElement(children: .combine).accessibilityLabel("\(e.name): Look \(e.scores.lookPts), Dance \(e.scores.dancePts), Trick \(e.scores.trickPts), total \(e.scores.totalPts)")
                }
                Text("Each bar is out of 300 (100 per round)").font(SK.font(10, .bold)).foregroundStyle(SK.muted).frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .accessibilityIdentifier("results-bars")
    }
    private func legend(_ s: String, _ c: Color) -> some View { HStack(spacing: 4) { Circle().fill(c).frame(width: 10, height: 10); Text(s).font(SK.font(11, .heavy)).foregroundStyle(SK.ink) } }
    private func seg(_ v: Int, _ c: Color, _ w: CGFloat) -> some View {
        Text(v > 24 ? "\(v)" : "").font(SK.font(10, .black)).foregroundStyle(SK.ink).frame(width: grown ? max(0, w * CGFloat(v) / 300) : 0, height: 22).background(c).clipped()
    }

    private var rewards: some View {
        let a = show.awards
        return VStack(spacing: 6) {
            HStack(spacing: 10) {
                HStack(spacing: 10) {
                    JellyCoinIcon(size: 36)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("+\(show.earned.coinText) JellyCoins").font(SK.font(20, .black)).foregroundStyle(SK.ink).lineLimit(1).minimumScaleFactor(0.7)
                        Text("\(ShowUI.ordinal(show.sim?.playerPlace ?? 4)) at \(show.rank.title)").font(SK.font(12, .heavy)).foregroundStyle(SK.ink)
                    }
                }
                .padding(10).frame(maxWidth: .infinity, alignment: .leading).background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(SK.sky))
                .accessibilityElement(children: .combine).accessibilityIdentifier("results-drops")
                HStack(spacing: 10) {
                    Image(systemName: "trophy.fill").font(.system(size: 26, weight: .black)).foregroundStyle(a?.cup == 1 ? ShowUI.goldDeep : a?.cup == 2 ? Color(hex: 0x9AA3B2) : a?.cup == 3 ? Color(hex: 0xC98B55) : SK.muted.opacity(0.35))
                    VStack(alignment: .leading, spacing: 1) {
                        Text(a?.cup.map { "\(show.rank.title) \($0 == 1 ? "gold" : $0 == 2 ? "silver" : "bronze") cup" } ?? (show.sim?.playerPlace ?? 4 <= 3 ? "Cup kept" : "No cup this time")).font(SK.font(14, .black)).foregroundStyle(SK.ink).lineLimit(2).minimumScaleFactor(0.7)
                        Text(a?.unlocked.map { "\($0.title) unlocked" } ?? (show.rank.above.map { show.progress.requirement($0) ?? "\($0.title) is open" } ?? "Top rank!")).font(SK.font(11, .heavy)).foregroundStyle(ShowUI.brownGold).lineLimit(2).minimumScaleFactor(0.7)
                    }
                }
                .padding(10).frame(maxWidth: .infinity, alignment: .leading).background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Color(hex: 0xFFE7A8)))
                .accessibilityElement(children: .combine).accessibilityIdentifier("results-cup")
            }
            if let a, !(a.stickers.isEmpty && a.rosette == nil) {
                FlowLayout(spacing: 6) {
                    ForEach(a.stickers, id: \.rawValue) { s in Text("Sticker: \(s.title)").font(SK.font(12, .black)).foregroundStyle(ShowUI.brownGold).padding(.horizontal, 10).padding(.vertical, 4).background(Capsule().fill(ShowUI.light)) }
                    if let r = a.rosette { Text("\(r.title) rosette").font(SK.font(12, .black)).foregroundStyle(Color(hex: 0x2E6B26)).padding(.horizontal, 10).padding(.vertical, 4).background(Capsule().fill(Color(hex: 0xE3F4DD))) }
                }
                .accessibilityIdentifier("results-stickers")
            }
        }
    }

    private var tip: some View {
        ShowCard(padding: 10) {
            HStack(spacing: 10) {
                Image(systemName: "lightbulb.fill").font(.system(size: 22, weight: .black)).foregroundStyle(SK.honeyDeep)
                (Text("Next time try: ").font(SK.font(13, .black)) + Text(show.sim?.tip ?? "").font(SK.font(13, .bold))).foregroundStyle(SK.ink).fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityIdentifier("results-tip")
    }

    private var buttons: some View {
        HStack(spacing: 10) {
            Button { AudioHub.shared.uiTap(); show.goHome(again: true) } label: {
                Text("Jelly Show again").font(SK.font(17, .black)).foregroundStyle(SK.ink).frame(maxWidth: .infinity, minHeight: 54).background(Capsule().fill(SK.cream))
            }.buttonStyle(.plain).accessibilityIdentifier("results-again")
            ShowCTA(title: "Done", id: "results-done", height: 54) { show.goHome() }
        }
    }
}

