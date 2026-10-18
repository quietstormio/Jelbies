//
//  WidgetPreviewTests.swift
//  Renders the real in-app portrait path (JellyPortraitRenderer -> PNG in a stand-in "group container") and every widget family with
//  ImageRenderer at the true iPhone 17 Pro Max point sizes (@3x), into WIDGET_OUT (default: the scratchpad widget/ folder).
//  Asserts the portraits are real renders (not blank), the PNGs round-trip, and that every family renders non-empty.
//

import XCTest
import SwiftUI
import WidgetKit
@testable import BobV1

@MainActor
final class WidgetPreviewTests: XCTestCase {
    nonisolated(unsafe) static var keep: [AnyObject] = []
    static let outPath = "/private/tmp/claude-501/-Users-dmarshall94-Desktop-BobV1/6a40096b-092a-48d0-8cbe-4e00ccea7702/scratchpad/widget"
    let t0 = Date(timeIntervalSince1970: 5_000_000)

    private func outDir() throws -> URL {
        let d = ProcessInfo.processInfo.environment["WIDGET_OUT"] ?? Self.outPath
        try FileManager.default.createDirectory(atPath: d, withIntermediateDirectories: true)
        return URL(fileURLWithPath: d)
    }

    /// Point sizes of the widget families on an iPhone 17 Pro Max.
    static func size(_ f: WidgetFamily) -> CGSize {
        switch f {
        case .systemSmall: return CGSize(width: 170, height: 170)
        case .systemMedium: return CGSize(width: 364, height: 170)
        case .systemLarge: return CGSize(width: 364, height: 382)
        case .accessoryRectangular: return CGSize(width: 172, height: 76)
        case .accessoryCircular: return CGSize(width: 76, height: 76)
        default: return CGSize(width: 170, height: 170)
        }
    }

    /// One family on a stand-in wallpaper, as the Home / Lock Screen would show it.
    static func widget(_ f: WidgetFamily, _ states: [JellyState], _ pics: [Int: UIImage]) -> some View {
        let s = size(f)
        let lock = f == .accessoryRectangular || f == .accessoryCircular
        return ZStack {
            (lock ? LinearGradient(colors: [Color(red: 0.16, green: 0.20, blue: 0.34), Color(red: 0.42, green: 0.30, blue: 0.40)], startPoint: .top, endPoint: .bottom)
                  : LinearGradient(colors: [Color(red: 0.62, green: 0.78, blue: 0.86), Color(red: 0.86, green: 0.80, blue: 0.90)], startPoint: .top, endPoint: .bottom))
            ZStack {
                if lock { AccessoryWidgetBackground() } else { WidgetTheme.card }
                JellyWidgetContent(family: f, states: states, portraits: pics)
                    .padding(lock ? (f == .accessoryCircular ? 4 : 8) : 16)
                    .foregroundStyle(lock ? Color.white : WidgetTheme.ink)
            }
            .frame(width: s.width, height: s.height)
            .clipShape(RoundedRectangle(cornerRadius: lock ? (f == .accessoryCircular ? 38 : 14) : 24, style: .continuous))
            .background(RoundedRectangle(cornerRadius: lock ? (f == .accessoryCircular ? 38 : 14) : 24, style: .continuous).fill(.black.opacity(0.2)).blur(radius: 6).offset(y: 3))
        }
        .frame(width: s.width + 28, height: s.height + 28)
        .environment(\.colorScheme, lock ? .dark : .light)
    }

    static func png(_ v: some View, scale: CGFloat = 3) -> UIImage? {
        let r = ImageRenderer(content: v)
        r.scale = scale
        return r.uiImage
    }
    private func save(_ img: UIImage?, _ url: URL) throws {
        let data = try XCTUnwrap(img?.pngData(), url.lastPathComponent)
        try data.write(to: url)
    }

    private func rec(_ id: Int, _ name: String, _ color: String, levels: [Float], dirt: Float = 0, sparkle: Float = 0) -> JellyRecord {
        JellyRecord(id: id, name: name, color: color, levels: levels, dirt: dirt, sparkle: sparkle, mood: AwayMath.mood(of: levels).rawValue)
    }

