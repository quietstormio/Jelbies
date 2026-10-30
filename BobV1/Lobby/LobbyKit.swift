//
//  LobbyKit.swift
//  The shared pieces of the Volleyball and Track lobbies, built to the lobby mockups (lobby.html): the header, the carousel card, the info pills, the stat bars,
//  the option rows, the chips, the pinned Train / Play bar, the pep dots and the sheet (Training, How to play). Sizes, weights and radii are the mockup's
//  px = pt on a 440 x 956 phone; text is SK.font so it follows Dynamic Type.
//

import SwiftUI

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

    init(header: AnyView, why: String?, whyID: String, @ViewBuilder left: () -> Left, @ViewBuilder right: () -> Right, @ViewBuilder bar: () -> Bar) {
        self.header = header; self.why = why; self.whyID = whyID; self.left = left(); self.right = right(); self.bar = bar()
    }

    private var whyLine: some View {
        Group {
            if let why { Text(why).font(SK.font(12, .bold)).foregroundStyle(SK.muted).frame(maxWidth: .infinity, alignment: .leading).padding(.bottom, 8).accessibilityIdentifier(whyID) }
        }
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
            } else {
                VStack(spacing: 0) {
                    header.padding(.top, 14).padding(.horizontal, 16)
                    ScrollView {
                        VStack(alignment: .leading, spacing: 0) {
                            left
                            right
                        }
                        .padding(.horizontal, 16).padding(.top, 16).padding(.bottom, 12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .scrollBounceBehavior(.basedOnSize)
                    VStack(spacing: 0) { whyLine; bar }.padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 10).modifier(BarBand())
                }
            }
        }
        .background(SK.cream.ignoresSafeArea())
    }
}

/// The pinned bar's own cream band (it reaches the bottom edge) with a soft fade above it, so scrolled content never pokes out over the buttons.
private struct BarBand: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(alignment: .bottom) { SK.cream.ignoresSafeArea(edges: .bottom) }
            .overlay(alignment: .top) {
                LinearGradient(colors: [SK.cream.opacity(0), SK.cream], startPoint: .top, endPoint: .bottom).frame(height: 18).offset(y: -18).allowsHitTesting(false)
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
    @Environment(\.dynamicTypeSize) private var typeSize
    private var backButton: some View {
        Button { AudioHub.shared.uiTap(); back() } label: {
            LobbyIcon(kind: .back).frame(width: 44, height: 44).background(Circle().fill(Color.white.opacity(0.85)))
        }.buttonStyle(.plain).accessibilityLabel("Back").accessibilityIdentifier(backID)
    }
    private var helpButton: some View {
        Button { AudioHub.shared.uiTap(); help() } label: {
            Text("?").font(SK.font(16, .black)).foregroundStyle(SK.muted).frame(width: 30, height: 30).background(Circle().fill(SK.ink.opacity(0.08)))
                .frame(width: 44, height: 44).contentShape(Circle())
        }.buttonStyle(.plain).padding(-7).accessibilityLabel("How to play").accessibilityIdentifier(helpID)
    }
    private var titleText: some View { Text(title).font(SK.font(30, .black)).foregroundStyle(SK.ink).accessibilityAddTraits(.isHeader) }
    var body: some View {
        if typeSize.isAccessibilitySize {
            // big text: the title gets a line of its own
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 10) { backButton; helpButton; Spacer(minLength: 0); DropsPill(wallet: wallet, lobby: true) }
                titleText.lineLimit(2).minimumScaleFactor(0.6)
            }
        } else {
            HStack(spacing: 10) {
                backButton
                titleText.lineLimit(1).minimumScaleFactor(0.6)
                helpButton.offset(y: 2)
                Spacer(minLength: 0)
                DropsPill(wallet: wallet, lobby: true)
            }
            .frame(minHeight: 52)
        }
    }
}

// MARK: - Labels, cards, pills

/// "Court" ... "1 of 4 open".
struct LobbyLabelRow: View {
    let title: String, trailing: String
    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(SK.font(17, .black)).foregroundStyle(SK.ink).accessibilityAddTraits(.isHeader)
            Spacer()
            Text(trailing).font(SK.font(12.5, .bold)).foregroundStyle(SK.muted)
        }
        .padding(.horizontal, 2).padding(.bottom, 8)
    }
}

