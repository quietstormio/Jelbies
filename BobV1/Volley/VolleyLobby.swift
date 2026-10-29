//
//  VolleyLobby.swift
//  The Volleyball lobby (Go out > Beach), rebuilt to the lobby mockups: the four courts in a carousel, the Team card (you and a chosen teammate), the two options, and a pinned
//  Train / Play bar. Training (the stats and the drills) and How to play are sheets. Shared pieces are in Lobby/LobbyKit.swift.
//

import SwiftUI

struct VolleyLobby: View {
    let care: GameCare
    @Binding var who: Int
    var back: () -> Void
    var play: (VolleyTier) -> Void
    /// A drill, for the Jelbie picked on the Training sheet.
    var drill: (VolleyDrillKind, Int) -> Void
    @Environment(\.verticalSizeClass) private var vsc
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var sheet: Sheet?
    @State private var trainee = 0
    @State private var hint = LobbyHint()
    enum Sheet { case train, how }
    private var book: VolleyBook { care.volley.book }
    private var compact: Bool { vsc == .compact }
    private var blocker: String? { care.volleyBlocker(jelly: who) }

    var body: some View {
        let char = care.jelly(who)?.character ?? who
        ZStack {
            LobbyScreen(header: AnyView(LobbyHeader(title: "Volleyball", wallet: care.bath.wallet, backID: "volley-back", helpID: "volley-help", back: back, help: { open(.how) })),
                        why: blocker, whyID: "volley-why") {
                courts
            } right: {
                VolleyTeamCard(care: care, who: $who, compact: compact)
                    .padding(.top, compact ? 0 : 18)
                optionsCard.padding(.top, compact ? 0 : 12)
            } bar: {
                LobbyBottomBar(pepLeft: book.sessionsLeft(char), pepTotal: VolleyTraining.fullSessions, pepID: "volley-pep", trainID: "volley-train", playID: "volley-play",
                               playTitle: "Play", playIcon: .ball, blocked: blocker != nil,
                               train: { trainee = who; open(.train) }, play: { play(book.chosen) })
            }
            .accessibilityHidden(sheet != nil)
            if let sheet {
                Group {
                    switch sheet {
                    case .train: trainingSheet
                    case .how:
                        LobbyHowSheet(rows: [
                            (.three, "Three touches a side", "Bump, set, then spike it over the net."),
                            (.ring, "Tap on the ring", "Tap as the ring closes for a Perfect hit."),
                            (.tap, "Steer a Jelbie", "Double-tap a Jelbie to move them yourself."),
                            (.trophy, "First to \(VolleyTuning.pointsToWin), win by 2", "Win a match to open the next court."),
                        ], close: { close() })
                    }
                }
                .zIndex(1)
            }
        }
        .accessibilityElement(children: .contain).accessibilityIdentifier("volley-lobby")
        .onAppear {
            trainee = who
            switch UserDefaults.standard.string(forKey: "LobbyAuto") {          // capture aid: -LobbyAuto volleyTrain | volleyHow
            case "volleyTrain": sheet = .train
            case "volleyHow": sheet = .how
            default: break
            }
        }
    }

    private func open(_ s: Sheet) { withAnimation(reduceMotion ? nil : .easeOut(duration: 0.28)) { sheet = s } }
    private func close() { withAnimation(reduceMotion ? nil : .easeOut(duration: 0.25)) { sheet = nil } }

    // MARK: courts

    private var courts: some View {
        let open = book.unlockedTiers.count
        return VStack(alignment: .leading, spacing: 0) {
            LobbyLabelRow(title: "Court", trailing: "\(open) of \(VolleyTier.allCases.count) open")
            LobbyCarousel(bleed: !compact, scrollTo: book.chosen.index >= 2 ? "tier-\(book.chosen.rawValue)" : nil) {
                ForEach(VolleyTier.allCases, id: \.rawValue) { t in courtCard(t).id("tier-\(t.rawValue)") }
            }
            .accessibilityIdentifier("volley-courts")
            LobbyInfoLine(text: hint.text ?? book.chosen.blurb, pillsBelow: typeSize.isAccessibilitySize) {
                LobbyPill(label: "Win", amount: VolleyTuning.drops(win: true, tier: book.chosen), gold: true)
                LobbyPill(label: "Loss", amount: VolleyTuning.drops(win: false, tier: book.chosen))
            }
            .accessibilityElement(children: .contain)
        }
    }

    private func unlockRule(_ t: VolleyTier) -> String { "Win a match (or three close ones) at \(t.below?.title ?? "") to open" }

