//
//  TrophyCabinet.swift
//  The look of the per-Jelmiko Trophies sheet (trophy-look-r1): a colourful cabinet of big icons, one section per event (Jelly Show, Jelly Race, Jelly Volleyball), almost no text.
//  View only: every number comes from the same models as before (ShowProgress.Trophies, JelbieTrophies). Earned = full colour; not earned = a faint grey silhouette (a small lock on the badges).
//  The words a tile no longer shows (place, win counts, what earns a locked badge) stay in its VoiceOver label.
//

import SwiftUI

/// The metals (and the Ocean cup's rainbow) the icons are painted in.
enum CabinetTone {
    case gold, silver, bronze, rainbow
    static func place(_ p: Int) -> CabinetTone { p == 1 ? .gold : p == 2 ? .silver : .bronze }
    var base: Color {
        switch self {
        case .gold: return Color(hex: 0xF5B82E)
        case .silver: return Color(hex: 0xB4BFD0)
        case .bronze: return Color(hex: 0xCD7F3C)
        case .rainbow: return Color(hex: 0xA46BE8)
        }
    }
    var gradient: LinearGradient {
        switch self {
        case .gold: return LinearGradient(colors: [Color(hex: 0xFFE88A), Color(hex: 0xF5B82E), Color(hex: 0xD98E12)], startPoint: .top, endPoint: .bottom)
        case .silver: return LinearGradient(colors: [Color(hex: 0xF4F7FB), Color(hex: 0xB4BFD0), Color(hex: 0x8E9AAE)], startPoint: .top, endPoint: .bottom)
        case .bronze: return LinearGradient(colors: [Color(hex: 0xF0B07A), Color(hex: 0xCD7F3C), Color(hex: 0xA2571F)], startPoint: .top, endPoint: .bottom)
        case .rainbow: return LinearGradient(colors: [Color(hex: 0xFF6B6B), Color(hex: 0xFFB347), Color(hex: 0xFFE14D), Color(hex: 0x58D68D), Color(hex: 0x4DA3FF), Color(hex: 0xA46BE8)], startPoint: .leading, endPoint: .trailing)
        }
    }
}

/// A Show cup, in its rank's tone (bronze Puddle, silver Pond, gold Lagoon, rainbow Ocean), on a little plinth. The place it won shows as a small medal numeral (1 / 2 / 3) so it never rests on colour alone.
struct CabinetCup: View {
    var tone: CabinetTone
    var size: CGFloat = 44
    var body: some View {
        VStack(spacing: 1) {
            Image(systemName: "trophy.fill").font(.system(size: size, weight: .black)).foregroundStyle(tone.gradient).shadow(color: .black.opacity(0.18), radius: 1.5, y: 1.5)
            Capsule().fill(tone.gradient).frame(width: size * 0.82, height: size * 0.17).overlay(Capsule().strokeBorder(.white.opacity(0.55), lineWidth: 0.8)).overlay(Capsule().fill(.black.opacity(0.12)))
        }
    }
}

/// The small place medal on a Show cup (1st gold, 2nd silver, 3rd bronze).
struct CabinetPlaceDot: View {
    var place: Int
    var body: some View {
        Text("\(place)").font(SK.font(11, .black)).foregroundStyle(Color(hex: 0x5A3A00)).frame(width: 19, height: 19)
            .background(Circle().fill(CabinetTone.place(place).gradient)).overlay(Circle().strokeBorder(.white, lineWidth: 1.4))
    }
}

/// A rosette: a scalloped disc in one colour with a lighter ring, two ribbon tails, and a number or symbol in the middle.
struct CabinetRosette: View {
    var base: Color
    var symbol: String? = nil
    var text: String? = nil
    var size: CGFloat = 44
    var body: some View {
        ZStack(alignment: .top) {
            ForEach([-1.0, 1.0], id: \.self) { s in
                RoundedRectangle(cornerRadius: 2.5, style: .continuous).fill(base).overlay(RoundedRectangle(cornerRadius: 2.5, style: .continuous).fill(.black.opacity(0.16)))
                    .frame(width: size * 0.26, height: size * 0.5).rotationEffect(.degrees(s * 14), anchor: .top)
                    .offset(x: s * size * 0.17, y: size * 0.62)
            }
            ZStack {
                Image(systemName: "seal.fill").font(.system(size: size, weight: .black)).foregroundStyle(base)
                Image(systemName: "seal.fill").font(.system(size: size, weight: .black)).foregroundStyle(LinearGradient(colors: [.white.opacity(0.5), .clear, .black.opacity(0.2)], startPoint: .top, endPoint: .bottom))
                Circle().strokeBorder(.white.opacity(0.75), lineWidth: 1.6).frame(width: size * 0.62, height: size * 0.62)
                if let symbol { Image(systemName: symbol).font(.system(size: size * 0.32, weight: .black)).foregroundStyle(.white).shadow(color: .black.opacity(0.25), radius: 0.8, y: 0.8) }
                if let text { Text(text).font(SK.font(size * 0.34, .black)).foregroundStyle(.white).shadow(color: .black.opacity(0.3), radius: 0.8, y: 0.8) }
            }
            .frame(width: size, height: size)
        }
        .frame(width: size * 1.1, height: size * 1.3, alignment: .top)
    }
}

