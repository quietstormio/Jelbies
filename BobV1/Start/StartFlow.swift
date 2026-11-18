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

    var phase: Phase {
        didSet { Self.rememberRoom(phase) }          // (not called for the assignments in `init`, so reading the flag there is safe)
    }
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

    /// Whether the player was in the room when the app last went away (iOS may drop a backgrounded app; the next cold launch then returns to the room instead of the menu).
    static let lastInRoomKey = "Jelbies.lastInRoom.v1"

    /// `.game` sets the flag; the main menu and a new game (`.wiping`) clear it; the other screens (picker, opening, first day) leave it as it was.
    static func rememberRoom(_ p: Phase, _ d: UserDefaults = .standard) {
        switch p {
        case .game: d.set(true, forKey: lastInRoomKey)
        case .menu, .wiping: d.set(false, forKey: lastInRoomKey)
        default: break
        }
    }

    /// The phase a cold launch starts in: the room when there is a save and the player left from the room, else the main menu.
    static func launchPhase(_ d: UserDefaults = .standard) -> Phase {
        hasSave(d) && d.bool(forKey: lastInRoomKey) ? .game : .menu
    }

    init() {
        let d = UserDefaults.standard
        phase = Self.launchPhase(d)
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
        JellyCamp.resumeRelease()          // a "Say goodbye" a kill interrupted is finished before anything reads the save
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
        #if targetEnvironment(simulator)
        applyCampSeed()
        #endif
        applyFavouriteFood(text: UserDefaults.standard.string(forKey: favouriteFoodKey))
        // Not simulator-gated: `-ImportSave 1` merges Documents/import_save.plist (an old save's room) into this game, once (`-ImportSave 0` re-arms). Runs before StoreBook is created.
        ImportSave.apply(arg: UserDefaults.standard.object(forKey: ImportSave.argKey) != nil ? UserDefaults.standard.integer(forKey: ImportSave.argKey) : nil)
        #endif
    }

    #if targetEnvironment(simulator)
    /// `-CampSeed <n>` (simulator only, once per value and NewGame): puts n creatures at Camp through the real purchase path (`placeNew`), so a capture can show the Jelly Spring
    /// and the Town square with Camp partly or fully stocked. Needs a full home (`-NewGame bob,pip,moss`).
    static func applyCampSeed(_ d: UserDefaults = .standard) {
        guard d.object(forKey: "CampSeed") != nil else { return }
        let n = min(max(d.integer(forKey: "CampSeed"), 0), JellyCamp.cap)
        let marker = "\(n)|\(d.string(forKey: newGameAppliedKey) ?? "")"
        guard d.string(forKey: "CampSeed.applied") != marker else { return }
        let species = [3, 4, 5, 6, 0, 1], names = ["Maple", "Biscuit", "Pearl Jr", "Dot", "Rex", "Sunny"]
        for i in 0..<n { _ = placeNew(species: species[i % 6], name: names[i % 6], variant: nil, traits: nil, first: false, d) }
        d.set(marker, forKey: "CampSeed.applied")
    }
    #endif

    static let favouriteFoodKey = "FavouriteFood"

    /// `-FavouriteFood bob:sushi,pip:taco` (development argument, dev-args-gated like `-NewGame`): gives the Jelmiko at home a favourite food by writing the same traits record the Jelly Spring's
    /// `bringHome` writes (a `-NewGame` / `-SetRoster` roster has none, so nothing is a favourite there). Names or ids, food ids as in the store ("sushi", "taco" ...). Idempotent: writing the same
    /// value again changes nothing. Returns how many were written.
    @discardableResult
    static func applyFavouriteFood(text: String?, defaults d: UserDefaults = .standard) -> Int {
        guard let text else { return 0 }
        var n = 0
        for part in text.split(separator: ",") {
            let bits = part.split(separator: ":").map { $0.trimmingCharacters(in: .whitespaces) }
            guard bits.count == 2, let c = JellyRoster.characterID(named: bits[0]), JellyRoster.savedIDs(d).contains(c), Consumables.with(id: bits[1]) != nil else { continue }
            JellyTraitsBook.adopt(c, JellyTraits(personality: .cuddly, jars: [60, 60, 60, 60, 60], snack: bits[1]), d)
            n += 1
        }
        return n
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
        store.starterGiven = true; store.unlistedRefunded = true; store.gardenRefunded = true; store.headbandsRefunded = true
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
        store.starterGiven = true; store.unlistedRefunded = true; store.gardenRefunded = true; store.headbandsRefunded = true
        if let data = try? JSONEncoder().encode(store) { d.set(data, forKey: StoreBook.key) }
        d.removeObject(forKey: firstCoinsKey)
        return pending
    }

    // MARK: moves

    /// Menu: Continue. The roster is the saved one.
    func continueGame() { LaunchTiming.mark("continue tapped"); enterGame() }

    /// A cold launch that resumed straight into the room (no Continue tap): once the logo / intro is gone, the short curtain covers the room building, as after Continue.
    func curtainForResume() { if phase == .game { LaunchGate.shared.hold(.resume) } }

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

    // MARK: Jelmiko Camp (JellyCamp.swift has the rules and the save)

    /// The creature just bought into Camp (home was full): the room it returns to may offer "waiting at Jelmiko Camp" for it. Read-and-clear by the one who shows it.
    var campArrival: Int?
    /// "<name> is at Jelmiko Camp": the one short line the room shows once after a Camp-bound purchase (ContentView draws it; it clears itself).
    var campNote: String?

    /// Jelmiko Camp is a 3D yard visited from the room (a mode of the park trip); there is NO Camp phase. The room's model still exists during a visit, so the moves below only
    /// write the save (kill-safe, JellyCamp.commit). What the visit changed at home is told by ONE pair of calls:
    ///   `campVisitBegan(d)` when the yard is entered (remembers the saved home list), `campVisitEnded(d)` when it is left: true when the home list changed (a bring home, a drop off, a
    ///   swap), and then the room has been rebuilt exactly once (`rebuildRoom`, the way adoption rebuilds it); false = nothing changed and nothing was rebuilt.
    @ObservationIgnored private var campEntryHome: [Int]?
    func campVisitBegan(_ d: UserDefaults = .standard) { campEntryHome = JellyRoster.savedIDs(d) }
    /// Pure part of the hook: did the saved home list change since `entry`? (Order counts: a swap keeps the set of three but changes a slot.)
    static func homeChanged(since entry: [Int]?, _ d: UserDefaults = .standard) -> Bool { entry.map { $0 != JellyRoster.savedIDs(d) } ?? false }
    @discardableResult
    func campVisitEnded(_ d: UserDefaults = .standard) -> Bool {
        let changed = Self.homeChanged(since: campEntryHome, d)
        campEntryHome = nil
        if changed { rebuildRoom() }
        return changed
    }
    /// The room is rebuilt from the saved lists (enterGame, callable): the caller has done `care.leftActive(); voice.training.save(); voice.cancel()`.
    func rebuildRoom() { enterGame() }

    enum CampMove: Equatable { case bringHome(Int), sendToCamp(Int), swap(in: Int, out: Int) }
    /// One move between home and Camp, against the lists saved in `d`: the rule (refused = false, nothing written), the frozen clocks of the one coming home reset to `now`,
    /// and the crash-safe write. Pure of the room: the live flow's `campBringHome` / `campSendToCamp` / `campSwap` call it, tests call it with a suite.
    @discardableResult
    static func campMove(_ move: CampMove, now: Date = Date(), _ d: UserDefaults = .standard) -> Bool {
        let old = JellyCamp.savedLists(d)
        let result: JellyCamp.Lists?
        let coming: Int, going: Int
        switch move {
        case .bringHome(let id): result = JellyCamp.bringHome(id, home: old.home, camp: old.camp); coming = id; going = -1
        case .sendToCamp(let id): result = JellyCamp.sendToCamp(id, home: old.home, camp: old.camp); coming = -1; going = id
        case .swap(let inID, let out): result = JellyCamp.swap(in: inID, out: out, home: old.home, camp: old.camp); coming = inID; going = out
        }
        guard let new = result, JellyCamp.isConsistent(new) else { return false }
        if going >= 0 { JellyCamp.settleCondition(going, now: now, d) }          // the one leaving: its condition decay so far is written in before its clocks stop
        if coming >= 0 { JellyCamp.restamp(coming, now: now, d) }          // the one arriving: its clocks start again from now
        return JellyCamp.commit(from: old, to: new, d)
    }
    /// After a live move: no hot-swap of bodies (the room is rebuilt on Home), a dev `-SetRoster` must not put the old list back, slot-numbered Siri / widget routes are stale,
    /// and nobody "arrives" (the newcomer flags stay off: the arrival would welcome the last slot).
    func afterCampMove() {
        JellyRoster.setRosterSuspended = true
        GameRouter.shared.clearPending()
        GameCare.newcomerPending = false; GameCare.newcomerWithOthers = false
        welcome = nil
    }
    @discardableResult func campBringHome(_ id: Int, now: Date = Date(), defaults d: UserDefaults = .standard) -> Bool { let ok = Self.campMove(.bringHome(id), now: now, d); if ok { afterCampMove() }; return ok }
    @discardableResult func campSendToCamp(_ id: Int, now: Date = Date(), defaults d: UserDefaults = .standard) -> Bool { let ok = Self.campMove(.sendToCamp(id), now: now, d); if ok { afterCampMove() }; return ok }
    @discardableResult func campSwap(in inID: Int, out outID: Int, now: Date = Date(), defaults d: UserDefaults = .standard) -> Bool { let ok = Self.campMove(.swap(in: inID, out: outID), now: now, d); if ok { afterCampMove() }; return ok }
    /// "Say goodbye": the creature at Camp is let go for good (JellyCamp.letGo: marker, 100 coins once, purge). The yard shows the confirmation (press and hold) first.
    @MainActor @discardableResult func campSayGoodbye(_ id: Int, defaults d: UserDefaults = .standard) -> Bool { let ok = JellyCamp.letGo(id, d); if ok { afterCampMove() }; return ok }
    /// Whether a purchase would really have a place right now (home or Camp), read from the save: the Jelly Spring asks BEFORE it takes any coins.
    static func canPlaceNew(_ d: UserDefaults = .standard) -> Bool {
        let l = JellyCamp.savedLists(d)
        return JellyCamp.destination(home: l.home.count, camp: l.camp.count) != .full
    }

    /// A Jelbie of `species` is chosen, named and paid for (`variant` = the Spring colour taken with him, nil = classic): he gets his INSTANCE id (the species id when he is
    /// the first of his kind at home, else a fresh id from the counter: a second Bob is allowed), a fresh start for his state, his colour and name, and joins the roster; then the room.
    /// The species map is written by `allocateInstance` before the roster is saved, so the new id is valid when the roster is read back.
    /// Where a bought creature ended up (`placeNew`).
    struct Placement: Equatable { let id: Int; let destination: JellyCamp.Destination }

    /// The list side of a purchase, against `d`: the creature gets its instance id (allocated against home AND Camp, so a Camp Bob's id is never reused), a fresh start for its
    /// state, colour, traits and name, and joins home (fewer than 3 there) or Camp. nil, and nothing written, when home and Camp are both full.
    static func placeNew(species s: Int, name: String, variant: JellyVariant?, traits: JellyTraits?, first: Bool, _ d: UserDefaults = .standard) -> Placement? {
        var ids = first ? [] : JellyRoster.savedIDs(d)
        let camp = first ? [] : JellyCamp.load(home: ids, d)
        let dest = JellyCamp.destination(home: ids.count, camp: camp.count)
        guard dest != .full else { return nil }
        let id = JellyRoster.allocateInstance(species: s, roster: JellyCamp.owned(home: ids, camp: camp), d)
        resetCharacterState(id, d)          // always: a preview (or an old, released slot) may have left something under his keys
        JellyVariants.adopt(id, variant, d)
        JellyTraitsBook.adopt(id, traits, d)          // his personality, jars and favourite snack (his starting stats seed from it when his profile is first built)
        if dest == .home { ids.append(id); JellyRoster.save(ids, to: d) } else { JellyCamp.addNew(id, camp: camp, d) }
        JellyRoster.setName(id, name, d)
        d.set(true, forKey: startedKey)
        return Placement(id: id, destination: dest)
    }

    func bringHome(species s: Int, name: String, variant: JellyVariant? = nil, traits: JellyTraits? = nil, defaults d: UserDefaults = .standard) {
        let first = phase == .adopt(.first)
        let pendingCoins = DevArgs.enabled ? d.object(forKey: Self.firstCoinsKey) as? Int : nil          // `-NewGame first`: read before the wipe below
        if first { oldSaveSnapshot = nil; if Self.hasSave(d) { Self.wipeAll() } }          // the new game really starts here: the previous save (if any) is replaced now, not when "Start over" was tapped
        JellyRoster.setRosterSuspended = true          // a developer `-SetRoster` must never put the old list back over the roster that now holds him
        guard let placed = Self.placeNew(species: s, name: name, variant: variant, traits: traits, first: first, d) else { enterGame(); return }          // home and Camp are full (the picker does not let it get here)
        let id = placed.id
        if placed.destination == .camp {          // home is full: he stays at Camp. No arrival (the newcomer flags stay off), no stale slot route
            GameRouter.shared.clearPending()
            GameCare.newcomerPending = false; GameCare.newcomerWithOthers = false
            welcome = nil
            campArrival = id
            campNote = SpringStates.roomNote(name: JellyRoster.nameOf(id))
            enterGame()          // back to the room as adoption always does (the home list is unchanged; nobody arrives)
            return
        }
        if DevArgs.enabled { Self.applyPendingFirstCoins(pendingCoins ?? DevArgs.phoneNewGameCoins, first: first, defaults: d) }          // the room's wallet is created after this (it reads the key in init), so it shows the balance at once
        // the first day at home in the REAL room (FirstDayTour.swift); .card = the old illustrated screen
        let room = first && FirstDayStyle.current == .room && FirstDayTour.shared.arm(name: name, replay: false, reduceMotion: A11ySettings.shared.reduceMotion || UIAccessibility.isReduceMotionEnabled)
        GameCare.newcomerPending = true; GameCare.newcomerWithOthers = JellyRoster.savedIDs(d).count > 1 || FirstDayTour.shared.armed          // (others at home, or the tour's run-in: the curtain is held until he is off-screen)
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
    /// With Jelmiko Camp: the same prices while fewer than 3 are home; with home full a new one goes to Camp for what a third costs (800, rare 1,100, special 2,000) until Camp holds
    /// `JellyCamp.cap`; nil when both are full (nothing is bought, nothing is paid).
    static func next(home: Int, camp: Int, rare: Bool = false, special: Bool = false) -> Int? {
        if home < JellyRoster.maxCount { return next(home: home, rare: rare, special: special) }
        guard camp < JellyCamp.cap else { return nil }
        return special ? Self.special : third + (rare ? rareSurcharge : 0)
    }
    static func next(home: Int, rare: Bool = false, special: Bool = false) -> Int? {
        if special { return home < 1 ? 0 : (home < JellyRoster.maxCount ? Self.special : nil) }
        switch home { case ..<1: return 0; case 1: return second + (rare ? rareSurcharge : 0); case 2: return third + (rare ? rareSurcharge : 0); default: return nil }
    }
}

/// "<name> is at Jelmiko Camp": a calm line on the one message bar (UI/GameMessageCenter.swift), then the flow's note is cleared.
struct CampNoteBanner: View {
    let text: String
    var gone: () -> Void
    var body: some View {
        Color.clear.frame(width: 0, height: 0).allowsHitTesting(false).accessibilityHidden(true)
            .onAppear {
                GameMessageCenter.shared.post(text, identifier: "camp-note")
                Task { try? await Task.sleep(nanoseconds: 200_000_000); gone() }
            }
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
        }
        .allowsHitTesting(false)
        .onAppear { up = true; GameMessageCenter.shared.post("Welcome home, \(name)!", identifier: "welcome-home"); Task { try? await Task.sleep(nanoseconds: 3_200_000_000); withAnimation(.easeOut(duration: 0.4)) { gone() } } }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Welcome home, \(name)")
        .transition(.opacity)
    }
}
