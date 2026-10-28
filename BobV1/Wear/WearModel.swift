//
//  WearModel.swift
//  The wardrobe's data model. The pieces themselves (cases, titles, anchors, prices, tags) are GENERATED from the Blender exports into
//  WearGenerated.swift by tools/convert_wear_art.py; this file adds what the game needs to know about them: the theme tags (for the beauty contest),
//  how each piece is carried (rigid / surface-bound / arm-frame, per part) and when it hides (asleep, eating, wash, flips).
//

import simd
import Foundation

/// Theme tags a look carries; the beauty contest scores a Jelly's outfit against the round's theme.
nonisolated enum WearTag: String, CaseIterable, Codable, Sendable { case cute, cool, sparkly, sporty, sweet }

/// The reference frame the artist authored a piece in (WearGenerated rows).
nonisolated enum WearAnchor: String, Sendable { case feet, headTop, face, neck, chest, wrist, back, waist }

nonisolated enum WearInfo {
    /// The shop blurb: no effect on anything but looks.
    static func blurb(_ r: WearGenerated.Row) -> String {
        let t = r.tags.map(\.rawValue)
        let mood = t.count > 1 ? "\(t[0].capitalized) and \(t[1])." : "\(t.first?.capitalized ?? "Fun")."
        switch r.slot {
        case .feet: return "\(mood) Just for looks."
        case .head: return "\(mood) A hat for your Jelbie. Just for looks."
        case .face: return "\(mood) Goes on his face, off while he sleeps. Just for looks."
        case .neck: return "\(mood) Round his middle. Just for looks."
        case .hands: return "\(mood) Goes on his arms. Just for looks."
        case .body: return "\(mood) Just for looks."
        }
    }
}

nonisolated extension WearLook {
    private static let table: [WearLook: WearGenerated.Row] = Dictionary(uniqueKeysWithValues: WearGenerated.rows.map { ($0.look, $0) })
    var row: WearGenerated.Row { Self.table[self]! }
    var slot: WearSlot { row.slot }
    var title: String { row.title }
    var tags: [WearTag] { row.tags }
    var anchor: WearAnchor { row.anchor }
    var isShoe: Bool { row.slot == .feet }
    /// The Blender export this look is drawn from ("" for the shoes, which are painted on the shell).
    var art: String { row.art }
    /// Every look of a slot, in catalogue order.
    static func looks(_ s: WearSlot) -> [WearLook] { WearGenerated.rows.filter { $0.slot == s }.map(\.look) }
    static let shoes: [WearLook] = looks(.feet)
    /// The winner medal: awarded for a first place on the Circuit, never sold.
    static let medal: WearLook = .medalGold
    /// Looks that are drawn from art (hats, glasses, ...): everything but the shoes.
    /// Pulled from the shop for now (2026-10-25: the hoodie and raincoat read as a bucket / diaper): not sold, taken off and refunded once. The art stays.
    static let unlisted: Set<WearLook> = [.hoodie, .raincoat]
    static let pieces: [WearLook] = WearGenerated.rows.filter { $0.slot != .feet }.map(\.look)
}

/// How a piece is carried and when it hides.
nonisolated struct WearHide: OptionSet, Sendable {
    let rawValue: Int
    /// Poofs off while he sleeps (the eye mask goes on), back when he wakes. Hats and face items.
    static let asleep = WearHide(rawValue: 1)
    /// UNUSED since the drink fix (2026-10-26): worn items stay on while he eats or drinks (food and bottle go to the mouth, below the eyes; the mouth keep-out is the clothes' side of that).
    static let eating = WearHide(rawValue: 2)
    /// Off in the wash scene (like the shoes). EVERYTHING.
    static let wash = WearHide(rawValue: 4)
    /// Off during flips and rolls where it would clip the floor or itself (tall hats, ears, cape, backpack).
    static let flip = WearHide(rawValue: 8)
}

