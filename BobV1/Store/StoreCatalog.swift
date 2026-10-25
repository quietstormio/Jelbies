//
//  StoreCatalog.swift
//  The store's goods as DATA: id, name, kind, price in Drops, perk, description. Drops are earned only (races now, more games later), never bought
//  with money, so there is no purchase code anywhere. Prices: a race pays 12 / 7 / 4, so about two races buy a treat, a week of play a big decor piece.
//
//  Kinds: food and treat (hand-held snacks fed from the inventory through the normal toss-into-the-mouth dining), supply (soaps and sprays used in
//  Clean), trick page (unlocks a voice trick), shoes (a wearable look, no speed effect), decor (part B: placeable room pieces Jellies play with; each
//  takes 1 or 2 of the room's `StoreTuning.roomCapacity` spots; Room/DecorModel.swift).
//

import Foundation

nonisolated enum StoreKind: String, CaseIterable, Codable, Sendable {
    case food, treat, supply, trickPage, shoes, wear, decor, room, seed
    var title: String {
        switch self {
        case .food: return "Food"; case .treat: return "Treats"; case .supply: return "Care"; case .trickPage: return "Tricks"
        case .shoes: return "Shoes"; case .wear: return "Wear"; case .decor: return "Decor"; case .room: return "Rooms"; case .seed: return "Seeds"
        }
    }
    var symbol: String {
        switch self {
        case .food: return "fork.knife"; case .treat: return "birthday.cake.fill"; case .supply: return "sparkles"; case .trickPage: return "book.fill"
        case .shoes: return "shoeprints.fill"; case .wear: return "crown.fill"; case .decor: return "chair.lounge.fill"; case .room: return "house.fill"; case .seed: return "camera.macro"
        }
    }
}

/// Where on the body a wearable goes (one look per slot per Jelly). Hats and headbands are `head`, glasses `face`, bow ties / scarves / medals `neck`,
/// mittens and wristbands `hands`, bibs / sashes / capes / tutus / backpacks `body`, shoes `feet`.
nonisolated enum WearSlot: String, CaseIterable, Codable, Sendable {
    case head, face, feet, neck, hands, body
    var title: String {
        switch self {
        case .head: return "Hats"; case .face: return "Faces"; case .feet: return "Shoes"; case .neck: return "Necks"; case .hands: return "Hands"; case .body: return "Bodies"
        }
    }
    var symbol: String {
        switch self {
        case .head: return "crown.fill"; case .face: return "eyeglasses"; case .feet: return "shoeprints.fill"; case .neck: return "bandage.fill"
        case .hands: return "hand.raised.fill"; case .body: return "tshirt.fill"
        }
    }
}

nonisolated enum StoreTuning {
    /// First open: one time, so the store is never empty-handed.
    static let starterDrops = 40
    /// Decor: how many room spots the placed decor may use (a big piece takes 2).
    static let roomCapacity = 10
    /// The beanbag's modest room perk ("Cozy-lite"): while one is placed, attention (love) drains at this fraction. Like every slowing perk the strongest
    /// wins (it does not stack with the Cozy snack's x0.5), and it applies while the game runs, not to the time away.
    static let beanbagAttentionDrain = 0.85
    /// Rooms (bought once with earned Drops; the home room is free). A Puddle win pays 12 and a Wave win 22, adoption costs 120 / 180 / 240 and the
    /// loveseat 120, so a room is a long-term goal: about 15 to 25 race wins.
    static let roomPrices: [RoomID: Int] = [.loft: 300, .cabin: 400, .garden: 250]
}

nonisolated struct StoreItem: Identifiable, Sendable {
    let id: String
    let name: String
    let kind: StoreKind
    let price: Int
    let perk: PerkKind?
    let description: String
    /// SF Symbol for the card when no 3D thumbnail applies.
    let symbol: String
    /// Food / treat: the Consumable id it feeds.
    var food: String? = nil
    /// Trick page: the trick it unlocks.
    var trick: VoiceTrick? = nil
    /// Shoes (and later other wearables).
    var wear: WearLook? = nil
    /// Decor (part B): room units it takes.
    var roomUnits = 0
    /// A room to live in (Room/RoomDef.swift).
    var room: RoomID? = nil
    /// Bought once and kept (pages, wearables, rooms; decor placement is part B) as opposed to stacked and used up.
    var unique: Bool { kind == .trickPage || kind == .shoes || kind == .wear || kind == .room }
    /// A wearable that is earned, not sold (the winner medal): never listed in the shop.
    var awarded = false
    var isWearable: Bool { kind == .shoes || kind == .wear }
    /// Decor: the piece this is.
    var decor: DecorKind? { kind == .decor ? DecorKind(storeID: id) : nil }
}

