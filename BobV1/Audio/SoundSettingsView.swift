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
    var openExtras: (() -> Void)? = nil          // the "Siri and Lock Screen" row (opens AppleExtrasPanel)
    var close: () -> Void
    @Environment(\.verticalSizeClass) private var vsc          // .compact = a phone on its side (~400 pt tall): a tighter layout
    private var tight: Bool { vsc == .compact }

    private let ink = CloudTheme.ink

    var body: some View {
        VStack(alignment: .leading, spacing: tight ? 6 : 12) {
            HStack {
                Text("Sound").font(CloudTheme.font(20, .bold)).foregroundStyle(ink)
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
            if let openExtras {
                Divider().overlay(ink.opacity(0.2))
                Button(action: openExtras) {
                    HStack {
                        Label("Siri and Lock Screen", systemImage: "sparkles.rectangle.stack").font(.system(size: 15, weight: .semibold, design: .rounded)).foregroundStyle(ink)
                        Spacer()
                        Image(systemName: "chevron.right").font(.system(size: 12, weight: .bold)).foregroundStyle(ink.opacity(0.5))
                    }
                    .frame(minHeight: 44).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("extras-button")
            }
        }
        .padding(tight ? 12 : 16)
        .frame(width: tight ? 300 : 270)
        .cloudCard(radius: 24)
        .accessibilityIdentifier("sound-panel")
    }

    private var nowPlayingRow: some View {
        let np = nowPlaying ?? hub.nowPlaying
        let tint = CloudTheme.deepJelly
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
            .tint(CloudTheme.deepJelly)
            .controlSize(tight ? .small : .regular)
            .accessibilityIdentifier("sound-\(id)-toggle")
            Slider(value: Binding(get: { Double(volume.wrappedValue) }, set: { volume.wrappedValue = Float($0) }), in: 0...1)
                .tint(CloudTheme.deepJelly)
                .disabled(!on.wrappedValue)
                .opacity(on.wrappedValue ? 1 : 0.4)
                .accessibilityIdentifier("sound-\(id)-volume")
        }
    }
}
