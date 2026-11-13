//
//  LockLookRenderTests.swift
//  Renders the home widgets, Lock Screen accessories, Live Activity banners and the Siri snippet with ImageRenderer (@3x) into LOCKLOOK_OUT
//  (default: the scratchpad locklook/after/ folder) so the look can be judged: the Water button clear of portraits, near-white Jelbies visible
//  on cream, a full large card for one Jelbie, napping home cards, long names, the rounded wake time. Portraits come from LOCKLOOK_PORTRAITS
//  (default: the scratchpad raw/ folder); without them the cards fall back to the initial tile. Fast and deterministic (no Metal).
//

import XCTest
import SwiftUI
import WidgetKit
@testable import BobV1

@MainActor
final class LockLookRenderTests: XCTestCase {
    static let base = "/private/tmp/claude-501/-Users-dmarshall94-Desktop-BobV1/49d32754-b08a-4bfd-999b-3f9f0cada45f/scratchpad/locklook"
    let t0 = Date(timeIntervalSince1970: 1_760_000_000)

    private func outDir() throws -> URL {
        let d = ProcessInfo.processInfo.environment["LOCKLOOK_OUT"] ?? Self.base + "/after"
        try FileManager.default.createDirectory(atPath: d, withIntermediateDirectories: true)
        return URL(fileURLWithPath: d)
    }
    private func portrait(_ name: String) -> UIImage? {
        let d = ProcessInfo.processInfo.environment["LOCKLOOK_PORTRAITS"] ?? Self.base + "/raw"
        return UIImage(contentsOfFile: "\(d)/portrait_\(name).png")
    }

    private func rec(_ id: Int, _ name: String, _ color: String, _ levels: [Float] = [0.95, 0.95, 0.95]) -> JellyRecord {
        JellyRecord(id: id, name: name, color: color, levels: levels, dirt: 0, sparkle: 0, mood: AwayMath.mood(of: levels).rawValue)
    }
    private func states(_ set: String, _ look: String) -> [JellyState] {
        let fine: [Float] = [0.95, 0.95, 0.95]
        func lv(_ i: Int, _ need: [Float]) -> [Float] { look == "needy" && i == 0 || look == "needyQ" && i == 1 || look == "thirst" && i == 0 ? need : fine }
        let thirstyOrHungry: (Int) -> [Float] = { i in look == "needy" ? lv(i, [0.3, 0.95, 0.95]) : lv(i, [0.95, 0.25, 0.95]) }
        let recs: [JellyRecord]
        switch set {
        case "r1": recs = [rec(0, "Lemon", "yellow", thirstyOrHungry(0))]
        case "r2": recs = [rec(0, "Lemon", "yellow", thirstyOrHungry(0)), rec(1, "Sage", "green", thirstyOrHungry(1))]
        case "L3": recs = [rec(0, "Marshmallowy", "teddy", thirstyOrHungry(0)), rec(1, "Snugglebumps", "pearl", thirstyOrHungry(1)), rec(2, "Pumpkinpuffs", "panda", thirstyOrHungry(2))]
        default: recs = [rec(0, "Eliza", "teddy", thirstyOrHungry(0)), rec(1, "Pearl", "pearl", thirstyOrHungry(1)), rec(2, "Bao", "panda", thirstyOrHungry(2))]
        }
        return JellySnapshot(savedAt: t0, jellies: recs).project(at: t0)
    }
    private func pics(_ st: [JellyState]) -> [Int: UIImage] {
        var out: [Int: UIImage] = [:]
        for s in st { if let i = portrait(s.color == "teddy" ? "teddy" : s.color) { out[s.id] = i } }
        return out
    }

    private func save(_ v: some View, _ name: String) throws {
        let r = ImageRenderer(content: v)
        r.scale = 3
        r.isOpaque = false
        let img = try XCTUnwrap(r.uiImage, name)
        XCTAssertGreaterThan(AppleExtrasCaptureTests.distinctColours(img), 12, "\(name) is not blank")
        try XCTUnwrap(img.pngData()).write(to: try outDir().appendingPathComponent("\(name).png"))
    }

    private static func size(_ f: WidgetFamily) -> CGSize {
        switch f {
        case .systemSmall: return CGSize(width: 170, height: 170)
        case .systemMedium: return CGSize(width: 364, height: 170)
        case .systemLarge: return CGSize(width: 364, height: 382)
        default: return CGSize(width: 172, height: 76)
        }
    }
    private static let homeWall = LinearGradient(colors: [Color(red: 0.62, green: 0.78, blue: 0.86), Color(red: 0.86, green: 0.80, blue: 0.90)], startPoint: .top, endPoint: .bottom)
    private static let lockWall = LinearGradient(colors: [Color(red: 0.16, green: 0.20, blue: 0.34), Color(red: 0.42, green: 0.30, blue: 0.40)], startPoint: .top, endPoint: .bottom)

