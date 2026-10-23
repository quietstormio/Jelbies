//
//  JellyAccessoryViews.swift
//  Lock Screen (accessory) and StandBy faces of the Jelbies widget, plus the little vector face glyph they share. In Shared/ so the
//  BobV1Tests target can render every family with ImageRenderer (AppleExtrasCaptureTests).
//
//  Palette: the game's cream #F7F0E0 and ink #4D331F (JellyPalette), rounded type; each Jelbie's own colour for his face.
//  Lock Screen accessories are drawn in the system's tint (vibrant / accented), so they use `widgetAccentable` and opacity only.
//  StandBy: the small / medium families with the container background removed and a dark scheme: big, legible, white-on-night.
//

import SwiftUI
import WidgetKit
import UIKit

/// The game palette the task names for the Apple extras (the Siri snippet, StandBy, the Live Activities).
nonisolated enum JellyPalette {
    static let cream = Color(.sRGB, red: 0xF7 / 255.0, green: 0xF0 / 255.0, blue: 0xE0 / 255.0)
    static let ink = Color(.sRGB, red: 0x4D / 255.0, green: 0x33 / 255.0, blue: 0x1F / 255.0)
    static let inkSoft = Color(.sRGB, red: 0x4D / 255.0, green: 0x33 / 255.0, blue: 0x1F / 255.0).opacity(0.62)
    static let night = Color(.sRGB, red: 0.09, green: 0.09, blue: 0.14)
    static let moon = Color(.sRGB, red: 0.98, green: 0.93, blue: 0.78)
    /// Follows Dynamic Type, capped at 1.3x because widget families are tight (the views keep their minimumScaleFactor).
    static func font(_ size: CGFloat, _ weight: Font.Weight = .bold) -> Font {
        .system(size: min(UIFontMetrics(forTextStyle: .body).scaledValue(for: size), size * 1.3), weight: weight, design: .rounded)
    }
    /// A Jelbie's body colour (blue Bob, yellow Pip, green Moss, lavender).
    static func body(_ color: String) -> Color {
        switch color {
        case "blue": return Color(.sRGB, red: 0.56, green: 0.74, blue: 0.95)
        case "yellow": return Color(.sRGB, red: 0.97, green: 0.84, blue: 0.42)
        case "green": return Color(.sRGB, red: 0.56, green: 0.84, blue: 0.60)
        case "purple", "lavender": return Color(.sRGB, red: 0.76, green: 0.66, blue: 0.93)
        case "pink": return Color(.sRGB, red: 0.95, green: 0.62, blue: 0.74)
        default: return Color(.sRGB, red: 0.96, green: 0.70, blue: 0.66)
        }
    }
    static func bodyDeep(_ color: String) -> Color {
        switch color {
        case "blue": return Color(.sRGB, red: 0.33, green: 0.52, blue: 0.80)
        case "yellow": return Color(.sRGB, red: 0.80, green: 0.62, blue: 0.20)
        case "green": return Color(.sRGB, red: 0.30, green: 0.60, blue: 0.36)
        case "purple", "lavender": return Color(.sRGB, red: 0.52, green: 0.40, blue: 0.74)
        default: return Color(.sRGB, red: 0.72, green: 0.42, blue: 0.40)
        }
    }
}

/// The expression of a face glyph.
nonisolated enum JellyFaceMood: Sendable { case happy, okay, hungry, grumpy, sleeping
    static func of(_ s: JellyState, sleeping: Bool) -> JellyFaceMood {
        if sleeping, !s.needsAttention { return .sleeping }
        if s.mood == .grumpy { return .grumpy }
        if s.needsAttention { return .hungry }
        return s.mood == .happy ? .happy : .okay
    }
}

/// A tiny Jelbie: a soft rounded-dome body with two antenna nubs, dot eyes and a mouth. `tinted`: draw in one colour (the Lock Screen's vibrant
/// rendering), otherwise in his body colour with ink features. Draws cleanly from 14 pt to 120 pt.
struct JellyFaceGlyph: View {
    var color: String = "blue"
    var mood: JellyFaceMood = .happy
    var tinted = false
    var ink: Color = JellyPalette.ink

