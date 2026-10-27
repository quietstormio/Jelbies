//
//  AroundTownIsland.swift
//  The "Around town" floating-island map on the Town ("Where to?") screen. Ported from the design SVG (viewBox 400x200):
//  laid out in that design space and scaled uniformly to the card width. Place nodes are buttons (44 pt minimum hit areas).
//

import SwiftUI

// MARK: - A tiny SVG path parser (M L H V C S A Z, absolute and relative) so the design's icon path data is used verbatim

enum SVGPath {
    static func parse(_ d: String) -> Path {
        var tokens: [String] = []
        var cur = ""
        func flush() { if !cur.isEmpty { tokens.append(cur); cur = "" } }
        var seenDot = false
        for ch in d {
            if ch.isLetter { flush(); seenDot = false; tokens.append(String(ch)) }
            else if ch == " " || ch == "," { flush(); seenDot = false }
            else if ch == "-" { flush(); seenDot = false; cur.append(ch) }
            else if ch == "." { if seenDot { flush() }; seenDot = true; cur.append(ch) }
            else { cur.append(ch) }
        }
        flush()
        var p = Path()
        var i = 0
        var cmd: Character = "M"
        var pt = CGPoint.zero, start = CGPoint.zero, lastC2: CGPoint? = nil
        func num() -> CGFloat { defer { i += 1 }; return CGFloat(Double(tokens[i]) ?? 0) }
        func isCmd(_ s: String) -> Bool { s.count == 1 && s.first!.isLetter }
        while i < tokens.count {
            if isCmd(tokens[i]) { cmd = tokens[i].first!; i += 1; if cmd == "Z" || cmd == "z" { p.closeSubpath(); pt = start; lastC2 = nil; continue } }
            let rel = cmd.isLowercase
            let ox = rel ? pt.x : 0, oy = rel ? pt.y : 0
            switch cmd.uppercased() {
            case "M":
                pt = CGPoint(x: ox + num(), y: oy + num()); start = pt; p.move(to: pt); cmd = rel ? "l" : "L"; lastC2 = nil
            case "L":
                pt = CGPoint(x: ox + num(), y: oy + num()); p.addLine(to: pt); lastC2 = nil
            case "H":
                pt = CGPoint(x: ox + num(), y: pt.y); p.addLine(to: pt); lastC2 = nil
            case "V":
                pt = CGPoint(x: pt.x, y: oy + num()); p.addLine(to: pt); lastC2 = nil
            case "C":
                let c1 = CGPoint(x: ox + num(), y: oy + num()), c2 = CGPoint(x: ox + num(), y: oy + num()), e = CGPoint(x: ox + num(), y: oy + num())
                p.addCurve(to: e, control1: c1, control2: c2); pt = e; lastC2 = c2
            case "S":
                let c1 = lastC2.map { CGPoint(x: 2 * pt.x - $0.x, y: 2 * pt.y - $0.y) } ?? pt
                let c2 = CGPoint(x: ox + num(), y: oy + num()), e = CGPoint(x: ox + num(), y: oy + num())
                p.addCurve(to: e, control1: c1, control2: c2); pt = e; lastC2 = c2
            case "A":
                let rx = num(), ry = num(), rot = num(), large = num() != 0, sweep = num() != 0
                let e = CGPoint(x: ox + num(), y: oy + num())
                addArc(&p, from: pt, rx: rx, ry: ry, rot: rot, large: large, sweep: sweep, to: e); pt = e; lastC2 = nil
            default: i += 1
            }
        }
        return p
    }

