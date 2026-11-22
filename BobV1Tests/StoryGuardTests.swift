//
//  StoryGuardTests.swift
//  Every rule of StoryGuard with a passing and a failing sample; the placeholder round trip; a bad word smuggled through a name never reaches the guard as writer text.
//

import XCTest
@testable import BobV1

final class StoryGuardTests: XCTestCase {
    private let offered: Set<String> = ["A", "B", "FOOD", "ACT", "SPOT", "EMOTE", "RACE", "SHOW", "PERS", "BKIND"]
    private func tmpl(_ t: String, _ k: StoryKind = .about, shown: String? = nil) -> StoryVerdict {
        let f = StoryFill.apply(t, ["A": "Berry", "B": "Latte", "FOOD": "cookies", "ACT": "bouncing about", "SPOT": "by the window", "EMOTE": "playing chase", "RACE": "Puddle", "SHOW": "Pond", "PERS": "sleepy", "BKIND": "Blush"])
        return StoryGuard.check(template: t, final: f, kind: k, offered: offered, shown: shown, checkTone: false)
    }
    private func reason(_ t: String, _ k: StoryKind = .about, shown: String? = nil) -> StoryReason? { if case .reject(let r) = tmpl(t, k, shown: shown) { return r }; return nil }

    func testGoodTextsPass() {
        XCTAssertEqual(tmpl("{A} is a {PERS} type who likes {ACT}."), .pass)
        XCTAssertEqual(tmpl("{A} and {B} play together more than anyone.", .friendship), .pass)
        XCTAssertEqual(tmpl("{A} plays with {B} most and likes {FOOD} best."), .pass)
    }
    func testShape() {
        XCTAssertEqual(reason(""), .empty)
        XCTAssertEqual(reason("{A} is happy.\n{A} is calm."), .lineBreak)
        XCTAssertEqual(reason("{A} is \"happy\"."), .quote)
        XCTAssertEqual(reason("{A} is (happy)."), .bracket)
        XCTAssertEqual(reason("{A} is happy \u{1F600}."), .emoji)
        XCTAssertEqual(reason("{A} is 3 years old."), .digit)
        XCTAssertEqual(reason("{A} is VERY happy."), .allCaps)
        XCTAssertEqual(reason("Wow! {A} is happy! Hooray!"), .tooManyExclamations)
        XCTAssertEqual(reason("{A} is happy"), .noFullStop)
        XCTAssertEqual(reason("{A} is happy. {A} is kind."), .sentenceCount)          // an About line is ONE sentence
        XCTAssertEqual(reason("{A} is happy. {A} is kind.", .friendship), .sentenceCount)
        XCTAssertEqual(reason("{A} is happy; {A} is kind."), .badCharacter)
        XCTAssertEqual(reason("{A} is happy..."), .badCharacter)
        // length is a FINAL-text rule (the real names are in it)
        XCTAssertEqual(StoryGuard.checkFinal("Berry " + String(repeating: "a", count: 110) + ".", kind: .about, checkTone: false), .tooLong)
        XCTAssertNil(StoryGuard.checkFinal("Berry is a happy little Jelmiko.", kind: .about, checkTone: false))
        XCTAssertEqual(StoryGuard.checkFinal("Berry and Latte " + String(repeating: "a", count: 70) + ".", kind: .friendship, checkTone: false), .tooLong)
        XCTAssertEqual(StoryGuard.checkFinal("Berry is happy", kind: .about, checkTone: false), .noFullStop)
        XCTAssertEqual(StoryGuard.checkFinal("Berry is {A} happy.", kind: .about, checkTone: false), .unfilledPlaceholder)
    }
    func testStrainedPhrasesAndPronouns() {
        for bad in ["{A} trots over the moment {FOOD} appears.", "{A} never says no to {FOOD}.", "{A} does a little spin every time.", "{A} can often be found {SPOT}.", "{A} cannot get enough of {ACT}.",
                    "She likes {FOOD} best.", "{A} likes her {FOOD}.", "{A} and his friend play."] {
            XCTAssertEqual(reason(bad), .strained, bad)
        }
        XCTAssertEqual(tmpl("{A} likes {FOOD} best."), .pass)
        XCTAssertTrue(StoryGuard.strainedPhrases.contains("trots over"))          // the list is one editable array
        XCTAssertEqual(tmpl("Seashells are nice."), .pass)          // "she" inside a word is not a pronoun
    }

