//
//  CafeChrome.swift
//  The café outing's screen furniture: the white veil, the top bar (Go home top-left, the Café chip, the music button and the Drops pill), the itemized order card
//  (a bottom card in portrait, a trailing panel in landscape; it stays up while they eat, with a tick for each Jelbie who is served), the thought bubbles over the
//  Jelbies at the table, the "That was yummy!" pill and the blocked-entry toast. Views only; GameCare+Cafe.swift owns the rules.
//

import SwiftUI

struct CafeChrome: View {
    let care: GameCare
    @Environment(\.verticalSizeClass) private var vsc
    @State private var soundOpen = UserDefaults.standard.integer(forKey: "CafeSoundOpen") != 0
    private var cafe: CafeTrip { care.cafe }
    private var cardHidden: Bool { UserDefaults.standard.bool(forKey: "CafeCardHidden") }

    var body: some View {
        GeometryReader { g in
            ZStack {
                if cafe.inScene, !cardHidden || cafe.phase != .menu { CafeThoughts(care: care).allowsHitTesting(false) }
                if cafe.inScene {
                    VStack {
                        HStack(alignment: .top, spacing: 8) {
                            if cafe.canGoHome { goHomeButton.transition(.opacity) }
                            if !cafe.canGoHome || vsc == .compact {
                                HStack(spacing: 7) {
                                    Image(systemName: "cup.and.saucer.fill").font(.system(size: 15, weight: .heavy))
                                    Text("Café").font(SK.font(17, .black)).lineLimit(1).fixedSize()
                                }
                                .foregroundStyle(SK.ink).padding(.horizontal, 14).frame(minHeight: 44)
                                .background(Capsule().fill(SK.cream).shadow(color: SK.shadow.opacity(0.2), radius: 5, y: 2))
                                .overlay(Capsule().strokeBorder(Color.white.opacity(0.5), lineWidth: 1))
                                .accessibilityElement(children: .ignore).accessibilityLabel("Café").accessibilityIdentifier("cafe-chip")
                            }
                            Spacer(minLength: 4)
                            musicButton
                            DropsPill(wallet: care.bath.wallet).fixedSize()
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 16).padding(.top, 8)
                    .allowsHitTesting(true)
                }
                if cafe.listOpen, !cardHidden {          // the order stack: above the menu (portrait: in the wall band above the Jelbies), beside it on the left in landscape
                    if vsc == .compact {
                        HStack { CafeOrderStack(care: care, compact: true).frame(width: 200); Spacer() }
                            .padding(.top, 62).padding(.leading, 12).frame(maxHeight: .infinity, alignment: .top)
                    } else {
                        VStack { CafeOrderStack(care: care, compact: false).padding(.horizontal, 22); Spacer() }
                            .padding(.top, g.size.height * 0.2)
                    }
                }
                if cafe.menuOpen, !cardHidden {          // the menu: the old card, a bottom card in portrait and a trailing panel in landscape
                    if vsc == .compact {
                        HStack { Spacer(); CafeMenuCard(care: care, compact: true).frame(width: min(360, g.size.width * 0.44)).padding(.top, 58).padding(.bottom, 6).padding(.trailing, 8) }
                            .transition(.move(edge: .trailing).combined(with: .opacity))
                    } else {
                        VStack { Spacer(); CafeMenuCard(care: care, compact: false).fixedSize(horizontal: false, vertical: true).padding(.horizontal, 10).padding(.bottom, 6) }
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
                if cafe.phase == .done {
                    VStack(spacing: 8) {
                        Spacer()
                        Text("That was yummy!").font(SK.font(15, .heavy)).foregroundStyle(SK.ink)
                            .padding(.horizontal, 14).padding(.vertical, 6).background(Capsule().fill(SK.cream.opacity(0.92)))
                        Button { UIImpactFeedbackGenerator(style: .soft).impactOccurred(); AudioHub.shared.uiTap(); cafe.goHome() } label: {
                            HStack(spacing: 8) { Image(systemName: "house.fill"); Text("Go home") }
                                .font(SK.font(19, .black)).foregroundStyle(SK.ink)
                                .padding(.horizontal, 26).frame(minHeight: 54)
                                .background(Capsule().fill(SK.honey).shadow(color: SK.shadow.opacity(0.25), radius: 6, y: 3))
                        }
                        .buttonStyle(.plain).accessibilityLabel("Go home").accessibilityIdentifier("cafe-go-home-done")
                    }
                    .padding(.bottom, 24).frame(maxWidth: vsc == .compact ? g.size.width * 0.5 : .infinity, alignment: .center)
                    .frame(maxWidth: .infinity, alignment: vsc == .compact ? .leading : .center)
                    .transition(.opacity)
                }
                if soundOpen, cafe.inScene {
                    VStack {
                        HStack { Spacer(); SoundSettingsPanel(hub: AudioHub.shared) { withAnimation(CareMenu.spring) { soundOpen = false } } }
                        Spacer()
                    }
                    .padding(.top, 60).padding(.trailing, 12)
                    .transition(.scale(scale: 0.9, anchor: .topTrailing).combined(with: .opacity))
                }
                if let r = cafe.refusal {
                    VStack {
                        Spacer()
                        HStack {
                            Text(r).font(SK.font(15, .heavy)).foregroundStyle(SK.ink).multilineTextAlignment(.leading)
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
            .animation(.easeInOut(duration: 0.25), value: cafe.canGoHome)
            .animation(.easeInOut(duration: 0.25), value: cafe.phase == .done)
            .animation(.easeInOut(duration: 0.2), value: cafe.refusal)
        }
        .allowsHitTesting(cafe.active || cafe.refusal != nil)
    }

    /// Top-left, from the moment the café fades in until the end: leaves the café (mid-meal too: GameCare cleans up under the white).
    private var goHomeButton: some View {
        Button { UIImpactFeedbackGenerator(style: .soft).impactOccurred(); AudioHub.shared.uiTap(); cafe.goHome() } label: {
            HStack(spacing: 6) {
                Image(systemName: "chevron.left").font(.system(size: 15, weight: .heavy))
                Text("Go home").font(SK.font(16, .black)).lineLimit(1).fixedSize()
            }
            .foregroundStyle(SK.ink).padding(.horizontal, 14).frame(minHeight: 44)
            .background(Capsule().fill(SK.honey).shadow(color: SK.shadow.opacity(0.22), radius: 5, y: 2))
        }
        .buttonStyle(.plain).accessibilityLabel("Go home").accessibilityHint("Leaves the café").accessibilityIdentifier("cafe-go-home")
    }

    /// The same look as the home HUD's sound button; opens the Sound panel (Skip cycles the café playlist).
    private var musicButton: some View {
        Button {
            AudioHub.shared.uiTap()
            withAnimation(CareMenu.spring) { soundOpen.toggle() }
        } label: {
            Image(systemName: soundOpen ? "speaker.wave.2.fill" : "speaker.wave.2").font(.system(size: 21, weight: .semibold)).foregroundStyle(CareMenu.brown)
                .frame(width: 48, height: 44)
                .background(Capsule().fill(SK.cream).shadow(color: SK.shadow.opacity(0.2), radius: 5, y: 2))
                .overlay(Capsule().strokeBorder(Color.white.opacity(0.5), lineWidth: 1))
        }
        .buttonStyle(.plain).accessibilityLabel("Sound").accessibilityHint("Music and sound settings").accessibilityValue(soundOpen ? "expanded" : "collapsed")
        .accessibilityIdentifier("cafe-sound-button")
    }
}

// MARK: - the order stack (above the menu)

/// One rounded row per Jelbie who has a pick (or, after Order, per Jelbie: the receipt with a tick once he is served): his face, name, the treat's icon and name and the price.
/// It grows as picks are made (a gentle spring), re-picking updates the row in place, and a tap on a row selects that Jelbie in the menu. "Same for everyone" shows a row for
/// everybody with the price struck through and the 15 % off.
struct CafeOrderStack: View {
    let care: GameCare
    var compact: Bool
    private var cafe: CafeTrip { care.cafe }
    private var editing: Bool { cafe.phase == .menu }
    private var ids: [Int] { Array(care.cafeDinerIDs.prefix(DiningGroup.maxDiners)) }
    private var special: CafeTreatID? { cafe.special ?? care.cafeSpecial }

    private func treat(_ id: Int) -> CafeTreatID? {
        if !editing { return cafe.order?.treat(for: id) }
        if cafe.draftTable { return cafe.draft[ids.first ?? 0] ?? cafe.draft.values.first }
        return cafe.draft[id]
    }
    private var rows: [(id: Int, treat: CafeTreatID)] { ids.compactMap { id in treat(id).map { (id, $0) } } }

    var body: some View {
        VStack(spacing: 4) {
            ForEach(rows, id: \.id) { r in row(r.id, r.treat).transition(.scale(scale: 0.85, anchor: .top).combined(with: .opacity)) }
        }
        .animation(.spring(response: 0.38, dampingFraction: 0.72), value: rows.map { "\($0.id)\($0.treat.rawValue)" })
        .accessibilityElement(children: .contain).accessibilityIdentifier("cafe-orders")
    }

    private func row(_ id: Int, _ t: CafeTreatID) -> some View {
        let served = cafe.served.contains(id), active = editing && !cafe.draftTable && cafe.draftWho == id
        let base = CafeMenu.price(t, special: special)
        let off = cafe.draftTable && editing || (!editing && (cafe.order?.forTable != nil))
        let paid = off ? Int((Double(base) * CafeTuning.tableDiscount).rounded(.down)) : base
        return Button { if editing { AudioHub.shared.uiTap(); cafe.draftWho = id; cafe.draftTable = false } } label: {
            HStack(spacing: 7) {
                JelbiePortrait(care: care, who: id, size: compact ? 28 : 30, head: true).accessibilityHidden(true)
                Text(care.jelly(id)?.name ?? "Jelbie").font(SK.font(13, .heavy)).foregroundStyle(SK.ink).lineLimit(1).minimumScaleFactor(0.7)
                Spacer(minLength: 2)
                thumb(t, size: 22)
                if !(compact && off) { Text(CafeMenu.treat(t).name).font(SK.font(compact ? 11 : 12, .bold)).foregroundStyle(SK.ink).lineLimit(1).minimumScaleFactor(0.5) }
                HStack(spacing: 2) {
                    JellyCoinIcon(size: 13)
                    if base != paid, !compact { Text("\(base)").font(SK.font(10, .bold)).foregroundStyle(SK.muted).strikethrough().monospacedDigit().lineLimit(1).fixedSize() }
                    Text(cafe.wasFree && !editing ? "0" : "\(paid)").font(SK.font(13, .black)).foregroundStyle(SK.ink).monospacedDigit().lineLimit(1).fixedSize()
                    if off && base != paid { Text("\u{2212}15%").font(SK.font(8, .black)).foregroundStyle(.white).padding(.horizontal, 3).padding(.vertical, 1).background(Capsule().fill(SK.pinkStrong)).fixedSize() }
                }
                if !editing {
                    Image(systemName: served ? "checkmark.circle.fill" : "circle.dotted").font(.system(size: 18, weight: .heavy))
                        .foregroundStyle(served ? Color(hex: 0x3E9B63) : SK.muted).contentTransition(.symbolEffect(.replace))
                }
            }
            .padding(.horizontal, 8).frame(minHeight: 36)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(SK.cream.opacity(0.97)).shadow(color: SK.shadow.opacity(0.22), radius: 4, y: 2))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(active ? SK.honeyDeep : Color.white.opacity(0.6), lineWidth: active ? 2 : 1))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(care.jelly(id)?.name ?? "Jelbie"): \(CafeMenu.treat(t).name), \(paid) JellyCoins\(!editing ? (served ? ", served" : ", on the way") : "")")
        .accessibilityHint(editing ? "Picks this Jelbie in the menu" : "").accessibilityIdentifier("cafe-order-\(id)")
    }

    private func thumb(_ t: CafeTreatID, size: CGFloat) -> some View {
        Group {
            if let img = StoreThumb.image("cafe-\(t.rawValue)", mesh: DiningModels.heldPiece(Consumables.cafeFood(t), index: 0, scale: 1.25)) { Image(uiImage: img).resizable().scaledToFit() }
            else { Image(systemName: Consumables.cafeFood(t).symbol).foregroundStyle(SK.ink) }
        }
        .frame(width: size, height: size).accessibilityHidden(true)
    }
}

// MARK: - the menu card (the old card: name chips, the treats, Same for everyone, the total, Order)

struct CafeMenuCard: View {
    let care: GameCare
    var compact: Bool
    @State private var refusal: String?
    private var cafe: CafeTrip { care.cafe }
    private var ids: [Int] { Array(care.cafeDinerIDs.prefix(DiningGroup.maxDiners)) }
    private var picks: [Int: CafeTreatID] { cafe.draft }
    private var table: Bool { cafe.draftTable }
    private var who: Int { cafe.draftWho }
    private var special: CafeTreatID? { cafe.special ?? care.cafeSpecial }
    private var order: CafeOrder { table ? CafeOrder(picks: [:], forTable: picks[ids.first ?? 0] ?? picks.values.first) : CafeOrder(picks: picks) }
    private var free: Bool { cafe.stamps.isFull }
    private var total: Int { free ? 0 : order.total(jellies: ids, special: special) }
    private var complete: Bool { order.isComplete(jellies: ids) }
    private func tint(_ id: Int) -> Color {
        let t = JellyRoster.tint(care.jelly(id)?.character ?? id)
        return Color(red: Double(t.x), green: Double(t.y), blue: Double(t.z))
    }
    private func name(_ id: Int) -> String { care.jelly(id)?.name ?? "Jelbie" }
    private var fullNote: String? {
        if table { let f = ids.filter { !care.cafeCanEat($0) }; return f.isEmpty ? nil : "\(f.map(name).joined(separator: " & ")) full" }
        return care.cafeCanEat(who) ? nil : "\(name(who))'s full"
    }

    private var tableToggle: some View {
        Button { AudioHub.shared.uiTap(); cafe.draftTable.toggle(); refusal = nil } label: {
            HStack(spacing: 6) {
                Image(systemName: table ? "checkmark.circle.fill" : "circle").font(.system(size: 15, weight: .bold))
                Text(compact ? "All same" : "Same for everyone").font(SK.font(12, .heavy)).lineLimit(1).fixedSize()
                if table || !(free || compact) { Text("-15%").font(SK.font(11, .black)).foregroundStyle(SK.muted).lineLimit(1).fixedSize() }
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
            Text("Order").font(SK.font(17, .black)).foregroundStyle(.white).lineLimit(1).fixedSize()
                .padding(.horizontal, 16).frame(minHeight: 44)
                .background(Capsule().fill(SK.pinkStrong.opacity(complete ? 1 : 0.4)))
        }
        .buttonStyle(.plain).disabled(!complete).accessibilityIdentifier("cafe-order")
        .accessibilityHint(complete ? "Places the order" : "Choose a treat for every Jelbie first")
    }
    private var totalView: some View {
        Group {
            if free {
                VStack(alignment: .trailing, spacing: 0) {
                    Text("Free").font(SK.font(17, .black)).foregroundStyle(SK.pinkStrong)
                    Text("stamp card").font(SK.font(10, .heavy)).foregroundStyle(SK.pinkStrong).lineLimit(1).fixedSize()
                }
            } else {
                HStack(spacing: 4) {
                    JellyCoinIcon(size: 18)
                    Text("\(total)").font(SK.font(18, .black)).foregroundStyle(SK.ink).monospacedDigit()
                }
            }
        }
        .accessibilityElement(children: .ignore).accessibilityLabel(free ? "Free, stamp card" : "\(total) JellyCoins").accessibilityIdentifier("cafe-total")
    }

    private var stampRow: some View {
        let n = cafe.stamps.card.count, full = cafe.stamps.isFull
        return HStack(spacing: 3) {
            ForEach(0..<CafeStamps.slots, id: \.self) { i in
                let gift = i == CafeStamps.slots - 1          // the 8th slot is the free order
                let on = gift ? full : i < n
                ZStack {
                    Circle().fill(Color.white.opacity(0.7))
                        .overlay(Image(systemName: gift ? "gift.fill" : "pawprint.fill").font(.system(size: 9, weight: .heavy)).foregroundStyle(gift ? SK.pinkStrong.opacity(0.7) : SK.muted.opacity(0.35)))
                        .overlay(Circle().strokeBorder(gift ? SK.pinkStrong.opacity(0.5) : SK.muted.opacity(0.25), lineWidth: 1.5))
                    if on {          // the stamp lands: it drops in big and settles
                        Circle().fill(SK.honey)
                            .overlay(Image(systemName: gift ? "gift.fill" : "pawprint.fill").font(.system(size: 9, weight: .heavy)).foregroundStyle(SK.ink))
                            .overlay(Circle().strokeBorder(SK.honeyDeep, lineWidth: 1.5))
                            .transition(.scale(scale: 2.2).combined(with: .opacity))
                    }
                }
                .frame(width: 19, height: 19)
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.5), value: n)
        .accessibilityElement(children: .ignore).accessibilityLabel("Stamp card: \(n) of \(CafeStamps.paidVisits)\(full ? ", the next order is free" : "")").accessibilityIdentifier("cafe-stamps")
    }

    var body: some View {
        VStack(spacing: 8) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(free ? "Free order!" : "Café menu").font(SK.font(compact ? 18 : 20, .black)).foregroundStyle(SK.ink)
                    if let r = refusal ?? cafe.cardRefusal {
                        Text(r).font(SK.font(12, .heavy)).foregroundStyle(Color(hex: 0xB0413E)).fixedSize(horizontal: false, vertical: true).accessibilityIdentifier("cafe-refusal")
                    } else if let n = fullNote {
                        Text(n + " \u{00B7} try a drink").font(SK.font(12, .heavy)).foregroundStyle(Color(hex: 0xB0413E)).lineLimit(1).minimumScaleFactor(0.7).accessibilityIdentifier("cafe-full-note")
                    } else if let sp = special {
                        Text("\(compact ? "Special" : "Daily special"): \(CafeMenu.treat(sp).name) \u{2212}20%").font(SK.font(12, .bold)).foregroundStyle(SK.muted).lineLimit(1).minimumScaleFactor(0.7).accessibilityIdentifier("cafe-special")
                    } else {
                        Text(table ? "One treat for the table" : "A treat for each Jelbie").font(SK.font(12, .bold)).foregroundStyle(SK.muted)
                    }
                }
                Spacer(minLength: 4)
                stampRow
            }
            HStack(spacing: 6) {
                ForEach(ids, id: \.self) { id in
                    let sel = !table && who == id
                    Button { AudioHub.shared.uiTap(); cafe.draftWho = id; cafe.draftTable = false } label: {
                        HStack(spacing: 5) {
                            Circle().fill(tint(id)).frame(width: 12, height: 12).overlay(Circle().strokeBorder(.white.opacity(0.8), lineWidth: 1))
                            Text(name(id)).font(SK.font(13, .heavy)).lineLimit(1).minimumScaleFactor(0.7)
                            if let t = (table ? order.forTable : picks[id]) { thumb(t, size: 20) }
                        }
                        .foregroundStyle(SK.ink).padding(.horizontal, 8).frame(minHeight: 44)
                        .background(Capsule().fill(sel ? SK.honey : Color.white.opacity(0.7)))
                    }
                    .buttonStyle(.plain).accessibilityIdentifier("cafe-who-\(id)")
                    .accessibilityLabel(name(id))
                    .accessibilityValue((table ? order.forTable : picks[id]) != nil ? "treat chosen" : "no treat yet")
                    .accessibilityHint("Choose a treat for this Jelbie")
                    .accessibilityAddTraits(sel ? .isSelected : [])
                }
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: compact ? 5 : 6), count: compact ? 4 : 3), spacing: compact ? 5 : 6) { ForEach(CafeMenu.treats) { treatTile($0) } }
            HStack(spacing: 8) {
                if ids.count > 1 { tableToggle }
                Spacer(minLength: 2)
                totalView
                orderButton
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(SK.cream).shadow(color: SK.shadow.opacity(0.28), radius: 6, y: 3))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(Color.white.opacity(0.6), lineWidth: 1))
        .onAppear {
            if let w = UserDefaults.standard.string(forKey: "CafePicks") {          // capture aid: -CafePicks swirl,juice,latte ("-" skips a Jelbie)
                for (i, n) in w.split(separator: ",", omittingEmptySubsequences: false).enumerated() where ids.indices.contains(i) { if let t = CafeTreatID(rawValue: String(n)) { cafe.draft[ids[i]] = t } }
            }
            if UserDefaults.standard.bool(forKey: "CafeSameForAll") { cafe.draftTable = true }
            cafe.draftWho = ids.first(where: { cafe.draft[$0] == nil }) ?? ids.first ?? 0
        }
        .accessibilityIdentifier("cafe-menu")
    }

    private func pick(_ t: CafeTreat) {
        AudioHub.shared.uiTap(); refusal = nil
        if table { for id in ids { cafe.draft[id] = t.id } }
        else {
            cafe.draft[who] = t.id
            if let next = ids.first(where: { cafe.draft[$0] == nil }) { cafe.draftWho = next }          // on to the next Jelbie without a pick
        }
    }
    private func isChosen(_ t: CafeTreat) -> Bool { table ? order.forTable == t.id : picks[who] == t.id }
    private func available(_ t: CafeTreat) -> Bool {
        if table { return ids.allSatisfy { CafeRules.canOrder(t.id, tier: care.needs(for: $0).tier(.hunger)) } }
        return CafeRules.canOrder(t.id, tier: care.needs(for: who).tier(.hunger))
    }

    private func thumb(_ t: CafeTreatID, size: CGFloat) -> some View {
        Group {
            if let img = StoreThumb.image("cafe-\(t.rawValue)", mesh: DiningModels.heldPiece(Consumables.cafeFood(t), index: 0, scale: 1.25)) {
                Image(uiImage: img).resizable().scaledToFit()
            } else { Image(systemName: Consumables.cafeFood(t).symbol).foregroundStyle(SK.ink) }
        }
        .frame(width: size, height: size)
    }

    /// The old tile (picture, name, price, perk), a little shorter so nine of them fit; greyed for a Jelbie who is full and Food; the daily special wears a badge.
    private func treatTile(_ t: CafeTreat) -> some View {
        let ok = available(t), chosen = isChosen(t), isSpecial = t.id == special
        let now = CafeMenu.price(t.id, special: special)
        return Button { pick(t) } label: {
            VStack(spacing: 0) {
                ZStack(alignment: .topTrailing) {
                    thumb(t.id, size: compact ? 28 : 34).frame(maxWidth: .infinity)
                    if isSpecial { Text("\u{2212}20%").font(SK.font(9, .black)).foregroundStyle(.white).padding(.horizontal, 4).padding(.vertical, 1).background(Capsule().fill(SK.pinkStrong)).fixedSize() }
                }
                Text(t.name).font(SK.font(compact ? 10 : 12, .heavy)).foregroundStyle(SK.ink).lineLimit(compact ? 2 : 1).minimumScaleFactor(0.55).multilineTextAlignment(.center)
                    .frame(height: compact ? 24 : nil)
                HStack(spacing: 3) {
                    JellyCoinIcon(size: compact ? 12 : 14)
                    if isSpecial { Text("\(t.price)").font(SK.font(10, .bold)).foregroundStyle(SK.muted).strikethrough().monospacedDigit() }
                    Text("\(now)").font(SK.font(compact ? 12 : 14, .black)).foregroundStyle(SK.ink).monospacedDigit()
                    if compact { Image(systemName: t.perk.symbol).font(.system(size: 9, weight: .heavy)).foregroundStyle(SK.muted).accessibilityHidden(true) }
                }
                if !compact {
                    HStack(spacing: 2) {
                        Image(systemName: t.perk.symbol).font(.system(size: 9, weight: .heavy))
                        Text(t.perk.title).font(SK.font(10, .heavy)).lineLimit(1).minimumScaleFactor(0.6)
                    }
                    .foregroundStyle(SK.muted)
                }
            }
            .frame(maxWidth: .infinity).padding(.vertical, 4)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(chosen ? SK.honey : Color.white.opacity(0.75)))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(chosen ? SK.honeyDeep : Color.clear, lineWidth: 2))
            .opacity(ok ? 1 : 0.35)
        }
        .buttonStyle(.plain).disabled(!ok).accessibilityIdentifier("cafe-treat-\(t.id.rawValue)")
        .accessibilityLabel("\(t.name), \(now) JellyCoins\(isSpecial ? ", daily special" : ""). \(ok ? t.blurb : "\(name(who)) is full, pick a drink.")")
        .accessibilityAddTraits(chosen ? .isSelected : [])
    }
}

