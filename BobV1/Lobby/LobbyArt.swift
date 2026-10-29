//
//  LobbyArt.swift
//  The art on the lobby cards, drawn in SwiftUI from the mockup's SVG (lobby.html courtArt / courseArt): a beach court per Volleyball tier, and a course
//  shape on a green field per Track course. Both draw into a 120 x 78 box scaled to fill (xMidYMid slice). UI only.
//

import SwiftUI

private func hexColor(_ h: UInt32, _ a: Double = 1) -> Color { Color(hex: h).opacity(a) }

private extension GraphicsContext {
    /// Maps the 120 x 78 art box onto `size`, "slice": scaled to cover, centred.
    mutating func sliceTransform(_ size: CGSize) {
        let s = max(size.width / 120, size.height / 78)
        translateBy(x: (size.width - 120 * s) / 2, y: (size.height - 78 * s) / 2)
        scaleBy(x: s, y: s)
    }
    func line(_ a: CGPoint, _ b: CGPoint, _ c: Color, _ w: CGFloat) {
        var p = Path(); p.move(to: a); p.addLine(to: b)
        stroke(p, with: .color(c), lineWidth: w)
    }
}

struct CourtArt: View {
    let tier: VolleyTier
    private var palette: (sea: UInt32, sand: UInt32, court: UInt32) {
        switch tier {
        case .sandcastle: return (0xA9DCE6, 0xF5DFB3, 0xECCF99)
        case .shore: return (0x86C9DC, 0xF3DAA9, 0xE8C990)
        case .reef: return (0x5CC3BE, 0xF4E5C6, 0xE9D5AC)
        case .tidal: return (0x4B86B9, 0xEBDAB8, 0xDFC79E)
        }
    }
    var body: some View {
        Canvas { ctx, size in
            var c = ctx
            c.clip(to: Path(CGRect(origin: .zero, size: size)))
            c.sliceTransform(size)
            let P = palette
            c.fill(Path(CGRect(x: 0, y: 0, width: 120, height: 78)), with: .linearGradient(Gradient(colors: [hexColor(0xD5EEF4), hexColor(0xF2FAF8)]), startPoint: .zero, endPoint: CGPoint(x: 0, y: 78)))
            var wave = "M0 22"
            var x = 0
            while x < 116 { wave += " Q \(Double(x) + 3.5) 19 \(x + 7) 22 T \(x + 14) 22"; x += 14 }
            c.fill(SVG.path(wave + " L120 22 L120 31 L0 31 Z"), with: .color(hexColor(P.sea)))
            c.stroke(SVG.path(wave), with: .color(.white.opacity(0.75)), lineWidth: 1.3)
            c.fill(Path(CGRect(x: 0, y: 30, width: 120, height: 48)), with: .color(hexColor(P.sand)))
            let court = SVG.path("M28 38 L92 38 L111 77 L9 77 Z")
            c.fill(court, with: .color(hexColor(P.court)))
            c.stroke(court, with: .color(.white), style: StrokeStyle(lineWidth: 1.6, lineJoin: .round))
            c.line(CGPoint(x: 19.5, y: 56), CGPoint(x: 100.5, y: 56), .white.opacity(0.7), 1)
            c.line(CGPoint(x: 19.5, y: 56), CGPoint(x: 19.5, y: 43), hexColor(0x7A5A40), 1.6)
            c.line(CGPoint(x: 100.5, y: 56), CGPoint(x: 100.5, y: 43), hexColor(0x7A5A40), 1.6)
            c.fill(Path(CGRect(x: 19.5, y: 44, width: 81, height: 6)), with: .color(.white.opacity(0.35)))
            var mx: CGFloat = 22
            while mx < 100 { c.line(CGPoint(x: mx, y: 44), CGPoint(x: mx, y: 50), hexColor(0x6B5749, 0.35), 0.6); mx += 3.4 }
            c.line(CGPoint(x: 19.5, y: 44), CGPoint(x: 100.5, y: 44), .white, 1.8)
            let ball = Path(ellipseIn: CGRect(x: 74 - 4.2, y: 33 - 4.2, width: 8.4, height: 8.4))
            c.fill(ball, with: .color(.white)); c.stroke(ball, with: .color(hexColor(0xE7B95A)), lineWidth: 1)
            c.stroke(SVG.path("M71 31.5 Q74 33 77 31.2 M72.5 36 Q74 33.5 73.6 29"), with: .color(hexColor(0xE7B95A)), lineWidth: 0.9)
            switch tier {
            case .sandcastle:
                var g = c; g.translateBy(x: 4, y: 55)
                let sand = hexColor(0xD9AF6C)
                g.fill(Path(CGRect(x: 2, y: 10, width: 20, height: 12)), with: .color(hexColor(0xE2BC7C)))
                g.fill(Path(CGRect(x: 0, y: 4, width: 7, height: 18)), with: .color(sand))
                g.fill(Path(CGRect(x: 17, y: 4, width: 7, height: 18)), with: .color(sand))
                g.fill(SVG.path("M0 4h2v-2h1.5v2h2v-2H7v2"), with: .color(sand))
                g.fill(SVG.path("M17 4h2v-2h1.5v2h2v-2H24v2"), with: .color(sand))
                g.fill(Path(roundedRect: CGRect(x: 9.5, y: 15, width: 5, height: 7), cornerRadius: 2.5), with: .color(hexColor(0xB98C4E)))
                g.line(CGPoint(x: 12, y: 10), CGPoint(x: 12, y: 1), hexColor(0x7A5A40), 1)
                g.fill(SVG.path("M12 1 L18 3 L12 5 Z"), with: .color(hexColor(0xE98AA4)))
            case .shore:
                var g = c; g.translateBy(x: 6, y: 30)
                g.stroke(SVG.path("M8 46 C9 34 6 22 9 12"), with: .color(hexColor(0xA9825A)), style: StrokeStyle(lineWidth: 2.6, lineCap: .round))
                g.fill(SVG.path("M9 12 C3 9 -2 11 -4 15 C1 12 5 12 9 13 Z M9 12 C14 7 20 8 23 12 C18 10 14 11 9 13 Z M9 12 C7 6 9 1 13 -1 C11 4 11 8 9.6 12.6 Z M9 12 C4 13 1 18 0 22 C4 17 7 15 9.5 13 Z M9 12 C14 13 17 17 18 21 C14 17 12 15 9 13 Z"), with: .color(hexColor(0x7FB384)))
            case .reef:
                var g = c; g.translateBy(x: 96, y: 18)
                g.stroke(SVG.path("M6 13 V5 M6 9 L2 5 M6 8 L10 3 M10 3 V0"), with: .color(hexColor(0xF08BA0)), style: StrokeStyle(lineWidth: 2.4, lineCap: .round))
                var h = c; h.translateBy(x: 13, y: 64)
                h.fill(SVG.path("M6 0 L7.6 4.4 L12.2 4.6 L8.6 7.4 L9.9 11.8 L6 9.2 L2.1 11.8 L3.4 7.4 L-0.2 4.6 L4.4 4.4 Z"), with: .color(hexColor(0xF4A261)))
            case .tidal:
                let fin = SVG.path("M0 31 C6 14 22 8 34 13 C27 13 23 18 26 23 C29 27 35 26 37 22 C38 28 32 33 24 32 Z")
                c.fill(fin, with: .color(hexColor(0x3E73A6)))
                c.stroke(SVG.path("M34 13 C27 13 23 18 26 23"), with: .color(.white), style: StrokeStyle(lineWidth: 2, lineCap: .round))
            }
        }
        .accessibilityHidden(true)
    }
}

