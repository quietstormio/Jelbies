//
//  BestHugTests.swift
//  The best-friends Hug (BlobBrain+BestHug.swift, GameCare+BestHug.swift): the words, the lock, the reveal, and the motion's own numbers. The feet / one-piece invariants are in
//  EmoteFeetTests.testBestHug (job "trick bestHug" in OnePieceInvariantTests).
//

import XCTest
import simd
@testable import BobV1

@MainActor
final class BestHugTests: XCTestCase {
    nonisolated(unsafe) static var keep: [AnyObject] = []
    private var suites: [String] = []
    private var savedProvider: ((Int) -> Bool)?
    override func setUp() { super.setUp(); EmoteFeetTests.reset(); savedProvider = BestHug.provider }
    override func tearDown() {
        BestHug.provider = savedProvider
        for n in suites { UserDefaults.standard.removePersistentDomain(forName: n) }
        suites = []
        EmoteFeetTests.reset(); super.tearDown()
    }

    private func book(unlocked: @escaping (VoiceTrick) -> Bool) -> VoiceTraining {
        let n = "BestHugTests.\(UUID().uuidString)"; suites.append(n)
        let v = VoiceTraining(defaults: UserDefaults(suiteName: n)!, persists: false, random: { 0.99 })
        v.names.roster = [0, 1, 2]
        v.unlocked = unlocked
        return v
    }

    // MARK: voice

    func testNamePlusHugRunsTheTrickWithNoMenuAndTheBareNameStillOpensIt() {
        let v = book { _ in true }
        let name = JellyRoster.names[1]
        for said in ["\(name) hug", "\(name) give me a hug", "\(name) hug me", "hug me \(name)", "hey \(name) can you give me a hug"] {
            let d = v.decideFull(transcript: said, runningMove: nil, mood: .happy, session: 1)
            XCTAssertEqual(d.reaction, .perform(.hug), "\"\(said)\"")
            XCTAssertFalse(d.nameOnly, "no menu: \"\(said)\"")
        }
        let bare = v.decideFull(transcript: name, runningMove: nil, mood: .happy, session: 1)
        XCTAssertTrue(bare.nameOnly, "the bare name opens the menu")
        XCTAssertNotEqual(bare.reaction, .perform(.hug))
    }

    func testWhoWantsAHugIsStillTheQuestion() {
        let v = book { _ in true }
        let d = v.decideFull(transcript: "who wants a hug", runningMove: nil, mood: .happy, session: 1)
        XCTAssertNotEqual(d.reaction, .perform(.hug))
    }

    func testLockedHugIsTheDontKnowShrug() {
        let v = book { $0 != .hug }
        let d = v.decideFull(transcript: "\(JellyRoster.names[0]) give me a hug", runningMove: nil, mood: .happy, session: 1)
        XCTAssertEqual(d.reaction, .dontKnow(.hug))
    }

    // MARK: the lock

    func testKnownOnlyWhenTheGateIsOpen() {
        let store = StoreBook(wallet: DropsWallet(persists: false), persists: false, defaults: UserDefaults(suiteName: { let n = "BestHugTests.\(UUID().uuidString)"; suites.append(n); return n }())!, key: "BestHugTests.book")
        Self.keep.append(store)
        BestHug.provider = { _ in false }
        XCTAssertFalse(store.knows(.hug, character: 0))
        BestHug.provider = { $0 == 1 }
        XCTAssertTrue(store.knows(.hug, character: 1)); XCTAssertFalse(store.knows(.hug, character: 0), "per character")
        XCTAssertFalse(TrickCatalog.forSale.contains { $0.trick == .hug }, "never sold")
        XCTAssertFalse(ShowTrickInfo.stageTricks.contains(.hug), "never on the stage")
    }

    func testTheHugIsInNoRandomPool() {
        // the hug rides the hula, flagged by `bestHug.go`: a hula that starts without the flag (the Show, a voice "hula") is the plain one
        let r = MotionRig(game: true)
        r.brain.idleForced = true
        XCTAssertTrue(r.brain.idleStart(.hula, r.sim))
        XCTAssertFalse(r.brain.isBestHugging)
        r.brain.abortAll(r.sim, r.skinner)
        r.brain.bestHug.go = true
        XCTAssertTrue(r.brain.idleStart(.hula, r.sim))
        XCTAssertTrue(r.brain.isBestHugging)
        XCTAssertFalse(r.brain.bestHug.go, "the flag is consumed")
    }