    /// SVG endpoint arc -> cubic segments.
    private static func addArc(_ p: inout Path, from a: CGPoint, rx rx0: CGFloat, ry ry0: CGFloat, rot: CGFloat, large: Bool, sweep: Bool, to b: CGPoint) {
        var rx = abs(rx0), ry = abs(ry0)
        if rx == 0 || ry == 0 || a == b { p.addLine(to: b); return }
        let phi = rot * .pi / 180, cp = cos(phi), sp = sin(phi)
        let dx = (a.x - b.x) / 2, dy = (a.y - b.y) / 2
        let x1 = cp * dx + sp * dy, y1 = -sp * dx + cp * dy
        let lam = x1 * x1 / (rx * rx) + y1 * y1 / (ry * ry)
        if lam > 1 { rx *= sqrt(lam); ry *= sqrt(lam) }
        let num = rx * rx * ry * ry - rx * rx * y1 * y1 - ry * ry * x1 * x1
        let den = rx * rx * y1 * y1 + ry * ry * x1 * x1
        var co = sqrt(max(0, num / den)); if large == sweep { co = -co }
        let cxp = co * rx * y1 / ry, cyp = -co * ry * x1 / rx
        let cx = cp * cxp - sp * cyp + (a.x + b.x) / 2, cy = sp * cxp + cp * cyp + (a.y + b.y) / 2
        func ang(_ ux: CGFloat, _ uy: CGFloat, _ vx: CGFloat, _ vy: CGFloat) -> CGFloat {
            let s = ux * vy - uy * vx, c = ux * vx + uy * vy; return atan2(s, c)
        }
        let th1 = ang(1, 0, (x1 - cxp) / rx, (y1 - cyp) / ry)
        var dth = ang((x1 - cxp) / rx, (y1 - cyp) / ry, (-x1 - cxp) / rx, (-y1 - cyp) / ry)
        if !sweep && dth > 0 { dth -= 2 * .pi } else if sweep && dth < 0 { dth += 2 * .pi }
        let n = max(1, Int(ceil(abs(dth) / (.pi / 2))))
        let step = dth / CGFloat(n), t = 4.0 / 3.0 * tan(step / 4)
        var th = th1
        func pnt(_ th: CGFloat) -> CGPoint { CGPoint(x: cx + rx * cos(th) * cp - ry * sin(th) * sp, y: cy + rx * cos(th) * sp + ry * sin(th) * cp) }
        func der(_ th: CGFloat) -> CGPoint { CGPoint(x: -rx * sin(th) * cp - ry * cos(th) * sp, y: -rx * sin(th) * sp + ry * cos(th) * cp) }
        for _ in 0..<n {
            let p0 = pnt(th), d0 = der(th), p1 = pnt(th + step), d1 = der(th + step)
            p.addCurve(to: p1, control1: CGPoint(x: p0.x + t * d0.x, y: p0.y + t * d0.y), control2: CGPoint(x: p1.x - t * d1.x, y: p1.y - t * d1.y))
            th += step
        }
    }
}

// MARK: - Design data

private struct IconPart {
    let d: String
    var fill: UInt32? = nil
    var stroke: UInt32? = nil
    var width: CGFloat = 0
    var round = false
    var opacity: CGFloat = 1
}

private struct IconDef {
    let tx: CGFloat, ty: CGFloat, scale: CGFloat
    let parts: [IconPart]
}

private let ink: UInt32 = 0x4D331F
private let creamFill: UInt32 = 0xFFF8EC

struct IslandNode: Identifiable {
    let id: String          // "shop", "track", "studio", "cafe", "park", "groom", "home"
    let name: String
    let cx: CGFloat, cy: CGFloat, r: CGFloat
    let fill: UInt32
    let pill: CGFloat
    var strokeW: CGFloat = 3.4
    fileprivate var icon: IconDef
}

