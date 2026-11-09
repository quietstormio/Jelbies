//
//  PrivacyPage.swift
//  The in-app Privacy page (Settings > Privacy), in the Settings look. The same text is published from docs/PRIVACY.md (keep the two in step).
//  `InfoPage` is the shared page shell (header with Done, themed background, one card per section) that SupportPage uses too.
//

import SwiftUI

struct InfoSection: Identifiable {
    let heading: String
    let paragraphs: [String]
    var id: String { heading }
}

/// A themed, scrolling text page with a Done button.
struct InfoPage<Extra: View>: View {
    let title: String
    let sections: [InfoSection]
    let identifier: String
    let close: () -> Void
    let extra: Extra
    private var theme = ThemeStore.shared
    private let ink = CloudTheme.ink

    init(title: String, sections: [InfoSection], identifier: String, close: @escaping () -> Void, @ViewBuilder extra: () -> Extra) {
        self.title = title; self.sections = sections; self.identifier = identifier; self.close = close; self.extra = extra()
    }

    var body: some View {
        let pal = theme.palette
        ZStack {
            pal.bg.ignoresSafeArea()
            VStack(spacing: 0) {
                HStack {
                    Text(title).font(CloudTheme.font(26, .heavy)).foregroundStyle(ink)
                        .padding(.horizontal, 18).frame(minHeight: 44)
                        .background(Capsule().fill(Color.white).shadow(color: pal.lip, radius: 0, y: 3))
                        .accessibilityAddTraits(.isHeader)
                    Spacer()
                    Button { AudioHub.shared.uiTap(); close() } label: {
                        Text("Done").font(CloudTheme.font(18, .heavy)).foregroundStyle(pal.continueText)
                            .padding(.horizontal, 20).frame(minHeight: 44)
                            .background(Capsule().fill(Color.white).shadow(color: pal.lip, radius: 0, y: 4))
                    }
                    .accessibilityIdentifier("\(identifier)-done")
                }
                .padding(.horizontal, 20).padding(.vertical, 10)
                ScrollView {
                    VStack(spacing: 16) {
                        ForEach(sections) { s in
                            VStack(alignment: .leading, spacing: 8) {
                                Text(s.heading).font(CloudTheme.font(18, .bold)).foregroundStyle(ink).accessibilityAddTraits(.isHeader)
                                ForEach(s.paragraphs, id: \.self) { p in
                                    Text(p).font(CloudTheme.font(15, .medium)).foregroundStyle(ink.opacity(0.85)).fixedSize(horizontal: false, vertical: true)
                                }
                            }
                            .padding(16).frame(maxWidth: .infinity, alignment: .leading).cloudCard(radius: 26)
                        }
                        extra
                    }
                    .padding(16).frame(maxWidth: 640)
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(identifier)
        .accessibilityAction(.escape) { close() }
    }
}

extension InfoPage where Extra == EmptyView {
    init(title: String, sections: [InfoSection], identifier: String, close: @escaping () -> Void) {
        self.init(title: title, sections: sections, identifier: identifier, close: close) { EmptyView() }
    }
}

enum PrivacyText {
    static let effective = "2026-11-09"
    static let contact = "dione@mgsllc.io"
    static let sections: [InfoSection] = [
        InfoSection(heading: "Who we are", paragraphs: [
            "Jelbies is made by MGS LLC. Effective \(effective).",
            "In short: Jelbies works offline and never sends anything anywhere."]),
        InfoSection(heading: "No data collected", paragraphs: [
            "The game never connects to our servers or anyone else's. There are no accounts, no ads, no tracking and no analytics. We do not collect any data about you or your child."]),
        InfoSection(heading: "Microphone and voice", paragraphs: [
            "The microphone is only used while you hold the mic button, or while the optional always-on Ears setting is on.",
            "What you say is turned into words on the phone by Apple's on-device speech recognition. It is never recorded to a file or sent anywhere.",
            "Apple may download its speech model once over the internet. That download is done by iOS, not by Jelbies, and no game data goes with it."]),
        InfoSection(heading: "Photos", paragraphs: [
            "Photos taken in Photo mode stay inside the app. They only leave it if you choose to save them to your Photos or share them."]),
        InfoSection(heading: "Names and saves", paragraphs: [
            "The names you type and everything your Jelbies have earned stay on this phone."]),
        InfoSection(heading: "Widgets and Live Activities", paragraphs: [
            "Widgets and Live Activities show your Jelbies' names, moods and pictures on your own Home Screen and Lock Screen. That information stays on your phone."]),
        InfoSection(heading: "Park visitors", paragraphs: [
            "On phones that support Apple Intelligence, the text for Park visitors (their names and what they say) may be written on the phone by Apple Intelligence. It is asked to keep everything gentle and kid-friendly, and the result is checked and filtered before it is shown. Phones without it use words written in advance."]),
        InfoSection(heading: "Delete everything", paragraphs: [
            "Open Settings and tap Reset save to erase your Jelbies, JellyCoins, items and photos from the app. Or delete the app from your phone. Photos you saved to your Photos library stay there until you delete them."]),
        InfoSection(heading: "Contact", paragraphs: [
            "Questions? Email \(contact)."]),
    ]
}

struct PrivacyPage: View {
    let close: () -> Void
    var body: some View {
        InfoPage(title: "Privacy", sections: PrivacyText.sections, identifier: "privacy-page", close: close)
    }
}
