//
//  GameMessageCenter.swift
//  ONE place for every short on-screen message (voice lines, guest / park lines, refusals, toasts, sound captions): a single queue and a single bar.
//  The bar is the cream capsule at the top LEFT, at the HUD's left margin directly under the top-left control (the same pills the close-up's cuddle line always used), drawn in its own pass-through window (like the tip cards) so it
//  stands in the same spot over the room, the park, a Town screen or a sheet. Never over the left rail, the mic, the heart or a menu (they are at the bottom).
//  Behaviour: one message at a time (no overlap), 2.5 to 4 s by length, anything above chatty replaces a chatty line (a refusal / error too), repeats are merged, VoiceOver hears each once,
//  Reduce Motion gets a plain fade. Tip cards share the anchor (`GameMessageLayout`) and never show at the same time (the message waits for the tip).
//  Thought bubbles above a Jelmiko (needs, the "Not hungry" label) are part of the world and stay where they are.
//

import SwiftUI
import UIKit
import Observation

/// Where the bar (and a tip card) stands: top LEFT, under the top-left control.
enum GameMessageLayout {
    /// Points below the top safe edge where the HUD's last top row ends (GameScreen measures it: the settings / coin row, plus the "Sleep until morning" pill when it is there).
    static var hudBottom: CGFloat = 60
    static let defaultHudBottom: CGFloat = 60
    /// The park / camp (portrait) has a second row (the friends chips): its own value while it is up.
    static var hudBottomOverride: CGFloat?
    static func top(safeTop: CGFloat) -> CGFloat { safeTop + (hudBottomOverride ?? hudBottom) }
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
        var shownAt: Date?
        var duration: TimeInterval { GameMessageCenter.duration(for: text) }
    }

    static let minDuration: TimeInterval = 2.5, maxDuration: TimeInterval = 4.0
    static let mergeWindow: TimeInterval = 4          // the same line again within this long of its last showing is dropped
    static let staleAfter: TimeInterval = 8           // a queued line that waited this long (a tip held the bar) is dropped
    static let queueCap = 4

    /// 2.5 s up to 20 characters, 4 s from 60, linear between.
    nonisolated static func duration(for text: String) -> TimeInterval {
        let n = Double(text.count)
        let f = min(1, max(0, (n - 20) / 40))
        return minDuration + (maxDuration - minDuration) * f
    }

    private(set) var current: Message?
    private(set) var queue: [Message] = []
    @ObservationIgnored private var seq = 0
    @ObservationIgnored private var lastShown: (text: String, at: Date)?
    /// A tip card is up: the bar waits (tests swap it).
    @ObservationIgnored var tipShowing: () -> Bool = { TipBook.shared.current != nil }
    /// Real use schedules the expiry itself; tests turn it off and call `tick(now:)`.
    @ObservationIgnored var autoSchedule = true
    @ObservationIgnored private var timer: Task<Void, Never>?

    nonisolated deinit {}

    func post(_ text: String, icon: String? = nil, priority: Priority = .normal, scope: Scope = .none, identifier: String = "game-message", announce: Bool = true, now: Date = Date()) {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        tick(now: now)
        if current?.text == text || queue.contains(where: { $0.text == text }) { return }          // a repeat: merged
        if let l = lastShown, l.text == text, now.timeIntervalSince(l.at) < Self.mergeWindow { return }
        seq += 1
        let m = Message(id: seq, text: text, icon: icon, priority: priority, scope: scope, identifier: identifier, announce: announce, posted: now, shownAt: nil)
        if priority == .caption {          // captions never wait: they take an empty bar or a caption's place, else they are dropped
            if current == nil, !tipShowing() { show(m, now: now) } else if current?.priority == .caption { show(m, now: now) }
            return
        }
        if let c = current, Self.replaces(m, c) { show(m, now: now); return }
        if current == nil, !tipShowing() { show(m, now: now); return }
        queue.append(m)
        queue = Self.stableSorted(queue)          // (highest first, equal priorities in the order posted)
        if queue.count > Self.queueCap { queue.removeLast(queue.count - Self.queueCap) }
        arm(now: now)
    }

    nonisolated static func replaces(_ new: Message, _ cur: Message) -> Bool {
        if cur.priority == .caption { return new.priority > .caption }
        return cur.priority == .chatty && new.priority >= .normal
    }
    private nonisolated static func stableSorted(_ q: [Message]) -> [Message] { q.enumerated().sorted { a, b in a.element.priority != b.element.priority ? a.element.priority > b.element.priority : a.offset < b.offset }.map(\.element) }

    /// Expire the current line, drop stale queued ones, promote the next (unless a tip card is up).
    func tick(now: Date = Date()) {
        if let c = current, let s = c.shownAt, now.timeIntervalSince(s) >= c.duration { current = nil }
        queue.removeAll { now.timeIntervalSince($0.posted) > Self.staleAfter }
        if current == nil, !tipShowing(), !queue.isEmpty { show(queue.removeFirst(), now: now) }
        if current != nil || !queue.isEmpty { arm(now: now) }
    }

    /// Drop everything said under `scope` (the outing ended).
    func dismiss(scope: Scope) {
        guard scope != .none else { return }
        queue.removeAll { $0.scope == scope }
        if current?.scope == scope { current = nil; tick() }
    }
    /// A sound caption gives way to a tip card.
    func dropCaption() { if current?.priority == .caption { current = nil } }
    func clear() { current = nil; queue = []; lastShown = nil; timer?.cancel() }

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
        if let c = current, let s = c.shownAt { wait = max(0.05, c.duration - now.timeIntervalSince(s) + 0.02) }
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
    static var reduceMotion: Bool { UIAccessibility.isReduceMotionEnabled || A11ySettings.shared.reduceMotion }

    var body: some View {
        GeometryReader { geo in
            let safe = GameMessageHost.safeInsets
            ZStack(alignment: .topLeading) {
                Color.clear
                if let m = center.current {
                    GameMessageCapsule(text: m.text, icon: m.icon, identifier: m.identifier)
                        .frame(maxWidth: GameMessageLayout.width(geo.size, safeLeft: safe.left), alignment: .leading)
                        .padding(.leading, GameMessageLayout.left(safeLeft: safe.left))
                        .padding(.top, GameMessageLayout.top(safeTop: safe.top))
                        .id(m.id)
                        .transition(Self.reduceMotion ? .opacity : .opacity.combined(with: .offset(y: -10)))
                }
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
            .animation(.easeOut(duration: 0.25), value: center.current?.id)
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

    var body: some View {
        HStack(spacing: 8) {
            if let icon { Image(systemName: icon).font(.system(size: 16, weight: .bold)).foregroundStyle(FocusStyle.pink).accessibilityHidden(true) }
            Text(text)
                .font(JFont.scaled(15, .bold, style: .body, cap: 1.3))
                .foregroundStyle(FocusStyle.brown)
                .lineLimit(2).minimumScaleFactor(0.85).multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 14).padding(.vertical, 7)
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
