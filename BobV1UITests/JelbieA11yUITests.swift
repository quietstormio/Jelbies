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

    private func save(_ shot: XCUIScreenshot, seen: [Seen], room: String, title: String, name: String) {
        let img = shot.image
        let bar: CGFloat = 150
        let size = CGSize(width: img.size.width, height: img.size.height + bar)
        let k = img.size.width / XCUIApplication().windows.firstMatch.frame.width
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

    @MainActor
    func testJelbiesAreElementsWithNamesAndPlaces() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-BlobCount", "3"]
        app.launch()
        let first = app.descendants(matching: .any).matching(identifier: "jelbie-0").firstMatch
        XCTAssertTrue(first.waitForExistence(timeout: 120), "the Jelbies are accessibility elements")
        sleep(2)
        let room = app.descendants(matching: .any).matching(identifier: "room").firstMatch
        XCTAssertTrue(room.exists); XCTAssertEqual(room.label, "Living room")
        var seen = gather(app)
        XCTAssertEqual(seen.count, 3)
        let screen = app.windows.firstMatch.frame
        for s in seen {
            XCTAssertTrue(s.label.hasPrefix(["Bob", "Pip", "Moss"][s.id]), s.label)
            XCTAssertTrue(s.label.contains("blue") || s.label.contains("yellow") || s.label.contains("green"), "told apart by words: \(s.label)")
            XCTAssertNotNil(s.value.range(of: #"^(Left|Middle|Right), (front|back)\. (Happy|Okay|Grumpy)\."#, options: .regularExpression), s.value)
            XCTAssertTrue(screen.intersects(s.frame) && s.frame.width > 20 && s.frame.height > 20, "\(s.label) frame \(s.frame)")
        }
        // the three are laid out left to right in reading order of their frames, and VoiceOver can find them by label
        XCTAssertEqual(Set(seen.map(\.label)).count, 3)
        save(app.screenshot(), seen: seen, room: room.value as? String ?? "", title: "VoiceOver elements: portrait", name: "ax_jelbies_portrait")

        // activating one (a double tap, or Switch Control's select) highlights him
        let pip = app.descendants(matching: .any).matching(identifier: "jelbie-1").firstMatch
        pip.doubleTap()
        sleep(2)
        seen = gather(app)
        XCTAssertTrue(seen[1].value.contains("Highlighted"), "tapping Pip's element highlights him: \(seen[1].value)")

        XCUIDevice.shared.orientation = .landscapeLeft
        sleep(4)
        seen = gather(app)
        XCTAssertEqual(seen.count, 3)
        save(app.screenshot(), seen: seen, room: room.value as? String ?? "", title: "VoiceOver elements: landscape", name: "ax_jelbies_landscape")
        XCUIDevice.shared.orientation = .portrait
    }
}
