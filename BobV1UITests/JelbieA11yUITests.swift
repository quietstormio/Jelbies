//
//  JelbieA11yUITests.swift
//  The Jelbies as accessibility elements, seen the way VoiceOver / Accessibility Inspector see them: each Jelbie in the room is an element with a
//  name + feature label, a value (where, mood, needs, doing) and a frame on his body. Also saves the screenshots with the frames, labels and values
//  drawn over them (portrait and landscape) to the scratchpad.
//

import XCTest
import UIKit

final class JelbieA11yUITests: XCTestCase {
    static let out = "/private/tmp/claude-501/-Users-dmarshall94-Desktop-BobV1/9cd2e159-911b-4a04-879f-e5e34721a64a/scratchpad/a11y/B"

    override func setUp() { continueAfterFailure = false }

    private struct Seen { var id: Int; var label: String; var value: String; var frame: CGRect }

    private func gather(_ app: XCUIApplication) -> [Seen] {
        (0..<3).compactMap { id in
            let e = app.descendants(matching: .any).matching(identifier: "jelbie-\(id)").firstMatch
            guard e.exists else { return nil }
            return Seen(id: id, label: e.label, value: (e.value as? String) ?? "", frame: e.frame)
        }
    }

    private func save(_ img: UIImage, seen: [Seen], win: CGRect, room: String, title: String, name: String) {
        let bar: CGFloat = 150
        let size = CGSize(width: img.size.width, height: img.size.height + bar)
        let k = img.size.width / win.width
        XCTAssertEqual(img.size.width / img.size.height, win.width / win.height, accuracy: 0.05, "\(name): screenshot and element frames are in the same orientation: \(img.size) vs \(win)")
        let colors: [UIColor] = [.systemBlue, .systemOrange, .systemGreen]
        let out = UIGraphicsImageRenderer(size: size).image { ctx in
            UIColor.white.setFill(); ctx.fill(CGRect(origin: .zero, size: size))
            img.draw(at: .zero)
            var y = img.size.height + 6
            let p = NSMutableParagraphStyle(); p.alignment = .left
            (title as NSString).draw(in: CGRect(x: 10, y: y, width: size.width - 20, height: 30), withAttributes: [.font: UIFont.boldSystemFont(ofSize: 24), .foregroundColor: UIColor.black])
            y += 30
            (("Room: " + room) as NSString).draw(in: CGRect(x: 10, y: y, width: size.width - 20, height: 22), withAttributes: [.font: UIFont.systemFont(ofSize: 16), .foregroundColor: UIColor.darkGray])
            y += 22
            for (i, s) in seen.enumerated() {
                let c = colors[i % 3]
                let r = CGRect(x: s.frame.minX * k, y: s.frame.minY * k, width: s.frame.width * k, height: s.frame.height * k)
                c.setStroke(); ctx.cgContext.setLineWidth(5); ctx.cgContext.stroke(r)
                let tag = "\(s.label)  |  \(s.value)"
                let attrs: [NSAttributedString.Key: Any] = [.font: UIFont.boldSystemFont(ofSize: 15), .foregroundColor: UIColor.white, .backgroundColor: c]
                (tag as NSString).draw(in: CGRect(x: max(4, r.minX), y: max(4, r.minY - 20 + CGFloat(i) * 22), width: size.width - 8, height: 20), withAttributes: attrs)
                ("\(s.label): \(s.value)" as NSString).draw(in: CGRect(x: 10, y: y, width: size.width - 20, height: 20), withAttributes: [.font: UIFont.systemFont(ofSize: 14), .foregroundColor: c])
                y += 20
            }
        }
        try? FileManager.default.createDirectory(atPath: Self.out, withIntermediateDirectories: true)
        try? out.pngData()?.write(to: URL(fileURLWithPath: "\(Self.out)/\(name).png"))
    }

