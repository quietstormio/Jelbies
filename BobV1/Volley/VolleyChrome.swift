//
//  VolleyChrome.swift
//  Jelly Volleyball's screen furniture while the court is up: the score, the controls (drag the lower area to walk, the left / right buttons, a big Jump
//  button that serves, jumps, digs at a low ball and spikes when pressed again in the air), drill read-outs, the results card and the white fade.
//  Portrait: the arrows bottom left, Jump bottom right. Landscape: the same corners, bigger. Everything has VoiceOver labels and keyboard shortcuts.
//

import SwiftUI

struct VolleyChrome: View {
    let care: GameCare
    private var volley: VolleyFlow { care.volley }
    @Environment(\.verticalSizeClass) private var vsc
    private var compact: Bool { vsc == .compact }
    @State private var dragDir: Float = 0

    var body: some View {
        ZStack {
            if volley.inScene {
                VStack(spacing: 0) {
                    topBar
                    Spacer()
                    if volley.showsCard { VolleyResultsCard(volley: volley) { volley.goHome() }.padding(.horizontal, 24).transition(.scale(scale: 0.85).combined(with: .opacity)) }
                    Spacer()
                    if volley.phase == .playing, !volley.hasResults { controls }
                }
                .padding(.horizontal, 14).padding(.bottom, compact ? 8 : 14)
                .animation(CareMenu.spring, value: volley.showsCard)
                if volley.live, volley.ui.phase == .intro { banner(volley.isDrill ? "Ready?" : "Beach volley!") }
            }
            Color.white.opacity(Double(volley.wipe)).ignoresSafeArea().allowsHitTesting(false)
        }
        .allowsHitTesting(volley.active)
        .accessibilityElement(children: .contain)
    }

    // MARK: top

    private var topBar: some View {
        VStack(spacing: 6) {
            HStack(alignment: .top) {
                Button { AudioHub.shared.uiTap(); volley.goHome() } label: {
                    Image(systemName: "xmark").font(.system(size: 16, weight: .black)).foregroundStyle(CareMenu.brown)
                        .frame(width: 44, height: 44).background(Circle().fill(CareMenu.cream).shadow(color: FocusStyle.shadow.opacity(0.2), radius: 5, y: 2))
                }.buttonStyle(.plain).accessibilityLabel("Leave the beach").accessibilityIdentifier("volley-leave")
                Spacer()
                scoreBoard
                Spacer()
                Color.clear.frame(width: 44, height: 44)
            }
            if let hint = hint { Text(hint).playFont(15, .semibold).foregroundStyle(CareMenu.brown).padding(.horizontal, 14).padding(.vertical, 6).background(Capsule().fill(CareMenu.cream.opacity(0.92))).transition(.opacity) }
            if let t = volley.toast { Text(t).playFont(14, .semibold).foregroundStyle(CareMenu.brown).padding(.horizontal, 14).padding(.vertical, 6).background(Capsule().fill(CareMenu.cream)) }
        }
        .padding(.top, 8)
    }

    @ViewBuilder
    private var scoreBoard: some View {
        let u = volley.ui
        if case .drill(let k) = volley.mode {
            HStack(spacing: 10) {
                Text(k.title).playFont(15, .heavy)
                switch k {
                case .bonk: Text("\(u.drillCount) bonks").playFont(17, .bold).monospacedDigit()
                case .spike: Text("Ball \(min(u.drillFeeds, VolleySim.spikeFeeds))/\(VolleySim.spikeFeeds) · \(u.drillGood) hit").playFont(15, .bold).monospacedDigit()
                case .sprint: Text("Flags \(u.drillFlags)/\(VolleySim.sprintFlags)").playFont(17, .bold).monospacedDigit()
                }
            }
            .foregroundStyle(CareMenu.brown).padding(.horizontal, 16).padding(.vertical, 8)
            .background(Capsule().fill(CareMenu.cream).shadow(color: FocusStyle.shadow.opacity(0.2), radius: 6, y: 2))
            .accessibilityElement(children: .combine).accessibilityIdentifier("volley-score")
        } else {
            HStack(spacing: 12) {
                team(volley.playerName.isEmpty ? "You" : volley.playerName, u.score[0], serving: u.serveTeam == 0 && u.phase != .over)
                Text(":").playFont(20, .black).foregroundStyle(CareMenu.brown.opacity(0.6))
                team("Them", u.score[1], serving: u.serveTeam == 1 && u.phase != .over)
            }
            .padding(.horizontal, 16).padding(.vertical, 8)
            .background(Capsule().fill(CareMenu.cream).shadow(color: FocusStyle.shadow.opacity(0.2), radius: 6, y: 2))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Score. You \(u.score[0]), them \(u.score[1]). First to \(VolleyTuning.pointsToWin).")
            .accessibilityIdentifier("volley-score")
        }
    }

