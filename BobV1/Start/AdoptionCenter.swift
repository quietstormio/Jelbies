//
//  AdoptionCenter.swift
//  The species picker: a full-screen, swipeable page per species (Blueberry, Lemon Drop, Taro, Matcha) with the real 3D Jelbie on a round stage, a
//  card with About / Traits / Moves, and the big button. Used for the first Jelbie of a new game (free) and for adopting more later (Drops via
//  AdoptionPrice; "Already home" for the ones you have; stops at 3). Then the naming step and the welcome home. Portrait and landscape.
//  Content: SpeciesInfo.swift. Background / rays / bubbles: PickerBackdrop.swift. Camera orbit: PickerCamera.swift.
//  Simulator-only capture flags: -PickerPage 0...3 (picker order), -PickerTab 0...2.
//

import SwiftUI

enum PickerTab: Int, CaseIterable {
    case about, traits, moves
    var title: String { ["About", "Traits", "Moves"][rawValue] }
}

struct AdoptionCenter: View {
    let mode: StartFlow.AdoptMode
    var done: (Int, String) -> Void
    var cancel: () -> Void

    @State private var page: Int
    @State private var tab: PickerTab = .about
    @State private var naming = false
    @State private var name = ""
    @State private var celebrating = false
    @State private var wallet = DropsWallet()
    @State private var home: [Int]
    @State private var ready = false
    @State private var slideX: CGFloat = 0
    @State private var slideO: Double = 1
    @State private var paging = false
    @State private var stageModel: MelonModel?
    @State private var acting = false
    @State private var camera = PickerCamera()
    @FocusState private var nameFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotionEnv

    init(mode: StartFlow.AdoptMode, done: @escaping (Int, String) -> Void, cancel: @escaping () -> Void) {
        self.mode = mode; self.done = done; self.cancel = cancel
        let h = mode == .first ? [] : JellyRoster.savedIDs()
        _home = State(initialValue: h)
        var start = mode == .first ? 0 : (SpeciesInfo.order.firstIndex { !h.contains($0) } ?? 0)
        var t = PickerTab.about
        #if targetEnvironment(simulator)
        let d = UserDefaults.standard
        if d.object(forKey: "PickerPage") != nil { start = min(max(d.integer(forKey: "PickerPage"), 0), 3) }
        if d.object(forKey: "PickerTab") != nil { t = PickerTab(rawValue: min(max(d.integer(forKey: "PickerTab"), 0), 2)) ?? .about }
        #endif
        _page = State(initialValue: start); _tab = State(initialValue: t)
    }

    private var reduce: Bool { reduceMotionEnv || A11ySettings.shared.reduceMotion }
    private var info: SpeciesInfo { SpeciesInfo.of(SpeciesInfo.order[page]) }
    private var pick: Int { info.character }
    private var price: Int? { mode == .first ? 0 : AdoptionPrice.next(home: home.count) }
    private var isHome: Bool { home.contains(pick) }
    private var canAdopt: Bool { !isHome && (price.map { $0 <= wallet.count } ?? false) }

    var body: some View {
        GeometryReader { geo in
            let landscape = geo.size.width > geo.size.height
            ZStack {
                PickerBackdrop(top: info.skyTop, bottom: info.skyBottom, calm: reduce)
                    .animation(.easeInOut(duration: reduce ? 0.2 : 0.55), value: page)
                if landscape { landscapeLayout(geo) } else { portraitLayout(geo) }
                if celebrating { Celebration(name: name).transition(.opacity) }
            }
            .contentShape(Rectangle())
            .gesture(swipe)
        }
        .onAppear { camera.reduceMotion = reduce; camera.engage() }
        .onDisappear { camera.release() }
        .accessibilityIdentifier("adoption-center")
    }

    // MARK: layouts

    private func portraitLayout(_ geo: GeometryProxy) -> some View {
        VStack(spacing: 0) {
            topBar.padding(.horizontal, 16)
            header(compact: geo.size.height < 700).padding(.top, 2).offset(x: slideX * 0.5).opacity(slideO)
            stageArea(arrows: true)
            bottomSheet
        }
        .padding(.top, 4)
    }

