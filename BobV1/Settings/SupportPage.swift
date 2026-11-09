//
//  SupportPage.swift
//  The in-app Help & Support page (Settings > Help & Support). The same text is published from docs/SUPPORT.md (keep the two in step).
//  The address is selectable text, and a "Write to us" button opens a mailto link behind the grown-up hold gate (UI/ParentGate.swift).
//

import SwiftUI

enum SupportText {
    static let email = "dione@mgsllc.io"
    static let sections: [InfoSection] = [
        InfoSection(heading: "How to play", paragraphs: [
            "Feed: tap the food button and pick a snack.",
            "Drink: tap the drink button to fill a thirsty Jelbie.",
            "Clean: tap Clean to scrub, rinse and make them sparkle.",
            "Play: tap Play and pick a toy.",
            "Call by name: hold the mic button and say your Jelbie's name.",
            "Jelly Race, Jelly Show and Jelly Volleyball: go out to compete and earn JellyCoins."]),
        InfoSection(heading: "The mic is not working", paragraphs: [
            "A grown-up can turn the microphone on in your phone's Settings, under Jelbies. Turn on Microphone and Speech Recognition.",
            "The first time you use your voice, the phone needs to download a small speech pack. Stay online once, then it works offline."]),
        InfoSection(heading: "How do I start over?", paragraphs: [
            "Open Settings in the game and tap Reset save, then hold the red button. This erases your Jelbies, JellyCoins and items for good."]),
    ]
}

struct SupportPage: View {
    let close: () -> Void
    private let ink = CloudTheme.ink
    @Environment(\.openURL) private var openURL
    var body: some View {
        InfoPage(title: "Help & Support", sections: SupportText.sections, identifier: "support-page", close: close) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Email us").font(CloudTheme.font(18, .bold)).foregroundStyle(ink).accessibilityAddTraits(.isHeader)
                Text(SupportText.email).font(CloudTheme.font(16, .bold)).foregroundStyle(ink).textSelection(.enabled)
                    .accessibilityIdentifier("support-email")
                GatedButton {
                    if let url = URL(string: "mailto:\(SupportText.email)") { openURL(url) }
                } label: {
                    Text("Write to us").font(CloudTheme.font(16, .heavy)).foregroundStyle(ink)
                        .padding(.horizontal, 20).frame(minHeight: 44)
                        .background(Capsule().fill(Color.white))
                }
                .accessibilityIdentifier("support-write")
                .accessibilityHint("Asks a grown-up first, then opens Mail")
            }
            .padding(16).frame(maxWidth: .infinity, alignment: .leading).cloudCard(radius: 26)
        }
    }
}
