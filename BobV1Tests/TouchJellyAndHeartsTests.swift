//
//  TouchJellyAndHeartsTests.swift
//  The jelly haptic on letting go follows the body's REAL squash oscillation (a soft pulse at each squash peak, fading with it), squishing him
//  is a soft low-sharpness texture that follows his actual deformation, and the heart bubbles above his head (replacing the finger hearts).
//

import XCTest
import simd
@testable import BobV1

@MainActor
final class TouchJellyAndHeartsTests: XCTestCase {
    private func grabCrown(_ r: TouchPlayTests.Rig) -> SIMD3<Float> {
        let sim = r.rig.sim
        var apex = 0, top: Float = -1
        for i in 0..<sim.n where sim.x[3 * i + 1] > top { top = sim.x[3 * i + 1]; apex = i }
        return SIMD3(sim.x[3 * apex], sim.x[3 * apex + 1], sim.x[3 * apex + 2])
    }

    /// Release from a lift (the body snaps back and lands, squashing): returns the recorded jelly pulses and the independently measured squash peaks.
    private func releaseRun(lift: Float, hold: Int = 90) -> (pulses: [(t: Double, i: Float, s: Float)], peaks: [Double], t0: Double, rest: Float, r: TouchPlayTests.Rig) {
        let r = TouchPlayTests.Rig()
        let sim = r.rig.sim, brain = r.rig.brain, sk = r.rig.skinner
        r.step(touched: true)
        let hit = grabCrown(r)
        sim.beginGrab(hit: hit, radius: 0.4)
        for k in 0..<hold {
            let l = lift * min(1, Float(k) / 40)
            r.step(touched: true) {
                sim.moveGrab(target: hit + SIMD3(0, l, 0), rot: nil)
                r.play.heldFrame(dt: 1.0 / 60, now: r.clock, grabbing: true, liftHeight: l, sim: sim, brain: brain, skinner: sk)
            }
        }
        sim.endGrab()
        r.rec.clear()
        let t0 = r.clock
        r.play.haptics.transient(now: t0, intensity: 0, sharpness: 0.99)          // marker: the recorder's time 0 is this clock time
        r.play.jellyLetGo(now: t0)
        var series: [(t: Double, h: Float)] = []
        for _ in 0..<(60 * 2) {
            r.step(touched: true) {
                series.append((r.clock, sim.heightExtent()))
                r.play.heldFrame(dt: 1.0 / 60, now: r.clock, grabbing: false, liftHeight: lift, sim: sim, brain: brain, skinner: sk)
            }
        }
        let rest = sim.restHeightExtent()
        var peaks: [Double] = []
        for k in 1..<(series.count - 1) where series[k].h < series[k - 1].h && series[k].h <= series[k + 1].h && rest - series[k].h > 0.012 {
            // parabolic refinement of the minimum time
            let a = series[k - 1].h, b = series[k].h, c = series[k + 1].h
            let d = a - 2 * b + c
            let off = d > 1e-9 ? Double(0.5 * (a - c) / d) : 0
            peaks.append(series[k].t + off / 60)
        }
        let pulses = r.rec.events(.transient).filter { $0.sharpness <= 0.15 }.map { (t: $0.t, i: $0.intensity, s: $0.sharpness) }
        return (pulses, peaks, t0, rest, r)
    }

    func testReleaseHapticFollowsTheMeasuredWobble() {
        let res = releaseRun(lift: 0.5)
        print("JELLY pulses (s after let-go) \(res.pulses.map { String(format: "%.3f(%.2f)", $0.t, $0.i) }) peaks \(res.peaks.map { String(format: "%.3f", $0 - res.t0) })")
        XCTAssertGreaterThanOrEqual(res.pulses.count, 2, "a few soft pulses, not one thump")
        XCTAssertLessThanOrEqual(res.pulses.count, 6)
        for p in res.pulses {
            XCTAssertLessThanOrEqual(p.i, 0.55, "subtle and warm")
            XCTAssertLessThanOrEqual(p.s, 0.15, "no sharp click")
        }
        // every pulse lines up with a measured squash peak within 40 ms
        for p in res.pulses {
            let tAbs = p.t + res.t0
            let nearest = res.peaks.map { abs($0 - tAbs) }.min() ?? 9
            XCTAssertLessThanOrEqual(nearest, 0.04, "pulse at \(tAbs) is within 40 ms of a squash peak")
        }
    }

