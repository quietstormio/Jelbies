//
//  GameCare.swift
//  Care actions of the game screen (feed / drink / call / wave). The SwiftUI menu calls feed(_:) / drink(_:) / call();
//  the stage controller calls tick() once per fixed sim step, which talks to Bob's brain and pops the meal TRAY in and out.
//
//  A meal: Feed / Drink -> a short little tray pops in (puff) at the front spot with the chosen food or bottle -> he walks to his place,
//  turns, eats (berries or pizza by hand) or sips (his own straw), a happy finish -> the tray poofs away. One tray at a time.
//

import Foundation
import QuartzCore
import UIKit
import Observation
import simd

@MainActor
@Observable
final class GameCare {
    /// A tray is out (or about to be): Feed and Drink are disabled until it has poofed away.
    private(set) var trayOut = false
    /// A voice command asked for a Town screen ("let's race" / "time to train" open the Track for the selected Jelly): GameScreen watches `townRequest`.
    private(set) var townRequest = 0
    @ObservationIgnored private(set) var townScreen: TownScreen?
    func requestTown(_ s: TownScreen) { townScreen = s; townRequest += 1 }
    /// Mirrors the brain's activity for the menu / tests.
    private(set) var busy = false
    var foodOut: Bool { trayOut && servingKind == .food }
    var waterOut: Bool { trayOut && servingKind == .drink }
    /// True while a tray is out (the debug script waits on it).
    var bowlOut: Bool { trayOut }
    private(set) var servingKind: ConsumableKind?

    @ObservationIgnored var queued: [BlobRequest] = []      // one-shot brain requests (wave / come)
    @ObservationIgnored private var hooked = false
    @ObservationIgnored var callRunning = false
    @ObservationIgnored private var finished: [BlobRequest] = []
    @ObservationIgnored var wanted: Consumable?             // picked, the tray not out yet
    @ObservationIgnored var meal: Consumable?               // the tray is out and he is working on it
    @ObservationIgnored var mealAge: Float = 0
    @ObservationIgnored var idleT: Float = 0
    @ObservationIgnored var retries = 0
    @ObservationIgnored var mealRequested = false
    /// The walk to the stand before the tray pops in (see `serveWanted`).
    @ObservationIgnored var standRequested = false
    @ObservationIgnored var standIdle: Float = 0
    @ObservationIgnored var standSettle: Float = 0
    @ObservationIgnored var standRetries = 0
    @ObservationIgnored var wantedAge: Float = 0
    @ObservationIgnored var wantedOrigin: SIMD2<Float>?
    /// Appetite of the current meal (decided when the tray pops in, from his tier then): pieces he will take (0 = refuses), already paid for.
    @ObservationIgnored private(set) var mealPieces = 3
    @ObservationIgnored var mealPaid = 0
    @ObservationIgnored var mealTier = NeedTier.famished
    /// Famished / Parched eats faster (tests of the shared bite timing turn this off).
    @ObservationIgnored var eagerWhenFamished = true
    /// The small "Not hungry" / "Not thirsty" label while he refuses (nil = none). `noticeSerial` bumps per refusal.
    var notice: String?
    @ObservationIgnored var noticeSerial = 0
    @ObservationIgnored var noticeAge: Float = 0
    @ObservationIgnored var noticeDone = false

