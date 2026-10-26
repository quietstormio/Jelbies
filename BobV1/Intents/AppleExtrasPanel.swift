//
//  AppleExtrasPanel.swift
//  The small settings card for the Apple extras (opened from the HUD like the sound panel): the two optional Live Activities (nap card,
//  Pep countdown) and a Siri & Shortcuts row (the system SiriTipView for "Check on the Jelbies" and the Shortcuts app link).
//

import SwiftUI
import AppIntents

struct AppleExtrasPanel: View {
    @Bindable var live: LiveActivities
    var close: () -> Void
    @State private var tipVisible = true

    private let ink = Color(red: 0.42, green: 0.34, blue: 0.30)
    private let tint = Color(red: 0.43, green: 0.70, blue: 0.82)

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Siri & Lock Screen").jFont(17, .bold).foregroundStyle(ink)
                Spacer()
                Button(action: close) {
                    Image(systemName: "xmark").font(.system(size: 13, weight: .bold)).foregroundStyle(ink).padding(6)
                }
                .buttonStyle(.plain).accessibilityLabel("Close Siri and Lock Screen settings")
            }

            Text("Live Activities").jFont(12, .bold).foregroundStyle(ink.opacity(0.6))
            Toggle(isOn: $live.napOn) {
                Label { Text("Nap card at bedtime") } icon: { Image(systemName: "moon.zzz.fill") }
                    .jFont(15, .semibold).foregroundStyle(ink)
            }
            .tint(tint).accessibilityIdentifier("extras-nap-toggle")
            Text("When the Jelbies sleep (after 9 pm, or “goodnight”), a quiet card on the Lock Screen says when they are up.")
                .jFont(12, .medium).foregroundStyle(ink.opacity(0.65))
            Toggle(isOn: $live.pepOn) {
                Label { Text("Pep refill countdown") } icon: { Image(systemName: "bolt.fill") }
                    .jFont(15, .semibold).foregroundStyle(ink)
            }
            .tint(tint).accessibilityIdentifier("extras-pep-toggle")
            Text("When training Pep runs out, a countdown to the midnight refill.")
                .jFont(12, .medium).foregroundStyle(ink.opacity(0.65))

            Divider().overlay(ink.opacity(0.15))

            Text("Siri & Shortcuts").jFont(12, .bold).foregroundStyle(ink.opacity(0.6))
            SiriTipView(intent: CheckOnJelbiesIntent(), isVisible: $tipVisible)
                .siriTipViewStyle(.automatic)
            Text("Feed, water, goodnight, race and train work too.")
                .jFont(12, .medium).foregroundStyle(ink.opacity(0.65))
            HStack { Spacer(); ShortcutsLink().shortcutsLinkStyle(.automatic).fixedSize() }
        }
        .padding(16)
        .frame(width: 300)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(DT.card).shadow(color: .black.opacity(0.2), radius: 10, y: 4))
        .accessibilityIdentifier("extras-panel")
    }
}
