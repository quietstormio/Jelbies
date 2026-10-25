//
//  StoreBook.swift
//  What the player owns: counts of food / treats / supplies, unlocked trick pages, wearables and who wears what. Persisted (UserDefaults, JSON, like the
//  roster). Buying spends Drops from the DropsWallet; the starter balance is granted once on first open. Nothing here ever touches money.
//

import Foundation
import Observation

nonisolated enum BuyResult: Equatable, Sendable { case bought, notEnough, alreadyOwned, unknown }

@MainActor
@Observable
final class StoreBook {
    struct Saved: Codable {
        var counts: [String: Int] = [:]
        var pages: [String] = []
        var wearables: [String] = []
        /// Jelly id -> slot -> look.
        var worn: [String: [String: String]] = [:]
        var starterGiven = false
        /// Goods bought since the bag was last opened (the Bag button's badge).
        var newItems = 0
        /// (Unused: the first sketch of decor placement; kept so older saves decode.)
        var placed: [String] = []
        /// Decor placed in the room, with positions. Optional so a save written before decor existed still decodes (never reset the player's goods).
        var placedAt: [PlacedDecor]? = nil
        var nextDecorUID: Int? = nil
        /// Wearables won rather than bought (the winner medal). Optional: a save from before the wardrobe decodes without it.
        var awarded: [String]? = nil
        /// The hoodie / raincoat refund (WearLook.unlisted) was paid.
        var unlistedRefunded: Bool? = nil
        /// Rooms bought (RoomID raw values; home is always owned). Optional: an older save decodes without it.
        var rooms: [String]? = nil
        /// Where the Jelbies live now (nil = home).
        var room: String? = nil
        /// The placed decor of every room except the current one (`placedAt` is the current room's list).
        var stash: [String: [PlacedDecor]]? = nil
        /// The removed Garden's room price was refunded (once). Optional: older saves decode without it.
        var gardenRefunded: Bool? = nil
    }
    static let key = "StoreBook.v1"

    private(set) var saved = Saved()
    let wallet: DropsWallet
    /// Bumped on every change (views and the shoe set read it).
    private(set) var revision = 0

    @ObservationIgnored private let persists: Bool
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let storeKey: String

    nonisolated deinit {}

    init(wallet: DropsWallet, persists: Bool = true, defaults: UserDefaults = .standard, key: String = StoreBook.key) {
        self.wallet = wallet; self.persists = persists; self.defaults = defaults; storeKey = key
        if persists, let d = defaults.data(forKey: key), let s = try? JSONDecoder().decode(Saved.self, from: d) { saved = Self.migrateSoccer(s); saved.worn = Self.dedupeWorn(saved.worn)
            let (kept, refund) = Self.dropUnlisted(saved)
            if kept.unlistedRefunded != saved.unlistedRefunded { saved = kept; if refund > 0 { wallet.add(refund, silent: true) }; save() } }
        if migrateGarden() { save() }
        if persists { defaults.removeObject(forKey: "Garden.v1") }          // the removed Garden's plots
    }

    /// The Garden was removed: seeds are refunded at their old prices, garden fruit dropped, the room unowned (250 Drops back once if it was bought) and the
    /// Jelbies moved home. Idempotent; true when anything changed.
    private func migrateGarden() -> Bool {
        var changed = false
        let seedPrices: [String: Int] = ["seed-daisy": 6, "seed-tulip": 8, "seed-rose": 12, "seed-strawberry": 10, "seed-blueberry": 10]
        var refund = 0
        for k in saved.counts.keys where k.hasPrefix("seed-") || k == "strawberry" || k == "gardenberries" {
            let n = max(saved.counts[k] ?? 0, 0)
            if k.hasPrefix("seed-") { refund += n * (seedPrices[k] ?? 8) }
            saved.counts[k] = nil; changed = true
        }
        if saved.room == "garden" { saved.room = nil; changed = true }
        if saved.stash?["garden"] != nil { saved.stash?["garden"] = nil; if saved.stash?.isEmpty == true { saved.stash = nil }; changed = true }
        if let r = saved.rooms, r.contains("garden") {
            saved.rooms = r.filter { $0 != "garden" }
            if saved.gardenRefunded != true { saved.gardenRefunded = true; refund += 250 }
            changed = true
        }
        if refund > 0 { wallet.add(refund, silent: true) }
        return changed
    }

