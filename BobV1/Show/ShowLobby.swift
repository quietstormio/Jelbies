//
//  ShowLobby.swift
//  The Jelly Show lobby (Studio > Enter Jelly Show), rebuilt to the user-approved cream mockup (lobby/show.html #showcream): the theme poster on the purple stage, the rank carousel with
//  per-rank stage art, the Entrant card (chips, Look / Dance / Trick, the weakest-round tip, the estimate against the rivals), and the pinned Dress up / Start show bar. Shared pieces
//  are in Lobby/LobbyKit.swift; the stage art is drawn here from the mockup's SVG.
//

import SwiftUI

extension ShowRank {
    /// The line under the carousel for each rank.
    var lobbyBlurb: String {
        switch self {
        case .puddle: return "Judges a hat and shoes. The gentlest stage."
        case .pond: return "Adds a necklace. Still kind on the beat."
        case .lagoon: return "Adds glasses. Stricter on the beat."
        case .ocean: return "The whole outfit. Duchess Marmalade headlines."
        }
    }
}

// MARK: - stage art

/// The stage as the mockup draws it (a flat picture: wall, spotlight cone, platform, a motif, two curtains and a scalloped valance) in a `w` x `h` design box scaled to fill.
struct ShowStageArt: View {
    enum Kind { case poster, rank(ShowRank) }
    let kind: Kind
    private var design: CGSize { if case .poster = kind { return CGSize(width: 408, height: 122) }; return CGSize(width: 120, height: 82) }

    var body: some View {
        Canvas { ctx, size in
            let w = design.width, h = design.height
            var c = ctx
            c.scaleBy(x: size.width / w, y: size.height / h)
            func col(_ x: UInt32, _ a: Double = 1) -> Color { Color(hex: x).opacity(a) }
            c.fill(Path(CGRect(x: 0, y: 0, width: w, height: h)), with: .color(col(0x4E3D68)))
            var cone = Path(); cone.move(to: CGPoint(x: w * 0.5, y: 0)); cone.addLine(to: CGPoint(x: w * 0.30, y: h)); cone.addLine(to: CGPoint(x: w * 0.70, y: h)); cone.closeSubpath()
            c.fill(cone, with: .linearGradient(Gradient(colors: [col(0xFFF3C9, 0.30), col(0xFFF3C9, 0.06)]), startPoint: CGPoint(x: 0, y: 0), endPoint: CGPoint(x: 0, y: h)))
            c.fill(Path(ellipseIn: CGRect(x: w * 0.5 - w * 0.30, y: h * 0.93 - h * 0.12, width: w * 0.6, height: h * 0.24)), with: .color(col(0x6B5487)))
            motif(&c, w: w, h: h)
            let cw = w * 0.075
            var l = Path(); l.move(to: .zero); l.addLine(to: CGPoint(x: cw, y: 0)); l.addCurve(to: CGPoint(x: cw * 1.1, y: h), control1: CGPoint(x: cw * 1.25, y: h * 0.35), control2: CGPoint(x: cw * 0.7, y: h * 0.7)); l.addLine(to: CGPoint(x: 0, y: h)); l.closeSubpath()
            var r = Path(); r.move(to: CGPoint(x: w, y: 0)); r.addLine(to: CGPoint(x: w - cw, y: 0)); r.addCurve(to: CGPoint(x: w - cw * 1.1, y: h), control1: CGPoint(x: w - cw * 1.25, y: h * 0.35), control2: CGPoint(x: w - cw * 0.7, y: h * 0.7)); r.addLine(to: CGPoint(x: w, y: h)); r.closeSubpath()
            c.fill(l, with: .color(col(0xC25A78))); c.fill(r, with: .color(col(0xC25A78)))
            for x in [cw * 0.45, w - cw * 0.45] { var f = Path(); f.move(to: CGPoint(x: x, y: 0)); f.addLine(to: CGPoint(x: x, y: h)); c.stroke(f, with: .color(col(0xA84462, 0.6)), lineWidth: 1.2) }
            var x: CGFloat = 0
            while x < w - 0.1 { c.fill(Path(ellipseIn: CGRect(x: x + w / 18 - (w / 18 + 1), y: h * 0.02 - h * 0.09, width: 2 * (w / 18 + 1), height: 2 * h * 0.09)), with: .color(col(0xC25A78))); x += w / 9 }
        }
        .accessibilityHidden(true)
    }

