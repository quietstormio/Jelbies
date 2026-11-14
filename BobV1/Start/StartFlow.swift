//
//  StartFlow.swift
//  The start of the game: which screen the app is on (main menu, Adoption Center, the room), what counts as a save, starting over, and
//  bringing a newly adopted Jelbie home. ContentView draws `phase`; the room (GameScreen) only exists in the `.game` phase, and is rebuilt
//  (new `session`) whenever the roster changed under it, because the roster is fixed per room build (JellyRoster.current).
//
//  Starting over: the menu's "Start over" (hold to confirm) and Settings > Reset save only open the opening story and the picker; the old save is wiped
//  when the first Jelbie is chosen and named (`bringHome`), so backing out of the picker keeps it.
//
//  Launch flags (simulator, DEBUG and JELBIES_DEV_ARGS builds only; -NewGame / -ImportSave / -ClearGuest also work in a device Release build made with JELBIES_DEV_ARGS): -MainMenu 0 (skip the menu: the room, or the Adoption Center when there is no save), -ResetForAdoption 1 (simulator only:
//  wipes everything before launch so the game starts fresh).
//

import SwiftUI
import Observation
import WidgetKit
import ActivityKit

@MainActor
@Observable
final class StartFlow {
    static let shared = StartFlow()

    enum AdoptMode: Equatable { case first, more }
    enum Phase: Equatable { case menu, wiping, opening, adopt(AdoptMode), firstDay(Int, String, Bool), game }

    var phase: Phase
    /// Bumped to rebuild the room (GameHost).
    private(set) var session = 0
    /// Settings > Watch the opening: the story plays over the room and ends back in it (no picker, no save changes).
    var replaying = false
    /// Start over: the old save's per-Jelbie keys as they were before the opening / picker previews (which write needs, stats, words...) ran over them.
    /// Put back when the player backs out to the menu; dropped once `bringHome` wipes for real.
    private var oldSaveSnapshot: [String: Any]?
    /// The name of the Jelbie just brought home: the room shows a welcome banner for it.
    var welcome: String?
    /// Photo mode registers the album screen here; the menu's Photos button shows only when it is set.
    static var albumView: (() -> AnyView)?

    static let startedKey = "Jelbies.started.v1"

    /// A save exists: an explicit start flag, or anything an older build saved (a roster, a Drops balance).
    static func hasSave(_ d: UserDefaults = .standard) -> Bool {
        d.bool(forKey: startedKey) || d.object(forKey: JellyRoster.rosterKey) != nil || d.object(forKey: DropsWallet.key) != nil
    }

    init() {
        let d = UserDefaults.standard
        phase = .menu
        #if DEBUG || targetEnvironment(simulator)
        let save = Self.hasSave(d)
        if d.object(forKey: "MainMenu") != nil, d.integer(forKey: "MainMenu") == 0 { phase = save ? .game : .adopt(.first) }
        #endif
        #if targetEnvironment(simulator)
        if d.string(forKey: "PickerMode") == "more" { phase = .adopt(.more) }          // capture aid: the adopt-more picker
        if d.object(forKey: "FirstDayChar") != nil {          // capture aid: the first-day-home beat (the card with that species, or the room's tour over the saved / default room)
            let c = min(max(d.integer(forKey: "FirstDayChar"), 0), 3)
            if FirstDayStyle.current == .card { phase = .firstDay(c, JellyRoster.baseNames[c], true) }
            else { phase = .game; FirstDayTour.shared.arm(name: JellyRoster.nameOf(JellyRoster.savedIDs().first ?? c), replay: true, reduceMotion: false); if d.object(forKey: "FirstDayStep") != nil { FirstDayTour.shared.jump(to: d.integer(forKey: "FirstDayStep")) } }
        }
        if d.object(forKey: "OpeningBeat") != nil { phase = .opening }                  // capture aid: the opening story at a given beat
        #endif
    }
    nonisolated deinit {}

