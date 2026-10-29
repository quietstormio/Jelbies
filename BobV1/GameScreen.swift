//
//  GameScreen.swift
//  The game: Bob in the living room, full screen. The HUD is a ZStack overlay on top of the stage:
//  small gear (top-left) opens the studio; `hud` is the slot for the care menu (bottom-right).
//

import SwiftUI
import QuartzCore
import AppIntents

struct GameScreen: View {
    @State private var model = GameScreen.makeGameModel()
    @State private var showStudio = false
    @State private var studioModel = ContentView.makeStudioModel()
    @State private var menuOpen = UserDefaults.standard.integer(forKey: "GameMenuOpen") != 0
    @State private var rosterOpen = false
    @State private var bookOpen = false                       // Voice v1 trick book
    @State private var soundOpen = UserDefaults.standard.integer(forKey: "SoundPanelOpen") != 0      // sound settings panel (-SoundPanelOpen 1: captures)
    @State private var town: TownScreen? = GameScreen.launchTown()      // Go out: Town / Shop / Track (Store/TownUI.swift)
    @State private var bagOpen = UserDefaults.standard.string(forKey: "StoreOpen") == "bag"
    @State private var bagTab: BagSheet.BagTab?               // Dress / Play / Decor open the Bag on that tab, for that Jelbie
    @State private var bagWho: Int?
    @State private var settingsOpen = UserDefaults.standard.integer(forKey: "SettingsOpen") != 0                   // the gear's Settings popover (Accessibility / Studio)
    @State private var a11yOpen = UserDefaults.standard.integer(forKey: "A11yPanelOpen") != 0      // the Accessibility sheet (-A11yPanelOpen 1: captures)
    @Environment(\.accessibilityReduceMotion) private var reduceMotionEnv
    @State private var extrasOpen = false                     // Siri & Lock Screen panel (Live Activity toggles, Siri tip)
    /// Every way into the game (widget links, Siri, the App Group queue) lands here; `apply` runs the routes on the care flows.
    private let router = GameRouter.shared
    private var jellyNames: [String] { model.care.jellies.map(\.name) }
    @State private var openPicker: ConsumableKind?
    @Environment(\.scenePhase) private var scenePhase
    @State private var hudTopH: CGFloat = 52          // measured: the top bar, so the open paw menu scrolls inside what is really left
    @State private var hudInfoH: CGFloat = 0          // measured: the info row (sleep-until-morning) under it
    @Environment(\.verticalSizeClass) private var vsc          // .compact = a phone on its side
    @State private var trainCardTop: CGFloat?          // the highest top edge the Train card has had this session (its tallest step): the camera frames the Jelbie above it
    @State private var trainCardLeft: CGFloat?         // landscape: the card's left edge
    private var focus: BlobFocus { model.care.focus }
    /// Tells the close-up camera which part of the screen the Train card leaves free (GameCamera.trainFrame), as fractions of the whole screen.
    private func frameTrainCamera(card: CGRect, g: GeometryProxy) {
        guard card.height > 1 else { return }
        trainCardTop = min(trainCardTop ?? .infinity, card.minY); trainCardLeft = min(trainCardLeft ?? .infinity, card.minX)
        let W = g.size.width + g.safeAreaInsets.leading + g.safeAreaInsets.trailing, H = g.size.height + g.safeAreaInsets.top + g.safeAreaInsets.bottom
        let top = Float((g.safeAreaInsets.top + 8 + hudTopH + 6) / H)
        let landscape = vsc == .compact
        let f: GameCamera.TrainFrame = landscape
            ? .init(minX: Float((g.safeAreaInsets.leading + 72) / W), maxX: Float(((trainCardLeft ?? card.minX) - 8) / W), minY: top, maxY: 0.95)
            : .init(minX: 0.04, maxX: 0.96, minY: top, maxY: Float((trainCardTop ?? card.minY) / H) - 0.012)
        GameCamera.trainInstant = a11yMotionReduced
        if GameCamera.trainFrame != f { GameCamera.trainFrame = f }
    }
    private var a11yMotionReduced: Bool { reduceMotionEnv || A11ySettings.shared.reduceMotion }
    private var cleaning: Bool { model.care.bath.active }
    private var racing: Bool { model.care.tripActive }
    private func setUpSelect() {
        let sel = model.care.select
        if let l = SelectPreview.blobsFromLaunchArguments() { sel.setBlobs(l) }
        let light = UIImpactFeedbackGenerator(style: .light), crisp = UIImpactFeedbackGenerator(style: .rigid)
        sel.onDrawStart = { light.impactOccurred(intensity: 0.6); AudioHub.shared.play(.select) }      // a light tick as the outline starts
        sel.onMeet = { crisp.impactOccurred(intensity: 0.9) }          // a crisp tap when the halves meet
        // Voice: a light tick as he starts and stops listening (works roaming; HapticDriver is only warm in focus mode)
        let voiceTick = UIImpactFeedbackGenerator(style: .light)
        voiceTick.prepare()                                  // warm, so the tick lands on the touch-down frame
        model.care.voice.mode.onOpen = { voiceTick.impactOccurred(intensity: 0.6); voiceTick.prepare(); AudioHub.shared.micListening(true) }
        model.care.voice.mode.onClose = { voiceTick.impactOccurred(intensity: 0.6); voiceTick.prepare(); AudioHub.shared.micListening(false) }
        model.care.voice.prewarm()
    }