    private func courtCard(_ t: VolleyTier) -> some View {
        let isOpen = book.unlocked(t), on = book.chosen == t
        return Button {
            if isOpen { AudioHub.shared.uiTap(); book.chosen = t; book.save() } else { hint.show(unlockRule(t)) }
        } label: {
            LobbyCarouselCard(name: t.title, sub: isOpen ? t.className : "Win at \(t.below?.title ?? "")", selected: on && isOpen, locked: !isOpen) { CourtArt(tier: t) }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(isOpen ? "\(t.title), \(t.className)" : "\(t.title), locked. Win at \(t.below?.title ?? "")")
        .accessibilityHint(isOpen ? t.blurb : unlockRule(t))
        .accessibilityAddTraits(on ? .isSelected : [])
        .accessibilityIdentifier("volley-tier-\(t.rawValue)")
    }

    // MARK: options

    private var optionsCard: some View {
        let autoOn = Binding(get: { book.autoSwitch }, set: { book.autoSwitch = $0 })
        let slowOn = Binding(get: { book.slowBall }, set: { book.slowBall = $0 })
        let assist = A11ySettings.shared.raceAssist != .off
        return VStack(alignment: .leading, spacing: 0) {
            if compact {
                HStack(spacing: 12) {
                    LobbyOptionRow(icon: .autosw, title: "Auto-switch", isOn: autoOn, id: "volley-autoswitch", compact: true)
                    LobbyOptionRow(icon: .turtle, title: "Slower ball", isOn: slowOn, id: "volley-slow", compact: true)
                }
            } else {
                LobbyOptionRow(icon: .autosw, title: "Auto-switch Jelbies", isOn: autoOn, id: "volley-autoswitch")
                Rectangle().fill(SK.ink.opacity(0.08)).frame(height: 1)
                LobbyOptionRow(icon: .turtle, title: "Slower ball", isOn: slowOn, id: "volley-slow")
            }
            if assist {
                Text("Play assist is on (Settings > Accessibility): the Jelbie walks to the ball for you.").font(SK.font(11, .bold)).foregroundStyle(SK.muted)
                    .padding(.vertical, 8).frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, compact ? 12 : 14).padding(.vertical, compact ? 6 : 4).frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(SK.card))
    }

    // MARK: training

    private func statColor(_ k: VolleyStatKind) -> Color {
        switch k { case .speed: return SK.sky; case .power: return SK.pink; case .hops: return SK.mint; case .timing: return SK.honeyDeep }
    }
    private func drillIcon(_ k: VolleyDrillKind) -> LobbyIcon.Kind {
        switch k { case .bonk: return .dotted; case .spike: return .spike; case .block: return .block; case .sprint: return .run }
    }
    private func sectionHead(_ title: String, _ trailing: String? = nil) -> some View {
        HStack {
            Text(title.uppercased()).font(SK.font(12.5, .heavy)).tracking(0.6).foregroundStyle(SK.muted).accessibilityAddTraits(.isHeader)
            Spacer(minLength: 8)
            if let trailing { Text(trailing).font(SK.font(12.5, .heavy)).foregroundStyle(SK.muted) }
        }
        .padding(.horizontal, 4).padding(.top, 16).padding(.bottom, 8)
    }

    private var trainingSheet: some View {
        let prof = care.jelly(trainee) ?? care.jelly(who)
        let c = prof?.character ?? trainee
        let st = book.stats(character: c)
        let left = book.sessionsLeft(c)
        let name = prof?.name ?? "Bob"
        return LobbySheet(title: "Training", full: true, close: { close() }) {
            VStack(alignment: .leading, spacing: 0) {
                LobbyChips(care: care, selected: trainee) { trainee = $0 }
                VStack(alignment: .leading, spacing: 7) {
                    HStack(spacing: 10) {
                        Text("Pep").font(SK.font(16, .black)).foregroundStyle(SK.ink)
                        HStack(spacing: 6) { ForEach(0..<VolleyTraining.fullSessions, id: \.self) { i in Capsule().fill(i < left ? SK.mint : SK.pepEmpty).frame(height: 12) } }
                        Text("\(left) left").font(SK.font(15, .black)).foregroundStyle(SK.ink).monospacedDigit()
                    }
                    .accessibilityElement(children: .ignore).accessibilityLabel("Pep: \(left) of \(VolleyTraining.fullSessions) full practices left today")
                    Text("Each practice uses one Pep. It refills overnight; after that, practice still helps, just less.").font(SK.font(12, .bold)).foregroundStyle(SK.muted).fixedSize(horizontal: false, vertical: true)
                }
                .lobbyCard(padding: EdgeInsets(top: 12, leading: 14, bottom: 12, trailing: 14)).padding(.top, 14)
                sectionHead("\(name) on the sand", "\(st.wins) win\(st.wins == 1 ? "" : "s") \u{00B7} \(st.matches) match\(st.matches == 1 ? "" : "es")")
                VStack(spacing: 11) {
                    LobbyBigStat(name: "Speed", value: st.speed, color: SK.sky, sub: "Quicker feet, longer steps")
                    LobbyBigStat(name: "Power", value: st.power, color: SK.pink, sub: "Harder hits and spikes")
                    LobbyBigStat(name: "Hops", value: st.hops, color: SK.mint, sub: "Higher jumps")
                    LobbyBigStat(name: "Timing", value: st.timing, color: SK.honeyDeep, sub: "A bigger hit window, a truer aim")
                }
                .lobbyCard().accessibilityElement(children: .contain).accessibilityIdentifier("volley-stats")
                sectionHead("Drills")
                VStack(spacing: 8) { ForEach(VolleyDrillKind.allCases, id: \.rawValue) { k in drillRow(k) } }
            }
            .accessibilityElement(children: .contain).accessibilityIdentifier("volley-training")
        }
    }

    private func drillRow(_ k: VolleyDrillKind) -> some View {
        HStack(spacing: 12) {
            LobbyIcon(kind: drillIcon(k)).frame(width: 46, height: 46).background(RoundedRectangle(cornerRadius: 13, style: .continuous).fill(SK.sky.opacity(0.55)))
            VStack(alignment: .leading, spacing: 4) {
                Text(k.title).font(SK.font(16, .black)).foregroundStyle(SK.ink).fixedSize(horizontal: false, vertical: true)
                FlowLayout(spacing: 5) {
                    ForEach(k.raises, id: \.rawValue) { s in
                        Text("+ \(s.title)").font(SK.font(11.5, .heavy)).foregroundStyle(SK.ink).padding(.horizontal, 8).padding(.vertical, 2).background(Capsule().fill(statColor(s).opacity(0x55 / 255.0)))
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Button {
                UIImpactFeedbackGenerator(style: .soft).impactOccurred(); AudioHub.shared.uiConfirm()
                let id = trainee
                close(); drill(k, id)
            } label: {
                Text("Go").font(SK.font(14.5, .black)).foregroundStyle(.white).padding(.horizontal, 16).frame(minHeight: 36)
                    .background(Capsule().fill(blocker == nil ? SK.pinkStrong : SK.muted.opacity(0.45)))
                    .frame(minHeight: 44).contentShape(Rectangle())
            }
            .buttonStyle(.plain).disabled(blocker != nil)
            .accessibilityLabel("Go, \(k.title)").accessibilityHint(k.blurb).accessibilityIdentifier("volley-drill-\(k.rawValue)")
        }
        .padding(EdgeInsets(top: 9, leading: 9, bottom: 9, trailing: 10))
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color.white.opacity(0.9)))
    }
}

// MARK: - The Team card

struct VolleyTeamCard: View {
    let care: GameCare
    @Binding var who: Int
    var compact = false
    @State private var cardW: CGFloat = 0
    private var book: VolleyBook { care.volley.book }

    var body: some View {
        let mine = care.jelly(who)
        let partner = care.volleyPartner(for: who)
        // with three Jelbies the third sits on the bench: a swap button trades a tile's Jelbie with him (two have no bench; one has a Park friend)
        let bench = care.volleyBench(for: who)
        let stacked = needsStack(mine: mine, partner: partner, swap: bench != nil)
        VStack(alignment: .leading, spacing: 12) {
            Text("Team").font(SK.font(19, .black)).foregroundStyle(SK.ink).accessibilityAddTraits(.isHeader)
            HStack(alignment: .top, spacing: 10) {
                if let mine {
                    VolleyTeamTile(care: care, jelly: mine, tileID: "volley-team-1", swapTo: bench, stacked: stacked) {
                        guard let b = bench else { return }
                        book.partner = partner?.character
                        who = b.id
                    }
                }
                if let partner {
                    VolleyTeamTile(care: care, jelly: partner, tileID: "volley-team-2", swapTo: bench, stacked: stacked) {
                        guard let b = bench else { return }
                        book.partner = b.character
                    }
                } else {
                    parkFriendTile
                }
            }
        }
        .padding(compact ? 12 : 14).frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(SK.card))
        .accessibilityIdentifier("volley-team")
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { cardW = $0 }
    }

    /// Both tiles use the same head: portrait, name and swap button in a row, or (when a name will not fit beside them) the name under the portrait.
    private func needsStack(mine: JellyProfile?, partner: JellyProfile?, swap: Bool) -> Bool {
        let tileInner = (cardW - 2 * (compact ? 12 : 14) - 10) / 2 - 24
        guard tileInner > 0 else { return false }
        let font = UIFont.systemFont(ofSize: JFont.scaledSize(18), weight: .black)
        let names = [mine?.name, partner?.name].compactMap { $0 }
        let w = names.map { ($0 as NSString).size(withAttributes: [.font: font]).width * 1.08 }.max() ?? 0
        return 46 + 10 + w + 10 + (swap ? 26 : 0) > tileInner
    }

    private var parkFriendTile: some View {
        let friend = care.volleyParkFriend()
        return VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 10) {
                // the friend as he will play: the lone Jelbie's body in the friend's colour and item, rendered by the stage (a friend with a signature feature is never picked)
                JelbiePortrait(care: care, who: care.jellies.first?.id ?? 0, size: 46, border: .white, outerRing: 3, head: true, friend: friend)
                Text("Park\nfriend").font(SK.font(15.5, .black)).foregroundStyle(SK.ink).lineLimit(2).fixedSize(horizontal: false, vertical: true)
            }
            Text("Plays with you until you adopt a second Jelbie. Steady, and sets you up.").font(SK.font(12.5, .bold)).foregroundStyle(SK.muted).lineSpacing(2).fixedSize(horizontal: false, vertical: true).padding(2)
        }
        .padding(EdgeInsets(top: 10, leading: 12, bottom: 11, trailing: 12)).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(SK.tile))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(SK.ink.opacity(0.06), lineWidth: 1.5))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Park friend. Plays with you until you adopt a second Jelbie. Steady, and sets you up.")
        .accessibilityIdentifier("volley-team-friend")
    }
}

