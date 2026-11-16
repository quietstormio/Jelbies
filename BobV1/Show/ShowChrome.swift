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

    var body: some View {
        ZStack {
            VStack(spacing: 8) {
                RoundHeader(care: care, round: 2, title: "Dance", quits: false)
                HStack { Spacer(); RivalPodium(care: care); Spacer() }
                Spacer(minLength: 0)
                if compact {
                    HStack(alignment: .bottom, spacing: 12) {
                        AssistFoot(side: 0, prefix: "show", live: show.buttonsLive, press: press).frame(width: 170, height: 140)
                        VStack(spacing: 8) {
                            cheer
                            ZStack { flash.padding(.bottom, 58); lane.padding(.top, 26) }.frame(height: 110)
                            stats
                            if show.beat == .danced { next }
                        }
                        AssistFoot(side: 1, prefix: "show", live: show.buttonsLive, press: press).frame(width: 170, height: 140)
                    }
                } else {
                    cheer
                    ZStack { flash; lane.padding(.top, 34) }.frame(height: 120)
                    stats
                    Text(show.rank.kindTiming ? "\(show.rank.title) timing is kind: Perfect within 80 ms." : "Perfect within 60 ms: tap right on the beat.").font(SK.font(12, .bold)).foregroundStyle(ShowUI.lilacPale)
                    if show.beat == .danced { next } else {
                        AssistFeetRow(prefix: "show", live: show.buttonsLive, press: press)
                            .frame(height: 150)
                    }
                }
            }
            .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 14)
            if !PadLayout.isPad {
                if show.showsCountdown { numeral("\(show.countdown)") }
                if show.showsGo { numeral("GO!") }
            }
        }
        .overlay {
            // iPad: the count sits at a third of the screen height (the cheer bar and lane are in the lower half, in either orientation), never over them
            if PadLayout.isPad {
                GeometryReader { g in
                    ZStack {
                        if show.showsCountdown { numeral("\(show.countdown)") }
                        if show.showsGo { numeral("GO!") }
                    }
                    .position(x: g.size.width / 2, y: g.size.height * 0.3)
                }
            }
        }
        .animation(CareMenu.spring, value: show.beat)
    }

    private func press(_ foot: Int) { light.impactOccurred(intensity: 0.5); show.tap(foot: foot) }

    private var cheer: some View {
        let c = show.sim?.cheer ?? 0
        return ShowCard(padding: 10) {
            VStack(spacing: 6) {
                HStack(alignment: .firstTextBaseline) { Text("Your Cheer").font(SK.font(16, .black)).foregroundStyle(SK.ink); Spacer(); Text("\(Int((c * 100).rounded()))%").font(SK.font(20, .black)).foregroundStyle(SK.ink).monospacedDigit() }
                CheerMeter(value: c, tick: ShowScoring.burstCheer, color: SK.pink, label: "75% unlocks Glow Burst")
            }
        }
        .accessibilityElement(children: .combine).accessibilityLabel("Cheer \(Int((c * 100).rounded())) percent").accessibilityIdentifier("dance-cheer")
    }

    private var flash: some View {
        VStack {
            Group {
                switch show.flash {
                case .perfect?: Text("Perfect!").foregroundStyle(ShowUI.gold)
                case .good?: Text("Good").foregroundStyle(.white)
                case .miss?: Text("Slip").foregroundStyle(ShowUI.mist)
                case nil: Text(" ")
                }
            }
            .font(SK.font(28, .black)).shadow(color: .black.opacity(0.4), radius: 4, y: 2)
            .id(show.flashSerial).transition(.scale(scale: 1.4).combined(with: .opacity))
            .accessibilityIdentifier("dance-flash")
            Spacer()
        }
        .animation(.easeOut(duration: 0.12), value: show.flashSerial)
        .allowsHitTesting(false)
    }

    private var lane: some View { PromptLane(care: care).accessibilityIdentifier("dance-prompts") }

    private var stats: some View {
        let d = show.sim?.dance
        return HStack(spacing: 8) {
            chip("Beat \(min((d?.judged ?? 0) + 1, d?.total ?? show.rank.promptCount)) / \(d?.total ?? show.rank.promptCount)", bg: SK.cream, fg: SK.ink)
            chip("Perfect \(d?.perfects ?? 0)", bg: Color(hex: 0xE3F4DD), fg: Color(hex: 0x2E6B26))
            chip("Good \(d?.goods ?? 0)", bg: Color(hex: 0xFFE7A8), fg: ShowUI.brownGold)
            chip("Slip \(d?.misses ?? 0)", bg: Color(hex: 0xF2ECE6), fg: SK.muted)
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine).accessibilityIdentifier("dance-stats")
    }
    private func chip(_ s: String, bg: Color, fg: Color) -> some View {
        Text(s).font(SK.font(13, .black)).foregroundStyle(fg).monospacedDigit().padding(.horizontal, 10).padding(.vertical, 6).background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(bg))
    }

    private var next: some View {
        let d = show.sim?.danceScore ?? 0
        return VStack(spacing: 6) {
            Text("Dance \(Int(d.rounded())) / 100").font(SK.font(18, .black)).foregroundStyle(ShowUI.gold).accessibilityIdentifier("dance-score")
            ShowCTA(title: "Finish dance, on to Trick", id: "dance-next", height: 52) { show.finishDance() }.frame(maxWidth: 360)
        }
        .transition(.scale(scale: 0.9).combined(with: .opacity))
    }

    private func numeral(_ s: String) -> some View {
        Text(s).font(.system(size: s == "GO!" ? 96 : 120, weight: .heavy, design: .rounded)).foregroundStyle(.white)
            .shadow(color: SK.pink.opacity(0.9), radius: 0, x: 0, y: 3).shadow(color: .black.opacity(0.35), radius: 6, y: 3)
            .id(show.cueSerial).transition(.scale(scale: 1.6).combined(with: .opacity)).allowsHitTesting(false)
            .offset(y: PadLayout.isPad ? 0 : (compact ? 20 : 40))
            .accessibilityIdentifier("show-count")
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

/// The L / R prompts scrolling toward the ring, on the music's clock (the drill's lane, on the show's grid).
struct PromptLane: View {
    let care: GameCare
    var body: some View {
        let show = care.show
        TimelineView(.animation(minimumInterval: 1.0 / 60)) { _ in
            let song = show.danceNow()
            let items = show.sim?.dance?.visible(at: song) ?? []
            ZStack(alignment: .leading) {
                Capsule().fill(Color(red: 0.08, green: 0.05, blue: 0.13).opacity(0.6))
                Circle().strokeBorder(Color(hex: 0xFFF6EC), lineWidth: 4).frame(width: 60, height: 60).padding(.leading, 14)
                ForEach(items, id: \.prompt.index) { it in
                    let near = it.ahead < 0.5
                    Text(it.prompt.foot == 0 ? "L" : "R").font(SK.font(near ? 22 : 18, .black)).foregroundStyle(.white)
                        .frame(width: near ? 54 : 46, height: near ? 54 : 46)
                        .background(Circle().fill(it.prompt.foot == 0 ? SK.sky : SK.pink))
                        .opacity(max(0.4, 1 - 0.13 * max(it.ahead, 0)))
                        .offset(x: 14 + 30 - (near ? 27 : 23) + CGFloat(max(it.ahead, -0.3)) * 62)
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
            let body = StageProject.body(ShowStage.playerSpot, frame: .trick(pad: PadLayout.isPad), size: size)
            ZStack(alignment: .top) {
                if show.burstFlash > 0 { Confetti(serial: show.burstFlash, at: body.centre).allowsHitTesting(false) }
                if compact {
                    // a phone on its side: the contestant has the left half; turn chips, Glow Burst and the menu (or the entrant's card) are the right column
                    HStack(alignment: .top, spacing: 12) {
                        VStack(alignment: .leading, spacing: 8) {
                            SideHeader(round: 3, title: "Trick", kicker: "ROUND 3 OF 3")
                            if let h = hint { StagePill(text: h) }
                            Spacer(minLength: 0)
                        }
                        Spacer(minLength: 0)
                        VStack(spacing: 8) {
                            turns
                            if rivalsOn { rivalPanel(full: full) } else if show.trickStage == .pick { burst(height: 52); menuBox(rowCap: 4) }
                            Spacer(minLength: 0)
                        }
                        .frame(width: size.width * 0.5)
                    }
                    .padding(.top, 14).padding(.bottom, 4)
                } else if PadLayout.isPad && size.width > size.height {
                    // iPad landscape: the stage fills the left ~55% (the camera frame puts the Jelbies there); chips, hint and the menu / entrant card are a clear right column
                    VStack(spacing: 8) {
                        RoundHeader(care: care, round: 3, title: "Trick", kicker: "ROUND 3 OF 3", quits: false)
                        HStack(alignment: .top, spacing: 24) {
                            Color.clear.frame(width: size.width * 0.55 - 16)
                            VStack(spacing: 10) {
                                turns
                                if let h = hint { StagePill(text: h, scale: sc) }
                                Spacer(minLength: 0)
                                if rivalsOn { rivalPanel(full: full) } else if show.trickStage == .pick {
                                    burst(height: 56 * sc)
                                    menuBox(rowCap: 6)
                                }
                            }
                            .frame(maxWidth: 560)
                        }
                    }
                    .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 24 + g.safeAreaInsets.bottom)
                } else {
                    VStack(spacing: 14) {
                        RoundHeader(care: care, round: 3, title: "Trick", kicker: "ROUND 3 OF 3", quits: false)
                        turns.padReadable(760)
                        if let h = hint { StagePill(text: h, scale: sc) }
                        if rivalsOn {
                            rivalPanel(full: full).padReadable(760)
                        } else {
                            Spacer(minLength: 0)
                            if show.trickStage == .pick {
                                VStack(spacing: 14) { burst(height: 58 * sc); menuBox(rowCap: nil) }.padReadable(760)
                            }
                        }
                    }
                    .padding(.horizontal, 16).padding(.top, 0).padding(.bottom, PadLayout.isPad ? 24 + g.safeAreaInsets.bottom : (rivalsOn ? 4 : 36))
                }
            }
        }
    }

    /// The flash over the stage while he performs ("Jumping jacks! +24"); nothing otherwise.
    private var hint: String? {
        guard show.sim != nil, show.trickStage == .performing, let t = show.lastTurn else { return show.sim?.tricksDone == true && show.trickStage == .pick ? "All three done!" : nil }
        return t.success ? "\(t.trick.title)! +\(t.points)\(t.burst ? " and Glow Burst +10" : "")" : "A cute flop. +\(t.points)"
    }

    private var rivalsOn: Bool { show.trickStage == .rivals }

    /// An entrant's turn: the card (name, trick, stars, points; tap it to skip just her), the row of who is next, and the big Skip.
    private func rivalPanel(full: CGSize) -> some View {
        let s = show.sim
        let k = compact ? CGFloat(0) : full.height / 874
        return VStack(spacing: (compact ? 8 : 0) * sc) {
            if !compact { Color.clear.frame(height: max(0, 254 * k - 14) * (PadLayout.isPad ? 0.9 : 1)) }
            Button { AudioHub.shared.uiTap(); show.skipCurrentRival() } label: { rivalBanner }
                .buttonStyle(.plain)
                .accessibilityIdentifier("rival-banner")
            if let s {
                if !compact { Color.clear.frame(height: 74 * k) }
                WhoIsNext(names: s.rivals.map(\.name), tints: s.rivals.map(\.tint), current: show.rivalNow?.rival,
                          size: (compact ? 40 : 60) * sc, spacing: compact ? 20 : 34 * sc, font: (compact ? 13 : 16) * sc)
                    .frame(maxWidth: .infinity)
                    .padding(.top, compact ? 4 : 0)
            }
            if !compact { Spacer(minLength: 0) }
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
            .accessibilityLabel("Skip").accessibilityIdentifier("rivals-skip")
        }
    }
    private var rivalBanner: some View {
        let n = show.rivalNow, s = show.sim
        return Group {
            if let n, let s {
                let r = s.rivals[n.rival], t = n.turn, stars = ShowTrickInfo.difficulty(t.trick)
                HStack(spacing: 14 * sc) {
                    EntrantBubble(tint: r.tint, size: (compact ? 40 : 56) * sc)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(r.name).font(SK.font((compact ? 19 : 24) * sc, .black)).foregroundStyle(SK.ink).lineLimit(1).minimumScaleFactor(0.7)
                        HStack(spacing: 6) {
                            Text(t.trick.title).font(SK.font((compact ? 14 : 17) * sc, .heavy)).foregroundStyle(SK.ink).lineLimit(1).minimumScaleFactor(0.7)
                            StarRow(n: stars, size: 12 * sc)
                        }
                    }
                    Spacer(minLength: 4)
                    Text(show.rivalScored ? "+\(t.points)" : "\u{2026}").font(SK.font((compact ? 26 : 34) * sc, .black)).foregroundStyle(SK.ink).monospacedDigit()
                }
            } else {
                Text(show.rivalRound < 2 ? "Your turn next" : " ").font(SK.font(18 * sc, .black)).foregroundStyle(SK.ink).frame(maxWidth: .infinity, alignment: .center)
            }
        }
        .padding(.horizontal, 18 * sc).frame(maxWidth: .infinity, minHeight: (compact ? 66 : 96) * sc)
        .background(RoundedRectangle(cornerRadius: 24 * sc, style: .continuous).fill(SK.cream.opacity(0.97)))
        .overlay(RoundedRectangle(cornerRadius: 24 * sc, style: .continuous).strokeBorder(ShowUI.lilac, lineWidth: 3))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(rivalBannerLabel)
        .accessibilityHint("Skips just this turn")
        .accessibilityAddTraits(.isButton)
    }
    private var rivalBannerLabel: String {
        guard let n = show.rivalNow, let s = show.sim else { return "Your turn next" }
        let t = n.turn, stars = ShowTrickInfo.difficulty(t.trick)
        let tail = show.rivalScored ? (t.success ? ", \(t.points) points" : ", a cute flop, \(t.points) points") : ""
        return "\(s.rivals[n.rival].name), \(t.trick.title), \(stars) star\(stars == 1 ? "" : "s")\(tail)"
    }

    /// One row of three: only ONE capsule is gold, the one that is happening now (his go, his trick landing, or the entrant on stage with her name).
    private var turns: some View {
        let s = show.sim
        let done = s?.turns.count ?? 0
        let stage = show.trickStage
        return HStack(spacing: 8) {
            ForEach(0..<3, id: \.self) { k in
                let turn = done > k ? s?.turns[k] : nil
                let playerBack = stage == .rivals && show.rivalStep == .playerBack          // (she is walking back: the entrant's turn is over, his next go is next)
                let entrantNow = stage == .rivals && show.rivalRound == k && !playerBack
                let nextGo = playerBack && k == show.rivalRound + 1 && k < 3
                let now: Bool = entrantNow || nextGo || (stage == .performing && k == done - 1) || (stage == .pick && !(s?.tricksDone ?? false) && k == done)
                let text: String = {
                    if entrantNow {
                        if let i = show.rivalTurn, let s { return s.rivals[i].name }
                        return "\u{2026}"
                    }
                    if let turn { return "+\(turn.points)" }
                    return now ? "Your go" : "\(k + 1)"
                }()
                TurnChip(text: text, now: now, scale: sc, height: compact ? 42 : 46)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Turn \(k + 1): \(text)\(now ? ", now" : "")")
            }
        }
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
            VStack(spacing: compact ? 6 : 8) { ForEach(known, id: \.rawValue) { t in row(t, live: live) } }.padding(.vertical, 2)
        }
        .scrollBounceBehavior(.basedOnSize)
        .frame(maxHeight: Self.menuHeight(rows: min(known.count, cap), compact: compact, scale: sc))
        .modifier(SoftBottomFade(on: known.count > cap))
        .accessibilityIdentifier("trick-cards")
    }
    /// The rows' height (68 pt, 59 on a phone on its side, 8 / 6 pt gaps).
    static func menuHeight(rows: Int, compact: Bool, scale: CGFloat = 1) -> CGFloat {
        let row: CGFloat = (compact ? 59 : 68) * scale, gap: CGFloat = compact ? 6 : 8
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
            .padding(.horizontal, 16 * sc).frame(maxWidth: .infinity, minHeight: (compact ? 59 : 68) * sc)
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
