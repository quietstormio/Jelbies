//
//  TrickThreeTests.swift
//  Three more Shop tricks built from existing emotes: Take a bow (politeBow), Belly drum (bellyDrum), Dizzy spin (the spin, then the dizzy wobble).
//  The shop rows, the moves, the voice words (longest match: plain "spin" stays the spin), and the real coordinator running them.
//

import XCTest
import UIKit
@testable import BobV1

@MainActor
private final class T3Clock { var t: Double = 100 }
@MainActor
private final class T3NoMic: SpeechInput {
    var availability: VoiceAvailability = .ready
    var onLevel: ((Float) -> Void)?
    func prepare(contextualWords: [String]) async {}
    func start(contextualWords: [String]) async throws { throw SpeechInputError.notReady }
    func stop() async -> String { "" }
}

@MainActor
final class TrickThreeTests: XCTestCase {
    nonisolated(unsafe) static var keep: [AnyObject] = []
    private var clock = T3Clock()
    private var suites: [String] = []
    override func tearDown() { for n in suites { UserDefaults.standard.removePersistentDomain(forName: n) }; suites = [] }

    func testShopRows() {
        let want: [(VoiceTrick, String, Int, TrickScope, Int)] = [(.bow, "Take a bow", 1, .everyone, 40), (.bellyDrum, "Belly drum", 2, .perJelbie, 70), (.dizzySpin, "Dizzy spin", 2, .perJelbie, 70)]
        for (t, name, stars, scope, price) in want {
            let d = TrickCatalog.def(t)
            XCTAssertEqual(d?.name, name); XCTAssertEqual(d?.stars, stars); XCTAssertEqual(d?.scope, scope); XCTAssertEqual(d?.price, price)
            XCTAssertFalse(TrickCatalog.isDefault(t)); XCTAssertTrue(ShowTrickInfo.stageTricks.contains(t))
            XCTAssertNotNil(VoiceCoordinator.idleKind(for: t), "\(t) has a move")
            let item = StoreCatalog.item("trick-\(t.rawValue)")
            XCTAssertNotNil(item, "\(t) is in the Shop's Tricks tab"); XCTAssertFalse(item?.description.isEmpty ?? true)
            XCTAssertFalse(ShowTrickInfo.menu(learned: Set<VoiceTrick>()).contains(t), "\(t) is not on the menu until it is owned")
            XCTAssertTrue(ShowTrickInfo.menu(learned: [t] as Set<VoiceTrick>).contains(t), "\(t) is listed once owned")
            XCTAssertNotNil(UIImage(systemName: ShowTrickInfo.symbol(t)), "\(t) icon exists")
        }
        XCTAssertEqual(VoiceCoordinator.idleKind(for: .bow), .politeBow)
        XCTAssertEqual(VoiceCoordinator.idleKind(for: .bellyDrum), .bellyDrum)
        XCTAssertEqual(VoiceCoordinator.idleKind(for: .dizzySpin), .tail)
        XCTAssertEqual(TrickCatalog.forSale.count, Set(TrickCatalog.forSale.map(\.trick)).count, "no trick sold twice")
    }

    func testBuyingWorks() {
        let w = DropsWallet(persists: false); w.add(500, silent: true)
        let n = "TrickThreeTests.\(UUID().uuidString)"; suites.append(n)
        let b = StoreBook(wallet: w, persists: false, defaults: UserDefaults(suiteName: n)!, key: "TrickThreeTests.book"); Self.keep.append(b)
        XCTAssertEqual(b.buyTrick(.bow, for: nil), .bought); XCTAssertTrue(b.knows(.bow, character: 0)); XCTAssertTrue(b.knows(.bow, character: 2))
        XCTAssertEqual(b.buyTrick(.bellyDrum, for: 1), .bought); XCTAssertTrue(b.knows(.bellyDrum, character: 1)); XCTAssertFalse(b.knows(.bellyDrum, character: 0))
        XCTAssertEqual(b.buyTrick(.dizzySpin, for: 2), .bought); XCTAssertFalse(b.knows(.dizzySpin, character: 1))
        XCTAssertEqual(w.count, 500 - 40 - 70 - 70)
    }

    private func book(knows: @escaping (VoiceTrick) -> Bool = { _ in true }) -> VoiceTraining {
        let n = "TrickThreeTests.\(UUID().uuidString)"; suites.append(n)
        let v = VoiceTraining(defaults: UserDefaults(suiteName: n)!, random: { 0 })
        v.names.roster = [0]; XCTAssertTrue(v.names.addNickname("alien", for: 0)); v.unlocked = knows
        return v
    }
    private let words: [(VoiceTrick, [String])] = [
        (.bow, ["bow", "take a bow", "take bow"]),
        (.bellyDrum, ["drum", "belly drum", "drum your belly", "drum on your belly", "belly-drum", "bellydrum"]),
        (.dizzySpin, ["dizzy", "dizzy spin", "dizzy-spin", "dizzyspin"]),
    ]

