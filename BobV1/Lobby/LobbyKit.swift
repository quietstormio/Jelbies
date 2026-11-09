//
//  LobbyKit.swift
//  The shared pieces of the Volleyball and Track lobbies, built to the lobby mockups (lobby.html): the header, the carousel card, the info pills, the stat bars,
//  the option rows, the chips, the pinned Train / Play bar, the pep dots and the sheet (Training, How to play). Sizes, weights and radii are the mockup's
//  px = pt on a 440 x 956 phone; text is SK.font so it follows Dynamic Type.
//

import SwiftUI
import UIKit

// MARK: - iPad readable width

/// iPad only: a readable column width for lobby content, cards and sheets (the phone layouts were drawn for 440 pt). On iPhone it is no limit at all.
enum PadLayout {
    static let isPad = UIDevice.current.userInterfaceIdiom == .pad
    static let column: CGFloat = 700
    static var maxColumn: CGFloat { isPad ? column : .infinity }
    /// iPad lobbies: wide enough for five course cards in one row.
    static let wideColumn: CGFloat = 860
}

extension View {
    /// iPad only: hides the status bar (its clock would sit over the score pill / a Jelbie in landscape play). A no-op on iPhone.
    @ViewBuilder func padStatusBarHidden(_ hidden: Bool) -> some View {
        if PadLayout.isPad { statusBarHidden(hidden) } else { self }
    }

    /// Caps the width to `PadLayout.column` (iPad) and centres it; a no-op on iPhone.
    @ViewBuilder func padColumn(_ width: CGFloat = PadLayout.column) -> some View {
        if PadLayout.isPad { frame(maxWidth: width).frame(maxWidth: .infinity) } else { self }
    }
}

// MARK: - Screen frame

/// Header on top, a scrolling body (one column in portrait; two in landscape), the muted reason line and the pinned bottom bar.
struct LobbyScreen<Left: View, Right: View, Bar: View>: View {
    let header: AnyView
    var why: String?
    var whyID: String
    let left: Left
    let right: Right
    let bar: Bar
    @Environment(\.verticalSizeClass) private var vsc
    @Environment(\.lobbyTheme) private var theme
    /// The portrait height of the place picker (a carousel with its info line, or the Studio's stage).
    static var placeHeight: CGFloat { 254 }

    init(header: AnyView, why: String?, whyID: String, @ViewBuilder left: () -> Left, @ViewBuilder right: () -> Right, @ViewBuilder bar: () -> Bar) {
        self.header = header; self.why = why; self.whyID = whyID; self.left = left(); self.right = right(); self.bar = bar()
    }

    /// One line, always reserved (empty when there is no blocker), so the bar and everything above it never move between states.
    private var whyLine: some View {
        Group {
            if let why { Text(why).font(SK.font(12, .bold)).foregroundStyle(theme.subheading).lineLimit(1).minimumScaleFactor(0.7).accessibilityIdentifier(whyID) }
            else { Text(" ").font(SK.font(12, .bold)).accessibilityHidden(true) }
        }
        .frame(maxWidth: .infinity, alignment: .leading).padding(.bottom, 8)
    }

