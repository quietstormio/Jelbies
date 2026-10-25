//
//  NowPlaying.swift
//  What the sound panel's now-playing row shows and whether Skip works. Pure (no audio): AudioHub feeds it the situation.
//

import Foundation

nonisolated struct NowPlaying: Equatable, Sendable {
    enum State: Equatable, Sendable { case playing, quiet, musicOff, yourMusic, muted, screen }
    var state: State
    var line: String
    var note: String?
    var canSkip: Bool

    static let initial = NowPlaying(state: .quiet, line: "Music", note: nil, canSkip: false)

    static func modeLabel(_ m: MusicMode) -> String {
        switch m { case .day: return "Day"; case .evening: return "Evening"; case .night: return "Night"; case .nap: return "Nap time" }
    }

    static func sceneLabel(_ s: MusicScene) -> String {
        switch s {
        case .race: return "Track"
        case .raceFinal: return "Final stretch"
        case .training: return "Training"
        case .shop: return "Shop"
        case .town: return "Town"
        case .park: return "Park"
        case .cafe: return "Café"
        case .volley: return "Beach"
        case .studio: return "Studio"
        case .show: return "Show"
        case .results: return "Results"
        default: return "Screen"
        }
    }

    /// Mirrors `SessionPolicy.gameMusicAllowed` (the off / your-music branches use it so the two cannot drift).
    static func make(muted: Bool, musicOn: Bool, musicVolume: Float, otherAudioPlaying: Bool,
                     mode: MusicMode, scene: MusicScene, current: MusicTrack?, inGap: Bool, layerOn: Bool) -> NowPlaying {
        if muted { return NowPlaying(state: .muted, line: "Music", note: "Sound is muted", canSkip: false) }
        if !musicOn || musicVolume < 0.01 {
            return NowPlaying(state: .musicOff, line: "Music is off", note: "Turn Music on to pick songs", canSkip: false)
        }
        if !SessionPolicy.gameMusicAllowed(musicOn: musicOn, otherAudioPlaying: otherAudioPlaying) {
            return NowPlaying(state: .yourMusic, line: "Your music is playing", note: "Game music rests until it stops", canSkip: false)
        }
        if scene != .none {
            return NowPlaying(state: .screen, line: "\(sceneLabel(scene)) music", note: "Plays on its own here", canSkip: false)
        }
        let m = modeLabel(mode)
        if inGap || current == nil { return NowPlaying(state: .quiet, line: "\(m) · quiet moment", note: "Next song soon", canSkip: true) }
        if layerOn { return NowPlaying(state: .playing, line: "Play time · \(MusicTrack.lofiPlay.title)", note: nil, canSkip: true) }
        return NowPlaying(state: .playing, line: "\(m) · \(current!.title)", note: nil, canSkip: true)
    }
}
