//
//  AITierBTests.swift
//  The rule parser (Tier B of natural voice commands): names, everyone, synonyms, objects (owned / unknown), partners, questions, and the
//  "not yet" actions. Runs against a catalog with a few decor / toy / wearable items added, the way the store and wardrobe will add theirs.
//

import XCTest
@testable import BobV1

@MainActor
final class AITierBTests: XCTestCase {
    private var suites: [String] = []
    private func names() -> JellyNames {
        let n = "AITierBTests.\(UUID().uuidString)"; suites.append(n)
        let names = JellyNames(defaults: UserDefaults(suiteName: n)!, key: "nick", persists: true)
        names.roster = [0, 1, 2, 3]          // slot == character, whatever roster the host app launched with
        return names
    }
    private var keepMap: [Int: Int] = [:], keepNames: [Int: String] = [:]
    override func setUp() { keepMap = JellyRoster.speciesMap; keepNames = JellyRoster.extraNames }
    override func tearDown() { JellyRoster.speciesMap = keepMap; JellyRoster.extraNames = keepNames; JellyNameRoster.alwaysNamed = 7; for n in suites { UserDefaults.standard.removePersistentDomain(forName: n) }; suites = [] }

    /// Foods and drinks from the game plus a beanbag, a ball and a pirate hat (the kinds other features will register).
    nonisolated static let catalog: AICatalog = {
        var c = AICatalogRegistry.catalog(jellies: [(0, "Bob"), (1, "Pip"), (2, "Moss")])
        c.items += [CatalogItem(id: "beanbag", name: "Beanbag", kind: .decor, aliases: ["bean bag"]),
                    CatalogItem(id: "rug", name: "Rug", kind: .decor),
                    CatalogItem(id: "ball", name: "Ball", kind: .toy),
                    CatalogItem(id: "pirate_hat", name: "Pirate hat", kind: .wearable, aliases: ["hat"])]
        return c
    }()
    /// The shipped catalog: no decor / toys / wearables yet.
    nonisolated static let bare = AICatalogRegistry.catalog(jellies: [(0, "Bob"), (1, "Pip"), (2, "Moss")])

    private func parse(_ s: String, catalog: AICatalog = AITierBTests.catalog) -> RuleParser.Result { RuleParser.parse(s, names: names(), catalog: catalog) }

    func testPhraseTable() {
        // (said, who, action, object, partner)
        let table: [(String, JellyWho, JellyAction, String?, Int?)] = [
            ("Bob, go sit on the beanbag", .jellies([0]), .goTo, "beanbag", nil),
            ("go to the bean bag", .selected, .goTo, "beanbag", nil),
            ("Pip, play soccer with Moss", .jellies([1]), .playWith, nil, 2),
            ("play ball with Pip", .selected, .playWith, "ball", 1),
            ("Moss play with Bob", .jellies([2]), .playWith, nil, 0),
            ("everyone come eat", .everyone, .feed, nil, nil),
            ("everybody, dinner time!", .everyone, .feed, nil, nil),
            ("all of you come eat", .everyone, .feed, nil, nil),
            ("you guys have a drink", .everyone, .drink, nil, nil),
            ("Moss, go to sleep", .jellies([2]), .sleep, nil, nil),
            ("Bob go to bed", .jellies([0]), .sleep, nil, nil),
            ("goodnight Pip", .jellies([1]), .sleep, nil, nil),
            ("night night everyone", .everyone, .sleep, nil, nil),
            ("take a nap", .selected, .sleep, nil, nil),
            ("wake up everyone", .everyone, .wake, nil, nil),
            ("good morning Pip", .jellies([1]), .wake, nil, nil),
            ("who's hungry?", .everyone, .whoIs(.hunger), nil, nil),
            ("who is thirsty", .everyone, .whoIs(.thirst), nil, nil),
            ("who wants a cuddle", .everyone, .whoIs(.attention), nil, nil),
            ("anyone hungry", .everyone, .whoIs(.hunger), nil, nil),
            ("Bob do a spin", .jellies([0]), .trick(.spin), nil, nil),
            ("spin around", .selected, .trick(.spin), nil, nil),
            ("Pippy twirl", .jellies([1]), .trick(.spin), nil, nil),
            ("hop hop Moss", .jellies([2]), .trick(.hop), nil, nil),
            ("go play with the ball", .selected, .playWith, "ball", nil),
            ("go to the ball", .selected, .playWith, "ball", nil),              // a toy is played with (the same kick as "go to")
            ("put on the pirate hat", .selected, .wear, "pirate_hat", nil),
            ("Bob wear your hat", .jellies([0]), .wear, "pirate_hat", nil),
            ("Pip eat some pizza", .jellies([1]), .feed, "pizza", nil),
            ("have some berries", .selected, .feed, "berries", nil),
            ("Moss, berries!", .jellies([2]), .feed, "berries", nil),
            ("drink some water", .selected, .drink, "water", nil),
            ("Bob have a sip of soda", .jellies([0]), .drink, "soda", nil),
            ("time to eat", .selected, .feed, nil, nil),
            ("Pip, feed", .jellies([1]), .feed, nil, nil),
            ("bath time Moss", .jellies([2]), .clean, nil, nil),
            ("Bob get clean", .jellies([0]), .clean, nil, nil),
            ("wash up everybody", .everyone, .clean, nil, nil),
            ("Pip do jumping jacks", .jellies([1]), .trick(.jacks), nil, nil),
            ("jump jump", .selected, .trick(.jacks), nil, nil),
            ("do a backflip", .selected, .trick(.flip), nil, nil),
            ("Moss, run around", .jellies([2]), .trick(.run), nil, nil),
            ("look around Bob", .jellies([0]), .trick(.look), nil, nil),
            ("Pip sit down", .jellies([1]), .trick(.sit), nil, nil),
            ("sit", .selected, .trick(.sit), nil, nil),
            ("let's race", .selected, .race, nil, nil),
            ("Bobby come here", .jellies([0]), .come, nil, nil),
            ("Pip and Moss come here", .jellies([1, 2]), .come, nil, nil),
            ("stop fighting you two", .everyone, .stopFighting, nil, nil),
            ("good boy Moss", .jellies([2]), .praise, nil, nil),
            ("no Pip", .jellies([1]), .scold, nil, nil),
            ("let's play", .selected, .play, nil, nil),
            ("go sit on the rug", .selected, .goTo, "rug", nil),
        ]
        XCTAssertGreaterThanOrEqual(table.count, 40)
        for (said, who, action, object, partner) in table {
            let r = parse(said)
            XCTAssertTrue(r.confident, "\(said): confident")
            XCTAssertEqual(r.command.who, who, said)
            XCTAssertEqual(r.command.action, action, said)
            XCTAssertEqual(r.command.object, object, said)
            XCTAssertEqual(r.command.partner, partner, said)
        }
    }

