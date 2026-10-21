//
//  EarsCaptureTests.swift
//  Not a regression test: renders the Ears HUD pieces (the sound panel with its Ears row in the regular AND the compact / landscape size class,
//  the ear button in every state) with SwiftUI's ImageRenderer into EARS_CAP_DIR (pass as TEST_RUNNER_EARS_CAP_DIR). Skipped otherwise.
//  The landscape case is the one the simulator cannot rotate for us headlessly: the panel must fit ~400 pt of height.
//

import XCTest
import SwiftUI
import UIKit
@testable import BobV1

@MainActor
final class EarsCaptureTests: XCTestCase {
    nonisolated(unsafe) static var keep: [AnyObject] = []
    private func render<V: View>(_ v: V, size: CGSize, _ name: String, dir: String) throws {
        let r = ImageRenderer(content: v.frame(width: size.width, height: size.height).background(Color(red: 0.55, green: 0.45, blue: 0.45)).environment(\.colorScheme, .light))
        r.scale = 2
        let img = try XCTUnwrap(r.uiImage, name)
        try XCTUnwrap(img.pngData()).write(to: URL(fileURLWithPath: "\(dir)/\(name).png"))
    }

    func testRenderEarsPanelAndButton() throws {
        guard let dir = ProcessInfo.processInfo.environment["EARS_CAP_DIR"], !dir.isEmpty else { throw XCTSkip("EARS_CAP_DIR not set") }
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let ears = Ears(defaults: UserDefaults(suiteName: "EarsCaptureTests")!, inert: true)
        Self.keep.append(ears)
        ears.setOn(true)
        // the panel in portrait (regular) and on a phone on its side (compact height: ~402 pt total, the panel sits at top 52)
        let portrait = SoundSettingsPanel(hub: AudioHub.shared, ears: ears) {}
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading).padding(.leading, 16).padding(.top, 52)
        try render(portrait, size: CGSize(width: 402, height: 874), "panel_portrait", dir: dir)
        let landscape = SoundSettingsPanel(hub: AudioHub.shared, ears: ears) {}
            .environment(\.verticalSizeClass, .compact)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading).padding(.leading, 16).padding(.top, 52)
        try render(landscape, size: CGSize(width: 874, height: 402), "panel_landscape", dir: dir)
        // the panel's own height must leave the bottom safe area free in landscape: measure it
        let probe = ImageRenderer(content: SoundSettingsPanel(hub: AudioHub.shared, ears: ears) {}.environment(\.verticalSizeClass, .compact).fixedSize())
        probe.scale = 1
        let h = try XCTUnwrap(probe.uiImage).size.height
        XCTAssertLessThanOrEqual(h, 402 - 52 - 24, "the sound panel (\(h) pt) does not fit a landscape phone under the top buttons")
        // the ear button states
        ears.debugSetState(.off); try render(EarsButton(ears: ears), size: CGSize(width: 60, height: 60), "button_off", dir: dir)
        ears.debugSetState(.listening); try render(EarsButton(ears: ears), size: CGSize(width: 60, height: 60), "button_on", dir: dir)
        ears.debugSetState(.paused(.voice)); try render(EarsButton(ears: ears), size: CGSize(width: 60, height: 60), "button_paused", dir: dir)
        ears.debugSetState(.denied); try render(EarsButton(ears: ears), size: CGSize(width: 60, height: 60), "button_denied", dir: dir)
        try render(SoundSettingsPanel(hub: AudioHub.shared, ears: ears) {}.fixedSize(), size: CGSize(width: 300, height: 420), "panel_denied", dir: dir)
    }
}
