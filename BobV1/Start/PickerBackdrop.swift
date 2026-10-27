//
//  PickerBackdrop.swift
//  The species picker's look (from the design boards): the saturated whole-screen page colour with strong light rays fanning from behind the
//  title, a glow behind the Jelbie and a few floating bubbles; and the round pedestal the Jelbie stands on (a cream top with a soft glow, a thick
//  rim in a deeper shade of the page colour, like a cylinder seen from slightly above). `calm` (Reduce Motion) holds rays and bubbles still.
//

import SwiftUI

struct PickerBackdrop: View {
    var top: Color, bottom: Color
    var calm: Bool
    /// Where the rays start, as a fraction of the screen height (behind the title / the Jelbie's head).
    var rayOriginY: CGFloat = 0.38

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
            let origin = CGPoint(x: size.width / 2, y: size.height * rayOriginY)
            let sway = calm ? 0 : sin(t * 0.22) * 0.03
            let n = 44
            let reach = size.height * 1.4
            // rays: alternating wedges across the upper half-plane and down the sides, brighter near the origin
            for i in 0..<n where i % 2 == 0 {
                let a0 = -Double.pi * 0.62 + Double(i) / Double(n) * Double.pi * 1.24 + sway
                let a1 = a0 + Double.pi * 1.24 / Double(n)
                var p = Path()
                p.move(to: origin)
                p.addLine(to: CGPoint(x: origin.x + CGFloat(sin(a0)) * reach, y: origin.y - CGFloat(cos(a0)) * reach))
                p.addLine(to: CGPoint(x: origin.x + CGFloat(sin(a1)) * reach, y: origin.y - CGFloat(cos(a1)) * reach))
                p.closeSubpath()
                ctx.fill(p, with: .radialGradient(Gradient(colors: [Color.white.opacity(0.19), Color.white.opacity(0.09), Color.white.opacity(0.04)]),
                                                  center: origin, startRadius: 0, endRadius: size.height * 0.75))
            }
            // glow behind the Jelbie
            let g = CGRect(x: origin.x - size.width * 0.75, y: origin.y - size.width * 0.5, width: size.width * 1.5, height: size.width * 1.2)
            ctx.fill(Path(ellipseIn: g), with: .radialGradient(Gradient(colors: [Color.white.opacity(0.32), Color.white.opacity(0)]),
                                                            center: CGPoint(x: origin.x, y: origin.y + size.height * 0.1), startRadius: 0, endRadius: size.width * 0.7))
            // bubbles (design-board positions, as fractions of 440 x 956)
            let seeds: [(Double, Double, Double, Double)] = [(0.075, 0.247, 9.5, 0.0), (0.90, 0.280, 14.5, 1.7), (0.13, 0.333, 5, 3.1),
                                                              (0.932, 0.157, 6, 4.4), (0.872, 0.492, 7.5, 5.2), (0.068, 0.544, 12, 2.3)]
            let k = size.width / 440
            for (fx, fy, r0, ph) in seeds {
                let r = r0 * k
                let dy = calm ? 0 : sin(t * 0.55 + ph) * 7 * k
                let dx = calm ? 0 : cos(t * 0.37 + ph) * 3 * k
                let c = CGPoint(x: size.width * fx + dx, y: size.height * fy + dy)
                let rect = CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)
                ctx.fill(Path(ellipseIn: rect), with: .color(Color.white.opacity(0.22)))
                ctx.stroke(Path(ellipseIn: rect.insetBy(dx: 0.75, dy: 0.75)), with: .color(Color.white.opacity(0.75)), lineWidth: max(1.5, r * 0.12))
                let gr = r * 0.22
                ctx.fill(Path(ellipseIn: CGRect(x: c.x - r * 0.42 - gr, y: c.y - r * 0.42 - gr, width: gr * 2, height: gr * 2)), with: .color(Color.white.opacity(0.9)))
            }
        }
    }
}

/// The round pedestal, in a 308 x 121 box: a cream top (soft inner glow, a faint inner ring, a bright edge) on a thick rim in a deeper page colour.
struct PickerPedestal: View {
    let look: SpeciesLook
    static let width: CGFloat = 308, topH: CGFloat = 86, thick: CGFloat = 35

    var body: some View {
        let w = Self.width, th = Self.topH, k = Self.thick
        ZStack(alignment: .topLeading) {
            PedestalSide(topH: th, thick: k)
                .fill(LinearGradient(colors: [look.rimTop, look.rimBottom], startPoint: .top, endPoint: .bottom))
                .overlay(PedestalSide(topH: th, thick: k).stroke(Color.white.opacity(0.18), lineWidth: 1).mask(LinearGradient(colors: [.white, .clear], startPoint: .top, endPoint: .bottom)))
            Ellipse().fill(LinearGradient(colors: [Color.white, look.padTop], startPoint: .top, endPoint: .bottom)).frame(width: w, height: th)
            Ellipse().fill(RadialGradient(colors: [look.glow.opacity(0.30), look.glow.opacity(0)], center: .center, startRadius: 0, endRadius: w * 0.36))
                .frame(width: w, height: th)
            Ellipse().strokeBorder(look.glow.opacity(0.10), lineWidth: 1).frame(width: w - 56, height: th - 20).offset(x: 28, y: 10)
            Ellipse().strokeBorder(Color.white.opacity(0.8), lineWidth: 1.2).frame(width: w, height: th)
        }
        .frame(width: w, height: th + k, alignment: .topLeading)
        .accessibilityHidden(true)
    }
}

private struct PedestalSide: SwiftUI.Shape {
    let topH: CGFloat, thick: CGFloat
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.addEllipse(in: CGRect(x: 0, y: thick, width: r.width, height: topH))
        p.addRect(CGRect(x: 0, y: topH / 2, width: r.width, height: thick))
        return p
    }
}