    var body: some View {
        Canvas { ctx, size in
            let w = size.width, h = size.height
            let s = min(w, h)
            let bodyRect = CGRect(x: (w - s * 0.92) / 2, y: h - s * 0.84, width: s * 0.92, height: s * 0.80)
            // body: a bean, a little wider at the base
            var p = Path()
            p.move(to: CGPoint(x: bodyRect.minX + s * 0.05, y: bodyRect.maxY))
            p.addCurve(to: CGPoint(x: bodyRect.midX, y: bodyRect.minY), control1: CGPoint(x: bodyRect.minX - s * 0.06, y: bodyRect.minY + s * 0.30), control2: CGPoint(x: bodyRect.minX + s * 0.12, y: bodyRect.minY))
            p.addCurve(to: CGPoint(x: bodyRect.maxX - s * 0.05, y: bodyRect.maxY), control1: CGPoint(x: bodyRect.maxX - s * 0.12, y: bodyRect.minY), control2: CGPoint(x: bodyRect.maxX + s * 0.06, y: bodyRect.minY + s * 0.30))
            p.addQuadCurve(to: CGPoint(x: bodyRect.minX + s * 0.05, y: bodyRect.maxY), control: CGPoint(x: bodyRect.midX, y: bodyRect.maxY + s * 0.04))
            p.closeSubpath()
            let fill: Color = tinted ? ink : JellyPalette.body(color)
            // antennae: two little nubs
            for dx: CGFloat in [-0.17, 0.17] {
                let r = s * 0.055
                let c = CGPoint(x: bodyRect.midX + dx * s, y: bodyRect.minY + s * 0.02)
                var stem = Path(); stem.move(to: CGPoint(x: c.x * 0.6 + bodyRect.midX * 0.4, y: bodyRect.minY + s * 0.10)); stem.addLine(to: c)
                ctx.stroke(stem, with: .color(fill), style: StrokeStyle(lineWidth: max(1, s * 0.05), lineCap: .round))
                ctx.fill(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)), with: .color(fill))
            }
            ctx.fill(p, with: .color(fill))
            if !tinted {
                // a soft highlight
                ctx.fill(Path(ellipseIn: CGRect(x: bodyRect.minX + s * 0.14, y: bodyRect.minY + s * 0.10, width: s * 0.16, height: s * 0.10)), with: .color(.white.opacity(0.45)))
            }
            // face
            let feature: Color = tinted ? JellyPalette.night : ink
            let ey = bodyRect.minY + s * 0.40
            let er = s * 0.055
            for dx: CGFloat in [-0.17, 0.17] {
                let cx = bodyRect.midX + dx * s
                switch mood {
                case .sleeping:
                    var e = Path(); e.move(to: CGPoint(x: cx - er * 1.4, y: ey)); e.addQuadCurve(to: CGPoint(x: cx + er * 1.4, y: ey), control: CGPoint(x: cx, y: ey + er * 1.6))
                    ctx.stroke(e, with: .color(feature), style: StrokeStyle(lineWidth: max(1, s * 0.045), lineCap: .round))
                case .grumpy:
                    ctx.fill(Path(ellipseIn: CGRect(x: cx - er, y: ey - er, width: 2 * er, height: 2 * er)), with: .color(feature))
                    var b = Path(); b.move(to: CGPoint(x: cx - er * 1.5, y: ey - er * 2.4 + (dx < 0 ? er : -er) * 0.6)); b.addLine(to: CGPoint(x: cx + er * 1.5, y: ey - er * 2.4 + (dx < 0 ? -er : er) * 0.6))
                    ctx.stroke(b, with: .color(feature), style: StrokeStyle(lineWidth: max(1, s * 0.04), lineCap: .round))
                default:
                    ctx.fill(Path(ellipseIn: CGRect(x: cx - er, y: ey - er, width: 2 * er, height: 2 * er)), with: .color(feature))
                    if !tinted { ctx.fill(Path(ellipseIn: CGRect(x: cx - er * 0.5, y: ey - er * 0.8, width: er * 0.6, height: er * 0.6)), with: .color(.white.opacity(0.8))) }
                }
            }
            let my = ey + s * 0.16
            var m = Path()
            switch mood {
            case .happy:
                m.move(to: CGPoint(x: bodyRect.midX - s * 0.10, y: my)); m.addQuadCurve(to: CGPoint(x: bodyRect.midX + s * 0.10, y: my), control: CGPoint(x: bodyRect.midX, y: my + s * 0.12))
                ctx.stroke(m, with: .color(feature), style: StrokeStyle(lineWidth: max(1, s * 0.045), lineCap: .round))
            case .okay, .sleeping:
                m.move(to: CGPoint(x: bodyRect.midX - s * 0.06, y: my + s * 0.02)); m.addQuadCurve(to: CGPoint(x: bodyRect.midX + s * 0.06, y: my + s * 0.02), control: CGPoint(x: bodyRect.midX, y: my + s * 0.06))
                ctx.stroke(m, with: .color(feature), style: StrokeStyle(lineWidth: max(1, s * 0.04), lineCap: .round))
            case .hungry:
                ctx.fill(Path(ellipseIn: CGRect(x: bodyRect.midX - s * 0.07, y: my - s * 0.01, width: s * 0.14, height: s * 0.11)), with: .color(feature))
            case .grumpy:
                m.move(to: CGPoint(x: bodyRect.midX - s * 0.09, y: my + s * 0.05)); m.addQuadCurve(to: CGPoint(x: bodyRect.midX + s * 0.09, y: my + s * 0.05), control: CGPoint(x: bodyRect.midX, y: my - s * 0.04))
                ctx.stroke(m, with: .color(feature), style: StrokeStyle(lineWidth: max(1, s * 0.045), lineCap: .round))
            }
            // cheeks
            if !tinted, mood == .happy || mood == .sleeping {
                for dx: CGFloat in [-0.26, 0.26] {
                    ctx.fill(Path(ellipseIn: CGRect(x: bodyRect.midX + dx * s - s * 0.05, y: ey + s * 0.06, width: s * 0.10, height: s * 0.06)), with: .color(Color(.sRGB, red: 0.98, green: 0.60, blue: 0.62).opacity(0.5)))
                }
            }
        }
    }
}