private let islandNodes: [IslandNode] = [
    IslandNode(id: "studio", name: "Studio", cx: 130, cy: 58, r: 19, fill: 0xFFE07A, pill: 52.76, icon: IconDef(tx: 121.07, ty: 49.07, scale: 0.744, parts: [
        IconPart(d: "M10.5 5.2l1.6 4.4 4.4 1.6-4.4 1.6-1.6 4.4-1.6-4.4-4.4-1.6 4.4-1.6z", fill: ink),
        IconPart(d: "M17.6 2.8l.8 2.1 2.1.8-2.1.8-.8 2.1-.8-2.1-2.1-.8 2.1-.8zM17.4 15.4l.7 1.8 1.8.7-1.8.7-.7 1.8-.7-1.8-1.8-.7 1.8-.7z", fill: ink)])),
    IslandNode(id: "track", name: "Track", cx: 270, cy: 58, r: 19, fill: 0x7DBAD4, pill: 48.1, icon: IconDef(tx: 261.07, ty: 49.07, scale: 0.744, parts: [
        IconPart(d: "M5.6 21.2V3.4", stroke: ink, width: 2.2, round: true),
        IconPart(d: "M6.4 4h12.2c.5 0 .8.5.5.9l-2.2 3.4 2.2 3.4c.3.4 0 .9-.5.9H6.4z", fill: ink),
        IconPart(d: "M9.2 4h2.8v2.8H9.2zM14.8 4h2.8v2.8h-2.8zM12 6.8h2.8v2.8H12zM9.2 9.6h2.8v2.8H9.2zM14.8 9.6h2.8v2.8h-2.8z", fill: creamFill)])),
    IslandNode(id: "shop", name: "Shop", cx: 56, cy: 92, r: 19, fill: 0xEE96AC, pill: 44.61, icon: IconDef(tx: 47.07, ty: 83.07, scale: 0.744, parts: [
        IconPart(d: "M4.4 8.2h15.2l-1.1 11.5a2 2 0 0 1-2 1.8H7.5a2 2 0 0 1-2-1.8z", fill: ink),
        IconPart(d: "M8.6 10.4V7.2a3.4 3.4 0 0 1 6.8 0v3.2", stroke: ink, width: 2, round: true)])),
    IslandNode(id: "park", name: "Park", cx: 344, cy: 92, r: 19, fill: 0x7DBAD4, pill: 43.09, icon: IconDef(tx: 335.07, ty: 83.07, scale: 0.744, parts: [
        IconPart(d: "M12 12.5v8.6", stroke: ink, width: 2.6, round: true),
        IconPart(d: "M16.9 7.6A4.9 4.9 0 1 1 7.1 7.6A4.9 4.9 0 1 1 16.9 7.6Z", fill: ink),
        IconPart(d: "M11.4 10.8A3.9 3.9 0 1 1 3.6 10.8A3.9 3.9 0 1 1 11.4 10.8Z", fill: ink),
        IconPart(d: "M20.4 10.8A3.9 3.9 0 1 1 12.6 10.8A3.9 3.9 0 1 1 20.4 10.8Z", fill: ink),
        IconPart(d: "M16.2 12A4.2 4.2 0 1 1 7.8 12A4.2 4.2 0 1 1 16.2 12Z", fill: ink)])),
    IslandNode(id: "cafe", name: "Café", cx: 112, cy: 134, r: 19, fill: 0x93D3A8, pill: 43.41, icon: IconDef(tx: 103.07, ty: 125.07, scale: 0.744, parts: [
        IconPart(d: "M4.2 8.6h11.6v5.2a5.8 5.8 0 0 1-11.6 0z", fill: ink),
        IconPart(d: "M15.8 9.6h1.4a2.6 2.6 0 0 1 0 5.2h-1.8", stroke: ink, width: 1.9),
        IconPart(d: "M2.8 20.2h14.4", stroke: ink, width: 2.2, round: true),
        IconPart(d: "M8 3.4c-.8 1 .8 1.6 0 2.8M11.4 3.4c-.8 1 .8 1.6 0 2.8", stroke: ink, width: 1.5, round: true)])),
    IslandNode(id: "groom", name: "Groomer", cx: 288, cy: 134, r: 19, fill: 0xEE96AC, pill: 66.93, icon: IconDef(tx: 279.07, ty: 125.07, scale: 0.744, parts: [
        IconPart(d: "M15.1 14A5.7 5.7 0 1 1 3.7 14A5.7 5.7 0 1 1 15.1 14Z", fill: ink),
        IconPart(d: "M20.2 8.2A3.6 3.6 0 1 1 13 8.2A3.6 3.6 0 1 1 20.2 8.2Z", fill: ink),
        IconPart(d: "M19.8 17A2.4 2.4 0 1 1 15 17A2.4 2.4 0 1 1 19.8 17Z", fill: ink),
        IconPart(d: "M8.9 12A1.5 1.5 0 1 1 5.9 12A1.5 1.5 0 1 1 8.9 12Z", fill: creamFill, opacity: 0.9),
        IconPart(d: "M6.4 3.4l.65 1.75 1.75.65-1.75.65-.65 1.75-.65-1.75-1.75-.65 1.75-.65z", fill: ink)])),
    IslandNode(id: "home", name: "Home", cx: 200, cy: 96, r: 25, fill: 0xFFF8EC, pill: 49.01, strokeW: 4, icon: IconDef(tx: 188, ty: 84, scale: 1, parts: [
        IconPart(d: "M12 3.2 2.8 11.2c-.5.4-.2 1.2.4 1.2h1.9v7.4c0 .7.5 1.2 1.2 1.2h3.6v-5.2c0-.5.4-.9.9-.9h2.4c.5 0 .9.4.9.9V21h3.6c.7 0 1.2-.5 1.2-1.2v-7.4h1.9c.6 0 .9-.8.4-1.2l-2.3-2V5.4c0-.4-.3-.7-.7-.7h-1.4c-.4 0-.7.3-.7.7v1.3z", fill: ink)])),
]