    /// Which Jelly the current order / meal is for (set by `order`; GameCare+Dining.swift). Others: their brain's finished jobs, their head, the brain to stand down.
    @ObservationIgnored var mealJelly = 0
    @ObservationIgnored var pendingJelly: Int? = 0
    @ObservationIgnored var eaterFinished: [BlobRequest] = []
    @ObservationIgnored var clearCool: [Int: Float] = [:]
    @ObservationIgnored var mealHead = SIMD3<Float>(0, BlobShape.H, 1)
    @ObservationIgnored weak var eaterBrain: BlobBrain?
    /// The meal tray (one shared serving scaled for N Blobs; drinks come with a straw per Blob).
    let dining = DiningSet()
    /// The sleep eye masks (Room/SleepMask.swift, GameCare+SleepMask.swift): on while a Jelly sleeps on his back, poof away when he wakes.
    @ObservationIgnored let sleepMasks = SleepMaskSet()
    @ObservationIgnored var masksDrawn = false
    /// The wardrobe on screen (Wear/WornSet.swift, GameCare+Wear.swift): hats, glasses, scarves, mitts, jerseys and the Circuit bibs.
    @ObservationIgnored let wardrobe = WornSet()
    @ObservationIgnored var wearDrawn = false
    /// The character features on screen (Features/FeatureSet.swift, GameCare+Features.swift): Pip's spines, Moss's daisy, Lavender's wings.
    @ObservationIgnored let features = FeatureSet()
    /// The fitting room's picture of Jelly `id` wearing a look, rendered by the stage with the game renderer (nil when no stage is running).
    @ObservationIgnored var fittingProvider: ((WearLook, Int) -> UIImage?)?
    /// A plain portrait of Jelly `id` as he is now (the Studio, the Condition card, the show lobby).
    @ObservationIgnored var portraitProvider: ((Int) -> UIImage?)?
    @ObservationIgnored var wearOutfitRev = -1
    @ObservationIgnored var wearOutfits: [Int: [WearSlot: WearLook]] = [:]
    @ObservationIgnored var shoesDrawn = false
    @ObservationIgnored var shoeCache: [Int: ShoeEntry] = [:]
    @ObservationIgnored var shoeSig: [Int] = []
    /// Shoe shells rebuilt vs reused since launch (tests / diagnostics).
    @ObservationIgnored var shoeStats = (rebuilt: 0, reused: 0)
    /// Decor (GameCare+Decor.swift): what was last drawn, so the room mesh is rebuilt only when something changed.
    @ObservationIgnored var decorDrawn = DecorDrawn()
    /// Arrange mode (drag the room's decor): set from the Bag's Place, ended by Done. The Jellies' touch is off meanwhile.
    var arranging = false
    var arrangingUID: Int? { didSet { DecorField.shared.held = arrangingUID } }
    /// Double tap on a piece a Jelly is using: he is asked to hop off, and arrange mode starts on it once he has (seconds left to wait).
    @ObservationIgnored var arrangeWait: (uid: Int, left: Float)?
    /// The GROUP serving (GameCare+Group.swift): one drink with a straw per Jelly, driven over the same `dining` set.
    @ObservationIgnored let group: DiningGroup
    @ObservationIgnored var groupWanted: Consumable?
    @ObservationIgnored var groupAge: Float = 0
    /// Four Jellies, three places: the ids waiting for the NEXT sitting of `groupNext`, and what `reserved` was on each before he was asked to wait.
    @ObservationIgnored var groupQueue: [Int] = []
    @ObservationIgnored var groupNext: Consumable?
    @ObservationIgnored var groupWaitSaved: [Int: GroupWaiter] = [:]
    /// Focus mode (Come here): phase, dock selection and the camera spring. See TouchMode.swift.
    let focus = BlobFocus()
    /// Which Jellies the close-up is on, where they stand, and their approach / touch bookkeeping (GameCare+Focus.swift).
    let focusGroup = FocusGroup()
    /// Clean: soap, rinse, shine (Bath/BathFlow.swift). Also owns the dirt that builds up in the room.
    let bath: BathFlow
    /// The store: what the player owns (Store/StoreBook.swift, GameCare+Store.swift). Bought with Drops from `bath.wallet`.
    let store: StoreBook
    /// Store food bookkeeping (GameCare+Store.swift): the serving already paid from the inventory, Jellies owed their sugar-rush zoomies, soaps armed for the next Clean.
    @ObservationIgnored var servingCharged = false
    @ObservationIgnored var zoomiesDue: Set<Int> = []
    @ObservationIgnored var armedSupplies: [Int: [String]] = [:]
    /// Jelly Circuit "Waddle Sprint" (Race/RaceFlow.swift, GameCare+Race.swift): the trip to the track and back, and the race on it.
    let race = RaceFlow()
    @ObservationIgnored let raceBook = RaceBook()
    @ObservationIgnored var raceWait: RaceWait?
    /// The Jelly Show (Show/ShowFlow.swift, GameCare+Show.swift): the trip to the stage and back, the three rounds, the Studio's dance drill.
    let show = ShowFlow()
    @ObservationIgnored let showBook = ShowBook()
    /// A trip is on: the race track or the show stage (the room's care, close-up and roaming wait).
    var tripActive: Bool { race.active || show.active }
    /// Clean-up of the other Jellies (GameCare+Bath.swift): who is washable, their after-bath wetness.
    @ObservationIgnored let bathPlug = BathPlug()
    /// Multi-Blob select (outline highlight, confirm chip). One Blob in the game for now: the action button is then always visible.
    let select = BlobSelect()
    @ObservationIgnored var approachIdle: Float = 0
    @ObservationIgnored var approachRetries = 0
    @ObservationIgnored private var savedAutonomy = true
    @ObservationIgnored private var wantHop = false
    @ObservationIgnored var afterRelease: Consumable?        // Feed / Drink asked inside focus: release first, then the tray flow
    /// Needs + mood (hunger / thirst / attention). `needs.mood` and `needs.wantedNeed` are what the touch reactions read.
    let needs: BlobNeeds
    var mood: BlobMood { needs.mood }
    var wantedNeed: NeedKind? { needs.wantedNeed }
    /// The need whose thought bubble is up right now (nil = none), and how the last bubble ended (the view poofs it, with a sparkle when fixed).
    var bubbleNeed: NeedKind?                  // (settable for GameCare+Bubbles: the bubble slot is shared by every Jelly)
    /// Who holds the one bubble slot when several Jellies need things (GameCare+Bubbles.swift). Never touched in a one-Jelly game.
    @ObservationIgnored let bubbleHub = BubbleHub()
    struct BubbleEnd: Equatable { var serial = 0; var need: NeedKind = .hunger; var fixed = false; var silent = false; var clean = false }
    var bubbleEnd = BubbleEnd()
    @ObservationIgnored private(set) var schedule = BubbleSchedule()
    /// The bath bubble (Dirty / Filthy coat): a parallel source to the need bubbles, sharing the one bubble slot.
    var bubbleClean = false
    @ObservationIgnored private(set) var coatSchedule = CoatBubbleSchedule()
    /// The touch model, read-only: petting in focus mode restores attention (set by the screen).
    @ObservationIgnored weak var touchPlay: TouchPlay?
    /// Where the bubble anchors: the top of his head in the world (the same projection as the hearts / outline), and his floor spot for the highlight.
    @ObservationIgnored private(set) var headWorld = SIMD3<Float>(0, BlobShape.H, 1)
    @ObservationIgnored private(set) var bodyFloor = SIMD3<Float>(0, 0, 1)
    /// Every Jelly in the room (index = id). [0] wraps this care's own `needs`, `bath.grime` and `voice.training`; the others own theirs and persist
    /// under their id (JellyKeys). Care actions (meals, Clean, Come here, voice) still drive Jelly 0 only.
    private(set) var jellies: [JellyProfile] = []
    var jellyCount: Int { jellies.count }
    /// The characters in the room, by slot (JellyRoster).
    var roster: [Int] { jellies.map(\.character) }
    /// Phase A: the care menu (Feed / Drink / Come here / Clean) always acts on Bob, so it stays visible with several Jellies instead of waiting for a selection.
    static let perJellyCare = false
    /// The Jelly the care menu targets: the one highlighted (or confirmed) in the selection, else Bob (0).
    var targetJelly: Int {
        if focus.isActive, focusGroup.ids.count == 1 { return focusGroup.ids[0] }        // the dock acts on the one Jelly in the close-up
        return select.selectedID ?? select.confirmed ?? 0
    }
    func jelly(_ id: Int) -> JellyProfile? { jellies.indices.contains(id) ? jellies[id] : nil }
    /// The coat word of a Jelly.
    /// The Home Screen / Lock Screen widget's data (Widget/WidgetBridge.swift): the snapshot + portraits in the App Group, written as needs / grime change.
    @ObservationIgnored let widget = WidgetBridge()
    /// What the widget shows: one input per Jelly in the room (`jellies`, each with its own needs / grime; colour by roster id).
    func widgetInputs() -> [WidgetBridge.Input] {
        jellies.map { j in
            WidgetBridge.Input(id: j.id, name: j.name, color: WidgetBridge.colorName(j.character), levels: NeedKind.allCases.map { j.needs.level($0) },
                               dirt: j.grime.dirt, sparkle: j.grime.sparkle)
        }
    }
    /// The select hook for the widget's deep link (`jelbies://jelly/<id>`): the game is already open, so this plays that Jelly's roster highlight.
    func openJelly(_ id: Int) { rosterPick(id) }
    func coat(for id: Int) -> BlobGrime.CoatTier { jelly(id)?.coat ?? .normal }
    func needs(for id: Int) -> BlobNeeds {
        if let p = jelly(id) { return p.needs }
        if let n = otherNeeds[id] { return n }
        let n = BlobNeeds(persists: false)                          // an id outside the roster: an in-memory stand-in
        otherNeeds[id] = n
        n.set(NeedKind(rawValue: id % 3) ?? .thirst, 0.2)           // stand-ins differ: Pip is thirsty, Moss wants love
        return n
    }
    @ObservationIgnored private var otherNeeds: [Int: BlobNeeds] = [:]
    /// The food / drink the player last picked (consumable ids).
    private(set) var selectedFoodID = Consumables.berries.id
    private(set) var selectedDrinkID = Consumables.water.id
    #if DEBUG || DINING_PREVIEW
    @ObservationIgnored private var preview = DiningPreview.fromLaunchArguments()
    #endif