    /// Old saves: a look worn by several characters stays only on the first (sorted key order).
    static func dedupeWorn(_ worn: [String: [String: String]]) -> [String: [String: String]] {
        var out = worn, seen = Set<String>()
        for k in worn.keys.sorted() {
            for (slot, look) in worn[k] ?? [:] {
                if seen.contains(look) { out[k]?[slot] = nil } else { seen.insert(look) }
            }
        }
        return out
    }

    private func save() {
        revision += 1
        guard persists, let d = try? JSONEncoder().encode(saved) else { return }
        defaults.set(d, forKey: storeKey)
    }

    // MARK: starter

    /// First open: 40 Drops, once (never again, even at 0).
    @discardableResult
    func grantStarterIfNeeded() -> Bool {
        guard !saved.starterGiven else { return false }
        saved.starterGiven = true
        wallet.add(StoreTuning.starterDrops, silent: true)
        save()
        return true
    }

    // MARK: queries

    var newCount: Int { saved.newItems }
    func markSeen() { if saved.newItems != 0 { saved.newItems = 0; save() } }

    func count(_ id: String) -> Int { saved.counts[id] ?? 0 }
    func count(food id: String) -> Int { StoreCatalog.item(forFood: id).map { count($0.id) } ?? 0 }
    func owns(_ item: StoreItem) -> Bool {
        switch item.kind {
        case .trickPage: return item.trick.map { saved.pages.contains($0.rawValue) } ?? false
        case .shoes, .wear: return item.wear.map { saved.wearables.contains($0.rawValue) } ?? false
        case .room: return item.room.map { ownsRoom($0) } ?? false
        default: return count(item.id) > 0
        }
    }
    /// How many the player has ("owned xN"); 1 for a unique thing they own.
    func owned(_ item: StoreItem) -> Int { item.unique ? (owns(item) ? 1 : 0) : count(item.id) }
    func hasPage(_ t: VoiceTrick) -> Bool { t.isStarter || saved.pages.contains(t.rawValue) }
    func ownsLook(_ l: WearLook) -> Bool { saved.wearables.contains(l.rawValue) }
    /// Foods the player can feed now (count > 0), in catalogue order.
    var snacks: [(item: StoreItem, count: Int)] {
        StoreCatalog.items.compactMap { i in i.food != nil && count(i.id) > 0 ? (i, count(i.id)) : nil }
    }

    // MARK: buy / use

    @discardableResult
    func buy(_ id: String) -> BuyResult {
        guard let item = StoreCatalog.item(id) else { return .unknown }
        if item.awarded { return .unknown }               // earned, never sold
        if item.unique, owns(item) { return .alreadyOwned }
        guard wallet.spend(item.price) else { return .notEnough }
        switch item.kind {
        case .trickPage: if let t = item.trick { saved.pages.append(t.rawValue) }
        case .shoes, .wear: if let w = item.wear { saved.wearables.append(w.rawValue) }
        case .room: if let r = item.room { saved.rooms = (saved.rooms ?? []) + [r.rawValue] }
        default: saved.counts[id, default: 0] += 1
        }
        saved.newItems += 1
        save()
        return .bought
    }

    /// Uses up one of `id`; false when there is none.
    @discardableResult
    func use(_ id: String) -> Bool {
        guard count(id) > 0 else { return false }
        saved.counts[id, default: 1] -= 1
        if saved.counts[id] == 0 { saved.counts[id] = nil }
        save()
        return true
    }
    /// Test / capture hook: adds goods without paying.
    func grant(_ id: String, _ n: Int = 1) {
        guard let item = StoreCatalog.item(id) else { return }
        switch item.kind {
        case .trickPage: if let t = item.trick, !saved.pages.contains(t.rawValue) { saved.pages.append(t.rawValue) }
        case .shoes, .wear: if let w = item.wear, !saved.wearables.contains(w.rawValue) { saved.wearables.append(w.rawValue) }
        case .room: if let r = item.room, !ownsRoom(r) { saved.rooms = (saved.rooms ?? []) + [r.rawValue] }
        default: saved.counts[id, default: 0] += n
        }
        save()
    }