    func testVoiceWordsEveryPhrasing() {
        var bad: [String] = []
        for (t, ws) in words { for w in ws { for said in ["Alien \(w)", "Alien do \(w)", "Alien do the \(w)", "\(w) Alien", "Alien, \(w)!", "Alien can you please do a \(w) now", "Alien, \(w) for me", "ALIEN \(w.uppercased())"] {
            let r = book().decide(transcript: said, runningMove: nil, mood: .happy, session: 1)
            if r != .perform(t) { bad.append("\(t): \"\(said)\" -> \(r)") }
            let u = book(knows: { $0 != t }).decide(transcript: said, runningMove: nil, mood: .happy, session: 1)
            if u != .dontKnow(t) { bad.append("\(t) not owned: \"\(said)\" -> \(u)") }
            let g = book().decide(transcript: said, runningMove: nil, mood: .grumpy, session: 1)
            if g != .grumpyIgnore { bad.append("\(t) grumpy: \"\(said)\" -> \(g)") }
        } } }
        XCTAssertTrue(bad.isEmpty, bad.joined(separator: "\n"))
    }

    func testPlainSpinStaysTheSpinAndNothingElseMoved() {
        for said in ["Alien spin", "Alien do a spin", "Alien twirl", "spin Alien"] { XCTAssertEqual(book().decide(transcript: said, runningMove: nil, mood: .happy, session: 1), .perform(.spin), said) }
        // a Jelmiko that owns spin but not the dizzy spin is told so, it does not just spin
        XCTAssertEqual(book(knows: { $0 != .dizzySpin }).decide(transcript: "Alien dizzy spin", runningMove: nil, mood: .happy, session: 1), .dontKnow(.dizzySpin))
        // the wardrobe and the places are not the tricks
        for said in ["Alien wear the bow", "Alien put a bow on", "Alien put on a bow", "Alien sit on the drum", "Alien hop on the drum"] {
            let r = book().decide(transcript: said, runningMove: nil, mood: .happy, session: 1)
            XCTAssertNotEqual(r, .perform(.bow), said); XCTAssertNotEqual(r, .perform(.bellyDrum), said)
        }
    }

    // MARK: the real coordinator (three Jelmiko)

    private func make() -> FocusAnyRun {
        RoomLayout.dynamicBoxes = []
        let c = T3Clock(); clock = c
        let training = VoiceTraining(defaults: UserDefaults(suiteName: "TrickThreeTests")!, persists: false, random: { 0.99 })
        let v = VoiceCoordinator(training: training, input: T3NoMic(), now: { c.t })
        let r = FocusAnyRun(voice: v); Self.keep.append(r)
        for id in 0..<3 { for k in NeedKind.allCases { r.care.needs(for: id).set(k, 1) }; r.care.jelly(id)?.training.unlocked = { _ in true } }
        r.run(0.3)
        return r
    }
    private func say(_ r: FocusAnyRun, _ words: String) {
        r.run(0.3); clock.t += 0.3
        XCTAssertTrue(r.care.voice.begin(), "the hold opens")
        for _ in 0..<20 { r.run(0.02); clock.t += 0.02 }
        r.care.voice.hear(words)
        r.run(0.3)
    }

    func testCoordinatorRunsEachTrick() {
        var r = make()
        say(r, "Pip take a bow")
        XCTAssertTrue(r.care.voice.feedbackLog.contains(.obeyed(.bow)), "\(r.care.voice.feedbackLog)")
        XCTAssertTrue(r.run(3) { r.care.brainFor(1)?.idleState.kind == .politeBow }, "Pip bows")
        r = make(); say(r, "Moss belly drum")
        XCTAssertTrue(r.care.voice.feedbackLog.contains(.obeyed(.bellyDrum)))
        XCTAssertTrue(r.run(3) { r.care.brainFor(2)?.idleState.kind == .bellyDrum }, "Moss drums")
        // the dizzy spin: a spin first, then ALWAYS the dizzy wobble; plain spin does not wobble on command
        for _ in 0..<4 {
            r = make(); say(r, "Pip dizzy spin")
            XCTAssertTrue(r.care.voice.feedbackLog.contains(.obeyed(.dizzySpin)))
            var sawSpin = false
            XCTAssertTrue(r.run(14) { let k = r.care.brainFor(1)?.idleState.kind; if k == .tail { sawSpin = true }; return sawSpin && k == .dizzyWobble }, "Pip spins, then goes dizzy (spin seen: \(sawSpin))")
        }
    }

    func testUnknownBowSaysSoOnTheHUD() {
        let r = make()
        r.care.jelly(1)?.training.unlocked = { $0 != .bow }
        say(r, "Pip take a bow")
        XCTAssertTrue(r.care.voice.understood?.text.contains("doesn't know Take a bow yet") == true, "\(String(describing: r.care.voice.understood))")
        XCTAssertFalse(r.care.voice.feedbackLog.contains(.obeyed(.bow)))
    }
}
