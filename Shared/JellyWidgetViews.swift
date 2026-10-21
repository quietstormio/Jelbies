//
//  JellyWidgetViews.swift
//  The widget's SwiftUI, kept in Shared/ (compiled into the app and the extension) so the BobV1Tests target can render every family
//  with ImageRenderer. Only the @main bundle, the Widget and the timeline provider live in JelbiesWidget/.
//  Style: the app's soft cream / peach UI (UITheme), rounded type, the same need colours as the thought bubbles; tier colours on the icons.
//

import SwiftUI
import WidgetKit
import UIKit

nonisolated enum WidgetTheme {
    static let cream = Color(.sRGB, red: 1.0, green: 0.95, blue: 0.89)
    static let peach = Color(.sRGB, red: 0.96, green: 0.78, blue: 0.66)
    static let panel = Color(.sRGB, red: 1.0, green: 0.93, blue: 0.85)
    static let ink = Color(.sRGB, red: 0.40, green: 0.24, blue: 0.20)
    static let inkSoft = Color(.sRGB, red: 0.40, green: 0.24, blue: 0.20).opacity(0.65)
    /// The card behind everything (a soft cream-to-peach wash).
    static var card: LinearGradient { LinearGradient(colors: [cream, Color(.sRGB, red: 0.99, green: 0.88, blue: 0.78)], startPoint: .top, endPoint: .bottom) }

    /// Icon colour by tier: Full green, Normal sage-gold, Hungry orange, Famished red.
    static func tint(_ t: NeedTier) -> Color {
        switch t {
        case .full: return Color(.sRGB, red: 0.40, green: 0.72, blue: 0.40)
        case .normal: return Color(.sRGB, red: 0.72, green: 0.66, blue: 0.34)
        case .hungry: return Color(.sRGB, red: 0.96, green: 0.55, blue: 0.20)
        case .famished: return Color(.sRGB, red: 0.88, green: 0.26, blue: 0.30)
        }
    }
    /// A Jelly's accent by palette key.
    static func accent(_ color: String) -> Color {
        switch color {
        case "blue": return Color(.sRGB, red: 0.45, green: 0.66, blue: 0.95)
        case "yellow": return Color(.sRGB, red: 0.96, green: 0.80, blue: 0.30)
        case "green": return Color(.sRGB, red: 0.45, green: 0.78, blue: 0.50)
        case "purple": return Color(.sRGB, red: 0.68, green: 0.54, blue: 0.90)
        case "lavender": return Color(.sRGB, red: 0.76, green: 0.66, blue: 0.93)
        case "pink": return Color(.sRGB, red: 0.95, green: 0.55, blue: 0.70)
        default: return Color(.sRGB, red: 0.96, green: 0.66, blue: 0.62)
        }
    }
    static func font(_ size: CGFloat, _ weight: Font.Weight = .bold) -> Font { .system(size: size, weight: weight, design: .rounded) }
}

/// A care icon (berries / drop / heart / soap bubbles) tinted by tier, on a soft disc.
struct CareIcon: View {
    let care: JellyCare
    let tier: NeedTier
    var size: CGFloat = 22
    var disc = true
    var body: some View {
        let tint = WidgetTheme.tint(tier)
        ZStack {
            if disc { Circle().fill(tint.opacity(0.20)) }
            switch care {
            case .food:
                Canvas { ctx, sz in
                    let s = sz.width * 0.74, r = s * 0.29, c = CGPoint(x: sz.width / 2, y: sz.height / 2 + s * 0.04)
                    for (dx, dy) in [(-0.2, 0.08), (0.2, 0.0)] {
                        let b = CGPoint(x: c.x + CGFloat(dx) * s, y: c.y + CGFloat(dy) * s)
                        ctx.fill(Path(ellipseIn: CGRect(x: b.x - r, y: b.y - r, width: 2 * r, height: 2 * r)), with: .color(tint))
                        ctx.fill(Path(ellipseIn: CGRect(x: b.x - r * 0.55, y: b.y - r * 0.6, width: r * 0.45, height: r * 0.45)), with: .color(.white.opacity(0.6)))
                    }
                }
            default:
                Image(systemName: care.systemImage).font(.system(size: size * 0.5, weight: .bold)).foregroundStyle(tint)
            }
        }
        .frame(width: size, height: size)
    }
}

/// The four tier icons of a Jelly in a row.
struct CareRow: View {
    let state: JellyState
    var size: CGFloat = 22
    var spacing: CGFloat = 5
    var body: some View {
        HStack(spacing: spacing) {
            ForEach(JellyCare.allCases, id: \.self) { CareIcon(care: $0, tier: state.tier($0), size: size) }
        }
    }
}

/// A Jelly's portrait (the app's own 3D render) in a rounded tile; before the app has rendered one, the initial on his colour.
struct JellyPortraitTile: View {
    let state: JellyState
    let image: UIImage?
    var corner: CGFloat = 16
    var body: some View {
        GeometryReader { g in
            let side = min(g.size.width, g.size.height)
            ZStack {
                if let image {
                    Image(uiImage: image).resizable().scaledToFill()
                } else {
                    WidgetTheme.accent(state.color).opacity(0.35)
                    Text(String(state.name.prefix(1))).font(WidgetTheme.font(side * 0.5)).foregroundStyle(WidgetTheme.ink)
                }
            }
            .frame(width: side, height: side)
            .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: corner, style: .continuous).strokeBorder(.white.opacity(0.55), lineWidth: 1))
            .frame(width: g.size.width, height: g.size.height)
        }
    }
}

