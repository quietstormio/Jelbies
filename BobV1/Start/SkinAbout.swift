//
//  SkinAbout.swift
//  THE one source of the paragraph under a Jelmiko's name (the Profile) and on its Jelly Spring page: two short static sentences,
//  "<its colour>. <a small, warm character note>."  e.g. "Pale pink with rose patches. Shy at first, then the friendliest one in the room."
//
//  Built from two parts so it can never name the wrong colour:
//    - the COLOUR sentence belongs to a skin = a look (id 0...26) plus, for the four starters (0...3), a colour variant (Soft, Deep, the rare jewel tone, or an old exclusive);
//    - the CHARACTER sentence belongs to the look and is shared by its variants.
//  Rules (SkinAboutTests): colour <= 45 characters, character <= 52, whole <= 88 (every paragraph is exactly two lines on the Profile: ProfileStableTests); plain, warm, third person, no numbers, nothing romantic; the colour words match the palette.
//  A new look or colour variant without text here fails SkinAboutTests; there is no fallback to another look's text.
//

import Foundation
import simd

nonisolated enum SkinAbout {
    /// Colour sentence + character sentence of a look in its own classic colour, by look (species) id.
    static let looks: [Int: (colour: String, character: String)] = [
        0: ("Baby blue, plain and perfectly round.", "Cool, calm and happy to follow you."),
        1: ("Sunny yellow, with a tail and back spikes.", "Bright, sunny and full of cheer."),
        2: ("Mint green, with two wobbly antennas.", "Calm, cosy and always sleepy."),
        3: ("Soft lavender purple, with small wings.", "Dreamy, with its head in the clouds."),
        4: ("Honey brown, round ears and a cream belly.", "Soft as a pillow, loves a hug."),
        5: ("Soft pearly white, with pearl-cream wings.", "Gentle, shimmery and light."),
        6: ("White with black ears, patches and feet.", "Silly, happy and full of wobble."),
        7: ("Bright orange with rust-brown stripes.", "Bold and bouncy, and full of energy."),
        8: ("Strawberry pink, with seeds and a leaf top.", "Sweet, cheerful and bouncy."),
        9: ("Aqua with milky white ribbons swirled in.", "Swirly and curious, and one of a kind."),
        10: ("Shiny gold from top to toe.", "Proud, cheerful and a bit of a show-off."),
        11: ("Shiny silver chrome from top to toe.", "Calm and sleek, with a silly side."),
        12: ("Pastel rainbow of pink, mint, sky and lilac.", "Playful, and a little proud of its colours."),
        13: ("White with black cow-print patches.", "Gentle, clumsy and up for a snack."),
        14: ("Cream with chocolate cow-print patches.", "Warm, sleepy and happiest in the sun."),
        15: ("Pale pink with rose patches.", "Shy at first, then the friendliest one in the room."),
        16: ("Red on top, melting to gold at the feet.", "Warm to look at, warmer to hug."),
        17: ("Deep jewel red with a polished shine.", "Bold, warm-hearted and quick to giggle."),
        18: ("Glossy black with pale lilac eyes.", "Quiet and gentle, loves low light."),
        19: ("Pink on top, lilac in the middle, blue below.", "Sweet and fluffy as a fairground treat."),
        20: ("Sea-foam on top, sinking to deep navy.", "Calm on the surface, curious underneath."),
        21: ("Lemon yellow on top, lime green below.", "Fizzy, bright and always up for a game."),
        22: ("Teal on top, then violet, then pink.", "Dreamy and easy-going, like a slow tide."),
        23: ("Deep emerald green with a polished shine.", "Wise, steady and calm as a forest pond."),
        24: ("Royal blue with a polished shine.", "Calm, loyal and good at keeping secrets."),
        25: ("Bright purple with a polished shine.", "Curious, creative and full of ideas."),
        26: ("Shiny bronze with warm highlights.", "Sturdy, friendly and glad to see you."),
    ]

    /// Colour sentences of the colour variants of the four starters: look id -> variant title ("Soft", "Deep", the rare jewel tone, an old exclusive) -> sentence.
    static let variants: [Int: [String: String]] = [
        0: ["Soft": "Soft sky blue, a shade lighter than most.",
            "Deep": "Cornflower blue, a shade darker than most.",
            "Sapphire": "Rich sapphire blue, a rare jewel tone."],
        1: ["Soft": "Light gold, a shade lighter than most.",
            "Deep": "Mustard yellow, a shade darker than most.",
            "Amber": "Glowing amber orange, a rare jewel tone."],
        2: ["Soft": "Pale mint green, a shade lighter than most.",
            "Deep": "Fern green, a shade darker than most.",
            "Emerald": "Deep emerald green, a rare jewel tone."],
        3: ["Soft": "Pale lilac, a shade lighter than most.",
            "Deep": "Dusty violet, a shade darker than most.",
            "Amethyst": "Rich amethyst purple, a rare jewel tone."],
    ]
    /// The five old exclusive colours that a save made before the jewel tones may still hold (any starter can wear one; the colour is the same on every look).
    static let legacy: [String: String] = [
        "Sunbeam gold": "Bright sunbeam gold, a colour from long ago.",
        "Midnight": "Midnight indigo blue, a colour from long ago.",
        "Moonstone": "Pale moonstone blue, a colour from long ago.",
        "Rose quartz": "Rose quartz pink, a colour from long ago.",
        "Aurora": "Glowing aurora green, a colour from long ago.",
    ]

    /// Whether `look` has its text (the test asks this for every look that exists).
    static func hasLook(_ look: Int) -> Bool { looks[look] != nil }
    /// The colour sentence of a colour variant `title` on `look`; nil when there is none written.
    static func variantColour(look: Int, title: String) -> String? { variants[look]?[title] ?? legacy[title] }

    static func character(look: Int) -> String { looks[look]?.character ?? "A Jelmiko all of its own." }

    /// The colour sentence of the skin: the look's own, or its variant's (a Jelmiko that wears a Spring colour variant).
    static func colour(look: Int, variant: JellyVariant?) -> String {
        guard let l = looks[look] else { assertionFailure("SkinAbout: look \(look) has no text"); return "A colour all of its own." }
        guard let v = variant, JellyVariants.takesVariant(look) else { return l.colour }
        if let s = variantColour(look: look, title: v.title) { return s }
        assertionFailure("SkinAbout: look \(look) variant '\(v.title)' has no text")
        // A colour saved by value that this file has never heard of: name it from its own body colour, so it can still never name the wrong one.
        return "\(SkinColour.primaryWord(of: v.fleshV)) all over, a colour of its own."
    }

    /// THE paragraph: colour sentence + character sentence. `variant` nil = the look's own classic colour.
    static func text(look: Int, variant: JellyVariant?) -> String {
        colour(look: look, variant: variant) + " " + character(look: look)
    }
}