    var body: some View {
        ZStack {
            MelonStage(model: model)
                .ignoresSafeArea()

            // dim scrim behind the care / Go out menus; a tap anywhere outside collapses them
            Color(red: 0.30, green: 0.20, blue: 0.14)
                .opacity(menuOpen ? 0.22 : 0)
                .ignoresSafeArea()
                .allowsHitTesting(menuOpen)
                .onTapGesture { withAnimation(CareMenu.spring) { menuOpen = false } }
                .animation(.easeInOut(duration: 0.25), value: menuOpen)
                .accessibilityHidden(true)          // the menus carry an Escape action instead

            TouchHeartsView(play: model.touch, care: model.care).photoHidden()

            SelectionOverlay(select: model.care.select).photoHidden()

            VoiceGlow(voice: model.care.voice, care: model.care).photoHidden()
            VoiceFeedbackView(voice: model.care.voice, care: model.care).photoHidden()

            GreetHeartsView(care: model.care).photoHidden()          // Pip's and Moss's greeting hearts

            ThoughtBubbleView(care: model.care) { action in
                switch action {
                case .feed: withAnimation(CareMenu.spring) { menuOpen = true; openPicker = .food }
                case .drink: withAnimation(CareMenu.spring) { menuOpen = true; openPicker = .drink }
                case .comeHere, .clean: break            // GameCare.tapBubble already called him / started the clean-up
                }
            }.photoHidden()

            CaptionsView(center: .shared).photoHidden()          // sound captions (Accessibility settings; off by default)

            RefusalLabel(care: model.care).photoHidden()

            // HUD
            GeometryReader { g in
            ZStack {
                VStack {
                    HStack {
                        if focus.showsRelease {
                            ReleaseButton(name: model.care.focusGroup.ids.count == 1 ? model.care.jelly(model.care.focusGroup.ids[0])?.name : nil) { withAnimation(CareMenu.spring) { model.care.release() } }
                                .transition(.move(edge: .leading).combined(with: .opacity))
                            GameCircleButton(systemName: "rectangle.portrait.on.rectangle.portrait.angled", label: "Condition card") {
                                AudioHub.shared.uiTap(); withAnimation(.easeInOut(duration: 0.25)) { town = .condition }
                            }
                            .accessibilityIdentifier("focus-card")
                            .transition(.opacity)
                        } else if !focus.isActive, !cleaning, !racing {
                            GlassEffectContainer(spacing: 8) {
                                HStack(spacing: 0) {
                                    HUDGlassIcon(systemName: "gearshape", label: "Settings") {
                                        AudioHub.shared.uiTap()
                                        withAnimation(CareMenu.spring) { soundOpen = false; extrasOpen = false; menuOpen = false }; settingsOpen = true
                                    }
                                    .accessibilityValue(settingsOpen ? "expanded" : "collapsed")
                                    .accessibilityIdentifier("studio-button")
                                    HUDGlassIcon(systemName: soundOpen ? "speaker.wave.2.fill" : "speaker.wave.2", label: "Sound") {
                                        AudioHub.shared.uiTap()
                                        withAnimation(CareMenu.spring) { soundOpen.toggle(); if soundOpen { extrasOpen = false; settingsOpen = false } }
                                    }
                                    .accessibilityIdentifier("sound-button")
                                }
                                .padding(.horizontal, 4)
                                .hudFrost(in: .capsule)
                            }
                            .transition(.opacity)
                        }
                        Spacer()
                        if !focus.isActive, !cleaning, !racing {
                            GlassEffectContainer(spacing: 8) {
                                HStack(spacing: 8) {
                                    DropsPill(wallet: model.care.bath.wallet, glass: true)
                                    RosterButton(care: model.care, open: $rosterOpen)
                                }
                            }
                            .transition(.opacity)
                        }
                    }
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { hudTopH = $0 }
                    .accessibilityElement(children: .contain)
                    .accessibilitySortPriority(4)          // VoiceOver order: top bar, left rail (book, bag, Go out, mic), then the paw
                    if !focus.isActive, !cleaning, !racing {
                        HStack(spacing: 8) { SleepUntilMorningButton(care: model.care); Spacer() }
                            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { hudInfoH = $0 }
                    }
                    Spacer()
                    if focus.showsDock {
                        FocusHint(interacted: { model.touch.contact || model.care.voice.mode.phase != .idle })                       // no tabs: the gesture decides; a first-time hint that fades after 4 s
                            .padding(.bottom, 18)
                            .transition(.opacity)
                    }
                    if !cleaning, !racing {
                        HStack(alignment: .bottom, spacing: 10) {
                            // LEFT RAIL: the trick book, the bag, Go out (a menu) and the mic (at the bottom)
                            GlassEffectContainer(spacing: 8) {
                                VStack(spacing: 0) {
                                    VoiceBookButton { bookOpen = true }
                                    if !focus.isActive { BagButton(store: model.care.store) { bagTab = nil; bagWho = nil; bagOpen = true } }
                                    if !focus.isActive {
                                        GoOutButton { withAnimation(.easeInOut(duration: 0.25)) { town = .town } }
                                    }
                                    Capsule().fill(CareMenu.brown.opacity(0.22)).frame(width: 28, height: 1.5).padding(.vertical, 4)
                                    VoiceMicButton(voice: model.care.voice, openBook: { bookOpen = true }, pulse: model.care.voice.tutorial.isShown && model.care.voice.tutorial.pulsingMic)
                                        .overlay(alignment: .topLeading) {
                                            VoiceTip(voice: model.care.voice).fixedSize().offset(y: -86)
                                        }
                                }
                                .padding(.vertical, 6)
                                .frame(width: HUDTuning.railWidth)
                                .hudFrost(in: .capsule)
                            }
                            .accessibilityElement(children: .contain)
                            .accessibilitySortPriority(3)
                            Spacer()
                            // RIGHT: the one main control (group / individual), alone
                            if !focus.isActive {
                                careSlot
                                .transition(a11yMotionReduced ? .opacity : .scale(scale: 0.5, anchor: .bottomTrailing).combined(with: .opacity))
                                .accessibilityElement(children: .contain)
                                .accessibilitySortPriority(1)
                            }
                        }
                        .padding(.bottom, HUDLayout.lift(size: CGSize(width: g.size.width, height: g.size.height + g.safeAreaInsets.top + g.safeAreaInsets.bottom), safeBottom: g.safeAreaInsets.bottom, compact: vsc == .compact))
                    }
                }
                .animation(CareMenu.spring, value: focus.phase)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                if model.care.voice.train != nil {          // the close-up's Train card (Voice/TrainCard.swift): bottom, right of the rail; landscape: the right side
                    TrainCard(voice: model.care.voice, landscape: vsc == .compact, maxHeight: vsc == .compact ? g.size.height - 20 : g.size.height * 0.40)
                        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frameTrainCamera(card: $0, g: g) }          // the close-up keeps the whole Jelbie in the free area
                        .onDisappear { trainCardTop = nil; trainCardLeft = nil; GameCamera.trainFrame = nil }
                        .padding(.leading, vsc == .compact ? 0 : 62).padding(.trailing, 12).padding(.bottom, 10)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                        .transition(.opacity)
                }
            }
            .jHUDCap()
            .environment(\.a11yAvailableHeight, max(120, g.size.height - 16 - hudTopH - hudInfoH - 24    // 16 = HUD vertical padding, 24 = VStack gaps; then the paw's lift
                - HUDLayout.lift(size: CGSize(width: g.size.width, height: g.size.height + g.safeAreaInsets.top + g.safeAreaInsets.bottom), safeBottom: g.safeAreaInsets.bottom, compact: vsc == .compact)))
            }.photoHidden()
            .opacity(model.care.nightSkip.active || model.care.arranging ? 0 : 1)          // "Sleep until morning": the HUD is away until the morning has been shown; arranging the room hides it too
            .allowsHitTesting(!model.care.nightSkip.active && !model.care.arranging)
            .accessibilityHidden(model.care.arranging)
            .animation(.easeInOut(duration: 0.6), value: model.care.nightSkip.active)
            .animation(.easeInOut(duration: 0.2), value: model.care.arranging)

            BathChrome(care: model.care)

            RaceChrome(care: model.care)          // Jelly Circuit: numerals, foot buttons, placings card, the white fade

            ShowChrome(care: model.care)          // Jelly Show: the Look / Dance / Trick rounds and the results on the stage, the white fade

            CafeChrome(care: model.care)          // the café outing: the menu card, Head home, the white fade

            ParkChrome(care: model.care)          // the park outing: the picker, the visitors' cards, Go home, the white fade

            GroomChrome(care: model.care)          // the Jelly Spa: the tier menu, the shop-front cut-scene, the reveal banner

            GuestChrome(care: model.care)          // a friend over at home: his card (a tap on him)

            VolleyChrome(care: model.care)          // Jelly Volleyball: score, controls, results, the white fade

            if model.care.arranging { ArrangeOverlay(care: model.care) }          // decor: drag the room's pieces about

            if PhotoMode.shared.active { PhotoModeView(care: model.care) }          // Photo mode: HUD hidden, the bar, the camera fingers

            if town != nil {                     // Go out: Town / Shop / Track
                TownFlow(care: model.care, screen: $town, who: model.care.targetJelly, cafe: { model.care.requestCafe() }, park: { model.care.requestPark() }, groom: { model.care.requestGroom() }) { withAnimation(.easeInOut(duration: 0.25)) { town = nil } }
                    .transition(.opacity)
            }

            // (the come-here tutorial card is retired: he knows "come here" from the start)

            RosterPanel(care: model.care, open: $rosterOpen) { id in model.care.rosterPick(id) }
                .padding(.top, 8)

            if soundOpen {
                SoundSettingsPanel(hub: AudioHub.shared, openExtras: { withAnimation(CareMenu.spring) { soundOpen = false; extrasOpen = true } }) { withAnimation(CareMenu.spring) { soundOpen = false } }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .padding(.leading, 16).padding(.top, 52)
                    .transition(.scale(scale: 0.8, anchor: .topLeading).combined(with: .opacity))
            }
            if extrasOpen {
                AppleExtrasPanel(live: LiveActivities.shared) { withAnimation(CareMenu.spring) { extrasOpen = false } }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .padding(.leading, 16).padding(.top, 52)
                    .transition(.scale(scale: 0.8, anchor: .topLeading).combined(with: .opacity))
            }
        }
        .background(Color.black)
        .onAppear {
            A11ySettings.shared.systemReduceMotion = reduceMotionEnv
            setUpSelect(); model.care.touchPlay = model.touch
            DayClock.shared.snapToNow()          // the room is on the real clock before the first frame (no catch-up sweep), and before the bedtime check
            model.care.launched()
            model.care.store.grantStarterIfNeeded()          // first open: the starter Drops, once
            AudioHub.shared.start()
            AudioHub.shared.setTownScene(GameScreen.townMusic(town))
            Ears.shared.launch(care: model.care)
            LiveActivities.shared.cleanUp(names: jellyNames)                                           // orphans from a killed run; adopt a live nap / Pep card
            let care = model.care
            let toTrack: (Int) -> Void = { id in                 // Siri "race" / "train": the Track panel for that Jelbie (its Race / Train buttons), like the voice command
                guard !care.raceBusy, !care.cafe.active, !care.focus.isActive, !care.arranging, !care.bath.active, !care.trayOut else { care.openJelly(id); return }
                care.rosterPick(id, quietHop: true); care.requestTown(.track)
            }
            router.onRace = toTrack; router.onTrain = toTrack
            router.onBed = { care.goodnight() }                 // Siri "goodnight": the voice goodnight flow (every Jelbie to bed)
            router.apply(care: model.care)                                                             // a Siri route that launched the app cold
            JelbiesShortcuts.updateAppShortcutParameters()                                             // Siri learns the Jelbies' names for "Feed Pip in Jelbies"
        }
        .onChange(of: reduceMotionEnv) { _, on in A11ySettings.shared.systemReduceMotion = on }          // camera / effects only; the jelly physics never changes
        .fullScreenCover(isPresented: $settingsOpen) {
            SettingsScreen(
                openStudio: { settingsOpen = false; model.paused = true; DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { showStudio = true } },
                mainMenu: {
                    model.care.leftActive(); model.care.voice.training.save(); model.care.voice.cancel()          // the same saves as leaving the app
                    settingsOpen = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { withAnimation(.easeInOut(duration: 0.4)) { StartFlow.shared.returnToMenu() } }
                },
                resetSave: {
                    model.care.voice.cancel()
                    settingsOpen = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { StartFlow.shared.startOver() }
                },
                openPhoto: {
                    settingsOpen = false; menuOpen = false; soundOpen = false; extrasOpen = false; rosterOpen = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { PhotoMode.shared.open(care: model.care) }          // after the Settings cover is gone
                },
                watchOpening: {
                    model.care.leftActive(); model.care.voice.training.save(); model.care.voice.cancel()          // the same saves as leaving for the menu
                    settingsOpen = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { withAnimation(.easeInOut(duration: 0.4)) { StartFlow.shared.replayOpening() } }          // after the Settings cover is gone; no picker, no save changes
                },
                close: { settingsOpen = false })
        }
        .sheet(isPresented: $a11yOpen) {
            AccessibilitySettingsView { a11yOpen = false }
                .presentationDetents(vsc == .compact ? [.large] : [.large, .medium])
                .presentationBackground(SK.cream)
        }
        .onOpenURL { url in _ = router.handle(url) }          // widget / Live Activity tap: jelbies://jelly|feed|water|bed|race|train|pet
        .onChange(of: router.serial) { _, _ in router.apply(care: model.care) }                       // Siri in-process, a drained queue
        .onChange(of: scenePhase) { _, p in
            if p == .active {
                model.care.skipNightCutscene(force: true)          // back mid "Sleep until morning": finish the skip now
                DayClock.shared.snapToNow()          // light, music bucket and night state jump to the real clock (no sweep), before the bedtime check and the director see the foreground
                model.care.returnedActive()          // time away: needs, dirt, sparkle (once per return) + the greeting
                AudioHub.shared.setForeground(true)
                Ears.shared.setForeground(true)
                LiveActivities.shared.returnedActive(names: jellyNames)                                // by day the nap card says good morning
                router.drainQueued()                                                                   // the widget's Water button / an intent run while away
                router.apply(care: model.care)
            } else {
                model.care.leftActive(); model.care.voice.training.save(); model.care.voice.cancel()
                DayClock.shared.leaving()
                AudioHub.shared.setForeground(false)
                Ears.shared.setForeground(false)
                LiveActivities.shared.leftActive(names: jellyNames)                                    // at night (or tucked in): the nap card
            }
        }
        .onChange(of: model.care.voice.bookRequest) { _, _ in bookOpen = true }       // the mic cannot be used: the trick book opens instead
        .onChange(of: bookOpen) { _, on in model.care.select.sheetOpen = on || rosterOpen }
        .onChange(of: bookOpen) { _, on in if !on, model.care.voice.tutorial.phase == .book { model.care.voice.tutorial.finish() } }      // tutorial: the book was read
        .sheet(isPresented: $bookOpen) {
            VoiceTrickBook(voice: model.care.voice) { bookOpen = false }
                .presentationDetents(vsc == .compact ? [.large] : [.medium, .large])
                .presentationBackground(FocusStyle.cream)
        }
        .onChange(of: model.care.cafe.inScene) { _, on in AudioHub.shared.setTownScene(on ? CafeTuning.music : GameScreen.townMusic(town)) }
        .onChange(of: model.care.park.inScene) { _, on in AudioHub.shared.setTownScene(on ? ParkTuning.music : GameScreen.townMusic(town)) }
        .onChange(of: model.care.volley.inScene) { _, on in AudioHub.shared.setTownScene(on ? .volley : GameScreen.townMusic(town)); AudioHub.shared.beachAmbience(on) }
        .onChange(of: town) { _, t in model.paused = t != nil; AudioHub.shared.setTownScene(GameScreen.townMusic(t)) }
        .onChange(of: bagOpen) { _, on in model.care.select.sheetOpen = on || rosterOpen || bookOpen; if !on { bagTab = nil; bagWho = nil } }
        .overlay { RoomSwitchVeil(care: model.care) }
        .overlay { NightSkipVeil(care: model.care) }
        .sheet(isPresented: $bagOpen) {
            BagSheet(care: model.care, who: bagWho ?? model.care.targetJelly, tab: bagTab) { bagOpen = false }
                .presentationDetents(vsc == .compact ? [.large] : [.large, .medium])
                .presentationDragIndicator(.visible)
                .presentationBackground(SK.cream)
        }
        .task { await GameScreen.runStoreDemo(model: model) }
        .onChange(of: focus.isActive) { _, on in if on { rosterOpen = false } }
        .onChange(of: rosterOpen) { _, on in model.care.select.sheetOpen = on || bookOpen }
        .onChange(of: model.care.townRequest) { _, _ in                 // voice: "let's race" / "time to train" open the Track for the picked Jelly
            if let s = model.care.townScreen { bookOpen = false; rosterOpen = false; withAnimation(.easeInOut(duration: 0.25)) { town = s } }
        }
        .onAppear { model.care.select.gateDraw = true }
        .task { await GameScreen.runDebugScript(model: model, open: $menuOpen, roster: $rosterOpen, picker: $openPicker, book: $bookOpen, goOut: $town) }   // on the root: the HUD's pieces come and go with focus mode
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
        CareMenu(open: $menuOpen, care: model.care, openPicker: $openPicker,
                 openBag: { tab, who in bagTab = tab; bagWho = who; bagOpen = true },
                 openTown: { t, who in withAnimation(.easeInOut(duration: 0.25)) { town = t }; model.care.select.sheetOpen = false })
        .padding(.trailing, 4)

    }

    /// Harmless launch args for captures: -GameAction feed|feed:pizza|water|drink:soda|call|callall|callids:1,2|wave (after 4 s), -GameScript 1 (timed demo of everything).
    @MainActor static func runDebugScript(model: MelonModel, open: Binding<Bool>, roster: Binding<Bool>, picker: Binding<ConsumableKind?>, book: Binding<Bool> = .constant(false), goOut: Binding<TownScreen?> = .constant(nil)) async {
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
        // perf capture aid: -FocusCycles <n> enters focus (call) and lets Bob go n times (3 s each way); logs show GPU time / memory per cycle
        if d.integer(forKey: "FocusCycles") > 0 {
            await sleep(4)
            for i in 1...d.integer(forKey: "FocusCycles") {
                NSLog("[melon] focus cycle %d: enter", i)
                care.call()
                for _ in 0..<100 where !care.focus.isFocused { await sleep(0.1) }
                await sleep(3)
                NSLog("[melon] focus cycle %d: release", i)
                withAnimation(CareMenu.spring) { care.release() }
                await sleep(3)
            }
        }
        // capture aid: -RaceStart 1 sends Jelly 0 (or -RaceJelly n) to the track as soon as the room is up; -RaceSeed n, -RaceAuto <taps/s> (the player's buttons tapped for him)
        if d.integer(forKey: "RaceStart") != 0 {
            let who = d.object(forKey: "RaceJelly") != nil ? d.integer(forKey: "RaceJelly") : 0
            for _ in 0..<100 where !care.canRace(jelly: who) || care.raceBook.actors.isEmpty { await sleep(0.1) }
            await sleep(d.double(forKey: "RaceStartDelay") > 0 ? d.double(forKey: "RaceStartDelay") : 1.5)
            care.startRace(jelly: who)
        }
        // capture aid: -TrainStart 1 sends Jelly 0 (or -RaceJelly n) to practise Rhythm Steps; -TrainAuto 1 plays the drill for him
        if d.integer(forKey: "TrainStart") != 0 {
            let who = d.object(forKey: "RaceJelly") != nil ? d.integer(forKey: "RaceJelly") : 0
            for _ in 0..<100 where !care.canRace(jelly: who) || care.raceBook.actors.isEmpty { await sleep(0.1) }
            await sleep(d.double(forKey: "RaceStartDelay") > 0 ? d.double(forKey: "RaceStartDelay") : 1.5)
            care.startDrill(jelly: who)
        }
        // capture aid: -ShowStart 1 sends Jelly 0 (or -RaceJelly n) to the Jelly Show at the chosen rank (-ShowRank) as soon as the room is up; -ShowAuto 1 plays it
        // for him (dress, dance, tricks, results); -ShowSeed n, -ShowDay yyyymmdd. -PracticeStart sway|bop|twirl runs the Studio's dance drill instead.
        if d.integer(forKey: "ShowStart") != 0 || d.string(forKey: "PracticeStart") != nil {
            let who = d.object(forKey: "RaceJelly") != nil ? d.integer(forKey: "RaceJelly") : 0
            for _ in 0..<100 where !care.canShow(jelly: who) || care.raceBook.actors.isEmpty { await sleep(0.1) }
            await sleep(d.double(forKey: "RaceStartDelay") > 0 ? d.double(forKey: "RaceStartDelay") : 1.5)
            if let p = d.string(forKey: "PracticeStart") { care.startDancePractice(jelly: who, dance: DanceID(rawValue: p) ?? .sway) } else { care.startShow(jelly: who) }
        }
        // capture aid: -EarsDemo on|hearing:<kind>|denied|paused shows the ear button's state (no engine), and after -EarsDelay s (default 4) plays
        // the reaction: -EarsEvent clap|double|dance|whistle|bark|laugh|meow|bang (dance = 110 BPM from then on)
        if d.string(forKey: "EarsDemo") != nil {
            let spec = d.string(forKey: "EarsDemo") ?? ""
            let event = d.string(forKey: "EarsEvent")
            await sleep(d.double(forKey: "EarsDelay") > 0 ? d.double(forKey: "EarsDelay") : 4)
            if spec.hasPrefix("hearing:"), let k = EarKind(rawValue: String(spec.dropFirst(8))) { Ears.shared.showHearing(k, seconds: 30) }
            switch event {
            case "clap": Ears.shared.inject(.heard(.clap)); Ears.shared.showHearing(.clap, seconds: 30)
            case "double": Ears.shared.inject(.doubleClap); Ears.shared.showHearing(.clap, seconds: 30)
            case "dance": Ears.shared.inject(.musicStarted(EarBeat(bpm: 110, anchor: CACurrentMediaTime(), strength: 3))); Ears.shared.showHearing(.music, seconds: 120)
            case "whistle": Ears.shared.inject(.heard(.whistle)); Ears.shared.showHearing(.whistle, seconds: 30)
            case "bark": Ears.shared.inject(.heard(.dogBark)); Ears.shared.showHearing(.dogBark, seconds: 30)
            case "laugh": Ears.shared.inject(.heard(.laugh)); Ears.shared.showHearing(.laugh, seconds: 30)
            case "meow": Ears.shared.inject(.heard(.catMeow)); Ears.shared.showHearing(.catMeow, seconds: 30)
            case "bang": Ears.shared.inject(.bang(level: 0.6)); Ears.shared.showHearing(.loudBang, seconds: 30)
            default: break
            }
        }
        // capture aids for the HUD: -HUDHighlight n (tap Jelbie n after 4 s), -HUDMenu open (the main control unfolds after 5 s), -HUDGoOut open,
        // -HUDFrontPark left|right|centre (Jelly 0 walks to the front corner; use with -BlobNoWander 1), -HUDSleepDemo n (Jelbie n sleeps, 500 s hold)
        if d.object(forKey: "HUDSleepDemo") != nil {
            let n = d.integer(forKey: "HUDSleepDemo")
            await sleep(2.5)
            if care.raceBook.actors.indices.contains(n), let b = care.raceBook.actors[n].brain {
                b.idleForced = true; _ = b.idleStart(.sleep, care.raceBook.actors[n].sim); b.sleep.hold = 500; b.sleep.holdForce = true
            }
        }
        if let side = d.string(forKey: "HUDFrontPark") {
            await sleep(3)
            if let rf = GameCamera.roamFloor {
                let c = rf.extremeCorners
                let spot: SIMD2<Float> = side == "left" ? (c.first ?? SIMD2(0, rf.maxZ)) : side == "right" ? (c.count > 1 ? c[1] : SIMD2(0, rf.maxZ)) : SIMD2(0, rf.maxZ)
                care.selectBrain(0)?.requestNow(.goTo(spot))
            }
        }
        if d.object(forKey: "HUDHighlight") != nil {
            await sleep(4)
            care.tapJelly(d.integer(forKey: "HUDHighlight"))
        }
        if d.string(forKey: "HUDMenu") == "open" {
            await sleep(5)
            withAnimation(CareMenu.spring) { open.wrappedValue = true }
        }
        // capture aid: -MenuQuickGo <file> waits for that file, then opens the care menu, closes it and re-opens it 0.12 s / 0.25 s into the fold (the
        // host clock of each step goes to <file>.quick)
        if let go = d.string(forKey: "MenuQuickGo") {
            for _ in 0..<1200 where !FileManager.default.fileExists(atPath: go) { await sleep(0.1) }
            await sleep(6)
            func mark(_ what: String) {
                let line = "\(what) \(Date().timeIntervalSince1970)\n"
                if let h = FileHandle(forWritingAtPath: go + ".quick") ?? { FileManager.default.createFile(atPath: go + ".quick", contents: nil); return FileHandle(forWritingAtPath: go + ".quick") }() {
                    h.seekToEndOfFile(); h.write(Data(line.utf8)); try? h.close()
                }
            }
            for gap in [0.12, 0.25] {
                mark("open"); withAnimation(CareMenu.spring) { open.wrappedValue = true }; await sleep(2)
                mark("close"); withAnimation(CareMenu.spring) { open.wrappedValue = false }; await sleep(gap)
                mark("reopen_\(gap)"); withAnimation(CareMenu.spring) { open.wrappedValue = true }; await sleep(2)
                mark("final_close"); withAnimation(CareMenu.spring) { open.wrappedValue = false }; await sleep(2.5)
            }
        }
        if d.string(forKey: "HUDGoOut") == "open" {
            await sleep(5)
            withAnimation(.easeInOut(duration: 0.25)) { goOut.wrappedValue = .town }
        }
        // capture aid: -CafeAuto enter|order|refuse (the café outing after 4 s; order picks Pip swirl, Moss pancakes, Lavender sundae; refuse orders with 9 Drops)
        if let m = d.string(forKey: "CafeAuto") {
            await sleep(4)
            care.requestCafe()
            if m == "order" || m == "refuse" {
                for _ in 0..<300 where !care.cafe.menuOpen { await sleep(0.1) }
                await sleep(2)
                let ids = care.cafeDinerIDs
                if m == "refuse" {
                    care.bath.wallet.add(9 - care.bath.wallet.count, silent: true)
                    care.cafe.cardRefusal = care.orderCafe(CafeOrder(picks: Dictionary(uniqueKeysWithValues: ids.map { ($0, CafeTreatID.sundae) })))
                } else {
                    let menu: [CafeTreatID] = [.swirl, .pancakes, .sundae]
                    care.orderCafe(CafeOrder(picks: Dictionary(uniqueKeysWithValues: ids.enumerated().map { ($0.element, menu[$0.offset % 3]) })))
                }
            }
        }
        // capture aid: -GroomAuto picker|visit (the Jelly Spa picker after 4 s; visit also picks the Royal Pamper for everybody and goes, with 300 Drops)
        if let m = d.string(forKey: "GroomAuto") {
            await sleep(4)
            care.bath.wallet.add(max(0, 300 - care.bath.wallet.count), silent: true)
            care.bath.grime.dirt = 0.5
            care.requestGroom()
            if m == "visit" { await sleep(1.5); care.startGroom(.royal) }
        }
        // capture aid: -BlobGameDemo gclean runs Clean with scripted fake scrubs (starting from some dirt)
        if d.string(forKey: "BlobGameDemo") == "gclean" {
            await sleep(4)
            care.bath.grime.dirt = 0.5
            care.bath.demo = true
            care.bath.demoHold = d.integer(forKey: "BathHold") != 0          // -BathHold 1: stop at every complete stage (captures)
            care.clean()
        }
        if let a = d.string(forKey: "GameAction") {
            await sleep(d.double(forKey: "GameActionDelay") > 0 ? d.double(forKey: "GameActionDelay") : 4)
            switch a {
            case "feed": care.feed()
            case "water": care.water()
            case "feed:pizza": care.feed("pizza")
            case "drink:soda": care.drink("soda")
            case "feed:berries": care.feed("berries")
            case "drink:water": care.drink("water")
            case "call": care.call()
            case "callall": care.comeHereEveryone()
            case _ where a.hasPrefix("callids:"): care.beginFocus(ids: a.dropFirst(8).split(separator: ",").compactMap { Int($0) })          // -GameAction callids:1,2
            case "clean": care.clean()
            default: care.wave()
            }
            // capture aid: -GameReleaseAfter <s> presses "Let Bob go" that long after the action
            if d.double(forKey: "GameReleaseAfter") > 0 {
                for _ in 0..<600 where !care.focus.isFocused { await sleep(0.1) }
                await sleep(d.double(forKey: "GameReleaseAfter"))
                withAnimation(CareMenu.spring) { care.release() }
            }
        }
        // capture aid: -VoiceLearned 1 pre-learns his name and every trick; -VoiceSay "<words>" [-VoiceTeach <trick id>] simulates one hold after
        // ~2 s (the teach move starts first and runs for a second); -VoiceBook 1 opens the trick book after 2 s
        if d.integer(forKey: "VoiceLearned") != 0 { care.voice.debugLearnAll() }
        if d.object(forKey: "VoiceTutorialReps") != nil { care.voice.training.debugReps(.come, word: "come here", reps: d.integer(forKey: "VoiceTutorialReps")) }     // tutorial dots
        if let spec = d.string(forKey: "VoiceReps") {                       // -VoiceReps sit:3 = a half-learned "sit" with 3 reps
            let parts = spec.split(separator: ":")
            if parts.count == 2, let t = VoiceTrick(rawValue: String(parts[0])), let n = Int(parts[1]) { care.voice.training.debugReps(t, word: t.suggestion, reps: n) }
        }
        if d.integer(forKey: "VoiceBook") != 0 { await sleep(2); book.wrappedValue = true }
        // capture aid: -SpreadStart 1 sends Jellies 0, 1, 2 to the back-left, back-right and front-right corners and waits -SpreadWait s (default 9) before the rest of the script
        if d.integer(forKey: "SpreadStart") != 0 {
            await sleep(2)
            if let rf = GameCamera.roamFloor {
                let c = rf.extremeCorners
                for (i, k) in [2, 3, 1].enumerated() where c.indices.contains(k) { care.selectBrain(i)?.requestNow(.goTo(c[k])) }
            }
            await sleep(d.double(forKey: "SpreadWait") > 0 ? d.double(forKey: "SpreadWait") : 9)
        }
        if let words = d.string(forKey: "VoiceSay") {
            await sleep(d.double(forKey: "VoiceDelay") > 0 ? d.double(forKey: "VoiceDelay") : 2)
            await care.voice.simulate(words, teach: d.string(forKey: "VoiceTeach").flatMap(VoiceTrick.init(rawValue:)))
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

    /// What each Town screen plays: the Shop its own loop, the Studio / Condition / Show lobby the studio practice loop, the rest the town's.
    static func townMusic(_ t: TownScreen?) -> MusicScene {
        switch t {
        case nil: return .none
        case .shop?: return .shop
        case .studio?, .condition?, .show?: return .studio
        default: return .town
        }
    }
    /// Capture aid: `-StoreOpen town|shop|item|bag|studio|condition|show` opens that screen at launch; `-StoreSeed 1` fills the bag and the wallet first.
    static func launchTown() -> TownScreen? {
        switch UserDefaults.standard.string(forKey: "StoreOpen") {
        case "town": return .town
        case "shop", "item": return .shop
        case "track": return .track
        case "studio": return .studio
        case "condition": return .condition
        case "show": return .show
        default: return nil
        }
    }
    @MainActor static func runStoreDemo(model: MelonModel) async {
        let d = UserDefaults.standard
        // capture aid: -ShowSeedGoods 1 makes a cared-for Jelbie for the Jelly Show: fed to the day's theme, bathed, Sway half learned, the three trick pages
        // bought and every trick learned, the wardrobe owned and dressed to the theme
        if d.integer(forKey: "ShowSeedGoods") != 0 {
            let care = model.care
            let theme = ShowSchedule.theme(dayKey: GameCare.showDay)
            for id in ["page-spin", "page-hop", "page-roll"] { care.store.grant(id) }
            for l in WearLook.allCases { care.store.grant(StoreCatalog.item(wearing: l)?.id ?? "") }
            for j in care.jellies {
                j.training.unlocked = { t in care.store.hasPage(t) }
                for t in VoiceTrick.allCases { j.training.debugLearn(t, word: t.suggestion, reliability: t == .spin ? 0.6 : t == .roll ? 0.82 : 0.75) }
                for t in WearTag.allCases { j.stats.setCondition(t.condition, t == theme.main ? 0.71 : t == theme.friend ? 0.62 : 0.4) }
                j.stats.nudge([theme.main.condition: 0.08, theme.friend.condition: 0.04], food: "Sushi")
                j.stats.learn(.sway, add: 0.4)
                j.grime.sparkle = 0.6; j.grime.dirt = 0
            }
            let wear: [WearLook] = WearLook.allCases.filter { $0.tags.contains(theme.main) }
            var dressed: Set<WearSlot> = []
            for l in wear where !dressed.contains(l.slot) && l.slot != .face { care.store.wear(l, on: 0); dressed.insert(l.slot) }
            if !dressed.contains(.neck), let bow = WearLook.allCases.first(where: { $0.slot == .neck && $0.tags.contains(theme.friend) }) { care.store.wear(bow, on: 0) }
            care.bath.wallet.add(max(0, 106 - care.bath.wallet.count), silent: true)
        }
        guard d.integer(forKey: "StoreSeed") != 0 else { return }
        let care = model.care
        care.store.grantStarterIfNeeded()
        for (id, n) in [("sushi", 2), ("donut", 1), ("nuggets", 3), ("lavender", 1), ("fries", 1)] where care.store.count(id) < n { care.store.grant(id, n - care.store.count(id)) }
        care.store.grant("shoe-mint"); care.store.grant("shoe-rain")
        if care.bath.wallet.count < 60 { care.bath.wallet.add(60 - care.bath.wallet.count, silent: true) }
        care.jelly(0)?.perks.grant(.cozy); care.jelly(0)?.perks.grant(.zoomies, duration: 25 * 60)
        care.jelly(1)?.perks.grant(.fullBelly, duration: 3 * 3600 + 20 * 60)
        if d.string(forKey: "StoreWear") != nil { care.store.wear(.sneakerMint, on: 0) }
        // capture aid: -WearSeed 1 owns the whole wardrobe (and the medal); -WearSeed 2 also dresses Bob, Pip and Moss in three outfits
        if d.integer(forKey: "WearSeed") != 0 {
            for l in WearLook.allCases { care.store.grant(StoreCatalog.item(wearing: l)?.id ?? "") }
            care.store.awardMedal()
            care.bath.wallet.add(max(0, 400 - care.bath.wallet.count), silent: true)
            if d.integer(forKey: "WearSeed") == 2 {
                let o: [[WearLook]] = [[.capTeamPink, .bibPink, .glovePink, .sneakerCoral], [.flowerCrown, .bowtieSky, .glitterShoes], [.crownGold, .pearls, .tutuPink, .balletPink]]
                for (i, ls) in o.enumerated() { for l in ls { care.store.wear(l, on: i) } }
            }
        }
        // capture aid: -StoreDecor 1 owns one of every decor piece (a second beanbag) and puts the first few in the room; -StoreDecor 2 fills the room (10 spots)
        if d.integer(forKey: "StoreDecor") != 0 {
            for k in DecorKind.allCases { care.store.grant(k.storeID) }
            care.store.grant(DecorKind.beanbag.storeID)
            care.bath.wallet.add(max(0, 120 - care.bath.wallet.count), silent: true)
            if care.store.placedDecor.isEmpty {
                let order: [DecorKind] = d.integer(forKey: "StoreDecor") == 2 ? DecorTuning.fullRoom : [.beanbag, .plant, .ball]
                for k in order { _ = care.store.place(k.storeID) }
            }
            if d.integer(forKey: "DoubleTapDemo") != 0 {          // capture aid: a double tap on the first piece (the demo drag follows in Store/DecorUI.swift)
                try? await Task.sleep(nanoseconds: UInt64((d.double(forKey: "DoubleTapDelay") > 0 ? d.double(forKey: "DoubleTapDelay") : 20) * 1e9))
                if let uid = care.store.placedDecor.first?.uid { care.pickUpDecor(uid) }
            }
            if d.integer(forKey: "ArrangeDemo") != 0 { try? await Task.sleep(nanoseconds: 1_000_000_000); care.beginArrange(care.store.placedDecor.first?.uid) }          // arrange mode with the demo drag (Store/DecorUI.swift)
        }
    }

    static func makeGameModel(jellyCount: Int = JellyRoster.launchCount()) -> MelonModel {
        LaunchTiming.mark("room build begins")
        let m = LaunchTiming.span("MelonModel") { MelonModel(jellyCount: jellyCount) }
        m.gameMode = true
        m.palette = .blue   // user 2026-10-16: pink is too close to Kirby; model default stays .blush (BaseBody lock)
        return m
    }
}

/// Small matte cream circle with an SF Symbol.
struct GameCircleButton: View {
    let systemName: String
    let label: String
    var size: CGFloat = 44
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: size > 44 ? 23 : 20, weight: .semibold))
                .foregroundStyle(Color(red: 0.42, green: 0.34, blue: 0.30))
                .frame(width: size, height: size)          // 44 pt minimum hit target
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .hudFrost(in: .circle)          // Liquid Glass (iOS 26)
        .accessibilityLabel(label)
        .accessibilityShowsLargeContentViewer { Label(label, systemImage: systemName) }
    }
}

