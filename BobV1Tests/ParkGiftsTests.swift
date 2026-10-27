import Testing
@testable import BobV1

@MainActor
struct ParkGiftsTests {
    @Test func visitorCountVariesAndRespectsRoom() {
        var rng = SystemRandomNumberGenerator()
        var seen = Set<Int>()
        for _ in 0..<400 { let n = ParkVisit.visitorCount(playerCount: 1, using: &rng); #expect((1...4).contains(n)); seen.insert(n) }
        #expect(seen == [1, 2, 3, 4])
        for _ in 0..<200 { #expect(ParkVisit.visitorCount(playerCount: 3, using: &rng) <= 2) }
        for _ in 0..<200 { #expect(ParkVisit.visitorCount(playerCount: 5, using: &rng) == 1) }
    }
    @Test func giftNeverTwiceRunningAndSkipsOwnedUniques() {
        var rng = SystemRandomNumberGenerator()
        for _ in 0..<50 { #expect(!ParkGifts.isDue(lastVisitGifted: true, using: &rng)) }
        for nicer in [false, true] {
            for _ in 0..<300 {
                guard let i = ParkGifts.pick(owns: { $0.isWearable ? $0.price <= 40 : false }, count: { _ in 0 }, nicer: nicer, using: &rng) else { Issue.record("none"); continue }
                #expect(i.price > 0 && !i.awarded && i.kind != .room && i.kind != .trickPage)
                if i.kind == .decor { #expect(i.roomUnits == 1 && i.decor?.category == .toys) }
                if !nicer { #expect(!(i.isWearable && i.price <= 40)) }
            }
        }
    }
}