    private func stars(_ c: inout GraphicsContext, _ pts: [(CGFloat, CGFloat, CGFloat)]) {
        for (x, y, r) in pts { c.fill(Path(ellipseIn: CGRect(x: x - r, y: y - r, width: 2 * r, height: 2 * r)), with: .color(Color(hex: 0xFFF3C9).opacity(0.85))) }
    }

    private func motif(_ c: inout GraphicsContext, w: CGFloat, h: CGFloat) {
        func col(_ x: UInt32, _ a: Double = 1) -> Color { Color(hex: x).opacity(a) }
        func ell(_ cx: CGFloat, _ cy: CGFloat, _ rx: CGFloat, _ ry: CGFloat) -> Path { Path(ellipseIn: CGRect(x: cx - rx, y: cy - ry, width: 2 * rx, height: 2 * ry)) }
        switch kind {
        case .poster: stars(&c, [(120, 28, 1.6), (300, 22, 1.3), (352, 58, 1.1), (96, 74, 1.1)])
        case .rank(.puddle):
            c.fill(ell(60, 72, 17, 4.2), with: .color(col(0x8FCBE4))); c.fill(ell(55, 71, 6, 1.4), with: .color(.white.opacity(0.6)))
            c.fill(SVG.path("M60 40 C63.5 45 65.5 48 65.5 51.5 a5.5 5.5 0 0 1 -11 0 C54.5 48 56.5 45 60 40 Z"), with: .color(col(0x8FCBE4)))
            stars(&c, [(28, 22, 1.4), (92, 26, 1.2)])
        case .rank(.pond):
            c.fill(ell(60, 72, 24, 5.5), with: .color(col(0x7CC4C9)))
            c.fill(SVG.path("M60 69.5 a10 3.4 0 1 0 0.01 0 Z"), with: .color(col(0x7FB384)))
            c.stroke(SVG.path("M60 66.5 L66 70"), with: .color(col(0x7CC4C9)), lineWidth: 1.6)
            c.fill(ell(56, 68.5, 2.6, 2.6), with: .color(col(0xF4A9C0))); c.fill(ell(56, 68.5, 1, 1), with: .color(col(0xFFE07A)))
            stars(&c, [(30, 24, 1.3), (90, 20, 1.4), (78, 36, 1)])
        case .rank(.lagoon):
            c.fill(ell(60, 73, 30, 6), with: .color(col(0x5CC3BE)))
            var g = c; g.translateBy(x: 70, y: 34)
            g.stroke(SVG.path("M6 38 C7 28 4 18 7 9"), with: .color(col(0xC9A36F)), style: StrokeStyle(lineWidth: 2.4, lineCap: .round))
            g.fill(SVG.path("M7 9 C2 6 -3 8 -5 12 C0 9 4 9 7 10 Z M7 9 C12 4 18 5 21 9 C16 7 12 8 7 10 Z M7 9 C5 3 7 -2 11 -4 C9 1 9 5 7.6 9.6 Z"), with: .color(col(0x7FB384)))
            stars(&c, [(26, 20, 1.4), (40, 34, 1), (94, 18, 1.2)])
        case .rank(.ocean):
            c.fill(SVG.path("M30 76 C34 62 48 58 56 62 C51 62 48 66 50 70 C52 73 57 72 58.5 69 C59 74 55 77 50 77 Z"), with: .color(col(0x4B86B9)))
            c.fill(SVG.path("M62 77 C66 64 80 60 88 64 C83 64 80 68 82 72 C84 75 89 74 90.5 71 C91 76 87 79 82 79 Z"), with: .color(col(0x5C9BCB)))
            let crown = SVG.path("M52 34 L55 27 L60 32 L65 27 L68 34 Z")
            c.fill(crown, with: .color(col(0xFFE07A))); c.stroke(crown, with: .color(col(0xF2B530)), style: StrokeStyle(lineWidth: 1, lineJoin: .miter))
            stars(&c, [(26, 18, 1.5), (38, 30, 1.1), (86, 22, 1.4), (96, 36, 1)])
        }
    }
}

