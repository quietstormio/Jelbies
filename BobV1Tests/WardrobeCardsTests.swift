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
        for w in [CGFloat(103), 125] {
            let hs = Set(looks.map { l in (size(face(l, w), width: w).height * 2).rounded() })
            XCTAssertEqual(hs.count, 1, "card heights at width \(w): \(hs)")
            // and the worn card is the same height as the others
            XCTAssertEqual(size(face(looks[0], w, worn: true), width: w).height, size(face(looks[1], w), width: w).height, accuracy: 0.5)
        }
    }

    func testNoNameIsCutOff() {
        for w in [CGFloat(103), 125] {
            let textW = (w - 2 * WardrobeCardFace.pad) / WardrobeCardFace.nameScale          // the name may shrink to nameScale to keep two lines
            let line = size(Text("Ag").font(SK.font(12, .black)).fixedSize()).height
            for l in looks {
                let h = size(Text(l.title).font(SK.font(12, .black)).multilineTextAlignment(.center).frame(width: textW).fixedSize(horizontal: false, vertical: true)).height
                XCTAssertLessThanOrEqual(h, line * 2 + 1, "\(l.title) needs more than two lines at card width \(w)")
                for word in l.title.split(separator: " ") {
                    let ww = size(Text(String(word)).font(SK.font(12, .black)).fixedSize()).width
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

    /// Writes every wearable's card picture on one sheet (6 per row) when the capture folder exists, for a look at the framing. Not an assertion beyond "every picture drew".
    func testContactSheetOfEveryCardPicture() throws {
        let dir = "/private/tmp/claude-501/-Users-dmarshall94-Desktop-BobV1/e0755ccf-aeea-4c40-b871-1f1d2b621362/scratchpad/dressup"
        guard FileManager.default.fileExists(atPath: dir) else { throw XCTSkip("no capture folder") }
        let items = StoreCatalog.items.filter { $0.isWearable && $0.wear != nil }
        let cell: CGFloat = 330, label: CGFloat = 46, cols = 6, rows = (items.count + cols - 1) / cols
        let fmt = UIGraphicsImageRendererFormat(); fmt.scale = 1
        let r = UIGraphicsImageRenderer(size: CGSize(width: cell * CGFloat(cols), height: (cell + label) * CGFloat(rows)), format: fmt)
        let sheet = r.image { ctx in
            UIColor(white: 0.93, alpha: 1).setFill(); ctx.fill(CGRect(origin: .zero, size: r.format.bounds.size))
            for (i, item) in items.enumerated() {
                let x = CGFloat(i % cols) * cell, y = CGFloat(i / cols) * (cell + label)
                UIColor(red: 0.98, green: 0.88, blue: 0.9, alpha: 1).setFill()
                UIBezierPath(roundedRect: CGRect(x: x + 8, y: y + 8, width: cell - 16, height: cell - 16), cornerRadius: 36).fill()
                if let img = StoreThumb.wardrobeImage(item) { img.draw(in: CGRect(x: x + 8, y: y + 8, width: cell - 16, height: cell - 16)) }
                else { XCTFail("no picture for \(item.id)") }
                (item.wear?.title ?? item.id as NSString as String).draw(at: CGPoint(x: x + 12, y: y + cell - 4), withAttributes: [.font: UIFont.boldSystemFont(ofSize: 26), .foregroundColor: UIColor.black])
            }
        }
        try sheet.jpegData(compressionQuality: 0.9)?.write(to: URL(fileURLWithPath: dir + "/all_items.jpg"))
    }
}
