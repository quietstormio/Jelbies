//
//  GameMessageTests.swift
//  The one message bar's queue (UI/GameMessageCenter.swift): no overlap, merged repeats, priority, durations by length, VoiceOver once, the merged cuddle line,
//  and a source check that no file outside the bar draws its own message overlay.
//

import XCTest
@testable import BobV1

@MainActor
final class GameMessageTests: XCTestCase {
    private func make(tip: Bool = false) -> GameMessageCenter {
        let c = GameMessageCenter()
        c.autoSchedule = false
        c.tipShowing = { tip }
        return c
    }
    private let t0 = Date(timeIntervalSince1970: 1_000_000)

    func testTwoMessagesNeverOverlapTheSecondWaits() {
        let c = make()
        c.post("First line", now: t0); c.post("Second line", now: t0 + 0.1)
        XCTAssertEqual(c.current?.text, "First line"); XCTAssertEqual(c.queue.map(\.text), ["Second line"])
        c.tick(now: t0 + 2.0); XCTAssertEqual(c.current?.text, "First line")
        c.tick(now: t0 + 2.6); XCTAssertEqual(c.current?.text, "Second line"); XCTAssertTrue(c.queue.isEmpty)
        c.tick(now: t0 + 6); XCTAssertNil(c.current)
    }

    func testIdenticalRepeatsAreMerged() {
        let c = make()
        c.post("Not right now", now: t0); c.post("Not right now", now: t0 + 0.5)
        XCTAssertTrue(c.queue.isEmpty)
        c.tick(now: t0 + 3); XCTAssertNil(c.current)
        c.post("Not right now", now: t0 + 3.2)          // within the merge window of its last showing
        XCTAssertNil(c.current)
        c.post("Not right now", now: t0 + 5)
        XCTAssertEqual(c.current?.text, "Not right now")
    }

    func testRefusalReplacesChattyAndNormalDoesNot() {
        let c = make()
        c.post("heard something", priority: .chatty, now: t0)
        c.post("Alien is too hungry for tricks", priority: .important, now: t0 + 0.2)
        XCTAssertEqual(c.current?.text, "Alien is too hungry for tricks")
        c.post("A normal line", now: t0 + 0.4)
        XCTAssertEqual(c.current?.text, "Alien is too hungry for tricks", "a normal line does not push out a refusal")
        XCTAssertEqual(c.queue.map(\.text), ["A normal line"])
        let d = make()
        d.post("heard", priority: .chatty, now: t0); d.post("understood", now: t0 + 0.1)
        XCTAssertEqual(d.current?.text, "understood", "an understood line replaces the heard echo")
    }

    func testQueueIsOrderedByPriorityAndCapped() {
        let c = make()
        c.post("a", now: t0)
        c.post("b", priority: .chatty, now: t0); c.post("c", priority: .important, now: t0 + 0.1)
        XCTAssertEqual(c.current?.text, "a"); XCTAssertEqual(c.queue.map(\.text).first, "b", "an important line replaces only a chatty current one")
        for i in 0..<8 { c.post("line \(i)", now: t0 + 0.2) }
        XCTAssertLessThanOrEqual(c.queue.count, GameMessageCenter.queueCap)
    }

    func testDurationsByLength() {
        XCTAssertEqual(GameMessageCenter.duration(for: "Short"), 2.5, accuracy: 0.001)
        XCTAssertEqual(GameMessageCenter.duration(for: String(repeating: "x", count: 80)), 4.0, accuracy: 0.001)
        let mid = GameMessageCenter.duration(for: String(repeating: "x", count: 40))
        XCTAssertGreaterThan(mid, 2.5); XCTAssertLessThan(mid, 4.0)
        let c = make()
        c.post(String(repeating: "word ", count: 14), now: t0)
        c.tick(now: t0 + 3.0); XCTAssertNotNil(c.current, "a long line stays past 3 s")
        c.tick(now: t0 + 4.1); XCTAssertNil(c.current)
    }

