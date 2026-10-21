//
//  VoiceCoordinator.swift
//  Voice v1 glue, owned by GameCare: the training book, the listen-mode state machine and the speech input, plus the queue of reactions that
//  `GameCare.tick` runs on Bob (pattern: `wantHop`). Holds no UI. The press / release entry points are what the HUD mic and the double-tap-hold
//  gesture call; `hear(_:)` is the synchronous end of a listen (tests and the debug script call it directly).
//
//  Listening pose: if he is free he stops, turns to the camera (stepped turn) and wanders no more until release; if he is DOING a trick-able move
//  (the player is teaching it) he keeps doing it. Either way the attention tilt eases 0.06 rad up and one blink marks the open. Restored after.
//  Reactions never show text: they are existing moves (look / slump / hop / sit ...), a blink, a heart bubble, or the need bubble.
//  A voice "come" (known from the start: "come here") is the game's Come here: he walks to the front, then focus / cuddle mode starts
//  (`GameCare.comeHere`); already in focus it is a happy hop. Grumpy never refuses come (decided in VoiceTraining); the reliability roll applies otherwise.
//

import AVFoundation
import Foundation
import Observation
import QuartzCore
import UIKit
import simd

@MainActor
@Observable
final class VoiceCoordinator {
    let training: VoiceTraining
    let mode: VoiceMode
    /// The first-trick tutorial (teach Bob to come); the card reads it.
    let tutorial: VoiceTutorial
    /// He is doing the come move right now (a voice walk, or the few seconds after it started): a word said then is a rep.
    private(set) var comingNow = false
    /// How many learned-word "come" commands were carried out (the tutorial's "Try it" ends on the next one).
    private(set) var comeCommands = 0
    @ObservationIgnored private var comeUntil: Double = 0
    @ObservationIgnored let input: SpeechInput
    /// Mirror of the input's availability (the real input is not observable): the mic button shows a slash / a progress ring from it.
    private(set) var availability: VoiceAvailability = .unknown
    /// Bumped when the mic cannot be used and the trick book should open instead.
    private(set) var bookRequest = 0
    /// How many listens have opened (the HUD's accessibility value; UI tests read it).
    private(set) var openCount = 0
    /// How many times the edge glow was drawn (the HUD's accessibility value; UI tests read it, since a press blocks the test while it holds).
    private(set) var glowShown = 0
    /// Touch-down -> glow drawn, in ms (nil until the first glow of a listen); the HUD exposes it and the UI test budgets it.
    private(set) var glowLatencyMs: Int?
    private(set) var audioLatencyMs: Int?
    @ObservationIgnored private var downAt: Double = 0
    /// Wakes the graphics idle-rest governor (set by the stage; `begin()` calls it).
    @ObservationIgnored var wake: (() -> Void)?
    @ObservationIgnored private var levelMin: Float = 1
    @ObservationIgnored private var levelMax: Float = 0
    @ObservationIgnored private var levelCount = 0
    @ObservationIgnored private var offMain = 0
    static var logging: Bool { UserDefaults.standard.bool(forKey: "VoiceLog") }
    func glowAppeared() {
        glowShown += 1
        if glowLatencyMs == nil, downAt > 0 {
            let ms = Int((CACurrentMediaTime() - downAt) * 1000)
            glowLatencyMs = ms
            if Self.logging { NSLog("[voice] open latency: touch-down -> glow visible %d ms", ms) }
        }
    }
    /// Smoothed live level 0...1 (the mic halo, the bars, the glow and Bob's nod read it).
    var level: Float { mode.glowLevel }
    /// Call early (app start): if the mic is already permitted, check assets and warm the recogniser so the first press starts fast.
    func prewarm() {
        guard availability == .unknown, input is DictationSpeechInput,
              AVAudioApplication.shared.recordPermission == .granted else { return }
        Task { [weak self] in
            guard let self else { return }
            await self.input.prepare(contextualWords: [])
            self.availability = self.input.availability
        }
    }
    @ObservationIgnored private var nod: Float = 0

    @ObservationIgnored weak var care: GameCare?
    @ObservationIgnored private let clock: () -> Double