    func testUnknownObjectsAreKeptForTheNotYetLine() {
        let r = parse("Bob, go sit on the beanbag", catalog: Self.bare)
        XCTAssertEqual(r.command.action, .goTo)
        XCTAssertNil(r.command.object)
        XCTAssertEqual(r.command.unknownObject, "beanbag")
        XCTAssertFalse(r.command.isActionable, "go WHERE: no place to go")
        let w = parse("put on the pirate hat", catalog: Self.bare)
        XCTAssertEqual(w.command.action, .wear)
        XCTAssertEqual(w.command.unknownObject, "pirate hat")
        let s = parse("Pip, play soccer with Moss", catalog: Self.bare)
        XCTAssertEqual(s.command.action, .playWith)
        XCTAssertEqual(s.command.partner, 2)
        XCTAssertEqual(s.command.unknownObject, "soccer")
        XCTAssertTrue(s.command.isActionable, "a partner is enough; the game says soccer is not here yet")
    }

    func testFreePhrasingIsNotConfident() {
        for said in ["the weather is nice", "banana", "what a lovely creature you are", "I had a long day", "I think the green one looks tired", "very slow phrase"] {
            let r = parse(said)
            XCTAssertFalse(r.confident, said)
            XCTAssertEqual(r.command.action, .none, said)
        }
        XCTAssertEqual(parse("").command.action, .none)
    }

    func testNicknamesAndNearMissesName() {
        let n = names()
        n.addNickname("bubbles", for: 1)
        let r = RuleParser.parse("bubbles go to sleep", names: n, catalog: Self.catalog)
        XCTAssertEqual(r.command.who, .jellies([1]))
        XCTAssertEqual(r.command.action, .sleep)
        XCTAssertEqual(parse("Bab come eat").command.who, .jellies([0]), "a recogniser near-miss of Bob")
    }

    func testPartnerIsNotATarget() {
        let r = parse("Bob play with Moss")
        XCTAssertEqual(r.command.who, .jellies([0]))
        XCTAssertEqual(r.command.partner, 2)
        let r2 = parse("play with Pip")
        XCTAssertEqual(r2.command.who, .selected)
        XCTAssertEqual(r2.command.partner, 1)
    }

    func testSummaryLine() {
        let n: (Int) -> String = { ["Bob", "Pip", "Moss"][$0] }
        XCTAssertEqual(parse("Moss, go to sleep").command.summary(names: n), "Moss: sleep")
        XCTAssertEqual(parse("everyone come eat").command.summary(names: n), "Everyone: eat")
        XCTAssertEqual(parse("Pip eat some pizza").command.summary(names: n), "Pip: eat pizza")
        XCTAssertEqual(parse("Pip, play soccer with Moss", catalog: Self.bare).command.summary(names: n), "Pip: play soccer with Moss")
    }

    // MARK: a name that is also a catalog word ("Berry") and a species name that is only a name when one is at home

