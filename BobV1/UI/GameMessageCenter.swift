//
//  GameMessageCenter.swift
//  ONE place for every short on-screen message (voice lines, guest / park lines, refusals, toasts, sound captions): a single queue and a single bar.
//  The bar is the cream capsule at the top LEFT, at the HUD's left margin directly under the top-left control (the same pills the close-up's cuddle line always used), drawn in its own pass-through window (like the tip cards) so it
//  stands in the same spot over the room, the park, a Town screen or a sheet. Never over the left rail, the mic, the heart or a menu (they are at the bottom).
//  Behaviour: one message at a time (no overlap), 2.5 to 4 s by length, anything above chatty replaces a chatty line (a refusal / error too), repeats are merged, VoiceOver hears each once,
//  Reduce Motion gets a plain fade. Tip cards share the anchor (`GameMessageLayout`) and never show at the same time (the message waits for the tip). A sound caption is a second, smaller pill under the message and is never dropped.
//  Thought bubbles above a Jelmiko (needs, the "Not hungry" label) are part of the world and stay where they are.
//

import SwiftUI
import UIKit
import Observation

/// Where the bar (and a tip card) stands: top LEFT, under the top-left control.
enum GameMessageLayout {
    /// Points below the top safe edge where the HUD's last top row ends (GameScreen measures it: the settings / coin row, plus the "Sleep until morning" pill when it is there).
    static var hudBottom: CGFloat = 60 { didSet { if oldValue != hudBottom { pokeBar() } } }
    static let defaultHudBottom: CGFloat = 60
    /// The park / camp (portrait) has a second row (the friends chips): its own value while it is up.
    static var hudBottomOverride: CGFloat?
    /// The bottom edge (window points) of the park's friends-chip row while it is on screen, measured by ParkChrome (a preference on the row itself), nil otherwise.
    /// The bar then stands 8 pt under it, whatever the width, however many chips, however the row lays out.
    nonisolated(unsafe) static var parkRowMaxY: CGFloat? { didSet { if oldValue != parkRowMaxY { pokeBar() } } }
    /// The bar re-reads its anchor when it changes (the park scene or the sleep pill can arrive after the message is up).
    static func pokeBar() { Task { @MainActor in GameMessageCenter.shared.layoutTick &+= 1 } }
    static func top(safeTop: CGFloat, portrait: Bool = true) -> CGFloat {
        if portrait, let y = parkRowMaxY { return y + 8 }
        return safeTop + (hudBottomOverride ?? hudBottom)
    }

    /// The HUD's left margin (GameScreen pads its rows 16 pt).
    static let margin: CGFloat = 16
    /// The bar's width: the screen less the margins (and the left safe inset), at most 520; on a phone on its side at most 55% so it stays clear of the right-hand corner.
    static func width(_ size: CGSize, safeLeft: CGFloat = 0) -> CGFloat {
        let landscape = size.width > size.height * 1.2
        let room = size.width - 2 * margin - safeLeft
        return landscape ? min(size.width * 0.55, 520, room) : min(room, 520)
    }
    static func left(safeLeft: CGFloat) -> CGFloat { safeLeft + margin }
}

@MainActor
@Observable
final class GameMessageCenter {
    static let shared = GameMessageCenter()

    /// Higher replaces lower. `caption` = a sound caption (never queues), `chatty` = what was heard / a visitor's small talk, `normal` = most lines, `important` = a refusal or error.
    enum Priority: Int, Comparable, Sendable {
        case caption, chatty, normal, important
        static func < (a: Priority, b: Priority) -> Bool { a.rawValue < b.rawValue }
    }
    /// `outing`: gone as soon as the park / camp outing is over (a line said out there must not turn up back at home).
    enum Scope: Sendable { case none, outing }

    struct Message: Identifiable, Equatable {
        let id: Int
        let text: String
        let icon: String?
        let priority: Priority
        let scope: Scope
        let identifier: String
        let announce: Bool
        let posted: Date
        /// A hint that stays until the player acts (VoiceOver / "Longer hints"): up to `stickyMax`, or until `dismiss(identifier:)`.
        var sticky = false
        var shownAt: Date?
        var duration: TimeInterval { sticky ? GameMessageCenter.stickyMax : GameMessageCenter.duration(for: text) }
    }

    static let minDuration: TimeInterval = 2.5, maxDuration: TimeInterval = 4.0
    static let mergeWindow: TimeInterval = 4          // the same line again within this long of its last showing is dropped
    static let staleAfter: TimeInterval = 8           // a queued line that waited this long (a tip held the bar) is dropped
    static let queueCap = 4
    static let stickyMax: TimeInterval = 60
    /// Hints stay until used when VoiceOver is on or "Longer hints" is set (Settings: "Hints stay until you use them").
    static var hintsSticky: Bool { A11ySettings.shared.longerHints || UIAccessibility.isVoiceOverRunning }

