//
//  JellySleepTests.swift
//  A settled, idle Jelly skips his sim step (JellyActor.updateSleep) and wakes the instant anything happens; the shared arm-keyframe cache;
//  and a headless "frame" (brain + sim + skin, as the stage runs them) timed with and without sleeping.
//

import XCTest
import simd
@testable import BobV1

@MainActor
final class JellySleepTests: XCTestCase {
    nonisolated(unsafe) static var keep: [AnyObject] = []

    private func makeActors(_ n: Int, autonomy: Bool = false) -> [JellyActor] {
        let sm = buildSimMesh(), rm = buildRenderMesh()
        let emb = embed(simRest: sm.rest, tets: sm.tets, verts: rm.rest)
        let spots = JellyRoster.spawnSpots(count: n)
        let actors = (0..<n).map { i -> JellyActor in
            let a = JellyActor(id: i, name: JellyRoster.names[i], simMesh: sm, renderMesh: rm, embedding: emb, appearance: .berry, firmness: 0.95, damping: 0.45, spawn: spots[i])
            a.reset(drop: 0.35, shift: n > 1)
            let b = BlobBrain.forGame()
            b.attach(renderMesh: rm, synchronous: true)
            b.autonomy = autonomy
            b.steerID = i
            a.brain = b
            for _ in 0..<150 { a.sim.step() }
            b.currentPose(a.sim)
            return a
        }
        Self.keep += actors
        return actors
    }

    /// One fixed step as the stage runs it: brain, then the sleep check, then the sim step.
    @discardableResult
    private func tick(_ a: JellyActor, force: Bool = false) -> Bool {
        a.brain?.tick(sim: a.sim, skinner: a.skinner, dt: a.sim.stepDt, touched: false)
        a.skinner.jelly.tick(brain: a.brain!, sim: a.sim, dt: a.sim.stepDt)
        let stepped = a.updateSleep(forceAwake: force)
        if stepped { a.sim.step() }
        return stepped
    }

    private func skinned(_ a: JellyActor, _ rm: RenderMesh) -> [Float] {
        var out = [Float](repeating: 0, count: rm.vertexCount * 6)
        out.withUnsafeMutableBufferPointer { a.skinner.update(x: a.sim.x, index: rm.index, into: $0.baseAddress!) }
        return out
    }

    func testSettledJellySleepsAndWakesOnCommandTouchAndForce() {
        let rm = buildRenderMesh()
        let a = makeActors(1)[0]
        var steps = 0
        while !a.asleep && steps < 600 { tick(a); steps += 1 }
        XCTAssertTrue(a.asleep, "a settled idle Jelly falls asleep (took \(steps) steps)")
        let before = skinned(a, rm), x0 = a.sim.x
        for _ in 0..<120 { XCTAssertFalse(tick(a), "no sim step while asleep") }
        XCTAssertEqual(a.sim.x, x0, "his body does not move while he sleeps")
        XCTAssertEqual(skinned(a, rm), before, "nothing pops while sleeping")

        // a brain command wakes him on that very step, and he moves
        a.brain!.request(.goTo(a.floor + SIMD2(0.5, 1.5)))
        XCTAssertTrue(tick(a), "woken by a command on the same step")
        XCTAssertFalse(a.asleep)
        for _ in 0..<90 { tick(a) }
        XCTAssertGreaterThan(simd_distance(a.floor, SIMD2(x0[0], x0[2])), 0.05, "he is walking")

        // back to sleep once he has stopped
        a.brain!.abortScript(a.sim, a.skinner)
        steps = 0
        while !a.asleep && steps < 1500 { tick(a); steps += 1 }
        XCTAssertTrue(a.asleep, "asleep again after the walk (\(steps) steps)")

        // a touch (press on the body) wakes him
        let c = a.sim.centroid()
        a.sim.setPress(center: SIMD3(c.x, c.y + 0.2, c.z + 0.6), radius: 0.2)
        XCTAssertTrue(tick(a), "woken by a press")
        a.sim.endPress()
        steps = 0
        while !a.asleep && steps < 1500 { tick(a); steps += 1 }
        XCTAssertTrue(a.asleep)

        // the stage's force flag (finger down, close-up, meal ...) keeps him awake, and a nudge wakes him
        for _ in 0..<60 { XCTAssertTrue(tick(a, force: true)) }
        XCTAssertFalse(a.asleep)
        steps = 0
        while !a.asleep && steps < 600 { tick(a); steps += 1 }
        XCTAssertTrue(a.asleep)
        a.sim.nudge()
        XCTAssertTrue(tick(a), "woken by a nudge")
        XCTAssertGreaterThan(a.wakeCount, 2)
    }

