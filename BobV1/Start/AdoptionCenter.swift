//
//  AdoptionCenter.swift
//  The species picker: a full-screen, swipeable page per species (Blueberry, Lemon Drop, Taro, Matcha) with the real 3D Jelbie on a round
//  pedestal, a card with About / Traits / Moves, and the big button. Used for the first Jelbie of a new game (free) and for adopting more later
//  (Drops via AdoptionPrice; any species, duplicates included, until the room holds 3). Then the naming step and the welcome home.
//  The layout follows the design boards (440 x 956 pt): everything is placed in that space and scaled to the screen. Landscape: the stage on the
//  left, the header + card + button on the right (the same blocks, scaled).
//  Content: SpeciesInfo.swift. Backdrop / pedestal: PickerBackdrop.swift. Camera orbit: PickerCamera.swift.
//  Simulator-only capture flags: -PickerPage 0...3 (picker order), -PickerTab 0...2, -PickerMode more.
//

import SwiftUI
import UIKit

enum PickerTab: Int, CaseIterable {
    case about, traits, moves
    var title: String { ["About", "Traits", "Moves"][rawValue] }
}

struct AdoptionCenter: View {
    let mode: StartFlow.AdoptMode
    /// (species, name, the colour variant taken with him): StartFlow.bringHome gives him his instance id.
    var done: (Int, String, JellyVariant?) -> Void
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
    /// Bumped on every page change; a stage's onReady is honoured only while its generation is still the current one.
    @State private var pageGen = 0
    /// Jelly Spring (mode .more) only: the branded loading cover, up until the first Jelbie is ready.
    @State private var coverUp: Bool
    @State private var stageModel: MelonModel?
    @State private var camera = PickerCamera()
    @State private var lastDrag: CGSize = .zero
    @State private var pinching = false
    @State private var emoteTask: Task<Void, Never>?
    @FocusState private var nameFocused: Bool
    /// iPad only: true when the keyboard's end frame, in window coordinates, overlaps the window by more than a shortcut bar's height.
    private static func padKeyboardCoversWindow(_ n: Notification) -> Bool {
        guard let screenFrame = (n.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect) else { return true }
        let window = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap(\.windows).first { $0.isKeyWindow }
        guard let window else { return screenFrame.height > 120 }
        let inWindow = window.convert(screenFrame, from: window.screen.coordinateSpace)
        let overlap = inWindow.intersection(window.bounds)
        return !overlap.isNull && overlap.height > 120
    }

    /// True while the software keyboard is up (the naming step then re-lays-out above it).
    @State private var kbUp = false
    @Environment(\.dynamicTypeSize) private var dts
    @Environment(\.accessibilityReduceMotion) private var reduceMotionEnv

    init(mode: StartFlow.AdoptMode, done: @escaping (Int, String, JellyVariant?) -> Void, cancel: @escaping () -> Void) {
        self.mode = mode; self.done = done; self.cancel = cancel
        let h = mode == .first ? [] : JellyRoster.savedIDs()
        _home = State(initialValue: h)
        _coverUp = State(initialValue: mode == .more)
        let homeSpecies = h.map(JellyRoster.species)          // `h` holds INSTANCE ids; the pages are species
        var start = mode == .first ? 0 : (SpeciesInfo.pages(includingSpecial: mode == .more).firstIndex { !homeSpecies.contains($0) } ?? 0)
        var t = PickerTab.about
        #if targetEnvironment(simulator)
        let d = UserDefaults.standard
        if d.object(forKey: "PickerPage") != nil { start = min(max(d.integer(forKey: "PickerPage"), 0), 3) }
        if d.object(forKey: "PickerTab") != nil { t = PickerTab(rawValue: min(max(d.integer(forKey: "PickerTab"), 0), 2)) ?? .about }
        #endif
        _page = State(initialValue: start); _tab = State(initialValue: t)
        Self.previewOffer(mode: mode, character: SpeciesInfo.pages(includingSpecial: mode == .more)[start])
    }

    private var reduce: Bool { reduceMotionEnv || A11ySettings.shared.reduceMotion }
    /// The species pages of this screen: the four starters, plus Teddy, Pearl and Panda when adopting more (not the free first gift).
    private var order: [Int] { SpeciesInfo.pages(includingSpecial: mode == .more) }
    private var info: SpeciesInfo { SpeciesInfo.of(order[page]) }
    private var look: SpeciesLook { info.look }
    private var pick: Int { info.character }
    /// Today's Jelly Spring colour variant of the shown species (nil = classic; the free first gift is always classic).
    private var variant: JellyVariant? { Self.offer(mode: mode, character: pick) }
    static func offer(mode: StartFlow.AdoptMode, character: Int) -> JellyVariant? {
        mode == .first ? nil : JellyVariantBook.offer(species: character, dayKey: JellyVariantBook.dayKey())          // every species, the ones you already have included
    }
    /// Makes the stage draw `character` in today's variant (read when the stage body is built).
    static func previewOffer(mode: StartFlow.AdoptMode, character: Int) {
        JellyVariants.setPreview(JellyRoster.previewID(character), offer(mode: mode, character: character))          // the scratch id: a preview never recolours an owned Jelbie
    }
    private var price: Int? { mode == .first ? 0 : AdoptionPrice.next(home: home.count, rare: variant?.rare == true, special: info.isSpecial) }
    /// Affordable and room for one more (the price is nil when the room is full). Owning the species already is fine: duplicates are allowed.
    private var canAdopt: Bool { price.map { $0 <= wallet.count } ?? false }
    /// The name he is given when the field is left empty: the species name, or "Teddy 2" when a Teddy is already home.
    private var suggested: String { JellyRoster.suggestedName(species: pick, taken: home.map(JellyRoster.nameOf)) }

