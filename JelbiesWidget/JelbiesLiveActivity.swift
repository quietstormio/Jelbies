//
//  JelbiesLiveActivity.swift
//  The one ActivityConfiguration (race / nap / pep by `attributes.kind`): the Lock Screen banner and the Dynamic Island compact, minimal and
//  expanded presentations. The views live in Shared/JellyActivityViews.swift so the tests can render them.
//

import WidgetKit
import SwiftUI

struct JelbiesLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: JelbiesActivityAttributes.self) { context in
            JellyActivityLockView(attrs: context.attributes, state: context.state)
                .activityBackgroundTint(JellyPalette.cream)
                .activitySystemActionForegroundColor(JellyPalette.ink)
                .widgetURL(JelbiesLiveActivity.link(context.attributes))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.center) {
                    JellyIslandExpanded(attrs: context.attributes, state: context.state)
                }
            } compactLeading: {
                JellyIslandCompactLeading(attrs: context.attributes, state: context.state)
            } compactTrailing: {
                JellyIslandCompactTrailing(attrs: context.attributes, state: context.state)
            } minimal: {
                JellyIslandMinimal(attrs: context.attributes, state: context.state)
            }
            .widgetURL(JelbiesLiveActivity.link(context.attributes))
            .keylineTint(JellyPalette.body(context.attributes.jellyColor))
        }
    }

    /// Tapping the activity opens the game on that Jelbie (a race: the track).
    static func link(_ a: JelbiesActivityAttributes) -> URL {
        switch a.kind {
        case .race: return JellyRoute.race(a.jellyID).url
        case .pep: return JellyRoute.train(a.jellyID).url
        case .nap: return JellyRoute.jelly(a.jellyID).url
        }
    }
}
