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
    enum Phase: Equatable { case menu, wiping, adopt(AdoptMode), game }

    var phase: Phase
    /// Bumped to rebuild the room (GameHost).
    private(set) var session = 0
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

    /// Menu: New game / Start. Clears the screen first (so the room stops writing), wipes, then the Adoption Center.
    func startOver() {
        phase = .wiping
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 350_000_000)
            Self.wipeAll()
            phase = .adopt(.first)
        }
    }

    /// Town: Adoption Center row.
    func openAdoption() { phase = .adopt(.more) }

    /// Back out of adoption (or the cancel button): into the room as it was.
    func cancelAdoption() { enterGame() }

    /// A Jelbie is chosen and named (and paid for): the roster, his name and a fresh start for his state, then the room.
    func bringHome(character c: Int, name: String) {
        var ids = phase == .adopt(.first) ? [] : JellyRoster.savedIDs()
        if !ids.contains(c) { Self.resetCharacterState(c) }
        if !ids.contains(c) { ids.append(c) }
        JellyRoster.save(ids)
        JellyRoster.setName(c, name)
        UserDefaults.standard.set(true, forKey: Self.startedKey)
        welcome = JellyRoster.names[c]
        GameCare.newcomerPending = true
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
