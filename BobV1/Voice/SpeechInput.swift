import Foundation
import AVFoundation
import Speech

/// Whether the mic + on-device dictation can be used right now.
enum VoiceAvailability: Equatable {
    case unknown
    case needsDownload(progress: Double)
    case ready
    case unavailable(reason: String)
    case denied
}

enum SpeechInputError: Error {
    case notReady
    case noFormat
    case alreadyRunning
}

/// Push-to-talk speech source. One start()/stop() pair per press.
@MainActor
protocol SpeechInput: AnyObject {
    var availability: VoiceAvailability { get }
    /// 0...1 smoothed RMS, called on main while started.
    var onLevel: ((Float) -> Void)? { get set }
    /// Permission + asset install + optional prepareToAnalyze. Never throws.
    func prepare(contextualWords: [String]) async
    func start(contextualWords: [String]) async throws
    /// Final transcript ("" if nothing). Keeps recording for a short post-roll first (the tail of the last word).
    func stop() async -> String
    /// Speculatively brings the mic up (first tap of a double-tap, mic-button touch-down) so the first word is not lost. Silent no-op if unavailable.
    func warmUp()
    /// Tears a speculative warm-up down if no `start` follows. Safe any time.
    func coolDown()
    /// Stops at once with no post-roll; the transcript is discarded.
    func abort() async
}

extension SpeechInput {
    func warmUp() {}
    func coolDown() {}
    func abort() async { _ = await stop() }
}

// MARK: - Fake

@MainActor
final class FakeSpeechInput: SpeechInput {
    private(set) var availability: VoiceAvailability = .ready
    var onLevel: ((Float) -> Void)?
    /// Overrides `-VoiceFakeText` when set.
    var nextTranscript: String?
    private(set) var isStarted = false
    private(set) var lastContextualWords: [String] = []
    private var timer: Timer?
    private var phase: Double = 0

    init() {}
    nonisolated deinit {}

    func prepare(contextualWords: [String]) async { availability = .ready }