    /// A meal that gets nowhere (he keeps being picked up) is cleared away after this long.
    static let mealTimeout: Float = 60

    /// Voice v1: his name, tricks, listen mode and the reaction queue (VoiceCoordinator.swift). Run from `tick`.
    let voice: VoiceCoordinator

    /// `jellyCount`: Jellies in the room (1...3), the first that many of `JellyRoster.current`; `roster` names the characters by slot instead
    /// (SetRosterTests). `persistent: false` keeps the slots after 0 in memory (tests); `defaults` is where they save.
    /// Slot 0 wraps the legacy objects (`needs`, `bath.grime`, the voice training) under ITS CHARACTER's keys: with Bob there they are the old keys.
    init(voice: VoiceCoordinator? = nil, jellyCount: Int = 1, roster: [Int]? = nil, persistent: Bool = true, defaults: UserDefaults = .standard) {
        var chars: [Int]
        if let roster { chars = JellyRoster.sanitised(roster) }
        else {
            let n = min(max(jellyCount, 1), JellyRoster.maxCount)
            chars = Array(JellyRoster.current.prefix(n))
            for c in 0..<JellyRoster.characterCount where chars.count < n && !chars.contains(c) { chars.append(c) }     // a short roster is padded
            chars = JellyRoster.sanitised(chars)
        }
        let c0 = chars[0]
        needs = c0 == 0 ? BlobNeeds() : BlobNeeds(defaults: defaults, key: JellyKeys.needs(c0), persists: persistent)
        bath = BathFlow(grimeKey: c0 == 0 ? nil : JellyKeys.grime(c0), grimeSeed: 0xB47B &+ UInt32(c0) &* 7919)
        group = DiningGroup(dining: dining, shared: true)
        store = StoreBook(wallet: bath.wallet, persists: ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil)
        let v = voice ?? VoiceCoordinator(training: c0 == 0 ? nil : VoiceTraining(defaults: defaults, key: JellyKeys.words(c0), name: JellyRoster.names[c0], persists: persistent))
        self.voice = v
        v.care = self
        bath.wallet.onEarn = { [weak self] _ in self?.brainFor(0)?.wantJoy() }          // drops earned: a jump for joy
        let n = chars.count
        let stats0: JellyStats? = c0 == 0 ? nil : JellyStats(persists: persistent, defaults: defaults, key: JellyKeys.stats(c0),
                                                                seedWaddle: StatTuning.seedWaddle(careLevels: NeedKind.allCases.map { needs.level($0) }))
        let perks0: JellyPerks? = c0 == 0 ? nil : JellyPerks(persists: persistent, defaults: defaults, key: JellyKeys.perks(c0))
        jellies = [JellyProfile(id: 0, character: c0, name: JellyRoster.names[c0], needs: needs, grime: bath.grime, training: v.training, stats: stats0, perks: perks0)]
            + chars.dropFirst().enumerated().map { JellyProfile(id: $0.offset + 1, character: $0.element, name: JellyRoster.names[$0.element], persists: persistent, defaults: defaults) }
        if n > 1 { select.setBlobs(JellyRoster.selectBlobs(roster: chars)) }
        store.characterOf = { [weak self] slot in self?.jelly(slot)?.character ?? slot }       // outfits are saved by character
        bath.haptic = { [weak self] i, s in self?.touchPlay?.haptics.transient(now: CACurrentMediaTime(), intensity: i, sharpness: s) }
        bath.success = { [weak self] in UINotificationFeedbackGenerator().notificationOccurred(.success); self?.soapFinished() }
        v.training.unlocked = { [weak self] t in self?.store.hasPage(t) ?? t.isStarter }
        if let ps = bath.sound as? BathSilence { ps.muted = { [weak self] in self?.voice.isListening ?? false } }
        wireRace()
        wireShow()
        DecorField.shared.set(store.placedDecor)
    }

    // Not isolated: Swift 6.2's implicit isolated deinit (swift_task_deinitOnExecutor) aborts on the iOS 26.2 runtime; see MelonModel.
    nonisolated deinit {}

    /// A grumpy Bob ignored an order: the thought bubble of the need he is wanting comes up now (nothing if none).
    /// What the bubble shows now: a need, the bath, or nothing.
    var bubbleIcon: BubbleIcon? { bubbleNeed.map { .need($0) } ?? (bubbleClean ? .clean : nil) }
    func showNeedBubble() { if !focus.isActive { applyBubble(schedule.showNow()) } }