/// Little floating Zs beside a sleeping Jelbie (static in widgets; the Live Activity animates them with a phase).
struct SleepZs: View {
    var size: CGFloat = 12
    var color: Color = .white
    var phase: Double = 0
    var body: some View {
        ZStack(alignment: .bottomLeading) {
            ForEach(0..<3, id: \.self) { i in
                let t = (phase + Double(i) / 3).truncatingRemainder(dividingBy: 1)
                Text("z")
                    .font(JellyPalette.font(size * (0.7 + CGFloat(i) * 0.25)))
                    .foregroundStyle(color.opacity(0.95 - t * 0.6))
                    .offset(x: CGFloat(i) * size * 0.55 + CGFloat(t) * size * 0.3, y: -CGFloat(i) * size * 0.65 - CGFloat(t) * size * 0.5)
            }
        }
        .frame(width: size * 2.4, height: size * 2.4, alignment: .bottomLeading)
    }
}

// MARK: - Lock Screen accessories

/// The data every accessory draws: the projected Jelbies, who is asleep, and what is queued (a Water tap waiting for the game to open).
nonisolated struct JellyAccessoryModel: Sendable {
    var states: [JellyState]
    var sleeping = false
    var queued: [JellyRoute] = []
    var neediest: JellyState? { JellyState.neediest(in: states) }
}

/// accessoryCircular: the neediest Jelbie's need ring with his tiny face in the middle.
struct JellyCircularView: View {
    let model: JellyAccessoryModel
    var body: some View {
        if let s = model.neediest {
            let n = s.neediest
            Gauge(value: Double(s.level(n.care))) { EmptyView() } currentValueLabel: {
                JellyFaceGlyph(color: s.color, mood: JellyFaceMood.of(s, sleeping: model.sleeping), tinted: true, ink: .white)
                    .frame(width: 30, height: 30)
                    .widgetAccentable()
            }
            .gaugeStyle(.accessoryCircularCapacity)
            .accessibilityLabel(s.headline)
        } else {
            JellyFaceGlyph(color: "blue", mood: .happy, tinted: true, ink: .white).frame(width: 34, height: 34).padding(4)
        }
    }
}

