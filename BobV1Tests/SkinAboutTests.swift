//
//  SkinAboutTests.swift
//  Guard for SkinAbout (the paragraph under a Jelmiko's name on the Profile and on its Jelly Spring page): every skin a creature can have (every look 0...26, and for the four
//  starters every colour variant: Soft, Deep, the rare jewel tone, the old exclusives) has a two-sentence paragraph of the right shape whose colour words match the palette.
//  A newly added look or colour variant WITHOUT text fails here, naming what to add.
//

import XCTest
import simd
@testable import BobV1

@MainActor
final class SkinAboutTests: XCTestCase {
    struct Skin { let look: Int; let variant: JellyVariant?; let label: String; let colours: [SIMD3<Float>]; let obtainable: Bool }

    static let banned = ["kiss", "romantic", "romance", "sweetheart", "darling", "lover", "boyfriend", "girlfriend", "crush", "wedding", "marry", "date"]
    /// The old exclusives' body colours (JellyVariantTests holds the same values): a save made before the jewel tones may still wear one.
    static let legacyFlesh: [String: [Float]] = ["Sunbeam gold": [1.000, 0.835, 0.330], "Midnight": [0.300, 0.340, 0.620], "Moonstone": [0.880, 0.930, 1.000],
                                                 "Rose quartz": [1.000, 0.740, 0.860], "Aurora": [0.560, 0.960, 0.800]]

    /// The colours a look's body really shows (sRGB-ish palette values): its flesh, plus every stop of a gradient or patch colour of a pattern.
    static func lookColours(_ id: Int) -> [SIMD3<Float>] {
        if let s = GradientLook.stops[id] { return [s.bottom, s.middle, s.top] }
        if id == JellyRoster.opalID { return GradientLook.Opal.stops }
        if let c = CowLook.looks[id] { return [c.flesh, c.patch] }
        if id == JellyRoster.teddyID { return [TeddyLook.current.flesh] }
        if id <= 3 { return [JellyVariantBook.classicPalette(id).flesh] }
        if id == JellyRoster.pearlID { return [WhiteWing.palette.flesh] }
        if id == JellyRoster.tigerID { return [TigerLook.flesh] }
        if id == JellyRoster.berryID { return [BerryLook.flesh] }
        return [JellyRoster.palette(id)?.flesh ?? SIMD3(0.5, 0.5, 0.5)]
    }

    /// Every skin, built from the game's own data (not from SkinAbout's tables, so an addition there cannot hide a gap).
    static func allSkins() -> [Skin] {
        let offered = Set(SpeciesInfo.pages(includingSpecial: true))
        var out: [Skin] = []
        for id in 0..<JellyRoster.knownCount {
            out.append(Skin(look: id, variant: nil, label: "\(JellyRoster.baseNames[id]) (look \(id)), classic", colours: lookColours(id), obtainable: offered.contains(id)))
        }
        for sp in 0...3 {
            var seen: [String: JellyVariant] = [:]
            for day in 0..<600 { for case let v? in JellyVariantBook.shades(species: sp, dayKey: day, owned: 0) { seen[v.title] = v } }
            seen[JellyVariantBook.exclusives[sp].title] = JellyVariantBook.exclusives[sp]
            for (_, v) in seen.sorted(by: { $0.key < $1.key }) {
                out.append(Skin(look: sp, variant: v, label: "\(JellyRoster.baseNames[sp]) (look \(sp)), \(v.title)", colours: [v.fleshV], obtainable: true))
            }
            // every rare jewel tone on offer for another species is not wearable by this one; the legacy ones are (old saves)
            for (t, f) in legacyFlesh.sorted(by: { $0.key < $1.key }) {
                let v = JellyVariant(title: t, flesh: SIMD3(f[0], f[1], f[2]), deep: SIMD3(f[0], f[1], f[2]) * 0.8, rare: true)
                out.append(Skin(look: sp, variant: v, label: "\(JellyRoster.baseNames[sp]) (look \(sp)), old exclusive \(t)", colours: [v.fleshV], obtainable: false))
            }
        }
        return out
    }

    func sentences(_ s: String) -> [String] { s.split(separator: ".", omittingEmptySubsequences: true).map { $0.trimmingCharacters(in: .whitespaces) } }