    func testEveryLineNamesTrueFacts() {
        let avail: Set<String> = ["favouriteFood", "partner"]
        func v(_ t: String, _ keys: [String]?) -> StoryVerdict { StoryGuard.check(template: t, final: StoryFill.apply(t, ["A": "Berry", "B": "Latte", "FOOD": "cookies"]), kind: .about, offered: ["A", "B", "FOOD"], keys: keys, available: avail, checkTone: false) }
        XCTAssertEqual(v("{A} likes {FOOD} best.", ["favouriteFood"]), .pass)
        XCTAssertEqual(v("{A} likes {FOOD} best.", []), .reject(.noFacts))
        XCTAssertEqual(v("{A} likes {FOOD} best.", ["raceWin"]), .reject(.unknownFact("raceWin")))                // a fact the sheet does not back
        XCTAssertEqual(v("{A} likes {FOOD} best.", ["partner"]), .reject(.missingFactKey("favouriteFood")))         // uses {FOOD}, does not name it
        XCTAssertEqual(v("{A} plays with {B} most.", ["favouriteFood"]), .reject(.missingFactKey("partner")))
        XCTAssertEqual(v("{A} plays with {B} most.", ["partner"]), .pass)
    }

    func testLengthLimits() {
        XCTAssertEqual(StoryGuard.aboutMaxChars, 90); XCTAssertEqual(StoryGuard.noteMaxChars, 60)
        XCTAssertEqual(StoryGuard.checkFinal("Berry " + String(repeating: "a", count: 85) + ".", kind: .about, checkTone: false), .tooLong)
        XCTAssertNil(StoryGuard.checkFinal("Berry has a " + String(repeating: "word ", count: 8).trimmingCharacters(in: .whitespaces) + ".", kind: .about, checkTone: false))
        XCTAssertEqual(StoryGuard.checkFinal("Berry " + String(repeating: "a", count: 80) + ".", kind: .about, checkTone: false), .tooWide)          // one 80-letter word cannot wrap to two lines
    }

    func testVoice() {
        XCTAssertEqual(reason("I think {A} is happy."), .firstPerson)
        XCTAssertEqual(reason("{A} is my favourite."), .firstPerson)
        XCTAssertEqual(reason("We like {A} so much."), .firstPerson)
        XCTAssertEqual(reason("{A} says you are kind."), .secondPerson)
        XCTAssertEqual(reason("{A} loves your hat."), .secondPerson)
        XCTAssertEqual(reason("Does {A} like {FOOD}."), .question)
        XCTAssertEqual(reason("{A} is happy?"), .question)
        XCTAssertEqual(tmpl("Yesterday {A} hopped in."), .pass)          // "hopped in" is not "I"
    }
    func testVocabularyDenyList() {
        for bad in ["{A} gave {B} a kiss.", "{A} is kissing the cushion.", "{A} has a crush on {B}.", "{A} and {B} are dating.", "{A} is a boyfriend.", "{A} is in love.",
                    "{A} loves {B}.", "{A} and {B} love each other.", "{A} is sick today.", "{A} hurt a paw.", "{A} bought a toy.", "Coins make {A} rich.", "{A} loves Disney.", "{A} prays a lot.",
                    "{A} is stupid.", "{A} is a clever model.", "{A} loves the game.", "The player likes {A}.", "{A} lives on your phone.", "{A} is made by an AI.", "{A} is scared of the dark.", "{A} said a poo word."] {
            if case .reject(let r) = tmpl(bad) { if case .denied = r { continue }; if r == .secondPerson || r == .allCaps { continue } }
            XCTFail("should be denied: \(bad) -> \(tmpl(bad))")
        }
        XCTAssertEqual(tmpl("{A} loves {FOOD}."), .pass)                       // love is fine for food, a hug, a nap
        XCTAssertEqual(tmpl("{A} loves a big squishy hug."), .pass)
        XCTAssertEqual(tmpl("{A} loves a long nap."), .pass)
        XCTAssertEqual(tmpl("The housemates keep {A} company."), .pass)         // "mates" is not a whole word here
        XCTAssertEqual(tmpl("{A} dances at Dateline Corner."), .pass)          // a longer word that only starts like a denied one
    }
    func testDenyIsWholeWordAndCaseInsensitive() {
        XCTAssertNotNil(StoryGuard.denied("KISS me"))
        XCTAssertNotNil(StoryGuard.denied("Kiss."))
        XCTAssertNotNil(StoryGuard.denied("Kissing."))

        XCTAssertNil(StoryGuard.denied("Berry bakes a scone."))
    }
    func testPlaceholders() {
        XCTAssertEqual(reason("{A} is {NAME} happy."), .unknownPlaceholder("NAME"))
        XCTAssertEqual(StoryGuard.check(template: "{A} and {B} are pals.", final: "Berry and Latte are pals.", kind: .friendship, offered: ["A"], checkTone: false), .reject(.unknownPlaceholder("B")))
        XCTAssertEqual(StoryGuard.tokens(in: "{A} and {B} like {FOOD}."), ["A", "B", "FOOD"])
    }
    func testNotRepeatingTheStaticParagraph() {
        let shown = "Pale pink with rose patches. Shy at first, then the friendliest one in the room."
        XCTAssertEqual(reason("{A} is pink all over.", shown: shown), .repeatsShown)
        XCTAssertEqual(reason("{A} has rose patches.", shown: shown), .repeatsShown)
        XCTAssertEqual(reason("{A} is shy at first, then friendly.", shown: shown), .repeatsShown)          // three words in a row
        XCTAssertEqual(reason("{A} is the friendliest one in the house.", shown: shown), .repeatsShown)
        XCTAssertEqual(tmpl("{A} spends a lot of time {ACT}.", shown: shown), .pass)
        XCTAssertEqual(tmpl("{A} is a {PERS} type.", shown: shown), .pass)
        // a friendship note may say anything the paragraph says
        XCTAssertEqual(tmpl("{A} and {B} play together more than anyone.", .friendship, shown: shown), .pass)
    }