    private func team(_ name: String, _ pts: Int, serving: Bool) -> some View {
        HStack(spacing: 6) {
            if serving { Circle().fill(FocusStyle.pink).frame(width: 9, height: 9) }
            Text(name).playFont(14, .semibold).lineLimit(1)
            Text("\(pts)").playFont(24, .heavy).monospacedDigit()
        }.foregroundStyle(CareMenu.brown)
    }

    private var hint: String? {
        let u = volley.ui
        guard volley.live else { return nil }
        if volley.isDrill {
            if u.phase == .intro { return nil }
            switch volley.mode { case .drill(.bonk): return "Keep it up! Walk under it"; case .drill(.spike): return "Jump, then Jump again to spike the pink cushion"; case .drill(.sprint): return "Run to the pink flag"; default: return nil }
        }
        if u.humanServes { return "Your serve. Tap Jump!" }
        if u.waitingToServe { return "Their serve" }
        return nil
    }

    private func banner(_ s: String) -> some View {
        Text(s).font(.system(size: 64, weight: .heavy, design: .rounded)).foregroundStyle(.white)
            .shadow(color: FocusStyle.pink.opacity(0.9), radius: 0, x: 0, y: 4).shadow(color: FocusStyle.shadow.opacity(0.35), radius: 8, y: 5)
            .allowsHitTesting(false).offset(y: -40).transition(.opacity)
    }

    // MARK: controls

    private var controls: some View {
        HStack(alignment: .bottom, spacing: 12) {
            if volley.sim?.autoMove == true {
                Text("The Jelbie walks for you").playFont(13, .semibold).foregroundStyle(CareMenu.brown).padding(.horizontal, 12).padding(.vertical, 6)
                    .background(Capsule().fill(CareMenu.cream.opacity(0.9))).frame(maxWidth: .infinity, alignment: .leading).padding(.bottom, 8)
            } else {
                HStack(spacing: 10) {
                    HoldButton(symbol: "chevron.left", title: "Move left", id: "volley-left", key: .leftArrow, size: compact ? 78 : 84) { down in care.volleyMove(down ? -1 : 0) }
                    HoldButton(symbol: "chevron.right", title: "Move right", id: "volley-right", key: .rightArrow, size: compact ? 78 : 84) { down in care.volleyMove(down ? 1 : 0) }
                }
                Spacer(minLength: 0)
            }
            if volley.sim?.autoMove == true { Spacer(minLength: 0) }
            jump
        }
        .frame(maxWidth: .infinity)
        // dragging anywhere in the lower area also walks him
        .background(
            Color.clear.contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 4)
                    .onChanged { v in
                        let d = Float(max(-1, min(1, v.translation.width / 60)))
                        if abs(d - dragDir) > 0.15 { dragDir = d; care.volleyMove(d) }
                    }
                    .onEnded { _ in dragDir = 0; care.volleyMove(0) })
                .padding(.top, -160)
        )
    }

    private var jump: some View {
        let serve = volley.ui.humanServes
        return FootButton(title: serve ? "Serve" : "Jump", id: "volley-jump", symbol: serve ? "figure.volleyball" : "arrow.up.circle.fill", flip: false, live: volley.live, tilt: false, key: .space) {
            care.volleyTap()
        }
        .frame(width: compact ? 150 : 170, height: compact ? 104 : 150)
        .accessibilityHint("Jump. Tap again in the air to spike. Near a low ball he dives to dig it.")
    }
}