    func start(contextualWords: [String]) async throws {
        lastContextualWords = contextualWords
        isStarted = true
        phase = 0
        timer?.invalidate()
        let t = Timer(timeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
        tick()
    }

    private func tick() {
        guard isStarted else { return }
        phase += 1.0 / 30.0
        let v = 0.5 + 0.4 * sin(phase * 2 * .pi * 2.5)
        onLevel?(Float(max(0.05, min(1, v))))
    }

    func stop() async -> String {
        timer?.invalidate()
        timer = nil
        let was = isStarted
        isStarted = false
        guard was else { return "" }
        if let t = nextTranscript { nextTranscript = nil; return t }
        return UserDefaults.standard.string(forKey: "VoiceFakeText") ?? ""
    }
}

// MARK: - Factory

enum SpeechInputFactory {
    @MainActor
    static func make(defaults: UserDefaults = .standard) -> SpeechInput {
        defaults.bool(forKey: "VoiceFakeMic") ? FakeSpeechInput() : DictationSpeechInput()
    }
}

// MARK: - Real

nonisolated enum VoiceAudioTuning {
    /// The mic keeps recording this long after release before it stops and finalises (the glow still hides at once).
    static let postRoll: TimeInterval = 0.4
    /// Audio kept from engine start until the analyzer stream is attached.
    static let preRollSeconds: Double = 1.5
    /// A warm-up with no hold after it is torn down after this long.
    static let warmTimeout: TimeInterval = 2.5
}

nonisolated enum VoiceTranscriptLog {
    static var on: Bool { UserDefaults.standard.bool(forKey: "VoiceLog") }
    static func log(_ s: @autoclosure () -> String) { if on { NSLog("[voice] %@", s()) } }
}

/// Collects dictation results: finals are committed, the latest volatile text is a fallback (and the tail after the last final).
nonisolated struct TranscriptAccumulator {
    private(set) var finals: [String] = []
    private(set) var volatile = ""
    mutating func add(text: String, isFinal: Bool) {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if isFinal { if !t.isEmpty { finals.append(t) }; volatile = "" } else { volatile = t }
    }
    var result: String {
        (finals + (volatile.isEmpty ? [] : [volatile])).joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// Audio-thread side of the pipe: converts tap buffers and feeds the analyzer stream. Until a stream is attached the converted buffers
/// are kept in a ring (the last `preRollSeconds`); `attach` flushes them first, so nothing recorded before the analyzer started is lost.
final class AudioPipe: @unchecked Sendable {
    let format: AVAudioFormat
    private let onLevel: @Sendable (Float) -> Void
    private let lock = NSLock()
    private var continuation: AsyncStream<AnalyzerInput>.Continuation?
    private var pending: [AVAudioPCMBuffer] = []
    private var pendingFrames = 0
    private var converter: AVAudioConverter?
    private var smoothed: Float = 0
    private(set) var buffersBefore = 0
    private(set) var buffersAfter = 0
    private(set) var convertFailures = 0

    init(format: AVAudioFormat, onLevel: @escaping @Sendable (Float) -> Void = { _ in }) {
        self.format = format
        self.onLevel = onLevel
    }

    func handle(_ buffer: AVAudioPCMBuffer) {
        guard let out = convert(buffer) else {
            lock.lock(); convertFailures += 1; let n = convertFailures; lock.unlock()
            if n <= 3 { VoiceTranscriptLog.log("converter failed (\(buffer.format) -> \(format)) #\(n)") }
            return
        }
        lock.lock()
        if let c = continuation {
            buffersAfter += 1
            lock.unlock()
            reportLevel(buffer)
            c.yield(AnalyzerInput(buffer: out))
        } else {
            buffersBefore += 1
            pending.append(out); pendingFrames += Int(out.frameLength)
            let cap = Int(format.sampleRate * VoiceAudioTuning.preRollSeconds)
            while pendingFrames > cap, pending.count > 1 { pendingFrames -= Int(pending.removeFirst().frameLength) }
            lock.unlock()
        }
    }

    /// Flushes the buffered audio into the stream, then forwards live.
    @discardableResult
    func attach(_ c: AsyncStream<AnalyzerInput>.Continuation) -> Int {
        lock.lock(); defer { lock.unlock() }
        let n = pending.count
        for b in pending { c.yield(AnalyzerInput(buffer: b)) }
        pending = []; pendingFrames = 0
        continuation = c
        return n
    }

    func finish() {
        lock.lock(); let c = continuation; continuation = nil; pending = []; pendingFrames = 0; lock.unlock()
        c?.finish()
    }

    private func reportLevel(_ buffer: AVAudioPCMBuffer) {
        guard let ch = buffer.floatChannelData?[0], buffer.frameLength > 0 else { return }
        let n = Int(buffer.frameLength)
        var sum: Float = 0
        for i in 0..<n { sum += ch[i] * ch[i] }
        let rms = (sum / Float(n)).squareRoot()
        // Map roughly -50 dB...-10 dB to 0...1.
        let db = 20 * log10(max(rms, 1e-6))
        let norm = max(0, min(1, (db + 50) / 40))
        smoothed += (norm - smoothed) * (norm > smoothed ? 0.6 : 0.25)
        onLevel(smoothed)
    }

    private func convert(_ buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        if buffer.format == format { return buffer }
        if converter == nil || converter?.outputFormat != format {
            converter = AVAudioConverter(from: buffer.format, to: format)
            converter?.primeMethod = .none
        }
        guard let converter else { return nil }
        let ratio = converter.outputFormat.sampleRate / converter.inputFormat.sampleRate
        let cap = AVAudioFrameCount((Double(buffer.frameLength) * ratio).rounded(.up))
        guard cap > 0, let out = AVAudioPCMBuffer(pcmFormat: converter.outputFormat, frameCapacity: cap) else { return nil }
        var err: NSError?
        var done = false
        let status = converter.convert(to: out, error: &err) { _, ptr in
            defer { done = true }
            ptr.pointee = done ? .noDataNow : .haveData
            return done ? nil : buffer
        }
        if status == .error { VoiceTranscriptLog.log("AVAudioConverter error: \(String(describing: err))"); return nil }
        return out
    }
}

/// Hands the freshly started engine back to the main actor (it is not used from two threads at once).
private struct EngineBox: @unchecked Sendable {
    let engine: AVAudioEngine
    init(_ e: AVAudioEngine) { engine = e }
}

@MainActor
final class DictationSpeechInput: SpeechInput {
    private(set) var availability: VoiceAvailability = .unknown
    var onLevel: ((Float) -> Void)?
    var postRoll: TimeInterval = VoiceAudioTuning.postRoll

    private var locale: Locale?
    private var analyzerFormat: AVAudioFormat?
    private var engine: AVAudioEngine?
    private var analyzer: SpeechAnalyzer?
    private var pipe: AudioPipe?
    private var collector: Task<String, Never>?
    private var warmTask: Task<Bool, Never>?
    private var coolTask: Task<Void, Never>?
    private var isRunning = false
    private var starting = false
    private var sessionActive = false
    private var t0 = CACurrentMediaTime()

    init() {}
    nonisolated deinit {}

    private static func makeTranscriber(_ locale: Locale) -> DictationTranscriber {
        // Same as the .phrase preset (short form) but with volatile results, so a short phrase is still heard if no final arrives.
        DictationTranscriber(locale: locale, contentHints: [.shortForm], transcriptionOptions: [.punctuation],
                             reportingOptions: [.volatileResults], attributeOptions: [])
    }

    func prepare(contextualWords: [String]) async {
        // Permission.
        let granted = await AVAudioApplication.requestRecordPermission()
        guard granted else { availability = .denied; return }
        // Locale.
        guard let loc = await DictationTranscriber.supportedLocale(equivalentTo: Locale.current) else {
            availability = .unavailable(reason: "Language not supported"); return
        }
        locale = loc
        let module = Self.makeTranscriber(loc)
        // Assets.
        do {
            if let req = try await AssetInventory.assetInstallationRequest(supporting: [module]) {
                availability = .needsDownload(progress: 0)
                let progress = req.progress
                let watcher = Task { @MainActor [weak self] in
                    while !Task.isCancelled {
                        self?.availability = .needsDownload(progress: progress.fractionCompleted)
                        try? await Task.sleep(nanoseconds: 200_000_000)
                    }
                }
                defer { watcher.cancel() }
                try await req.downloadAndInstall()
            }
            _ = try? await AssetInventory.reserve(locale: loc)
            guard let fmt = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [module]) else {
                availability = .unavailable(reason: "No audio format"); return
            }
            analyzerFormat = fmt
            let analyzer = SpeechAnalyzer(modules: [module])
            try? await analyzer.prepareToAnalyze(in: fmt)
            await analyzer.cancelAndFinishNow()
            availability = .ready
        } catch {
            availability = .unavailable(reason: "\(error.localizedDescription)")
        }
    }

    // MARK: warm-up

    func warmUp() {
        guard availability == .ready, !isRunning, !starting else { return }
        t0 = CACurrentMediaTime()
        if warmTask == nil { warmTask = makeWarmTask() }
        scheduleCool()
    }

    func coolDown() {
        guard !isRunning, !starting else { return }
        coolTask?.cancel(); coolTask = nil
        let w = warmTask
        Task { [weak self] in
            _ = await w?.value
            guard let self, !self.isRunning, !self.starting else { return }
            self.teardownEngine()
        }
    }

    private func scheduleCool() {
        coolTask?.cancel()
        coolTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(VoiceAudioTuning.warmTimeout * 1e9))
            guard !Task.isCancelled else { return }
            VoiceTranscriptLog.log("warm-up timed out with no hold; stopping the mic")
            self?.coolDown()
        }
    }

