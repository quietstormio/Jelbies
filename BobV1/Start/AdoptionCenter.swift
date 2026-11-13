//
//  AdoptionCenter.swift
//  The species picker: a full-screen, swipeable page per species (Blueberry, Lemon Drop, Taro, Matcha) with the real 3D Jelbie on a round
//  pedestal, a card with About / Traits / Moves, and the big button. Used for the first Jelbie of a new game (free) and for adopting more later
//  (Drops via AdoptionPrice; any species, duplicates included, until the room holds 3). Then the naming step and the welcome home.
//  The layout follows the design boards (440 x 956 pt): everything is placed in that space and scaled to the screen. Landscape: the stage on the
//  left, the header + card + button on the right (the same blocks, scaled).
//  Content: SpeciesInfo.swift. Backdrop / pedestal: PickerBackdrop.swift. Camera orbit: PickerCamera.swift.
//  Species page -> "Meet the three" -> PICK page (three Jelbies of the species side by side, each with its own personality, stats, favourite snack and a slight colour
//  shade: JellyTraits.swift) -> naming -> bring home. The same flow serves the free first gift and the Jelly Spring.
//  Simulator-only capture flags: -PickerPage 0...6 (picker order; 4...6 = Teddy, Pearl, Panda with -PickerMode more), -PickerTab 0...2, -PickerMode more,
//  -PickerStep species|pick|name, -PickerCandidate 0...2, -PickerEmote <n> (the species' n-th emote, every 4 s, instead of the random loop; species/naming steps).
//

import SwiftUI
import UIKit

enum PickerTab: Int, CaseIterable {
    case about, traits, moves
    var title: String { ["About", "Traits", "Moves"][rawValue] }
}

/// What the player chose: StartFlow.bringHome gives him his instance id.
struct AdoptionResult {
    let species: Int
    let name: String
    /// The colour shade he was shown (nil = the classic colour).
    let variant: JellyVariant?
    /// His personality, jars and favourite snack.
    let traits: JellyTraits?
}

extension JellyPersonality {
    /// The gentle in-place move or face the pick page shows while the player looks.
    var emote: StageMove {
        switch self {
        case .bouncy: return .idle(.bounce)
        case .cuddly: return .idle(.sway)
        case .curious: return .idle(.look)
        case .sleepy: return .idle(.stretch)
        case .giggly, .brave: return .face(.excited)
        case .gentle: return .face(.hopeful)
        case .cheeky: return .hop          // (front-facing: the tail idle turns the body away from the camera)
        }
    }
}

struct AdoptionCenter: View {
    let mode: StartFlow.AdoptMode
    var done: (AdoptionResult) -> Void
    var cancel: () -> Void

    enum Step { case species, pick, naming }
    @State private var step: Step
    private var naming: Bool { step == .naming }
    /// The three Jelbies of the shown species (pure function of species, `dayKey`, mode and how many are home): made when the pick page opens.
    @State private var candidates: [JellyCandidate]
    /// The picked candidate (left to right 0...2); the pick page opens on the middle one.
    @State private var picked: Int?
    /// Captured when the screen opens, so midnight cannot reshuffle the three.
    private let dayKey: Int
    /// A pick (or nothing yet) has been tapped: the chips stop breathing.
    @State private var tapped = false
    @State private var breathe = false
    /// Bumped once the camera preset is set, so the projected tap targets are read again.
    @State private var camEpoch = 0
    /// The three standing spots, cached when the pick step opens so the overlay and the stage agree.
    @State private var rowSpots: [SIMD2<Float>] = GameCamera.pickRowSpots(count: JellyRoster.previewSlots)
    @State private var page: Int
    @State private var tab: PickerTab = .about
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

    init(mode: StartFlow.AdoptMode, done: @escaping (AdoptionResult) -> Void, cancel: @escaping () -> Void) {
        self.mode = mode; self.done = done; self.cancel = cancel
        let day = JellyVariantBook.dayKey()
        dayKey = day
        let h = mode == .first ? [] : JellyRoster.savedIDs()
        _home = State(initialValue: h)
        _coverUp = State(initialValue: mode == .more)
        let homeSpecies = h.map(JellyRoster.species)          // `h` holds INSTANCE ids; the pages are species
        var start = mode == .first ? 0 : (SpeciesInfo.pages(includingSpecial: mode == .more).firstIndex { !homeSpecies.contains($0) } ?? 0)
        var t = PickerTab.about
        #if targetEnvironment(simulator)
        let d = UserDefaults.standard
        if d.object(forKey: "PickerPage") != nil { start = min(max(d.integer(forKey: "PickerPage"), 0), SpeciesInfo.pages(includingSpecial: mode == .more).count - 1) }
        if d.object(forKey: "PickerTab") != nil { t = PickerTab(rawValue: min(max(d.integer(forKey: "PickerTab"), 0), 2)) ?? .about }
        #endif
        var step0 = Step.species
        var pick0: Int?
        #if targetEnvironment(simulator)
        if let s = d.string(forKey: "PickerStep") { step0 = s == "pick" ? .pick : s == "name" ? .naming : .species }
        if d.object(forKey: "PickerCandidate") != nil { pick0 = min(max(d.integer(forKey: "PickerCandidate"), 0), 2) }
        #endif
        _page = State(initialValue: start); _tab = State(initialValue: t)
        let species = SpeciesInfo.pages(includingSpecial: mode == .more)[start]
        let cands = step0 == .species ? [] : Self.makeCandidates(mode: mode, species: species, dayKey: day, home: h)
        _step = State(initialValue: step0)
        _candidates = State(initialValue: cands)
        _picked = State(initialValue: step0 == .species ? nil : (pick0 ?? 1))
        switch step0 {
        case .species: Self.setSinglePreview(species: species, variant: nil)
        case .pick: Self.setRowPreviews(cands)
        case .naming: Self.setSinglePreview(species: species, variant: cands[pick0 ?? 1].variant)
        }
    }