// MARK: - Care menu

/// The one main HUD control (side of the screen): the paw expands upward into the GROUP controls (nobody highlighted) or into the highlighted
/// Jelbie's INDIVIDUAL controls (HUDControls.swift decides the rows and what they do).
struct CareMenu: View {
    @Binding var open: Bool
    let care: GameCare
    /// A thought bubble tap asks for a picker to be unfolded (Feed or Drink).
    @Binding var openPicker: ConsumableKind?
    /// Dress / Play / Decor ask the screen for the Bag on a tab; Compete asks for the Track / Show screens.
    var openBag: (BagSheet.BagTab, Int) -> Void = { _, _ in }
    var openTown: (TownScreen, Int) -> Void = { _, _ in }

    static let spring = Animation.spring(response: 0.42, dampingFraction: 0.72)
    /// Closing folds the rows back into the heart: quick, no overshoot (the spring above bounces, which threw the leaving rows sideways).
    static let foldOut = Animation.easeIn(duration: 0.2)
    static let cream = Color(red: 0.97, green: 0.94, blue: 0.88)
    static let brown = Color(red: 0.42, green: 0.34, blue: 0.30)

    /// "waterbottle.fill" exists on the deployment target (iOS 26); keep the drop as a fallback.
    static let waterSymbol = UIImage(systemName: "waterbottle.fill") != nil ? "waterbottle.fill" : "drop.fill"
    static let cleanSymbol = UIImage(systemName: "bubbles.and.sparkles") != nil ? "bubbles.and.sparkles" : "sparkles"
    static let raceSymbol = UIImage(systemName: "flag.checkered") != nil ? "flag.checkered" : "flag.fill"

