//
//  CoachCard.swift
//  The one card. Every tutorial step, tip and the Show's "Pick a move" is this view with a different set of parts present:
//      [symbol disc + title] / text / rows / primary button / footer (dots left, Skip right)
//  Same fill, radius, padding, fonts and spacing everywhere (CoachTokens.swift). When the card is taller than the room it was given, the top part (title, text, rows) scrolls and the button and
//  footer stay put: nothing is ever cropped, at any Dynamic Type size.
//

import SwiftUI

struct CoachRow: Equatable, Identifiable {
    var id: String { text }
    let symbol: String          // an SF Symbol, or "coin" for the JellyCoin icon
    let color: UInt32
    let text: String
}

struct CoachCard: View {
    var symbol: String? = nil
    var title: String? = nil
    var subtitle: String? = nil
    var text: String? = nil
    var rows: [CoachRow] = []
    var columns = 1
    var button: String? = nil
    var buttonID = "coach-button"
    var buttonHint: String? = nil
    var onButton: () -> Void = {}
    var dots: (current: Int, count: Int)? = nil
    var onSkip: (() -> Void)? = nil
    /// Pointer toward the ring: `up` = the tip points up (the card is below its ring); x = the pointer's centre inside the card.
    var pointer: (up: Bool, x: CGFloat)? = nil
    var width: CGFloat
    /// The room the card was given; the top part scrolls when the card would be taller.
    var maxHeight: CGFloat? = nil
    var identifier = "coach-card"
    var textIdentifier: String? = nil
    var centered = false
    @AccessibilityFocusState private var textFocus: Bool

    init(symbol: String? = nil, title: String? = nil, subtitle: String? = nil, text: String? = nil, rows: [CoachRow] = [], columns: Int = 1, button: String? = nil, buttonID: String = "coach-button", buttonHint: String? = nil,
         onButton: @escaping () -> Void = {}, dots: (current: Int, count: Int)? = nil, onSkip: (() -> Void)? = nil, pointer: (up: Bool, x: CGFloat)? = nil, width: CGFloat, maxHeight: CGFloat? = nil, identifier: String = "coach-card", centered: Bool = false) {
        self.symbol = symbol; self.title = title; self.subtitle = subtitle; self.text = text; self.rows = rows; self.columns = columns; self.button = button; self.buttonID = buttonID; self.buttonHint = buttonHint
        self.onButton = onButton; self.dots = dots; self.onSkip = onSkip; self.pointer = pointer; self.width = width; self.maxHeight = maxHeight; self.identifier = identifier; self.centered = centered
    }

    private var hasFooter: Bool { dots != nil || onSkip != nil }
    private var hasBottom: Bool { button != nil || hasFooter }

    var body: some View {
        let inner = max(width - 2 * Coach.inset, 60)
        let verticalRoom = maxHeight.map { $0 - 2 * Coach.inset }
        VStack(alignment: centered ? .center : .leading, spacing: Coach.spacing) {
            if let verticalRoom {
                ViewThatFits(in: .vertical) {
                    top(inner)
                    ScrollView(.vertical, showsIndicators: true) { top(inner) }
                        .frame(maxHeight: max(verticalRoom - bottomEstimate, 80))
                }
            } else {
                top(inner)
            }
            bottom(inner)
        }
        .padding(Coach.inset)
        .frame(width: width, alignment: centered ? .center : .leading)
        .background(RoundedRectangle(cornerRadius: Coach.cardRadius, style: .continuous).fill(Coach.fill).shadow(color: Coach.shadow, radius: 10, y: 4))
        .overlay(alignment: pointer.map { $0.up ? .topLeading : .bottomLeading } ?? .top) {
            if let pointer {
                CoachPointer(up: pointer.up).fill(Coach.fill).frame(width: 22, height: 12)
                    .offset(x: min(max(pointer.x - 11, 22), width - 44), y: pointer.up ? -11 : 11)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(identifier)
    }

    /// A safe guess for the pinned part's height, used only to size the scroll area.
    private var bottomEstimate: CGFloat { (button != nil ? Coach.minTap + Coach.spacing : 0) + (hasFooter ? Coach.minTap + Coach.spacing : 0) }

    @ViewBuilder private func top(_ inner: CGFloat) -> some View {
        VStack(alignment: centered ? .center : .leading, spacing: Coach.spacing) {
            if title != nil || symbol != nil {
                HStack(spacing: 12) {
                    if let symbol {
                        Image(systemName: symbol).font(.system(size: 20, weight: .heavy)).foregroundStyle(Coach.ink)
                            .frame(width: 40, height: 40).background(Circle().fill(SK.honey)).accessibilityHidden(true)
                    }
                    if let title {
                        Text(title).font(Coach.title()).foregroundStyle(Coach.ink).fixedSize(horizontal: false, vertical: true)
                            .accessibilityAddTraits(.isHeader).accessibilityFocused($textFocus).accessibilityIdentifier("coach-title")
                    }
                }
                .frame(minHeight: Coach.minTap, alignment: .leading)
            }
            if let subtitle {
                Text(subtitle).font(SK.font(17, .bold)).foregroundStyle(Coach.muted).fixedSize(horizontal: false, vertical: true)
            }
            if let text {
                Text(text).font(title == nil && symbol == nil ? Coach.line() : Coach.body())
                    .foregroundStyle(title == nil && symbol == nil ? Coach.ink : Coach.muted)
                    .multilineTextAlignment(centered ? .center : .leading)
                    .lineSpacing(2).fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("coach-text")
            }
            if !rows.isEmpty { rowsView(inner) }
        }
        .frame(maxWidth: .infinity, alignment: centered ? .center : .leading)
    }

    @ViewBuilder private func rowsView(_ inner: CGFloat) -> some View {
        let cols = max(1, min(columns, rows.count))
        let per = Int((Double(rows.count) / Double(cols)).rounded(.up))
        HStack(alignment: .top, spacing: 18) {
            ForEach(0..<cols, id: \.self) { c in
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(Array(rows.enumerated()).filter { $0.offset / per == c }.map(\.element)) { r in
                        HStack(spacing: 12) {
                            if r.symbol == "coin" { JellyCoinIcon(size: 36).accessibilityHidden(true) }
                            else {
                                Image(systemName: r.symbol).font(.system(size: 16, weight: .bold)).foregroundStyle(.white)
                                    .frame(width: 36, height: 36).background(Circle().fill(Color(hex: r.color))).accessibilityHidden(true)
                            }
                            Text(r.text).font(SK.font(16, .heavy)).foregroundStyle(Coach.ink).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    @ViewBuilder private func bottom(_ inner: CGFloat) -> some View {
        if let button {
            HStack {
                Spacer(minLength: 0)
                CoachButton(title: button, hint: buttonHint, id: buttonID, action: onButton)
                    .background(GeometryReader { g in Color.clear.preference(key: CoachButtonFrameKey.self, value: g.frame(in: .global)) })
                Spacer(minLength: 0)
            }
        }
        if hasFooter {
            HStack(spacing: 10) {
                if let dots { CoachDots(current: dots.current, count: dots.count) }
                Spacer(minLength: 8)
                if let onSkip { CoachSkipChip(action: onSkip) }
            }
            .frame(minHeight: Coach.minTap)
        }
    }
}

/// Where the card's primary button is (window points): the tip window lets a tap through everywhere else on a landscape map.
struct CoachButtonFrameKey: PreferenceKey {
    static let defaultValue: CGRect = .zero
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) { value = nextValue() }
}
