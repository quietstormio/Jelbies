//
//  AppleExtrasCaptureTests.swift
//  Renders the Apple extras with ImageRenderer (@3x) into APPLE_CAPS_OUT (default: the scratchpad apple_caps_v2/ folder), on stand-in
//  wallpapers / the Island's black: the Lock Screen accessories (circular / rectangular / inline), StandBy small / medium at night, the three Live
//  Activities (race / nap / pep) as the Lock Screen banner and the Dynamic Island compact + expanded, and the Siri snippet. Asserts every image
//  renders at the expected size and is not blank.
//

import XCTest
import SwiftUI
import WidgetKit
@testable import BobV1

@MainActor
final class AppleExtrasCaptureTests: XCTestCase {
    static let outPath = "/private/tmp/claude-501/-Users-dmarshall94-Desktop-BobV1/6a40096b-092a-48d0-8cbe-4e00ccea7702/scratchpad/apple_caps_v2"
    let t0 = Date(timeIntervalSince1970: 1_760_000_000)
    private var written: [String] = []

    private func outDir() throws -> URL {
        let d = ProcessInfo.processInfo.environment["APPLE_CAPS_OUT"] ?? Self.outPath
        try FileManager.default.createDirectory(atPath: d, withIntermediateDirectories: true)
        return URL(fileURLWithPath: d)
    }
    private func rec(_ id: Int, _ name: String, _ color: String, levels: [Float] = [1, 1, 1], dirt: Float = 0, sparkle: Float = 0) -> JellyRecord {
        JellyRecord(id: id, name: name, color: color, levels: levels, dirt: dirt, sparkle: sparkle, mood: AwayMath.mood(of: levels).rawValue)
    }
    /// Bob hungry, Pip dirty, Moss sparkling (daytime); and everyone fine at night.
    private var day: [JellyState] {
        JellySnapshot(savedAt: t0, jellies: [rec(0, "Bob", "blue", levels: [0.4, 0.9, 0.9]), rec(1, "Pip", "yellow", dirt: 0.5), rec(2, "Moss", "green", levels: [0.95, 0.95, 0.95], sparkle: 1)]).project(at: t0)
    }
    private var night: [JellyState] {
        JellySnapshot(savedAt: t0, jellies: [rec(0, "Bob", "blue", levels: [0.9, 0.9, 0.9]), rec(1, "Pip", "yellow", levels: [0.95, 0.95, 0.95]), rec(2, "Moss", "green", levels: [0.8, 0.9, 0.9])]).project(at: t0)
    }
    private var oneThirsty: [JellyState] { JellySnapshot(savedAt: t0, jellies: [rec(0, "Bob", "blue", levels: [0.9, 0.3, 0.9])]).project(at: t0) }

    private static let lockWall = LinearGradient(colors: [Color(red: 0.16, green: 0.20, blue: 0.34), Color(red: 0.42, green: 0.30, blue: 0.40)], startPoint: .top, endPoint: .bottom)
    private static let homeWall = LinearGradient(colors: [Color(red: 0.62, green: 0.78, blue: 0.86), Color(red: 0.86, green: 0.80, blue: 0.90)], startPoint: .top, endPoint: .bottom)

    private func save(_ v: some View, _ name: String, expect: CGSize? = nil, scale: CGFloat = 3) throws {
        let r = ImageRenderer(content: v)
        r.scale = scale
        r.isOpaque = false
        let img = try XCTUnwrap(r.uiImage, name)
        if let e = expect {
            XCTAssertEqual(img.size.width * img.scale, e.width * scale, accuracy: 1, "\(name) width")
            XCTAssertEqual(img.size.height * img.scale, e.height * scale, accuracy: 1, "\(name) height")
        }
        XCTAssertGreaterThan(Self.distinctColours(img), 12, "\(name) is not blank")
        try XCTUnwrap(img.pngData()).write(to: try outDir().appendingPathComponent("\(name).png"))
        written.append(name)
    }
    static func distinctColours(_ img: UIImage) -> Int {
        guard let cg = img.cgImage, let data = cg.dataProvider?.data, let p = CFDataGetBytePtr(data) else { return 0 }
        var set = Set<UInt32>()
        let n = CFDataGetLength(data)
        for o in stride(from: 0, to: n - 3, by: 4 * 29) { set.insert(UInt32(p[o]) << 16 | UInt32(p[o + 1]) << 8 | UInt32(p[o + 2])) }
        return set.count
    }

    // MARK: Lock Screen accessories

    private func lock(_ content: some View, size: CGSize, corner: CGFloat, pad: CGFloat) -> some View {
        ZStack {
            Self.lockWall
            ZStack {
                AccessoryWidgetBackground()
                content.padding(pad).foregroundStyle(.white)
            }
            .frame(width: size.width, height: size.height)
            .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
        }
        .frame(width: size.width + 28, height: size.height + 28)
        .environment(\.colorScheme, .dark)
    }