// MARK: - the lobby

struct ShowLobby: View {
    let care: GameCare
    @Binding var who: Int
    var back: () -> Void
    var card: () -> Void
    var start: (ShowRank) -> Void
    @Environment(\.verticalSizeClass) private var vsc
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var howOpen = false
    @State private var wardrobeOpen = false
    @State private var hint = LobbyHint()
    private var compact: Bool { vsc == .compact }
    private var day: Int { GameCare.showDay }
    private var theme: ShowTheme { ShowSchedule.theme(dayKey: day) }
    private var tomorrow: ShowTheme { ShowSchedule.tomorrow(dayKey: day) }
    private var rank: ShowRank { care.show.progress.chosen }
    private var rivals: [ShowRival] { ShowRivalSource.rivals(dayKey: day, rank: rank, theme: theme, firstShow: care.show.progress.firstShowEver) }
    private var blocker: String? { care.showBlocker(jelly: who) }
    private var prof: JellyProfile? { care.jelly(who) }

    var body: some View {
        ZStack {
            LobbyScreen(header: AnyView(LobbyHeader(title: "Jelly Show", wallet: care.bath.wallet, backID: "show-back", helpID: "show-help", back: back, help: { setHow(true) })),
                        why: blocker, whyID: "show-why") {
                VStack(alignment: .leading, spacing: 0) {
                    poster
                    LobbyLabelRow(title: "Rank", trailing: "\(care.show.progress.unlockedRanks.count) of \(ShowRank.allCases.count) open").padding(.top, compact ? 8 : 16)
                    LobbyCarousel(bleed: !compact, scrollTo: rank.index >= 2 ? "rank-card-\(rank.rawValue)" : nil) {
                        ForEach(ShowRank.allCases, id: \.rawValue) { r in rankCard(r).id("rank-card-\(r.rawValue)") }
                    }
                    .accessibilityElement(children: .contain).accessibilityIdentifier("show-ranks")
                    if !compact { info }
                }
            } right: {
                if compact { info.padding(.top, -6).padding(.bottom, 4) }
                entrant.padding(.top, compact ? 0 : 16)
            } bar: {
                bar
            }
            .accessibilityHidden(howOpen)
            if howOpen {
                LobbyHowSheet(rows: [
                    (.three, "Three rounds", "Look, Dance and Trick, each scored out of 100."),
                    (.hanger, "Dress for the theme", "Things in today\u{2019}s style count most. The + style helps a little."),
                    (.drop, "Feed and shine", "Theme foods fill the jars. A Clean before the show adds Glow."),
                    (.trophy, "Win to open the next rank", "Or finish in the top two \(TrackPanel.words(ShowProgress.topTwoToUnlock)) times."),
                ], close: { setHow(false) })
                .zIndex(1)
            }
        }
        .accessibilityElement(children: .contain).accessibilityIdentifier("show-lobby")
        .sheet(isPresented: $wardrobeOpen) {
            WardrobeSheet(care: care, who: who, theme: theme, rank: rank) { wardrobeOpen = false }
                .presentationDetents(compact ? [.large] : [.medium, .large]).presentationBackground(SK.cream)
        }
        .onAppear { if UserDefaults.standard.string(forKey: "LobbyAuto") == "showHow" { howOpen = true } }          // capture aid: -LobbyAuto show | showHow
    }

    private func setHow(_ on: Bool) { withAnimation(reduceMotion ? nil : .easeOut(duration: 0.28)) { howOpen = on } }

    // MARK: poster

