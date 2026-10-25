//
//  ParkChrome.swift
//  The park outing's screen furniture: the picker (who comes along), the white veil, the top bar (the Park chip, the Drops pill, a dot per visitor), a visitor's card
//  (a bottom card in portrait, a trailing panel in landscape), the Go home button at the bottom and the toast. Views only; GameCare+Park.swift owns the rules.
//

import SwiftUI

struct ParkChrome: View {
    let care: GameCare
    @Environment(\.verticalSizeClass) private var vsc
    private var park: ParkTrip { care.park }
    private var book: ParkBook { care.parkBook }

    private func tint(_ c: ParkColour) -> Color { Color(red: Double(c.swatch.x), green: Double(c.swatch.y), blue: Double(c.swatch.z)) }
    private func jellyTint(_ slot: Int) -> Color {
        let t = JellyRoster.tint(care.jelly(slot)?.character ?? slot)
        return Color(red: Double(t.x), green: Double(t.y), blue: Double(t.z))
    }

    var body: some View {
        let _ = book.revision          // (the visitors' levels and text: read through `revision`)
        GeometryReader { g in
            ZStack {
                if park.picking { picker }
                if park.inScene {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(alignment: .top) {
                            HStack(spacing: 7) {
                                Image(systemName: "tree.fill").font(.system(size: 15, weight: .heavy))
                                Text("Park").font(SK.font(17, .black))
                            }
                            .foregroundStyle(SK.ink).padding(.horizontal, 14).frame(minHeight: 44)
                            .background(Capsule().fill(SK.cream).shadow(color: SK.shadow.opacity(0.2), radius: 5, y: 2))
                            .overlay(Capsule().strokeBorder(Color.white.opacity(0.5), lineWidth: 1))
                            .accessibilityElement(children: .ignore).accessibilityLabel("Park").accessibilityIdentifier("park-chip")
                            Spacer()
                            DropsPill(wallet: care.bath.wallet)
                        }
                        friends
                        Spacer()
                    }
                    .padding(.horizontal, 16).padding(.top, 8)
                }
                if park.phase == .playing {
                    if let vid = park.card, let v = book.visitor(vid) {
                        if vsc == .compact {
                            HStack { Spacer(); VisitorCard(care: care, visitor: v).frame(width: min(320, g.size.width * 0.38)).padding(.top, 112).padding(.bottom, 80).padding(.trailing, 8) }
                                .transition(.move(edge: .trailing).combined(with: .opacity))
                        } else {
                            VStack { Spacer(); VisitorCard(care: care, visitor: v).fixedSize(horizontal: false, vertical: true).padding(.horizontal, 10).padding(.bottom, 84) }
                                .transition(.move(edge: .bottom).combined(with: .opacity))
                        }
                    }
                    VStack {
                        Spacer()
                        Button { UIImpactFeedbackGenerator(style: .soft).impactOccurred(); AudioHub.shared.uiTap(); park.goHome() } label: {
                            HStack(spacing: 8) { Image(systemName: "house.fill"); Text("Go home") }
                                .font(SK.font(19, .black)).foregroundStyle(SK.ink)
                                .padding(.horizontal, 26).frame(minHeight: 54)
                                .background(Capsule().fill(SK.honey).shadow(color: SK.shadow.opacity(0.25), radius: 7, y: 3))
                        }
                        .buttonStyle(.plain).accessibilityIdentifier("park-home")
                    }
                    .padding(.bottom, 24)
                    .transition(.opacity)
                }
                if let t = park.toast {
                    VStack {
                        Spacer()
                        HStack {
                            Text(t).font(SK.font(15, .heavy)).foregroundStyle(SK.ink).multilineTextAlignment(.leading)
                                .padding(.horizontal, 16).padding(.vertical, 10)
                                .background(Capsule().fill(SK.cream).shadow(color: SK.shadow.opacity(0.22), radius: 6, y: 2))
                                .accessibilityIdentifier("park-toast")
                            Spacer(minLength: 20)
                        }
                        .padding(.leading, 16).padding(.bottom, park.phase == .playing ? 92 : 24)
                    }
                    .allowsHitTesting(false).transition(.opacity)
                }
                Color.white.opacity(Double(park.wipe)).ignoresSafeArea().allowsHitTesting(park.wipe > 0).accessibilityHidden(true)
            }
            .frame(width: g.size.width, height: g.size.height)
            .animation(.easeInOut(duration: 0.25), value: park.card)
            .animation(.easeInOut(duration: 0.25), value: park.phase == .playing)
            .animation(.easeInOut(duration: 0.2), value: park.toast)
            .onChange(of: park.toast) { _, t in if let t { A11yAnnounce.say(t) } }
        }
        .allowsHitTesting(park.active || park.toast != nil)
    }

    /// A dot per visitor in the park: tap one for his card (also the way in for VoiceOver).
    private var friends: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(book.cast, id: \.self) { vid in
                    if let v = book.visitor(vid) {
                        let best = book.comers.compactMap { care.jelly($0)?.character }.map { v.level(with: $0) }.max() ?? .stranger
                        Button { care.parkOpenCard(vid) } label: {
                            HStack(spacing: 6) {
                                Circle().fill(tint(v.colour)).frame(width: 22, height: 22).overlay(Circle().strokeBorder(Color.white.opacity(0.8), lineWidth: 1.5))
                                Text(v.name).font(SK.font(13, .heavy)).foregroundStyle(SK.ink).lineLimit(1)
                                if best > .stranger { Image(systemName: "heart.fill").font(.system(size: 11, weight: .heavy)).foregroundStyle(SK.pink) }
                            }
                            .padding(.horizontal, 10).frame(minHeight: 40)
                            .background(Capsule().fill(park.card == vid ? SK.honey : SK.cream.opacity(0.92)))
                        }
                        .buttonStyle(.plain).accessibilityLabel("\(v.name), \(best.title)").accessibilityIdentifier("park-friend-\(vid)")
                    }
                }
            }
            .padding(.vertical, 2)
        }
        .accessibilityIdentifier("park-friends")
    }

    /// Who comes along: a chip per Jelbie (all on to start), then Go.
    private var picker: some View {
        ZStack {
            Color(red: 0.30, green: 0.20, blue: 0.14).opacity(0.28).ignoresSafeArea().onTapGesture { park.cancelPicker() }.accessibilityHidden(true)
            VStack(spacing: 12) {
                HStack {
                    Image(systemName: "tree.fill").font(.system(size: 20, weight: .heavy)).foregroundStyle(SK.ink)
                    Text("Who comes to the park?").font(SK.font(20, .black)).foregroundStyle(SK.ink)
                    Spacer(minLength: 0)
                }
                Text("Pick one to three. Visitors are there to meet.").font(SK.font(13, .bold)).foregroundStyle(SK.muted).frame(maxWidth: .infinity, alignment: .leading)
                HStack(spacing: 8) {
                    ForEach(care.jellies, id: \.id) { j in
                        let on = park.picked.contains(j.id)
                        Button {
                            AudioHub.shared.uiTap()
                            if on { if park.picked.count > 1 { park.picked.removeAll { $0 == j.id } } }
                            else { park.picked.append(j.id); park.picked.sort() }
                        } label: {
                            HStack(spacing: 7) {
                                Circle().fill(jellyTint(j.id)).frame(width: 22, height: 22).overlay(Circle().strokeBorder(Color.white.opacity(0.7), lineWidth: 1.5))
                                Text(j.name).font(SK.font(15, .heavy)).foregroundStyle(SK.ink).lineLimit(1)
                                Image(systemName: on ? "checkmark.circle.fill" : "circle").font(.system(size: 15, weight: .bold)).foregroundStyle(SK.ink)
                            }
                            .padding(.horizontal, 12).frame(minHeight: 44)
                            .background(Capsule().fill(on ? SK.honey : Color.white.opacity(0.8)))
                        }
                        .buttonStyle(.plain).accessibilityLabel(j.name).accessibilityAddTraits(on ? .isSelected : []).accessibilityIdentifier("park-pick-\(j.id)")
                    }
                    Spacer(minLength: 0)
                }
                HStack(spacing: 10) {
                    Button { AudioHub.shared.uiTap(); park.cancelPicker() } label: {
                        Text("Not now").font(SK.font(16, .heavy)).foregroundStyle(SK.muted).padding(.horizontal, 18).frame(minHeight: 48)
                            .background(Capsule().fill(Color.white.opacity(0.8)))
                    }
                    .buttonStyle(.plain).accessibilityIdentifier("park-cancel")
                    Button { UIImpactFeedbackGenerator(style: .soft).impactOccurred(); care.startPark() } label: {
                        HStack(spacing: 8) { Image(systemName: "figure.walk"); Text("Go to the park") }
                            .font(SK.font(18, .black)).foregroundStyle(.white).frame(maxWidth: .infinity, minHeight: 48)
                            .background(Capsule().fill(SK.pinkStrong))
                    }
                    .buttonStyle(.plain).accessibilityIdentifier("park-go")
                }
            }
            .padding(16).frame(maxWidth: 440)
            .background(RoundedRectangle(cornerRadius: 26, style: .continuous).fill(SK.cream).shadow(color: SK.shadow.opacity(0.25), radius: 10, y: 4))
            .padding(.horizontal, 16)
            .accessibilityElement(children: .contain).accessibilityIdentifier("park-picker")
        }
        .transition(.opacity)
    }
}

