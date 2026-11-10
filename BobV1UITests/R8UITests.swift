import XCTest

final class R8UITests: XCTestCase {
    static let out = "/private/tmp/claude-501/-Users-dmarshall94-Desktop-BobV1/49d32754-b08a-4bfd-999b-3f9f0cada45f/scratchpad/ipad/r8"
    let base = ["-Mute", "1", "-MainMenu", "0", "-Intro", "0", "-SkipIntro", "1", "-Jelbies.started.v1", "YES", "-BlobDrops.v1", "1024", "-BlobNoWander", "1", "-ClockHour", "12"]
    var app = XCUIApplication()

    override func setUp() { continueAfterFailure = true; XCUIDevice.shared.orientation = .portrait }
    override func tearDown() { app.terminate(); XCUIDevice.shared.orientation = .portrait }

    func launch(_ extra: [String], roster: String? = "bob,pearl,teddy", withBase: Bool = true, settle: UInt32 = 12) {
        app = XCUIApplication()
        XCUIDevice.shared.orientation = .portrait
        if withBase { app.launchArguments += base }
        if let r = roster { app.launchArguments += ["-SetRoster", r] }
        app.launchArguments += extra
        app.launch()
        sleep(settle)
    }
    func el(_ id: String) -> XCUIElement { app.descendants(matching: .any)[id].firstMatch }
    @discardableResult func tap(_ id: String, _ t: Double = 15) -> Bool {
        let e = el(id)
        if e.waitForExistence(timeout: t) { e.tap(); sleep(2); return true }
        print("TOUR-MISS \(id)"); return false
    }
    func tapFrac(_ x: Double, _ y: Double) { app.coordinate(withNormalizedOffset: CGVector(dx: x, dy: y)).tap(); sleep(3) }
    func raw(_ name: String) {
        try? FileManager.default.createDirectory(atPath: Self.out, withIntermediateDirectories: true)
        try? XCUIScreen.main.screenshot().image.pngData()?.write(to: URL(fileURLWithPath: "\(Self.out)/\(name).png"))
    }
    /// portrait then landscape of the current screen (rotates back to portrait after)
    func both(_ name: String) {
        XCUIDevice.shared.orientation = .portrait; sleep(3)
        raw("\(name)_portrait")
        XCUIDevice.shared.orientation = .landscapeLeft; sleep(4)
        raw("\(name)_landscape")
        XCUIDevice.shared.orientation = .portrait; sleep(3)
    }

    func btn(_ label: String) -> XCUIElement { app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", label)).firstMatch }
    func tapLabel(_ label: String, _ t: Double = 10) -> Bool { let b = btn(label); if b.waitForExistence(timeout: t) { b.tap(); sleep(3); return true }; print("TOUR-MISS label \(label)"); return false }

    func launchO(_ extra: [String], landscape: Bool, roster: String? = "bob,pearl,teddy", settle: UInt32 = 6, noBase: Bool = false) {
        app = XCUIApplication()
        XCUIDevice.shared.orientation = landscape ? .landscapeLeft : .portrait
        if !noBase { app.launchArguments += base }
        if let r = roster { app.launchArguments += ["-SetRoster", r] }
        app.launchArguments += extra
        app.launch()
        sleep(settle)
    }
    func seq(_ name: String, _ n: Int, _ gap: UInt32, landscape: Bool) {
        for i in 0..<n { raw("\(name)\(i)_\(landscape ? "landscape" : "portrait")"); sleep(gap) }
    }

    func each(_ body: (Bool) -> Void) { for l in [false, true] { body(l); app.terminate() } }
    func tag(_ l: Bool) -> String { l ? "landscape" : "portrait" }
    func test1_TownDirectLandscape() {
        launchO(["-StoreSeed", "1", "-OpenTown", "town"], landscape: true, settle: 15); raw("town_direct_landscape")
    }
    func test2_TownPortraitThenRotate() {
        launch(["-StoreSeed", "1", "-OpenTown", "town"], settle: 15); both("town_rot")
    }
    func test3_Spa() {
        each { l in launchO(["-GroomAuto", "picker"], landscape: l, settle: 12); raw("spa_picker_\(tag(l))") }
    }
}
