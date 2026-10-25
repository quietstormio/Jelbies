//
//  A11yCore.swift
//  The shared accessibility contract (round-1023 a11y sweep). PART A and PART B both add this file BYTE-IDENTICAL from the scratchpad copy
//  (a11y/A11yCore.swift) and neither edits it afterwards, so the merge is clean. Settings (in-app Accessibility section), the announcer and the
//  sound-captions queue. UI lives in Accessibility/AccessibilitySettingsView.swift + CaptionsView.swift (Part A); emitters in Part B files.
//

import SwiftUI
import Observation

/// How the Jelly Circuit / drills take input.
enum RaceAssist: String, CaseIterable, Sendable {
    case off            // two foot buttons, as designed
    case forgiving      // two buttons; a repeated foot is forgiven (no stumble)
    case oneButton      // one big Step button; the feet alternate by themselves
    case auto           // he runs by himself at a steady pace; the player cheers (no input needed)
    var title: String {
        switch self { case .off: return "Off"; case .forgiving: return "Forgiving"; case .oneButton: return "One button"; case .auto: return "Auto run" }
    }
}

@MainActor
@Observable
final class A11ySettings {
    static let shared = A11ySettings()

    /// Sound captions ("Pip chirps", "Squish") under the top bar.
    var captions: Bool { didSet { save("a11y.captions", captions) } }
    /// In-app Reduce Motion (OR-ed with the system setting): camera swoops become crossfades, no confetti / pulses / screen sweeps. Jelly physics never changes.
    var reduceMotionInApp: Bool { didSet { save("a11y.reduceMotion", reduceMotionInApp) } }
    /// Mirrors `accessibilityReduceMotion` (GameScreen sets it). Not persisted.
    var systemReduceMotion = false
    /// Race / drill input assist.
    var raceAssist: RaceAssist { didSet { d.set(raceAssist.rawValue, forKey: "a11y.raceAssist") } }
    /// Hurdles are jumped for the player in any race control mode (the Jump button still works).
    var autoJump: Bool { didSet { save("a11y.autoJump", autoJump) } }
    /// Rhythm timing (drill, Show dance, trick ring): wider windows and a slower ring.
    var relaxedTiming: Bool { didSet { save("a11y.relaxedTiming", relaxedTiming) } }
    /// The mic is tap-to-start / tap-to-stop instead of hold.
    var tapToTalk: Bool { didSet { save("a11y.tapToTalk", tapToTalk) } }
    /// Hints and transient bubbles stay until dismissed / handled.
    var longerHints: Bool { didSet { save("a11y.longerHints", longerHints) } }
    /// Announce game events with VoiceOver (on by default; only matters while VoiceOver runs).
    var announcements: Bool { didSet { save("a11y.announce", announcements) } }

    var reduceMotion: Bool { systemReduceMotion || reduceMotionInApp }
    /// Window scale for rhythm judging.
    var timingScale: Double { relaxedTiming ? 2.5 : 1 }

    @ObservationIgnored private let d: UserDefaults

    init(defaults: UserDefaults = .standard) {
        d = defaults
        func b(_ k: String, _ arg: String, _ def: Bool) -> Bool {
            if defaults.object(forKey: arg) != nil { return defaults.integer(forKey: arg) != 0 }       // launch argument (-A11yCaptions 1)
            return defaults.object(forKey: k) == nil ? def : defaults.bool(forKey: k)
        }
        captions = b("a11y.captions", "A11yCaptions", false)
        reduceMotionInApp = b("a11y.reduceMotion", "A11yReduceMotion", false)
        autoJump = b("a11y.autoJump", "A11yAutoJump", false)
        relaxedTiming = b("a11y.relaxedTiming", "A11yRelaxedTiming", false)
        tapToTalk = b("a11y.tapToTalk", "A11yTapToTalk", false)
        longerHints = b("a11y.longerHints", "A11yLongerHints", false)
        announcements = b("a11y.announce", "A11yAnnounce", true)
        raceAssist = RaceAssist(rawValue: defaults.string(forKey: "A11yRaceAssist") ?? defaults.string(forKey: "a11y.raceAssist") ?? "") ?? .off
    }
    nonisolated deinit {}

    private func save(_ k: String, _ v: Bool) { d.set(v, forKey: k) }
}

/// VoiceOver announcements. Everything goes through `say` so tests can read `log` / swap `sink`.
@MainActor
enum A11yAnnounce {
    enum Priority: Sendable { case low, normal, high }
    /// Test seam: replaces the system post.
    static var sink: ((String, Priority) -> Void)?
    /// The last announcements (newest last, at most 20), whether or not VoiceOver is running.
    private(set) static var log: [String] = []
    private static var last: (text: String, at: Date)?

    static func say(_ text: String, priority: Priority = .normal, settings: A11ySettings = .shared, now: Date = Date()) {
        guard settings.announcements, !text.isEmpty else { return }
        if let l = last, l.text == text, now.timeIntervalSince(l.at) < 1.5 { return }          // de-dupe bursts
        last = (text, now)
        log.append(text); if log.count > 20 { log.removeFirst(log.count - 20) }
        if let sink { sink(text, priority); return }
        var s = AttributedString(text)
        s.accessibilitySpeechAnnouncementPriority = priority == .high ? .high : priority == .low ? .low : .default
        AccessibilityNotification.Announcement(s).post()
    }
    static func resetForTests() { log = []; last = nil; sink = nil }
}

/// One on-screen sound caption.
struct Caption: Identifiable, Equatable, Sendable {
    let id: Int
    let text: String
    let born: Date
}

/// The sound-captions queue: emitters (AudioHub, Part B) `post`; CaptionsView (Part A) draws `items`.
@MainActor
@Observable
final class CaptionCenter {
    static let shared = CaptionCenter()
    static let life: TimeInterval = 2.4, maxShown = 3

    private(set) var items: [Caption] = []
    @ObservationIgnored private var seq = 0
    @ObservationIgnored var settings: A11ySettings = .shared

    nonisolated deinit {}

    func post(_ text: String, now: Date = Date()) {
        guard settings.captions, !text.isEmpty else { return }
        prune(now: now)
        if let i = items.firstIndex(where: { $0.text == text }) { items.remove(at: i) }          // same sound again: refresh, do not stack
        seq += 1
        items.append(Caption(id: seq, text: text, born: now))
        if items.count > Self.maxShown { items.removeFirst(items.count - Self.maxShown) }
    }
    func prune(now: Date = Date()) { items.removeAll { now.timeIntervalSince($0.born) > Self.life } }
    func clear() { items = [] }
}
