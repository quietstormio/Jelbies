//
//  FeedCaptureUITests.swift
//  Capture aid for the Feed / Drink rows of the care menu, portrait and landscape: the row at rest, scrolled to the middle, scrolled to the end.
//  Screenshots go to FEED_OUT (TEST_RUNNER_FEED_OUT; default /tmp/feed_ui). Works on the old two-row layout too (it taps Snacks when that button exists).
//

import XCTest
import UIKit

final class FeedCaptureUITests: XCTestCase {
    static let out = ProcessInfo.processInfo.environment["FEED_OUT"] ?? "/tmp/feed_ui"

    private func save(_ name: String) {
        try? FileManager.default.createDirectory(atPath: Self.out, withIntermediateDirectories: true)
        try? XCUIScreen.main.screenshot().image.pngData()?.write(to: URL(fileURLWithPath: "\(Self.out)/\(name).png"))
    }

    @MainActor
    func testFeedAndDrinkRows() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-Mute", "1", "-SetRoster", "pip", "-MainMenu", "0", "-Intro", "0", "-Jelbies.started.v1", "YES", "-BlobDrops.v1", "300", "-BlobNoWander", "1", "-StoreSeed", "2"]
        app.launch()
        sleep(6)
        for (orient, name) in [(UIDeviceOrientation.portrait, "portrait"), (.landscapeLeft, "landscape")] {
            XCUIDevice.shared.orientation = orient
            sleep(5)
            let menu = app.buttons["care-menu"]
            XCTAssertTrue(menu.waitForExistence(timeout: 20))
            for (button, first, tag) in [("care-feed", "care-food-sushi", "feed"), ("care-snacks", "care-snack-sushi", "snacks"), ("care-water", "care-drink-water", "drink")] {
                if !app.buttons["care-feed"].exists { menu.tap(); sleep(1) }
                let b = app.buttons[button]
                guard b.waitForExistence(timeout: 5) else { continue }
                b.tap()
                let item = app.buttons[first]
                guard item.waitForExistence(timeout: 5) else { save("\(name)_\(tag)_missing"); menu.tap(); continue }
                sleep(1)
                save("\(name)_\(tag)_1_rest")
                let row = item.frame
                func drag(_ dx: CGFloat) {          // a short drag along the row (not a swipe: a fast swipe on the menu can close it)
                    let a = app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: row.midX, dy: row.midY))
                    a.press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: row.midX - dx, dy: row.midY)))
                }
                drag(160); sleep(1)
                if item.exists { save("\(name)_\(tag)_2_mid") }
                drag(400); drag(400); sleep(1)
                save("\(name)_\(tag)_3_end")
                menu.tap(); sleep(1)           // close the menu (the picker folds away with it)
                if app.buttons["care-feed"].exists { menu.tap(); sleep(1) }
            }
        }
    }

    /// The Shop's food and drinks tabs (TEST_RUNNER_FEED_TABS = "food,drinks"; the old build used "snacks,drinks"), portrait and landscape.
    @MainActor
    func testShopTabs() throws {
        let tabs = (ProcessInfo.processInfo.environment["FEED_TABS"] ?? "food,drinks").split(separator: ",").map(String.init)
        for tab in tabs {
            for (orient, name) in [(UIDeviceOrientation.portrait, "portrait"), (.landscapeLeft, "landscape")] {
                let app = XCUIApplication()
                app.launchArguments += ["-Mute", "1", "-SetRoster", "pip", "-MainMenu", "0", "-Intro", "0", "-Jelbies.started.v1", "YES", "-BlobDrops.v1", "300", "-BlobNoWander", "1", "-StoreSeed", "1", "-StoreTab", tab]
                app.launch()
                XCUIDevice.shared.orientation = orient
                sleep(5)
                guard app.buttons["go-out"].waitForExistence(timeout: 20) else { continue }
                app.buttons["go-out"].tap()
                guard app.buttons["town-shop"].waitForExistence(timeout: 10) else { save("shop_\(tab)_\(name)_notown"); continue }
                app.buttons["town-shop"].tap()
                sleep(3)
                save("shop_\(tab)_\(name)")
                app.terminate()
            }
        }
    }

    /// The user's exact situation: -NewGame lavender,pearl,teddy with 10000 JellyCoins. Empty Feed row, the Food tab, buy berries + pizza, the Feed row again; portrait then landscape.
    @MainActor
    func testFreshNewGameBuyFlow() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-NewGame", "lavender,pearl,teddy", "-NewGameCoins", "10000", "-MainMenu", "0", "-Mute", "1", "-BlobNoWander", "1"]
        app.launch()
        for (orient, name) in [(UIDeviceOrientation.portrait, "portrait"), (.landscapeLeft, "landscape")] {
            XCUIDevice.shared.orientation = orient
            sleep(5)
            let menu = app.buttons["care-menu"]
            XCTAssertTrue(menu.waitForExistence(timeout: 30))
            func openFeed(_ tag: String) {
                if !app.buttons["care-feed"].exists { menu.tap(); sleep(1) }
                if !app.buttons["care-feed"].waitForExistence(timeout: 8) { save("\(name)_\(tag)_nofeedbutton"); menu.tap(); sleep(1) }
                app.buttons["care-feed"].tap(); sleep(2)
                save("\(name)_\(tag)")
                menu.tap(); sleep(1)
                if app.buttons["care-feed"].exists { menu.tap(); sleep(1) }
            }
            if name == "portrait" { openFeed("1_feed_empty") } else { openFeed("5_feed_after_buy_landscape") }
            app.buttons["go-out"].tap()
            XCTAssertTrue(app.buttons["town-shop"].waitForExistence(timeout: 10))
            app.buttons["town-shop"].tap(); sleep(2)
            if app.buttons["shop-tab-food"].waitForExistence(timeout: 5) { app.buttons["shop-tab-food"].tap() }
            sleep(2)
            save("\(name)_2_shop_food")
            if name == "portrait" {
                for id in ["berries", "pizza"] {
                    app.buttons["shop-item-\(id)"].tap(); sleep(2)
                    save("portrait_2b_item_sheet_\(id)")
                    if app.buttons["item-qty-plus"].waitForExistence(timeout: 5) { app.buttons["item-qty-plus"].tap() }
                    let buy = app.buttons["item-buy"].exists ? app.buttons["item-buy"] : app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Buy '")).firstMatch
                    if buy.waitForExistence(timeout: 5) { buy.tap(); sleep(1) }
                    app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.15)).press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.95)))
                    sleep(1)
                }
                save("portrait_3_shop_after_buy")
            }
            (app.buttons["shop-back"].exists ? app.buttons["shop-back"] : app.buttons["Back"]).tap(); sleep(2)
            if app.buttons["town-home"].exists { app.buttons["town-home"].tap(); sleep(2) }
            if name == "portrait" { openFeed("4_feed_after_buy") }
        }
    }
}
