//
//  TipBook.swift
//  First-time tips: one show-once card per feature (the model; the card and its window are in TipCards.swift).
//  ONE queue and ONE flag family ("Jelbies.tip.<id>.v1", player-wide, written when the card APPEARS) next to the first-day tour (Start/FirstDayTour.swift);
//  a screen calls `request(id)` at its trigger and registers itself with `screenOpened(id)` / `screenClosed(id)`; `tick()` (a 0.25 s pump) offers the first queued card whose
//  screen is still open, 1.5 s after the last one went, and never while something else owns the game (`TipContext.blocked`).
//

import Foundation
import Observation
import SwiftUI

struct TipCard: Equatable {
    let id: String
    let symbol: String
    let title: String
    let body: String
}

/// What the game is doing right now; a card never shows (and a shown one hides) while any of it is true. Built by `TipBook.shared.context` (GameScreen), plain Bools so tests can set them.
struct TipContext: Equatable {
    var tour = false            // FirstDayTour.holdsGame
    var introHold = false       // GameCare.introHold
    var race = false            // a race is running (not the lobby)
    var show = false            // a Show performance
    var volley = false          // a match
    var raceWait = false
    var meal = false            // tray out, walking to it, eating
    var cutscene = false        // arrival, guest, park goodbye / walk-in, fades
    var focus = false           // the close-up
    var nightSkip = false
    var arranging = false       // decor arrange mode
    var settings = false        // Settings, Photo mode, a "?" sheet, any system sheet we know of
    var blocked: Bool { tour || introHold || race || show || volley || raceWait || meal || cutscene || focus || nightSkip || arranging || settings }
}

@MainActor @Observable
final class TipBook {
    static let shared: TipBook = {
        let b = TipBook()
        NotificationCenter.default.addObserver(forName: StartFlow.didWipe, object: nil, queue: .main) { _ in MainActor.assumeIsolated { b.resetFlags() } }          // a wipe already took the flags (the whole defaults domain); this empties the queue too
        return b
    }()

    /// Seconds between a card going and the next one coming.
    static let gap: TimeInterval = 1.5

    nonisolated static func key(_ id: String) -> String { "Jelbies.tip.\(id).v1" }
    nonisolated static let ids = ["feed", "clean", "tricks", "dress", "play", "shop", "town", "spring", "park", "trophies", "race", "show", "volley", "camp", "powerup"]
    nonisolated static var allKeys: [String] { ids.map { key($0) } }

    /// The cards, word for word from the design (the Play card wording is the spec's spare line, "bump" made "bumps").
    static let cards: [TipCard] = [
        TipCard(id: "feed", symbol: "fork.knife", title: "Feeding", body: "Tap a food to put it on the tray. No food? Get some in the Shop."),
        TipCard(id: "clean", symbol: CareMenu.cleanSymbol, title: "Bath time", body: "Scrub, rinse, then rub to shine. Need a hand? Turn on Bath helper in Accessibility."),
        TipCard(id: "tricks", symbol: HUDMenu.symbol(.tricks), title: "Tricks", body: "Tap a trick and your Jelmiko does it. Locked ones are in the Shop."),
        TipCard(id: "dress", symbol: HUDMenu.symbol(.dress), title: "Dress up", body: "Tap Wear to put clothes on. Get more clothes in the Shop."),
        TipCard(id: "play", symbol: HUDMenu.symbol(.play), title: "Play", body: "Pick a toy and flick it. Your Jelmiko bumps it back."),
        TipCard(id: "shop", symbol: "bag.fill", title: "The Shop", body: "Spend JellyCoins on food, clothes and tricks. It all goes to your Bag."),
        TipCard(id: "town", symbol: "door.left.hand.open", title: "Where to?", body: "Race, dance and play to earn JellyCoins. Spend them in the Shop."),
        TipCard(id: "spring", symbol: "drop.fill", title: "The Jelly Spring", body: "Find a kind you love, then tap Pick. Up to three live at home."),
        TipCard(id: "park", symbol: "tree.fill", title: "The Park", body: "Tap a visitor to say hi. Play together to make new friends."),
        TipCard(id: "trophies", symbol: "trophy.fill", title: "Trophies", body: "Win races, shows and volleyball. Every trophy is kept here."),
        TipCard(id: "race", symbol: "flag.checkered", title: "Jelly Race", body: RaceHelp.tip),
        TipCard(id: "show", symbol: HUDMenu.symbol(.tricks), title: "Jelly Show", body: "Dress for today's theme, then dance and do tricks. Tap ? to learn more."),
        TipCard(id: "volley", symbol: UIImage(systemName: "figure.volleyball") != nil ? "figure.volleyball" : "sportscourt.fill", title: "Jelly Volleyball", body: "Tap as the ring closes to hit the ball. Tap ? to learn more."),
        TipCard(id: "camp", symbol: "tent.fill", title: "Jelmiko Camp", body: "When home is full, the others wait here. Tap one to bring them home."),
        TipCard(id: "powerup", symbol: "bolt.fill", title: "Power-up!", body: "Some foods give a boost for a while. The Shop shows each one."),
    ]
    static func card(_ id: String) -> TipCard? { cards.first { $0.id == id } }