    private var mode: HUDMode { frozenMode ?? HUDMenu.mode(care) }
    /// The mode a tapped row ran in, held while the menu closes: Come here / Clean clear the highlight, and the rows must not flip to the group labels mid-fade.
    @State private var frozenMode: HUDMode?

    /// The rows' natural size (they scroll when the screen is too short).
    @State private var careNatural: CGSize?
    /// Which picker is unfolded under its row: Feed (berries, pizza) and Drink (water, soda), each as two chips.
    @State private var picker: ConsumableKind?
    /// The Snacks picker (store foods in the bag, with counts) is unfolded.
    @State private var snackPicker = false
    /// Compete is unfolded into its two chips (Track / Jelly Show).
    @State private var competeRow = false
    @Environment(\.verticalSizeClass) private var vsc
    @Environment(\.dynamicTypeSize) private var dts
    @Environment(\.accessibilityReduceMotion) private var reduceMotionEnv
    @AccessibilityFocusState private var focusedRow: HUDItem?
    private var calm: Bool { reduceMotionEnv || A11ySettings.shared.reduceMotion }
    private var tight: Bool { vsc == .compact }          // a phone on its side: only ~400 pt of height, so the rows shrink
    private var iconSize: CGFloat { tight ? 44 : 54 }
    private var rowGap: CGFloat { tight ? 5 : 14 }

