//
//  PodiumCaptureUITests.swift
//  Capture aid, not a regression test (skips without PODIUM_OUT): the Studio action shot in a given outfit (PODIUM_WEAR "bowtieSky,tutuPink", PODIUM_ROSTER "bob,pearl,teddy"),
//  and the adoption picker (PODIUM_PICKER=1, PODIUM_PAGE). PODIUM_LAND=1 for landscape. Saves PODIUM_OUT/PODIUM_TAG_*.png.
//

import XCTest

final class PodiumCaptureUITests: XCTestCase {
    private var env: [String: String] { ProcessInfo.processInfo.environment }
    private func shot(_ name: String) {
        try? XCUIScreen.main.screenshot().image.pngData()?.write(to: URL(fileURLWithPath: "\(env["PODIUM_OUT"] ?? "")/\(env["PODIUM_TAG"] ?? "p")_\(name).png"))
    }

    @MainActor func testCapture() throws {
        guard let out = env["PODIUM_OUT"], !out.isEmpty else { throw XCTSkip("PODIUM_OUT not set") }
        try? FileManager.default.createDirectory(atPath: out, withIntermediateDirectories: true)
        let land = env["PODIUM_LAND"] == "1"
        XCUIDevice.shared.orientation = land ? .landscapeLeft : .portrait
        let app = XCUIApplication()
        let picker = env["PODIUM_PICKER"] == "1"
        app.launchArguments += ["-SetRoster", env["PODIUM_ROSTER"] ?? "bob,pearl,teddy", "-MainMenu", "0", "-Intro", "0", "-Jelbies.started.v1", "YES", "-BlobDrops.v1", "1024", "-BlobNoWander", "1", "-ClockHour", "12"]
        if picker { app.launchArguments += ["-PickerMode", "more", "-PickerPage", env["PODIUM_PAGE"] ?? "2"] }
        else if env["PODIUM_ROOM"] == "1" { app.launchArguments += ["-StoreSeed", "1"] }
        else { app.launchArguments += ["-StoreOpen", "studio", "-StoreSeed", "1"] }
        if let w = env["PODIUM_WEAR"], !w.isEmpty { app.launchArguments += ["-WearList", w, "-WearWho", env["PODIUM_WHO"] ?? "0"] }
        if land { app.launchArguments += ["-ForceOrientation", "left"] }
        if let l = env["PODIUM_LIMBS"], !l.isEmpty { app.launchEnvironment["WEARFIT_LIMBS"] = l }
        app.launch()
        let skip = app.buttons["Skip"]
        if skip.waitForExistence(timeout: 20) { skip.tap() }
        if !picker, env["PODIUM_ROOM"] != "1" { _ = app.descendants(matching: .any)["studio-screen"].firstMatch.waitForExistence(timeout: 60) }
        sleep(6)
        for k in 0..<(Int(env["PODIUM_SHOTS"] ?? "3") ?? 3) { shot("t\(k)"); usleep(1_100_000) }
        app.terminate()
    }
}