    /// Runs before anything reads a save: `-ResetForAdoption 1` (simulator builds only).
    static func applyLaunchArguments() {
        #if DEBUG || targetEnvironment(simulator)
        if UserDefaults.standard.integer(forKey: "ResetForAdoption") != 0 { wipeAll() }
        #endif
        #if targetEnvironment(simulator)
        if UserDefaults.standard.integer(forKey: "FootCollarOld") != 0 { Skinner.collarCrossing = false }          // capture aid: the old tangent foot collar (before / after stills)
        #endif
        // -ClearGuest / -NewGame / -ImportSave are dev arguments: local Release device installs keep them (JELBIES_DEV_ARGS, set by the Release configuration);
        // the App Store archive clears JELBIES_DEV_ARGS_COND, so they do not exist there.
        #if DEBUG || JELBIES_DEV_ARGS || targetEnvironment(simulator)
        applyClearGuest(arg: UserDefaults.standard.object(forKey: clearGuestKey) != nil ? UserDefaults.standard.integer(forKey: clearGuestKey) : nil)
        // Not simulator-gated (but dev-args-gated): a device dev-args Release build can restart the game with `-NewGame lavender,pearl,teddy [-NewGameCoins 10000]` (once per value).
        applyNewGame(text: UserDefaults.standard.string(forKey: newGameKey),
                     coins: UserDefaults.standard.object(forKey: newGameCoinsKey) != nil ? UserDefaults.standard.integer(forKey: newGameCoinsKey) : 10_000)
        // Not simulator-gated: `-ImportSave 1` merges Documents/import_save.plist (an old save's room) into this game, once (`-ImportSave 0` re-arms). Runs before StoreBook is created.
        ImportSave.apply(arg: UserDefaults.standard.object(forKey: ImportSave.argKey) != nil ? UserDefaults.standard.integer(forKey: ImportSave.argKey) : nil)
        #endif
    }

    static let clearGuestKey = "ClearGuest", clearGuestAppliedKey = "ClearGuest.applied"

    /// `-ClearGuest 1` (device-safe, one-shot): drops a stuck guest visit (`GuestBook.key`, the ONLY thing the invite / visit flow persists) and nothing else:
    /// the park visitors, their friendship and the ledger are the Park's own and stay. The marker is stored in the app domain so a relaunch without the
    /// argument does nothing; `-ClearGuest 0` clears the marker (so a later `-ClearGuest 1` applies again). GuestBook reads its key in init, after this runs,
    /// so there is no in-memory cache to reload. Returns true when it removed the key.
    @discardableResult
    static func applyClearGuest(arg: Int?, defaults d: UserDefaults = .standard) -> Bool {
        guard let arg else { return false }
        if arg == 0 { d.removeObject(forKey: clearGuestAppliedKey); return false }
        guard d.string(forKey: clearGuestAppliedKey) != "1" else { return false }
        d.removeObject(forKey: GuestBook.key)
        d.set("1", forKey: clearGuestAppliedKey)
        return true
    }

    static let newGameKey = "NewGame", newGameCoinsKey = "NewGameCoins", newGameAppliedKey = "NewGame.applied"

    /// `-NewGame a,b,c` (names or ids): wipes everything, saves exactly that roster, sets the JellyCoins balance (DropsWallet.key) and marks the save as started
    /// (the store's one-time starter grant given, the intro seen), so the next screen is the main menu's Continue straight into the room with those Jelbies: no
    /// opening story, no picker, no first-day beat. Applied once per (roster, coins) value: the value is stored under `NewGame.applied` AFTER the wipe (the
    /// launch argument itself lives in the argument domain; this marker is in the app domain), so relaunching with the same arguments changes nothing.
    /// Returns true when it applied.
    @discardableResult
    static func applyNewGame(text: String?, coins: Int, defaults d: UserDefaults = .standard, wipe: (() -> Void)? = nil) -> Bool {
        if text?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "first" { return applyNewGameFirst(coins: coins, defaults: d, wipe: wipe) }
        guard let text, let ids = JellyRoster.parseRoster(text) else { return false }
        let value = "\(ids.map(String.init).joined(separator: ","))|\(coins)"
        guard d.string(forKey: newGameAppliedKey) != value else { return false }
        if let wipe { wipe() } else { wipeAll() }
        JellyRoster.save(ids, to: d)
        d.set(max(coins, 0), forKey: DropsWallet.key)
        var store = StoreBook.Saved()
        store.starterGiven = true; store.unlistedRefunded = true; store.gardenRefunded = true
        if let data = try? JSONEncoder().encode(store) { d.set(data, forKey: StoreBook.key) }
        d.set(true, forKey: startedKey)
        IntroGate.markSeen(d)
        d.set(value, forKey: newGameAppliedKey)
        JellyRoster.names = JellyRoster.loadNames(d)
        JellyRoster.current = ids
        return true
    }

    static let firstCoinsKey = "NewGame.firstCoins"