private func C(_ h: UInt32, _ o: Double = 1) -> Color { Color(hex: h).opacity(o) }
private func ellipsePath(_ cx: CGFloat, _ cy: CGFloat, _ rx: CGFloat, _ ry: CGFloat) -> Path { Path(ellipseIn: CGRect(x: cx - rx, y: cy - ry, width: 2 * rx, height: 2 * ry)) }

// MARK: - Drawing

private enum IslandArt {
    static func sky(_ ctx: inout GraphicsContext) {
        let r = CGRect(x: 0, y: 0, width: 400, height: 200)
        ctx.fill(Path(r), with: .linearGradient(Gradient(stops: [.init(color: C(0x9FD0E3), location: 0), .init(color: C(0xD6EEF1), location: 0.85)]), startPoint: .zero, endPoint: CGPoint(x: 0, y: 200)))
        // sun glow: objectBoundingBox radial (0.12, 0.1) r 0.5 -> an ellipse 200 x 100
        ctx.drawLayer { l in
            l.translateBy(x: 48, y: 20); l.scaleBy(x: 1, y: 0.5)
            l.fill(Path(CGRect(x: -48, y: -40, width: 400, height: 400)), with: .radialGradient(Gradient(colors: [C(0xFFF3CF, 0.9), C(0xFFF3CF, 0)]), center: .zero, startRadius: 0, endRadius: 200))
        }
        func cloud(_ o: Double, _ e: [(CGFloat, CGFloat, CGFloat, CGFloat)]) {
            ctx.drawLayer { l in
                l.opacity = o
                for (cx, cy, rx, ry) in e { l.fill(ellipsePath(cx, cy, rx, ry), with: .color(.white)) }
            }
        }
        cloud(0.55, [(360, 30, 17.6, 7.2), (352, 26.8, 8.8, 7.2), (366.4, 24.4, 10.4, 8.8)])
        cloud(0.35, [(200, 14, 13.2, 5.4), (194, 11.6, 6.6, 5.4), (204.8, 9.8, 7.8, 6.6)])
        cloud(0.35, [(20, 170, 15.4, 6.3), (13, 167.2, 7.7, 6.3), (25.6, 165.1, 9.1, 7.7)])
    }

    static func island(_ ctx: inout GraphicsContext) {
        ctx.drawLayer { l in
            l.addFilter(.blur(radius: 6))
            l.fill(ellipsePath(200, 134, 178, 52), with: .color(C(0x4F8F6A, 0.22)))
        }
        let rim = ellipsePath(200, 116, 184, 62)
        ctx.fill(rim, with: .color(C(0xD9B98F)))
        ctx.stroke(rim, with: .color(C(0xC7A276)), lineWidth: 2)
        ctx.fill(ellipsePath(200, 104, 184, 62), with: .linearGradient(Gradient(colors: [C(0xB9E5C2), C(0x9FD7AE)]), startPoint: CGPoint(x: 0, y: 42), endPoint: CGPoint(x: 0, y: 166)))
        ctx.fill(ellipsePath(200, 100, 158, 46), with: .color(C(0xC6EBCD, 0.6)))
        ctx.fill(ellipsePath(200, 160, 22, 5.5), with: .color(C(0x9FD3E6)))
        ctx.fill(ellipsePath(195, 158.6, 7, 1.6), with: .color(.white.opacity(0.65)))
        for (x, y, w, h, cy, r) in [(164.8, 50.0, 2.4, 5.2, 48.1, 5.5), (234.8, 50, 2.4, 5.2, 48.1, 5.5), (170.8, 160, 2.4, 4, 158.5, 4.2), (226.8, 160, 2.4, 4, 158.5, 4.2)] as [(CGFloat, CGFloat, CGFloat, CGFloat, CGFloat, CGFloat)] {
            ctx.fill(Path(roundedRect: CGRect(x: x, y: y, width: w, height: h), cornerRadius: 1), with: .color(C(0xB58D67)))
            ctx.fill(ellipsePath(x + 1.2, cy, r, r), with: .color(C(0x8FCB9C)))
        }
        for (x, y, c) in [(250.0, 112.0, 0xF7B3C5), (256, 117, 0xFFE07A), (146, 112, 0xFFF8EC), (152, 117, 0xF7B3C5)] as [(CGFloat, CGFloat, UInt32)] {
            ctx.fill(ellipsePath(x, y, 2.1, 2.1), with: .color(C(c)))
        }
    }