    var body: some View {
        GeometryReader { geo in
            let landscape = HUDLayout.isPad ? HUDLayout.isLandscape(vsc: .regular, size: geo.size) : geo.size.width > geo.size.height
            ZStack {
                PickerBackdrop(top: look.top, bottom: look.bottom, calm: reduce, rayOriginY: landscape ? 0.45 : 0.38)
                    .animation(.easeInOut(duration: reduce ? 0.2 : 0.55), value: page)
                Group {
                    if bigText { flowLayout(geo.size, insets: geo.safeAreaInsets) } else if landscape { landscapeLayout(geo.size) } else { portraitLayout(geo.size) }
                    if HUDLayout.isPad, mode == .more, !landscape, !bigText {          // iPad portrait: the coin pill sits in the top-right corner, clear of the title and the status bar
                        dropsPill.padding(.top, Self.padPillTop).padding(.trailing, 24).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    }
                }
                .accessibilityHidden(coverUp)
                if coverUp { springCover(geo.size, landscape: landscape, insets: geo.safeAreaInsets).transition(.opacity).zIndex(5) }
                if celebrating { Celebration(name: name).transition(.opacity) }
            }
            .contentShape(Rectangle())
            .gesture(swipe)
        }
        // Only the container (status bar / home indicator) is ignored: the keyboard still shrinks the space, so the naming step lifts above it.
        .ignoresSafeArea(.container)
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { n in
            // iPad: the hardware-keyboard shortcut bar is small, a floating keyboard is small and off the bottom. Decide from how much of the window
            // the keyboard frame (screen coordinates, converted to window coordinates) actually covers; iPhone logic unchanged.
            withAnimation(.easeOut(duration: 0.2)) { kbUp = !HUDLayout.isPad || Self.padKeyboardCoversWindow(n) }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in withAnimation(.easeOut(duration: 0.2)) { kbUp = false } }
        .task { await runCover() }
        .onAppear { camera.reduceMotion = reduce; camera.setSpecies(pick); camera.engage() }
        .onDisappear {
            camera.release(); emoteTask?.cancel(); JellyVariants.clearPreviews()
            for s in 0..<JellyRoster.knownCount { StartFlow.resetCharacterState(JellyRoster.previewID(s)) }          // scratch preview ids never keep anything
        }
        .accessibilityIdentifier("adoption-center")
    }

    // MARK: layouts (design space 440 x 956)

    /// Larger text than the default: the fixed design canvas cannot hold it, so the page becomes a scrolling column (see flowLayout).
    private var bigText: Bool { dts > .large }
    /// Design-space size that is 44 pt on screen at canvas scale `u` (so small controls keep a 44 pt touch target).
    private func hitMin(_ u: CGFloat) -> CGFloat { max(44, 44 / max(u, 0.1)) }

    /// Largest canvas scale on an iPad-sized window (shorter side over 600 pt); unlimited on a phone.
    private static func padCap(_ size: CGSize) -> CGFloat { min(size.width, size.height) > 600 ? 1.3 : .greatestFiniteMagnitude }

    /// iPad: the coin pill's distance from the top edge (the window ignores the safe area, and the iPad status bar is ~24 pt).
    private static let padPillTop: CGFloat = 40

    /// Jelly Spring: keeps the loading cover up for at least 0.6 s and until the first Jelbie is ready (6 s at the latest), then fades it out.
    private func runCover() async {
        guard coverUp else { return }
        let start = Date()
        while !Task.isCancelled {
            let e = Date().timeIntervalSince(start)
            if (ready && e >= 0.6) || e >= 6 { break }
            try? await Task.sleep(nanoseconds: 40_000_000)
        }
        guard !Task.isCancelled else { return }
        withAnimation(.easeOut(duration: 0.35)) { coverUp = false }
    }

    /// Where the real close button sits (screen points, canvas scale for its size), so the cover's copy lands exactly on it.
    private func coverClose(_ size: CGSize, landscape: Bool, insets: EdgeInsets) -> (center: CGPoint, u: CGFloat) {
        if bigText { return (CGPoint(x: 16 + 22 + max(0, (size.width - 592) / 2), y: max(insets.top, 20) + 6 + 22), 1) }
        if landscape {
            let us = min(size.width / 2 / 440, (size.height - 8) / 470, Self.padCap(size)), s = min(1, us)
            return (CGPoint(x: 6 + 42 * s, y: 88 * s), s)
        }
        let u = min(size.width / 440, size.height / 956, Self.padCap(size))
        return (CGPoint(x: (size.width - 440 * u) / 2 + 42 * u, y: 88 * u), u)
    }

    /// The branded cover over the Jelly Spring page while the first Jelbie builds: backdrop, overline, big title, bouncing jelly dots, tagline.
    private func springCover(_ size: CGSize, landscape: Bool, insets: EdgeInsets) -> some View {
        let c = coverClose(size, landscape: landscape, insets: insets)
        return ZStack {
            PickerBackdrop(top: look.top, bottom: look.bottom, calm: reduce, rayOriginY: 0.42).ignoresSafeArea()
                .contentShape(Rectangle()).onTapGesture { }
            VStack(spacing: 14) {
                Text("THE JELLY SPRING").font(SK.font(13, .heavy)).tracking(2.2).foregroundStyle(SK.ink.opacity(0.78))
                Text("Jelly Spring").font(SK.font(56, .black)).foregroundStyle(SK.ink).lineLimit(1).minimumScaleFactor(0.5)
                if reduce { ProgressView().tint(SK.ink.opacity(0.6)).controlSize(.large).frame(height: 40) }
                else { SpringLoaderDots(colors: order.map { SpeciesInfo.of($0).look.dot }).frame(height: 40) }
                Text("Every adoption helps the Spring care for the Jelbies still waiting.").font(SK.font(13, .semibold)).foregroundStyle(SK.ink.opacity(0.72))
                    .lineLimit(3).minimumScaleFactor(0.8).multilineTextAlignment(.center).padding(.horizontal, 36)
            }
            .padding(.horizontal, 20)
            .accessibilityElement(children: .ignore).accessibilityLabel("Opening the Jelly Spring")
            roundButton("xmark", label: "Close", id: "adopt-cover-close", u: c.u) { cancel() }
                .scaleEffect(c.u).position(c.center)
        }
        .onAppear { AccessibilityNotification.Announcement("Opening the Jelly Spring").post() }
    }

