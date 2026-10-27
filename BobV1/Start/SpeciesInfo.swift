//
//  SpeciesInfo.swift
//  The words and numbers behind the species picker (Adoption Center): species names, epithets, about lines, the starting trait jars and the
//  moves each species shows off. Content as decided 2026-10-26 (docs/Species.md). Characters: 0 Bob (blue), 1 Pip (yellow), 2 Moss (green),
//  3 Lavender (purple); the picker order is blue, yellow, purple, green.
//

import SwiftUI

/// What a Moves-tab play button (or an idle emote) makes the stage's Jelbie do. Existing moves only.
enum StageMove: Equatable {
    case idle(IdleKind)      // a commanded idle move (look, roll, tail spin, stretch, sway, flap-hop, cartwheel...)
    case hop                 // the jump for joy
    case blink
    case face(FaceKind)
}

struct SpeciesMoveInfo: Identifiable {
    let id = UUID()
    let title: String, subtitle: String, icon: String
    let move: StageMove
}

struct SpeciesInfo {
    let character: Int
    let name: String, epithet: String, about: String, signature: String, signatureIcon: String
    let lore: String
    let bestAt: String, bestAtKey: ConditionKey
    let loves: String
    /// Starting jars in the order Cute, Sweet, Sparkly, Cool, Sporty.
    let traits: [Int]
    let moves: [SpeciesMoveInfo]
    /// What the Jelbie does now and then while the player reads (gentle, in place).
    let emotes: [StageMove]
    var defaultName: String { JellyRoster.baseNames[character] }

    /// Picker order (blue, yellow, purple, green), as character ids.
    static let order = [0, 1, 3, 2]
    static func of(_ character: Int) -> SpeciesInfo { all.first { $0.character == character } ?? all[0] }

    static let jarNames = ["Cute", "Sweet", "Sparkly", "Cool", "Sporty"]
    /// Jar index (Cute, Sweet, Sparkly, Cool, Sporty) -> the game's condition stat.
    static let jarKeys: [ConditionKey] = [.cute, .sweet, .sparkle, .cool, .sporty]

    static let all: [SpeciesInfo] = [
        SpeciesInfo(character: 0, name: "Blueberry", epithet: "The unbothered one",
                    about: "Cool as a cucumber. Acts like they don't care, then follows you everywhere.",
                    signature: "Side-eye", signatureIcon: "eye.fill",
                    lore: "Woke up in a rain puddle at dusk, under a blue-grey sky. Blueberries take life slow and steady. Nothing rattles them, but they always sit a little closer to their favourite person.",
                    bestAt: "Cool", bestAtKey: .cool, loves: "Sushi roll", traits: [50, 45, 30, 85, 55],
                    moves: [SpeciesMoveInfo(title: "Side-eye", subtitle: "A slow, unimpressed glance", icon: "eye.fill", move: .idle(.look)),
                            SpeciesMoveInfo(title: "Shrug-hop", subtitle: "A lazy little hop", icon: "arrow.up", move: .hop),
                            SpeciesMoveInfo(title: "Roll over", subtitle: "Knows it already", icon: "arrow.left.arrow.right", move: .idle(.roll))],
                    emotes: [.idle(.look), .blink, .hop, .face(.focused), .blink]),
        SpeciesInfo(character: 1, name: "Lemon Drop", epithet: "The sunny one",
                    about: "Sunshine on legs. First one up, last one to nap, and it wags that spiky tail at everyone.",
                    signature: "Tail wag", signatureIcon: "sun.max.fill",
                    lore: "Woke up inside a sunbeam. The little orange spikes down its back are sun-sparks that cooled off and went soft. Lemon Drops can't sit still: zooming, bouncing and chasing are their love language.",
                    bestAt: "Sporty", bestAtKey: .sporty, loves: "Donut", traits: [58, 60, 46, 28, 85],
                    moves: [SpeciesMoveInfo(title: "Tail wag", subtitle: "Spins after that spiky tail", icon: "sun.max.fill", move: .idle(.tail)),
                            SpeciesMoveInfo(title: "Cartwheel", subtitle: "Shows off", icon: "figure.gymnastics", move: .idle(.cartwheel)),
                            SpeciesMoveInfo(title: "Happy hop", subtitle: "When you come home", icon: "arrow.up", move: .hop)],
                    emotes: [.idle(.bounce), .hop, .face(.excited), .idle(.tail), .hop]),
        SpeciesInfo(character: 3, name: "Taro", epithet: "The dreamy one",
                    about: "Head in the clouds, and nearly the rest of it too. Flaps, floats, dances and nuzzles.",
                    signature: "Little wings", signatureIcon: "bird.fill",
                    lore: "Woke up in the very last drop of twilight, just as the first stars came out. That's why Taros can almost fly: their little wings lift them for a moment or two, and they always land smiling.",
                    bestAt: "Sparkly", bestAtKey: .sparkle, loves: "Bedtime cookie", traits: [70, 55, 84, 40, 45],
                    moves: [SpeciesMoveInfo(title: "Flutter hop", subtitle: "A flap and a float", icon: "bird.fill", move: .idle(.flapHop)),
                            SpeciesMoveInfo(title: "Twirl", subtitle: "A dreamy spin", icon: "arrow.triangle.2.circlepath", move: .idle(.tail)),
                            SpeciesMoveInfo(title: "Happy hop", subtitle: "When you come home", icon: "arrow.up", move: .hop)],
                    emotes: [.idle(.flapHop), .face(.hopeful), .idle(.flapHop), .blink, .idle(.sway)]),
        SpeciesInfo(character: 2, name: "Matcha", epithet: "The sleepy one",
                    about: "Calm and cosy. Loves a long sit, a big stretch and a look out the window. Never far from a nap.",
                    signature: "Head daisy", signatureIcon: "camera.macro",
                    lore: "Woke up under a tea bush in the shade. A daisy seed landed on its head that very morning and simply never left. Matchas say the daisy tells them when it's nap time. It is always nap time.",
                    bestAt: "Sweet", bestAtKey: .sweet, loves: "Onigiri", traits: [62, 82, 40, 50, 30],
                    moves: [SpeciesMoveInfo(title: "Big stretch", subtitle: "Reaches for the sky", icon: "figure.arms.open", move: .idle(.stretch)),
                            SpeciesMoveInfo(title: "Sleepy sway", subtitle: "When it's nap time", icon: "moon.zzz.fill", move: .idle(.sway)),
                            SpeciesMoveInfo(title: "Roll over", subtitle: "Knows it already", icon: "arrow.left.arrow.right", move: .idle(.roll))],
                    emotes: [.idle(.stretch), .face(.sleepy), .blink, .idle(.sway), .blink]),
    ]

    /// The species colour (the game's own tint) and a deeper shade for rims and the selected tab.
    var tint: Color { let t = JellyRoster.tint(character); return Color(red: Double(t.x), green: Double(t.y), blue: Double(t.z)) }
    var deep: Color { let t = JellyRoster.tint(character); return Color(red: Double(t.x) * 0.62, green: Double(t.y) * 0.62, blue: Double(t.z) * 0.66) }
    /// The tint lightened for the page background (top, bottom).
    var skyTop: Color { Self.mix(tint, 0.62) }
    var skyBottom: Color { Self.mix(tint, 0.28) }
    private static func mix(_ c: Color, _ w: Double) -> Color {
        let u = UIColor(c); var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        u.getRed(&r, green: &g, blue: &b, alpha: &a)
        return Color(red: Double(r) + (1 - Double(r)) * w, green: Double(g) + (1 - Double(g)) * w, blue: Double(b) + (1 - Double(b)) * w)
    }
}