    func testLockScreenAccessories() throws {
        let dayM = JellyAccessoryModel(states: day), nightM = JellyAccessoryModel(states: night, sleeping: true)
        let queuedM = JellyAccessoryModel(states: oneThirsty, queued: [.water(0)])
        try save(lock(JellyCircularView(model: dayM), size: CGSize(width: 76, height: 76), corner: 38, pad: 3), "lock_circular_day", expect: CGSize(width: 104, height: 104))
        try save(lock(JellyCircularView(model: nightM), size: CGSize(width: 76, height: 76), corner: 38, pad: 3), "lock_circular_night", expect: CGSize(width: 104, height: 104))
        try save(lock(JellyCircularView(model: JellyAccessoryModel(states: [])), size: CGSize(width: 76, height: 76), corner: 38, pad: 3), "lock_circular_empty", expect: CGSize(width: 104, height: 104))
        try save(lock(JellyRectangularView(model: dayM), size: CGSize(width: 172, height: 76), corner: 14, pad: 8), "lock_rectangular_day", expect: CGSize(width: 200, height: 104))
        try save(lock(JellyRectangularView(model: nightM), size: CGSize(width: 172, height: 76), corner: 14, pad: 8), "lock_rectangular_night", expect: CGSize(width: 200, height: 104))
        try save(lock(JellyRectangularView(model: queuedM), size: CGSize(width: 172, height: 76), corner: 14, pad: 8), "lock_rectangular_queued", expect: CGSize(width: 200, height: 104))
        // inline: the one line above the clock, as the Lock Screen draws it (white, rounded 13 pt)
        for (name, m) in [("lock_inline_day", dayM), ("lock_inline_night", nightM), ("lock_inline_one", JellyAccessoryModel(states: oneThirsty))] {
            let v = ZStack {
                Self.lockWall
                JellyInlineView(model: m).font(.system(size: 14, weight: .semibold, design: .rounded)).foregroundStyle(.white)
            }
            .frame(width: 260, height: 36)
            .environment(\.colorScheme, .dark)
            try save(v, name, expect: CGSize(width: 260, height: 36))
        }
    }

    // MARK: StandBy

    private func standBy(_ family: WidgetFamily, _ m: JellyAccessoryModel, tinted: Bool = false) -> some View {
        let s = family == .systemSmall ? CGSize(width: 170, height: 170) : CGSize(width: 364, height: 170)
        return ZStack {
            Color.black
            ZStack {
                JellyPalette.night
                JellyStandByView(family: family, model: m, tinted: tinted).padding(14)
            }
            .frame(width: s.width, height: s.height)
            .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        }
        .frame(width: s.width + 28, height: s.height + 28)
        .environment(\.colorScheme, .dark)
    }

    func testStandBy() throws {
        let nightM = JellyAccessoryModel(states: night, sleeping: true), dayM = JellyAccessoryModel(states: day)
        try save(standBy(.systemSmall, nightM), "standby_small_night", expect: CGSize(width: 198, height: 198))
        try save(standBy(.systemMedium, nightM), "standby_medium_night", expect: CGSize(width: 392, height: 198))
        try save(standBy(.systemSmall, dayM), "standby_small_day", expect: CGSize(width: 198, height: 198))
        try save(standBy(.systemMedium, dayM), "standby_medium_day", expect: CGSize(width: 392, height: 198))
        try save(standBy(.systemMedium, nightM, tinted: true), "standby_medium_night_tinted", expect: CGSize(width: 392, height: 198))
        try save(standBy(.systemSmall, JellyAccessoryModel(states: oneThirsty)), "standby_small_one", expect: CGSize(width: 198, height: 198))
    }

    // MARK: Live Activities

    private var raceAttrs: JelbiesActivityAttributes { JelbiesActivityAttributes(kind: .race, jellyID: 0, jellyName: "Bob", jellyColor: "blue", startedAt: t0) }
    private var napAttrs: JelbiesActivityAttributes { JelbiesActivityAttributes(kind: .nap, jellyID: 0, jellyName: "Bob", jellyColor: "blue", startedAt: t0) }
    private var pepAttrs: JelbiesActivityAttributes { JelbiesActivityAttributes(kind: .pep, jellyID: 1, jellyName: "Pip", jellyColor: "yellow", startedAt: t0) }
    private var wake: Date { Calendar.current.date(bySettingHour: 6, minute: 0, second: 0, of: Date.now.addingTimeInterval(86400))! }

    /// The Lock Screen banner: cream card, 364 pt wide, its natural height.
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

