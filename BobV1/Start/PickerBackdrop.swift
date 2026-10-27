//
//  PickerBackdrop.swift
//  The species picker's whole-screen background: a gentle vertical gradient in the species' own (lightened) colour, soft light rays from the top
//  centre and a few floating translucent bubbles. `calm` (Reduce Motion) holds the rays and bubbles still; the colour change is a plain cross-fade.
//

import SwiftUI

struct PickerBackdrop: View {
    var top: Color, bottom: Color
    var calm: Bool

    var body: some View {
        ZStack {
            LinearGradient(colors: [top, bottom], startPoint: .top, endPoint: .bottom)
            if calm { scene(t: 0) } else { TimelineView(.animation) { tl in scene(t: tl.date.timeIntervalSinceReferenceDate) } }
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }

    private func scene(t: Double) -> some View {
        Canvas { ctx, size in
            let origin = CGPoint(x: size.width / 2, y: -20)
            let sway = calm ? 0 : sin(t * 0.25) * 0.05
            for i in 0..<9 {
                let a = (Double(i) / 8 - 0.5) * 1.5 + sway
                let half = 0.05 + 0.02 * Double(i % 3)
                var p = Path()
                p.move(to: origin)
                let r = size.height * 1.3
                p.addLine(to: CGPoint(x: origin.x + CGFloat(sin(a - half)) * r, y: origin.y + CGFloat(cos(a - half)) * r))
                p.addLine(to: CGPoint(x: origin.x + CGFloat(sin(a + half)) * r, y: origin.y + CGFloat(cos(a + half)) * r))
                p.closeSubpath()
                ctx.fill(p, with: .linearGradient(Gradient(colors: [Color.white.opacity(0.26), Color.white.opacity(0)]), startPoint: origin, endPoint: CGPoint(x: size.width / 2, y: size.height * 0.8)))
            }
            let seeds: [(Double, Double, Double, Double)] = [(0.12, 0.30, 26, 0.0), (0.86, 0.22, 18, 1.7), (0.78, 0.55, 34, 3.1), (0.20, 0.62, 22, 4.4), (0.50, 0.14, 14, 5.2), (0.92, 0.78, 20, 2.3)]
            for (fx, fy, r, ph) in seeds {
                let dy = calm ? 0 : sin(t * 0.5 + ph) * 12
                let dx = calm ? 0 : cos(t * 0.35 + ph) * 6
                let c = CGPoint(x: size.width * fx + dx, y: size.height * fy + dy)
                let rect = CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)
                ctx.fill(Path(ellipseIn: rect), with: .color(Color.white.opacity(0.16)))
                ctx.stroke(Path(ellipseIn: rect), with: .color(Color.white.opacity(0.35)), lineWidth: 1.5)
            }
        }
    }
}
