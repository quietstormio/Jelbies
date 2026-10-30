//
//  LobbySVG.swift
//  A tiny SVG path reader (M L H V C S Q T A Z, absolute and relative) and the icon set of the lobby mockups (lobby.html's `ic`), so the lobby icons and the
//  card art are the mockup's own drawings. UI only.
//

import SwiftUI

enum SVG {
    private enum Tok { case cmd(Character), num(CGFloat) }

    private static func tokens(_ d: String) -> [Tok] {
        var out: [Tok] = []
        let cs = Array(d)
        var i = 0
        while i < cs.count {
            let c = cs[i]
            if c.isLetter && c != "e" && c != "E" { out.append(.cmd(c)); i += 1; continue }
            if c == "-" || c == "+" || c == "." || c.isNumber {
                var j = i
                if cs[j] == "-" || cs[j] == "+" { j += 1 }
                var dot = false
                while j < cs.count {
                    if cs[j].isNumber { j += 1 }
                    else if cs[j] == ".", !dot { dot = true; j += 1 }
                    else { break }
                }
                out.append(.num(CGFloat(Double(String(cs[i..<j])) ?? 0)))
                i = max(j, i + 1)
                continue
            }
            i += 1
        }
        return out
    }

    /// The path of an SVG `d` string.
    static func path(_ d: String) -> Path {
        var p = Path()
        let t = tokens(d)
        var i = 0
        var cmd: Character = "M"
        var cur = CGPoint.zero, start = CGPoint.zero
        var lastC: CGPoint?, lastQ: CGPoint?
        func num() -> CGFloat { if i < t.count, case .num(let v) = t[i] { i += 1; return v }; return 0 }
        func hasNum() -> Bool { if i < t.count, case .num = t[i] { return true }; return false }
        while i < t.count {
            if case .cmd(let c) = t[i] { cmd = c; i += 1; if c == "z" || c == "Z" { p.closeSubpath(); cur = start; lastC = nil; lastQ = nil; continue } }
            else if !hasNum() { i += 1; continue }
            let rel = cmd.isLowercase
            let o = rel ? cur : .zero
            switch Character(cmd.uppercased()) {
            case "M":
                cur = CGPoint(x: o.x + num(), y: o.y + num()); start = cur; p.move(to: cur); cmd = rel ? "l" : "L"; lastC = nil; lastQ = nil
            case "L":
                cur = CGPoint(x: o.x + num(), y: o.y + num()); p.addLine(to: cur); lastC = nil; lastQ = nil
            case "H":
                cur = CGPoint(x: (rel ? cur.x : 0) + num(), y: cur.y); p.addLine(to: cur); lastC = nil; lastQ = nil
            case "V":
                cur = CGPoint(x: cur.x, y: (rel ? cur.y : 0) + num()); p.addLine(to: cur); lastC = nil; lastQ = nil
            case "C":
                let c1 = CGPoint(x: o.x + num(), y: o.y + num()), c2 = CGPoint(x: o.x + num(), y: o.y + num()), e = CGPoint(x: o.x + num(), y: o.y + num())
                p.addCurve(to: e, control1: c1, control2: c2); cur = e; lastC = c2; lastQ = nil
            case "S":
                let c1 = lastC.map { CGPoint(x: 2 * cur.x - $0.x, y: 2 * cur.y - $0.y) } ?? cur
                let c2 = CGPoint(x: o.x + num(), y: o.y + num()), e = CGPoint(x: o.x + num(), y: o.y + num())
                p.addCurve(to: e, control1: c1, control2: c2); cur = e; lastC = c2; lastQ = nil
            case "Q":
                let c = CGPoint(x: o.x + num(), y: o.y + num()), e = CGPoint(x: o.x + num(), y: o.y + num())
                p.addQuadCurve(to: e, control: c); cur = e; lastQ = c; lastC = nil
            case "T":
                let c = lastQ.map { CGPoint(x: 2 * cur.x - $0.x, y: 2 * cur.y - $0.y) } ?? cur
                let e = CGPoint(x: o.x + num(), y: o.y + num())
                p.addQuadCurve(to: e, control: c); cur = e; lastQ = c; lastC = nil
            case "A":
                let rx = num(), ry = num(); _ = num(); let large = num() != 0, sweep = num() != 0
                let e = CGPoint(x: o.x + num(), y: o.y + num())
                arc(&p, from: cur, rx: rx, ry: ry, large: large, sweep: sweep, to: e); cur = e; lastC = nil; lastQ = nil
            default: i += 1
            }
        }
        return p
    }