/// A round milestone badge (a number or a symbol on a metal disc).
struct CabinetBadge: View {
    var tone: CabinetTone = .gold
    var color: Color? = nil          // (a sticker's own colour instead of a metal)
    var symbol: String? = nil
    var text: String? = nil
    var size: CGFloat = 42
    var body: some View {
        ZStack {
            if let color { Circle().fill(color); Circle().fill(LinearGradient(colors: [.white.opacity(0.45), .clear, .black.opacity(0.18)], startPoint: .top, endPoint: .bottom)) }
            else { Circle().fill(tone.gradient) }
            Circle().strokeBorder(.white.opacity(0.7), lineWidth: 1.6).padding(size * 0.1)
            if let symbol { Image(systemName: symbol).font(.system(size: size * 0.4, weight: .black)).foregroundStyle(.white).shadow(color: .black.opacity(0.25), radius: 0.8, y: 0.8) }
            if let text { Text(text).font(SK.font(size * (text.count > 1 ? 0.36 : 0.44), .black)).foregroundStyle(.white).shadow(color: .black.opacity(0.3), radius: 0.8, y: 0.8) }
        }
        .frame(width: size, height: size).shadow(color: .black.opacity(0.12), radius: 1.5, y: 1.5)
    }
}

/// One cell of the cabinet: the icon (full colour when earned, a faint silhouette when not), a one-word label, an optional "x N" count and, for a locked badge, a small lock.
struct CabinetTile<Icon: View>: View {
    var label: String
    var earned: Bool
    var count: Int = 0
    var place: Int = 0          // (a Show cup's place: a small medal at its corner)
    var locked = false
    var glow: Color = Color(hex: 0xFFD66B)
    var a11y: String
    var id: String
    @ViewBuilder var icon: () -> Icon
    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                if earned { Circle().fill(RadialGradient(colors: [glow.opacity(0.55), .clear], center: .center, startRadius: 2, endRadius: 30)).frame(width: 56, height: 56) }
                icon().grayscale(earned ? 0 : 1).opacity(earned ? 1 : 0.22)
            }
            .frame(height: 62)
            .overlay(alignment: .topTrailing) {
                if count > 1 { Text("\u{00D7}\(count)").font(SK.font(11, .black)).foregroundStyle(.white).padding(.horizontal, 6).padding(.vertical, 2).background(Capsule().fill(Color(hex: 0xE0533D))).overlay(Capsule().strokeBorder(.white, lineWidth: 1.5)).offset(x: 4, y: -2) }
            }
            .overlay(alignment: .topLeading) { if earned && place > 0 { CabinetPlaceDot(place: place).offset(x: -2, y: 0) } }
            .overlay(alignment: .bottomTrailing) {
                if locked && !earned { Image(systemName: "lock.fill").font(.system(size: 9, weight: .black)).foregroundStyle(.white).frame(width: 18, height: 18).background(Circle().fill(SK.muted.opacity(0.7))).offset(x: 3, y: -2) }
            }
            Text(label).font(SK.font(11, .black)).foregroundStyle(earned ? SK.ink : SK.muted).lineLimit(1).minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 8).padding(.horizontal, 2)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(.white.opacity(earned ? 0.88 : 0.4)))
        .accessibilityElement(children: .ignore).accessibilityLabel(a11y).accessibilityIdentifier(id)
    }
}

/// An event's section: a coloured band with a round icon and the event's name, then its rows of tiles.
struct CabinetSection<Content: View>: View {
    var title: String
    var symbol: String
    var tint: Color
    var identifier: String
    @ViewBuilder var content: () -> Content
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: symbol).font(.system(size: 14, weight: .black)).foregroundStyle(.white).frame(width: 30, height: 30).background(Circle().fill(tint)).accessibilityHidden(true)
                Text(title).font(SK.font(19, .black)).foregroundStyle(SK.ink).accessibilityAddTraits(.isHeader)
            }
            content()
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(tint.opacity(0.22)))
        .accessibilityElement(children: .contain).accessibilityIdentifier(identifier)
    }
}

/// A row of tiles: as many columns as fit (tiles 58...96 pt wide), so five rosettes sit in one row on a phone and the rows simply get longer on an iPad or a phone on its side.
struct CabinetRow<Content: View>: View {
    @ViewBuilder var content: () -> Content
    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 58, maximum: 96), spacing: 8, alignment: .top)], alignment: .leading, spacing: 8, content: content)
    }
}

/// The metal of a "wins" milestone, 5 / 10 / 25.
enum CabinetMilestone {
    static func tone(_ t: Trophy) -> CabinetTone {
        switch t.id {
        case "wins5", "vwins5": return .bronze
        case "wins10", "vwins10": return .silver
        case "champion": return .rainbow
        default: return .gold
        }
    }
    static func label(_ t: Trophy) -> String { t.id == "champion" ? "Champion" : "Wins" }
    static func number(_ t: Trophy) -> String? { t.id == "champion" ? nil : String(t.id.drop { !$0.isNumber }) }
    /// One tile for a milestone trophy: a metal disc with its number (a crown for Champion); faint with a lock until won.
    static func tile(_ t: Trophy, has: Bool, idPrefix: String = "trophy-") -> some View {
        CabinetTile(label: label(t), earned: has, locked: true, glow: tone(t).base, a11y: has ? "\(t.title), earned" : "\(t.detail), not yet", id: "\(idPrefix)\(t.id)") {
            CabinetBadge(tone: tone(t), symbol: t.id == "champion" ? "crown.fill" : nil, text: number(t))
        }
    }
}
