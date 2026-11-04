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
    private var theme = ThemeStore.shared

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
        let hint = np.state == .musicOff && !hub.settings.musicOn
        let showNote = np.note != nil && !(tight && (np.state == .playing || np.state == .quiet))
        return HStack(spacing: 8) {
            Image(systemName: symbol).font(.system(size: 13)).foregroundStyle(ink.opacity(0.7)).frame(width: 18)
            VStack(alignment: .leading, spacing: 0) {
                Text(np.line).font(.system(size: 13, weight: .bold, design: .rounded)).foregroundStyle(ink).lineLimit(1).minimumScaleFactor(0.8)
                if showNote, let n = np.note {
                    Text(hint ? "Tap to turn Music on" : n).font(.system(size: 11, weight: hint ? .semibold : .regular, design: .rounded)).foregroundStyle(hint ? tint : ink.opacity(0.6)).lineLimit(np.canSkip || tight ? 1 : 2).minimumScaleFactor(0.8)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 4)
            Button { hub.skipTrack() } label: {
                Label("Skip", systemImage: "forward.fill")
                    .font(.system(size: 13, weight: .bold, design: .rounded)).foregroundStyle(.white)
                    .padding(.horizontal, tight ? 8 : 10).padding(.vertical, tight ? 3 : 5)
                    .background(Capsule().fill(np.canSkip ? tint : SoundSwitchStyle.offTrack.opacity(0.55)))
            }
            .buttonStyle(.plain)
            .disabled(!np.canSkip)
            .accessibilityIdentifier("sound-skip")
            .accessibilityLabel("Skip song")
            .accessibilityHint(np.canSkip ? "" : (np.note ?? ""))
        }
        .padding(tight ? 6 : 8)
        .background(RoundedRectangle(cornerRadius: 12).fill(hint ? tint.opacity(0.14) : ink.opacity(0.06)))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(hint ? tint.opacity(0.6) : .clear, lineWidth: 1.5))
        .contentShape(RoundedRectangle(cornerRadius: 12))
        .onTapGesture { if hint { hub.settings.musicOn = true } }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("sound-now-playing")
        .animation(.easeInOut(duration: 0.2), value: np)
    }

    private func row(_ title: String, symbol: String, on: Binding<Bool>, volume: Binding<Float>, id: String) -> some View {
        VStack(alignment: .leading, spacing: tight ? 0 : 4) {
            Toggle(isOn: on) {
                Label(title, systemImage: symbol).font(.system(size: 15, weight: .semibold, design: .rounded)).foregroundStyle(ink)
            }
            .toggleStyle(SoundSwitchStyle(tint: theme.controlAccent, compact: tight))
            .accessibilityIdentifier("sound-\(id)-toggle")
            // The slider is always live: dragging it above 0 while the switch is off turns the switch on (volume 0 leaves it alone).
            SoundVolumeSlider(value: Binding(get: { Double(volume.wrappedValue) },
                                             set: { v in
                                                 volume.wrappedValue = Float(v)
                                                 if v > 0.001 && !on.wrappedValue { on.wrappedValue = true }
                                             }),
                              tint: on.wrappedValue ? theme.controlAccent : SoundSwitchStyle.offTrack,
                              label: "\(title) volume", id: "sound-\(id)-volume")
        }
    }
}

/// A switch whose OFF state is a clearly visible blue-grey track (>= 3:1 on the white card) with a shadowed knob: off but tappable.
struct SoundSwitchStyle: ToggleStyle {
    static let offTrack = Color(.sRGB, red: 0x72 / 255, green: 0x86 / 255, blue: 0x9E / 255)     // ~3.6:1 on white
    var tint: Color
    var compact = false
    func makeBody(configuration: Configuration) -> some View {
        let w: CGFloat = compact ? 44 : 51, h: CGFloat = compact ? 27 : 31
        return Button { configuration.isOn.toggle() } label: {
            HStack {
                configuration.label
                Spacer(minLength: 8)
                ZStack(alignment: configuration.isOn ? .trailing : .leading) {
                    Capsule().fill(configuration.isOn ? tint : Self.offTrack).frame(width: w, height: h)
                    Circle().fill(.white).frame(width: h - 4, height: h - 4)
                        .shadow(color: .black.opacity(0.3), radius: 3, x: 0, y: 1)
                        .padding(2)
                }
                .animation(.easeInOut(duration: 0.15), value: configuration.isOn)
            }
            .frame(minHeight: 44).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityValue(configuration.isOn ? "On" : "Off")
    }
}

/// An opaque volume slider that never ghosts: full-strength track and a shadowed knob in any state.
struct SoundVolumeSlider: View {
    @Binding var value: Double
    var tint: Color
    var label: String
    var id: String
    private let knob: CGFloat = 28
    var body: some View {
        GeometryReader { geo in
            let usable = max(1, geo.size.width - knob)
            ZStack(alignment: .leading) {
                Capsule().fill(CloudTheme.ink.opacity(0.22)).frame(height: 8)
                Capsule().fill(tint).frame(width: knob / 2 + usable * value, height: 8)
                Circle().fill(.white).overlay(Circle().stroke(tint, lineWidth: 2))
                    .frame(width: knob, height: knob)
                    .shadow(color: .black.opacity(0.3), radius: 3, x: 0, y: 1)
                    .offset(x: usable * value)
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { g in
                value = min(1, max(0, (g.location.x - knob / 2) / usable))
            })
        }
        .frame(height: 36)
        .accessibilityElement()
        .accessibilityLabel(label)
        .accessibilityValue("\(Int((value * 100).rounded())) percent")
        .accessibilityAdjustableAction { d in
            switch d {
            case .increment: value = min(1, value + 0.1)
            case .decrement: value = max(0, value - 0.1)
            @unknown default: break
            }
        }
        .accessibilityIdentifier(id)
    }
}