    /// `-NewGame first`: wipes everything and leaves NO save (no roster, wallet, started flag, store flags, intro-seen), so the next launch is a true first launch (menu without
    /// Continue, intro, opening story, first picker, first-day beat). The wanted balance waits under `NewGame.firstCoins` until the first Jelbie comes home (`applyPendingFirstCoins`).
    /// Applied once per coins value (marker "first|coins"). Returns true when it applied.
    @discardableResult
    static func applyNewGameFirst(coins: Int, defaults d: UserDefaults = .standard, wipe: (() -> Void)? = nil) -> Bool {
        let value = "first|\(coins)|intro2"
        guard d.string(forKey: newGameAppliedKey) != value else { return false }
        if let wipe { wipe() } else { wipeAll() }
        d.removeObject(forKey: IntroGate.seenKey); d.set(true, forKey: IntroGate.pendingKey)          // a genuine first launch: the intro plays again (wipeAll keeps "seen" for the player's own Start over)
        d.set(max(coins, 0), forKey: firstCoinsKey)
        d.set(value, forKey: newGameAppliedKey)
        JellyRoster.names = JellyRoster.loadNames(d)          // wipeAll already reset the in-memory roster (names, species, [0]); with a custom wipe this keeps the same state
        JellyRoster.current = [0]
        return true
    }

    /// The first Jelbie is home and the roster saved: the pending `-NewGame first` balance becomes the wallet (DropsWallet.key) and the pending key goes. The store's one-time 40-Drop
    /// starter is marked given as well, so the room opens with EXACTLY that balance (GameScreen runs `grantStarterIfNeeded` on entering the room). Does nothing unless `first` and pending.
    /// Returns the applied balance (nil = nothing applied).
    @discardableResult
    static func applyPendingFirstCoins(_ pending: Int?, first: Bool, defaults d: UserDefaults = .standard) -> Int? {
        guard first, let pending else { return nil }
        d.set(pending, forKey: DropsWallet.key)
        var store = StoreBook.Saved()
        store.starterGiven = true; store.unlistedRefunded = true; store.gardenRefunded = true
        if let data = try? JSONEncoder().encode(store) { d.set(data, forKey: StoreBook.key) }
        d.removeObject(forKey: firstCoinsKey)
        return pending
    }

    // MARK: moves

    /// Menu: Continue. The roster is the saved one.
    func continueGame() { LaunchTiming.mark("continue tapped"); enterGame() }

    /// Pause card: back to the main menu (the room is dropped; Continue brings it back from the save).
    func returnToMenu() { if phase == .game { FirstDayTour.shared.reset(); phase = .menu } }

