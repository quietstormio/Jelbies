//
//  Silhouette.swift
//  The screen silhouette of a Blob, as a closed polyline, from his projected render vertices (or any world points).
//  Used by the multi-Blob select highlight: hit-testing a double tap and the outline that draws from the top centre down both sides.
//
//  Method: bin the projected points by angle around their screen centroid, keep the farthest point per bin, fill and lightly smooth the bins.
//  That is the true outer contour of a star-shaped body (egg + arms + feet); the dip between his feet is bridged, which reads fine as a halo.
//

import CoreGraphics
import simd

enum Silhouette {
    static let bins = 288

    /// The outline (closed, counter-clockwise on screen from the top is NOT assumed: use `halves`) of `pts` (screen points).
    static func outline(of pts: [CGPoint], bins n: Int = Silhouette.bins) -> [CGPoint] {
        guard pts.count >= 8 else { return [] }
        var cx = 0.0, cy = 0.0
        for p in pts { cx += Double(p.x); cy += Double(p.y) }
        cx /= Double(pts.count); cy /= Double(pts.count)
        var rad = [Double](repeating: 0, count: n)
        for p in pts {
            let dx = Double(p.x) - cx, dy = Double(p.y) - cy
            let r = (dx * dx + dy * dy).squareRoot()
            if r < 1e-6 { continue }
            var a = atan2(dx, -dy)                     // 0 = straight up (screen), + = clockwise on screen
            if a < 0 { a += 2 * .pi }
            let b = min(n - 1, Int(a / (2 * .pi) * Double(n)))
            if r > rad[b] { rad[b] = r }
        }
        // fill empty bins from the neighbours, then a 3-tap smooth that never shrinks below a bin's own radius by more than a hair
        for _ in 0..<4 {
            for i in 0..<n where rad[i] == 0 {
                let a = rad[(i + n - 1) % n], b = rad[(i + 1) % n]
                if a > 0 && b > 0 { rad[i] = (a + b) / 2 } else if a > 0 || b > 0 { rad[i] = max(a, b) }
            }
        }
        var sm = rad
        for i in 0..<n { sm[i] = max(rad[i], 0.25 * rad[(i + n - 1) % n] + 0.5 * rad[i] + 0.25 * rad[(i + 1) % n]) }     // never inside the true contour
        return (0..<n).map { i in
            let a = (Double(i) + 0.5) / Double(n) * 2 * .pi
            return CGPoint(x: cx + sin(a) * sm[i], y: cy - cos(a) * sm[i])
        }
    }

    /// The outline moved outward by `d` points along its normals (an even pad around the true contour).
    static func padded(_ o: [CGPoint], by d: CGFloat) -> [CGPoint] {
        let n = o.count
        guard n >= 4, d != 0 else { return o }
        var cx: CGFloat = 0, cy: CGFloat = 0
        for p in o { cx += p.x; cy += p.y }
        cx /= CGFloat(n); cy /= CGFloat(n)
        var out = (0..<n).map { i -> CGPoint in
            let a = o[(i + n - 1) % n], b = o[(i + 1) % n], p = o[i]
            var nx = b.y - a.y, ny = a.x - b.x                      // perpendicular to the tangent
            let l = hypot(nx, ny)
            if l < 1e-6 { return p }
            nx /= l; ny /= l
            if nx * (p.x - cx) + ny * (p.y - cy) < 0 { nx = -nx; ny = -ny }
            return CGPoint(x: p.x + nx * d, y: p.y + ny * d)
        }
        for _ in 0..<2 {                                            // iron out the kinks the offset makes in the notch between his feet
            let q = out
            for i in 0..<n { let a = q[(i + n - 1) % n], b = q[(i + 1) % n]; out[i] = CGPoint(x: 0.25 * a.x + 0.5 * q[i].x + 0.25 * b.x, y: 0.25 * a.y + 0.5 * q[i].y + 0.25 * b.y) }
        }
        return out
    }