    // Target Jelly: every care action takes `jelly:` (default 0 = Bob). Phase A drives Jelly 0 only; phase B routes the id to that Jelly's brain / needs / tray place.
    func feed(jelly: Int? = nil) { feed(selectedFoodID, jelly: jelly) }
    func water(jelly: Int? = nil) { drink(selectedDrinkID, jelly: jelly) }
    /// Picker entry points: pop the tray in with the chosen consumable (ignored while a tray is out).
    /// `jelly: nil` = nobody singled out: with several Jellies a GROUP serving (like `drink`).
    func feed(_ id: String, jelly: Int? = nil) {
        guard let c = Consumables.with(id: id), c.kind == .food else { return }
        if c.stored, store.count(food: c.id) == 0 { return }          // a store food needs one in the bag
        selectedFoodID = id; servingCharged = false; order(c, jelly: jelly)
    }
    /// `jelly: nil` = nobody singled out: with several Jellies it is a GROUP serving (one drink, a straw each); one Jelly keeps the old flow.
    func drink(_ id: String, jelly: Int? = nil) { if let c = Consumables.with(id: id), c.kind == .drink { selectedDrinkID = id; order(c, jelly: jelly) } }
    func water(_ id: String, jelly: Int? = nil) { drink(id, jelly: jelly) }
    /// A tap on the thought bubble: opens the matching care action. Feed / Drink return the action so the screen can open the care menu on that
    /// picker; the attention bubble calls him over right here. The bubble goes away until its next turn.
    @discardableResult
    func tapBubble() -> BubbleAction? {
        if bubbleHub.owner != 0 { return tapOtherBubble() }          // another Jelly's bubble (GameCare+Bubbles.swift)
        if bubbleClean, bubbleNeed == nil {
            _ = coatSchedule.dismiss(); bubbleClean = false
            bubbleEnd = BubbleEnd(serial: bubbleEnd.serial + 1, clean: true)
            selectForBubble(0)
            if canClean { clean() }
            return .clean
        }
        guard let n = bubbleNeed else { return nil }
        let a = n.action
        if a != .comeHere, trayOut || focus.isActive { return nil }         // a meal is already on: the bubble only waits for it
        applyBubble(schedule.dismiss())
        selectForBubble(0)
        if a == .comeHere { comeHere() }
        return a
    }
    /// The roster: tapping a card plays the outline highlight on that Blob (works with one Blob too), then the action button shows for him.
    func rosterPick(_ id: Int, quietHop: Bool = false) {
        guard !focus.isActive else { return }
        select.highlight(id, quietHop: quietHop)
    }
    func applyBubble(_ events: [BubbleSchedule.Event], from id: Int = 0) {
        guard id == bubbleHub.owner else { return }          // only the Jelly holding the slot may change it
        for e in events {
            switch e {
            case .appeared(let n): bubbleNeed = n
            case .disappeared(let n):
                bubbleNeed = nil; bubbleEnd = BubbleEnd(serial: bubbleEnd.serial + 1, need: n, fixed: false, silent: bath.active)   // no puff when a clean-up starts
            case .fixed(let n, _):
                AudioHub.shared.chirp(jelly: id, .happy, x: id == 0 ? bodyFloor.x : 0)
                brainFor(id)?.wantJoy()          // a need fixed: a jump for joy
                bubbleNeed = nil; bubbleEnd = BubbleEnd(serial: bubbleEnd.serial + 1, need: n, fixed: true)
            }
        }
    }
    private func tickNeeds(brain: BlobBrain, sim: SoftBody?, dt: Float) {
        var petting = false, purring = false
        if focus.isFocused, focusGroup.touchID == 0, let tp = touchPlay {
            petting = tp.contact && tp.speed > TouchPlay.strokeSpeed * 0.5
            purring = tp.isPurring
        }
        let pk = jellies.first?.perks
        pk?.step(dt: dt)
        var drain = pk?.cache.drain ?? [1, 1, 1]
        if store.beanbagPlaced { drain[NeedKind.attention.rawValue] = min(drain[NeedKind.attention.rawValue], StoreTuning.beanbagAttentionDrain) }          // Cozy-lite: a beanbag in the room
        needs.step(dt: dt, petting: petting, purring: purring, exerting: brain.isExerting, drainScale: brain.napDrainScale, perkDrain: drain)
        // where his head is (for the bubble) and his floor spot (for the highlight)
        var c = SIMD3<Float>(brain.position.x, BlobShape.H * 0.5, brain.position.y)
        if let sim { c = sim.centroid() }
        if let a = focusGroup.touchAnchor { c = a }          // petting another Jelly in the close-up: hearts and bubbles anchor on him
        bodyFloor = SIMD3(c.x, 0, c.z); select.bodyFloor = bodyFloor
        headWorld = SIMD3(c.x, c.y + BlobShape.H * 0.5, c.z)
        // a bubble is held back in focus mode and while a highlight is up; it stays while his meal for that need is on
        var pinned = false
        if let n = needs.wantedNeed, trayOut, mealJelly == 0, let k = servingKind { pinned = (k == .food && n == .hunger) || (k == .drink && n == .thirst) }
        let suppressed = ((focus.isActive || select.isSelecting || bath.active || tripActive) && !pinned) || bubbleHub.owner != 0
        // the one bubble slot: whoever is up keeps it; a Filthy coat takes it over from a need unless some need is Famished / Parched / Neglected
        let coat = bath.grime.coat
        let famished = NeedKind.allCases.contains { needs.tier($0) == .famished }
        let preempt = coat == .filthy && !famished
        let coatSuppressed = suppressed || pinned || (schedule.visible && !preempt)
        if coatSchedule.update(coat: coat, dt: dt, suppressed: coatSuppressed) { bubbleClean = coatSchedule.visible; if !bubbleClean { bubbleEnd = BubbleEnd(serial: bubbleEnd.serial + 1, silent: bath.active, clean: true) } }
        let needSuppressed = suppressed || (coatSchedule.visible && !pinned)
        applyBubble(schedule.update(wanted: needs.wantedNeed, dt: dt, suppressed: needSuppressed, pinned: pinned))
    }

    // MARK: time away

    /// Greeting: back after at least this long, Bob trots to the front and does a happy hop with hearts.
    @ObservationIgnored private(set) var greetings = 0
    @ObservationIgnored var greeting = false
    @ObservationIgnored private var greetAge: Float = 0
    @ObservationIgnored var greetHop = false
    @ObservationIgnored private var greetHearts = 0
    @ObservationIgnored private var greetT: Float = 0
    @ObservationIgnored private var launchGreeted = false
    /// The other Jellies' greeting: ids still to be sent, and the ones on their way (id -> seconds so far, spot).
    /// The Jelly whose selection already woke him (one wake per selection).
    @ObservationIgnored var selectWokeFor: Int?
    @ObservationIgnored var greetPending: Set<Int> = []
    @ObservationIgnored var greetOthers: [Int: (age: Float, spot: SIMD2<Float>, arrived: Float)] = [:]
    /// Where each Jelly stands for the greeting (Bob takes the usual front spot; the others fan out behind him).
    static func greetSpot(_ id: Int) -> SIMD2<Float> {
        let c = VoiceCoordinator.comeSpot
        switch id { case 1: return c + SIMD2(-0.9, -1.5); case 2: return c + SIMD2(0.9, -1.5); default: return c }
    }

