//
//  SoundSettingsView.swift
//  The sound panel: Music (with the room ambience) and Sound Effects, each with an on/off switch and a volume, and the Ears switch with its
//  privacy text (Audio/EarsHUD.swift). Opened from the speaker button next to the studio gear. Persisted by AudioHub / Ears (UserDefaults).
//

import SwiftUI

struct SoundSettingsPanel: View {
    @Bindable var hub: AudioHub
    var ears: Ears = .shared
    var close: () -> Void
    @Environment(\.verticalSizeClass) private var vsc          // .compact = a phone on its side (~400 pt tall): a tighter layout
    private var tight: Bool { vsc == .compact }

    private let ink = Color(red: 0.42, green: 0.34, blue: 0.30)

    var body: some View {
        VStack(alignment: .leading, spacing: tight ? 6 : 12) {
            HStack {
                Text("Sound").font(.system(size: 17, weight: .bold, design: .rounded)).foregroundStyle(ink)
                Spacer()
                Button(action: close) {
                    Image(systemName: "xmark").font(.system(size: 13, weight: .bold)).foregroundStyle(ink).padding(6)
                }
                .buttonStyle(.plain).accessibilityLabel("Close sound settings")
            }
            row("Music", symbol: "music.note", on: $hub.settings.musicOn, volume: $hub.settings.musicVolume, id: "music")
            row("Sound effects", symbol: "speaker.wave.2.fill", on: $hub.settings.sfxOn, volume: $hub.settings.sfxVolume, id: "sfx")
            Divider().overlay(ink.opacity(0.2))
            EarsSettingsRow(ears: ears, tight: tight)
        }
        .padding(tight ? 12 : 16)
        .frame(width: tight ? 300 : 270)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Color(red: 0.97, green: 0.94, blue: 0.88)).shadow(color: .black.opacity(0.2), radius: 10, y: 4))
        .accessibilityIdentifier("sound-panel")
    }

    private func row(_ title: String, symbol: String, on: Binding<Bool>, volume: Binding<Float>, id: String) -> some View {
        VStack(alignment: .leading, spacing: tight ? 0 : 4) {
            Toggle(isOn: on) {
                Label(title, systemImage: symbol).font(.system(size: 15, weight: .semibold, design: .rounded)).foregroundStyle(ink)
            }
            .tint(Color(red: 0.43, green: 0.70, blue: 0.82))
            .controlSize(tight ? .small : .regular)
            .accessibilityIdentifier("sound-\(id)-toggle")
            Slider(value: Binding(get: { Double(volume.wrappedValue) }, set: { volume.wrappedValue = Float($0) }), in: 0...1)
                .tint(Color(red: 0.43, green: 0.70, blue: 0.82))
                .disabled(!on.wrappedValue)
                .opacity(on.wrappedValue ? 1 : 0.4)
                .accessibilityIdentifier("sound-\(id)-volume")
        }
    }
}
