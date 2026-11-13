//
//  JellyActivityViews.swift
//  The Live Activity faces (race / nap): the Lock Screen banner and the Dynamic Island regions, in the game palette (cream, ink, rounded).
//  The regions are plain named views so the tests can render them on a black pill with ImageRenderer; JelbiesWidget wires them into
//  `DynamicIsland { ... }` (which cannot be rendered outside WidgetKit).
//

import SwiftUI
import WidgetKit

/// The race track: a rounded bar with a tiny Jelbie face riding the progress, lap ticks underneath.
struct RaceTrackBar: View {
    let attrs: JelbiesActivityAttributes
    let state: JelbiesActivityAttributes.ContentState
    var height: CGFloat = 14
    var ink: Color = JellyPalette.ink
    var body: some View {
        GeometryReader { g in
            let w = g.size.width
            let x = min(max(CGFloat(state.progress), 0), 1) * (w - height) + height / 2
            ZStack(alignment: .leading) {
                Capsule().fill(ink.opacity(0.12)).frame(height: height)
                Capsule().fill(JellyPalette.solid(attrs.jellyColor)).frame(width: max(height, x + height / 2), height: height)
                // lap ticks
                ForEach(1..<max(state.laps, 1), id: \.self) { i in
                    Rectangle().fill(ink.opacity(0.35)).frame(width: 2, height: height * 0.6)
                        .offset(x: CGFloat(i) / CGFloat(state.laps) * (w - height) + height / 2 - 1)
                }
                Image(systemName: "flag.checkered").font(.system(size: height * 0.7, weight: .bold)).foregroundStyle(ink.opacity(0.7))
                    .offset(x: w - height * 0.9)
                JellyFaceGlyph(color: attrs.jellyColor, mood: state.phase == .finished && (state.place ?? 1) == 1 ? .happy : .okay)
                    .frame(width: height * 1.9, height: height * 1.9)
                    .offset(x: x - height * 0.95, y: -height * 0.35)
            }
        }
        .frame(height: height * 1.9)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Jelly Race progress")
        .accessibilityValue("\(JelbiesActivityAttributes.ContentState.ordinal(state.position)) of \(state.racers), \(Int((min(max(state.progress, 0), 1) * 100).rounded())) percent")
    }
}

/// The Lock Screen / banner presentation.
struct JellyActivityLockView: View {
    let attrs: JelbiesActivityAttributes
    let state: JelbiesActivityAttributes.ContentState
    /// Lets the capture tests freeze the Z drift.
    var zPhase: Double = 0

