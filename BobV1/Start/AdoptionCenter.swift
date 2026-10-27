//
//  AdoptionCenter.swift
//  The species picker: a full-screen, swipeable page per species (Blueberry, Lemon Drop, Taro, Matcha) with the real 3D Jelbie on a round
//  pedestal, a card with About / Traits / Moves, and the big button. Used for the first Jelbie of a new game (free) and for adopting more later
//  (Drops via AdoptionPrice; "Already home" for the ones you have; stops at 3). Then the naming step and the welcome home.
//  The layout follows the design boards (440 x 956 pt): everything is placed in that space and scaled to the screen. Landscape: the stage on the
//  left, the header + card + button on the right (the same blocks, scaled).
//  Content: SpeciesInfo.swift. Backdrop / pedestal: PickerBackdrop.swift. Camera orbit: PickerCamera.swift.
//  Simulator-only capture flags: -PickerPage 0...3 (picker order), -PickerTab 0...2, -PickerMode more.
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
    @State private var camera = PickerCamera()
    @State private var lastDrag: CGSize = .zero
    @State private var pinching = false
    @State private var emoteTask: Task<Void, Never>?
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
    private var look: SpeciesLook { info.look }
    private var pick: Int { info.character }
    private var price: Int? { mode == .first ? 0 : AdoptionPrice.next(home: home.count) }
    private var isHome: Bool { home.contains(pick) }
    private var canAdopt: Bool { !isHome && (price.map { $0 <= wallet.count } ?? false) }

    var body: some View {
        GeometryReader { geo in
            let landscape = geo.size.width > geo.size.height
            ZStack {
                PickerBackdrop(top: look.top, bottom: look.bottom, calm: reduce, rayOriginY: landscape ? 0.45 : 0.38)
                    .animation(.easeInOut(duration: reduce ? 0.2 : 0.55), value: page)
                if landscape { landscapeLayout(geo.size) } else { portraitLayout(geo.size) }
                if celebrating { Celebration(name: name).transition(.opacity) }
            }
            .contentShape(Rectangle())
            .gesture(swipe)
        }
        .ignoresSafeArea()
        .onAppear { camera.reduceMotion = reduce; camera.setSpecies(pick); camera.engage() }
        .onDisappear { camera.release(); emoteTask?.cancel() }
        .accessibilityIdentifier("adoption-center")
    }

    // MARK: layouts (design space 440 x 956)

    private func portraitLayout(_ size: CGSize) -> some View {
        let u = min(size.width / 440, size.height / 956)
        return ZStack(alignment: .topLeading) {
            stageBlock.offset(y: 130)
            headerBlock.frame(width: 440).offset(y: 70).offset(x: slideX * 0.4).opacity(slideO)
            topBar()
            sheetCard.frame(width: 408, height: 252).offset(x: 16, y: 597)
            cta.frame(width: 400, height: 68).offset(x: 20, y: 862)
        }
        .frame(width: 440, height: 956, alignment: .topLeading)
        .scaleEffect(u, anchor: .topLeading)
        .frame(width: 440 * u, height: 956 * u, alignment: .topLeading)
        .frame(width: size.width, height: size.height, alignment: .top)
    }

    private func landscapeLayout(_ size: CGSize) -> some View {
        let half = size.width / 2
        let us = min(half / 440, (size.height - 8) / 470)
        let ur = min((half - 20) / 440, (size.height - 12) / 500)
        return HStack(spacing: 0) {
            ZStack(alignment: .topLeading) {
                stageBlock.frame(width: 440, height: 470, alignment: .topLeading)
                    .scaleEffect(us, anchor: .topLeading).frame(width: 440 * us, height: 470 * us, alignment: .topLeading)
                    .frame(width: half, height: size.height, alignment: .center)
                topBar(pill: false).frame(width: 440, height: 130, alignment: .topLeading).scaleEffect(min(1, us), anchor: .topLeading)
                    .frame(width: half, height: 60, alignment: .topLeading).padding(.leading, 6).frame(width: half, height: size.height, alignment: .topLeading)
            }
            .frame(width: half, height: size.height)
            VStack(spacing: 0) {
                VStack(spacing: 6) {
                    headerBlock.frame(width: 440, height: 150).offset(x: slideX * 0.4).opacity(slideO)
                    sheetCard.frame(width: 408, height: 252)
                    cta.frame(width: 400, height: 68)
                }
                .frame(width: 440, height: 500, alignment: .top)
                .scaleEffect(ur, anchor: .top)
                .frame(width: 440 * ur, height: 500 * ur, alignment: .top)
            }
            .frame(width: half, height: size.height)
        }
        .overlay(alignment: .topTrailing) { if mode == .more { dropsPill.padding(.top, 10).padding(.trailing, 16) } }
    }

    // MARK: top bar and header

    /// Back / close at the top left; the Drops pill at the top right when adopting more.
    private func topBar(pill: Bool = true) -> some View {
        ZStack(alignment: .topLeading) {
            roundButton(naming || mode == .first ? "chevron.left" : "xmark", label: naming ? "Back" : (mode == .first ? "Back to the menu" : "Close"), id: "adopt-back") {
                if naming { withAnimation(.easeOut(duration: 0.2)) { naming = false } } else { cancel() }
            }
            .offset(x: 20, y: 66)
            if mode == .more && pill { dropsPill.position(x: 440 - 20 - 50, y: 88) }
        }
        .frame(width: 440, height: 130, alignment: .topLeading)
    }

    /// The Drops balance: a white pill with the blue drop (top right when adopting more).
    private var dropsPill: some View {
        HStack(spacing: 7) {
            Image(systemName: "drop.fill").font(.system(size: 20, weight: .bold)).foregroundStyle(Color(hex: 0x5BA9E0))
            Text(wallet.count.formatted()).font(SK.font(22, .black)).foregroundStyle(SK.ink).monospacedDigit().lineLimit(1).minimumScaleFactor(0.6)
        }
        .padding(.horizontal, 14).frame(minWidth: 100, minHeight: 40)
        .background(Capsule().fill(Color.white).shadow(color: look.glow.opacity(0.25), radius: 6, y: 2))
        .fixedSize()
        .accessibilityElement(children: .ignore).accessibilityLabel("\(wallet.count) Drops").accessibilityIdentifier("drops-pill")
    }

    private func roundButton(_ symbol: String, label: String, id: String? = nil, _ action: @escaping () -> Void) -> some View {
        Button { AudioHub.shared.uiTap(); action() } label: {
            Image(systemName: symbol).font(.system(size: 18, weight: .bold)).foregroundStyle(SK.ink)
                .frame(width: 44, height: 44)
                .background(Circle().fill(Color.white.opacity(0.58)))
                .overlay(Circle().strokeBorder(Color.white.opacity(0.85), lineWidth: 1.5))
                .shadow(color: look.glow.opacity(0.25), radius: 6, y: 2)
                .contentShape(Circle())
        }
        .buttonStyle(.plain).accessibilityLabel(label).accessibilityIdentifier(id ?? "picker-btn")
    }

    /// Overline, name, epithet and the four colour dots (design: overline y 18, name y 61, epithet y 104, dots y 134 in this 150-high block).
    private var headerBlock: some View {
        ZStack(alignment: .top) {
            Text(mode == .first ? "CHOOSE YOUR FIRST JELBIE" : "ADOPT A JELBIE").font(SK.font(13, .heavy)).tracking(2.6).foregroundStyle(SK.ink.opacity(0.78))
                .frame(height: 20).position(x: 220, y: 18)
            Text(info.name).font(SK.font(52, .black)).foregroundStyle(SK.ink).lineLimit(1).minimumScaleFactor(0.6).frame(width: 330, height: 60).position(x: 220, y: 61)
            Text(info.epithet).font(SK.font(17.5, .semibold)).foregroundStyle(SK.ink.opacity(0.85)).frame(height: 24).position(x: 220, y: 104)
            HStack(spacing: 4) {
                ForEach(0..<SpeciesInfo.order.count, id: \.self) { i in
                    let s = SpeciesInfo.of(SpeciesInfo.order[i])
                    let on = i == page
                    ZStack {
                        Circle().fill(Color.white).frame(width: on ? 24 : 17, height: on ? 24 : 17)
                        if on { Circle().strokeBorder(s.look.dot.opacity(0.85), lineWidth: 1.5).frame(width: 24, height: 24) }
                        Circle().fill(s.look.dot).frame(width: on ? 15 : 11, height: on ? 15 : 11)
                    }
                    .frame(width: 26, height: 26).contentShape(Circle())
                    .onTapGesture { jump(to: i) }
                }
            }
            .position(x: 221, y: 134)
            .accessibilityHidden(true)
        }
        .frame(width: 440, height: 150, alignment: .topLeading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(info.name), \(info.epithet). \(isHome ? "Already home. " : "")Jelbie \(page + 1) of \(SpeciesInfo.order.count)")
        .accessibilityHint("Swipe up or down to change Jelbie")
        .accessibilityAddTraits(.isHeader)
        .accessibilityAdjustableAction { dir in
            switch dir { case .increment: step(1); case .decrement: step(-1); @unknown default: break }
        }
    }

    // MARK: stage (design box 440 x 470, origin at canvas y 130)

    /// The pedestal, the Jelbie standing on it (transparent 3D, no room), the arrows and the "Drag to spin" pill.
    private var stageBlock: some View {
        ZStack(alignment: .topLeading) {
            PickerPedestal(look: look).offset(x: 66, y: 482 - 130 - PickerPedestal.topH / 2).offset(x: slideX * 0.15).opacity(slideO)
            ShowcaseStage(roster: [pick], focusFirst: true, fullScreen: false, cutout: true, onReady: stageReady)
                .id(pick).frame(width: 420, height: 420)
                .offset(x: 10, y: 46)
                .opacity(ready ? slideO : 0).offset(x: slideX)
                .animation(.easeInOut(duration: 0.3), value: ready)
                .allowsHitTesting(false)
            Rectangle().fill(Color.clear).contentShape(Rectangle()).frame(width: 330, height: 260)
                .gesture(orbit.simultaneously(with: pinch)).offset(x: 55, y: 215)
            roundButton("chevron.left", label: "Previous Jelbie") { step(-1) }.offset(x: 14, y: 399 - 130 - 22)
            roundButton("chevron.right", label: "Next Jelbie") { step(1) }.offset(x: 382, y: 399 - 130 - 22)
            dragPill.offset(x: 220 - 60, y: 571 - 130 - 15)
        }
        .frame(width: 440, height: 470, alignment: .topLeading)
    }

    private var orbit: some Gesture {
        DragGesture(minimumDistance: 3).onChanged { v in
            let dx = v.translation.width - lastDrag.width, dy = v.translation.height - lastDrag.height
            lastDrag = v.translation
            camera.drag(dx: Float(dx), dy: Float(dy))
        }.onEnded { _ in lastDrag = .zero; camera.endDrag() }
    }
    private var pinch: some Gesture {
        MagnifyGesture().onChanged { v in
            if !pinching { pinching = true; camera.beginZoom() }
            camera.zoom(magnification: Float(v.magnification))
        }.onEnded { _ in pinching = false }
    }

    private var dragPill: some View {
        HStack(spacing: 7) {
            Image(systemName: "arrow.counterclockwise").font(.system(size: 13, weight: .heavy))
            Text("Drag to spin").font(SK.font(15, .heavy))
        }
        .foregroundStyle(SK.ink).frame(width: 120, height: 30)
        .background(Capsule().fill(Color.white.opacity(0.58)))
        .overlay(Capsule().strokeBorder(Color.white.opacity(0.85), lineWidth: 1.5))
        .accessibilityHidden(true)
    }

    // MARK: card (design box 408 x 252)

    private var sheetCard: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 22, style: .continuous).fill(look.card).shadow(color: look.glow.opacity(0.22), radius: 10, y: 3)
            Capsule().fill(SK.ink.opacity(0.16)).frame(width: 22, height: 5).offset(x: 193, y: 8).accessibilityHidden(true)
            if naming { nameCard } else {
                tabs.offset(x: 14, y: 23)
                Group {
                    switch tab {
                    case .about: aboutTab
                    case .traits: traitsTab
                    case .moves: movesTab
                    }
                }
                .frame(width: 408, height: 252, alignment: .topLeading)
                .id("\(page)-\(tab.rawValue)").transition(.opacity)
            }
        }
        .frame(width: 408, height: 252)
    }

    private var tabs: some View {
        HStack(spacing: 0) {
            ForEach(PickerTab.allCases, id: \.rawValue) { t in
                Button { AudioHub.shared.uiTap(); withAnimation(.easeOut(duration: 0.18)) { tab = t } } label: {
                    Text(t.title).font(SK.font(16, tab == t ? .heavy : .bold)).foregroundStyle(tab == t ? SK.ink : SK.ink.opacity(0.62))
                        .frame(maxWidth: .infinity, minHeight: 34)
                        .background(Capsule().fill(tab == t ? look.tabFill : Color.clear))
                        .overlay(Capsule().strokeBorder(tab == t ? look.tabLine : Color.clear, lineWidth: 1.5))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain).accessibilityAddTraits(tab == t ? .isSelected : []).accessibilityIdentifier("picker-tab-\(t.title.lowercased())")
            }
        }
        .padding(3).frame(width: 380, height: 40)
        .background(Capsule().fill(SK.ink.opacity(0.06)))
    }

    private var aboutTab: some View {
        ZStack(alignment: .topLeading) {
            Text(info.about).font(SK.font(16, .medium)).foregroundStyle(SK.ink).lineSpacing(4).fixedSize(horizontal: false, vertical: true)
                .frame(width: 345, alignment: .leading).offset(x: 22, y: 77)
            tile("Best at", dot: SpeciesInfo.jarNames.firstIndex(of: info.bestAt).map { Self.jarColor($0) }, value: info.bestAt).offset(x: 14, y: 141)
            tile("Signature", dot: nil, value: info.signature).offset(x: 145, y: 141)
            tile("Loves", dot: nil, value: info.loves).offset(x: 277, y: 141)
        }
    }

    private func tile(_ title: String, dot: Color?, value: String) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(title).font(SK.font(12.5, .bold)).foregroundStyle(Color(hex: 0x8D7C6E))
            HStack(spacing: 6) {
                if let dot { Circle().fill(dot).frame(width: 13, height: 13) }
                Text(value).font(SK.font(19, .black)).foregroundStyle(SK.ink).lineLimit(1).minimumScaleFactor(0.7)
            }
        }
        .padding(.leading, 13).padding(.bottom, 18)
        .frame(width: 117, height: 91, alignment: .leading).offset(y: 0)
        .background(RoundedRectangle(cornerRadius: 17, style: .continuous).fill(SK.ink.opacity(0.055)))
        .accessibilityElement(children: .combine)
    }

    static func jarColor(_ i: Int) -> Color { [SK.pink, SK.honeyDeep, SK.sky, Color(hex: 0xB58BDB), SK.mint][i % 5] }

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
        return ZStack(alignment: .topLeading) {
            ForEach(0..<5, id: \.self) { i in
                PickerJar(color: Self.jarColor(i), value: j.values[i], animate: !reduce).offset(x: 52 + CGFloat(i) * 76 - 23, y: 78)
                Text(SpeciesInfo.jarNames[i]).font(SK.font(13.5, .bold)).foregroundStyle(SK.ink).frame(width: 76).offset(x: 52 + CGFloat(i) * 76 - 38, y: 176)
                    .accessibilityHidden(true)
            }
            Text(j.real ? "Strongest in \(SpeciesInfo.jarNames[best]). These are \(JellyRoster.names[pick])'s real stats."
                        : "Strongest in \(SpeciesInfo.jarNames[best]). Jars fill up as you play together.")
                .font(SK.font(14, .semibold)).foregroundStyle(SK.ink.opacity(0.62)).multilineTextAlignment(.center).frame(width: 380).offset(x: 14, y: 203)
        }
    }

    private var movesTab: some View {
        ZStack(alignment: .topLeading) {
            ForEach(Array(info.moves.enumerated()), id: \.element.id) { k, m in
                let cy: CGFloat = [103, 160, 212][k], h: CGFloat = k == 0 ? 56 : 52
                ZStack(alignment: .topLeading) {
                    if k == 0 { RoundedRectangle(cornerRadius: 17, style: .continuous).fill(look.rowHi).frame(width: 380, height: h) }
                    Circle().fill(k == 0 ? Color.white : SK.ink.opacity(0.07)).frame(width: 38, height: 38).offset(x: 14, y: (h - 38) / 2)
                    Image(systemName: m.icon).font(.system(size: 16, weight: .bold)).foregroundStyle(SK.ink).frame(width: 38, height: 38).offset(x: 14, y: (h - 38) / 2)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(m.title).font(SK.font(19, .black)).foregroundStyle(SK.ink)
                        Text(m.subtitle).font(SK.font(15, .semibold)).foregroundStyle(SK.ink.opacity(0.6))
                    }
                    .offset(x: 61, y: (h - 40) / 2)
                    Button { AudioHub.shared.uiTap(); perform(m.move) } label: {
                        Image(systemName: "play.fill").font(.system(size: 13, weight: .black)).foregroundStyle(SK.cream)
                            .frame(width: 36, height: 36).background(Circle().fill(SK.ink)).contentShape(Circle())
                    }
                    .buttonStyle(.plain).accessibilityLabel("Play \(m.title)").offset(x: 330, y: (h - 36) / 2)
                }
                .frame(width: 380, height: h, alignment: .topLeading)
                .offset(x: 14, y: cy - h / 2)
            }
        }
    }

    // MARK: button and naming

    private var nameCard: some View {
        VStack(spacing: 14) {
            Text("What will you call your \(info.name)?").font(SK.font(19, .black)).foregroundStyle(SK.ink).multilineTextAlignment(.center)
            TextField(info.defaultName, text: $name)
                .focused($nameFocused)
                .textInputAutocapitalization(.words).autocorrectionDisabled().submitLabel(.done)
                .font(SK.font(26, .heavy)).foregroundStyle(SK.ink).multilineTextAlignment(.center)
                .padding(.horizontal, 14).frame(height: 56)
                .background(Capsule().fill(Color.white.opacity(0.9)))
                .overlay(Capsule().strokeBorder(look.tabLine, lineWidth: 3))
                .onChange(of: name) { _, v in if v.count > 12 { name = String(v.prefix(12)) } }
                .onSubmit { bringHome() }
                .accessibilityIdentifier("adopt-name")
        }
        .padding(.horizontal, 24).padding(.top, 30).frame(width: 408, alignment: .top)
    }

    private var finalName: String {
        let t = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? info.defaultName : String(t.prefix(12))
    }

    private var cta: some View {
        Group {
            if naming { ctaButton(Text("Bring \(finalName) home"), enabled: true, id: "adopt-bring-home") { bringHome() } }
            else { ctaButton(ctaLabel, enabled: canAdopt, id: "adopt-pick") { withAnimation(.easeOut(duration: 0.2)) { name = ""; naming = true }; nameFocused = true } }
        }
    }

    private var ctaLabel: Text {
        if isHome { return Text("Already home") }
        guard let p = price else { return Text("Your room is full: 3 Jelbies") }
        if mode == .first { return Text("Choose \(info.name)") }
        if p > wallet.count { return Text("Need \(p - wallet.count) more Drops") }
        return Text("Adopt for \(Image(systemName: "drop.fill")) \(p)")
    }

    /// The big dark-brown pill with a darker bottom lip.
    private func ctaButton(_ title: Text, enabled: Bool, id: String, _ action: @escaping () -> Void) -> some View {
        Button { AudioHub.shared.uiTap(); action() } label: {
            ZStack(alignment: .top) {
                Capsule().fill(Color(hex: 0x2E1E12)).frame(height: 63).offset(y: 5)
                Capsule().fill(SK.ink).frame(height: 63)
                title.font(SK.font(21, .black)).foregroundStyle(SK.cream).multilineTextAlignment(.center).lineLimit(1).minimumScaleFactor(0.7)
                    .padding(.horizontal, 16).frame(height: 63)
            }
            .frame(width: 400, height: 68, alignment: .top)
            .opacity(enabled ? 1 : 0.5)
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
        withAnimation(.easeIn(duration: 0.16)) { slideX = reduce ? 0 : CGFloat(-dir) * 160; slideO = 0 }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 170_000_000)
            ready = false; stageModel = nil
            page = next
            camera.setSpecies(SpeciesInfo.order[next])
            slideX = reduce ? 0 : CGFloat(dir) * 160
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

/// One glass jar (design: 46 x 92): a coloured lid, a glass body with a white highlight stripe, the liquid at its level and the number near the bottom.
struct PickerJar: View {
    let color: Color
    let value: Int
    var animate = true
    private let w: CGFloat = 46, h: CGFloat = 92, lid: CGFloat = 13

    var body: some View {
        let bodyH = h - lid + 4
        ZStack(alignment: .top) {
            ZStack(alignment: .bottom) {
                RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color.white.opacity(0.78))
                JarLiquid(level: CGFloat(value) / 100).fill(color).frame(height: bodyH).clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .animation(animate ? .spring(response: 0.55, dampingFraction: 0.8) : nil, value: value)
                JarHighlight().stroke(Color.white.opacity(0.9), style: StrokeStyle(lineWidth: 2.4, lineCap: .round, lineJoin: .round)).frame(width: 14, height: 34)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading).padding(.leading, 9).padding(.top, 14)
                Text("\(value)").font(SK.font(13, .black)).foregroundStyle(SK.ink).monospacedDigit().padding(.bottom, 6)
            }
            .frame(width: w, height: bodyH)
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Color(hex: 0xCFDCE0), lineWidth: 2.2))
            .offset(y: lid - 4)
            Capsule().fill(color).frame(width: 32, height: lid).overlay(Capsule().strokeBorder(Color.white.opacity(0.4), lineWidth: 1))
        }
        .frame(width: w, height: h)
        .accessibilityElement(children: .ignore).accessibilityLabel("\(value)")
    }
}

private struct JarLiquid: SwiftUI.Shape {
    var level: CGFloat
    var animatableData: CGFloat { get { level } set { level = newValue } }
    func path(in r: CGRect) -> Path {
        let top = r.maxY - r.height * 0.78 * level - r.height * 0.06 * (level > 0 ? 1 : 0)
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.maxY)); p.addLine(to: CGPoint(x: r.minX, y: top))
        p.addCurve(to: CGPoint(x: r.maxX, y: top), control1: CGPoint(x: r.width * 0.3, y: top - 5), control2: CGPoint(x: r.width * 0.65, y: top + 5))
        p.addLine(to: CGPoint(x: r.maxX, y: r.maxY)); p.closeSubpath()
        return p
    }
}

/// The glass highlight: a short vertical stroke with a small hook, like the boards' "r".
private struct JarHighlight: SwiftUI.Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.minX + 1, y: r.maxY)); p.addLine(to: CGPoint(x: r.minX + 1, y: r.minY + 5))
        p.addQuadCurve(to: CGPoint(x: r.maxX, y: r.minY + 2), control: CGPoint(x: r.minX + 1, y: r.minY))
        return p
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