    func testEveryLookAndVariantHasText() {
        for id in 0..<JellyRoster.knownCount {
            XCTAssertTrue(SkinAbout.hasLook(id), "NEW LOOK WITHOUT TEXT: look \(id) (\(JellyRoster.baseNames[id])) has no entry in SkinAbout.looks (add its colour sentence and its character sentence)")
        }
        for sp in 0...3 {
            var titles = Set(["Soft", "Deep", JellyVariantBook.exclusives[sp].title]); titles.formUnion(JellyVariantBook.legacyExclusiveTitles)
            for t in titles.sorted() {
                XCTAssertNotNil(SkinAbout.variantColour(look: sp, title: t), "NEW COLOUR VARIANT WITHOUT TEXT: '\(t)' on look \(sp) (\(JellyRoster.baseNames[sp])) has no colour sentence in SkinAbout.variants / legacy")
            }
        }
        for v in JellyVariantBook.exclusives { XCTAssertTrue(SkinAbout.variants[0]?[v.title] != nil || SkinAbout.variants.values.contains { $0[v.title] != nil }, "rare colour \(v.title) has no text") }
        for id in 0..<JellyRoster.knownCount where JellyRoster.baseNames.indices.contains(id) && id != JellyRoster.tigerID && id != JellyRoster.berryID {
            XCTAssertTrue(SpeciesInfo.all.contains { $0.character == id }, "look \(id) (\(JellyRoster.baseNames[id])) is offered but has no SpeciesInfo page")
        }
    }

    func testShapeLengthsAndWords() {
        for k in SkinAboutTests.allSkins() {
            let colour = SkinAbout.colour(look: k.look, variant: k.variant)
            let character = SkinAbout.character(look: k.look)
            let text = SkinAbout.text(look: k.look, variant: k.variant)
            XCTAssertEqual(text, colour + " " + character, k.label)
            XCTAssertEqual(sentences(text).count, 2, "\(k.label): exactly two sentences: \(text)")
            XCTAssertTrue(colour.hasSuffix(".") && character.hasSuffix("."), "\(k.label): each sentence ends with a full stop")
            XCTAssertEqual(sentences(colour).count, 1, "\(k.label): colour part is one sentence")
            XCTAssertEqual(sentences(character).count, 1, "\(k.label): character part is one sentence")
            XCTAssertLessThanOrEqual(colour.count, 45, "\(k.label): colour sentence too long (\(colour.count)): \(colour)")
            XCTAssertLessThanOrEqual(character.count, 60, "\(k.label): character sentence too long (\(character.count)): \(character)")
            XCTAssertLessThanOrEqual(text.count, 100, "\(k.label): paragraph too long (\(text.count))")
            XCTAssertTrue(text.unicodeScalars.allSatisfy { $0.value >= 32 && $0.value < 127 }, "\(k.label): plain ASCII only (no emoji, no symbols)")
            XCTAssertNil(text.rangeOfCharacter(from: .decimalDigits), "\(k.label): no numbers")
            let lower = text.lowercased()
            for w in SkinAboutTests.banned { XCTAssertFalse(lower.contains(w), "\(k.label): banned word '\(w)'") }
        }
    }

    func testColourWordsMatchThePalette() {
        for k in SkinAboutTests.allSkins() {
            let colour = SkinAbout.colour(look: k.look, variant: k.variant).lowercased()
            var allowed = Set<String>()
            for c in k.colours { for f in SkinColour.families(c) { allowed.formUnion(f.words) } }
            XCTAssertTrue(allowed.contains { colour.contains($0) }, "\(k.label): colour sentence '\(colour)' names no colour of its palette \(k.colours) (allowed words: \(allowed.sorted()))")
        }
    }

    func testNoTwoLooksShareACharacterSentence() {
        var seen: [String: Int] = [:]
        for id in 0..<JellyRoster.knownCount {
            let c = SkinAbout.character(look: id)
            if let other = seen[c] { XCTFail("looks \(other) and \(id) share the character sentence '\(c)'") }
            seen[c] = id
        }
        // and no two skins of different looks share a whole paragraph
        var paras: [String: String] = [:]
        for k in SkinAboutTests.allSkins() {
            let t = SkinAbout.text(look: k.look, variant: k.variant)
            if let other = paras[t] { XCTFail("\(other) and \(k.label) show the same paragraph") }
            paras[t] = k.label
        }
    }

    func testVariantsDifferFromClassic() {
        for sp in 0...3 {
            let classic = SkinAbout.colour(look: sp, variant: nil)
            for k in SkinAboutTests.allSkins() where k.look == sp && k.variant != nil {
                XCTAssertNotEqual(SkinAbout.colour(look: sp, variant: k.variant), classic, "\(k.label) reuses the classic colour sentence")
            }
        }
    }

    func testSpringPageAndProfileAgree() {
        for id in 0..<JellyRoster.knownCount where SpeciesInfo.all.contains(where: { $0.character == id }) {
            XCTAssertEqual(SpeciesInfo.of(id).about, SkinAbout.text(look: id, variant: nil), "look \(id)")
        }
    }
}
