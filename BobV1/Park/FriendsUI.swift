//
//  FriendsUI.swift
//  Asking a friend over (2026-10-25): the Town's Friends page (the visitors who are Friends of the Jelbies, each with "Play date" and "Sleepover"), the invite
//  chooser that a visitor's card at the Park shares, and the guest's own card at home (a tap on him). Rules: Park/GameCare+Guest.swift. Views only.
//

import SwiftUI

/// "Invite over": one button that opens the two choices (Play date / Sleepover). Used on a visitor's card.
struct InviteChooser: View {
    let care: GameCare
    let visitorID: Int
    var after: () -> Void = {}
    @State private var choosing = false

    var body: some View {
        if !choosing {
            Button { AudioHub.shared.uiTap(); withAnimation(.easeInOut(duration: 0.2)) { choosing = true } } label: {
                HStack(spacing: 8) { Image(systemName: "house.fill"); Text("Invite over") }
                    .font(SK.font(16, .black)).foregroundStyle(.white).frame(maxWidth: .infinity, minHeight: 46)
                    .background(Capsule().fill(SK.pinkStrong))
            }
            .buttonStyle(.plain).accessibilityIdentifier("invite-over")
        } else {
            VStack(spacing: 6) {
                HStack(spacing: 8) {
                    choice(.playDate)
                    choice(.sleepover)
                }
                Button { AudioHub.shared.uiTap(); withAnimation(.easeInOut(duration: 0.2)) { choosing = false } } label: {
                    Text("Not now").font(SK.font(13, .heavy)).foregroundStyle(SK.muted).frame(maxWidth: .infinity, minHeight: 36)
                }
                .buttonStyle(.plain).accessibilityIdentifier("invite-cancel")
            }
        }
    }

    private func choice(_ kind: GuestVisit.Kind) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .soft).impactOccurred()
            if care.inviteFriend(visitorID, kind: kind) { after() }
        } label: {
            VStack(spacing: 2) {
                HStack(spacing: 6) { Image(systemName: kind.symbol); Text(kind.title) }.font(SK.font(15, .black))
                Text(kind == .playDate ? "10 to 15 minutes" : "Until morning").font(SK.font(11, .bold)).opacity(0.75)
            }
            .foregroundStyle(SK.ink).frame(maxWidth: .infinity, minHeight: 52)
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(SK.honey))
        }
        .buttonStyle(.plain).accessibilityLabel(kind.title).accessibilityHint(kind.blurb).accessibilityIdentifier("invite-\(kind.rawValue)")
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
        if let cur = care.guestBook.visit, let v = care.parkBook.visitor(cur.visitor) {
            HStack(spacing: 12) {
                Circle().fill(tint(v.colour)).frame(width: 40, height: 40).overlay(Circle().strokeBorder(Color.white.opacity(0.8), lineWidth: 2))
                VStack(alignment: .leading, spacing: 2) {
                    Text(cur.arrived ? "\(v.name) is visiting" : "\(v.name) is on the way").font(SK.font(17, .black)).foregroundStyle(SK.ink)
                    Text(cur.kind.title).font(SK.font(12, .heavy)).foregroundStyle(SK.muted)
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
            .accessibilityElement(children: .combine)
        }
    }

    private func row(_ v: ParkVisitor) -> some View {
        let lvl = v.bestLevel(among: care.jellies.map(\.character))
        let free = care.guestBook.visit == nil
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Circle().fill(tint(v.colour)).frame(width: 44, height: 44).overlay(Circle().strokeBorder(Color.white.opacity(0.8), lineWidth: 2))
                VStack(alignment: .leading, spacing: 1) {
                    Text(v.name).font(SK.font(20, .black)).foregroundStyle(SK.ink)
                    Text(v.style.word).font(SK.font(12, .heavy)).foregroundStyle(SK.muted)
                }
                Spacer(minLength: 4)
                HStack(spacing: 2) {
                    ForEach(0..<3, id: \.self) { i in
                        Image(systemName: i < lvl.hearts ? "heart.fill" : "heart").font(.system(size: 14, weight: .heavy)).foregroundStyle(i < lvl.hearts ? SK.pink : SK.muted.opacity(0.5))
                    }
                }
                Text(lvl.title).font(SK.font(12, .heavy)).foregroundStyle(SK.muted)
            }
            HStack(spacing: 8) {
                ForEach([GuestVisit.Kind.playDate, .sleepover], id: \.self) { kind in
                    Button {
                        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
                        if care.inviteFriend(v.id, kind: kind) { goHome() }
                    } label: {
                        HStack(spacing: 6) { Image(systemName: kind.symbol); Text(kind.title) }
                            .font(SK.font(15, .black)).foregroundStyle(SK.ink).frame(maxWidth: .infinity, minHeight: 46)
                            .background(Capsule().fill(SK.honey.opacity(free ? 1 : 0.4)))
                    }
                    .buttonStyle(.plain).disabled(!free).accessibilityLabel("\(kind.title) with \(v.name)").accessibilityIdentifier("friends-\(kind.rawValue)-\(v.id)")
                }
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(SK.card).shadow(color: SK.shadow.opacity(0.10), radius: 5, y: 2))
    }
}
