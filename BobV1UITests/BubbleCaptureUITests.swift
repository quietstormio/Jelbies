//
//  BubbleCaptureUITests.swift
//  Capture aid + check: with three Jellies, the roster lists all three cards with their own status words, and a thirsty Pip's thought bubble
//  appears (labelled "Pip is thirsty"). Saves labelled phone-proportion screenshots to the scratchpad.
//

import XCTest
import UIKit

final class BubbleCaptureUITests: XCTestCase {
    static let out = "/private/tmp/claude-501/-Users-dmarshall94-Desktop-BobV1/6a40096b-092a-48d0-8cbe-4e00ccea7702/scratchpad/B4"

    private func save(_ shot: XCUIScreenshot, label: String, name: String) {
        let img = shot.image
        let bar: CGFloat = 90
        let r = UIGraphicsImageRenderer(size: CGSize(width: img.size.width, height: img.size.height + bar))
        let composed = r.image { ctx in
            UIColor.white.setFill(); ctx.fill(CGRect(origin: .zero, size: CGSize(width: img.size.width, height: img.size.height + bar)))
            img.draw(at: .zero)
            let p = NSMutableParagraphStyle(); p.alignment = .center
            (label as NSString).draw(in: CGRect(x: 8, y: img.size.height + 8, width: img.size.width - 16, height: bar - 12),
                                     withAttributes: [.font: UIFont.boldSystemFont(ofSize: 26), .foregroundColor: UIColor.black, .paragraphStyle: p])
        }
        try? FileManager.default.createDirectory(atPath: Self.out, withIntermediateDirectories: true)
        try? composed.pngData()?.write(to: URL(fileURLWithPath: "\(Self.out)/\(name).png"))
    }

    @MainActor
    func testRosterListsAllThreeWithTheirOwnWords() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-BlobCount", "3"]
        app.launch()
        let button = app.buttons["roster-button"]
        XCTAssertTrue(button.waitForExistence(timeout: 20))
        button.tap()
        var values: [String] = []
        for id in 0..<3 {
            let card = app.buttons["roster-card-\(id)"]
            XCTAssertTrue(card.waitForExistence(timeout: 10), "card \(id)")
            let v = (card.value as? String) ?? ""
            XCTAssertNotNil(v.range(of: #"Hunger \w+, Thirst \w+, Attention \w+, Coat \w+"#, options: .regularExpression), v)
            values.append(v)
        }
        XCTAssertNotEqual(values[0], values[1], "Pip's words are his own")
        XCTAssertNotEqual(values[1], values[2], "Moss's words are his own")
        sleep(1)
        save(app.screenshot(), label: "Roster: all 3 Jellies, own words", name: "roster-three")
    }

    @MainActor
    func testThirstyPipsBubbleSitsOverPip() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-BlobCount", "3"]
        app.launch()
        let pip = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Pip is thirsty'")).firstMatch
        XCTAssertTrue(pip.waitForExistence(timeout: 90), "Pip's thirst bubble appears")
        sleep(1)
        save(app.screenshot(), label: "Thirsty Pip: his bubble over Pip", name: "pip-thirsty-bubble")
        pip.tap()
        sleep(1)
        save(app.screenshot(), label: "Bubble tapped: Pip selected", name: "pip-bubble-tapped")
    }
}
