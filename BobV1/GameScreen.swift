//
//  GameScreen.swift
//  The game: Bob in the living room, full screen. The HUD is a ZStack overlay on top of the stage:
//  small gear (top-left) opens the studio; `hud` is the slot for the care menu (bottom-right).
//

import SwiftUI

struct GameScreen: View {
    @State private var model = GameScreen.makeGameModel()
    @State private var showStudio = false
    @State private var studioModel = ContentView.makeStudioModel()
    @State private var menuOpen = UserDefaults.standard.integer(forKey: "GameMenuOpen") != 0
    @State private var rosterOpen = false
    @State private var openPicker: ConsumableKind?
    @Environment(\.scenePhase) private var scenePhase
    private var focus: BlobFocus { model.care.focus }
    private func setUpSelect() {
        let sel = model.care.select
        if let l = SelectPreview.blobsFromLaunchArguments() { sel.setBlobs(l) }
        let light = UIImpactFeedbackGenerator(style: .light), crisp = UIImpactFeedbackGenerator(style: .rigid)
        sel.onDrawStart = { light.impactOccurred(intensity: 0.6) }      // a light tick as the outline starts
        sel.onMeet = { crisp.impactOccurred(intensity: 0.9) }          // a crisp tap when the halves meet
    }

    var body: some View {
        ZStack {
            MelonStage(model: model)
                .ignoresSafeArea()

            // dim scrim behind the care menu; a tap anywhere outside collapses it
            Color(red: 0.30, green: 0.20, blue: 0.14)
                .opacity(menuOpen ? 0.22 : 0)
                .ignoresSafeArea()
                .allowsHitTesting(menuOpen)
                .onTapGesture { withAnimation(CareMenu.spring) { menuOpen = false } }
                .animation(.easeInOut(duration: 0.25), value: menuOpen)

            TouchHeartsView(play: model.touch)

            SelectionOverlay(select: model.care.select)

            ThoughtBubbleView(care: model.care) { action in
                switch action {
                case .feed: withAnimation(CareMenu.spring) { menuOpen = true; openPicker = .food }
                case .drink: withAnimation(CareMenu.spring) { menuOpen = true; openPicker = .drink }
                case .comeHere: break                    // GameCare.tapBubble already called him
                }
            }

            // HUD
            ZStack {
                VStack {
                    HStack {
                        if focus.showsRelease {
                            ReleaseButton { withAnimation(CareMenu.spring) { model.care.release() } }
                                .transition(.move(edge: .leading).combined(with: .opacity))
                        } else if !focus.isActive {
                            GameCircleButton(systemName: "gearshape", label: "Studio") {
                                model.paused = true
                                showStudio = true
                            }
                            .accessibilityIdentifier("studio-button")
                            .transition(.opacity)
                        }
                        Spacer()
                        if !focus.isActive {
                            RosterButton(care: model.care, open: $rosterOpen)
                                .transition(.opacity)
                        }
                    }
                    Spacer()
                    if focus.showsDock {
                        FocusHint()                       // no tabs: the gesture decides; a first-time hint that fades after 4 s
                            .padding(.bottom, 18)
                            .transition(.opacity)
                    }
                    HStack {
                        Spacer()
                        if !focus.isActive, model.care.select.actionVisible { careSlot.transition(.scale(scale: 0.5, anchor: .bottomTrailing).combined(with: .opacity)) }
                    }
                }
                .animation(CareMenu.spring, value: focus.phase)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }

            RosterPanel(care: model.care, open: $rosterOpen) { id in model.care.rosterPick(id) }
                .padding(.top, 8)
        }
        .background(Color.black)
        .onAppear { setUpSelect(); model.care.touchPlay = model.touch }
        .onChange(of: scenePhase) { _, p in if p != .active { model.care.needs.save() } }
        .onChange(of: focus.isActive) { _, on in if on { rosterOpen = false } }
        .onChange(of: rosterOpen) { _, on in model.care.select.sheetOpen = on }
        .onAppear { model.care.select.gateDraw = true }
        .task { await GameScreen.runDebugScript(model: model, open: $menuOpen, roster: $rosterOpen, picker: $openPicker) }   // on the root: the HUD's pieces come and go with focus mode
        .fullScreenCover(isPresented: $showStudio, onDismiss: { model.paused = false }) {
            ZStack(alignment: .topTrailing) {
                MelonScreen(model: studioModel) {
                    MelonStage(model: studioModel)
                }
                GameCircleButton(systemName: "xmark", label: "Close studio") { showStudio = false }
                    .accessibilityIdentifier("studio-close")
                    .padding(.trailing, 16)
                    .padding(.top, 8)
            }
        }
    }