    var body: some View {
        HStack(spacing: 14) {
            leadingFace(size: 58)
            VStack(alignment: .leading, spacing: 4) {
                FitHeadline(attrs: attrs, state: state, size: 18, color: JellyPalette.ink)
                switch attrs.kind {
                case .race:
                    Text(attrs.detail(state, roundedWake: true)).font(JellyPalette.font(13, .semibold)).foregroundStyle(JellyPalette.inkSoft).lineLimit(1)
                    RaceTrackBar(attrs: attrs, state: state).padding(.top, 2)
                case .nap:
                    HStack(spacing: 6) {
                        Image(systemName: "moon.zzz.fill").font(.system(size: 12, weight: .bold)).foregroundStyle(JellyPalette.inkSoft)
                        Text(attrs.detail(state, roundedWake: true)).font(JellyPalette.font(13, .semibold)).foregroundStyle(JellyPalette.inkSoft).lineLimit(1)
                    }
                    if state.phase == .sleeping, state.sleepers.count > 1 {
                        HStack(spacing: 5) {
                            ForEach(Array(state.sleepers.enumerated()), id: \.offset) { i, n in
                                Text(n).font(JellyPalette.font(11, .semibold)).foregroundStyle(JellyPalette.ink.opacity(0.85))
                                    .lineLimit(1).minimumScaleFactor(0.6).truncationMode(.tail)
                                    .padding(.horizontal, 7).padding(.vertical, 2).background(Capsule().fill(JellyPalette.backing(state.sleeperColor(i), 0.4)))
                                    .layoutPriority(Double(n.count))
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            trailingBadge
        }
        .padding(16)
    }

    @ViewBuilder private func leadingFace(size: CGFloat) -> some View {
        ZStack(alignment: .topTrailing) {
            ZStack {
                Circle().fill(JellyPalette.backing(attrs.jellyColor, 0.28)).frame(width: size, height: size)
                if attrs.kind == .nap, state.phase == .sleeping || state.phase == .awake, state.sleepers.count > 1 {
                    HStack(spacing: -size * 0.22) {
                        ForEach(Array(state.sleepers.prefix(3).enumerated()), id: \.offset) { i, _ in
                            JellyFaceGlyph(color: state.sleeperColor(i), mood: state.phase == .sleeping ? .sleeping : .happy).frame(width: size * 0.5, height: size * 0.5)
                        }
                    }
                } else {
                    JellyFaceGlyph(color: attrs.jellyColor, mood: faceMood).frame(width: size * 0.8, height: size * 0.8)
                }
            }
            if attrs.kind == .nap, state.phase == .sleeping { SleepZs(size: 12, color: JellyPalette.bodyDeep(attrs.jellyColor), phase: zPhase).offset(x: 10, y: -8) }
        }
    }

    private var faceMood: JellyFaceMood {
        switch (attrs.kind, state.phase) {
        case (.nap, .sleeping): return .sleeping
        case (.race, .finished): return (state.place ?? 1) <= 3 ? .happy : .okay
        default: return .happy
        }
    }

    @ViewBuilder private var trailingBadge: some View {
        switch (attrs.kind, state.phase) {
        case (.race, .running):
            VStack(spacing: 0) {
                Text(JelbiesActivityAttributes.ContentState.ordinal(state.position)).font(JellyPalette.font(24)).foregroundStyle(JellyPalette.ink)
                Text("of \(state.racers)").font(JellyPalette.font(11, .semibold)).foregroundStyle(JellyPalette.inkSoft)
            }
        case (.race, .finished):
            Text(JelbiesActivityAttributes.ContentState.medal(state.place ?? state.position)).font(.system(size: 34))
        case (.nap, .sleeping):
            Image(systemName: "moon.stars.fill").font(.system(size: 24, weight: .bold)).foregroundStyle(JellyPalette.bodyDeep("yellow"))
        case (.nap, _):
            Image(systemName: "sun.max.fill").font(.system(size: 26, weight: .bold)).foregroundStyle(JellyPalette.bodyDeep("yellow"))
        default: EmptyView()
        }
    }
}

// MARK: - Dynamic Island regions

/// Compact leading: the Jelbie's face (sleeping / racing / tired).
struct JellyIslandCompactLeading: View {
    let attrs: JelbiesActivityAttributes
    let state: JelbiesActivityAttributes.ContentState
    var body: some View {
        JellyFaceGlyph(color: attrs.jellyColor, mood: attrs.kind == .nap && state.phase == .sleeping ? .sleeping : JellyFaceMood.happy, ink: .white)
            .frame(width: 22, height: 22)
            .padding(.leading, 2)
    }
}

/// Compact trailing: the position ("2nd") or Zs.
struct JellyIslandCompactTrailing: View {
    let attrs: JelbiesActivityAttributes
    let state: JelbiesActivityAttributes.ContentState
    var body: some View {
        switch (attrs.kind, state.phase) {
        case (.race, .finished): Text(JelbiesActivityAttributes.ContentState.medal(state.place ?? state.position)).font(.system(size: 15))
        case (.race, _): Text(JelbiesActivityAttributes.ContentState.ordinal(state.position)).font(JellyPalette.font(14)).foregroundStyle(JellyPalette.body(attrs.jellyColor))
        case (.nap, .sleeping): Text("zZ").font(JellyPalette.font(14)).foregroundStyle(JellyPalette.moon)
        case (.nap, _): Image(systemName: "sun.max.fill").font(.system(size: 13, weight: .bold)).foregroundStyle(JellyPalette.moon)
        }
    }
}

/// Minimal: just the face.
struct JellyIslandMinimal: View {
    let attrs: JelbiesActivityAttributes
    let state: JelbiesActivityAttributes.ContentState
    var body: some View {
        JellyFaceGlyph(color: attrs.jellyColor, mood: attrs.kind == .nap && state.phase == .sleeping ? .sleeping : .happy, ink: .white).frame(width: 22, height: 22)
    }
}

/// Expanded: face on the left, headline + detail in the centre, the track / Zs along the bottom. White on the Island's black.
struct JellyIslandExpanded: View {
    let attrs: JelbiesActivityAttributes
    let state: JelbiesActivityAttributes.ContentState
    var zPhase: Double = 0
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 12) {
                ZStack(alignment: .topTrailing) {
                    ZStack {
                        Circle().fill(JellyPalette.body(attrs.jellyColor).opacity(0.25)).frame(width: 46, height: 46)
                        JellyFaceGlyph(color: attrs.jellyColor, mood: attrs.kind == .nap && state.phase == .sleeping ? .sleeping : .happy, ink: .white).frame(width: 38, height: 38)
                    }
                    if attrs.kind == .nap, state.phase == .sleeping { SleepZs(size: 10, color: JellyPalette.moon, phase: zPhase).offset(x: 8, y: -6) }
                }
                VStack(alignment: .leading, spacing: 2) {
                    FitHeadline(attrs: attrs, state: state, size: 17, color: .white)
                    Text(attrs.detail(state, roundedWake: true)).font(JellyPalette.font(13, .semibold)).foregroundStyle(.white.opacity(0.7)).lineLimit(1)
                }
                Spacer(minLength: 0)
                switch (attrs.kind, state.phase) {
                case (.race, .running):
                    Text(JelbiesActivityAttributes.ContentState.ordinal(state.position)).font(JellyPalette.font(26)).foregroundStyle(JellyPalette.body(attrs.jellyColor))
                case (.race, .finished):
                    Text(JelbiesActivityAttributes.ContentState.medal(state.place ?? state.position)).font(.system(size: 30))
                case (.nap, .sleeping):
                    Image(systemName: "moon.stars.fill").font(.system(size: 22, weight: .bold)).foregroundStyle(JellyPalette.moon)
                default: EmptyView()
                }
            }
            if attrs.kind == .race { RaceTrackBar(attrs: attrs, state: state, height: 12, ink: .white) }
        }
        .padding(.horizontal, 6).padding(.vertical, 4)
    }
}

/// The activity headline on one line: the longest wording that fits (full, then without the course / the "JellyCoins" word), then scaled down.
struct FitHeadline: View {
    let attrs: JelbiesActivityAttributes
    let state: JelbiesActivityAttributes.ContentState
    var size: CGFloat = 18
    var color: Color = JellyPalette.ink
    var body: some View {
        let c = attrs.headlineCandidates(state)
        ViewThatFits(in: .horizontal) {
            line(c[0]).fixedSize(horizontal: true, vertical: false)
            line(c[1]).fixedSize(horizontal: true, vertical: false)
            line(c[2]).fixedSize(horizontal: true, vertical: false)
            line(c[3]).minimumScaleFactor(0.6).truncationMode(.tail)
        }
        .accessibilityLabel(c[0])
    }
    private func line(_ t: String) -> some View { Text(t).font(JellyPalette.font(size)).foregroundStyle(color).lineLimit(1) }
}