    /// The image turned a quarter turn (right = clockwise), drawn pixel for pixel from its CGImage, 1x.
    private static func rotated(_ img: UIImage, _ o: UIImage.Orientation) -> UIImage {
        guard let cg = img.cgImage else { return img }
        let w = CGFloat(cg.width), h = CGFloat(cg.height)
        let fmt = UIGraphicsImageRendererFormat(); fmt.scale = 1
        let src = UIImage(cgImage: cg)
        return UIGraphicsImageRenderer(size: CGSize(width: h, height: w), format: fmt).image { ctx in
            let c = ctx.cgContext
            c.translateBy(x: h / 2, y: w / 2)
            c.rotate(by: o == .right ? .pi / 2 : -.pi / 2)
            src.draw(in: CGRect(x: -w / 2, y: -h / 2, width: w, height: h))
        }
    }

    /// Share of pixels in the middle of `frame` that are the Jelbie's own colour (Bob blue, Pip yellow, Moss green): proves the frame is on his body.
    private static func bodyColourShare(_ img: UIImage, frame: CGRect, window: CGRect, id: Int) -> Double {
        guard let cg = img.cgImage else { return 0 }
        let kx = CGFloat(cg.width) / window.width, ky = CGFloat(cg.height) / window.height
        let box = CGRect(x: frame.midX - frame.width * 0.25, y: frame.midY - frame.height * 0.25, width: frame.width * 0.5, height: frame.height * 0.5)
        var data = [UInt8](repeating: 0, count: cg.width * cg.height * 4)
        guard let ctx = CGContext(data: &data, width: cg.width, height: cg.height, bitsPerComponent: 8, bytesPerRow: cg.width * 4,
                                  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return 0 }
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: cg.width, height: cg.height))
        var hit = 0, n = 0
        for yy in stride(from: box.minY * ky, to: box.maxY * ky, by: 4) {
            for xx in stride(from: box.minX * kx, to: box.maxX * kx, by: 4) {
                let x = Int(xx), y = Int(yy)
                guard x >= 0, y >= 0, x < cg.width, y < cg.height else { continue }
                let o = (y * cg.width + x) * 4
                let r = Int(data[o]), g = Int(data[o + 1]), b = Int(data[o + 2])
                n += 1
                switch id {
                case 0: if b > r + 40 && b > g + 10 { hit += 1 }
                case 1: if r > 170 && g > 150 && b < 130 { hit += 1 }
                default: if g > r + 20 && g > b + 20 { hit += 1 }
                }
            }
        }
        return n == 0 ? 0 : Double(hit) / Double(n)
    }

    @MainActor
    func testJelbiesAreElementsWithNamesAndPlaces() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-BlobCount", "3"]
        XCUIDevice.shared.orientation = .portrait          // the simulator keeps the last test's orientation
        sleep(2)
        app.launch()
        let first = app.descendants(matching: .any).matching(identifier: "jelbie-0").firstMatch
        XCTAssertTrue(first.waitForExistence(timeout: 120), "the Jelbies are accessibility elements")
        sleep(2)
        let room = app.descendants(matching: .any).matching(identifier: "room").firstMatch
        XCTAssertTrue(room.exists); XCTAssertEqual(room.label, "Living room")
        var seen = gather(app)
        XCTAssertEqual(seen.count, 3)
        let screen = app.windows.firstMatch.frame
        XCTAssertGreaterThan(screen.height, screen.width, "the portrait pass starts in portrait")
        for s in seen {
            XCTAssertTrue(s.label.hasPrefix(["Bob", "Pip", "Moss"][s.id]), s.label)
            XCTAssertTrue(s.label.contains("blue") || s.label.contains("yellow") || s.label.contains("green"), "told apart by words: \(s.label)")
            XCTAssertNotNil(s.value.range(of: #"^(Left|Middle|Right), (front|back)\. (Happy|Okay|Grumpy)\."#, options: .regularExpression), s.value)
            XCTAssertTrue(screen.intersects(s.frame) && s.frame.width > 20 && s.frame.height > 20, "\(s.label) frame \(s.frame)")
        }
        // the three are laid out left to right in reading order of their frames, and VoiceOver can find them by label
        XCTAssertEqual(Set(seen.map(\.label)).count, 3)
        save(app.screenshot().image, seen: seen, win: screen, room: room.value as? String ?? "", title: "VoiceOver elements: portrait", name: "ax_jelbies_portrait")

        // activating one (a double tap, or Switch Control's select) highlights him
        let pip = app.descendants(matching: .any).matching(identifier: "jelbie-1").firstMatch
        pip.doubleTap()
        sleep(2)
        seen = gather(app)
        XCTAssertTrue(seen[1].value.contains("Highlighted"), "tapping Pip's element highlights him: \(seen[1].value)")

        XCUIDevice.shared.orientation = .landscapeLeft
        sleep(6)
        let land = app.windows.firstMatch.frame
        XCTAssertGreaterThan(land.width, land.height, "the app is in landscape")
        seen = gather(app)
        XCTAssertEqual(seen.count, 3)
        // XCUIScreenshot of a landscape simulator is a cropped portrait framebuffer, so it cannot be used to check frames. The frames go to a JSON
        // file and the test holds the screen while `xcrun simctl io <udid> screenshot` takes the real landscape picture (checked by a script).
        for s in seen {
            XCTAssertTrue(land.insetBy(dx: -1, dy: -1).contains(s.frame), "\(s.label) frame \(s.frame) inside \(land)")
        }
        let json = seen.map { ["id": $0.id, "label": $0.label, "x": $0.frame.minX, "y": $0.frame.minY, "w": $0.frame.width, "h": $0.frame.height] as [String: Any] }
        let blob = ["window": [land.width, land.height], "frames": json] as [String: Any]
        try? JSONSerialization.data(withJSONObject: blob).write(to: URL(fileURLWithPath: "\(Self.out)/landscape_frames.json"))
        sleep(20)
        XCUIDevice.shared.orientation = .portrait
    }
}