/// A visitor: his name and style, one line about him, how much each of the player's Jelbies and he like each other, and what he says hello with.
struct VisitorCard: View {
    let care: GameCare
    let visitor: ParkVisitor

    var body: some View {
        let c = visitor.colour.swatch
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Circle().fill(Color(red: Double(c.x), green: Double(c.y), blue: Double(c.z))).frame(width: 30, height: 30).overlay(Circle().strokeBorder(Color.white.opacity(0.8), lineWidth: 2))
                VStack(alignment: .leading, spacing: 1) {
                    Text(visitor.name).font(SK.font(20, .black)).foregroundStyle(SK.ink)
                    Text("\(visitor.style.word)").font(SK.font(12, .heavy)).foregroundStyle(SK.muted)
                }
                Spacer(minLength: 0)
                Button { AudioHub.shared.uiTap(); care.park.card = nil } label: {
                    Image(systemName: "xmark").font(.system(size: 13, weight: .black)).foregroundStyle(SK.ink).frame(width: 40, height: 40).background(Circle().fill(Color.white.opacity(0.85)))
                }
                .buttonStyle(.plain).accessibilityLabel("Close").accessibilityIdentifier("park-card-close")
            }
            Text(visitor.blurb).font(SK.font(13, .bold)).foregroundStyle(SK.ink).fixedSize(horizontal: false, vertical: true)
            ForEach(care.parkBook.comers, id: \.self) { slot in
                if let prof = care.jelly(slot) {
                    let lvl = visitor.level(with: prof.character)
                    HStack(spacing: 8) {
                        Text(prof.name).font(SK.font(14, .heavy)).foregroundStyle(SK.ink).lineLimit(1)
                        Spacer(minLength: 4)
                        HStack(spacing: 2) {
                            ForEach(0..<3, id: \.self) { i in
                                Image(systemName: i < lvl.hearts ? "heart.fill" : "heart").font(.system(size: 14, weight: .heavy)).foregroundStyle(i < lvl.hearts ? SK.pink : SK.muted.opacity(0.5))
                            }
                        }
                        Text(lvl.title).font(SK.font(12, .heavy)).foregroundStyle(SK.muted).frame(minWidth: 70, alignment: .trailing)
                    }
                    .accessibilityElement(children: .combine).accessibilityLabel("\(prof.name): \(lvl.title)")
                }
            }
            Text("\u{201C}\(visitor.greeting)\u{201D}").font(SK.font(14, .heavy)).foregroundStyle(SK.ink)
                .padding(.horizontal, 12).padding(.vertical, 8).frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.white.opacity(0.7)))
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(SK.cream).shadow(color: SK.shadow.opacity(0.25), radius: 8, y: 3))
        .accessibilityElement(children: .contain).accessibilityIdentifier("park-card")
    }
}