    /// The app left the foreground: stamp and save needs AND grime (the stamp is what the next return / launch measures from).
    func leftActive(at t: Date? = nil) {
        for j in jellies { j.leftActive(at: t) }          // every Jelly: needs AND grime
        widget.leftActive(widgetInputs())
    }
    /// The app is back in the foreground: apply the time away once (needs curve, dirt, sparkle), then greet after a long absence.
    /// Returns the seconds applied.
    @discardableResult
    func returnedActive(at t: Date? = nil) -> TimeInterval {
        var away: TimeInterval = 0
        for j in jellies { away = max(away, j.returnedActive(at: t)) }
        greetIfAway(away)
        return away
    }
    /// Cold launch: the away time was applied when the models loaded; greet if it was long. Once.
    func launched() {
        guard !launchGreeted else { return }
        launchGreeted = true
        greetIfAway(jellies.map(\.lastAway).max() ?? 0)
    }
    /// True when a meal, a clean-up, a voice action or the close-up is going on (no greeting then).
    var greetBlocked: Bool {
        trayOut || meal != nil || wanted != nil || groupActive || bath.active || tripActive || focus.isActive || focus.phase != .roaming
            || voice.mode.phase != .idle || voice.voiceGoing || voice.comingNow
    }
    func greetIfAway(_ away: TimeInterval) {
        guard away >= TimeAway.greetAfter, !greetBlocked else { return }
        select.cancel()
        greeting = true; greetAge = 0; greetHop = false
        queued = [.come(to: VoiceCoordinator.comeSpot)]          // the existing come-to-front walk (no close-up), then the happy hop
        greetPending = Set(1..<max(jellies.count, 1)); greetOthers = [:]       // the other Jellies trot to the front too (tickOthers)
        bubbleHub.greetClock = 0; bubbleHub.greetHearts = [:]
        greetings += 1
    }

    func wave(jelly: Int = 0) { AudioHub.shared.chirp(jelly: jelly, .babble); if meal == nil, wanted == nil, !groupActive, !focus.isActive, !bath.active, !tripActive { queued = [.wave] } }
    /// Menu row "Clean" is available: no tray, no meal, no clean-up running, not in the come-here close-up.
    var canClean: Bool { canClean(jelly: 0) }
    /// "Clean": he runs out toward the camera, then the clean-up scene (see BathFlow).
    func clean(jelly: Int = 0) {
        guard jelly == 0 else { startCleanOther(jelly: jelly); return }        // another Jelly: GameCare+Bath.swift
        guard canClean, let brain = lastBrain else { return }
        select.cancel()
        queued.removeAll(); callRunning = false
        voice.cancel()
        bath.start(brain: brain)
    }
    @ObservationIgnored var outfitSeen: [Int: Int] = [:]
    @ObservationIgnored weak var lastBrain: BlobBrain?
    /// The brain of Jelly `id` (0 = Bob).
    func brainFor(_ id: Int) -> BlobBrain? { id == 0 ? lastBrain : bathPlug.actors[id]?.actor?.brain }
    @ObservationIgnored weak var lastSim: SoftBody?
    /// "Come here": calls him to the front spot, then focus mode starts (camera close-up, actions dock, release button).
    /// A meal in progress is dropped first: the tray poofs, the piece he held goes with it.
    func comeHere(jelly: Int? = nil) { beginFocus(ids: [jelly ?? targetJelly]) }       // GameCare+Focus.swift
    /// Old name of `comeHere()` (the menu and the capture scripts).
    func call(jelly: Int? = nil) { comeHere(jelly: jelly) }

    /// "Let Bob go": the only way out of focus mode. The camera eases out, he hops, and he resumes roaming.
    func release() {
        guard focus.phase == .focused || focus.phase == .approaching else { return }
        let wasFocused = focus.phase == .focused
        focus.release()
        if wasFocused, focusGroup.includes(0) { wantHop = true }
        else { queued.removeAll { if case .come = $0 { return true }; return false }; callRunning = false }
    }

    private func order(_ c: Consumable, jelly: Int? = 0) {
        if focus.isActive {                          // Feed / Drink from inside focus ends focus first
            release()
            if focus.isActive { afterRelease = c; pendingJelly = jelly; return }
        }
        guard wanted == nil, meal == nil, dining.phase == .absent, !bath.active, !tripActive, !groupActive else { return }
        if jelly == nil, jellies.count > 1 {         // the group serving: started by `tickGroup` (it has every brain)
            mealJelly = 0; groupWanted = c; groupAge = 0; servingKind = c.kind; trayOut = true; retries = 0
            return
        }
        let jelly = jelly ?? 0
        mealJelly = jellies.indices.contains(jelly) ? jelly : 0
        wanted = c; servingKind = c.kind; trayOut = true
        retries = 0                                  // a fresh tap: the re-serve budget (`Self.maxReserves`) starts over
        resetStandWalk()
    }
    func resetStandWalk() { standRequested = false; standIdle = 0; standSettle = 0; standRetries = 0; wantedAge = 0; wantedOrigin = nil }

    /// Floor obstacle for the brain's resolver: pushes a point out of the tray.
    /// Sipping stands `sipCloser` nearer the tray (his mouth only reaches a straw tip that close); his belly may overlap the tray's rim by that much.
    static let sipCloser: Float = 0.08
    /// Eating stands a little FARTHER back than the layout's stand (negative = away from the tray): measured, the berries are reached with less miss.
    static let eatCloser: Float = -0.03
    func obstacle(_ p: SIMD3<Float>, radius: Float) -> SIMD3<Float> { dining.obstacle(p, radius: radius * RoomLayout.lowPropRadiusScale) }
    /// The footprint the brain's resolver uses while a drink is out is a little smaller (the room's own tray collider is in `base`).
    private func footprint(_ r: Float) -> Float { r - (servingKind == .drink ? Self.sipCloser * 1.5 : 0) }