    private func portraitLayout(_ size: CGSize) -> some View {
        // Naming with the keyboard up: the canvas keeps its width scale, drops the header, shrinks the Jelbie and stacks the name card and
        // the button right under it, so both sit above the keyboard.
        let compact = naming && kbUp
        let u = compact ? min(size.width / 440, 1.2) : min(size.width / 440, size.height / 956, Self.padCap(size))
        let h = size.height / u                                   // visible design height
        let su = min(0.7, max(0, h - 352) / 470)
        let showStage = !compact || su >= 0.25
        let stageS: CGFloat = compact ? su : 1
        let padNaming = HUDLayout.isPad && naming && !compact          // iPad naming step: a snug card with the button right under it (no empty lower half)
        let cardH: CGFloat = compact ? 160 : padNaming ? 170 : 252
        let cardY: CGFloat = compact ? 108 + (showStage ? 470 * su : 0) : 597
        let ctaY: CGFloat = compact ? cardY + cardH + 6 : padNaming ? cardY + cardH + 16 : 862
        let canvasH: CGFloat = compact ? h : 956
        return ZStack(alignment: .topLeading) {
            stageBlock(u).scaleEffect(stageS, anchor: .topLeading).offset(y: compact ? 100 : 130).opacity(showStage ? 1 : 0).allowsHitTesting(showStage)
            headerBlock.frame(width: 440).offset(y: 70).opacity(compact ? 0 : 1).allowsHitTesting(!compact)
            topBar(pill: !HUDLayout.isPad, u: u)
            sheetCard(u, height: cardH).frame(width: 408, height: cardH).offset(x: 16, y: cardY)
            cta.frame(width: 400, height: 68).offset(x: 20, y: ctaY)
        }
        .frame(width: 440, height: canvasH, alignment: .topLeading)
        .scaleEffect(u, anchor: .topLeading)
        .frame(width: 440 * u, height: canvasH * u, alignment: .topLeading)
        .frame(width: size.width, height: size.height, alignment: .top)
    }

    private func landscapeLayout(_ size: CGSize) -> some View {
        let half = size.width / 2
        let cap = Self.padCap(size)          // iPad-sized windows only; iPhone unchanged
        let us = min(half / 440, (size.height - 8) / 470, cap)
        let ur = min((half - 20) / 440, (size.height - 12) / 500, cap)
        let compact = naming && kbUp
        let uc = min((half - 20) / 440, (size.height - 8) / 240, cap)  // name card + button only, above the keyboard
        return HStack(spacing: 0) {
            ZStack(alignment: .topLeading) {
                stageBlock(us).frame(width: 440, height: 470, alignment: .topLeading)
                    .scaleEffect(us, anchor: .topLeading).frame(width: 440 * us, height: 470 * us, alignment: .topLeading)
                    .frame(width: half, height: size.height, alignment: .center)
                topBar(pill: false, u: min(1, us)).frame(width: 440, height: 130, alignment: .topLeading).scaleEffect(min(1, us), anchor: .topLeading)
                    .frame(width: half, height: 60, alignment: .topLeading).padding(.leading, 6).frame(width: half, height: size.height, alignment: .topLeading)
                // iPhone landscape: the coin pill sits in the stage column's top-right corner, so it can never meet the centred title column
                if mode == .more, !HUDLayout.isPad { dropsPillCompact.padding(.top, 10).padding(.trailing, 12).frame(width: half, height: size.height, alignment: .topTrailing) }
            }
            .frame(width: half, height: size.height)
            VStack(spacing: 0) {
                if compact {
                    VStack(spacing: 6) {
                        sheetCard(uc, height: 160).frame(width: 408, height: 160)
                        cta.frame(width: 400, height: 68)
                    }
                    .frame(width: 440, height: 240, alignment: .top)
                    .scaleEffect(uc, anchor: .top)
                    .frame(width: 440 * uc, height: 240 * uc, alignment: .top)
                } else {
                    let padNaming = HUDLayout.isPad && naming          // iPad naming step: snug card, the whole column centred (no blank lower half)
                    let headH: CGFloat = mode == .more ? 172 : 150, cardH: CGFloat = padNaming ? 170 : 252, ctaH: CGFloat = 68, gap: CGFloat = 6
                    let colH: CGFloat = padNaming ? headH + cardH + ctaH + gap * 2 : 500          // iPad: the sum of the stacked parts, so it cannot clip
                    VStack(spacing: gap) {
                        headerBlock.frame(width: 440, height: headH, alignment: .top)
                        sheetCard(ur, height: cardH).frame(width: 408, height: cardH)
                        cta.frame(width: 400, height: ctaH)
                    }
                    .frame(width: 440, height: colH, alignment: .top)
                    .scaleEffect(ur, anchor: .top)
                    .frame(width: 440 * ur, height: colH * ur, alignment: .top)
                }
            }
            .frame(width: half, height: size.height)
        }
        .overlay(alignment: .topTrailing) { if mode == .more, HUDLayout.isPad { dropsPill.padding(.top, Self.padPillTop).padding(.trailing, 24) } }
    }

    // MARK: large-text layout (Dynamic Type above Large)

