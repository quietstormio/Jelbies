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
//  (`GameCare.comeHere`); already in focus it is a happy hop. Grumpy and the reliability roll still apply (decided in VoiceTraining).
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
        @ObservationIgnored private var queue: [(r: VoiceReaction, kind: VoiceFeedback.Kind?)] = []
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
            case .nameHeard(learned: false): kind = .nameRep(training.book.name.reps)
            case .nameLearned: kind = .nameLearned
            case .nameHeard(learned: true): kind = nil
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

    init(training: VoiceTraining? = nil, input: SpeechInput? = nil, tutorial: VoiceTutorial? = nil, now: @escaping () -> Double = { Date.timeIntervalSinceReferenceDate }) {
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
        input.warmUp()
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

    private func process(_ transcript: String) {
        defer { mode.finish() }
        guard let care else { return }
        // a meal / tray owns him: commands are ignored and nothing is learned
        if care.trayOut { queue.append((.ignore, nil)); return }
        if Self.logging { NSLog("[voice] process transcript=\"%@\" tokens=%@", transcript, VoiceMatcher.tokens(transcript).joined(separator: ",")) }
        let r = training.decide(transcript: transcript, runningMove: runningAtOpen, mood: care.mood, session: session)
        if r == .perform(.come) { comeCommands += 1 }
        // feedback for the player: what was heard (now), and what he understood (when the reaction runs)
        let trimmed = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        heardSeq += 1
        heard = VoiceHeard(id: heardSeq, text: trimmed.isEmpty ? "\u{2026}" : "\u{201C}\(trimmed)\u{201D}", born: clock())
        teachPrompt = nil
        var kind: VoiceFeedback.Kind?
        switch r {
        case .ignore:
            if VoiceMatcher.tokens(transcript).isEmpty { kind = .nothing }
            else if let m = training.lastMiss { kind = .missed(m, pct: Int((training.reliability(m) * 100).rounded())) }
            else { kind = .unknown }
        case .wrongTrick(let said, _): kind = .missed(said, pct: Int((training.reliability(said) * 100).rounded()))
        default: break
        }
        if r == .ignore, training.lastMiss == .flip, flipRoll() < 0.5 {            // he knew it but missed: sometimes it is a faceplant
            flipFailQueued = true
            queue.append((.perform(.flip), kind)); return
        }
        queue.append((r, kind))
    }

    /// Debug / capture: a listen that "hears" `words` after `hold` seconds. `teach` starts that trick first and waits a second.
    func simulate(_ words: String, teach: VoiceTrick? = nil, hold: Double = 1.2) async {
        if let t = teach {
            queue.append((.perform(t), .silent))
            try? await Task.sleep(nanoseconds: 1_000_000_000)
        }
        guard begin() else { return }
        try? await Task.sleep(nanoseconds: UInt64(hold * 1e9))
        debugTranscript = words
        release()
    }

    /// Debug / capture (`-VoiceLearned 1`): his name and every trick count as learned with their suggestion words.
    func debugLearnAll() {
        training.debugLearnName()
        for t in VoiceTrick.allCases { training.debugLearn(t, word: t.suggestion, reliability: 0.95) }
        tutorial.finish()
    }

    /// The trick book row: do the trick now (so the next said word binds to it).
    func show(_ t: VoiceTrick) {
        queue.append((.perform(t), .silent))
        if !training.isLearned(t) { teachPrompt = TeachPrompt(trick: t, until: clock() + Self.promptTime) }
    }

    // MARK: mapping

    static func trick(for kind: IdleKind?) -> VoiceTrick? {
        switch kind {
        case .sit: return .sit
        case .jacks: return .jacks
        case .run, .stumble: return .run
        case .look: return .look
        default: return nil
        }
    }
    static func idleKind(for t: VoiceTrick) -> IdleKind? {
        switch t {
        case .sit: return .sit
        case .jacks: return .jacks
        case .run: return .run
        case .look: return .look
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
        if !listening, !queue.isEmpty { let q = queue.removeFirst(); run(q.r, kind: q.kind, care: care, brain: brain) }
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

    private func run(_ r: VoiceReaction, kind: VoiceFeedback.Kind?, care: GameCare, brain: BlobBrain) {
        if UserDefaults.standard.bool(forKey: "VoiceLog") { NSLog("VOICELOG reaction=%@ mood=%@", String(describing: r), String(describing: care.needs.mood)) }   // capture aid
        if care.trayOut { return }                                   // a meal owns him
        let focused = care.focus.isActive
        if focused, care.focus.phase == .approaching { return }
        let trickRunning = Self.running(brain) != nil
        emitFeedback(r, override: kind)
        switch r {
        case .perform(let t), .wrongTrick(_, let t):
            doTrick(t, care: care, brain: brain, focused: focused)
        case .learnedStep:
            brain.blinkRequested = true                              // a nod: he noticed (plus the small ear-perk tilt, see `perkLeft`)
        case .trickLearned(let learnedTrick):
            brain.blinkRequested = true
            care.touchPlay?.spawnHeart(now: CACurrentMediaTime())
            if !care.focus.isActive { pendingHop = true; hopWait = 0; walkAfterHop = false }      // the happy hop at the lesson's end
        case .puzzled, .nameHeard(learned: false), .ignore:
            if !trickRunning { brain.commandedIdle = .look }         // the tilt / shrug: look away briefly and back
        case .grumpyIgnore:
            if !trickRunning { brain.commandedIdle = .slump }
            care.showNeedBubble()
        case .nameHeard(learned: true), .nameLearned:
            nameHop = true; nameHopSeen = false; hopWait = 0; walkAfterHop = !focused
            brain.commandedNameHop = true
        }
    }

    private func doTrick(_ t: VoiceTrick, care: GameCare, brain: BlobBrain, focused: Bool) {
        switch t {
        case .come:
            comeUntil = clock() + Self.comeWindow
            if focused { pendingHop = true; hopWait = 0; walkAfterHop = false; return }       // already in the close-up: a happy hop
            care.comeHere()                      // the same call as tapping him: he walks to the front, then the camera zooms into cuddle mode
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
