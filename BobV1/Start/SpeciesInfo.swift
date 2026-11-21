//
//  SpeciesInfo.swift
//  The words and numbers behind the species picker (Adoption Center): species names, epithets, about lines, the starting trait jars and the
//  moves each species shows off. Content as decided 2026-10-26 (docs/Species.md). Characters: 0 Bob (blue), 1 Pip (yellow), 2 Moss (green),
//  3 Lavender (purple); the picker order is blue, yellow, purple, green, then the specials Teddy (4), Pearl (5), Panda (6), Opal (12) when adopting more.
//

import SwiftUI

/// What a Moves-tab play button (or an idle emote) makes the stage's Jelbie do. Existing moves only.
enum StageMove: Equatable {
    case idle(IdleKind)      // a commanded idle move (look, roll, tail spin, stretch, sway, flap-hop...)
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
    /// The special species sold in the Jelly Spring for JellyCoins (never the free first gift): Teddy, Pearl, Panda, Opal (AdoptionPrice.special).
    /// 2026-11-21 (spring-seven-r1): + the seven new looks: Moo, Cocoa, Blush (the cows; only while `cowsInStore`) and the gradients Sunset, Cotton Candy, Ocean, Lagoon.
    static let special = [JellyRoster.teddyID, JellyRoster.pearlID, JellyRoster.pandaID, JellyRoster.opalID] + (cowsInStore ? cowIDs : []) + gradientIDs
    /// THE ONE SWITCH for the three cows: false until cow-looks-r1 (body modes 91 / 93 / 95) is merged; then true and Moo, Cocoa, Blush appear in the Jelly Spring.
    static let cowsInStore = false
    static let cowIDs = [JellyRoster.mooID, JellyRoster.cocoaID, JellyRoster.blushID]
    static let gradientIDs = [JellyRoster.sunsetID, JellyRoster.cottonCandyID, JellyRoster.oceanID, JellyRoster.lagoonID]
    /// The picker pages: the four starters, then (when adopting more, not the free first gift) the four specials.
    static func pages(includingSpecial: Bool) -> [Int] { includingSpecial ? order + special : order }
    var isSpecial: Bool { Self.special.contains(character) }
    static func of(_ character: Int) -> SpeciesInfo { all.first { $0.character == character } ?? all[0] }

    static let jarNames = ["Cute", "Sweet", "Sparkly", "Cool", "Sporty"]
    /// Jar index (Cute, Sweet, Sparkly, Cool, Sporty) -> the game's condition stat.
    static let jarKeys: [ConditionKey] = [.cute, .sweet, .sparkle, .cool, .sporty]