    /// The brain's dining hooks wired to a tray (the same wiring the tests use).
    static func hooks(for c: Consumable, tray d: DiningSet, place i: Int = 0) -> BlobBrain.DineHooks {
        var h = BlobBrain.DineHooks(
            piece: { _ in d.pieceAnchorWorld(place: i, index: d.nextPiece(place: i)) },
            begin: { d.beginBite(place: i) },
            finish: { d.finishBite(place: i) },
            cancel: { d.cancelBite(place: i); d.release(.piece, place: i) },
            hold: { m in d.hold(.piece, place: i, transform: m) })
        switch c.eatStyle {
        case .finger: break
        case .fork:
            h.fork = true
            h.piece = { _ in d.forkBitePoint(place: i) }
            h.cancel = { d.cancelBite(place: i); d.poofFork(place: i) }
            h.forkAppear = { p in d.appearFork(place: i, at: p) }
            h.holdFork = { m in d.hold(.fork, place: i, transform: m) }
            h.releaseFork = { d.poofFork(place: i) }
            h.launch = { d.launchBite(place: i) }
            h.holdBite = { m in d.hold(.bite, place: i, transform: m) }
        case .sip:
            h.straw = { d.strawTip(place: i) ?? .zero }
            h.level = { f in d.setDrunk(place: i, f) }
        }
        return h
    }

    func mealRequest(_ c: Consumable) -> BlobRequest { Self.mealRequest(c, tray: dining, place: 0, pieces: mealPieces) }

    /// How the sitting goes for a tier: the hooks' plan for the brain (refuse / pace / how much of the drink share this sitting drains).
    static func plan(for c: Consumable, tier: NeedTier, tray d: DiningSet, place i: Int = 0) -> BlobBrain.DinePlan {
        var p = BlobBrain.DinePlan()
        p.refuse = MealAppetite.pieces(tier) == 0
        p.pace = MealAppetite.pace(tier)
        if c.kind == .drink {
            let per = 1 / Float(DiningTiming.gulpsPerDrink)
            let left = Int(((1 - d.drunk[i]) * Float(DiningTiming.gulpsPerDrink)).rounded(.up))
            let take = max(min(left, MealAppetite.pieces(tier) - (DiningTiming.gulpsPerDrink - left)), 1)
            p.levelBase = d.drunk[i]; p.levelSpan = Float(take) * per
        }
        return p
    }
    /// Pieces eaten so far from this tray (bites gone / gulps drunk).
    private var piecesEaten: Int {
        guard let c = meal else { return 0 }
        if c.kind == .drink { return Int((dining.drunk[0] * Float(DiningTiming.gulpsPerDrink) + 0.001).rounded(.down)) }
        return DiningTiming.bitesPerServing - dining.bitesLeft[0]
    }
    /// Hooks + plan + request for the current meal (the first serve and every re-serve).
    func startMeal(_ c: Consumable, brain: BlobBrain) {
        brain.dineHooks = Self.hooks(for: c, tray: dining)
        brain.dinePlan = Self.plan(for: c, tier: mealTier, tray: dining)
        if !eagerWhenFamished { brain.dinePlan.pace = 1 }
        brain.requestNow(mealRequest(c))
    }
    /// The brain request for place `i` of tray `d` (sip stands a little closer, eating a little farther back). `pieces` caps what he takes this meal.
    static func mealRequest(_ c: Consumable, tray dining: DiningSet, place i: Int, pieces: Int = DiningTiming.bitesPerServing) -> BlobRequest {
        var place = dining.places[i]
        switch c.eatStyle {
        case .sip:
            place.stand += SIMD2(sinf(place.yaw), cosf(place.yaw)) * sipCloser
            let left = Int(((1 - dining.drunk[i]) * Float(DiningTiming.gulpsPerDrink)).rounded(.up))
            return .sip(place: place, gulps: max(min(left, pieces - (DiningTiming.gulpsPerDrink - left)), 1))
        default:
            place.stand += SIMD2(sinf(place.yaw), cosf(place.yaw)) * eatCloser
            let left = dining.bitesLeft[i] + (dining.forkBite[i] ? 1 : 0)
            return .dine(place: place, bites: max(min(left, pieces - (DiningTiming.bitesPerServing - left)), 1))
        }
    }

    private func enterFocus(brain: BlobBrain) {
        savedAutonomy = brain.autonomy
        brain.autonomy = false                       // he stays on the front spot until released
        if focusGroup.markArrived(0) { focus.arrive() }
        AudioHub.shared.chirp(jelly: 0, .happy)
    }

    /// Focus bookkeeping per fixed step: a stuck walk is retried, the camera spring runs, release hops and resumes roaming.
    private func tickFocus(brain: BlobBrain, sim: SoftBody?, dt: Float) {
        switch focus.phase {
        case .approaching where focusGroup.includes(0):
            // the come request can be cancelled (for example he was grabbed): ask again a couple of times, then give up
            let act = brain.activity
            if !callRunning, queued.isEmpty, act == .idle || act == .lookingAround || act == .steppingInPlace {
                approachIdle += dt
                if approachIdle > 0.8 {
                    approachIdle = 0
                    let d = simd_length(brain.position - focusGroup.spot(of: 0))
                    if d < 0.5 { enterFocus(brain: brain) }
                    else if approachRetries < 2 { approachRetries += 1; queued = [.come(to: focusGroup.spot(of: 0))] }
                    else { focus.cancelApproach() }
                }
            } else { approachIdle = 0 }
        case .leaving:
            if wantHop, let sim {
                wantHop = false
                brain.autonomy = savedAutonomy
                brain.startHopPlay(sim: sim, distance: 0.25)
            } else if wantHop, sim == nil { wantHop = false; brain.autonomy = savedAutonomy }
        default: break
        }
        if focus.step(dt: dt) {
            if let c = afterRelease { afterRelease = nil; order(c, jelly: pendingJelly) }
        }
    }

    /// Each piece he has eaten adds its share of the need as it goes (a Call mid-meal keeps what was eaten).
    func payPieces() {
        guard meal != nil, mealPieces > 0 else { return }
        let n = min(piecesEaten, mealPieces)
        guard n > mealPaid else { return }
        needs(for: mealJelly).gain(meal!.kind == .food ? .hunger : .thirst, Float(n - mealPaid) * MealAppetite.gainPerPiece)
        ate(jelly: mealJelly, meal!, pieces: n - mealPaid)
        mealPaid = n
    }