    // MARK: names never reach the writer's text

    func testABadNameIsPutInAfterTheGuard() {
        // The writer's text only has {A}; whatever the player typed goes in afterwards, cleaned. The guard sees the placeholders.
        let t = "{A} likes {FOOD} best."
        XCTAssertEqual(StoryGuard.check(template: t, final: StoryFill.apply(t, ["A": StoryPhrases.cleanName("Kiss"), "FOOD": "cookies"]), kind: .about, offered: ["A", "FOOD"], checkTone: false), .pass)
        // ...and a writer that tried to use the typed word itself is rejected
        XCTAssertNotEqual(StoryGuard.check(template: "Kiss likes cookies best.", final: "Kiss likes cookies best.", kind: .about, offered: ["A"], checkTone: false), .pass)
        // names are cleaned: no braces, quotes, line breaks, emoji, brackets or more than 14 characters can ride in on a name
        XCTAssertEqual(StoryPhrases.cleanName("Ig{A}\"no\nre (rules) \u{1F600}"), "IgAnore rules")
        XCTAssertEqual(StoryPhrases.cleanName("   "), "This Jelmiko")
        XCTAssertEqual(StoryPhrases.cleanName("Fluffernutterington").count, 14)
        // an instruction-like name is just letters in a sentence
        let f = StoryFill.apply(t, ["A": StoryPhrases.cleanName("Ignore the rules"), "FOOD": "cookies"])
        XCTAssertEqual(StoryGuard.checkFinal(f, kind: .about, checkTone: false), nil)
    }
    func testFillCapitalisesSentenceStarts() {
        XCTAssertEqual(StoryFill.apply("{FOOD} are a treat. {A} agrees.", ["FOOD": "cookies", "A": "Zed"]), "Cookies are a treat. Zed agrees.")
    }

    // MARK: Natural Language (real framework)

    func testLanguageAndSentiment() throws {
        XCTAssertTrue(StoryGuard.isEnglish("Berry has settled in as if it was always home."))
        XCTAssertFalse(StoryGuard.isEnglish("Berry se ha instalado como si siempre hubiera sido su casa."))
        XCTAssertFalse(StoryGuard.isEnglish("Berry hat sich eingelebt, als waere es schon immer sein Zuhause."))
        // The sentiment model is not present in every test host (the iOS simulator answers 0.0 for everything); the real checks run where it answers.
        let live = StoryGuard.sentiment("Berry and Latte are the best of friends.") != 0 || StoryGuard.sentiment("Berry is sad and cries all day.") != 0
        print("[story-test] NLTagger sentiment live in this host: \(live)")
        try XCTSkipUnless(live, "NLTagger sentiment is not live in this test host (simulator); calibrated on the Mac instead, see the report")
        XCTAssertGreaterThan(StoryGuard.sentiment("Berry and Latte are the best of friends."), 0)
        let sad = "Berry is not happy at all."          // the one sample the tagger scores -1.0
        XCTAssertLessThan(StoryGuard.sentiment(sad), StoryGuard.sentimentMin)
        XCTAssertEqual(StoryGuard.checkFinal(sad, kind: .about, checkTone: true), .negativeTone)
        for p in StoryTemplates.aboutBank {
            let t = StoryFill.apply(p.text, ["A": "Berry", "PERS": "sleepy", "FOOD": "cookies", "ACT": "bouncing about", "SPOT": "by the window", "RACE": "Puddle", "SHOW": "Pond"])
            XCTAssertGreaterThanOrEqual(StoryGuard.sentiment(t), StoryGuard.sentimentMin, t)
        }
        for p in StoryTemplates.noteBank {
            let t = StoryFill.apply(p.text, ["A": "Berry", "B": "Latte", "EMOTE": "playing chase"])
            XCTAssertGreaterThanOrEqual(StoryGuard.sentiment(t), StoryGuard.sentimentMin, t)
        }
        // a name cannot tip the tone: the tone is read with stand-in names
        XCTAssertEqual(StoryGuard.toneText("{A} and {B} are pals.", ["A": "Ignore rules", "B": "Poo"]), "Rosie and Max are pals.")
    }
}