    private func home(_ f: WidgetFamily, _ st: [JellyState], sleeping: Bool = false, queued: [JellyRoute] = []) -> some View {
        let s = Self.size(f)
        return ZStack {
            Self.homeWall
            JellyWidgetContent(family: f, states: st, portraits: pics(st), sleeping: sleeping, showsWater: f != .systemSmall, queued: queued)
                .padding(16)
                .frame(width: s.width, height: s.height)
                .background(WidgetTheme.card)
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        }
        .frame(width: s.width + 28, height: s.height + 28)
        .environment(\.colorScheme, .light)
    }

    func testHomeWidgets() throws {
        for set in ["r1", "r2", "r3"] {
            let n = set.dropFirst()
            try save(home(.systemMedium, states(set, "fine")), "medium_\(set)_fine")
            try save(home(.systemMedium, states(set, "thirst")), "medium_\(set)_water")
            try save(home(.systemMedium, states(set, "thirst"), queued: [.water(0)]), "medium_\(set)_waterQ")
            try save(home(.systemLarge, states(set, "fine")), "large_\(set)_fine")
            try save(home(.systemLarge, states(set, "thirst")), "large_\(set)_water")
            _ = n
        }
        try save(home(.systemMedium, states("r3", "needyQ"), queued: [.water(1)]), "medium_r3_needyQ")
        try save(home(.systemLarge, states("r3", "needyQ"), queued: [.water(1)]), "large_r3_needyQ")
        try save(home(.systemMedium, states("L3", "thirst")), "medium_L3_water")
        try save(home(.systemLarge, states("r1", "needy")), "large_r1_needy")
        try save(home(.systemSmall, states("r1", "fine"), sleeping: true), "small_r1_night")
        try save(home(.systemMedium, states("r3", "fine"), sleeping: true), "medium_r3_night")
        try save(home(.systemMedium, states("r1", "fine"), sleeping: true), "medium_r1_night")
        try save(home(.systemLarge, states("r1", "fine"), sleeping: true), "large_r1_night")
        try save(home(.systemLarge, states("r3", "fine"), sleeping: true), "large_r3_night")
    }

    private func lock(_ st: [JellyState], sleeping: Bool) -> some View {
        let s = Self.size(.accessoryRectangular)
        return ZStack {
            Self.lockWall
            ZStack {
                AccessoryWidgetBackground()
                JellyRectangularView(model: JellyAccessoryModel(states: st, sleeping: sleeping)).padding(8).foregroundStyle(.white)
            }
            .frame(width: s.width, height: s.height)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .frame(width: s.width + 28, height: s.height + 28)
        .environment(\.colorScheme, .dark)
    }

    func testAccessoryAndSiri() throws {
        try save(lock(states("r3", "fine"), sleeping: false), "rect_r3_fine")
        try save(lock(states("r3", "needyQ"), sleeping: false), "rect_r3_needy")
        try save(lock(states("r3", "fine"), sleeping: true), "rect_r3_night")
        try save(lock(states("L3", "needy"), sleeping: false), "rect_L3_needy")
        for (name, look, sleeping) in [("siri_r3_fine", "fine", false), ("siri_r3_needy", "needyQ", false), ("siri_r3_night", "fine", true)] {
            let v = ZStack { Color(white: 0.93); JelbiesSnippetView(states: states("r3", look), sleeping: sleeping).frame(width: 361).padding(16) }
                .fixedSize().environment(\.colorScheme, .light)
            try save(v, name)
        }
    }

    // MARK: Live Activities

    private func attrs(_ kind: JelbiesActivityAttributes.Kind, _ name: String, _ color: String, course: String? = nil) -> JelbiesActivityAttributes {
        JelbiesActivityAttributes(kind: kind, jellyID: 0, jellyName: name, jellyColor: color, startedAt: t0, course: course)
    }
    private func banner(_ a: JelbiesActivityAttributes, _ s: JelbiesActivityAttributes.ContentState) -> some View {
        ZStack {
            Self.lockWall
            JellyActivityLockView(attrs: a, state: s, zPhase: 0.3)
                .frame(width: 364)
                .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(JellyPalette.cream))
                .padding(14)
        }
        .fixedSize()
        .environment(\.colorScheme, .dark)
    }
    private var wake: Date { Calendar.current.date(bySettingHour: 7, minute: 7, second: 0, of: Date.now.addingTimeInterval(86400))! }