    /// 2.5 s up to 20 characters, 4 s from 60, linear between.
    nonisolated static func duration(for text: String) -> TimeInterval {
        let n = Double(text.count)
        let f = min(1, max(0, (n - 20) / 40))
        return minDuration + (maxDuration - minDuration) * f
    }

    /// Bumped when the bar's anchor moves (GameMessageLayout); the bar reads it so it re-places itself.
    var layoutTick = 0
    private(set) var current: Message?
    /// The sound caption: its own small pill under the message (or alone in the bar's place). At most one; a newer caption replaces it, it never replaces or waits for a message.
    private(set) var caption: Message?
    private(set) var queue: [Message] = []
    @ObservationIgnored private var seq = 0
    @ObservationIgnored private var lastShown: (text: String, at: Date)?
    /// A tip card is up: the bar waits (tests swap it).
    @ObservationIgnored var tipShowing: () -> Bool = { TipBook.shared.current != nil }
    /// Real use schedules the expiry itself; tests turn it off and call `tick(now:)`.
    @ObservationIgnored var autoSchedule = true
    @ObservationIgnored private var timer: Task<Void, Never>?

    nonisolated deinit {}

    func post(_ text: String, icon: String? = nil, priority: Priority = .normal, scope: Scope = .none, identifier: String = "game-message", announce: Bool = true, sticky: Bool = false, now: Date = Date()) {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        tick(now: now)
        if priority == .caption {
            if caption?.text == text { return }
            seq += 1
            caption = Message(id: seq, text: text, icon: icon, priority: .caption, scope: scope, identifier: identifier, announce: false, posted: now, shownAt: now)
            arm(now: now)
            return
        }
        if current?.text == text || queue.contains(where: { $0.text == text }) { return }          // a repeat: merged
        if let l = lastShown, l.text == text, now.timeIntervalSince(l.at) < Self.mergeWindow { return }
        seq += 1
        let m = Message(id: seq, text: text, icon: icon, priority: priority, scope: scope, identifier: identifier, announce: announce, posted: now, sticky: sticky, shownAt: nil)
        if let c = current, Self.replaces(m, c) { show(m, now: now); return }
        if current == nil, !tipShowing() { show(m, now: now); return }
        queue.append(m)
        queue = Self.stableSorted(queue)          // (highest first, equal priorities in the order posted)
        if queue.count > Self.queueCap { queue.removeLast(queue.count - Self.queueCap) }
        arm(now: now)
    }

    nonisolated static func replaces(_ new: Message, _ cur: Message) -> Bool {
        return cur.priority == .chatty && new.priority >= .normal
    }
    private nonisolated static func stableSorted(_ q: [Message]) -> [Message] { q.enumerated().sorted { a, b in a.element.priority != b.element.priority ? a.element.priority > b.element.priority : a.offset < b.offset }.map(\.element) }

    /// Expire the current line, drop stale queued ones, promote the next (unless a tip card is up).
    func tick(now: Date = Date()) {
        if let c = current, let s = c.shownAt, now.timeIntervalSince(s) >= c.duration { current = nil }
        if let c = caption, let s = c.shownAt, now.timeIntervalSince(s) >= c.duration { caption = nil }
        queue.removeAll { now.timeIntervalSince($0.posted) > Self.staleAfter }
        if current == nil, !tipShowing(), !queue.isEmpty { show(queue.removeFirst(), now: now) }
        if current != nil || caption != nil || !queue.isEmpty { arm(now: now) }
    }

    /// THE RULE: a refused start never returns silently. Every place that says "not now" (a blocker, a closed door, a greyed button) calls this with the reason, so the player always hears why and what to do.
    /// An empty reason still says something kind (`fallback`).
    static let fallback = "Not right now. Try again in a moment."
    func refuse(_ why: String?, now: Date = Date()) {
        post((why?.isEmpty == false ? why! : Self.fallback), priority: .important, identifier: "refusal", now: now)
    }

    /// Drop everything said under `scope` (the outing ended).
    func dismiss(scope: Scope, now: Date = Date()) {
        guard scope != .none else { return }
        queue.removeAll { $0.scope == scope }
        if current?.scope == scope { current = nil; tick(now: now) }
    }
    /// The player acted: a sticky hint (or any line) with this identifier goes now.
    func dismiss(identifier: String, now: Date = Date()) {
        queue.removeAll { $0.identifier == identifier }
        if current?.identifier == identifier { current = nil; tick(now: now) }
    }
    func clear() { current = nil; caption = nil; queue = []; lastShown = nil; timer?.cancel() }