    /// Bottom-right care menu: one round button that expands upward into Feed / Drink / Come here.
    private var careSlot: some View {
        CareMenu(open: $menuOpen, care: model.care, openPicker: $openPicker)
            .padding(.trailing, 4)
            .padding(.bottom, 12)

    }

    /// Harmless launch args for captures: -GameAction feed|feed:cake|water|drink:soda|call|wave (after 4 s), -GameScript 1 (timed demo of everything).
    @MainActor static func runDebugScript(model: MelonModel, open: Binding<Bool>, roster: Binding<Bool>, picker: Binding<ConsumableKind?>) async {
        let d = UserDefaults.standard
        let care = model.care
        func sleep(_ s: Double) async { try? await Task.sleep(nanoseconds: UInt64(s * 1e9)) }
        func idleWait() async {
            await sleep(1.5)
            for _ in 0..<80 where care.bowlOut || care.busy { await sleep(0.5) }
        }
        func choose(_ f: () -> Void) async {
            withAnimation(CareMenu.spring) { open.wrappedValue = true }
            await sleep(1.4)
            f()
            withAnimation(CareMenu.spring) { open.wrappedValue = false }
        }
        // capture aid: -NeedsDemo bubble (the bubble pops, its tap opens Feed, he eats, it poofs) | roster (open it, tap Bob's card)
        if let demo = d.string(forKey: "NeedsDemo") {
            if demo == "bubble" {
                for _ in 0..<200 where care.bubbleNeed == nil { await sleep(0.1) }
                await sleep(3)
                if let a = care.tapBubble(), a == .feed {
                    withAnimation(CareMenu.spring) { open.wrappedValue = true; picker.wrappedValue = .food }
                    await sleep(1.8)
                    care.feed("berries")
                    withAnimation(CareMenu.spring) { open.wrappedValue = false }
                }
            } else {
                await sleep(3)
                withAnimation(CareMenu.spring) { roster.wrappedValue = true }
                await sleep(3)
                withAnimation(CareMenu.spring) { roster.wrappedValue = false }
                care.rosterPick(0)
            }
        }
        if let a = d.string(forKey: "GameAction") {
            await sleep(d.double(forKey: "GameActionDelay") > 0 ? d.double(forKey: "GameActionDelay") : 4)
            switch a {
            case "feed": care.feed()
            case "water": care.water()
            case "feed:cake": care.feed("cake")
            case "drink:soda": care.drink("soda")
            case "feed:berries": care.feed("berries")
            case "drink:water": care.drink("water")
            case "call": care.call()
            default: care.wave()
            }
            // capture aid: -GameReleaseAfter <s> presses "Let Bob go" that long after the action
            if d.double(forKey: "GameReleaseAfter") > 0 {
                for _ in 0..<600 where !care.focus.isFocused { await sleep(0.1) }
                await sleep(d.double(forKey: "GameReleaseAfter"))
                withAnimation(CareMenu.spring) { care.release() }
            }
        }
        #if DEBUG || SELECT_PREVIEW
        // capture aid: -BlobSelectPreview 3 -BlobSelectScript 1 double-taps Pip, switches to Moss, switches mid-draw back to Pip, then confirms
        if d.integer(forKey: "BlobSelectScript") != 0 {
            let sel = care.select
            await sleep(3)
            sel.doubleTap(1); await sleep(2.2)
            sel.doubleTap(2); await sleep(2.2)
            sel.doubleTap(0); await sleep(0.22)
            sel.doubleTap(1); await sleep(2.0)
            withAnimation(CareMenu.spring) { sel.confirm() }
            await sleep(3)
            sel.doubleTap(2); await sleep(1.5)
            withAnimation(CareMenu.spring) { sel.cancel() }
        }
        #endif
        if d.integer(forKey: "GameScript") != 0 {
            await sleep(16)
            await choose { care.feed() }
            await idleWait()
            await sleep(5)
            await choose { care.water() }
            await idleWait()
            await sleep(5)
            await choose { care.call() }
            await idleWait()
        }
    }

    static func makeGameModel() -> MelonModel {
        let m = MelonModel()
        m.gameMode = true
        m.palette = .blush
        return m
    }
}

/// Small matte cream circle with an SF Symbol.
struct GameCircleButton: View {
    let systemName: String
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color(red: 0.42, green: 0.34, blue: 0.30))
                .frame(width: 36, height: 36)
                .background(Circle().fill(Color(red: 0.97, green: 0.94, blue: 0.88)).opacity(0.92))
                .overlay(Circle().strokeBorder(Color.black.opacity(0.06), lineWidth: 0.5))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

// MARK: - Care menu

