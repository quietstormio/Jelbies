//
//  RunOutTests.swift
//  The outing run-out (GameCare+Outing.swift): the Jelbies are still running at full speed when the fade covers the screen, nobody stops, and after the trip's swap
//  everybody is home again. Frames (real renderer, portrait) go to RUNOUT_OUT (TEST_RUNNER_RUNOUT_OUT) as runout_<n>_<k>.png plus a sheet.
//
import XCTest
import simd
import UIKit
@testable import BobV1

@MainActor
final class RunOutTests: XCTestCase {
    static var dir: String? { ProcessInfo.processInfo.environment["RUNOUT_OUT"].flatMap { $0.isEmpty ? nil : $0 } }
    override func setUp() { RoomLayout.dynamicBoxes = [] }
    override func tearDown() { RoomLayout.dynamicBoxes = []; GameCamera.clearRoam(); GameCamera.configureRoom(count: 1); _ = GameCamera.camera(aspect: 440.0 / 956.0) }

    struct Result { var minSpeedAtCover: Float; var homeErr: Float; var report: [String]; var fadeStart: Float }

    func runScene(count n: Int, plan: Float? = nil) throws -> Result {
        let aspect: Float = 603.0 / 1311.0
        if n > 1 { GameCamera.configureRoom(count: 3, option: .A, wide: 2); _ = GameCamera.camera(aspect: aspect); GameCamera.refreshRoam(aspect: aspect) }
        else { GameCamera.configureRoom(count: 1); _ = GameCamera.camera(aspect: aspect) }
        let r = FocusAnyRun(count: n, peers: true)
        W2CaptureTests.keep.append(r.care)
        for a in r.actors { a.brain?.autonomy = true; a.brain?.restTimer = 1e6 }          // (autonomy on, as in the room; nobody wanders off by himself)
        r.care.groomBook.actors = r.actors
        let spots = JellyRoster.spawnSpots(count: n)
        for (i, a) in r.actors.enumerated() { r.place(i, at: spots[i]) }
        for _ in 0..<60 { r.tick() }
        let homes = r.actors.map(\.floor)
        let dt = r.actors[0].sim.stepDt
        let shot = (Self.dir != nil && plan != nil) ? W2CaptureTests.Shot(r, W: 603, H: 1311) : nil
        var report: [String] = []
        var fadeStart: Float?, t: Float = 0, wipe: Float = 0
        var frames: [(LockImage, String)] = []
        var stoppedBeforeCover = false
        var lastSpeeds = [Float](repeating: 99, count: n)
        func at(_ a: JellyActor) -> SIMD2<Float> { GameCare.floorPos(a.brain!, a.sim) }          // (`floor` reports the spot he LEFT FROM while he is out)
        var prev = r.actors.map(at)
        var swapped = false, swapT: Float = 0, returnStart: Float?
        r.care.runOut(Array(0..<n)) { fadeStart = t }
        let wanted: [Float] = plan.map { fs in (0..<5).map { Float($0) / 5 * fs } + [fs + 0.15, fs + 0.3, fs + 0.45] } ?? []          // capture times (seconds from the start)
        var step = 0
        func snap(_ label: String) {
            guard let shot else { return }
            var (img, _) = shot.frame(r)
            if wipe > 0 { img = Self.veil(img, wipe) }
            frames.append((img, label))
        }
        // phase 1: run until the fade has covered the screen
        var guardN = 0
        var captured = Set<Int>()
        while guardN < 60 * 12 {
            r.tick(); r.care.tickOutExit(r.actors, dt: dt); t += dt; guardN += 1; step += 1
            if let fs = fadeStart { wipe = min(1, (t - fs) / 0.45) }
            // speed of each runner over the last 6 steps
            if step % 6 == 0 {
                for (k, a) in r.actors.enumerated() {
                    let p = at(a); lastSpeeds[k] = simd_length(p - prev[k]) / (6 * dt); prev[k] = p
                    if fadeStart != nil, wipe < 1, lastSpeeds[k] < 1.2 { stoppedBeforeCover = true }
                }
            }
            if let k = wanted.indices.first(where: { wanted[$0] <= t && !captured.contains($0) }) {
                captured.insert(k)
                snap(String(format: "t=%.2fs wipe %.2f speeds %@", t, wipe, lastSpeeds.map { String(format: "%.1f", $0) }.joined(separator: "/")))
                report.append(String(format: "frame %d t=%.2f wipe=%.2f pos %@ speeds %@", k, t, wipe, r.actors.map { String(format: "(%.1f,%.1f)", at($0).x, at($0).y) }.joined(separator: " "), lastSpeeds.map { String(format: "%.2f", $0) }.joined(separator: "/")))
            }
            if wipe >= 1 { break }
        }
        XCTAssertNotNil(fadeStart, "the fade started")
        XCTAssertFalse(stoppedBeforeCover, "nobody slowed below running pace before the screen was covered")
        let coverSpeeds = lastSpeeds
        report.append("speeds at cover: \(coverSpeeds)")
        // the trip's swap (the park's): remember the spots they left from, send them away, bring them back
        var home2: [Int: SIMD2<Float>] = [:]
        for a in r.actors { home2[a.id] = a.floor }
        for (i, a) in r.actors.enumerated() { XCTAssertLessThan(simd_distance(home2[i]!, homes[i]), 0.5, "the saved home is where he left from (\(i))"); r.care.rehome(a, at: SIMD2(40, 40)) }
        var ret = 0
        while ret < 60 * 4 {
            r.tick(); r.care.tickOutExit(r.actors, dt: dt); ret += 1
            if ret == 20 {          // the way back: everybody comes home at the spot he left from
                for a in r.actors { r.care.rehome(a, at: a.brain!.fixed(home2[a.id]!)) }
                returnStart = Float(ret)
                wipe = 0.6; snap("return: fade-in begins (wipe 0.6)")
            }
            if ret == 20 + 30 { wipe = 0; snap("return: 0.5 s later") }
            if ret == 20 + 150 { snap("return: 2.5 s later (tidied)") }
        }
        _ = (swapped, swapT, returnStart)
        var worst: Float = 0
        for (i, a) in r.actors.enumerated() {
            let d = simd_distance(a.floor, homes[i]); worst = max(worst, d)
            XCTAssertLessThan(a.floor.y, GameCamera.roamMaxZ + 0.6, "\(i) is inside the room again (z \(a.floor.y))")
            XCTAssertFalse(a.sim.arenaSuspended, "the arena wall is back (\(i))")
            XCTAssertFalse(a.brain!.hurry, "no leftover hurry (\(i))")
            XCTAssertNil(a.outingHome)
        }
        XCTAssertTrue(r.care.outing.lifted.isEmpty)
        XCTAssertLessThan(worst, 1.0, "back near where they left from")
        report.append("worst home error \(worst)")
        if let dir = Self.dir, !frames.isEmpty {
            try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
            for (k, f) in frames.enumerated() { try f.0.uiImage()?.pngData()?.write(to: URL(fileURLWithPath: "\(dir)/runout_\(n)_\(k).png")) }
            try Self.sheet(frames, cols: 4).pngData()?.write(to: URL(fileURLWithPath: "\(dir)/runout_\(n)_sheet.png"))
        }
        try? report.joined(separator: "\n").write(toFile: (Self.dir ?? "/tmp") + "/runout_\(n)_report.txt", atomically: true, encoding: .utf8)
        return Result(minSpeedAtCover: coverSpeeds.min() ?? 0, homeErr: worst, report: report, fadeStart: fadeStart ?? 0)
    }