    var body: some View {
        Group {
            if vsc == .compact {
                VStack(spacing: 0) {
                    header.padding(.top, 10).padding(.bottom, 8)
                    HStack(alignment: .top, spacing: 16) {
                        VStack(spacing: 0) {
                            ScrollView { VStack(alignment: .leading, spacing: 0) { left }.frame(maxWidth: .infinity, alignment: .leading) }.scrollBounceBehavior(.basedOnSize)
                            VStack(spacing: 0) { whyLine; bar }.padding(.top, 6).modifier(BarBand())
                        }
                        ScrollView { VStack(spacing: 10) { right }.frame(maxWidth: .infinity) }.scrollBounceBehavior(.basedOnSize)
                    }
                    .padding(.bottom, 2)
                }
            } else if PadLayout.isPad {
                VStack(spacing: 0) {
                    header.padding(.top, 8).padding(.horizontal, 16)
                    ViewThatFits(in: .vertical) {
                        // everything fits: the content sits right under the header with the bar just below it (no empty band above the content)
                        VStack(spacing: 0) {
                            VStack(alignment: .leading, spacing: 0) {
                                left.frame(maxWidth: .infinity, minHeight: Self.placeHeight, alignment: .topLeading)
                                right
                            }
                            .padding(.horizontal, 16).padding(.top, 18).padding(.bottom, 20)
                            VStack(spacing: 0) { whyLine; bar }.padding(.horizontal, 16).padding(.top, 4).padding(.bottom, 6)
                            Spacer(minLength: 0)
                        }
                        // too tall (landscape iPad, big text): scroll the body, bar pinned
                        VStack(spacing: 0) {
                            ScrollView {
                                VStack(alignment: .leading, spacing: 0) {
                                    left.frame(maxWidth: .infinity, minHeight: Self.placeHeight, alignment: .topLeading)
                                    right
                                }
                                .padding(.horizontal, 16).padding(.top, 6).padding(.bottom, 8)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .scrollBounceBehavior(.basedOnSize)
                            VStack(spacing: 0) { whyLine; bar }.padding(.horizontal, 16).padding(.top, 4).padding(.bottom, 6).modifier(BarBand())
                        }
                    }
                    .frame(maxHeight: .infinity)
                }
                .padColumn(PadLayout.wideColumn)
            } else {
                VStack(spacing: 0) {
                    header.padding(.top, 8).padding(.horizontal, 16)
                    ScrollView {
                        VStack(alignment: .leading, spacing: 0) {
                            left.frame(maxWidth: .infinity, minHeight: Self.placeHeight, alignment: .topLeading)          // the place picker has the same height on every lobby, so the Jelbie picker below sits at the same y
                            right
                        }
                        .padding(.horizontal, 16).padding(.top, 6).padding(.bottom, 8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .scrollBounceBehavior(.basedOnSize)
                    VStack(spacing: 0) { whyLine; bar }.padding(.horizontal, 16).padding(.top, 4).padding(.bottom, 6).modifier(BarBand())
                }
                .padColumn()
            }
        }
        .background(theme.background.ignoresSafeArea())
    }
}

/// The pinned bar's own cream band (it reaches the bottom edge) with a soft fade above it, so scrolled content never pokes out over the buttons.
private struct BarBand: ViewModifier {
    @Environment(\.lobbyTheme) private var theme
    func body(content: Content) -> some View {
        content
            .background(alignment: .bottom) { theme.background.ignoresSafeArea(edges: .bottom) }
            .overlay(alignment: .top) {
                LinearGradient(colors: [theme.background.opacity(0), theme.background], startPoint: .top, endPoint: .bottom).frame(height: 18).offset(y: -18).allowsHitTesting(false)
            }
    }
}

// MARK: - Header

struct LobbyHeader: View {
    let title: String
    let wallet: DropsWallet
    let backID: String, helpID: String
    var back: () -> Void
    var help: () -> Void
    /// The gear next to the ?: a screen with options (the Volleyball's) opens them here, and nowhere else.
    var optionsID: String? = nil
    var options: (() -> Void)? = nil
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.lobbyTheme) private var theme
    private var backButton: some View {
        Button { AudioHub.shared.uiTap(); back() } label: {
            LobbyIcon(kind: .back).frame(width: 44, height: 44).background(Circle().fill(Color.white.opacity(0.85)))
        }.buttonStyle(.plain).accessibilityLabel("Back").accessibilityIdentifier(backID)
    }
    private var helpButton: some View {
        Button { AudioHub.shared.uiTap(); help() } label: {
            Text("?").font(SK.font(16, .black)).foregroundStyle(theme.subheading).frame(width: 30, height: 30).background(Circle().fill(theme.heading.opacity(0.12)))
                .frame(width: 44, height: 44).contentShape(Circle())
        }.buttonStyle(.plain).padding(-7).accessibilityLabel("How to play").accessibilityIdentifier(helpID)
    }
    @ViewBuilder private var optionsButton: some View {
        if let options, let optionsID {
            Button { AudioHub.shared.uiTap(); options() } label: {
                Image(systemName: "gearshape.fill").font(.system(size: 14, weight: .black)).foregroundStyle(theme.subheading).frame(width: 30, height: 30).background(Circle().fill(theme.heading.opacity(0.12)))
                    .frame(width: 44, height: 44).contentShape(Circle())
            }.buttonStyle(.plain).padding(-7).accessibilityLabel("Options").accessibilityIdentifier(optionsID)
        }
    }
    private var titleText: some View { Text(title).font(SK.font(30, .black)).foregroundStyle(theme.heading).accessibilityAddTraits(.isHeader) }
    var body: some View {
        if typeSize.isAccessibilitySize {
            // big text: the title gets a line of its own
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 10) { backButton; helpButton; optionsButton; Spacer(minLength: 0); DropsPill(wallet: wallet, lobby: true) }
                titleText.lineLimit(2).minimumScaleFactor(0.6)
            }
        } else {
            HStack(spacing: 10) {
                backButton
                titleText.lineLimit(1).minimumScaleFactor(0.6)
                helpButton.offset(y: 2)
                optionsButton.offset(y: 2)
                Spacer(minLength: 0)
                DropsPill(wallet: wallet, lobby: true)
            }
            .frame(minHeight: 52)
        }
    }
}