    /// The three Jelbies of `species` for this screen: classic colours for the free first gift and the special species.
    static func makeCandidates(mode: StartFlow.AdoptMode, species: Int, dayKey: Int, home: [Int]) -> [JellyCandidate] {
        let owned = home.filter { JellyRoster.species($0) == species }.count
        return JellyCandidates.make(species: species, dayKey: dayKey, classic: mode == .first || SpeciesInfo.of(species).isSpecial, owned: owned)
    }
    /// The scratch ids the stage draws are recoloured before the stage body is built (read when its actors are made): a preview never recolours an owned Jelbie.
    static func setRowPreviews(_ c: [JellyCandidate]) {
        JellyVariants.clearPreviews()
        for x in c { JellyVariants.setPreview(x.previewID, x.variant) }
    }
    static func setSinglePreview(species: Int, variant: JellyVariant?) {
        JellyVariants.clearPreviews()
        JellyVariants.setPreview(JellyRoster.previewID(species), variant)
    }

    private var reduce: Bool { reduceMotionEnv || A11ySettings.shared.reduceMotion }
    /// The species pages of this screen: the four starters, plus Teddy, Pearl and Panda when adopting more (not the free first gift).
    private var order: [Int] { SpeciesInfo.pages(includingSpecial: mode == .more) }
    private var info: SpeciesInfo { SpeciesInfo.of(order[page]) }
    private var look: SpeciesLook { info.look }
    private var pick: Int { info.character }
    /// The picked candidate of the pick / naming step.
    private var pickedCand: JellyCandidate? { picked.flatMap { candidates.indices.contains($0) ? candidates[$0] : nil } }
    /// What this candidate costs (nil = the room is full): the rare colour (the Spring's rare mutation on a lucky day) is the only one that costs more.
    private func price(for c: JellyCandidate) -> Int? { mode == .first ? 0 : AdoptionPrice.next(home: home.count, rare: c.variant?.rare == true, special: info.isSpecial) }
    private var price: Int? { pickedCand.flatMap { price(for: $0) } }
    /// Affordable and room for one more (the price is nil when the room is full). Owning the species already is fine: duplicates are allowed.
    private func canAdopt(_ c: JellyCandidate) -> Bool { price(for: c).map { $0 <= wallet.count } ?? false }
    private var canAdopt: Bool { pickedCand.map { canAdopt($0) } ?? false }
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
        .onAppear {
            camera.reduceMotion = reduce
            if step == .pick { rowSpots = GameCamera.pickRowSpots(count: JellyRoster.previewSlots); camera.setRow(species: pick) } else if step == .naming { camera.setNaming() } else { camera.setSpecies(pick); camera.engage() }
            camEpoch += 1
            if !reduce { withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true)) { breathe = true } }
        }
        .onDisappear {
            camera.release(); emoteTask?.cancel(); JellyVariants.clearPreviews()
            for s in 0..<JellyRoster.knownCount { for k in 0..<JellyRoster.previewSlots { StartFlow.resetCharacterState(JellyRoster.previewID(species: s, slot: k)) } }          // scratch preview ids never keep anything
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
                Text("THE JELLY SPRING").font(SK.font(13, .heavy)).tracking(2.2).foregroundStyle(look.onPage.opacity(0.78))
                Text("Jelly Spring").font(SK.font(56, .black)).foregroundStyle(look.onPage).lineLimit(1).minimumScaleFactor(0.5)
                if reduce { ProgressView().tint(look.onPage.opacity(0.6)).controlSize(.large).frame(height: 40) }
                else { SpringLoaderDots(colors: order.map { SpeciesInfo.of($0).look.dot }).frame(height: 40) }
                Text("Every adoption helps the Spring care for the Jelbies still waiting.").font(SK.font(13, .semibold)).foregroundStyle(look.onPage.opacity(0.72))
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
        let cardH: CGFloat = compact ? Self.nameCardCompactH : naming ? Self.nameCardH : 252          // the naming card is snug: prompt, field, idea chips
        let cardY: CGFloat = compact ? 108 + (showStage ? 470 * su : 0) : naming && !padNaming ? 849 - Self.nameCardH : 597          // (phone: its bottom stays where the tall card's was, right over the button)
        let ctaY: CGFloat = compact ? cardY + cardH + 6 : padNaming ? cardY + cardH + 16 : 862
        let canvasH: CGFloat = compact ? h : 956
        return ZStack(alignment: .topLeading) {
            stageBlock(u).scaleEffect(stageS, anchor: .top).offset(y: compact ? 100 : 130).opacity(showStage ? 1 : 0).allowsHitTesting(showStage)
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

    /// The naming card's design height (prompt, field, the "Ideas:" row) and its keyboard-up compact height.
    private static let nameCardH: CGFloat = 220, nameCardCompactH: CGFloat = 192

    private func landscapeLayout(_ size: CGSize) -> some View {
        let half = size.width / 2
        let cap = Self.padCap(size)          // iPad-sized windows only; iPhone unchanged
        let us = min(half / 440, (size.height - 8) / 470, cap)
        let ur = min((half - 20) / 440, (size.height - 12) / (naming ? (mode == .more ? 172 : 150) + Self.nameCardH + 80 : 500), cap)
        let compact = naming && kbUp
        let compactH = Self.nameCardCompactH + 6 + 68
        let uc = min((half - 20) / 440, (size.height - 8) / compactH, cap)  // name card + button only, above the keyboard
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
                        sheetCard(uc, height: Self.nameCardCompactH).frame(width: 408, height: Self.nameCardCompactH)
                        cta.frame(width: 400, height: 68)
                    }
                    .frame(width: 440, height: compactH, alignment: .top)
                    .scaleEffect(uc, anchor: .top)
                    .frame(width: 440 * uc, height: compactH * uc, alignment: .top)
                } else {
                    let headH: CGFloat = mode == .more ? 172 : 150, cardH: CGFloat = naming ? Self.nameCardH : 252, ctaH: CGFloat = 68, gap: CGFloat = 6
                    let colH: CGFloat = naming ? headH + cardH + ctaH + gap * 2 : 500          // naming: the sum of the stacked parts (a snug card, the column centred), so it cannot clip
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
                        roundButton(backSymbol, label: backLabel, id: "adopt-back") { goBack() }
                        Spacer(minLength: 8)
                        if mode == .more { dropsPill }
                    }
                    if !naming { flowHeader }
                    stageBlock(1, chips: false).frame(width: 440, height: 470, alignment: .topLeading)
                        .scaleEffect(ss, anchor: .topLeading).frame(width: 440 * ss, height: 470 * ss, alignment: .topLeading)
                        .frame(height: naming && kbUp ? 0 : 470 * ss).clipped().opacity(naming && kbUp ? 0 : 1)
                    if step == .pick { candidateRow }
                    if step == .species {
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
            Text(mode == .first ? "THE SPRING'S WELCOME GIFT" : "THE JELLY SPRING").font(SK.font(13, .heavy)).tracking(2.6).foregroundStyle(look.onPage.opacity(0.78))
            Text(info.name).font(SK.font(52, .black)).foregroundStyle(look.onPage).minimumScaleFactor(0.5)
            Text(epithetLine).font(SK.font(17.5, .semibold)).foregroundStyle(look.onPage.opacity(0.85))
            if mode == .more { roomLine }
            HStack(spacing: 4) {
                ForEach(0..<order.count, id: \.self) { i in
                    Circle().fill(SpeciesInfo.of(order[i]).look.dot).frame(width: i == page ? 15 : 11, height: i == page ? 15 : 11)
                        .padding(3).background(Circle().fill(Color.white))
                }
            }
            .opacity(step == .species ? 1 : 0)
            .accessibilityHidden(true)
        }
        .multilineTextAlignment(.center).frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(headerLabel)
        .accessibilityHint(step == .species ? "Swipe up or down to change Jelbie" : "")
        .accessibilityAddTraits(.isHeader)
        .accessibilityAdjustableAction { dir in
            guard step == .species else { return }
            switch dir { case .increment: step(1); case .decrement: step(-1); @unknown default: break }
        }
    }

    private var flowCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            if naming {
                Text(namingPrompt).font(SK.font(19, .black)).foregroundStyle(SK.ink).multilineTextAlignment(.center).frame(maxWidth: .infinity)
                nameField(1)
                ideasRow(1)
            } else if step == .pick {
                flowPick
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
            else { flowCtaButton(ctaLabel, enabled: ctaEnabled, id: ctaID) { ctaAction() } }
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
            roundButton(backSymbol, label: backLabel, id: "adopt-back", u: u) { goBack() }
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
            Text(mode == .first ? "THE SPRING'S WELCOME GIFT" : "THE JELLY SPRING").font(SK.font(13, .heavy)).tracking(2.2).foregroundStyle(look.onPage.opacity(0.78))
                .frame(height: 20).position(x: 220, y: 18)
            // Only the name, epithet and Rare tag slide and fade with a swipe; the overline, dots and room line stay put.
            ZStack(alignment: .topLeading) {
                Text(info.name).font(SK.font(52, .black)).foregroundStyle(look.onPage).lineLimit(1).minimumScaleFactor(0.6).frame(width: 330, height: 60).position(x: 220, y: 61)
                Text(epithetLine).font(SK.font(17.5, .semibold)).foregroundStyle(look.onPage.opacity(0.85)).frame(height: 24).position(x: 220, y: 104)
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
            .opacity(step == .species ? 1 : 0).allowsHitTesting(step == .species)
            .accessibilityHidden(true)
        }
        .frame(width: 440, height: 150, alignment: .topLeading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(headerLabel)
        .accessibilityHint(step == .species ? "Swipe up or down to change Jelbie" : "")
        .accessibilityAddTraits(.isHeader)
        .accessibilityAdjustableAction { dir in
            guard step == .species else { return }
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
        .padding(.horizontal, 12).padding(.vertical, 4)
        .background(Capsule().fill(SK.cream.opacity(0.85)))          // reads cleanly when a tall head feature (daisy, ears) rises behind it
        .accessibilityHidden(true)
    }

    /// The line under the big name: the species' epithet, or the pick page's question.
    private var epithetLine: String { step == .pick ? "Which one will it be?" : info.epithet }
    private var headerLabel: String {
        let lead = mode == .more ? "The Jelly Spring. \(roomText). Every adoption helps the Spring care for the Jelbies still waiting. " : ""
        switch step {
        case .species: return "\(lead)\(info.name), \(info.epithet). Jelbie \(page + 1) of \(order.count)"
        case .pick: return "\(lead)Pick one of three \(info.name)"
        case .naming: return "Naming your \(info.name)"
        }
    }
    private var namingPrompt: String { "What will you call your \(pickedCand.map { $0.traits.personality.title + " " } ?? "")\(info.name)?" }

    // MARK: stage (design box 440 x 470, origin at canvas y 130)

    /// The soft placeholder shows while the page's Jelbie(s) build (never under the loading cover).
    private var showPlaceholder: Bool { !ready && !coverUp }

    /// The scratch ids the stage draws: the single page and the naming step stand ONE Jelbie; the pick page stands the three side by side (stage slot 0 in the middle).
    private var stageRoster: [Int] {
        step == .pick ? (0..<JellyRoster.previewSlots).map { JellyRoster.previewID(species: pick, slot: $0) } : [JellyRoster.previewID(pick)]
    }
    private var ownedOfPick: Int { home.filter { JellyRoster.species($0) == pick }.count }
    private var stageID: String {
        switch step {
        case .species: return "single-\(pick)"
        case .pick: return "row-\(pick)-\(ownedOfPick)"
        case .naming: return "name-\(pick)-\(picked ?? 0)"
        }
    }

    /// Where the three bodies appear on the 420 x 420 stage view (by stage slot), from the same row and camera the stage draws.
    private var rowProjection: [GameCamera.RowProjection] {
        _ = camEpoch
        guard step == .pick else { return [] }
        return GameCamera.projectRow(spots: rowSpots)
    }
    /// Stage view (0...1) -> stage block design units: the view is 420 x 420 at (10, 46).
    private func dx(_ x: Float) -> CGFloat { 10 + 420 * CGFloat(x) }
    private func dy(_ y: Float) -> CGFloat { 46 + 420 * CGFloat(y) }

    /// The pedestal (one wide one under the row), the Jelbie(s) standing on it (transparent 3D, no room), the arrows and the "Drag to spin" pill, or on the pick page the
    /// tap bands with their name chips.
    private func stageBlock(_ u: CGFloat, chips: Bool = true) -> some View {
        let row = step == .pick
        let proj = rowProjection
        return ZStack(alignment: .topLeading) {
            if row {
                rowBackdrop(proj)
            } else {
                PickerPedestal(look: look).offset(x: 66, y: 482 - 130 - PickerPedestal.topH / 2).offset(x: slideX * 0.15).opacity(slideO)
            }
            Group {
                if showPlaceholder {
                    if row {
                        ForEach(0..<3, id: \.self) { slot in
                            let p = proj[slot]
                            StagePlaceholder(color: look.dot, calm: reduce)
                                .frame(width: 120, height: 128).scaleEffect(max(0.5, CGFloat(p.bodyW) * 420 / 140), anchor: .bottom)
                                .offset(x: dx(p.foot.x) - 60, y: dy(p.foot.y) - 128 + 2)
                        }
                        .transition(.opacity)
                        .allowsHitTesting(false).accessibilityHidden(true)
                    } else {
                        StagePlaceholder(color: look.dot, calm: reduce)
                            .frame(width: 120, height: 128).offset(x: 160, y: 350 - 128)       // stands on the pedestal's top (centre at local y 352)
                            .offset(x: slideX * 0.15).opacity(slideO)
                            .transition(.opacity)
                            .allowsHitTesting(false).accessibilityHidden(true)
                    }
                }
            }
            .animation(.easeInOut(duration: 0.3), value: showPlaceholder)
            ShowcaseStage(roster: stageRoster, focusFirst: true, fullScreen: false, cutout: true, onReady: { [gen = pageGen] m in stageReady(m, gen: gen) }, silent: row)
                .id(stageID).frame(width: 420, height: 420)
                .offset(x: 10, y: 46)
                .opacity(ready ? slideO : 0).offset(x: slideX)
                .animation(.easeInOut(duration: 0.3), value: ready)
                .allowsHitTesting(false)
            if step == .species {
                Rectangle().fill(Color.clear).contentShape(Rectangle()).frame(width: 330, height: 260)
                    .gesture(orbit.simultaneously(with: pinch)).offset(x: 55, y: 215)
                roundButton("chevron.left", label: "Previous Jelbie", u: u) { step(-1) }.offset(x: 14, y: 399 - 130 - 22)
                roundButton("chevron.right", label: "Next Jelbie", u: u) { step(1) }.offset(x: 382, y: 399 - 130 - 22)
                dragPill.offset(x: 220 - 60, y: 571 - 130 - 15)
            } else if row {
                rowBands(proj, u: u, chips: chips)
                hintPill.offset(x: 220 - 105, y: 571 - 130 - 15)
            }
        }
        .frame(width: 440, height: 470, alignment: .topLeading)
    }

    /// One wide pedestal under the row, and (once a pick is made) the spotlight and the ring around the picked Jelbie's feet.
    @ViewBuilder private func rowBackdrop(_ proj: [GameCamera.RowProjection]) -> some View {
        let n = Float(max(proj.count, 1))
        let xc = dx(proj.map(\.foot.x).reduce(0, +) / n)
        let yf = dy(proj.map(\.foot.y).reduce(0, +) / n) + 2
        let ped = PickerPedestal(look: look, width: 392)
        ped.offset(x: xc - 196, y: yf - ped.topH / 2).offset(x: slideX * 0.15).opacity(slideO)
        if let i = picked {
            let p = proj[PickerRow.slot(ofCandidate: i)]
            let bw = CGFloat(p.bodyW) * 420
            Circle().fill(RadialGradient(colors: [Color.white.opacity(0.35), Color.white.opacity(0)], center: .center, startRadius: 0, endRadius: bw * 0.8))
                .frame(width: bw * 1.6, height: bw * 1.6)
                .offset(x: dx(p.mid.x) - bw * 0.8, y: dy(p.mid.y) - bw * 0.8)
                .allowsHitTesting(false).accessibilityHidden(true)
            Ellipse().strokeBorder(Color.white, lineWidth: 3)
                .shadow(color: look.glow.opacity(0.5), radius: 6)
                .frame(width: bw * 1.05, height: bw * 1.05 * 0.28)
                .offset(x: dx(p.foot.x) - bw * 1.05 / 2, y: dy(p.foot.y) - bw * 1.05 * 0.14)
                .allowsHitTesting(false).accessibilityHidden(true)
        }
    }

    /// The three tap targets (vertical bands from the middle between neighbours, from a little above the body down to the chip) with the personality chips under the feet.
    private func rowBands(_ proj: [GameCamera.RowProjection], u: CGFloat, chips: Bool) -> some View {
        let xs = (0..<3).map { dx(proj[PickerRow.slot(ofCandidate: $0)].foot.x) }
        return ZStack(alignment: .topLeading) {
            ForEach(0..<min(3, candidates.count), id: \.self) { i in
                let p = proj[PickerRow.slot(ofCandidate: i)]
                let x0: CGFloat = i == 0 ? 10 : (xs[i - 1] + xs[i]) / 2
                let x1: CGFloat = i == 2 ? 430 : (xs[i] + xs[i + 1]) / 2
                let y0 = dy(p.top.y - 0.03)
                let chipTop = dy(p.foot.y) + 14
                let chipH = min(hitMin(u), max(26, 420 - chipTop))          // (the hint pill starts at 426: the chips never reach it)
                let gap = min(i > 0 ? xs[i] - xs[i - 1] : .infinity, i < 2 ? xs[i + 1] - xs[i] : .infinity)
                let chipW = min(90, gap * 0.9)
                let sel = picked == i
                let pers = candidates[i].traits.personality
                Button { pickCandidate(i) } label: {
                    ZStack(alignment: .topLeading) {
                        Color.clear
                        if chips {
                            HStack(spacing: 5) {
                                Image(systemName: pers.symbol).font(.system(size: 14, weight: .black))
                                Text(pers.title).font(SK.font(14, .black)).lineLimit(1).minimumScaleFactor(0.7)
                            }
                            .foregroundStyle(sel ? SK.cream : SK.ink)
                            .padding(.horizontal, 6).frame(width: chipW, height: chipH)
                            .background(Capsule().fill(sel ? SK.ink : Color.white.opacity(0.7)))
                            .scaleEffect(sel ? 1 : (tapped || reduce ? 1 : (breathe ? 1.05 : 1)))
                            .animation(tapped || reduce ? nil : .easeInOut(duration: 1.6).repeatForever(autoreverses: true).delay(Double(i) * 0.25), value: breathe)
                            .offset(x: xs[i] - x0 - chipW / 2, y: chipTop - y0)
                        }
                    }
                    .frame(width: x1 - x0, height: chipTop + chipH - y0, alignment: .topLeading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .offset(x: x0, y: y0)
                .accessibilityLabel("\(pers.title), option \(i + 1) of 3").accessibilityHint("Opens their details")
                .accessibilityAddTraits(sel ? .isSelected : [])
                .accessibilityHidden(!chips)
                .accessibilityIdentifier("adopt-cand-\(i)")
            }
        }
    }

    private var hintPill: some View {
        Text("Tap one to meet them").font(SK.font(15, .heavy)).foregroundStyle(SK.ink).lineLimit(1).frame(width: 210, height: 30)
            .background(Capsule().fill(Color.white.opacity(0.58)))
            .overlay(Capsule().strokeBorder(Color.white.opacity(0.85), lineWidth: 1.5))
            .accessibilityHidden(true)
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
            if naming { nameCard(u) } else if step == .pick { pickCard(u) } else {
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
            // the text takes the first size that fits its 64-high box (16 pt, then 15, then 14 pt), so even a 3-line About never reaches the tiles below it
            ViewThatFits(in: .vertical) {
                aboutText(16, spacing: 4)
                aboutText(15, spacing: 3)
                aboutText(14, spacing: 2)
            }
            .frame(width: 345, height: 64, alignment: .topLeading).offset(x: 22, y: 76)
            tile("Best at", dot: SpeciesInfo.jarNames.firstIndex(of: info.bestAt).map { Self.jarColor($0) }, value: info.bestAt).offset(x: 14, y: 156)
            tile("Signature", dot: nil, value: info.signature).offset(x: 145, y: 156)
            tile("Loves", dot: nil, value: info.loves).offset(x: 277, y: 156)
        }
    }

    private func aboutText(_ size: CGFloat, spacing: CGFloat) -> some View {
        Text(info.about).font(SK.font(size, .medium)).foregroundStyle(SK.ink).lineSpacing(spacing).fixedSize(horizontal: false, vertical: true)
            .frame(width: 345, alignment: .topLeading)
    }

    private func tile(_ title: String, dot: Color?, value: String) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(title).font(SK.font(12.5, .bold)).foregroundStyle(Color(hex: 0x8D7C6E))
            HStack(spacing: 6) {
                if let dot { Circle().fill(dot).frame(width: 13, height: 13) }
                Text(value).font(SK.font(19, .black)).foregroundStyle(SK.ink).lineLimit(1).minimumScaleFactor(0.7)
            }
        }
        .padding(.leading, 13).padding(.bottom, 14)
        .frame(width: 117, height: 84, alignment: .leading).offset(y: 0)
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

    // MARK: the pick page's card (design box 408 x 252)

    /// The food's name, symbol and tint (a store food id).
    private func snackInfo(_ id: String) -> (name: String, symbol: String, tint: Color) {
        guard let c = Consumables.with(id: id) else { return (id.capitalized, "fork.knife", SK.honeyDeep) }
        func srgb(_ v: Float) -> Double { Double(v <= 0.0031308 ? 12.92 * v : 1.055 * powf(v, 1 / 2.4) - 0.055) }
        let p = c.palette.primary
        return (c.name, c.symbol, Color(red: srgb(p.x), green: srgb(p.y), blue: srgb(p.z)))
    }
    /// "Classic", "Soft", "Deep" or the rare colour; its label and swatch.
    private func shadeInfo(_ c: JellyCandidate) -> (label: String, value: String, dot: Color) {
        guard let v = c.variant else { return ("Shade", "Classic", look.dot) }
        let s = v.swatch
        let dot = Color(red: Double(s.x), green: Double(s.y), blue: Double(s.z))
        return (v.title == "Soft" || v.title == "Deep" ? "Shade" : "Rare colour", v.title, dot)
    }
    private func strongestJar(_ t: JellyTraits) -> String { SpeciesInfo.jarNames[t.jars.enumerated().max { $0.element < $1.element }?.offset ?? 0] }

    private func rareTag(id: String = "adopt-rare-tag") -> some View {
        Text("Rare").font(SK.font(12.5, .black)).foregroundStyle(SK.ink)
            .padding(.horizontal, 10).frame(height: 22)
            .background(Capsule().fill(Color(hex: 0xFFD65C)))
            .overlay(Capsule().strokeBorder(Color.white.opacity(0.85), lineWidth: 1.5))
            .accessibilityIdentifier(id)
    }

    private func miniTile(_ title: String, symbol: String?, tint: Color, dot: Color?, value: String) -> some View {
        HStack(spacing: 8) {
            if let symbol { Image(systemName: symbol).font(.system(size: 17, weight: .bold)).foregroundStyle(tint).frame(width: 22) }
            if let dot { Circle().fill(dot).frame(width: 18, height: 18).overlay(Circle().strokeBorder(Color.white.opacity(0.9), lineWidth: 1.5)) }
            VStack(alignment: .leading, spacing: 0) {
                Text(title).font(SK.font(11.5, .bold)).foregroundStyle(Color(hex: 0x8D7C6E)).lineLimit(1)
                Text(value).font(SK.font(15.5, .black)).foregroundStyle(SK.ink).lineLimit(1).minimumScaleFactor(0.7)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10).frame(width: 190, height: 40, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 13, style: .continuous).fill(SK.ink.opacity(0.055)))
        .accessibilityElement(children: .combine)
    }

    private func pickCard(_ u: CGFloat) -> some View {
        Group {
            if let c = pickedCand {
                let t = c.traits, p = t.personality, snack = snackInfo(t.snack), shade = shadeInfo(c)
                ZStack(alignment: .topLeading) {
                    Circle().fill(look.rowHi).frame(width: 40, height: 40)
                        .overlay(Image(systemName: p.symbol).font(.system(size: 18, weight: .bold)).foregroundStyle(SK.ink)).offset(x: 16, y: 16)
                    Text(p.title).font(SK.font(26, .black)).foregroundStyle(SK.ink).lineLimit(1).frame(height: 40, alignment: .leading).offset(x: 66, y: 16)
                    if c.variant?.rare == true { rareTag().offset(x: 408 - 16 - 56, y: 25) }
                    Text(p.blurb).font(SK.font(15, .medium)).foregroundStyle(SK.ink.opacity(0.75)).lineLimit(1).offset(x: 18, y: 60)
                    miniTile("Favourite snack", symbol: snack.symbol, tint: snack.tint, dot: nil, value: snack.name).offset(x: 14, y: 88)
                    miniTile(shade.label, symbol: nil, tint: SK.ink, dot: shade.dot, value: shade.value).offset(x: 204, y: 88)
                    ForEach(0..<5, id: \.self) { i in
                        PickerJar(color: Self.jarColor(i), value: t.jars[i], animate: !reduce).offset(x: 52 + CGFloat(i) * 76 - 23, y: 134)
                        Text(SpeciesInfo.jarNames[i]).font(SK.font(13.5, .bold)).foregroundStyle(SK.ink).frame(width: 76).offset(x: 52 + CGFloat(i) * 76 - 38, y: 228)
                            .accessibilityHidden(true)
                    }
                }
                .frame(width: 408, height: 252, alignment: .topLeading)
                .id("pick-\(picked ?? -1)").transition(.opacity)
                .accessibilityElement(children: .contain)
                .accessibilityLabel("\(p.title). \(p.blurb) Favourite snack \(snack.name). Strongest in \(strongestJar(t)).")
            } else {
                Text("Tap a Jelbie to meet them").font(SK.font(19, .black)).foregroundStyle(SK.ink).frame(width: 408, height: 252)
            }
        }
        .animation(.easeOut(duration: 0.18), value: picked)
    }

    /// The pick page in the large-text column: the card's content stacked.
    private var flowPick: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let c = pickedCand {
                let t = c.traits, p = t.personality, snack = snackInfo(t.snack), shade = shadeInfo(c)
                HStack(spacing: 10) {
                    Circle().fill(look.rowHi).frame(width: 40, height: 40).overlay(Image(systemName: p.symbol).font(.system(size: 18, weight: .bold)).foregroundStyle(SK.ink))
                    Text(p.title).font(SK.font(26, .black)).foregroundStyle(SK.ink)
                    Spacer(minLength: 4)
                    if c.variant?.rare == true { rareTag() }
                }
                Text(p.blurb).font(SK.font(16, .medium)).foregroundStyle(SK.ink.opacity(0.75)).fixedSize(horizontal: false, vertical: true)
                flowTile("Favourite snack", dot: nil, value: snack.name)
                flowTile(shade.label, dot: shade.dot, value: shade.value)
                HStack(alignment: .top, spacing: 2) {
                    ForEach(0..<5, id: \.self) { i in
                        VStack(spacing: 6) {
                            PickerJar(color: Self.jarColor(i), value: t.jars[i], animate: !reduce)
                            Text(SpeciesInfo.jarNames[i]).font(SK.font(13.5, .bold)).foregroundStyle(SK.ink).lineLimit(2).minimumScaleFactor(0.6)
                                .multilineTextAlignment(.center).accessibilityHidden(true)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                Text("Strongest in \(strongestJar(t)).").font(SK.font(14, .semibold)).foregroundStyle(SK.ink.opacity(0.62)).frame(maxWidth: .infinity)
            }
        }
    }

    /// Large text: the three choices as real buttons under the stage (the in-stage chips are too small to keep at 44 pt there).
    private var candidateRow: some View {
        let layout = dts.isAccessibilitySize ? AnyLayout(VStackLayout(spacing: 10)) : AnyLayout(HStackLayout(spacing: 10))
        return layout {
            ForEach(0..<candidates.count, id: \.self) { i in
                let p = candidates[i].traits.personality, sel = picked == i
                Button { pickCandidate(i) } label: {
                    HStack(spacing: 6) {
                        Image(systemName: p.symbol)
                        Text(p.title).lineLimit(1).minimumScaleFactor(0.7)
                    }
                    .font(SK.font(17, .black)).foregroundStyle(sel ? SK.cream : SK.ink)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .background(Capsule().fill(sel ? SK.ink : Color.white.opacity(0.7)))
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(p.title), option \(i + 1) of 3").accessibilityHint("Opens their details")
                .accessibilityAddTraits(sel ? .isSelected : []).accessibilityIdentifier("adopt-cand-\(i)")
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
            Text(namingPrompt).font(SK.font(19, .black)).foregroundStyle(SK.ink).multilineTextAlignment(.center).lineLimit(2).minimumScaleFactor(0.85)
            nameField(u)
            ideasRow(u)
        }
        .padding(.horizontal, 20).padding(.top, kbUp ? 22 : 26).frame(width: 408, alignment: .top)
    }

    /// Three name ideas for the chosen Jelbie (the first is the name he gets when the field is left empty); a tap fills the name field.
    private var nameIdeas: [String] { NameIdeas.ideas(species: pick, index: picked ?? 1, taken: home.map(JellyRoster.nameOf)) }

    private func ideasRow(_ u: CGFloat) -> some View {
        let h = min(max(36, hitMin(u)), 52)
        let layout = dts.isAccessibilitySize ? AnyLayout(VStackLayout(spacing: 8)) : AnyLayout(HStackLayout(spacing: 7))
        return layout {
            Text("Ideas:").font(SK.font(14, .bold)).foregroundStyle(SK.ink.opacity(0.62)).fixedSize().accessibilityHidden(true)
            ForEach(Array(nameIdeas.enumerated()), id: \.offset) { k, idea in
                let on = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == idea.lowercased()
                Button { AudioHub.shared.uiTap(); name = idea } label: {
                    Text(idea).font(SK.font(16, .heavy)).foregroundStyle(on ? SK.cream : SK.ink).lineLimit(1).minimumScaleFactor(0.6)
                        .padding(.horizontal, 8).frame(maxWidth: .infinity, minHeight: 34, maxHeight: 34)
                        .background(Capsule().fill(on ? SK.ink : Color.white.opacity(0.78)))
                        .overlay(Capsule().strokeBorder(look.tabLine.opacity(on ? 0 : 0.9), lineWidth: 1.5))
                        .frame(height: h).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Name idea: \(idea)").accessibilityAddTraits(on ? .isSelected : [])
                .accessibilityIdentifier("adopt-idea-\(k)")
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var finalName: String {
        let t = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty { return suggested }
        return JellyRoster.uniqueName(t, taken: home.map(JellyRoster.nameOf))          // a typed name equal to one at home becomes "Rex 2"
    }

    private var ctaID: String { step == .species ? "adopt-meet" : "adopt-pick" }
    /// The species page always opens the pick page (browsing is never blocked); the price is checked per candidate there.
    private var ctaEnabled: Bool { step == .pick ? canAdopt : true }
    private func ctaAction() {
        switch step {
        case .species: toPick()
        case .pick: toNaming()
        case .naming: bringHome()
        }
    }

    private var cta: some View {
        Group {
            if naming { ctaButton(Text("Bring \(finalName) home"), enabled: true, id: "adopt-bring-home") { bringHome() } }
            else { ctaButton(ctaLabel, enabled: ctaEnabled, id: ctaID) { ctaAction() } }
        }
    }

    @ViewBuilder private var ctaLabel: some View {
        switch step {
        case .species: Text("Meet the three")
        case .naming: Text("Bring \(finalName) home")
        case .pick:
            if let c = pickedCand {
                if let p = price(for: c) {
                    if mode == .first { Text("This one!") }
                    else if p > wallet.count { Text("Need \(p - wallet.count) more JellyCoins") }
                    else { HStack(spacing: 8) { Text("This one!"); JellyCoinIcon(size: 28); Text(p.coinText) } }
                } else { Text("Your home is full: \(JellyRoster.maxCount) Jelbies") }
            } else { Text("Pick one of the three") }
        }
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
            guard step == .species, !coverUp, abs(v.translation.width) > abs(v.translation.height) else { return }
            step(v.translation.width < 0 ? 1 : -1)
        }
    }

    private func step(_ d: Int) {
        guard step == .species else { return }
        let n = order.count
        move(to: (page + d + n) % n, dir: d)
    }

    private func jump(to i: Int) {
        guard step == .species, i != page else { return }
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
            Self.setSinglePreview(species: order[next], variant: nil)
            page = next
            camera.setSpecies(order[next])
            slideX = reduce ? 0 : CGFloat(dir) * 160
            withAnimation(reduce ? .easeOut(duration: 0.25) : .spring(response: 0.42, dampingFraction: 0.8)) { slideX = 0; slideO = 1 }
            paging = false
        }
    }

    // MARK: steps (species -> pick -> naming)

    private var backSymbol: String { step != .species || mode == .first ? "chevron.left" : "xmark" }
    private var backLabel: String { step != .species ? "Back" : (mode == .first ? "Back to the menu" : "Close") }
    /// One step back: naming -> pick (the pick is kept) -> species -> the menu / the room.
    private func goBack() {
        switch step {
        case .naming: backToPick()
        case .pick: backToSpecies()
        case .species: cancel()
        }
    }

    /// A step change swaps the stage (the old Jelbie(s) go, the placeholder covers the build); the generation makes a stale stage's ready callback harmless.
    private func resetStage() { ready = false; stageModel = nil; pageGen += 1; emoteTask?.cancel() }

    /// "Meet the three": the day's three Jelbies of this species stand side by side.
    private func toPick() {
        guard step == .species, !paging else { return }
        candidates = Self.makeCandidates(mode: mode, species: pick, dayKey: dayKey, home: home)
        Self.setRowPreviews(candidates)
        picked = 1; tapped = false
        resetStage()
        rowSpots = GameCamera.pickRowSpots(count: JellyRoster.previewSlots); camera.setRow(species: pick); camEpoch += 1
        withAnimation(.easeOut(duration: 0.2)) { step = .pick }
    }

    /// "This one!": the chosen Jelbie alone, big, in its own colour, for the name.
    private func toNaming() {
        guard step == .pick, let c = pickedCand, canAdopt(c) else { return }
        Self.setSinglePreview(species: pick, variant: c.variant)
        resetStage()
        camera.setNaming()
        name = ""
        withAnimation(.easeOut(duration: 0.2)) { step = .naming }
        nameFocused = true
    }

    private func backToPick() {
        guard step == .naming else { return }
        nameFocused = false
        Self.setRowPreviews(candidates)
        resetStage()
        rowSpots = GameCamera.pickRowSpots(count: JellyRoster.previewSlots); camera.setRow(species: pick); camEpoch += 1
        withAnimation(.easeOut(duration: 0.2)) { step = .pick }
    }

    private func backToSpecies() {
        guard step == .pick else { return }
        picked = nil
        Self.setSinglePreview(species: pick, variant: nil)
        resetStage()
        camera.setSpecies(pick); camera.engage()
        withAnimation(.easeOut(duration: 0.2)) { step = .species }
    }

    // MARK: the Jelbie's moves

    private func stageReady(_ m: MelonModel, gen: Int) {
        guard gen == pageGen else { return }          // a stale stage (an old page or step) must never mark the new one ready
        stageModel = m
        m.care.previewFaceCamera()
        if step == .pick { ready = true; landedRow(m); return }          // (the row stage waited for its close-up camera itself: `ShowcaseStage`)
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

    /// The three say hello left to right, then each shows its personality now and then.
    private func landedRow(_ m: MelonModel) {
        Task { @MainActor in
            for i in 0..<3 {
                try? await Task.sleep(nanoseconds: i == 0 ? 450_000_000 : 200_000_000)
                guard step == .pick, stageModel === m, !m.paused else { return }
                let slot = PickerRow.slot(ofCandidate: i)
                if reduce { m.care.brainFor(slot)?.blinkRequested = true } else { m.care.previewHop(slot) }
            }
        }
        startRowEmotes()
    }

    /// While the player reads, the Jelbie does one gentle, in-place move or expression every few seconds that suits its personality (the naming step: the chosen one's).
    private func startEmotes(for character: Int) {
        emoteTask?.cancel()
        emoteTask = Task { @MainActor in
            var i = Int.random(in: 0..<10)
            var fixed = false
            #if targetEnvironment(simulator)
            if UserDefaults.standard.object(forKey: "PickerEmote") != nil { i = UserDefaults.standard.integer(forKey: "PickerEmote"); fixed = true }
            #endif
            while !Task.isCancelled, pick == character, step != .pick {
                try? await Task.sleep(nanoseconds: fixed ? 4_000_000_000 : UInt64(Double.random(in: 4.0...6.5) * 1_000_000_000))
                guard !Task.isCancelled, pick == character, step != .pick, !celebrating else { continue }
                let list: [StageMove] = naming ? [pickedCand?.traits.personality.emote ?? .blink, .blink] : SpeciesInfo.of(character).emotes
                perform(list[i % list.count]); if !fixed { i += 1 }
            }
        }
    }

    /// The pick page: every 3.5-5.5 s one Jelbie shows its personality (round-robin until one is picked, then the picked one; the others blink).
    private func startRowEmotes() {
        emoteTask?.cancel()
        emoteTask = Task { @MainActor in
            var turn = 0
            while !Task.isCancelled, step == .pick {
                try? await Task.sleep(nanoseconds: UInt64(Double.random(in: 3.5...5.5) * 1_000_000_000))
                guard !Task.isCancelled, step == .pick, !celebrating, candidates.count == 3 else { continue }
                let i = tapped ? (picked ?? turn % 3) : turn % 3
                turn += 1
                perform(candidates[i].traits.personality.emote, slot: PickerRow.slot(ofCandidate: i), calm: reduce)
                if tapped { for j in 0..<3 where j != i { perform(.blink, slot: PickerRow.slot(ofCandidate: j), calm: reduce) } }
            }
        }
    }

    /// A tap on one of the three: it hops in place with a chirp (the other two give a small happy face); its details fill the card.
    private func pickCandidate(_ i: Int) {
        guard step == .pick, candidates.indices.contains(i) else { return }
        AudioHub.shared.uiTap()
        tapped = true
        let c = candidates[i]
        withAnimation(reduce ? nil : .spring(response: 0.35, dampingFraction: 0.7)) { picked = i }
        let t = c.traits
        AccessibilityNotification.Announcement("\(t.personality.title). \(t.personality.blurb) Favourite snack \(snackInfo(t.snack).name). Strongest in \(strongestJar(t)).").post()
        guard let m = stageModel, !m.paused else { return }
        let slot = PickerRow.slot(ofCandidate: i)
        if reduce { m.care.brainFor(slot)?.blinkRequested = true }
        else {
            m.care.previewHop(slot)
            AudioHub.shared.chirp(jelly: slot, .happy, src: "pick")
        }
        var k = 0
        for j in 0..<3 where j != i {
            k += 1
            let other = PickerRow.slot(ofCandidate: j), delay = UInt64(k) * 120_000_000
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: delay)
                guard step == .pick, stageModel === m, let b = m.care.brainFor(other) else { return }
                b.face(.happy, hold: 1.2); b.blinkRequested = true
            }
        }
    }

    /// Asks the stage's Jelbie in `slot` for a move (when it is free to take one). `calm`: Reduce Motion, only blinks and faces.
    private func perform(_ move: StageMove, slot: Int = 0, calm: Bool = false) {
        guard let m = stageModel, !m.paused, let b = m.care.brainFor(slot) else { return }
        var move = move
        // pick and naming steps: front-facing moves only (a turning idle would show his back or tail); the species page keeps its own emotes
        if step != .species, case .idle(let k) = move, Self.turningIdles.contains(k) { move = .hop }
        if calm { switch move { case .idle, .hop: move = .blink; default: break } }
        switch move {
        case .blink: b.blinkRequested = true
        case .face(let f): b.face(f, hold: 1.6)
        case .hop: m.care.previewHop(slot); refaceSoon(m)
        case .idle(let k):
            guard b.commandedIdle == nil, b.idleState.kind == nil, case .none = b.script else { return }
            if k == .flapHop, b.feature != .wings || b.wingsFolded { m.care.previewHop(slot); return }
            b.commandedIdle = k
            refaceSoon(m)
        }
    }

    /// Idles that turn the body away from the camera.
    private static let turningIdles: Set<IdleKind> = [.tail, .tailThump, .tailHug, .legSpin, .window, .peek, .hmph]

    /// After a move on the pick/naming steps the Jelbie ends facing the camera again.
    private func refaceSoon(_ m: MelonModel) {
        guard step != .species else { return }
        Task { @MainActor in
            for ms in [1_500_000_000, 2_500_000_000, 3_000_000_000] as [UInt64] {
                try? await Task.sleep(nanoseconds: ms)
                guard stageModel === m, !m.paused else { return }
                m.care.previewFaceCamera()
            }
        }
    }

    // MARK: bring home

    private func bringHome() {
        guard !celebrating, let c = pickedCand, canAdopt(c), let p = price(for: c) else { return }
        name = finalName
        if p > 0, !wallet.spend(p) { return }
        nameFocused = false
        emoteTask?.cancel()
        withAnimation(.easeIn(duration: 0.2)) { celebrating = true }
        // the one he was shown is the one he keeps: his colour shade (nil = the classic one) and his personality go with him; StartFlow.bringHome adopts them under his new instance id
        let result = AdoptionResult(species: pick, name: name, variant: c.variant, traits: c.traits)
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_800_000_000)
            done(result)
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
