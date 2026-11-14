//
//  RosterView.swift
//  "See them all, tap one" (Nintendogs-style). A round button at the top-right (opposite the gear) opens a panel of Blob cards: a pastel colour
//  dot, the name, the mood word and the current power-ups (boosts) with their time left, one compact row per Blob (the needs live in the Condition card and the bubbles). Tapping a card closes the panel
//  and plays the outline highlight on that Blob in the room; then the action button shows for him. No Blob drawings on the cards.
//

import SwiftUI

struct RosterButton: View {
    let care: GameCare
    @Binding var open: Bool

    var body: some View {
        let wanting = care.select.blobs.filter { care.needs(for: $0.id).wantedNeed != nil }.count
        Button {
            UIImpactFeedbackGenerator(style: .soft).impactOccurred(); AudioHub.shared.uiTap()
            withAnimation(CareMenu.spring) { open.toggle() }
        } label: {
            ZStack {
                if open {
                    Image(systemName: "xmark").font(.system(size: 19, weight: .semibold))
                } else {
                    JelbieGlyph().frame(width: 34, height: 32)
                }
            }
            .foregroundStyle(Color(red: 0.42, green: 0.34, blue: 0.30))
            .frame(width: 44, height: 44).contentShape(Circle())
                .overlay(alignment: .topTrailing) {
                    if wanting > 0 && !open {
                        Circle().fill(FocusStyle.pink).frame(width: 12, height: 12)
                            .overlay(Circle().strokeBorder(FocusStyle.cream, lineWidth: 2))
                            .offset(x: 2, y: -2)
                    }
                }
        }
        .buttonStyle(.plain)
        .hudFrost(in: .circle)
        .accessibilityIdentifier("roster-button")
        .accessibilityLabel(wanting > 0 ? "All Jelmiko, \(wanting) need\(wanting == 1 ? "s" : "") you" : "All Jelmiko")
        .accessibilityValue(open ? "expanded" : "collapsed")
        .accessibilityAction(.escape) { withAnimation(CareMenu.spring) { open = false } }
        .accessibilityShowsLargeContentViewer { Label("All Jelmiko", systemImage: "person.2.fill") }
        .keyboardShortcut("r", modifiers: .command)
    }
}

/// The panel under the button: a scrim plus a 90%-opaque cream card (portrait width min(screen - 32, 340), landscape up to 60% of the width, 12 pt inside padding, scrolls when the cards do not fit).
struct RosterPanel: View {
    let care: GameCare
    @Binding var open: Bool
    var onPick: (Int) -> Void = { _ in }
    @State private var contentH: CGFloat = 0

    var body: some View {
        GeometryReader { g in
            let landscape = g.size.width > g.size.height
            let width = landscape ? min(g.size.width * 0.6, 460) : min(g.size.width - 32, 340)          // landscape: at most ~60% of the width, top-right
            let top: CGFloat = 52
            let chrome: CGFloat = 24 + 8 + 28          // padding, spacing, header
            let avail = max(120, g.size.height - top - 16 - chrome)
            ZStack(alignment: .topTrailing) {
                if open {
                    Color(red: 0.30, green: 0.20, blue: 0.14).opacity(0.22)
                        .ignoresSafeArea()
                        .onTapGesture { withAnimation(CareMenu.spring) { open = false } }
                        .transition(.opacity)
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Your Jelmiko")
                                .jFont(17, .bold)
                                .foregroundStyle(FocusStyle.brown)
                            Spacer(minLength: 8)
                            DayChip()
                        }
                        .frame(minHeight: 28)
                        ScrollView {
                            VStack(spacing: 6) {
                                ForEach(care.select.blobs) { b in
                                    BlobCard(blob: b, needs: care.needs(for: b.id), perks: care.jelly(b.id).map { j in j.perks.active.map { ($0, j.perks.remaining($0)) } } ?? [], personality: care.jelly(b.id)?.traits?.summary) {
                                        UIImpactFeedbackGenerator(style: .soft).impactOccurred(); AudioHub.shared.uiTap()
                                        withAnimation(CareMenu.spring) { open = false }
                                        onPick(b.id)
                                    }
                                }
                            }
                            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentH = $0 }
                        }
                        .frame(height: contentH > 0 ? min(contentH, avail) : avail)
                        .scrollBounceBehavior(.basedOnSize)
                    }
                    .padding(12)
                    .frame(width: width)
                    .background {          // plain alpha fill: a normal blend, no glass / material / blur over the live Metal view
                        RoundedRectangle(cornerRadius: 22, style: .continuous).fill(HUDGlass.opaque.opacity(0.9))
                            .shadow(color: Color(red: 0.3, green: 0.2, blue: 0.12).opacity(0.2), radius: 6, y: 2)
                    }
                    .padding(.top, top).padding(.trailing, 16)
                    .transition(.scale(scale: 0.4, anchor: .topTrailing).combined(with: .opacity))
                    .accessibilityIdentifier("roster-panel")
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
        }
    }
}