/// The expanding care button (bottom-right): paw -> cross, with Feed / Drink / Come here stacked above it.
struct CareMenu: View {
    @Binding var open: Bool
    let care: GameCare
    /// A thought bubble tap asks for a picker to be unfolded (Feed or Drink).
    @Binding var openPicker: ConsumableKind?

    static let spring = Animation.spring(response: 0.42, dampingFraction: 0.72)
    static let cream = Color(red: 0.97, green: 0.94, blue: 0.88)
    static let brown = Color(red: 0.42, green: 0.34, blue: 0.30)

    private struct Item: Identifiable {
        let id: String, title: String, symbol: String
    }
    /// "waterbottle.fill" exists on the deployment target (iOS 26); keep the drop as a fallback.
    static let waterSymbol = UIImage(systemName: "waterbottle.fill") != nil ? "waterbottle.fill" : "drop.fill"
    // top to bottom
    private let items = [Item(id: "care-feed", title: "Feed", symbol: "fork.knife"),
                         Item(id: "care-water", title: "Drink", symbol: CareMenu.waterSymbol),
                         Item(id: "care-call", title: "Come here", symbol: "hand.wave.fill")]

    /// Which picker is unfolded under its row: Feed (berries, cake) and Drink (water, soda), each as two chips.
    @State private var picker: ConsumableKind?

