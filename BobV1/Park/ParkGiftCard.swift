//
//  ParkGiftCard.swift
//  The gift reveal: a "Gift from <friend>!" card that springs in over the park with the item's art on a glowing backdrop (slow rays, a confetti burst),
//  the item name and "Added to your bag". About 3.6 s, a tap closes it. Reduce Motion: a plain fade-in card, no rays, no confetti, no spring.
//

import SwiftUI

struct ParkGiftCard: View {
    let friend: String
    let item: StoreItem
    let close: () -> Void
    @State private var shown = false
    @State private var born = Date()
    private var calm: Bool { A11ySettings.shared.reduceMotion }

    var body: some View {
        ZStack {
            Color.black.opacity(0.12).ignoresSafeArea().onTapGesture { close() }
            if !calm { Confetti(born: born).allowsHitTesting(false).ignoresSafeArea() }
            VStack(spacing: 10) {
                Text("Gift from \(friend)!").font(SK.font(20, .black)).foregroundStyle(SK.ink)
                ZStack {
                    if !calm { Rays(born: born) }
                    Circle().fill(RadialGradient(colors: [SK.honey.opacity(0.9), SK.honey.opacity(0)], center: .center, startRadius: 4, endRadius: 80)).frame(width: 170, height: 170)
                    ItemArt(item: item, size: 104).shadow(color: SK.shadow.opacity(0.25), radius: 6, y: 3)
                }
                .frame(width: 170, height: 170)
                Text(item.name).font(SK.font(18, .heavy)).foregroundStyle(SK.ink)
                HStack(spacing: 6) { Image(systemName: "gift.fill"); Text("Added to your bag") }
                    .font(SK.font(14, .bold)).foregroundStyle(SK.ink.opacity(0.7))
            }
            .padding(.horizontal, 26).padding(.vertical, 18)
            .background(RoundedRectangle(cornerRadius: 28, style: .continuous).fill(SK.cream).shadow(color: SK.shadow.opacity(0.3), radius: 12, y: 5))
            .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).strokeBorder(Color.white.opacity(0.6), lineWidth: 1.5))
            .scaleEffect(calm ? 1 : (shown ? 1 : 0.4)).opacity(shown ? 1 : 0)
            .onTapGesture { close() }
        }
        .onAppear {
            born = Date()
            if calm { withAnimation(.easeIn(duration: 0.25)) { shown = true } }
            else { withAnimation(.spring(response: 0.45, dampingFraction: 0.55)) { shown = true } }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Gift from \(friend): \(item.name). Added to your bag.")
        .accessibilityAddTraits(.isButton).accessibilityHint("Closes the gift")
        .accessibilityIdentifier("park-gift")
    }

    /// Slow spinning rays behind the item.
    private struct Rays: View {
        let born: Date
        var body: some View {
            TimelineView(.animation) { t in
                let a = t.date.timeIntervalSince(born) * 25
                ZStack {
                    ForEach(0..<10, id: \.self) { k in
                        Capsule().fill(SK.honey.opacity(0.55)).frame(width: 14, height: 70).offset(y: -62).rotationEffect(.degrees(Double(k) * 36 + a))
                    }
                }
            }
        }
    }

    /// A short burst of confetti from the middle (fixed pseudo-random pieces; no state).
    private struct Confetti: View {
        let born: Date
        var body: some View {
            TimelineView(.animation) { t in
                Canvas { ctx, size in
                    let age = t.date.timeIntervalSince(born)
                    guard age < 2.2 else { return }
                    let palette: [Color] = [SK.honey, SK.pink, SK.sky, SK.mint]
                    for k in 0..<36 {
                        let f = Double(k)
                        let ang = f * 2.399 + sin(f * 7.1) * 0.4
                        let speed = 150 + 130 * abs(sin(f * 3.7))
                        let x = size.width / 2 + cos(ang) * speed * age
                        let y = size.height / 2 - 60 + sin(ang) * speed * age * 0.8 + 260 * age * age
                        let r = CGRect(x: x - 4, y: y - 3, width: 8, height: 6)
                        ctx.opacity = max(0, 1 - age / 2.2)
                        ctx.fill(Path(roundedRect: r, cornerRadius: 2), with: .color(palette[k % palette.count]))
                    }
                }
            }
        }
    }
}
