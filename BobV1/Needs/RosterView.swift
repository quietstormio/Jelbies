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
        .accessibilityLabel(wanting > 0 ? "All Jelbies, \(wanting) need\(wanting == 1 ? "s" : "") you" : "All Jelbies")
        .accessibilityValue(open ? "expanded" : "collapsed")
        .accessibilityAction(.escape) { withAnimation(CareMenu.spring) { open = false } }
        .accessibilityShowsLargeContentViewer { Label("All Jelbies", systemImage: "person.2.fill") }
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
                            Text("Your Jelbies")
                                .jFont(17, .bold)
                                .foregroundStyle(FocusStyle.brown)
                            Spacer(minLength: 8)
                            DayChip()
                        }
                        .frame(minHeight: 28)
                        ScrollView {
                            VStack(spacing: 6) {
                                ForEach(care.select.blobs) { b in
                                    BlobCard(blob: b, needs: care.needs(for: b.id), perks: care.jelly(b.id).map { j in j.perks.active.map { ($0, j.perks.remaining($0)) } } ?? []) {
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
    let blob: SelectBlob
    let needs: BlobNeeds
    var perks: [(kind: PerkKind, left: TimeInterval)] = []          // active power-ups (Perks model), shown as chips with the time left
    let action: () -> Void

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

    var body: some View {
        Button(action: action) {
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
                if perks.isEmpty {
                    Text("no boosts").jFont(12, .medium).foregroundStyle(FocusStyle.brown.opacity(0.75))
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 110), spacing: 6, alignment: .leading)], alignment: .leading, spacing: 4) {          // wraps instead of clipping
                        ForEach(perks, id: \.kind.rawValue) { p in PerkChip(kind: p.kind, left: p.left) }
                    }
                }
            }
            .accessibilityElement(children: .ignore)          // one element per row: "<name>, <mood>, boosts: ..."
            .accessibilityLabel("\(blob.name), \(needs.mood.word), boosts: \(boostSummary)")
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.white.opacity(0.6)))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(needs.wantedNeed != nil ? FocusStyle.pink.opacity(0.55) : Color.clear, lineWidth: 1.5))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("roster-card-\(blob.id)")
    }
}