/// A rough colour naming of an sRGB-ish body colour: which colour words may describe it (the guard test checks every colour sentence against this).
nonisolated enum SkinColour {
    enum Family: String, CaseIterable {
        case red, orange, brown, yellow, green, teal, blue, purple, pink, white, grey, black
        /// The words that count as naming this family.
        var words: [String] {
            switch self {
            case .red: return ["red", "ruby", "crimson", "scarlet"]
            case .orange: return ["orange", "amber", "apricot", "peach", "coral", "tangerine", "bronze", "copper", "rust"]
            case .brown: return ["brown", "chocolate", "caramel", "honey", "toffee", "bronze", "copper", "rust"]
            case .yellow: return ["yellow", "gold", "lemon", "butter", "cream", "sunbeam", "mustard"]
            case .green: return ["green", "lime", "mint", "emerald", "sea-foam", "aurora", "fern"]
            case .teal: return ["teal", "aqua", "turquoise", "sea-foam", "green", "blue"]
            case .blue: return ["blue", "sapphire", "navy", "sky", "royal", "indigo", "periwinkle", "cornflower"]
            case .purple: return ["purple", "violet", "lilac", "lavender", "plum", "amethyst", "indigo"]
            case .pink: return ["pink", "rose", "blush", "magenta"]
            case .white: return ["white", "cream", "pearl", "milky", "ivory"]
            case .grey: return ["grey", "silver", "chrome", "steel"]
            case .black: return ["black", "midnight", "ink", "dark"]
            }
        }
    }

    /// Hue ranges in degrees; a colour within `tolerance` of a range also counts as that family (colours near a border may be named either way).
    private static let hueRanges: [(Family, Float, Float)] = [
        (.orange, 15, 45), (.yellow, 45, 70), (.green, 70, 165), (.teal, 165, 200), (.blue, 200, 255), (.purple, 255, 290), (.pink, 290, 345),
    ]
    static let tolerance: Float = 14

    /// The families a colour (r, g, b in 0...1, values above 1 are clamped) may be called.
    static func families(_ rgb: SIMD3<Float>) -> Set<Family> {
        let c = simd_clamp(rgb, SIMD3(repeating: 0), SIMD3(repeating: 1))
        let mx = max(c.x, c.y, c.z), mn = min(c.x, c.y, c.z), d = mx - mn
        let s = mx > 0 ? d / mx : 0
        var hue: Float = 0
        if d > 0 {
            if mx == c.x { hue = 60 * ((c.y - c.z) / d).truncatingRemainder(dividingBy: 6) }
            else if mx == c.y { hue = 60 * ((c.z - c.x) / d + 2) }
            else { hue = 60 * ((c.x - c.y) / d + 4) }
            if hue < 0 { hue += 360 }
        }
        var out = Set<Family>()
        if s < 0.12 {
            if mx < 0.35 { out.insert(.black) } else if mx < 0.9 { out.insert(.grey) } else { out.insert(.white) }
            if s < 0.06 { return out }
        }
        func within(_ lo: Float, _ hi: Float) -> Bool { hue >= lo - tolerance && hue <= hi + tolerance }
        for (f, lo, hi) in hueRanges where within(lo, hi) { out.insert(f) }
        if hue >= 345 - tolerance || hue <= 15 + tolerance {            // the red end of the wheel
            out.insert(.red)
            if s < 0.6 && mx > 0.85 { out.insert(.pink) }
            if hue >= 345 - tolerance { out.insert(.pink) }
        }
        if out.contains(.orange), mx < 0.78 { out.insert(.brown) }
        if out.contains(.yellow), s < 0.35 { out.insert(.white) }
        if out.contains(.orange), s < 0.35 { out.insert(.white); out.insert(.yellow) }
        if mx < 0.35 { out.insert(.black) }
        return out
    }

    /// One word for a colour (used only for a colour variant this file has no sentence for).
    static func primaryWord(of rgb: SIMD3<Float>) -> String {
        let f = families(rgb)
        let order: [Family] = [.black, .grey, .white, .brown, .red, .orange, .yellow, .green, .teal, .blue, .purple, .pink]
        let pick = order.first(where: { f.contains($0) }) ?? .grey
        return pick.words[0].capitalized
    }
}
