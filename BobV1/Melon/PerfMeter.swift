//
//  PerfMeter.swift
//  On-device frame meter. Off unless launched with `-PerfLog 1` (which is then remembered in UserDefaults key "PerfLog" until `-PerfLog 0`).
//  Off = one Bool test per call. On = a few mach_absolute_time reads per frame into preallocated rings (no per-frame allocation);
//  every 5 s (and on didEnterBackground) one JSON line is appended to Documents/perf_log.jsonl, and a {"type":"summary"} line on background.
//  Nothing is shown in the UI. Copy it off the phone:
//    devicectl device copy from --domain-type appDataContainer --domain-identifier io.mgsllc.BobV1 --source Documents/perf_log.jsonl
//

import Foundation
import QuartzCore
#if canImport(UIKit)
import UIKit
#endif

nonisolated enum PerfStage: Int, CaseIterable {
    case gpuwait, brain, sim, skin, feature, wear, encode
    var name: String { ["gpu_wait", "brain", "sim", "skin", "feature", "wear", "encode"][rawValue] }
}

/// What the stage knows cheaply; read only when a line is written.
nonisolated struct PerfContext {
    var scene = "game"
    var jelbies = 0
    var preferredFPS = 0
    var maxFPS = 0
    var renderScale = 0.0
    var tier = ""
}

