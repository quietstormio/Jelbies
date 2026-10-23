//
//  SelectionOverlay.swift
//  The multi-Blob highlight, drawn over the stage: preview Blobs (DEBUG / SELECT_PREVIEW only), the dimming of the others, the outline that
//  draws from the top centre down both sides and meets at the bottom (with a spark), the soft pulsing glow, and the persistent floor ring of a settled pick.
//

import SwiftUI
import simd

struct SelectionOverlay: View {
    let select: BlobSelect

    var body: some View {
        ZStack {
            // Perf: with no highlight and no pick there is nothing to animate, so the full-screen Canvas must not redraw at display rate.
            // A settled pick only pulses its floor ring, which needs 30 Hz, not 120.
            TimelineView(.animation(minimumInterval: select.isSelecting ? nil : 1.0 / 30,
                                    paused: !select.isSelecting && select.highlighted == nil && !select.blobs.contains { $0.floor != nil })) { tl in      // (stand-in previews are DEBUG only)
                let frame = tl.date          // the Canvas must read the timeline's date, or SwiftUI reuses its last drawing and the draw never animates
                Canvas { ctx, size in _ = frame; SelectionPainter.paint(&ctx, size: size, select: select) }
            }
            .allowsHitTesting(false)
            .ignoresSafeArea()
        }
    }
}

@MainActor
enum SelectionPainter {
    static let pink = Color(red: 0.914, green: 0.541, blue: 0.643)
    /// Even gap (screen points) between the body's true contour and the stroke's centre line.
    static let pad: CGFloat = 5

    static func paint(_ ctx: inout GraphicsContext, size: CGSize, select: BlobSelect) {
        let t = select.clock
        if select.selectedID == nil { paintRing(&ctx, select: select, time: CACurrentMediaTime()) }
        // preview Blobs (stand-ins for a 2nd / 3rd Blob until the renderer draws several)
        for b in select.blobs where b.floor != nil {
            paintPreview(&ctx, b, select: select)
        }
        guard let id = select.selectedID else { return }
        // the others dim
        for b in select.blobs where b.id != id && b.floor == nil {
            if let o = select.outlines[b.id], o.count > 3 { ctx.fill(path(o), with: .color(Color(red: 1.0, green: 0.97, blue: 0.94).opacity(0.38))) }
        }
        guard !select.waiting, let o0 = hopped(select.outlines[id], select: select, id: id), o0.count >= 8 else { return }     // never over an empty / not-yet-real path
        let o = Silhouette.padded(o0, by: pad)
        ctx.opacity = Double(select.outlineAlpha)
        defer { ctx.opacity = 1 }
        let (l, r) = Silhouette.halves(o)
        let p = Double(select.drawProgress)
        let pl = Silhouette.prefix(l, fraction: p), pr = Silhouette.prefix(r, fraction: p)
        let glow = select.glowing ? 0.5 + 0.5 * sin(Double(select.glowTime) * 2 * .pi / 0.7 - .pi / 2) : 1.0     // soft pulse once drawn
        let style = { (w: CGFloat) in StrokeStyle(lineWidth: w, lineCap: .round, lineJoin: .round) }
        for (w, a) in [(26.0, 0.10), (16.0, 0.18), (9.0, 0.30)] {
            let k = select.glowing ? (0.55 + 0.45 * glow) : 1
            for half in [pl, pr] where half.count > 1 { ctx.stroke(path(half), with: .color(pink.opacity(a * k)), style: style(w)) }
        }
        for half in [pl, pr] where half.count > 1 { ctx.stroke(path(half), with: .color(pink), style: style(4.6)) }
        for half in [pl, pr] where half.count > 1 { ctx.stroke(path(half), with: .color(.white.opacity(0.85)), style: style(1.6)) }
        // spark at the two leading ends while drawing; a burst where they meet
        if !select.glowing {
            for half in [pl, pr] where half.count > 1 { if let e = half.last { spark(&ctx, at: e, r: 9, a: 0.95) } }     // never a spark without its line
        } else if t - BlobSelect.drawDuration < 0.18, let m = pl.last {
            let k = CGFloat((t - BlobSelect.drawDuration) / 0.18)
            spark(&ctx, at: m, r: 9 + 20 * k, a: Double(1 - k))
        }
    }

    static func path(_ pts: [CGPoint]) -> Path {
        var p = Path()
        guard let f = pts.first else { return p }
        p.move(to: f)
        for q in pts.dropFirst() { p.addLine(to: q) }
        if pts.count > 8 && hypot(pts[0].x - pts[pts.count - 1].x, pts[0].y - pts[pts.count - 1].y) < 40 { p.closeSubpath() }
        return p
    }