    var body: some View {
        let items = HUDMenu.items(mode)
        CareScroller(natural: $careNatural, reserved: tight ? 58 : 72) {
            VStack(alignment: .trailing, spacing: rowGap) {
                if open {
                    ForEach(Array(items.enumerated()), id: \.element.rawValue) { index, item in
                        row(item, count: items.count, index: index)
                        if picker == .food, item == .feed { pickerRow(Consumables.foods, kind: .food) }
                        if picker == .drink, item == .drink { pickerRow(care.drinkChoices, kind: .drink) }
                        if snackPicker, item == .snacks { snackRow }
                        if competeRow, item == .compete { competeChips }
                    }
                }
            }
            .padding(.bottom, open ? rowGap : 0)          // the gap between the rows and the paw (the paw is outside the scroll)
        } footer: {
            mainButton
        }
        .onChange(of: open) { _, isOpen in
            if !isOpen { picker = nil; snackPicker = false; competeRow = false }
            else if UIAccessibility.isVoiceOverRunning { DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { focusedRow = HUDMenu.items(mode).first } }      // focus moves into the opened rows
        }
        .onChange(of: care.select.highlighted) { _, _ in withAnimation(Self.spring) { picker = nil; snackPicker = false; competeRow = false } }
        .onChange(of: openPicker) { _, k in
            guard let k else { return }
            openPicker = nil
            if case .individual = mode {          // Feed / Drink live in the group menu: drop the highlight, then unfold the picker there (after the highlight's own reset)
                care.clearHighlight()
                DispatchQueue.main.async { withAnimation(Self.spring) { open = true; picker = k } }
                return
            }
            withAnimation(Self.spring) { open = true; picker = k }
        }
    }