struct JellyWidgetContent: View {
    let family: WidgetFamily
    let states: [JellyState]
    let portraits: [Int: UIImage]

    var body: some View {
        switch family {
        case .systemMedium: medium
        case .systemLarge, .systemExtraLarge: large
        case .accessoryRectangular: rectangular
        case .accessoryCircular: circular
        default: small
        }
    }

    private var neediest: JellyState? { JellyState.neediest(in: states) }

    // MARK: Home Screen

    private var small: some View {
        Group {
            if let s = neediest {
                VStack(spacing: 6) {
                    JellyPortraitTile(state: s, image: portraits[s.id])
                    Text(s.headline)
                        .font(WidgetTheme.font(15)).foregroundStyle(WidgetTheme.ink)
                        .lineLimit(2).minimumScaleFactor(0.8).multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                }
            } else { empty }
        }
    }

    private var medium: some View {
        Group {
            if states.count == 1, let s = states.first {
                HStack(spacing: 12) {
                    JellyPortraitTile(state: s, image: portraits[s.id])
                    VStack(alignment: .leading, spacing: 8) {
                        Text(s.headline).font(WidgetTheme.font(18)).foregroundStyle(WidgetTheme.ink).lineLimit(2).minimumScaleFactor(0.8)
                        wordGrid(s)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else if states.isEmpty { empty } else {
                HStack(alignment: .top, spacing: 10) {
                    ForEach(states) { s in
                        Link(destination: JellyLink.url(for: s.id)) {
                            VStack(spacing: 4) {
                                JellyPortraitTile(state: s, image: portraits[s.id], corner: 14)
                                Text(s.name).font(WidgetTheme.font(13)).foregroundStyle(WidgetTheme.ink).lineLimit(1)
                                CareRow(state: s, size: states.count > 2 ? 19 : 22, spacing: states.count > 2 ? 2 : 4)
                            }
                            .frame(maxWidth: .infinity)
                        }
                    }
                }
            }
        }
    }

    private var large: some View {
        Group {
            if states.isEmpty { empty } else {
                VStack(spacing: 8) {
                    ForEach(states) { s in
                        Link(destination: JellyLink.url(for: s.id)) {
                            HStack(spacing: 12) {
                                JellyPortraitTile(state: s, image: portraits[s.id], corner: 14).frame(width: 92)
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(s.headline).font(WidgetTheme.font(17)).foregroundStyle(WidgetTheme.ink).lineLimit(1).minimumScaleFactor(0.8)
                                    wordGrid(s)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .padding(8)
                            .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(WidgetTheme.panel.opacity(0.7)))
                        }
                    }
                }
            }
        }
    }

    /// Icon + word pairs, two per line.
    private func wordGrid(_ s: JellyState) -> some View {
        let cols = [GridItem(.flexible(), spacing: 6, alignment: .leading), GridItem(.flexible(), spacing: 6, alignment: .leading)]
        return LazyVGrid(columns: cols, alignment: .leading, spacing: 4) {
            ForEach(JellyCare.allCases, id: \.self) { c in
                HStack(spacing: 4) {
                    CareIcon(care: c, tier: s.tier(c), size: 20)
                    Text(s.word(c)).font(WidgetTheme.font(11, .semibold)).foregroundStyle(WidgetTheme.inkSoft).lineLimit(1).minimumScaleFactor(0.7)
                }
            }
        }
    }

    private var empty: some View {
        VStack(spacing: 6) {
            Text("Jelbies").font(WidgetTheme.font(18)).foregroundStyle(WidgetTheme.ink)
            Text("Open the game to meet your Jelly").font(WidgetTheme.font(12, .medium)).foregroundStyle(WidgetTheme.inkSoft).multilineTextAlignment(.center)
        }
    }

    // MARK: Lock Screen

    private var rectangular: some View {
        Group {
            if let s = neediest {
                VStack(alignment: .leading, spacing: 3) {
                    Text(s.headline).font(.system(size: 15, weight: .bold, design: .rounded)).lineLimit(1).minimumScaleFactor(0.7).widgetAccentable()
                    HStack(spacing: 8) {
                        ForEach(JellyCare.allCases, id: \.self) { c in
                            let t = s.tier(c)
                            Image(systemName: c.systemImage)
                                .font(.system(size: 14, weight: .bold))
                                .opacity(t.rawValue >= NeedTier.hungry.rawValue ? 1 : 0.4)
                                .overlay(alignment: .topTrailing) {
                                    if t.rawValue >= NeedTier.hungry.rawValue { Circle().frame(width: 5, height: 5).offset(x: 3, y: -2) }
                                }
                        }
                    }
                    Text(s.needsAttention ? "Needs you" : "All good").font(.system(size: 11, weight: .medium, design: .rounded)).opacity(0.7)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else { Text("Open Jelbies").font(.system(size: 14, weight: .bold, design: .rounded)) }
        }
    }

    private var circular: some View {
        Group {
            if let s = neediest {
                let n = s.neediest
                Gauge(value: Double(s.level(n.care))) {
                    EmptyView()
                } currentValueLabel: {
                    Image(systemName: n.care.systemImage).font(.system(size: 17, weight: .bold))
                }
                .gaugeStyle(.accessoryCircularCapacity)
            } else { Image(systemName: "heart.fill") }
        }
    }
}