    private func landscapeLayout(_ geo: GeometryProxy) -> some View {
        HStack(spacing: 0) {
            ZStack(alignment: .topLeading) {
                stageArea(arrows: true)
                topBar.padding(.leading, 16).padding(.top, 8)
            }
            .frame(width: geo.size.width * 0.5)
            VStack(spacing: 8) {
                HStack { Spacer(); if mode == .more { DropsPill(wallet: wallet) } }.padding(.top, 6).padding(.trailing, 16)
                header(compact: true).offset(x: slideX * 0.5).opacity(slideO)
                ScrollView(showsIndicators: false) { sheetCard.padding(.horizontal, 12) }
                cta.padding(.horizontal, 12).padding(.bottom, 8)
            }
            .frame(width: geo.size.width * 0.5)
        }
    }

    private var bottomSheet: some View {
        VStack(spacing: 10) { sheetCard; cta }
            .padding(.horizontal, 14).padding(.bottom, 8)
            .frame(maxWidth: 560)
    }

    // MARK: top bar and header

    private var topBar: some View {
        HStack {
            Button { AudioHub.shared.uiTap(); if naming { withAnimation(.easeOut(duration: 0.2)) { naming = false } } else { cancel() } } label: {
                Image(systemName: naming || mode == .first ? "chevron.left" : "xmark").font(.system(size: 17, weight: .heavy)).foregroundStyle(SK.ink)
                    .frame(width: 44, height: 44).background(Circle().fill(SK.cream).shadow(color: SK.shadow.opacity(0.18), radius: 4, y: 2)).contentShape(Circle())
            }
            .buttonStyle(.plain).accessibilityLabel(naming ? "Back" : (mode == .first ? "Back to the menu" : "Close")).accessibilityIdentifier("adopt-back")
            Spacer()
            if mode == .more, UIScreen.main.bounds.width <= UIScreen.main.bounds.height { DropsPill(wallet: wallet) }
        }
    }

    private func header(compact: Bool) -> some View {
        VStack(spacing: compact ? 1 : 3) {
            Text(mode == .first ? "CHOOSE YOUR FIRST JELBIE" : "ADOPT A JELBIE").font(SK.font(12, .heavy)).tracking(2.4).foregroundStyle(SK.ink.opacity(0.62))
            Text(info.name).font(SK.font(compact ? 34 : 46, .black)).foregroundStyle(SK.ink).lineLimit(1).minimumScaleFactor(0.6)
            Text(info.epithet).font(SK.font(compact ? 15 : 17, .bold)).foregroundStyle(SK.ink.opacity(0.75))
            HStack(spacing: 10) {
                ForEach(0..<SpeciesInfo.order.count, id: \.self) { i in
                    let s = SpeciesInfo.of(SpeciesInfo.order[i])
                    Circle().fill(s.tint).frame(width: 16, height: 16)
                        .overlay(Circle().strokeBorder(SK.ink.opacity(0.35), lineWidth: 1))
                        .padding(3).overlay(Circle().strokeBorder(SK.ink, lineWidth: i == page ? 2.5 : 0))
                        .contentShape(Circle().inset(by: -8))
                        .onTapGesture { jump(to: i) }
                }
            }
            .padding(.top, compact ? 2 : 5).accessibilityHidden(true)
        }
        .padding(.horizontal, 16)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(info.name), \(info.epithet). \(isHome ? "Already home. " : "")Jelbie \(page + 1) of \(SpeciesInfo.order.count)")
        .accessibilityValue(info.name)
        .accessibilityHint("Swipe up or down to change Jelbie")
        .accessibilityAddTraits(.isHeader)
        .accessibilityAdjustableAction { dir in
            switch dir { case .increment: step(1); case .decrement: step(-1); @unknown default: break }
        }
    }

    // MARK: stage

