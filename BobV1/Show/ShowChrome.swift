//
//  ShowChrome.swift
//  The Jelly Show's screen furniture over the 3D stage (the mockups ShowLook / ShowDance / ShowTrick / ShowResults.dc.html): the round header
//  with its three pips, the Look round's slot chips, wardrobe and live score, the Dance round's Cheer meter, prompt lane, flash and foot buttons,
//  the Trick round's turn chips, spotlight ring, meters, Glow Burst and trick cards, the results' podium, stacked bars, Drops, cup, stickers and
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
                if show.isPractice { PracticeChrome(care: care) }
                else {
                    switch show.round {
                    case .look: LookRound(care: care)
                    case .dance: DanceRound(care: care)
                    case .trick: TrickRound(care: care)
                    case .results: if show.trickStage == .performing { TrickRound(care: care) } else { ResultsScreen(care: care) }
                    }
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
                    Image(systemName: "xmark").font(.system(size: 17, weight: .semibold)).foregroundStyle(SK.ink)
                        .frame(width: 44, height: 44).background(Circle().fill(SK.cream))
                }.buttonStyle(.plain).accessibilityLabel("Leave the show").accessibilityIdentifier("show-quit")
            }
            VStack(alignment: .leading, spacing: 0) {
                Text(kicker ?? "ROUND \(round) OF 3 \u{00B7} \(show.rank.title.uppercased())").font(SK.font(12, .semibold)).foregroundStyle(ShowUI.gold).tracking(0.5)
                Text(title).font(SK.font(24, .semibold)).foregroundStyle(SK.cream)
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
    var body: some View {
        Text(text).font(SK.font(14, .semibold)).foregroundStyle(ShowUI.brownGold).lineLimit(1).minimumScaleFactor(0.7)
            .padding(.horizontal, 14).padding(.vertical, 6).background(Capsule().fill(ShowUI.light.opacity(0.95)))
    }
}

/// The cream card every round's numbers sit in.
struct ShowCard<Content: View>: View {
    var padding: CGFloat = 12
    @ViewBuilder var content: () -> Content
    var body: some View {
        content().padding(padding).frame(maxWidth: .infinity)
            .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(SK.cream.opacity(0.96)).shadow(color: .black.opacity(0.18), radius: 8, y: 3))
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
                        Text(s.rivals[i].name).font(SK.font(12, .semibold)).foregroundStyle(ShowUI.mist).lineLimit(1)
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

