//
//  StartFlow.swift
//  The start of the game: which screen the app is on (main menu, Adoption Center, the room), what counts as a save, starting over, and
//  bringing a newly adopted Jelbie home. ContentView draws `phase`; the room (GameScreen) only exists in the `.game` phase, and is rebuilt
//  (new `session`) whenever the roster changed under it, because the roster is fixed per room build (JellyRoster.current).
//
//  Launch flags: -MainMenu 0 (skip the menu: the room, or the Adoption Center when there is no save), -ResetForAdoption 1 (simulator only:
//  wipes everything before launch so the game starts fresh).
//

import SwiftUI
import Observation

@MainActor
@Observable
final class StartFlow {
    static let shared = StartFlow()

    enum AdoptMode: Equatable { case first, more }
    enum Phase: Equatable { case menu, wiping, opening, adopt(AdoptMode), firstDay(Int, String, Bool), game }

    var phase: Phase
    /// Bumped to rebuild the room (GameHost).
    private(set) var session = 0
    /// Settings > Watch the opening: the story, the species picker (a preview) and the first-day scene play over the room and end back in it,
    /// with the save exactly as it was (no roster, coins, names or outfits change; every Jelbie shown is bare).
    var replaying = false
    /// The previews write their Jelbies' needs / stats while they stand on a stage: the keys as they were when the replay began.
    private(set) var replaySnapshot: [String: Any]?
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
        let save = Self.hasSave(d)
        if d.object(forKey: "MainMenu") != nil, d.integer(forKey: "MainMenu") == 0 { phase = save ? .game : .adopt(.first) }
        else { phase = .menu }
        #if targetEnvironment(simulator)
        if d.string(forKey: "PickerMode") == "more" { phase = .adopt(.more) }          // capture aid: the adopt-more picker
        if d.object(forKey: "FirstDayChar") != nil { let c = min(max(d.integer(forKey: "FirstDayChar"), 0), 3); phase = .firstDay(c, JellyRoster.baseNames[c], true) }          // capture aid: the first-day-home beat
        if d.object(forKey: "OpeningBeat") != nil { phase = .opening }                  // capture aid: the opening story at a given beat
        if d.integer(forKey: "OpeningNew") != 0 { phase = .opening }                    // capture aid: a new game's opening, not held (use with -ResetForAdoption 1)
        if d.integer(forKey: "OpeningReplay") != 0, save { replaying = true; replaySnapshot = OpeningStoryView.saveSnapshot(); phase = .opening }          // capture aid: Settings > Watch the opening, straight away
        #endif
    }
    nonisolated deinit {}

    /// Runs before anything reads a save: `-ResetForAdoption 1` (simulator builds only).
    static func applyLaunchArguments() {
        #if targetEnvironment(simulator)
        if UserDefaults.standard.integer(forKey: "ResetForAdoption") != 0 { wipeAll() }
        #endif
    }

    // MARK: moves

    /// Menu: Continue. The roster is the saved one.
    func continueGame() { enterGame() }

    /// Pause card: back to the main menu (the room is dropped; Continue brings it back from the save).
    func returnToMenu() { if phase == .game { phase = .menu } }

    /// Menu: New game / Start. Clears the screen first (so the room stops writing), wipes, then the opening story, then the Adoption Center.
    func startOver() {
        replaying = false; replaySnapshot = nil
        phase = .wiping
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 350_000_000)
            Self.wipeAll()
            phase = .opening
        }
    }

    /// The opening story is over (or skipped): on to the species picker (the cross-fade is the caller's animation). A replay (Settings > Watch the
    /// opening) gets the same picker as a preview: `previewPick` takes its choice on, nothing is saved.
    func finishOpening() {
        guard phase == .opening else { return }
        phase = .adopt(.first)
    }

    /// Settings: play the opening again. The room is dropped like the main menu does (the caller saved first); nothing is wiped or changed,
    /// and the replay ends in `endReplay`, which rebuilds the room from the save.
    func replayOpening() { replaying = true; replaySnapshot = OpeningStoryView.saveSnapshot(); phase = .opening }

    /// A replay's picker: the species chosen and named (nothing paid, nothing saved, nobody renamed) goes on to the first-day scene with THAT species.
    func previewPick(character c: Int, name: String) {
        guard replaying else { return }
        phase = .firstDay(c, name, true)
    }

    /// The replay is over (Skip, Back or the end of the first-day scene): the previews' writes are undone and the room comes back as it was saved.
    func endReplay() {
        if let s = replaySnapshot { OpeningStoryView.restoreSnapshot(s) }
        replaySnapshot = nil
        replaying = false
        enterGame()
    }

    /// The first-adoption picker's back button: to the title menu.
    func backToMenu() { if case .adopt = phase { if replaying { endReplay() } else { phase = .menu } } }

    /// Town: Adoption Center row.
    func openAdoption() { phase = .adopt(.more) }

    /// Back out of adoption (or the cancel button): into the room as it was.
    func cancelAdoption() { enterGame() }

    /// A Jelbie is chosen and named (and paid for): the roster, his name and a fresh start for his state, then the room.
    func bringHome(character c: Int, name: String) {
        if replaying { previewPick(character: c, name: name); return }          // a replay saves nothing
        let first = phase == .adopt(.first)
        var ids = first ? [] : JellyRoster.savedIDs()
        if !ids.contains(c) { Self.resetCharacterState(c) }
        if !ids.contains(c) { ids.append(c) }
        JellyRoster.save(ids)
        JellyRoster.setName(c, name)
        UserDefaults.standard.set(true, forKey: Self.startedKey)
        GameCare.newcomerPending = true
        if first { welcome = nil; phase = .firstDay(c, name, false); return }          // the first day at home says "Welcome home" itself
        welcome = JellyRoster.names[c]
        enterGame()
    }

    /// The first-day-home beat is over (or skipped): into the room. A new game's Jelbie starts fresh again (the preview wrote to his keys).
    func finishFirstDay() {
        guard case .firstDay(let c, _, let replay) = phase else { return }
        if replay { endReplay(); return }
        Self.resetCharacterState(c)
        enterGame()
    }

    private func enterGame() {
        JellyRoster.current = JellyRoster.launchIDs()
        LaunchGate.shared.hold(.resume)          // the short curtain covers the room building
        session += 1
        phase = .game
    }

    // MARK: saves

    /// Everything the app saved (settings of this app's defaults, the old BobSave.json); the Photos album stays.
    static func wipeAll() {
        let introSeen = UserDefaults.standard.bool(forKey: IntroGate.seenKey)
        if let id = Bundle.main.bundleIdentifier { UserDefaults.standard.removePersistentDomain(forName: id) }
        if introSeen { IntroGate.markSeen() }          // starting over does not replay the intro
        try? FileManager.default.removeItem(at: URL.applicationSupportDirectory.appending(path: "BobSave.json"))
        JellyRoster.names = JellyRoster.loadNames()
        JellyRoster.current = [0]
        DecorField.shared.set([])
        DayClock.shared.resetForNewGame()          // Day 1, 8:00
    }

    /// A newcomer starts fresh: whatever a preview (the Adoption Center's stage) saved under his keys goes.
    static func resetCharacterState(_ c: Int, _ d: UserDefaults = .standard) {
        for k in [JellyKeys.needs(c), JellyKeys.grime(c), JellyKeys.words(c), JellyKeys.stats(c), JellyKeys.perks(c)] { d.removeObject(forKey: k) }
    }
}

/// The room, rebuilt per session (the body has no inputs that change otherwise, so SwiftUI does not re-make the game model).
struct GameHost: View {
    let session: Int
    var body: some View { GameScreen().id(session) }
}

/// Adoption prices (Drops). Rationale: a race pays 12-22 for a win, so 120 is about 6-8 wins (a couple of sessions), above the dearest trick page
/// (55) and decor piece (90); the third costs more, so the room fills over weeks. The first Jelbie of a new game is free.
enum AdoptionPrice {
    static let second = 120, third = 180
    /// Cost of the next Jelbie when `home` are in the room (nil = the room is full).
    static func next(home: Int) -> Int? {
        switch home { case ..<1: return 0; case 1: return second; case 2: return third; default: return nil }
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
