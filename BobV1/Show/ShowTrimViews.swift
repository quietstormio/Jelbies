//
//  ShowTrimViews.swift
//  Small views of the trimmed Look / Trick / Results screens (the approved after-boards: Look, Trick pick, an entrant's turn, Results, Trick in landscape):
//  the theme pill, the turn row, the entrants' bubbles, the star row, the phone-on-its-side header, the short Results tip.
//  New views live here so ShowChrome.swift keeps small hunks (a sibling branch edits that file's Dance part).
//

import SwiftUI

/// "Judges love [Sporty]": the theme as one pill, the main tag in its own colour.
struct ThemePill: View {
    var tag: WearTag
    var scale: CGFloat = 1
    var body: some View {
        HStack(spacing: 8 * scale) {
            Text("Judges love").font(SK.font(14 * scale, .black)).foregroundStyle(ShowUI.brownGold)
            Text(tag.title).font(SK.font(13 * scale, .black)).foregroundStyle(SK.ink)
                .padding(.horizontal, 10 * scale).padding(.vertical, 3 * scale).background(Capsule().fill(ShowUI.tag(tag)))
        }
        .lineLimit(1)
        .padding(.leading, 16 * scale).padding(.trailing, 6 * scale).padding(.vertical, 5 * scale)
        .background(Capsule().fill(ShowUI.light.opacity(0.95)))
        .accessibilityElement(children: .combine).accessibilityLabel("Judges love \(tag.title)").accessibilityIdentifier("look-theme")
    }
}

/// Three stars, `n` filled.
struct StarRow: View {
    var n: Int
    var size: CGFloat = 13
    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<3, id: \.self) { k in
                Image(systemName: k < n ? "star.fill" : "star").font(.system(size: size, weight: .black)).foregroundStyle(k < n ? ShowUI.goldDeep : SK.muted.opacity(0.4))
            }
        }
        .accessibilityHidden(true)
    }
}

/// One capsule of the turn row: gold when it is happening now (only ever one), cream otherwise.
struct TurnChip: View {
    var text: String
    var now: Bool
    var scale: CGFloat = 1
    var height: CGFloat = 46
    var font: CGFloat = 17
    var body: some View {
        Text(text).font(JFont.scaled(font * scale, .black, cap: 1.3)).foregroundStyle(SK.ink).lineLimit(1).minimumScaleFactor(0.6).padding(.horizontal, 8)
            .frame(maxWidth: .infinity, minHeight: height * scale)
            .background(Capsule().fill(now ? ShowUI.gold : SK.cream.opacity(0.95)))
            .overlay(Capsule().strokeBorder(now ? ShowUI.goldDeep : .clear, lineWidth: 3))
    }
}

/// An entrant as a round bubble in her colour with a highlight (the "who is next" row, the card).
struct EntrantBubble: View {
    var tint: SIMD3<Float>
    var size: CGFloat
    var body: some View {
        let c = Color(red: Double(tint.x), green: Double(tint.y), blue: Double(tint.z))
        Circle()
            .fill(RadialGradient(stops: [.init(color: .white, location: 0), .init(color: .white, location: 0.08), .init(color: c, location: 0.3), .init(color: c.opacity(0.92), location: 1)],
                                 center: UnitPoint(x: 0.35, y: 0.3), startRadius: 0, endRadius: size * 0.75))
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

/// The three entrants in the order they perform, the one on stage lit, the others at 55%.
struct WhoIsNext: View {
    var names: [String]
    var tints: [SIMD3<Float>]
    var current: Int?
    var size: CGFloat = 60
    var spacing: CGFloat = 34
    var font: CGFloat = 16
    var body: some View {
        HStack(alignment: .top, spacing: spacing) {
            ForEach(names.indices, id: \.self) { i in
                VStack(spacing: 4) {
                    EntrantBubble(tint: tints[i], size: size)
                    Text(names[i]).font(SK.font(font, .black)).foregroundStyle(ShowUI.mist).lineLimit(1).minimumScaleFactor(0.6)
                }
                .opacity(i == current ? 1 : 0.55)
                .accessibilityElement(children: .combine).accessibilityLabel(i == current ? "\(names[i]), up now" : names[i])
            }
        }
        .animation(.easeOut(duration: 0.2), value: current)
        .accessibilityIdentifier("trick-next")
    }
}

/// Phone on its side: kicker and title at the left, the three pips under the title (the turn row takes the top right).
struct SideHeader: View {
    var round: Int
    var title: String
    var kicker: String
    var turns: TurnPips? = nil
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(kicker).font(SK.font(12, .black)).foregroundStyle(ShowUI.gold).tracking(0.5)
            Text(title).font(SK.font(24, .black)).foregroundStyle(SK.cream)
            Group {
                if let t = turns { TurnPipRow(pips: t) }
                else { HStack(spacing: 6) { ForEach(1...3, id: \.self) { k in Capsule().fill(k <= round ? ShowUI.gold : ShowUI.platform).frame(width: 26, height: 8) } } }
            }.padding(.top, 8)
        }
        .accessibilityElement(children: .combine).accessibilityLabel("Round \(round) of 3, \(title)").accessibilityIdentifier("show-round")
    }
}

/// The soft bottom fade of a scrolling list that is longer than what shows.
struct SoftBottomFade: ViewModifier {
    var on: Bool
    func body(content: Content) -> some View {
        content.mask(alignment: .top) {
            if on { VStack(spacing: 0) { Rectangle(); LinearGradient(colors: [.black, .black.opacity(0.3)], startPoint: .top, endPoint: .bottom).frame(height: 16) } }
            else { Rectangle() }
        }
    }
}

/// "Next time: ..." on one line, from the weakest round of the player's show.
enum ShowShortTip {
    /// head, whether three gold stars follow, tail.
    static func parts(_ s: ShowSim?, theme: ShowTheme) -> (head: String, stars: Bool, tail: String) {
        guard let s else { return ("", false, "") }
        let p = s.playerScores
        let best = s.rivals.indices.map { s.rivalScores($0) }.reduce(ShowScores()) { ShowScores(look: max($0.look, $1.look), dance: max($0.dance, $1.dance), trick: max($0.trick, $1.trick)) }
        let gaps: [(ShowRound, Float)] = [(.look, best.look - p.look), (.dance, best.dance - p.dance), (.trick, best.trick - p.trick)]
        let worst = gaps.max { $0.1 < $1.1 }!
        if worst.1 <= 0 { return ("Next time: try the next rank up!", false, "") }
        switch worst.0 {
        case .look:
            if s.lookParts.glow < 12 && s.lookParts.outfit >= 24 { return ("Next time: a Clean before the Show", false, "") }
            return ("Next time: wear \(theme.main.title) things", false, "")
        case .dance: return ("Next time: tap right on the beat", false, "")
        default: return ("Next time: try a ", true, " trick")
        }
    }
    static func text(_ s: ShowSim?, theme: ShowTheme) -> String {
        let t = parts(s, theme: theme)
        return t.head + (t.stars ? "three-star" : "") + t.tail
    }
}
