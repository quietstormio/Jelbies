//
//  BubbleOverlay.swift
//  Draws the bubble wand's bubbles over the game view WITHOUT any blur / material / Liquid Glass (those cost 12x GPU in the room before): a pool of
//  <= 40 plain CALayers, each showing one pre-rendered soap-bubble image (clear centre, rainbow-sheen rim, two highlights). Per frame only
//  position / size / opacity / rotation are set (the sheen turns slowly with the rotation; the wobble is a small squash). A CADisplayLink at 30...60 Hz
//  runs while the overlay is on screen and returns at once when there is nothing to draw. Also the wand button (tap-and-hold), the hint and the Done chip.
//

import SwiftUI
import UIKit
import simd

// MARK: images (drawn once)

enum BubbleArt {
    static let bubble: CGImage = render(size: 160) { c, s in
        let r = s / 2, mid = CGPoint(x: r, y: r)
        let cs = CGColorSpaceCreateDeviceRGB()
        // a whisper of white over the whole disc
        c.saveGState()
        c.addEllipse(in: CGRect(x: 2, y: 2, width: s - 4, height: s - 4)); c.clip()
        if let g = CGGradient(colorsSpace: cs, colors: [UIColor(white: 1, alpha: 0.0).cgColor, UIColor(white: 1, alpha: 0.10).cgColor] as CFArray, locations: [0.5, 1]) {
            c.drawRadialGradient(g, startCenter: mid, startRadius: 0, endCenter: mid, endRadius: r, options: [])
        }
        c.restoreGState()
        // the rainbow rim: wedges of hue, each clipped, each a radial gradient that is clear inside and glows at the edge
        let wedges = 48
        for i in 0..<wedges {
            let a0 = CGFloat(i) / CGFloat(wedges) * 2 * .pi, a1 = CGFloat(i + 1) / CGFloat(wedges) * 2 * .pi + 0.02
            let hue = (CGFloat(i) * 2 / CGFloat(wedges)).truncatingRemainder(dividingBy: 1)
            let col = UIColor(hue: hue, saturation: 0.55, brightness: 1, alpha: 1)
            c.saveGState()
            c.move(to: mid); c.addArc(center: mid, radius: r, startAngle: a0, endAngle: a1, clockwise: false); c.closePath(); c.clip()
            if let g = CGGradient(colorsSpace: cs, colors: [col.withAlphaComponent(0).cgColor, col.withAlphaComponent(0).cgColor, col.withAlphaComponent(0.5).cgColor, col.withAlphaComponent(0).cgColor] as CFArray, locations: [0, 0.70, 0.93, 1]) {
                c.drawRadialGradient(g, startCenter: mid, startRadius: 0, endCenter: mid, endRadius: r, options: [])
            }
            c.restoreGState()
        }
        // a thin bright edge
        c.setStrokeColor(UIColor(white: 1, alpha: 0.32).cgColor); c.setLineWidth(1.6)
        c.strokeEllipse(in: CGRect(x: 3, y: 3, width: s - 6, height: s - 6))
        // highlights: a soft crescent top-left and a small glint bottom-right
        c.saveGState()
        c.translateBy(x: r - r * 0.42, y: r - r * 0.46); c.rotate(by: -0.7)
        c.setFillColor(UIColor(white: 1, alpha: 0.85).cgColor)
        c.fillEllipse(in: CGRect(x: -r * 0.2, y: -r * 0.075, width: r * 0.4, height: r * 0.15))
        c.restoreGState()
        c.setFillColor(UIColor(white: 1, alpha: 0.45).cgColor)
        c.fillEllipse(in: CGRect(x: r + r * 0.38, y: r + r * 0.40, width: r * 0.12, height: r * 0.12))
    }

    /// The pop: a faint ring and six tiny sparkle dots.
    static let pop: CGImage = render(size: 128) { c, s in
        let r = s / 2, mid = CGPoint(x: r, y: r)
        c.setStrokeColor(UIColor(white: 1, alpha: 0.55).cgColor); c.setLineWidth(2.2)
        c.strokeEllipse(in: CGRect(x: r * 0.42, y: r * 0.42, width: r * 1.16, height: r * 1.16))
        for k in 0..<8 {
            let a = CGFloat(k) / 8 * 2 * .pi + 0.2, d = r * (k % 2 == 0 ? 0.82 : 0.66), dot = r * (k % 2 == 0 ? 0.075 : 0.05)
            c.setFillColor(UIColor(hue: CGFloat(k) / 8, saturation: 0.25, brightness: 1, alpha: 0.95).cgColor)
            c.fillEllipse(in: CGRect(x: mid.x + cos(a) * d - dot, y: mid.y + sin(a) * d - dot, width: dot * 2, height: dot * 2))
        }
    }

