//
//  JelbiesIntents.swift
//  Siri / Shortcuts (App Intents). Two kinds:
//    - CheckOnJelbies answers WITHOUT opening the game: it reads the snapshot the game last published to the App Group, projects it to now
//      (night hours at half weight, like the widget) and speaks one sentence per Jelbie, with the snippet card (JelbiesSnippetView).
//    - Feed / GiveWater / Goodnight / StartRace open the game (`openAppWhenRun`) and hand GameRouter a route; the game performs it
//      through its normal care flows on the next `apply` (GameScreen), so every lock (tray, bath, focus) still applies.
//  App Shortcuts: every phrase must contain `\(.applicationName)` (Apple rejects phrases without it). The display name is "Jelbies", so they
//  read "... in Jelbies"; INAlternativeAppNames in BobV1-Info.plist lets Siri also accept "My Jelbies" for the app.
//

import AppIntents
import Foundation
import SwiftUI

// MARK: - What Siri reads

/// The Jelbies as Siri sees them: the shared snapshot projected to now, and whether they are asleep (tucked in or the room's night).
nonisolated enum JelbiesSiriStatus {
    struct Report: Sendable {
        var states: [JellyState]
        var sleeping: Bool
        var spoken: String { JellyStatus.spoken(states, sleeping: sleeping) }
        var asleepAnswer: String { JellyStatus.asleepAnswer(states, sleeping: sleeping) }
        var hungryAnswer: String { JellyStatus.hungryAnswer(states, sleeping: sleeping) }
    }
    static func report(directory: URL? = JellyShare.containerURL, now: Date = .now, calendar: Calendar = .current) -> Report {
        let states = JellySnapshot.read(from: directory)?.projectNightAware(at: now, calendar: calendar) ?? []
        let sleeping = Bedtime.isSleeping(at: now, tuckedIn: Bedtime.read(from: directory, now: now), calendar: calendar)
        return Report(states: states, sleeping: sleeping)
    }
}

// MARK: - Check on the Jelbies (no app)

struct CheckOnJelbiesIntent: AppIntent {
    static let title: LocalizedStringResource = "Check on the Jelmiko"
    static let description = IntentDescription("How your Jelmiko are doing right now, without opening the game.")
    static let openAppWhenRun = false

    /// Optional: "How is Lemon" answers for one Jelbie. An id that is not in the snapshot answers for everyone.
    @Parameter(title: "Jelmiko")
    var jelbie: JelbieEntity?

    nonisolated init() {}
    init(jelbie: JelbieEntity?) { self.jelbie = jelbie }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog & ShowsSnippetView {
        var r = JelbiesSiriStatus.report()
        if let id = jelbie?.id {
            let one = r.states.filter { $0.id == id }
            if !one.isEmpty { r.states = one }
        }
        return .result(dialog: IntentDialog(stringLiteral: r.spoken), view: JelbiesSnippetView(states: r.states, sleeping: r.sleeping))
    }
}

// MARK: - Are they asleep? Are they hungry? (no app)

struct AreJelbiesAsleepIntent: AppIntent {
    static let title: LocalizedStringResource = "Are the Jelmiko asleep?"
    static let description = IntentDescription("Whether your Jelmiko are asleep right now, without opening the game.")
    static let openAppWhenRun = false

    nonisolated init() {}

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog & ShowsSnippetView {
        let r = JelbiesSiriStatus.report()
        return .result(dialog: IntentDialog(stringLiteral: r.asleepAnswer), view: JelbiesSnippetView(states: r.states, sleeping: r.sleeping))
    }
}

struct AreJelbiesHungryIntent: AppIntent {
    static let title: LocalizedStringResource = "Are the Jelmiko hungry?"
    static let description = IntentDescription("Whether your Jelmiko want food or water right now, without opening the game.")
    static let openAppWhenRun = false

    nonisolated init() {}

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog & ShowsSnippetView {
        let r = JelbiesSiriStatus.report()
        return .result(dialog: IntentDialog(stringLiteral: r.hungryAnswer), view: JelbiesSnippetView(states: r.states, sleeping: r.sleeping))
    }
}

// MARK: - Open the game and do something

struct FeedJelbieIntent: AppIntent {
    static let title: LocalizedStringResource = "Feed a Jelmiko"
    static let description = IntentDescription("Opens the game and serves a snack (everyone when no Jelmiko is named).")
    static let openAppWhenRun = true

    @Parameter(title: "Jelmiko")
    var jelbie: JelbieEntity?

    nonisolated init() {}
    init(jelbie: JelbieEntity?) { self.jelbie = jelbie }

    static var parameterSummary: some ParameterSummary { Summary("Feed \(\.$jelbie)") }

    @MainActor
    func perform() async throws -> some IntentResult {
        GameRouter.shared.request(.feed(jelbie?.id))
        return .result()
    }
}

struct GiveWaterIntent: AppIntent {
    static let title: LocalizedStringResource = "Give a Jelmiko water"
    static let description = IntentDescription("Opens the game and pours a drink of water (everyone when no Jelmiko is named).")
    static let openAppWhenRun = true