    // MARK: state

    /// On screen now (its flag is already written).
    private(set) var current: String?
    /// Waiting, first come first served.
    private(set) var queue: [String] = []
    /// The screens that are open right now.
    private(set) var open: Set<String> = []
    /// The card's frame in window points while it is drawn (the tap-outside check reads it).
    @ObservationIgnored var cardFrame: CGRect = .zero
    /// Landscape "Where to?": the island fills the screen, so the card covers map buttons whatever its place; there only "Got it" takes touches and the rest of the card lets them through to the map.
    @ObservationIgnored var passThrough = false
    @ObservationIgnored var gotItFrame: CGRect = .zero
    /// Screens that hold every card while they are up (Settings, a "?" sheet, Photo mode): `hold("settings", true)`.
    private(set) var holds: Set<String> = []
    func hold(_ k: String, _ on: Bool) { if on { holds.insert(k) } else { holds.remove(k) } }

    @ObservationIgnored var defaults: UserDefaults
    @ObservationIgnored var now: () -> Date = { Date() }
    @ObservationIgnored var context: () -> TipContext = { TipContext() }
    /// True on an iPhone turned to landscape: no card shows there (the map, the Bag's faces and the buttons leave no clear spot). Held cards wait in the queue; iPad is unchanged. Tests set this.
    @ObservationIgnored var landscapePhone: () -> Bool = { TipBook.deviceIsLandscapePhone }
    @MainActor static var deviceIsLandscapePhone: Bool {
        guard UIDevice.current.userInterfaceIdiom == .phone else { return false }
        let w = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap(\.windows).first { $0.isKeyWindow && !($0 is TipWindow) }
        guard let b = w?.bounds else { return false }
        return b.width > b.height
    }
    @ObservationIgnored private var lastEnd: Date?
    @ObservationIgnored private var lastLog = ""
    /// `-TipShow <id>` (dev only): that card ignores its flag and the gap (never the suppression).
    @ObservationIgnored private(set) var forced: String?
    @ObservationIgnored private var pump: Task<Void, Never>?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// `-TipsReset 1` / `-TipShow <id>`: dev-only launch arguments (DevArgs.enabled; the store build strips them anyway).
    nonisolated static func launchOverrides(devArgs: Bool = DevArgs.enabled, defaults d: UserDefaults = .standard) -> (reset: Bool, show: String?) {
        guard devArgs else { return (false, nil) }
        let show = d.string(forKey: "TipShow")
        return (d.integer(forKey: "TipsReset") == 1, (show?.isEmpty ?? true) ? nil : show)
    }

    /// Applied once at launch (the app calls this when the room is built).
    func applyLaunchOverrides(devArgs: Bool = DevArgs.enabled, launch: UserDefaults = .standard) {
        let o = Self.launchOverrides(devArgs: devArgs, defaults: launch)
        if o.reset { resetFlags() }
        forced = o.show
    }

    // MARK: asking

    /// Seconds no tip card shows after the home walkthrough ends.
    nonisolated static let quietAfterTutorial: TimeInterval = 45
    @ObservationIgnored private var quietUntil = Date.distantPast
    /// No card for `seconds` from now (the tutorial just ended: cards are spaced out, never stacked on it).
    func quiet(for seconds: TimeInterval) { quietUntil = max(quietUntil, now().addingTimeInterval(seconds)) }
    /// The tutorial taught this already: the card never shows (its flag is written).
    func markSeen(_ id: String) { defaults.set(true, forKey: Self.key(id)); queue.removeAll { $0 == id } }

    func isSeen(_ id: String) -> Bool { defaults.bool(forKey: Self.key(id)) }

