//
//  SoundCaptions.swift
//  Sound captions (round-1023 a11y): a pure map from a sound effect / a Jelbie's voice to the words shown under the top bar when the
//  "Sound captions" setting is on. UI ticks and footsteps are never captioned. AudioHub posts to `CaptionCenter` at its two choke points
//  (`play` and `chirp`) BEFORE its mute / volume guards, so a player who cannot hear the sound still sees it.
//

import Foundation

nonisolated enum SoundCaptions {
    /// The caption of a sound effect; nil = none (UI taps, footsteps and other constant noise).
    static func text(_ sfx: SFX, jelly name: String? = nil) -> String? {
        switch sfx {
        case .squish: return "Squish"
        case .boop: return "Boop"
        case .letgo: return "Boing"
        case .jump: return "Hop"
        case .chomp: return "Chomp"
        case .crunchNugget, .crunchFries: return "Crunch"
        case .slurp: return "Slurp"
        case .splash: return "Splash"
        case .soapbubbles: return "Soap bubbles"
        case .lintroller: return "Roll roll"
        case .sparkle, .perkSparkle: return "Sparkle"
        case .snore: return name.map { "\($0) snores" } ?? "Snoring"
        case .coin, .buyCoins, .purchase: return "Coins"
        case .notEnough: return "Not enough JellyCoins"
        case .countdownBeep: return "Beep"
        case .raceGo: return "Go whistle"
        case .raceFinish: return "Finish fanfare"
        case .stumble: return "Stumble"
        case .whistle: return "Whistle"
        case .volleyBonk: return "Bonk"
        case .volleySpike: return "Spike thwack"
        case .volleyLand: return "Soft landing"
        case .volleyPoint: return "Crowd cheers for the point"
        case .statUp: return "Level-up chime"
        case .perfectStreak: return "Streak chime"
        case .cheerSmall: return "Crowd cheers"
        case .tired: return name.map { "\($0) sighs" } ?? "Tired sigh"
        case .storeOpen: return "Shop bell"
        case .placeItem: return "Thunk"
        case .beanbagSit: return "Plop"
        case .unwrap: return "Unwrap"
        // quiet or constant: no caption
        case .wobble, .footstep, .zoomies, .setdown, .bubblepop, .uitap, .uiconfirm, .select, .pageTurn, .shoeOn, .tick, .goodStep: return nil
        }
    }

    /// The caption of a Jelbie's voice ("Pip chirps").
    static func voice(_ v: JellyVoice, name: String) -> String {
        switch v {
        case .happy: return "\(name) chirps"
        case .sad: return "\(name) whimpers"
        case .babble: return "\(name) babbles"
        }
    }
}