struct BlobCard: View {
    @Environment(\.dynamicTypeSize) private var dts
    let blob: SelectBlob
    let needs: BlobNeeds
    var perks: [(kind: PerkKind, left: TimeInterval)] = []          // active power-ups (Perks model), shown as chips with the time left
    var personality: String? = nil          // "Cuddly · loves Bedtime cookie" (a picked Jelbie; nil for the older ones)
    let action: () -> Void
    @State private var openPerk: PerkKind?          // the boost whose one-line explanation is showing (derived against `perks` below)

    static func moodColor(_ m: BlobMood) -> Color {
        switch m {
        case .happy: return Color(red: 0.80, green: 0.93, blue: 0.78)
        case .okay: return Color(red: 0.98, green: 0.92, blue: 0.74)
        case .grumpy: return Color(red: 0.99, green: 0.78, blue: 0.74)
        }
    }

    /// "Cozy 2h 40m, Sugar rush 22m" or "none"
    var boostSummary: String {
        perks.isEmpty ? "none" : perks.map { "\($0.kind.title) \(SK.timeLeft($0.left)) left" }.joined(separator: ", ")
    }

    /// "Deep sleep: <blurb>" for each active boost, for VoiceOver.
    var boostExplanations: String {
        perks.map { "\($0.kind.title): \($0.kind.blurb)" }.joined(separator: " ")
    }

