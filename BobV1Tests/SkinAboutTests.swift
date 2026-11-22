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
    struct Skin { let look: Int; let variant: JellyVariant?; let label: String; let colours: [SIMD3<Float>]; let obtainable: Bool; var layout = "single" }

    static let banned = ["kiss", "romantic", "romance", "sweetheart", "darling", "lover", "boyfriend", "girlfriend", "crush", "wedding", "marry", "date"]
    /// The old exclusives' body colours (JellyVariantTests holds the same values): a save made before the jewel tones may still wear one.
    static let legacyFlesh: [String: [Float]] = ["Sunbeam gold": [1.000, 0.835, 0.330], "Midnight": [0.300, 0.340, 0.620], "Moonstone": [0.880, 0.930, 1.000],
                                                 "Rose quartz": [1.000, 0.740, 0.860], "Aurora": [0.560, 0.960, 0.800]]

    /// The colours a look's body really shows (sRGB-ish palette values): its flesh, plus every stop of a gradient or patch colour of a pattern.
    static func lookColours(_ id: Int) -> [SIMD3<Float>] {
        if let s = GradientLook.stops[id] { return [s.top, s.middle, s.bottom] }          // top to bottom
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
            out.append(Skin(look: id, variant: nil, label: "\(JellyRoster.baseNames[id]) (look \(id)), classic", colours: lookColours(id), obtainable: offered.contains(id), layout: GradientLook.stops[id] != nil || id == JellyRoster.opalID ? "stops" : CowLook.looks[id] != nil ? "patch" : "single"))
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
            XCTAssertLessThanOrEqual(character.count, 52, "\(k.label): character sentence too long (\(character.count)): \(character)")
            XCTAssertLessThanOrEqual(text.count, 88, "\(k.label): paragraph too long (\(text.count))")
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

    // MARK: feature words (a colour sentence may only claim what the look really draws)

    /// Words that name each feature; a look may not use another feature's words, and must use its own where listed in `required`.
    static let featureWords: [JellyFeature: [String]] = [
        .daisy: ["daisy", "flower", "petal"], .spines: ["spike", "spiky", "tail"], .wings: ["wing"], .ears: ["ear", "ears"],
    ]
    static let antennaWords = ["antenna"]
    /// What each look's classic colour sentence MUST mention (its real drawn features / marks today).
    static let required: [Int: [String]] = [
        1: ["tail", "spike"], 2: ["antenna"], 3: ["wing"], 4: ["ear", "belly"], 5: ["wing"], 6: ["black", "ear"],
        7: ["stripe"], 8: ["seed", "leaf"], 13: ["patch"], 14: ["patch"], 15: ["patch"],
    ]
    /// Words no sentence of that look may use (things the look does not draw): cows have no horns, Marble has no patches ...
    static let alwaysForbidden = ["horn", "horns", "mane", "fin", "fins", "beak", "whisker", "whiskers"]

    func containsWord(_ text: String, _ w: String) -> Bool {
        text.lowercased().range(of: "\\b" + w + "s?\\b", options: .regularExpression) != nil
    }

    func testFeatureWordsAgreeWithWhatTheLookDraws() {
        for id in 0..<JellyRoster.knownCount {
            let feature = JellyRoster.feature(id)
            let colour = SkinAbout.looks[id]?.colour ?? ""
            let whole = colour + " " + SkinAbout.character(look: id)
            for w in SkinAboutTests.required[id] ?? [] { XCTAssertTrue(containsWord(colour, w) || colour.lowercased().contains(w), "look \(id) (\(JellyRoster.baseNames[id])) draws '\(w)' but its colour sentence does not say so: \(colour)") }
            for (f, words) in SkinAboutTests.featureWords where f != feature && !(f == .ears && feature == .ears) {
                // Pip's spikes/tail belong only to Pip; ears to Teddy and Panda; wings to Lavender and Pearl; the antennas to Moss
                for w in words { XCTAssertFalse(containsWord(whole, w), "look \(id) (\(JellyRoster.baseNames[id])) has feature \(feature) but its text says '\(w)': \(whole)") }
            }
            for w in SkinAboutTests.antennaWords where feature != .daisy { XCTAssertFalse(containsWord(whole, w), "look \(id) draws no antennas but says '\(w)'") }
            if feature == .daisy { for w in SkinAboutTests.featureWords[.daisy]! { XCTAssertFalse(containsWord(whole, w), "Moss has two antennas, not a \(w): \(whole)") } }
            for w in SkinAboutTests.alwaysForbidden { XCTAssertFalse(containsWord(whole, w), "look \(id) says '\(w)': \(whole)") }
        }
        // variants of the starters: never claim a feature the colour sentence of the classic look does not (they may only name a colour)
        for k in SkinAboutTests.allSkins() where k.variant != nil {
            let c = SkinAbout.colour(look: k.look, variant: k.variant)
            for words in SkinAboutTests.featureWords.values { for w in words { XCTAssertFalse(containsWord(c, w), "\(k.label): a colour variant sentence names a feature '\(w)'") } }
        }
    }

    /// Writes every skin with its real palette values to a JSON file for the swatch board (only when the folder named by SKIN_BOARD_DIR exists; no assertions).
    func testDumpSkinsForTheBoard() {
        let dir = ProcessInfo.processInfo.environment["SKIN_BOARD_DIR"] ?? "/private/tmp/claude-501/-Users-dmarshall94-Desktop-BobV1/e0755ccf-aeea-4c40-b871-1f1d2b621362/scratchpad/skinabout"
        guard FileManager.default.fileExists(atPath: dir) else { return }
        func c(_ v: SIMD3<Float>) -> [Double] { [Double(min(max(v.x, 0), 1)), Double(min(max(v.y, 0), 1)), Double(min(max(v.z, 0), 1))] }
        let rows: [[String: Any]] = SkinAboutTests.allSkins().map { k in
            ["label": k.label, "obtainable": k.obtainable, "layout": k.layout, "colours": k.colours.map(c), "sentence": SkinAbout.colour(look: k.look, variant: k.variant),
             "families": k.colours.map { SkinColour.families($0).map(\.rawValue).sorted() }]
        }
        if let d = try? JSONSerialization.data(withJSONObject: rows, options: [.prettyPrinted]) { try? d.write(to: URL(fileURLWithPath: dir + "/skins.json")) }
    }
}