// MARK: - thought bubbles

/// A small thought bubble with an icon over the Jelbie who is thinking (one at a time, 3...5 s): a coffee cup, cocoa, cake, a heart, a note, a sparkle, a friend's face or the stamp card.
struct CafeThoughts: View {
    let care: GameCare

    var body: some View {
        GeometryReader { geo in
            TimelineView(.animation(minimumInterval: 1.0 / 30)) { _ in
                ZStack {
                    if let t = care.cafeBook.thought, let head = ThoughtBubbleView.project(care.bubbleHead(t.who) + SIMD3(0, 0.1, 0), size: geo.size, focus: care.focus.blend) {
                        bubble(t)
                            .scaleEffect(scale(t.age), anchor: .bottom)
                            .opacity(min(1, Double(min(t.age, 1 - t.age)) * 8))
                            .position(x: head.x + 14, y: head.y - 58)
                    }
                }
            }
        }
        .ignoresSafeArea().accessibilityHidden(true)
    }

    private func scale(_ age: Float) -> CGFloat {
        let u = Double(min(age * 5, 1))          // springy pop in the first fifth
        return CGFloat(max(0.01, 1 - exp(-7 * u) * cos(14 * u)))
    }

    private func bubble(_ t: CafeThought) -> some View {
        ZStack {
            Circle().fill(Color.white).frame(width: 9, height: 9).offset(x: -16, y: 38)
            Circle().fill(Color.white).frame(width: 15, height: 15).offset(x: -10, y: 28)
            Capsule().fill(Color.white).frame(width: 64, height: 50)
                .shadow(color: SK.shadow.opacity(0.25), radius: 5, y: 2)
                .overlay(Capsule().strokeBorder(SK.honey.opacity(0.7), lineWidth: 2))
            switch t.icon {
            case .symbol(let name):
                Image(systemName: name).font(.system(size: 26, weight: .bold)).foregroundStyle(color(name))
            case .friend(let id):
                JelbiePortrait(care: care, who: id, size: 34, head: true)
            }
        }
        .frame(width: 80, height: 90)
    }

    private func color(_ s: String) -> Color {
        switch s {
        case "heart.fill": return SK.pinkStrong
        case "sparkles": return SK.honeyDeep
        case "music.note": return Color(hex: 0x7C8FD6)
        case "cup.and.saucer.fill", "mug.fill": return Color(hex: 0x8B5A3C)
        case "birthday.cake.fill": return Color(hex: 0xE98AA4)
        default: return SK.honeyDeep
        }
    }
}