struct CourseArt: View {
    let tier: CourseTier
    private var d: String {
        switch tier {
        case .puddle: return "M60 10 L60 64"
        case .ripple: return "M54 10 C 34 24, 84 32, 62 44 S 48 58, 60 64"
        case .splash: return "M40 10 C 96 16, 18 34, 66 42 S 92 60, 52 64"
        case .wave: return "M26 11 L88 13 C 102 14, 102 27, 88 28 L 32 31 C 16 32, 16 46, 32 47 L 86 49 C 100 50, 98 63, 84 64"
        case .tsunami: return "M24 10 L92 12 C104 13 104 22 92 23 L30 25 C18 26 18 35 30 36 L90 38 C102 39 102 48 90 49 L32 51 C20 52 22 63 36 64"
        }
    }
    private var hurdles: [(CGFloat, CGFloat)] {
        switch tier {
        case .splash: return [(46, 22), (66, 42), (74, 56)]
        case .wave: return [(58, 12), (58, 30), (58, 48)]
        case .tsunami: return [(60, 11), (60, 24), (60, 37)]
        default: return []
        }
    }
    var body: some View {
        Canvas { ctx, size in
            var c = ctx
            c.clip(to: Path(CGRect(origin: .zero, size: size)))
            c.sliceTransform(size)
            c.fill(Path(CGRect(x: 0, y: 0, width: 120, height: 78)), with: .linearGradient(Gradient(colors: [hexColor(0xE6F2DD), hexColor(0xD3E8C7)]), startPoint: .zero, endPoint: CGPoint(x: 0, y: 78)))
            let path = SVG.path(d)
            c.stroke(path, with: .color(hexColor(0xE5A88E)), style: StrokeStyle(lineWidth: 7, lineCap: .round, lineJoin: .round))
            c.stroke(path, with: .color(.white.opacity(0.9)), style: StrokeStyle(lineWidth: 1, lineCap: .round, lineJoin: .round, dash: [3, 3]))
            for (x, y) in hurdles {
                c.fill(Path(roundedRect: CGRect(x: x - 5, y: y - 1.2, width: 10, height: 2.4), cornerRadius: 1), with: .color(hexColor(0x6B5749)))
            }
            // start dot at the first point, flag at the last
            let first = SVG.path(String(d.prefix(while: { $0 != "L" && $0 != "C" }))).currentPoint ?? .zero
            let last = path.currentPoint ?? .zero
            let dot = Path(ellipseIn: CGRect(x: first.x - 5, y: first.y - 5, width: 10, height: 10))
            c.fill(dot, with: .color(hexColor(0x9FD9B0))); c.stroke(dot, with: .color(.white), lineWidth: 1.2)
            var f = c; f.translateBy(x: last.x - 5, y: last.y + 2)
            let ink = hexColor(0x4D331F)
            f.line(CGPoint(x: 1, y: 0), CGPoint(x: 1, y: 10), ink, 1.4)
            f.fill(SVG.path("M1.5 .5h3v2.2h-3zM7.5 .5h3v2.2h-3zM4.5 2.7h3v2.2h-3z"), with: .color(ink))
            f.stroke(SVG.path("M1.5 .5H10.5V4.9H1.5Z"), with: .color(ink), lineWidth: 0.8)
        }
        .accessibilityHidden(true)
    }
}
