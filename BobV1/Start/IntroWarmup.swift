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

    /// Starts the background warm-up (a no-op the second time, and under the test host, where suites time their own builds).
    static func begin() {
        started.lock(); defer { started.unlock() }
        guard !didStart, ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else { return }
        didStart = true
        if UserDefaults.standard.object(forKey: "IntroWarmup") != nil, UserDefaults.standard.integer(forKey: "IntroWarmup") == 0 { return }          // -IntroWarmup 0: off (A/B timing)
        LaunchTiming.mark("warm-up starts")
        // a short pause first: the clip's first frames are decoded and on screen before anything else competes for the CPU
        Task.detached(priority: .utility) {
            try? await Task.sleep(for: .milliseconds(400))
            MelonPipelines.warm()
            LaunchTiming.mark("warm-up: pipelines done")
        }
        Task.detached(priority: .utility) {
            try? await Task.sleep(for: .milliseconds(400))
            LaunchTiming.span("warm: meshes") { BobMeshCache.warm() }
            LaunchTiming.mark("warm-up: meshes done")
        }
    }
}
