//
//  TrainAuditUITests.swift  (AUDIT ONLY, not for merge)
//  Walks today's training flow end to end with the fake mic and records what the player sees.
//

import XCTest
import UIKit

final class TrainAuditUITests: XCTestCase {
    static let out = ProcessInfo.processInfo.environment["TRAIN_OUT"] ?? "/tmp/train_audit"
    var log: [String] = []

    private func save(_ name: String) {
        try? FileManager.default.createDirectory(atPath: Self.out, withIntermediateDirectories: true)
        try? XCUIScreen.main.screenshot().image.pngData()?.write(to: URL(fileURLWithPath: "\(Self.out)/\(name).png"))
    }
    private func note(_ s: String) {
        log.append(s)
        try? log.joined(separator: "\n").write(toFile: "\(Self.out)/audit_log.txt", atomically: true, encoding: .utf8)
    }
    private func launch(_ extra: [String], orient: UIDeviceOrientation) -> XCUIApplication {
        XCUIDevice.shared.orientation = orient
        let app = XCUIApplication()
        app.launchArguments += ["-SetRoster", "pip,moss,lavender", "-VoiceFakeMic", "1", "-NeedsHappy", "1", "-VoiceTipSeen", "1"] + extra
        app.launch()
        return app
    }
    /// The real path: tap the Jelbie at `at` (normalized), paw, Train.
    private func train(_ app: XCUIApplication, at: CGVector) -> Bool {
        let menu = app.buttons["care-menu"]
        guard menu.waitForExistence(timeout: 240) else { note("no care-menu"); return false }
        sleep(4)
        let id = at.dx < 0.5 ? 1 : 2       // (moss = 1, lavender = 2) picked through the roster panel: the tap on a moving Jelbie is flaky
        app.buttons["roster-button"].tap()
        let card = app.buttons["roster-card-\(id)"]
        guard card.waitForExistence(timeout: 5) else { note("no roster card \(id)"); return false }
        card.tap()
        sleep(2)
        if app.descendants(matching: .any)["roster-panel"].exists { app.buttons["roster-button"].tap(); sleep(1) }
        menu.tap()
        let t = app.buttons["hud-train"]
        guard t.waitForExistence(timeout: 5) else { note("no hud-train (individual menu did not open)"); save("no_train"); return false }
        note("hud-train enabled=\(t.isEnabled)")
        t.tap()
        return app.descendants(matching: .any)["voice-trickbook"].waitForExistence(timeout: 300)
    }
    private func bubble(_ app: XCUIApplication) -> String {
        let b = app.descendants(matching: .any)["voice-bubble"]
        return b.waitForExistence(timeout: 6) ? (b.value as? String ?? "?") : "(no bubble)"
    }
    private func row(_ app: XCUIApplication, _ t: String) -> String {
        let r = app.buttons["voice-trick-\(t)"]
        return r.waitForExistence(timeout: 6) ? r.label : "(no row)"
    }

    @MainActor func testAuditPortrait() throws { try flow(.portrait, "P") }
    @MainActor func testAuditLandscape() throws { try flow(.landscapeLeft, "L") }

