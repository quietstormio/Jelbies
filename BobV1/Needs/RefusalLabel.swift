//
//  RefusalLabel.swift
//  The small "Not hungry" / "Not thirsty" label above his head while he shakes his head at a tray he does not want (GameCare.notice).
//

import SwiftUI

struct RefusalLabel: View {
    let care: GameCare

    var body: some View {
        GeometryReader { geo in
            if let text = care.notice,
               let h = ThoughtBubbleView.project(care.noticeHeadWorld + SIMD3(0, 0.1, 0), size: geo.size, focus: care.focus.blend) {
                Text(text)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(FocusStyle.brown)
                    .padding(.horizontal, 14).padding(.vertical, 7)
                    .background(Capsule().fill(FocusStyle.cream).shadow(color: FocusStyle.shadow.opacity(0.25), radius: 5, y: 2))
                    .position(x: h.x, y: h.y - 46)
                    .transition(.scale(scale: 0.6).combined(with: .opacity))
                    .accessibilityIdentifier("refusal-label")
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: care.notice)
    }
}
