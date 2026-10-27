//
//  JelbieGlyph.swift
//  A one-colour Jelbie silhouette: a round dome (a little wider than tall, flattened base), two stubby arm nubs, two bean feet peeking out under
//  the base, and two tall oval eyes cut out. Used as the roster button's icon (Needs/RosterView.swift).
//

import SwiftUI

struct JelbieGlyph: SwiftUI.Shape {
    func path(in r: CGRect) -> Path {
        let w = r.width, h = r.height
        func P(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: r.minX + x * w, y: r.minY + y * h) }
        func oval(_ cx: CGFloat, _ cy: CGFloat, _ rx: CGFloat, _ ry: CGFloat) -> Path {
            Path(ellipseIn: CGRect(x: r.minX + (cx - rx) * w, y: r.minY + (cy - ry) * h, width: 2 * rx * w, height: 2 * ry * h))
        }
        // body: a wide soft dome with a flat-ish base (like the icon's Peek head)
        var body = Path()
        body.move(to: P(0.12, 0.78))
        body.addCurve(to: P(0.50, 0.06), control1: P(0.12, 0.20), control2: P(0.26, 0.06))
        body.addCurve(to: P(0.88, 0.78), control1: P(0.74, 0.06), control2: P(0.88, 0.20))
        body.addQuadCurve(to: P(0.78, 0.88), control: P(0.88, 0.88))
        body.addLine(to: P(0.22, 0.88))
        body.addQuadCurve(to: P(0.12, 0.78), control: P(0.12, 0.88))
        body.closeSubpath()
        var s = body
        s = s.union(oval(0.10, 0.60, 0.10, 0.12))          // arms: bold stubs
        s = s.union(oval(0.90, 0.60, 0.10, 0.12))
        s = s.union(oval(0.35, 0.92, 0.14, 0.075))          // bean feet
        s = s.union(oval(0.65, 0.92, 0.14, 0.075))
        s = s.subtracting(oval(0.36, 0.50, 0.07, 0.115))          // eyes
        s = s.subtracting(oval(0.64, 0.50, 0.07, 0.115))
        // small arched brows above the eyes
        for cx: CGFloat in [0.36, 0.64] {
            var brow = Path()
            brow.move(to: P(cx - 0.09, 0.325))
            brow.addQuadCurve(to: P(cx + 0.09, 0.325), control: P(cx, 0.17))
            brow.addQuadCurve(to: P(cx - 0.09, 0.325), control: P(cx, 0.29))
            brow.closeSubpath()
            s = s.subtracting(brow)
        }
        return s
    }
}

#Preview { JelbieGlyph().fill(Color(red: 0.42, green: 0.34, blue: 0.30)).frame(width: 240, height: 240).padding() }