    func testActivityBanners() throws {
        let three = ["Eliza", "Pearl", "Bao"], colours = ["teddy", "pearl", "panda"]
        let longs = ["Marshmallowy", "Snugglebumps", "Pumpkinpuffs"]
        let nap = attrs(.nap, three[0], colours[0])
        try save(banner(nap, .sleeping(three, colors: colours, wakeAt: wake)), "nap_r3_sleeping")
        try save(banner(nap, .awake(three, colors: colours)), "nap_r3_stale")
        try save(banner(attrs(.nap, longs[0], "teddy"), .sleeping(longs, colors: colours, wakeAt: wake)), "nap_L3_sleeping")
        try save(banner(attrs(.nap, longs[0], "yellow"), .sleeping([longs[0]], colors: ["yellow"], wakeAt: wake)), "nap_L1_sleeping")
        try save(banner(attrs(.nap, "Lemon", "yellow"), .sleeping(["Lemon", "Sage"], colors: ["yellow", "green"], wakeAt: wake)), "nap_r2_sleeping")
        for c in ["pearl", "panda"] {
            let a = attrs(.race, c == "pearl" ? "Pearl" : "Bao", c, course: "Puddle")
            try save(banner(a, .race(position: 2, racers: 4, progress: 0.42, lap: 2, laps: 3)), "race_\(c)_running")
            try save(banner(a, .finished(place: 1, racers: 4, drops: 120, laps: 3)), "race_\(c)_won")
        }
        let long = attrs(.race, "Marshmallowy", "teddy", course: "Puddle")
        try save(banner(long, .race(position: 2, racers: 4, progress: 0.42, lap: 2, laps: 3)), "race_long_running")
        try save(banner(long, .finished(place: 1, racers: 4, drops: 120, laps: 3)), "race_long_won")
    }

    // MARK: Logic pins

    func testWakeTextIsRounded() {
        var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone.current
        let a = attrs(.nap, "Lemon", "yellow")
        let seven07 = cal.date(bySettingHour: 7, minute: 7, second: 0, of: t0)!
        let s = JelbiesActivityAttributes.ContentState.sleeping(["Lemon"], wakeAt: seven07)
        XCTAssertTrue(a.detail(s, roundedWake: true).hasPrefix("Up around "), a.detail(s, roundedWake: true))
        XCTAssertFalse(a.detail(s, roundedWake: true).contains(":"), "no minutes on the kid card")
        XCTAssertTrue(a.detail(s).hasPrefix("Up at "), "the plain detail keeps the exact time")
        let eight = cal.date(bySettingHour: 7, minute: 40, second: 0, of: t0)!
        XCTAssertEqual(a.nearestHour(eight), cal.date(bySettingHour: 8, minute: 0, second: 0, of: t0)!)
        XCTAssertEqual(a.nearestHour(seven07), cal.date(bySettingHour: 7, minute: 0, second: 0, of: t0)!)
    }

    func testRectangularLineAndHomeHeadline() {
        let fine = states("r3", "fine")
        XCTAssertEqual(JellyStatus.rectangularLine(fine, sleeping: false), "All 3 are happy")
        XCTAssertEqual(JellyStatus.rectangularLine(fine, sleeping: true), "Everyone is napping")
        let needy = states("r3", "needyQ")          // Pearl thirsty
        XCTAssertTrue(JellyStatus.rectangularLine(needy, sleeping: false).hasPrefix("Pearl\u{00A0}is\u{00A0}thirsty"), JellyStatus.rectangularLine(needy, sleeping: false))
        XCTAssertEqual(JellyStatus.line(fine, sleeping: false), "Eliza is happy · Pearl happy · Bao happy", "the existing line is unchanged")
        XCTAssertEqual(JellyStatus.headline(fine[0], sleeping: true), "Eliza is napping")
        XCTAssertEqual(JellyStatus.headline(needy[1], sleeping: true), needy[1].headline, "a needy Jelbie still shows its need")
        XCTAssertEqual(JellyStatus.headline(fine[0], sleeping: false), fine[0].headline)
    }

    func testWakeCardKeepsColours() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("locklook-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        var utc = Calendar(identifier: .gregorian); utc.timeZone = TimeZone(identifier: "UTC")!
        var clock = utc.date(from: DateComponents(year: 2025, month: 10, day: 20, hour: 22))!
        let m = MockActivityDriver()
        let l = LiveActivities(driver: m, defaults: UserDefaults(suiteName: "locklook.\(UUID().uuidString)")!)
        l.now = { clock }; l.calendar = utc; l.directory = dir
        Self.keep.append(l); Self.keep.append(m)
        let names = ["Eliza", "Pearl", "Bao"], colours = ["teddy", "pearl", "panda"]
        l.leftActive(names: names, colors: colours)
        XCTAssertTrue(l.napLive)
        clock = utc.date(from: DateComponents(year: 2025, month: 10, day: 21, hour: 9))!
        l.returnedActive(names: names, colors: colours)
        guard case .end(_, let e) = try XCTUnwrap(m.calls.last) else { return XCTFail("end") }
        XCTAssertEqual(e.phase, .awake); XCTAssertEqual(e.sleeperColors, colours, "the woke card keeps every face's colour")
    }
    nonisolated(unsafe) static var keep: [AnyObject] = []
}
