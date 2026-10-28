//
//  JelbieGlyph.swift
//  A one-colour Jelbie silhouette from the real front proportions (BobForm, the same outline the theme icon uses): the soft egg with its wider
//  lower half, the two short arm nubs at the real arm height, the two bean feet under the base, with the two oval eyes and the two short tilted
//  brows cut out (the frost shows through). Used as the roster button's icon (Needs/RosterView.swift).
//

import SwiftUI

struct JelbieGlyph: SwiftUI.Shape {
    func path(in r: CGRect) -> Path {
        // world box: x -0.70...0.70 (arm tips), y 0 (floor) ... BobForm.top
        let wx = 1.40, wy = BobForm.top
        let sc = Double(min(r.width / wx, r.height / wy))
        let ox = Double(r.midX), oy = Double(r.midY) + (wy / 2) * sc          // screen y of world y = 0
        func P(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x: ox + x * sc, y: oy - y * sc) }

        var body = Path()
        let n = 160
        var left: [CGPoint] = [], right: [CGPoint] = []
        for i in 0...n {
            let y = BobForm.lift + (1 - Double(i) / Double(n)) * BobForm.bodyH
            let hw = BobForm.halfWidth(t: (y - BobForm.lift) / BobForm.bodyH)
            left.append(P(-hw, y)); right.append(P(hw, y))
        }
        body.addLines(left); for q in right.reversed() { body.addLine(to: q) }; body.closeSubpath()

        func arm(_ s: Double) -> Path {
            let c = P(s * BobForm.armC.x, BobForm.armC.y)
            let e = Path(ellipseIn: CGRect(x: -BobForm.armSemi.x * sc, y: -BobForm.armSemi.y * sc, width: 2 * BobForm.armSemi.x * sc, height: 2 * BobForm.armSemi.y * sc))
            return e.applying(CGAffineTransform(translationX: c.x, y: c.y).rotated(by: CGFloat(s * -BobForm.armTilt)))
        }
        func foot(_ s: Double) -> Path {
            let hw = BobForm.footRadii.x * 0.88, h = 0.18
            return Path(roundedRect: CGRect(x: P(s * BobForm.footX - hw, h).x, y: P(0, h).y, width: 2 * hw * sc, height: h * sc),
                        cornerRadii: RectangleCornerRadii(topLeading: 0.09 * sc, bottomLeading: 0.075 * sc, bottomTrailing: 0.075 * sc, topTrailing: 0.09 * sc), style: .continuous)
        }
        var sil = body
        for s in [-1.0, 1.0] { sil = sil.union(arm(s)).union(foot(s)) }

        // face, cut out: eyes and tilted brows at the real positions, a little enlarged so they read at 44 pt
        let k = 1.2
        let rx = BobForm.eyeHalfW * k, ry = BobForm.eyeHalfH * k
        let hl = BobForm.browHalfLen * k, ht = BobForm.browHalfThick * k * 1.35
        let dy = sin(atan(BobForm.browTilt)) * (hl - ht)
        for s in [-1.0, 1.0] {
            let ecx = s * BobForm.eyeX, pe = P(ecx, BobForm.eyeY)
            sil = sil.subtracting(Path(ellipseIn: CGRect(x: pe.x - rx * sc, y: pe.y - ry * sc, width: 2 * rx * sc, height: 2 * ry * sc)))
            var brow = Path()
            brow.move(to: P(ecx - s * (hl - ht), BobForm.browY + dy)); brow.addLine(to: P(ecx + s * (hl - ht), BobForm.browY - dy))
            sil = sil.subtracting(brow.strokedPath(StrokeStyle(lineWidth: 2 * ht * sc, lineCap: .round)))
        }
        return sil
    }
}

#Preview { JelbieGlyph().fill(Color(red: 0.42, green: 0.34, blue: 0.30)).frame(width: 256, height: 256).padding() }
