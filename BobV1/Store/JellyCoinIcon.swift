//
//  JellyCoinIcon.swift
//  The money icon (JellyCoins, the currency of Wobble Isle; code name DropsWallet): a soft, round gold coin with a thick darker rim, a glossy
//  highlight and a stamped "JC" monogram. Legible from ~14 pt up; below ~22 pt the bevel and the dotted ring are left out and only the JC stays.
//

import SwiftUI

struct JellyCoinIcon: View {
    var size: CGFloat = 18

    var body: some View {
        let s = size
        let small = s < 22
        let rim = s * (small ? 0.085 : 0.1)
        ZStack {
            Circle().fill(Color(hex: 0x6B3F08).opacity(0.28)).offset(y: s * 0.05).blur(radius: s * 0.03)
            // rim: lighter on top, darker below (a bevel)
            Circle().fill(LinearGradient(colors: [Color(hex: 0xFFE9A0), Color(hex: 0xE0A31C), Color(hex: 0xA8680C)], startPoint: .top, endPoint: .bottom))
            if !small { Circle().strokeBorder(Color.white.opacity(0.55), lineWidth: max(0.8, s * 0.018)).padding(s * 0.012) }
            // face: soft radial gold
            Circle().fill(RadialGradient(colors: [Color(hex: 0xFFEE9C), Color(hex: 0xF9CA3E), Color(hex: 0xE6A71F)], center: UnitPoint(x: 0.34, y: 0.28), startRadius: 0, endRadius: s * 0.62))
                .padding(rim)
            if !small {
                Circle().strokeBorder(Color(hex: 0xB9770F).opacity(0.5), style: StrokeStyle(lineWidth: max(1, s * 0.022), lineCap: .round, dash: [s * 0.02, s * 0.055]))
                    .padding(rim + s * 0.06)
            }
            // stamped JC: a light edge below, the darker gold letters on top
            Text("JC").font(.system(size: s * (small ? 0.47 : 0.42), weight: .black, design: .rounded)).tracking(-s * 0.035)
                .foregroundStyle(Color(hex: 0xFFF3B8).opacity(0.95)).offset(y: max(0.6, s * 0.03))
            Text("JC").font(.system(size: s * (small ? 0.47 : 0.42), weight: .black, design: .rounded)).tracking(-s * 0.035)
                .foregroundStyle(LinearGradient(colors: [Color(hex: 0xB8710B), Color(hex: 0x9A5A06)], startPoint: .top, endPoint: .bottom))
            // gloss
            Ellipse().fill(LinearGradient(colors: [Color.white.opacity(0.85), Color.white.opacity(0)], startPoint: .top, endPoint: .bottom))
                .frame(width: s * 0.3, height: s * 0.16).rotationEffect(.degrees(-35)).offset(x: -s * 0.2, y: -s * 0.27)
        }
        .frame(width: s, height: s)
        .accessibilityHidden(true)
    }
}

/// A coin and a number (a price or a payout), the common pairing.
struct CoinAmount: View {
    let amount: Int
    var size: CGFloat = 16
    var font: Font = SK.font(15, .black)
    var color: Color = SK.ink
    var body: some View {
        HStack(spacing: size * 0.25) { JellyCoinIcon(size: size); Text("\(amount)").font(font).foregroundStyle(color).monospacedDigit() }
    }
}