    func testRevealMemoryIsPerCharacterAndPurged() {
        let d = UserDefaults(suiteName: { let n = "BestHugTests.\(UUID().uuidString)"; suites.append(n); return n }())!
        XCTAssertFalse(BestHug.revealShown(5, d))
        BestHug.markRevealShown(5, d)
        XCTAssertTrue(BestHug.revealShown(5, d)); XCTAssertFalse(BestHug.revealShown(6, d))
        StartFlow.resetCharacterState(5, d)
        XCTAssertFalse(BestHug.revealShown(5, d), "purged with the creature's other data")
    }

    // MARK: the motion

    func testHugOpensTheArmsSqueezesWithHeartsAndHandsBackClean() {
        let r = MotionRig(game: true)
        r.brain.idleForced = true; r.brain.commanded = true
        r.brain.bestHug.go = true
        XCTAssertTrue(r.brain.idleStart(.hula, r.sim))
        var started = false, maxHearts = 0, hearts = 0, big = false, buzzes = 0, maxPitch: Float = 0, minSquash: Float = 9, maxRoll: Float = 0, armsOpenEl: Float = 0, armsClosedEl: Float = 9
        r.run(8, until: {
            if r.brain.idleState.kind == nil && started { return true }
            if r.brain.idleState.phase >= 1 { started = true }
            return false
        }, each: {
            let b = r.brain
            guard b.idleState.kind == .hula, b.idleState.phase >= 1 else { return }
            hearts += b.bestHug.hearts; b.bestHug.hearts = 0
            if b.bestHug.bigHeart { big = true; b.bestHug.bigHeart = false }
            if b.bestHug.buzz > 0 { buzzes += 1; b.bestHug.buzz = 0 }
            maxHearts = max(maxHearts, hearts)
            maxPitch = max(maxPitch, b.pitch); minSquash = min(minSquash, b.squash); maxRoll = max(maxRoll, abs(b.roll))
            let t = b.idleState.phaseT
            if abs(t - BestHugTuning.openEnd) < 0.02 { armsOpenEl = max(armsOpenEl, b.armDirEl[0]) }
            if abs(t - (BestHugTuning.squeezeStart + 0.5)) < 0.02 { armsClosedEl = min(armsClosedEl, b.armDirEl[0]) }
        })
        XCTAssertTrue(started); XCTAssertNil(r.brain.idleState.kind, "back to idle")
        XCTAssertGreaterThanOrEqual(hearts, 6, "hearts all along the squeeze (a normal cuddle gives one per 0.6 to 1 s)")
        XCTAssertTrue(big, "one bigger heart at the end"); XCTAssertGreaterThanOrEqual(buzzes, 3, "the squeeze purrs")
        XCTAssertGreaterThan(maxPitch, 0.2, "leans to the glass"); XCTAssertLessThan(minSquash, 0.97, "pressed a little"); XCTAssertGreaterThan(maxRoll, 0.05, "the slow sway")
        XCTAssertGreaterThan(armsOpenEl, armsClosedEl + 0.5, "arms open wide, then closed in")
        XCTAssertEqual(r.brain.armDirW, 0); XCTAssertFalse(r.brain.isBestHugging); XCTAssertFalse(r.sim.hasNonFinite())
    }

    func testReduceMotionKeepsTheHeartsButNotTheSway() {
        let was = A11ySettings.shared.reduceMotionInApp
        A11ySettings.shared.reduceMotionInApp = true
        defer { A11ySettings.shared.reduceMotionInApp = was }
        let r = MotionRig(game: true)
        r.brain.idleForced = true; r.brain.commanded = true
        r.brain.bestHug.go = true
        XCTAssertTrue(r.brain.idleStart(.hula, r.sim))
        var started = false, hearts = 0, maxRoll: Float = 0
        r.run(8, until: { if r.brain.idleState.kind == nil && started { return true }; if r.brain.idleState.phase >= 1 { started = true }; return false }, each: {
            guard r.brain.idleState.kind == .hula, r.brain.idleState.phase >= 1 else { return }
            hearts += r.brain.bestHug.hearts; r.brain.bestHug.hearts = 0
            maxRoll = max(maxRoll, abs(r.brain.roll))
        })
        XCTAssertGreaterThanOrEqual(hearts, 6); XCTAssertLessThan(maxRoll, 0.05, "no sway")
    }
}
