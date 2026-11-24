//
//  ProfileStableTests.swift
//  The Profile has a FIXED SKELETON: every text slot reserves its worst-case height, so no card moves between Jelmiko or states (the owner's rule).
//  Each slot view is the production one (ProfileScreen.swift); each is rendered at the narrowest (iPhone SE class, 375 pt) and the widest (Pro Max, 440 pt)
//  iPhone content width with every text it can hold, and every height must be the same.
//

import XCTest
import SwiftUI
@testable import BobV1

@MainActor
final class ProfileStableTests: XCTestCase {
    /// Card inner width for a phone of `w` points: the screen minus the page margins (16 x 2) minus the card padding (14 x 2).
    private func inner(_ w: CGFloat) -> CGFloat { w - 32 - 28 }
    private let phones: [CGFloat] = [375, 440]

    private func height<V: View>(_ v: V, width: CGFloat) -> CGFloat {
        let h = UIHostingController(rootView: v.frame(width: width, alignment: .topLeading))
        h.view.frame = CGRect(x: 0, y: 0, width: width, height: 2000)
        return h.sizeThatFits(in: CGSize(width: width, height: CGFloat.infinity)).height
    }

    private func assertSame(_ label: String, _ heights: [String: CGFloat], file: StaticString = #filePath, line: UInt = #line) {
        let vals = Array(heights.values)
        guard let lo = vals.min(), let hi = vals.max() else { return XCTFail("\(label): nothing measured", file: file, line: line) }
        XCTAssertLessThan(hi - lo, 0.5, "\(label): heights differ \(heights.filter { abs($0.value - lo) > 0.5 })", file: file, line: line)
        print("PROFILE-STABLE \(label): \(lo) pt over \(heights.count) variants")
    }

    func testEverySkinParagraphTakesTheSameHeight() {
        XCTAssertGreaterThan(ProfileRuler.paragraphs.count, 20)
        for w in phones {
            var h: [String: CGFloat] = [:]
            for t in ProfileRuler.paragraphs { h[t] = height(ProfileParagraph(text: t), width: inner(w)) }
            assertSame("paragraph @\(w)", h)
        }
    }

    func testEveryStatusTakesTwoLinesOfSpace() {
        let texts = ["Berry is happy.", "Berry is doing fine.", "Berry is happy and sparkling.", "Berry is asleep.", "Berry is napping.",
                     "Berry is grumpy: famished.", "Berry is a bit dirty.", "Berry needs you: hungry and thirsty.",
                     "Marshmallow needs you: thirsty and lonely."]
        for w in phones {
            let col = inner(w) - 128 - 14          // the column beside the picture
            var h: [String: CGFloat] = [:]
            for t in texts { h[t] = height(ProfileStatus(text: t), width: col) }
            assertSame("status @\(w)", h)
        }
    }

    func testEveryChipValueTakesTheSameHeight() {
        var chips: [ProfileWords.Chip] = []
        for hour in stride(from: 0.0, to: 24.0, by: 0.5) { chips.append(ProfileWords.sleep(asleep: true, hour: hour)); chips.append(ProfileWords.sleep(asleep: false, hour: hour)) }
        for (t, v) in [("Food", "Full"), ("Food", "Not hungry"), ("Food", "Peckish"), ("Food", "Very hungry"), ("Water", "Quenched"), ("Water", "A little thirsty"),
                       ("Water", "Very thirsty"), ("Clean", "Sparkling clean"), ("Clean", "A bit grubby"), ("Clean", "Needs a bath")] {
            chips.append(.init(title: t, value: v, icon: "drop.fill", tone: .good))
        }
        for w in phones {
            let chipW = (inner(w) - 8) / 2
            var h: [String: CGFloat] = [:]
            for c in chips { h["\(c.title)|\(c.value)"] = height(ProfileChipView(chip: c), width: chipW) }
            assertSame("chip @\(w)", h)
        }
    }

    func testEveryFavouriteRowTakesTheSameHeight() {
        for w in phones {
            var food: [String: CGFloat] = [:], friend: [String: CGFloat] = [:], perks: [String: CGFloat] = [:]
            for v in ["Ice pop", "Still finding out", "Cheeseburger"] { food[v] = height(ProfileFavRow(title: "Favourite food", value: { ProfileFavText(text: v) }) { Color.clear }, width: inner(w)) }
            for v in ["Still finding out", "Moomoo \u{00B7} Best friend", "A very long visitor name \u{00B7} Good friends"] { friend[v] = height(ProfileFavRow(title: "Best friend at the Park", value: { ProfileFavText(text: v, lines: 2) }) { Color.clear }, width: inner(w)) }
            let sets: [[String]] = [[], ["Full belly"], ["Full belly", "Tidy"], ["Full belly", "Tidy", "Cozy", "Shiny"], ["Full belly", "Tidy", "Cozy", "Shiny", "Zoomy", "Lucky"]]
            for n in sets { perks[n.joined(separator: ",")] = height(ProfileFavRow(title: "Power-ups", value: { ProfilePerkNames(names: n) }) { Color.clear }, width: inner(w)) }
            assertSame("favourite food row @\(w)", food); assertSame("friend row @\(w)", friend); assertSame("power-ups row @\(w)", perks)
        }
    }