    static let all: [SpeciesInfo] = [
        SpeciesInfo(character: 0, name: "Blueberry", epithet: "The unbothered one",
                    about: "Cool as a cucumber. Acts like they don't care, then follows you everywhere.",
                    signature: "Side-eye", signatureIcon: "eye.fill",
                    lore: "Woke up in a rain puddle at dusk, under a blue-grey sky. Blueberries take life slow and steady. Nothing rattles them, but they always sit a little closer to their favourite person.",
                    bestAt: "Cool", bestAtKey: .cool, loves: "Sushi", traits: [50, 45, 30, 85, 55],
                    moves: [SpeciesMoveInfo(title: "Side-eye", subtitle: "Signature move", icon: "eye.fill", move: .idle(.look)),
                            SpeciesMoveInfo(title: "Shrug-hop", subtitle: "A lazy little hop", icon: "arrow.up", move: .hop)],
                    emotes: [.idle(.look), .blink, .hop, .face(.focused), .blink]),
        SpeciesInfo(character: 1, name: "Lemon Drop", epithet: "The sunny one",
                    about: "Sunshine on legs. First one up, last one to nap, and it wags that spiky tail at everyone.",
                    signature: "Tail wag", signatureIcon: "sun.max.fill",
                    lore: "Woke up inside a sunbeam. The little orange spikes down its back are sun-sparks that cooled off and went soft. Lemon Drops can't sit still: zooming, bouncing and chasing are their love language.",
                    bestAt: "Sporty", bestAtKey: .sporty, loves: "Donut", traits: [58, 60, 46, 28, 85],
                    moves: [SpeciesMoveInfo(title: "Tail wag", subtitle: "Signature move", icon: "sun.max.fill", move: .idle(.tail)),
                            SpeciesMoveInfo(title: "Happy hop", subtitle: "When you come home", icon: "arrow.up", move: .hop)],
                    emotes: [.idle(.bounce), .hop, .face(.excited), .idle(.tail), .hop]),
        SpeciesInfo(character: 3, name: "Taro", epithet: "The dreamy one",
                    about: "Head in the clouds, and nearly the rest of it too. Flaps, floats, dances and nuzzles.",
                    signature: "Little wings", signatureIcon: "bird.fill",
                    lore: "Woke up in the very last drop of twilight, just as the first stars came out. That's why Taros can almost fly: their little wings lift them for a moment or two, and they always land smiling.",
                    bestAt: "Sparkly", bestAtKey: .sparkle, loves: "Cookie", traits: [70, 55, 84, 40, 45],
                    moves: [SpeciesMoveInfo(title: "Flutter hop", subtitle: "Signature move", icon: "bird.fill", move: .idle(.flapHop)),
                            SpeciesMoveInfo(title: "Twirl", subtitle: "A dreamy spin", icon: "arrow.triangle.2.circlepath", move: .idle(.tail)),
                            SpeciesMoveInfo(title: "Happy hop", subtitle: "When you come home", icon: "arrow.up", move: .hop)],
                    emotes: [.idle(.flapHop), .face(.hopeful), .idle(.flapHop), .blink, .idle(.sway)]),
        SpeciesInfo(character: 2, name: "Matcha", epithet: "The sleepy one",
                    about: "Calm and cosy. Loves a long sit, a big stretch and a look out the window. Never far from a nap.",
                    signature: "Antennas", signatureIcon: "camera.macro",
                    lore: "Woke up under a tea bush in the shade. Two little sprouts grew on its head that very morning and have wobbled along ever since. Matchas say the antennas tell them when it's nap time. It is always nap time.",
                    bestAt: "Sweet", bestAtKey: .sweet, loves: "Onigiri", traits: [62, 82, 40, 50, 30],
                    moves: [SpeciesMoveInfo(title: "Big stretch", subtitle: "Signature move", icon: "figure.arms.open", move: .idle(.stretch)),
                            SpeciesMoveInfo(title: "Sleepy sway", subtitle: "When it's nap time", icon: "moon.zzz.fill", move: .idle(.sway))],
                    emotes: [.idle(.stretch), .face(.sleepy), .blink, .idle(.sway), .blink]),
        SpeciesInfo(character: JellyRoster.teddyID, name: "Teddy", epithet: "The cuddly one",
                    about: "Soft as a pillow, with round bear ears and a puffy tail. Loves hugs more than anything.",
                    signature: "Bear ears", signatureIcon: "heart.fill",
                    lore: "Woke up in a pile of warm blankets. Teddies are always ready for a cuddle, and they hum when they are happy.",
                    bestAt: "Cute", bestAtKey: .cute, loves: "Cookie", traits: [88, 75, 40, 35, 40],
                    moves: [SpeciesMoveInfo(title: "Sway", subtitle: "Signature move", icon: "heart.fill", move: .idle(.sway)),
                            SpeciesMoveInfo(title: "Happy hop", subtitle: "When you come home", icon: "arrow.up", move: .hop)],
                    emotes: [.idle(.sway), .blink, .hop, .face(.hopeful), .blink]),
        SpeciesInfo(character: JellyRoster.pearlID, name: "Pearl", epithet: "The shimmery one",
                    about: "Soft white and shiny, with little pearly wings. Floats, flutters and sparkles.",
                    signature: "Pearly wings", signatureIcon: "bird.fill",
                    lore: "Woke up inside a seashell at moonrise. Pearls glow a little in the dark, and their wings lift them for a happy flutter.",
                    bestAt: "Sparkly", bestAtKey: .sparkle, loves: "Onigiri", traits: [65, 60, 90, 45, 35],
                    moves: [SpeciesMoveInfo(title: "Flutter hop", subtitle: "Signature move", icon: "bird.fill", move: .idle(.flapHop)),
                            SpeciesMoveInfo(title: "Happy hop", subtitle: "When you come home", icon: "arrow.up", move: .hop)],
                    emotes: [.idle(.flapHop), .face(.hopeful), .idle(.sway), .blink, .idle(.flapHop)]),
        SpeciesInfo(character: JellyRoster.pandaID, name: "Panda", epithet: "The silly one",
                    about: "Black ears, black patches and a big happy wobble. Loves to roll around and play.",
                    signature: "Silly wobble", signatureIcon: "face.smiling.fill",
                    lore: "Woke up in a bamboo grove, and has been snacking and giggling ever since. Pandas always find a sunny spot for a nap.",
                    bestAt: "Sweet", bestAtKey: .sweet, loves: "Donut", traits: [70, 80, 35, 40, 55],
                    moves: [SpeciesMoveInfo(title: "Stretch", subtitle: "Signature move", icon: "figure.arms.open", move: .idle(.stretch)),
                            SpeciesMoveInfo(title: "Happy hop", subtitle: "When you come home", icon: "arrow.up", move: .hop)],
                    emotes: [.idle(.stretch), .blink, .hop, .face(.excited), .idle(.sway)]),
        // Opal (12): a special, sold in the Jelly Spring like Teddy / Pearl / Panda (`special`, so `pages`); never a starter.
        SpeciesInfo(character: JellyRoster.opalID, name: "Opal", epithet: "The rainbow one",
                    about: "Pastel rainbow from head to toe. Every turn shows a new colour, and it loves to show them off.",
                    signature: "Rainbow glow", signatureIcon: "rainbow",
                    lore: "Woke up inside a soap bubble at sunrise, just as the light turned every colour at once. Opals keep a little of that rainbow wherever they go.",
                    bestAt: "Sparkly", bestAtKey: .sparkle, loves: "Ice pop", traits: [72, 68, 90, 50, 38],
                    moves: [SpeciesMoveInfo(title: "Twirl", subtitle: "Signature move", icon: "rainbow", move: .idle(.tail)),
                            SpeciesMoveInfo(title: "Happy hop", subtitle: "When you come home", icon: "arrow.up", move: .hop)],
                    emotes: [.idle(.tail), .face(.excited), .blink, .idle(.sway), .hop]),
        // The seven new Spring looks (2026-11-21): cows Moo / Cocoa / Blush (listed in `special` only while `cowsInStore`) and the gradients Sunset / Cotton Candy / Ocean / Lagoon.
        // Specials like Opal: never a starter, a classic colour only, a voice set borrowed from Panda's (every id >= 7), Opal's price.
        SpeciesInfo(character: JellyRoster.mooID, name: "Moo", epithet: "The patchy one",
                    about: "White with big black patches. Gentle, a little clumsy and always up for a snack.",
                    signature: "Patchy wobble", signatureIcon: "pawprint.fill",
                    lore: "Woke up in a meadow at milking time, with every patch landing somewhere new. No two Moos are spotted the same.",
                    bestAt: "Sweet", bestAtKey: .sweet, loves: "Donut", traits: [74, 82, 38, 36, 50],
                    moves: [SpeciesMoveInfo(title: "Sway", subtitle: "Signature move", icon: "pawprint.fill", move: .idle(.sway)),
                            SpeciesMoveInfo(title: "Happy hop", subtitle: "When you come home", icon: "arrow.up", move: .hop)],
                    emotes: [.idle(.sway), .blink, .hop, .face(.hopeful), .blink]),
        SpeciesInfo(character: JellyRoster.cocoaID, name: "Cocoa", epithet: "The cosy one",
                    about: "Cream with chocolate patches. Warm, sleepy and happiest in a sunny spot.",
                    signature: "Cosy stretch", signatureIcon: "cup.and.saucer.fill",
                    lore: "Woke up beside a mug of hot chocolate on the first cold morning. Cocoas smell faintly of toast.",
                    bestAt: "Sweet", bestAtKey: .sweet, loves: "Cookie", traits: [72, 84, 34, 40, 44],
                    moves: [SpeciesMoveInfo(title: "Stretch", subtitle: "Signature move", icon: "figure.arms.open", move: .idle(.stretch)),
                            SpeciesMoveInfo(title: "Happy hop", subtitle: "When you come home", icon: "arrow.up", move: .hop)],
                    emotes: [.idle(.stretch), .blink, .idle(.sway), .face(.sleepy), .hop]),
        SpeciesInfo(character: JellyRoster.blushID, name: "Blush", epithet: "The rosy one",
                    about: "Pale pink with rose patches. Shy at first, then the friendliest one in the room.",
                    signature: "Rosy giggle", signatureIcon: "heart.fill",
                    lore: "Woke up in a strawberry field at sunrise, and has been a little pink in the cheeks ever since.",
                    bestAt: "Cute", bestAtKey: .cute, loves: "Donut", traits: [90, 72, 48, 30, 42],
                    moves: [SpeciesMoveInfo(title: "Sway", subtitle: "Signature move", icon: "heart.fill", move: .idle(.sway)),
                            SpeciesMoveInfo(title: "Happy hop", subtitle: "When you come home", icon: "arrow.up", move: .hop)],
                    emotes: [.idle(.sway), .face(.hopeful), .blink, .hop, .blink]),
        SpeciesInfo(character: JellyRoster.sunsetID, name: "Sunset", epithet: "The glowing one",
                    about: "Red on top, melting through orange to golden yellow at the feet. Warm to look at, warmer to hug.",
                    signature: "Sunset glow", signatureIcon: "sun.horizon.fill",
                    lore: "Woke up at the very end of the day, as the sky poured from red to gold. Sunsets glow a little brighter when they are happy.",
                    bestAt: "Sparkly", bestAtKey: .sparkle, loves: "Donut", traits: [66, 62, 84, 44, 56],
                    moves: [SpeciesMoveInfo(title: "Twirl", subtitle: "Signature move", icon: "sun.horizon.fill", move: .idle(.tail)),
                            SpeciesMoveInfo(title: "Happy hop", subtitle: "When you come home", icon: "arrow.up", move: .hop)],
                    emotes: [.idle(.tail), .face(.excited), .blink, .idle(.sway), .hop]),
        SpeciesInfo(character: JellyRoster.cottonCandyID, name: "Cotton Candy", epithet: "The fluffy one",
                    about: "Pink on top, lilac in the middle and baby blue at the feet. Sweet as a fairground treat.",
                    signature: "Candy swirl", signatureIcon: "cloud.fill",
                    lore: "Woke up spinning in a cloud of sugar at the fair. Cotton Candies never quite stop giggling.",
                    bestAt: "Sweet", bestAtKey: .sweet, loves: "Donut", traits: [82, 86, 66, 34, 40],
                    moves: [SpeciesMoveInfo(title: "Twirl", subtitle: "Signature move", icon: "cloud.fill", move: .idle(.tail)),
                            SpeciesMoveInfo(title: "Happy hop", subtitle: "When you come home", icon: "arrow.up", move: .hop)],
                    emotes: [.idle(.tail), .face(.excited), .blink, .idle(.sway), .hop]),
        SpeciesInfo(character: JellyRoster.oceanID, name: "Ocean", epithet: "The deep one",
                    about: "Sea-foam green on top, sinking through blue to navy at the feet. Calm on the surface, curious underneath.",
                    signature: "Tide sway", signatureIcon: "water.waves",
                    lore: "Woke up where the shallows turn deep, with the tide rocking it to sleep. Oceans hum along with the waves.",
                    bestAt: "Cool", bestAtKey: .cool, loves: "Sushi", traits: [56, 60, 62, 84, 46],
                    moves: [SpeciesMoveInfo(title: "Sway", subtitle: "Signature move", icon: "water.waves", move: .idle(.sway)),
                            SpeciesMoveInfo(title: "Happy hop", subtitle: "When you come home", icon: "arrow.up", move: .hop)],
                    emotes: [.idle(.sway), .blink, .face(.focused), .hop, .blink]),
        SpeciesInfo(character: JellyRoster.lagoonID, name: "Lagoon", epithet: "The dreamy tide",
                    about: "Teal on top, violet in the middle and pink at the feet. Every angle is a new sunset in the water.",
                    signature: "Lagoon glow", signatureIcon: "drop.fill",
                    lore: "Woke up in a hidden lagoon where the light never quite settles. Lagoons are shy, but love to splash.",
                    bestAt: "Sparkly", bestAtKey: .sparkle, loves: "Ice pop", traits: [68, 60, 86, 52, 44],
                    moves: [SpeciesMoveInfo(title: "Twirl", subtitle: "Signature move", icon: "drop.fill", move: .idle(.tail)),
                            SpeciesMoveInfo(title: "Happy hop", subtitle: "When you come home", icon: "arrow.up", move: .hop)],
                    emotes: [.idle(.tail), .face(.hopeful), .blink, .idle(.sway), .hop]),
    ]

