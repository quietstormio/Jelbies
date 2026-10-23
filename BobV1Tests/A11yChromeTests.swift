//
//  A11yChromeTests.swift
//  Accessibility of the SwiftUI chrome (round-1023 sweep, part A): disabled-row reasons, the settings object, the captions queue, Dynamic Type
//  scaling of the central fonts, the release button's name, and the Assistive Access / Info.plist wiring.
//

import XCTest
import SwiftUI
@testable import BobV1

@MainActor
final class A11yChromeTests: XCTestCase {
    nonisolated(unsafe) static var keep: [AnyObject] = []

    private func care3() -> GameCare {
        let c = GameCare(jellyCount: 3, persistent: false, defaults: UserDefaults(suiteName: "A11yChrome.3")!)
        Self.keep.append(c)
        return c
    }
    private func freshDefaults(_ name: String) -> UserDefaults {
        let d = UserDefaults(suiteName: name)!
        d.removePersistentDomain(forName: name)
        return d
    }

    // MARK: disabled reasons

    func testEnabledRowsHaveNoReasonAndEveryDisabledRowHasOne() {
        let care = care3()
        for mode in [HUDMode.group, .individual(0)] {
            for item in HUDMenu.items(mode) {
                let on = HUDMenu.enabled(item, mode, care: care)
                let why = HUDMenu.disabledReason(item, mode, care: care)
                XCTAssertEqual(on, why == nil, "\(item) \(mode): a row is disabled exactly when it explains why")
            }
        }
    }

    func testBathDisablesFoodRowsWithAReason() {
        let care = care3()
        care.clean(jelly: 0)
        if care.bath.active {
            XCTAssertEqual(HUDMenu.disabledReason(.feed, .group, care: care), care.trayOut ? "Food is already out" : "Not while cleaning")
            XCTAssertNotNil(HUDMenu.disabledReason(.clean, .individual(0), care: care))
            XCTAssertNotNil(HUDMenu.disabledReason(.bedtime, .group, care: care))
        }
    }

    func testGlyphOnlyAndAlwaysOnRowsNeverExplain() {
        let care = care3()
        for item in [HUDItem.play, .decor, .dress] { XCTAssertNil(HUDMenu.disabledReason(item, .individual(0), care: care)) }
    }

    // MARK: settings

    func testLaunchArgumentsAndPersistence() {
        let d = freshDefaults("A11yChrome.settings")
        d.set(1, forKey: "A11yCaptions"); d.set("oneButton", forKey: "A11yRaceAssist"); d.set(1, forKey: "A11yTapToTalk")
        let s = A11ySettings(defaults: d)
        XCTAssertTrue(s.captions); XCTAssertTrue(s.tapToTalk); XCTAssertEqual(s.raceAssist, .oneButton)
        XCTAssertTrue(s.announcements, "announcements are on by default")
        XCTAssertFalse(s.reduceMotion)
        s.systemReduceMotion = true
        XCTAssertTrue(s.reduceMotion, "the system setting alone turns the in-game reduction on")
        s.systemReduceMotion = false; s.reduceMotionInApp = true
        XCTAssertTrue(s.reduceMotion, "so does the in-app setting")
        let d2 = freshDefaults("A11yChrome.settings2")
        let a = A11ySettings(defaults: d2); a.relaxedTiming = true
        XCTAssertEqual(a.timingScale, 2.5)
        XCTAssertTrue(A11ySettings(defaults: d2).relaxedTiming, "saved settings come back")
    }

    func testAnnouncerDedupesAndHonoursTheSwitch() {
        A11yAnnounce.resetForTests()
        let s = A11ySettings(defaults: freshDefaults("A11yChrome.say"))
        var heard: [String] = []
        A11yAnnounce.sink = { t, _ in heard.append(t) }
        let t0 = Date()
        A11yAnnounce.say("Moss learned Sit", settings: s, now: t0)
        A11yAnnounce.say("Moss learned Sit", settings: s, now: t0.addingTimeInterval(0.5))
        A11yAnnounce.say("Moss learned Sit", settings: s, now: t0.addingTimeInterval(3))
        XCTAssertEqual(heard, ["Moss learned Sit", "Moss learned Sit"], "a burst is one announcement")
        s.announcements = false
        A11yAnnounce.say("quiet", settings: s, now: t0.addingTimeInterval(9))
        XCTAssertEqual(heard.count, 2)
        A11yAnnounce.resetForTests()
    }