    private static func render(size: CGFloat, _ draw: (CGContext, CGFloat) -> Void) -> CGImage {
        let f = UIGraphicsImageRendererFormat(); f.scale = 1; f.opaque = false
        let img = UIGraphicsImageRenderer(size: CGSize(width: size, height: size), format: f).image { draw($0.cgContext, size) }
        return img.cgImage!
    }
}

// MARK: the layer view

final class BubbleLayerView: UIView {
    private var bubbleLayers: [CALayer] = []
    private var fxLayers: [CALayer] = []
    private var link: CADisplayLink?
    private let wand = BubbleWand.shared

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        isAccessibilityElement = false
        for _ in 0..<BubbleField.cap {
            let l = CALayer(); l.contents = BubbleArt.bubble; l.isHidden = true; l.bounds = CGRect(x: 0, y: 0, width: 10, height: 10); layer.addSublayer(l); bubbleLayers.append(l)
        }
        for _ in 0..<16 {
            let l = CALayer(); l.contents = BubbleArt.pop; l.isHidden = true; layer.addSublayer(l); fxLayers.append(l)
        }
    }
    required init?(coder: NSCoder) { fatalError() }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        link?.invalidate(); link = nil
        guard window != nil else { return }
        let l = CADisplayLink(target: self, selector: #selector(step))
        l.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: 60, preferred: 60)
        l.add(to: .main, forMode: .common)
        link = l
    }

    @objc func step() {
        let size = bounds.size
        guard size.width > 1 else { return }
        if wand.viewSize != size { wand.viewSize = size }
        let bubbles = wand.field.bubbles, fx = wand.fx
        if bubbles.isEmpty && fx.isEmpty {
            if !bubbleLayers[0].isHidden || !fxLayers[0].isHidden { hideAll() }
            return
        }
        let t0 = CACurrentMediaTime()
        let cam = GameCamera.camera(aspect: Float(size.width / size.height))
        let vp = cam.viewProj
        let halfH = Float(size.height) * 0.5, tanHalf = tanf(GameCamera.fovY * 0.5)
        CATransaction.begin(); CATransaction.setDisableActions(true)
        for (i, l) in bubbleLayers.enumerated() {
            guard i < bubbles.count else { l.isHidden = true; continue }
            let b = bubbles[i]
            let c = vp * SIMD4<Float>(b.pos.x, b.pos.y, b.pos.z, 1)
            guard c.w > 0.1 else { l.isHidden = true; continue }
            let rpx = CGFloat(b.radius / (c.w * tanHalf) * halfH)
            let x = CGFloat(c.x / c.w * 0.5 + 0.5) * size.width, y = CGFloat(1 - (c.y / c.w * 0.5 + 0.5)) * size.height
            l.isHidden = false
            l.bounds = CGRect(x: 0, y: 0, width: rpx * 2, height: rpx * 2)
            l.position = CGPoint(x: x, y: y)
            let w = CGFloat(b.wobble) * 0.05
            let spin = CGFloat(b.age * 0.5 + b.phase)
            l.transform = CATransform3DScale(CATransform3DMakeRotation(spin, 0, 0, 1), 1 + w, 1 - w, 1)
            let fadeIn = min(1, b.age / 0.2), fadeOut = min(1, max(0, (b.life - b.age) / 0.35))
            l.opacity = Float(min(fadeIn, fadeOut)) * 0.95
        }
        for (i, l) in fxLayers.enumerated() {
            guard i < fx.count else { l.isHidden = true; continue }
            let f = fx[i]
            let c = vp * SIMD4<Float>(f.pos.x, f.pos.y, f.pos.z, 1)
            guard c.w > 0.1 else { l.isHidden = true; continue }
            let a = CGFloat(wand.fxAge(f))
            let rpx = CGFloat(f.size / (c.w * tanHalf) * halfH) * (1.2 + 1.6 * a)
            l.isHidden = false
            l.bounds = CGRect(x: 0, y: 0, width: rpx * 2, height: rpx * 2)
            l.position = CGPoint(x: CGFloat(c.x / c.w * 0.5 + 0.5) * size.width, y: CGFloat(1 - (c.y / c.w * 0.5 + 0.5)) * size.height)
            l.opacity = Float(1 - a) * 0.9
        }
        CATransaction.commit()
        BubbleWand.drawCostSum += CACurrentMediaTime() - t0; BubbleWand.drawCostN += 1
    }

    private func hideAll() {
        CATransaction.begin(); CATransaction.setDisableActions(true)
        for l in bubbleLayers { l.isHidden = true }
        for l in fxLayers { l.isHidden = true }
        CATransaction.commit()
    }
    deinit { link?.invalidate() }
}

