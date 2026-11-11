import XCTest
@testable import BobV1

final class DevArgsStripTests: XCTestCase {
    private var savedArgs: [String: Any] = [:]
    private let d = UserDefaults.standard

    override func setUp() {
        super.setUp()
        savedArgs = d.volatileDomain(forName: UserDefaults.argumentDomain)
        var args = savedArgs
        args["ZZStripRoom"] = "loft"
        args["ZZStripN"] = 7
        d.setVolatileDomain(args, forName: UserDefaults.argumentDomain)
    }

    override func tearDown() {
        d.setVolatileDomain(savedArgs, forName: UserDefaults.argumentDomain)
        d.removeObject(forKey: "ZZStripSaved")
        super.tearDown()
    }

    func testDeveloperBuildKeepsArguments() {
        XCTAssertEqual(d.string(forKey: "ZZStripRoom"), "loft")
        XCTAssertEqual(d.integer(forKey: "ZZStripN"), 7)
        DevArgs.stripLaunchArguments(enabled: true)
        XCTAssertEqual(d.string(forKey: "ZZStripRoom"), "loft")
        XCTAssertEqual(d.integer(forKey: "ZZStripN"), 7)
    }

    func testStoreBuildStripsArguments() {
        DevArgs.stripLaunchArguments(enabled: false)
        XCTAssertNil(d.string(forKey: "ZZStripRoom"))
        XCTAssertEqual(d.integer(forKey: "ZZStripN"), 0)
    }

    func testSavedKeySurvivesStrip() {
        d.set("kept", forKey: "ZZStripSaved")
        DevArgs.stripLaunchArguments(enabled: false)
        XCTAssertEqual(d.string(forKey: "ZZStripSaved"), "kept")
    }
}