private struct LobbyCardStyle: ViewModifier {
    let padding: EdgeInsets
    @Environment(\.lobbyTheme) private var theme
    func body(content: Content) -> some View {
        content.padding(padding).frame(maxWidth: .infinity, alignment: .leading).background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(theme.card))
    }
}

// MARK: - Labels, cards, pills

/// "Court" ... "1 of 4 open".
struct LobbyLabelRow: View {
    let title: String, trailing: String
    @Environment(\.lobbyTheme) private var theme
    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(SK.font(17, .black)).foregroundStyle(theme.heading).accessibilityAddTraits(.isHeader)
            Spacer()
            Text(trailing).font(SK.font(12.5, .bold)).foregroundStyle(theme.subheading)
        }
        .padding(.horizontal, 2).padding(.bottom, 8)
    }
}

extension View {
    /// The mockups' white card: radius 24.
    func lobbyCard(padding: EdgeInsets = EdgeInsets(top: 12, leading: 14, bottom: 12, trailing: 14)) -> some View {
        modifier(LobbyCardStyle(padding: padding))
    }
}

/// A carousel card (a court, a course): 150 wide, art 94 tall, name and subtitle; selected = honey with a check, locked = faded art and a lock.
struct LobbyCarouselCard<Art: View>: View {
    let name: String, sub: String
    var selected = false, locked = false
    var artH: CGFloat = 94
    let art: Art
    @ScaledMetric(relativeTo: .body) private var scaledW: CGFloat = 150
    init(name: String, sub: String, selected: Bool = false, locked: Bool = false, artH: CGFloat = 94, @ViewBuilder art: () -> Art) {
        self.name = name; self.sub = sub; self.selected = selected; self.locked = locked; self.artH = artH; self.art = art()
    }
    var body: some View {
        let w = min(scaledW, 230)
        VStack(alignment: .leading, spacing: 0) {
            ZStack {
                art.saturation(locked ? 0.15 : 1).opacity(locked ? 0.5 : 1)
                if selected {
                    LobbyIcon(kind: .check, size: 22).frame(width: 22, height: 22).background(Circle().fill(SK.ink)).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing).padding(5)
                }
                if locked { LobbyIcon(kind: .lock, color: SK.ink.opacity(0.5), size: 32).frame(width: 32, height: 32).background(Circle().fill(Color.white.opacity(0.92))) }
            }
            .frame(height: (w - 16) * artH / 134)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            Text(name).font(SK.font(15.5, .black)).foregroundStyle(locked ? SK.muted : SK.ink).lineLimit(1).minimumScaleFactor(0.6).padding(.top, 7).padding(.horizontal, 2)
            Text(sub).font(SK.font(12, .bold)).foregroundStyle(SK.muted).lineLimit(2).fixedSize(horizontal: false, vertical: true).padding(.top, 1).padding(.horizontal, 2)
            Spacer(minLength: 0)
        }
        .padding(EdgeInsets(top: 8, leading: 8, bottom: 10, trailing: 8))
        .frame(width: w, alignment: .topLeading)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(selected ? SK.honey : Color.white.opacity(locked ? 0.5 : 0.88)))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(selected ? SK.honeyDeep : .clear, lineWidth: 2))
    }
}

