//
//  PairRealAppUITests.swift
//  Not a regression test: REAL-APP frames of the pair kinds of the pair-distinct round at home (the home camera, no photo pose), portrait or landscape. Env (TEST_RUNNER_...): PAIR_REAL_OUT = folder,
//  PAIR_REAL_KINDS = "sitTogether,highFive,..." (SocialKind raw values), PAIR_REAL_CAST = "bob,pip", PAIR_REAL_ORIENT = portrait | landscape, PAIR_REAL_SECS (longest a scene may run, default 30).
//  One launch per kind (-NewGame <cast> -ContactDemo <kind>, Melon/ContactDemo.swift); screenshots go to <out>/<orient>/<kind>/f_<ms>.png and the demo's own log (gap ticks, start / end epoch) to <out>/<orient>/<kind>.demolog.
//

import XCTest

final class PairRealAppUITests: XCTestCase {
    func testKinds() throws {
        let env = ProcessInfo.processInfo.environment
        guard let out = env["PAIR_REAL_OUT"], !out.isEmpty, let kinds = env["PAIR_REAL_KINDS"], !kinds.isEmpty else { throw XCTSkip("PAIR_REAL_OUT / PAIR_REAL_KINDS not set") }
        let cast = env["PAIR_REAL_CAST"] ?? "bob,pip", orient = env["PAIR_REAL_ORIENT"] ?? "portrait"
        let secs = env["PAIR_REAL_SECS"].flatMap(Double.init) ?? 150
        for kind in kinds.split(separator: ",").map(String.init) {
            let base = out + "/" + orient
            let dir = base + "/" + kind
            try? FileManager.default.removeItem(atPath: dir)
            try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
            let log = base + "/" + kind + ".demolog"
            try? FileManager.default.removeItem(atPath: log)
            let app = XCUIApplication()
            app.launchArguments += ["-NewGame", cast, "-NewGameCoins", "10000", "-MainMenu", "0", "-RoomWide", "0", "-NeedsHappy", "1", "-ContactDemo", kind, "-ContactDemoDelay", "3"]
            app.launchEnvironment["CONTACTDEMO_LOG"] = log
            XCUIDevice.shared.orientation = orient == "landscape" ? .landscapeLeft : .portrait
            app.launch()
            let cont = app.buttons["Continue"]
            let t0 = Date()
            try? String(format: "%.3f", t0.timeIntervalSince1970).write(toFile: base + "/" + kind + ".t0", atomically: true, encoding: .utf8)          // (frame f_<ms> is t0 + ms)
            func epoch(_ key: String) -> Double? {
                guard let txt = try? String(contentsOfFile: log, encoding: .utf8), let r = txt.range(of: key + "=", options: .backwards) else { return nil }
                return Double(txt[r.upperBound...].prefix(while: { $0 != "\n" && $0 != " " }))
            }
            // (the demo starts by itself ~10-60 s after the launch whatever the test is doing: tap the intro's Continue while waiting, take NO screenshot until the emote has started, then one every loop to 2 s after it ends)
            var n = 0
            while Date().timeIntervalSince(t0) < secs {
                if epoch("startEpoch") == nil {
                    if cont.exists, cont.isHittable { cont.tap() }
                    Thread.sleep(forTimeInterval: 0.4); continue
                }
                if let e = epoch("endEpoch"), Date().timeIntervalSince1970 > e + 2.0 { break }
                let ms = Int(Date().timeIntervalSince(t0) * 1000)
                let png = XCUIScreen.main.screenshot().pngRepresentation
                try? png.write(to: URL(fileURLWithPath: String(format: "%@/f_%06d.png", dir, ms)))
                n += 1
            }
            XCTAssertGreaterThan(n, 5, "\(kind): frames were captured")
            app.terminate()
        }
    }
}