    /// An elliptical arc (no axis rotation) as short line pieces.
    private static func arc(_ p: inout Path, from a: CGPoint, rx rx0: CGFloat, ry ry0: CGFloat, large: Bool, sweep: Bool, to b: CGPoint) {
        var rx = abs(rx0), ry = abs(ry0)
        guard rx > 0, ry > 0, a != b else { p.addLine(to: b); return }
        let x1 = (a.x - b.x) / 2, y1 = (a.y - b.y) / 2
        let lam = x1 * x1 / (rx * rx) + y1 * y1 / (ry * ry)
        if lam > 1 { let s = lam.squareRoot(); rx *= s; ry *= s }
        let num = rx * rx * ry * ry - rx * rx * y1 * y1 - ry * ry * x1 * x1
        let den = rx * rx * y1 * y1 + ry * ry * x1 * x1
        let coef = (large == sweep ? -1 : 1) * (max(0, num / den)).squareRoot()
        let cxp = coef * rx * y1 / ry, cyp = -coef * ry * x1 / rx
        let cx = cxp + (a.x + b.x) / 2, cy = cyp + (a.y + b.y) / 2
        let t1 = atan2((y1 - cyp) / ry, (x1 - cxp) / rx)
        let t2 = atan2((-y1 - cyp) / ry, (-x1 - cxp) / rx)
        var dt = t2 - t1
        if !sweep && dt > 0 { dt -= 2 * .pi }
        if sweep && dt < 0 { dt += 2 * .pi }
        let n = max(4, Int(abs(dt) / (.pi / 24)))
        for k in 1...n { let t = t1 + dt * CGFloat(k) / CGFloat(n); p.addLine(to: CGPoint(x: cx + rx * cos(t), y: cy + ry * sin(t))) }
    }
}

/// One drawn element of an icon.
struct SVGEl {
    enum Paint { case current(Double), white(Double) }
    enum Shape { case path(String), circle(CGFloat, CGFloat, CGFloat), ellipse(CGFloat, CGFloat, CGFloat, CGFloat), rect(CGFloat, CGFloat, CGFloat, CGFloat, CGFloat) }
    var shape: Shape
    var fill: Paint?
    var stroke: Paint?
    var width: CGFloat = 0
    var round = false
    func path() -> Path {
        switch shape {
        case .path(let d): return SVG.path(d)
        case .circle(let x, let y, let r): return Path(ellipseIn: CGRect(x: x - r, y: y - r, width: 2 * r, height: 2 * r))
        case .ellipse(let x, let y, let rx, let ry): return Path(ellipseIn: CGRect(x: x - rx, y: y - ry, width: 2 * rx, height: 2 * ry))
        case .rect(let x, let y, let w, let h, let r): return Path(roundedRect: CGRect(x: x, y: y, width: w, height: h), cornerRadius: r)
        }
    }
}