    var body: some View {
        let _ = show.revision
        return GeometryReader { g in
            let size = g.size
            let frame = ShowFrame.look
            let body = StageProject.body(ShowStage.playerSpot, frame: frame, size: size)
            ZStack(alignment: .top) {
                slots(body: body, size: size)
                VStack(spacing: 10) {
                    RoundHeader(care: care, round: 1, title: "Look")
                    HStack { if !compact { Spacer() }; StagePill(text: "\(show.theme.title): \(show.theme.main.title), friend \(show.theme.friend.title)"); Spacer() }
                    Spacer(minLength: 0)
                    if compact {
                        HStack(alignment: .bottom, spacing: 12) {
                            Spacer(minLength: 0)
                            VStack(spacing: 8) { wardrobe; score; cta }.frame(width: min(size.width * 0.52, 520))
                        }
                    } else {
                        Text("Gold glow: matches \(show.theme.main.title) \u{00B7} \(show.rank.slots) slots at \(show.rank.title)").font(SK.font(12, .semibold)).foregroundStyle(ShowUI.mist)
                        wardrobe
                        score
                        cta
                    }
                }
                .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 14)
            }
        }
    }

    /// The scored slots as tap chips either side of him (the rank's slots: left column, then right); a phone on its side keeps both columns on his left.
    private func slots(body: (centre: CGPoint, radius: CGFloat), size: CGSize) -> some View {
        let order = show.rank.slotOrder
        let outfit = care.store.outfit(show.playerID)
        var left = Array(order.prefix((order.count + 1) / 2)), right = Array(order.dropFirst((order.count + 1) / 2))
        if compact { left = order; right = [] }
        let dx = max(body.radius + 74, 96)
        return ZStack {
            ForEach(Array(left.enumerated()), id: \.offset) { k, s in
                SlotChip(slot: s, look: outfit[s], theme: show.theme) { tapSlot(s) }
                    .position(x: max(44, body.centre.x - dx - (compact && k % 2 == 1 ? 64 : 0)), y: body.centre.y - (compact ? 60 : 30) + CGFloat(compact ? k / 2 : k) * 72 + (compact && k % 2 == 1 ? 36 : 0))
            }
            ForEach(Array(right.enumerated()), id: \.offset) { k, s in
                SlotChip(slot: s, look: outfit[s], theme: show.theme) { tapSlot(s) }
                    .position(x: min(size.width - 44, body.centre.x + dx), y: body.centre.y - 30 + CGFloat(k) * 72)
            }
        }
    }
    private func tapSlot(_ s: WearSlot) {
        // tap a worn slot to take the piece off; an empty slot wears the best match owned for it
        if let l = care.store.worn(show.playerID, s) { care.store.takeOff(l.slot, from: show.playerID); AudioHub.shared.play(.shoeOn) }
        else {
            let owned = StoreCatalog.items.filter { $0.isWearable && care.store.owns($0) }.compactMap(\.wear).filter { $0.slot == s }
            if let best = owned.max(by: { show.theme.match($0.tags) < show.theme.match($1.tags) }) { care.store.wear(best, on: show.playerID); AudioHub.shared.play(.shoeOn) }
        }
        show.setOutfit(care.showOutfitTags(jelly: show.playerID))
    }

    private var wardrobe: some View {
        ShowCard(padding: 10) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline) { Text("Wardrobe").font(SK.font(16, .semibold)).foregroundStyle(SK.ink); Spacer(); Text("Tap to wear or swap").font(SK.font(12, .semibold)).foregroundStyle(SK.muted) }
                WardrobeStrip(care: care, who: show.playerID, theme: show.theme, slots: show.rank.slotOrder) { show.setOutfit(care.showOutfitTags(jelly: show.playerID)) }
            }
        }
        .accessibilityIdentifier("look-wardrobe")
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
                    Text("\(total)").font(SK.font(32, .semibold)).foregroundStyle(SK.ink).monospacedDigit().contentTransition(.numericText())
                    Text("Look / 100").font(SK.font(11, .semibold)).foregroundStyle(ShowUI.brownGold)
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
                Text(name).font(SK.font(14, .semibold)).foregroundStyle(SK.ink); Spacer()
                (Text("\(Int(v.rounded()))").font(SK.font(14, .semibold)) + Text(" / \(Int(max))").font(SK.font(11, .semibold)).foregroundColor(SK.muted)).foregroundStyle(SK.ink)
            }
            GeometryReader { g in ZStack(alignment: .leading) { Capsule().fill(ShowUI.bar); Capsule().fill(c).frame(width: Swift.max(4, g.size.width * CGFloat(v / max))) } }.frame(height: 10)
            Text(note).font(SK.font(11, .bold)).foregroundStyle(SK.muted).frame(maxWidth: .infinity, alignment: .leading).lineLimit(1).minimumScaleFactor(0.7)
        }
        .accessibilityElement(children: .combine)
    }

    private var cta: some View {
        ShowCTA(title: "Looks great. On to Dance", symbol: nil, id: "look-next", height: compact ? 50 : 60) { show.finishLook() }
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
            if show.showsCountdown { numeral("\(show.countdown)") }
            if show.showsGo { numeral("GO!") }
        }
        .animation(CareMenu.spring, value: show.beat)
    }

    private func press(_ foot: Int) { light.impactOccurred(intensity: 0.5); show.tap(foot: foot) }

    private var cheer: some View {
        let c = show.sim?.cheer ?? 0
        return ShowCard(padding: 10) {
            VStack(spacing: 6) {
                HStack(alignment: .firstTextBaseline) { Text("Your Cheer").font(SK.font(16, .semibold)).foregroundStyle(SK.ink); Spacer(); Text("\(Int((c * 100).rounded()))%").font(SK.font(20, .semibold)).foregroundStyle(SK.ink).monospacedDigit() }
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
            .font(SK.font(28, .semibold)).shadow(color: .black.opacity(0.4), radius: 4, y: 2)
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
        Text(s).font(SK.font(13, .semibold)).foregroundStyle(fg).monospacedDigit().padding(.horizontal, 10).padding(.vertical, 6).background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(bg))
    }

    private var next: some View {
        let d = show.sim?.danceScore ?? 0
        return VStack(spacing: 6) {
            Text("Dance \(Int(d.rounded())) / 100").font(SK.font(18, .semibold)).foregroundStyle(ShowUI.gold).accessibilityIdentifier("dance-score")
            ShowCTA(title: "Finish dance, on to Trick", id: "dance-next", height: 52) { show.finishDance() }.frame(maxWidth: 360)
        }
        .transition(.scale(scale: 0.9).combined(with: .opacity))
    }

    private func numeral(_ s: String) -> some View {
        Text(s).font(.system(size: s == "GO!" ? 96 : 120, weight: .semibold, design: .rounded)).foregroundStyle(.white)
            .shadow(color: SK.pink.opacity(0.9), radius: 0, x: 0, y: 5).shadow(color: .black.opacity(0.35), radius: 10, y: 6)
            .id(show.cueSerial).transition(.scale(scale: 1.6).combined(with: .opacity)).allowsHitTesting(false)
            .offset(y: compact ? 20 : 40)
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
        VStack(spacing: 2) {
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
                Text(label).font(SK.font(11, .semibold)).foregroundStyle(ShowUI.brownGold).fixedSize()
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
        TimelineView(.animation) { _ in
            let song = AudioHub.shared.songTime(of: show.track) ?? show.song
            let items = (show.isPractice ? show.practice?.visible(at: song) : show.sim?.dance?.visible(at: song)) ?? []
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
    private let rigid = UIImpactFeedbackGenerator(style: .rigid)

    var body: some View {
        let _ = show.revision
        return GeometryReader { g in
            let size = g.size
            let body = StageProject.body(ShowStage.playerSpot, frame: .trick, size: size)
            ZStack(alignment: .top) {
                ring(body: body)
                if show.burstFlash > 0 { Confetti(serial: show.burstFlash, at: body.centre).allowsHitTesting(false) }
                VStack(spacing: 8) {
                    RoundHeader(care: care, round: 3, title: "Trick", quits: false)
                    if compact {
                        HStack(alignment: .top, spacing: 12) {
                            VStack(alignment: .leading) { StagePill(text: hint); Spacer(minLength: 0) }
                            VStack(spacing: 8) { turns; meters; burst; cards }.frame(width: min(size.width * 0.52, 520))
                        }
                    } else {
                        turns
                        HStack { Spacer(); StagePill(text: hint); Spacer() }
                        Spacer(minLength: 0)
                        Text(show.trickStage == .ring ? "Tap anywhere when the gold ring hugs \(show.playerName)" : "Better timing, more points (up to +6)").font(SK.font(12, .semibold)).foregroundStyle(ShowUI.mist)
                        meters
                        burst
                        cards
                    }
                }
                .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 14)
            }
        }
    }

    private var hint: String {
        guard let s = show.sim else { return "" }
        switch show.trickStage {
        case .pick: return s.tricksDone ? "All three done!" : "Turn \(s.turnIndex + 1) of 3 \u{00B7} pick a trick"
        case .ring: return "Turn \(s.turnIndex + 1) of 3 \u{00B7} tap when the gold ring hugs \(show.playerName)"
        case .performing:
            guard let t = show.lastTurn else { return "" }
            return t.success ? "\(t.trick.title)! +\(t.points)\(t.burst ? " and Glow Burst +10" : "")" : "A cute flop. +\(t.points)"
        }
    }

    /// The spotlight ring round the Jelbie: a dashed outer circle and the gold ring closing on him; the whole stage is the tap.
    private func ring(body: (centre: CGPoint, radius: CGFloat)) -> some View {
        let outer = body.radius * 2.6, inner = body.radius * 1.15
        return ZStack {
            Circle().strokeBorder(ShowUI.light.opacity(0.6), style: StrokeStyle(lineWidth: 2.5, dash: [4, 7])).frame(width: outer * 2, height: outer * 2).position(body.centre)
            TimelineView(.animation(paused: show.trickStage != .ring)) { _ in
                let p = show.trickStage == .ring ? min(max(CGFloat(show.ringProgress), 0), 1.3) : 0
                let r = outer + (inner - outer) * min(p, 1)
                Circle().strokeBorder(p > 1 ? ShowUI.goldDeep.opacity(0.5) : ShowUI.gold, lineWidth: 5).frame(width: r * 2, height: r * 2).position(body.centre)
                    .opacity(show.trickStage == .ring ? 0.95 : 0)
            }
            if show.trickStage == .ring {
                Color.white.opacity(0.001).contentShape(Rectangle())
                    .onTapGesture { rigid.impactOccurred(intensity: 0.8); show.tapRing() }
                    .accessibilityLabel("Tap when the ring hugs \(show.playerName)").accessibilityHint("You will hear Now at the right moment")
                    .accessibilityIdentifier("trick-ring").accessibilityAddTraits(.isButton)
                    .accessibilityAction { rigid.impactOccurred(intensity: 0.8); show.tapRing() }
            }
        }
        .ignoresSafeArea()
    }

    private var turns: some View {
        let s = show.sim
        return HStack(spacing: 6) {
            ForEach(0..<3, id: \.self) { k in
                let t = (s?.turns.count ?? 0) > k ? s?.turns[k] : nil
                let now = (s?.turns.count ?? 0) == k && !(s?.tricksDone ?? false)
                HStack(spacing: 6) {
                    Text(t.map { "\(k + 1) \($0.trick.title)" } ?? "Turn \(k + 1)").font(SK.font(11, .semibold)).opacity(0.8)
                    Text(t.map { "+\($0.points)" } ?? (now ? "Your go" : "\u{2014}")).font(SK.font(15, .semibold))
                }
                .foregroundStyle(SK.ink).frame(maxWidth: .infinity, minHeight: 44)
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
            HStack(alignment: .firstTextBaseline) { Text(name).font(SK.font(15, .semibold)).foregroundStyle(SK.ink); Spacer(); Text("\(Int((v * 100).rounded()))%").font(SK.font(18, .semibold)).foregroundStyle(SK.ink).monospacedDigit() }
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(ShowUI.bar)
                    Capsule().fill(c).frame(width: max(0, g.size.width * CGFloat(min(max(v, 0), 1))))
                    RoundedRectangle(cornerRadius: 2).fill(SK.ink).frame(width: 3, height: 20).offset(x: g.size.width * CGFloat(tick) - 1.5)
                }
            }.frame(height: 14)
            Text(note).font(SK.font(11, .semibold)).foregroundStyle(SK.muted).frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine).accessibilityLabel("\(name) \(Int((v * 100).rounded())) percent. \(note)")
    }

    @ViewBuilder private var burst: some View {
        if let s = show.sim, s.burstUnlocked || s.burstUsed {
            let ready = s.burstReady, armed = !ready && !s.burstUsed
            Button { if ready { AudioHub.shared.uiConfirm(); show.armBurst() } } label: {
                HStack(spacing: 10) {
                    Image(systemName: "sparkles").font(.system(size: 24, weight: .semibold)).foregroundStyle(.white).shadow(color: SK.ink, radius: 1)
                    Text("Glow Burst \u{00B7} +10").font(SK.font(20, .semibold)).foregroundStyle(SK.ink)
                    Text(s.burstUsed ? "Used" : armed ? "Armed" : "Ready").font(SK.font(12, .semibold)).foregroundStyle(ShowUI.gold).padding(.horizontal, 8).padding(.vertical, 3).background(Capsule().fill(SK.ink))
                }
                .frame(maxWidth: .infinity, minHeight: 56)
                .background(Capsule().fill(s.burstUsed ? ShowUI.gold.opacity(0.4) : ShowUI.gold))
                .overlay(Capsule().strokeBorder(ShowUI.light, lineWidth: 3))
                .shadow(color: ShowUI.gold.opacity(s.burstUsed ? 0 : 0.7), radius: 14)
            }
            .buttonStyle(.plain).disabled(!ready)
            .accessibilityLabel("Glow Burst, \(s.burstUsed ? "used" : armed ? "armed for this trick" : "ready"). Plus 10 points").accessibilityIdentifier("trick-burst")
        } else if let s = show.sim {
            Text("Glow Burst needs Cheer 75% and Glow 50%\(s.player.glow < ShowScoring.burstGlow ? " (a Clean before the show)" : "")").font(SK.font(12, .semibold)).foregroundStyle(ShowUI.lilacPale)
        }
    }

    private var cards: some View {
        let s = show.sim
        let known = s?.knownTricks ?? []
        return VStack(alignment: .leading, spacing: 6) {
            if !compact { HStack(alignment: .firstTextBaseline) { Text("Pick your trick").font(SK.font(16, .semibold)).foregroundStyle(SK.cream); Spacer(); Text("Max 30 points per turn").font(SK.font(12, .semibold)).foregroundStyle(ShowUI.lilacPale) } }
            if known.isEmpty {
                ShowCard { Text("No tricks learned yet. Teach one by voice (the trick book), then come back. Each turn still scores a cute flop: 8 points.").font(SK.font(13, .bold)).foregroundStyle(SK.muted).fixedSize(horizontal: false, vertical: true) }
                if show.trickStage == .pick, let s, !s.tricksDone { ShowCTA(title: "Flop cutely", id: "trick-flop", height: 48) { show.pick(.sit) } }
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) { ForEach(known, id: \.rawValue) { t in card(t) } }.padding(.horizontal, 2).padding(.vertical, 4)
                }
            }
        }
        .accessibilityIdentifier("trick-cards")
    }
    private func card(_ t: VoiceTrick) -> some View {
        let s = show.sim!
        let used = s.usedTricks.contains(t), r = s.reliability(t), bonus = show.theme.trickBonus(ShowTrickInfo.tags(t))
        let tag = ShowTrickInfo.tags(t).first { $0 == show.theme.main } ?? ShowTrickInfo.tags(t).first { $0 == show.theme.friend }
        let live = show.trickStage == .pick && !s.tricksDone
        return Button { if live { AudioHub.shared.uiTap(); show.pick(t) } } label: {
            VStack(spacing: 4) {
                if !compact { Image(systemName: ShowTrickInfo.symbol(t)).font(.system(size: 26, weight: .semibold)).foregroundStyle(SK.ink) }
                Text(t.title).font(SK.font(16, .semibold)).foregroundStyle(SK.ink).lineLimit(1).minimumScaleFactor(0.7)
                if let tag { Text("\(tag.title) +\(bonus)").font(SK.font(11, .semibold)).foregroundStyle(SK.ink).padding(.horizontal, 8).padding(.vertical, 3).background(Capsule().fill(ShowUI.tag(tag))) }
                else { Text("No match").font(SK.font(11, .semibold)).foregroundStyle(SK.muted).padding(.horizontal, 8).padding(.vertical, 3).background(Capsule().fill(Color(hex: 0xECE8EE))) }
                GeometryReader { g in ZStack(alignment: .leading) { Capsule().fill(ShowUI.bar); Capsule().fill(r >= 0.7 ? SK.mint : SK.honeyDeep).frame(width: max(4, g.size.width * CGFloat(r))) } }.frame(height: 8)
                Text("Chance \(Int((r * 100).rounded()))%").font(SK.font(13, .semibold)).foregroundStyle(SK.ink)
                if !compact { Text(used ? "Used: base 12" : "Fresh: base 18").font(SK.font(10.5, .semibold)).foregroundStyle(SK.muted) }
            }
            .padding(.horizontal, 8).padding(.vertical, compact ? 6 : 10).frame(width: 112)
            .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(SK.cream.opacity(live ? 0.97 : 0.7)))
            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(tag == show.theme.main ? ShowUI.gold : .clear, lineWidth: 3))
        }
        .buttonStyle(.plain).disabled(!live)
        .accessibilityLabel("\(t.title): \(tag.map { "\($0.title) match plus \(bonus)" } ?? "no theme match"), \(Int((r * 100).rounded())) percent chance\(used ? ", used already" : "")")
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
            Text("Glow Burst!").playFont(26, .semibold).foregroundStyle(ShowUI.gold)
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
        TimelineView(.animation) { ctx in
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
                    Text("\(show.theme.title.uppercased()) \u{00B7} \(show.rank.title.uppercased())").font(SK.font(12, .semibold)).foregroundStyle(ShowUI.gold).tracking(0.5)
                    Text("Results").font(SK.font(24, .semibold)).foregroundStyle(SK.cream)
                }
                Spacer()
                Text(place == 1 ? "\(show.playerName) wins!" : "\(show.playerName) comes \(ShowUI.ordinal(place))").font(SK.font(15, .semibold)).foregroundStyle(SK.ink)
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
                            Image(systemName: "face.smiling.fill").font(.system(size: 26, weight: .semibold)).foregroundStyle(.white.opacity(0.85))
                        }
                        .frame(width: 52, height: 52).overlay(Circle().strokeBorder(ShowUI.gold, lineWidth: 3)).shadow(color: ShowUI.gold.opacity(0.7), radius: 10)
                    } else { RivalBlob(tint: e.tint, size: 50) }
                    Text(e.name).font(SK.font(e.name.count > 9 ? 10 : 13, .black)).foregroundStyle(e.isPlayer ? ShowUI.gold : ShowUI.mist).lineLimit(1).minimumScaleFactor(0.6)
                    VStack(spacing: 2) {
                        Text(ShowUI.ordinal(e.place)).font(SK.font(24, .semibold)).foregroundStyle(SK.ink)
                        Text("\(e.scores.totalPts)").font(SK.font(13, .semibold)).foregroundStyle(SK.ink)
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
                    Text("Round by round").font(SK.font(15, .semibold)).foregroundStyle(SK.ink); Spacer()
                    legend("Look", SK.pink); legend("Dance", Color(hex: 0xB58BDB)); legend("Trick", SK.honeyDeep)
                }
                ForEach(Array(list.enumerated()), id: \.offset) { _, e in
                    HStack(spacing: 8) {
                        Text(e.name).font(SK.font(13, .semibold)).foregroundStyle(SK.ink).frame(width: 60, alignment: .leading).lineLimit(1).minimumScaleFactor(0.6)
                        GeometryReader { g in
                            HStack(spacing: 0) {
                                seg(e.scores.lookPts, SK.pink, g.size.width); seg(e.scores.dancePts, Color(hex: 0xB58BDB), g.size.width); seg(e.scores.trickPts, SK.honeyDeep, g.size.width)
                                Spacer(minLength: 0)
                            }
                            .background(Capsule().fill(ShowUI.bar)).clipShape(Capsule())
                        }
                        .frame(height: 22)
                        Text("\(e.scores.totalPts)").font(SK.font(14, .semibold)).foregroundStyle(SK.ink).monospacedDigit().frame(width: 34, alignment: .trailing)
                    }
                    .accessibilityElement(children: .combine).accessibilityLabel("\(e.name): Look \(e.scores.lookPts), Dance \(e.scores.dancePts), Trick \(e.scores.trickPts), total \(e.scores.totalPts)")
                }
                Text("Each bar is out of 300 (100 per round)").font(SK.font(10, .bold)).foregroundStyle(SK.muted).frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .accessibilityIdentifier("results-bars")
    }
    private func legend(_ s: String, _ c: Color) -> some View { HStack(spacing: 4) { Circle().fill(c).frame(width: 10, height: 10); Text(s).font(SK.font(11, .semibold)).foregroundStyle(SK.ink) } }
    private func seg(_ v: Int, _ c: Color, _ w: CGFloat) -> some View {
        Text(v > 24 ? "\(v)" : "").font(SK.font(10, .semibold)).foregroundStyle(SK.ink).frame(width: grown ? max(0, w * CGFloat(v) / 300) : 0, height: 22).background(c).clipped()
    }

    private var rewards: some View {
        let a = show.awards
        return VStack(spacing: 6) {
            HStack(spacing: 10) {
                HStack(spacing: 10) {
                    Image(systemName: "drop.fill").font(.system(size: 26, weight: .semibold)).foregroundStyle(.white)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("+\(show.earned) Drops").font(SK.font(20, .semibold)).foregroundStyle(SK.ink).lineLimit(1).minimumScaleFactor(0.7)
                        Text("\(ShowUI.ordinal(show.sim?.playerPlace ?? 4)) at \(show.rank.title)").font(SK.font(12, .semibold)).foregroundStyle(SK.ink)
                    }
                }
                .padding(10).frame(maxWidth: .infinity, alignment: .leading).background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(SK.sky))
                .accessibilityElement(children: .combine).accessibilityIdentifier("results-drops")
                HStack(spacing: 10) {
                    Image(systemName: "trophy.fill").font(.system(size: 26, weight: .semibold)).foregroundStyle(a?.cup == 1 ? ShowUI.goldDeep : a?.cup == 2 ? Color(hex: 0x9AA3B2) : a?.cup == 3 ? Color(hex: 0xC98B55) : SK.muted.opacity(0.35))
                    VStack(alignment: .leading, spacing: 1) {
                        Text(a?.cup.map { "\(show.rank.title) \($0 == 1 ? "gold" : $0 == 2 ? "silver" : "bronze") cup" } ?? (show.sim?.playerPlace ?? 4 <= 3 ? "Cup kept" : "No cup this time")).font(SK.font(14, .semibold)).foregroundStyle(SK.ink).lineLimit(2).minimumScaleFactor(0.7)
                        Text(a?.unlocked.map { "\($0.title) unlocked" } ?? (show.rank.above.map { show.progress.requirement($0) ?? "\($0.title) is open" } ?? "Top rank!")).font(SK.font(11, .semibold)).foregroundStyle(ShowUI.brownGold).lineLimit(2).minimumScaleFactor(0.7)
                    }
                }
                .padding(10).frame(maxWidth: .infinity, alignment: .leading).background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Color(hex: 0xFFE7A8)))
                .accessibilityElement(children: .combine).accessibilityIdentifier("results-cup")
            }
            if let a, !(a.stickers.isEmpty && a.rosette == nil) {
                FlowLayout(spacing: 6) {
                    ForEach(a.stickers, id: \.rawValue) { s in Text("Sticker: \(s.title)").font(SK.font(12, .semibold)).foregroundStyle(ShowUI.brownGold).padding(.horizontal, 10).padding(.vertical, 4).background(Capsule().fill(ShowUI.light)) }
                    if let r = a.rosette { Text("\(r.title) rosette").font(SK.font(12, .semibold)).foregroundStyle(Color(hex: 0x2E6B26)).padding(.horizontal, 10).padding(.vertical, 4).background(Capsule().fill(Color(hex: 0xE3F4DD))) }
                }
                .accessibilityIdentifier("results-stickers")
            }
        }
    }

    private var tip: some View {
        ShowCard(padding: 10) {
            HStack(spacing: 10) {
                Image(systemName: "lightbulb.fill").font(.system(size: 22, weight: .semibold)).foregroundStyle(SK.honeyDeep)
                (Text("Next time try: ").font(SK.font(13, .semibold)) + Text(show.sim?.tip ?? "").font(SK.font(13, .bold))).foregroundStyle(SK.ink).fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityIdentifier("results-tip")
    }

    private var buttons: some View {
        HStack(spacing: 10) {
            Button { AudioHub.shared.uiTap(); show.goHome(again: true) } label: {
                Text("Show again").font(SK.font(17, .semibold)).foregroundStyle(SK.ink).frame(maxWidth: .infinity, minHeight: 54).background(Capsule().fill(SK.cream))
            }.buttonStyle(.plain).accessibilityIdentifier("results-again")
            ShowCTA(title: "Done", id: "results-done", height: 54) { show.goHome() }
        }
    }
}

// MARK: - the Studio's dance drill

struct PracticeChrome: View {
    let care: GameCare
    @Environment(\.verticalSizeClass) private var vsc
    private var compact: Bool { vsc == .compact }
    private var show: ShowFlow { care.show }
    private let light = UIImpactFeedbackGenerator(style: .light)

    var body: some View {
        ZStack {
            VStack(spacing: 8) {
                HStack(spacing: 10) {
                    Button { AudioHub.shared.uiTap(); show.goHome() } label: {
                        Image(systemName: "xmark").font(.system(size: 17, weight: .semibold)).foregroundStyle(SK.ink).frame(width: 44, height: 44).background(Circle().fill(SK.cream))
                    }.buttonStyle(.plain).accessibilityLabel("Stop practice").accessibilityIdentifier("practice-quit")
                    VStack(alignment: .leading, spacing: 0) {
                        Text("STUDIO \u{00B7} PRACTISE").font(SK.font(12, .semibold)).foregroundStyle(ShowUI.gold).tracking(0.5)
                        Text(show.practiceDance.title).font(SK.font(24, .semibold)).foregroundStyle(SK.cream)
                    }
                    Spacer()
                    let p = show.practice
                    Text("Beat \(min((p?.judged ?? 0) + 1, p?.total ?? ShowFlow.practicePrompts)) / \(p?.total ?? ShowFlow.practicePrompts)").font(SK.font(13, .semibold)).foregroundStyle(SK.ink).monospacedDigit().padding(.horizontal, 12).frame(height: 36).background(Capsule().fill(SK.cream))
                }
                Spacer(minLength: 0)
                if let r = show.practiceResult {
                    PracticeResultCard(result: r) { show.goHome() }.frame(maxWidth: 520)
                    Spacer(minLength: 0)
                } else if compact {
                    HStack(alignment: .bottom, spacing: 12) {
                        AssistFoot(side: 0, prefix: "show", live: show.buttonsLive, press: press).frame(width: 170, height: 140)
                        ZStack { flash.padding(.bottom, 58); PromptLane(care: care).padding(.top, 26) }.frame(height: 110)
                        AssistFoot(side: 1, prefix: "show", live: show.buttonsLive, press: press).frame(width: 170, height: 140)
                    }
                } else {
                    stats
                    ZStack { flash; PromptLane(care: care).padding(.top, 34) }.frame(height: 120)
                    AssistFeetRow(prefix: "show", live: show.buttonsLive, press: press)
                        .frame(height: 150)
                }
            }
            .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 14)
            .animation(CareMenu.spring, value: show.practiceResult != nil)
            if show.showsCountdown { numeral("\(show.countdown)") }
            if show.showsGo { numeral("GO!") }
        }
        .accessibilityIdentifier("practice-screen")
    }
    private func press(_ foot: Int) { light.impactOccurred(intensity: 0.5); show.tap(foot: foot) }

    private var stats: some View {
        let p = show.practice
        return HStack(spacing: 8) {
            chip("Streak \(p?.streak ?? 0)", bg: Color(hex: 0xFFE7A8), fg: ShowUI.brownGold)
            chip("Perfect \(p?.perfects ?? 0)", bg: Color(hex: 0xE3F4DD), fg: Color(hex: 0x2E6B26))
            chip("Slip \(p?.misses ?? 0)", bg: Color(hex: 0xF2ECE6), fg: SK.muted)
            Spacer(minLength: 0)
        }
        .padding(10).background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(SK.cream.opacity(0.94)))
        .accessibilityIdentifier("practice-stats")
    }
    private func chip(_ s: String, bg: Color, fg: Color) -> some View {
        Text(s).font(SK.font(13, .semibold)).foregroundStyle(fg).monospacedDigit().padding(.horizontal, 10).padding(.vertical, 4).background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(bg))
    }
    private var flash: some View {
        VStack {
            Group {
                switch show.flash { case .perfect?: Text("Perfect!").foregroundStyle(ShowUI.gold); case .good?: Text("Good").foregroundStyle(.white); case .miss?: Text("Slip").foregroundStyle(ShowUI.mist); case nil: Text(" ") }
            }
            .font(SK.font(26, .semibold)).shadow(color: .black.opacity(0.4), radius: 4, y: 2).id(show.flashSerial).transition(.scale(scale: 1.4).combined(with: .opacity))
            Spacer()
        }
        .animation(.easeOut(duration: 0.12), value: show.flashSerial).allowsHitTesting(false)
    }
    private func numeral(_ s: String) -> some View {
        Text(s).font(.system(size: s == "GO!" ? 96 : 120, weight: .semibold, design: .rounded)).foregroundStyle(.white)
            .shadow(color: SK.pink.opacity(0.9), radius: 0, x: 0, y: 5).shadow(color: .black.opacity(0.35), radius: 10, y: 6)
            .id(show.cueSerial).transition(.scale(scale: 1.6).combined(with: .opacity)).allowsHitTesting(false).offset(y: compact ? 20 : 40)
    }
}