    /// Menu: New game / Start (and Settings > Reset save). Clears the screen first (so the room stops writing), then the opening story, then the Adoption Center.
    /// Nothing is wiped here: the old save goes when the first Jelbie is brought home (`bringHome`), so backing out keeps it.
    func startOver() {
        FirstDayTour.shared.reset()
        phase = .wiping
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 350_000_000)
            if Self.hasSave() { oldSaveSnapshot = OpeningStoryView.saveSnapshot() }          // after the room has stopped writing, before the previews start
            phase = .opening
        }
    }

    /// The opening story is over (or skipped) on a new game: on to the species picker (the cross-fade is the caller's animation).
    /// A replay (Settings > Watch the opening) goes back to the room as it was saved instead.
    func finishOpening() {
        guard phase == .opening else { return }
        if replaying {
            replaying = false
            if let c = JellyRoster.savedIDs().first {          // the replay shows the first-day beat with the player's own Jelbie
                if FirstDayStyle.current == .room {          // in the real room: the captions and the coach marks (nobody runs in, nothing is written to the save)
                    FirstDayTour.shared.arm(name: JellyRoster.nameOf(c), replay: true, reduceMotion: A11ySettings.shared.reduceMotion || UIAccessibility.isReduceMotionEnabled)
                    enterGame()
                } else { phase = .firstDay(c, JellyRoster.nameOf(c), true) }
            } else { enterGame() }
        } else { phase = .adopt(.first) }
    }

    /// Settings: play the opening again. The room is dropped like the main menu does (the caller saved first); nothing is wiped or changed,
    /// and `finishOpening` rebuilds the room from the save. No picker.
    func replayOpening() { replaying = true; phase = .opening }

    /// The first-adoption picker's back button: to the title menu.
    func backToMenu() {
        guard case .adopt = phase else { return }
        FirstDayTour.shared.reset()
        if let s = oldSaveSnapshot { OpeningStoryView.restoreSnapshot(s); oldSaveSnapshot = nil }          // the previews' writes go; the old save is as it was
        phase = .menu
    }

    /// Town: Adoption Center row.
    func openAdoption() { phase = .adopt(.more) }

    /// Back out of adoption (or the cancel button): into the room as it was.
    func cancelAdoption() { enterGame() }

    /// A Jelbie of `species` is chosen, named and paid for (`variant` = the Spring colour taken with him, nil = classic): he gets his INSTANCE id (the species id when he is
    /// the first of his kind at home, else a fresh id from the counter: a second Bob is allowed), a fresh start for his state, his colour and name, and joins the roster; then the room.
    /// The species map is written by `allocateInstance` before the roster is saved, so the new id is valid when the roster is read back.
    func bringHome(species s: Int, name: String, variant: JellyVariant? = nil, traits: JellyTraits? = nil) {
        let first = phase == .adopt(.first)
        let pendingCoins = DevArgs.enabled ? UserDefaults.standard.object(forKey: Self.firstCoinsKey) as? Int : nil          // `-NewGame first`: read before the wipe below
        if first { oldSaveSnapshot = nil; if Self.hasSave() { Self.wipeAll() } }          // the new game really starts here: the previous save (if any) is replaced now, not when "Start over" was tapped
        var ids = first ? [] : JellyRoster.savedIDs()
        guard ids.count < JellyRoster.maxCount else { enterGame(); return }          // the room is full (the picker does not let it get here)
        let id = JellyRoster.allocateInstance(species: s, roster: ids)
        Self.resetCharacterState(id)          // always: a preview (or an old, released slot) may have left something under his keys
        JellyVariants.adopt(id, variant)
        JellyTraitsBook.adopt(id, traits)          // his personality, jars and favourite snack (his starting stats seed from it when his profile is first built)
        ids.append(id)
        JellyRoster.setRosterSuspended = true          // a developer `-SetRoster` must never put the old list back over the roster that now holds him
        JellyRoster.save(ids)
        JellyRoster.setName(id, name)
        UserDefaults.standard.set(true, forKey: Self.startedKey)
        if DevArgs.enabled { Self.applyPendingFirstCoins(pendingCoins ?? DevArgs.phoneNewGameCoins, first: first) }          // the room's wallet is created after this (it reads the key in init), so it shows the balance at once
        // the first day at home in the REAL room (FirstDayTour.swift); .card = the old illustrated screen
        let room = first && FirstDayStyle.current == .room && FirstDayTour.shared.arm(name: name, replay: false, reduceMotion: A11ySettings.shared.reduceMotion || UIAccessibility.isReduceMotionEnabled)
        GameCare.newcomerPending = true; GameCare.newcomerWithOthers = ids.count > 1 || FirstDayTour.shared.armed          // (others at home, or the tour's run-in: the curtain is held until he is off-screen)
        if room { welcome = nil; enterGame(); return }          // the tour says "Welcome home" itself
        if first { welcome = nil; phase = .firstDay(id, name, false); return }          // the first day at home says "Welcome home" itself
        welcome = JellyRoster.nameOf(id)
        enterGame()
    }

    /// The first-day-home beat is over (or skipped): into the room. A new game's Jelbie starts fresh again (the preview wrote to his keys).
    func finishFirstDay() {
        guard case .firstDay(let c, _, let replay) = phase else { return }
        if !replay { Self.resetCharacterState(c) }
        enterGame()
    }

    private func enterGame() {
        JellyRoster.current = JellyRoster.launchIDs()
        LaunchGate.shared.hold(.resume)          // the short curtain covers the room building
        session += 1
        phase = .game
    }

    // MARK: saves

    /// Posted after a wipe: observers (JellyNames, ...) drop their in-memory copies of the save.
    static let didWipe = Notification.Name("JelbiesDidWipe")

    /// Everything the app saved: this app's defaults, the old BobSave.json, the App Group files (widget snapshot + portraits), the Photos album,
    /// widget timelines and Live Activities. (The intro-seen flag survives.)
    static func wipeAll() {
        let introSeen = UserDefaults.standard.bool(forKey: IntroGate.seenKey)
        if let id = Bundle.main.bundleIdentifier { UserDefaults.standard.removePersistentDomain(forName: id) }
        if introSeen { IntroGate.markSeen() }          // starting over does not replay the intro
        try? FileManager.default.removeItem(at: URL.applicationSupportDirectory.appending(path: "BobSave.json"))
        let fm = FileManager.default
        if let group = JellyShare.containerURL, let items = try? fm.contentsOfDirectory(at: group, includingPropertiesForKeys: [.isRegularFileKey]) {
            for u in items where (try? u.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true { try? fm.removeItem(at: u) }          // jellies.json, portrait-N.png, the Siri queue (not the group's Library)
        }
        try? fm.removeItem(at: URL.documentsDirectory.appending(path: "Photos", directoryHint: .isDirectory))
        WidgetCenter.shared.reloadAllTimelines()
        let live = Activity<JelbiesActivityAttributes>.activities          // snapshot now: a Live Activity started later must not be ended by this
        Task { for a in live { await a.end(nil, dismissalPolicy: .immediate) } }
        JellyRoster.names = JellyRoster.loadNames()
        JellyRoster.reloadSpecies()          // the duplicates' species map, counter and names died with the domain
        JellyVariants.reload()
        JellyTraitsBook.reload()
        JellyRoster.current = [0]
        DecorField.shared.set([])
        DayClock.shared.resetForNewGame()          // Day 1, 8:00
        GameRouter.shared.clearPending()          // a Siri / widget route asked before "New Game" must not fire on the new game
        NotificationCenter.default.post(name: didWipe, object: nil)
    }

    /// A newcomer starts fresh: whatever a preview (the Adoption Center's stage) saved under his keys goes.
    static func resetCharacterState(_ c: Int, _ d: UserDefaults = .standard) {
        for k in [JellyKeys.needs(c), JellyKeys.grime(c), JellyKeys.words(c), JellyKeys.stats(c), JellyKeys.perks(c)] { d.removeObject(forKey: k) }
        let stats = JellyKeys.stats(c)          // the stats' condition, meal diary and dances live under suffixed keys: a newcomer starts without them too
        for s in [".cond", ".meals", ".dances"] { d.removeObject(forKey: stats + s) }          // (JellyTraits.v1 stays: the seed comes from it when his profile is first built)
    }
}