    static func node(_ ctx: inout GraphicsContext, _ n: IslandNode, label: GraphicsContext.ResolvedText) {
        ctx.drawLayer { l in
            l.addFilter(.shadow(color: C(0x3C5A3C, 0.22), radius: 6, x: 0, y: 3))
            let c = ellipsePath(n.cx, n.cy, n.r, n.r)
            l.fill(c, with: .color(C(n.fill)))
            l.stroke(c, with: .color(.white), lineWidth: n.strokeW)
        }
        let t = CGAffineTransform(translationX: n.icon.tx, y: n.icon.ty).scaledBy(x: n.icon.scale, y: n.icon.scale)
        for part in n.icon.parts {
            let p = SVGPath.parse(part.d).applying(t)
            if let f = part.fill { ctx.fill(p, with: .color(C(f, part.opacity))) }
            if let s = part.stroke { ctx.stroke(p, with: .color(C(s)), style: StrokeStyle(lineWidth: part.width * n.icon.scale, lineCap: part.round ? .round : .butt)) }
        }
        let py = n.cy + n.r + 3 + (n.id == "home" ? 0 : 0)
        _ = py
        let top: CGFloat = n.id == "home" ? 124 : n.cy + 22
        ctx.drawLayer { l in
            l.addFilter(.shadow(color: C(0x3C5A3C, 0.18), radius: 3.2, x: 0, y: 1.5))
            l.fill(Path(roundedRect: CGRect(x: n.cx - n.pill / 2, y: top, width: n.pill, height: 22), cornerRadius: 11), with: .color(C(0xFFF9EF)))
        }
        ctx.draw(label, at: CGPoint(x: n.cx, y: top + 11), anchor: .center)
    }

    struct Palette { let body, edge, shine, feet: UInt32; let shadow: Double; let browL, browR, eyeL, eyeR: CGFloat; let bx: (CGFloat, CGFloat) }

    static func jelbie(_ ctx: inout GraphicsContext, x: CGFloat, y: CGFloat, scale: CGFloat, body: UInt32, edge: UInt32, shine: UInt32, feet: UInt32, shadow: Double, brow: (CGFloat, CGFloat, CGFloat, CGFloat), eyes: (CGFloat, CGFloat), bob: CGFloat) {
        ctx.drawLayer { g in
            g.translateBy(x: x, y: y); g.scaleBy(x: scale, y: scale)
            g.fill(ellipsePath(0, 1.5, 15, 3.2), with: .color(Color(hex: 0x2E4A2E).opacity(shadow)))
            g.translateBy(x: 0, y: bob / scale)
            for fx in [-6.2, 6.2] as [CGFloat] { g.fill(ellipsePath(fx, -1.6, 4.6, 3), with: .color(C(feet))) }
            let bodyP = SVGPath.parse("M-14,-9 C-14,-26 -8,-31 0,-31 C8,-31 14,-26 14,-9 C14,-3.5 10,-1.8 6,-1.8 L-6,-1.8 C-10,-1.8 -14,-3.5 -14,-9 Z")
            g.fill(bodyP, with: .color(C(body))); g.stroke(bodyP, with: .color(C(edge)), lineWidth: 1.2)
            for (ex, ey) in [(-14.6, -11.0), (14.6, -12.0)] as [(CGFloat, CGFloat)] {
                let e = ellipsePath(ex, ey, 3.4, 4.2)
                g.fill(e, with: .color(C(body))); g.stroke(e, with: .color(C(edge)), lineWidth: 1.1)
            }
            g.stroke(SVGPath.parse("M-9,-25 C-6,-28.5 -1,-29 2,-28.6"), with: .color(C(shine)), style: StrokeStyle(lineWidth: 2.2, lineCap: .round))
            var b = Path()
            b.move(to: CGPoint(x: brow.0, y: -19.8)); b.addLine(to: CGPoint(x: brow.0 + 3.8, y: -19.8))
            b.move(to: CGPoint(x: brow.1, y: -19.8)); b.addLine(to: CGPoint(x: brow.1 + 3.8, y: -19.8))
            g.stroke(b, with: .color(C(ink)), style: StrokeStyle(lineWidth: 1.3, lineCap: .round))
            for ex in [eyes.0, eyes.1] { g.fill(ellipsePath(ex, -15.6, 1.45, 1.9), with: .color(C(ink))) }
        }
    }
}