    private var poster: some View {
        let big = typeSize.isAccessibilitySize
        return ZStack(alignment: .bottomTrailing) {
            ShowStageArt(kind: .poster)
            VStack(alignment: .leading, spacing: 0) {
                Text("\(ShowUI.dayName(day).uppercased())'S THEME").font(SK.font(12, .black)).tracking(0.6).foregroundStyle(ShowUI.gold).lineLimit(1).minimumScaleFactor(0.7)
                Text(theme.title).font(SK.font(27, .black)).foregroundStyle(ShowUI.light).lineLimit(2).minimumScaleFactor(0.7).padding(.top, 2)
                FlowLayout(spacing: 6) {
                    tagChip(theme.main, "")
                    tagChip(theme.friend, "+ ")
                }
                .padding(.top, 7)
                if big { tomorrowView(alignment: .leading).padding(.top, 8) }
            }
            .padding(.leading, 30).padding(.trailing, 30).padding(.top, 15).padding(.bottom, big ? 13 : 14).frame(maxWidth: .infinity, alignment: .leading)
            if !big { tomorrowView(alignment: .trailing).padding(.trailing, 30).padding(.bottom, 13) }
        }
        .frame(minHeight: compact ? 96 : 122)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(ShowUI.dayName(day))'s theme: \(theme.title). \(theme.main.title), and \(theme.friend.title) helps a little. Tomorrow: \(tomorrow.title).")
        .accessibilityIdentifier("show-theme")
    }

    private func tagChip(_ t: WearTag, _ prefix: String) -> some View {
        Text("\(prefix)\(t.title)").font(SK.font(13.5, .black)).foregroundStyle(SK.ink).padding(.horizontal, 11).frame(minHeight: 26)
            .background(Capsule().fill(ShowUI.tag(t)))
    }

    private func tomorrowView(alignment: HorizontalAlignment) -> some View {
        VStack(alignment: alignment, spacing: 0) {
            Text("Tomorrow").font(SK.font(11.5, .heavy)).foregroundStyle(ShowUI.lilacPale)
            Text(tomorrow.title).font(SK.font(13.5, .black)).foregroundStyle(SK.cream).lineLimit(1).minimumScaleFactor(0.7)
        }
    }

    // MARK: ranks

    private func cupWord(_ n: Int) -> String { n == 1 ? "Gold cup" : n == 2 ? "Silver cup" : "Bronze cup" }
    private func rankSub(_ r: ShowRank) -> String {
        let prog = care.show.progress
        guard prog.unlocked(r) else { return "Win at \(r.below?.title ?? "")" }
        let base = r == .puddle ? "Starter" : "Open"
        if let cup = prog.trophies(character: prof?.character ?? who).cup(r) { return "\(base) \u{00B7} \(cupWord(cup))" }
        return base
    }