    var body: some View {
        let shown = perks.first(where: { $0.kind == openPerk })?.kind
        VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Circle().fill(Color(red: Double(blob.tint.x), green: Double(blob.tint.y), blue: Double(blob.tint.z)))
                        .frame(width: 18, height: 18)
                        .overlay(Circle().strokeBorder(Color.white.opacity(0.7), lineWidth: 1.5))
                        .accessibilityHidden(true)          // the tint is decoration; the name carries the identity
                    Text(blob.name).jFont(17, .bold).foregroundStyle(FocusStyle.brown).lineLimit(1).minimumScaleFactor(0.7)
                    Spacer(minLength: 4)
                    Text(needs.mood.word)
                        .jFont(12, .semibold).foregroundStyle(FocusStyle.brown)
                        .lineLimit(1).fixedSize()
                        .padding(.horizontal, 9).padding(.vertical, 3)
                        .background(Capsule().fill(Self.moodColor(needs.mood)))
                }
                if let personality { Text(personality).jFont(12, .medium).foregroundStyle(FocusStyle.brown.opacity(0.8)).lineLimit(1).minimumScaleFactor(0.7) }
                let meters = dts.isAccessibilitySize
                    ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4)) : AnyLayout(HStackLayout(spacing: 6))
                meters { ForEach(NeedKind.allCases, id: \.rawValue) { k in meter(k) } }          // the three bars only; no word rows
                    .frame(maxWidth: .infinity)
                if perks.isEmpty {
                    Text("No Boosts").jFont(12, .medium).foregroundStyle(FocusStyle.brown.opacity(0.75))
                } else {
                    PerkWrapRow(spacing: 6, lineSpacing: 4) {          // natural-width chips that wrap instead of truncating
                        ForEach(perks, id: \.kind.rawValue) { p in
                            Button {
                                AudioHub.shared.uiTap()
                                withAnimation(.easeInOut(duration: 0.15)) { openPerk = (openPerk == p.kind) ? nil : p.kind }
                            } label: {
                                PerkChip(kind: p.kind, left: p.left)
                                    .overlay(Capsule().strokeBorder(FocusStyle.brown, lineWidth: shown == p.kind ? 1.5 : 0))
                                    .padding(.vertical, 6).contentShape(Rectangle())          // ~34 pt tall tap target ...
                            }
                            .buttonStyle(.plain)
                            .padding(.vertical, -6)          // ... without making the row taller
                        }
                    }
                    if let shown {
                        Text("\(shown.title): \(shown.blurb)")
                            .jFont(12, .medium).foregroundStyle(FocusStyle.brown.opacity(0.85))
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.white.opacity(0.6)))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(needs.wantedNeed != nil ? FocusStyle.pink.opacity(0.55) : Color.clear, lineWidth: 1.5))
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .onTapGesture(perform: action)          // the whole card opens the Jelbie; the chip Buttons above take their own taps first
        .accessibilityElement(children: .ignore)          // one element per row: "<name>, <mood>, boosts: ..."
        .accessibilityLabel("\(blob.name), \(personality.map { $0 + ", " } ?? "")\(needs.mood.word), boosts: \(boostSummary)")
        .accessibilityValue(boostExplanations)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { action() }
        .accessibilityIdentifier("roster-card-\(blob.id)")
    }

    private func meter(_ k: NeedKind) -> some View {
        let v = CGFloat(needs.levels[k.rawValue])
        let want = needs.wantedNeed == k || v < CGFloat(NeedsTuning.wanting)
        return HStack(spacing: 3) {
            NeedGlyph(kind: k, size: 16)
            Capsule().fill(FocusStyle.brown.opacity(0.12))
                .overlay(alignment: .leading) {
                    GeometryReader { bar in
                        Capsule().fill(want ? SK.pinkStrong : Color(red: 0.62, green: 0.82, blue: 0.62))
                            .overlay { if want { StripePattern(color: .white.opacity(0.7)).clipShape(Capsule()) } }          // wanting = stripes + "!", not only pink vs green
                            .frame(width: max(5, bar.size.width * v))
                    }
                }
                .frame(minWidth: 12, maxWidth: .infinity).frame(height: 10)
            if want { Image(systemName: "exclamationmark.circle.fill").font(.system(size: 12, weight: .bold)).foregroundStyle(SK.pinkStrong) }
        }
        .padding(.horizontal, 4).padding(.vertical, 2)
        .frame(maxWidth: .infinity)
        .background(Capsule().fill(want ? FocusStyle.pink.opacity(0.16) : Color.clear))
        .overlay(Capsule().strokeBorder(want ? FocusStyle.pink.opacity(0.7) : Color.clear, lineWidth: 1.2))
    }
}

/// A wrapping row: every child keeps its natural width and wraps to the next line; a child wider than the row is proposed the row width (so a one-line chip truncates instead of overflowing).
private struct PerkWrapRow: Layout {
    var spacing: CGFloat = 6
    var lineSpacing: CGFloat = 4

    private func arrange(_ width: CGFloat, _ subviews: Subviews) -> (frames: [CGRect], size: CGSize) {
        var frames: [CGRect] = []
        var x: CGFloat = 0, y: CGFloat = 0, rowH: CGFloat = 0, maxX: CGFloat = 0
        for s in subviews {
            var sz = s.sizeThatFits(.unspecified)
            if sz.width > width { sz = s.sizeThatFits(ProposedViewSize(width: width, height: nil)) }
            if x > 0, x + sz.width > width { x = 0; y += rowH + lineSpacing; rowH = 0 }
            frames.append(CGRect(x: x, y: y, width: min(sz.width, width), height: sz.height))
            x += sz.width + spacing; rowH = max(rowH, sz.height); maxX = max(maxX, x - spacing)
        }
        return (frames, CGSize(width: min(maxX, width), height: y + rowH))
    }
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrange(proposal.width ?? 300, subviews).size
    }
    func placeSubviews(in r: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let a = arrange(r.width, subviews)
        for (s, f) in zip(subviews, a.frames) {
            s.place(at: CGPoint(x: r.minX + f.minX, y: r.minY + f.minY), proposal: ProposedViewSize(width: f.width, height: f.height))
        }
    }
}
