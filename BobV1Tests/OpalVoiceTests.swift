import XCTest
@testable import BobV1

/// Opal (12) has her own voice set, jelly8 (2026-11-18); every other character's file names are exactly what they were.
final class OpalVoiceTests: XCTestCase {
    private func has(_ n: String) -> Bool {
        Bundle.main.url(forResource: n, withExtension: "m4a") != nil
            || Bundle(for: OpalVoiceTests.self).url(forResource: n, withExtension: "m4a") != nil
    }
    private let opal = JellyRoster.opalID

    func testEveryKindResolvesToABundledOpalFile() {
        for v in JellyVoice.allCases { for k in 1...3 {
            let name = JellyVoiceSet.file(character: opal, v, variant: k)
            XCTAssertTrue(has(name), name)
            if JellyVoiceSet.opalKinds.contains(v) { XCTAssertTrue(name.contains("_jelly8"), name) }
        } }
        XCTAssertEqual(JellyVoiceSet.opalKinds.count, 20)
        for r in [0.0, 0.99] {
            let name = JellyVoiceSet.snoreFile(character: opal, roll: r)
            XCTAssertTrue(has(name), name); XCTAssertTrue(name.contains("_jelly8"), name)
        }
        for r in [0.1, 0.5, 0.9] {
            let name = JellyVoiceSet.sleepCooFile(character: opal, roll: r)
            XCTAssertTrue(has(name), name); XCTAssertTrue(name.contains("_jelly8"), name)
        }
        let lala = "lala_jelly\(JellyVoiceSet.borrowed(JellyVoiceSet.index(character: opal)))"
        XCTAssertEqual(lala, "lala_jelly8")
        XCTAssertTrue(has(lala))
    }

    func testNobodyElseMoved() {
        func oldIndex(_ c: Int) -> Int { min(max(c, 0), 6) + 1 }
        func oldBorrowed(_ n: Int) -> Int { n <= 4 ? n : (n == 5 ? 1 : (n == 6 ? 4 : 3)) }
        func oldBase(_ c: Int) -> Int { min(max(c, 0), 3) + 1 }
        func oldFile(_ c: Int, _ v: JellyVoice, _ variant: Int) -> String {
            let n = oldIndex(c)
            switch v {
            case .babble: return "babble_jelly\(n)"
            case .happy, .sad: return "chirp_jelly\(n)_\(v.rawValue)"
            default:
                let m = v.isBatchB ? oldBorrowed(n) : n
                return "\(v.rawValue)_jelly\(m)" + (v.hasVariants && m <= 4 && variant > 1 ? "_v\(min(variant, 3))" : "")
            }
        }
        for c in 0...26 where c != opal {
            for v in JellyVoice.allCases { for k in 1...3 {
                XCTAssertEqual(JellyVoiceSet.file(character: c, v, variant: k), oldFile(c, v, k), "char \(c) \(v) v\(k)")
            } }
            XCTAssertEqual(JellyVoiceSet.index(character: c), oldIndex(c), "index \(c)")
            XCTAssertEqual(JellyVoiceSet.baseIndex(character: c), oldBase(c), "baseIndex \(c)")
            for r in [0.0, 0.29, 0.3, 0.99] {
                XCTAssertEqual(JellyVoiceSet.snoreFile(character: c, roll: r), "snore_jelly\(oldBase(c))_\(r < 0.3 ? 2 : 1)", "snore \(c) \(r)")
            }
            for r in [0.0, 0.1, 0.34, 0.5, 0.67, 0.9, 0.99] {
                let want = "sleep_coo_jelly\(oldBase(c))_\(min(Int(r * 3.0), 2) + 1)"
                XCTAssertEqual(JellyVoiceSet.sleepCooFile(character: c, roll: r), want, "coo \(c) \(r)")
            }
        }
        for n in 0...12 where n != JellyVoiceSet.opalSet {
            XCTAssertEqual(JellyVoiceSet.borrowed(n), oldBorrowed(n), "borrowed \(n)")
        }
        XCTAssertEqual(JellyVoiceSet.count, 4)
        XCTAssertEqual(JellyVoiceSet.voiceSets, 7)
    }

    func testPreloadReachesOpalAndKeepsTheOldOrder() {
        XCTAssertTrue(JellyVoiceSet.voiceCharacters.contains(opal))
        XCTAssertTrue(JellyVoiceSet.snoreCharacters.contains(opal))
        XCTAssertEqual(Array(JellyVoiceSet.voiceCharacters.prefix(JellyVoiceSet.voiceSets)), Array(0..<JellyVoiceSet.voiceSets))
        XCTAssertEqual(Array(JellyVoiceSet.snoreCharacters.prefix(JellyVoiceSet.count)), Array(0..<JellyVoiceSet.count))
    }

    func testAll25OpalFilesAreBundled() {
        let names = ["chirp_jelly8_happy", "chirp_jelly8_sad", "babble_jelly8",
                     "curious_jelly8", "ooh_jelly8", "hum_jelly8", "giggle_jelly8", "hello_jelly8", "yawn_jelly8", "yay_jelly8", "uhoh_jelly8",
                     "wheee_jelly8", "tasty_jelly8", "aww_jelly8", "huh_jelly8", "pfft_jelly8", "lala_jelly8", "eep_jelly8", "mmhmm_jelly8", "nyoo_jelly8",
                     "snore_jelly8_1", "snore_jelly8_2", "sleep_coo_jelly8_1", "sleep_coo_jelly8_2", "sleep_coo_jelly8_3"]
        XCTAssertEqual(names.count, 25)
        for n in names { XCTAssertTrue(has(n), n) }
    }
}
