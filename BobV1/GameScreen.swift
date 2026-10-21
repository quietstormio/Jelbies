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
    @State private var extrasOpen = false                     // Siri & Lock Screen panel (Live Activity toggles, Siri tip)
    /// Every way into the game (widget links, Siri, the App Group queue) lands here; `apply` runs the routes on the care flows.
    private let router = GameRouter.shared
    private var jellyNames: [String] { model.care.jellies.map(\.name) }
    @State private var openPicker: ConsumableKind?
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.verticalSizeClass) private var vsc          // .compact = a phone on its side
    private var focus: BlobFocus { model.care.focus }
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

            // dim scrim behind the care menu; a tap anywhere outside collapses it
            Color(red: 0.30, green: 0.20, blue: 0.14)
                .opacity(menuOpen ? 0.22 : 0)
                .ignoresSafeArea()
                .allowsHitTesting(menuOpen)
                .onTapGesture { withAnimation(CareMenu.spring) { menuOpen = false } }
                .animation(.easeInOut(duration: 0.25), value: menuOpen)

            TouchHeartsView(play: model.touch, care: model.care)

            SelectionOverlay(select: model.care.select)

            VoiceGlow(voice: model.care.voice, care: model.care)
            VoiceFeedbackView(voice: model.care.voice, care: model.care)

            GreetHeartsView(care: model.care)          // Pip's and Moss's greeting hearts

            ThoughtBubbleView(care: model.care) { action in
                switch action {
                case .feed: withAnimation(CareMenu.spring) { menuOpen = true; openPicker = .food }
                case .drink: withAnimation(CareMenu.spring) { menuOpen = true; openPicker = .drink }
                case .comeHere, .clean: break            // GameCare.tapBubble already called him / started the clean-up
                }
            }

            RefusalLabel(care: model.care)

            // HUD
            ZStack {
                VStack {
                    HStack {
                        if focus.showsRelease {
                            ReleaseButton { withAnimation(CareMenu.spring) { model.care.release() } }
                                .transition(.move(edge: .leading).combined(with: .opacity))
                            GameCircleButton(systemName: "rectangle.portrait.on.rectangle.portrait.angled", label: "Condition card") {
                                AudioHub.shared.uiTap(); withAnimation(.easeInOut(duration: 0.25)) { town = .condition }
                            }
                            .accessibilityIdentifier("focus-card")
                            .transition(.opacity)
                        } else if !focus.isActive, !cleaning, !racing {
                            GameCircleButton(systemName: "gearshape", label: "Studio") {
                                model.paused = true
                                showStudio = true
                            }
                            .accessibilityIdentifier("studio-button")
                            .transition(.opacity)
                            GameCircleButton(systemName: soundOpen ? "speaker.wave.2.fill" : "speaker.wave.2", label: "Sound") {
                                AudioHub.shared.uiTap()
                                withAnimation(CareMenu.spring) { soundOpen.toggle(); if soundOpen { extrasOpen = false } }
                            }
                            .accessibilityIdentifier("sound-button")
                            .transition(.opacity)
                            EarsButton(ears: Ears.shared)                  // "Ears on" (Audio/EarsHUD.swift)
                                .transition(.opacity)
                            GameCircleButton(systemName: extrasOpen ? "sparkles.rectangle.stack.fill" : "sparkles.rectangle.stack", label: "Siri and Lock Screen") {
                                AudioHub.shared.uiTap()
                                withAnimation(CareMenu.spring) { extrasOpen.toggle(); if extrasOpen { soundOpen = false } }
                            }
                            .accessibilityIdentifier("extras-button")
                            .transition(.opacity)
                        }
                        Spacer()
                        if !focus.isActive, !cleaning, !racing {
                            HStack(spacing: 8) {
                                DropsPill(wallet: model.care.bath.wallet)
                                RosterButton(care: model.care, open: $rosterOpen)
                            }
                            .transition(.opacity)
                        }
                    }
                    if !focus.isActive, !cleaning, !racing {
                        HStack { Spacer(); PerkBadgeRow(care: model.care) }
                    }
                    Spacer()
                    if focus.showsDock {
                        FocusHint()                       // no tabs: the gesture decides; a first-time hint that fades after 4 s
                            .padding(.bottom, 18)
                            .transition(.opacity)
                    }
                    if !cleaning, !racing { HStack(alignment: .bottom, spacing: 10) {
                        VoiceMicButton(voice: model.care.voice, openBook: { bookOpen = true }, pulse: model.care.voice.tutorial.isShown && model.care.voice.tutorial.pulsingMic)
                            .overlay(alignment: .topLeading) {
                                VoiceTip(voice: model.care.voice).fixedSize().offset(y: -86)
                            }
                        VStack(spacing: 6) {
                            VoiceBookButton { bookOpen = true }
                            if !focus.isActive { BagButton(store: model.care.store) { bagOpen = true } }
                        }
                        .padding(.bottom, focus.isActive ? 4 : 0)
                        Spacer()
                        if !focus.isActive { careSlot.transition(.scale(scale: 0.5, anchor: .bottomTrailing).combined(with: .opacity)) }
                    }
                    .overlay(alignment: .bottom) {
                        if !focus.isActive, !model.care.trayOut, !model.care.arranging, !model.care.select.isSelecting, !model.care.select.chipVisible {          // (hidden while a Jelly is picked / the "Play with ...?" chip is up: they share the bottom centre)
                            GoOutPill { withAnimation(.easeInOut(duration: 0.25)) { town = .town } }.padding(.bottom, 10)
                        }
                    } }
                }
                .animation(CareMenu.spring, value: focus.phase)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }

            BathChrome(care: model.care)

            RaceChrome(care: model.care)          // Jelly Circuit: numerals, foot buttons, placings card, the white fade

            ShowChrome(care: model.care)          // Jelly Show: the Look / Dance / Trick rounds and the results on the stage, the white fade

            if model.care.arranging { ArrangeOverlay(care: model.care) }          // decor: drag the room's pieces about

            if town != nil {                     // Go out: Town / Shop / Track
                TownFlow(care: model.care, screen: $town, who: model.care.targetJelly) { withAnimation(.easeInOut(duration: 0.25)) { town = nil } }
                    .transition(.opacity)
            }

            // (the come-here tutorial card is retired: he knows "come here" from the start)

            RosterPanel(care: model.care, open: $rosterOpen) { id in model.care.rosterPick(id) }
                .padding(.top, 8)

            if soundOpen {
                SoundSettingsPanel(hub: AudioHub.shared) { withAnimation(CareMenu.spring) { soundOpen = false } }
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
            setUpSelect(); model.care.touchPlay = model.touch; model.care.launched()
            model.care.store.grantStarterIfNeeded()          // first open: the starter Drops, once
            AudioHub.shared.start()
            AudioHub.shared.setTownScene(GameScreen.townMusic(town))
            Ears.shared.launch(care: model.care)
            if let left = DayClock.shared.takeLeft() { DayClock.shared.returned(from: left) }        // cold launch after > 1 h: the time-lapse from when he left
            LiveActivities.shared.cleanUp(names: jellyNames)                                           // orphans from a killed run; adopt a live nap / Pep card
            let care = model.care
            let toTrack: (Int) -> Void = { id in                 // Siri "race" / "train": the Track panel for that Jelbie (its Race / Train buttons), like the voice command
                guard !care.raceBusy, !care.focus.isActive, !care.arranging, !care.bath.active, !care.trayOut else { care.openJelly(id); return }
                care.rosterPick(id, quietHop: true); care.requestTown(.track)
            }
            router.onRace = toTrack; router.onTrain = toTrack
            router.onBed = { care.goodnight() }                 // Siri "goodnight": the voice goodnight flow (every Jelbie to bed)
            router.apply(care: model.care)                                                             // a Siri route that launched the app cold
            JelbiesShortcuts.updateAppShortcutParameters()                                             // Siri learns the Jelbies' names for "Feed Pip in Bob"
        }
        .onOpenURL { url in _ = router.handle(url) }          // widget / Live Activity tap: jelbies://jelly|feed|water|bed|race|train|pet
        .onChange(of: router.serial) { _, _ in router.apply(care: model.care) }                       // Siri in-process, a drained queue
        .onChange(of: scenePhase) { _, p in
            if p == .active {
                model.care.returnedActive()          // time away: needs, dirt, sparkle (once per return) + the greeting
                AudioHub.shared.setForeground(true)
                Ears.shared.setForeground(true)
                if let left = DayClock.shared.takeLeft() { DayClock.shared.returned(from: left) }      // away > 1 h: sweep the window light from then to now
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
        .onChange(of: town) { _, t in model.paused = t != nil; AudioHub.shared.setTownScene(GameScreen.townMusic(t)) }
        .onChange(of: bagOpen) { _, on in model.care.select.sheetOpen = on || rosterOpen || bookOpen }
        .sheet(isPresented: $bagOpen) {
            BagSheet(care: model.care, who: model.care.targetJelly) { bagOpen = false }
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
        .task { await GameScreen.runDebugScript(model: model, open: $menuOpen, roster: $rosterOpen, picker: $openPicker, book: $bookOpen) }   // on the root: the HUD's pieces come and go with focus mode
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

    /// Harmless launch args for captures: -GameAction feed|feed:pizza|water|drink:soda|call|wave (after 4 s), -GameScript 1 (timed demo of everything).
    @MainActor static func runDebugScript(model: MelonModel, open: Binding<Bool>, roster: Binding<Bool>, picker: Binding<ConsumableKind?>, book: Binding<Bool> = .constant(false)) async {
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
        // capture aid: -BlobGameDemo gclean runs Clean with scripted fake scrubs (starting from some dirt)
        if d.string(forKey: "BlobGameDemo") == "gclean" {
            await sleep(4)
            care.bath.grime.dirt = 0.5
            care.bath.demo = true
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
        let m = MelonModel(jellyCount: jellyCount)
        m.gameMode = true
        m.palette = .blue   // user 2026-10-16: pink is too close to Kirby; model default stays .blush (BaseBody lock)
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
    static let cleanSymbol = UIImage(systemName: "bubbles.and.sparkles") != nil ? "bubbles.and.sparkles" : "sparkles"
    static let raceSymbol = UIImage(systemName: "flag.checkered") != nil ? "flag.checkered" : "flag.fill"
    // top to bottom
    private let items = [Item(id: "care-feed", title: "Feed", symbol: "fork.knife"),
                         Item(id: "care-snacks", title: "Snacks", symbol: "bag.fill"),
                         Item(id: "care-water", title: "Drink", symbol: CareMenu.waterSymbol),
                         Item(id: "care-call", title: "Come here", symbol: "hand.wave.fill"),
                         Item(id: "care-clean", title: "Clean", symbol: CareMenu.cleanSymbol),
                         Item(id: "care-race", title: "Race", symbol: CareMenu.raceSymbol)]

    /// Which picker is unfolded under its row: Feed (berries, pizza) and Drink (water, soda), each as two chips.
    @State private var picker: ConsumableKind?
    /// The Snacks picker (store foods in the bag, with counts) is unfolded.
    @State private var snackPicker = false
    @Environment(\.verticalSizeClass) private var vsc
    private var tight: Bool { vsc == .compact }          // a phone on its side: only ~400 pt of height, so the rows shrink
    private var iconSize: CGFloat { tight ? 40 : 54 }
    private var rowGap: CGFloat { tight ? 5 : 14 }

    var body: some View {
        VStack(alignment: .trailing, spacing: rowGap) {
            if open {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    row(item, index: index)
                    if picker == .food, item.id == "care-feed" { pickerRow(Consumables.foods, kind: .food) }
                    if picker == .drink, item.id == "care-water" { pickerRow(Consumables.drinks, kind: .drink) }
                    if snackPicker, item.id == "care-snacks" { snackRow }
                }
            }
            mainButton
        }
        .onChange(of: open) { _, isOpen in if !isOpen { picker = nil; snackPicker = false } }
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
                    UIImpactFeedbackGenerator(style: .soft).impactOccurred(); AudioHub.shared.uiTap()
                    if kind == .food { care.feed(c.id, jelly: care.singledOutJelly) } else { care.drink(c.id, jelly: care.singledOutJelly) }
                    withAnimation(Self.spring) { picker = nil; open = false }
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: UIImage(systemName: c.symbol) != nil ? c.symbol : "drop.fill")
                            .font(.system(size: 19, weight: .semibold))
                            .foregroundStyle(Self.brown)
                            .frame(width: tight ? 38 : 46, height: tight ? 38 : 46)
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

    /// The snacks in the bag as chips (3D thumbnail, count); tapping one feeds the selected Jelly (or everybody with nobody singled out).
    private var snackRow: some View {
        let list = care.store.snacks
        return HStack(spacing: 10) {
            if list.isEmpty {
                Text("None yet. Visit the Shop!").font(.system(size: 13, weight: .semibold, design: .rounded)).foregroundStyle(Self.brown)
                    .padding(.horizontal, 12).padding(.vertical, 8).background(Capsule().fill(Self.cream))
            }
            ForEach(Array(list.prefix(4).enumerated()), id: \.element.item.id) { i, s in
                Button {
                    UIImpactFeedbackGenerator(style: .soft).impactOccurred(); AudioHub.shared.uiTap()
                    care.feedSnack(s.item.id, jelly: care.singledOutJelly)
                    withAnimation(Self.spring) { snackPicker = false; open = false }
                } label: {
                    VStack(spacing: 3) {
                        ItemArt(item: s.item, size: 50).overlay(alignment: .topTrailing) {
                            Text("\(s.count)").font(.system(size: 11, weight: .black, design: .rounded)).foregroundStyle(.white)
                                .frame(minWidth: 18, minHeight: 18).background(Circle().fill(FocusStyle.pink)).offset(x: 5, y: -5)
                        }
                        Text(s.item.name).font(.system(size: 11, weight: .semibold, design: .rounded)).foregroundStyle(Self.brown).lineLimit(1)
                            .padding(.horizontal, 6).padding(.vertical, 2).background(Capsule().fill(Self.cream))
                    }
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("care-snack-\(s.item.id)").accessibilityLabel("\(s.item.name), \(s.count) left")
                .transition(.scale(scale: 0.3, anchor: .trailing).combined(with: .opacity).animation(Self.spring.delay(Double(i) * 0.05)))
            }
        }
        .padding(.trailing, 8)
    }

    private func enabled(_ item: Item) -> Bool {
        switch item.id {
        case "care-feed", "care-water", "care-snacks": return !care.trayOut && !care.bath.active
        case "care-clean": return care.canClean(jelly: care.targetJelly)
        case "care-race": return care.canRace(jelly: care.targetJelly)
        default: return !care.bath.active
        }
    }

    private func row(_ item: Item, index: Int) -> some View {
        let fromBottom = items.count - 1 - index          // 0 = nearest the main button
        let on = enabled(item)
        return Button {
            UIImpactFeedbackGenerator(style: .soft).impactOccurred(); AudioHub.shared.uiTap()
            switch item.id {
            case "care-feed":
                withAnimation(Self.spring) { picker = picker == .food ? nil : .food; snackPicker = false }
                return                                       // the picker row chooses; the menu stays open
            case "care-snacks":
                withAnimation(Self.spring) { snackPicker.toggle(); picker = nil }
                return
            case "care-water":
                if Consumables.drinks.count >= 2 {
                    withAnimation(Self.spring) { picker = picker == .drink ? nil : .drink }
                    return
                }
                care.drink(Consumables.drinks.first?.id ?? "water", jelly: care.singledOutJelly)   // one drink: starts directly (nobody singled out = the group serving)
            case "care-clean": care.clean(jelly: care.targetJelly)
            case "care-race": care.startRace(jelly: care.targetJelly)
            default: care.comeHere(jelly: care.targetJelly)
            }
            withAnimation(Self.spring) { open = false }
        } label: {
            HStack(spacing: 10) {
                Text(item.title)
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(Self.brown)
                    .padding(.horizontal, 15).padding(.vertical, tight ? 5 : 8)
                    .background(Capsule().fill(Self.cream).shadow(color: Color(red: 0.3, green: 0.2, blue: 0.12).opacity(0.18), radius: 6, y: 2))
                Image(systemName: item.symbol)
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
        .accessibilityIdentifier(item.id)
        .accessibilityLabel(item.title)
        .transition(.scale(scale: 0.3, anchor: .bottomTrailing).combined(with: .opacity)
            .combined(with: .offset(y: 24 + CGFloat(fromBottom) * 10))
            .animation(Self.spring.delay(Double(fromBottom) * 0.05)))
    }

    private var mainButton: some View {
        Button {
            UIImpactFeedbackGenerator(style: .soft).impactOccurred(); AudioHub.shared.uiTap()
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
            .frame(width: tight ? 54 : 64, height: tight ? 54 : 64)
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
            UIImpactFeedbackGenerator(style: .soft).impactOccurred(); AudioHub.shared.uiTap()
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

/// The first-time hint in focus mode: "Rub to pet · double-tap & hold to pick up · flick to throw". Shown for the first few visits only, fades after 4 s.
struct FocusHint: View {
    static let key = "FocusHintSeen"
    @State private var shown = UserDefaults.standard.integer(forKey: FocusHint.key) < 3
    @State private var visible = true

    var body: some View {
        if shown {
            Text("Rub to pet · double-tap & hold to pick up · flick to throw")
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
