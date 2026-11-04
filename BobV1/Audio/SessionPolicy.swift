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

/// The home room's ambience bed level for the music scene in front: off in the café (its own playlist), on everywhere else. A pure function of the
/// scene, slewed so the change is a fade, never a step; because it only reads the scene it cannot stay muted after Go home / a trip exit / a cold launch.
nonisolated enum HomeAmbience {
    static let fadeSeconds: Float = 1.2
    static func target(scene: MusicScene) -> Float { scene == .cafe ? 0 : 1 }
    static func slew(_ level: Float, scene: MusicScene, dt: Double) -> Float {
        let t = target(scene: scene), step = Float(dt) / fadeSeconds
        return level < t ? min(t, level + step) : max(t, level - step)
    }
}

/// Music that should be audible but is not for `grace` seconds triggers one recovery, then waits `retry` seconds before the next. Pure.
nonisolated struct MusicWatchdog: Sendable {
    static let grace = 3.0, retry = 5.0
    private(set) var silent = 0.0
    mutating func reset() { silent = 0 }
    /// A route change or similar: check sooner.
    mutating func nudge() { silent = max(silent, Self.grace - 1) }
    /// True when the caller should re-run the resume path now.
    mutating func update(dt: Double, shouldPlay: Bool, isPlaying: Bool) -> Bool {
        guard shouldPlay, !isPlaying else { silent = 0; return false }
        silent += dt
        guard silent >= Self.grace else { return false }
        silent = Self.grace - Self.retry
        return true
    }
}
