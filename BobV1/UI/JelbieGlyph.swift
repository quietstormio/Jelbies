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
        // body: dome, wide, gently flat bottom
        var body = Path()
        body.move(to: P(0.08, 0.78))
        body.addCurve(to: P(0.50, 0.08), control1: P(0.08, 0.28), control2: P(0.24, 0.08))
        body.addCurve(to: P(0.92, 0.78), control1: P(0.76, 0.08), control2: P(0.92, 0.28))
        body.addQuadCurve(to: P(0.80, 0.88), control: P(0.92, 0.88))
        body.addLine(to: P(0.20, 0.88))
        body.addQuadCurve(to: P(0.08, 0.78), control: P(0.08, 0.88))
        body.closeSubpath()
        var s = body
        s = s.union(oval(0.06, 0.56, 0.08, 0.10))          // arms
        s = s.union(oval(0.94, 0.56, 0.08, 0.10))
        s = s.union(oval(0.33, 0.91, 0.12, 0.07))          // feet
        s = s.union(oval(0.67, 0.91, 0.12, 0.07))
        s = s.subtracting(oval(0.36, 0.42, 0.055, 0.115))          // eyes
        s = s.subtracting(oval(0.64, 0.42, 0.055, 0.115))
        return s
    }
}

#Preview { JelbieGlyph().fill(Color(red: 0.42, green: 0.34, blue: 0.30)).frame(width: 240, height: 240).padding() }
