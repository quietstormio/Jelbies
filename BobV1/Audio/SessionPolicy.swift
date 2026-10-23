//
//  SessionPolicy.swift
//  The pure decision for the shared AVAudioSession: category + options from (music on, other app's audio playing, mic needed), and whether the
//  game's own music/ambience stays silent. The game NEVER ducks or stops the user's Music / Spotify / podcast audio: every state mixes.
//

import AVFoundation

nonisolated struct SessionPlan: Equatable, Sendable {
    var category: AVAudioSession.Category
    var options: AVAudioSession.CategoryOptions
}

nonisolated enum SessionPolicy {
    /// `.ambient` (always mixes, respects the silent switch) for play; `.playAndRecord` + mixWithOthers while a mic engine needs input.
    /// Never `.duckOthers` / `.interruptSpokenAudioAndMixWithOthers`. (musicOn / otherAudioPlaying do not change the category: both mix; they
    /// are in the signature so a future change is a one-line test.)
    static func plan(musicOn: Bool, otherAudioPlaying: Bool, micActive: Bool) -> SessionPlan {
        if micActive { return SessionPlan(category: .playAndRecord, options: [.mixWithOthers, .defaultToSpeaker, .allowBluetoothA2DP]) }
        return SessionPlan(category: .ambient, options: [.mixWithOthers])
    }

    /// The game's music and room ambience play only when the setting is on AND no other app is playing audio (the saved setting is untouched).
    static func gameMusicAllowed(musicOn: Bool, otherAudioPlaying: Bool) -> Bool { musicOn && !otherAudioPlaying }
}