    /// The mockup's palette for the picker screen (saturated page colours sampled from the design boards; purple follows the same family).
    var look: SpeciesLook { SpeciesLook.of(character) }
}

/// Colours of one species page, taken from the design boards.
struct SpeciesLook {
    let top: Color, bottom: Color          // page gradient
    let dot: Color                         // the colour dot
    let tabFill: Color, tabLine: Color     // selected tab (light tint + outline)
    let card: Color                        // info card
    let rowHi: Color                       // the signature move row
    let padTop: Color                      // pedestal top (a white tinted a little)
    let glow: Color                        // inner glow / contact shadow on the pedestal
    var isDark = false                     // a dark page (Panda): text drawn straight on the background switches to cream
    var rimOverride: (top: Color, bottom: Color)? = nil   // pedestal side, when it should not be the page colour deepened
    /// Ink for text and icons drawn straight on the page background (cards and pills with their own light fill keep SK.ink).
    var onPage: Color { isDark ? SK.cream : SK.ink }

    static func of(_ c: Int) -> SpeciesLook {
        switch c {
        case 1: return SpeciesLook(top: Color(hex: 0xFFDD7E), bottom: Color(hex: 0xFFC04B), dot: Color(hex: 0xFFCB45), tabFill: Color(hex: 0xFFEBA9), tabLine: Color(hex: 0xF1C24C),
                                   card: Color(hex: 0xFFF8EC), rowHi: Color(hex: 0xFFEBB0), padTop: Color(hex: 0xF6EFE0), glow: Color(hex: 0xE59A52))
        case 2: return SpeciesLook(top: Color(hex: 0xACE0BF), bottom: Color(hex: 0x79C598), dot: Color(hex: 0x7FCB9E), tabFill: Color(hex: 0xD3F1DF), tabLine: Color(hex: 0x8BD1A7),
                                   card: Color(hex: 0xF9F8ED), rowHi: Color(hex: 0xD3F1DF), padTop: Color(hex: 0xE8F0EB), glow: Color(hex: 0x4F9A76))
        case 3: return SpeciesLook(top: Color(hex: 0xD1BBF3), bottom: Color(hex: 0xA98BDD), dot: Color(hex: 0xAF8FE3), tabFill: Color(hex: 0xE7DBFA), tabLine: Color(hex: 0xBA9FEA),
                                   card: Color(hex: 0xF9F6F2), rowHi: Color(hex: 0xE7DBFA), padTop: Color(hex: 0xF0ECF6), glow: Color(hex: 0x7E62B8))
        case JellyRoster.teddyID: return SpeciesLook(top: Color(hex: 0xEBC9A0), bottom: Color(hex: 0xD2A272), dot: Color(hex: 0xC99563), tabFill: Color(hex: 0xF6E3CB), tabLine: Color(hex: 0xD9AE82),
                                   card: Color(hex: 0xFBF5EC), rowHi: Color(hex: 0xF6E3CB), padTop: Color(hex: 0xF2E8DC), glow: Color(hex: 0x9A6E44))
        case JellyRoster.pearlID: return SpeciesLook(top: Color(hex: 0xE4E8F5), bottom: Color(hex: 0xB9C3E0), dot: Color(hex: 0xC4CCE6), tabFill: Color(hex: 0xEEF1FA), tabLine: Color(hex: 0xC4CCE6),
                                   card: Color(hex: 0xFAF8F5), rowHi: Color(hex: 0xEEF1FA), padTop: Color(hex: 0xF1F2F7), glow: Color(hex: 0x7C88B4))
        case JellyRoster.pandaID: return SpeciesLook(top: Color(hex: 0x3A3A40), bottom: Color(hex: 0x24242A), dot: Color(hex: 0x4A4A4F), tabFill: Color(hex: 0xE6E6E8), tabLine: Color(hex: 0xB4B4BA),
                                   card: Color(hex: 0xF9F8F0), rowHi: Color(hex: 0xE6E6E8), padTop: Color(hex: 0xF2F2F2), glow: Color(hex: 0x6A6A70),
                                   isDark: true, rimOverride: (Color(hex: 0x8A8A90), Color(hex: 0x65656B)))
        case JellyRoster.opalID: return SpeciesLook(top: Color(hex: 0xF6D9EE), bottom: Color(hex: 0xCBD8F6), dot: Color(hex: 0xE6C8F0), tabFill: Color(hex: 0xF3E8FA), tabLine: Color(hex: 0xD9C4F0),
                                   card: Color(hex: 0xFBF8F6), rowHi: Color(hex: 0xF3E8FA), padTop: Color(hex: 0xF4F1F8), glow: Color(hex: 0x9A8CC4))
        case JellyRoster.mooID: return SpeciesLook(top: Color(hex: 0xE4EBEE), bottom: Color(hex: 0xB3BFC8), dot: Color(hex: 0x9AA6AE), tabFill: Color(hex: 0xEEF2F4), tabLine: Color(hex: 0xB3BFC8),
                                   card: Color(hex: 0xFAF8F5), rowHi: Color(hex: 0xEEF2F4), padTop: Color(hex: 0xF1F3F4), glow: Color(hex: 0x6F7C86))
        case JellyRoster.cocoaID: return SpeciesLook(top: Color(hex: 0xEAD2B8), bottom: Color(hex: 0xC29A74), dot: Color(hex: 0xB88A62), tabFill: Color(hex: 0xF6E7D6), tabLine: Color(hex: 0xD2AE88),
                                   card: Color(hex: 0xFBF5EE), rowHi: Color(hex: 0xF6E7D6), padTop: Color(hex: 0xF3EADF), glow: Color(hex: 0x8A6244))
        case JellyRoster.blushID: return SpeciesLook(top: Color(hex: 0xFBD8E0), bottom: Color(hex: 0xEBA8BB), dot: Color(hex: 0xEE9FB4), tabFill: Color(hex: 0xFCE6EC), tabLine: Color(hex: 0xEDB5C5),
                                   card: Color(hex: 0xFCF6F4), rowHi: Color(hex: 0xFCE6EC), padTop: Color(hex: 0xF7EDEF), glow: Color(hex: 0xB86A82))
        case JellyRoster.sunsetID: return SpeciesLook(top: Color(hex: 0xFFC98F), bottom: Color(hex: 0xF2767A), dot: Color(hex: 0xF58A55), tabFill: Color(hex: 0xFFE2C4), tabLine: Color(hex: 0xF5A78A),
                                   card: Color(hex: 0xFFF6EC), rowHi: Color(hex: 0xFFE2C4), padTop: Color(hex: 0xF8EDE3), glow: Color(hex: 0xC4534F))
        case JellyRoster.cottonCandyID: return SpeciesLook(top: Color(hex: 0xF9CBE2), bottom: Color(hex: 0xB8C9F4), dot: Color(hex: 0xCDA8F0), tabFill: Color(hex: 0xF4E6FA), tabLine: Color(hex: 0xD3BDF0),
                                   card: Color(hex: 0xFBF7F8), rowHi: Color(hex: 0xF4E6FA), padTop: Color(hex: 0xF5EFF6), glow: Color(hex: 0x9C84C8))
        case JellyRoster.oceanID: return SpeciesLook(top: Color(hex: 0x95D8E8), bottom: Color(hex: 0x3F7CC6), dot: Color(hex: 0x4FA9E8), tabFill: Color(hex: 0xD2ECF8), tabLine: Color(hex: 0x82BEE6),
                                   card: Color(hex: 0xF6F8F8), rowHi: Color(hex: 0xD2ECF8), padTop: Color(hex: 0xE9F1F5), glow: Color(hex: 0x2E5A96))
        case JellyRoster.lagoonID: return SpeciesLook(top: Color(hex: 0xB8A6F0), bottom: Color(hex: 0x5CCFD0), dot: Color(hex: 0xA070E8), tabFill: Color(hex: 0xE3DAFA), tabLine: Color(hex: 0xB9A3EA),
                                   card: Color(hex: 0xF8F6F8), rowHi: Color(hex: 0xE3DAFA), padTop: Color(hex: 0xEFEDF6), glow: Color(hex: 0x5D4AA8))
        default: return SpeciesLook(top: Color(hex: 0x9DD0F2), bottom: Color(hex: 0x6DADE0), dot: Color(hex: 0x79B7E6), tabFill: Color(hex: 0xD4EAFA), tabLine: Color(hex: 0x8DC1EA),
                                    card: Color(hex: 0xF8F6F1), rowHi: Color(hex: 0xD4EAFA), padTop: Color(hex: 0xEAF0F5), glow: Color(hex: 0x4F83B5))
        }
    }
    /// Pedestal side: lighter under the top edge, darker at the bottom (the page colour, deepened).
    var rimTop: Color { rimOverride?.top ?? Self.shade(bottom, 0.98) }
    var rimBottom: Color { rimOverride?.bottom ?? Self.shade(bottom, 0.76) }
    static func shade(_ c: Color, _ k: Double) -> Color {
        let u = UIColor(c); var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        u.getRed(&r, green: &g, blue: &b, alpha: &a)
        return Color(red: Double(r) * k, green: Double(g) * k, blue: Double(b) * k)
    }
}