/// The horizontally scrolling row of cards. `bleed`: runs off the right edge of the screen (portrait, inside a 16 pt page margin).
struct LobbyCarousel<Content: View>: View {
    var bleed = true
    var scrollTo: String?
    let content: Content
    init(bleed: Bool = true, scrollTo: String? = nil, @ViewBuilder content: () -> Content) { self.bleed = bleed; self.scrollTo = scrollTo; self.content = content() }
    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 10) { content }
                    .padding(.horizontal, bleed ? 16 : 0).padding(.vertical, 2).fixedSize(horizontal: false, vertical: true)
            }
            .scrollBounceBehavior(.basedOnSize)
            .padding(.horizontal, bleed ? -16 : 0)
            .onAppear { if let id = scrollTo { proxy.scrollTo(id, anchor: .center) } }
        }
    }
}

/// "Win (coin) 16": a small label, the coin and the amount.
struct LobbyPill: View {
    let label: String, amount: Int
    var gold = false
    @Environment(\.lobbyTheme) private var theme
    var body: some View {
        HStack(spacing: 5) {
            Text(label).font(SK.font(12, .heavy)).foregroundStyle(SK.muted)
            JellyCoinIcon(size: 16)
            Text(amount.coinText).font(SK.font(14, .black)).foregroundStyle(SK.ink).monospacedDigit().lineLimit(1).minimumScaleFactor(0.8).fixedSize()
        }
        .padding(.horizontal, 10).frame(minHeight: 30)
        .background(Capsule().fill(gold ? theme.accent : theme.tile))
        .fixedSize()
        .accessibilityElement(children: .ignore).accessibilityLabel("\(label), \(amount) JellyCoins")
    }
}

/// The line under a carousel: the blurb (or an unlock rule for a few seconds) and, to its right (or below at big text sizes), the pills.
struct LobbyInfoLine<Pills: View>: View {
    let text: String
    var textID: String?
    var pillsBelow = false
    /// One line, shrinking down to 0.7 (landscape's short blurb beside the pills).
    var squeeze = false
    let pills: Pills
    init(text: String, textID: String? = nil, pillsBelow: Bool = false, squeeze: Bool = false, @ViewBuilder pills: () -> Pills) { self.text = text; self.textID = textID; self.pillsBelow = pillsBelow; self.squeeze = squeeze; self.pills = pills() }
    @State private var availW: CGFloat = 0
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.lobbyTheme) private var theme
    /// One line when the text fits at 90% size or better (never scaled at accessibility sizes); otherwise it wraps at full size.
    private var oneLine: Bool {
        guard !typeSize.isAccessibilitySize, availW > 0 else { return false }
        let d = UIFont.systemFont(ofSize: JFont.scaledSize(13), weight: .bold).fontDescriptor.withDesign(.rounded)
        let font = d.map { UIFont(descriptor: $0, size: JFont.scaledSize(13)) } ?? UIFont.systemFont(ofSize: JFont.scaledSize(13), weight: .bold)
        return (text as NSString).size(withAttributes: [.font: font]).width * 0.9 <= availW
    }
    private var blurb: some View {
        Text(text).font(SK.font(13, .bold)).foregroundStyle(theme.subheading).lineSpacing(2)
            .lineLimit(oneLine || squeeze ? 1 : nil).minimumScaleFactor(squeeze ? 0.7 : (oneLine ? 0.9 : 1)).fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading).accessibilityIdentifier(textID ?? "lobby-info")
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { availW = $0 }
    }
    var body: some View {
        Group {
            if pillsBelow {
                VStack(alignment: .leading, spacing: 10) { blurb; FlowLayout(spacing: 6) { pills } }
            } else {
                HStack(spacing: 10) { blurb; HStack(spacing: 6) { pills } }
            }
        }
        .padding(.horizontal, 2).padding(.top, 10)
    }
}

