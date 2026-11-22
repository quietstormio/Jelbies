//
//  CuddleLandStrokeTests.swift
//  The landscape cuddle close-up (cuddle-land-r1) must keep touch working: with the close-up open, a finger put on a body's screen position (the body's centre
//  projected through the real close-up camera, picked by the real `TouchPick`) hits THAT Jelmiko, and a 3 s stroke across it (rays unprojected through the same camera,
//  fed to `TouchPlay.petFrame` like the stage does) gives hearts, haptic intensity and the purr. Portrait is run as the control (same scenario, same asserts).
//

import XCTest
import simd
@testable import BobV1

@MainActor
final class CuddleLandStrokeTests: XCTestCase {
    nonisolated(unsafe) static var keep: [AnyObject] = []     // the runtime aborts when these are released (see FocusAnyJellyTests)
    nonisolated(unsafe) static var savedHour: Double?
    override func setUp() { Self.savedHour = DayClock.shared.forcedHour; DayClock.shared.forcedHour = 14 }
    override func tearDown() { DayClock.shared.forcedHour = Self.savedHour; GameCamera.aspect = 440.0 / 956.0 }

    static let portrait: Float = 440.0 / 956.0, landscape: Float = 2.17

    struct Result { var hearts = 0, buzz: Float = 0, purr: Float = 0, pressing = false; var picks: [Int?] = [] }

    /// Opens the close-up for `count` Jelmiko at `aspect` and settles it.
    private func openCloseUp(count: Int, aspect: Float) -> FocusAnyRun {
        GameCamera.aspect = aspect
        let r = FocusAnyRun(count: count); Self.keep.append(r)
        r.run(1.5)
        if count > 1 { r.care.comeHereEveryone() } else { r.care.comeHere() }
        XCTAssertTrue(r.run(40) { r.care.focus.isFocused }, "the close-up opens (\(count) at \(aspect))")
        r.run(1.5)
        return r
    }

    private func pick(_ r: FocusAnyRun, at p: CGPoint, size: CGSize, cam: CameraState) -> Int? {
        let n = r.rm.vertexCount * 6
        var dyn = [Float](repeating: 0, count: n * 3)
        var out: Int?
        dyn.withUnsafeMutableBufferPointer { buf in
            for a in r.actors { a.skinner.update(x: a.sim.x, index: r.rm.index, into: buf.baseAddress! + a.id * n) }
            let bodies = r.care.focusGroup.ids.filter { $0 < r.actors.count }.map { TouchPick.Body(id: $0, dyn: UnsafePointer(buf.baseAddress! + $0 * n), x: r.actors[$0].sim.x) }
            out = TouchPick.pick(p, size: size, viewProj: cam.viewProj, invViewProj: cam.invViewProj, bodies: bodies,
                                 index: r.rm.index, bodyIndexCount: r.rm.body.first + r.rm.body.count)?.id
        }
        return out
    }

    private func screen(_ w: SIMD3<Float>, _ cam: CameraState, _ size: CGSize) -> CGPoint {
        let c = cam.viewProj * SIMD4<Float>(w.x, w.y, w.z, 1)
        return CGPoint(x: CGFloat(c.x / c.w * 0.5 + 0.5) * size.width, y: CGFloat(0.5 - c.y / c.w * 0.5) * size.height)
    }