    func testCaptionIsASecondPillNeverDroppedNorBlockingAMessage() {
        let c = make()
        c.post("Squish", priority: .caption, announce: false, now: t0); c.post("Chirp", priority: .caption, announce: false, now: t0 + 0.3)
        XCTAssertNil(c.current, "a caption alone takes the bar's place (the view draws it first), it is not a message"); XCTAssertEqual(c.caption?.text, "Chirp"); XCTAssertTrue(c.queue.isEmpty)
        c.post("A real line", now: t0 + 0.5)
        XCTAssertEqual(c.current?.text, "A real line"); XCTAssertEqual(c.caption?.text, "Chirp", "both show, the caption under the message")
        c.post("Pop", priority: .caption, announce: false, now: t0 + 0.6)
        XCTAssertEqual(c.current?.text, "A real line"); XCTAssertEqual(c.caption?.text, "Pop", "a newer caption replaces the older caption only")
        c.tick(now: t0 + 3.2); XCTAssertNil(c.caption)
        let tipUp = GameMessageCenter(); tipUp.autoSchedule = false; tipUp.tipShowing = { true }
        tipUp.post("Splash", priority: .caption, announce: false, now: t0); XCTAssertEqual(tipUp.caption?.text, "Splash", "not dropped while a tip is up")
    }

    func testStickyHintStaysUntilDismissedAndAnImportantLineReplacesIt() {
        let c = make()
        c.post("Rub to pet", priority: .chatty, identifier: "focus-hint", sticky: true, now: t0)
        c.tick(now: t0 + 30); XCTAssertEqual(c.current?.text, "Rub to pet", "stays past the normal duration")
        c.dismiss(identifier: "focus-hint"); XCTAssertNil(c.current)
        c.post("Hold the mic to talk", priority: .chatty, identifier: "voice-tip", sticky: true, now: t0 + 40)
        c.post("Alien is too hungry for tricks", priority: .important, now: t0 + 41)
        XCTAssertEqual(c.current?.text, "Alien is too hungry for tricks")
        c.post("Another", priority: .chatty, identifier: "x", sticky: true, now: t0 + 50)
        c.tick(now: t0 + 111); XCTAssertNil(c.current, "never longer than a minute")
    }

    func testTheMessageWaitsForATipCard() {
        var tip = true
        let c = GameMessageCenter(); c.autoSchedule = false; c.tipShowing = { tip }
        c.post("Hello", now: t0); XCTAssertNil(c.current); XCTAssertEqual(c.queue.count, 1)
        tip = false; c.tick(now: t0 + 1); XCTAssertEqual(c.current?.text, "Hello")
        let d = GameMessageCenter(); d.autoSchedule = false; d.tipShowing = { true }
        d.post("Old", now: t0); d.tick(now: t0 + 9); XCTAssertTrue(d.queue.isEmpty, "stale after a long wait")
    }

    func testVoiceOverHearsEachLineOnceWhenItAppears() {
        A11yAnnounce.resetForTests(); defer { A11yAnnounce.resetForTests() }
        var said: [String] = []
        A11yAnnounce.sink = { t, _ in said.append(t) }
        let c = make()
        c.post("Heads up", now: t0); c.post("Heads up", now: t0 + 0.2); c.post("Queued line", now: t0 + 0.3)
        XCTAssertEqual(said, ["Heads up"], "merged repeat and the waiting line are silent until shown")
        c.tick(now: t0 + 2.6); XCTAssertEqual(said, ["Heads up", "Queued line"])
        c.post("Quiet", announce: false, now: t0 + 9); XCTAssertEqual(said.count, 2, "captions and voice lines opt out")
    }

    func testParkLineGoesWithTheOutingButAHomeLineStays() {
        let c = make()
        c.post("A line said at the park", scope: .outing, now: t0)
        c.post("Next", scope: .none, now: t0 + 0.1)
        c.dismiss(scope: .outing)
        XCTAssertEqual(c.current?.text, "Next", "the park line is not shown back at home")
    }