/// One prize: "1st" and its JellyCoins; the first is gold.
struct LobbyPrize: Identifiable {
    var id: String { label }
    var label: String
    var amount: Int
    var gold = false
    /// 1st / 2nd / 3rd from three amounts.
    static func places(_ a: [Int]) -> [LobbyPrize] { zip(["1st", "2nd", "3rd"], a).enumerated().map { LobbyPrize(label: $0.element.0, amount: $0.element.1, gold: $0.offset == 0) } }
}

/// The line under the place picker (Course, Court, Stage): one short description on the left and, directly under it, the row of prize pills. The same place on every lobby.
struct LobbyPlaceInfo: View {
    let text: String
    var textID: String? = nil
    var prizes: [LobbyPrize]
    var prizeID = "lobby-prizes"
    var body: some View {
        LobbyInfoLine(text: text, textID: textID, pillsBelow: true) {
            ForEach(prizes) { LobbyPill(label: $0.label, amount: $0.amount, gold: $0.gold) }
        }
        .accessibilityIdentifier(prizeID)
    }
}

// MARK: - Bars

struct LobbyBar: View {
    let value: Float
    let color: Color
    var height: CGFloat
    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(SK.ink.opacity(0.1))
                Capsule().fill(color).frame(width: g.size.width * CGFloat(min(max(value, 0), 1)))
            }
        }
        .frame(height: height).clipShape(Capsule())
    }
}

/// Label, value and a 12 tall bar (the Runner card, the Training stats).
struct LobbyBigStat: View {
    let name: String, value: Float, color: Color
    var sub: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack { Text(name).font(SK.font(15, .heavy)).foregroundStyle(SK.ink); Spacer(); Text("\(Int((value * 100).rounded()))").font(SK.font(15, .black)).foregroundStyle(SK.ink).monospacedDigit() }
            LobbyBar(value: value, color: color, height: 12)
            if let sub { Text(sub).font(SK.font(12, .bold)).foregroundStyle(SK.muted).padding(.top, -1) }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(name) \(Int((value * 100).rounded())) out of 100").accessibilityHint(sub ?? "")
    }
}

// MARK: - Chips

struct LobbyChip: View {
    let care: GameCare
    let jelly: JellyProfile
    let selected: Bool
    var id: String?
    var action: () -> Void
    var body: some View {
        Button { AudioHub.shared.uiTap(); action() } label: {
            HStack(spacing: 8) {
                JelbiePortrait(care: care, who: jelly.id, size: 36, border: .white, outerRing: 2, head: true).accessibilityHidden(true)
                Text(jelly.name).font(SK.font(15.5, .heavy)).foregroundStyle(SK.ink).lineLimit(1)
            }
            .padding(.leading, 6).padding(.trailing, 14).frame(minHeight: 48)
            .background(Capsule().fill(selected ? SK.honey : Color.white.opacity(0.85)))
            .overlay(Capsule().strokeBorder(selected ? SK.honeyDeep : .clear, lineWidth: 2))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(jelly.name).accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier(id ?? "who-\(jelly.id)")
    }
}

/// The Jelbies as chips, wrapping when they do not fit.
struct LobbyChips: View {
    let care: GameCare
    let selected: Int
    var pick: (Int) -> Void
    var body: some View {
        FlowLayout(spacing: 8) {
            ForEach(care.jellies, id: \.id) { j in LobbyChip(care: care, jelly: j, selected: selected == j.id) { pick(j.id) } }
        }
    }
}

// MARK: - Bottom bar

/// Children laid out in a row with widths in the ratio of `weights`.
struct WeightedRow: Layout {
    var weights: [CGFloat]
    var spacing: CGFloat = 12
    private func widths(_ total: CGFloat, _ n: Int) -> [CGFloat] {
        let avail = total - spacing * CGFloat(max(n - 1, 0)), sum = weights.prefix(n).reduce(0, +)
        return (0..<n).map { avail * weights[$0] / sum }
    }
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let w = proposal.width ?? 300
        let ws = widths(w, subviews.count)
        let h = subviews.enumerated().map { $0.element.sizeThatFits(ProposedViewSize(width: ws[$0.offset], height: nil)).height }.max() ?? 0
        return CGSize(width: w, height: h)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let ws = widths(bounds.width, subviews.count)
        var x = bounds.minX
        for (i, s) in subviews.enumerated() {
            s.place(at: CGPoint(x: x, y: bounds.minY), anchor: .topLeading, proposal: ProposedViewSize(width: ws[i], height: bounds.height))
            x += ws[i] + spacing
        }
    }
}