    /// Clears the meal. Does NOT touch `retries`: a re-serve goes endMeal -> wanted -> serveWanted -> spawn, and the count has to survive that
    /// round trip or the loop is never bounded. `retries` restarts only on a fresh tap (`order`), a finished meal, or a dropped one (Come here).
    func endMeal() {
        notice = nil
        standDownEater()
        dining.despawn()
        meal = nil; mealRequested = false; idleT = 0
    }
    /// A meal that fails (he is displaced / his request keeps being cancelled) is served again at most this many times, then given up on.
    static let maxReserves = 2

    /// After the frame's last sim step: what he holds goes back onto his nub for the pose the body has now, and the tray mesh is refreshed.
    func refreshHeld(brain: BlobBrain, sim: SoftBody, renderer: MelonRenderer?) {
        guard meal != nil else { return }
        brain.refreshHeld(sim: sim)
        if let room = renderer?.room, let f = dining.frame(theme: room.theme) { room.setDining(f) }
    }

    /// Where he is on the floor now: the body's centroid when it is free (just put down after a grab: the brain's own position is stale until it
    /// starts its next job), else the brain's root.
    static func floorPos(_ brain: BlobBrain, _ sim: SoftBody?) -> SIMD2<Float> {
        guard let sim, brain.poseW <= 0 else { return brain.position }
        let c = sim.centroid(); return SIMD2(c.x, c.z)
    }
    /// How far past his stand line (toward the camera) he may be for the tray to pop in at once: his belly already hangs that far over the
    /// tray's back edge at the stand itself (by design), so this is "he is at, or behind, his place".
    static let popTolerance: Float = 0.03
    /// The walk-to-stand target sits this far behind the stand, so the final step forward to the stand happens with the tray already out.
    static let approachBack: Float = 0.25
    /// After a walk to the stand he stands still this long before the tray pops in.
    static let popSettle: Float = 0.45

    /// The tray never pops in where he would have to cross it. The visible floor beside the 1.56-wide tray is only ~0.2 u wide, so there is NO
    /// on-screen way around it for a body 1.4 wide: instead the tray waits until he is at (or behind) his stand line. If he is in front of
    /// it (or on the spot where it pops in) he first walks to his place with no tray out, then it pops in front of him.
    func serveWanted(_ c: Consumable, brain: BlobBrain, here: SIMD2<Float>, act: BlobActivity, dt: Float) {
        let layout = DiningLayout.make(n: 1)
        if wantedOrigin == nil { wantedOrigin = DiningSpot.choose(bob: SIMD2(99, 99), layout: layout) }
        let origin = wantedOrigin ?? DiningSpot.preferred
        var stand = origin + layout.places[0].rel
        stand.y += c.eatStyle == .sip ? Self.sipCloser : Self.eatCloser
        wantedAge += dt
        if wantedAge > Self.mealTimeout { wanted = nil; retries = 0; resetStandWalk(); return }
        if here.y <= stand.y + Self.popTolerance {
            // he walked here because he was in front: let him come to rest first (the soft body overshoots toward the tray while it stops)
            if standRequested {
                if act == .idle || act == .lookingAround || act == .steppingInPlace { standSettle += dt } else { standSettle = 0 }
                guard standSettle >= Self.popSettle else { return }
            }
            if dining.phase == .absent, dining.spawn(serving: c, n: 1, bobAt: SIMD2(99, 99), forcedOrigin: origin) {
                wanted = nil; meal = c; mealAge = 0; idleT = 0; resetStandWalk()
                let kind: NeedKind = c.kind == .food ? .hunger : .thirst
                mealTier = needs(for: mealJelly).tier(kind); mealPieces = MealAppetite.pieces(mealTier); mealPaid = 0; noticeDone = false
                startMeal(c, brain: brain); mealRequested = true
            }
            return
        }
        // in front of his place: walk there first (the tray is not out yet, so nothing is in the way)
        let approach = SIMD2(stand.x, stand.y - Self.approachBack)
        if !standRequested {
            standRequested = true; standIdle = 0
            brain.requestNow(.goTo(approach))
        } else if act == .idle || act == .lookingAround || act == .steppingInPlace {
            standIdle += dt
            if standIdle > 0.8 {
                standIdle = 0
                if standRetries < 3 { standRetries += 1; brain.requestNow(.goTo(approach)) } else { wanted = nil; resetStandWalk() }
            }
        } else { standIdle = 0 }
    }

    /// The floor rules every Jelly's brain walks by: the visible floor, plus the meal tray as an obstacle.
    func wireWorld(_ brain: BlobBrain, isBob: Bool) {
        let base = brain.resolve
        brain.resolve = { [weak self, weak brain] p, r in
            if self?.bath.fenceLifted == true, self?.bath.targetID == (isBob ? 0 : brain?.steerID) { return p }          // the clean-up's exit run leaves the room: no floor bounds, only in that phase, only for the Jelly being washed
            let rr = self?.footprint(r) ?? r
            if self?.focusGroup.rowOpen == true, let me = self { return me.obstacle(GameCamera.constrain(p, radius: rr, lowPropScale: RoomLayout.lowPropRadiusScale, openSides: true), radius: rr) }       // the wide close-up row stands past the roaming floor's sides
            let q = base(p, rr)
            return self?.obstacle(q, radius: rr) ?? q
        }
    }

    /// Once per fixed step, after Bob's `tick`: the other Jellies' needs and dirt, their mood for the idle behaviours, the selection hop and the
    /// greeting after a long absence. (Meals, Clean, Come here and voice stay Jelly 0's.)
    func tickOthers(_ actors: [JellyActor], dt: Float) {
        for a in actors where a.id > 0 {
            guard let brain = a.brain, let profile = jelly(a.id) else { continue }
            let here = Self.floorPos(brain, a.sim)
            if tickBathOther(a, brain: brain, profile: profile, dt: dt) {} else { profile.step(dt: dt, position: here, exerting: brain.isExerting, drainScale: brain.napDrainScale) }
            brain.idleMood = profile.needs.mood
            syncPerks(id: a.id, brain: brain)
            brain.idleBlocked = (bath.active || focusGroup.pauses(a.id, phase: focus.phase)) && !brain.commanded
            driveFocus(id: a.id, brain: brain, sim: a.sim, dt: dt)
            tickDining(id: a.id, brain: brain, sim: a.sim, dt: dt)           // his meal, when the tray is for him (GameCare+Dining.swift)
            if select.hopRequest == a.id, !focus.isActive, select.takeHopRequest() != nil { brain.startHopPlay(sim: a.sim, distance: 0.0001) }
            // greeting: walk to the front spot (the existing come-to-front walk), then the happy in-place hop
            if greetPending.contains(a.id), !greetBlocked, brain.activity != .coming, bubbleHub.greetClock >= BubbleHub.greetStagger(a.id) {
                greetPending.remove(a.id)
                let spot = greetSpotNow(a.id)
                greetOthers[a.id] = (0, spot, 0)
                brain.requestNow(.come(to: spot))
            } else if var g = greetOthers[a.id] {
                g.age += dt
                let calm = brain.activity == .idle || brain.activity == .lookingAround || brain.activity == .steppingInPlace
                g.arrived = (calm && g.age > 0.5) ? g.arrived + dt : 0
                if g.age > 25 || greetBlocked { greetOthers[a.id] = nil }
                else if g.arrived > 0.3 { greetOthers[a.id] = nil; brain.startHopPlay(sim: a.sim, distance: 0.0001); startGreetHearts(a.id) }
                else { greetOthers[a.id] = g }
            }
        }
        tickGroup(actors, dt: dt)            // the group serving (GameCare+Group.swift)
        tickBubbles(actors, dt: dt)          // who holds the bubble slot, the greeting hearts (GameCare+Bubbles.swift)
    }

