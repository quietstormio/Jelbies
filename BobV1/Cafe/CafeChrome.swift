//
//  CafeChrome.swift
//  The café outing's screen furniture: the white veil, the top bar (the Café chip and the Drops pill), the menu card (a bottom card in portrait, a trailing panel in
//  landscape), the Head home button after the treats, and the blocked-entry toast. Views only; GameCare+Cafe.swift owns the rules.
//

import SwiftUI

struct CafeChrome: View {
    let care: GameCare
    @Environment(\.verticalSizeClass) private var vsc
    private var cafe: CafeTrip { care.cafe }
    private var cardHidden: Bool { UserDefaults.standard.bool(forKey: "CafeCardHidden") }

    var body: some View {
        GeometryReader { g in
            ZStack {
                if cafe.inScene {
                    VStack {
                        HStack(alignment: .top) {
                            HStack(spacing: 7) {
                                Image(systemName: "cup.and.saucer.fill").font(.system(size: 15, weight: .semibold))
                                Text("Café").font(SK.font(17, .semibold))
                            }
                            .foregroundStyle(SK.ink).padding(.horizontal, 14).frame(minHeight: 44)
                            .background(Capsule().fill(SK.cream).shadow(color: SK.shadow.opacity(0.2), radius: 5, y: 2))
                            .overlay(Capsule().strokeBorder(Color.white.opacity(0.5), lineWidth: 1))
                            .accessibilityElement(children: .ignore).accessibilityLabel("Café").accessibilityIdentifier("cafe-chip")
                            Spacer()
                            DropsPill(wallet: care.bath.wallet)
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 16).padding(.top, 8)
                    .allowsHitTesting(true)
                }
                if cafe.menuOpen, !cardHidden {
                    if vsc == .compact {
                        HStack { Spacer(); CafeMenuCard(care: care, compact: true).frame(width: min(320, g.size.width * 0.36)).padding(.top, 64).padding(.bottom, 8).padding(.trailing, 8) }
                            .transition(.move(edge: .trailing).combined(with: .opacity))
                    } else {
                        VStack { Spacer(); CafeMenuCard(care: care, compact: false).fixedSize(horizontal: false, vertical: true).padding(.horizontal, 10).padding(.bottom, 8) }
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
                if cafe.phase == .done {
                    VStack(spacing: 8) {
                        Spacer()
                        Text("That was yummy!").font(SK.font(15, .semibold)).foregroundStyle(SK.ink)
                            .padding(.horizontal, 14).padding(.vertical, 6).background(Capsule().fill(SK.cream.opacity(0.92)))
                        Button { AudioHub.shared.uiTap(); cafe.goHome() } label: {
                            HStack(spacing: 8) { Image(systemName: "house.fill"); Text("Head home") }
                                .font(SK.font(19, .semibold)).foregroundStyle(SK.ink)
                                .padding(.horizontal, 26).frame(minHeight: 54)
                                .background(Capsule().fill(SK.honey).shadow(color: SK.shadow.opacity(0.25), radius: 7, y: 3))
                        }
                        .buttonStyle(.plain).accessibilityIdentifier("cafe-home")
                    }
                    .padding(.bottom, 24)
                    .transition(.opacity)
                }
                if let r = cafe.refusal {
                    VStack {
                        Spacer()
                        HStack {
                            Text(r).font(SK.font(15, .semibold)).foregroundStyle(SK.ink).multilineTextAlignment(.leading)
                                .padding(.horizontal, 16).padding(.vertical, 10)
                                .background(Capsule().fill(SK.cream).shadow(color: SK.shadow.opacity(0.22), radius: 6, y: 2))
                                .accessibilityIdentifier("cafe-toast")
                            Spacer(minLength: 70)
                        }
                        .padding(.leading, 76).padding(.bottom, 24)
                    }
                    .allowsHitTesting(false).transition(.opacity)
                }
                Color.white.opacity(Double(cafe.wipe)).ignoresSafeArea().allowsHitTesting(cafe.wipe > 0).accessibilityHidden(true)
            }
            .frame(width: g.size.width, height: g.size.height)
            .animation(.easeInOut(duration: 0.25), value: cafe.menuOpen)
            .animation(.easeInOut(duration: 0.25), value: cafe.phase == .done)
            .animation(.easeInOut(duration: 0.2), value: cafe.refusal)
        }
        .allowsHitTesting(cafe.active || cafe.refusal != nil)
    }
}

/// The menu: a chip per Jelbie, the six treats, "Same for everyone", the total, Order and Head home.
struct CafeMenuCard: View {
    let care: GameCare
    var compact: Bool
    @State private var picks: [Int: CafeTreatID] = [:]
    @State private var table = false
    @State private var who = 0
    @State private var refusal: String?

    private var ids: [Int] { Array(care.cafeDinerIDs.prefix(DiningGroup.maxDiners)) }
    private var order: CafeOrder { table ? CafeOrder(picks: [:], forTable: picks[ids.first ?? 0] ?? picks.values.first) : CafeOrder(picks: picks) }
    private var total: Int { order.total(jellies: ids) }
    private var complete: Bool { order.isComplete(jellies: ids) }
    private func tint(_ id: Int) -> Color {
        let t = JellyRoster.tint(care.jelly(id)?.character ?? id)
        return Color(red: Double(t.x), green: Double(t.y), blue: Double(t.z))
    }

    private var homeButton: some View {
        Button { AudioHub.shared.uiTap(); care.cafe.goHome() } label: {
            HStack(spacing: 4) { Image(systemName: "house.fill").font(.system(size: 12, weight: .bold)); Text("Head home").font(SK.font(12, .semibold)).lineLimit(1) }
                .foregroundStyle(SK.muted).padding(.horizontal, 10).frame(minHeight: 44)
                .background(Capsule().fill(Color.white.opacity(0.7)))
        }
        .buttonStyle(.plain).accessibilityIdentifier("cafe-home")
    }
    private var tableToggle: some View {
        Button { AudioHub.shared.uiTap(); table.toggle(); refusal = nil } label: {
            HStack(spacing: 6) {
                Image(systemName: table ? "checkmark.circle.fill" : "circle").font(.system(size: 15, weight: .bold))
                Text("Same for everyone").font(SK.font(13, .semibold)).lineLimit(1).minimumScaleFactor(0.7)
                Text("-15%").font(SK.font(11, .semibold)).foregroundStyle(SK.muted)
            }
            .foregroundStyle(SK.ink).padding(.horizontal, 10).frame(minHeight: 44)
            .background(Capsule().fill(table ? SK.honey : Color.white.opacity(0.7)))
        }
        .buttonStyle(.plain).accessibilityIdentifier("cafe-table")
        .accessibilityLabel("Same for everyone, 15 percent off")
        .accessibilityValue(table ? "on" : "off")
        .accessibilityAddTraits(table ? .isSelected : [])
    }
    private var orderButton: some View {
        Button {
            UIImpactFeedbackGenerator(style: .soft).impactOccurred()
            refusal = care.orderCafe(order)
        } label: {
            Text("Order").font(SK.font(17, .semibold)).foregroundStyle(.white).lineLimit(1).fixedSize()
                .padding(.horizontal, 20).frame(minHeight: 44)
                .background(Capsule().fill(SK.pinkStrong.opacity(complete ? 1 : 0.4)))
        }
        .buttonStyle(.plain).disabled(!complete).accessibilityIdentifier("cafe-order")
        .accessibilityHint(complete ? "Places the order" : "Choose a treat for every Jelbie first")
    }
    private var totalView: some View {
        HStack(spacing: 4) {
            Image(systemName: "drop.fill").font(.system(size: 13, weight: .semibold)).foregroundStyle(SK.skyDeep)
            Text("\(total)").font(SK.font(18, .semibold)).foregroundStyle(SK.ink).monospacedDigit()
        }
        .accessibilityElement(children: .ignore).accessibilityLabel("\(total) Drops").accessibilityIdentifier("cafe-total")
    }

    var body: some View {
        VStack(spacing: 8) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Café menu").font(SK.font(compact ? 18 : 20, .black)).foregroundStyle(SK.ink)
                    if let r = refusal ?? care.cafe.cardRefusal {
                        Text(r).font(SK.font(12, .semibold)).foregroundStyle(Color(hex: 0xB0413E)).fixedSize(horizontal: false, vertical: true).accessibilityIdentifier("cafe-refusal")
                    } else {
                        Text(table ? "One treat for the table" : "A treat for each Jelbie").font(SK.font(12, .bold)).foregroundStyle(SK.muted)
                    }
                }
                Spacer(minLength: 4)
                homeButton
            }
            HStack(spacing: 6) {
                ForEach(ids, id: \.self) { id in
                    let sel = !table && who == id
                    Button { AudioHub.shared.uiTap(); who = id; table = false } label: {
                        HStack(spacing: 5) {
                            Circle().fill(tint(id)).frame(width: 12, height: 12).overlay(Circle().strokeBorder(.white.opacity(0.8), lineWidth: 1))
                            Text(care.jelly(id)?.name ?? "Jelbie").font(SK.font(13, .semibold)).lineLimit(1).minimumScaleFactor(0.7)
                            if let t = (table ? order.forTable : picks[id]) { thumb(t, size: 20) }
                        }
                        .foregroundStyle(SK.ink).padding(.horizontal, 8).frame(minHeight: 44)
                        .background(Capsule().fill(sel ? SK.honey : Color.white.opacity(0.7)))
                    }
                    .buttonStyle(.plain).accessibilityIdentifier("cafe-who-\(id)")
                    .accessibilityLabel(care.jelly(id)?.name ?? "Jelbie")
                    .accessibilityValue((table ? order.forTable : picks[id]) != nil ? "treat chosen" : "no treat yet")
                    .accessibilityHint("Choose a treat for this Jelbie")
                    .accessibilityAddTraits(sel ? .isSelected : [])
                }
            }
            if compact {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 5), GridItem(.flexible(), spacing: 5)], spacing: 5) { ForEach(CafeMenu.treats) { t in treatRow(t) } }
            } else {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 3), spacing: 6) { ForEach(CafeMenu.treats) { t in treatTile(t) } }
            }
            if compact, ids.count > 1 { tableToggle }
            HStack(spacing: 8) {
                if !compact, ids.count > 1 { tableToggle }
                Spacer(minLength: 2)
                totalView
                orderButton
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(SK.cream).shadow(color: SK.shadow.opacity(0.28), radius: 14, y: 4))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(Color.white.opacity(0.6), lineWidth: 1))
        .onAppear { who = ids.first ?? 0 }
        .accessibilityIdentifier("cafe-menu")
    }

    private func pick(_ t: CafeTreat) {
        AudioHub.shared.uiTap(); refusal = nil
        if table { for id in ids { picks[id] = t.id } }
        else {
            picks[who] = t.id
            if let next = ids.first(where: { picks[$0] == nil }) { who = next }          // on to the next Jelbie without a pick
        }
    }
    private func isChosen(_ t: CafeTreat) -> Bool { table ? order.forTable == t.id : picks[who] == t.id }

    /// Landscape: a slim row per treat.
    private func treatRow(_ t: CafeTreat) -> some View {
        Button { pick(t) } label: {
            HStack(spacing: 8) {
                thumb(t.id, size: 30)
                VStack(alignment: .leading, spacing: 0) {
                    Text(t.name).font(SK.font(12, .semibold)).foregroundStyle(SK.ink).lineLimit(1).minimumScaleFactor(0.55)
                    HStack(spacing: 3) {
                        Image(systemName: "drop.fill").font(.system(size: 9, weight: .semibold)).foregroundStyle(SK.skyDeep)
                        Text("\(t.price)").font(SK.font(13, .semibold)).foregroundStyle(SK.ink).monospacedDigit()
                        Image(systemName: t.perk.symbol).font(.system(size: 9, weight: .semibold)).foregroundStyle(SK.muted).accessibilityLabel(t.perk.title)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 6).frame(minHeight: 44)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(isChosen(t) ? SK.honey : Color.white.opacity(0.75)))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(isChosen(t) ? SK.honeyDeep : Color.clear, lineWidth: 2))
        }
        .buttonStyle(.plain).accessibilityIdentifier("cafe-treat-\(t.id.rawValue)")
        .accessibilityLabel("\(t.name), \(t.price) Drops. \(t.blurb)")
        .accessibilityAddTraits(isChosen(t) ? .isSelected : [])
    }

    private func thumb(_ t: CafeTreatID, size: CGFloat) -> some View {
        Group {
            if let img = StoreThumb.image("cafe-\(t.rawValue)", mesh: DiningModels.heldPiece(Consumables.cafeFood(t), index: 0, scale: 1.25)) {
                Image(uiImage: img).resizable().scaledToFit()
            } else { Image(systemName: Consumables.cafeFood(t).symbol).foregroundStyle(SK.ink) }
        }
        .frame(width: size, height: size)
    }

    private func treatTile(_ t: CafeTreat) -> some View {
        let chosen = isChosen(t)
        return Button { pick(t) } label: {
            VStack(spacing: 2) {
                thumb(t.id, size: 40)
                Text(t.name).font(SK.font(12, .semibold)).foregroundStyle(SK.ink).lineLimit(1).minimumScaleFactor(0.5)
                HStack(spacing: 3) {
                    Image(systemName: "drop.fill").font(.system(size: 10, weight: .semibold)).foregroundStyle(SK.skyDeep)
                    Text("\(t.price)").font(SK.font(14, .semibold)).foregroundStyle(SK.ink).monospacedDigit()
                }
                HStack(spacing: 2) {
                    Image(systemName: t.perk.symbol).font(.system(size: 9, weight: .semibold))
                    Text(t.perk.title).font(SK.font(10, .semibold)).lineLimit(1).minimumScaleFactor(0.6)
                }
                .foregroundStyle(SK.muted)
            }
            .frame(maxWidth: .infinity).padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(chosen ? SK.honey : Color.white.opacity(0.75)))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(chosen ? SK.honeyDeep : Color.clear, lineWidth: 2))
        }
        .buttonStyle(.plain).accessibilityIdentifier("cafe-treat-\(t.id.rawValue)")
        .accessibilityLabel("\(t.name), \(t.price) Drops. \(t.blurb)")
        .accessibilityAddTraits(isChosen(t) ? .isSelected : [])
    }
}