/// A button that reports press and release (the arrows hold).
struct HoldButton: View {
    let symbol: String
    let title: String
    let id: String
    var key: KeyEquivalent?
    var size: CGFloat = 84
    let change: (Bool) -> Void
    @State private var down = false
    var body: some View {
        Image(systemName: symbol).font(.system(size: 34, weight: .black)).foregroundStyle(CareMenu.brown)
            .frame(width: size, height: size * 0.95)
            .background(RoundedRectangle(cornerRadius: 30, style: .continuous).fill(down ? FocusStyle.pink.opacity(0.55) : CareMenu.cream)
                .shadow(color: FocusStyle.shadow.opacity(down ? 0.12 : 0.28), radius: down ? 4 : 9, y: down ? 1 : 4))
            .overlay(RoundedRectangle(cornerRadius: 30, style: .continuous).strokeBorder(Color.white.opacity(0.55), lineWidth: 1.5))
            .scaleEffect(down ? 0.96 : 1)
            .contentShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { _ in if !down { down = true; change(true) } }
                .onEnded { _ in down = false; change(false) })
            .background { if let key { Button("") { change(true); DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { change(false) } }.keyboardShortcut(key, modifiers: []).frame(width: 0, height: 0).opacity(0).accessibilityHidden(true) } }
            .accessibilityElement().accessibilityLabel(title).accessibilityIdentifier(id).accessibilityAddTraits(.isButton)
            .accessibilityAction { change(true); DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { change(false) } }
    }
}

struct VolleyResultsCard: View {
    let volley: VolleyFlow
    let home: () -> Void
    @Environment(\.verticalSizeClass) private var vsc
    private var tight: Bool { vsc == .compact }

    private func chip(_ text: String, _ symbol: String, _ id: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: UIImage(systemName: symbol) != nil ? symbol : "star.fill").font(.system(size: 14, weight: .black))
            Text(text).playFont(14, .heavy)
        }.foregroundStyle(CareMenu.brown).padding(.horizontal, 12).padding(.vertical, 5)
            .background(Capsule().fill(Color(red: 0.98, green: 0.80, blue: 0.35))).accessibilityElement(children: .combine).accessibilityIdentifier(id)
    }

    var body: some View {
        let s = volley.sim
        VStack(spacing: tight ? 6 : 12) {
            if case .drill(let k) = volley.mode {
                Text("\(k.title) done!").playFont(tight ? 22 : 28, .heavy).foregroundStyle(CareMenu.brown)
                Text(summary(s)).playFont(18, .semibold).foregroundStyle(CareMenu.brown)
                VStack(spacing: 4) {
                    gainRow("Speed", volley.gain.speed); gainRow("Power", volley.gain.power); gainRow("Hops", volley.gain.hops); gainRow("Timing", volley.gain.timing)
                    if volley.gain.speed + volley.gain.power + volley.gain.hops + volley.gain.timing < 0.0005 { Text("Tired legs: a rest helps. Pep comes back tomorrow.").playFont(13, .medium).foregroundStyle(CareMenu.brown.opacity(0.85)) }
                }
            } else {
                Text(s?.humanTeamWon == true ? "You won!" : "Good game!").playFont(tight ? 24 : 32, .heavy).foregroundStyle(CareMenu.brown)
                Text("\(s?.score[0] ?? 0)  :  \(s?.score[1] ?? 0)").playFont(30, .heavy).monospacedDigit().foregroundStyle(CareMenu.brown)
                HStack(spacing: 8) {
                    Image(systemName: "drop.fill").foregroundStyle(SK.pink)
                    Text("+\(volley.earned) Drops").playFont(20, .bold).foregroundStyle(CareMenu.brown)
                }
                if volley.assistFactor < 1 { Text("Auto play pays half").playFont(14, .medium).foregroundStyle(CareMenu.brown.opacity(0.85)) }
                if !volley.awards.isEmpty {
                    HStack(spacing: 8) {
                        if volley.awards.newRibbon { chip("New ribbon!", "rosette", "volley-new-ribbon") }
                        if let t = volley.awards.trophies.first { chip("Trophy! \(t.title)", "trophy.fill", "volley-trophy") }
                    }
                }
                if let t = volley.unlockedNow { Text("\(t.title) unlocked!").playFont(15, .heavy).foregroundStyle(SK.pink).accessibilityIdentifier("volley-unlocked") }
            }
            Button { UIImpactFeedbackGenerator(style: .soft).impactOccurred(); AudioHub.shared.uiTap(); home() } label: {
                Text("Back home").playFont(20, .bold).foregroundStyle(.white).padding(.horizontal, 30).padding(.vertical, tight ? 8 : 12)
                    .background(Capsule().fill(SK.pink).shadow(color: FocusStyle.shadow.opacity(0.25), radius: 6, y: 3))
            }.buttonStyle(.plain).accessibilityIdentifier("volley-home")
        }
        .padding(.horizontal, 22).padding(.vertical, tight ? 10 : 20)
        .background(RoundedRectangle(cornerRadius: 34, style: .continuous).fill(CareMenu.cream).shadow(color: FocusStyle.shadow.opacity(0.3), radius: 16, y: 8))
        .overlay(RoundedRectangle(cornerRadius: 34, style: .continuous).strokeBorder(Color.white.opacity(0.6), lineWidth: 1.5))
        .accessibilityElement(children: .contain).accessibilityIdentifier("volley-card")
    }

    private func summary(_ s: VolleySim?) -> String {
        guard let s else { return "" }
        switch s.drillKind {
        case .bonk?: return "\(s.drillCount) bonks in a row"
        case .spike?: return "\(s.drillGood) of \(VolleySim.spikeFeeds) on the cushion"
        case .sprint?: return "\(s.flagIndex) of \(VolleySim.sprintFlags) flags"
        case nil: return ""
        }
    }
    @ViewBuilder
    private func gainRow(_ name: String, _ v: Float) -> some View {
        if v > 0.0005 {
            HStack { Text(name).playFont(16, .semibold); Spacer(); Text("+\(Int((v * 100).rounded(.up)))").playFont(16, .heavy).monospacedDigit() }
                .foregroundStyle(CareMenu.brown).frame(width: 180)
        }
    }
}