/// The room, rebuilt per session (the body has no inputs that change otherwise, so SwiftUI does not re-make the game model).
struct GameHost: View {
    let session: Int
    var body: some View { GameScreen().id(session) }
}

/// Adoption prices (Drops). Rationale: a race pays 250-1500 for a win, so the second Jelbie (500) is about two Puddle wins and the third (800) a few more, well above the dearest trick page
/// (55) and decor piece (90), so the room fills over weeks. A rare Jelly Spring colour (an exclusive mutation) costs +300 on top, so the most anyone pays is 1,100. The first Jelbie of a new game is free.
enum AdoptionPrice {
    static let special = 2000
    static let second = 500, third = 800, rareSurcharge = 300
    /// Teddy, Pearl and Panda (Jelly Spring specials): 2,000 JellyCoins each, whichever slot they fill. That is 2.5x the dearest ordinary adoption (800) and 1.8x
    /// the dearest rare colour (1,100): a long saving goal (about 2 Splash wins), so they feel earned. A special never carries a rare colour or the rare surcharge.
    /// Cost of the next Jelbie when `home` are in the room (nil = the room is full); `rare` = the offered colour is a rare mutation (+300; never on the free first gift).
    static func next(home: Int, rare: Bool = false, special: Bool = false) -> Int? {
        if special { return home < 1 ? 0 : (home < JellyRoster.maxCount ? Self.special : nil) }
        switch home { case ..<1: return 0; case 1: return second + (rare ? rareSurcharge : 0); case 2: return third + (rare ? rareSurcharge : 0); default: return nil }
    }
}

/// "Welcome home, Pip!" for a few seconds after an adoption, with hearts rising.
struct WelcomeBanner: View {
    let name: String
    var gone: () -> Void
    @State private var up = false
    var body: some View {
        ZStack {
            ForEach(0..<7, id: \.self) { i in
                Image(systemName: "heart.fill").font(.system(size: CGFloat(16 + (i % 3) * 6), weight: .black)).foregroundStyle(SK.pink)
                    .offset(x: CGFloat(i - 3) * 38, y: up ? -170 - CGFloat(i % 3) * 30 : 20).opacity(up ? 0 : 0.95)
                    .animation(.easeOut(duration: 2.2).delay(Double(i) * 0.1), value: up)
            }
            Text("Welcome home, \(name)!").font(SK.font(22, .black)).foregroundStyle(SK.ink)
                .padding(.horizontal, 20).frame(minHeight: 50).background(Capsule().fill(SK.cream).shadow(color: SK.shadow.opacity(0.25), radius: 8, y: 3))
                .offset(y: -140)
        }
        .allowsHitTesting(false)
        .onAppear { up = true; Task { try? await Task.sleep(nanoseconds: 3_200_000_000); withAnimation(.easeOut(duration: 0.4)) { gone() } } }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Welcome home, \(name)")
        .transition(.opacity)
    }
}
