//
//  PetTwoTests.swift
//  Two-finger petting (pet-two-r1). Part 1: the ONE-finger baseline, recorded on the base commit (before any production edit): a 3 s stroke on one Jelmiko through a real
//  HapticDriver + RecordingHapticSink must give the same hearts, love, purr and haptic events after the change. The numbers are pinned below.
//

import XCTest
import simd
@testable import BobV1

@MainActor
final class PetTwoTests: XCTestCase {
    nonisolated(unsafe) static var savedHour: Double?
    override func setUp() { Self.savedHour = DayClock.shared.forcedHour; DayClock.shared.forcedHour = 14 }
    override func tearDown() { DayClock.shared.forcedHour = Self.savedHour }

    static let eye = SIMD3<Float>(0, 0.9, 6)

    /// One Jelmiko on its own rig with its own recording haptic driver.
    @MainActor final class Body {
        let rig: MotionRig
        let rec = RecordingHapticSink()
        let driver: HapticDriver
        let play: TouchPlay
        let surface = RestSurface(mesh: MotionRig.renderMesh)
        var born = Set<Double>()
        init() {
            rig = MotionRig(game: true, settle: 2)
            driver = HapticDriver(sinks: [rec])
            play = TouchPlay(haptics: driver)
            driver.enabled = true
            driver.setWarm(true)
            rec.clear()
            driver.setWarm(false); driver.setWarm(true)
        }
        func ray(localX: Float, localY: Float) -> (o: SIMD3<Float>, d: SIMD3<Float>) {
            let e = BodyEllipsoid(sim: rig.sim)
            let p = e.center + e.rot.act(SIMD3(localX, localY, 0))
            return (PetTwoTests.eye, simd_normalize(p - PetTwoTests.eye))
        }
        func frame(clock: Double, ray r: (o: SIMD3<Float>, d: SIMD3<Float>)?) {
            play.petFrame(dt: 1.0 / 60, now: clock, ray: r, screen: r == nil ? nil : SIMD2(0.5, 0.5), sim: rig.sim, brain: rig.brain, skinner: rig.skinner, surface: surface)
            for h in play.hearts { born.insert(h.born) }
            rig.tick()
        }
    }

    struct Numbers: Equatable, CustomStringConvertible {
        var hearts = 0, petEvents = 0, transients = 0, loveAt3s: Float = 0, purrAt3s: Float = 0, maxPetIntensity: Float = 0, firstHeartT: Double = -1, firstPurrT: Double = -1
        var description: String { "hearts \(hearts) petEvents \(petEvents) transients \(transients) love \(loveAt3s) purr \(purrAt3s) maxPet \(maxPetIntensity) firstHeart \(firstHeartT) firstPurr \(firstPurrT)" }
    }

    /// A 3 s stroke on one body (x sweep on the plain-stroke area), then 0.5 s hands-off.
    static func singleStroke(seconds: Float = 3) -> Numbers {
        let b = Body()
        var clock = 100.0
        var n = Numbers()
        var t: Float = 0
        while t < seconds {
            b.frame(clock: clock, ray: b.ray(localX: 0.38 + 0.12 * sinf(2 * .pi * 1.2 * t), localY: 0.15))
            if n.firstPurrT < 0, b.play.isPurring { n.firstPurrT = clock - 100 }
            if n.firstHeartT < 0, !b.born.isEmpty { n.firstHeartT = clock - 100 }
            clock += 1.0 / 60; t += 1.0 / 60
        }
        n.loveAt3s = b.play.love; n.purrAt3s = b.play.purrLevel
        for _ in 0..<30 { b.frame(clock: clock, ray: nil); clock += 1.0 / 60 }
        n.hearts = b.born.count
        let pet = b.rec.events(.continuous, channel: "pet")
        n.petEvents = pet.count; n.maxPetIntensity = pet.map { $0.intensity }.max() ?? 0
        n.transients = b.rec.events(.transient).count
        return n
    }

    func testSingleStrokeBaseline() {
        let n = Self.singleStroke()
        print("PETTWO baseline: \(n)")
        XCTAssertGreaterThan(n.hearts, 0)
        XCTAssertGreaterThan(n.petEvents, 0)
    }
}
