//
//  JelbiesIntents.swift
//  Siri / Shortcuts (App Intents). Two kinds:
//    - CheckOnJelbies answers WITHOUT opening the game: it reads the snapshot the game last published to the App Group, projects it to now
//      (night hours at half weight, like the widget) and speaks one sentence per Jelbie, with the snippet card (JelbiesSnippetView).
//    - Feed / GiveWater / Goodnight / StartRace / Train open the game (`openAppWhenRun`) and hand GameRouter a route; the game performs it
//      through its normal care flows on the next `apply` (GameScreen), so every lock (tray, bath, focus) still applies.
//  App Shortcuts: every phrase must contain `\(.applicationName)` (Apple rejects phrases without it). The display name is "Bob" today, so they
//  read "... in Bob"; INAlternativeAppNames in BobV1-Info.plist lets Siri also accept "Jelbies" as the app's name. If the display name becomes
//  Jelbies the phrases follow automatically.
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
    }
    static func report(directory: URL? = JellyShare.containerURL, now: Date = .now, calendar: Calendar = .current) -> Report {
        let states = JellySnapshot.read(from: directory)?.projectNightAware(at: now, calendar: calendar) ?? []
        let sleeping = Bedtime.isSleeping(at: now, tuckedIn: Bedtime.read(from: directory, now: now), calendar: calendar)
        return Report(states: states, sleeping: sleeping)
    }
}

// MARK: - Check on the Jelbies (no app)

struct CheckOnJelbiesIntent: AppIntent {
    static let title: LocalizedStringResource = "Check on the Jelbies"
    static let description = IntentDescription("How your Jelbies are doing right now, without opening the game.")
    static let openAppWhenRun = false

    nonisolated init() {}

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog & ShowsSnippetView {
        let r = JelbiesSiriStatus.report()
        return .result(dialog: IntentDialog(stringLiteral: r.spoken), view: JelbiesSnippetView(states: r.states, sleeping: r.sleeping))
    }
}

// MARK: - Open the game and do something

struct FeedJelbieIntent: AppIntent {
    static let title: LocalizedStringResource = "Feed a Jelbie"
    static let description = IntentDescription("Opens the game and serves a snack (everyone when no Jelbie is named).")
    static let openAppWhenRun = true

    @Parameter(title: "Jelbie")
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
    static let title: LocalizedStringResource = "Give a Jelbie water"
    static let description = IntentDescription("Opens the game and pours a drink of water (everyone when no Jelbie is named).")
    static let openAppWhenRun = true

    @Parameter(title: "Jelbie")
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
    static let title: LocalizedStringResource = "Put the Jelbies to bed"
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
    static let title: LocalizedStringResource = "Start a race"
    static let description = IntentDescription("Opens the game on the Jelly Circuit with that Jelbie picked.")
    static let openAppWhenRun = true

    @Parameter(title: "Jelbie")
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

struct TrainJelbieIntent: AppIntent {
    static let title: LocalizedStringResource = "Train a Jelbie"
    static let description = IntentDescription("Opens the game on training for that Jelbie.")
    static let openAppWhenRun = true

    @Parameter(title: "Jelbie")
    var jelbie: JelbieEntity

    nonisolated init() {}
    init(jelbie: JelbieEntity) { self.jelbie = jelbie }

    static var parameterSummary: some ParameterSummary { Summary("Train \(\.$jelbie)") }

    @MainActor
    func perform() async throws -> some IntentResult {
        GameRouter.shared.request(.train(jelbie.id))
        return .result()
    }
}

// MARK: - App Shortcuts

/// The phrases Siri listens for without any set-up. `\(.applicationName)` is required by Apple in every phrase; with the display name "Bob" they
/// read "Check on the Jelbies in Bob". INAlternativeAppNames (Info.plist) adds "Jelbies" as a spoken name for the app.
nonisolated struct JelbiesShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: CheckOnJelbiesIntent(),
            phrases: [
                "Check on the Jelbies in \(.applicationName)",
                "Check on my Jelbies in \(.applicationName)",
                "How are the Jelbies in \(.applicationName)",
                "How are my Jelbies in \(.applicationName)",
                "How is everyone in \(.applicationName)",
                "Check on \(.applicationName)",
            ],
            shortTitle: "Check on the Jelbies",
            systemImageName: "heart.text.square.fill"
        )
        AppShortcut(
            intent: FeedJelbieIntent(),
            phrases: [
                "Feed the Jelbies in \(.applicationName)",
                "Feed my Jelbies in \(.applicationName)",
                "Feed \(\.$jelbie) in \(.applicationName)",
                "Give \(\.$jelbie) a snack in \(.applicationName)",
            ],
            shortTitle: "Feed",
            systemImageName: "fork.knife"
        )
        AppShortcut(
            intent: GiveWaterIntent(),
            phrases: [
                "Give the Jelbies water in \(.applicationName)",
                "Water my Jelbies in \(.applicationName)",
                "Give \(\.$jelbie) water in \(.applicationName)",
                "Give \(\.$jelbie) a drink in \(.applicationName)",
            ],
            shortTitle: "Water",
            systemImageName: "drop.fill"
        )
        AppShortcut(
            intent: GoodnightJelbiesIntent(),
            phrases: [
                "Put my Jelbies to bed in \(.applicationName)",
                "Put the Jelbies to bed in \(.applicationName)",
                "Goodnight Jelbies in \(.applicationName)",
                "Say goodnight in \(.applicationName)",
            ],
            shortTitle: "Goodnight",
            systemImageName: "moon.zzz.fill"
        )
        AppShortcut(
            intent: StartRaceIntent(),
            phrases: [
                "Start a race in \(.applicationName)",
                "Race \(\.$jelbie) in \(.applicationName)",
                "Take \(\.$jelbie) to the Jelly Circuit in \(.applicationName)",
            ],
            shortTitle: "Race",
            systemImageName: "flag.checkered"
        )
        AppShortcut(
            intent: TrainJelbieIntent(),
            phrases: [
                "Train \(\.$jelbie) in \(.applicationName)",
                "Teach \(\.$jelbie) a trick in \(.applicationName)",
                "Start training in \(.applicationName)",
            ],
            shortTitle: "Train",
            systemImageName: "figure.run"
        )
    }

    static let shortcutTileColor: ShortcutTileColor = .teal
}