    static func spark(_ ctx: inout GraphicsContext, at c: CGPoint, r: CGFloat, a: Double) {
        var p = Path()
        p.move(to: CGPoint(x: c.x - r, y: c.y)); p.addLine(to: CGPoint(x: c.x + r, y: c.y))
        p.move(to: CGPoint(x: c.x, y: c.y - r)); p.addLine(to: CGPoint(x: c.x, y: c.y + r))
        let d = r * 0.6
        p.move(to: CGPoint(x: c.x - d, y: c.y - d)); p.addLine(to: CGPoint(x: c.x + d, y: c.y + d))
        p.move(to: CGPoint(x: c.x - d, y: c.y + d)); p.addLine(to: CGPoint(x: c.x + d, y: c.y - d))
        ctx.stroke(p, with: .color(.white.opacity(a)), style: StrokeStyle(lineWidth: 2, lineCap: .round))
        ctx.fill(Path(ellipseIn: CGRect(x: c.x - 3, y: c.y - 3, width: 6, height: 6)), with: .color(pink.opacity(a)))
    }

    /// The hop of the selected Blob after the draw (preview Blobs only; the real one hops in the sim): a quick up-and-down of the outline.
    static func hopped(_ o: [CGPoint]?, select: BlobSelect, id: Int) -> [CGPoint]? {
        guard let o else { return nil }
        guard select.blobs.first(where: { $0.id == id })?.floor != nil else { return o }
        let dy = hopOffset(select)
        return o.map { CGPoint(x: $0.x, y: $0.y - dy) }
    }
    static func hopOffset(_ select: BlobSelect) -> CGFloat {
        let u = (select.clock - BlobSelect.drawDuration) / 0.25
        return (u > 0 && u < 1) ? CGFloat(sinf(u * .pi)) * 38 : 0
    }

    static func paintPreview(_ ctx: inout GraphicsContext, _ b: SelectBlob, select: BlobSelect) {
        guard let o0 = select.outlines[b.id], o0.count > 3, let fl = b.floor else { return }
        let dy = select.selectedID == b.id ? hopOffset(select) : 0
        let o = o0.map { CGPoint(x: $0.x, y: $0.y - dy) }
        let dim = select.isDimmed(b.id)
        let c = b.tint
        let top = o.map(\.y).min() ?? 0, bot = o.map(\.y).max() ?? 0
        let body = Gradient(colors: [Color(red: Double(c.x), green: Double(c.y), blue: Double(c.z)),
                                     Color(red: Double(c.x) * 0.92, green: Double(c.y) * 0.9, blue: Double(c.z) * 0.92)])
        // soft floor shadow (stays on the floor while he hops)
        let sw = (o.map(\.x).max() ?? 0) - (o.map(\.x).min() ?? 0)
        let gy = bot + dy
        ctx.fill(Path(ellipseIn: CGRect(x: (o.map(\.x).min() ?? 0) + sw * 0.05, y: gy - sw * 0.08, width: sw * 0.9, height: sw * 0.16)), with: .color(Color(red: 0.4, green: 0.25, blue: 0.15).opacity(0.18)))
        let opacity = dim ? 0.55 : 1.0
        ctx.opacity = opacity
        ctx.fill(path(o), with: .linearGradient(body, startPoint: CGPoint(x: 0, y: top), endPoint: CGPoint(x: 0, y: bot)))
        // face: the two oval eyes and brows at the profile's eye height, placed with the same camera
        let H = BobShape.H, eyeH = 0.58 * H * b.scale
        let dx = 0.26 * 2 * BobShape.R * b.scale * 0.5
        let rEye = BobShape.radius(atHeight: 0.58 * H) * b.scale
        for sx in [-1.0, 1.0] {
            let w = SIMD3<Float>(fl.x + Float(sx) * dx, eyeH, fl.y + rEye * 0.93)
            if let p = Silhouette.project([w], viewProj: select.viewProj, size: select.viewSize).first {
                let ey = CGRect(x: p.x - 7, y: p.y - dy - 10, width: 14, height: 20)
                ctx.fill(Path(ellipseIn: ey), with: .color(Color(red: 0.33, green: 0.2, blue: 0.16)))
                var br = Path(); br.move(to: CGPoint(x: p.x - 10, y: p.y - dy - 19 + CGFloat(sx) * 1)); br.addLine(to: CGPoint(x: p.x + 10, y: p.y - dy - 20 - CGFloat(sx) * 1))
                ctx.stroke(br, with: .color(Color(red: 0.33, green: 0.2, blue: 0.16)), style: StrokeStyle(lineWidth: 3, lineCap: .round))
            }
        }
        ctx.opacity = 1
    }
}