// MARK: - The Town screen: pick a Jelbie, a tier, play or train

struct VolleyLobby: View {
    let care: GameCare
    @Binding var who: Int
    var back: () -> Void
    var play: (VolleyTier) -> Void
    var drill: (VolleyDrillKind) -> Void
    @Environment(\.verticalSizeClass) private var vsc
    private var book: VolleyBook { care.volley.book }

    var body: some View {
        let prof = care.jelly(who)
        let compact = vsc == .compact
        VStack(spacing: compact ? 8 : 14) {
            HStack(spacing: 10) {
                Button { AudioHub.shared.uiTap(); back() } label: {
                    Image(systemName: "chevron.left").font(.system(size: 17, weight: .black)).foregroundStyle(SK.ink)
                        .frame(width: 44, height: 44).background(Circle().fill(Color.white.opacity(0.85)))
                }.buttonStyle(.plain).accessibilityLabel("Back").accessibilityIdentifier("volley-back")
                Text("Beach Volleyball").font(SK.font(28, .black)).foregroundStyle(SK.ink)
                Spacer()
                DropsPill(wallet: care.bath.wallet)
            }
            ScrollView {
                if compact {
                    HStack(alignment: .top, spacing: 14) {
                        VStack(spacing: 10) { matchCard(prof); tiers }
                        VStack(spacing: 10) { statCard(prof); drills(prof) }
                    }
                } else {
                    VStack(spacing: 12) { matchCard(prof); tiers; statCard(prof); drills(prof) }
                }
            }.scrollBounceBehavior(.basedOnSize)
        }
        .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 8)
        .background(SK.cream.ignoresSafeArea())
        .accessibilityElement(children: .contain).accessibilityIdentifier("volley-lobby")
    }

    private var blocker: String? { care.volleyBlocker(jelly: who) }

    private func matchCard(_ prof: JellyProfile?) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 14) {
                Image(systemName: "figure.volleyball").font(.system(size: 26, weight: .heavy)).foregroundStyle(SK.ink)
                    .frame(width: 62, height: 62).background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(SK.honey))
                VStack(alignment: .leading, spacing: 3) {
                    Text("2 vs 2 on the sand").font(SK.font(20, .black)).foregroundStyle(SK.ink)
                    Text("Bonk the ball with your head, jump twice to spike, dive for low ones. First to \(VolleyTuning.pointsToWin).").font(SK.font(12, .bold)).foregroundStyle(SK.muted).fixedSize(horizontal: false, vertical: true)
                }
            }
            if care.jellies.count > 1 { WhoRow(care: care, who: $who) }
            Button {
                UIImpactFeedbackGenerator(style: .soft).impactOccurred(); AudioHub.shared.uiConfirm(); play(book.chosen)
            } label: {
                Text("Play \(book.chosen.title)").font(SK.font(18, .black)).foregroundStyle(.white).frame(maxWidth: .infinity, minHeight: 50)
                    .background(Capsule().fill(blocker == nil ? SK.pink : SK.muted.opacity(0.45)))
            }.buttonStyle(.plain).disabled(blocker != nil).accessibilityIdentifier("volley-play")
            if let b = blocker { Text(b).font(SK.font(12, .bold)).foregroundStyle(SK.muted) }
            Toggle(isOn: Binding(get: { book.slowBall }, set: { book.slowBall = $0 })) {
                Text("Slower ball").font(SK.font(14, .heavy)).foregroundStyle(SK.ink)
            }.tint(SK.pink).accessibilityIdentifier("volley-slow")
            if A11ySettings.shared.raceAssist != .off { Text("Play assist is on (Settings > Accessibility): the Jelbie walks to the ball for you.").font(SK.font(11, .bold)).foregroundStyle(SK.muted) }
        }
        .padding(14).frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(SK.card))
    }

    private var tiers: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Courts").font(SK.font(12, .heavy)).foregroundStyle(SK.muted).textCase(.uppercase)
            ForEach(VolleyTier.allCases, id: \.rawValue) { t in
                let open = book.unlocked(t), on = book.chosen == t
                Button { AudioHub.shared.uiTap(); if open { book.chosen = t; book.save() } } label: {
                    HStack(spacing: 10) {
                        Image(systemName: open ? (on ? "checkmark.circle.fill" : "circle") : "lock.fill").font(.system(size: 18, weight: .heavy)).foregroundStyle(SK.ink)
                        VStack(alignment: .leading, spacing: 1) {
                            Text("\(t.title) · \(t.className)").font(SK.font(15, .black)).foregroundStyle(SK.ink)
                            Text(open ? t.blurb : "Win a match (or three close ones) at \(t.below?.title ?? "") to open").font(SK.font(11, .bold)).foregroundStyle(SK.muted)
                        }
                        Spacer()
                        HStack(spacing: 3) { Image(systemName: "drop.fill").font(.system(size: 11, weight: .black)).foregroundStyle(SK.sky); Text("\(VolleyTuning.drops(win: true, tier: t))").font(SK.font(15, .black)).foregroundStyle(SK.ink) }
                    }
                    .padding(10).frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(on ? SK.honey : Color.white.opacity(0.6)))
                    .opacity(open ? 1 : 0.6)
                }.buttonStyle(.plain).accessibilityIdentifier("volley-tier-\(t.rawValue)").accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .padding(14).frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(SK.card))
    }

    private func statCard(_ prof: JellyProfile?) -> some View {
        let st = book.stats(character: prof?.character ?? who)
        return VStack(alignment: .leading, spacing: 10) {
            Text("\(prof?.name ?? "Bob") on the sand").font(SK.font(20, .black)).foregroundStyle(SK.ink)
            VolleyStatBar(name: "Speed", value: st.speed, sub: "Quicker feet, longer steps", color: SK.sky)
            VolleyStatBar(name: "Power", value: st.power, sub: "Harder hits and spikes", color: SK.pink)
            VolleyStatBar(name: "Hops", value: st.hops, sub: "Higher jumps", color: SK.mint)
            VolleyStatBar(name: "Timing", value: st.timing, sub: "A bigger hit window, a truer aim", color: SK.honeyDeep)
            Text("\(st.wins) wins in \(st.matches) matches").font(SK.font(12, .bold)).foregroundStyle(SK.muted)
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(SK.card))
        .accessibilityIdentifier("volley-stats")
    }

    private func drills(_ prof: JellyProfile?) -> some View {
        let left = book.sessionsLeft(prof?.character ?? who)
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Training").font(SK.font(12, .heavy)).foregroundStyle(SK.muted).textCase(.uppercase)
                Spacer()
                HStack(spacing: 5) {
                    Text("Pep").font(SK.font(12, .heavy)).foregroundStyle(SK.ink)
                    ForEach(0..<VolleyTraining.fullSessions, id: \.self) { i in Capsule().fill(i < left ? SK.mint : Color(hex: 0xE6D8C6)).frame(width: 22, height: 10) }
                }.accessibilityElement(children: .ignore).accessibilityLabel("Pep: \(left) of \(VolleyTraining.fullSessions) full practices left today")
            }
            ForEach(VolleyDrillKind.allCases, id: \.rawValue) { k in
                Button { UIImpactFeedbackGenerator(style: .soft).impactOccurred(); AudioHub.shared.uiConfirm(); drill(k) } label: {
                    HStack(spacing: 10) {
                        Image(systemName: UIImage(systemName: k.symbol) != nil ? k.symbol : "figure.walk").font(.system(size: 20, weight: .heavy)).foregroundStyle(SK.ink)
                            .frame(width: 44, height: 44).background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(SK.sky.opacity(0.7)))
                        VStack(alignment: .leading, spacing: 1) {
                            Text(k.title).font(SK.font(15, .black)).foregroundStyle(SK.ink)
                            Text(k.blurb).font(SK.font(11, .bold)).foregroundStyle(SK.muted).fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer()
                        Text("Train").font(SK.font(13, .black)).foregroundStyle(.white).padding(.horizontal, 12).frame(minHeight: 36)
                            .background(Capsule().fill(blocker == nil ? SK.pink : SK.muted.opacity(0.45)))
                    }
                    .padding(8).background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color.white.opacity(0.6)))
                }.buttonStyle(.plain).disabled(blocker != nil).accessibilityIdentifier("volley-drill-\(k.rawValue)")
            }
            Text("Practice raises the stats a little each time. Pep refills overnight; after that it still helps, just less.").font(SK.font(11, .bold)).foregroundStyle(SK.muted)
        }
        .padding(14).frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(SK.card))
    }
}

