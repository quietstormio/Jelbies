//
//  JelbiesWidgetBundle.swift
//  The Jelbies widget: the Jellies' needs on the Home Screen and Lock Screen. Read-only: it never writes game state.
//

import WidgetKit
import SwiftUI

@main
struct JelbiesWidgetBundle: WidgetBundle {
    var body: some Widget { JelbiesNeedsWidget() }
}

struct JelbiesNeedsWidget: Widget {
    static let kind = "JelbiesNeeds"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: JelbiesProvider()) { entry in
            JelbiesWidgetView(entry: entry)
        }
        .configurationDisplayName("Jelly Needs")
        .description("See how your Jellies are doing, and when they need you.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .accessoryRectangular, .accessoryCircular])
    }
}

struct JelbiesEntry: TimelineEntry {
    let date: Date
    let states: [JellyState]
    let portraits: [Int: UIImage]
}

struct JelbiesWidgetView: View {
    let entry: JelbiesEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        let link = JellyState.neediest(in: entry.states).map { JellyLink.url(for: $0.id) } ?? URL(string: "\(JellyShare.scheme)://")!
        let content = JellyWidgetContent(family: family, states: entry.states, portraits: entry.portraits)
        switch family {
        case .accessoryRectangular, .accessoryCircular:
            content.widgetURL(link).containerBackground(for: .widget) { AccessoryWidgetBackground() }
        default:
            content.widgetURL(link).containerBackground(for: .widget) { WidgetTheme.card }
        }
    }
}
