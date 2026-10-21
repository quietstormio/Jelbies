//
//  JellyQuickIntents.swift
//  The interactive widget button (iOS 17+): "Water" queues a drink for a Jelbie in the App Group; the game pours it through the normal
//  tray flow the next time it opens (thirst is restored only when he actually sips, so no game rule is bent). Runs in the widget
//  extension's process, so it lives in Shared/ (the app compiles it too, hidden from Shortcuts).
//  "Pet" is NOT a button: attention comes only from live petting in the close-up, so the widget deep-links (`jelbies://pet/<id>`) instead.
//

import AppIntents
import WidgetKit

nonisolated struct WaterQuickIntent: AppIntent {
    static let title: LocalizedStringResource = "Water a Jelbie"
    static let description = IntentDescription("Queues a drink of water; it is poured when the game opens.")
    static let isDiscoverable = false

    @Parameter(title: "Jelbie")
    var jellyID: Int

    init() { jellyID = 0 }
    init(jellyID: Int) { self.jellyID = jellyID }

    func perform() async throws -> some IntentResult {
        PendingActions.enqueue(.water(jellyID))
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}