struct VolleyStatBar: View {
    let name: String, value: Float, sub: String, color: Color
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack { Text(name).font(SK.font(15, .heavy)).foregroundStyle(SK.ink); Spacer(); Text("\(Int((value * 100).rounded()))").font(SK.font(15, .black)).foregroundStyle(SK.ink).monospacedDigit() }
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(SK.ink.opacity(0.1))
                    Capsule().fill(color).frame(width: max(14, g.size.width * CGFloat(min(max(value, 0), 1))))
                }
            }.frame(height: 14)
            Text(sub).font(SK.font(11, .bold)).foregroundStyle(SK.muted)
        }.accessibilityElement(children: .combine)
    }
}

/// The volleyball half of a Jelbie's Trophies sheet.
struct VolleyTrophiesSection: View {
    let care: GameCare
    var who: Int
    var body: some View {
        let shelf = care.race.trophies.shelf(character: care.jelly(who)?.character ?? who)
        VStack(alignment: .leading, spacing: 8) {
            Text("Beach volleyball").font(SK.font(13, .heavy)).foregroundStyle(SK.muted).textCase(.uppercase).accessibilityAddTraits(.isHeader)
            FlowLayout(spacing: 6) {
                ForEach(VolleyTier.allCases, id: \.rawValue) { t in
                    let n = shelf.volleyWon(t)
                    HStack(spacing: 4) {
                        Image(systemName: UIImage(systemName: "rosette") != nil ? "rosette" : "seal.fill").font(.system(size: 12, weight: .black))
                        Text("\(t.title) \u{00D7}\(n)").font(SK.font(12, .black))
                    }
                    .foregroundStyle(n > 0 ? SK.ink : SK.muted).padding(.horizontal, 10).padding(.vertical, 5)
                    .background(Capsule().fill(n > 0 ? Color(red: 0.98, green: 0.80, blue: 0.35) : Color.white.opacity(0.5)))
                    .accessibilityElement(children: .ignore).accessibilityLabel("\(t.title) volleyball ribbon: \(n) win\(n == 1 ? "" : "s")")
                }
                ForEach(Trophy.allVolley.filter { $0.id.hasPrefix("vwins") }) { t in
                    let has = shelf.has(t)
                    HStack(spacing: 4) {
                        Image(systemName: has ? "trophy.fill" : "lock.fill").font(.system(size: 11, weight: .black))
                        Text(has ? t.title : t.detail).font(SK.font(12, .black))
                    }
                    .foregroundStyle(has ? SK.ink : SK.muted).padding(.horizontal, 10).padding(.vertical, 5)
                    .background(Capsule().fill(has ? Color(red: 0.98, green: 0.80, blue: 0.35) : Color.white.opacity(0.5)))
                    .accessibilityElement(children: .ignore).accessibilityLabel(has ? "\(t.title), earned" : "\(t.detail), not yet")
                }
            }
        }.accessibilityIdentifier("volley-trophies")
    }
}
