//
//  WeatherPerfTests.swift
//  What a storm costs (docs/PERFORMANCE.md: GPU ~ 6 ms, CPU ~ 5 ms per frame): the room drawn with the room cache on (the game's path) in clear weather and in a storm,
//  GPU time per frame from the command buffer (median of 150), and the CPU of one weather + reactor step. The rain / flash are applied in the cache blit and the
//  window shader, the gloom / flash lift in the post exposure: no extra pass, no cache rebuild.
//

import XCTest
import Metal
import simd
@testable import BobV1

@MainActor
final class WeatherPerfTests: XCTestCase {
    override func setUp() { super.setUp(); RoomLayout.dynamicBoxes = []; GameCamera.configureRoom(count: 3, option: .A, wide: 2); _ = GameCamera.camera(aspect: 603.0 / 1311.0) }
    override func tearDown() { RoomLayout.dynamicBoxes = []; GameCamera.configureRoom(count: 1); _ = GameCamera.camera(aspect: 440.0 / 956.0); super.tearDown() }

    func testStormCostIsUnderHalfAMillisecond() throws {
        let rigs = (0..<3).map { _ in MotionRig(game: true) }
        let spots = JellyRoster.spawnSpots(count: 3)
        for (i, r) in rigs.enumerated() { r.sim.teleport(toXZ: spots[i]); for _ in 0..<90 { r.sim.step() }; r.brain.currentPose(r.sim) }
        WeatherCaptureTests.keep += rigs
        guard let sh = WeatherCaptureTests.Shooter(W: 880, H: 1912, rigs: rigs) else { throw XCTSkip("no renderer") }
        WeatherCaptureTests.keep.append(sh)
        sh.ren.roomCacheEnabled = true
        let looks: [(String, WeatherLook)] = [("clear", WeatherLook()), ("rain+gloom", WeatherLook(phase: .peak, gloom: 1, rain: 1, flash: 0, spot: 0.5)), ("flash", WeatherLook(phase: .peak, gloom: 1, rain: 1, flash: 0.8, spot: 0.3))]
        var gpu: [String: [Double]] = [:]
        func frame(_ look: WeatherLook) -> Double {
            sh.ren.weatherLook = look
            sh.ren.dayHourOverride = 13
            let cam = GameCamera.camera(aspect: 880.0 / 1912.0, focus: 0)
            let light = GameCamera.light(centroids: rigs.map { $0.sim.centroid() })
            sh.ren.beginFrame()
            for (i, r) in rigs.enumerated() { r.skinner.update(x: r.sim.x, index: MotionRig.renderMesh.index, into: sh.ren.dynPointer(body: i)) }
            var fp = FrameParams(); fp.shape = SIMD4<Float>(Shape.T, Shape.Ro, Shape.skin, Shape.pale); fp.exposure = look.exposure(night: 0); fp.time = 3.7
            let pal = PaletteKey.blue.palette; fp.bg = pal.matte ? melonCreamLinear : melonBackgroundLinear
            sh.ren.setUniforms(camera: cam, light: light, palette: pal, params: fp, viewSize: SIMD2<Float>(880, 1912))
            let cmd = sh.ren.queue.makeCommandBuffer()!
            sh.ren.draw(to: sh.target, commandBuffer: cmd, showMesh: false)
            cmd.waitUntilCompleted()
            return (cmd.gpuEndTime - cmd.gpuStartTime) * 1000
        }
        for _ in 0..<20 { _ = frame(WeatherLook()) }          // (the cache settles and builds)
        for round in 0..<150 { var rng = WeatherSeededRNG(seed: UInt64(round) + 1); for (n, l) in looks.shuffled(using: &rng) { gpu[n, default: []].append(frame(l)) } }
        func median(_ a: [Double]) -> Double { a.sorted()[a.count / 2] }
        let base = median(gpu["clear"]!)
        var lines: [String] = []
        for (n, _) in looks { lines.append(String(format: "GPU %@: median %.3f ms (clear %.3f ms, delta %+.3f ms)", n, median(gpu[n]!), base, median(gpu[n]!) - base)) }
        // CPU of one fixed step of the weather clock + the reactor (storm on, three Jelbies)
        let book = WeatherBook(defaults: UserDefaults(suiteName: "wp-\(UUID().uuidString)")!)
        book.begin(seed: 4, jumpTo: .peak)
        let reactor = StormReactor()
        let js = rigs.enumerated().map { StormReactor.Jelly(id: $0.offset, brain: $0.element.brain, sim: $0.element.sim, skinner: $0.element.skinner) }
        reactor.handle([StormEvent(t: 0, kind: .began), StormEvent(t: 0, kind: .phase(.peak))], plan: book.plan, jellies: js, care: nil)
        let n = 20000
        let t0 = CACurrentMediaTime()
        for _ in 0..<n { let ev = book.tick(dt: 1.0 / 60); if !ev.isEmpty { reactor.handle(ev, plan: book.plan, jellies: js, care: nil) }; reactor.tick(jellies: js, care: nil, dt: 1.0 / 60); _ = book.look() }
        let cpu = (CACurrentMediaTime() - t0) / Double(n) * 1000
        lines.append(String(format: "CPU weather + reactor step: %.4f ms (storm, 3 Jelbies)", cpu))
        let out = lines.joined(separator: "\n")
        print("WEATHERPERF\n" + out)
        try? out.write(toFile: WeatherCaptureTests.dir + "/perf.txt", atomically: true, encoding: .utf8)
        XCTAssertLessThan(median(gpu["rain+gloom"]!) - base, 0.5)
        XCTAssertLessThan(median(gpu["flash"]!) - base, 0.5)
        XCTAssertLessThan(cpu, 0.5)
    }
}

struct WeatherSeededRNG: RandomNumberGenerator {
    var s: UInt64
    init(seed: UInt64) { s = seed &* 0x9E3779B97F4A7C15 | 1 }
    mutating func next() -> UInt64 { s ^= s << 13; s ^= s >> 7; s ^= s << 17; return s }
}