    func tick(brain: BlobBrain, renderer: MelonRenderer?, dt: Float, sim: SoftBody? = nil) {
        driveFocus(id: 0, brain: brain, sim: sim, dt: dt)
        tickFocus(brain: brain, sim: sim, dt: dt)
        tickNeeds(brain: brain, sim: sim, dt: dt)
        widget.tick(dt: dt) { widgetInputs() }
        // a pick on a sleeper wakes him ONCE per selection (edge-triggered: no wake on every tick), the draw waits until he is upright; and nobody who is picked goes to bed
        for a in raceBook.actors { a.brain?.selectedNow = (a.id == select.selectedID) }
        if let sid = select.selectedID {
            if selectWokeFor != sid { selectWokeFor = sid; if let b = selectBrain(sid), b.isSleeping, !b.sleep.wakeAsked { b.sleepWake(groggy: true) } }
        } else { selectWokeFor = nil }
        select.tick(dt: dt)
        if select.hopRequest == 0, let id = select.takeHopRequest(), id == 0, let sim, !focus.isActive { brain.startHopPlay(sim: sim, distance: 0.0001) }   // "he hops" (Bob; the others' hop is `tickOthers`)
        if !hooked {
            hooked = true
            AudioHub.shared.onSnore = { [weak self] i in self?.sleepMasks.snore(i) }
            brain.onFinished = { [weak self] r in self?.finished.append(r) }
            wireWorld(brain, isBob: true)
        }
        lastBrain = brain; lastSim = sim
        syncPerks(id: 0, brain: brain)
        let act = brain.activity
        busy = (act != .idle && act != .lookingAround && act != .steppingInPlace) || bath.active

        // greeting: the hop and hearts once he has come to the front (a stuck walk gives up after 25 s)
        if greeting { greetAge += dt; if greetAge > 25 || greetBlocked { greeting = false } }
        if greetHop {
            greetHop = false
            if let sim, !greetBlocked { brain.startHopPlay(sim: sim, distance: 0.0001); greetHearts = 3; greetT = 0; AudioHub.shared.chirp(jelly: 0, .happy) }       // the existing in-place hop (arm / feet caps hold)
        }
        if greetHearts > 0 { greetT -= dt; if greetT <= 0 { greetT = 0.45; greetHearts -= 1; touchPlay?.spawnHeart(now: CACurrentMediaTime()) } }

        // finished jobs
        for r in finished {
            switch r {
            case .come:
                callRunning = false; retries = 0
                if greeting { greeting = false; greetHop = true }
                if UserDefaults.standard.integer(forKey: "GameFeedAfterCall") != 0 { feed() }          // capture aid: serve a meal once he has come
                if focus.phase == .approaching, focusGroup.includes(0) { enterFocus(brain: brain) }
            case .goTo:
                voice.goFinished()                  // a voice walk ends facing the camera
            case .dine, .sip:
                if meal != nil, mealJelly == 0 {      // a finished meal (not a dropped one): the leftovers poof with the tray (each piece already paid for)
                    payPieces()
                    endMeal(); retries = 0
                }
            default: break
            }
        }
        finished.removeAll()

        // one-shot requests (a Call drops the meal first so the tray poofs and the held piece goes with it)
        if let r = queued.first {
            var isCome = false
            if case .come = r { isCome = true }
            if isCome, groupActive { cancelGroup() }
            if isCome, meal != nil { endMeal(); retries = 0 }
            if isCome, wanted != nil { wanted = nil; retries = 0; resetStandWalk() }        // a pending tray (he is still walking to his place) is dropped too
            if isCome, dining.isPresent {
                // the tray is poofing (its collider is already gone): he starts walking once it has gone, so he never walks through it
            } else {
                queued.removeFirst()
                brain.requestNow(r)
                if isCome { callRunning = true }
            }
        }

        // the meal for Jelly 0 (the other Jellies' meals run from `tickOthers`): GameCare+Dining.swift
        tickDining(id: 0, brain: brain, sim: sim, dt: dt)

        #if DEBUG || DINING_PREVIEW
        preview?.tick(dining: dining, bob: brain.position, dt: dt)
        #endif
        dining.update(dt: dt)
        if let room = renderer?.room, let f = dining.frame(theme: room.theme) { room.setDining(f) }
        let out = wanted != nil || meal != nil || dining.isPresent || groupActive
        if out != trayOut { trayOut = out }
        if !out, servingKind != nil { servingKind = nil }
        if bath.targetID == 0 { bath.tick(brain: brain, sim: sim, play: touchPlay, dt: dt) }         // another Jelly's clean-up ticks in tickOthers
        if !bath.active, !tripActive { voice.tick(care: self, brain: brain, sim: sim, dt: dt) }
    }
}

enum BubbleIcon: Equatable { case need(NeedKind), clean }

extension BlobBrain {
    /// Hurrying (thrown back to the focus spot), running, or one of the zoomies / slide / scoot moves: hunger and thirst drain faster and dirt builds 3x.
    var isExerting: Bool {
        if hurry || runW > 0.5 || zoomW > 0.1 { return true }
        switch idleState.kind { case .run, .zoomies, .slide, .scoot: return true; default: return false }
    }
}