/// The dance drill's results: the grades, the dance's skill bar filling from before to after, Pep.
struct PracticeResultCard: View {
    let result: DancePracticeResult
    var done: () -> Void
    @State private var shown = false
    @Environment(\.verticalSizeClass) private var vsc
    var body: some View {
        let r = result
        VStack(spacing: vsc == .compact ? 6 : 12) {
            Text(r.accuracy >= 0.75 ? "Great dancing!" : r.accuracy >= 0.45 ? "Nice moves!" : "Keep practising!").font(SK.font(vsc == .compact ? 22 : 28, .black)).foregroundStyle(SK.ink)
            HStack(spacing: 8) {
                chip("Perfect \(r.perfects)", bg: Color(hex: 0xE3F4DD), fg: Color(hex: 0x2E6B26))
                chip("Good \(r.goods)", bg: Color(hex: 0xFFE7A8), fg: ShowUI.brownGold)
                chip("Slip \(r.misses)", bg: Color(hex: 0xF2ECE6), fg: SK.muted)
            }
            VStack(spacing: 4) {
                HStack {
                    Text(r.dance.title).font(SK.font(16, .semibold)).foregroundStyle(SK.ink); Spacer()
                    Text("+\(DrillResultCard.points(r.gain)) \(r.dance.title)").font(SK.font(16, .semibold)).foregroundStyle(Color(hex: 0xC0603D)).monospacedDigit().accessibilityIdentifier("practice-gain")
                }
                GeometryReader { g in
                    let v = shown ? r.after : r.before
                    ZStack(alignment: .leading) {
                        Capsule().fill(ShowUI.bar)
                        Capsule().fill(Color(hex: 0xB58BDB)).frame(width: max(14, g.size.width * CGFloat(min(max(v, 0), 1))))
                        Capsule().fill(.white.opacity(0.55)).frame(width: 3, height: 14).offset(x: max(14, g.size.width * CGFloat(r.before)) - 3)
                    }
                }.frame(height: 16)
                Text("Dance skill is 30% of the show's Dance round.").font(SK.font(11, .bold)).foregroundStyle(SK.muted)
            }
            HStack(spacing: 6) {
                ForEach(0..<TrainingTuning.fullSessions, id: \.self) { i in Circle().fill(i < r.pepLeft ? SK.honey : SK.ink.opacity(0.12)).frame(width: 14, height: 14) }
                Text(r.pepLeft > 0 ? "Pep left today" : "Pep used up. Practice still helps, just less.").font(SK.font(12, .bold)).foregroundStyle(SK.muted)
            }
            Button { UIImpactFeedbackGenerator(style: .soft).impactOccurred(); AudioHub.shared.uiTap(); done() } label: {
                Text("Done").font(SK.font(20, .semibold)).foregroundStyle(SK.ink).padding(.horizontal, 44).padding(.vertical, vsc == .compact ? 8 : 12).background(Capsule().fill(ShowUI.gold))
            }
            .buttonStyle(.plain).accessibilityIdentifier("practice-done")
        }
        .padding(.horizontal, 20).padding(.vertical, vsc == .compact ? 10 : 18)
        .background(RoundedRectangle(cornerRadius: 30, style: .continuous).fill(SK.cream).shadow(color: .black.opacity(0.3), radius: 16, y: 8))
        .accessibilityElement(children: .contain).accessibilityIdentifier("practice-card")
        .onAppear { withAnimation(.easeOut(duration: 1.3).delay(0.35)) { shown = true } }
    }
    private func chip(_ s: String, bg: Color, fg: Color) -> some View {
        Text(s).font(SK.font(13, .semibold)).foregroundStyle(fg).padding(.horizontal, 10).padding(.vertical, 4).background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(bg))
    }
}