/// accessoryRectangular: "Bob is hungry · Pip napping" over the three small faces and the item they each want most.
struct JellyRectangularView: View {
    let model: JellyAccessoryModel
    var body: some View {
        let states = model.states.sorted { $0.id < $1.id }
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Text("Jelbies").font(JellyPalette.font(11, .heavy)).opacity(0.75)
                if JellyStatus.needyCount(states) > 0 { Circle().frame(width: 5, height: 5).widgetAccentable() }
                if !model.queued.isEmpty { Image(systemName: "drop.fill").font(.system(size: 8, weight: .bold)).opacity(0.8) }
            }
            Text(JellyStatus.line(states, sleeping: model.sleeping))
                .font(JellyPalette.font(14))
                .lineLimit(2).minimumScaleFactor(0.75)
                .widgetAccentable()
            if !states.isEmpty {
                HStack(spacing: 6) {
                    ForEach(states) { s in
                        HStack(spacing: 2) {
                            JellyFaceGlyph(color: s.color, mood: JellyFaceMood.of(s, sleeping: model.sleeping), tinted: true, ink: .white).frame(width: 15, height: 15)
                            if s.needsAttention { Image(systemName: s.neediest.care.systemImage).font(.system(size: 9, weight: .bold)) }
                            else if model.sleeping { Text("z").font(JellyPalette.font(9)).opacity(0.8) }
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// accessoryInline: one line, "Bob is hungry" / "Everyone is napping".
struct JellyInlineView: View {
    let model: JellyAccessoryModel
    var body: some View {
        if let s = model.neediest, s.needsAttention {
            Label(JellyStatus.inline(model.states, sleeping: model.sleeping), systemImage: s.neediest.care.systemImage)
        } else if model.sleeping {
            Label(JellyStatus.inline(model.states, sleeping: true), systemImage: "moon.zzz.fill")
        } else {
            Label(JellyStatus.inline(model.states, sleeping: false), systemImage: "heart.fill")
        }
    }
}

// MARK: - StandBy

/// The StandBy look of the Home Screen families: the container background removed, a dark scheme, big faces and large type. Each Jelbie
/// is a glowing face with his name and one word; a sleeping room shows Zs and a moon.
struct JellyStandByView: View {
    let family: WidgetFamily
    let model: JellyAccessoryModel
    /// `tinted`: the Lock Screen / StandBy tinted rendering mode (one colour): faces go monochrome.
    var tinted = false

    var body: some View {
        let states = model.states.sorted { $0.id < $1.id }
        Group {
            if states.isEmpty {
                VStack(spacing: 8) {
                    JellyFaceGlyph(color: "blue", mood: .happy, tinted: tinted, ink: .white).frame(width: 64, height: 64)
                    Text("Jelbies").font(JellyPalette.font(22)).foregroundStyle(.white)
                }
            } else if family == .systemSmall {
                small(states)
            } else {
                medium(states)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func small(_ states: [JellyState]) -> some View {
        let s = model.neediest ?? states[0]
        return VStack(spacing: 4) {
            ZStack(alignment: .topTrailing) {
                face(s, size: 84)
                if model.sleeping, !s.needsAttention { SleepZs(size: 13, color: JellyPalette.moon).offset(x: 14, y: -8) }
            }
            Text(s.name).font(JellyPalette.font(24)).foregroundStyle(.white).lineLimit(1).minimumScaleFactor(0.7)
            Text(JellyStatus.word(s, sleeping: model.sleeping).capitalized)
                .font(JellyPalette.font(16, .semibold))
                .foregroundStyle(s.needsAttention ? WidgetTheme.tint(s.neediest.tier) : .white.opacity(0.75))
                .lineLimit(1).minimumScaleFactor(0.7)
            if states.count > 1 {
                HStack(spacing: 5) {
                    ForEach(states.filter { $0.id != s.id }) { o in
                        JellyFaceGlyph(color: o.color, mood: JellyFaceMood.of(o, sleeping: model.sleeping), tinted: tinted, ink: .white).frame(width: 16, height: 16)
                    }
                }
            }
        }
    }

    private func medium(_ states: [JellyState]) -> some View {
        HStack(alignment: .top, spacing: 0) {
            ForEach(states) { s in
                VStack(spacing: 4) {
                    ZStack(alignment: .topTrailing) {
                        face(s, size: states.count > 2 ? 76 : 88)
                        if model.sleeping, !s.needsAttention { SleepZs(size: 12, color: JellyPalette.moon).offset(x: 14, y: -8) }
                    }
                    Text(s.name).font(JellyPalette.font(21)).foregroundStyle(.white).lineLimit(1).minimumScaleFactor(0.7)
                    HStack(spacing: 4) {
                        if s.needsAttention { Image(systemName: s.neediest.care.systemImage).font(.system(size: 13, weight: .bold)).foregroundStyle(WidgetTheme.tint(s.neediest.tier)) }
                        Text(JellyStatus.word(s, sleeping: model.sleeping).capitalized)
                            .font(JellyPalette.font(15, .semibold))
                            .foregroundStyle(s.needsAttention ? WidgetTheme.tint(s.neediest.tier) : .white.opacity(0.75))
                    }
                    .lineLimit(1).minimumScaleFactor(0.7)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .overlay(alignment: .topLeading) {
            if model.sleeping { Image(systemName: "moon.fill").font(.system(size: 14, weight: .bold)).foregroundStyle(JellyPalette.moon.opacity(0.9)) }
        }
    }

    private func face(_ s: JellyState, size: CGFloat) -> some View {
        ZStack {
            Circle().fill(JellyPalette.body(s.color).opacity(tinted ? 0.15 : 0.22)).frame(width: size, height: size)
            JellyFaceGlyph(color: s.color, mood: JellyFaceMood.of(s, sleeping: model.sleeping), tinted: tinted, ink: .white)
                .frame(width: size * 0.78, height: size * 0.78)
        }
    }
}
