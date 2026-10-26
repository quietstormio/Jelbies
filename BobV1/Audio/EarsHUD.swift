//
//  EarsHUD.swift
//  The ear button (top-left, next to Sound) and the Ears row of the sound panel.
//    button  off: an outlined ear. on: a filled ear; while something is heard it glows with the mic level and a small badge shows WHAT
//            (clap, music note, dog ...). Paused (background / the voice mic / an interruption): a small orange dot. Denied: ear with a warning;
//            a tap opens Settings. Otherwise a tap flips the switch (the first ON asks for the mic).
//    row     the switch plus the plain privacy text.
//

import SwiftUI

struct EarsButton: View {
    let ears: Ears
    private let ink = Color(red: 0.42, green: 0.34, blue: 0.30)
    private let cream = DT.card
    private let glow = Color(red: 0.43, green: 0.70, blue: 0.82)

    var body: some View {
        let st = ears.state
        let on = st.isOn
        let hearing = st == .listening ? ears.hearing : nil
        let lit = hearing != nil
        let lvl = CGFloat(st == .listening ? ears.level : 0)
        var paused = false
        if case .paused = st { paused = true }
        let symbol: String = {
            switch st {
            case .denied: return "ear.trianglebadge.exclamationmark"
            case .unavailable: return "ear.trianglebadge.exclamationmark"
            case .off: return "ear"
            default: return "ear.fill"
            }
        }()
        return Button {
            AudioHub.shared.uiTap()
            if st == .denied { ears.openSettings() } else { ears.setOn(!on) }
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(lit ? Color.white : (st == .denied ? Color(red: 0.80, green: 0.36, blue: 0.30) : ink))
                .frame(width: 44, height: 44)
                .background(Circle().fill(lit ? glow : cream).opacity(0.92))
                .overlay(Circle().strokeBorder(Color.black.opacity(0.06), lineWidth: 0.5))
                .background {
                    if on, st == .listening {
                        // live halo: with the level, brighter while a kind is heard
                        Circle().fill(glow.opacity((lit ? 0.30 : 0.10) + 0.25 * lvl))
                            .scaleEffect(1.0 + 0.22 * lvl + (lit ? 0.12 : 0))
                            .animation(.easeOut(duration: 0.1), value: ears.level)
                            .animation(.easeOut(duration: 0.15), value: lit)
                    }
                }
                .overlay(alignment: .bottomTrailing) {
                    if let k = hearing {
                        Image(systemName: k.symbol)
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(ink)
                            .frame(width: 17, height: 17)
                            .background(Circle().fill(cream))
                            .overlay(Circle().strokeBorder(glow, lineWidth: 1.2))
                            .offset(x: 5, y: 4)
                            .transition(.scale.combined(with: .opacity))
                            .accessibilityIdentifier("ears-hearing-\(k.rawValue)")
                    }
                }
                .overlay(alignment: .topTrailing) {
                    if paused {
                        Circle().fill(Color(red: 0.96, green: 0.58, blue: 0.20)).frame(width: 9, height: 9)
                            .overlay(Circle().strokeBorder(cream, lineWidth: 1.5))
                            .offset(x: 1, y: -1)
                            .accessibilityIdentifier("ears-paused-dot")
                    }
                }
                .animation(.spring(duration: 0.3), value: hearing)
                .frame(width: 44, height: 44).contentShape(Circle())          // 44 pt hit target
        }
        .buttonStyle(.plain)
        .accessibilityShowsLargeContentViewer { Label(label(st, hearing), systemImage: symbol) }
        .accessibilityLabel(label(st, hearing))
        .accessibilityIdentifier("ears-button")
    }

    private func label(_ st: Ears.State, _ hearing: EarKind?) -> String {
        switch st {
        case .off: return "Ears off"
        case .denied: return "Ears: microphone not allowed, opens Settings"
        case .unavailable: return "Ears unavailable"
        case .starting: return "Ears starting"
        case .paused: return "Ears paused"
        case .listening: return hearing.map { "Ears on, hearing \($0.title.lowercased())" } ?? "Ears on"
        }
    }
}

/// The Ears row in the sound panel: the switch and the privacy text.
struct EarsSettingsRow: View {
    let ears: Ears
    /// A phone on its side: smaller text, no extra spacing.
    var tight = false
    private let ink = Color(red: 0.42, green: 0.34, blue: 0.30)
    private let tint = Color(red: 0.43, green: 0.70, blue: 0.82)

    static let privacyText = "Your Jelbies listen for claps, whistles, laughter and music while the app is open, and react. Sound is understood right on your phone. Nothing is recorded or sent anywhere."
    static let deniedText = "The microphone is turned off for this app. Allow it in Settings to use Ears."

    var body: some View {
        let on = Binding<Bool>(get: { ears.state.isOn }, set: { ears.setOn($0) })
        VStack(alignment: .leading, spacing: tight ? 2 : 4) {
            Toggle(isOn: on) {
                Label("Ears", systemImage: "ear.fill").jFont(15, .semibold).foregroundStyle(ink)
            }
            .tint(tint)
            .controlSize(tight ? .small : .regular)
            .disabled(ears.state == .denied)
            .accessibilityIdentifier("sound-ears-toggle")
            Text(ears.state == .denied ? Self.deniedText : Self.privacyText)
                .jFont(tight ? 11 : 12, .regular)
                .foregroundStyle(ink.opacity(0.75))
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("sound-ears-privacy")
            if ears.state == .denied {
                Button("Open Settings") { ears.openSettings() }
                    .jFont(13, .semibold)
                    .foregroundStyle(tint)
                    .buttonStyle(.plain)
            }
        }
    }
}
