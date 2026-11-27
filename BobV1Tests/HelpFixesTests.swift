//
//  HelpFixesTests.swift
//  Help and hint fixes (help-fixes-r1): the race help matches the pull control per course, a coach step with no control is skipped (never the JellyCoins caption),
//  the mic line follows Tap-to-talk, a hint is "seen" only once it was on the bar, the Play hint names the toy. (The tip card consuming its tap is in TipBookTests.)
//

import XCTest
@testable import BobV1

@MainActor
final class HelpFixesTests: XCTestCase {
    private func words(_ s: String) -> Int { s.split(separator: " ").count }

    // race help
    func testRaceHelpNamesThePullNeverTheFootButtons() {
        let all = [RaceHelp.tip] + CourseTier.allCases.map(\.blurb) + RaceHelp.rows.flatMap { [$0.1, $0.2] }
        for t in all {
            XCTAssertFalse(t.lowercased().contains("foot button"), t)
            XCTAssertFalse(t.lowercased().contains("left, right"), t)
            XCTAssertFalse(t.contains("Tap Jump"), t)
        }
        XCTAssertLessThanOrEqual(words(RaceHelp.tip), 16)
        XCTAssertTrue(RaceHelp.tip.contains("Pull down"))
        XCTAssertEqual(TipBook.card("race")?.body, RaceHelp.tip)
    }
    func testRaceBlurbPerCourse() {
        XCTAssertTrue(CourseTier.puddle.blurb.contains("Pull down"))
        for c in [CourseTier.splash, .wave] { XCTAssertTrue(c.blurb.contains("Green clears each bar"), c.title) }
        XCTAssertTrue(RaceHelp.rows.contains { $0.2.contains("hurdle") && $0.2.contains("green") })
        XCTAssertNotEqual(CourseTier.puddle.blurb, CourseTier.splash.blurb)
    }

    // coach skip (the tutorial: a step whose control is not on screen has nothing to ring, blocks nothing, never turns into a caption, and is moved past: TutorialTests.testAControlThatNeverShowsMovesOnOrGoesBack)
    func testSpotStepWithNoControlIsSkippedAndNeverDrawsACaption() {
        let targets = TutorialTargets()
        for s in Tutorial.homeSteps where s.kind == .spot && s.target != "jelmiko" {
            XCTAssertNil(targets.spot(for: s, size: CGSize(width: 393, height: 852)), "\(s.id): no control, no ring")
            XCTAssertFalse(TutorialPolicy.swallows(s, spot: nil, cardFrame: .zero, at: CGPoint(x: 5, y: 5)), "\(s.id): nothing is blocked when nothing is pointed at")
            XCTAssertEqual(s.kind, .spot); XCTAssertNil(s.button, "\(s.id) is never a caption card")
        }
    }

    // mic wording
    func testMicTipFollowsTapToTalk() {
        XCTAssertEqual(VoiceTip.text(tapMode: false), "Hold the mic to talk")
        XCTAssertEqual(VoiceTip.text(tapMode: true), "Tap the mic to talk")
        XCTAssertTrue(SupportText.sections.flatMap(\.paragraphs).contains { $0.contains("Tap to talk") && $0.contains("tap the mic") })
    }

    // seen only when shown
    func testHintIsSeenOnlyOnceItIsOnTheBar() {
        let c = GameMessageCenter(); c.autoSchedule = false
        let t0 = Date(timeIntervalSince1970: 2_000_000)
        var seen: [String] = []
        c.post("Busy line", priority: .normal, now: t0)
        c.post("A hint", priority: .chatty, identifier: "h", onShown: { seen.append("hint") }, now: t0 + 0.1)
        XCTAssertEqual(c.queue.map(\.text), ["A hint"]); XCTAssertTrue(seen.isEmpty, "queued is not seen")
        c.tick(now: t0 + 20)          // waited too long: dropped
        XCTAssertTrue(c.queue.isEmpty); XCTAssertTrue(seen.isEmpty, "a dropped hint is never marked seen")
        c.tick(now: t0 + 30); XCTAssertTrue(seen.isEmpty)
        // a hint that is replaced while on the bar was seen; one that gets shown calls once
        c.clear()
        c.post("Another hint", priority: .chatty, identifier: "h2", onShown: { seen.append("shown") }, now: t0 + 40)
        XCTAssertEqual(seen, ["shown"])
        // promoted from the queue: seen then
        c.post("Normal", priority: .normal, now: t0 + 40.1)
        c.post("Queued hint", priority: .chatty, identifier: "h3", onShown: { seen.append("promoted") }, now: t0 + 40.2)
        XCTAssertEqual(seen, ["shown"])
        c.tick(now: t0 + 44); c.tick(now: t0 + 48)
        XCTAssertTrue(seen.contains("promoted"))
        // dismissed while waiting: never seen
        var gone = false
        c.clear(); c.post("Busy", priority: .normal, now: t0 + 60)
        c.post("Hint x", priority: .chatty, identifier: "hx", onShown: { gone = true }, now: t0 + 60.1)
        c.dismiss(identifier: "hx", now: t0 + 60.2); c.tick(now: t0 + 70)
        XCTAssertFalse(gone)
    }

    // play hint
    func testPlayHintNamesTheToy() {
        XCTAssertEqual(PlayHint.text(toy: "Bouncy ball"), "Flick the bouncy ball to a Jelmiko")
        XCTAssertEqual(PlayHint.text(toy: "Frisbee"), "Flick the frisbee to a Jelmiko")
        XCTAssertEqual(PlayHint.text(toy: ""), "Flick the toy to a Jelmiko")
        XCTAssertFalse(PlayHint.text(toy: "Yarn ball").contains("the ball"))
    }
}
