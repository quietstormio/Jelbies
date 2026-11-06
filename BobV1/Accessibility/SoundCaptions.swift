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
        case .boop, .highFiveBoop: return "Boop"
        case .ringChime: return "Soft chime"
        case .letgo: return "Boing"
        case .jump: return "Hop"
        case .chomp: return "Chomp"
        case .crunchNugget, .crunchFries: return "Crunch"
        case .slurp: return "Slurp"
        case .splash: return "Splash"
        case .soapbubbles: return "Soap bubbles"
        case .lintroller: return "Roll roll"
        case .sparkle, .perkSparkle, .shineFinish: return "Sparkle"
        case .squeakPolish: return "Squeak"
        case .scrubLoop: return "Scrubbing"
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
        case .doorbell: return "Doorbell"
        case .placeItem: return "Thunk"
        case .beanbagSit: return "Plop"
        case .unwrap: return "Unwrap"
        case .emoteHic: return "Hic!"
        case .emoteAchoo: return "Achoo!"
        case .emoteWoozy: return "Woozy wobble"
        case .emoteBow: return "Little chime"
        case .emotePat: return "Pat pat"
        case .emoteTail: return "Tail swish"
        case .emoteFlutter: return "Wing flutter"
        case .emoteSpin: return "Twirl"
        case .emoteWiggle: return "Wiggle boing"
        case .emoteSpinHug: return "Happy hug coo"
        case .emoteStarSigh: return "Little sigh"
        case .emoteTilt: return "Curious hm?"
        case .emoteWelcome: return "Excited welcome"
        case .emoteCheckIn: return "Hello?"
        case .emoteTwinkle: return "Twinkle"
        case .emoteStrut: return "Proud marching"
        case .emoteSploot: return "Soft flop"
        // quiet or constant: no caption
        case .bubbleBloop, .bubblePop, .bubbleChirp, .wobble, .footstep, .congaTick, .zoomies, .setdown, .bubblepop, .uitap, .uiconfirm, .select, .pageTurn, .shoeOn, .tick, .goodStep: return nil
        }
    }

    /// The caption of a Jelbie's voice ("Pip chirps").
    static func voice(_ v: JellyVoice, name: String) -> String {
        switch v {
        case .happy: return "\(name) chirps"
        case .sad: return "\(name) whimpers"
        case .babble: return "\(name) babbles"
        case .curious: return "\(name) hums, curious"
        case .ooh: return "\(name) says ooh"
        case .hum: return "\(name) hums happily"
        case .giggle: return "\(name) giggles"
        case .hello: return "\(name) calls hello"
        case .yawn: return "\(name) yawns"
        case .yay: return "\(name) cheers"
        case .uhoh: return "\(name) says uh-oh"
        case .wheee: return "\(name) squeals wheee"
        case .tasty: return "\(name) hums, tasty"
        case .aww: return "\(name) says aww"
        case .huh: return "\(name) says huh"
        case .pfft: return "\(name) huffs"
        case .lala: return "\(name) sings la la"
        case .eep: return "\(name) says eep"
        case .mmhmm: return "\(name) says mm-hmm"
        case .nyoo: return "\(name) whines softly"
        }
    }
}