    @MainActor
    private func flow(_ o: UIDeviceOrientation, _ tag: String) throws {
        let env = ProcessInfo.processInfo.environment
        func v(_ k: String, _ d: CGVector) -> CGVector { guard let s = env[k] else { return d }; let p = s.split(separator: ",").compactMap { Double($0) }; return CGVector(dx: p[0], dy: p[1]) }
        let moss = v("MOSS_\(tag)", CGVector(dx: 0.40, dy: 0.52)), lav = v("LAV_\(tag)", CGVector(dx: 0.59, dy: 0.56))
        note("=== \(tag) fresh, -TrainJelly 1 (Moss) ===")
        var app = launch(["-VoiceReset", "1", "-VoiceFakeText", "sit"], orient: o)
        let book = app.descendants(matching: .any)["voice-trickbook"]
        let ok = train(app, at: moss)
        note("book opened on arrival: \(ok) subject=\(ok ? "\(book.value ?? "nil")" : "-")")
        save("\(tag)_01_book_on_arrival")
        guard ok else { return }
        save("\(tag)_01_book_on_arrival")
        note("sit row: \(row(app, "sit"))")
        for i in 1...3 {
            if !app.buttons["voice-trick-sit"].exists { app.buttons["voice-tricks"].tap(); _ = book.waitForExistence(timeout: 5) }
            app.buttons["voice-trick-sit"].tap()
            let prompt = app.descendants(matching: .any)["voice-prompt"]
            note("rep \(i): prompt shown=\(prompt.waitForExistence(timeout: 4)) text=\(prompt.exists ? prompt.label : "-")")
            sleep(1)
            save("\(tag)_0\(i + 1)a_prompt_rep\(i)")
            app.buttons["voice-mic"].press(forDuration: 1.2)
            let v = bubble(app)
            note("rep \(i): bubble=\(v)")
            let heard = app.descendants(matching: .any)["voice-heard"]
            note("rep \(i): heard=\(heard.exists ? (heard.value as? String ?? heard.label) : "-")")
            save("\(tag)_0\(i + 1)b_after_rep\(i)")
            if i == 3 {
                let toast = app.descendants(matching: .any)["voice-toast"]
                note("toast exists=\(toast.waitForExistence(timeout: 2)) \(toast.exists ? toast.label : "")")
            }
            sleep(2)
        }
        app.buttons["voice-tricks"].tap(); _ = book.waitForExistence(timeout: 5)
        note("sit row after 3: \(row(app, "sit"))")
        save("\(tag)_05_book_after")
        app.buttons["voice-book-close"].tap(); sleep(1)
        // try it: no demo
        app.buttons["voice-mic"].press(forDuration: 1.2)
        note("try-it in close-up: bubble=\(bubble(app))")
        save("\(tag)_06_tryit")
        app.terminate()

        // persistence + the room command
        note("=== \(tag) relaunch, no reset: room 'sit' (nothing highlighted) ===")
        app = launch(["-VoiceFakeText", "sit"], orient: o)
        _ = app.buttons["care-menu"].waitForExistence(timeout: 240); sleep(4)
        app.buttons["voice-mic"].press(forDuration: 1.2)
        note("room 'sit': bubble=\(bubble(app))")
        save("\(tag)_07_room_sit")
        app.terminate()

        note("=== \(tag) relaunch: room 'moss sit' ===")
        app = launch(["-VoiceFakeText", "moss sit"], orient: o)
        _ = app.buttons["care-menu"].waitForExistence(timeout: 240); sleep(4)
        app.buttons["voice-mic"].press(forDuration: 1.2)
        note("room 'moss sit': bubble=\(bubble(app))")
        save("\(tag)_08_room_named_sit")
        app.terminate()

        note("=== \(tag) relaunch: Lavender's book (isolation) + Moss's book (persist) ===")
        app = launch([], orient: o)
        _ = train(app, at: lav)
        note("Lavender sit row: \(row(app, "sit"))")
        save("\(tag)_09_lavender_book")
        app.terminate()
        app = launch([], orient: o)
        _ = train(app, at: moss)
        note("Moss sit row after relaunch: \(row(app, "sit"))")
        app.terminate()

        note("=== \(tag) unknown word while nothing runs ===")
        app = launch(["-VoiceFakeText", "banana"], orient: o)
        _ = train(app, at: moss)
        app.buttons["voice-book-close"].tap(); sleep(1)
        app.buttons["voice-mic"].press(forDuration: 1.2)
        note("'banana' no demo: bubble=\(bubble(app))")
        save("\(tag)_10_unknown")
        app.terminate()

        note("=== \(tag) late word: tap sit, wait 7 s, then speak ===")
        app = launch(["-VoiceReset", "1", "-VoiceFakeText", "sit"], orient: o)
        _ = train(app, at: moss)
        app.buttons["voice-trick-sit"].tap()
        sleep(7)
        app.buttons["voice-mic"].press(forDuration: 1.2)
        note("late word: bubble=\(bubble(app))")
        app.terminate()
    }
}