    /// Every kind name x every type name: ONE row, and the same height whichever pair (the narrowest column beside the picture is 375 - 32 - 28 - 128 - 14 = 173 pt).
    func testEveryKindAndTypeSitsInOneRowOfTheSameHeight() {
        XCTAssertGreaterThan(ProfileTagRow.kinds.count, 15)
        XCTAssertGreaterThanOrEqual(ProfileTagRow.types.count, 8)
        for w in phones {
            let col = inner(w) - 128 - 14
            var h: [String: CGFloat] = [:]
            for k in ProfileTagRow.kinds { for t in ProfileTagRow.types { h["\(k)|\(t)"] = height(ProfileTagRow(kind: k, type: t, typeIcon: "moon.fill"), width: col) } }
            assertSame("tag row @\(w)", h)
            XCTAssertLessThan(h.values.max() ?? 99, 40, "the tags are one row (a chip is about 30 pt high)")
        }
    }

    /// Every skin's paragraph is exactly two lines at the default size on the narrowest and the widest iPhone (not three, not one).
    func testEverySkinParagraphIsExactlyTwoLines() {
        for w in phones {
            let f = SK.font(15, .bold)
            let one = height(Text("A").font(f).lineSpacing(3), width: inner(w)), two = height(Text("A\nB").font(f).lineSpacing(3), width: inner(w))
            XCTAssertGreaterThan(two, one + 5)
            for t in ProfileRuler.paragraphs {
                let h = height(Text(t).font(f).lineSpacing(3).fixedSize(horizontal: false, vertical: true), width: inner(w))
                XCTAssertEqual(h, two, accuracy: 0.5, "\(t) @\(w): exactly two lines")
            }
        }
    }

    func testEveryStageNameTakesTheSameRelationshipLine() {
        for w in phones {
            var h: [String: CGFloat] = [:]
            for p in [0] + BondTuning.heartFull.flatMap({ [$0 - 1, $0] }) { let l = BondLevel(points: p); h["\(l.name)#\(p)"] = height(BondHeartsRow(level: l), width: inner(w)) }
            assertSame("relationship @\(w)", h)
        }
    }

    // MARK: the story slots (Story/): the friend rows

    /// Every line the pre-written bank can say with the longest names, plus the longest text the guard allows (90 characters that still fit two lines at 375 pt) and "no line".
    private func livingLines() -> [String] {
        var out: [String] = [""]
        let v = ["A": "Marshmallow", "B": "Fluffernutter", "PERS": "cheeky", "FOOD": "cheeseburgers", "ACT": "flapping and hopping", "SPOT": "at the front of the room", "RACE": "Tsunami", "SHOW": "Lagoon", "EMOTE": "bouncing up and down together",
                 "LEFT": "three more race wins", "WHEN": "yesterday", "TIER": "Sandcastle", "PLACE": "second", "LEVEL": "Close friends"]
        for p in StoryTemplates.aboutBank + StoryTemplates.newsBank { out.append(StoryFill.apply(p.text, v)) }
        let longest = out.filter { StoryGuard.checkFinal($0, kind: .about, checkTone: false) == nil }.max { $0.count < $1.count } ?? ""
        out.append(longest)
        return out
    }

    func testEveryLineThatPassesTheGuardFitsTwoLinesAt375() {
        for t in livingLines() where !t.isEmpty && StoryGuard.checkFinal(t, kind: .about, checkTone: false) == nil {
            XCTAssertTrue(StoryGuard.fitsLines(t, width: StoryLayout.lineWidth, size: StoryLayout.lineSize, lines: 2), t)
            let one = height(Text(t).font(SK.font(StoryLayout.lineSize, .semibold)).frame(width: StoryLayout.lineWidth, alignment: .leading), width: StoryLayout.lineWidth)
            let two = height(Text("Aa\nBb").font(SK.font(StoryLayout.lineSize, .semibold)).frame(width: StoryLayout.lineWidth, alignment: .leading), width: StoryLayout.lineWidth)
            XCTAssertLessThanOrEqual(one, two + 0.5, "needs a third line in the real font: \(t)")
        }
        // and a text the guard refuses for width is refused
        XCTAssertEqual(StoryGuard.checkFinal(String(repeating: "Wide wide words ", count: 5).trimmingCharacters(in: .whitespaces) + ".", kind: .about, checkTone: false), .tooWide)
    }

    func testEveryFriendRowTakesTheSameHeight() {
        let notes = [""] + StoryTemplates.noteBank.map { StoryFill.apply($0.text, ["A": "Marshmallow", "B": "Fluffernutter", "EMOTE": "bouncing up and down together"]) }
        for w in phones {
            var h: [String: CGFloat] = [:]
            for n in notes { h[n] = height(StoryFriendRow(names: "Marshmallow and Fluffernutter", note: n, byModel: n.count % 2 == 0) { Circle().frame(width: 40, height: 40) }, width: inner(w)) }
            h["placeholder"] = height(StoryFriendPlaceholder(), width: inner(w))
            assertSame("friend row @\(w)", h)
        }
    }
}