    func testPortraitsAndEveryFamily() throws {
        let out = try outDir()
        let group = FileManager.default.temporaryDirectory.appendingPathComponent("widget-group-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: group, withIntermediateDirectories: true)

        // 1. the in-app portrait path: real renderer -> PNG file, for three colours and three coats
        let t = Date()
        let renderer = try XCTUnwrap(JellyPortraitRenderer(), "Metal renderer")
        let setupSeconds = Date().timeIntervalSince(t)
        let looks: [(Int, Palette, Float, Float)] = [(0, WidgetBridge.palette(0), 0, 0), (1, WidgetBridge.palette(1), 0.5, 0), (2, WidgetBridge.palette(2), 0, 1)]
        let t1 = Date()
        for (id, key, dirt, sparkle) in looks {
            let px = try XCTUnwrap(renderer.render(palette: key, look: JellyPortraitRenderer.look(dirt: dirt, sparkle: sparkle)))
            XCTAssertTrue(JellyPortraitRenderer.writePNG(bgra: px, size: renderer.size, to: group.appendingPathComponent(JellyShare.portraitFile(id))))
            var colours = Set<UInt32>()
            for o in stride(from: 0, to: px.count - 3, by: 4 * 97) {
                let b = UInt32(px[o]), g = UInt32(px[o + 1]), r = UInt32(px[o + 2])
                colours.insert((r << 16) | (g << 8) | b)
            }
            let distinct = colours.count
            XCTAssertGreaterThan(distinct, 40, "portrait \(id) is a real shaded render, not a flat fill")
        }
        print("WIDGETCAP portrait setup \(String(format: "%.2f", setupSeconds)) s, \(looks.count) renders \(String(format: "%.2f", Date().timeIntervalSince(t1))) s")
        Self.keep.append(renderer)
        var pics: [Int: UIImage] = [:]
        for (id, _, _, _) in looks {
            let img = try XCTUnwrap(UIImage(contentsOfFile: group.appendingPathComponent(JellyShare.portraitFile(id)).path))
            XCTAssertEqual(img.size.width * img.scale, 360)
            pics[id] = img
            try save(img, out.appendingPathComponent("portrait-\(id).png"))
        }

        // 2. the families
        let three = JellySnapshot(savedAt: t0, jellies: [
            rec(0, "Bob", "blue", levels: [0.95, 0.9, 0.9]),
            rec(1, "Pip", "yellow", levels: [0.9, 0.9, 0.9], dirt: 0.5),
            rec(2, "Moss", "green", levels: [0.9, 0.9, 0.9], sparkle: 1),
        ])
        let one = JellySnapshot(savedAt: t0, jellies: [rec(0, "Bob", "blue", levels: [1, 1, 1])])
        let scenes: [(String, JellySnapshot, TimeInterval)] = [
            ("1jelly_now", one, 0), ("1jelly_plus5h", one, 5.5 * 3600), ("1jelly_plus12h", one, 12 * 3600),
            ("3jellies_now", three, 0), ("3jellies_plus12h", three, 12 * 3600),
        ]
        let families: [(String, WidgetFamily)] = [("small", .systemSmall), ("medium", .systemMedium), ("large", .systemLarge), ("rect", .accessoryRectangular), ("circ", .accessoryCircular)]
        var sheet: [(String, UIImage)] = []
        for (sname, snap, ahead) in scenes {
            let states = snap.project(at: t0.addingTimeInterval(ahead))
            for (fname, fam) in families {
                let img = try XCTUnwrap(Self.png(Self.widget(fam, states, pics)), "\(sname) \(fname)")
                let s = Self.size(fam)
                XCTAssertEqual(img.size.width * img.scale, (s.width + 28) * 3, accuracy: 1)
                try save(img, out.appendingPathComponent("\(sname)_\(fname).png"))
                if fname != "circ" || sname == "1jelly_now" { sheet.append(("\(sname) \(fname)", img)) }
            }
        }
        // the first-launch look: no portrait yet, nothing to show
        try save(Self.png(Self.widget(.systemSmall, one.project(at: t0), [:])), out.appendingPathComponent("no_portrait_small.png"))
        try save(Self.png(Self.widget(.systemMedium, [], [:])), out.appendingPathComponent("empty_medium.png"))
        print("WIDGETCAP wrote \(sheet.count) family images to \(out.path)")
    }

    private func waitFor(_ what: String, timeout: TimeInterval = 40, _ cond: () -> Bool) {
        let end = Date().addingTimeInterval(timeout)
        while !cond(), Date() < end { RunLoop.current.run(until: Date().addingTimeInterval(0.05)) }
        XCTAssertTrue(cond(), what)
    }

    /// The bridge end to end: a first run renders the missing portrait while playing; a changed look waits for leaving `.active`.
    func testBridgeRendersPortraitsAtTheRightTimes() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("widget-bridge-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        var clock = t0, reloads = 0
        let b = WidgetBridge(directory: dir, now: { clock }, rendersPortraits: true, reload: { reloads += 1 }); Self.keep.append(b)
        func input(dirt: Float) -> WidgetBridge.Input { WidgetBridge.Input(id: 0, name: "Bob", color: "blue", levels: [0.6, 0.9, 0.9], dirt: dirt, sparkle: 0) }
        let png = dir.appendingPathComponent(JellyShare.portraitFile(0))

        b.publish([input(dirt: 0)], force: false)                              // first run, playing: no portrait yet -> rendered
        waitFor("first portrait") { b.portraitRenders == 1 }
        XCTAssertTrue(FileManager.default.fileExists(atPath: png.path))
        XCTAssertEqual(JellySnapshot.read(from: dir)?.jellies.first?.look, WidgetBridge.lookKey(input(dirt: 0)), "the snapshot names the look the PNG shows")
        let reloadsAfterFirst = reloads
        XCTAssertGreaterThanOrEqual(reloadsAfterFirst, 2, "the new portrait forces a reload")

        clock = t0.addingTimeInterval(600)
        b.publish([input(dirt: 0.6)], force: false)                           // dirtier while playing: no hitch now
        RunLoop.current.run(until: Date().addingTimeInterval(1))
        XCTAssertEqual(b.portraitRenders, 1, "a changed look is not rendered mid-play")
        b.leftActive([input(dirt: 0.6)])                                       // leaving: now
        waitFor("portrait on leave") { b.portraitRenders == 2 }
        XCTAssertEqual(JellySnapshot.read(from: dir)?.jellies.first?.look, WidgetBridge.lookKey(input(dirt: 0.6)))
        let data = try Data(contentsOf: png)
        XCTAssertNotNil(UIImage(data: data))
    }
}
