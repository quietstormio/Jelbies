//
//  SoundSettingsView.swift
//  The sound panel: Music (with the room ambience) and Sound Effects, each with an on/off switch and a volume, and the Ears switch with its
//  privacy text (Audio/EarsHUD.swift). Opened from the speaker button next to the studio gear. Persisted by AudioHub / Ears (UserDefaults).
//

import SwiftUI

struct SoundSettingsPanel: View {
    @Bindable var hub: AudioHub
    var ears: Ears = .shared
    var nowPlaying: NowPlaying? = nil          // override for captures / tests (the XCTest hub is muted)
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
            nowPlayingRow
            row("Sound effects", symbol: "speaker.wave.2.fill", on: $hub.settings.sfxOn, volume: $hub.settings.sfxVolume, id: "sfx")
            Divider().overlay(ink.opacity(0.2))
            EarsSettingsRow(ears: ears, tight: tight)
        }
        .padding(tight ? 12 : 16)
        .frame(width: tight ? 300 : 270)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Color(red: 0.97, green: 0.94, blue: 0.88)).shadow(color: .black.opacity(0.2), radius: 10, y: 4))
        .accessibilityIdentifier("sound-panel")
    }

    private var nowPlayingRow: some View {
        let np = nowPlaying ?? hub.nowPlaying
        let tint = Color(red: 0.43, green: 0.70, blue: 0.82)
        let symbol: String = {
            switch np.state {
            case .playing: return "waveform"
            case .quiet: return "moon.zzz"
            case .musicOff, .muted: return "speaker.slash"
            case .yourMusic: return "headphones"
            case .screen: return "music.note.house"
            }
        }()
        let showNote = np.note != nil && !(tight && (np.state == .playing || np.state == .quiet))
        return HStack(spacing: 8) {
            Image(systemName: symbol).font(.system(size: 13)).foregroundStyle(ink.opacity(0.7)).frame(width: 18)
            VStack(alignment: .leading, spacing: 0) {
                Text(np.line).font(.system(size: 13, weight: .semibold, design: .rounded)).foregroundStyle(ink).lineLimit(1).minimumScaleFactor(0.8)
                if showNote, let n = np.note {
                    Text(n).font(.system(size: 11, design: .rounded)).foregroundStyle(ink.opacity(0.6)).lineLimit(np.canSkip || tight ? 1 : 2).minimumScaleFactor(0.8)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 4)
            Button { hub.skipTrack() } label: {
                Label("Skip", systemImage: "forward.fill")
                    .font(.system(size: 13, weight: .bold, design: .rounded)).foregroundStyle(.white)
                    .padding(.horizontal, tight ? 8 : 10).padding(.vertical, tight ? 3 : 5)
                    .background(Capsule().fill(tint))
            }
            .buttonStyle(.plain)
            .disabled(!np.canSkip)
            .opacity(np.canSkip ? 1 : 0.4)
            .accessibilityIdentifier("sound-skip")
            .accessibilityLabel("Skip song")
            .accessibilityHint(np.canSkip ? "" : (np.note ?? ""))
        }
        .padding(tight ? 6 : 8)
        .background(RoundedRectangle(cornerRadius: 12).fill(ink.opacity(0.06)))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("sound-now-playing")
        .animation(.easeInOut(duration: 0.2), value: np)
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
