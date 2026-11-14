//
//  JelbiesWidgetBundle.swift
//  The Jelbies widget: the Jelbies' needs on the Home Screen, the Lock Screen (circular / rectangular / inline) and in StandBy, plus the
//  Live Activities (race / nap). Read-only apart from the Water button, which only QUEUES a drink (Shared/JellyQuickIntents.swift).
//

import WidgetKit
import SwiftUI

@main
struct JelbiesWidgetBundle: WidgetBundle {
    var body: some Widget {
        JelbiesNeedsWidget()
        JelbiesLiveActivity()
    }
}

struct JelbiesNeedsWidget: Widget {
    static let kind = "JelbiesNeeds"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: JelbiesProvider()) { entry in
            JelbiesWidgetView(entry: entry)
        }
        .configurationDisplayName("Jelmiko")
        .description("See how your Jelmiko are doing, and when they need you.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .accessoryRectangular, .accessoryCircular, .accessoryInline])
        .containerBackgroundRemovable(true)
    }
}

struct JelbiesEntry: TimelineEntry {
    let date: Date
    let states: [JellyState]
    let portraits: [Int: UIImage]
    /// Night (21:00-06:00) or tucked in by "Put my Jelbies to bed".
    var sleeping = false
    /// Queued quick actions (a Water tap waiting for the game to open).
    var queued: [JellyRoute] = []
    var accessory: JellyAccessoryModel { JellyAccessoryModel(states: states, sleeping: sleeping, queued: queued) }
}

struct JelbiesWidgetView: View {
    let entry: JelbiesEntry
    @Environment(\.widgetFamily) private var family
    @Environment(\.showsWidgetContainerBackground) private var showsBackground
    @Environment(\.widgetRenderingMode) private var renderingMode
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let link = JellyState.neediest(in: entry.states).map { JellyLink.url(for: $0.id) } ?? URL(string: "\(JellyShare.scheme)://")!
        switch family {
        case .accessoryCircular:
            JellyCircularView(model: entry.accessory).widgetURL(link).containerBackground(for: .widget) { AccessoryWidgetBackground() }
        case .accessoryRectangular:
            JellyRectangularView(model: entry.accessory).widgetURL(link).containerBackground(for: .widget) { AccessoryWidgetBackground() }
        case .accessoryInline:
            JellyInlineView(model: entry.accessory).widgetURL(link).containerBackground(for: .widget) { EmptyView() }
        default:
            // StandBy (and a Home Screen with the background removed): the night look. Otherwise the usual cream card.
            if !showsBackground, family == .systemSmall || family == .systemMedium {
                JellyStandByView(family: family, model: entry.accessory, tinted: renderingMode == .accented || renderingMode == .vibrant)
                    .widgetURL(link)
                    .containerBackground(for: .widget) { JellyPalette.night }
            } else {
                JellyWidgetContent(family: family, states: entry.states, portraits: entry.portraits, sleeping: entry.sleeping,
                                   showsWater: family != .systemSmall, queued: entry.queued)
                    .widgetURL(link)
                    .containerBackground(for: .widget) { WidgetTheme.card }
            }
        }
    }
}
