//
//  WardrobeCardsTests.swift
//  dressup-cards-r1: the Dress up sheet's cards. Every item's card is the same height at a given width (two name lines reserved), no name is cut off
//  (at most two lines, no word broken), the grid keeps at least 3 columns and the cards about one size, and the card picture is a big square.
//

import XCTest
import SwiftUI
@testable import BobV1

@MainActor
final class WardrobeCardsTests: XCTestCase {
    private var looks: [WearLook] { StoreCatalog.items.filter(\.isWearable).compactMap(\.wear) }
    private func size<V: View>(_ v: V, width: CGFloat? = nil, fixed: Bool = false) -> CGSize {
        let c = UIHostingController(rootView: v)
        return c.sizeThatFits(in: CGSize(width: width ?? 1000, height: 5000))
    }
    private func face(_ look: WearLook, _ w: CGFloat, worn: Bool = false) -> WardrobeCardFace {
        WardrobeCardFace(look: look, tag: look.tags.first, match: 1, worn: worn, otherName: nil, width: w)
    }

    func testEveryCardHasTheSameHeightAtTwoWidths() {
        XCTAssertGreaterThan(looks.count, 10)
        for w in [CGFloat(105), 130] {
            let hs = Set(looks.map { l in (size(face(l, w), width: w).height * 2).rounded() })
            XCTAssertEqual(hs.count, 1, "card heights at width \(w): \(hs)")
            // and the worn card is the same height as the others
            XCTAssertEqual(size(face(looks[0], w, worn: true), width: w).height, size(face(looks[1], w), width: w).height, accuracy: 0.5)
        }
    }

    func testNoNameIsCutOff() {
        for w in [CGFloat(105), 130] {
            let textW = w - 2 * WardrobeCardFace.pad
            let line = size(Text("Ag").font(SK.font(13, .black)).fixedSize()).height
            for l in looks {
                let h = size(Text(l.title).font(SK.font(13, .black)).multilineTextAlignment(.center).frame(width: textW).fixedSize(horizontal: false, vertical: true)).height
                XCTAssertLessThanOrEqual(h, line * 2 + 1, "\(l.title) needs more than two lines at card width \(w)")
                for word in l.title.split(separator: " ") {
                    let ww = size(Text(String(word)).font(SK.font(13, .black)).fixedSize()).width
                    XCTAssertLessThanOrEqual(ww, textW, "the word \(word) of \(l.title) does not fit one line at card width \(w)")
                }
            }
        }
    }

    func testGridColumnsAndPictureSize() {
        for (avail, cols) in [(CGFloat(396), 3), (331, 3), (380, 3), (600, 5), (900, 8)] {
            let c = WardrobeStrip.columns(for: avail)
            XCTAssertEqual(c.count, cols, "columns for \(avail)")
            XCTAssertGreaterThanOrEqual(c.card, 100); XCTAssertLessThanOrEqual(c.card, 165)
        }
        let promax = WardrobeStrip.columns(for: 440 - 32 - 12)
        XCTAssertGreaterThanOrEqual(promax.card - 2 * WardrobeCardFace.pad, 96)
        XCTAssertEqual(WardrobeStrip.columns(for: 300, accessibility: true).count, 2)
    }

    func testEveryWearableHasACardPicture() {
        for item in StoreCatalog.items where item.isWearable && item.wear != nil {
            let a = StoreThumb.wardrobeImage(item), b = StoreThumb.wardrobeImage(item)
            XCTAssertNotNil(a, item.id)
            if let a, let b { XCTAssertTrue(a === b, "\(item.id) is rendered once and cached") }
        }
    }
}
