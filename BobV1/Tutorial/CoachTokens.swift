//
//  CoachTokens.swift
//  The ONE set of numbers every tutorial card, tip and hint is drawn with (spec: the tutorial3 SPEC.md). Nothing else in the app may hold a card radius, padding, font or colour for a coach card.
//  Apple basis: concentric corners (inner radius = outer radius - padding), continuous corners, 44 pt tap targets, a solid fill (no Liquid Glass) over the game view.
//

import SwiftUI

enum Coach {
    // MARK: shape
    /// The card's corner radius (continuous).
    static let cardRadius: CGFloat = 24
    /// The card's padding on every side.
    static let inset: CGFloat = 16
    /// Concentric rule: an element inside a container with `outer` radius, `inset` points in from its edge, has radius outer - inset (never below 0).
    static func innerRadius(outer: CGFloat = cardRadius, inset: CGFloat = Coach.inset) -> CGFloat { max(outer - inset, 0) }
    /// Space between the parts inside a card.
    static let spacing: CGFloat = 12
    static let minTap: CGFloat = 44
    /// The icon disc in a header and in a row.
    static let disc: CGFloat = 40

    // MARK: colour (solid: a coach card is content-layer UI over the game, never glass)
    static let fill = SK.cream
    static let ink = SK.ink
    static let muted = SK.muted
    static let accent = SK.pinkStrong
    static let shadow = Color(hex: 0x5A3A2A).opacity(0.3)
    static let dim = Color(red: 0.16, green: 0.10, blue: 0.08).opacity(0.58)

    // MARK: type (all follow Dynamic Type through SK.font)
    static func title() -> Font { SK.font(22, .black) }
    static func body() -> Font { SK.font(15, .bold) }
    static func caption() -> Font { SK.font(14, .bold) }
    static func button() -> Font { SK.font(17, .heavy) }
    static func chip() -> Font { SK.font(15, .heavy) }

    // MARK: spotlight
    /// Space between a control and its ring (the ring is concentric with the control: its radius is the control's plus this).
    static let ringGap: CGFloat = 6
    static let ringWidth: CGFloat = 3
    /// Distance from the ring to the card (the 12 pt pointer stands in it).
    static let cardGap: CGFloat = 20

    // MARK: width
    static func width(_ size: CGSize) -> CGFloat {
        let landscape = size.width > size.height * 1.2
        return landscape ? min(size.width * 0.42, 380) : min(size.width - 2 * inset, 340)
    }
    static let wideWidth: CGFloat = 640
}

/// A control's outline: what the ring has to be concentric with.
enum CoachShape: Equatable {
    case capsule          // radius = half the shorter side (circles are capsules)
    case rounded(CGFloat)
    func radius(for r: CGRect) -> CGFloat {
        switch self {
        case .capsule: return min(r.width, r.height) / 2
        case .rounded(let v): return min(v, min(r.width, r.height) / 2)
        }
    }
}

/// A spotlighted control: its frame in window points and its shape. The ring and the touch hole are the control grown by `Coach.ringGap` (radius grows with it, so ring and control stay concentric).
struct CoachSpot: Equatable {
    var rect: CGRect
    var shape: CoachShape = .capsule
    var controlRadius: CGFloat { shape.radius(for: rect) }
    var hole: CGRect { rect.insetBy(dx: -Coach.ringGap, dy: -Coach.ringGap) }
    var holeRadius: CGFloat { controlRadius + Coach.ringGap }
    var holePath: Path { Path(roundedRect: hole, cornerRadius: holeRadius, style: .continuous) }
    func contains(_ p: CGPoint) -> Bool { holePath.contains(p) }
}

/// The pointer: tip up or down.
struct CoachPointer: SwiftUI.Shape {
    var up: Bool
    func path(in r: CGRect) -> Path {
        var p = Path()
        if up { p.move(to: CGPoint(x: r.minX, y: r.maxY)); p.addLine(to: CGPoint(x: r.midX, y: r.minY)); p.addLine(to: CGPoint(x: r.maxX, y: r.maxY)) }
        else { p.move(to: CGPoint(x: r.minX, y: r.minY)); p.addLine(to: CGPoint(x: r.midX, y: r.maxY)); p.addLine(to: CGPoint(x: r.maxX, y: r.minY)) }
        p.closeSubpath()
        return p
    }
}

/// The primary button: ONE view for the tour's "Show me how", every tip's "Got it" and the forfeit sheet's button.
struct CoachButton: View {
    let title: String
    var label: String? = nil
    var hint: String? = nil
    let id: String
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(title).font(Coach.button()).foregroundStyle(.white).lineLimit(1).minimumScaleFactor(0.7)
                .padding(.horizontal, 18).frame(minHeight: Coach.minTap)
                .background(Capsule().fill(Coach.accent))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label ?? title).accessibilityHint(hint ?? "").accessibilityIdentifier(id)
    }
}

/// Kept for the callers that already use the old name (the forfeit sheet); it IS the one primary button.
typealias TourCapsuleButton = CoachButton

/// Skip: a small capsule on every tutorial card. Visible height 32, hit area 44 x 44.
struct CoachSkipChip: View {
    var id = "tutorial-skip"
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Text("Skip").font(Coach.chip())
                Image(systemName: "forward.fill").font(.system(size: 10, weight: .bold)).accessibilityHidden(true)
            }
            .foregroundStyle(Coach.ink).padding(.horizontal, 10).frame(minHeight: 32)
            .background(Capsule().fill(Color.white.opacity(0.95)))
            .overlay(Capsule().strokeBorder(Coach.muted.opacity(0.45), lineWidth: 1.2))
            .frame(minWidth: Coach.minTap, minHeight: Coach.minTap)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Skip").accessibilityHint("Skips the tutorial").accessibilityIdentifier(id)
    }
}

/// Progress dots: one per chapter, the current one filled.
struct CoachDots: View {
    let current: Int          // 1-based
    let count: Int
    var body: some View {
        HStack(spacing: 6) {
            ForEach(1...max(count, 1), id: \.self) { i in
                let on = i == current
                Circle().fill(on ? Coach.accent : Coach.fill).frame(width: 9, height: 9)
                    .overlay(Circle().strokeBorder(on ? Coach.accent : Coach.muted.opacity(0.7), lineWidth: 1.5))
            }
        }
        .accessibilityElement(children: .ignore).accessibilityLabel("Step \(current) of \(count)")
    }
}

/// The dim with the hole and the ring. The ring is concentric with the control (`CoachSpot`); the pulse grows it from the same centre.
struct CoachSpotlight: View {
    let spot: CoachSpot?
    var pulse = true
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !pulse)) { tl in
            let k = pulse ? 0.5 + 0.5 * sin(tl.date.timeIntervalSinceReferenceDate * 3.2) : 0.5
            Canvas { ctx, sz in
                guard let spot else { ctx.fill(Path(CGRect(origin: .zero, size: sz)), with: .color(Coach.dim)); return }
                var p = Path(CGRect(origin: .zero, size: sz))
                p.addPath(spot.holePath)
                ctx.fill(p, with: .color(Coach.dim), style: FillStyle(eoFill: true))
                let grow = 3 * k
                let ring = spot.hole.insetBy(dx: -grow, dy: -grow)
                ctx.stroke(Path(roundedRect: ring, cornerRadius: spot.holeRadius + grow, style: .continuous), with: .color(.white.opacity(0.55 + 0.4 * k)), lineWidth: Coach.ringWidth)
            }
        }
        .allowsHitTesting(false).accessibilityHidden(true)
    }
}
