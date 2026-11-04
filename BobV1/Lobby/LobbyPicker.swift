//
//  LobbyPicker.swift
//  What the competition lobbies (Track, Volleyball, the Studio) share beyond the frame: the per-event colour theme, the Jelbie picker (always three equal rounded tiles) and the
//  stats card (label, bar, value rows). The screens differ in colours and in what they put in the card, never in this layout.
//

import SwiftUI

// MARK: - Theme

/// The colours of one event's lobby. Passed down through the environment so the shared pieces never fork.
struct LobbyTheme {
    var background: Color
    /// Titles and labels sitting on the background.
    var heading: Color
    var subheading: Color
    var card: Color
    /// A selected Jelbie tile: fill and ring.
    var accent: Color
    var accentRing: Color
    var tile: Color
    var primary: Color
    var primaryText: Color
    var secondaryFill: Color
    var secondaryStroke: Color
    var secondaryText: Color

    /// Track: the cream lobby with the honey picks.
    static let cream = LobbyTheme(background: SK.cream, heading: SK.ink, subheading: SK.muted, card: SK.card, accent: SK.honey, accentRing: SK.honeyDeep, tile: Color.white.opacity(0.88),
                                  primary: SK.pinkStrong, primaryText: .white, secondaryFill: Color.white.opacity(0.92), secondaryStroke: SK.ink, secondaryText: SK.ink)
    /// Volleyball: sand and sea (the court art's colours).
    static let beach = LobbyTheme(background: Color(hex: 0xF8ECCB), heading: SK.ink, subheading: SK.muted, card: Color.white.opacity(0.78), accent: Color(hex: 0xBFE4EE), accentRing: Color(hex: 0x2F7FA3),
                                  tile: Color.white.opacity(0.88), primary: Color(hex: 0x276F94), primaryText: .white, secondaryFill: Color.white.opacity(0.92), secondaryStroke: Color(hex: 0x276F94), secondaryText: SK.ink)
    /// The Studio: the purple hall, the cream card, the gold call to action.
    static let studio = LobbyTheme(background: ShowUI.hall, heading: ShowUI.light, subheading: ShowUI.lilacPale, card: SK.cream, accent: ShowUI.gold, accentRing: ShowUI.goldDeep,
                                   tile: SK.cream, primary: ShowUI.gold, primaryText: SK.ink, secondaryFill: SK.cream, secondaryStroke: ShowUI.lilacPale, secondaryText: SK.ink)
}

private struct LobbyThemeKey: EnvironmentKey { static let defaultValue = LobbyTheme.cream }
extension EnvironmentValues {
    var lobbyTheme: LobbyTheme {
        get { self[LobbyThemeKey.self] }
        set { self[LobbyThemeKey.self] = newValue }
    }
}

// MARK: - The Jelbie picker

/// One rounded container (the stats card's radius) split into three equal segments by hairlines, full width and edge to edge: one segment per Jelbie (his whole head, large, and his
/// name). `selected` segments take the theme's accent; spare slots (fewer than three Jelbies) are a faint dashed inset that does nothing. `selectCount` is only the label
/// ("Pick 1" / "Pick 2"): the screen decides what a tap does.
struct LobbyJelbiePicker: View {
    let care: GameCare
    var title: String
    var selected: [Int]
    var selectCount = 1
    var id = "lobby-picker"
    /// The accessibility identifier of a Jelbie's tile.
    var tileID: (JellyProfile) -> String = { "who-\($0.id)" }
    /// Park friends who fill the first spare slots as selected tiles (Volleyball with one Jelbie).
    var friends: [ParkVisitor] = []
    var friendID = "volley-who-friend"
    /// A blocker (the partner rule): replaces the hint in the same fixed slot.
    var blocker: String? = nil
    /// One muted line under the row, and (optional) a small button at its right.
    var footnote: String? = nil
    var footnoteButton: (title: String, id: String, action: () -> Void)? = nil
    /// The first this many spare slots (after the friends) are locked: a lock and `lockedText`.
    var lockedCount = 0
    var lockedText = "Needs a partner"
    var pick: (Int) -> Void
    @Environment(\.lobbyTheme) private var theme
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var rowW: CGFloat = 0
    static let slots = 3
    static let radius: CGFloat = 24
    /// The row never gets wider than this (iPad).
    static let maxRow: CGFloat = 600

