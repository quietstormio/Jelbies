//
//  HoldToConfirm.swift
//  The destructive-action confirm: a red button that fills while held for 2 seconds (Settings > Reset save, the main menu's Start over).
//

import SwiftUI

/// A red button that fills while it is held for 2 seconds. VoiceOver's double tap does it directly (its own confirm card came first).
struct HoldToConfirm: View {
    var title: String
    var id: String = "settings-reset-hold"
    var done: () -> Void
    @State private var progress: CGFloat = 0
    @State private var holding = false

    var body: some View {
        Text(title).font(CloudTheme.font(18, .heavy)).foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(
                GeometryReader { g in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color(hex: 0xB3261E))
                        Capsule().fill(Color.black.opacity(0.28)).frame(width: g.size.width * progress)
                    }
                }
            )
            .clipShape(Capsule())
            .contentShape(Capsule())
            .onLongPressGesture(minimumDuration: 2, maximumDistance: 40) {
                done()
            } onPressingChanged: { down in
                holding = down
                withAnimation(down ? .linear(duration: 2) : .easeOut(duration: 0.2)) { progress = down ? 1 : 0 }
            }
            .accessibilityElement().accessibilityLabel(title).accessibilityAddTraits(.isButton)
            .accessibilityAction { done() }
            .accessibilityIdentifier(id)
    }
}