    /// Sleeping must not change what is drawn: a twin that never sleeps ends in the same pose (within a hair) through a sleep and a wake.
    func testSleepingDoesNotChangeThePose() {
        let rm = buildRenderMesh()
        let sleeper = makeActors(1)[0], twin = makeActors(1)[0]
        for f in 0..<1200 {
            if f == 700 { sleeper.brain!.request(.goTo(sleeper.floor + SIMD2(0.3, 1.0))); twin.brain!.request(.goTo(twin.floor + SIMD2(0.3, 1.0))) }
            tick(sleeper)
            twin.brain!.tick(sim: twin.sim, skinner: twin.skinner, dt: twin.sim.stepDt, touched: false)
            twin.skinner.jelly.tick(brain: twin.brain!, sim: twin.sim, dt: twin.sim.stepDt)
            twin.sim.step()
            if f == 600 { XCTAssertTrue(sleeper.asleep, "the sleeper slept before the command") }
        }
        XCTAssertGreaterThan(sleeper.sleptSteps, 200)
        var worst: Float = 0
        let a = skinned(sleeper, rm), b = skinned(twin, rm)
        for i in 0..<a.count { worst = max(worst, abs(a[i] - b[i])) }
        MotionLog.write(String(format: "SLEEPTWIN worst vertex difference sleeper vs twin: %.5f", worst))
        XCTAssertLessThan(worst, 0.03, "the sleeper and the never-sleeping twin look the same (worst vertex difference \(worst))")
    }

    /// The game brain with its autonomy on (face-the-player idle, looks, wanders): Jellies still spend long stretches asleep.
    func testSleepEngagesWithAutonomyOn() {
        let actors = makeActors(3, autonomy: true)
        for (i, a) in actors.enumerated() { a.brain!.seed = UInt64(5 + i * 3) }
        for _ in 0..<(60 * 25) { for a in actors { tick(a) } }
        let slept = actors.map(\.sleptSteps)
        MotionLog.write("SLEEPAUTONOMY slept steps of 1500 per Jelly: \(slept), wakes \(actors.map(\.wakeCount))")
        XCTAssertTrue(slept.allSatisfy { $0 > 100 }, "each autonomous Jelly slept some of the time: \(slept)")
    }

    /// Waking changes nothing by itself: after a long sleep the first stepped frame moves no vertex (worst displacement logged).
    func testWakingDoesNotPop() {
        let rm = buildRenderMesh()
        let a = makeActors(1)[0]
        var steps = 0
        while !a.asleep && steps < 600 { tick(a); steps += 1 }
        XCTAssertTrue(a.asleep)
        for _ in 0..<300 { tick(a) }
        let before = skinned(a, rm)
        XCTAssertTrue(tick(a, force: true), "woken")
        let after = skinned(a, rm)
        var worst: Float = 0
        for i in 0..<before.count { worst = max(worst, abs(before[i] - after[i])) }
        MotionLog.write(String(format: "SLEEPWAKE worst vertex displacement on the waking step: %.6f", worst))
        XCTAssertLessThan(worst, 1e-3, "no pop on waking")
    }

    func testBusyJelliesNeverSleep() {
        let a = makeActors(1, autonomy: true)[0]
        a.brain!.request(.goTo(a.floor + SIMD2(0.5, 3)))
        for _ in 0..<45 { XCTAssertTrue(tick(a)) }
        XCTAssertFalse(a.asleep, "a walking Jelly is awake")
    }

    func testArmKeyframesAreBuiltOnceAndShared() {
        let rm = buildRenderMesh()
        let store = ArmKeyframeStore.shared
        let before = store.buildCount
        let brains = (0..<3).map { _ -> BlobBrain in let b = BlobBrain.forGame(); b.attach(renderMesh: rm, synchronous: true); return b }
        XCTAssertLessThanOrEqual(store.buildCount - before, 1, "three Jellies, at most one computation (none if cached on disk)")
        XCTAssertTrue(brains.allSatisfy { $0.armReady })
        // the async path (the stage's) shares it too
        let b = BlobBrain.forGame(); b.attach(renderMesh: rm)
        let ex = expectation(description: "keyframes ready")
        Task { @MainActor in while !b.armReady { try? await Task.sleep(nanoseconds: 20_000_000) }; ex.fulfill() }
        wait(for: [ex], timeout: 60)
        XCTAssertLessThanOrEqual(store.buildCount - before, 1)
        Self.keep += brains + [b]
    }