/// The lobbies' one big main button (Go race / Enter Jelly Show / Play); a blocker mutes and disables it. With `upgrade` set, the secondary Upgrade button sits to its left
/// (white, ink outline, a star badge with the runner's unspent points); it is never blocked.
struct LobbyBottomBar: View {
    let playID: String
    let playTitle: String, playIcon: LobbyIcon.Kind
    let blocked: Bool
    var upgradeID: String = "lobby-upgrade"
    var upgradePoints = 0
    var upgrade: (() -> Void)? = nil
    var play: () -> Void
    @Environment(\.lobbyTheme) private var theme

    private var playButton: some View {
        Button { UIImpactFeedbackGenerator(style: .soft).impactOccurred(); AudioHub.shared.uiConfirm(); play() } label: {
            HStack(spacing: 9) {
                LobbyIcon(kind: playIcon, color: theme.primaryText)
                Text(playTitle).font(SK.font(19, .black)).lineLimit(1).minimumScaleFactor(0.6)
            }
            .padding(.horizontal, 12)
            .foregroundStyle(theme.primaryText).frame(maxWidth: .infinity, minHeight: 58)
            .background(Capsule().fill(blocked ? SK.muted.opacity(0.5) : theme.primary))
        }
        .buttonStyle(.plain).disabled(blocked).accessibilityIdentifier(playID)
    }

    private func upgradeContent(icon: Bool) -> some View {
        HStack(spacing: 8) {
            if icon { Image(systemName: "arrow.up.circle.fill").font(.system(size: 20, weight: .heavy)) }
            Text("Upgrade").font(SK.font(19, .black)).lineLimit(1).minimumScaleFactor(0.6)
            if upgradePoints > 0 {
                HStack(spacing: 2) {
                    Image(systemName: "star.fill").font(.system(size: 10, weight: .black))
                    Text("\(upgradePoints)").font(SK.font(13, .black)).monospacedDigit()
                }
                .foregroundStyle(theme.primaryText).padding(.horizontal, 7).frame(minHeight: 22).background(Capsule().fill(theme.primary))
            }
        }
        .padding(.horizontal, 8)
    }

    var body: some View {
        if let upgrade {
            WeightedRow(weights: [1, 1.25], spacing: 12) {
                Button { UIImpactFeedbackGenerator(style: .soft).impactOccurred(); AudioHub.shared.uiTap(); upgrade() } label: {
                    ViewThatFits(in: .horizontal) { upgradeContent(icon: true); upgradeContent(icon: false) }
                        .foregroundStyle(theme.secondaryText)
                        .frame(maxWidth: .infinity, minHeight: 58)
                        .background(Capsule().fill(theme.secondaryFill))
                        .overlay(Capsule().strokeBorder(theme.secondaryStroke, lineWidth: 3))
                }
                .buttonStyle(.plain).accessibilityLabel("Upgrade").accessibilityValue(upgradePoints > 0 ? "\(upgradePoints) points to spend" : "").accessibilityIdentifier(upgradeID)
                playButton
            }
        } else { playButton }
    }
}