    /// A finger down on Jelly `id`'s screen position, then a 3 s back-and-forth stroke across it (screen path = the body's centre swept +-0.3 world units sideways).
    private func stroke(_ r: FocusAnyRun, id: Int, aspect: Float, size: CGSize) -> Result {
        let rec = RecordingHapticSink()
        let driver = HapticDriver(sinks: [rec])
        let play = TouchPlay(haptics: driver)
        driver.enabled = true; driver.setWarm(true)
        var clock = 100.0
        rec.clock = { clock }
        rec.clear(); driver.setWarm(false); driver.setWarm(true)
        let a = r.actors[id]
        let surface = RestSurface(mesh: r.rm)
        var res = Result()
        let c0 = a.sim.centroid()
        var t: Float = 0, k = 0
        while t < 3 {
            let cam = GameCamera.camera(aspect: aspect, focus: 1)
            let p = screen(c0 + SIMD3(0.3 * sinf(2 * .pi * 1.2 * t), 0, 0), cam, size)
            if k % 30 == 0 { res.picks.append(pick(r, at: p, size: size, cam: cam)) }
            let ndc = SIMD2<Float>(Float(p.x / size.width) * 2 - 1, 1 - Float(p.y / size.height) * 2)
            let ray = unproject(ndc: ndc, invViewProj: cam.invViewProj)
            play.petFrame(dt: 1.0 / 60, now: clock, ray: ray, screen: SIMD2(Float(p.x / size.width), Float(p.y / size.height)), sim: a.sim, brain: a.brain, skinner: a.skinner, surface: surface)
            res.hearts = max(res.hearts, play.hearts.count); res.purr = max(res.purr, play.purrLevel)
            res.pressing = res.pressing || a.sim.pressing
            r.tick(); clock += 1.0 / 60; t += 1.0 / 60; k += 1
        }
        res.buzz = rec.events.map { $0.intensity }.max() ?? 0
        play.petFrame(dt: 1.0 / 60, now: clock, ray: nil, screen: nil, sim: a.sim, brain: a.brain, skinner: a.skinner, surface: surface)
        r.run(1.0)
        return res
    }

    private func scenario(count: Int, aspect: Float, label: String) {
        let size = aspect > 1 ? CGSize(width: 956, height: 440) : CGSize(width: 440, height: 956)
        let r = openCloseUp(count: count, aspect: aspect)
        let cam = GameCamera.camera(aspect: aspect, focus: 1)
        for id in 0..<count {
            let c = r.actors[id].sim.centroid()
            let p = screen(c, cam, size)
            XCTAssertTrue(CGRect(origin: .zero, size: size).contains(p), "\(label): Jelmiko \(id) on screen at \(p)")
            XCTAssertEqual(pick(r, at: p, size: size, cam: cam), id, "\(label): a touch on Jelmiko \(id)'s centre hits him")
        }
        // the empty floor beside / in front of the row: nobody
        for q in [CGPoint(x: 0.03 * size.width, y: 0.97 * size.height), CGPoint(x: 0.97 * size.width, y: 0.97 * size.height), CGPoint(x: 0.5 * size.width, y: 0.99 * size.height)] {
            XCTAssertNil(pick(r, at: q, size: size, cam: cam), "\(label): the floor at \(q) is nobody")
        }
        if aspect > 1 { XCTAssertNil(pick(r, at: CGPoint(x: 0.04 * size.width, y: 0.5 * size.height), size: size, cam: cam), "\(label): the floor beside the row is nobody") }
        for id in 0..<count {
            let s = stroke(r, id: id, aspect: aspect, size: size)
            print("CUDDLELAND \(label) count \(count) jelmiko \(id): hearts \(s.hearts) buzz \(s.buzz) purr \(s.purr) pressing \(s.pressing) picks \(s.picks)")
            XCTAssertTrue(s.picks.allSatisfy { $0 == id } && !s.picks.isEmpty, "\(label): the whole stroke stays on Jelmiko \(id): \(s.picks)")
            XCTAssertGreaterThan(s.hearts, 0, "\(label) \(id): hearts")
            XCTAssertGreaterThan(s.buzz, 0, "\(label) \(id): haptic intensity")
            XCTAssertGreaterThan(s.purr, 0, "\(label) \(id): purr")
            XCTAssertTrue(s.pressing, "\(label) \(id): the body is dented under the finger")
        }
    }

    func testPortraitControlOne() { scenario(count: 1, aspect: Self.portrait, label: "portrait") }
    func testPortraitControlTwo() { scenario(count: 2, aspect: Self.portrait, label: "portrait") }
    func testPortraitControlThree() { scenario(count: 3, aspect: Self.portrait, label: "portrait") }
    func testLandscapeOne() { scenario(count: 1, aspect: Self.landscape, label: "landscape") }
    func testLandscapeTwo() { scenario(count: 2, aspect: Self.landscape, label: "landscape") }
    func testLandscapeThree() { scenario(count: 3, aspect: Self.landscape, label: "landscape") }
}