/// The lobby mockups' icon set (viewBox 24).
struct LobbyIcon: View {
    enum Kind {
        case star, hanger, drop, bulb, back, check, lock, swap, autosw, turtle, ball, run, flag, x, dotted, spike, block, ring, three, tap, trophy, feet, bend
        var size: CGFloat {
            switch self {
            case .check: return 13
            case .bulb: return 14
            case .hanger: return 24
            case .lock: return 16
            case .swap: return 13
            case .autosw: return 19
            case .turtle: return 21
            case .x: return 14
            case .dotted, .spike, .block: return 24
            default: return 22
            }
        }
        var els: [SVGEl] {
            func p(_ d: String, fill: SVGEl.Paint? = nil, stroke: SVGEl.Paint? = nil, w: CGFloat = 0, round: Bool = false) -> SVGEl { SVGEl(shape: .path(d), fill: fill, stroke: stroke, width: w, round: round) }
            let cur = SVGEl.Paint.current(1)
            switch self {
            case .star: return [SVGEl(shape: .path("M12 2.8 L14.7 8.6 L21 9.3 L16.3 13.6 L17.6 19.9 L12 16.7 L6.4 19.9 L7.7 13.6 L3 9.3 L9.3 8.6 Z"), fill: cur, stroke: cur, width: 1.2, round: true)]
            case .hanger: return [p("M12 8.2 V7.4 a2.4 2.4 0 1 1 2.4-2.4", stroke: cur, w: 2.3, round: true), p("M12 8.2 L3 15.2 a1.4 1.4 0 0 0 .9 2.5 H20.1 a1.4 1.4 0 0 0 .9-2.5 Z", stroke: cur, w: 2.3, round: true)]
            case .drop: return [p("M12 3 C15.5 8 18 11 18 14.5 a6 6 0 0 1 -12 0 C6 11 8.5 8 12 3 Z", fill: cur), p("M9.3 14.6 a2.8 2.8 0 0 0 2.4 2.7", stroke: .white(0.7), w: 1.6, round: true)]
            case .bulb: return [p("M12 2.5 a7 7 0 0 0 -4.2 12.6 V18 H16.2 V15.1 A7 7 0 0 0 12 2.5 Z", fill: cur), SVGEl(shape: .rect(8.6, 19.4, 6.8, 2.6, 1.3), fill: cur)]
            case .back: return [p("M15 4.5 L7.5 12 L15 19.5", stroke: cur, w: 3.4, round: true)]
            case .check: return [p("M5 12.5 L10 17.5 L19 7", stroke: .white(1), w: 4, round: true)]
            case .lock: return [SVGEl(shape: .rect(4.5, 10.5, 15, 11, 3), fill: cur), p("M8 10.8V8a4 4 0 0 1 8 0v2.8", stroke: cur, w: 2.8)]
            case .swap: return [p("M7 9.5 L12 4.5 L17 9.5 M7 14.5 L12 19.5 L17 14.5", stroke: cur, w: 3, round: true)]
            case .autosw: return [p("M4 8 H18 M14.5 4.5 L18 8 L14.5 11.5 M20 16 H6 M9.5 12.5 L6 16 L9.5 19.5", stroke: cur, w: 2.6, round: true)]
            case .turtle: return [p("M4 15.5 C4.5 10 8 7.5 11.5 7.5 C15 7.5 18.2 10 18.6 15.5 Z", fill: cur), SVGEl(shape: .circle(20.3, 13.2, 2.1), fill: cur),
                                  SVGEl(shape: .rect(5.5, 15, 3, 3.6, 1.2), fill: cur), SVGEl(shape: .rect(14, 15, 3, 3.6, 1.2), fill: cur),
                                  p("M7.3 12.3 L11.3 9.7 L15.3 12.3", stroke: .white(0.55), w: 1.4)]
            case .ball: return [SVGEl(shape: .circle(12, 12, 9), stroke: cur, width: 2.4),
                                p("M12 3 C9 7 9 12 12 12 C15 12 19.5 14.5 20.4 15.5 M12 12 C11 15 7.5 19 5 18.6 M4 9.2 C7 10.8 9 11.5 12 12", stroke: cur, w: 2)]
            case .run: return [SVGEl(shape: .circle(14.5, 4.6, 2.3), fill: cur),
                               p("M8 11 L11.5 8.3 L15 9.4 L17 12.6 M11.5 8.3 L10.4 13.6 L14 16.4 L13.2 21 M10.4 13.6 L8.2 17.4 L4.6 18.2", stroke: cur, w: 2.6, round: true)]
            case .flag: return [p("M5 21 V4", stroke: cur, w: 2.4, round: true), p("M5.5 4.5 H19 V14 H5.5 Z", fill: .current(0.25)),
                                p("M5.5 4.5h4.5v3.2H5.5zM14.5 4.5H19v3.2h-4.5zM10 7.7h4.5v3.2H10zM5.5 10.9H10V14H5.5zM14.5 10.9H19V14h-4.5z", fill: cur)]
            case .x: return [p("M5 5 L19 19 M19 5 L5 19", stroke: cur, w: 3.4, round: true)]
            case .dotted:
                return (0..<12).map { i in let a = Double(i) / 12 * 2 * .pi; return SVGEl(shape: .circle(12 + 8 * CGFloat(cos(a)), 12 + 8 * CGFloat(sin(a)), 1.5), fill: cur) }
            case .spike: return [SVGEl(shape: .circle(12, 12, 9.5), fill: cur), p("M8.5 8.5 L15.5 15.5 M15.8 9.8 V15.8 H9.8", stroke: .white(1), w: 2.6, round: true)]
            case .block: return [SVGEl(shape: .rect(8.5, 4, 7, 16, 1.8), stroke: cur, width: 2.5), p("M2.5 12 L5.5 9.5 V14.5 Z M21.5 12 L18.5 9.5 V14.5 Z", fill: cur)]
            case .ring: return [SVGEl(shape: .circle(12, 12, 8.5), stroke: cur, width: 2.4), SVGEl(shape: .circle(12, 12, 3.6), fill: cur)]
            case .three: return []
            case .tap: return [p("M9.5 12.5 V5.8 a1.8 1.8 0 0 1 3.6 0 V11 l4.2.8 a2.2 2.2 0 0 1 1.8 2.5 l-.9 5.7 H10.8 L6.6 15.3 a1.6 1.6 0 0 1 2.3-2.2 Z", fill: cur)]
            case .trophy: return [p("M7 4 H17 V9 a5 5 0 0 1 -10 0 Z", fill: cur), p("M7 6 H4 a3 3 0 0 0 3.5 4 M17 6 H20 a3 3 0 0 1 -3.5 4", stroke: cur, w: 2),
                                  SVGEl(shape: .rect(10.8, 13, 2.4, 4, 0), fill: cur), SVGEl(shape: .rect(7.5, 17, 9, 3, 1.2), fill: cur)]
            case .feet: return [SVGEl(shape: .ellipse(8, 9, 3.2, 4.6), fill: cur), SVGEl(shape: .ellipse(16, 15, 3.2, 4.6), fill: cur)]
            case .bend: return [p("M6 21 C6 13 18 12 18 4", stroke: cur, w: 2.8, round: true)]
            }
        }
    }
    let kind: Kind
    var color: Color = SK.ink
    var size: CGFloat?

    var body: some View {
        let s = size ?? kind.size
        Group {
            if kind == .three {
                Text("3").font(.system(size: 16 * s / 24, weight: .black, design: .rounded)).foregroundStyle(color).frame(width: s, height: s)
            } else {
                Canvas { ctx, sz in
                    let k = min(sz.width, sz.height) / 24
                    for e in kind.els {
                        let path = e.path().applying(CGAffineTransform(scaleX: k, y: k))
                        func col(_ p: SVGEl.Paint) -> Color { switch p { case .current(let o): return color.opacity(o); case .white(let o): return Color.white.opacity(o) } }
                        if let f = e.fill { ctx.fill(path, with: .color(col(f))) }
                        if let st = e.stroke { ctx.stroke(path, with: .color(col(st)), style: StrokeStyle(lineWidth: e.width * k, lineCap: e.round ? .round : .butt, lineJoin: e.round ? .round : .miter)) }
                    }
                }
                .frame(width: s, height: s)
            }
        }
        .accessibilityHidden(true)
    }
}