    var body: some View {
        let roster: [JellyProfile] = care.jellies.prefix(Self.slots).map { $0 }
        let segW = max((rowW - 2) / 3, 90)
        let portrait = min(segW * 0.74, 140)
        let shape = RoundedRectangle(cornerRadius: Self.radius, style: .continuous)
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center) {          // the same height on every lobby
                Text(title).font(SK.font(17, .black)).foregroundStyle(theme.heading).accessibilityAddTraits(.isHeader)
                Spacer(minLength: 8)
                Text("Pick \(selectCount)").font(SK.font(12.5, .bold)).foregroundStyle(theme.subheading)
            }
            .padding(.horizontal, 2).frame(height: 34)
            HStack(spacing: 0) {
                ForEach(0..<Self.slots, id: \.self) { i in
                    if i > 0 { Rectangle().fill(SK.ink.opacity(0.16)).frame(width: 1) }
                    Group {
                        if i < roster.count { segment(roster[i], portrait: portrait) }
                        else if i - roster.count < friends.count { friendSegment(friends[i - roster.count], index: i - roster.count, portrait: portrait) }
                        else if i - roster.count - friends.count < lockedCount { lockedSegment() }
                        else { emptySegment() }
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .background(theme.tile)
            .clipShape(shape)
            .overlay(shape.strokeBorder(SK.ink.opacity(0.14), lineWidth: 2))
            .frame(maxWidth: Self.maxRow)
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { rowW = $0 }
            // one fixed slot under the strip, on every lobby: the hint, or the blocker in its place (with the way out beside it). Nothing below it ever moves.
            HStack(spacing: 8) {
                Text(blocker ?? footnote ?? " ").font(SK.font(12, .bold)).foregroundStyle(theme.subheading).lineLimit(2).minimumScaleFactor(0.75)
                    .frame(maxWidth: .infinity, alignment: .leading).accessibilityIdentifier("\(id)-note")
                if let b = footnoteButton {
                    Button { AudioHub.shared.uiTap(); b.action() } label: {
                        Text(b.title).font(SK.font(13, .black)).foregroundStyle(.white).lineLimit(1).minimumScaleFactor(0.7).padding(.horizontal, 12).frame(minHeight: 26)
                            .background(Capsule().fill(theme.primary)).frame(minHeight: 44).contentShape(Rectangle())
                    }.buttonStyle(.plain).accessibilityIdentifier(b.id)
                }
            }
            .padding(.horizontal, 2).frame(height: 28)
        }
        .accessibilityElement(children: .contain).accessibilityIdentifier(id)
    }

    private func height(_ portrait: CGFloat) -> CGFloat { portrait + (typeSize.isAccessibilitySize ? 48 : 26) }

    private func highlight(_ on: Bool) -> some View {
        ZStack {
            if on {
                theme.accent
                RoundedRectangle(cornerRadius: Self.radius - 6, style: .continuous).strokeBorder(theme.accentRing, lineWidth: 3).padding(4)
            }
        }
    }

    private func segment(_ j: JellyProfile, portrait: CGFloat) -> some View {
        let on = selected.contains(j.id)
        return Button { AudioHub.shared.uiTap(); pick(j.id) } label: {
            VStack(spacing: 0) {
                JelbiePortrait(care: care, who: j.id, size: portrait, head: true, frameless: true).accessibilityHidden(true)
                Text(j.name).font(SK.font(15.5, .heavy)).foregroundStyle(SK.ink).lineLimit(1).minimumScaleFactor(0.6).padding(.horizontal, 6)
            }
            .padding(.top, 6).padding(.bottom, 8)
            .frame(maxWidth: .infinity, minHeight: height(portrait))
            .background(highlight(on))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(j.name).accessibilityAddTraits(on ? .isSelected : [])
        .accessibilityIdentifier(tileID(j))
    }

    private func friendSegment(_ f: ParkVisitor, index: Int, portrait: CGFloat) -> some View {
        VStack(spacing: 0) {
            JelbiePortrait(care: care, who: care.jellies.first?.id ?? 0, size: portrait, head: true, friend: f, frameless: true).accessibilityHidden(true)
            Text(f.name).font(SK.font(14, .heavy)).foregroundStyle(SK.ink).lineLimit(1).minimumScaleFactor(0.6).padding(.horizontal, 6)
        }
        .padding(.top, 6).padding(.bottom, 8)
        .frame(maxWidth: .infinity, minHeight: height(portrait))
        .background(highlight(true))
        .overlay(alignment: .topTrailing) {
            Text("fills in").font(SK.font(10.5, .black)).foregroundStyle(SK.ink).lineLimit(1).padding(.horizontal, 7).padding(.vertical, 2)
                .background(Capsule().fill(Color.white.opacity(0.9))).padding(.top, 9).padding(.trailing, 9)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Park friend \(f.name), fills in as your teammate").accessibilityAddTraits(.isSelected)
        .accessibilityIdentifier(index == 0 ? friendID : "\(friendID)-\(index)")
    }

    private func lockedSegment() -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: Self.radius - 6, style: .continuous)
                .strokeBorder(theme.subheading.opacity(0.55), style: StrokeStyle(lineWidth: 2, dash: [6, 5]))
            VStack(spacing: 4) {
                Image(systemName: "lock.fill").font(.system(size: 22, weight: .heavy)).foregroundStyle(theme.subheading)
                Text(lockedText).font(SK.font(12.5, .heavy)).foregroundStyle(theme.subheading).multilineTextAlignment(.center).lineLimit(2).minimumScaleFactor(0.7)
            }
            .padding(.horizontal, 10)
        }
        .padding(6)
        .frame(maxWidth: .infinity, minHeight: 100)
        .accessibilityElement(children: .ignore).accessibilityLabel("Locked. \(lockedText)")
        .accessibilityIdentifier("\(id)-locked")
    }