struct VolleyTeamTile: View {
    let care: GameCare
    let jelly: JellyProfile
    let tileID: String
    /// The Jelbie on the bench this tile can trade with (nil: no swap button).
    let swapTo: JellyProfile?
    var stacked = false
    var swap: () -> Void

    private var book: VolleyBook { care.volley.book }

    private var swapButton: some View {
        Group {
            if let b = swapTo {
                Button { UIImpactFeedbackGenerator(style: .light).impactOccurred(); AudioHub.shared.uiTap(); swap() } label: {
                    LobbyIcon(kind: .swap, color: SK.muted).frame(width: 26, height: 26).background(Circle().fill(SK.ink.opacity(0.07)))
                        .frame(width: 44, height: 44).contentShape(Circle())
                }
                .buttonStyle(.plain).padding(-9)
                .accessibilityLabel("Swap \(jelly.name) for \(b.name)").accessibilityIdentifier("\(tileID)-swap")
            }
        }
    }

    private var avatar: some View {
        JelbiePortrait(care: care, who: jelly.id, size: 46, border: .white, outerRing: 3, head: true).accessibilityHidden(true)
    }
    private var name: some View { Text(jelly.name).font(SK.font(18, .black)).foregroundStyle(SK.ink).lineLimit(1) }

    var body: some View {
        let st = book.stats(character: jelly.character)
        VStack(alignment: .leading, spacing: 9) {
            if stacked {
                HStack(alignment: .top, spacing: 6) { VStack(alignment: .leading, spacing: 6) { avatar; name.minimumScaleFactor(0.6) }.frame(maxWidth: .infinity, alignment: .leading); swapButton }
            } else {
                HStack(spacing: 10) { avatar; name.frame(maxWidth: .infinity, alignment: .leading); swapButton }
            }
            Grid(horizontalSpacing: 7, verticalSpacing: 0) {
                miniRow("Speed", st.speed, SK.sky)
                miniRow("Power", st.power, SK.pink)
                miniRow("Hops", st.hops, SK.mint)
                miniRow("Timing", st.timing, SK.honeyDeep)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(jelly.name): Speed \(Int((st.speed * 100).rounded())), Power \(Int((st.power * 100).rounded())), Hops \(Int((st.hops * 100).rounded())), Timing \(Int((st.timing * 100).rounded()))")
        }
        .padding(EdgeInsets(top: 10, leading: 12, bottom: 11, trailing: 12))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(SK.tile))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(SK.ink.opacity(0.06), lineWidth: 1.5))
        .accessibilityElement(children: .contain).accessibilityIdentifier(tileID)
    }

    private func miniRow(_ n: String, _ v: Float, _ c: Color) -> some View {
        GridRow {
            Text(n).font(SK.font(12.5, .heavy)).foregroundStyle(SK.muted).lineLimit(1).minimumScaleFactor(0.7).gridColumnAlignment(.leading)
            LobbyBar(value: v, color: c, height: 8).frame(minWidth: 20)
            Text("\(Int((v * 100).rounded()))").font(SK.font(13, .black)).foregroundStyle(SK.ink).monospacedDigit().gridColumnAlignment(.trailing)
        }
        .frame(minHeight: 20)
    }
}