    /// Session + engine + tap, off the main thread; audio flows into the pipe's ring from the first buffer.
    private func makeWarmTask() -> Task<Bool, Never> {
        let loc = locale
        let cached = analyzerFormat
        return Task { [weak self] in
            var fmt = cached
            if fmt == nil, let loc { fmt = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [Self.makeTranscriber(loc)]) }
            guard let self, let fmt else { return false }
            let pipe = AudioPipe(format: fmt) { [weak self] level in
                DispatchQueue.main.async { MainActor.assumeIsolated { self?.onLevel?(level) } }
            }
            self.sessionActive = true
            do {
                let box = try await Task.detached { () -> EngineBox in
                    try Self.activateSessionOffMain()
                    let engine = AVAudioEngine()
                    try Self.installTap(engine: engine, pipe: pipe)
                    engine.prepare()
                    try engine.start()
                    return EngineBox(engine)
                }.value
                self.engine = box.engine
                self.pipe = pipe
                VoiceTranscriptLog.log("engine running \(Int((CACurrentMediaTime() - self.t0) * 1000)) ms after warm-up/start; analyzer format \(fmt); input format \(box.engine.inputNode.outputFormat(forBus: 0))")
                return true
            } catch {
                VoiceTranscriptLog.log("engine start failed: \(error)")
                self.deactivateSession()
                return false
            }
        }
    }

    private func teardownEngine() {
        coolTask?.cancel(); coolTask = nil
        engine?.inputNode.removeTap(onBus: 0)
        engine?.stop()
        engine = nil
        pipe?.finish()
        pipe = nil
        warmTask = nil
        deactivateSession()
    }

    // MARK: start / stop

    func start(contextualWords: [String]) async throws {
        guard !isRunning, !starting else { throw SpeechInputError.alreadyRunning }
        starting = true
        defer { starting = false }
        coolTask?.cancel(); coolTask = nil
        if availability == .unknown { await prepare(contextualWords: contextualWords) }
        guard availability == .ready, let locale else { throw SpeechInputError.notReady }
        if warmTask == nil { t0 = CACurrentMediaTime(); warmTask = makeWarmTask() }
        let ok = await warmTask?.value ?? false
        guard ok, let pipe, engine != nil else {
            teardownEngine()
            throw SpeechInputError.noFormat
        }

        let transcriber = Self.makeTranscriber(locale)
        let analyzer = SpeechAnalyzer(modules: [transcriber])
        let (stream, continuation) = AsyncStream<AnalyzerInput>.makeStream()
        let started = CACurrentMediaTime()
        collector = Task {
            var acc = TranscriptAccumulator()
            do {
                for try await r in transcriber.results {
                    let text = String(r.text.characters)
                    acc.add(text: text, isFinal: r.isFinal)
                    VoiceTranscriptLog.log("result \(r.isFinal ? "FINAL" : "volatile") at +\(Int((CACurrentMediaTime() - started) * 1000)) ms: \"\(text)\"")
                }
            } catch { VoiceTranscriptLog.log("results stream error: \(error)") }
            let out = acc.result
            VoiceTranscriptLog.log("final transcript: \"\(out)\" (finals \(acc.finals.count), volatile fallback \"\(acc.volatile)\")")
            return out
        }
        // Attach BEFORE the analyzer starts: buffered pre-roll is flushed into the stream and the stream holds it until the analyzer reads.
        let flushed = pipe.attach(continuation)
        VoiceTranscriptLog.log("attached stream; \(flushed) buffers fed before analyzer start (\(pipe.buffersBefore) recorded before attach)")
        do {
            let ctx = AnalysisContext()
            ctx.contextualStrings[.general] = Array(contextualWords.filter { !$0.isEmpty }.prefix(100))
            try? await analyzer.setContext(ctx)
            try await analyzer.start(inputSequence: stream)
            VoiceTranscriptLog.log("analyzer started; \(pipe.buffersAfter) buffers fed since attach")
            self.analyzer = analyzer
            isRunning = true
        } catch {
            VoiceTranscriptLog.log("analyzer start failed: \(error)")
            continuation.finish()
            for await _ in stream {}              // never drop a stream that still holds buffers (that frees them badly)
            await analyzer.cancelAndFinishNow()
            collector?.cancel(); collector = nil
            teardownEngine()
            throw error
        }
    }

    nonisolated private static func installTap(engine: AVAudioEngine, pipe: AudioPipe) throws {
        let input = engine.inputNode
        input.removeTap(onBus: 0)
        let fmt = input.outputFormat(forBus: 0)
        input.installTap(onBus: 0, bufferSize: 2048, format: fmt) { buffer, _ in
            pipe.handle(buffer)
        }
    }

    func stop() async -> String { await finish(postRoll: postRoll) }

    func abort() async { _ = await finish(postRoll: 0) }

    private func finish(postRoll: TimeInterval) async -> String {
        guard isRunning else { return "" }
        if postRoll > 0 { try? await Task.sleep(nanoseconds: UInt64(postRoll * 1e9)) }     // the tail of the last word is still being recorded
        isRunning = false
        let a = analyzer
        analyzer = nil
        let p = pipe
        teardownEngine()                       // removes the tap, stops the engine, ends the stream
        VoiceTranscriptLog.log("stopped; buffers fed after attach \(p?.buffersAfter ?? -1), converter failures \(p?.convertFailures ?? -1)")
        if let a { try? await a.finalizeAndFinishThroughEndOfInput() }
        let text = await collector?.value ?? ""
        collector = nil
        return text
    }

    nonisolated private static func activateSessionOffMain() throws {
        let s = AVAudioSession.sharedInstance()
        try s.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
        try s.setAllowHapticsAndSystemSoundsDuringRecording(true)
        try s.setActive(true)
        Task { @MainActor in AudioHub.shared.micSessionBegan() }       // the audio hub owns the session; it keeps its hands off while the mic is up
    }

    private func deactivateSession() {
        guard sessionActive else { return }
        sessionActive = false
        // the hub puts the shared `.ambient` session back (music and effects keep playing); without a running hub the session is just deactivated
        if !AudioHub.shared.micSessionEnded() { try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation) }
    }
}