    private func show(_ m: Message, now: Date) {
        var m = m; m.shownAt = now
        current = m
        lastShown = (m.text, now)
        if m.announce { A11yAnnounce.say(m.text, priority: m.priority == .important ? .high : .normal, now: now) }          // VoiceOver: once, when it appears
        arm(now: now)
    }

    private func arm(now: Date) {
        guard autoSchedule else { return }
        timer?.cancel()
        var wait: TimeInterval = 0.5
        let live = [current, caption].compactMap { $0 }.compactMap { m in m.shownAt.map { m.duration - now.timeIntervalSince($0) } }
        if let soon = live.min() { wait = max(0.05, soon + 0.02) }
        timer = Task { [weak self] in
            try? await Task.sleep(for: .seconds(wait))
            guard !Task.isCancelled else { return }
            self?.tick()
        }
    }
}

// MARK: the bar

struct GameMessageBar: View {
    let center: GameMessageCenter
    private let book = TipBook.shared
    static var reduceMotion: Bool { UIAccessibility.isReduceMotionEnabled || A11ySettings.shared.reduceMotion }

    var body: some View {
        GeometryReader { geo in
            let safe = GameMessageHost.safeInsets
            let _ = center.layoutTick
            let w = GameMessageLayout.width(geo.size, safeLeft: safe.left)
            // a caption sits under the message, or under a top tip card (a caption is never dropped for a tip); alone it takes the bar's place
            let tipBottom: CGFloat? = book.current != nil && book.cardFrame.minY < geo.size.height / 2 && book.cardFrame != .zero ? book.cardFrame.maxY + 6 : nil
            let top = GameMessageLayout.top(safeTop: safe.top, portrait: geo.size.height > geo.size.width)
            ZStack(alignment: .topLeading) {
                Color.clear
                VStack(alignment: .leading, spacing: 6) {
                    if let m = center.current {
                        GameMessageCapsule(text: m.text, icon: m.icon, identifier: m.identifier)
                            .id(m.id)
                            .transition(Self.reduceMotion ? .opacity : .opacity.combined(with: .offset(y: -10)))
                    }
                    if tipBottom == nil, let c = center.caption {
                        GameMessageCapsule(text: c.text, icon: c.icon, identifier: c.identifier, small: true)
                            .id(c.id)
                            .transition(.opacity)
                    }
                }
                .frame(maxWidth: w, alignment: .leading)
                .padding(.leading, GameMessageLayout.left(safeLeft: safe.left))
                .padding(.top, top)
                if let y = tipBottom, let c = center.caption {
                    GameMessageCapsule(text: c.text, icon: c.icon, identifier: c.identifier, small: true)
                        .id(c.id)
                        .frame(maxWidth: w, alignment: .leading)
                        .padding(.leading, GameMessageLayout.left(safeLeft: safe.left))
                        .padding(.top, y)
                        .transition(.opacity)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
            .animation(.easeOut(duration: 0.25), value: center.current?.id)
            .animation(.easeOut(duration: 0.2), value: center.caption?.id)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}

/// The capsule itself: solid cream, dark brown rounded bold text, soft shadow. Also what the tests and the boards look at.
struct GameMessageCapsule: View {
    let text: String
    var icon: String? = nil
    var identifier = "game-message"
    /// The sound caption's size: a smaller pill, same look.
    var small = false

    var body: some View {
        HStack(spacing: 8) {
            if let icon { Image(systemName: icon).font(.system(size: small ? 12 : 16, weight: .bold)).foregroundStyle(FocusStyle.pink).accessibilityHidden(true) }
            Text(text)
                .font(JFont.scaled(small ? 13 : 15, .bold, style: .body, cap: 1.3))
                .foregroundStyle(FocusStyle.brown)
                .lineLimit(2).minimumScaleFactor(0.85).multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, small ? 11 : 14).padding(.vertical, small ? 5 : 7)
        .background(Capsule().fill(FocusStyle.cream).shadow(color: FocusStyle.shadow.opacity(0.25), radius: 5, y: 2))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(text)
        .accessibilityIdentifier(identifier)
    }
}

// MARK: the window

/// A clear window the bar lives in: above the room, the Town screens and sheets, and it never takes a touch.
final class GameMessageWindow: UIWindow {
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? { nil }
}

@MainActor
enum GameMessageHost {
    private static var window: GameMessageWindow?
    static var safeInsets: UIEdgeInsets { TipWindowHost.safeInsets }

    static func install() {
        guard window == nil else { return }
        guard let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first(where: { $0.activationState == .foregroundActive }) ?? UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first else { return }
        let w = GameMessageWindow(windowScene: scene)
        w.windowLevel = .normal + 4
        w.backgroundColor = .clear
        let host = UIHostingController(rootView: GameMessageBar(center: .shared))
        host.view.backgroundColor = .clear
        w.rootViewController = host
        w.isHidden = false
        window = w
    }
}