    /// The same blocks as one scrolling column that grows with the text: back button, header, the Jelbie, the card, the button. The naming step
    /// scrolls the field and the button into view above the keyboard.
    private func flowLayout(_ size: CGSize, insets: EdgeInsets) -> some View {
        let ss = min(0.75, (min(size.width, 560) - 32) / 440)
        return ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 16) {
                    HStack {
                        roundButton(naming || mode == .first ? "chevron.left" : "xmark", label: naming ? "Back" : (mode == .first ? "Back to the menu" : "Close"), id: "adopt-back") {
                            if naming { withAnimation(.easeOut(duration: 0.2)) { naming = false } } else { cancel() }
                        }
                        Spacer(minLength: 8)
                        if mode == .more { dropsPill }
                    }
                    if !naming { flowHeader }
                    stageBlock(1).frame(width: 440, height: 470, alignment: .topLeading)
                        .scaleEffect(ss, anchor: .topLeading).frame(width: 440 * ss, height: 470 * ss, alignment: .topLeading)
                        .frame(height: naming && kbUp ? 0 : 470 * ss).clipped().opacity(naming && kbUp ? 0 : 1)
                    if !naming {
                        HStack {
                            roundButton("chevron.left", label: "Previous Jelbie") { step(-1) }
                            Spacer()
                            roundButton("chevron.right", label: "Next Jelbie") { step(1) }
                        }
                    }
                    flowCard
                    flowCTA.id("flow-cta")
                }
                .frame(maxWidth: 560)
                .padding(.horizontal, 16).padding(.top, max(insets.top, 20) + 6).padding(.bottom, max(insets.bottom, 0) + 24)
                .frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: naming) { _, on in if on { scrollToButton(proxy) } }
            .onChange(of: kbUp) { _, up in if up && naming { scrollToButton(proxy) } }
        }
    }

    private func scrollToButton(_ proxy: ScrollViewProxy) {
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 250_000_000)
            withAnimation(.easeOut(duration: 0.25)) { proxy.scrollTo("flow-cta", anchor: .bottom) }
        }
    }

    private var flowHeader: some View {
        VStack(spacing: 6) {
            Text(mode == .first ? "THE SPRING'S WELCOME GIFT" : "THE JELLY SPRING").font(SK.font(13, .heavy)).tracking(2.6).foregroundStyle(SK.ink.opacity(0.78))
            Text(info.name).font(SK.font(52, .black)).foregroundStyle(SK.ink).minimumScaleFactor(0.5)
            Text(info.epithet + (variant.map { " · \($0.title)" } ?? "")).font(SK.font(17.5, .semibold)).foregroundStyle(SK.ink.opacity(0.85))
            if variant?.rare == true {
                Text("Rare").font(SK.font(12.5, .black)).foregroundStyle(SK.ink)
                    .padding(.horizontal, 10).padding(.vertical, 3)
                    .background(Capsule().fill(Color(hex: 0xFFD65C)))
                    .overlay(Capsule().strokeBorder(Color.white.opacity(0.85), lineWidth: 1.5))
                    .accessibilityIdentifier("adopt-rare-tag")
            }
            if mode == .more { roomLine }
            HStack(spacing: 4) {
                ForEach(0..<order.count, id: \.self) { i in
                    Circle().fill(SpeciesInfo.of(order[i]).look.dot).frame(width: i == page ? 15 : 11, height: i == page ? 15 : 11)
                        .padding(3).background(Circle().fill(Color.white))
                }
            }
            .accessibilityHidden(true)
        }
        .multilineTextAlignment(.center).frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(headerLabel)
        .accessibilityHint("Swipe up or down to change Jelbie")
        .accessibilityAddTraits(.isHeader)
        .accessibilityAdjustableAction { dir in
            switch dir { case .increment: step(1); case .decrement: step(-1); @unknown default: break }
        }
    }

    private var flowCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            if naming {
                Text("What will you call your \(info.name)?").font(SK.font(19, .black)).foregroundStyle(SK.ink).multilineTextAlignment(.center).frame(maxWidth: .infinity)
                nameField(1)
            } else {
                flowTabs
                switch tab {
                case .about: flowAbout
                case .traits: flowTraits
                case .moves: flowMoves
                }
            }
        }
        .padding(18).frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(look.card).shadow(color: look.glow.opacity(0.22), radius: 6, y: 3))
    }

    private var flowTabs: some View {
        HStack(spacing: 0) {
            ForEach(PickerTab.allCases, id: \.rawValue) { t in
                Button { AudioHub.shared.uiTap(); withAnimation(.easeOut(duration: 0.18)) { tab = t } } label: {
                    Text(t.title).font(SK.font(16, tab == t ? .heavy : .bold)).foregroundStyle(tab == t ? SK.ink : SK.ink.opacity(0.62))
                        .lineLimit(1).minimumScaleFactor(0.7)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(Capsule().fill(tab == t ? look.tabFill : Color.clear))
                        .overlay(Capsule().strokeBorder(tab == t ? look.tabLine : Color.clear, lineWidth: 1.5))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain).accessibilityAddTraits(tab == t ? .isSelected : []).accessibilityIdentifier("picker-tab-\(t.title.lowercased())")
            }
        }
        .padding(3).background(Capsule().fill(SK.ink.opacity(0.06)))
    }

    private var flowAbout: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(info.about).font(SK.font(16, .medium)).foregroundStyle(SK.ink).lineSpacing(4).fixedSize(horizontal: false, vertical: true)
            flowTile("Best at", dot: SpeciesInfo.jarNames.firstIndex(of: info.bestAt).map { Self.jarColor($0) }, value: info.bestAt)
            flowTile("Signature", dot: nil, value: info.signature)
            flowTile("Loves", dot: nil, value: info.loves)
        }
    }

    private func flowTile(_ title: String, dot: Color?, value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(SK.font(12.5, .bold)).foregroundStyle(Color(hex: 0x8D7C6E))
            HStack(spacing: 6) {
                if let dot { Circle().fill(dot).frame(width: 13, height: 13) }
                Text(value).font(SK.font(19, .black)).foregroundStyle(SK.ink)
            }
        }
        .padding(13).frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 17, style: .continuous).fill(SK.ink.opacity(0.055)))
        .accessibilityElement(children: .combine)
    }

    private var flowTraits: some View {
        let j = jarValues
        let best = j.values.enumerated().max { $0.element < $1.element }?.offset ?? 0
        return VStack(spacing: 12) {
            HStack(alignment: .top, spacing: 2) {
                ForEach(0..<5, id: \.self) { i in
                    VStack(spacing: 6) {
                        PickerJar(color: Self.jarColor(i), value: j.values[i], animate: !reduce)
                        Text(SpeciesInfo.jarNames[i]).font(SK.font(13.5, .bold)).foregroundStyle(SK.ink).lineLimit(2).minimumScaleFactor(0.6)
                            .multilineTextAlignment(.center).accessibilityHidden(true)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            Text("Strongest in \(SpeciesInfo.jarNames[best]). Jars fill up as you play together.")
                .font(SK.font(14, .semibold)).foregroundStyle(SK.ink.opacity(0.62)).multilineTextAlignment(.center).frame(maxWidth: .infinity)
        }
    }

    private var flowMoves: some View {
        VStack(spacing: 8) {
            ForEach(Array(info.moves.enumerated()), id: \.element.id) { k, m in
                HStack(spacing: 10) {
                    Image(systemName: m.icon).font(.system(size: 16, weight: .bold)).foregroundStyle(SK.ink)
                        .frame(width: 38, height: 38).background(Circle().fill(k == 0 ? Color.white : SK.ink.opacity(0.07)))
                    VStack(alignment: .leading, spacing: 1) {
                        Text(m.title).font(SK.font(19, .black)).foregroundStyle(SK.ink)
                        Text(m.subtitle).font(SK.font(15, .semibold)).foregroundStyle(SK.ink.opacity(0.6))
                    }
                    Spacer(minLength: 4)
                    Button { AudioHub.shared.uiTap(); perform(m.move) } label: {
                        Image(systemName: "play.fill").font(.system(size: 13, weight: .black)).foregroundStyle(SK.cream)
                            .frame(width: 36, height: 36).background(Circle().fill(SK.ink))
                            .frame(width: 44, height: 44).contentShape(Circle())
                    }
                    .buttonStyle(.plain).accessibilityLabel("Play \(m.title)")
                }
                .padding(.horizontal, 12).padding(.vertical, 8).frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 17, style: .continuous).fill(k == 0 ? look.rowHi : Color.clear))
            }
        }
    }

    private var flowCTA: some View {
        Group {
            if naming { flowCtaButton(Text("Bring \(finalName) home"), enabled: true, id: "adopt-bring-home") { bringHome() } }
            else { flowCtaButton(ctaLabel, enabled: canAdopt, id: "adopt-pick") { withAnimation(.easeOut(duration: 0.2)) { name = ""; naming = true }; nameFocused = true } }
        }
    }

    /// The big dark-brown pill, growing with the text instead of clipping it.
    private func flowCtaButton<T: View>(_ title: T, enabled: Bool, id: String, _ action: @escaping () -> Void) -> some View {
        Button { AudioHub.shared.uiTap(); action() } label: {
            title.font(SK.font(21, .black)).foregroundStyle(SK.cream).multilineTextAlignment(.center)
                .padding(.horizontal, 16).padding(.vertical, 14).frame(maxWidth: .infinity, minHeight: 63)
                .background(Capsule().fill(SK.ink))
                .background(Capsule().fill(Color(hex: 0x2E1E12)).offset(y: 5))
                .padding(.bottom, 5)
                .opacity(enabled ? 1 : 0.5)
        }
        .buttonStyle(.plain).disabled(!enabled).accessibilityIdentifier(id)
    }

    // MARK: top bar and header

    /// Back / close at the top left; the Drops pill at the top right when adopting more.
    private func topBar(pill: Bool = true, u: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            roundButton(naming || mode == .first ? "chevron.left" : "xmark", label: naming ? "Back" : (mode == .first ? "Back to the menu" : "Close"), id: "adopt-back", u: u) {
                if naming { withAnimation(.easeOut(duration: 0.2)) { naming = false } } else { cancel() }
            }
            .offset(x: 20, y: 66)
            if mode == .more && pill { dropsPillCompact.position(x: 440 - 14 - Self.compactPillW / 2, y: 88) }
        }
        .frame(width: 440, height: 130, alignment: .topLeading)
    }

    /// The Drops balance: a white pill with the blue drop (top right when adopting more).
    private var dropsPill: some View {
        HStack(spacing: 7) {
            JellyCoinIcon(size: 28)
            Text(wallet.count.formatted()).font(SK.font(22, .black)).foregroundStyle(SK.ink).monospacedDigit().lineLimit(1).minimumScaleFactor(0.6)
        }
        .padding(.horizontal, 14).frame(minWidth: 100, minHeight: 40)
        .background(Capsule().fill(Color.white).shadow(color: look.glow.opacity(0.25), radius: 6, y: 2))
        .fixedSize()
        .accessibilityElement(children: .ignore).accessibilityLabel("\(wallet.count) JellyCoins").accessibilityIdentifier("drops-pill")
    }

    /// Width of the compact top-row pill in canvas points: its left edge (x 308) stays 10 pt clear of the overline's right edge (about x 298).
    private static let compactPillW: CGFloat = 118

    /// Portrait / landscape iPhone pill: coin 24, digits 19, padding 11, height 36, right-aligned in a 118-wide slot; the digits shrink instead of growing it.
    private var dropsPillCompact: some View {
        HStack(spacing: 6) {
            JellyCoinIcon(size: 24)
            Text(wallet.count.formatted()).font(SK.font(19, .black)).foregroundStyle(SK.ink).monospacedDigit().lineLimit(1).minimumScaleFactor(0.5)
                .frame(maxWidth: Self.compactPillW - 22 - 24 - 6)
        }
        .padding(.horizontal, 11).frame(height: 36)
        .background(Capsule().fill(Color.white).shadow(color: look.glow.opacity(0.25), radius: 6, y: 2))
        .frame(width: Self.compactPillW, height: 36, alignment: .trailing)
        .accessibilityElement(children: .ignore).accessibilityLabel("\(wallet.count) JellyCoins").accessibilityIdentifier("drops-pill")
    }

    private func roundButton(_ symbol: String, label: String, id: String? = nil, u: CGFloat = 1, _ action: @escaping () -> Void) -> some View {
        let d = hitMin(u)
        return Button { AudioHub.shared.uiTap(); action() } label: {
            Image(systemName: symbol).font(.system(size: 18, weight: .bold)).foregroundStyle(SK.ink)
                .frame(width: 44, height: 44)
                .background(Circle().fill(Color.white.opacity(0.58)))
                .overlay(Circle().strokeBorder(Color.white.opacity(0.85), lineWidth: 1.5))
                .shadow(color: look.glow.opacity(0.25), radius: 6, y: 2)
                .frame(width: d, height: d)             // 44 pt on screen even when the canvas is scaled down
                .contentShape(Circle())
                .padding(-(d - 44) / 2)                 // the look and position stay as designed
        }
        .buttonStyle(.plain).accessibilityLabel(label).accessibilityIdentifier(id ?? "picker-btn")
    }

    /// Overline, name, epithet and the four colour dots (design: overline y 18, name y 61, epithet y 104, dots y 134 in this 150-high block).
    private var headerBlock: some View {
        ZStack(alignment: .top) {
            Text(mode == .first ? "THE SPRING'S WELCOME GIFT" : "THE JELLY SPRING").font(SK.font(13, .heavy)).tracking(2.2).foregroundStyle(SK.ink.opacity(0.78))
                .frame(height: 20).position(x: 220, y: 18)
            // Only the name, epithet and Rare tag slide and fade with a swipe; the overline, dots and room line stay put.
            ZStack(alignment: .topLeading) {
                Text(info.name).font(SK.font(52, .black)).foregroundStyle(SK.ink).lineLimit(1).minimumScaleFactor(0.6).frame(width: 330, height: 60).position(x: 220, y: 61)
                Text(info.epithet + (variant.map { " · \($0.title)" } ?? "")).font(SK.font(17.5, .semibold)).foregroundStyle(SK.ink.opacity(0.85)).frame(height: 24).position(x: 220, y: 104)
                if variant?.rare == true {
                    // Right of the name (the coin pill occupies the overline row's right end).
                    Text("Rare").font(SK.font(12.5, .black)).foregroundStyle(SK.ink)
                        .padding(.horizontal, 10).frame(height: 22)
                        .background(Capsule().fill(Color(hex: 0xFFD65C)))
                        .overlay(Capsule().strokeBorder(Color.white.opacity(0.85), lineWidth: 1.5))
                        .position(x: 396, y: 52).accessibilityIdentifier("adopt-rare-tag")
                }
            }
            .frame(width: 440, height: 150, alignment: .topLeading)
            .offset(x: slideX * 0.4).opacity(slideO)
            if mode == .more {
                roomLine.frame(width: 380).position(x: 220, y: 160)
            }
            HStack(spacing: 4) {
                ForEach(0..<order.count, id: \.self) { i in
                    let s = SpeciesInfo.of(order[i])
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
        .accessibilityLabel(headerLabel)
        .accessibilityHint("Swipe up or down to change Jelbie")
        .accessibilityAddTraits(.isHeader)
        .accessibilityAdjustableAction { dir in
            switch dir { case .increment: step(1); case .decrement: step(-1); @unknown default: break }
        }
    }

    /// The still home-room status line (Jelly Spring only): how many Jelbies are home and how many more fit.
    private var roomText: String {
        let cap = JellyRoster.maxCount, n = min(home.count, cap), free = cap - n
        return free > 0 ? "\(n) of \(cap) at home · room for \(free) more" : "Your home is full · \(n) of \(cap)"
    }
    private var roomLine: some View {
        HStack(spacing: 5) {
            Image(systemName: "house.fill").font(.system(size: 12, weight: .bold))
            Text(roomText).lineLimit(1).minimumScaleFactor(0.8)
        }
        .font(SK.font(13, .semibold)).foregroundStyle(SK.ink.opacity(0.72)).multilineTextAlignment(.center)
        .accessibilityHidden(true)
    }

    private var headerLabel: String { "\(mode == .more ? "The Jelly Spring. \(roomText). Every adoption helps the Spring care for the Jelbies still waiting. " : "")\(info.name), \(info.epithet). \(variant.map { ($0.rare ? "Rare colour: " : "Today's colour: ") + $0.title + ". " } ?? "")Jelbie \(page + 1) of \(order.count)" }

    // MARK: stage (design box 440 x 470, origin at canvas y 130)

    /// The pedestal, the Jelbie standing on it (transparent 3D, no room), the arrows and the "Drag to spin" pill.
    /// The soft placeholder shows while the page's Jelbie builds (never under the loading cover, never while naming).
    private var showPlaceholder: Bool { !ready && !naming && !coverUp }

    private func stageBlock(_ u: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            PickerPedestal(look: look).offset(x: 66, y: 482 - 130 - PickerPedestal.topH / 2).offset(x: slideX * 0.15).opacity(slideO)
            Group {
                if showPlaceholder {
                    StagePlaceholder(color: look.dot, calm: reduce)
                        .frame(width: 120, height: 128).offset(x: 160, y: 350 - 128)       // stands on the pedestal's top (centre at local y 352)
                        .offset(x: slideX * 0.15).opacity(slideO)
                        .transition(.opacity)
                        .allowsHitTesting(false).accessibilityHidden(true)
                }
            }
            .animation(.easeInOut(duration: 0.3), value: showPlaceholder)
            ShowcaseStage(roster: [JellyRoster.previewID(pick)], focusFirst: true, fullScreen: false, cutout: true, onReady: { [gen = pageGen, expect = pick] m in stageReady(m, character: expect, gen: gen) })
                .id(pick).frame(width: 420, height: 420)
                .offset(x: 10, y: 46)
                .opacity(ready ? slideO : 0).offset(x: slideX)
                .animation(.easeInOut(duration: 0.3), value: ready)
                .allowsHitTesting(false)
            Rectangle().fill(Color.clear).contentShape(Rectangle()).frame(width: 330, height: 260)
                .gesture(orbit.simultaneously(with: pinch)).offset(x: 55, y: 215)
            roundButton("chevron.left", label: "Previous Jelbie", u: u) { step(-1) }.offset(x: 14, y: 399 - 130 - 22)
            roundButton("chevron.right", label: "Next Jelbie", u: u) { step(1) }.offset(x: 382, y: 399 - 130 - 22)
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

    private func sheetCard(_ u: CGFloat, height: CGFloat = 252) -> some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 22, style: .continuous).fill(look.card).shadow(color: look.glow.opacity(0.22), radius: 6, y: 3)
            Capsule().fill(SK.ink.opacity(0.16)).frame(width: 22, height: 5).offset(x: 193, y: 8).accessibilityHidden(true)
            if naming { nameCard(u) } else {
                tabs(u).offset(x: 14, y: 23)
                Group {
                    switch tab {
                    case .about: aboutTab
                    case .traits: traitsTab
                    case .moves: movesTab(u)
                    }
                }
                .frame(width: 408, height: 252, alignment: .topLeading)
                .id("\(page)-\(tab.rawValue)").transition(.opacity)
            }
        }
        .frame(width: 408, height: height)
    }

    private func tabs(_ u: CGFloat) -> some View {
        HStack(spacing: 0) {
            ForEach(PickerTab.allCases, id: \.rawValue) { t in
                Button { AudioHub.shared.uiTap(); withAnimation(.easeOut(duration: 0.18)) { tab = t } } label: {
                    Text(t.title).font(SK.font(16, tab == t ? .heavy : .bold)).foregroundStyle(tab == t ? SK.ink : SK.ink.opacity(0.62))
                        .frame(maxWidth: .infinity, minHeight: 34)
                        .background(Capsule().fill(tab == t ? look.tabFill : Color.clear))
                        .overlay(Capsule().strokeBorder(tab == t ? look.tabLine : Color.clear, lineWidth: 1.5))
                        .frame(minHeight: hitMin(u))        // a 44 pt touch target around the 34 pt pill
                        .contentShape(Rectangle())
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

    /// The five jars: always the species' starting profile (duplicates are allowed, so "the one at home" is no longer a single Jelbie).
    private var jarValues: (values: [Int], real: Bool) { (info.traits, false) }

    private var traitsTab: some View {
        let j = jarValues
        let best = j.values.enumerated().max { $0.element < $1.element }?.offset ?? 0
        return ZStack(alignment: .topLeading) {
            ForEach(0..<5, id: \.self) { i in
                PickerJar(color: Self.jarColor(i), value: j.values[i], animate: !reduce).offset(x: 52 + CGFloat(i) * 76 - 23, y: 78)
                Text(SpeciesInfo.jarNames[i]).font(SK.font(13.5, .bold)).foregroundStyle(SK.ink).frame(width: 76).offset(x: 52 + CGFloat(i) * 76 - 38, y: 176)
                    .accessibilityHidden(true)
            }
            Text("Strongest in \(SpeciesInfo.jarNames[best]). Jars fill up as you play together.")
                .font(SK.font(14, .semibold)).foregroundStyle(SK.ink.opacity(0.62)).multilineTextAlignment(.center).frame(width: 380).offset(x: 14, y: 203)
        }
    }

    private func movesTab(_ u: CGFloat) -> some View {
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
                            .frame(width: 36, height: 36).background(Circle().fill(SK.ink))
                            .frame(width: hitMin(u), height: hitMin(u)).contentShape(Circle()).padding(-(hitMin(u) - 36) / 2)
                    }
                    .buttonStyle(.plain).accessibilityLabel("Play \(m.title)").offset(x: 330, y: (h - 36) / 2)
                }
                .frame(width: 380, height: h, alignment: .topLeading)
                .offset(x: 14, y: cy - h / 2)
            }
        }
    }

    // MARK: button and naming

    /// The name field: dark text on the white pill whatever the system appearance, a visible placeholder, 44 pt tall at least.
    private func nameField(_ u: CGFloat) -> some View {
        TextField("", text: $name, prompt: Text(suggested).foregroundStyle(SK.ink.opacity(0.4)))
            .focused($nameFocused)
            .textInputAutocapitalization(.words).autocorrectionDisabled().submitLabel(.done)
            .font(SK.font(26, .heavy)).foregroundStyle(SK.ink).tint(SK.ink).multilineTextAlignment(.center)
            .padding(.horizontal, 14).frame(minHeight: max(56, hitMin(u)))
            .background(Capsule().fill(Color.white.opacity(0.9)))
            .overlay(Capsule().strokeBorder(look.tabLine, lineWidth: 3))
            .onChange(of: name) { _, v in if v.count > 12 { name = String(v.prefix(12)) } }
            .onSubmit { bringHome() }
            .accessibilityIdentifier("adopt-name")
    }

    private func nameCard(_ u: CGFloat) -> some View {
        VStack(spacing: 14) {
            Text("What will you call your \(info.name)?").font(SK.font(19, .black)).foregroundStyle(SK.ink).multilineTextAlignment(.center)
            nameField(u)
        }
        .padding(.horizontal, 24).padding(.top, 30).frame(width: 408, alignment: .top)
    }

    private var finalName: String {
        let t = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty { return suggested }
        return JellyRoster.uniqueName(t, taken: home.map(JellyRoster.nameOf))          // a typed name equal to one at home becomes "Rex 2"
    }

    private var cta: some View {
        Group {
            if naming { ctaButton(Text("Bring \(finalName) home"), enabled: true, id: "adopt-bring-home") { bringHome() } }
            else { ctaButton(ctaLabel, enabled: canAdopt, id: "adopt-pick") { withAnimation(.easeOut(duration: 0.2)) { name = ""; naming = true }; nameFocused = true } }
        }
    }

    @ViewBuilder private var ctaLabel: some View {
        if let p = price {
            if mode == .first { Text("Choose \(info.name)") }
            else if p > wallet.count { Text("Need \(p - wallet.count) more JellyCoins") }
            else { HStack(spacing: 8) { Text("Adopt for"); JellyCoinIcon(size: 28); Text(p.coinText) } }
        } else { Text("Your home is full: \(JellyRoster.maxCount) Jelbies") }
    }

    /// The big dark-brown pill with a darker bottom lip.
    private func ctaButton<T: View>(_ title: T, enabled: Bool, id: String, _ action: @escaping () -> Void) -> some View {
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
            guard !naming, !coverUp, abs(v.translation.width) > abs(v.translation.height) else { return }
            step(v.translation.width < 0 ? 1 : -1)
        }
    }

    private func step(_ d: Int) {
        guard !naming else { return }
        let n = order.count
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
            ready = false; stageModel = nil; pageGen += 1
            Self.previewOffer(mode: mode, character: order[next])
            page = next
            camera.setSpecies(order[next])
            slideX = reduce ? 0 : CGFloat(dir) * 160
            withAnimation(reduce ? .easeOut(duration: 0.25) : .spring(response: 0.42, dampingFraction: 0.8)) { slideX = 0; slideO = 1 }
            paging = false
        }
    }

    // MARK: the Jelbie's moves

    private func stageReady(_ m: MelonModel, character: Int, gen: Int) {
        guard gen == pageGen, character == pick else { return }          // a stale stage (an old page) must never mark the new page ready
        stageModel = m
        if HUDLayout.isPad {          // iPad: show him only once the close-up camera has settled (else a slow first frame shows him as a speck in the wide room view)
            Task { @MainActor in
                for _ in 0..<80 where m.care.focus.blend < 0.97 { try? await Task.sleep(nanoseconds: 100_000_000) }
                if stageModel === m, gen == pageGen { ready = true; landed(m) }
            }
            return
        }
        ready = true
        landed(m)
    }

    private func landed(_ m: MelonModel) {
        Task { @MainActor in           // landing: a happy hop (or the flutter hop for wings)
            try? await Task.sleep(nanoseconds: 450_000_000)
            perform(pick == 3 || pick == JellyRoster.pearlID ? .idle(.flapHop) : .hop)
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
        withAnimation(.easeIn(duration: 0.2)) { celebrating = true }
        let c = pick, n = name
        let v = variant          // the colour he was shown is the colour he keeps (nil = the classic one): StartFlow.bringHome adopts it under his new instance id
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_800_000_000)
            done(c, n, v)
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

/// A soft, pulsing jelly silhouette in the page's colour with a small spinner: stands on the pedestal while the 3D Jelbie builds.
private struct StagePlaceholder: View {
    let color: Color
    let calm: Bool
    @State private var pulse = false
    var body: some View {
        ZStack {
            Ellipse().fill(Color.black.opacity(0.08)).frame(width: 110, height: 16).offset(y: 52)
            RoundedRectangle(cornerRadius: 54, style: .continuous).fill(color.opacity(pulse ? 0.5 : 0.32))
                .overlay(RoundedRectangle(cornerRadius: 54, style: .continuous).strokeBorder(Color.white.opacity(0.55), lineWidth: 2))
                .frame(width: 104, height: 100).scaleEffect(pulse ? 1.04 : 0.98, anchor: .bottom).offset(y: -2)
            ProgressView().tint(SK.ink.opacity(0.55)).offset(y: -4)
        }
        .onAppear { if !calm { withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) { pulse = true } } }
    }
}

/// Four jelly dots that bounce in a wave (the Jelly Spring loading cover).
private struct SpringLoaderDots: View {
    let colors: [Color]
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30)) { tl in
            let t = tl.date.timeIntervalSinceReferenceDate
            HStack(spacing: 12) {
                ForEach(0..<min(4, colors.count), id: \.self) { i in
                    let w = abs(sin(t * 3.2 - Double(i) * 0.7))
                    Circle().fill(colors[i]).frame(width: 22, height: 22)
                        .overlay(Circle().strokeBorder(Color.white.opacity(0.9), lineWidth: 2))
                        .scaleEffect(x: 1 + 0.12 * (1 - w), y: 1 - 0.12 * (1 - w), anchor: .bottom)
                        .offset(y: -CGFloat(w) * 14)
                }
            }
        }
        .accessibilityHidden(true)
    }
}