    /// The flip never needs the player: untrained (a teaching rep) he faceplants about 1 time in `flipFailOneIn`, never on the first try and
    /// never twice in a row. `flipRoll` is uniform 0..<1 (tests inject it). `flipFailQueued` = a learned flip missed its reliability roll and
    /// is queued as a faceplant instead of the generic miss.
    static let flipFailChance = 1.0 / 3.0
    @ObservationIgnored var flipRoll: () -> Double = { Double.random(in: 0..<1) }
    @ObservationIgnored private(set) var flipTries = 0
    @ObservationIgnored private(set) var lastFlipFailed = false
    @ObservationIgnored private var flipFailQueued = false
    @ObservationIgnored private var seenFaceplants = 0
    /// Who each "goodnight" meant (tests).
    @ObservationIgnored private(set) var goodnightLog: [[Int]] = []
    @ObservationIgnored private var queue: [(r: VoiceReaction, kind: VoiceFeedback.Kind?, ids: [Int], target: VoiceTarget)] = []
    // MARK: multi-Jelly hooks (phase B wires these; the lab has one real Jelly, Bob = id 0)
    /// The on-device language model fallback (nil = none: the deterministic result stands).
    @ObservationIgnored let intentModel: VoiceIntentModel?
    /// The Jelly ids in the room (default: the selection model's blobs).
    @ObservationIgnored var jellyIDs: (() -> [Int])?
    /// A Jelly was NAMED: select it (default: `care.rosterPick(id)`, the same outline highlight a tap gives).
    @ObservationIgnored var onSelect: ((Int) -> Void)?
    /// "Everyone ...": called with all ids before the action runs.
    @ObservationIgnored var onEveryone: (([Int]) -> Void)?
    /// Come here for these ids (default: Bob comes if id 0 is in the list; the close-up frames all in phase B).
    @ObservationIgnored var onComeHere: (([Int]) -> Void)?
    /// stopFighting: stop any interaction and step them apart (Bob alone: just a stop plus a sheepish look).
    @ObservationIgnored var onStopFighting: (([Int]) -> Void)?
    /// A reaction for Jellies other than Bob (ids != 0); Bob's own part still runs here.
    @ObservationIgnored var onRemote: ((VoiceReaction, [Int]) -> Void)?
    /// "Goodnight": the Jellies (ids) that go to bed now (the stage sets `commandedGoodnight` on their brains).
    @ObservationIgnored var onGoodnight: (([Int]) -> Void)?
    /// The language-model request in flight (tests await it).
    private(set) var intentTask: Task<Void, Never>?
    /// How the last utterance was understood: "det", "model", "timeout", "error", "unavailable" and the ms it took.
    private(set) var lastParse: (path: String, ms: Int)?
    /// The nickname being taught by voice (3 listens), nil when none.
    private(set) var nickLesson: NickLesson?
    struct NickLesson: Equatable { var id: Int; var word = ""; var reps = 0; var sessions: [Int] = [] }
    @ObservationIgnored private var currentIDs: [Int] = []
    @ObservationIgnored private var session = 0
    @ObservationIgnored private var runningAtOpen: VoiceTrick?
    @ObservationIgnored private weak var brainRef: BlobBrain?
    @ObservationIgnored private var startTask: Task<Void, Never>?
    @ObservationIgnored private var stopping = false
    /// Capture / test aid: this text is "heard" on release instead of the input's.
    @ObservationIgnored var debugTranscript: String?

    // pose
    @ObservationIgnored private var poseDue = false
    @ObservationIgnored private var lift: Float = 0            // eased attention tilt added while listening (rad)
    @ObservationIgnored private var basePitch: Float = 0
    @ObservationIgnored private var faceLocked = false         // the listening turn was started: keep him from wandering off

    // follow-ups
    @ObservationIgnored private var pendingHop = false
    @ObservationIgnored private var hopWait: Float = 0
    @ObservationIgnored private var hopStarted = false
    @ObservationIgnored private var walkAfterHop = false
    /// The name moment: hop (commanded, at once), then the walk, the turn, and `nameHold` seconds of attention.
    @ObservationIgnored private var nameHop = false
    @ObservationIgnored private var nameTurning = false
    @ObservationIgnored private var nameHopSeen = false
    @ObservationIgnored private var nameWalking = false
    @ObservationIgnored private var holdLeft: Float = 0
    /// A voice walk (come / toward the camera) is under way; its finish turns him to the camera.
    @ObservationIgnored private(set) var voiceGoing = false
    @ObservationIgnored private var goAge: Float = 0
    @ObservationIgnored private var turnDue = false
    @ObservationIgnored private var seenTakeoffs = 0
    @ObservationIgnored private var seenLandings = 0

    // MARK: feedback (the player sees that he heard, understood and is learning)

    /// What was heard, as a pill above the mic (`VoiceFeedbackView`).
    private(set) var heard: VoiceHeard?
    /// His understanding, as a small bubble beside his head.
    private(set) var feedback: VoiceFeedback?
    /// "Learned “word” -> Trick" toast.
    private(set) var toast: VoiceToast?
    /// "Now hold the mic and say a word for <Trick>" while a trick-book move runs.
    private(set) var teachPrompt: TeachPrompt?
    /// Every feedback event in order (tests read it; capped).
    private(set) var feedbackLog: [VoiceFeedback.Kind] = []
    @ObservationIgnored private var heardSeq = 0
    @ObservationIgnored private var feedbackSeq = 0
    @ObservationIgnored private var perkLeft: Float = 0
    static let promptTime: Double = 8
    func now() -> Double { clock() }

    private func emitFeedback(_ r: VoiceReaction, override: VoiceFeedback.Kind?) {
        let kind: VoiceFeedback.Kind?
        if let o = override { kind = o == .silent ? nil : o }          // .silent: a demonstration (trick-book row), not a command
        else {
            switch r {
            case .learnedStep(let t, let n): kind = .rep(t, reps: n)
            case .trickLearned(let t): kind = .learned(t, word: training.word(for: t) ?? "")
            case .perform(let t): kind = .obeyed(t)
            case .wrongTrick(let said, _): kind = .missed(said, pct: Int((training.reliability(said) * 100).rounded()))
            case .puzzled, .ignore: kind = .unknown
            case .grumpyIgnore: kind = .grumpy
            case .nicknameStep(let n): kind = .nameRep(n)
            case .nicknameLearned: kind = .nameLearned
            case .social(let s): kind = .social(s)
            case .nameHeard: kind = nil
            }
        }
        guard let kind else { return }
        feedbackSeq += 1
        feedback = VoiceFeedback(id: feedbackSeq, kind: kind, born: clock())
        feedbackLog.append(kind); if feedbackLog.count > 60 { feedbackLog.removeFirst() }
        switch kind {
        case .rep, .nameRep, .nameLearned: perkLeft = 0.6
        case .learned(let t, let w): perkLeft = 0.6; toast = VoiceToast(id: feedbackSeq, text: "Learned \u{201C}\(w)\u{201D} \u{2192} \(t.title)", born: clock())
        default: break
        }
    }