extension View {
    /// The mockups' white card: radius 24.
    func lobbyCard(padding: EdgeInsets = EdgeInsets(top: 14, leading: 14, bottom: 14, trailing: 14)) -> some View {
        self.padding(padding).frame(maxWidth: .infinity, alignment: .leading).background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(SK.card))
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
    var body: some View {
        HStack(spacing: 5) {
            Text(label).font(SK.font(12, .heavy)).foregroundStyle(SK.muted)
            JellyCoinIcon(size: 16)
            Text("\(amount)").font(SK.font(14, .black)).foregroundStyle(SK.ink).monospacedDigit()
        }
        .padding(.horizontal, 10).frame(minHeight: 30)
        .background(Capsule().fill(gold ? SK.honey : Color.white.opacity(0.85)))
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
    /// One line when the text fits at 90% size or better (never scaled at accessibility sizes); otherwise it wraps at full size.
    private var oneLine: Bool {
        guard !typeSize.isAccessibilitySize, availW > 0 else { return false }
        let d = UIFont.systemFont(ofSize: JFont.scaledSize(13), weight: .bold).fontDescriptor.withDesign(.rounded)
        let font = d.map { UIFont(descriptor: $0, size: JFont.scaledSize(13)) } ?? UIFont.systemFont(ofSize: JFont.scaledSize(13), weight: .bold)
        return (text as NSString).size(withAttributes: [.font: font]).width * 0.9 <= availW
    }
    private var blurb: some View {
        Text(text).font(SK.font(13, .bold)).foregroundStyle(SK.muted).lineSpacing(2)
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

// MARK: - Pep

/// Three pips: mint = a full-value practice left today, #E6D8C6 = used.
struct PepDots: View {
    let left: Int, total: Int
    var id: String?
    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<total, id: \.self) { i in
                Circle().fill(i < left ? SK.mint : SK.pepEmpty).frame(width: 9, height: 9).overlay(Circle().strokeBorder(SK.ink.opacity(0.12), lineWidth: 1))
            }
        }
        .accessibilityElement(children: .ignore).accessibilityLabel("Pep: \(left) of \(total) full practices left today")
        .accessibilityIdentifier(id ?? "lobby-pep")
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

/// Train (white, ink outline, figure, pep pips) and the main button (pinkStrong, 1.25x as wide). A blocker mutes and disables both.
struct LobbyBottomBar: View {
    let pepLeft: Int, pepTotal: Int
    let pepID: String
    let trainID: String, playID: String
    let playTitle: String, playIcon: LobbyIcon.Kind
    let blocked: Bool
    var train: () -> Void
    var play: () -> Void
    @Environment(\.verticalSizeClass) private var vsc

    var body: some View {
        let minH: CGFloat = 58
        WeightedRow(weights: [1, 1.25], spacing: 12) {
            Button { UIImpactFeedbackGenerator(style: .soft).impactOccurred(); train() } label: {
                ViewThatFits(in: .horizontal) {
                    trainContent(icon: true, dots: true)
                    trainContent(icon: false, dots: true)
                    trainContent(icon: false, dots: false)
                }
                .foregroundStyle(blocked ? SK.muted : SK.ink)
                .frame(maxWidth: .infinity, minHeight: minH)
                .background(Capsule().fill(Color.white.opacity(0.92)))
                .overlay(Capsule().strokeBorder(blocked ? SK.muted.opacity(0.4) : SK.ink, lineWidth: 3))
            }
            .buttonStyle(.plain).disabled(blocked).accessibilityIdentifier(trainID)
            .accessibilityLabel("Train").accessibilityValue("Pep: \(pepLeft) of \(pepTotal) full practices left")
            Button { UIImpactFeedbackGenerator(style: .soft).impactOccurred(); AudioHub.shared.uiConfirm(); play() } label: {
                HStack(spacing: 9) {
                    LobbyIcon(kind: playIcon, color: .white)
                    Text(playTitle).font(SK.font(19, .black)).lineLimit(1).minimumScaleFactor(0.6)
                }
                .foregroundStyle(.white).frame(maxWidth: .infinity, minHeight: minH)
                .background(Capsule().fill(blocked ? SK.muted.opacity(0.5) : SK.pinkStrong))
            }
            .buttonStyle(.plain).disabled(blocked).accessibilityIdentifier(playID)
        }
    }

    private func trainContent(icon: Bool, dots: Bool) -> some View {
        HStack(spacing: 9) {
            if icon { LobbyIcon(kind: .run, color: blocked ? SK.muted : SK.ink) }
            Text("Train").font(SK.font(19, .black)).lineLimit(1).minimumScaleFactor(0.6)
            if dots { PepDots(left: pepLeft, total: pepTotal, id: pepID).padding(.leading, 2).opacity(blocked ? 0.6 : 1) }
        }
        .padding(.horizontal, 8)
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
    init(title: String, full: Bool = false, close: @escaping () -> Void, @ViewBuilder content: () -> Content) { self.title = title; self.full = full; self.close = close; self.content = content() }

    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .bottom) {
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
                    ScrollView { content.padding(.bottom, full ? 0 : 94).background(GeometryReader { Color.clear.preference(key: SheetContentHeight.self, value: $0.size.height) }) }
                        .scrollBounceBehavior(.basedOnSize)
                        .onPreferenceChange(SheetContentHeight.self) { contentH = $0 }
                        .modifier(SheetScrollHeight(full: full, height: contentH, cap: g.size.height - 120))
                }
                .padding(.horizontal, 16).padding(.top, 10).padding(.bottom, 12)
                .frame(maxWidth: .infinity)
                .modifier(SheetHeight(full: full, cap: g.size.height - 2))
                .background(UnevenRoundedRectangle(topLeadingRadius: 34, topTrailingRadius: 34, style: .continuous).fill(SK.sheet).ignoresSafeArea(edges: .bottom))
                .transition(reduceMotion ? .opacity : .move(edge: .bottom))
            }
            .frame(width: g.size.width, height: g.size.height, alignment: .bottom)
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