struct BubbleLayerRepresentable: UIViewRepresentable {
    func makeUIView(context: Context) -> BubbleLayerView { BubbleLayerView(frame: .zero) }
    func updateUIView(_ v: BubbleLayerView, context: Context) {}
}

extension BubbleWand {
    /// Wall time spent drawing (perf line / tests).
    nonisolated(unsafe) static var drawCostSum: Double = 0
    nonisolated(unsafe) static var drawCostN = 0
}

// MARK: the wand and its controls

/// A bubble wand drawn as a stick with a ring (no image asset).
struct WandShape: SwiftUI.Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        let ring = CGRect(x: r.midX - r.width * 0.30, y: r.minY + r.height * 0.02, width: r.width * 0.60, height: r.width * 0.60)
        p.addEllipse(in: ring)
        p.addRoundedRect(in: CGRect(x: r.midX - r.width * 0.045, y: ring.maxY - 2, width: r.width * 0.09, height: r.height - ring.maxY - r.minY + 2), cornerSize: CGSize(width: 4, height: 4))
        return p
    }
}

struct BubbleWandOverlay: View {
    var wand: BubbleWand = .shared
    @State private var pressing = false

    var body: some View {
        ZStack {
            BubbleLayerRepresentable().ignoresSafeArea().allowsHitTesting(false)
            VStack {
                HStack {
                    Spacer()
                    Button { wand.stop() } label: {
                        Text("Done").font(.system(size: 16, weight: .heavy, design: .rounded)).foregroundStyle(.white)
                            .padding(.horizontal, 16).padding(.vertical, 8).background(Capsule().fill(Color(red: 0.36, green: 0.55, blue: 0.80)))
                    }
                    .accessibilityLabel("Put the bubble wand away")
                    Spacer()
                }
                .padding(.horizontal, 16).padding(.top, 8)
                Spacer()
                Text(wand.micUnavailable ? "Hold the wand to blow bubbles" : "Blow on the microphone, or hold the wand")
                    .font(.system(size: 14, weight: .bold, design: .rounded)).foregroundStyle(Color(red: 0.25, green: 0.33, blue: 0.5))
                    .padding(.horizontal, 14).padding(.vertical, 6).background(Capsule().fill(Color.white.opacity(0.92)))
                    .accessibilityHidden(true)
                wandButton.padding(.bottom, 14)
            }
        }
    }

    private var wandButton: some View {
        let on = pressing || wand.strength > 0.05
        return ZStack {
            Circle().fill(Color.white.opacity(on ? 1 : 0.92)).frame(width: 84, height: 84)
                .overlay(Circle().strokeBorder(Color(red: 0.55, green: 0.75, blue: 0.95), lineWidth: 3))
            WandShape().stroke(Color(red: 0.36, green: 0.55, blue: 0.80), style: StrokeStyle(lineWidth: 4, lineCap: .round)).frame(width: 40, height: 52)
        }
        .scaleEffect(on ? 1.08 : 1)
        .animation(.easeOut(duration: 0.12), value: on)
        .gesture(DragGesture(minimumDistance: 0)
            .onChanged { _ in if !pressing { pressing = true; wand.holding = true } }
            .onEnded { _ in pressing = false; wand.holding = false })
        .accessibilityElement()
        .accessibilityLabel("Bubble wand")
        .accessibilityHint("Double tap to blow a stream of bubbles. You can also blow on the microphone.")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { wand.burst(seconds: 2.5) }
    }
}
