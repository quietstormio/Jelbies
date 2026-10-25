//
//  PhotoLook.swift
//  Photo mode's filters and frames, drawn in SwiftUI with plain alpha (no blend modes), so the same overlay is the live viewfinder look and the
//  saved picture (ImageRenderer over the captured stage frame).
//

import SwiftUI

enum PhotoFilter: String, CaseIterable, Identifiable {
    case normal, warm, cool, dreamy
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
}

enum PhotoFrame: String, CaseIterable, Identifiable {
    case none, polaroid, cream, hearts, stars, film
    var id: String { rawValue }
    var title: String { self == .none ? "No frame" : rawValue.capitalized }
    var symbol: String {
        switch self { case .none: return "rectangle"; case .polaroid: return "photo"; case .cream: return "rectangle.inset.filled"
        case .hearts: return "heart.fill"; case .stars: return "sparkles"; case .film: return "film" }
    }
}

/// The filter wash and the frame, filling whatever size it is given.
struct PhotoLook: View {
    var filter: PhotoFilter
    var frame: PhotoFrame

    var body: some View {
        ZStack {
            filterLayer
            GeometryReader { g in FrameArt(frame: frame, size: g.size) }
        }
        .allowsHitTesting(false)
    }

    @ViewBuilder private var filterLayer: some View {
        switch filter {
        case .normal: Color.clear
        case .warm: Color(red: 1.0, green: 0.62, blue: 0.28).opacity(0.17)
        case .cool: Color(red: 0.35, green: 0.62, blue: 1.0).opacity(0.17)
        case .dreamy:
            ZStack {
                Color(red: 1.0, green: 0.86, blue: 0.93).opacity(0.20)
                RadialGradient(colors: [.clear, Color.white.opacity(0.38)], center: .center, startRadius: 120, endRadius: 560)
            }
        }
    }
}

private struct FrameArt: View {
    let frame: PhotoFrame
    let size: CGSize

    var body: some View {
        let w = size.width, h = size.height, m = min(w, h)
        switch frame {
        case .none: Color.clear
        case .polaroid:
            let side = m * 0.045, top = m * 0.045, bottom = m * 0.17
            ring(w, h, EdgeInsets(top: top, leading: side, bottom: bottom, trailing: side), Color(red: 0.99, green: 0.98, blue: 0.95))
                .overlay(alignment: .bottom) {
                    Text("Jelbies").font(.system(size: bottom * 0.36, weight: .bold, design: .rounded)).foregroundStyle(SK.ink.opacity(0.85))
                        .frame(height: bottom).frame(maxWidth: .infinity)
                }
        case .cream:
            let t = m * 0.04
            ZStack {
                ring(w, h, EdgeInsets(top: t, leading: t, bottom: t, trailing: t), SK.cream)
                Rectangle().strokeBorder(SK.honeyDeep, lineWidth: max(2, m * 0.008)).padding(t).allowsHitTesting(false)
            }
        case .hearts:
            let t = m * 0.04
            ZStack {
                ring(w, h, EdgeInsets(top: t, leading: t, bottom: t, trailing: t), SK.pink.opacity(0.95))
                ForEach(0..<14, id: \.self) { i in
                    let u = CGFloat(i) / 13
                    Image(systemName: "heart.fill").font(.system(size: t * (i % 2 == 0 ? 0.9 : 0.6))).foregroundStyle(Color.white.opacity(0.9))
                        .position(x: w * (0.05 + 0.9 * u), y: i % 2 == 0 ? t * 0.5 : h - t * 0.5)
                }
                ForEach(0..<4, id: \.self) { c in
                    Image(systemName: "heart.fill").font(.system(size: m * 0.09)).foregroundStyle(Color.white)
                        .position(x: c % 2 == 0 ? m * 0.07 : w - m * 0.07, y: c < 2 ? m * 0.07 : h - m * 0.07)
                }
            }
        case .stars:
            let t = m * 0.045
            ZStack {
                ring(w, h, EdgeInsets(top: t, leading: t, bottom: t, trailing: t), Color(red: 0.16, green: 0.20, blue: 0.40).opacity(0.96))
                ForEach(0..<16, id: \.self) { i in
                    let u = CGFloat(i) / 15
                    Image(systemName: i % 3 == 0 ? "sparkle" : "star.fill").font(.system(size: t * (i % 3 == 0 ? 0.9 : 0.55))).foregroundStyle(SK.honey)
                        .position(x: i % 2 == 0 ? w * (0.04 + 0.92 * u) : t * 0.5, y: i % 2 == 0 ? (i % 4 == 0 ? t * 0.5 : h - t * 0.5) : h * (0.06 + 0.88 * u))
                }
            }
        case .film:
            let t = m * 0.07
            ZStack {
                ring(w, h, EdgeInsets(top: t, leading: t * 0.35, bottom: t, trailing: t * 0.35), Color(red: 0.08, green: 0.07, blue: 0.07))
                let n = 12
                ForEach(0..<n, id: \.self) { i in
                    let x = w * (CGFloat(i) + 0.5) / CGFloat(n)
                    RoundedRectangle(cornerRadius: t * 0.08).fill(Color.white.opacity(0.85)).frame(width: t * 0.42, height: t * 0.42).position(x: x, y: t * 0.5)
                    RoundedRectangle(cornerRadius: t * 0.08).fill(Color.white.opacity(0.85)).frame(width: t * 0.42, height: t * 0.42).position(x: x, y: h - t * 0.5)
                }
            }
        }
    }

    /// A border: the full rectangle with the inner picture area cut out.
    private func ring(_ w: CGFloat, _ h: CGFloat, _ inset: EdgeInsets, _ color: Color) -> some View {
        Path { p in
            p.addRect(CGRect(x: 0, y: 0, width: w, height: h))
            p.addRect(CGRect(x: inset.leading, y: inset.top, width: w - inset.leading - inset.trailing, height: h - inset.top - inset.bottom))
        }
        .fill(color, style: FillStyle(eoFill: true))
    }
}
