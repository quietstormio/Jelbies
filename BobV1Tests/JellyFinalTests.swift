//
//  JellyFinalTests.swift
//  Per-species jelly look: the species -> (style, level, neon) table, and that every palette the game can produce lands in the right group,
//  by the species tag the roster puts on a palette and (race rivals, park visitors, tests) by colour alone.
//

import XCTest
import simd
@testable import BobV1

@MainActor
final class JellyFinalTests: XCTestCase {
    typealias S = JellyLook.Species

    func flesh(_ p: Palette) -> SIMD4<Float> { SIMD4(p.flesh, 1) }

    func testTable() {
        let b = JellyLook.profile(species: .blue), g = JellyLook.profile(species: .green), y = JellyLook.profile(species: .yellow), o = JellyLook.profile(species: .other)
        XCTAssertEqual([b.style, g.style, y.style, o.style], [.a, .b, .b, .b])
        XCTAssertEqual([b.level, g.level, y.level, o.level], [1, 1, 2, 1])
        XCTAssertEqual(g.neon.soft, 0.15); XCTAssertEqual(g.neon.deepen, 0.22)
        XCTAssertEqual(b.neon.soft + b.neon.deepen + y.neon.soft + y.neon.deepen + o.neon.soft + o.neon.deepen, 0)
        // the buffer a shader reads: [0].x = 2 for style A, 1 for style B; neon only for Green
        JellyLook.level = 1; defer { JellyLook.level = 0 }
        XCTAssertEqual(JellyLook.params(profile: b)[0].x, 2); XCTAssertEqual(JellyLook.params(profile: o)[0].x, 1)
        XCTAssertEqual(JellyLook.params(profile: b)[4].x, 0); XCTAssertEqual(JellyLook.params(profile: b)[0].w, 0.35)           // round 4: gloss 0.35, no highlight shift
        XCTAssertEqual(JellyLook.params(profile: g)[6].y, 0.22); XCTAssertEqual(JellyLook.params(profile: y)[6].y, 0)
        XCTAssertGreaterThan(JellyLook.params(profile: y)[0].y, 0.001)          // yellow: see-through level 2
        XCTAssertEqual(JellyLook.params(profile: o)[0].y, 0)
        XCTAssertEqual(JellyLook.launchLevel, 1, "the approved look is the shipped default")
        XCTAssertEqual(JellyLook.launchAll, true)
    }

    /// The look every species gets in a launch with no arguments, with the dev switch forced off (the store build) and on (the phone test build): the same table both ways.
    func testShippedLookEqualsTableWithAndWithoutDevSwitch() throws {
        let suite = "JellyFinalTests.empty.\(UUID().uuidString)"
        let empty = try XCTUnwrap(UserDefaults(suiteName: suite)); defer { empty.removePersistentDomain(forName: suite) }
        let savedLevel = JellyLook.level, savedAll = JellyLook.all; defer { JellyLook.level = savedLevel; JellyLook.all = savedAll }
        // species id -> (style rawValue in [0].x, level, neon soft, neon deepen, kind: 1 opaque / 2 see-through)
        let want: [Int: (Float, Int, Float, Float, Int)] = [0: (2, 1, 0, 0, 1), 1: (1, 2, 0, 0, 2), 2: (1, 1, 0.15, 0.22, 1)]
        for dev in [false, true] {
            JellyLook.level = JellyLook.resolveLevel(devArgs: dev, defaults: empty)
            JellyLook.all = JellyLook.resolveAll(devArgs: dev, defaults: empty)
            XCTAssertEqual(JellyLook.level, 1, "dev \(dev)"); XCTAssertEqual(JellyLook.all, true, "dev \(dev)")
            for id in 0..<JellyRoster.knownCount {
                let f = SIMD4<Float>((JellyRoster.palette(id) ?? PaletteKey.blue.palette).flesh, 1)          // (Bob's palette is nil: the model's own)
                let w = want[id] ?? (1, 1, 0, 0, 1)
                let pr = JellyLook.profile(forFlesh: f, speciesID: id), v = JellyLook.params(profile: pr)
                XCTAssertEqual([v[0].x, Float(pr.level), v[6].x, v[6].y], [w.0, Float(w.1), w.2, w.3], "species \(id) dev \(dev)")
                XCTAssertEqual(JellyLook.kind(flesh: f, bellyMode: 0, speciesID: id), w.4, "species \(id) dev \(dev)")
                XCTAssertEqual(JellyLook.level(forFlesh: f, speciesID: id), w.1, "species \(id) dev \(dev)")
            }
        }
        // a dev argument still wins where the switch is on, and is ignored where it is off
        empty.set(0, forKey: "JellyLook"); empty.set(0, forKey: "JellyAll")
        XCTAssertEqual(JellyLook.resolveLevel(devArgs: true, defaults: empty), 0); XCTAssertEqual(JellyLook.resolveAll(devArgs: true, defaults: empty), false)
        XCTAssertEqual(JellyLook.resolveLevel(devArgs: false, defaults: empty), 1); XCTAssertEqual(JellyLook.resolveAll(devArgs: false, defaults: empty), true)
    }

    /// The roster's species tag decides, whatever the saved colour is.
    func testTagWins() {
        let odd = SIMD4<Float>(0.9, 0.1, 0.9, 1)          // a colour near no species
        XCTAssertEqual(JellyLook.profile(forFlesh: odd, speciesID: 0).species, .blue)
        XCTAssertEqual(JellyLook.profile(forFlesh: odd, speciesID: 1).species, .yellow)
        XCTAssertEqual(JellyLook.profile(forFlesh: odd, speciesID: 2).species, .green)
        for sp in [3, 4, 5, 6] { XCTAssertEqual(JellyLook.profile(forFlesh: odd, speciesID: sp).species, .other) }
        for sp in 0..<JellyRoster.knownCount {          // the palette the roster gives out carries the tag
            if let p = JellyRoster.palette(sp) { XCTAssertEqual(p.jellySpecies, sp) }
        }
    }

    /// By colour alone (no tag): every colour the game makes.
    func testColourFallback() {
        var rows: [String] = []
        func check(_ name: String, _ p: Palette, _ want: S?) {
            let got = JellyLook.classify(flesh: flesh(p)); rows.append("\(name): \(got)")
            if let want { XCTAssertEqual(got, want, name) }
        }
        check("Blue", PaletteKey.blue.palette, .blue)
        check("Yellow", PaletteKey.yellow.palette, .yellow)
        check("Green", JellyPalettes.green, .green)
        check("Lavender", JellyPalettes.lavender, .other)
        check("Pearl", WhiteWing.palette, .other)
        check("Panda", PandaLook.palette, .other)
        for t in TeddyLook.tones { check("Teddy " + t.name, t.palette, .other) }
        let want: [S] = [.blue, .yellow, .green, .other]
        for (i, v) in JellyVariantBook.exclusives.enumerated() { check(v.title, v.palette, want[i]) }
        for c in ParkColour.allCases {
            check("park " + c.rawValue, JellyPalettes.park(c), c.isClassic ? [.blue, .yellow, .green, .other][ParkColour.classics.firstIndex(of: c)!] : nil)
            // by tag: only the classic colours are a species; the rest of the visitors get the default (style B, level 1, no neon)
            let tagged = JellyLook.profile(forFlesh: flesh(JellyPalettes.park(c)), speciesID: JellyPalettes.park(c).jellySpecies)
            if !c.isClassic { XCTAssertEqual(tagged.species, .other, "park " + c.rawValue) }
        }
        print("JELLYFINAL colour fallback:\n" + rows.joined(separator: "\n"))
    }
}
