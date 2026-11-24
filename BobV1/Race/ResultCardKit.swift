//
//  ResultCardKit.swift
//  The shared frame and rows of the Jelly Volleyball and Jelly Race results cards (owner 11-24: "cluttered, texts not spaced properly"). The rules:
//    - every text wraps at its own width (never a line limit, never a shrink) and asks for the height it needs, so nothing is squeezed or drawn over its neighbour;
//    - the rewards are a tidy vertical list of full-width rows (icon + one wrapping line each), the points a row of the same kind;
//    - the card hugs its content with even gaps and "Back home" has its own space below the content;
//    - when the content cannot fit the height it is given (a phone on its side, the largest text sizes) the content scrolls INSIDE the card and the button stays put;
//    - a phone on its side puts the content in two columns (the result left, the points and rewards right) so it stays short.
//

import SwiftUI

enum ResultCardMetrics {
    static let gold = Color(red: 0.98, green: 0.80, blue: 0.35)
    /// The tallest the card may be: the screen height the chrome measured, less the top bar band and the gaps. iPad draws the card at 1.45x (a transform, not layout), so its layout height is divided by that.
    static func maxHeight(screenH: CGFloat) -> CGFloat {
        guard screenH > 0 else { return .infinity }
        return PadLayout.isPad ? max(200, (screenH - 120) / 1.45) : max(160, screenH - 96)
    }
}

extension View {
    /// How the chromes place a results card: a readable width, 24 pt from the sides on a phone, drawn 1.45x on iPad.
    func resultCardSlot() -> some View {
        frame(maxWidth: PadLayout.isPad ? 440 : .infinity).scaleEffect(PadLayout.isPad ? 1.45 : 1).padding(.horizontal, PadLayout.isPad ? 0 : 24)
    }
    /// A result text: wraps, never cut off, centred.
    func resultText(_ probe: String) -> some View {
        multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true).resultProbe(probe)
    }
}

/// The card: `primary` on top (or left), `secondary` below (or right), then the button.
struct ResultCardFrame<Primary: View, Secondary: View>: View {
    let buttonColor: Color
    let homeID: String
    var maxHeight: CGFloat = .infinity
    var hasSecondary = true
    let home: () -> Void
    @ViewBuilder let primary: () -> Primary
    @ViewBuilder let secondary: () -> Secondary

    @Environment(\.verticalSizeClass) private var vsc
    @Environment(\.dynamicTypeSize) private var dts
    private var tight: Bool { vsc == .compact }
    private var gap: CGFloat { tight ? 8 : 12 }

    @ViewBuilder private var content: some View {
        if tight && hasSecondary && !dts.isAccessibilitySize {
            HStack(alignment: .center, spacing: 22) {
                VStack(spacing: gap) { primary() }.frame(maxWidth: .infinity)
                VStack(spacing: gap) { secondary() }.frame(maxWidth: .infinity)
            }
        } else {
            VStack(spacing: gap) { primary(); if hasSecondary { secondary() } }.frame(maxWidth: .infinity)
        }
    }

    private var button: some View {
        Button { UIImpactFeedbackGenerator(style: .soft).impactOccurred(); AudioHub.shared.uiTap(); home() } label: {
            Text("Back home").playFont(20, .bold).foregroundStyle(.white).resultText("home")
                .padding(.horizontal, 32).padding(.vertical, tight ? 9 : 12)
                .background(Capsule().fill(buttonColor).shadow(color: FocusStyle.shadow.opacity(0.25), radius: 6, y: 3))
        }.buttonStyle(.plain).accessibilityIdentifier(homeID)
    }

    private func card(scrolling: Bool) -> some View {
        VStack(spacing: tight ? 12 : 20) {
            if scrolling {
                ScrollView(.vertical, showsIndicators: false) { content }.scrollBounceBehavior(.basedOnSize)
            } else {
                content
            }
            button
        }
        .padding(.horizontal, tight ? 20 : 24).padding(.top, tight ? 16 : 22).padding(.bottom, tight ? 16 : 22)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 34, style: .continuous).fill(CareMenu.cream).shadow(color: FocusStyle.shadow.opacity(0.3), radius: 6, y: 3))
        .overlay(RoundedRectangle(cornerRadius: 34, style: .continuous).strokeBorder(Color.white.opacity(0.6), lineWidth: 1.5))
    }

    var body: some View {
        ViewThatFits(in: .vertical) {
            card(scrolling: false)
            // too tall: fill the height we are given, the content scrolls inside and "Back home" stays under it
            card(scrolling: true).frame(height: maxHeight.isFinite ? maxHeight : nil)
        }
        .frame(maxHeight: maxHeight)
    }
}

/// "+250 JellyCoins".
struct ResultCoinsLine: View {
    let coinText: String
    var body: some View {
        HStack(spacing: 8) {
            JellyCoinIcon(size: 24)
            Text("+\(coinText) JellyCoins").playFont(20, .bold).foregroundStyle(CareMenu.brown).resultText("coins")
        }
        .accessibilityElement(children: .combine)
    }
}

/// A soft full-width row: an icon and one wrapping line (or two). The reward and points rows of both cards.
struct ResultRow<Text1: View>: View {
    let symbol: String
    let tint: Color
    let fill: Color
    let id: String
    @ViewBuilder let text: () -> Text1
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: UIImage(systemName: symbol) != nil ? symbol : "star.fill").playFont(18, .black).foregroundStyle(tint)
                .frame(width: 26, alignment: .center).padding(.top, 1)
            text().frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 14).padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(fill))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(id)
    }
}

/// "Jelly Volleyball points +3 / Berry now has 2 to spend".
struct ResultPointsRow: View {
    let title: String
    let detail: String
    let id: String
    var body: some View {
        ResultRow(symbol: "star.fill", tint: ResultCardMetrics.gold, fill: Color.white.opacity(0.62), id: id) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).playFont(16, .bold).foregroundStyle(CareMenu.brown).multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true).resultProbe("points")
                Text(detail).playFont(14, .medium).foregroundStyle(CareMenu.brown.opacity(0.85)).multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true).resultProbe("pointsDetail")
            }
        }
    }
}

/// A new ribbon / new trophy row (the gold ones).
struct ResultRewardRow: View {
    let symbol: String
    let text: String
    let id: String
    let probe: String
    var body: some View {
        ResultRow(symbol: symbol, tint: CareMenu.brown, fill: ResultCardMetrics.gold, id: id) {
            Text(text).playFont(16, .heavy).foregroundStyle(CareMenu.brown).multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true).resultProbe(probe)
        }
        .transition(A11ySettings.shared.reduceMotion ? .opacity : .scale(scale: 0.6).combined(with: .opacity))
    }
}
