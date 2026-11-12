//
//  SpringPageGlyphs.swift
//  The two small line icons of the Jelly Spring species page (design B): the "Drag to spin" arrows and the house under the big button.
//  Both are SwiftUI Shapes drawn in the design's 24 x 24 box (round caps and joins); the size is the frame they are given.
//

import SwiftUI

/// SVG `A r r 0 large sweep x y` (circle, no rotation) from `p0` as cubic curves, in y-down coordinates (the same as SwiftUI's).
private func addSVGArc(_ p: inout Path, from p0: CGPoint, radius r0: CGFloat, large: Bool, sweep: Bool, to p1: CGPoint) {
    let x1p = (p0.x - p1.x) / 2, y1p = (p0.y - p1.y) / 2
    var r = r0
    let h2 = x1p * x1p + y1p * y1p
    if h2 > r * r { r = h2.squareRoot() }                                  // the chord is longer than the diameter: grow the radius
    let k = max(0, (r * r * r * r - r * r * h2) / max(r * r * h2, 0.000001)).squareRoot() * (large != sweep ? 1 : -1)
    let cxp = k * y1p, cyp = -k * x1p
    let c = CGPoint(x: cxp + (p0.x + p1.x) / 2, y: cyp + (p0.y + p1.y) / 2)
    let a1 = atan2((y1p - cyp) / r, (x1p - cxp) / r)
    let a2 = atan2((-y1p - cyp) / r, (-x1p - cxp) / r)
    var d = a2 - a1
    if sweep, d < 0 { d += 2 * .pi }
    if !sweep, d > 0 { d -= 2 * .pi }
    let n = max(1, Int((abs(d) / (.pi / 2)).rounded(.up)))
    let step = d / CGFloat(n)
    for i in 0..<n {
        let s = a1 + step * CGFloat(i), e = s + step
        let t = 4 / 3 * tan(step / 4)
        let ps = CGPoint(x: c.x + r * cos(s), y: c.y + r * sin(s)), pe = CGPoint(x: c.x + r * cos(e), y: c.y + r * sin(e))
        let c1 = CGPoint(x: ps.x - t * r * sin(s), y: ps.y + t * r * cos(s))
        let c2 = CGPoint(x: pe.x + t * r * sin(e), y: pe.y - t * r * cos(e))
        p.addCurve(to: pe, control1: c1, control2: c2)
    }
}

/// Two curved arrows chasing each other: `M3 12a9 9 0 0 1 15.5-6.2L21 8`, `M21 3v5h-5`, `M21 12a9 9 0 0 1-15.5 6.2L3 16`, `M3 21v-5h5`.
struct SpinGlyph: SwiftUI.Shape {
    func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height) / 24
        func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: rect.minX + x * s, y: rect.minY + y * s) }
        var p = Path()
        p.move(to: pt(3, 12))
        addSVGArc(&p, from: pt(3, 12), radius: 9 * s, large: false, sweep: true, to: pt(18.5, 5.8))
        p.addLine(to: pt(21, 8))
        p.move(to: pt(21, 3)); p.addLine(to: pt(21, 8)); p.addLine(to: pt(16, 8))
        p.move(to: pt(21, 12))
        addSVGArc(&p, from: pt(21, 12), radius: 9 * s, large: false, sweep: true, to: pt(5.5, 18.2))
        p.addLine(to: pt(3, 16))
        p.move(to: pt(3, 21)); p.addLine(to: pt(3, 16)); p.addLine(to: pt(8, 16))
        return p
    }
}

/// A little house: `M3 11.5 12 4l9 7.5` (roof) and `M5.5 10v9.5h13V10` (walls).
struct HomeGlyph: SwiftUI.Shape {
    func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height) / 24
        func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: rect.minX + x * s, y: rect.minY + y * s) }
        var p = Path()
        p.move(to: pt(3, 11.5)); p.addLine(to: pt(12, 4)); p.addLine(to: pt(21, 11.5))
        p.move(to: pt(5.5, 10)); p.addLine(to: pt(5.5, 19.5)); p.addLine(to: pt(18.5, 19.5)); p.addLine(to: pt(18.5, 10))
        return p
    }
}

/// The spin arrows at `size` pt, stroked 3 / 24 of the size (the design's stroke 3 in a 24 box), in the current foreground colour.
struct SpinGlyphIcon: View {
    var size: CGFloat = 12
    var body: some View {
        SpinGlyph().stroke(style: StrokeStyle(lineWidth: 3 * size / 24, lineCap: .round, lineJoin: .round))
            .frame(width: size, height: size).accessibilityHidden(true)
    }
}

/// The house at `size` pt, stroked 2.6 / 24 of the size, in the current foreground colour.
struct HomeGlyphIcon: View {
    var size: CGFloat = 13
    var body: some View {
        HomeGlyph().stroke(style: StrokeStyle(lineWidth: 2.6 * size / 24, lineCap: .round, lineJoin: .round))
            .frame(width: size, height: size).accessibilityHidden(true)
    }
}