    private func stageArea(arrows: Bool) -> some View {
        GeometryReader { g in
            let d = max(120, min(g.size.width - 2 * 58, (g.size.height - 44) / 1.1))
            ZStack {
                VStack(spacing: 8) {
                    stageDisc(d)
                    dragPill
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                HStack {
                    arrow("chevron.left", "Previous Jelbie") { step(-1) }
                    Spacer()
                    arrow("chevron.right", "Next Jelbie") { step(1) }
                }
                .padding(.horizontal, 10)
            }
        }
    }

    private func stageDisc(_ d: CGFloat) -> some View {
        ZStack {
            Ellipse().fill(info.deep).frame(width: d * 0.92, height: d * 0.2).offset(y: d * 0.44)                 // the stage's side
            Ellipse().fill(Color.white.opacity(0.9)).frame(width: d * 0.92, height: d * 0.2).offset(y: d * 0.4)
            Circle().fill(info.deep).frame(width: d, height: d)                                                 // the rim
            Circle().fill(Color.white).frame(width: d - 12, height: d - 12)                                     // the white top
            ShowcaseStage(roster: [pick], focusFirst: true, fullScreen: false, onReady: stageReady)
                .id(pick).frame(width: d - 26, height: d - 26).clipShape(Circle())
            Circle().fill(info.skyTop).frame(width: d - 26, height: d - 26).opacity(ready ? 0 : 1)             // covers the build and the walk to the front
                .animation(.easeInOut(duration: 0.3), value: ready)
            Circle().contentShape(Circle()).foregroundStyle(Color.clear).frame(width: d, height: d)
                .gesture(orbit.simultaneously(with: pinch))
        }
        .frame(width: d, height: d * 1.1, alignment: .top)
        .offset(x: slideX, y: 0).opacity(slideO)
        .accessibilityHidden(true)
    }

    private var orbit: some Gesture {
        DragGesture(minimumDistance: 3).onChanged { v in
            let dx = v.translation.width - lastDrag.width, dy = v.translation.height - lastDrag.height
            lastDrag = v.translation
            camera.drag(dx: Float(dx), dy: Float(dy))
        }.onEnded { _ in lastDrag = .zero; camera.endDrag() }
    }
    @State private var lastDrag: CGSize = .zero
    private var pinch: some Gesture {
        MagnifyGesture().onChanged { v in
            if !pinching { pinching = true; camera.beginZoom() }
            camera.zoom(magnification: Float(v.magnification))
        }.onEnded { _ in pinching = false }
    }
    @State private var pinching = false

    private var dragPill: some View {
        HStack(spacing: 6) {
            Image(systemName: "arrow.triangle.2.circlepath").font(.system(size: 12, weight: .heavy))
            Text("Drag to look around").font(SK.font(13, .bold))
        }
        .foregroundStyle(SK.ink.opacity(0.75)).padding(.horizontal, 12).frame(minHeight: 28)
        .background(Capsule().fill(Color.white.opacity(0.55)))
        .accessibilityHidden(true)
    }

    private func arrow(_ symbol: String, _ label: String, _ action: @escaping () -> Void) -> some View {
        Button { AudioHub.shared.uiTap(); action() } label: {
            Image(systemName: symbol).font(.system(size: 18, weight: .black)).foregroundStyle(SK.ink)
                .frame(width: 44, height: 44).background(Circle().fill(SK.cream).shadow(color: SK.shadow.opacity(0.18), radius: 4, y: 2)).contentShape(Circle())
        }
        .buttonStyle(.plain).accessibilityLabel(label)
    }

    // MARK: card

    private var sheetCard: some View {
        VStack(spacing: 10) {
            Capsule().fill(SK.ink.opacity(0.18)).frame(width: 40, height: 5).accessibilityHidden(true)
            if naming { nameCard } else {
                tabs
                Group {
                    switch tab {
                    case .about: aboutTab
                    case .traits: traitsTab
                    case .moves: movesTab
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 142, alignment: .top)
                .id("\(page)-\(tab.rawValue)").transition(.opacity)
            }
        }
        .padding(.horizontal, 14).padding(.top, 8).padding(.bottom, 12)
        .background(RoundedRectangle(cornerRadius: 28, style: .continuous).fill(SK.cream).shadow(color: SK.shadow.opacity(0.22), radius: 10, y: 3))
        .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).strokeBorder(Color.white.opacity(0.6), lineWidth: 1))
    }