    func testLiveActivityBanners() throws {
        try save(banner(raceAttrs, .race(position: 2, racers: 4, progress: 0.42, lap: 2, laps: 3)), "la_race_lock")
        try save(banner(raceAttrs, .finished(place: 1, racers: 4, drops: 12, laps: 3)), "la_race_won_lock")
        try save(banner(raceAttrs, .finished(place: 3, racers: 4, drops: 4, laps: 3)), "la_race_third_lock")
        try save(banner(napAttrs, .sleeping(["Bob", "Pip", "Moss"], wakeAt: wake)), "la_nap_lock")
        try save(banner(napAttrs, .sleeping(["Bob"], wakeAt: wake)), "la_nap_one_lock")
        try save(banner(napAttrs, .awake(["Bob", "Pip", "Moss"])), "la_nap_morning_lock")
        try save(banner(pepAttrs, .refilling(until: Date.now.addingTimeInterval(5 * 3600 + 23 * 60))), "la_pep_lock")
        try save(banner(pepAttrs, .refilled), "la_pep_refilled_lock")
    }

    /// The Dynamic Island compact: leading | camera | trailing on the black pill.
    private func compact(_ a: JelbiesActivityAttributes, _ s: JelbiesActivityAttributes.ContentState) -> some View {
        ZStack {
            Color(white: 0.12)
            HStack(spacing: 0) {
                JellyIslandCompactLeading(attrs: a, state: s).frame(width: 40)
                Circle().fill(Color.black).frame(width: 30, height: 30).frame(width: 90)
                JellyIslandCompactTrailing(attrs: a, state: s).frame(width: 56)
            }
            .frame(width: 186, height: 37)
            .background(Capsule().fill(Color.black))
            .overlay(Capsule().strokeBorder(JellyPalette.body(a.jellyColor).opacity(0.5), lineWidth: 1))
        }
        .frame(width: 214, height: 65)
        .environment(\.colorScheme, .dark)
    }
    private func expanded(_ a: JelbiesActivityAttributes, _ s: JelbiesActivityAttributes.ContentState) -> some View {
        ZStack {
            Color(white: 0.12)
            JellyIslandExpanded(attrs: a, state: s, zPhase: 0.3)
                .padding(.horizontal, 14).padding(.vertical, 12)
                .frame(width: 364)
                .background(RoundedRectangle(cornerRadius: 44, style: .continuous).fill(Color.black))
                .overlay(RoundedRectangle(cornerRadius: 44, style: .continuous).strokeBorder(JellyPalette.body(a.jellyColor).opacity(0.5), lineWidth: 1))
                .padding(14)
        }
        .fixedSize()
        .environment(\.colorScheme, .dark)
    }

    func testDynamicIsland() throws {
        let race = JelbiesActivityAttributes.ContentState.race(position: 2, racers: 4, progress: 0.42, lap: 2, laps: 3)
        let won = JelbiesActivityAttributes.ContentState.finished(place: 1, racers: 4, drops: 12, laps: 3)
        let nap = JelbiesActivityAttributes.ContentState.sleeping(["Bob", "Pip", "Moss"], wakeAt: wake)
        let pep = JelbiesActivityAttributes.ContentState.refilling(until: Date.now.addingTimeInterval(5 * 3600 + 23 * 60))
        try save(compact(raceAttrs, race), "di_compact_race", expect: CGSize(width: 214, height: 65))
        try save(compact(raceAttrs, won), "di_compact_race_won", expect: CGSize(width: 214, height: 65))
        try save(compact(napAttrs, nap), "di_compact_nap", expect: CGSize(width: 214, height: 65))
        try save(compact(pepAttrs, pep), "di_compact_pep", expect: CGSize(width: 214, height: 65))
        try save(expanded(raceAttrs, race), "di_expanded_race")
        try save(expanded(raceAttrs, won), "di_expanded_race_won")
        try save(expanded(napAttrs, nap), "di_expanded_nap")
        try save(expanded(pepAttrs, pep), "di_expanded_pep")
        // the minimal face
        let minimal = ZStack { Color(white: 0.12); ZStack { Circle().fill(Color.black); JellyIslandMinimal(attrs: napAttrs, state: nap) }.frame(width: 37, height: 37) }.frame(width: 65, height: 65)
        try save(minimal, "di_minimal_nap", expect: CGSize(width: 65, height: 65))
    }

    // MARK: Siri snippet

    func testSiriSnippet() throws {
        for (name, states, sleeping) in [("siri_snippet_day", day, false), ("siri_snippet_night", night, true), ("siri_snippet_one", oneThirsty, false), ("siri_snippet_empty", [], false)] {
            let v = ZStack {
                Color(white: 0.93)
                JelbiesSnippetView(states: states, sleeping: sleeping).frame(width: 361).padding(16)
            }
            .fixedSize()
            .environment(\.colorScheme, .light)
            try save(v, name)
        }
        // the in-game panel
        let d = UserDefaults(suiteName: "extras.panel.cap")!
        let live = LiveActivities(driver: MockActivityDriver(), defaults: d)
        let panel = ZStack { Color(red: 0.55, green: 0.62, blue: 0.70); AppleExtrasPanel(live: live) {}.padding(20) }.fixedSize().environment(\.colorScheme, .light)
        try save(panel, "extras_panel")
        print("APPLECAP wrote \(written.count) images to \(try outDir().path)")
    }
}
