//
//  FriendsUI.swift
//  Asking a friend over (2026-10-25): the Town's Friends page (one card per visitor who is a Friend of the Jelbies: who they are, which of the player's Jelbies
//  they know and how well, and ONE "Invite over" button: they come in the evening and go home in the morning), the invite button that a visitor's card at the
//  Park shares, and the guest's own card at home (a tap on him). Rules: Park/GameCare+Guest.swift. Views only.
//

import SwiftUI

/// "Invite over": ONE button (they come in the evening, go home in the morning). Used on a visitor's card.
struct InviteChooser: View {
    let care: GameCare
    let visitorID: Int
    var after: () -> Void = {}

    var body: some View {
        Button {
            UIImpactFeedbackGenerator(style: .soft).impactOccurred()
            if care.inviteFriend(visitorID) { after() }
        } label: {
            VStack(spacing: 1) {
                HStack(spacing: 8) { Image(systemName: GuestVisit.Kind.sleepover.symbol); Text(GuestVisit.Kind.sleepover.title) }
                    .font(SK.font(16, .black))
                Text(GuestVisit.Kind.sleepover.blurb).font(SK.font(11, .bold)).opacity(0.85)
            }
            .foregroundStyle(.white).frame(maxWidth: .infinity, minHeight: 46)
            .background(Capsule().fill(SK.pinkStrong))
        }
        .buttonStyle(.plain).accessibilityLabel("Invite over").accessibilityHint(GuestVisit.Kind.sleepover.blurb).accessibilityIdentifier("invite-over")
    }
}

/// The guest's card at home (a tap on him): the visitor card with a Say goodbye button instead of the invite.
struct GuestChrome: View {
    let care: GameCare
    @Environment(\.verticalSizeClass) private var vsc
    private var book: GuestBook { care.guestBook }

    var body: some View {
        GeometryReader { g in
            ZStack {
                if book.card, book.present, let vid = book.visit?.visitor, let v = care.parkBook.visitor(vid) {
                    if vsc == .compact {
                        HStack { Spacer(); VisitorCard(care: care, visitor: v, home: true).frame(width: min(320, g.size.width * 0.38)).padding(.top, 70).padding(.bottom, 80).padding(.trailing, 8) }
                            .transition(.move(edge: .trailing).combined(with: .opacity))
                    } else {
                        VStack { Spacer(); VisitorCard(care: care, visitor: v, home: true).fixedSize(horizontal: false, vertical: true).padding(.horizontal, 10).padding(.bottom, 150) }
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
            }
            .frame(width: g.size.width, height: g.size.height)
            .animation(.easeInOut(duration: 0.25), value: book.card)
        }
        .allowsHitTesting(book.card)
    }
}

/// The Town's Friends page.
struct FriendsScreen: View {
    let care: GameCare
    var back: () -> Void
    var goHome: () -> Void
    @Environment(\.verticalSizeClass) private var vsc

    private func tint(_ c: ParkColour) -> Color { Color(red: Double(c.swatch.x), green: Double(c.swatch.y), blue: Double(c.swatch.z)) }

    var body: some View {
        let _ = care.parkBook.revision
        VStack(spacing: vsc == .compact ? 8 : 14) {
            HStack(spacing: 10) {
                Button { AudioHub.shared.uiTap(); back() } label: {
                    Image(systemName: "chevron.left").font(.system(size: 17, weight: .black)).foregroundStyle(SK.ink)
                        .frame(width: 44, height: 44).background(Circle().fill(Color.white.opacity(0.85)))
                }.buttonStyle(.plain).accessibilityLabel("Back").accessibilityIdentifier("friends-back")
                Text("Friends").font(SK.font(30, .black)).foregroundStyle(SK.ink)
                Spacer()
            }
            ScrollView {
                VStack(spacing: 10) {
                    status
                    let list = care.friendsToInvite()
                    if list.isEmpty {
                        Text("Make friends with the visitors at the Park. When one reaches Friend, you can ask them over here.")
                            .font(SK.font(15, .bold)).foregroundStyle(SK.muted).multilineTextAlignment(.leading)
                            .padding(16).frame(maxWidth: .infinity, alignment: .leading)
                            .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(SK.card))
                    }
                    ForEach(list) { v in row(v) }
                }
                .padding(.bottom, 16)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .padding(.horizontal, 16).padding(.top, 8)
        .background(SK.cream.ignoresSafeArea())
        .accessibilityElement(children: .contain).accessibilityIdentifier("friends-screen")
    }

    /// Who is coming or here now (one at a time).
    @ViewBuilder private var status: some View {
        if let cur = care.guestBook.visit, let v = care.parkBook.visitor(cur.visitor), let line = care.guestStatusText() {
            HStack(spacing: 12) {
                Circle().fill(tint(v.colour)).frame(width: 40, height: 40).overlay(Circle().strokeBorder(Color.white.opacity(0.8), lineWidth: 2))
                VStack(alignment: .leading, spacing: 2) {
                    Text(line).font(SK.font(17, .black)).foregroundStyle(SK.ink)
                    Text(GuestVisit.Kind.sleepover.blurb).font(SK.font(12, .heavy)).foregroundStyle(SK.muted)
                }
                Spacer(minLength: 4)
                if !cur.arrived {
                    Button { AudioHub.shared.uiTap(); care.cancelInvite() } label: {
                        Text("Cancel").font(SK.font(14, .heavy)).foregroundStyle(SK.ink).padding(.horizontal, 14).frame(minHeight: 44)
                            .background(Capsule().fill(Color.white.opacity(0.85)))
                    }.buttonStyle(.plain).accessibilityIdentifier("friends-cancel")
                }
            }
            .padding(12).frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(SK.mint.opacity(0.7)))
            .accessibilityElement(children: .combine).accessibilityIdentifier("friends-status")
        }
    }

    /// One card per friend: who (colour, name, personality tag), which of the player's Jelbies they know and how well, and the one Invite button.
    private func row(_ v: ParkVisitor) -> some View {
        let free = care.guestBook.visit == nil
        let lvl = v.bestLevel(among: care.jellies.map(\.character))
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Circle().fill(tint(v.colour)).frame(width: 44, height: 44).overlay(Circle().strokeBorder(Color.white.opacity(0.8), lineWidth: 2))
                VStack(alignment: .leading, spacing: 3) {
                    Text(v.name).font(SK.font(20, .black)).foregroundStyle(SK.ink).lineLimit(1).minimumScaleFactor(0.7)
                    // the personality word is a tag, never a bare word: "Zippy" alone reads like a name
                    Text("personality: \(v.style.word.lowercased())").font(SK.font(11, .heavy)).foregroundStyle(SK.ink.opacity(0.8))
                        .padding(.horizontal, 8).frame(minHeight: 20)
                        .background(Capsule().fill(SK.honey.opacity(0.35)))
                        .accessibilityLabel("Personality: \(v.style.word.lowercased())")
                }
                Spacer(minLength: 4)
                Text(lvl.title).font(SK.font(12, .heavy)).foregroundStyle(SK.muted)
            }
            VStack(alignment: .leading, spacing: 5) {
                Text("Friends with").font(SK.font(12, .heavy)).foregroundStyle(SK.muted)
                ChipFlow(spacing: 6, lineSpacing: 6) {
                    ForEach(care.jellies, id: \.id) { j in chip(j, level: v.level(with: j.character), friend: v.name) }
                }
            }
            Button {
                UIImpactFeedbackGenerator(style: .soft).impactOccurred()
                if care.inviteFriend(v.id) { goHome() }
            } label: {
                VStack(spacing: 1) {
                    HStack(spacing: 6) { Image(systemName: GuestVisit.Kind.sleepover.symbol); Text(GuestVisit.Kind.sleepover.title) }.font(SK.font(15, .black))
                    Text(GuestVisit.Kind.sleepover.blurb).font(SK.font(11, .bold)).opacity(0.8)
                }
                .foregroundStyle(SK.ink).frame(maxWidth: .infinity, minHeight: 46)
                .padding(.vertical, 3)
                .background(Capsule().fill(SK.honey.opacity(free ? 1 : 0.4)))
            }
            .buttonStyle(.plain).disabled(!free)
            .accessibilityLabel("Invite \(v.name) over").accessibilityHint(GuestVisit.Kind.sleepover.blurb).accessibilityIdentifier("friends-invite-\(v.id)")
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(SK.card).shadow(color: SK.shadow.opacity(0.10), radius: 5, y: 2))
        .accessibilityIdentifier("friends-card-\(v.id)")
    }