    @Parameter(title: "Jelmiko")
    var jelbie: JelbieEntity?

    nonisolated init() {}
    init(jelbie: JelbieEntity?) { self.jelbie = jelbie }

    static var parameterSummary: some ParameterSummary { Summary("Give \(\.$jelbie) water") }

    @MainActor
    func perform() async throws -> some IntentResult {
        GameRouter.shared.request(.water(jelbie?.id))
        return .result()
    }
}

struct GoodnightJelbiesIntent: AppIntent {
    static let title: LocalizedStringResource = "Put the Jelmiko to bed"
    static let description = IntentDescription("Opens the game, draws the curtains to night and tucks everyone in (the nap card on the Lock Screen).")
    static let openAppWhenRun = true

    nonisolated init() {}

    @MainActor
    func perform() async throws -> some IntentResult {
        GameRouter.shared.request(.bed)
        return .result()
    }
}

struct StartRaceIntent: AppIntent {
    static let title: LocalizedStringResource = "Start Jelly Race"
    static let description = IntentDescription("Opens the game on Jelly Race with that Jelmiko picked.")
    static let openAppWhenRun = true

    @Parameter(title: "Jelmiko")
    var jelbie: JelbieEntity

    nonisolated init() {}
    init(jelbie: JelbieEntity) { self.jelbie = jelbie }

    static var parameterSummary: some ParameterSummary { Summary("Race with \(\.$jelbie)") }

    @MainActor
    func perform() async throws -> some IntentResult {
        GameRouter.shared.request(.race(jelbie.id))
        return .result()
    }
}

// MARK: - App Shortcuts

/// The phrases Siri listens for without any set-up. `\(.applicationName)` is required by Apple in every phrase; with the display name "Jelmiko" they
/// read "Check on my Jelmiko". INAlternativeAppNames (Info.plist) adds "My Jelmiko" as a spoken name for the app.
nonisolated struct JelbiesShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: CheckOnJelbiesIntent(),
            phrases: [
                "How is everyone in \(.applicationName)",
                "Check on \(.applicationName)",
                "How are my \(.applicationName)",
                "How are the \(.applicationName)",
                "What's the status of my \(.applicationName)",
                "\(.applicationName) status",
                "Check on my \(.applicationName)",
                "How is \(\.$jelbie) in \(.applicationName)",
                "Check on \(\.$jelbie) in \(.applicationName)",
            ],
            shortTitle: "Check on the Jelmiko",
            systemImageName: "heart.text.square.fill"
        )
        AppShortcut(
            intent: AreJelbiesAsleepIntent(),
            phrases: [
                "Are my \(.applicationName) asleep",
                "Are the \(.applicationName) asleep",
                "Are my \(.applicationName) sleeping",
                "Are \(.applicationName) asleep",
                "Are my \(.applicationName) awake",
            ],
            shortTitle: "Are they asleep?",
            systemImageName: "moon.zzz.fill"
        )
        AppShortcut(
            intent: AreJelbiesHungryIntent(),
            phrases: [
                "Are my \(.applicationName) hungry",
                "Are the \(.applicationName) hungry",
                "Are \(.applicationName) hungry",
                "Do my \(.applicationName) need food",
                "Are my \(.applicationName) thirsty",
            ],
            shortTitle: "Are they hungry?",
            systemImageName: "fork.knife"
        )
        AppShortcut(
            intent: FeedJelbieIntent(),
            phrases: [
                "Feed \(.applicationName)",
                "Feed my \(.applicationName)",
                "Feed \(\.$jelbie) in \(.applicationName)",
                "Give \(\.$jelbie) a snack in \(.applicationName)",
            ],
            shortTitle: "Feed",
            systemImageName: "fork.knife"
        )
        AppShortcut(
            intent: GiveWaterIntent(),
            phrases: [
                "Give my \(.applicationName) water",
                "Water my \(.applicationName)",
                "Give \(\.$jelbie) water in \(.applicationName)",
                "Give \(\.$jelbie) a drink in \(.applicationName)",
            ],
            shortTitle: "Water",
            systemImageName: "drop.fill"
        )
        AppShortcut(
            intent: GoodnightJelbiesIntent(),
            phrases: [
                "Put my \(.applicationName) to bed",
                "Put the \(.applicationName) to bed",
                "Goodnight \(.applicationName)",
                "Say goodnight in \(.applicationName)",
            ],
            shortTitle: "Goodnight",
            systemImageName: "moon.zzz.fill"
        )
        AppShortcut(
            intent: StartRaceIntent(),
            phrases: [
                "Start a race in \(.applicationName)",
                "Play Jelly Race in \(.applicationName)",
                "Start Jelly Race in \(.applicationName)",
                "Race \(\.$jelbie) in \(.applicationName)",
                "Take \(\.$jelbie) to Jelly Race in \(.applicationName)",
            ],
            shortTitle: "Jelly Race",
            systemImageName: "flag.checkered"
        )
    }

    static let shortcutTileColor: ShortcutTileColor = .teal
}
