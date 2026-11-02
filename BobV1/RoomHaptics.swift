//
//  RoomHaptics.swift
//  Small soft haptics for the room's solo emotes (hiccup, sneeze, dizzy wobble, polite bow, belly drum, species flourish), 2026-11-02.
//  The touch haptics (Haptics.swift) are only warm while he is in focus / the wash. This is the room's own light layer:
//    LAZY       the engine starts at the first request and shuts down ~30 s after the last one (`idleShutdown`); nothing exists before that
//    FREE       Haptics off in Settings, hardware without haptics: a request returns after one defaults read / one flag, nothing is created
//    RATE       at most ~2 requests a second across ALL Jelbies (`minGap`); a request that comes sooner is dropped, never queued
//    POLITE     skipped while focus mode / the wash (the touch driver is warm and gives its own haptics) or a race / volleyball gives its own (`externalBusy`, the brain's own race / volley flags)
//  Every pattern is one or two soft transients (intensity <= 0.4): never a buzz. Tests count requests through `requestTap` (no hardware needed) and drive the clock with `clock`.
//

import Foundation
import QuartzCore
import CoreHaptics

@MainActor
final class RoomHaptics {
    static let shared = RoomHaptics()

    /// The emote cues. One request = one pattern.
    enum Pattern: String, CaseIterable, Sendable {
        case hic, sneezeBuild, sneezeBump, wobble, bowTick, patA, patB, flourish
        /// (delay s, intensity, sharpness) of each soft transient.
        var pulses: [(delay: Double, i: Float, s: Float)] {
            switch self {
            case .hic: return [(0, 0.35, 0.25)]
            case .sneezeBuild: return [(0, 0.15, 0.2), (0.14, 0.20, 0.2)]          // tick-tick
            case .sneezeBump: return [(0, 0.40, 0.15)]                              // the achoo: one soft bump
            case .wobble: return [(0, 0.18, 0.10), (0.11, 0.12, 0.10)]              // a single faint wobble pulse
            case .bowTick: return [(0, 0.20, 0.20)]
            case .patA: return [(0, 0.26, 0.20)]
            case .patB: return [(0, 0.18, 0.20)]
            case .flourish: return [(0, 0.25, 0.15)]
            }
        }
    }

    /// Shortest gap between two accepted requests, whoever asks (2 a second).
    static let minGap: Double = 0.5
    /// Seconds without a request after which the engine is shut down.
    static let idleShutdown: Double = 30

    /// Test seams: every accepted request (after the Settings / busy / rate guards), and the clock.
    nonisolated(unsafe) static var requestTap: ((Pattern) -> Void)?
    nonisolated(unsafe) static var clock: () -> Double = { CACurrentMediaTime() }
    /// Something else is giving its own haptics (focus mode, the wash): the stage sets this every frame.
    var externalBusy = false

    private var sink: CoreHapticsSink?
    private var last: Double = -.infinity
    private var shutdown: Task<Void, Never>?
    private(set) var requests = 0, dropped = 0
    private(set) var engineStarts = 0
    private static let capable: Bool = CoreHapticsSink.supported

    /// Ask for a pattern. Returns whether it was accepted (tests).
    @discardableResult
    func request(_ p: Pattern) -> Bool {
        guard HapticSettings.enabled, !externalBusy else { return false }
        let now = Self.clock()
        guard now - last >= Self.minGap else { dropped += 1; return false }
        last = now
        requests += 1
        Self.requestTap?(p)
        guard Self.capable else { return true }
        if sink == nil { sink = CoreHapticsSink.make(); sink?.start(); engineStarts += 1 }
        guard let s = sink else { return true }
        for (k, pulse) in p.pulses.enumerated() {
            if k == 0 { s.transient(intensity: pulse.i, sharpness: pulse.s) }
            else { DispatchQueue.main.asyncAfter(deadline: .now() + pulse.delay) { [weak self] in self?.sink?.transient(intensity: pulse.i, sharpness: pulse.s) } }
        }
        shutdown?.cancel()
        shutdown = Task { [weak self] in
            try? await Task.sleep(for: .seconds(Self.idleShutdown))
            guard !Task.isCancelled else { return }
            self?.sink?.stop(); self?.sink = nil
        }
        return true
    }

    /// Tests: forget the rate limit and the engine.
    func reset() { last = -.infinity; requests = 0; dropped = 0; shutdown?.cancel(); sink?.stop(); sink = nil; externalBusy = false }
}

extension BlobBrain {
    /// An emote's haptic: not while this Jelbie races or plays volleyball (they give their own); the global guards are in `RoomHaptics.request`.
    func emoteHaptic(_ p: RoomHaptics.Pattern) {
        guard !race.active, !volley.active else { return }
        RoomHaptics.shared.request(p)
    }
}