    static let tiltLift: Float = 0.06                          // 0.28 -> 0.34 with the game's default tilt
    static let tiltTime: Float = 0.25
    /// Extra attention tilt at full speech level (rad): a very small lean-in.
    static let nodMax: Float = 0.035
    /// "Come" stops here (a little in front of the focus call spot, so it can never be mistaken for the Come here approach).
    static let comeSpot = SIMD2<Float>(0, GameCamera.callSpot.y - 0.4)
    /// The name makes him walk this far toward the camera.
    static let nameWalk: Float = 1.5
    /// ... and then keeps his attention on the camera this long.
    static let nameHold: Float = 2.0
    /// After a come starts it counts as "doing the move" for this long (seconds), even when he was already at the spot.
    static let comeWindow: Double = 4

    nonisolated deinit {}

    init(training: VoiceTraining? = nil, input: SpeechInput? = nil, tutorial: VoiceTutorial? = nil, intentModel: VoiceIntentModel? = nil,
         now: @escaping () -> Double = { Date.timeIntervalSinceReferenceDate }) {
        // The real model only in the shipped app (not in unit tests, which pass a fake or nothing; `-VoiceNoModel 1` turns it off).
        self.intentModel = intentModel ?? (NSClassFromString("XCTestCase") == nil && !UserDefaults.standard.bool(forKey: "VoiceNoModel") ? VoiceIntentModels.make() : nil)
        self.training = training ?? VoiceTraining()
        self.tutorial = tutorial ?? VoiceTutorial()
        self.clock = now
        self.mode = VoiceMode(now: now)
        self.input = input ?? SpeechInputFactory.make()
        availability = self.input.availability
        mode.onSend = { [weak self] text in self?.process(text) }
        self.tutorial.voice = self
    }

    // MARK: listening

    var isListening: Bool { mode.isListening }
    /// True when the mic is known to be unusable (slashed mic; it opens the trick book).
    var micUnusable: Bool {
        switch availability { case .unavailable, .denied: return true; default: return false }
    }

    /// Speculative mic start (first tap of a double-tap on empty space, mic-button touch-down). Cheap, off the main thread, cancels itself.
    func warmUp() {
        guard mode.phase == .idle, !stopping, !micUnusable else { return }
        input.warmUp()
    }

    /// Press (button down / second tap down). False = nothing opened (busy, or the mic is unusable and the book was requested instead).
    @discardableResult
    func begin() -> Bool {
        guard mode.phase == .idle, !stopping else { return false }
        wake?()                                    // leave the 30 fps idle rest now (the mic button does not pass through the Metal view's touches)
        if micUnusable { bookRequest += 1; return false }
        downAt = CACurrentMediaTime()
        session = training.newSession()
        glowLatencyMs = nil; audioLatencyMs = nil
        levelMin = 1; levelMax = 0; levelCount = 0; offMain = 0
        Ears.shared.voicePause()                       // Ears lets go of the input before the voice engine takes the session
        input.warmUp()
        intentModel?.prewarm()                         // the first request must not pay the model load
        guard mode.begin() else { return false }       // phase = .listening: the glow / pressed state read it on the very next view update
        if Self.logging { NSLog("[voice] begin() ran synchronously in %d ms (glow state set)", Int((CACurrentMediaTime() - downAt) * 1000)) }
        openCount += 1
        runningAtOpen = brainRef.flatMap(Self.running)
        poseDue = true
        input.onLevel = { [weak self] l in
            guard let self else { return }
            if !Thread.isMainThread { self.offMain += 1 }
            self.levelCount += 1; self.levelMin = min(self.levelMin, l); self.levelMax = max(self.levelMax, l)
            self.mode.levelUpdate(l)
        }
        let words = training.contextualWords
        let t0 = downAt
        startTask = Task { [weak self] in
            guard let self else { return }
            // Everything slow runs behind the UI: let the glow / pressed state / tick commit first (audio before the engine is up is dropped).
            try? await Task.sleep(nanoseconds: 16_000_000)
            let watcher = Task { @MainActor [weak self] in            // a first-use download shows its progress on the mic
                while !Task.isCancelled {
                    self?.availability = self?.input.availability ?? .unknown
                    try? await Task.sleep(nanoseconds: 200_000_000)
                }
            }
            defer { watcher.cancel() }
            do {
                try await self.input.start(contextualWords: words); self.availability = self.input.availability
                let ms = Int((CACurrentMediaTime() - t0) * 1000)
                self.audioLatencyMs = ms
                if Self.logging { NSLog("[voice] open latency: touch-down -> glow visible %d ms, -> audio running %d ms", self.glowLatencyMs ?? -1, ms) }
            }
            catch {
                self.availability = self.input.availability
                if self.mode.isListening { self.mode.cancel() }
                if self.micUnusable { self.bookRequest += 1 }
            }
        }
        return true
    }

