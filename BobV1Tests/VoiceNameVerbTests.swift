//
//  VoiceNameVerbTests.swift
//  Name vs command in the real coordinator (three Jelmiko, FocusAnyRun): a name highlights; a verb in the same hold, a LATER hold within 2.5 s, or before the name
//  makes that Jelmiko do it; a lone name is a highlight only; a verb with no name goes to the highlighted one; no hold ever runs a trick twice.
//

import XCTest
@testable import BobV1

@MainActor
private final class NClock { var t: Double = 100 }

@MainActor
private final class NoMic2: SpeechInput {
    var availability: VoiceAvailability = .ready
    var onLevel: ((Float) -> Void)?
    func prepare(contextualWords: [String]) async {}
    func start(contextualWords: [String]) async throws { throw SpeechInputError.notReady }
    func stop() async -> String { "" }
}

@MainActor
final class VoiceNameVerbTests: XCTestCase {
    nonisolated(unsafe) static var keep: [AnyObject] = []
    private var clock = NClock()

    private func make() -> FocusAnyRun {
        RoomLayout.dynamicBoxes = []
        let c = NClock(); clock = c
        let training = VoiceTraining(defaults: UserDefaults(suiteName: "VoiceNameVerbTests")!, persists: false, random: { 0.99 })          // the WORST roll: a valid command must still obey
        let v = VoiceCoordinator(training: training, input: NoMic2(), now: { c.t })
        let r = FocusAnyRun(voice: v); Self.keep.append(r)
        for id in 0..<3 { for k in NeedKind.allCases { r.care.needs(for: id).set(k, 1) } }
        r.run(0.3)
        return r
    }
    private func say(_ r: FocusAnyRun, _ words: String, gap: Double = 0.3) {
        r.run(Float(gap)); clock.t += gap
        XCTAssertTrue(r.care.voice.begin(), "the hold opens")
        for _ in 0..<20 { r.run(0.02); clock.t += 0.02 }
        r.care.voice.hear(words)
        r.run(0.3)
    }
    private func obeyed(_ r: FocusAnyRun, _ t: VoiceTrick) -> Int { r.care.voice.feedbackLog.filter { $0 == .obeyed(t) }.count }

    func testSixCases() {
        // 1. a lone name: highlights, no action, no error feedback
        var r = make()
        say(r, "Pip")
        XCTAssertEqual(r.care.targetJelly, 1, "1: the name highlights")
        XCTAssertTrue(r.care.voice.feedbackLog.isEmpty, "1: a lone name gives no action and no error: \(r.care.voice.feedbackLog)")
        // 2. the verb in a LATER hold (0.5 .. 2.5 s) goes to the highlighted one; the highlight stays
        for gap in [0.5, 1.5, 2.4] {
            r = make()
            say(r, "Pip"); say(r, "spin", gap: gap)
            XCTAssertEqual(obeyed(r, .spin), 1, "2: spin after a name, gap \(gap)")
            XCTAssertEqual(r.care.targetJelly, 1, "2: the highlight stays on Pip")
            XCTAssertEqual(VoiceCoordinator.running(r.care.brainFor(1)!), .spin, "2: Pip is the one spinning")
        }
        // 3. name + verb in one hold
        r = make(); say(r, "Pip spin")
        XCTAssertEqual(obeyed(r, .spin), 1, "3"); XCTAssertEqual(r.care.targetJelly, 1)
        // 4. verb before the name: highlight and do it at once
        r = make(); say(r, "spin Moss")
        XCTAssertEqual(obeyed(r, .spin), 1, "4"); XCTAssertEqual(r.care.targetJelly, 2, "4: Moss is highlighted")
        XCTAssertEqual(VoiceCoordinator.running(r.care.brainFor(2)!), .spin, "4: Moss spins")
        // 5. a verb with no name goes to the highlighted one
        r = make(); r.care.rosterPick(2, quietHop: true); r.run(0.5)
        say(r, "hop")
        XCTAssertEqual(obeyed(r, .hop), 1, "5"); XCTAssertEqual(VoiceCoordinator.running(r.care.brainFor(2)!), .hop, "5: the highlighted Moss hops")
        // 6. never twice: three holds, three runs; each hold exactly one
        r = make()
        say(r, "Pip sit"); say(r, "Moss hop"); say(r, "Pip spin")
        XCTAssertEqual(obeyed(r, .sit) + obeyed(r, .hop) + obeyed(r, .spin), 3, "6: \(r.care.voice.feedbackLog)")
    }

    /// A trick Pip was never given: the HUD says so (not a silent highlight), and Pip does no trick.
    func testUnknownTrickSaysSoOnTheHUD() {
        let r = make()
        r.care.jelly(1)?.training.unlocked = { $0 != .sing }
        say(r, "Pip sing")
        XCTAssertEqual(r.care.targetJelly, 1, "the name still highlights")
        XCTAssertEqual(obeyed(r, .sing), 0)
        XCTAssertEqual(r.care.voice.understood?.ok, false)
        XCTAssertTrue(r.care.voice.understood?.text.contains("doesn't know Sing yet") == true, "\(String(describing: r.care.voice.understood))")
    }

    /// "Alien" / "Violet" as REAL renames (the Adoption rename path), not nicknames.
    func testRealRenamesWork() {
        let saved = JellyRoster.names
        defer { JellyRoster.names = saved }
        JellyRoster.names[1] = "Alien"; JellyRoster.names[2] = "Violet"
        let r = make()
        for i in 0..<3 { r.care.jelly(i)?.training.unlocked = { _ in true } }          // moonwalk is a Shop trick: give them all of it
        say(r, "Alien do moonwalk")
        XCTAssertEqual(obeyed(r, .moonwalk), 1)
        XCTAssertEqual(r.care.targetJelly, 1)
        say(r, "Violet spin")
        XCTAssertEqual(obeyed(r, .spin), 1)
        XCTAssertEqual(r.care.targetJelly, 2)
        say(r, "Alien, sing!"); say(r, "moonwalk Violet")
        XCTAssertEqual(obeyed(r, .sing), 1); XCTAssertEqual(obeyed(r, .moonwalk), 2)
    }

    /// With nothing highlighted, a verb with no name is the room command: every Jelmiko who knows it does it (the existing behaviour).
    func testVerbWithNoNameAndNothingHighlighted() {
        let r = make()
        say(r, "spin")
        voiceTableLog("VOICESTRESS case 5b: no name, nothing highlighted, 'spin' -> obeyed \(obeyed(r, .spin)) feedback \(r.care.voice.feedbackLog) running \((0..<3).map { VoiceCoordinator.running(r.care.brainFor($0)!)?.rawValue ?? "-" })", file: "stress.txt")
    }
}