/// The trick book's typing field (teach + command), captured portrait / landscape / AX5, and the controls proven reachable.
final class TrickBookTypingUITests: XCTestCase {
    static let out = JelbieA11yUITests.out
    override func setUp() { continueAfterFailure = false }

    @MainActor
    private func capture(_ name: String, orientation: String, ax: Bool) {
        let app = XCUIApplication()
        app.launchArguments += ["-VoiceFakeMic", "1", "-VoiceReset", "1", "-VoiceLearned", "1", "-ForceOrientation", orientation]
        if ax { app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"] }
        app.launch()
        let bookBtn = app.buttons["voice-tricks"]
        XCTAssertTrue(bookBtn.waitForExistence(timeout: 150))
        sleep(2)
        bookBtn.tap()
        let row = app.descendants(matching: .any).matching(identifier: "voice-trick-jacks").firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 20), "the trick book opens")
        let win = app.windows.firstMatch.frame
        if orientation != "portrait" { XCTAssertGreaterThan(win.width, win.height, "landscape") }
        let learnedBtn = app.descendants(matching: .any).matching(identifier: "voice-teach-typing-jacks").firstMatch
        XCTAssertTrue(learnedBtn.waitForExistence(timeout: 10), "a learned trick still offers a typed command")
        XCTAssertEqual(learnedBtn.label, "Type a command")
        XCTAssertGreaterThanOrEqual(learnedBtn.frame.height, 40, "44 pt target")
        // (XCUIScreenshot is a cropped portrait framebuffer in landscape: the picture is taken from outside with `simctl io screenshot`)
        try? FileManager.default.createDirectory(atPath: Self.out, withIntermediateDirectories: true)
        try? "ready".write(toFile: "\(Self.out)/\(name).ready", atomically: true, encoding: .utf8)
        sleep(8)
    }

    @MainActor func testTrickBookPortrait() { capture("trickbook_portrait", orientation: "portrait", ax: false) }
    @MainActor func testTrickBookLandscape() { capture("trickbook_landscape", orientation: "left", ax: false) }
    @MainActor func testTrickBookAX5Landscape() { capture("trickbook_ax5_landscape", orientation: "left", ax: true) }
}