    // MARK: awards

    /// A first place on the Circuit: the winner medal is awarded (once) and can then be worn. True when it is new.
    @discardableResult
    func awardMedal() -> Bool {
        let m = WearLook.medal
        guard !ownsLook(m) else { return false }
        saved.wearables.append(m.rawValue)
        saved.awarded = (saved.awarded ?? []) + [m.rawValue]
        saved.newItems += 1
        save()
        return true
    }

    // MARK: wearing

    /// The fitting room: a piece tried on one Jelly before it is bought (never saved, never owned). Every reader of `worn` sees it, so the real
    /// renderers draw the try-on with no extra render code.
    @ObservationIgnored var fitting: (jelly: Int, look: WearLook)?
    /// Slot in the room -> CHARACTER (JellyRoster): what a Jelbie wears is saved by character, so it follows him when the roster changes.
    /// GameCare sets it from its profiles; identity (the default roster) otherwise.
    @ObservationIgnored var characterOf: (Int) -> Int = { $0 }
    private func wornKey(_ jelly: Int) -> String { "\(characterOf(jelly))" }

    func worn(_ jelly: Int, _ slot: WearSlot) -> WearLook? {
        if let f = fitting, f.jelly == jelly, f.look.slot == slot { return f.look }
        return saved.worn[wornKey(jelly)]?[slot.rawValue].flatMap(WearLook.init(rawValue:))
    }
    /// The room slot whose SAVED outfit has this look on (not the fitting try-on), if any.
    func wearer(_ look: WearLook, among count: Int = 3) -> Int? {
        (0..<count).first { saved.worn[wornKey($0)]?[look.slot.rawValue] == look.rawValue }
    }
    /// Puts a look on a Jelly (must be owned). Replaces whatever he wore in that slot.
    @discardableResult
    func wear(_ look: WearLook, on jelly: Int) -> Bool {
        guard ownsLook(look) else { return false }
        // One owner per look: taking it off whoever else had it.
        for k in Array(saved.worn.keys) where k != wornKey(jelly) {
            for (slot, v) in saved.worn[k] ?? [:] where v == look.rawValue { saved.worn[k]?[slot] = nil }
        }
        saved.worn[wornKey(jelly), default: [:]][look.slot.rawValue] = look.rawValue
        save()
        return true
    }
    /// Everything one Jelly wears, by slot (slots with nothing are absent).
    func outfit(_ jelly: Int) -> [WearSlot: WearLook] {
        var o: [WearSlot: WearLook] = [:]
        for s in WearSlot.allCases { if let l = worn(jelly, s) { o[s] = l } }
        return o
    }
    func takeOff(_ slot: WearSlot, from jelly: Int) {
        saved.worn[wornKey(jelly)]?[slot.rawValue] = nil
        save()
    }

    // MARK: decor

    var placedDecor: [PlacedDecor] { saved.placedAt ?? [] }
    var roomUnitsUsed: Int { placedDecor.reduce(0) { $0 + $1.kind.spec.units } }
    /// How many of `id` stand in a room: this room and every other (a single owned cushion sits in one room at a time).
    func placedCount(_ id: String) -> Int {
        placedDecor.filter { $0.kind.storeID == id }.count + (saved.stash ?? [:]).values.reduce(0) { $0 + $1.filter { $0.kind.storeID == id }.count }
    }
    /// Owned and not in the room.
    func unplaced(_ id: String) -> Int { max(count(id) - placedCount(id), 0) }
    func canPlace(_ item: StoreItem) -> Bool {
        guard let k = item.decor, unplaced(item.id) > 0, roomUnitsUsed + k.spec.units <= StoreTuning.roomCapacity else { return false }
        return DecorPlacement.findSpot(k, among: placedDecor) != nil
    }
    /// Why a piece cannot be placed (nil = it can).
    func placeBlocker(_ item: StoreItem) -> String? {
        guard let k = item.decor else { return "Not decor" }
        if unplaced(item.id) == 0 { return "All of them are in the room" }
        if roomUnitsUsed + k.spec.units > StoreTuning.roomCapacity { return "The room is full. Put something away first." }
        if DecorPlacement.findSpot(k, among: placedDecor) == nil { return "No free floor for it. Move something." }
        return nil
    }