    /// Project world points to screen points (points, y down) with a view-projection.
    static func project(_ world: [SIMD3<Float>], viewProj: simd_float4x4, size: CGSize) -> [CGPoint] {
        world.compactMap { w in
            let q = viewProj * SIMD4<Float>(w, 1)
            guard q.w > 1e-4 else { return nil }
            return CGPoint(x: CGFloat((q.x / q.w * 0.5 + 0.5)) * size.width, y: CGFloat((1 - (q.y / q.w * 0.5 + 0.5))) * size.height)
        }
    }

    /// The two halves of the outline from its top centre down to the bottom centre: `left` runs down the left side, `right` down the right side.
    /// Both have the same length; their last points meet at the bottom.
    static func halves(_ o: [CGPoint]) -> (left: [CGPoint], right: [CGPoint]) {
        let n = o.count
        guard n >= 4, n % 2 == 0 else { return ([], []) }
        let h = n / 2
        // bin i covers angle (i + 0.5) / n * 2pi from the top, clockwise: 0..h-1 is the right side (top to bottom), h..n-1 the left side (bottom to top)
        let top = CGPoint(x: (o[0].x + o[n - 1].x) / 2, y: (o[0].y + o[n - 1].y) / 2)
        let bottom = CGPoint(x: (o[h - 1].x + o[h].x) / 2, y: (o[h - 1].y + o[h].y) / 2)
        var right = [top], left = [top]
        for i in 0..<h { right.append(o[i]) }
        for i in 0..<h { left.append(o[n - 1 - i]) }
        right.append(bottom); left.append(bottom)
        return (left, right)
    }

    /// The first `fraction` (0...1) of a polyline's length, as points (the last one interpolated).
    static func prefix(_ pts: [CGPoint], fraction f: Double) -> [CGPoint] {
        guard pts.count >= 2 else { return pts }
        let f = min(max(f, 0), 1)
        if f >= 1 { return pts }
        var len = [0.0]
        for i in 1..<pts.count { len.append(len[i - 1] + Double(hypot(pts[i].x - pts[i - 1].x, pts[i].y - pts[i - 1].y))) }
        let goal = (len.last ?? 0) * f
        var out = [pts[0]]
        for i in 1..<pts.count {
            if len[i] <= goal { out.append(pts[i]); continue }
            let seg = len[i] - len[i - 1]
            let t = seg > 0 ? (goal - len[i - 1]) / seg : 0
            out.append(CGPoint(x: pts[i - 1].x + (pts[i].x - pts[i - 1].x) * CGFloat(t), y: pts[i - 1].y + (pts[i].y - pts[i - 1].y) * CGFloat(t)))
            break
        }
        return out
    }

    /// Point-in-polygon (even-odd).
    static func contains(_ poly: [CGPoint], _ p: CGPoint) -> Bool {
        guard poly.count >= 3 else { return false }
        var inside = false
        var j = poly.count - 1
        for i in 0..<poly.count {
            let a = poly[i], b = poly[j]
            if (a.y > p.y) != (b.y > p.y), p.x < (b.x - a.x) * (p.y - a.y) / (b.y - a.y) + a.x { inside.toggle() }
            j = i
        }
        return inside
    }

    /// World points of a Blob standing at floor (x, z): the surface of revolution of the true body profile (for the preview Blobs).
    static func profileWorldPoints(at floor: SIMD2<Float>, scale: Float = 1, rings: Int = 36, around: Int = 32) -> [SIMD3<Float>] {
        var out: [SIMD3<Float>] = []
        let H = BobShape.H
        for i in 0...rings {
            let y = H * Float(i) / Float(rings)
            let r = BobShape.radius(atHeight: y) * scale
            for k in 0..<around {
                let a = Float(k) / Float(around) * 2 * .pi
                out.append(SIMD3(floor.x + sinf(a) * r, y * scale, floor.y + cosf(a) * r))
            }
        }
        return out
    }
}