    /// A chip of an unfolded row: springs out in order, folds back (scale + fade toward the row) quickly with no bounce. Reduce Motion: fade only.
    private func chipTransition(_ i: Int) -> AnyTransition {
        if calm { return .opacity }
        return .asymmetric(insertion: .scale(scale: 0.3, anchor: .trailing).combined(with: .opacity).animation(Self.spring.delay(Double(i) * 0.05)),
                           removal: .scale(scale: 0.3, anchor: .trailing).combined(with: .opacity).animation(Self.foldOut))
    }

    /// A tiny row of the catalogue's items in the same cream style; tapping one starts it and closes the menu.
    private func pickerRow(_ list: [Consumable], kind: ConsumableKind) -> some View {
        ViewThatFits(in: .horizontal) {
            pickerChips(list, kind: kind)
            ScrollView(.horizontal, showsIndicators: false) { pickerChips(list, kind: kind) }          // water, soda and four bought drinks do not fit one line
        }
    }
    private func pickerChips(_ list: [Consumable], kind: ConsumableKind) -> some View {
        HStack(spacing: 10) {
            ForEach(Array(list.enumerated()), id: \.element.id) { i, c in
                Button {
                    UIImpactFeedbackGenerator(style: .soft).impactOccurred(); AudioHub.shared.uiTap()
                    if kind == .food { care.feed(c.id, jelly: care.singledOutForFood) } else { care.drink(c.id, jelly: care.singledOutForFood) }
                    withAnimation(Self.spring) { picker = nil; open = false }
                } label: {
                    VStack(spacing: 3) {
                        if c.stored, let it = StoreCatalog.item(forFood: c.id) {
                            ItemArt(item: it, size: tight ? 44 : 46)          // a bought drink shows its own cup
                                .background(Circle().fill(Self.cream).shadow(color: Color(red: 0.3, green: 0.2, blue: 0.12).opacity(0.2), radius: 6, y: 2))
                        } else {
                        Image(systemName: UIImage(systemName: c.symbol) != nil ? c.symbol : "drop.fill")
                            .font(.system(size: 19, weight: .semibold))
                            .foregroundStyle(Self.brown)
                            .frame(width: tight ? 44 : 46, height: tight ? 44 : 46)
                            .background(Circle().fill(Self.cream).shadow(color: Color(red: 0.3, green: 0.2, blue: 0.12).opacity(0.2), radius: 6, y: 2))
                            .overlay(Circle().strokeBorder(Color.white.opacity(0.5), lineWidth: 1))
                        }
                        Text(c.name)
                            .jFont(12, .semibold)
                            .foregroundStyle(Self.brown)
                            .padding(.horizontal, 8).padding(.vertical, 2)
                            .background(Capsule().fill(Self.cream))
                    }
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("care-\(kind == .food ? "food" : "drink")-\(c.id)")
                .accessibilityLabel(c.name)
                .transition(chipTransition(i))
            }
        }
        .padding(.trailing, 8)
    }

    /// The snacks in the bag as chips (3D thumbnail, count); tapping one feeds the selected Jelly (or everybody with nobody singled out).
    private var snackRow: some View {
        let list = care.store.snacks
        return HStack(spacing: 10) {
            if list.isEmpty {
                Text("None yet. Visit the Shop!").jFont(13, .semibold).foregroundStyle(Self.brown)
                    .padding(.horizontal, 12).padding(.vertical, 8).background(Capsule().fill(Self.cream))
            }
            ForEach(Array(list.prefix(4).enumerated()), id: \.element.item.id) { i, s in
                Button {
                    UIImpactFeedbackGenerator(style: .soft).impactOccurred(); AudioHub.shared.uiTap()
                    care.feedSnack(s.item.id, jelly: care.singledOutForFood)
                    withAnimation(Self.spring) { snackPicker = false; open = false }
                } label: {
                    VStack(spacing: 3) {
                        ItemArt(item: s.item, size: 50).overlay(alignment: .topTrailing) {
                            Text("\(s.count)").jFont(11, .black).foregroundStyle(.white)
                                .frame(minWidth: 18, minHeight: 18).background(Circle().fill(FocusStyle.pink)).offset(x: 5, y: -5)
                        }
                        Text(s.item.name).jFont(11, .semibold).foregroundStyle(Self.brown).lineLimit(1)
                            .padding(.horizontal, 6).padding(.vertical, 2).background(Capsule().fill(Self.cream))
                    }
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("care-snack-\(s.item.id)").accessibilityLabel("\(s.item.name), \(s.count) left")
                .transition(chipTransition(i))
            }
        }
        .padding(.trailing, 8)
    }

    /// Compete unfolds into Track (train or race) and Jelly Show, for the highlighted Jelbie.
    private var competeChips: some View {
        let id: Int = { if case .individual(let n) = mode { return n }; return care.targetJelly }()
        let opts: [(String, String, TownScreen, Bool, String)] = [("Track", Self.raceSymbol, .track, care.canRace(jelly: id), "hud-compete-track"),
                                                                    ("Jelly Show", "sparkles", .show, care.canShow(jelly: id), "hud-compete-show"),
                                                                    ("Volleyball", UIImage(systemName: "figure.volleyball") != nil ? "figure.volleyball" : "sportscourt.fill", .volley, care.canVolley(jelly: id), "hud-compete-volley")]
        return HStack(spacing: 10) {
            ForEach(Array(opts.enumerated()), id: \.offset) { i, o in
                Button {
                    UIImpactFeedbackGenerator(style: .soft).impactOccurred(); AudioHub.shared.uiTap()
                    if case .town(let t, let who) = HUDMenu.compete(o.2, id: id) { openTown(t, who) }
                    withAnimation(Self.spring) { competeRow = false; open = false }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: o.1).font(.system(size: 15, weight: .semibold))
                        Text(o.0).jFont(15, .semibold)
                    }
                    .foregroundStyle(Self.brown)
                    .padding(.horizontal, 14).frame(minHeight: 44)
                    .background(Capsule().fill(Self.cream).shadow(color: Color(red: 0.3, green: 0.2, blue: 0.12).opacity(0.2), radius: 6, y: 2))
                    .overlay(Capsule().strokeBorder(Color.white.opacity(0.5), lineWidth: 1))
                    .opacity(o.3 ? 1 : 0.45)
                }
                .buttonStyle(.plain).disabled(!o.3)
                .accessibilityIdentifier(o.4).accessibilityLabel(o.0)
                .transition(chipTransition(i))
            }
        }
        .padding(.trailing, 8)
    }