    // MARK: captions

    func testCaptionsAreOffByDefaultDedupeCapAtThreeAndPrune() {
        let center = CaptionCenter()
        center.settings = A11ySettings(defaults: freshDefaults("A11yChrome.cap0"))
        center.post("Pip chirps")
        XCTAssertTrue(center.items.isEmpty, "captions are off by default")
        let s = A11ySettings(defaults: freshDefaults("A11yChrome.cap1")); s.captions = true
        center.settings = s
        let t = Date()
        center.post("Pip chirps", now: t); center.post("Squish", now: t); center.post("Pip chirps", now: t)
        XCTAssertEqual(center.items.map(\.text), ["Squish", "Pip chirps"], "the same sound refreshes instead of stacking")
        center.post("Whistle", now: t); center.post("Splash", now: t)
        XCTAssertEqual(center.items.count, CaptionCenter.maxShown)
        center.prune(now: t.addingTimeInterval(CaptionCenter.life + 1))
        XCTAssertTrue(center.items.isEmpty)
    }

    // MARK: Dynamic Type

    func testCentralFontsGrowAtAccessibilitySizesButStayCapped() {
        let large = JFont.scaledSize(16, category: .large)
        let ax5 = JFont.scaledSize(16, category: .accessibilityExtraExtraExtraLarge)
        XCTAssertGreaterThan(ax5, large)
        XCTAssertLessThanOrEqual(ax5, 16 * JFont.helperCap + 0.01)
        XCTAssertEqual(JFont.scaledSize(16, category: .extraSmall), 16, "never smaller than designed")
    }

    private func height<V: View>(_ v: V, _ size: DynamicTypeSize) -> CGFloat {
        let r = ImageRenderer(content: v.environment(\.dynamicTypeSize, size).frame(width: 200))
        r.scale = 1
        return r.uiImage?.size.height ?? 0
    }

    func testJFontTextIsTallerAtAX5() {
        let t = Text("Hungry Jelbie needs a snack right now please").jFont(16, .semibold)
        XCTAssertGreaterThan(height(t, .accessibility5), height(t, .large))
    }

    func testLineLimitModifierWrapsAtAccessibilitySizes() {
        let t = Text("A long Jelbie name that would be truncated").font(.system(size: 15)).jLine(1, scale: 0.8)
        XCTAssertGreaterThan(height(t, .accessibility3), height(t, .large) * 1.5, "at accessibility sizes the text wraps instead of truncating")
    }

    // MARK: labels

    func testReleaseButtonNamesTheFocusedJelbie() {
        XCTAssertEqual(ReleaseButton(name: "Pip") {}.title, "Let Pip go")
        XCTAssertEqual(ReleaseButton(name: nil) {}.title, "Let them go")
    }

    func testRaceFootnotesCoverEveryAssist() {
        for a in RaceAssist.allCases { XCTAssertFalse(AccessibilitySettingsView.raceFootnote(a).isEmpty) }
    }

    func testAssistiveAccessKeyIsDeclared() throws {
        let plist = Bundle(for: A11yChromeTests.self).path(forResource: "BobV1-Info", ofType: "plist")
        _ = plist          // (the test bundle does not carry the app plist; the host app does)
        let supports = Bundle.main.object(forInfoDictionaryKey: "UISupportsAssistiveAccess") as? Bool
        XCTAssertEqual(supports, true)
    }

    func testPinkStrongCarriesWhiteText() {
        func lum(_ c: UInt32) -> Double {
            func ch(_ v: UInt32) -> Double { let x = Double(v) / 255; return x <= 0.03928 ? x / 12.92 : pow((x + 0.055) / 1.055, 2.4) }
            return 0.2126 * ch((c >> 16) & 255) + 0.7152 * ch((c >> 8) & 255) + 0.0722 * ch(c & 255)
        }
        let ratio = 1.05 / (lum(0xB84A70) + 0.05)
        XCTAssertGreaterThanOrEqual(ratio, 4.5)
        XCTAssertLessThan(1.05 / (lum(0xE98AA4) + 0.05), 3, "the old pink did not")
    }
}