    private func rankCard(_ r: ShowRank) -> some View {
        let prog = care.show.progress
        let open = prog.unlocked(r), picked = r == rank
        let sub = rankSub(r)
        return Button {
            if open { AudioHub.shared.uiTap(); _ = care.chooseShowRank(r) } else { hint.show(prog.requirement(r) ?? "Win at \(r.below?.title ?? "")") }
        } label: {
            LobbyCarouselCard(name: r.title, sub: sub, selected: picked && open, locked: !open, artH: compact ? 66 : 82) { ShowStageArt(kind: .rank(r)) }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(open ? "\(r.title), \(sub.replacingOccurrences(of: " \u{00B7} ", with: ", "))" : "\(r.title), locked. Win at \(r.below?.title ?? "")")
        .accessibilityHint(open ? r.lobbyBlurb : (prog.requirement(r) ?? ""))
        .accessibilityAddTraits(picked ? .isSelected : [])
        .accessibilityIdentifier("rank-\(r.rawValue)")
    }

    /// Landscape shows only the first sentence on one line (the full blurb stays in VoiceOver).
    private var shortBlurb: String { rank.lobbyBlurb.components(separatedBy: ". ").first.map { $0.hasSuffix(".") ? $0 : $0 + "." } ?? rank.lobbyBlurb }

    private var info: some View {
        LobbyInfoLine(text: hint.text ?? (compact && !typeSize.isAccessibilitySize ? shortBlurb : rank.lobbyBlurb), textID: "show-blurb", pillsBelow: !compact || typeSize.isAccessibilitySize, squeeze: compact && hint.text == nil && !typeSize.isAccessibilitySize) {
            LobbyPill(label: "1st", amount: rank.drops(place: 1), gold: true)
            LobbyPill(label: "2nd", amount: rank.drops(place: 2))
            LobbyPill(label: "3rd", amount: rank.drops(place: 3))
        }
        .accessibilityElement(children: .contain).accessibilityIdentifier("show-prizes")
        .accessibilityLabel(rank.lobbyBlurb)
    }

    // MARK: entrant

    private var entrant: some View {
        let est = care.showEstimate(jelly: who, rank: rank, theme: theme)
        let p = care.showPlayerInput(jelly: who)
        let outfit = care.showOutfitTags(jelly: who)
        let items = rank.slotOrder.compactMap { outfit[$0] }
        let match = ShowScoring.outfitMatch(items: items, slots: rank.slots, theme: theme)
        let total = Int((est.total / 10).rounded()) * 10
        let name = prof?.name ?? p.name
        // the weakest round (ties: Look, Dance, Trick) and what to do about it
        let pts = [est.lookPts, est.dancePts, est.trickPts]
        let lowest = pts.firstIndex(of: pts.min() ?? 0) ?? 0
        let tip: String
        switch lowest {
        case 0: tip = match < 1 ? "Look is lowest. Wear \(theme.main.title) things." : (p.glow < 0.5 ? "Look is lowest. A Clean adds Glow." : "Look is lowest. \(theme.main.title) food helps.")
        case 1: tip = p.dance == nil ? "Dance is lowest. Learn a dance in the Studio." : "Dance is lowest. Practise in the Studio."
        default: tip = ShowTrickInfo.stageTricks.contains { p.tricks[$0] != nil } ? "Trick is lowest. Practise your tricks." : "Trick is lowest. Teach a trick."
        }
        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text("Entrant").font(SK.font(19, .black)).foregroundStyle(SK.ink).accessibilityAddTraits(.isHeader)
                Spacer(minLength: 8)
                Button { AudioHub.shared.uiTap(); card() } label: {
                    Text("\(name)'s card \u{203A}").font(SK.font(13.5, .heavy)).foregroundStyle(SK.muted).lineLimit(1).minimumScaleFactor(0.8).frame(minHeight: 44).contentShape(Rectangle())
                }.buttonStyle(.plain).padding(.vertical, -10).accessibilityLabel("\(name)'s card").accessibilityIdentifier("show-card")
            }
            .padding(.bottom, compact ? 8 : 12)
            if care.jellies.count > 1 { LobbyChips(care: care, selected: who) { who = $0 } }
            else if let pr = prof { LobbyChip(care: care, jelly: pr, selected: true) {}.allowsHitTesting(false) }
            VStack(spacing: 8) {
                roundRow("Look", est.lookPts, SK.pink)
                roundRow("Dance", est.dancePts, Color(hex: 0xB58BDB))
                roundRow("Trick", est.trickPts, SK.honeyDeep)
            }
            .padding(.top, compact ? 9 : 14)
            HStack(spacing: 7) {
                LobbyIcon(kind: .bulb, color: SK.ink).frame(width: 22, height: 22).background(Circle().fill(SK.honeyDeep.opacity(0.45)))
                Text(tip).font(SK.font(13, .heavy)).foregroundStyle(SK.muted).fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, compact ? 7 : 10).accessibilityElement(children: .combine).accessibilityIdentifier("show-tip")
            versus(name: name, total: total)
        }
        .lobbyCard(padding: compact ? EdgeInsets(top: 10, leading: 14, bottom: 11, trailing: 14) : EdgeInsets(top: 14, leading: 14, bottom: 14, trailing: 14))
        .accessibilityElement(children: .contain).accessibilityIdentifier("show-entrant")
    }

    private func roundRow(_ n: String, _ v: Int, _ c: Color) -> some View {
        HStack(spacing: 9) {
            Text(n).font(SK.font(15, .black)).foregroundStyle(SK.ink).lineLimit(1).minimumScaleFactor(0.7).frame(width: typeSize.isAccessibilitySize ? 86 : 52, alignment: .leading)
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(SK.ink.opacity(0.1))
                    Capsule().fill(c).frame(width: max(g.size.width * CGFloat(min(max(Float(v) / 100, 0), 1)), g.size.height))
                }
            }.frame(height: 10)
            Text("\(v)").font(SK.font(15, .black)).foregroundStyle(SK.ink).monospacedDigit().frame(minWidth: 30, alignment: .trailing)
        }
        .accessibilityElement(children: .ignore).accessibilityLabel("\(n) \(v) out of 100")
    }

    private func versus(name: String, total: Int) -> some View {
        let r = rank.rivalEstimate
        let rv = rivals
        let left = (Text(name).font(SK.font(14.5, .black)).foregroundStyle(SK.ink) + Text(" about \(total) ").font(SK.font(13.5, .heavy)).foregroundStyle(SK.muted) + Text("of 300").font(SK.font(11.5, .heavy)).foregroundStyle(SK.muted))
        let faces = HStack(spacing: -5) {
            ForEach(Array(rv.enumerated()), id: \.offset) { _, riv in
                JelbiePortrait(care: care, who: care.jellies.first?.id ?? 0, size: 24, border: .white, outerRing: 2, head: true, rival: riv)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Rivals today: " + rv.map { "\($0.name) the \($0.persona.title)" }.joined(separator: ", "))
        .accessibilityIdentifier("show-rivals")
        let right = HStack(spacing: 7) { Text("Rivals about \(r)").font(SK.font(13.5, .heavy)).foregroundStyle(SK.muted); faces }
        return VStack(alignment: .leading, spacing: 7) {
            ViewThatFits(in: .horizontal) {
                HStack { left.lineLimit(1); Spacer(minLength: 6); right }
                VStack(alignment: .leading, spacing: 6) { left; right }
            }
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(SK.ink.opacity(0.1))
                    Capsule().fill(SK.pinkStrong).frame(width: g.size.width * CGFloat(min(max(Double(total) / 300, 0), 1)))
                    RoundedRectangle(cornerRadius: 2).fill(Color(hex: 0x9C8AB5)).frame(width: 4, height: 20).offset(x: g.size.width * CGFloat(Double(r) / 300) - 2)
                }
            }.frame(height: 12)
        }
        .padding(.top, compact ? 8 : 12).overlay(alignment: .top) { Rectangle().fill(Color(hex: 0xE8DCC6)).frame(height: 2) }
        .padding(.top, compact ? 8 : 12)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(name) about \(total) out of 300. Rivals about \(r).")
        .accessibilityIdentifier("show-estimate")
    }

    // MARK: bar

    private var bar: some View {
        let off = blocker != nil
        let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(spacing: 10)) : AnyLayout(WeightedRow(weights: [1, 1.25], spacing: 12))
        return layout {
            Button { UIImpactFeedbackGenerator(style: .soft).impactOccurred(); AudioHub.shared.uiTap(); wardrobeOpen = true } label: {
                HStack(spacing: 9) {
                    LobbyIcon(kind: .hanger, color: SK.ink)
                    Text("Dress up").font(SK.font(19, .black)).lineLimit(1).minimumScaleFactor(0.6)
                }
                .foregroundStyle(off ? SK.muted : SK.ink).frame(maxWidth: .infinity, minHeight: 58)
                .background(Capsule().fill(Color.white.opacity(0.92)))
                .overlay(Capsule().strokeBorder(off ? SK.muted.opacity(0.4) : SK.ink, lineWidth: 3))
            }
            .buttonStyle(.plain).disabled(off).accessibilityIdentifier("show-dress")
            Button { UIImpactFeedbackGenerator(style: .soft).impactOccurred(); AudioHub.shared.uiConfirm(); start(rank) } label: {
                HStack(spacing: 9) {
                    LobbyIcon(kind: .star, color: .white)
                    Text("Start show").font(SK.font(19, .black)).lineLimit(1).minimumScaleFactor(0.6)
                }
                .foregroundStyle(.white).frame(maxWidth: .infinity, minHeight: 58)
                .background(Capsule().fill(off ? SK.muted.opacity(0.5) : SK.pinkStrong))
            }
            .buttonStyle(.plain).disabled(off).accessibilityIdentifier("show-start")
        }
    }
}