    // MARK: hearts in thought bubbles

    private var seenSides: [Float] = []
    private func pet(_ r: TouchPetTests.Run, seconds: Float, births: inout [Double]) {
        let eye = SIMD3<Float>(0, 0.9, 6)
        var t: Float = 0, last: Double = -1
        while t < seconds {
            r.frame(r.ray(localX: 0.35 * sinf(2 * .pi * 1.2 * t), localY: 0, eye: eye)); t += 1.0 / 60
            if let h = r.play.hearts.last, h.born != last { last = h.born; births.append(h.born); seenSides.append(h.side) }
        }
    }

    func testHeartBubblesPopOutWhileHeEnjoysPettingAndNotWhenGrumpy() {
        let r = TouchPetTests.Run()
        var births: [Double] = []
        pet(r, seconds: 6, births: &births)
        XCTAssertGreaterThanOrEqual(births.count, 4, "a bubble-heart every ~0.6-1 s once he is really enjoying it")
        for k in 1..<births.count {
            let gap = births[k] - births[k - 1]
            XCTAssertGreaterThanOrEqual(gap, 0.58, "not faster than ~0.6 s"); XCTAssertLessThanOrEqual(gap, 1.05, "not slower than ~1 s")
        }
        XCTAssertEqual(TouchPlay.heartLife, 1.2, "rise and fade over about 1.2 s")
        for k in 1..<seenSides.count { XCTAssertEqual(seenSides[k], -seenSides[k - 1], "alternating upper-left / upper-right of the crown") }
        for h in r.play.hearts { XCTAssertLessThanOrEqual(r.clock - h.born, TouchPlay.heartLife + 0.05); XCTAssertTrue(abs(h.drift) <= 1 && abs(h.start) <= 1 && abs(h.side) == 1) }
        r.idle(2)
        XCTAssertTrue(r.play.hearts.isEmpty, "they are gone 1.2 s after the petting stops (and cost nothing)")

        let g = TouchPetTests.Run()
        g.play.mood = .grumpy
        var gb: [Double] = []
        pet(g, seconds: 6, births: &gb)
        XCTAssertTrue(gb.isEmpty, "no hearts for a grumpy Blob")
        XCTAssertTrue(TouchPetTests.Run().play.hearts.isEmpty, "idle: nothing")
    }

    func testHeartBubblesWhileHeldHappy() {
        let r = TouchPlayTests.Rig()
        let sim = r.rig.sim, brain = r.rig.brain, sk = r.rig.skinner
        r.step(touched: true)
        let hit = grabCrown(r)
        sim.beginGrab(hit: hit, radius: 0.4)
        var births: [Double] = [], last: Double = -1
        for k in 0..<300 {
            let l = min(0.4, 0.4 * Float(k) / 60)
            r.step(touched: true) {
                sim.moveGrab(target: hit + SIMD3(0, l, 0), rot: nil)
                r.play.heldFrame(dt: 1.0 / 60, now: r.clock, grabbing: true, liftHeight: l, sim: sim, brain: brain, skinner: sk)
            }
            if let b = r.play.hearts.last?.born, b != last { last = b; births.append(b) }
        }
        XCTAssertGreaterThanOrEqual(births.count, 3, "hearts while he is lifted and happy")
    }

    // MARK: squishing feels like jelly