    private func emptySegment() -> some View {
        RoundedRectangle(cornerRadius: Self.radius - 6, style: .continuous)
            .strokeBorder(theme.subheading.opacity(0.35), style: StrokeStyle(lineWidth: 2, dash: [6, 5]))
            .padding(6)
            .frame(maxWidth: .infinity, minHeight: 100)
            .accessibilityHidden(true)
    }
}

// MARK: - The stats card

/// One row: a name, a bar, and a value (a number, or a short note such as the Show's hints).
struct LobbyStatRow: Identifiable {
    var id: String { label }
    var label: String
    var value: Float
    var color: Color
    /// nil: the number 0...100 from `value`.
    var note: String? = nil
}

struct LobbyStatGroup: Identifiable {
    var id: String
    var name: String? = nil
    var rows: [LobbyStatRow] = []
    /// Replaces the rows (the Park friend).
    var custom: AnyView? = nil
}

struct LobbyStatRowView: View {
    let row: LobbyStatRow
    /// Name and number on one line, the bar under them: for three columns.
    var stacked = false
    @Environment(\.dynamicTypeSize) private var typeSize
    @ScaledMetric(relativeTo: .body) private var labelW: CGFloat = 58
    var body: some View {
        if stacked { stackedBody } else { rowBody }
    }
    private var stackedBody: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                Text(row.label).font(SK.font(13, .heavy)).foregroundStyle(SK.ink).lineLimit(1).minimumScaleFactor(0.7)
                Spacer(minLength: 2)
                Text("\(Int((row.value * 100).rounded()))").font(SK.font(13, .black)).foregroundStyle(SK.ink).monospacedDigit()
            }
            LobbyBar(value: row.value, color: row.color, height: 9)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(row.label) \(Int((row.value * 100).rounded())) out of 100")
    }
    private var rowBody: some View {
        HStack(spacing: 8) {
            Text(row.label).font(SK.font(14.5, .heavy)).foregroundStyle(SK.ink).lineLimit(1).minimumScaleFactor(0.7).frame(width: min(labelW, 120), alignment: .leading)
            LobbyBar(value: row.value, color: row.color, height: 10).frame(minWidth: 24)
            if let n = row.note {
                Text(n).font(SK.font(12, .heavy)).foregroundStyle(SK.muted).lineLimit(2).minimumScaleFactor(0.8).fixedSize(horizontal: false, vertical: true)
                    .frame(width: typeSize.isAccessibilitySize ? 120 : 126, alignment: .leading)
            } else {
                Text("\(Int((row.value * 100).rounded()))").font(SK.font(14.5, .black)).foregroundStyle(SK.ink).monospacedDigit().frame(minWidth: 28, alignment: .trailing)
            }
        }
        .frame(minHeight: 22)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(row.label) \(row.note ?? "\(Int((row.value * 100).rounded())) out of 100")")
    }
}

/// The card under the picker: a title (and an optional trailing button), then one or two groups of rows. Two groups sit side by side when they fit, else stacked.
struct LobbyStatsCard<Trailing: View, Footer: View>: View {
    var title: String
    var groups: [LobbyStatGroup]
    var id: String
    let trailing: Trailing
    let footer: Footer
    init(title: String, groups: [LobbyStatGroup], id: String, @ViewBuilder trailing: () -> Trailing = { EmptyView() }, @ViewBuilder footer: () -> Footer = { EmptyView() }) {
        self.title = title; self.groups = groups; self.id = id; self.trailing = trailing(); self.footer = footer()
    }

    private func groupView(_ g: LobbyStatGroup) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            if let n = g.name { Text(n).font(SK.font(15.5, .black)).foregroundStyle(SK.ink).lineLimit(1).accessibilityAddTraits(.isHeader) }
            if let c = g.custom { c } else { ForEach(g.rows) { LobbyStatRowView(row: $0, stacked: groups.count >= 3) } }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .accessibilityElement(children: .contain).accessibilityIdentifier(g.id)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).font(SK.font(19, .black)).foregroundStyle(SK.ink).accessibilityAddTraits(.isHeader)
                Spacer(minLength: 8)
                trailing
            }
            if groups.count > 1 {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: groups.count >= 3 ? 14 : 22) { ForEach(groups) { groupView($0) } }
                    VStack(alignment: .leading, spacing: 14) { ForEach(groups) { groupView($0) } }
                }
            } else if let g = groups.first {
                groupView(g)
            }
            footer
        }
        .lobbyCard()
        .accessibilityElement(children: .contain).accessibilityIdentifier(id)
    }
}
