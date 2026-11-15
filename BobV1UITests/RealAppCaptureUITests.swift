//
//  RealAppCaptureUITests.swift
//  Capture aid, not a regression test (it skips without RA_OUT): launches the REAL app with the launch arguments given, waits until the scene is up,
//  then saves screenshots as fast as the simulator gives them to <RA_OUT>/<RA_NAME>/f_<ms>.jpg (ms since the scene was up; <RA_OUT>/<RA_NAME>.t0 = the
//  wall clock of ms 0). One scene per run. Env (through xcodebuild: TEST_RUNNER_RA_OUT=… and so on):
//    RA_OUT     folder (required)                    RA_NAME    scene name (required)
//    RA_ARGS    the app's launch arguments, space separated ("-SetRoster bob,pearl -MainMenu 0 -Intro 0 -Jelbies.started.v1 YES -StartPark 1")
//    RA_WAIT    accessibility id of the button that shows the scene is up: care-menu (home, the default) | park-home (the park)
//    RA_DELAY   seconds between "the scene is up" and the first frame (default 0)
//    RA_SECS    seconds of frames (default 40)
//    RA_ORIENT  portrait (default) | landscape
//    RA_SOUND   1 = leave the sound on (default: `-Mute 1` is added, the host's speakers stay quiet)
//    RA_APPENV  KEY=value pairs for the app's environment, comma separated (for a capture log path, e.g. CONTACTDEMO_LOG=/path)
//    RA_EVERY   at least this many seconds between two frames (default 0 = as fast as the simulator gives them); for long runs that only need a look now and then
//    RA_PLAN    steps DURING the capture, comma separated, each "<seconds>:<verb>:<what>". They happen IN THE ORDER GIVEN: a step is tried only when
//               every step before it is done, and not before its own second (seconds since ms 0):
//                 20:rotate:left | right | portrait      turns the device (the frames after a turn to landscape arrive sideways)
//                 30:tap:park-home                       waits until the element with that accessibility id exists and is hittable (looked for once a second), taps it once
//                                                         (an element that exists but stays not hittable for 4 looks in a row is tapped through the screen point at the centre
//                                                         of its frame instead; the .plan line says so. Follow such a tap with a `gone:` or `wait:` step that proves it landed)
//                 10:wait:race-card                      waits until the element exists (no tap)
//                 10:gone:race-card                      waits until the element is gone
//                 13:reach:photo-button                  a row of a scroll view that is off the screen: once a second, drags the page by 40 % of the screen's height
//                                                         (slow drag down the left margin, no fling) until the centre of the element's frame is inside the middle 70 % of
//                                                         the screen; at most 10 drags. No tap: follow it with `tap:`
//                 38:tree:tour                           writes the whole accessibility tree as XCUITest sees it at that moment (every element's type, frame, identifier,
//                                                         label) to <RA_OUT>/<RA_NAME>.tree_<what>.txt (`what` is only the file's suffix: letters and digits)
//                 40:tapat:0.50x0.919                    taps the screen point at these fractions of the app's frame (across, then down, an "x" between them): for a control
//                                                         whose XCUITest hit point is not where it is drawn. No lookup: follow it with a `gone:` or `wait:` step that proves it landed
//               Every step is written to <RA_OUT>/<RA_NAME>.plan with the time it really happened; a step that never happened fails the test. A `tap:` / `wait:`
//               line ends with the element's accessibility frame (screen points) and element type number as XCUITest reports them (9 = button), a `tapat:` line with its screen point.
//    RA_TAIL    with RA_PLAN: the capture ends this many seconds after the LAST step was done (and at RA_SECS at the latest); without it the capture runs RA_SECS
//  Build Release + ENABLE_TESTABILITY=YES like the other app captures (a Debug build runs at about 1 frame/s in the simulator).
//

import XCTest
import UIKit

final class RealAppCaptureUITests: XCTestCase {
    private struct Step {
        let at: Double
        let verb: String
        let what: String
        var done = false
        var lastTry = -10.0
        var unhittable = 0          // looks in a row at which the element existed but was not hittable
    }