    private func tap(_ item: HUDItem) {
        frozenMode = mode
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { frozenMode = nil }
        let route = HUDMenu.perform(item, mode, care: care)
        switch route {
        case .picker(let k):
            if k == .food { withAnimation(Self.spring) { picker = picker == .food ? nil : .food; snackPicker = false; competeRow = false }; return }
            if care.drinkChoices.count >= 2 { withAnimation(Self.spring) { picker = picker == .drink ? nil : .drink; snackPicker = false; competeRow = false }; return }
            care.drink(care.drinkChoices.first?.id ?? "water", jelly: care.singledOutJelly)         // one drink: starts directly (nobody singled out = the group serving)
        case .snacks: withAnimation(Self.spring) { snackPicker.toggle(); picker = nil; competeRow = false }; return
        case .competeChips: withAnimation(Self.spring) { competeRow.toggle(); picker = nil; snackPicker = false }; return
        case .bag(let tab, let who): openBag(tab, who)
        case .town(let t, let who): openTown(t, who)
        case .none: break
        }
        withAnimation(Self.spring) { open = false }
    }

    private func row(_ item: HUDItem, count: Int, index: Int) -> some View {
        let fromBottom = count - 1 - index          // 0 = nearest the main button
        let on = HUDMenu.enabled(item, mode, care: care)
        let title = HUDMenu.title(item, mode, care: care)
        let reason = HUDMenu.disabledReason(item, mode, care: care)
        return Button {
            UIImpactFeedbackGenerator(style: .soft).impactOccurred(); AudioHub.shared.uiTap()
            tap(item)
        } label: {
            HStack(spacing: 10) {
                Text(title)
                    .jFont(16, .semibold)
                    .foregroundStyle(Self.brown)
                    .padding(.horizontal, 15).padding(.vertical, tight ? 5 : 8)
                    .background(Capsule().fill(Self.cream).shadow(color: Color(red: 0.3, green: 0.2, blue: 0.12).opacity(0.18), radius: 6, y: 2))
                Image(systemName: HUDMenu.symbol(item))
                    .font(.system(size: tight ? 17 : 21, weight: .semibold))
                    .foregroundStyle(Self.brown)
                    .frame(width: iconSize, height: iconSize)
                    .background(Circle().fill(Self.cream).shadow(color: Color(red: 0.3, green: 0.2, blue: 0.12).opacity(0.22), radius: 7, y: 3))
                    .overlay(Circle().strokeBorder(Color.white.opacity(0.5), lineWidth: 1))
            }
            .opacity(on ? 1 : 0.45)
        }
        .buttonStyle(.plain)
        .disabled(!on)
        .accessibilityIdentifier(item.rawValue)
        .accessibilityLabel(HUDMenu.spokenLabel(item, mode, care: care))
        .accessibilityHint(reason ?? "")
        .accessibilityFocused($focusedRow, equals: item)
        .transition(calm ? .opacity : .asymmetric(
            insertion: .scale(scale: 0.3, anchor: .bottomTrailing).combined(with: .opacity)
                .combined(with: .offset(y: 24 + CGFloat(fromBottom) * 10))
                .animation(Self.spring.delay(Double(fromBottom) * 0.05)),
            // mirrors opening: the top row goes first and every row folds down into the heart (a row's distance to it = the rows below it + the gap)
            removal: .scale(scale: 0.3, anchor: .bottomTrailing).combined(with: .opacity)
                .combined(with: .offset(y: CGFloat(fromBottom + 1) * (iconSize + rowGap)))
                .animation(Self.foldOut.delay(Double(index) * 0.02))))
    }