    /// Puts one of `id` on the floor at the free spot. nil = cannot.
    @discardableResult
    func place(_ id: String) -> PlacedDecor? {
        guard let item = StoreCatalog.item(id), canPlace(item), let k = item.decor, let at = DecorPlacement.findSpot(k, among: placedDecor) else { return nil }
        let uid = (saved.nextDecorUID ?? 1)
        saved.nextDecorUID = uid + 1
        let p = PlacedDecor(uid: uid, kind: k, x: at.x, z: at.y)
        saved.placedAt = placedDecor + [p]
        save()
        return p
    }
    /// Moves a placed piece to `at` when the spot is valid (the finger's drag); false = not there.
    @discardableResult
    func move(_ uid: Int, to at: SIMD2<Float>) -> Bool {
        guard var list = saved.placedAt, let i = list.firstIndex(where: { $0.uid == uid }) else { return false }
        guard DecorPlacement.isValid(list[i].kind, at: at, among: list, ignoring: uid, quarter: list[i].quarter) else { return false }
        list[i].x = at.x; list[i].z = at.y
        saved.placedAt = list
        save()
        return true
    }
    /// Turns a placed piece a quarter turn, nudged to the nearest spot where it fits; false = it fits nowhere near (nothing changes).
    @discardableResult
    func rotate(_ uid: Int) -> Bool {
        guard var list = saved.placedAt, let i = list.firstIndex(where: { $0.uid == uid }) else { return false }
        let q = (list[i].quarter + 1) & 3
        guard let at = DecorPlacement.spotAfterTurn(list[i].kind, at: list[i].at, quarter: q, among: list, ignoring: uid) else { return false }
        list[i].x = at.x; list[i].z = at.y; list[i].turns = q
        saved.placedAt = list
        save()
        return true
    }
    /// A rolling ball came to rest: its piece stays where it stopped (no checks: the ball only rolls on free floor).
    func setPosition(_ uid: Int, _ at: SIMD2<Float>) {
        guard var list = saved.placedAt, let i = list.firstIndex(where: { $0.uid == uid }) else { return }
        list[i].x = at.x; list[i].z = at.y
        saved.placedAt = list
        save()
    }
    /// Back into the bag.
    func putAway(_ uid: Int) {
        guard var list = saved.placedAt, let i = list.firstIndex(where: { $0.uid == uid }) else { return }
        list.remove(at: i)
        saved.placedAt = list
        save()
    }
    /// Everything in THIS room back into the bag (the other rooms keep their furniture).
    func putAwayAll() { if !placedDecor.isEmpty { saved.placedAt = []; save() } }
    /// The beanbag perk is on.
    var beanbagPlaced: Bool { placedDecor.contains { $0.kind == .beanbag } }

    // MARK: rooms

    /// The room the Jelbies live in (home until they move).
    var currentRoom: RoomID { saved.room.flatMap(RoomID.init(rawValue:)) ?? .home }
    func ownsRoom(_ id: RoomID) -> Bool { id == .home || (saved.rooms ?? []).contains(id.rawValue) }
    /// Home first, then the bought rooms in catalogue order.
    var ownedRooms: [RoomID] { RoomID.allCases.filter { ownsRoom($0) } }
    /// Moves the Jelbies into an owned room: this room's decor is stashed and the new room's comes back (an unvisited room is empty).
    @discardableResult
    func moveIn(_ id: RoomID) -> Bool {
        guard id != .cafe, id != .beach, ownsRoom(id) else { return false }          // the café is a visit, never a home
        let cur = currentRoom
        guard id != cur else { return true }
        var stash = saved.stash ?? [:]
        stash[cur.rawValue] = placedDecor
        saved.placedAt = stash[id.rawValue] ?? []
        stash[id.rawValue] = nil
        saved.stash = stash.isEmpty ? nil : stash
        saved.room = id == .home ? nil : id.rawValue
        save()
        return true
    }
}
