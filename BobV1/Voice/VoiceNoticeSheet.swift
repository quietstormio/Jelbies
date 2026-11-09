//
//  VoiceNoticeSheet.swift
//  The card about the microphone: the first-press explainer (shown before the system permission alert) and the reasons the mic cannot be
//  used (denied, needs the internet once, not available), with an Open Settings button where Settings can fix it. Scrolls, so it fits landscape.
//

import SwiftUI
import UIKit

enum VoiceNoticeText {
    static func title(_ n: VoiceNotice) -> String {
        switch n {
        case .explainer: return "Talk to your Jelbies"
        case .denied: return "The microphone is off"
        case .needsInternet: return "Voice needs the internet once to get ready"
        case .unavailable: return "Voice isn't ready"
        }
    }
    static func body(_ n: VoiceNotice) -> String {
        switch n {
        case .explainer:
            return "Jelbies can listen for their names and tricks when you hold the mic. Nothing leaves your phone. Your phone will ask to use the microphone next. Say yes so they can hear you."
        case .denied:
            return "Jelbies can't hear you because the microphone is turned off for this app. You can turn it on in Settings, or type a command in the trick book."
        case .needsInternet:
            return "Connect to Wi-Fi or mobile data, then tap the mic again. After that, voice works without the internet."
        case .unavailable:
            return "Voice can't start on this phone right now. Tap the mic to try again, or type a command in the trick book."
        }
    }
    static func openSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
    }
}

struct VoiceNoticeSheet: View {
    let notice: VoiceNotice
    var primary: () -> Void
    var openBook: () -> Void
    var close: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                Image(systemName: notice == .denied ? "mic.slash.fill" : (notice == .needsInternet ? "wifi" : "mic.fill"))
                    .font(.system(size: 34, weight: .semibold)).foregroundStyle(SK.pinkStrong)
                    .accessibilityHidden(true)
                Text(VoiceNoticeText.title(notice))
                    .jFont(21, .bold).foregroundStyle(FocusStyle.brown).multilineTextAlignment(.center)
                    .accessibilityAddTraits(.isHeader)
                Text(VoiceNoticeText.body(notice))
                    .jFont(16, .medium).foregroundStyle(FocusStyle.brown).multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                if notice == .explainer {
                    button("Turn on the mic", id: "voice-notice-continue", filled: true) { primary() }
                    button("Not now", id: "voice-notice-close", filled: false) { close() }
                } else {
                    if notice == .denied { button("Open Settings", id: "voice-notice-settings", filled: true) { VoiceNoticeText.openSettings() } }
                    button("Open tricks", id: "voice-notice-book", filled: notice != .denied) { openBook() }
                    button("Close", id: "voice-notice-close", filled: false) { close() }
                }
            }
            .padding(20).frame(maxWidth: 480).frame(maxWidth: .infinity)
        }
        .scrollBounceBehavior(.basedOnSize)
        .background(FocusStyle.cream.ignoresSafeArea())
        .accessibilityIdentifier("voice-notice")
    }

    private func button(_ title: String, id: String, filled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).jFont(17, .bold)
                .foregroundStyle(filled ? Color.white : FocusStyle.brown)
                .frame(maxWidth: .infinity, minHeight: 48)
                .background(Capsule().fill(filled ? SK.pinkStrong : Color.white.opacity(0.75)))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(id)
    }
}
