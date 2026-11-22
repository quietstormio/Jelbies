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
    /// The card at its own natural height (the card asks for all the height it is offered, so a row can stretch it: pin it to what it needs for the measurement).
    private func face(_ look: WearLook, _ w: CGFloat, worn: Bool = false) -> some View {
        WardrobeCardFace(look: look, tag: look.tags.first, match: 1, worn: worn, otherName: nil, width: w).fixedSize(horizontal: false, vertical: true)
    }

    func testEveryCardHasTheSameHeightAtTwoWidths() {
        XCTAssertGreaterThan(looks.count, 10)
        for w in [CGFloat(100), 125] {
            let hs = Set(looks.map { l in (size(face(l, w), width: w).height * 2).rounded() })
            XCTAssertEqual(hs.count, 1, "card heights at width \(w): \(hs)")
            // and the worn card is the same height as the others
            XCTAssertEqual(size(face(looks[0], w, worn: true), width: w).height, size(face(looks[1], w), width: w).height, accuracy: 0.5)
        }
    }

    func testNoNameIsCutOff() {
        for w in [CGFloat(100), 125] {
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

    // MARK: the sideways row at the low height

    private func stocked() -> GameCare {
        let room = RaceThreeTests.Room(count: 1)
        RaceThreeTests.keep.append(room)
        for item in StoreCatalog.items where item.isWearable { room.care.store.grant(item.id) }
        return room.care
    }

    /// The low height is exactly what the content needs, whatever the room offered, at the narrowest and the widest phone width, and it holds a whole card row.
    func testLowHeightIsContentSizedAndHoldsAWholeCardRow() {
        let care = stocked()
        let theme = ShowSchedule.theme(dayKey: GameCare.showDay)
        for w in [CGFloat(375), 440] {
            let card = WardrobeStrip.rowCard(sheetWidth: w)
            let gap = WardrobeCardFace.gap
            XCTAssertLessThan(16 + 3 * card + 3 * gap, w, "part of the fourth card shows at \(w)")
            XCTAssertGreaterThan(16 + 3 * card + 3 * gap + card, w, "the fourth card runs off the edge at \(w)")
            XCTAssertGreaterThanOrEqual(card, 100, "cards keep their size at \(w)")
            let sheet = WardrobeSheet(care: care, who: 0, theme: theme, rank: care.show.progress.chosen, low: true) {}
            let tall = size(sheet, width: w).height
            let c = UIHostingController(rootView: sheet)
            let short = c.sizeThatFits(in: CGSize(width: w, height: 400)).height
            XCTAssertEqual(tall, short, accuracy: 0.5, "the low sheet is as tall as its content, not as the room, at \(w)")
            XCTAssertGreaterThanOrEqual(tall, size(face(looks[0], card), width: card).height, "a whole card fits at \(w)")
        }
    }

    /// The row and the grid are the same cards in the same order, and filtering keeps that order.
    func testRowAndGridShowTheSameItemsInTheSameOrder() {
        let care = stocked()
        let theme = ShowSchedule.theme(dayKey: GameCare.showDay)
        let all = WardrobeStrip.ordered(care: care, theme: theme, slots: nil)
        XCTAssertGreaterThan(all.count, 10)
        for n in [3, 4, 6] { XCTAssertEqual(WardrobeStrip.rows(all, columns: n).flatMap { $0 }, all, "\(n) columns") }
        for slot in WearSlot.allCases {
            let some = WardrobeStrip.ordered(care: care, theme: theme, slots: [slot])
            XCTAssertEqual(some, all.filter { $0.slot == slot }, "the \(slot.title) filter keeps the order")
        }
        XCTAssertEqual(all.map { theme.match($0.tags) }, all.map { theme.match($0.tags) }.sorted(by: >), "best theme match first")
    }

    // MARK: every picture shows its item

    private func pixels(_ img: UIImage) -> [UInt8]? {
        guard let cg = img.cgImage else { return nil }
        let w = cg.width, h = cg.height
        var data = [UInt8](repeating: 0, count: w * h * 4)
        guard let ctx = CGContext(data: &data, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4, space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
        return data
    }

    /// A piece that renders nothing (inside the arm, at the origin, culled) would leave its card the bare Jelmiko: every catalogue item's card picture must differ from the
    /// bare catalogue Jelmiko's, framed the same way, by a minimum number of pixels (shoes, which draw on their own foot stubs, must at least fill a fair part of the picture).
    func testEveryItemsCardPictureDiffersFromTheBareJelmiko() throws {
        var slots = Set<WearSlot>()
        for item in StoreCatalog.items where item.isWearable {
            guard let w = item.wear, let img = StoreThumb.wardrobeImage(item), let px = pixels(img) else { XCTFail("no picture for \(item.id)"); continue }
            slots.insert(w.slot)
            if w.isShoe {
                let opaque = stride(from: 3, to: px.count, by: 4).filter { px[$0] > 40 }.count
                XCTAssertGreaterThan(opaque, px.count / 4 / 20, "\(item.id): the shoes fill the picture")
                continue
            }
            guard let bare = StoreThumb.wardrobeBareImage(item), let bpx = pixels(bare), bpx.count == px.count else { XCTFail("no bare picture for \(item.id)"); continue }
            var diff = 0
            for i in stride(from: 0, to: px.count, by: 4) {
                let d = max(abs(Int(px[i]) - Int(bpx[i])), abs(Int(px[i + 1]) - Int(bpx[i + 1])), abs(Int(px[i + 2]) - Int(bpx[i + 2])), abs(Int(px[i + 3]) - Int(bpx[i + 3])))
                if d > 24 { diff += 1 }
            }
            XCTAssertGreaterThan(diff, 700, "\(item.id) (\(w.slot.title)) shows its piece: \(diff) pixels differ from the bare Jelmiko")
        }
        XCTAssertTrue(slots.contains(.hands) && slots.contains(.head) && slots.contains(.feet) && slots.contains(.neck), "the check covers every slot the catalogue uses")
    }

    /// Writes the hand items' card picture and the Shop's own thumbnail to the capture folder (a look at the fit; skipped when the folder is not there).
    func testWriteHandPictures() throws {
        let dir = "/private/tmp/claude-501/-Users-dmarshall94-Desktop-BobV1/e0755ccf-aeea-4c40-b871-1f1d2b621362/scratchpad/dressup"
        guard FileManager.default.fileExists(atPath: dir) else { throw XCTSkip("no capture folder") }
        for item in StoreCatalog.items where item.wear?.slot == .hands {
            if let c = StoreThumb.wardrobeImage(item)?.pngData() { try c.write(to: URL(fileURLWithPath: "\(dir)/hands_card_\(item.id).png")) }
            if let s = StoreThumb.image(for: item)?.pngData() { try s.write(to: URL(fileURLWithPath: "\(dir)/hands_shop_\(item.id).png")) }
        }
    }
}
