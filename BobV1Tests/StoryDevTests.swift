//
//  StoryDevTests.swift
//  The evaluation set and the dump run end to end with the pre-written writer (what `-StoryDump` does, without the app): every sheet gets a line, nothing typed reaches a prompt.
//

import XCTest
@testable import BobV1

@MainActor
final class StoryDevTests: XCTestCase {
    func testTheEvaluationSetHasAtLeastTwentyFourSheetsAndRunsThroughTheChain() async {
        let sheets = StoryDev.evaluationSheets()
        XCTAssertGreaterThanOrEqual(sheets.count, 24)
        let memory = StoryMemory(salt: 1)
        let out = await StoryDev.evaluation(n: 1, sheets: sheets, writers: [TemplateWriter(memory: memory)], modelLine: "test", hasModel: false)
        XCTAssertTrue(out.contains("prompt leaks of a player-typed name: 0"), "a typed name reached a prompt")
        XCTAssertFalse(out.contains("LEAK"))
        XCTAssertFalse(out.contains("NONE") && out.components(separatedBy: "NONE").count > sheets.count, "most sheets must get a line")
        try? out.write(toFile: "/private/tmp/claude-501/-Users-dmarshall94-Desktop-BobV1/e0755ccf-aeea-4c40-b871-1f1d2b621362/scratchpad/story/test_eval.txt", atomically: true, encoding: .utf8)
    }

    func testTheDumpWritesBlurbsAndNotes() async {
        var f = StoryFacts(id: 1, name: "Berry", kindName: "Blush", kindAbout: "", shownParagraph: "Pale pink with rose patches.", mood: "")
        f.personality = "sleepy"; f.favouriteFood = "popsicle"; f.minutesSeen = 90
        f.housemates = [.init(id: 2, name: "Latte", kindName: "Moo", playShare: 0.8, togetherSeconds: 400, topEmote: "chase", mostPlayedWith: true)]
        let s = await StoryDev.dump(f, n: 3, chain: StoryChain([TemplateWriter(memory: StoryMemory(salt: 2))]))
        XCTAssertEqual(s.components(separatedBy: "about ").count - 1, 3)
        XCTAssertEqual(s.components(separatedBy: "note Berry>Latte").count - 1, 3)
        XCTAssertFalse(s.contains("NONE"))
    }
}