    /// Release (button up / finger lifted). A hold under 0.25 s is a cancel; otherwise the transcript is collected and `hear` runs.
    func release() {
        guard mode.isListening else { return }
        if Self.logging {
            NSLog("[voice] level range min %.3f max %.3f over %d updates (off-main %d)", levelCount > 0 ? levelMin : -1, levelMax, levelCount, offMain)
        }
        let st = startTask
        // The glow / pressed state end on THIS call: the transcript (analyzer finalise) can take a second, the UI never waits for it.
        let long = mode.endHold()
        if !long {
            Task { [input] in await st?.value; await input.abort() }
            return
        }
        stopping = true
        Task { [weak self] in
            await st?.value
            guard let self else { return }
            let text = await self.input.stop()
            self.stopping = false
            let said = self.debugTranscript ?? text
            self.debugTranscript = nil
            self.hear(said)
        }
    }

    /// The end of a listen: the mode sends it (or cancels a short hold) and the reaction is queued.
    func hear(_ transcript: String) {
        if mode.phase == .processing { mode.send(transcript) } else { mode.end(transcript: transcript) }
    }

    /// Abort (backgrounded): nothing is sent.
    func cancel() {
        let st = startTask
        if mode.phase != .idle { mode.cancel(); mode.finish(); Task { [input] in await st?.value; await input.abort() } }
    }

    private func enqueue(_ r: VoiceReaction, _ kind: VoiceFeedback.Kind?, ids: [Int] = [], target: VoiceTarget = .selected) { queue.append((r, kind, ids, target)) }

    /// The Jelly ids in the room.
    var presentIDs: [Int] { jellyIDs?() ?? care?.jellies.map(\.id) ?? [0] }
    /// The selected Jelly (Bob by default).
    var selectedJellyID: Int { care?.targetJelly ?? 0 }
    /// Who a target means right now.
    func ids(for t: VoiceTarget) -> [Int] {
        switch t {
        case .selected: return [selectedJellyID]
        case .jelly(let id): return [id]
        case .everyone: return presentIDs
        }
    }

    private func process(_ transcript: String) {
        defer { mode.finish() }
        guard let care else { return }
        // a meal / tray owns him: commands are ignored and nothing is learned
        if care.trayOut { enqueue(.ignore, nil); return }
        if Self.logging { NSLog("[voice] process transcript=\"%@\" tokens=%@", transcript, VoiceMatcher.tokens(transcript).joined(separator: ",")) }
        let trimmed = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        heardSeq += 1
        heard = VoiceHeard(id: heardSeq, text: trimmed.isEmpty ? "\u{2026}" : "\u{201C}\(trimmed)\u{201D}", born: clock())
        teachPrompt = nil
        if nickLesson != nil { nicknameListen(transcript); return }
        let t0 = CACurrentMediaTime()
        let d = training.decideFull(transcript: transcript, runningMove: runningAtOpen, mood: moodMeant(by: transcript), session: session)
        if d.noMatch, !VoiceMatcher.tokens(transcript).isEmpty, let model = intentModel {
            guard model.availability.isAvailable else {
                recordParse("unavailable", t0, transcript); finish(d, transcript: transcript); return
            }
            askModel(model, transcript: transcript, deterministic: d, t0: t0)
            return
        }
        recordParse("det", t0, transcript)
        finish(d, transcript: transcript)
    }

    /// The mood of the Jelly a transcript is aimed at (a name in it), else of the targeted one: a grumpy Jelly is the one who refuses (but always comes).
    private func moodMeant(by transcript: String) -> BlobMood {
        guard let care else { return .happy }
        if let id = training.names.resolve(tokens: VoiceMatcher.tokens(transcript)).first?.id { return care.needs(for: id).mood }
        return care.needs(for: care.targetJelly).mood
    }

    private func recordParse(_ path: String, _ t0: Double, _ transcript: String) {
        let ms = Int((CACurrentMediaTime() - t0) * 1000)
        lastParse = (path, ms)
        if Self.logging { NSLog("VOICELOG parse path=%@ ms=%d text=\"%@\"", path, ms, transcript) }
    }

    /// (b) the model fallback: free phrasing -> a structured intent, within `modelBudget` seconds. Never produces text for the player.
    private func askModel(_ model: VoiceIntentModel, transcript: String, deterministic d: VoiceDecision, t0: Double) {
        let learned = training.learnedTricks.filter { $0 != .come }
        let names = JellyNameRoster.all.map(\.display)
        intentTask = Task { @MainActor [weak self] in
            var path = "model"
            var intent: ModelIntent?
            do {
                intent = try await Self.withBudget(VoiceTuning.modelBudget) { try await model.interpret(transcript, learned: learned, names: names) }
            } catch VoiceModelError.timedOut { path = "timeout" } catch { path = "error" }
            guard let self, let care = self.care else { return }
            self.recordParse(path, t0, transcript)
            var decision = d
            if let i = intent, i.confidence >= VoiceTuning.modelMinConfidence, i.action != .none {
                var target = d.target
                if target == .selected {
                    switch i.targetKind {
                    case .everyone: target = .everyone
                    case .named: if let h = self.training.names.match(token: i.targetName) { target = .jelly(h.id) }
                    case .selected: break
                    }
                }
                decision = self.training.decide(model: i.action, target: target, mood: { if case .jelly(let id) = target { return care.needs(for: id).mood }; return care.needs(for: care.targetJelly).mood }())
            }
            self.finish(decision, transcript: transcript)
        }
    }