// MARK: - The view

struct AroundTownIsland: View {
    /// Place ids (island node ids) that are tappable right now; Home is always active.
    var active: (String) -> Bool
    var go: (String) -> Void
    var home: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geo in
            let s = geo.size.width / 400
            ZStack(alignment: .topLeading) {
                Canvas { ctx, _ in
                    ctx.scaleBy(x: s, y: s)
                    var c = ctx
                    IslandArt.sky(&c); IslandArt.island(&c)
                }
                ForEach(islandNodes) { n in
                    let on = n.id == "home" || active(n.id)
                    Canvas { ctx, _ in
                        ctx.scaleBy(x: s, y: s)
                        var c = ctx
                        let label = c.resolve(Text(n.name).font(.system(size: 12.5, weight: .semibold, design: .rounded)).foregroundColor(C(ink)))
                        IslandArt.node(&c, n, label: label)
                    }
                    .opacity(on ? 1 : 0.35)
                    .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: on)
                }
                TimelineView(.animation(minimumInterval: 1.0 / 30, paused: reduceMotion)) { tl in
                    let t = reduceMotion ? 0 : tl.date.timeIntervalSinceReferenceDate
                    Canvas { ctx, _ in
                        ctx.scaleBy(x: s, y: s)
                        var c = ctx
                        func bob(_ phase: Double) -> CGFloat { reduceMotion ? 0 : CGFloat(-0.9 * (0.5 + 0.5 * sin(t * 1.6 + phase))) }
                        IslandArt.jelbie(&c, x: 201, y: 70, scale: 0.9, body: 0xFFE27E, edge: 0xF2C24E, shine: 0xFFF6D2, feet: 0xF7C95C, shadow: 0.16, brow: (-7.6, 3.8, 0, 0), eyes: (-5.6, 5.6), bob: bob(0))
                        IslandArt.jelbie(&c, x: 147, y: 146, scale: 0.5, body: 0xF8B6C7, edge: 0xE897AD, shine: 0xFFE6EE, feet: 0xEFA3B8, shadow: 0.12, brow: (-6.6, 4.8, 0, 0), eyes: (-4.6, 6.6), bob: bob(1.3))
                        IslandArt.jelbie(&c, x: 159, y: 150, scale: 0.5, body: 0xAED6EF, edge: 0x88BFE0, shine: 0xE8F4FB, feet: 0x97C9E8, shadow: 0.12, brow: (-8.6, 2.8, 0, 0), eyes: (-6.6, 4.6), bob: bob(2.6))
                        IslandArt.jelbie(&c, x: 304, y: 67, scale: 0.5, body: 0xABE3C3, edge: 0x86CFA6, shine: 0xE6F9EE, feet: 0x95D8B1, shadow: 0.12, brow: (-8.6, 2.8, 0, 0), eyes: (-6.6, 4.6), bob: bob(3.9))
                    }
                }
                .allowsHitTesting(false)
                // Tap targets: the node and its label pill, at least 44 pt each way
                ForEach(islandNodes) { n in
                    let on = n.id == "home" || active(n.id)
                    let top = n.cy - n.r, bottom = (n.id == "home" ? 124 : n.cy + 22) + 22
                    let w = max(44, max(n.pill, 2 * n.r) * s), h = max(44, (bottom - top) * s)
                    Button {
                        AudioHub.shared.uiTap()
                        if n.id == "home" { home() } else { go(n.id) }
                    } label: { Color.clear.frame(width: w, height: h).contentShape(Rectangle()) }
                    .buttonStyle(.plain).disabled(!on)
                    .accessibilityLabel(n.name).accessibilityIdentifier("island-\(n.id)")
                    .position(x: n.cx * s, y: (top + bottom) / 2 * s)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .clipShape(RoundedRectangle(cornerRadius: 30 * s, style: .continuous))
        }
        .aspectRatio(2, contentMode: .fit)
        .accessibilityElement(children: .contain)
    }
}