    static func veil(_ img: LockImage, _ a: Float) -> LockImage {
        var px = img.bgra
        for i in stride(from: 0, to: px.count, by: 4) { for c in 0..<3 { px[i + c] = UInt8(Float(px[i + c]) * (1 - a) + 255 * a) } }
        return LockImage(w: img.w, h: img.h, bgra: px)
    }
    static func sheet(_ cells: [(LockImage, String)], cols: Int) -> UIImage {
        let cw = 300, ch = 652, bar = 30
        let rows = (cells.count + cols - 1) / cols
        let fmt = UIGraphicsImageRendererFormat(); fmt.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: cw * cols, height: rows * (ch + bar)), format: fmt).image { _ in
            UIColor(white: 0.08, alpha: 1).setFill(); UIRectFill(CGRect(x: 0, y: 0, width: cw * cols, height: rows * (ch + bar)))
            for (i, c) in cells.enumerated() {
                let x = (i % cols) * cw, y = (i / cols) * (ch + bar)
                (c.1 as NSString).draw(in: CGRect(x: x + 4, y: y + 3, width: cw - 8, height: bar), withAttributes: [.font: UIFont.boldSystemFont(ofSize: 11), .foregroundColor: UIColor.white])
                c.0.uiImage()?.draw(in: CGRect(x: x, y: y + bar, width: cw, height: ch))
            }
        }
    }

    func testRunOutOneJelbie() throws { let a = try runScene(count: 1); _ = try runScene(count: 1, plan: a.fadeStart) }
    func testRunOutThreeJelbies() throws { let a = try runScene(count: 3); _ = try runScene(count: 3, plan: a.fadeStart) }
}