// MARK: - Option rows

struct LobbySwitchStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button { UIImpactFeedbackGenerator(style: .light).impactOccurred(); AudioHub.shared.uiTap(); configuration.isOn.toggle() } label: {
            ZStack(alignment: configuration.isOn ? .trailing : .leading) {
                Capsule().fill(configuration.isOn ? SK.pink : SK.toggleOff)
                Circle().fill(.white).frame(width: 27, height: 27).shadow(color: .black.opacity(0.18), radius: 2, y: 2).padding(2)
            }
            .frame(width: 51, height: 31)
            .frame(minWidth: 51, minHeight: 44).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityValue(configuration.isOn ? "On" : "Off").accessibilityAddTraits(.isToggle)
    }
}

struct LobbyOptionRow: View {
    let icon: LobbyIcon.Kind, title: String
    @Binding var isOn: Bool
    let id: String
    var compact = false
    var body: some View {
        HStack(spacing: 12) {
            LobbyIcon(kind: icon).frame(width: compact ? 30 : 34, height: compact ? 30 : 34).background(RoundedRectangle(cornerRadius: compact ? 10 : 11, style: .continuous).fill(SK.sky.opacity(0.22)))
            Text(title).font(SK.font(compact ? 14.5 : 15.5, .heavy)).foregroundStyle(SK.ink).lineLimit(compact ? 1 : 2).minimumScaleFactor(compact ? 0.6 : 0.8).frame(maxWidth: .infinity, alignment: .leading)
            Toggle("", isOn: $isOn).labelsHidden().toggleStyle(LobbySwitchStyle()).accessibilityLabel(title).accessibilityIdentifier(id)
        }
        .frame(minHeight: compact ? 44 : 50)
    }
}

// MARK: - Sheet

/// A bottom sheet in the mockup's chrome: dim, #FBF7EE, 34 top radius, grab handle, title 26 black and a close button. `full`: reaches up to the top.
struct LobbySheet<Content: View>: View {
    let title: String
    var full = false
    var close: () -> Void
    let content: Content
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var contentH: CGFloat = 0
    /// iPad only: the widest the centred card gets (default 680).
    var padMaxWidth: CGFloat = 680
    func padWidth(_ w: CGFloat) -> Self { var c = self; c.padMaxWidth = w; return c }
    init(title: String, full: Bool = false, close: @escaping () -> Void, @ViewBuilder content: () -> Content) { self.title = title; self.full = full; self.close = close; self.content = content() }

