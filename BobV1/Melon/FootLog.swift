//
//  FootLog.swift
//  2026-11-01. In-app telemetry for a detached foot, which we have never reproduced off the phone. Off unless launched with `-FootLog 1` (remembered in UserDefaults key "FootLog" until `-FootLog 0`).
//  Off = one Bool test per frame. On: after the full skin pass of a frame (weld + leash included), for every actor that has foot pieces out, a line is appended to Documents/foot_log.jsonl
//  when the piece's top was outside the body before the leash moved it (gap > 0), or the leash / tether pulled it. At most 20 lines per second; the per-piece session maximum is kept for the
//  perf line as `feet[max cm, count]` (`FootLog.summary`). Copy it off the phone:
//    devicectl device copy from --domain-type appDataContainer --domain-identifier io.mgsllc.BobV1 --source Documents/foot_log.jsonl
//

import Foundation
import QuartzCore

@MainActor
final class FootLog {
    nonisolated(unsafe) static var on = false
    static let shared = FootLog()
    /// Set by whoever owns a frame-interval meter (PerfMeter on g-perfint): the last frame interval in ms, logged with every line.
    nonisolated(unsafe) static var lastIntervalMs: Double = 0
    private(set) var maxCm: [String: (cm: Float, n: Int)] = [:]
    private var tokens: Double = 20, lastT: Double = 0
    private var handle: FileHandle?
    let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("foot_log.jsonl")

    static func configure(defaults: UserDefaults = .standard) {
        let v = defaults.object(forKey: "FootLog") != nil && defaults.bool(forKey: "FootLog")
        defaults.set(v, forKey: "FootLog")
        on = v
    }

    /// The perf line's `feet[...]`: the worst gap this session and how many logged events, over all pieces ("feet[none]" when clean).
    var summary: String {
        guard let w = maxCm.max(by: { $0.value.cm < $1.value.cm }) else { return "feet[none]" }
        let n = maxCm.values.reduce(0) { $0 + $1.n }
        return String(format: "feet[%.1f cm @%@, %d]", w.value.cm, w.key, n)
    }

    /// Call once per frame after the skin pass. `scene`: what the room is showing (game / park / volley / groom / bath ...).
    func record(actors: [JellyActor], dt: Float, scene: String) {
        guard FootLog.on else { return }
        let now = CACurrentMediaTime()
        tokens = min(20, tokens + (now - lastT) * 20); lastT = now
        for a in actors {
            let sk = a.skinner
            guard sk.beansActive, sk.beanBlend > 0.05 else { continue }
            for s in 0..<2 {
                let pre = sk.leashPre[s]
                let gap = pre < 1 ? max(0, -pre) : 0
                let pull = max(sk.joinLeash[s], sk.weldPull[s])
                guard gap > 0 || pull > 0 else { continue }
                let key = "\(a.id)\(s == 0 ? "L" : "R")"
                let cm = max(gap, pull) * 100
                var e = maxCm[key] ?? (0, 0); e.cm = max(e.cm, cm); e.n += 1; maxCm[key] = e
                guard tokens >= 1 else { continue }
                tokens -= 1
                let b = a.brain
                let line: [String: Any] = [
                    "t": now, "actor": a.id, "species": b.map { "\($0.feature)" } ?? "?", "piece": s == 0 ? "footL" : "footR",
                    "gap_cm": Double(gap * 100), "leash_cm": Double(sk.joinLeash[s] * 100), "tether_cm": Double(sk.weldPull[s] * 100), "pole_hip_cm": Double(sk.weldDist[s] * 100),
                    "script": b?.scriptKindName ?? "-", "idle": b?.idleState.kind?.rawValue ?? "-", "activity": b.map { "\($0.activity)" } ?? "-",
                    "gait_phase": b.map { "\($0.gait.phase)" } ?? "-", "gait_busy": b?.gait.isBusy ?? false, "volley": b?.volley.active ?? false, "volley_phase": b.map { "\($0.volley.phase)" } ?? "-",
                    "shoes": b?.shoesWorn ?? false, "tilt": Double(sk.joinTilt), "dt_ms": Double(dt * 1000), "interval_ms": FootLog.lastIntervalMs,
                    "blend": Double(sk.beanBlend), "scene": scene, "thermal": ProcessInfo.processInfo.thermalState.rawValue,
                ]
                write(line)
            }
        }
    }

    private func write(_ obj: [String: Any]) {
        guard let d = try? JSONSerialization.data(withJSONObject: obj, options: [.sortedKeys]) else { return }
        if handle == nil {
            if !FileManager.default.fileExists(atPath: url.path) { FileManager.default.createFile(atPath: url.path, contents: nil) }
            handle = try? FileHandle(forWritingTo: url); _ = try? handle?.seekToEnd()
        }
        handle?.write(d); handle?.write(Data([10]))
    }
}
