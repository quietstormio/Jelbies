//
//  TrainSession.swift
//  The close-up's trick-training session (r1023-train): a small state machine the Train card (TrainCard.swift) shows and the voice coordinator drives
//  (VoiceCoordinator+Train.swift). pick a trick -> he does the move (demo) -> the mic opens by itself (listen) -> a rep fills a pip (heard)
//  -> after 3 reps "<name> learned <trick>!" (learned) -> "Try it" with no demo (tryIt) -> he does it (tried). A word that does not count says why (missed).
//  Pure state: no UIKit, no audio. Times are in game seconds (the coordinator's tick adds dt), so tests are deterministic.
//

import Foundation
import Observation
import UIKit

nonisolated enum TrainWhy: Equatable, Sendable {
    case nothing                                   // silence / nothing recognised
    case otherWord(expected: String, heard: String) // a different word than the one this trick is bound to
    case wasName                                   // only a name was said
    case reserved(heard: String)                   // the word is already a command (stop, come ...) or another trick's word
}

nonisolated enum TrainStep: Equatable, Sendable {
    case pick
    case demo(VoiceTrick)
    case listen(VoiceTrick)
    case heard(VoiceTrick, reps: Int)
    case missed(VoiceTrick, why: TrainWhy)
    case learned(VoiceTrick)
    case tryIt(VoiceTrick)
    case tried(VoiceTrick, ok: Bool, heard: String)

    var name: String {
        switch self {
        case .pick: return "pick"; case .demo: return "demo"; case .listen: return "listen"; case .heard: return "heard"
        case .missed: return "missed"; case .learned: return "learned"; case .tryIt: return "tryIt"; case .tried: return "tried"
        }
    }
    var trick: VoiceTrick? {
        switch self {
        case .pick: return nil
        case .demo(let t), .listen(let t), .heard(let t, _), .missed(let t, _), .learned(let t), .tryIt(let t), .tried(let t, _, _): return t
        }
    }
    /// The step is waiting for the player to say the word.
    var isListening: Bool { switch self { case .listen, .tryIt: return true; default: return false } }
}

@MainActor
@Observable
final class TrainSession {
    /// The Jelly being taught (the close-up's one Jelly).
    let subject: Int
    private(set) var step: TrainStep = .pick
    /// Seconds in the current step (the coordinator's tick adds dt).
    var age: Float = 0
    /// The auto-listen window left (seconds); 0 = not auto-listening.
    var autoLeft: Float = 0
    /// The listen should open as soon as the mic is free.
    var wantsOpen = false
    /// The mic cannot be used (denied / unavailable): the card says so.
    var noMic = false
    /// VoiceOver is speaking the step's announcement: the mic stays shut until it finishes (or this many seconds pass), so it never transcribes VoiceOver.
    var openGate: Float = 0
    /// The announcement text the gate waits for.
    var gateText = ""
    var gateObserver: NSObjectProtocol?
    /// Whether VoiceOver is running (a seam for tests).
    nonisolated(unsafe) static var voiceOverRunning: () -> Bool = { UIAccessibility.isVoiceOverRunning }
    /// The longest the mic waits for VoiceOver to finish speaking.
    static let voiceOverGate: Float = 2.0
    /// What was last heard, quoted (empty = nothing).
    var heardText = ""
    /// The last transcript (for "Use that word instead").
    var lastTranscript = ""
    /// Steps taken (tests).
    private(set) var history: [String] = []

    /// How long the mic stays open on its own, in seconds.
    static let listenWindow: Float = 3.5
    /// How long the "Again!" beat lasts before the next demo, and the "learned" celebration before Try it.
    static let againBeat: Float = 0.8
    static let learnedBeat: Float = 2.4
    /// The demo waits at most this long for the move to start (run / flip / hop stand-ins never look like the move).
    static let demoCap: Float = 1.5

    nonisolated deinit {}
    init(subject: Int) { self.subject = subject; history = ["pick"] }

    func go(_ s: TrainStep) {
        guard s != step || age > 0 else { return }
        step = s; age = 0; autoLeft = 0
        history.append(s.name)
        if history.count > 80 { history.removeFirst() }
    }

    /// The line the card shows and VoiceOver announces for a step.
    static func headline(_ step: TrainStep, name: String, word: (VoiceTrick) -> String, reps: (VoiceTrick) -> Int) -> String {
        let n = VoiceTuning.repsToLearn
        switch step {
        case .pick: return "Teach \(name) a trick"
        case .demo(let t): return "Watch \(name) \(t.title.lowercased())"
        case .listen(let t): return "Say \u{201C}\(word(t))\u{201D} now. \(reps(t)) of \(n)"
        case .heard(let t, let r): return r >= n ? "\(name) learned \(t.title)!" : "Good! \(r) of \(n). Again!"
        case .missed(let t, let why):
            switch why {
            case .nothing: return "Didn\u{2019}t catch that. Say \u{201C}\(word(t))\u{201D} when \(name) does it"
            case .otherWord(let expected, let heard): return "Heard \u{201C}\(heard)\u{201D}. Say \u{201C}\(expected)\u{201D} to keep going"
            case .wasName: return "That\u{2019}s \(name)\u{2019}s name. Say the trick word"
            case .reserved(let heard): return "\u{201C}\(heard)\u{201D} already means something else. Pick another word"
            }
        case .learned(let t): return "\(name) learned \(t.title)!"
        case .tryIt(let t): return "Now say \u{201C}\(word(t))\u{201D}. No help this time"
        case .tried(let t, let ok, let heard):
            return ok ? "\(name) did it! Say \u{201C}\(word(t))\u{201D} in the room any time"
                      : (heard.isEmpty ? "Didn\u{2019}t catch that. Try saying \u{201C}\(word(t))\u{201D}" : "Heard \u{201C}\(heard)\u{201D}. Say \u{201C}\(word(t))\u{201D}")
        }
    }
}