    nonisolated static func withBudget<T: Sendable>(_ seconds: Double, _ op: @escaping @MainActor @Sendable () async throws -> T) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { g in
            g.addTask { try await op() }
            g.addTask { try await Task.sleep(nanoseconds: UInt64(seconds * 1e9)); throw VoiceModelError.timedOut }
            defer { g.cancelAll() }
            return try await g.next()!
        }
    }

    /// A decision becomes feedback + a queued reaction (with who it is for), and a named Jelly is selected.
    private func finish(_ d: VoiceDecision, transcript: String) {
        guard let care else { return }
        var r = d.reaction
        if r == .perform(.come) { comeCommands += 1 }
        var ids = ids(for: d.target)
        if case .jelly(let id) = d.target, !presentIDs.contains(id) { r = .puzzled; ids = [] }        // a name for a Jelly that is not here
        var kind: VoiceFeedback.Kind?
        switch r {
        case .ignore:
            if VoiceMatcher.tokens(transcript).isEmpty { kind = .nothing }
            else if let m = training.lastMiss { kind = .missed(m, pct: Int((training.reliability(m) * 100).rounded())) }
            else { kind = .unknown }
        case .wrongTrick(let said, _): kind = .missed(said, pct: Int((training.reliability(said) * 100).rounded()))
        default: break
        }
        // naming a Jelly selects it (the outline a tap gives); come already zooms onto him, and the close-up needs no highlight
        if case .jelly(let id) = d.target, presentIDs.contains(id), !care.focus.isActive, r != .perform(.come) {
            if let f = onSelect { f(id) } else { care.rosterPick(id, quietHop: true) }
        }
        if d.target == .everyone { onEveryone?(ids) }
        if r == .ignore, training.lastMiss == .flip, flipRoll() < 0.5 {            // he knew it but missed: sometimes it is a faceplant
            flipFailQueued = true
            enqueue(.perform(.flip), kind, ids: ids); return
        }
        enqueue(r, kind, ids: ids, target: d.target)
    }

    // MARK: nicknames (taught by voice: say it 3 times while he is selected)

    /// The trick book's "Say it" button: the next listens teach a nickname for Jelly `id`.
    func startNicknameLesson(for id: Int) { nickLesson = NickLesson(id: id) }
    func cancelNicknameLesson() { nickLesson = nil }

    private func nicknameListen(_ transcript: String) {
        guard var l = nickLesson else { return }
        let toks = VoiceMatcher.tokens(transcript)
        let word = toks.prefix(2).joined(separator: " ")
        guard !toks.isEmpty else { enqueue(.ignore, .nothing); return }
        if let h = training.names.match(token: toks[0]), h.score >= 0.8 || training.names.nicknames(for: h.id).contains(toks[0]) {
            enqueue(.ignore, .unknown); return                                   // that is already a name
        }
        let same = !l.word.isEmpty && (word == l.word || (word.count >= 4 && VoiceMatcher.levenshtein(word, l.word) <= 1)
                                       || (word.count >= 4 && !word.contains(" ") && !l.word.contains(" ") && VoiceMatcher.soundex(word) == VoiceMatcher.soundex(l.word)))
        if !same { l.word = word; l.reps = 0; l.sessions = [] }
        guard !l.sessions.contains(session) else { nickLesson = l; return }       // one rep per listen
        l.reps += 1; l.sessions.append(session)
        if l.reps >= VoiceTuning.nicknameReps {
            if training.names.addNickname(l.word, for: l.id) { enqueue(.nicknameLearned, nil, ids: [l.id]) } else { enqueue(.ignore, .unknown) }
            nickLesson = nil
        } else {
            nickLesson = l
            enqueue(.nicknameStep(reps: l.reps), nil, ids: [l.id])
        }
    }

    /// Debug / capture: a listen that "hears" `words` after `hold` seconds. `teach` starts that trick first and waits a second.
    func simulate(_ words: String, teach: VoiceTrick? = nil, hold: Double = 1.2) async {
        if let t = teach {
            enqueue(.perform(t), .silent)
            try? await Task.sleep(nanoseconds: 1_000_000_000)
        }
        guard begin() else { return }
        try? await Task.sleep(nanoseconds: UInt64(hold * 1e9))
        debugTranscript = words
        release()
    }

    /// Debug / capture (`-VoiceLearned 1`): his name and every trick count as learned with their suggestion words.
    func debugLearnAll() {
                for t in VoiceTrick.allCases where training.unlocked(t) { training.debugLearn(t, word: t.suggestion, reliability: 0.95) }
        tutorial.finish()
    }

    /// The trick book row: do the trick now (so the next said word binds to it).
    func show(_ t: VoiceTrick) {
        enqueue(.perform(t), .silent)
        if !training.isLearned(t) { teachPrompt = TeachPrompt(trick: t, until: clock() + Self.promptTime) }
    }

    // MARK: mapping

    static func trick(for kind: IdleKind?) -> VoiceTrick? {
        switch kind {
        case .sit: return .sit
        case .jacks: return .jacks
        case .run, .stumble: return .run
        case .look: return .look
        case .tail: return .spin
        case .bounce: return .hop
        case .roll: return .roll
        default: return nil
        }
    }
    static func idleKind(for t: VoiceTrick) -> IdleKind? {
        switch t {
        case .sit: return .sit
        case .jacks: return .jacks
        case .run: return .run
        case .look: return .look
        case .spin: return .tail
        case .hop: return .bounce
        case .roll: return .roll
        case .flip, .come: return nil
        }
    }
    /// The trick-able move he is doing right now (nil = none).
    private static func running(_ b: BlobBrain) -> VoiceTrick? {
        if case .flipPlay = b.script { return .flip }
        if !b.idleState.yielding, let t = trick(for: b.idleState.kind) { return t }
        return nil
    }
    private func runningNow(_ b: BlobBrain) -> VoiceTrick? { Self.running(b) ?? (voiceGoing || clock() < comeUntil ? .come : nil) }
    /// A listen opened while he was coming (the tutorial keeps saying "hold the mic" through a long hold).
    var listeningToCome: Bool { mode.isListening && runningAtOpen == .come }

    // MARK: tick (GameCare.tick)

    func tick(care: GameCare, brain: BlobBrain, sim: SoftBody?, dt: Float) {
        brainRef = brain
        let coming = voiceGoing || clock() < comeUntil
        if coming != comingNow { comingNow = coming }
        tutorial.update()
        if voiceGoing { goAge += dt; if goAge > 15 { voiceGoing = false } }      // a cancelled walk (he was grabbed) never reports back
        if mode.phase == .idle { runningAtOpen = nil }

        // listening pose
        let listening = mode.isListening
        if poseDue, listening {
            poseDue = false
            runningAtOpen = runningNow(brain)
            brain.blinkRequested = true
            let act = brain.activity
            let free = act == .idle || act == .walking || act == .lookingAround || act == .steppingInPlace || act == .turning
            if let sim, free, runningAtOpen == nil, brain.idleState.kind == nil || brain.idleState.kind == .slump,
               !care.focus.isActive, !care.trayOut, !(care.touchPlay?.holdsBrain ?? false) {
                brain.startTurn(to: brain.faceCameraYaw(), sim: sim)
                faceLocked = true
            }
        } else if poseDue { poseDue = false }
        if listening { brain.restTimer = max(brain.restTimer, 1) }               // no new wander while he listens
        if !listening { faceLocked = false }
        let target: Float = (listening || holdLeft > 0 || nameTurning) ? Self.tiltLift : 0
        if lift == 0 && target > 0 { basePitch = brain.attentionPitch }
        if lift != target {
            lift += max(-Self.tiltLift / Self.tiltTime * dt, min(Self.tiltLift / Self.tiltTime * dt, target - lift))
            if abs(lift - target) < 1e-4 { lift = target }
            brain.attentionPitch = (lift == 0 ? basePitch : basePitch + lift) + nod
        }
        // tiny nod on speech bursts: a small extra tilt (body only) eased toward the live level while he listens
        if perkLeft > 0 { perkLeft = max(0, perkLeft - dt) }
        let nodTarget: Float = listening ? Self.nodMax * max(0, min(1, (mode.glowLevel - 0.25) / 0.6)) : (perkLeft > 0 ? Self.nodMax * 1.6 : 0)
        if nod != nodTarget {
            let step = Self.nodMax / 0.12 * dt
            let new = nod + max(-step, min(step, nodTarget - nod))
            brain.attentionPitch += new - nod
            nod = abs(new) < 1e-5 && nodTarget == 0 ? 0 : new
        }

        if let tp = care.touchPlay { tp.pruneHearts(now: CACurrentMediaTime()) }
        flipFeedbackTick(care: care, brain: brain)
        // flip haptics (the driver is warm only in focus mode, so roaming is silent): a light tick at take-off, a strong soft thump on landing
        if brain.flipTakeoffs != seenTakeoffs || brain.flipLandings != seenLandings {
            let now = CACurrentMediaTime()
            if brain.flipTakeoffs != seenTakeoffs { care.touchPlay?.haptics.transient(now: now, intensity: 0.35, sharpness: 0.45) }
            if brain.flipLandings != seenLandings { care.touchPlay?.haptics.transient(now: now, intensity: 0.95, sharpness: 0.15) }
            seenTakeoffs = brain.flipTakeoffs; seenLandings = brain.flipLandings
        }
        guard let sim else { return }

        // the name moment: hop now, walk toward the camera, turn, hold attention
        if nameHop {
            hopWait += dt
            if case .hopPlay = brain.script { nameHopSeen = true }
            else if nameHopSeen || hopWait > 1.5 {
                let landed = nameHopSeen
                nameHop = false; nameHopSeen = false; hopWait = 0
                brain.nameHopDone()
                if landed {
                    brain.blinkRequested = true                  // the happy blink at landing
                    if walkAfterHop { walkAfterHop = false; nameWalking = true; if !walkToward(brain, sim: sim) { nameWalking = false; beginHold(brain, sim: sim) } }
                }
                walkAfterHop = false
            }
        }
        // follow-ups of a voice hop / a voice walk
        if pendingHop {
            if case .none = brain.script, brain.idleState.kind == nil, brain.activity != .touched {
                pendingHop = false; hopWait = 0
                brain.startHopPlay(sim: sim, distance: 0.0001)
                hopStarted = true
            } else {
                hopWait += dt
                if Self.running(brain) == nil { brain.interruptScript = true }       // feedback never cuts a flip / a trick being taught: the hop waits (or is dropped)
                brain.restTimer = max(brain.restTimer, 1)
                if hopWait > 2 { pendingHop = false; hopWait = 0; walkAfterHop = false }
            }
        } else if hopStarted, !nameHop, case .none = brain.script {
            hopStarted = false
            if walkAfterHop { walkAfterHop = false; walkToward(brain, sim: sim) }
        }
        if turnDue {
            turnDue = false
            if voiceGoing {
                voiceGoing = false
                if !care.focus.isActive {
                    if nameWalking { nameWalking = false; beginHold(brain, sim: sim) }
                    else { brain.startTurn(to: brain.faceCameraYaw(), sim: sim) }
                }
            }
        }
        if nameTurning, case .none = brain.script, brain.activity != .turning { nameTurning = false; holdLeft = Self.nameHold }
        if holdLeft > 0 {
            // attention: no wander, no idle behaviour, eyes (the whole body) on the camera
            holdLeft -= dt
            brain.restTimer = max(brain.restTimer, 1)
            brain.idleState.cooldown = max(brain.idleState.cooldown, 3)
            if care.focus.isActive || brain.activity == .touched { holdLeft = 0 }
        }

        // one reaction at a time, once the hold is over
        if !listening, !queue.isEmpty { let q = queue.removeFirst(); run(q.r, kind: q.kind, ids: q.ids, target: q.target, care: care, brain: brain) }
    }

    // MARK: flip

    private func flipFeedbackTick(care: GameCare, brain: BlobBrain) {
        if brain.flipFaceplants != seenFaceplants {
            seenFaceplants = brain.flipFaceplants
            if care.focus.isActive { care.touchPlay?.haptics.transient(now: CACurrentMediaTime(), intensity: 0.9, sharpness: 0.05) }     // dull thud
            else { UIImpactFeedbackGenerator(style: .heavy).impactOccurred(intensity: 0.8) }
        }
    }

    /// Does this flip faceplant? A queued reliability miss always does; while the word is not learned about 1 in 3, never the first try, never twice running.
    private func rollFlipFail() -> Bool {
        let fail: Bool
        if flipFailQueued { fail = true }
        else if training.isLearned(.flip) { fail = false }
        else { fail = flipTries > 0 && !lastFlipFailed && flipRoll() < Self.flipFailChance }
        flipFailQueued = false
        flipTries += 1; lastFlipFailed = fail
        return fail
    }

    /// `GameCare` reports a finished `.goTo`: ours turns him to the camera.
    func goFinished() { if voiceGoing { turnDue = true } }

    /// Starts the walk toward the camera; false = he is already (nearly) at the front, nothing to walk.
    @discardableResult
    private func walkToward(_ brain: BlobBrain, sim: SoftBody) -> Bool {
        let here = GameCare.floorPos(brain, sim)
        let d = brain.cameraPosXZ - here
        let len = simd_length(d)
        guard len > 0.01 else { return false }
        var goal = here + d / len * Self.nameWalk
        goal.y = min(goal.y, GameCamera.callSpot.y + 0.4)            // never off the front of the floor
        guard simd_length(goal - here) > 0.3 else { return false }
        startWalk(to: goal, brain)
        return true
    }
    /// The stepped turn to the camera; the hold of attention starts when it is over.
    private func beginHold(_ brain: BlobBrain, sim: SoftBody) {
        brain.startTurn(to: brain.faceCameraYaw(), sim: sim)
        nameTurning = true
    }
    private func startWalk(to goal: SIMD2<Float>, _ brain: BlobBrain) {
        voiceGoing = true; goAge = 0; turnDue = false
        brain.requestNow(.goTo(goal))
    }

    // MARK: reactions

    private func run(_ r: VoiceReaction, kind: VoiceFeedback.Kind?, ids: [Int] = [], target: VoiceTarget = .selected, care: GameCare, brain: BlobBrain) {
        if UserDefaults.standard.bool(forKey: "VoiceLog") { NSLog("VOICELOG reaction=%@ mood=%@ ids=%@", String(describing: r), String(describing: care.needs.mood), ids.description) }   // capture aid
        if care.trayOut { return }                                   // a meal owns him
        if r == .social(.goodnight), care.raceBusy { return }        // no bedtime during a race trip (or the roll up before it)
        let focused = care.focus.isActive
        if focused, care.focus.phase == .approaching { return }
        if r == .social(.goodnight) {            // a group command like come-here-everyone: every awake Jelly (or the one meant) goes to bed
            emitFeedback(r, override: kind)
            let meant: [Int]
            switch target {
            case .everyone: meant = presentIDs
            case .jelly(let id): meant = [id]
            case .selected: meant = (focused || care.select.selectedID != nil) ? [care.targetJelly] : presentIDs
            }
            goodnightLog.append(meant); if goodnightLog.count > 20 { goodnightLog.removeFirst() }
            if let f = onGoodnight { f(meant) } else { brain.commandedGoodnight = true }
            return
        }
        if r == .perform(.come), !focused, onComeHere == nil, care.jellyCount > 1 {      // come goes to the close-up of the Jelly meant (GameCare+Focus)
            emitFeedback(r, override: kind)
            comeUntil = clock() + Self.comeWindow
            switch target {
            case .jelly(let id): care.comeHere(jelly: id)
            case .selected: care.comeHere(jelly: nil)                 // = care.targetJelly
            case .everyone: care.comeHereEveryone()
            }
            return
        }
        let others = ids.filter { $0 != 0 }
        if !others.isEmpty { onRemote?(r, others) }
        if !ids.isEmpty, !ids.contains(0) { emitFeedback(r, override: kind); return }      // only other Jellies were meant: Bob does nothing
        currentIDs = ids.isEmpty ? [0] : ids
        let trickRunning = Self.running(brain) != nil
        emitFeedback(r, override: kind)
        switch r {
        case .perform(let t), .wrongTrick(_, let t):
            doTrick(t, care: care, brain: brain, focused: focused)
        case .learnedStep, .nicknameStep:
            brain.blinkRequested = true                              // a nod: he noticed (plus the small ear-perk tilt, see `perkLeft`)
        case .trickLearned:
            brain.blinkRequested = true
            care.touchPlay?.spawnHeart(now: CACurrentMediaTime())
            if !care.focus.isActive { pendingHop = true; hopWait = 0; walkAfterHop = false }      // the happy hop at the lesson's end
        case .puzzled, .ignore:
            if !trickRunning { brain.commandedIdle = .look }         // the tilt / shrug: look away briefly and back
        case .grumpyIgnore:
            if !trickRunning { brain.commandedIdle = .slump }
            care.showNeedBubble()
        case .nameHeard, .nicknameLearned:
            nameHop = true; nameHopSeen = false; hopWait = 0; walkAfterHop = !focused
            brain.commandedNameHop = true
        case .social(let s):
            doSocial(s, care: care, brain: brain, focused: focused, trickRunning: trickRunning)
        }
    }

    /// Stops what he is doing: walks, runs, hops and idle moves end (a flip in the air is allowed to land first), pending follow-ups are dropped.
    func stopNow(brain: BlobBrain) {
        voiceGoing = false; pendingHop = false; walkAfterHop = false; hopWait = 0; comeUntil = 0
        nameHop = false; nameTurning = false; nameWalking = false; holdLeft = 0
        guard Self.running(brain) != .flip else { return }
        brain.interruptScript = true
        brain.commandedIdle = nil
        if brain.idleState.kind != nil, !brain.idleState.yielding { brain.idleState.yielding = true; brain.idleState.yieldT = 0 }
    }

    private func doSocial(_ s: VoiceSocial, care: GameCare, brain: BlobBrain, focused: Bool, trickRunning: Bool) {
        switch s {
        case .stop:
            stopNow(brain: brain)
            brain.stop()                                             // and any social he is in ends
        case .stopFighting:
            stopNow(brain: brain)
            onStopFighting?(currentIDs)                              // phase C: stop any interaction and step the Jellies apart
            if Self.running(brain) == nil { brain.commandedIdle = .look }      // alone he is just sheepish: a look away and back
        case .praise:
            care.needs.gain(.attention, VoiceTuning.praiseAttention)  // a small attention boost
            care.touchPlay?.spawnHeart(now: CACurrentMediaTime())
            brain.blinkRequested = true
            if !focused { pendingHop = true; hopWait = 0; walkAfterHop = false }     // the happy hop
        case .scold:
            if !trickRunning { brain.commandedIdle = .slump }        // the droop
        case .play:
            care.touchPlay?.spawnHeart(now: CACurrentMediaTime())
            if !focused { pendingHop = true; hopWait = 0; walkAfterHop = false }
        case .goodnight:
            break                                                    // (handled before: a group command)
        }
    }

    private func doTrick(_ t: VoiceTrick, care: GameCare, brain: BlobBrain, focused: Bool) {
        switch t {
        case .come:
            comeUntil = clock() + Self.comeWindow
            if focused { pendingHop = true; hopWait = 0; walkAfterHop = false; return }       // already in the close-up: a happy hop
            if let f = onComeHere { f(currentIDs) }                  // phase B: every Jelly in the list comes, the close-up frames them all
            else { care.comeHere(jelly: currentIDs.first ?? 0) }             // the same call as tapping him: he walks to the front, then the camera zooms into cuddle mode
                                                 // (a grumpy Bob comes too: his grumpy walk is already slow and small, and the close-up petting cheers him up)
        case .run where focused:
            pendingHop = true; hopWait = 0; walkAfterHop = false      // a run would carry him off the focus spot
        case .flip:
            brain.flipCompact = focused
            brain.commandedFlipFail = rollFlipFail()
            brain.commandedFlip = true
        default:
            brain.commandedIdle = Self.idleKind(for: t)
        }
    }
}