    var body: some View {
        GeometryReader { g in
            // iPad: ONE presentation in every orientation: a centred card that is exactly as tall as its content (up to 90% of the window), never touching an edge.
            let pad = PadLayout.isPad
            let padCap = min(g.size.height * 0.9, 900)
            ZStack(alignment: pad ? .center : .bottom) {
                Color(red: 40 / 255, green: 26 / 255, blue: 14 / 255).opacity(0.38).ignoresSafeArea().onTapGesture { close() }.accessibilityHidden(true)
                VStack(spacing: 0) {
                    VStack(spacing: 0) {
                        Capsule().fill(SK.ink.opacity(0.22)).frame(width: 38, height: 5).padding(.bottom, 12).accessibilityHidden(true)
                        HStack {
                            Text(title).font(SK.font(26, .black)).foregroundStyle(SK.ink).lineLimit(1).minimumScaleFactor(0.6).accessibilityAddTraits(.isHeader)
                            Spacer()
                            Button { AudioHub.shared.uiTap(); close() } label: {
                                LobbyIcon(kind: .x, color: SK.muted).frame(width: 34, height: 34).background(Circle().fill(SK.ink.opacity(0.08)))
                                    .frame(width: 44, height: 44).contentShape(Circle())
                            }.buttonStyle(.plain).padding(-5).accessibilityLabel("Close").accessibilityIdentifier("lobby-sheet-close")
                        }
                        .padding(.bottom, 12)
                    }
                    .contentShape(Rectangle())
                    .gesture(DragGesture(minimumDistance: 12).onEnded { if $0.translation.height > 60 { close() } })
                    ScrollView { content.padding(.bottom, full || pad ? 0 : 94).background(GeometryReader { Color.clear.preference(key: SheetContentHeight.self, value: $0.size.height) }) }
                        .scrollBounceBehavior(.basedOnSize)
                        .onPreferenceChange(SheetContentHeight.self) { contentH = $0 }
                        .modifier(SheetScrollHeight(full: full && !pad, height: contentH, cap: (pad ? padCap : g.size.height - 2) - 118))
                }
                .padding(.horizontal, 16).padding(.top, 10).padding(.bottom, 12)
                .frame(maxWidth: pad ? padMaxWidth : .infinity)
                .modifier(SheetHeight(full: full && !pad, cap: g.size.height - 2))
                .background(pad ? AnyView(RoundedRectangle(cornerRadius: 34, style: .continuous).fill(SK.sheet))
                                : AnyView(UnevenRoundedRectangle(topLeadingRadius: 34, topTrailingRadius: 34, style: .continuous).fill(SK.sheet).ignoresSafeArea(edges: .bottom)))
                .padding(pad ? 16 : 0)
                .transition(reduceMotion ? .opacity : (pad ? .scale(scale: 0.94).combined(with: .opacity) : .move(edge: .bottom)))
            }
            .frame(width: g.size.width, height: g.size.height, alignment: pad ? .center : .bottom)
        }
        .accessibilityAddTraits(.isModal)
        .accessibilityAction(.escape) { close() }
    }
}

struct LobbyHowRow: View {
    let icon: LobbyIcon.Kind, title: String, text: String
    var first = false
    var body: some View {
        VStack(spacing: 0) {
            if !first { Rectangle().fill(SK.ink.opacity(0.08)).frame(height: 1) }
            HStack(alignment: .top, spacing: 14) {
                LobbyIcon(kind: icon).frame(width: 42, height: 42).background(Circle().fill(SK.honey))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(SK.font(16.5, .black)).foregroundStyle(SK.ink)
                    Text(text).font(SK.font(13.5, .bold)).foregroundStyle(SK.muted).lineSpacing(2.5)
                }
                .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .padding(.vertical, 12).padding(.horizontal, 2)
        }
        .accessibilityElement(children: .combine)
    }
}

/// The How to play rows in one sheet.
struct LobbyHowSheet: View {
    let rows: [(LobbyIcon.Kind, String, String)]
    var close: () -> Void
    var body: some View {
        LobbySheet(title: "How to play", close: close) {
            VStack(spacing: 0) {
                ForEach(rows.indices, id: \.self) { i in LobbyHowRow(icon: rows[i].0, title: rows[i].1, text: rows[i].2, first: i == 0) }
            }
        }
        .accessibilityIdentifier("lobby-how")
    }
}

// MARK: - Locked-card hint

/// Shows `text` in place of the info line for about 3 seconds.
@MainActor
@Observable
final class LobbyHint {
    var text: String?
    @ObservationIgnored private var task: Task<Void, Never>?
    func show(_ t: String, seconds: Double = 3) {
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        text = t
        UIAccessibility.post(notification: .announcement, argument: t)
        task?.cancel()
        task = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            if !Task.isCancelled { self?.text = nil }
        }
    }
}

private struct SheetHeight: ViewModifier {
    let full: Bool, cap: CGFloat
    func body(content: Content) -> some View { if full { content.frame(height: cap) } else { content } }
}

private struct SheetContentHeight: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}
/// A sheet's scrolling body: all the room it can have when `full`, else exactly its content (up to what the screen allows).
private struct SheetScrollHeight: ViewModifier {
    let full: Bool, height: CGFloat, cap: CGFloat
    func body(content: Content) -> some View {
        if full { content.frame(maxHeight: .infinity) } else { content.frame(height: min(max(height, 1), cap)) }
    }
}