nonisolated final class PerfMeter: @unchecked Sendable {
    nonisolated(unsafe) static var on = false
    nonisolated(unsafe) static let shared = PerfMeter()
    /// Set by the stage; called only when a line is written.
    nonisolated(unsafe) static var context: (() -> PerfContext)?

    static let nStages = PerfStage.allCases.count
    private static let cap = 2048                      // frames kept per window (5 s at 120 Hz = 600)
    private static let tb: Double = { var i = mach_timebase_info_data_t(); mach_timebase_info(&i); return Double(i.numer) / Double(i.denom) / 1e6 }()   // ticks -> ms

    var logURL: URL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("perf_log.jsonl")
    var windowSeconds = 5.0

    // per-frame rings (main thread)
    private let interval = UnsafeMutablePointer<Double>.allocate(capacity: cap)
    private let cpu = UnsafeMutablePointer<Double>.allocate(capacity: cap)
    private let stages = UnsafeMutablePointer<Double>.allocate(capacity: cap * nStages)
    private var n = 0                                  // frames in this window (may exceed cap: ring wraps, newest kept)
    var cur = [Double](repeating: 0, count: nStages)
    private var lastBegin: UInt64 = 0, frameStart: UInt64 = 0, windowStart: UInt64 = 0
    // gpu ring (completion handler thread)
    private let gpu = UnsafeMutablePointer<Double>.allocate(capacity: cap)
    private var gpuN = 0
    private let gpuLock = NSLock()
    // since launch
    private var tFrames = 0, tOver17 = 0, tOver33 = 0, tIntervalSum = 0.0, tMax = 0.0, tCpuSum = 0.0
    private var tStage = [Double](repeating: 0, count: nStages)
    private var tGpuSum = 0.0, tGpuN = 0
    private var hist = [Int](repeating: 0, count: 401)     // 0.25 ms bins to 100 ms
    private var observing = false

    deinit { interval.deallocate(); cpu.deallocate(); stages.deallocate(); gpu.deallocate() }

    // MARK: enable

    /// Call once at launch. `-PerfLog 1` / `-PerfLog 0` arrive through the argument domain; the value is persisted so a later plain launch keeps logging.
    static func configure(defaults: UserDefaults = .standard) {
        let v = defaults.object(forKey: "PerfLog") != nil && defaults.bool(forKey: "PerfLog")
        defaults.set(v, forKey: "PerfLog")
        if v { shared.enable() } else { on = false }
    }

    func enable() {
        PerfMeter.on = true
        guard !observing else { return }
        observing = true
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in          // frames drive the 5 s flush; this covers a stage that stopped drawing
            guard let self, PerfMeter.on else { return }
            let now = mach_absolute_time()
            if self.windowStart == 0 { self.windowStart = now }
            else if Double(now &- self.windowStart) * PerfMeter.tb >= self.windowSeconds * 1000 + 500 { self.flush(at: now, idleLine: true) }
        }
        RunLoop.main.add(timer, forMode: .common)
        #if canImport(UIKit)
        NotificationCenter.default.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { [weak self] _ in
            guard let self, PerfMeter.on else { return }
            self.flush(); self.writeSummary()
        }
        #endif
    }

    // MARK: probes (all no-ops when off)

    @inline(__always) static func begin() -> UInt64 { on ? mach_absolute_time() : 0 }
    @inline(__always) static func end(_ s: PerfStage, _ t0: UInt64) {
        guard on, t0 != 0 else { return }
        shared.cur[s.rawValue] += Double(mach_absolute_time() &- t0) * tb
    }
    @inline(__always) static func frameBegin() { if on { shared.beginFrame(mach_absolute_time()) } }
    @inline(__always) static func frameEnd() { if on { shared.endFrame(mach_absolute_time()) } }
    @inline(__always) static func gpuDone(ms: Double) { if on { shared.addGPU(ms) } }

    func beginFrame(_ t: UInt64) {
        frameStart = t
        for i in 0..<PerfMeter.nStages { cur[i] = 0 }
        if windowStart == 0 { windowStart = t }
    }

    func endFrame(_ t: UInt64) {
        defer { lastBegin = frameStart }
        let cpuMs = Double(t &- frameStart) * PerfMeter.tb
        var iv = lastBegin == 0 ? 0 : Double(frameStart &- lastBegin) * PerfMeter.tb
        if iv > 1000 { iv = 0; windowStart = frameStart }          // a pause / backgrounding gap is not a frame interval
        if iv == 0 { return }
        let k = n % PerfMeter.cap
        interval[k] = iv; cpu[k] = cpuMs
        for i in 0..<PerfMeter.nStages { stages[k * PerfMeter.nStages + i] = cur[i] }
        n += 1
        tFrames += 1; tIntervalSum += iv; tMax = max(tMax, iv); tCpuSum += cpuMs
        if iv > 16.7 { tOver17 += 1 }
        if iv > 33 { tOver33 += 1 }
        hist[min(Int(iv * 4), 400)] += 1
        for i in 0..<PerfMeter.nStages { tStage[i] += cur[i] }
        if Double(t &- windowStart) * PerfMeter.tb >= windowSeconds * 1000 { flush(at: t) }
    }

    func addGPU(_ ms: Double) {
        gpuLock.lock()
        gpu[gpuN % PerfMeter.cap] = ms; gpuN += 1
        tGpuSum += ms; tGpuN += 1
        gpuLock.unlock()
    }

    // MARK: output

    static func pct(_ sorted: [Double], _ p: Double) -> Double {
        guard !sorted.isEmpty else { return 0 }
        return sorted[max(0, min(sorted.count - 1, Int((p * Double(sorted.count)).rounded(.up)) - 1))]
    }
    private static func r(_ x: Double) -> Double { (x * 1000).rounded() / 1000 }
    private static func stat(_ a: [Double]) -> [String: Double] {
        let s = a.sorted()
        return ["mean": r(a.isEmpty ? 0 : a.reduce(0, +) / Double(a.count)), "p50": r(pct(s, 0.5)), "p95": r(pct(s, 0.95)), "p99": r(pct(s, 0.99)), "max": r(s.last ?? 0)]
    }

    private func header() -> [String: Any] {
        let c = PerfMeter.context?() ?? PerfContext()
        var sys = utsname(); uname(&sys)
        let machine = withUnsafeBytes(of: &sys.machine) { String(cString: $0.bindMemory(to: CChar.self).baseAddress!) }
        let model = ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] ?? machine
        let th: String
        switch ProcessInfo.processInfo.thermalState { case .nominal: th = "nominal"; case .fair: th = "fair"; case .serious: th = "serious"; case .critical: th = "critical"; @unknown default: th = "unknown" }
        return ["t": ISO8601DateFormatter().string(from: Date()), "scene": c.scene, "jelbies": c.jelbies, "device": model, "ios": ProcessInfo.processInfo.operatingSystemVersionString,
                "thermal": th, "low_power": ProcessInfo.processInfo.isLowPowerModeEnabled, "preferred_fps": c.preferredFPS, "max_fps": c.maxFPS,
                "render_scale": c.renderScale, "tier": c.tier]
    }

    /// Writes the current window as one JSON line and starts a new window. Returns the object (tests read it).
    @discardableResult
    func flush(at now: UInt64 = mach_absolute_time(), idleLine: Bool = false) -> [String: Any]? {
        defer { n = 0; windowStart = now; gpuLock.lock(); gpuN = 0; gpuLock.unlock() }
        let m = min(n, PerfMeter.cap)
        guard m > 0 else {
            guard idleLine else { return nil }          // the timer found a window with no frames at all (the stage stopped drawing): still say so
            var l = header(); l["type"] = "window"; l["frames"] = 0; l["window_s"] = PerfMeter.r(Double(now &- windowStart) * PerfMeter.tb / 1000)
            append(l); return l
        }
        let ns = PerfMeter.nStages
        let iv = Array(UnsafeBufferPointer(start: interval, count: m)), cp = Array(UnsafeBufferPointer(start: cpu, count: m))
        var line = header()
        line["type"] = "window"
        line["window_s"] = PerfMeter.r(Double(now &- windowStart) * PerfMeter.tb / 1000)
        line["frames"] = n
        line["interval_ms"] = PerfMeter.stat(iv)
        line["pct_over_16_7ms"] = PerfMeter.r(Double(iv.filter { $0 > 16.7 }.count) / Double(m) * 100)
        line["pct_over_33ms"] = PerfMeter.r(Double(iv.filter { $0 > 33 }.count) / Double(m) * 100)
        line["frame_cpu_ms"] = PerfMeter.stat(cp)
        var st: [String: Any] = [:]
        for s in PerfStage.allCases {
            let a = (0..<m).map { stages[$0 * ns + s.rawValue] }
            let sorted = a.sorted()
            st[s.name] = ["mean": PerfMeter.r(a.reduce(0, +) / Double(m)), "p95": PerfMeter.r(PerfMeter.pct(sorted, 0.95))]
        }
        line["stages_cpu_ms"] = st
        gpuLock.lock()
        let g = Array(UnsafeBufferPointer(start: gpu, count: min(gpuN, PerfMeter.cap)))
        gpuLock.unlock()
        let gs = g.sorted()
        line["gpu_ms"] = ["mean": PerfMeter.r(g.isEmpty ? 0 : g.reduce(0, +) / Double(g.count)), "p95": PerfMeter.r(PerfMeter.pct(gs, 0.95)), "max": PerfMeter.r(gs.last ?? 0), "samples": g.count] as [String: Any]
        let li = iv.indices.max { iv[$0] < iv[$1] }!
        var ls: [String: Any] = [:]
        for s in PerfStage.allCases { ls[s.name] = PerfMeter.r(stages[li * ns + s.rawValue]) }
        line["longest_frame"] = ["interval_ms": PerfMeter.r(iv[li]), "cpu_ms": PerfMeter.r(cp[li]), "stages_cpu_ms": ls] as [String: Any]
        append(line)
        return line
    }

    @discardableResult
    func writeSummary() -> [String: Any] {
        var line = header()
        line["type"] = "summary"
        let f = Double(max(tFrames, 1))
        func q(_ p: Double) -> Double {
            let target = Int((p * Double(tFrames)).rounded(.up)); var acc = 0
            for (i, c) in hist.enumerated() { acc += c; if acc >= target { return Double(i) / 4 } }
            return 100
        }
        line["frames"] = tFrames
        line["interval_ms"] = ["mean": PerfMeter.r(tIntervalSum / f), "p50": q(0.5), "p95": q(0.95), "p99": q(0.99), "max": PerfMeter.r(tMax)] as [String: Any]
        line["pct_over_16_7ms"] = PerfMeter.r(Double(tOver17) / f * 100)
        line["pct_over_33ms"] = PerfMeter.r(Double(tOver33) / f * 100)
        line["frame_cpu_ms_mean"] = PerfMeter.r(tCpuSum / f)
        var st: [String: Any] = [:]
        for s in PerfStage.allCases { st[s.name] = PerfMeter.r(tStage[s.rawValue] / f) }
        line["stages_cpu_ms_mean"] = st
        line["gpu_ms_mean"] = PerfMeter.r(tGpuN > 0 ? tGpuSum / Double(tGpuN) : 0)
        append(line)
        return line
    }

    private func append(_ obj: [String: Any]) {
        guard var d = try? JSONSerialization.data(withJSONObject: obj, options: [.sortedKeys]) else { return }
        d.append(10)
        if !FileManager.default.fileExists(atPath: logURL.path) { FileManager.default.createFile(atPath: logURL.path, contents: nil) }
        if let h = try? FileHandle(forWritingTo: logURL) { _ = try? h.seekToEnd(); try? h.write(contentsOf: d); try? h.close() }
    }
}
