//
//  RosterView.swift
//  "See them all, tap one" (Nintendogs-style). A round button at the top-right (opposite the gear) opens a panel of Blob cards: a pastel colour
//  dot, the name, the mood word and the three need meters (food, drink, heart) with the wanting one highlighted. Tapping a card closes the panel
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
            Image(systemName: open ? "xmark" : "person.2.fill")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color(red: 0.42, green: 0.34, blue: 0.30))
                .frame(width: 36, height: 36)
                .background(Circle().fill(Color(red: 0.97, green: 0.94, blue: 0.88)).opacity(0.92))
                .overlay(Circle().strokeBorder(Color.black.opacity(0.06), lineWidth: 0.5))
                .overlay(alignment: .topTrailing) {
                    if wanting > 0 && !open {
                        Circle().fill(FocusStyle.pink).frame(width: 12, height: 12)
                            .overlay(Circle().strokeBorder(FocusStyle.cream, lineWidth: 2))
                            .offset(x: 2, y: -2)
                    }
                }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("roster-button")
        .accessibilityLabel("All Blobs")
    }
}

/// The panel under the button: a scrim plus the cards.
struct RosterPanel: View {
    let care: GameCare
    @Binding var open: Bool
    var onPick: (Int) -> Void = { _ in }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            if open {
                Color(red: 0.30, green: 0.20, blue: 0.14).opacity(0.22)
                    .ignoresSafeArea()
                    .onTapGesture { withAnimation(CareMenu.spring) { open = false } }
                    .transition(.opacity)
                VStack(alignment: .leading, spacing: 10) {
                    Text("Your Blobs")
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                        .foregroundStyle(FocusStyle.brown)
                        .padding(.leading, 6)
                    ScrollView {
                        VStack(spacing: 10) {
                            ForEach(care.select.blobs) { b in
                                BlobCard(blob: b, needs: care.needs(for: b.id), coat: care.coat(for: b.id)) {
                                    UIImpactFeedbackGenerator(style: .soft).impactOccurred(); AudioHub.shared.uiTap()
                                    withAnimation(CareMenu.spring) { open = false }
                                    onPick(b.id)
                                }
                            }
                        }
                    }
                    .scrollBounceBehavior(.basedOnSize)
                }
                .padding(14)
                .frame(width: 300)
                .frame(maxHeight: 500)
                .fixedSize(horizontal: false, vertical: true)
                .background(RoundedRectangle(cornerRadius: 26, style: .continuous).fill(FocusStyle.cream).shadow(color: FocusStyle.shadow.opacity(0.28), radius: 14, y: 6))
                .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).strokeBorder(Color.white.opacity(0.6), lineWidth: 1))
                .padding(.top, 52).padding(.trailing, 16)
                .transition(.scale(scale: 0.4, anchor: .topTrailing).combined(with: .opacity))
                .accessibilityIdentifier("roster-panel")
            }
        }
    }
}

struct BlobCard: View {
    let blob: SelectBlob
    let needs: BlobNeeds
    var coat: BlobGrime.CoatTier = .normal
    let action: () -> Void

    static func moodColor(_ m: BlobMood) -> Color {
        switch m {
        case .happy: return Color(red: 0.80, green: 0.93, blue: 0.78)
        case .okay: return Color(red: 0.98, green: 0.92, blue: 0.74)
        case .grumpy: return Color(red: 0.99, green: 0.78, blue: 0.74)
        }
    }

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 9) {
                HStack(spacing: 9) {
                    Circle().fill(Color(red: Double(blob.tint.x), green: Double(blob.tint.y), blue: Double(blob.tint.z)))
                        .frame(width: 22, height: 22)
                        .overlay(Circle().strokeBorder(Color.white.opacity(0.7), lineWidth: 1.5))
                    Text(blob.name).font(.system(size: 18, weight: .bold, design: .rounded)).foregroundStyle(FocusStyle.brown)
                    Spacer()
                    Text(needs.mood.word)
                        .font(.system(size: 13, weight: .semibold, design: .rounded)).foregroundStyle(FocusStyle.brown)
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .background(Capsule().fill(Self.moodColor(needs.mood)))
                }
                HStack(spacing: 12) {
                    ForEach(NeedKind.allCases, id: \.rawValue) { k in meter(k) }
                }
                status
            }
            .padding(.horizontal, 12).padding(.vertical, 10)
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color.white.opacity(0.75)))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(needs.wantedNeed != nil ? FocusStyle.pink.opacity(0.55) : Color.white.opacity(0.0), lineWidth: 1.5))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("roster-card-\(blob.id)")
        .accessibilityLabel("\(blob.name), \(needs.mood.word)")
        .accessibilityValue(statusSummary)
    }

    /// The Nintendogs-style status words, per Blob: Hunger, Thirst, Attention (their tier words) and Coat.
    var statusItems: [(title: String, word: String)] {
        [("Hunger", needs.tier(.hunger).word(.hunger)), ("Thirst", needs.tier(.thirst).word(.thirst)),
         ("Attention", needs.tier(.attention).word(.attention)), ("Coat", coat.word)]
    }
    var statusSummary: String { statusItems.map { "\($0.title) \($0.word)" }.joined(separator: ", ") }

    private var status: some View {
        let cols = [GridItem(.flexible(), alignment: .leading), GridItem(.flexible(), alignment: .leading)]
        return LazyVGrid(columns: cols, alignment: .leading, spacing: 3) {
            ForEach(statusItems, id: \.title) { item in
                HStack(spacing: 4) {
                    Text(item.title).foregroundStyle(FocusStyle.brown.opacity(0.55))
                    Text(item.word).foregroundStyle(FocusStyle.brown).fontWeight(.bold)
                        .accessibilityIdentifier("status-\(item.title.lowercased())-\(blob.id)")
                }
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .lineLimit(1).minimumScaleFactor(0.8)
            }
        }
    }

    private func meter(_ k: NeedKind) -> some View {
        let v = CGFloat(needs.levels[k.rawValue])
        let want = needs.wantedNeed == k || v < CGFloat(NeedsTuning.wanting)
        return HStack(spacing: 4) {
            NeedGlyph(kind: k, size: 18)
            ZStack(alignment: .leading) {
                Capsule().fill(FocusStyle.brown.opacity(0.12))
                Capsule().fill(want ? FocusStyle.pink : Color(red: 0.62, green: 0.82, blue: 0.62))
                    .frame(width: max(5, 44 * v))
            }
            .frame(width: 44, height: 8)
        }
        .padding(.horizontal, 5).padding(.vertical, 4)
        .background(Capsule().fill(want ? FocusStyle.pink.opacity(0.16) : Color.clear))
        .overlay(Capsule().strokeBorder(want ? FocusStyle.pink.opacity(0.7) : Color.clear, lineWidth: 1.2))
    }
}