    func testSquishTextureIsSoftAndFollowsTheRealDeformation() {
        var prevI: Float = 0
        for d in stride(from: Float(0.01), through: 0.6, by: 0.01) {
            XCTAssertLessThanOrEqual(HapticMap.squishSharpness(depth: d), 0.30, "low sharpness: soft and round")
            let i = HapticMap.squishIntensity(depth: d); XCTAssertGreaterThanOrEqual(i, prevI); prevI = i
        }
        XCTAssertLessThanOrEqual(HapticMap.impactSharpness(speed: 99), 0.45, "no sharp thump on a landing")
        // live: the lifted body's deformation drives it, and a rigid move reads ~0
        let r = TouchPlayTests.Rig()
        let sim = r.rig.sim
        r.step(touched: true)
        let hit = grabCrown(r)
        sim.beginGrab(hit: hit, radius: 0.4)
        for k in 0..<90 { let l = 0.9 * Float(k) / 90; r.step(touched: true) { sim.moveGrab(target: hit + SIMD3(0, l, 0), rot: nil) } }
        let stretched = sim.deformation()
        let felt = HapticMap.squishIntensity(depth: min(0.5, stretched * TouchPlay.liftDepthGain))
        XCTAssertGreaterThan(felt, 0.12, "the real stretch of the body (\(stretched) u) is felt as a soft squish")
        XCTAssertLessThanOrEqual(HapticMap.squishSharpness(depth: min(0.5, stretched * TouchPlay.liftDepthGain)), 0.30)
    }

    func testHeartBubbleSizeAndSafeAreaPlacement() {
        // bare hearts, 28-44 pt wide, size varies with the start offset
        XCTAssertEqual(TouchHeartsView.size(of: TouchPlay.Heart(born: 0, drift: 0, start: -1, side: 1)), 28, accuracy: 0.01)
        XCTAssertEqual(TouchHeartsView.size(of: TouchPlay.Heart(born: 0, drift: 0, start: 1, side: 1)), 44, accuracy: 0.01)
        XCTAssertLessThanOrEqual(TouchHeartsView.maxSize / 2, TouchHeartsView.halfExtent)
        for a in [0.0, 0.05, 0.15, 0.3, 0.6] { XCTAssertTrue((0.5...1.15).contains(TouchHeartsView.scale(age: a)), "pop scale at \(a)") }
        XCTAssertEqual(TouchHeartsView.opacity(age: 0.99), 0.025, accuracy: 0.01)
        let size = CGSize(width: 402, height: 874), safeTop: CGFloat = 62
        let r = TouchHeartsView.halfExtent
        for ax in stride(from: CGFloat(-50), through: 450, by: 25) {
            for ay in stride(from: CGFloat(-100), through: 950, by: 50) {
                for age in [0.0, 0.3, 0.6, 1.0] {
                    let h = TouchPlay.Heart(born: 0, drift: 1, start: -1, side: 1)
                    let p = TouchHeartsView.place(h, age: age, anchor: CGPoint(x: ax, y: ay), size: size, safeTop: safeTop)
                    XCTAssertGreaterThanOrEqual(p.x - r, 8); XCTAssertLessThanOrEqual(p.x + r, size.width - 8)
                    XCTAssertGreaterThanOrEqual(p.y - r, safeTop, "below the status bar / island")
                    XCTAssertLessThanOrEqual(p.y + r, size.height)
                    if p.x - r < 126 { XCTAssertGreaterThanOrEqual(p.y - r, 116, "clear of the Let Bob go pill") }
                }
            }
        }
        // rises only ~75 pt
        let h = TouchPlay.Heart(born: 0, drift: 0, start: 0, side: 1)
        let a = TouchHeartsView.place(h, age: 0, anchor: CGPoint(x: 300, y: 400), size: size, safeTop: safeTop)
        let b = TouchHeartsView.place(h, age: 1, anchor: CGPoint(x: 300, y: 400), size: size, safeTop: safeTop)
        XCTAssertEqual(a.y - b.y, 75, accuracy: 1)
    }
}