    func testCuddleLineIsOneMergedMessage() {
        typealias E = (name: String, hungry: Bool, thirsty: Bool)
        let all: [E] = [("Violet", true, true), ("Alien", true, true), ("Pogo", true, true)]
        XCTAssertEqual(GameCare.cuddleGroupLine(all), "Violet, Alien and Pogo are too hungry and thirsty to cuddle")
        XCTAssertEqual(GameCare.cuddleGroupLine(Array(all.prefix(2))), "Violet and Alien are too hungry and thirsty to cuddle")
        XCTAssertEqual(GameCare.cuddleGroupLine([("Pogo", true, false)]), "Pogo is too hungry to cuddle")
        XCTAssertEqual(GameCare.cuddleGroupLine([("A", true, false), ("B", false, true)]), "A and B are too hungry or thirsty to cuddle")
        XCTAssertNil(GameCare.cuddleGroupLine([]))
    }

    func testBarIsTopLeftUnderTheHudRow() {
        let size = CGSize(width: 402, height: 874)
        XCTAssertEqual(GameMessageLayout.left(safeLeft: 0), 16)
        XCTAssertEqual(GameMessageLayout.width(size), 370)
        XCTAssertLessThanOrEqual(GameMessageLayout.width(CGSize(width: 874, height: 402), safeLeft: 62), 520)
        GameMessageLayout.hudBottom = 60
        XCTAssertEqual(GameMessageLayout.top(safeTop: 62), 122)
    }

    /// No file outside the bar draws a message pill with its own background: the transient-message overlays are gone from the home / park / town sources.
    func testNoOverlayOutsideTheBarDrawsItsOwnMessageBackground() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("BobV1")
        let fm = FileManager.default
        guard let en = fm.enumerator(at: root, includingPropertiesForKeys: nil) else { return XCTFail("no sources") }
        let banned = ["park-toast", "groom-toast", "cafe-toast", "shop-bought-toast", "cuddle-notice", "voice-understood", "voice-heard", "camp-note", "photo-notice", "focus-hint", "welcome-home"]
        var offenders: [String] = []
        for case let u as URL in en where u.pathExtension == "swift" {
            let name = u.lastPathComponent
            if name == "GameMessageCenter.swift" { continue }
            let text = try String(contentsOf: u, encoding: .utf8)
            for id in banned {
                for (i, line) in text.split(separator: "\n", omittingEmptySubsequences: false).enumerated() where line.contains(".accessibilityIdentifier(\"\(id)\")") {
                    offenders.append("\(name):\(i + 1) \(id)")
                }
            }
        }
        // the pattern of an ad-hoc overlay: `if let x = <something>.toast / .refusal / .notice` (or the old boughtToast) in a view. The allowlist is the second pass (competition screens, the bath, the world label above a head).
        let secondPass = ["Show/", "Bath/", "Volley/", "Race/", "Needs/RefusalLabel.swift", "Groomer/GroomChrome.swift"]
        let rx = try NSRegularExpression(pattern: #"if let \w+ = \w+(\.\w+)*\.(toast|refusal|notice)\b(?!\()|boughtToast"#)
        guard let en2 = fm.enumerator(at: root, includingPropertiesForKeys: nil) else { return }
        for case let u as URL in en2 where u.pathExtension == "swift" {
            let rel = u.path.replacingOccurrences(of: root.path + "/", with: "")
            if rel == "UI/GameMessageCenter.swift" || secondPass.contains(where: { rel.hasPrefix($0) }) { continue }
            let text = try String(contentsOf: u, encoding: .utf8)
            if rx.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil { offenders.append("\(rel): own message overlay") }
        }
        XCTAssertTrue(offenders.isEmpty, "own overlays left: \(offenders)")
    }
}
