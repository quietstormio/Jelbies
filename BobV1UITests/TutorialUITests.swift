//
//  TutorialUITests.swift
//  The tutorial on the real app (Release, simulator). Dev launch arguments work on the simulator only.
//   - testTrueFirstLaunchTapsEverySpotlightToTheEnd: a fresh install, menu > New Game > opening > Spring > bring home, then REAL taps through every spotlight (the middle of the ring), a negative tap outside
//     the ring at every spotlight step that must do nothing, to the end. Run it after `xcrun simctl uninstall <udid> <bundle id>` so the container is clean.
//   - testSkipAtEveryStep: each step (jumped to with -TutorialStep) has a Skip that ends it for good.
//   - testKillAndRelaunchResumes: terminate mid-tutorial, relaunch with NO reset arguments, it resumes at the chapter start.
//   - testStills: one picture per card kind in the configuration TUT_CONFIG names (portrait, landscape, ax, ipad) into TUT_OUT.
//

import XCTest

final class TutorialUITests: XCTestCase {
    private var out = ""
    private var app: XCUIApplication!
    private var log: [String] = []
    private let base = ["-SkipIntro", "1", "-Mute", "1"]

    override func setUp() {
        continueAfterFailure = false
        out = ProcessInfo.processInfo.environment["TUT_OUT"] ?? NSTemporaryDirectory() + "tut"
        try? FileManager.default.createDirectory(atPath: out, withIntermediateDirectories: true)
    }
    override func tearDown() { XCUIDevice.shared.orientation = .portrait }

