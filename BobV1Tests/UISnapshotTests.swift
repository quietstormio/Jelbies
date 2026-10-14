import XCTest
import SwiftUI
import UIKit
@testable import BobV1

@MainActor
final class UISnapshotTests: XCTestCase {
    static let dir = "/private/tmp/claude-501/-Users-dmarshall94-Desktop-BobV1/6a40096b-092a-48d0-8cbe-4e00ccea7702/scratchpad"

    private func render<V: View>(_ v: V, _ name: String) throws {
        let r = ImageRenderer(content: v.frame(width: 393, height: 852).environment(\.colorScheme, .light))
        r.scale = 2
        let img = try XCTUnwrap(r.uiImage, name)
        try XCTUnwrap(img.pngData()).write(to: URL(fileURLWithPath: "\(Self.dir)/ui_\(name).png"))
    }

    func testRenderAll() throws {
        let empty = PreviewSupport.store(blobs: 0)
        try render(KennelView(store: empty, flat: true), "kennel")
        let s = PreviewSupport.store(blobs: 3)
        try render(HomeView(store: s, events: CareEvents(), persist: {}) { HUDPlaceholderStage(store: s) }, "home")
        let ev = CareEvents(); ev.showStatus(s.blobs[1].id)
        try render(HomeView(store: s, events: ev, persist: {}) { HUDPlaceholderStage(store: s) }, "status")
    }
}
