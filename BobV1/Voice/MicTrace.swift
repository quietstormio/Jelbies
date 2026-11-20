//
//  MicTrace.swift
//  Per-press timing trace of the hold-to-talk mic (what a press costs, step by step) plus the audio / frame-pacing / main-thread disturbance
//  around it. Collected ONLY when `-VoiceLog 1` is on or `-MicBench N` runs (dev builds); when off every hook is one nil / Bool test and nothing
//  is allocated, no timer or observer exists. It changes nothing the player sees, hears or feels. Read the lines with Voice/MicBench.swift.
//
//  Units: "abs" = ms from touch-down; durations are ms; "r_" fields are ms from the release (the finger lifting).
//  Marks are stamped on the thread where the event happens (session queue, audio tap, notification thread); nothing hops to main first.
//

import Foundation
import AVFoundation
import QuartzCore

nonisolated enum TraceMark: Int, CaseIterable, Sendable {
    case begin, sessionAsked, queueEntered, categoryDone, activeDone, engineUp, live
    case startEntered, engineReady, analyzerBuilt, contextBegin, contextDone, analyzerStarted, volatile
    case release, listenOff, glowGone, engineStopped, finalized, transcript, heard, reaction, putBack
}

/// One press. All state behind one lock (marks arrive from several threads).
nonisolated final class PressTrace: @unchecked Sendable {
    let number: Int
    let cold: Bool
    let t0: Double
    let variant: String
    private let lock = NSLock()
    private var at: [Double?] = Array(repeating: nil, count: TraceMark.allCases.count)
    private var _quick = false, _ears = "", _cat0 = "", _putBack = "pending", _finished = false, _timedOut = false
    private var _summary: PressSummary?
    private var waiters: [@Sendable () -> Void] = []

    init(number: Int, cold: Bool, t0: Double, variant: String) { self.number = number; self.cold = cold; self.t0 = t0; self.variant = variant }

    /// First write wins; a finished trace ignores everything.
    func mark(_ m: TraceMark, at t: Double = CACurrentMediaTime()) {
        lock.lock(); defer { lock.unlock() }
        guard !_finished, at[m.rawValue] == nil else { return }
        at[m.rawValue] = t
    }
    func time(_ m: TraceMark) -> Double? { lock.lock(); defer { lock.unlock() }; return at[m.rawValue] }
    /// ms from touch-down.
    func abs(_ m: TraceMark) -> Double? { time(m).map { ($0 - t0) * 1000 } }
    /// ms from release.
    func rel(_ m: TraceMark) -> Double? { guard let r = time(.release), let t = time(m) else { return nil }; return (t - r) * 1000 }
    /// Duration between two marks, ms.
    func span(_ a: TraceMark, _ b: TraceMark) -> Double? { guard let x = time(a), let y = time(b) else { return nil }; return (y - x) * 1000 }

    var quick: Bool { get { lock.lock(); defer { lock.unlock() }; return _quick } set { lock.lock(); _quick = newValue; lock.unlock() } }
    var ears: String { get { lock.lock(); defer { lock.unlock() }; return _ears } set { lock.lock(); _ears = newValue; lock.unlock() } }
    /// The session category the queue block found before it switched (first write wins).
    func setCategoryBefore(_ c: String) { lock.lock(); if _cat0.isEmpty { _cat0 = c }; lock.unlock() }
    var categoryBefore: String { lock.lock(); defer { lock.unlock() }; return _cat0 }
    /// ran = the hub put `.ambient` back; voided = a newer press cancelled it; none-ears = Ears owns the session (no put-back); no-hub.
    var putBackOutcome: String { get { lock.lock(); defer { lock.unlock() }; return _putBack } set { lock.lock(); _putBack = newValue; lock.unlock() } }
    var isFinished: Bool { lock.lock(); defer { lock.unlock() }; return _finished }
    var timedOut: Bool { lock.lock(); defer { lock.unlock() }; return _timedOut }
    var summary: PressSummary? { lock.lock(); defer { lock.unlock() }; return _summary }

    /// Calls `f` once when the trace is finished (at once if it already is).
    func whenFinished(_ f: @escaping @Sendable () -> Void) {
        lock.lock()
        if _finished { lock.unlock(); f(); return }
        waiters.append(f); lock.unlock()
    }
    func finish(_ s: PressSummary, timedOut: Bool) {
        lock.lock(); _summary = s; _finished = true; _timedOut = timedOut
        let w = waiters; waiters = []; lock.unlock()
        for f in w { f() }
    }
}