    // MARK: helpers
    private func el(_ id: String) -> XCUIElement { app.descendants(matching: .any).matching(identifier: id).firstMatch }
    private func centre(_ e: XCUIElement) -> XCUICoordinate {
        let f = e.frame
        return app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: f.midX, dy: f.midY))
    }
    private var roomT0: Date?
    private func note(_ s: String) {
        log.append(s)
        let t = roomT0.map { String(format: "[game %3.0fs] ", Date().timeIntervalSince($0)) } ?? ""
        let line = t + s + "\n", p = out + "/tutorial_log.txt"
        if let h = FileHandle(forWritingAtPath: p) { h.seekToEndOfFile(); h.write(line.data(using: .utf8)!); try? h.close() } else { try? line.write(toFile: p, atomically: true, encoding: .utf8) }
    }
    private func shot(_ name: String) {
        sleep(1)          // the card fades and the ring settles
        try? XCUIScreen.main.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: out + "/\(name).png"))
        note("shot \(name)")
    }
    /// The text of the card now up (the step's line, or the intro's title).
    private var cardText: String {
        let t = app.staticTexts["coach-text"]
        if t.exists { return t.label }
        let h = app.staticTexts["coach-title"]
        return h.exists ? h.label : ""
    }
    private func waitText(_ text: String, timeout: TimeInterval = 20, file: StaticString = #filePath, line: UInt = #line) {
        let end = Date().addingTimeInterval(timeout)
        while Date() < end { if cardText == text || (app.staticTexts["coach-title"].exists && app.staticTexts["coach-title"].label == text) { note("step: \(text)"); return }; usleep(300_000) }
        shot("FAIL_waiting_\(text.prefix(20).replacingOccurrences(of: " ", with: "_"))")
        XCTFail("the card never said '\(text)' (it says '\(cardText)')", file: file, line: line)
    }
    private func tapEl(_ id: String, wait: TimeInterval = 10, file: StaticString = #filePath, line: UInt = #line) {
        let e = el(id)
        guard e.waitForExistence(timeout: wait) else { shot("FAIL_missing_\(id)"); XCTFail("missing \(id)", file: file, line: line); return }
        centre(e).tap(); note("tapped \(id)")
    }
    /// A tap far from the ring and the card (the floor's far corner): must change nothing.
    private func negativeTap(_ what: String) {
        let before = cardText
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.62)).tap()
        sleep(1)
        XCTAssertEqual(cardText, before, "a tap outside the ring moved the step (\(what))")
        note("negative tap ok: \(what)")
    }
    private func launch(_ extra: [String], orientation: UIDeviceOrientation = .portrait) {
        app = XCUIApplication()
        XCUIDevice.shared.orientation = orientation
        app.launchArguments += base + extra
        app.launch()
    }
    private let fresh = ["-NewGame", "bob", "-MainMenu", "0", "-ClockHour", "12", "-TipsReset", "1", "-BlobNoWander", "1"]

    // MARK: 1. a true first launch, every spotlight tapped to the end
    func testTrueFirstLaunchTapsEverySpotlightToTheEnd() { walk(trueFirst: true, cfg: "first", orient: .portrait, extra: []) }

    /// The whole walkthrough with real taps. `trueFirst`: from a fresh container through the menu, the opening, the Spring and the naming page (the run-in too); else from a new game with the tutorial begun at the intro.
    private func walk(trueFirst: Bool, cfg: String, orient: UIDeviceOrientation, extra: [String]) {
        func shot(_ n: String) { self.shot("\(cfg)_\(n)") }
        if trueFirst {
        app = XCUIApplication()
        XCUIDevice.shared.orientation = orient
        app.launchArguments += base + ["-ClockHour", "12", "-BlobNoWander", "1"] + extra          // no -NewGame: the container is the fresh one
        app.launch()
        let start = el("menu-start")
        XCTAssertTrue(start.waitForExistence(timeout: 90), "no main menu: the container is not fresh")
        sleep(2); centre(start).tap(); note("New Game")
        let skip = el("opening-skip")
        _ = skip.waitForExistence(timeout: 40); sleep(3)
        if skip.exists { centre(skip).tap() }
        let pick = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Pick your'")).firstMatch
        XCTAssertTrue(pick.waitForExistence(timeout: 60)); sleep(2); centre(pick).tap(); note("picked")
        sleep(2)
        let this = app.descendants(matching: .any).matching(NSPredicate(format: "label == 'This one!'")).firstMatch
        XCTAssertTrue(this.waitForExistence(timeout: 20)); centre(this).tap()
        let bring = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Bring'")).firstMatch
        XCTAssertTrue(bring.waitForExistence(timeout: 20)); sleep(2); centre(bring).tap(); note("brought home"); roomT0 = Date()

        // the run-in: only Skip is up
        XCTAssertTrue(el("tutorial-skip").waitForExistence(timeout: 60), "no Skip during the run-in")
        shot("01_runin")
        } else {
            launch(fresh + ["-TutorialAuto", "1", "-TutorialStep", "intro"] + extra, orientation: orient)
        }
        // the intro
        XCTAssertTrue(el("tutorial-button").waitForExistence(timeout: 60), "no intro card")
        let title = app.staticTexts["coach-title"].label
        XCTAssertTrue(title.hasPrefix("This is your Jelmiko, "), title)
        let name = String(title.dropFirst("This is your Jelmiko, ".count).dropLast())
        shot("02_intro")
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap(); sleep(1)
        XCTAssertTrue(el("tutorial-button").exists, "a tap on the ring does nothing on the intro card")
        tapEl("tutorial-button")
        // 1 Cuddle
        waitText("Double tap \(name) to pick them.")
        shot("03_tap_jelmiko")
        negativeTap("pick")
        centre(el("jelbie-0")).doubleTap()
        waitText("Tap Come here for a cuddle.")
        shot("04_come_here")
        negativeTap("Tap Come here")
        tapEl(el("hud-come").exists ? "hud-come" : "hud-call-all")
        waitText("Rub \(name)'s head. Cuddles make them happy.", timeout: 40)
        shot("05_rub")
        let a = app.coordinate(withNormalizedOffset: CGVector(dx: 0.42, dy: 0.45)), b = app.coordinate(withNormalizedOffset: CGVector(dx: 0.58, dy: 0.45))
        for _ in 0..<4 { a.press(forDuration: 0.5, thenDragTo: b, withVelocity: .slow, thenHoldForDuration: 0.2); if cardText == "Tap Let \(name) go when you're done." { break } }
        waitText("Tap Let \(name) go when you're done.")
        shot("06_release")
        tapEl("focus-release")
        // 2 Care: selecting a Jelmiko opens the menu, so after the cuddle it is usually open already ("Tap the heart to close"); when it is closed the first card asks for the heart
        let closeLine = "Care, dress-up and more are in here. Tap the heart to close."
        let openLine = "Tap the heart to care for \(name)."
        let end = Date().addingTimeInterval(40)
        while Date() < end, cardText != closeLine, cardText != openLine { usleep(300_000) }
        if cardText == openLine {
            shot("07_heart")
            negativeTap("Tap the heart")
            let goOut = el("go-out")
            if goOut.exists { let before = cardText; centre(goOut).tap(); sleep(4); XCTAssertFalse(el("town-screen").exists, "Go out opened through the dim"); XCTAssertEqual(cardText, before, "the step moved after a tap on a control outside the ring"); note("go-out blocked ok") }
            tapEl("care-menu")
        }
        waitText(closeLine, timeout: 20)
        shot("08_menu")
        negativeTap("Tap the heart to close")
        tapEl("care-menu")
        // 3 Go out
        waitText("Tap Go out to visit the town.")
        shot("09_goout")
        tapEl("go-out")
        waitText("Shop, races, the park and more.", timeout: 20)
        XCTAssertTrue(el("town-screen").exists)
        shot("10_town_card")
        tapEl("tutorial-button")
        sleep(2)
        XCTAssertFalse(el("tutorial-card").exists, "the card is gone at the end")
        XCTAssertFalse(el("tutorial-skip").exists)
        shot("11_done")
        note("DONE: \(cfg) walked to the end")
    }

    // MARK: 2. Skip at every step
    func testSkipAtEveryStep() {
        let steps = (ProcessInfo.processInfo.environment["TUT_STEPS"] ?? "intro,cuddle.tap,cuddle.come,cuddle.rub,cuddle.release,care.heart,care.menu,out.go,out.town").split(separator: ",").map(String.init)
        for id in steps {
            launch(fresh + ["-TutorialAuto", "1", "-TutorialStep", id])
            XCTAssertTrue(el("tutorial-skip").waitForExistence(timeout: 90), "no Skip on \(id)")
            shot("skip_\(id)_before")
            centre(el("tutorial-skip")).tap()
            sleep(2)
            XCTAssertFalse(el("tutorial-skip").exists, "Skip did not end the tutorial at \(id)")
            XCTAssertFalse(el("tutorial-card").exists, "the card stayed after Skip at \(id)")
            // it stays gone: still no card a few seconds on, and the heart answers (nothing is in the way)
            sleep(3)
            XCTAssertFalse(el("tutorial-card").exists)
            centre(el("care-menu")).tap(); sleep(1)
            XCTAssertTrue(el("care-feed").waitForExistence(timeout: 5), "the heart does not answer after Skip at \(id)")
            shot("skip_\(id)_after")
            note("skip ok at \(id)")
            app.terminate()
        }
    }

    // MARK: 3. kill and relaunch mid-tour
    func testKillAndRelaunchResumes() {
        for (kill, resume) in [("care.heart", "Tap the heart to care for Bob."), ("cuddle.release", nil as String?), ("out.go", "Tap Go out to visit the town.")] {
            launch(fresh + ["-TutorialAuto", "1", "-TutorialStep", kill])
            XCTAssertTrue(el("tutorial-card").waitForExistence(timeout: 90), "no card at \(kill)")
            sleep(2)
            app.terminate(); note("killed at \(kill)")
            launch(["-MainMenu", "0", "-ClockHour", "12", "-BlobNoWander", "1"])          // NO reset or new-game arguments
            XCTAssertTrue(el("tutorial-card").waitForExistence(timeout: 90), "the tutorial did not resume after a kill at \(kill)")
            shot("resume_\(kill)")
            let expected = resume ?? cardText          // chapter 1 restarts at "Double tap <name>."
            XCTAssertEqual(cardText, expected, "killed at \(kill)")
            if resume == nil { XCTAssertTrue(cardText.hasPrefix("Double tap "), cardText) }
            centre(el("tutorial-skip")).tap(); sleep(1)
            app.terminate()
        }
    }

    // MARK: 4. stills: the same real walk in each configuration (TUT_CONFIG = portrait | landscape | ax | ipad), a picture at every card
    func testStills() {
        let cfg = ProcessInfo.processInfo.environment["TUT_CONFIG"] ?? "portrait"
        var extra: [String] = [], orient = UIDeviceOrientation.portrait
        switch cfg {
        case "landscape": orient = .landscapeLeft
        case "ax": extra = ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        default: break
        }
        walk(trueFirst: false, cfg: cfg, orient: orient, extra: extra)
    }

    // MARK: debug: what the care steps do after one tap on the heart
    func testHeartSteps() {
        launch(fresh + ["-TutorialAuto", "1", "-TutorialStep", "care.heart"])
        XCTAssertTrue(el("tutorial-card").waitForExistence(timeout: 90)); sleep(3)
        note("start text=\(cardText) feed=\(el("care-feed").exists)")
        centre(el("care-menu")).tap()
        for i in 0..<14 { sleep(1); note("t+\(i + 1)s text=\(cardText) feed=\(el("care-feed").exists)") }
        shot("heart_after")
    }

    // MARK: debug: the heart after a cuddle in the plain game (no tutorial)
    func testHeartAfterCuddlePlain() {
        launch(fresh)
        XCTAssertTrue(el("care-menu").waitForExistence(timeout: 90)); sleep(6)
        centre(el("jelbie-0")).doubleTap(); sleep(3)
        note("selected: come=\(el("hud-come").exists) clear=\(el("hud-clear").exists) feed=\(el("care-feed").exists)")
        tapEl(el("hud-come").exists ? "hud-come" : "hud-call-all")
        XCTAssertTrue(el("focus-release").waitForExistence(timeout: 40)); sleep(3)
        tapEl("focus-release"); sleep(6)
        note("after release: clear=\(el("hud-clear").exists) feed=\(el("care-feed").exists) come=\(el("hud-come").exists)")
        centre(el("care-menu")).tap()
        for i in 0..<4 { sleep(1); note("heart +\(i + 1)s feed=\(el("care-feed").exists) clear=\(el("hud-clear").exists)") }
        centre(el("care-menu")).tap()
        for i in 0..<3 { sleep(1); note("heart2 +\(i + 1)s feed=\(el("care-feed").exists) clear=\(el("hud-clear").exists)") }
    }

    func testHeartWhileSelected() {
        launch(fresh + ["-TutorialAuto", "1", "-TutorialStep", "cuddle.tap"])
        XCTAssertTrue(el("tutorial-card").waitForExistence(timeout: 90)); sleep(3)
        centre(el("jelbie-0")).doubleTap()
        XCTAssertTrue(el("hud-come").waitForExistence(timeout: 15)); sleep(1)
        tapEl("tutorial-skip"); sleep(3)
        note("selected, skipped: dress=\(el("hud-dress").exists) clear=\(el("hud-clear").exists) menu=\(el("care-menu").value ?? "")")
        shot("sel_before")
        centre(el("care-menu")).tap()
        for i in 0..<5 { sleep(2); note("heart +\(2 * i + 2)s dress=\(el("hud-dress").exists) value=\(el("care-menu").value ?? "")") }
        shot("sel_after")
        centre(el("care-menu")).tap()
        for i in 0..<3 { sleep(2); note("heart again +\(2 * i + 2)s dress=\(el("hud-dress").exists) value=\(el("care-menu").value ?? "")") }
    }
}
