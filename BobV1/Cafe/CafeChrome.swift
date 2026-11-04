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
                            HStack(spacing: 7) {
                                Image(systemName: "cup.and.saucer.fill").font(.system(size: 15, weight: .heavy))
                                Text("Café").font(SK.font(17, .black))
                            }
                            .foregroundStyle(SK.ink).padding(.horizontal, 14).frame(minHeight: 44)
                            .background(Capsule().fill(SK.cream).shadow(color: SK.shadow.opacity(0.2), radius: 5, y: 2))
                            .overlay(Capsule().strokeBorder(Color.white.opacity(0.5), lineWidth: 1))
                            .accessibilityElement(children: .ignore).accessibilityLabel("Café").accessibilityIdentifier("cafe-chip")
                            Spacer()
                            musicButton
                            DropsPill(wallet: care.bath.wallet)
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 16).padding(.top, 8)
                    .allowsHitTesting(true)
                }
                if cafe.listOpen, !cardHidden {
                    if vsc == .compact {
                        HStack { Spacer(); CafeOrderCard(care: care, compact: true, maxHeight: g.size.height - 72).frame(width: min(340, g.size.width * 0.4)).padding(.top, 64).padding(.bottom, 8).padding(.trailing, 8) }
                            .transition(.move(edge: .trailing).combined(with: .opacity))
                    } else {
                        VStack { Spacer(); CafeOrderCard(care: care, compact: false, maxHeight: g.size.height * (cafe.phase == .menu ? 0.6 : 0.3)).padding(.horizontal, 10).padding(.bottom, cafe.phase == .done ? 84 : 18) }
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
                    .padding(.bottom, 24).frame(maxWidth: vsc == .compact ? g.size.width * 0.55 : .infinity, alignment: .center)
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
            .animation(.easeInOut(duration: 0.25), value: cafe.listOpen)
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
                Text("Go home").font(SK.font(16, .black)).lineLimit(1).minimumScaleFactor(0.7)
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

// MARK: - the itemized order card

/// The order: a row per Jelbie (portrait, name, the chosen treat and its price; the active row is honey; tap a row to pick for that Jelbie), the daily special, Food and Drinks
/// (Food is greyed for a Jelbie who is full), the stamp card, the total and Order. After Order the same card stays up as the receipt with a tick per served Jelbie.
struct CafeOrderCard: View {
    let care: GameCare
    var compact: Bool
    var maxHeight: CGFloat
    @State private var picks: [Int: CafeTreatID] = [:]
    @State private var table = false
    @State private var who = 0
    @State private var refusal: String?

    private var cafe: CafeTrip { care.cafe }
    private var editing: Bool { cafe.phase == .menu }
    private var ids: [Int] { Array(care.cafeDinerIDs.prefix(DiningGroup.maxDiners)) }
    private var special: CafeTreatID? { cafe.special ?? care.cafeSpecial }
    private var order: CafeOrder { editing ? (table ? CafeOrder(picks: [:], forTable: picks[ids.first ?? 0] ?? picks.values.first) : CafeOrder(picks: picks)) : (cafe.order ?? CafeOrder()) }
    private var free: Bool { editing ? cafe.stamps.isFull : cafe.wasFree }
    private var total: Int { editing ? (free ? 0 : order.total(jellies: ids, special: special)) : cafe.charged }
    private var complete: Bool { order.isComplete(jellies: ids) }
    private var name: (Int) -> String { { care.jelly($0)?.name ?? "Jelbie" } }

    var body: some View {
        VStack(spacing: 6) {
            ViewThatFits(in: .vertical) {
                scrolled
                ScrollView(.vertical, showsIndicators: false) { scrolled }.scrollBounceBehavior(.basedOnSize)
            }
            footer
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(SK.cream).shadow(color: SK.shadow.opacity(0.28), radius: 6, y: 3))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(Color.white.opacity(0.6), lineWidth: 1))
        .frame(maxHeight: maxHeight)
        .onAppear {
            if let w = UserDefaults.standard.string(forKey: "CafePicks") {          // capture aid: -CafePicks swirl,juice,latte
                for (i, n) in w.split(separator: ",").enumerated() where ids.indices.contains(i) { if let t = CafeTreatID(rawValue: String(n)) { picks[ids[i]] = t } }
            }
            who = ids.first(where: { picks[$0] == nil }) ?? ids.first ?? 0
        }
        .accessibilityElement(children: .contain).accessibilityIdentifier("cafe-menu")
    }

    private var scrolled: some View {
        VStack(spacing: 8) {
            header
            VStack(spacing: 5) { ForEach(ids, id: \.self) { row($0) } }
            if editing {
                specialLine
                section("Food", note: foodNote)
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 5), count: 3), spacing: 5) { ForEach(CafeMenu.foods) { tile($0) } }
                section("Drinks", note: nil)
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 5), count: 3), spacing: 5) { ForEach(CafeMenu.drinks) { tile($0) } }
            }
        }
    }

    // MARK: pieces

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 1) {
                Text(editing ? "Café menu" : "Your order").font(SK.font(compact ? 18 : 20, .black)).foregroundStyle(SK.ink)
                if let r = refusal ?? cafe.cardRefusal {
                    Text(r).font(SK.font(12, .heavy)).foregroundStyle(Color(hex: 0xB0413E)).fixedSize(horizontal: false, vertical: true).accessibilityIdentifier("cafe-refusal")
                } else {
                    Text(editing ? "Tap a name, then pick for them" : "Served at your table").font(SK.font(12, .bold)).foregroundStyle(SK.muted)
                }
            }
            Spacer(minLength: 4)
            if editing, ids.count > 1 { tableToggle }
        }
    }

    private func row(_ id: Int) -> some View {
        let t = editing ? (table ? order.forTable : picks[id]) : order.treat(for: id)
        let active = editing && !table && who == id
        let served = cafe.served.contains(id)
        return Button {
            guard editing else { return }
            AudioHub.shared.uiTap(); who = id; table = false
        } label: {
            HStack(spacing: 8) {
                JelbiePortrait(care: care, who: id, size: 34, head: true).accessibilityHidden(true)
                Text(name(id)).font(SK.font(15, .heavy)).foregroundStyle(SK.ink).lineLimit(1).minimumScaleFactor(0.7)
                Spacer(minLength: 4)
                if let t {
                    thumb(t, size: 26)
                    Text(CafeMenu.treat(t).name).font(SK.font(13, .bold)).foregroundStyle(SK.ink).lineLimit(1).minimumScaleFactor(0.55)
                    priceView(t)
                } else {
                    Text("Choose…").font(SK.font(13, .bold)).foregroundStyle(SK.muted)
                }
                if !editing {
                    Image(systemName: served ? "checkmark.circle.fill" : "circle.dotted").font(.system(size: 20, weight: .heavy))
                        .foregroundStyle(served ? Color(hex: 0x3E9B63) : SK.muted)
                        .contentTransition(.symbolEffect(.replace))
                }
            }
            .padding(.horizontal, 8).frame(minHeight: 44)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(active ? SK.honey : Color.white.opacity(0.7)))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(active ? SK.honeyDeep : Color.clear, lineWidth: 2))
        }
        .buttonStyle(.plain).disabled(!editing)
        .accessibilityIdentifier("cafe-who-\(id)")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(name(id)): \(t.map { "\(CafeMenu.treat($0).name), \(CafeMenu.price($0, special: special)) JellyCoins" } ?? "no treat yet")\(!editing ? (served ? ", served" : ", on the way") : "")")
        .accessibilityHint(editing ? "Choose a treat for this Jelbie" : "")
        .accessibilityAddTraits(active ? .isSelected : [])
    }

    @ViewBuilder private func priceView(_ t: CafeTreatID) -> some View {
        let full = CafeMenu.treat(t).price, now = free && !editing ? 0 : CafeMenu.price(t, special: special)
        HStack(spacing: 3) {
            JellyCoinIcon(size: 14)
            if now != full { Text("\(full)").font(SK.font(11, .bold)).foregroundStyle(SK.muted).strikethrough().monospacedDigit() }
            Text("\(table && editing ? Int((Double(now) * CafeTuning.tableDiscount).rounded(.down)) : now)").font(SK.font(14, .black)).foregroundStyle(SK.ink).monospacedDigit()
        }
        .opacity(free ? 0.45 : 1)
    }

    private var specialLine: some View {
        HStack(spacing: 6) {
            Image(systemName: "sparkles").font(.system(size: 12, weight: .heavy)).foregroundStyle(SK.honeyDeep)
            if let sp = special {
                Text("Daily special: \(CafeMenu.treat(sp).name) \u{2212}20%").font(SK.font(12, .heavy)).foregroundStyle(SK.ink).lineLimit(1).minimumScaleFactor(0.6)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 6)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(special.map { "Daily special: \(CafeMenu.treat($0).name), 20 percent off" } ?? "").accessibilityIdentifier("cafe-special")
    }

    private var foodNote: String? {
        let full = ids.filter { !care.cafeCanEat($0) }
        if table { return full.isEmpty ? nil : "\(full.map(name).joined(separator: " & ")) full" }
        return care.cafeCanEat(who) ? nil : "\(name(who))'s full"
    }

    private func section(_ title: String, note: String?) -> some View {
        HStack(spacing: 6) {
            Text(title).font(SK.font(13, .black)).foregroundStyle(SK.ink)
            if let note {
                Text(note + (title == "Food" ? " \u{00B7} try a drink" : "")).font(SK.font(12, .heavy)).foregroundStyle(Color(hex: 0xB0413E)).lineLimit(1).minimumScaleFactor(0.6)
                    .accessibilityIdentifier("cafe-full-note")
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 6).padding(.top, 2)
    }

    private var tableToggle: some View {
        Button { AudioHub.shared.uiTap(); table.toggle(); refusal = nil } label: {
            HStack(spacing: 5) {
                Image(systemName: table ? "checkmark.circle.fill" : "circle").font(.system(size: 14, weight: .bold))
                Text("Same for all").font(SK.font(12, .heavy)).lineLimit(1).minimumScaleFactor(0.7)
                Text("-15%").font(SK.font(11, .black)).foregroundStyle(SK.muted)
            }
            .foregroundStyle(SK.ink).padding(.horizontal, 9).frame(minHeight: 44)
            .background(Capsule().fill(table ? SK.honey : Color.white.opacity(0.7)))
        }
        .buttonStyle(.plain).accessibilityIdentifier("cafe-table")
        .accessibilityLabel("Same for everyone, 15 percent off")
        .accessibilityValue(table ? "on" : "off")
        .accessibilityAddTraits(table ? .isSelected : [])
    }

    // MARK: tiles

    private func available(_ t: CafeTreat) -> Bool {
        if table { return ids.allSatisfy { CafeRules.canOrder(t.id, tier: care.needs(for: $0).tier(.hunger)) } }
        return CafeRules.canOrder(t.id, tier: care.needs(for: who).tier(.hunger))
    }
    private func isChosen(_ t: CafeTreat) -> Bool { table ? order.forTable == t.id : picks[who] == t.id }

    private func tile(_ t: CafeTreat) -> some View {
        let ok = available(t), chosen = isChosen(t), isSpecial = t.id == special
        return Button { pick(t) } label: {
            VStack(spacing: 1) {
                ZStack(alignment: .topTrailing) {
                    thumb(t.id, size: compact ? 32 : 38).frame(maxWidth: .infinity)
                    if isSpecial { Text("\u{2212}20%").font(SK.font(10, .black)).foregroundStyle(.white).padding(.horizontal, 5).padding(.vertical, 1).background(Capsule().fill(SK.pinkStrong)) }
                }
                Text(t.name).font(SK.font(11, .heavy)).foregroundStyle(SK.ink).lineLimit(1).minimumScaleFactor(0.5)
                HStack(spacing: 3) {
                    JellyCoinIcon(size: 13)
                    if isSpecial { Text("\(t.price)").font(SK.font(10, .bold)).foregroundStyle(SK.muted).strikethrough().monospacedDigit() }
                    Text("\(CafeMenu.price(t.id, special: special))").font(SK.font(13, .black)).foregroundStyle(SK.ink).monospacedDigit()
                }
            }
            .frame(maxWidth: .infinity, minHeight: 44).padding(.vertical, 4)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(chosen ? SK.honey : Color.white.opacity(0.75)))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(chosen ? SK.honeyDeep : Color.clear, lineWidth: 2))
            .opacity(ok ? 1 : 0.35)
        }
        .buttonStyle(.plain).disabled(!ok).accessibilityIdentifier("cafe-treat-\(t.id.rawValue)")
        .accessibilityLabel("\(t.name), \(CafeMenu.price(t.id, special: special)) JellyCoins\(isSpecial ? ", daily special" : ""). \(ok ? t.blurb : "\(name(who)) is full, pick a drink.")")
        .accessibilityAddTraits(chosen ? .isSelected : [])
    }

    private func pick(_ t: CafeTreat) {
        AudioHub.shared.uiTap(); refusal = nil
        if table { for id in ids { picks[id] = t.id } }
        else {
            picks[who] = t.id
            if let next = ids.first(where: { picks[$0] == nil }) { who = next }          // on to the next Jelbie without a pick
        }
    }

    private func thumb(_ t: CafeTreatID, size: CGFloat) -> some View {
        Group {
            if let img = StoreThumb.image("cafe-\(t.rawValue)", mesh: DiningModels.heldPiece(Consumables.cafeFood(t), index: 0, scale: 1.25)) {
                Image(uiImage: img).resizable().scaledToFit()
            } else { Image(systemName: Consumables.cafeFood(t).symbol).foregroundStyle(SK.ink) }
        }
        .frame(width: size, height: size).accessibilityHidden(true)
    }

    // MARK: footer (pinned): the stamp card, the total, Order

    private var footer: some View {
        VStack(spacing: 6) {
            stampRow
            HStack(spacing: 8) {
                totalView
                Spacer(minLength: 2)
                if editing { orderButton }
            }
        }
    }

    private var stampRow: some View {
        let n = cafe.stamps.card.count, full = cafe.stamps.isFull
        return HStack(spacing: 5) {
            Text("Stamps").font(SK.font(12, .heavy)).foregroundStyle(SK.muted)
            ForEach(0..<CafeStamps.slots, id: \.self) { i in
                let on = i < n
                Circle().fill(on ? SK.honey : Color.white.opacity(0.7))
                    .overlay(Image(systemName: "pawprint.fill").font(.system(size: 10, weight: .heavy)).foregroundStyle(on ? SK.ink : SK.muted.opacity(0.35)))
                    .overlay(Circle().strokeBorder(on ? SK.honeyDeep : SK.muted.opacity(0.25), lineWidth: 1.5))
                    .frame(width: 22, height: 22)
                    .scaleEffect(on && i == n - 1 && cafe.stamps.landed > 0 ? 1.0 : 1)
                    .animation(.spring(response: 0.35, dampingFraction: 0.45), value: n)
                    .symbolEffect(.bounce, value: on && i == n - 1 ? cafe.stamps.landed : 0)
            }
            Spacer(minLength: 0)
            if full { Text("Next is free!").font(SK.font(12, .black)).foregroundStyle(SK.pinkStrong).lineLimit(1).minimumScaleFactor(0.6) }
        }
        .accessibilityElement(children: .ignore).accessibilityLabel("Stamp card: \(n) of \(CafeStamps.slots)\(full ? ", the next order is free" : "")").accessibilityIdentifier("cafe-stamps")
    }

    private var totalView: some View {
        let list = order.fullPrice(jellies: ids)
        return HStack(spacing: 5) {
            Text("Total").font(SK.font(12, .heavy)).foregroundStyle(SK.muted)
            if free {
                Text("Free \u{00B7} stamp card").font(SK.font(16, .black)).foregroundStyle(SK.pinkStrong).lineLimit(1).minimumScaleFactor(0.6)
            } else {
                JellyCoinIcon(size: 18)
                if list > total, total > 0 || !editing { Text("\(list)").font(SK.font(13, .bold)).foregroundStyle(SK.muted).strikethrough().monospacedDigit() }
                Text("\(total)").font(SK.font(18, .black)).foregroundStyle(SK.ink).monospacedDigit()
            }
        }
        .accessibilityElement(children: .ignore).accessibilityLabel(free ? "Total: free, stamp card" : "Total: \(total) JellyCoins").accessibilityIdentifier("cafe-total")
    }

    private var orderButton: some View {
        Button {
            UIImpactFeedbackGenerator(style: .soft).impactOccurred()
            refusal = care.orderCafe(order)
        } label: {
            Text("Order").font(SK.font(17, .black)).foregroundStyle(.white).lineLimit(1).fixedSize()
                .padding(.horizontal, 22).frame(minHeight: 44)
                .background(Capsule().fill(SK.pinkStrong.opacity(complete ? 1 : 0.4)))
        }
        .buttonStyle(.plain).disabled(!complete).accessibilityIdentifier("cafe-order")
        .accessibilityHint(complete ? "Places the order" : "Choose a treat for every Jelbie first")
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
