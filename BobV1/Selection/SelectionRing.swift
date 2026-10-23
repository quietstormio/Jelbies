//
//  SelectionRing.swift
//  The persistent highlight of a picked Jelbie: a soft pulsing ring on the floor around his front (the part toward the camera), drawn by the
//  selection overlay (SwiftUI Canvas, not Metal). The stage projects the ring each frame while a pick is settled.
//

import SwiftUI
import simd

struct SelectRing { let id: Int; let pts: [CGPoint]; let at: Double }

enum SelectTuning {
    static let ringRadius: Float = 0.95        // world units, floor plane (body R 0.8; clears Pip's spines / Moss's flower)
    static let ringY: Float = 0.02
    static let ringSegments = 28
    static let ringFrontArc: Float = 220       // degrees of the ring drawn, centred on +z (toward the camera); the back arc would lie over his body
    static let ringPulse: Double = 1.4         // s per soft pulse
    static let ringFresh: Double = 0.25        // s; an older ring is not drawn (the stage stopped publishing: focus, bath, trip, arrange)
}

extension BlobSelect {
    /// Builds the front arc about +z at `ringY` around `floor` (x, z), projects it, and stores it.
    func publishRing(id: Int, floor: SIMD2<Float>, scale: Float = 1, viewProj: simd_float4x4, size: CGSize) {
        let n = SelectTuning.ringSegments
        let half = SelectTuning.ringFrontArc * .pi / 180 / 2
        var world = [SIMD3<Float>]()
        for i in 0..<n {
            let a = -half + 2 * half * Float(i) / Float(n - 1)          // 0 = straight toward the camera (+z)
            let r = SelectTuning.ringRadius * scale
            world.append(SIMD3(floor.x + r * sinf(a), SelectTuning.ringY, floor.y + r * cosf(a)))
        }
        ring = SelectRing(id: id, pts: Silhouette.project(world, viewProj: viewProj, size: size), at: CACurrentMediaTime())
    }
    /// The ring was published recently enough to draw.
    var ringIsFresh: Bool { ring.map { CACurrentMediaTime() - $0.at < SelectTuning.ringFresh } ?? false }
}

extension SelectionPainter {
    static func paintRing(_ ctx: inout GraphicsContext, select: BlobSelect, time: Double) {
        guard let h = select.highlighted, select.ringIsFresh, let r = select.ring, r.id == h, r.pts.count > 2 else { return }
        let pulse = 0.85 + 0.15 * sin(time * 2 * .pi / SelectTuning.ringPulse)
        ctx.opacity = pulse
        defer { ctx.opacity = 1 }
        var p = Path()
        p.move(to: r.pts[0])
        for q in r.pts.dropFirst() { p.addLine(to: q) }
        let style = { (w: CGFloat) in StrokeStyle(lineWidth: w, lineCap: .round, lineJoin: .round) }
        ctx.stroke(p, with: .color(pink.opacity(0.12)), style: style(14))
        ctx.stroke(p, with: .color(pink.opacity(0.22)), style: style(8))
        ctx.stroke(p, with: .color(pink), style: style(3.2))
        ctx.stroke(p, with: .color(.white.opacity(0.85)), style: style(1.2))
    }
}