    private var tabs: some View {
        HStack(spacing: 4) {
            ForEach(PickerTab.allCases, id: \.rawValue) { t in
                Button { AudioHub.shared.uiTap(); withAnimation(.easeOut(duration: 0.18)) { tab = t } } label: {
                    Text(t.title).font(SK.font(15, .heavy)).foregroundStyle(tab == t ? SK.ink : SK.muted)
                        .frame(maxWidth: .infinity, minHeight: 36)
                        .background(Capsule().fill(tab == t ? info.tint : Color.clear))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain).accessibilityAddTraits(tab == t ? .isSelected : []).accessibilityIdentifier("picker-tab-\(t.title.lowercased())")
            }
        }
        .padding(3).background(Capsule().fill(SK.ink.opacity(0.07)))
    }

    private var aboutTab: some View {
        VStack(spacing: 10) {
            Text(info.about).font(SK.font(15, .semibold)).foregroundStyle(SK.ink).multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                tile("Best at") { Circle().fill(Self.jarColor(SpeciesInfo.jarNames.firstIndex(of: info.bestAt) ?? 0)).frame(width: 11, height: 11); Text(info.bestAt) }
                tile("Signature") { Text(info.signature) }
                tile("Loves") { Text(info.loves) }
            }
        }
    }

    private func tile<C: View>(_ title: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(spacing: 4) {
            Text(title.uppercased()).font(SK.font(10, .heavy)).tracking(1.2).foregroundStyle(SK.muted)
            HStack(spacing: 5) { content() }.font(SK.font(14, .heavy)).foregroundStyle(SK.ink).lineLimit(2).minimumScaleFactor(0.7).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, minHeight: 58).padding(.horizontal, 4)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(info.tint.opacity(0.32)))
        .accessibilityElement(children: .combine)
    }

    static func jarColor(_ i: Int) -> Color { [SK.pink, SK.honeyDeep, Color(hex: 0xB79BE0), SK.sky, SK.mint][i % 5] }

    /// The five jars: the species' starting profile, or the real stats of a Jelbie that is already home.
    private var jarValues: (values: [Int], real: Bool) {
        if isHome {
            let key = JellyKeys.stats(pick)
            if UserDefaults.standard.array(forKey: key) != nil {
                let s = JellyStats(persists: true, key: key)
                let v = SpeciesInfo.jarKeys.map { Int((s.condition($0) * 100).rounded()) }
                if v.contains(where: { $0 > 0 }) { return (v, true) }
            }
        }
        return (info.traits, false)
    }

    private var traitsTab: some View {
        let j = jarValues
        let best = j.values.enumerated().max { $0.element < $1.element }?.offset ?? 0
        return VStack(spacing: 8) {
            HStack(alignment: .bottom, spacing: 6) {
                ForEach(0..<5, id: \.self) { i in jar(i, j.values[i]) }
            }
            Text(j.real ? "Strongest in \(SpeciesInfo.jarNames[best]). These are \(JellyRoster.names[pick])'s real stats."
                        : "Strongest in \(SpeciesInfo.jarNames[best]). Jars fill up as you play together.")
                .font(SK.font(13, .semibold)).foregroundStyle(SK.muted).multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func jar(_ i: Int, _ v: Int) -> some View {
        VStack(spacing: 3) {
            Text("\(v)").font(SK.font(14, .black)).foregroundStyle(SK.ink).monospacedDigit()
            ZStack(alignment: .bottom) {
                RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.white.opacity(0.7))
                RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Self.jarColor(i).opacity(0.85)).frame(height: 46 * CGFloat(v) / 100)
                    .animation(reduce ? nil : .spring(response: 0.5, dampingFraction: 0.8), value: v)
            }
            .frame(width: 34, height: 46).clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(SK.ink.opacity(0.22), lineWidth: 1.5))
            .overlay(alignment: .top) { Capsule().fill(Self.jarColor(i)).frame(width: 26, height: 7).overlay(Capsule().strokeBorder(SK.ink.opacity(0.25), lineWidth: 1)).offset(y: -5) }
            .padding(.top, 5)
            Text(SpeciesInfo.jarNames[i]).font(SK.font(11, .heavy)).foregroundStyle(SK.muted).lineLimit(1).minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore).accessibilityLabel("\(SpeciesInfo.jarNames[i]) \(v)")
    }

    private var movesTab: some View {
        VStack(spacing: 6) {
            ForEach(Array(info.moves.enumerated()), id: \.element.id) { k, m in
                HStack(spacing: 10) {
                    Image(systemName: m.icon).font(.system(size: 16, weight: .heavy)).foregroundStyle(SK.ink)
                        .frame(width: 34, height: 34).background(Circle().fill(k == 0 ? info.tint : SK.ink.opacity(0.08)))
                    VStack(alignment: .leading, spacing: 0) {
                        Text(m.title).font(SK.font(15, .heavy)).foregroundStyle(SK.ink)
                        Text(m.subtitle).font(SK.font(12, .semibold)).foregroundStyle(SK.muted)
                    }
                    Spacer(minLength: 4)
                    Button { AudioHub.shared.uiTap(); perform(m.move) } label: {
                        Image(systemName: "play.fill").font(.system(size: 14, weight: .black)).foregroundStyle(SK.cream)
                            .frame(width: 36, height: 36).background(Circle().fill(SK.ink)).contentShape(Circle())
                    }
                    .buttonStyle(.plain).accessibilityLabel("Play \(m.title)")
                }
                .padding(.horizontal, 8).frame(minHeight: 42)
                .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(k == 0 ? info.tint.opacity(0.32) : Color.clear))
            }
        }
    }

    // MARK: button and naming

    private var cta: some View {
        Group {
            if naming { primary(Text("Bring \(finalName) home"), enabled: true, id: "adopt-bring-home") { bringHome() } }
            else {
                primary(ctaLabel, enabled: canAdopt, id: "adopt-pick") { withAnimation(.easeOut(duration: 0.2)) { name = ""; naming = true }; nameFocused = true }
            }
        }
    }

    private var ctaLabel: Text {
        if isHome { return Text("Already home") }
        guard let p = price else { return Text("Your room is full: 3 Jelbies") }
        if mode == .first { return Text("Choose \(info.name)") }
        if p > wallet.count { return Text("Need \(p - wallet.count) more Drops") }
        return Text("Adopt for \(Image(systemName: "drop.fill")) \(p)")
    }

    private var nameCard: some View {
        VStack(spacing: 10) {
            Text("What will you call your \(info.name)?").font(SK.font(19, .black)).foregroundStyle(SK.ink).multilineTextAlignment(.center)
            TextField(info.defaultName, text: $name)
                .focused($nameFocused)
                .textInputAutocapitalization(.words).autocorrectionDisabled().submitLabel(.done)
                .font(SK.font(24, .heavy)).foregroundStyle(SK.ink).multilineTextAlignment(.center)
                .padding(.horizontal, 14).frame(minHeight: 52)
                .background(Capsule().fill(Color.white.opacity(0.9)))
                .overlay(Capsule().strokeBorder(info.tint, lineWidth: 3))
                .onChange(of: name) { _, v in if v.count > 12 { name = String(v.prefix(12)) } }
                .onSubmit { bringHome() }
                .accessibilityIdentifier("adopt-name")
        }
    }

    private var finalName: String {
        let t = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? info.defaultName : String(t.prefix(12))
    }

    private func primary(_ title: Text, enabled: Bool, id: String, _ action: @escaping () -> Void) -> some View {
        Button { AudioHub.shared.uiTap(); action() } label: {
            title.font(SK.font(19, .black)).foregroundStyle(SK.cream).multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, minHeight: 56).padding(.horizontal, 10)
                .background(Capsule().fill(SK.ink.opacity(enabled ? 1 : 0.35)))
                .shadow(color: SK.shadow.opacity(enabled ? 0.25 : 0), radius: 6, y: 3)
        }
        .buttonStyle(.plain).disabled(!enabled).accessibilityIdentifier(id)
    }

    // MARK: paging

    private var swipe: some Gesture {
        DragGesture(minimumDistance: 30).onEnded { v in
            guard !naming, abs(v.translation.width) > abs(v.translation.height) else { return }
            step(v.translation.width < 0 ? 1 : -1)
        }
    }

    private func step(_ d: Int) {
        guard !naming else { return }
        let n = SpeciesInfo.order.count
        move(to: (page + d + n) % n, dir: d)
    }

    private func jump(to i: Int) {
        guard !naming, i != page else { return }
        move(to: i, dir: i > page ? 1 : -1)
    }

    /// Slides the Jelbie out, swaps the species, slides the new one in (a fade only with Reduce Motion).
    private func move(to next: Int, dir: Int) {
        guard !paging else { return }
        paging = true
        camera.reset()
        withAnimation(.easeIn(duration: 0.16)) { slideX = reduce ? 0 : CGFloat(-dir) * 220; slideO = 0 }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 170_000_000)
            ready = false; stageModel = nil; acting = false
            page = next
            slideX = reduce ? 0 : CGFloat(dir) * 220
            withAnimation(reduce ? .easeOut(duration: 0.25) : .spring(response: 0.42, dampingFraction: 0.8)) { slideX = 0; slideO = 1 }
            paging = false
        }
    }

    // MARK: the Jelbie's moves

    private func stageReady(_ m: MelonModel) {
        stageModel = m; ready = true
        Task { @MainActor in           // landing: a happy hop (or the flutter hop for wings)
            try? await Task.sleep(nanoseconds: 450_000_000)
            perform(pick == 3 ? .idle(.flapHop) : .hop)
        }
        startEmotes(for: pick)
    }

    @State private var emoteTask: Task<Void, Never>?
    /// While the player reads, the Jelbie does one gentle, in-place move or expression every few seconds that suits its personality.
    private func startEmotes(for character: Int) {
        emoteTask?.cancel()
        let list = SpeciesInfo.of(character).emotes
        emoteTask = Task { @MainActor in
            var i = Int.random(in: 0..<list.count)
            while !Task.isCancelled, pick == character {
                try? await Task.sleep(nanoseconds: UInt64(Double.random(in: 4.0...6.5) * 1_000_000_000))
                guard !Task.isCancelled, pick == character, !naming, !celebrating else { continue }
                perform(list[i % list.count]); i += 1
            }
        }
    }

    /// Asks the stage's Jelbie for a move (when it is free to take one).
    private func perform(_ move: StageMove) {
        guard let m = stageModel, !m.paused, let b = m.care.brainFor(0) else { return }
        switch move {
        case .blink: b.blinkRequested = true
        case .face(let f): b.face(f, hold: 1.6)
        case .hop: b.wantJoy()
        case .idle(let k):
            guard b.commandedIdle == nil, b.idleState.kind == nil, case .none = b.script else { return }
            if k == .flapHop, b.feature != .wings || b.wingsFolded { b.wantJoy(); return }
            b.commandedIdle = k
        }
    }

    // MARK: bring home

    private func bringHome() {
        guard !celebrating, canAdopt, let p = price else { return }
        name = finalName
        if p > 0, !wallet.spend(p) { return }
        nameFocused = false
        emoteTask?.cancel()
        AudioHub.shared.play(.coin)
        withAnimation(.easeIn(duration: 0.2)) { celebrating = true }
        let c = pick, n = name
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_800_000_000)
            done(c, n)
        }
    }
}

