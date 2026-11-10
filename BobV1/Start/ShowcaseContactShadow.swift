//
//  ShowcaseContactShadow.swift
//  The Jelly Spring's soft contact shadow. The showcase draws the Jelbie cut out (no room, so no floor shadow) over the SwiftUI pedestal, and without one he
//  reads as floating above it. A blurred ellipse on the pedestal under him, projected with the stage's own camera (the game camera with the picker's orbit),
//  following his floor spot; it shrinks and fades while he is off the floor (hops) and comes back as he lands.
//

import SwiftUI
import simd

struct ShowcaseContactShadow: View {
    let model: MelonModel
    /// The lowest body centre seen (standing): his height off the floor is measured from it. A class so the Canvas can update it without a view update.
    private final class Rest { var y: Float = .infinity }
    @State private var rest = Rest()

    static let halfX: Float = 0.44, halfZ: Float = 0.36, opacity: Double = 0.2

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: model.paused)) { _ in
            Canvas { ctx, size in
                let care = model.care
                let head = care.bubbleHead(0)
                let c = SIMD3<Float>(head.x, head.y - BlobShape.H * 0.5, head.z)          // body centre (GameCare keeps the head point H/2 above it)
                rest.y = min(rest.y, c.y)
                let lift = min(max((c.y - rest.y) / 0.35, 0), 1)          // 0 standing ... 1 at a hop's height
                let fy = care.lastSim?.floorY ?? 0
                let focus = care.focus.blend
                let ground = SIMD3<Float>(c.x, fy, c.z + 0.04)
                guard let p0 = ThoughtBubbleView.project(ground, size: size, focus: focus),
                      let px = ThoughtBubbleView.project(ground + SIMD3(Self.halfX, 0, 0), size: size, focus: focus),
                      let pz = ThoughtBubbleView.project(ground + SIMD3(0, 0, Self.halfZ), size: size, focus: focus) else { return }
                let s = CGFloat(1 - 0.3 * lift)
                let rx = hypot(px.x - p0.x, px.y - p0.y) * s, ry = max(hypot(pz.x - p0.x, pz.y - p0.y), rx * 0.18) * s
                guard rx > 2, rx < size.width else { return }
                let rect = CGRect(x: p0.x - rx, y: p0.y - ry, width: 2 * rx, height: 2 * ry)
                ctx.addFilter(.blur(radius: rx * 0.12))
                let a = Self.opacity * Double(1 - 0.75 * lift)
                ctx.fill(Path(ellipseIn: rect), with: .radialGradient(Gradient(colors: [Color.black.opacity(a), Color.black.opacity(a * 0.55), Color.black.opacity(0)]),
                                                                     center: p0, startRadius: 0, endRadius: rx))
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
