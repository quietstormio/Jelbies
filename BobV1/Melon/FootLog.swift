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
    nonisolated deinit {}          // (a main-actor deinit crashes the Release test host: swift_task_deinitOnExecutor)
    /// Set by whoever owns a frame-interval meter (PerfMeter on g-perfint): the last frame interval in ms, logged with every line.
    nonisolated(unsafe) static var lastIntervalMs: Double = 0
    private(set) var maxCm: [String: (cm: Float, n: Int)] = [:]
    private var tokens: Double = 20, lastT: Double = 0
    private var handle: FileHandle?, handleURL: URL?
    var url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("foot_log.jsonl")

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
        for a in actors { recordOne(id: a.id, skinner: a.skinner, brain: a.brain, now: now, dt: dt, scene: scene) }
    }

    /// One body's two feet (the per-actor part of `record`; tests call it with a rig's skinner).
    func recordOne(id: Int, skinner sk: Skinner, brain b: BlobBrain?, now: Double, dt: Float, scene: String) {
        guard sk.beansActive, sk.beanBlend > 0.05 else { return }
        do {
            for s in 0..<2 {
                let pre = sk.leashPre[s]
                let gap = pre < 1 ? max(0, -pre) : 0
                let pull = max(sk.joinLeash[s], sk.weldPull[s])
                guard gap > 0 || pull > 0 else { continue }
                let key = "\(id)\(s == 0 ? "L" : "R")"
                let cm = max(gap, pull) * 100
                var e = maxCm[key] ?? (0, 0); e.cm = max(e.cm, cm); e.n += 1; maxCm[key] = e
                guard tokens >= 1 else { continue }
                tokens -= 1
                let line: [String: Any] = [
                    "t": now, "actor": id, "species": b.map { "\($0.feature)" } ?? "?", "piece": s == 0 ? "footL" : "footR",
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


    // MARK: move timeline (independent of the gap metric)

    /// What a body is doing, as cheap Equatable fields: compared every frame, a name is only built when it changes.
    struct MoveKey: Equatable {
        var script = "none"; var idle: IdleKind?; var activity: BlobBrain.Activity = .idle; var gait: GaitDriver.Phase = .idle
        var volley: VolleyDrive.Phase?; var race = false, held = false, asleep = false
        var name: String {
            var p = [script]
            if let i = idle { p.append("idle:\(i.rawValue)") }
            if activity != .idle { p.append("act:\(activity)") }
            if gait != .idle { p.append("gait:\(gait)") }
            if let v = volley { p.append("volley:\(v)") }
            if race { p.append("race") }
            if held { p.append("held") }
            if asleep { p.append("asleep") }
            return p.joined(separator: "+")
        }
    }
    private var moves: [Int: MoveKey] = [:], moveSpecies: [Int: String] = [:]
    private var lastCtxT: Double = 0
    nonisolated(unsafe) private static let isoFmt: ISO8601DateFormatter = { let f = ISO8601DateFormatter(); f.timeZone = .current; f.formatOptions = [.withInternetDateTime, .withFractionalSeconds, .withTimeZone]; return f }()
    nonisolated(unsafe) private static let clockFmt: DateFormatter = { let f = DateFormatter(); f.dateFormat = "HH:mm:ss"; f.timeZone = .current; return f }()

    /// Once per frame (after the skin): any actor whose move changed gets a `"ev":"move"` line; every 30 s a `"ev":"ctx"` line lists every actor's current move. `parkActors` ids are offset by 1000 in the key.
    func recordMoves(actors: [JellyActor], parkActors: [JellyActor], scene: String) {
        guard FootLog.on else { return }
        let now = CACurrentMediaTime()
        for a in actors { recordMove(id: a.id, key: a.id, brain: a.brain, asleep: a.asleep, now: now, scene: scene) }
        for a in parkActors { recordMove(id: a.id, key: 1000 + a.id, brain: a.brain, asleep: a.asleep, now: now, scene: scene) }
        if now - lastCtxT >= 30 {
            if lastCtxT != 0 {
                var list: [[String: Any]] = []
                for (k, v) in moves.sorted(by: { $0.key < $1.key }) { list.append(["key": k, "move": v.name, "species": moveSpecies[k] ?? "?"]) }
                var l = stamp(); l["ev"] = "ctx"; l["scene"] = scene; l["interval_ms"] = FootLog.lastIntervalMs; l["moves"] = list
                write(l)
            }
            lastCtxT = now
        }
    }

    /// One body's move check (tests call it directly). `key` distinguishes bodies with the same id (home vs park).
    func recordMove(id: Int, key: Int, brain b: BlobBrain?, asleep: Bool, now: Double, scene: String) {
        guard FootLog.on, let b else { return }
        let k = MoveKey(script: b.scriptKindName, idle: b.idleState.kind, activity: b.activity, gait: b.gait.phase, volley: b.volley.active ? b.volley.phase : nil,
                        race: b.race.active, held: b.held, asleep: asleep)
        let old = moves[key]
        guard old != k else { return }
        moves[key] = k
        if old == nil { moveSpecies[key] = "\(b.feature)" }
        var l = stamp(); l["ev"] = "move"; l["id"] = id; l["key"] = key; l["species"] = moveSpecies[key] ?? "?"
        l["from"] = old?.name ?? "(first seen)"; l["to"] = k.name; l["scene"] = scene; l["interval_ms"] = FootLog.lastIntervalMs
        write(l)
    }

    /// Wall clock for matching a phone screenshot: ISO8601 with seconds and zone, plus local hh:mm:ss.
    private func stamp() -> [String: Any] {
        let d = Date()
        return ["t": Self.isoFmt.string(from: d), "local": Self.clockFmt.string(from: d), "mono": CACurrentMediaTime()]
    }

    private func write(_ obj: [String: Any]) {
        guard let d = try? JSONSerialization.data(withJSONObject: obj, options: [.sortedKeys]) else { return }
        if handle == nil || handleURL != url {
            try? handle?.close(); handle = nil; handleURL = url
            if !FileManager.default.fileExists(atPath: url.path) { FileManager.default.createFile(atPath: url.path, contents: nil) }
            handle = try? FileHandle(forWritingTo: url); _ = try? handle?.seekToEnd()
        }
        handle?.write(d); handle?.write(Data([10]))
    }
}