    /// One of the player's Jelbies: its colour dot, name and hearts with this friend ("not yet" at Stranger).
    private func chip(_ j: JellyProfile, level: ParkFriendLevel, friend: String) -> some View {
        let t = JellyRoster.tint(j.character)
        return HStack(spacing: 5) {
            Circle().fill(Color(red: Double(t.x), green: Double(t.y), blue: Double(t.z))).frame(width: 14, height: 14)
                .overlay(Circle().strokeBorder(Color.white.opacity(0.8), lineWidth: 1.5))
            Text(j.name).font(SK.font(13, .heavy)).foregroundStyle(SK.ink).lineLimit(1)
            if level == .stranger {
                Text("not yet").font(SK.font(11, .bold)).foregroundStyle(SK.muted)
            } else {
                HStack(spacing: 1) {
                    ForEach(0..<3, id: \.self) { i in
                        Image(systemName: i < level.hearts ? "heart.fill" : "heart").font(.system(size: 10, weight: .heavy)).foregroundStyle(i < level.hearts ? SK.pink : SK.muted.opacity(0.5))
                    }
                }
            }
        }
        .padding(.horizontal, 10).frame(minHeight: 30)
        .background(Capsule().fill(Color.white.opacity(0.85)))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(j.name): \(level == .stranger ? "not yet friends" : level.title) with \(friend)")
        .accessibilityIdentifier("friends-chip-\(j.id)")
    }
}

/// Chips that wrap onto new lines (the roster has up to three Jelbies; long names wrap instead of clipping).
struct ChipFlow: Layout {
    var spacing: CGFloat = 6
    var lineSpacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxW = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, lineH: CGFloat = 0, width: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x > 0, x + s.width > maxW { y += lineH + lineSpacing; x = 0; lineH = 0 }
            x += s.width + spacing; lineH = max(lineH, s.height); width = max(width, x - spacing)
        }
        return CGSize(width: width, height: y + lineH)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, lineH: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x > bounds.minX, x + s.width > bounds.maxX { y += lineH + lineSpacing; x = bounds.minX; lineH = 0 }
            v.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(s))
            x += s.width + spacing; lineH = max(lineH, s.height)
        }
    }
}