    @MainActor
    func testScene() throws {
        let env = ProcessInfo.processInfo.environment
        guard let out = env["RA_OUT"], !out.isEmpty, let name = env["RA_NAME"], !name.isEmpty else { throw XCTSkip("RA_OUT / RA_NAME not set") }
        let dir = out + "/" + name
        try? FileManager.default.removeItem(atPath: dir)
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let secs = env["RA_SECS"].flatMap(Double.init) ?? 40, delay = env["RA_DELAY"].flatMap(Double.init) ?? 0
        let every = env["RA_EVERY"].flatMap(Double.init) ?? 0
        let tail = env["RA_TAIL"].flatMap(Double.init)
        var plan: [Step] = []
        for part in (env["RA_PLAN"] ?? "").split(separator: ",") {
            let f = part.split(separator: ":", maxSplits: 2).map(String.init)
            if f.count == 3, let at = Double(f[0]) { plan.append(Step(at: at, verb: f[1], what: f[2])) }
        }
        let planPath = out + "/" + name + ".plan"
        try? FileManager.default.removeItem(atPath: planPath)
        var planText = ""
        func note(_ line: String) {
            planText += line + "\n"
            try? planText.write(toFile: planPath, atomically: true, encoding: .utf8)
        }
        // where XCUITest sees an element (its accessibility frame in screen points) and what it is (the element type's number); a snapshot that fails (the element
        // has just gone) does not fail the test, unlike `e.frame`
        func info(_ e: XCUIElement) -> String {
            guard let s = try? e.snapshot() else { return " [no snapshot]" }
            let f = s.frame
            return String(format: " [frame %.1f,%.1f %.1fx%.1f type %d]", Double(f.minX), Double(f.minY), Double(f.width), Double(f.height), Int(s.elementType.rawValue))
        }
        let landscape = env["RA_ORIENT"] == "landscape"
        XCUIDevice.shared.orientation = landscape ? .landscapeLeft : .portrait
        let app = XCUIApplication()
        if let args = env["RA_ARGS"], !args.isEmpty { app.launchArguments += args.split(separator: " ").map(String.init) }
        if env["RA_SOUND"] != "1" { app.launchArguments += ["-Mute", "1"] }
        for pair in (env["RA_APPENV"] ?? "").split(separator: ",") {
            let kv = pair.split(separator: "=", maxSplits: 1).map(String.init)
            if kv.count == 2 { app.launchEnvironment[kv[0]] = kv[1] }
        }
        app.launch()
        // the scene is up when its button exists; a new game's "Continue" pages are tapped through on the way
        let ready = app.buttons[env["RA_WAIT"] ?? "care-menu"], cont = app.buttons["Continue"]
        let start = Date()
        while !ready.exists, Date().timeIntervalSince(start) < 300 {
            if cont.exists, cont.isHittable { cont.tap() }
            Thread.sleep(forTimeInterval: 1)
        }
        let up = ready.exists
        if !up { try? XCUIScreen.main.screenshot().image.jpegData(compressionQuality: 0.9)?.write(to: URL(fileURLWithPath: out + "/" + name + "_FAILED_not_up.jpg")) }
        XCTAssertTrue(up, "the scene never came up (no \(env["RA_WAIT"] ?? "care-menu") button in 300 s)")
        if delay > 0 { Thread.sleep(forTimeInterval: delay) }
        let t0 = Date()
        try? String(format: "%.3f", t0.timeIntervalSince1970).write(toFile: out + "/" + name + ".t0", atomically: true, encoding: .utf8)
        var n = 0
        var lastShot = -1.0e9
        var lastDoneAt = 0.0          // when the latest step of the plan was done (RA_TAIL counts from it)
        while Date().timeIntervalSince(t0) < secs {
            let now = Date().timeIntervalSince(t0)
            if let tail, !plan.isEmpty, plan.allSatisfy({ $0.done }), now >= lastDoneAt + tail { break }
            // the steps happen in the order given: a step is tried only when every step before it is done, and not before its own second
            if let i = plan.firstIndex(where: { !$0.done }), now >= plan[i].at {
                let step = plan[i]
                var byPoint = false
                var extra = ""          // the end of this step's .plan line: where XCUITest sees the element / where the tap went
                switch step.verb {
                case "rotate":
                    XCUIDevice.shared.orientation = step.what == "left" ? .landscapeLeft : (step.what == "right" ? .landscapeRight : .portrait)
                    plan[i].done = true
                case "reach":
                    if now - step.lastTry >= 1 {          // looked for once a second, like the other lookups
                        plan[i].lastTry = now
                        let e = app.descendants(matching: .any)[step.what].firstMatch
                        if e.exists {
                            let f = e.frame, a = app.frame
                            let mid = CGPoint(x: f.midX, y: f.midY)
                            if !f.isEmpty, a.insetBy(dx: 0, dy: a.height * 0.15).contains(mid) {
                                plan[i].done = true
                            } else if plan[i].unhittable < 10 {          // (the tap verb's counter doubles as the number of drags of this verb)
                                plan[i].unhittable += 1
                                // a slow drag down the page's left margin (outside the cards, so no row and no slider is touched), held at the end: no fling, no overshoot
                                let up = mid.y >= a.midY          // the row is below the middle: the page goes up
                                let from = app.coordinate(withNormalizedOffset: CGVector(dx: 0.03, dy: up ? 0.72 : 0.32))
                                let to = app.coordinate(withNormalizedOffset: CGVector(dx: 0.03, dy: up ? 0.32 : 0.72))
                                from.press(forDuration: 0.05, thenDragTo: to, withVelocity: .default, thenHoldForDuration: 0.2)
                            }
                        }
                    }
                case "tree":
                    // the whole accessibility tree as XCUITest sees it now (every element's type, frame, identifier and label): for a control that does not take its tap
                    try? app.debugDescription.write(toFile: out + "/" + name + ".tree_" + step.what + ".txt", atomically: true, encoding: .utf8)
                    plan[i].done = true
                case "tapat":
                    // a tap at a point of the screen given as fractions of the app's frame ("0.50x0.919" = the middle, 91.9 % of the way down); no element lookup
                    let p = step.what.split(separator: "x").compactMap { Double(String($0)) }
                    if p.count == 2, (0.0...1.0).contains(p[0]), (0.0...1.0).contains(p[1]) {
                        let c = app.coordinate(withNormalizedOffset: CGVector(dx: p[0], dy: p[1]))
                        let sp = c.screenPoint
                        c.tap()
                        extra = String(format: " [screen point %.1f,%.1f]", Double(sp.x), Double(sp.y))
                    } else {
                        extra = " [BAD point (want <across>x<down>, each 0...1): no tap]"
                    }
                    plan[i].done = true
                case "tap", "wait", "gone":
                    if now - step.lastTry >= 1 {          // looked for once a second (a query costs frames)
                        plan[i].lastTry = now
                        let e = app.descendants(matching: .any)[step.what].firstMatch
                        if step.verb == "gone" { plan[i].done = !e.exists }
                        else if step.verb == "wait" { plan[i].done = e.exists; if plan[i].done { extra = info(e) } }
                        else if e.exists {
                            if e.isHittable { extra = info(e); e.tap(); plan[i].done = true }
                            else {
                                // the accessibility hit test answers a later full-screen container (VolleyChrome's) for every chrome under it, so XCUITest never calls
                                // the button hittable although a finger reaches it: after 4 looks in a row, tap the screen point at the centre of its frame instead
                                plan[i].unhittable += 1
                                if plan[i].unhittable >= 4 {
                                    let f = e.frame
                                    if !f.isEmpty, app.frame.contains(CGPoint(x: f.midX, y: f.midY)) {
                                        extra = info(e)
                                        e.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
                                        plan[i].done = true; byPoint = true
                                    }
                                }
                            }
                        } else { plan[i].unhittable = 0 }
                    }
                default:
                    plan[i].done = true
                    note(String(format: "%.1f %@ %@ UNKNOWN verb, skipped", step.at, step.verb, step.what))
                }
                if plan[i].done {
                    lastDoneAt = Date().timeIntervalSince(t0)
                    note(String(format: "%.1f %@ %@ done at %.2f", step.at, step.verb, step.what, lastDoneAt) + (byPoint ? " (by screen point: exists but not hittable for 4 looks)" : "") + extra)
                }
            }
            if every > 0, now - lastShot < every {
                Thread.sleep(forTimeInterval: 0.05)
                continue
            }
            lastShot = now
            let ms = Int(Date().timeIntervalSince(t0) * 1000)
            if let jpg = XCUIScreen.main.screenshot().image.jpegData(compressionQuality: 0.9) {
                try? jpg.write(to: URL(fileURLWithPath: String(format: "%@/f_%06d.jpg", dir, ms)))
                n += 1
            }
        }
        for step in plan where !step.done { note(String(format: "%.1f %@ %@ NEVER HAPPENED", step.at, step.verb, step.what)) }
        XCTAssertGreaterThan(n, 5, "frames were captured")
        XCTAssertTrue(plan.allSatisfy { $0.done }, "a step of RA_PLAN never happened: see \(planPath)")
        XCUIDevice.shared.orientation = .portrait
        app.terminate()
    }
}
