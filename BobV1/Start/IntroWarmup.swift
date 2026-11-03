//
//  IntroWarmup.swift
//  The launch intro doubles as a loading screen: while the clip plays, the quiet start-up work that needs no UI runs on two low-priority
//  background tasks, so the room appears sooner afterwards. Only work that is safe off the main thread and that the room later picks up from an
//  existing cache is done here (compiled Metal pipelines: MelonPipelines; Bob's meshes: BobMeshCache). Everything that touches views, the
//  game model or the save stays on the main thread after the intro. Starts once per process.
//

import Foundation

nonisolated enum IntroWarmup {
    private static let started = NSLock()
    nonisolated(unsafe) private static var didStart = false
    nonisolated(unsafe) private static var pending = 0

    /// Every started warm-up task has finished (true when nothing was started: tests, `-IntroWarmup 0`).
    static var isFinished: Bool { started.lock(); defer { started.unlock() }; return pending == 0 }
    private static func run(_ body: @escaping @Sendable () async -> Void) {
        started.lock(); pending += 1; started.unlock()
        Task.detached(priority: .utility) {
            await body()
            started.lock(); pending -= 1; started.unlock()
        }
    }
    /// Test seam: pretend a warm-up task is (or is no longer) running.
    static func _simulatePending(_ on: Bool) { started.lock(); pending += on ? 1 : -1; started.unlock() }
    /// 0 = off (A/B timing), 1 = pipelines + meshes only (the first version), 2 = everything (default).
    static var level: Int { UserDefaults.standard.object(forKey: "IntroWarmup") != nil ? UserDefaults.standard.integer(forKey: "IntroWarmup") : 2 }

    /// Starts the background warm-up (a no-op the second time, and under the test host, where suites time their own builds).
    static func begin(forTests: Bool = false) {
        started.lock()
        guard !didStart, forTests || ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else { started.unlock(); return }
        didStart = true
        started.unlock()
        let lvl = level
        if lvl == 0 { return }          // -IntroWarmup 0: off (A/B timing)
        LaunchTiming.mark("warm-up starts")
        // a short pause first: the clip's first frames are decoded and on screen before anything else competes for the CPU
        run {
            try? await Task.sleep(for: .milliseconds(400))
            MelonPipelines.warm()
            LaunchTiming.mark("warm-up: pipelines done")
        }
        run {
            try? await Task.sleep(for: .milliseconds(400))
            LaunchTiming.span("warm: meshes") { BobMeshCache.warm() }
            LaunchTiming.mark("warm-up: meshes done")
        }
        guard lvl >= 2 else { return }
        let count = JellyRoster.launchCount()          // read on the main thread; the bodies are built on a task
        run {
            try? await Task.sleep(for: .milliseconds(900))
            LaunchTiming.span("warm: jelly bodies") { ActorPrebuild.warm(count: count, firmness: Float(0.95), damping: Float(0.45)) }
            LaunchTiming.mark("warm-up: bodies done")
        }
        run {
            try? await Task.sleep(for: .milliseconds(600))
            LaunchTiming.span("warm: sound files") { AudioPrewarm.touchBundleSounds() }
            LaunchTiming.mark("warm-up: sounds done")
        }
    }
}

/// Reads the bundle's sound files once so the first play / prepareToPlay (AudioHub.preloadEffects, the room theme) finds them in the file cache. Safe off the main thread (no players are created).
nonisolated enum AudioPrewarm {
    static func touchBundleSounds() {
        guard let dir = Bundle.main.resourcePath, let names = try? FileManager.default.contentsOfDirectory(atPath: dir) else { return }
        for n in names where n.hasSuffix(".m4a") {
            if let d = try? Data(contentsOf: URL(fileURLWithPath: dir + "/" + n), options: .alwaysMapped) { _ = d.first; _ = d.last }
        }
    }
}

/// The per-Jelly physics body (SoftBody) and its skinner (eye / antenna rigs, tail landmarks) built ahead on a background task for the Bob-breed meshes, ~0.3 s per Jelly on the main thread otherwise.
/// JellyActor.init takes one when firmness and damping match; the pairs are used by exactly one actor each.
nonisolated enum ActorPrebuild {
    final class Pair: @unchecked Sendable { let sim: SoftBody, skinner: Skinner; init(sim: SoftBody, skinner: Skinner) { self.sim = sim; self.skinner = skinner } }
    private static let lock = NSLock()
    nonisolated(unsafe) private static var stash: [(firmness: Float, damping: Float, pair: Pair)] = []

    static func warm(count: Int, firmness: Float, damping: Float) {
        let sm = BobMeshCache.sim, rm = BobMeshCache.render, emb = BobMeshCache.embedding
        for _ in 0..<count {
            let sim = SoftBody(mesh: sm, firmness: firmness, damping: damping)
            let sk = Skinner(simTets: sm.tets, embedding: emb, vertexCount: rm.vertexCount,
                             eyes: buildEyeRig(render: rm, sim: sm, appearance: .berry), antennae: buildAntennaRig(render: rm, sim: sm))
            sk.configureTail(rm)
            lock.lock(); stash.append((firmness, damping, Pair(sim: sim, skinner: sk))); lock.unlock()
        }
    }
    static func take(firmness: Float, damping: Float) -> Pair? {
        lock.lock(); defer { lock.unlock() }
        guard let i = stash.firstIndex(where: { $0.firmness == firmness && $0.damping == damping }) else { return nil }
        return stash.remove(at: i).pair
    }
    static var count: Int { lock.lock(); defer { lock.unlock() }; return stash.count }
}