    var body: some View {
        VStack(alignment: .trailing, spacing: 14) {
            if open {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    row(item, index: index)
                    if picker == .food, item.id == "care-feed" { pickerRow(Consumables.foods, kind: .food) }
                    if picker == .drink, item.id == "care-water" { pickerRow(Consumables.drinks, kind: .drink) }
                }
            }
            mainButton
        }
        .onChange(of: open) { _, isOpen in if !isOpen { picker = nil } }
        .onChange(of: openPicker) { _, k in
            guard let k else { return }
            openPicker = nil
            withAnimation(Self.spring) { open = true; picker = k }
        }
    }

    /// A tiny row of the catalogue's items in the same cream style; tapping one starts it and closes the menu.
    private func pickerRow(_ list: [Consumable], kind: ConsumableKind) -> some View {
        HStack(spacing: 10) {
            ForEach(Array(list.enumerated()), id: \.element.id) { i, c in
                Button {
                    UIImpactFeedbackGenerator(style: .soft).impactOccurred()
                    if kind == .food { care.feed(c.id) } else { care.drink(c.id) }
                    withAnimation(Self.spring) { picker = nil; open = false }
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: UIImage(systemName: c.symbol) != nil ? c.symbol : "drop.fill")
                            .font(.system(size: 19, weight: .semibold))
                            .foregroundStyle(Self.brown)
                            .frame(width: 46, height: 46)
                            .background(Circle().fill(Self.cream).shadow(color: Color(red: 0.3, green: 0.2, blue: 0.12).opacity(0.2), radius: 6, y: 2))
                            .overlay(Circle().strokeBorder(Color.white.opacity(0.5), lineWidth: 1))
                        Text(c.name)
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundStyle(Self.brown)
                            .padding(.horizontal, 8).padding(.vertical, 2)
                            .background(Capsule().fill(Self.cream))
                    }
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("care-\(kind == .food ? "food" : "drink")-\(c.id)")
                .accessibilityLabel(c.name)
                .transition(.scale(scale: 0.3, anchor: .trailing).combined(with: .opacity)
                    .animation(Self.spring.delay(Double(i) * 0.05)))
            }
        }
        .padding(.trailing, 8)
    }

    private func enabled(_ item: Item) -> Bool {
        switch item.id { case "care-feed", "care-water": return !care.trayOut; default: return true }
    }

    private func row(_ item: Item, index: Int) -> some View {
        let fromBottom = items.count - 1 - index          // 0 = nearest the main button
        let on = enabled(item)
        return Button {
            UIImpactFeedbackGenerator(style: .soft).impactOccurred()
            switch item.id {
            case "care-feed":
                withAnimation(Self.spring) { picker = picker == .food ? nil : .food }
                return                                       // the picker row chooses; the menu stays open
            case "care-water":
                if Consumables.drinks.count >= 2 {
                    withAnimation(Self.spring) { picker = picker == .drink ? nil : .drink }
                    return
                }
                care.drink(Consumables.drinks.first?.id ?? "water")   // one drink: starts directly
            default: care.comeHere()
            }
            withAnimation(Self.spring) { open = false }
        } label: {
            HStack(spacing: 10) {
                Text(item.title)
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(Self.brown)
                    .padding(.horizontal, 15).padding(.vertical, 8)
                    .background(Capsule().fill(Self.cream).shadow(color: Color(red: 0.3, green: 0.2, blue: 0.12).opacity(0.18), radius: 6, y: 2))
                Image(systemName: item.symbol)
                    .font(.system(size: 21, weight: .semibold))
                    .foregroundStyle(Self.brown)
                    .frame(width: 54, height: 54)
                    .background(Circle().fill(Self.cream).shadow(color: Color(red: 0.3, green: 0.2, blue: 0.12).opacity(0.22), radius: 7, y: 3))
                    .overlay(Circle().strokeBorder(Color.white.opacity(0.5), lineWidth: 1))
            }
            .opacity(on ? 1 : 0.45)
        }
        .buttonStyle(.plain)
        .disabled(!on)
        .accessibilityIdentifier(item.id)
        .accessibilityLabel(item.title)
        .transition(.scale(scale: 0.3, anchor: .bottomTrailing).combined(with: .opacity)
            .combined(with: .offset(y: 24 + CGFloat(fromBottom) * 10))
            .animation(Self.spring.delay(Double(fromBottom) * 0.05)))
    }

    private var mainButton: some View {
        Button {
            UIImpactFeedbackGenerator(style: .soft).impactOccurred()
            withAnimation(Self.spring) { open.toggle() }
        } label: {
            ZStack {
                Image(systemName: "pawprint.fill")
                    .font(.system(size: 27, weight: .semibold))
                    .opacity(open ? 0 : 1)
                    .rotationEffect(.degrees(open ? 90 : 0))
                    .scaleEffect(open ? 0.4 : 1)
                Image(systemName: "xmark")
                    .font(.system(size: 24, weight: .bold))
                    .opacity(open ? 1 : 0)
                    .rotationEffect(.degrees(open ? 0 : -90))
                    .scaleEffect(open ? 1 : 0.4)
            }
            .foregroundStyle(Self.brown)
            .frame(width: 64, height: 64)
            .background(Circle().fill(Self.cream).shadow(color: Color(red: 0.3, green: 0.2, blue: 0.12).opacity(0.28), radius: 9, y: 4))
            .overlay(Circle().strokeBorder(Color.white.opacity(0.55), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("care-menu")
        .accessibilityLabel(open ? "Close care menu" : "Care menu")
    }
}

// MARK: - Focus mode UI

/// The pastel palette of the focus-mode UI (cream #FFF8F1, pink #E98AA4, brown #5a3324).
enum FocusStyle {
    static let cream = Color(red: 1.0, green: 0.973, blue: 0.945)
    static let pink = Color(red: 0.914, green: 0.541, blue: 0.643)
    static let brown = Color(red: 0.353, green: 0.2, blue: 0.141)
    static let shadow = Color(red: 0.3, green: 0.2, blue: 0.12)
}

/// "Let Bob go": the only way out of focus mode (top-left).
struct ReleaseButton: View {
    let action: () -> Void
    var body: some View {
        Button {
            UIImpactFeedbackGenerator(style: .soft).impactOccurred()
            action()
        } label: {
            HStack(spacing: 7) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 13, weight: .bold))
                Text("Let Bob go")
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
            }
            .foregroundStyle(FocusStyle.brown)
            .padding(.horizontal, 16).padding(.vertical, 10)
            .background(Capsule().fill(FocusStyle.cream).shadow(color: FocusStyle.shadow.opacity(0.2), radius: 7, y: 3))
            .overlay(Capsule().strokeBorder(Color.white.opacity(0.6), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("focus-release")
        .accessibilityLabel("Let Bob go")
    }
}

/// The first-time hint in focus mode: "Pet · Pinch cheeks · Hold to pick up". Shown for the first few visits only, fades after 4 s.
struct FocusHint: View {
    static let key = "FocusHintSeen"
    @State private var shown = UserDefaults.standard.integer(forKey: FocusHint.key) < 3
    @State private var visible = true

    var body: some View {
        if shown {
            Text("Pet · Pinch cheeks · Hold to pick up")
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(FocusStyle.brown)
                .padding(.horizontal, 18).padding(.vertical, 10)
                .background(Capsule().fill(FocusStyle.cream).shadow(color: FocusStyle.shadow.opacity(0.2), radius: 7, y: 3))
                .overlay(Capsule().strokeBorder(Color.white.opacity(0.6), lineWidth: 1))
                .opacity(visible ? 1 : 0)
                .allowsHitTesting(false)
                .accessibilityIdentifier("focus-hint")
                .task {
                    UserDefaults.standard.set(UserDefaults.standard.integer(forKey: FocusHint.key) + 1, forKey: FocusHint.key)
                    try? await Task.sleep(nanoseconds: 3_500_000_000)
                    withAnimation(.easeOut(duration: 0.5)) { visible = false }
                }
        }
    }
}
