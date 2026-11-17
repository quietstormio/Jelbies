//
//  RaceProgressPerRunnerTests.swift
//  2026-11-16 (the user, with the Jelly Race lobby showing "5 of 5 open" for a Jelmiko that had never raced: "Races need to be locked until you beat the previous one they need to progress"):
//  the courses open per runner. Each Jelmiko opens the next course only by winning (1st) the one below himself; the Puddle is always open; the Grand Champion
//  badge is unchanged.
//

import XCTest
@testable import BobV1

@MainActor
final class RaceProgressPerRunnerTests: XCTestCase {
    /// Runner `c` wins (1st) once on each course in `tiers`.
    private func win(_ b: TrophyBook, _ c: Int, _ tiers: [CourseTier]) { for t in tiers { b.recordRace(character: c, tier: t, place: 1) } }

    func testEachRunnerOpensTheNextCourseOnlyByWinningTheOneBelowHimself() {
        let b = TrophyBook(), p = CourseProgress()
        win(b, 1, CourseTier.allCases)          // the Grand Champion (Violet in the user's screenshot)
        p.bind(runner: 1, trophies: b)
        XCTAssertEqual(p.unlockedTiers, CourseTier.allCases, "the champion has every course")
        XCTAssertTrue(b.shelf(character: 1).wonEveryCourse, "her Grand Champion badge is unchanged")
        p.bind(runner: 2, trophies: b)
        XCTAssertEqual(p.unlockedTiers, [.puddle], "a runner who never raced has the Puddle only, whatever the champion won")
        XCTAssertEqual(p.requirement(.ripple), "Win on Puddle to open it")
        for _ in 0..<4 { b.recordRace(character: 2, tier: .puddle, place: 2) }
        XCTAssertEqual(p.unlockedTiers, [.puddle], "top-two finishes open nothing")
        b.recordRace(character: 2, tier: .puddle, place: 1)
        XCTAssertEqual(p.unlockedTiers, [.puddle, .ripple], "his own win on the Puddle opens his Ripple")
        XCTAssertFalse(p.unlocked(.splash), "only the next one")
        // the lobby asks for the Jelmiko it shows, whoever is bound
        XCTAssertTrue(p.unlocked(.tsunami, runner: 1, trophies: b))
        XCTAssertTrue(p.unlocked(.ripple, runner: 2, trophies: b)); XCTAssertFalse(p.unlocked(.splash, runner: 2, trophies: b))
        XCTAssertTrue(p.unlocked(.puddle, runner: 3, trophies: b)); XCTAssertFalse(p.unlocked(.ripple, runner: 3, trophies: b))
    }

    func testAPickTheNewRunnerHasNotOpenedFallsBackToHisHighestOpenCourse() {
        let b = TrophyBook(), p = CourseProgress()
        win(b, 1, CourseTier.allCases)
        win(b, 2, [.puddle, .ripple])
        p.bind(runner: 1, trophies: b)
        p.chosen = .tsunami
        p.bind(runner: 2, trophies: b)
        XCTAssertEqual(p.highestOpen, .splash)
        XCTAssertEqual(p.chosen, .splash, "runner 2 has the Puddle, Ripple and Splash: the Tsunami falls back to the Splash")
        p.bind(runner: 3, trophies: b)
        XCTAssertEqual(p.chosen, .puddle, "a runner who never raced falls back to the Puddle")
        p.bind(runner: 1, trophies: b)
        XCTAssertEqual(p.chosen, .puddle, "an open pick stays as it is")
    }

    /// The race from the lobby: the lobby binds the runner it shows; a course he has not opened falls back to his highest open one, and his own win announces his next course.
    func testTheRaceRunsOnTheRunnersHighestOpenCourseAndHisWinOpensTheNext() {
        struct Slow: RivalSource { func rivals(count: Int, player: RacerStats, playerTint: SIMD3<Float>, seed: UInt64) -> [Rival] { (0..<count).map { Rival(name: "R\($0)", tint: .one, stats: RacerStats(waddle: 0.15, focus: 1)) } } }
        let f = RaceFlow(); f.rivalSource = Slow(); f.cue = { _ in }; f.jingle = { _ in }; f.autoRate = 6; f.wallet = DropsWallet(persists: false)
        win(f.trophies, 1, CourseTier.allCases)
        f.progress.bind(runner: 1, trophies: f.trophies)
        f.courseTier = .tsunami          // the champion's pick
        f.progress.bind(runner: 2, trophies: f.trophies)          // (the lobby's CoursePicker now shows a runner who never raced)
        XCTAssertEqual(f.courseTier, .puddle, "the pick fell back with him")
        f.playerCharacter = 2          // (GameCare.beginRace sets the racer's character)
        f.begin(playerID: 0, name: "Alien", player: RacerStats(waddle: 0.9, focus: 1), playerTint: JellyRoster.tint(2), rivalCount: 2, seed: 5, course: .tsunami)
        XCTAssertEqual(f.course.tier, .puddle, "asked for the Tsunami, which is not his: he races on the Puddle")
        for _ in 0..<(60 * 120) { _ = f.tick(dt: 1 / 60, bodyFree: { _ in true }, bodyReady: { _ in true }); if f.hasResults { break } }
        XCTAssertTrue(f.hasResults)
        XCTAssertEqual(f.trophies.shelf(character: 2).raceRibbons(.puddle)[0], 1, "he won the Puddle")
        XCTAssertEqual(f.unlockedNow, .ripple, "his win opened his Ripple")
        f.goHome()
        for _ in 0..<400 { _ = f.tick(dt: 1 / 60, bodyFree: { _ in true }, bodyReady: { _ in true }) }
        XCTAssertFalse(f.active)
    }
}