nonisolated enum WearRules {
    static func hide(_ l: WearLook) -> WearHide {
        var h: WearHide = [.wash]
        switch l.slot {
        case .head, .face: h.insert(.asleep)
        default: break
        }
        switch l {
        case .partyHat, .chefHat, .witchHat, .tophat, .propellerBeanie, .bunnyEars, .catEars, .frogEars, .crownGold, .capeHero, .backpackSky, .cowboyHat, .beeAntennae, .vikingHat: h.insert(.flip)
        default: break
        }
        return h
    }

    /// How one named part of a piece is carried. `w0` / `w1`: surface weight at the part's top / bottom (1 = bound to the skin, 0 = carried rigidly with
    /// the body); `h0` / `h1`: how much it swings (hanging pieces) at its top / bottom. A part that hangs ramps from bound at the top to loose at the bottom.
    struct PartRule { var w0: Float = 0, w1: Float = 0, h0: Float = 0, h1: Float = 0; var spin = false }

    static func rule(_ l: WearLook, part: String) -> PartRule {
        let surface = PartRule(w0: 1, w1: 1)
        let rigid = PartRule()
        switch l {
        case .scarfCosy, .scarfSky:
            if part.hasPrefix("tail") { return PartRule(w0: 1, w1: 0.3, h0: 0, h1: 1) }
            return part == "knot" ? rigid : surface
        case .medalGold: return part.hasPrefix("ribbon") ? surface : PartRule(w0: 0, w1: 0, h0: 1, h1: 1)
        case .whistleCoach: return part.hasPrefix("strap") ? surface : PartRule(w0: 0, w1: 0, h0: 1, h1: 1)
        case .pearls: return part == "drop" || part == "cap" ? PartRule(w0: 1, w1: 1, h0: 0.5, h1: 0.5) : surface
        case .tutuPink: return part == "waistband" || part.hasPrefix("bow") ? surface : PartRule(w0: 1, w1: 1, h0: 0, h1: 1)
        case .scarfSilk:
            if part.hasPrefix("tail") { return PartRule(w0: 1, w1: 0.3, h0: 0, h1: 1) }
            return part == "knot" ? rigid : surface
        case .chainGold: return part == "coin" || part == "coinring" || part == "star" || part == "bail" ? PartRule(w0: 1, w1: 1, h0: 0.5, h1: 0.5) : surface
        case .capeHero: return part == "panel" ? PartRule(w0: 1, w1: 0.35, h0: 0, h1: 1) : surface
        case .monocleGold: return part == "chain" || part.hasPrefix("link") ? PartRule(w0: 1, w1: 0.4, h0: 0, h1: 1) : rigid
        case .backpackSky: return part.hasPrefix("strap") ? surface : rigid
        case .gogglesAviator: return part == "strap" ? surface : rigid
        // batch 3 (2026-10-24): the hoodie's and raincoat's hoods rest rigid behind the shoulders; the rest hugs the belly, cords and the slicker's hem hang a little
        case .hoodie: return part == "hood" || part == "hoodrim" ? rigid : part.hasPrefix("cord") || part.hasPrefix("aglet") ? PartRule(w0: 1, w1: 0.5, h0: 0, h1: 1) : surface
        case .raincoat: return part.hasPrefix("hood") ? rigid : part == "coat" ? PartRule(w0: 1, w1: 1, h0: 0, h1: 0.3) : surface
        case .propellerBeanie: return part.hasPrefix("blade") || part == "hub" ? PartRule(spin: true) : rigid
        default: return isSurface(l) ? surface : rigid
        }
    }

    /// Which looks have any surface-bound part.
    static func isSurface(_ l: WearLook) -> Bool {
        switch l {
        case .bandanaCoral, .bandanaMint, .bibPink, .bibSky, .sashPink, .sashSky, .heroPatch, .sweatband, .scarfCosy, .scarfSky, .medalGold,
             .whistleCoach, .pearls, .tutuPink, .capeHero, .backpackSky, .monocleGold, .gogglesAviator, .lei, .hoodie, .raincoat,
             .vestPuffer, .cardiganCable, .bagCrossbody, .scarfSilk, .chainGold: return true
        default: return false
        }
    }
    static func isArm(_ l: WearLook) -> Bool { l.slot == .hands }
}

/// The team colours of the Circuit jerseys and bibs (the spec's palette): the player's Jelly is sky or pink, the rivals lavender / coral / honey / mint.
nonisolated enum WearTeam: Int, CaseIterable, Sendable {
    case sky, pink, lavender, coral, honey, mint
    var srgb: SIMD3<Float> {
        switch self {
        case .sky: return SIMD3(0x6E, 0xB3, 0xD1) / 255; case .pink: return SIMD3(0xE9, 0x8A, 0xA4) / 255
        case .lavender: return SIMD3(0xB9, 0xA3, 0xE6) / 255; case .coral: return SIMD3(0xF5, 0x8B, 0x6E) / 255
        case .honey: return SIMD3(0xF9, 0xCC, 0x59) / 255; case .mint: return SIMD3(0x9F, 0xD9, 0xB0) / 255
        }
    }
    var linear: SIMD3<Float> { OKLab.srgbToLinear(srgb) }
    static let creamLinear = OKLab.srgbToLinear(SIMD3<Float>(0xF7, 0xF0, 0xE0) / 255)
    static let inkLinear = OKLab.srgbToLinear(SIMD3<Float>(0x4D, 0x33, 0x1F) / 255)
    /// The rival teams in lane order.
    static let rivals: [WearTeam] = [.lavender, .coral, .honey, .mint]
    /// The player's own colour: sky or pink by roster index.
    static func player(roster id: Int) -> WearTeam { id % 2 == 0 ? .sky : .pink }
    /// The race number on a bib: the player's is chosen by roster index; rivals take other numbers.
    static func playerNumber(roster id: Int) -> Int { [7, 12, 21][((id % 3) + 3) % 3] }
    static let rivalNumbers = [3, 9, 15, 4]
}
