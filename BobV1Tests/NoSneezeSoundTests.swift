//
//  NoSneezeSoundTests.swift
//  Owner 2026-11-27, after hearing the clip: "remove that sound, never use it again anywhere". No catalog entry, clip file, caption, idle kind or play site may bring it back.
//  The words are assembled from pieces so this file itself never contains them.
//

import XCTest
@testable import BobV1

final class NoSneezeSoundTests: XCTestCase {
    private let words = ["ach" + "oo", "sne" + "ez"]

    private var repoRoot: URL { URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent() }

    func testNoCatalogEntryNamesIt() {
        for s in SFX.allCases {
            for w in words { XCTAssertFalse(s.rawValue.lowercased().contains(w), "SFX \(s) names \(w)") }
        }
    }

    func testNoIdleKindNamesIt() {
        for k in IdleKind.allCases {
            for w in words { XCTAssertFalse(k.rawValue.lowercased().contains(w), "idle kind \(k) names \(w)") }
        }
    }

    func testNoFileOrSourceLineNamesIt() throws {
        let src = repoRoot.appendingPathComponent("BobV1")
        guard FileManager.default.fileExists(atPath: src.path) else { throw XCTSkip("sources not reachable from the test host") }
        let en = FileManager.default.enumerator(at: src, includingPropertiesForKeys: nil)
        var hits: [String] = []
        while let u = en?.nextObject() as? URL {
            let name = u.lastPathComponent
            for w in words where name.lowercased().contains(w) { hits.append("file \(u.path)") }
            guard u.pathExtension == "swift", name != "StoryGuard.swift" else { continue }          // (StoryGuard's word list BANS the word in generated text)
            guard let text = try? String(contentsOf: u, encoding: .utf8) else { continue }
            for (i, line) in text.components(separatedBy: "\n").enumerated() {
                for w in words where line.lowercased().contains(w) { hits.append("\(name):\(i + 1)") }
            }
        }
        XCTAssertTrue(hits.isEmpty, "the removed sound is named again: \(hits.prefix(10))")
    }

    func testBathVoicePoolsAreAllCreatureVoices() {
        XCTAssertFalse(BathMoment.allCases.map(\.rawValue).contains("pop"))
        for m in BathMoment.allCases { XCTAssertFalse(m.pool.isEmpty, "\(m) has a voice") }
    }
}