/// The numbers of one press, in print order. `nil` = not measured ("-").
nonisolated struct PressSummary: Sendable {
    var fields: [(String, Double?)] = []
    var extras: [(String, String)] = []

    static func fmt(_ v: Double?) -> String { v.map { String(Int($0.rounded())) } ?? "-" }

    func line(number: Int, cold: Bool, variant: String, note: String? = nil) -> String {
        var s = "[micbench] press \(number) variant=\(variant) cold=\(cold ? 1 : 0)"
        for (k, v) in extras { s += " \(k)=\(v)" }
        for (k, v) in fields { s += " \(k)=\(Self.fmt(v))" }
        if let note { s += " \(note)" }
        return s
    }
}

nonisolated enum MicTrace {
    /// Test seam: nil = decided once at launch from `-VoiceLog 1` / `-MicBench N`.
    nonisolated(unsafe) static var override: Bool?
    private static let launchEnabled: Bool = isEnabled()
    /// The trace runs only where dev arguments are on (never in an App Store build), and only with `-VoiceLog 1` or `-MicBench N`.
    static func isEnabled(devArgs: Bool = DevArgs.enabled, defaults: UserDefaults = .standard) -> Bool {
        devArgs && (defaults.bool(forKey: "VoiceLog") || MicBench.count(devArgs: devArgs, defaults: defaults) > 0)
    }
    static var enabled: Bool { override ?? launchEnabled }
    /// True while the frame / main-thread / playback recorders run (the stage's draw hook reads it: one Bool test per frame).
    nonisolated(unsafe) static private(set) var recording = false

    private static let lock = NSLock()
    nonisolated(unsafe) private static var _latest: PressTrace?
    nonisolated(unsafe) private static var presses = 0
    nonisolated(unsafe) private static var history: [PressTrace] = []
    nonisolated(unsafe) private static var frames: [Double] = []
    nonisolated(unsafe) private static var ticks: [Double] = []
    nonisolated(unsafe) private static var playback: [(t: Double, expected: Bool, playing: Bool)] = []
    nonisolated(unsafe) private static var events: [(t: Double, kind: String, detail: String)] = []
    nonisolated(unsafe) private static var recordStart = 0.0
    nonisolated(unsafe) private static var glowWait: PressTrace?
    nonisolated(unsafe) private static var observers: [NSObjectProtocol] = []
    nonisolated(unsafe) private static var probe: Timer?
    nonisolated(unsafe) private static var probeN = 0
    /// Where lines are appended (Documents/micbench.log); a test points it elsewhere.
    nonisolated(unsafe) static var logURL: URL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("micbench.log")
    /// Prints every finished press (the bench prints its own, with the quick flag).
    nonisolated(unsafe) static var printFinished = true
    /// The scene-music engine's identity (refreshed at each press), so a configuration-change notice can say whose engine it was.
    nonisolated(unsafe) static var sceneEngineID: ObjectIdentifier?
    static let q = DispatchQueue(label: "io.mgsllc.BobV1.micbench", qos: .utility)

    /// The newest press (the input's start / stop side stamps it; release-side code captures its own).
    static var latest: PressTrace? { lock.lock(); defer { lock.unlock() }; return _latest }

    // MARK: press

    /// A press began (touch-down). nil when the trace is off: the whole cost of a press with the trace off is this call.
    @MainActor
    static func begin(t0: Double, variant: String = MicBench.variant()) -> PressTrace? {
        guard enabled else { return nil }
        sceneEngineID = AudioHub.shared.traceSceneEngineID
        startRecording()
        lock.lock()
        let t = PressTrace(number: presses + 1, cold: presses == 0, t0: t0, variant: variant)
        presses += 1
        _latest = t
        history.append(t); if history.count > 60 { history.removeFirst(20) }
        lock.unlock()
        t.ears = "\(Ears.shared.state)"
        return t
    }

    /// The press never opened (mode refused): forget it.
    static func discard(_ t: PressTrace?) {
        guard let t else { return }
        lock.lock(); history.removeAll { $0 === t }; if _latest === t { _latest = history.last }; presses = max(0, presses - 1); lock.unlock()
    }

    /// The finger lifted: start watching for the end (put-back + 1 s, or 8 s after the release).
    static func released(_ t: PressTrace?) {
        guard let t else { return }
        t.mark(.release)
        lock.lock(); glowWait = t; lock.unlock()
        watch(t)
    }

    private static func watch(_ t: PressTrace) {
        q.asyncAfter(deadline: .now() + 0.1) {
            guard !t.isFinished else { return }
            let now = CACurrentMediaTime()
            let pb = t.time(.putBack), r = t.time(.release) ?? now
            if let pb, now >= pb + 1.0 { finalize(t, timedOut: false) }
            else if now >= r + 8 { finalize(t, timedOut: true) }
            else { watch(t) }
        }
    }

    /// Ends a press that will never see its release (the bench calls it when `release()` did nothing).
    static func abandon(_ t: PressTrace?, reason: String) {
        guard let t, !t.isFinished else { return }
        q.async { finalize(t, timedOut: true, note: reason) }
    }

    // MARK: recorders

    @MainActor
    private static func startRecording() {
        guard !recording else { return }
        lock.lock(); recordStart = CACurrentMediaTime(); lock.unlock()
        recording = true
        let nc = NotificationCenter.default
        // queue nil: the observer runs on the posting thread and stamps there
        observers.append(nc.addObserver(forName: .AVAudioEngineConfigurationChange, object: nil, queue: nil) { n in
            let ours = (n.object as AnyObject?).map { ObjectIdentifier($0) } == sceneEngineID
            record("cfg", ours ? "scene" : "other")
        })
        observers.append(nc.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: nil) { n in
            let r = (n.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt) ?? 99
            record("route", "reason\(r)")
        })
        observers.append(nc.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: nil) { n in
            let r = (n.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt) ?? 99
            record("intr", "type\(r)")
        })
        let p = Timer(timeInterval: 0.01, repeats: true) { _ in
            let now = CACurrentMediaTime()
            probeN += 1
            var sample: (Bool, Bool)?
            if probeN % 5 == 0 { sample = MainActor.assumeIsolated { AudioHub.shared.traceMusicProbe() } }
            lock.lock()
            ticks.append(now); if ticks.count > 4000 { ticks.removeFirst(1500) }
            if let s = sample { playback.append((now, s.0, s.1)); if playback.count > 1500 { playback.removeFirst(500) } }
            lock.unlock()
        }
        RunLoop.main.add(p, forMode: .common)
        probe = p
    }

    /// Real draw timestamps from the Metal view (called from `MelonStageController.draw` only while `recording`).
    static func frame(_ now: Double) {
        lock.lock()
        frames.append(now); if frames.count > 6000 { frames.removeFirst(2000) }
        let g = glowWait; glowWait = nil
        lock.unlock()
        if let g, g.time(.listenOff) != nil { g.mark(.glowGone, at: now) } else if let g { lock.lock(); glowWait = g; lock.unlock() }
    }

    /// A route change, engine configuration change, interruption or scene-music restart (stamped where it happened).
    static func record(_ kind: String, _ detail: String) {
        guard recording else { return }
        lock.lock(); events.append((CACurrentMediaTime(), kind, detail)); if events.count > 400 { events.removeFirst(100) }; lock.unlock()
    }

    // MARK: summary

    private struct Win { var n = 0, med = 0.0, worst = 0.0, over25 = 0 }

    private static func frameWindow(_ f: [Double], _ a: Double, _ b: Double) -> Win? {
        var iv: [Double] = []
        var prev: Double?
        for t in f where t >= a - 0.5 && t <= b { if let p = prev, t >= a { iv.append((t - p) * 1000) }; prev = t }
        guard !iv.isEmpty else { return nil }
        let s = iv.sorted()
        return Win(n: iv.count, med: s[s.count / 2], worst: s.last ?? 0, over25: iv.filter { $0 > 25 }.count)
    }
    /// The longest gap between main-queue probe ticks (10 ms nominal) inside the window.
    private static func mainGap(_ k: [Double], _ a: Double, _ b: Double) -> Double? {
        var worst: Double?
        var prev: Double?
        for t in k where t >= a - 0.5 && t <= b { if let p = prev, t >= a { worst = Swift.max(worst ?? 0, (t - p) * 1000) }; prev = t }
        return worst
    }

    private static func finalize(_ t: PressTrace, timedOut: Bool, note: String? = nil) {
        lock.lock()
        let f = frames, k = ticks, pb = playback, ev = events, rs = recordStart
        let idx = history.firstIndex { $0 === t }
        let prev = idx.flatMap { $0 > 0 ? history[$0 - 1] : nil }
        lock.unlock()
        let t0 = t.t0, tr = t.time(.release), tp = t.time(.putBack)
        let end = (tp ?? (tr ?? t0)) + 1.0
        var s = PressSummary()
        func put(_ k: String, _ v: Double?) { s.fields.append((k, v)) }
        s.extras = [("quick", t.quick ? "1" : "0"), ("ears", t.ears), ("cat0", t.categoryBefore.replacingOccurrences(of: "AVAudioSessionCategory", with: "")),
                    ("putBackOutcome", t.putBackOutcome)]
        if let note { s.extras.append(("note", note)) }
        if timedOut { s.extras.append(("timedOut", "1")) }
        put("begin", t.abs(.begin)); put("asked", t.abs(.sessionAsked))
        put("queueWait", t.span(.sessionAsked, .queueEntered)); put("setCategory", t.span(.queueEntered, .categoryDone))
        put("setActive", t.span(.categoryDone, .activeDone)); put("engine", t.span(.activeDone, .engineUp))
        put("engineUp", t.abs(.engineUp)); put("live", t.abs(.live))
        put("startAt", t.abs(.startEntered)); put("gateWait", t.span(.startEntered, .engineReady))
        put("analyzer", t.span(.engineReady, .analyzerBuilt)); put("setContext", t.span(.contextBegin, .contextDone))
        put("analyzerStart", t.span(.contextDone, .analyzerStarted)); put("analyzerUp", t.abs(.analyzerStarted)); put("volatile", t.abs(.volatile))
        put("hold", t.abs(.release))
        for (name, m) in [("r_listenOff", TraceMark.listenOff), ("r_glowGone", .glowGone), ("r_engineStop", .engineStopped), ("r_finalize", .finalized),
                          ("r_transcript", .transcript), ("r_heard", .heard), ("r_reaction", .reaction), ("r_putBack", .putBack)] { put(name, t.rel(m)) }
        // disturbance: touch-down .. put-back + 1 s
        let mine = ev.filter { $0.t >= t0 && $0.t <= end }
        func count(_ kind: String) -> Double { Double(mine.filter { $0.kind == kind }.count) }
        put("cfg", count("cfg")); put("route", count("route")); put("intr", count("intr")); put("sceneRestart", count("sceneRestart"))
        if !mine.isEmpty { s.extras.append(("events", mine.map { "\($0.kind)(\($0.detail))@+\(Int(($0.t - t0) * 1000))" }.joined(separator: ","))) }
        // playback: samples every 50 ms; a sample where the music is expected but not advancing is "down"
        let inWin = pb.filter { $0.t >= t0 && $0.t <= end }
        var down = 0.0, run = 0.0, longest = 0.0
        for i in 1..<Swift.max(inWin.count, 1) where inWin.count > 1 {
            let dt = (inWin[i].t - inWin[i - 1].t) * 1000
            if inWin[i - 1].expected && !inWin[i - 1].playing && inWin[i].expected && !inWin[i].playing { down += dt; run += dt; longest = Swift.max(longest, run) } else { run = 0 }
        }
        let expected = inWin.contains { $0.expected }
        put("playDown", expected ? down : nil); put("playGap", expected ? longest : nil)
        // frames and main thread: control (2 s before), the second after touch-down, the second after release
        let quietCtl = !t.quick && rs <= t0 - 2 && (prev?.time(.putBack).map { $0 <= t0 - 2 } ?? true)
        s.extras.append(("ctlQuiet", quietCtl ? "1" : "na"))
        func win(_ name: String, _ a: Double, _ b: Double, valid: Bool = true) {
            let w = valid ? frameWindow(f, a, b) : nil
            put("\(name)_ivMed", w?.med); put("\(name)_ivWorst", w?.worst); put("\(name)_over25", w.map { Double($0.over25) })
            put("\(name)_main", valid ? mainGap(k, a, b) : nil)
        }
        win("ctl", t0 - 2, t0, valid: quietCtl)
        win("press", t0, t0 + 1)
        if let tr { win("rel", tr, tr + 1) }
        t.finish(s, timedOut: timedOut)
        if printFinished && MicBench.active == false { emit(s.line(number: t.number, cold: t.cold, variant: t.variant)) }
    }

    /// NSLog + append to Documents/micbench.log, off the main thread (this runs on `q`).
    static func emit(_ line: String) {
        NSLog("%@", line)
        let data = Data((line + "\n").utf8)
        if let h = try? FileHandle(forWritingTo: logURL) { defer { try? h.close() }; _ = try? h.seekToEnd(); try? h.write(contentsOf: data) }
        else { try? data.write(to: logURL) }
    }

    /// Stops the recorders (tests; the bench leaves them on).
    @MainActor
    static func stopRecording() {
        probe?.invalidate(); probe = nil
        for o in observers { NotificationCenter.default.removeObserver(o) }
        observers = []
        recording = false
        lock.lock(); frames = []; ticks = []; playback = []; events = []; glowWait = nil; lock.unlock()
    }
    static func resetForTest() {
        lock.lock(); _latest = nil; presses = 0; history = []; lock.unlock()
    }
}