    /// A screen's trigger. Ignored when the flag is set, the id is already queued / up, or `ready` is false (the Camp card waits for somebody to be there).
    func request(_ id: String, when ready: Bool = true) {
        guard ready, Self.card(id) != nil else { return }
        guard forced == id || !isSeen(id) else { return }
        guard current != id, !queue.contains(id) else { return }
        queue.append(id)
        startPump()
    }

    func screenOpened(_ id: String) { open.insert(id) }
    func screenClosed(_ id: String) {
        open.remove(id)
        if current == id { hide() }
    }

    /// Got it, a tap outside, the screen going: the card goes; the next waits `gap`.
    func dismiss() {
        guard current != nil else { return }
        consumeFrame = passThrough ? gotItFrame : cardFrame          // the tap that closed the card ends on the card: a touch that lands there a moment later is eaten by the window, never the control underneath
        consumeUntil = now().addingTimeInterval(Self.consumeGrace)
        hide()
    }
    /// Seconds after a dismissal during which the card's spot still swallows touches.
    nonisolated static let consumeGrace: TimeInterval = 0.5
    @ObservationIgnored var consumeFrame: CGRect = .zero
    @ObservationIgnored var consumeUntil: Date = .distantPast
    /// True when a touch at `p` (window points) must be swallowed by the tip window: on the card, or on the spot a card was just dismissed from.
    func swallows(_ p: CGPoint) -> Bool {
        if current != nil { return (passThrough ? gotItFrame : cardFrame).insetBy(dx: -4, dy: -4).contains(p) }
        return now() < consumeUntil && consumeFrame.insetBy(dx: -4, dy: -4).contains(p)
    }
    private func hide() { current = nil; cardFrame = .zero; lastEnd = now() }

    /// The pump: shows the first queued card whose screen is open (flag written now), or hides the one up when the game becomes busy.
    func tick() {
        let ctx = context()
        if let c = current {
            if ctx.blocked || !holds.isEmpty || !open.contains(c) || landscapePhone() { hide() }          // (turned to landscape on an iPhone: gone, as if tapped outside; its flag was written on appear)
            return
        }
        if DevArgs.enabled, !queue.isEmpty { let line = "queue=\(queue) open=\(open.sorted()) ctx=\(ctx) holds=\(holds.sorted())"; if line != lastLog { lastLog = line; NSLog("[tips] %@", line) } }
        guard !queue.isEmpty, !ctx.blocked, holds.isEmpty, !landscapePhone(), now() >= quietUntil else { return }          // landscape iPhone: the queue holds, no flag is written
        if let last = lastEnd, now().timeIntervalSince(last) < Self.gap, !(queue.first == forced && forced != nil) { return }
        if GameMessageCenter.shared.current != nil { return }          // one place: a tip card waits for the message on the bar (the bar waits for a tip too)
        guard let i = queue.firstIndex(where: { open.contains($0) }) else { return }
        let id = queue.remove(at: i)
        defaults.set(true, forKey: Self.key(id))          // written when the card APPEARS
        current = id
    }

    /// Settings > Show tips again: every tip flag goes, the queue empties. The first-day tour's flag and the close-up hint stay.
    func resetFlags() {
        for k in Self.allKeys { defaults.removeObject(forKey: k) }
        queue.removeAll(); current = nil; cardFrame = .zero; lastEnd = nil
    }

    private func startPump() {
        guard pump == nil else { return }
        pump = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 250_000_000)
                guard let self else { return }
                self.tick()
            }
        }
    }
}

extension TipContext {
    /// The live game's state. Not `tripActive`: the Park and the Camp ARE trips and have cards of their own; only their fades, walk-ins and goodbyes (any phase but playing) are cut-scenes.
    @MainActor static func live(_ c: GameCare) -> TipContext {
        TipContext(tour: FirstDayTour.shared.holdsGame, introHold: GameCare.introHold, race: c.race.active, show: c.show.active, volley: c.volley.active,
                   raceWait: c.raceWait != nil, meal: c.trayOut,
                   cutscene: (c.park.active && c.park.phase != .playing) || c.cafe.active || c.groom.active || c.guestBook.phase != .away || PhotoMode.shared.active,
                   focus: c.focus.isActive, nightSkip: c.nightSkip.active, arranging: c.arranging, settings: false)
    }
}

extension View {
    /// While this view is up no tip card shows (Settings, a "?" sheet).
    func tipHold(_ key: String) -> some View {
        onAppear { TipBook.shared.hold(key, true) }.onDisappear { TipBook.shared.hold(key, false) }
    }
}