nonisolated enum StoreCatalog {
    static let items: [StoreItem] = base + batch2 + wearItems + roomItems + gardenItems

    /// The rooms for sale (home is never sold).
    static let roomItems: [StoreItem] = [
        StoreItem(id: "room-loft", name: RoomCatalog.loft.title, kind: .room, price: StoreTuning.roomPrices[.loft] ?? 300, perk: nil, description: RoomCatalog.loft.blurb, symbol: "sun.max.fill", room: .loft),
        StoreItem(id: "room-cabin", name: RoomCatalog.cabin.title, kind: .room, price: StoreTuning.roomPrices[.cabin] ?? 400, perk: nil, description: RoomCatalog.cabin.blurb, symbol: "flame.fill", room: .cabin),
        StoreItem(id: "room-garden", name: RoomCatalog.garden.title, kind: .room, price: StoreTuning.roomPrices[.garden] ?? 250, perk: nil, description: RoomCatalog.garden.blurb, symbol: "camera.macro", room: .garden),
    ]

    /// The second batch of furniture and toys (prices and spots from the Blender exports' JSON).
    private static let batch2: [StoreItem] = [
        (DecorKind.loveseat, 120, "sofa.fill"), (.petbed, 90, "bed.double.fill"), (.pouf, 40, "circle.circle.fill"), (.rockingchair, 80, "chair.fill"),
        (.armchair, 70, "chair.lounge.fill"), (.swing, 100, "figure.play"), (.diningset, 85, "fork.knife"), (.bookshelf, 65, "books.vertical.fill"),
        (.wardrobe, 75, "cabinet.fill"), (.divider, 60, "rectangle.split.3x1.fill"), (.floorlamp, 55, "lamp.floor.fill"), (.slide, 110, "arrow.down.right.circle.fill"),
        (.monstera, 70, "leaf.fill"), (.duck, 25, "bird.fill"), (.blocks, 35, "cube.fill"), (.spintop, 30, "tornado"), (.toycar, 50, "car.fill"),
        (.yarnball, 25, "scribble.variable"), (.drum, 45, "drum.fill"),
        // soccer (2026-10-20, replaces the football): the ball and the mini goal
        (.soccerball, 35, "soccerball"), (.minigoal, 70, "sportscourt.fill"),
    ].map { StoreItem(id: $0.0.storeID, name: $0.0.title, kind: .decor, price: $0.1, perk: nil, description: $0.0.use, symbol: $0.2, roomUnits: $0.0.spec.units) }

    private static let base: [StoreItem] = [
        // food (hand-held, tossed into his mouth)
        StoreItem(id: "nuggets", name: "Chicken nuggets", kind: .food, price: 12, perk: .fullBelly, description: "Crispy and filling. Hunger falls slower for 4 hours.", symbol: "fork.knife", food: "nuggets"),
        StoreItem(id: "fries", name: "Fries", kind: .food, price: 10, perk: .bouncy, description: "Salty and fun. More bouncing for an hour.", symbol: "fork.knife", food: "fries"),
        StoreItem(id: "sushi", name: "Sushi roll", kind: .food, price: 18, perk: .cozy, description: "Calm and cozy. Stays happy longer for 4 hours.", symbol: "fork.knife", food: "sushi"),
        StoreItem(id: "sandwich", name: "Sandwich", kind: .food, price: 14, perk: .focus, description: "Brain food. Fewer stumbles in the next race.", symbol: "fork.knife", food: "sandwich"),
        StoreItem(id: "minipizza", name: "Mini pizza", kind: .food, price: 14, perk: .social, description: "Share the slices. Plays with the others more for an hour.", symbol: "fork.knife", food: "minipizza"),
        StoreItem(id: "taco", name: "Taco", kind: .food, price: 15, perk: .zoomies, description: "Spicy! Zoomies now and a quicker next race.", symbol: "fork.knife", food: "taco"),
        // treats
        StoreItem(id: "donut", name: "Donut", kind: .treat, price: 14, perk: .zoomies, description: "Sugar rush! Zoomies now and a quicker next race.", symbol: "birthday.cake.fill", food: "donut"),
        StoreItem(id: "popsicle", name: "Ice pop", kind: .treat, price: 12, perk: .cozy, description: "Cool and calm. Stays happy longer for 4 hours.", symbol: "birthday.cake.fill", food: "popsicle"),
        StoreItem(id: "onigiri", name: "Onigiri", kind: .treat, price: 12, perk: .fullBelly, description: "A rice ball. Hunger falls slower for 4 hours.", symbol: "birthday.cake.fill", food: "onigiri"),
        StoreItem(id: "cookie", name: "Bedtime cookie", kind: .treat, price: 10, perk: .bedtime, description: "Falls asleep fast and sleeps deep for 8 hours.", symbol: "moon.zzz.fill", food: "cookie"),
        // care supplies (used from Clean)
        StoreItem(id: "lavender", name: "Lavender soap", kind: .supply, price: 20, perk: .shine, description: "The shine after a Clean lasts much longer (12 hours).", symbol: "sparkles"),
        StoreItem(id: "lintguard", name: "Lint-guard spray", kind: .supply, price: 18, perk: .tidy, description: "Lint comes back half as fast for 6 hours.", symbol: "wind"),
        // trick pages
        StoreItem(id: "page-spin", name: "Spin page", kind: .trickPage, price: 45, perk: nil, description: "Teach a spin on the spot with your own word.", symbol: "arrow.triangle.2.circlepath", trick: .spin),
        StoreItem(id: "page-hop", name: "Hop page", kind: .trickPage, price: 45, perk: nil, description: "Teach happy hops with your own word.", symbol: "arrow.up.circle.fill", trick: .hop),
        StoreItem(id: "page-roll", name: "Roll page", kind: .trickPage, price: 55, perk: nil, description: "Teach a sideways roll with your own word.", symbol: "arrow.left.arrow.right.circle.fill", trick: .roll),
        // decor (placed in the room; Jellies play with it; a big piece takes 2 of the 10 spots)
        StoreItem(id: "decor-cushion", name: "Floor cushion", kind: .decor, price: 25, perk: nil, description: DecorKind.cushion.use, symbol: "square.fill", roomUnits: 1),
        StoreItem(id: "decor-ball", name: "Bouncy ball", kind: .decor, price: 30, perk: nil, description: DecorKind.ball.use, symbol: "circle.fill", roomUnits: 1),
        StoreItem(id: "decor-rug", name: "Small rug", kind: .decor, price: 30, perk: nil, description: DecorKind.rug.use, symbol: "oval.fill", roomUnits: 1),
        StoreItem(id: "decor-plant", name: "Potted plant", kind: .decor, price: 35, perk: nil, description: DecorKind.plant.use, symbol: "leaf.fill", roomUnits: 1),
        StoreItem(id: "decor-nightlight", name: "Night light", kind: .decor, price: 45, perk: nil, description: DecorKind.nightlight.use, symbol: "moon.stars.fill", roomUnits: 1),
        StoreItem(id: "decor-toybox", name: "Toy box", kind: .decor, price: 55, perk: nil, description: DecorKind.toybox.use, symbol: "shippingbox.fill", roomUnits: 1),
        StoreItem(id: "decor-beanbag", name: "Beanbag", kind: .decor, price: 70, perk: nil, description: DecorKind.beanbag.use, symbol: "chair.lounge.fill", roomUnits: 2),
        StoreItem(id: "decor-bouncymat", name: "Bouncy mat", kind: .decor, price: 90, perk: nil, description: DecorKind.bouncymat.use, symbol: "arrow.up.circle.fill", roomUnits: 2),
    ]

    static func item(_ id: String) -> StoreItem? { items.first { $0.id == id } }
    /// The store item of a wearable look.
    static func item(wearing look: WearLook) -> StoreItem? { items.first { $0.wear == look } }
    static func items(_ k: StoreKind) -> [StoreItem] { items.filter { $0.kind == k } }
    /// The decor of one Shop / Bag tab (furniture or toys).
    static func decorItems(_ c: DecorKind.Category) -> [StoreItem] { items.filter { $0.decor?.category == c } }
    /// Every wearable, built from the Blender art table (WearGenerated.swift): shoes keep their original ids, the rest are `wear-<art id>`.
    /// The winner medal is awarded for a first place on the Circuit and never sold.
    static let wearItems: [StoreItem] = WearGenerated.rows.map { r in
        StoreItem(id: r.storeID, name: r.title, kind: r.slot == .feet ? .shoes : .wear, price: r.price, perk: nil, description: WearInfo.blurb(r),
                  symbol: r.slot.symbol, wear: r.look, awarded: r.look == .medalGold)
    }

    /// Tabs the store shows (a kind with no items stays hidden).
    static var tabs: [StoreKind] { StoreKind.allCases.filter { !items($0).isEmpty } }
    /// The item that feeds consumable `id` (nil for the free berries / pizza).
    static func item(forFood id: String) -> StoreItem? { items.first { $0.food == id } }
}