    /// Three threads ask at once for a set nobody has built: it is computed exactly once (no disk).
    func testConcurrentRequestsBuildOnce() {
        let rm = buildRenderMesh()
        guard let cap = rm.armCapsule else { return XCTFail("no capsule") }
        let store = ArmKeyframeStore(); store.diskEnabled = false
        let rest = rm.rest, mat = rm.mat, index = rm.index
        nonisolated(unsafe) var results = [[ArmKeyframes]](repeating: [], count: 3)
        let lock = NSLock()
        DispatchQueue.concurrentPerform(iterations: 3) { i in
            let r = store.keyframes(paths: BlobBrain.armPaths, rest: rest, mat: mat, capsule: cap, index: index, scale: 1)
            lock.lock(); results[i] = r; lock.unlock()
        }
        XCTAssertEqual(store.buildCount, 1, "built once for three simultaneous askers")
        XCTAssertTrue(results.allSatisfy { $0.count == BlobBrain.armPaths.count })
    }

    /// Cache round trip: a loaded set drives the same displacement as the computed one.
    func testArmKeyframeDiskRoundTrip() {
        let rm = buildRenderMesh()
        let store = ArmKeyframeStore.shared
        let paths = BlobBrain.armPaths
        guard let cap = rm.armCapsule else { return XCTFail("no capsule") }
        let a = store.keyframes(paths: paths, rest: rm.rest, mat: rm.mat, capsule: cap, index: rm.index, scale: 1)
        let fresh = ArmKeyframeStore()
        let b = fresh.keyframes(paths: paths, rest: rm.rest, mat: rm.mat, capsule: cap, index: rm.index, scale: 1)
        XCTAssertEqual(fresh.buildCount + fresh.diskHits, 1)
        XCTAssertEqual(fresh.buildCount, 0, "the second store loads from disk instead of computing")
        for (x, y) in zip(a, b) {
            XCTAssertEqual(x.name, y.name); XCTAssertEqual(x.intervals, y.intervals)
            for s in 0..<2 {
                XCTAssertEqual(x.sides[s].vertices, y.sides[s].vertices); XCTAssertEqual(x.sides[s].delta, y.sides[s].delta)
                XCTAssertEqual(x.sides[s].ao, y.sides[s].ao); XCTAssertEqual(x.sides[s].cls, y.sides[s].cls)
            }
        }
    }

    /// A headless 60 Hz frame of three idle Jellies (brain + sim + skin, the stage's work minus the GPU), timed awake vs. sleeping.
    func testIdleFrameCostWithAndWithoutSleep() {
        let rm = buildRenderMesh()
        let n = rm.vertexCount * 6
        let dyn = UnsafeMutablePointer<Float>.allocate(capacity: n * 3)
        defer { dyn.deallocate() }
        func run(sleep: Bool, count: Int = 3) -> Double {
            let actors = makeActors(count)
            var sims: [SoftBody] = []
            var jobs: [JellyParallel.SkinJob] = []
            for (i, a) in actors.enumerated() { jobs.append(.init(skinner: a.skinner, sim: a.sim, dst: dyn + i * n)) }
            func frame() {
                sims.removeAll(keepingCapacity: true)
                for a in actors {
                    a.brain!.tick(sim: a.sim, skinner: a.skinner, dt: a.sim.stepDt, touched: false)
                    a.skinner.jelly.tick(brain: a.brain!, sim: a.sim, dt: a.sim.stepDt)
                    if !sleep || a.updateSleep(forceAwake: false) { sims.append(a.sim) }
                }
                JellyParallel.step(sims)
                for a in actors { a.skinner.tickBlink(dt: 1.0 / 60) }
                JellyParallel.skin(jobs, index: rm.index)
            }
            for _ in 0..<400 { frame() }          // settle (and fall asleep)
            let frames = 300
            let t0 = CACurrentMediaTime()
            for _ in 0..<frames { frame() }
            let ms = (CACurrentMediaTime() - t0) / Double(frames) * 1000
            if sleep { XCTAssertTrue(actors.allSatisfy(\.asleep), "all asleep") }
            return ms
        }
        let awake1 = run(sleep: false, count: 1), asleep1 = run(sleep: true, count: 1)
        MotionLog.write(String(format: "SLEEPPERF 1 idle Jelly per 60 Hz frame (brain+sim+skin): awake %.3f ms, sleeping %.3f ms", awake1, asleep1))
        let awake = run(sleep: false), asleep = run(sleep: true)
        let line = String(format: "SLEEPPERF 3 idle Jellies per 60 Hz frame (brain+sim+skin): awake %.3f ms, sleeping %.3f ms", awake, asleep)
        MotionLog.write(line); print(line)
        XCTAssertLessThan(asleep, awake * 0.6, "sleeping Jellies cost far less than awake ones")
    }
}
