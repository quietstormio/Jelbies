import XCTest
import simd
@testable import BobV1

/// Pip's spikes: classic Pip (and every colour but the Amber rare) keeps the baked spike mesh and cache key; Amber's spines carry the russet tint.
final class AmberSpikeTintTests: XCTestCase {
    func testOnlyAmberHasASpikeTint() {
        XCTAssertNil(JellyVariantBook.spikeTint(for: nil))
        for v in JellyVariantBook.exclusives where v.title != "Amber" { XCTAssertNil(JellyVariantBook.spikeTint(for: v), v.title) }
        for t in JellyVariantBook.legacyExclusiveTitles { XCTAssertNil(JellyVariantBook.spikeTint(for: JellyVariant(title: t, flesh: [1, 1, 1], deep: [1, 1, 1], rare: true))) }
        XCTAssertEqual(JellyVariantBook.spikeTint(for: JellyVariantBook.exclusives[1]), JellyVariantBook.amberSpikeTint)
        for c in ParkColour.allCases { XCTAssertNotEqual(c.rawValue, "amber") }
    }

    func testClassicSpinesUnchangedAndAmberSpinesTinted() throws {
        let body = WearBody.shared
        let classic = try XCTUnwrap(FeatureMeshes.prepare(.spines, body: body))
        let classic2 = try XCTUnwrap(FeatureMeshes.prepare(.spines, body: body, spikeTint: nil))
        XCTAssertEqual(classic.col, classic2.col, "no tint = the same cached mesh")
        let amber = try XCTUnwrap(FeatureMeshes.prepare(.spines, body: body, spikeTint: JellyVariantBook.amberSpikeTint))
        XCTAssertEqual(amber.rest, classic.rest, "geometry is untouched")
        XCTAssertEqual(amber.col.count, classic.col.count)
        func mean(_ c: [SIMD3<Float>]) -> SIMD3<Float> { c.reduce(.zero, +) / Float(max(c.count, 1)) }
        let m = mean(amber.col), k = mean(classic.col)
        XCTAssertGreaterThan(k.x, 0.8); XCTAssertEqual(m.x, JellyVariantBook.amberSpikeTint.x, accuracy: 0.08)
        XCTAssertLessThan(m.y, k.y * 0.65, "clearly darker and warmer than the classic orange")
        XCTAssertNotEqual(amber.col, classic.col)
        // the classic mesh is still the classic one after an Amber was built (separate cache keys)
        XCTAssertEqual(try XCTUnwrap(FeatureMeshes.prepare(.spines, body: body)).col, classic.col)
    }
}
