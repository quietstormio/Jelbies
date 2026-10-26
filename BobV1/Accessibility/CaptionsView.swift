//
//  CaptionsView.swift
//  Sound captions: the last few sounds as pills under the top bar ("Pip chirps", "Squish"). Posted by AudioHub through `CaptionCenter`.
//  Not an accessibility element (VoiceOver users get announcements instead) and never takes touches.
//

import SwiftUI

struct CaptionsView: View {
    let center: CaptionCenter
    var settings: A11ySettings = .shared

    var body: some View {
        Group {
            if settings.captions { timeline } else { Color.clear }          // no 0.5 s re-render while captions are off
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .accessibilityIdentifier("captions")
    }

    private var timeline: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { ctx in
            let live = center.items.filter { ctx.date.timeIntervalSince($0.born) <= CaptionCenter.life }
            VStack(spacing: 6) {
                if settings.captions {
                    ForEach(live) { c in
                        Label(c.text, systemImage: "speaker.wave.2.fill")
                            .labelStyle(CaptionLabelStyle())
                            .transition(.opacity)
                    }
                }
            }
            .animation(.easeOut(duration: 0.2), value: live.map(\.id))
            .padding(.top, 58)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .dynamicTypeSize(...DynamicTypeSize.accessibility2)
        }
    }
}

private struct CaptionLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 6) {
            configuration.icon.font(.system(size: 12, weight: .bold))
            configuration.title.jFont(15, .bold, relativeTo: .callout)
        }
        .foregroundStyle(Color.white)
        .padding(.horizontal, 14).padding(.vertical, 7)
        .background(Capsule().fill(Color.black.opacity(0.78)))
        .overlay(Capsule().strokeBorder(DT.line, lineWidth: 1))
    }
}