    /// Home: Pip (slot 0), Moss (slot 1) and a second Bob called "Berry" (slot 2, instance 100). The catalog has the berries food and a "Berry smoothie" drink.
    private func berryRoom(berryHome: Bool) -> (JellyNames, AICatalog) {
        JellyRoster.speciesMap[100] = 0; JellyRoster.extraNames[100] = "Berry"
        let n = JellyNames(defaults: UserDefaults(suiteName: "AITierBTests.berry.\(UUID().uuidString)")!, key: "nick", persists: false)
        n.roster = berryHome ? [1, 2, 100] : [1, 2, 3]
        var c = AICatalogRegistry.catalog(jellies: [(0, "Pip"), (1, "Moss"), (2, berryHome ? "Berry" : "Lavender")])
        c.items.append(CatalogItem(id: "smoothie", name: "Berry smoothie", kind: .drink))
        return (n, c)
    }
    func testACreatureNamedBerryAtHomeIsTheNameFirstAndTheFoodAfterSomeoneIsNamed() {
        let (n, c) = berryRoom(berryHome: true)
        func p(_ s: String) -> JellyCommand { RuleParser.parse(s, names: n, catalog: c).command }
        XCTAssertEqual(p("give Pip a berry").who, .jellies([0])); XCTAssertEqual(p("give Pip a berry").object, "berries"); XCTAssertEqual(p("give Pip a berry").action, .feed)
        XCTAssertEqual(p("Berry sit").who, .jellies([2]), "nobody named yet: the name")
        XCTAssertEqual(p("give Berry a berry").who, .jellies([2])); XCTAssertEqual(p("give Berry a berry").object, "berries"); XCTAssertEqual(p("give Berry a berry").action, .feed)
        XCTAssertEqual(p("Pip, give Moss some berries").who, .jellies([0, 1])); XCTAssertEqual(p("Pip, give Moss some berries").object, "berries")
        let smoothie = p("Pip drink a berry smoothie"); XCTAssertEqual(smoothie.who, .jellies([0])); XCTAssertEqual(smoothie.object, "smoothie"); XCTAssertEqual(smoothie.action, .drink)
        XCTAssertEqual(p("berry smoothie").who, .selected, "an item's whole name wins over the creature's name")
        XCTAssertEqual(p("berries").who, .selected, "'berries' is not her name"); XCTAssertEqual(p("berries").object, "berries")
    }
    func testWithNoBerryAtHomeTheWordIsAlwaysTheFood() {
        let (n, c) = berryRoom(berryHome: false)
        func p(_ s: String) -> JellyCommand { RuleParser.parse(s, names: n, catalog: c).command }
        XCTAssertEqual(p("give Pip a berry").who, .jellies([0])); XCTAssertEqual(p("give Pip a berry").object, "berries")
        XCTAssertEqual(p("a berry please").object, "berries")
        XCTAssertEqual(p("berries").object, "berries"); XCTAssertEqual(p("drink a berry smoothie").object, "smoothie")
        for s in ["berries", "berry smoothie", "a berry"] { XCTAssertEqual(p(s).who, .selected, s) }
    }
    func testAGrownUpBaseNameIsOnlyANameWhileOneIsHomeButTodaysSevenAlwaysAre() {
        let n = JellyNames(defaults: UserDefaults(suiteName: "AITierBTests.base.\(UUID().uuidString)")!, key: "nick", persists: false)
        n.roster = [0, 1, 2]
        XCTAssertEqual(n.match(token: "teddy")?.id, JellyNames.absentID(4), "today's species: a name said for one who is not here is still heard (the confused look)")
        JellyNameRoster.alwaysNamed = 4          // Teddy, Pearl and Panda stand in for species added later
        XCTAssertNil(n.match(token: "teddy"), "not at home: not a name"); XCTAssertNil(n.match(token: "pearl")); XCTAssertNil(n.match(token: "pan da")); XCTAssertNil(n.match(token: "pandy"))
        XCTAssertEqual(n.match(token: "bob")?.id, 0, "the seven that exist today are unchanged")
        XCTAssertFalse(n.priorityWords.contains("teddy")); XCTAssertFalse(n.contextualWords.contains("teddy"))
        XCTAssertNil(n.resolve(tokens: ["pan", "da"]).first)
        n.roster = [0, 1, 4]
        XCTAssertEqual(n.match(token: "teddy")?.id, 2, "at home: the name"); XCTAssertEqual(n.match(token: "teddie")?.id, 2)
        XCTAssertTrue(n.priorityWords.contains("teddy"))
        n.roster = [0, 1, 6]
        XCTAssertEqual(n.resolve(tokens: ["pan", "da"]).first?.id, 2, "the split-in-two form works while Panda is at home")
        XCTAssertNil(n.match(token: "teddy"), "Teddy at Camp or not owned: not a name")
    }
}