/// The small "bring home" moment: sparkles and hearts float up over the Jelbie.
private struct Celebration: View {
    let name: String
    @State private var go = false
    var body: some View {
        ZStack {
            Color.white.opacity(go ? 0 : 0.5).ignoresSafeArea()
            ForEach(0..<16, id: \.self) { i in
                let a = Double(i) / 16 * 2 * .pi
                Image(systemName: i % 3 == 0 ? "sparkle" : "heart.fill")
                    .font(.system(size: CGFloat(18 + (i % 4) * 5), weight: .black))
                    .foregroundStyle(i % 3 == 0 ? SK.honeyDeep : SK.pink)
                    .offset(x: go ? CGFloat(cos(a)) * 150 : 0, y: go ? CGFloat(sin(a)) * 150 - 80 : 20)
                    .opacity(go ? 0 : 1).scaleEffect(go ? 1.2 : 0.4)
                    .animation(.easeOut(duration: 1.5).delay(Double(i % 4) * 0.06), value: go)
            }
            Text("\(name) is coming home!").font(SK.font(28, .black)).foregroundStyle(SK.cream)
                .shadow(color: SK.ink.opacity(0.7), radius: 4, y: 2).multilineTextAlignment(.center).padding(.horizontal, 24)
                .scaleEffect(go ? 1 : 0.6).animation(.spring(response: 0.5, dampingFraction: 0.6), value: go)
        }
        .allowsHitTesting(true)
        .onAppear { go = true }
        .accessibilityElement(children: .combine)
    }
}