    /// The Jelbie's name capsule (individual mode), left of the paw. The cross lets go of the highlight.
    @ViewBuilder private var nameCapsule: some View {
        if case .individual(let id) = mode, let name = care.jelly(id)?.name {
            HStack(spacing: 6) {
                Text(name).jFont(15, .bold).foregroundStyle(Self.brown)
                    .accessibilityIdentifier("hud-name")
                Button {
                    UIImpactFeedbackGenerator(style: .soft).impactOccurred(); AudioHub.shared.uiTap()
                    withAnimation(Self.spring) { care.clearHighlight() }
                } label: {
                    Image(systemName: "xmark.circle.fill").font(.system(size: 18)).foregroundStyle(Self.brown.opacity(0.6))
                        .frame(width: 44, height: 44).contentShape(Rectangle())
                }
                .buttonStyle(.plain).accessibilityIdentifier("hud-clear").accessibilityLabel("Let go of \(name)")
            }
            .padding(.leading, 14).padding(.trailing, 0).frame(minHeight: 44)
            .background(Capsule().fill(Self.cream).shadow(color: Color(red: 0.3, green: 0.2, blue: 0.12).opacity(0.22), radius: 7, y: 3))
            .overlay(Capsule().strokeBorder(Color.white.opacity(0.5), lineWidth: 1))
            .transition(.scale(scale: 0.6, anchor: .trailing).combined(with: .opacity))
        }
    }

    private var mainButton: some View {
        var ring: Color? = nil
        var who: String? = nil
        if case .individual(let id) = mode, let j = care.jelly(id) {
            let t = JellyRoster.tint(j.character)
            ring = Color(red: Double(t.x), green: Double(t.y), blue: Double(t.z)); who = j.name
        }
        return HStack(spacing: 8) {
            nameCapsule
            Button {
                UIImpactFeedbackGenerator(style: .soft).impactOccurred(); AudioHub.shared.uiTap()
                withAnimation(Self.spring) { open.toggle() }
            } label: {
                ZStack {
                    Image(systemName: "heart.fill")
                        .font(.system(size: 29, weight: .semibold))
                        .opacity(open ? 0 : 1)
                        .rotationEffect(.degrees(open ? 90 : 0))
                        .scaleEffect(open ? 0.4 : 1)
                    Image(systemName: "xmark")
                        .font(.system(size: 24, weight: .bold))
                        .opacity(open ? 1 : 0)
                        .rotationEffect(.degrees(open ? 0 : -90))
                        .scaleEffect(open ? 1 : 0.4)
                }
                .foregroundStyle(Color.white)
                .frame(width: tight ? 58 : 72, height: tight ? 58 : 72)
                .contentShape(Circle())
                .overlay { if let ring { Circle().strokeBorder(ring, lineWidth: 3) } }
            }
            .buttonStyle(.plain)
            .glassEffect(HUDGlass.pink, in: .circle)
            .accessibilityIdentifier("care-menu")
            .accessibilityLabel(who.map { open ? "Close \($0)'s menu" : "\($0)'s menu" } ?? (open ? "Close care menu" : "Care menu"))
            .accessibilityValue(open ? "expanded" : "collapsed")
            .accessibilityHint(who.map { "Shows care actions for \($0)" } ?? "Shows care actions for everyone")
            .accessibilityAction(.escape) { withAnimation(Self.spring) { open = false } }
            .accessibilityShowsLargeContentViewer { Label(who.map { "\($0)'s menu" } ?? "Care menu", systemImage: "heart.fill") }
            .keyboardShortcut("p", modifiers: .command)
        }
        .animation(Self.spring, value: who)
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
    var name: String? = nil          // the Jelbie in the close-up (nil = more than one: "them")
    let action: () -> Void
    var title: String { name.map { "Let \($0) go" } ?? "Let them go" }
    var body: some View {
        Button {
            UIImpactFeedbackGenerator(style: .soft).impactOccurred(); AudioHub.shared.uiTap()
            action()
        } label: {
            HStack(spacing: 7) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 13, weight: .bold))
                Text(title)
                    .jFont(16, .semibold)
            }
            .foregroundStyle(FocusStyle.brown)
            .padding(.horizontal, 16).padding(.vertical, 10).frame(minHeight: 44)
        }
        .buttonStyle(.plain)
        .hudFrost(in: .capsule)
        .accessibilityIdentifier("focus-release")
        .accessibilityLabel(title)
        .accessibilityHint("Goes back to the room")
        .keyboardShortcut(.escape, modifiers: [])
    }
}

/// The first-time hint in focus mode: "Rub to pet · double-tap & hold to pick up · flick to throw". Shown for the first few visits only, fades after 4 s.
struct FocusHint: View {
    static let key = "FocusHintSeen"
    @State private var shown = UserDefaults.standard.integer(forKey: FocusHint.key) < 3 || UIAccessibility.isVoiceOverRunning
    @State private var visible = true
    /// True once the player has touched the Jelbie or used the mic (polled while the hint is sticky).
    var interacted: () -> Bool = { false }
    /// The VoiceOver wording names the pet / pat / toss rotor actions; flip to true when they exist (Accessibility part B).
    static var petActionsInRotor = false
    /// With VoiceOver on, or "Longer hints" set, the hint stays until the first interaction instead of fading at 3.5 s.
    private var sticky: Bool { A11ySettings.shared.longerHints || UIAccessibility.isVoiceOverRunning }
    private var text: String {
        UIAccessibility.isVoiceOverRunning && Self.petActionsInRotor ? "Use the Actions rotor on a Jelbie to pet, pat or toss" : "Rub to pet · double-tap & hold to pick up · flick to throw"
    }

    var body: some View {
        if shown {
            Text(text)
                .jFont(15, .semibold)
                .foregroundStyle(FocusStyle.brown)
                .padding(.horizontal, 18).padding(.vertical, 10)
                .background(Capsule().fill(FocusStyle.cream).shadow(color: FocusStyle.shadow.opacity(0.2), radius: 7, y: 3))
                .overlay(Capsule().strokeBorder(Color.white.opacity(0.6), lineWidth: 1))
                .opacity(visible ? 1 : 0)
                .allowsHitTesting(false)
                .accessibilityIdentifier("focus-hint")
                .task {
                    UserDefaults.standard.set(UserDefaults.standard.integer(forKey: FocusHint.key) + 1, forKey: FocusHint.key)
                    if sticky {          // stays until the first touch or mic use (or 60 s, so it never lingers for good)
                        var waited = 0.0
                        while !Task.isCancelled, waited < 60, !interacted() { try? await Task.sleep(nanoseconds: 250_000_000); waited += 0.25 }
                    } else {
                        try? await Task.sleep(nanoseconds: 3_500_000_000)
                    }
                    withAnimation(.easeOut(duration: 0.5)) { visible = false }
                }
        }
    }
}

/// An icon button inside a shared glass capsule (no disc of its own): 44 pt wide x 44 pt tall hit target.
struct HUDGlassIcon: View {
    let systemName: String
    let label: String
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 21, weight: .semibold))
                .foregroundStyle(CareMenu.brown)
                .frame(width: 48, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityShowsLargeContentViewer { Label(label, systemImage: systemName) }
    }
}
