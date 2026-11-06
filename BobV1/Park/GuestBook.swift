//
//  GuestBook.swift
//  A friend over (2026-10-25): from a visitor's card at the Park, or the Town's Friends page, the player invites ONE friend (Friend level or better).
//  Since 2026-11-05 every visit is the same: the friend comes in the EVENING (17:00 on) and goes home the next morning (7:30). `GuestVisit.Kind` keeps
//  both old cases so an old save decodes; nothing reads the kind any more. While he is coming or here the Jelly Wash is closed. This file is the data and the rules; the
//  body, the walk-in, the sleep and the goodbye are GameCare+Guest.swift. Everything is saved on the device (UserDefaults) so a visit survives closing the
//  app; the clock is the wall clock, so time away is handled by the same rules (see `GuestRules.verdict`): a guest whose time ran out while the app was
//  closed has "gone home" (a short note), unless the app comes back soon enough to see the goodbye.
//

import Foundation
import Observation

nonisolated struct GuestVisit: Codable, Equatable, Sendable {
    enum Kind: String, Codable, Sendable {
        /// `playDate` is only kept so old saves decode; it is treated exactly like `sleepover` (the evening visit).
        case playDate, sleepover
        var title: String { "Invite over" }
        var blurb: String { "Comes in the evening, goes home in the morning" }
        var symbol: String { "moon.stars.fill" }
    }
    /// The visitor's pool id.
    var visitor: Int
    var kind: Kind
    /// Seconds since 1970: the invitation, the arrival at the door (0 = not here yet) and when the visit is over.
    var invitedAt: Double
    var arrivedAt: Double = 0
    var endsAt: Double = 0
    /// The end on the GAME clock (`DayClock.gameTime`, game hours): the game clock stands still while the app is in the background, so the morning is judged on it
    /// whenever the game clock runs the day (nil = the wall clock decides: an old save, or "follow real clock").
    var endsGame: Double? = nil
    var arrived: Bool { arrivedAt > 0 }
}

nonisolated enum GuestTuning {
    /// A friend never comes before this hour of the day (evening starts at 17:00; the hours up to midnight count, 0...17 wait for the evening).
    static let eveningHour = 17.0
    /// A sleepover ends at this local time the next morning (the brain's own morning wake is about 07:10).
    static let morningHour = 7, morningMinute = 30
    /// An arrival before this local hour ends the same morning (a late-night invitation).
    static let lateNightHour = 6
    /// The app comes back this long after the end: the goodbye is still shown (the guest is still there, waves and leaves); later he has "gone home".
    static let graceAfterSleepover: Double = 3 * 3600
    /// The same grace on the game clock (game hours).
    static let graceGameHours: Double = 3
    /// A visit whose end is this old on the wall clock is over for good, whatever the game clock says (the app was closed for days).
    static let staleAfter: Double = 24 * 3600
    /// An invitation nobody came home to answer for this long is dropped quietly.
    static let inviteExpires: Double = 2 * 86_400
    /// Where the guest comes in and goes out (the same back edge the adopted Jelbie walks in from).
    static let door = SIMD2<Float>(1.1, -2.2)
    /// Seconds after the player is home before the knock.
    static let knock: Float = 1.8
}

nonisolated enum GuestRules {
    static func morningEnd(after arrival: Date, calendar c: Calendar = .current) -> Date {
        var comps = c.dateComponents([.year, .month, .day], from: arrival)
        comps.hour = GuestTuning.morningHour; comps.minute = GuestTuning.morningMinute; comps.second = 0
        let today = c.date(from: comps) ?? arrival.addingTimeInterval(8 * 3600)
        let h = c.component(.hour, from: arrival)
        if h < GuestTuning.lateNightHour { return today }
        return c.date(byAdding: .day, value: 1, to: today) ?? today.addingTimeInterval(86_400)
    }
    /// The end of a visit that begins at `arrival`: the next morning. `sleepoverSeconds`: on the game clock that is 7:30 GAME time (`DayClock.secondsToSleepoverEnd`); nil = the phone clock's 07:30.
    static func endsAt(arrival: Date, calendar: Calendar = .current, sleepoverSeconds: Double? = nil) -> Date {
        sleepoverSeconds.map { arrival.addingTimeInterval($0) } ?? morningEnd(after: arrival, calendar: calendar)
    }

    /// An invited friend may be at the door from 17:00 until midnight; before 17:00 (and after midnight) he waits for the evening.
    static func canArrive(hour: Double) -> Bool { DayMath.wrap(hour) >= GuestTuning.eveningHour }
    /// "this evening" / "tonight" for the notes and the Friends screen.
    static func when(hour: Double) -> String { DayMath.wrap(hour) >= 21 ? "tonight" : "this evening" }

    enum Verdict: Equatable {
        case stay                  // not over (or not here yet and still wanted)
        case goodbye               // over, but the app is back soon enough to wave him off
        case wentHome              // over a while ago: he has gone (a note)
        case dropped               // an old invitation nobody answered
    }
    /// The visit is over: on the game clock when it was recorded there (`gameNow` = `DayClock.gameNow`), else on the wall clock.
    static func isOver(_ v: GuestVisit, now: Double, gameNow: Double? = nil) -> Bool {
        guard v.arrived else { return false }
        if let g = v.endsGame, let gn = gameNow { return gn >= g }
        return now >= v.endsAt
    }
    static func verdict(_ v: GuestVisit, now: Double, gameNow: Double? = nil) -> Verdict {
        guard v.arrived else { return now - v.invitedAt > GuestTuning.inviteExpires ? .dropped : .stay }
        if now - v.endsAt > GuestTuning.staleAfter { return .wentHome }
        if !isOver(v, now: now, gameNow: gameNow) { return .stay }
        if let g = v.endsGame, let gn = gameNow { return gn - g <= GuestTuning.graceGameHours ? .goodbye : .wentHome }
        return now - v.endsAt <= GuestTuning.graceAfterSleepover ? .goodbye : .wentHome
    }
    static func note(_ name: String, _ kind: GuestVisit.Kind = .sleepover) -> String { "\(name) went home this morning" }
}

@MainActor
@Observable
final class GuestBook {
    static let key = "GuestVisit.v1"
    enum Phase { case away, walkingIn, here, leaving }

    /// The invitation or the visit now (one at a time).
    private(set) var visit: GuestVisit?
    /// The guest's card is open.
    var card = false
    /// The arrival moment (Park/GuestArrival.swift): the card on screen, the dim under it, the name on it, when "Welcome!" showed (CACurrentMediaTime).
    var arrivalCard: ArrivalCardStage = .hidden
    var arrivalDim = false
    var arrivalName = ""
    var welcomeAt: Double = 0
    @ObservationIgnored var arrival = ArrivalClock()
    @ObservationIgnored var arrivalTarget: SIMD2<Float>?
    /// The hug waits this long (seconds) for a guest still running.
    @ObservationIgnored var hugWait: Float?
    @ObservationIgnored private let defaults: UserDefaults

    // the body and the run (GameCare+Guest.swift); none of it is saved
    @ObservationIgnored var actor: JellyActor?
    @ObservationIgnored var phase: Phase = .away
    @ObservationIgnored var phaseT: Float = 0
    @ObservationIgnored var stage = 0
    @ObservationIgnored var knockT: Float = 0
    @ObservationIgnored var bedT: Float = 1.5
    @ObservationIgnored var wakeT: Float = 0
    @ObservationIgnored var greeted = false
    @ObservationIgnored var settleT: Float = 0
    @ObservationIgnored var checkT: Float = 0
    /// A group serving was on last step (the guest cheers with the Jelbies when it ends).
    @ObservationIgnored var snack = false
    @ObservationIgnored var spawnFailT: Float = 0
    @ObservationIgnored var friendSession: [Int: ObjectIdentifier] = [:]
    /// A note to show once (a visit that ended while the app was closed).
    @ObservationIgnored var pendingNote: String?

    nonisolated deinit {}

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let d = defaults.data(forKey: Self.key), let v = try? JSONDecoder().decode(GuestVisit.self, from: d) { visit = v }
    }

    var present: Bool { actor != nil }
    var waitingToArrive: Bool { visit.map { !$0.arrived } ?? false }

    private func save() {
        if let v = visit, let d = try? JSONEncoder().encode(v) { defaults.set(d, forKey: Self.key) } else { defaults.removeObject(forKey: Self.key) }
    }

    /// One at a time. False = somebody is already coming or here.
    @discardableResult
    func invite(visitor: Int, kind: GuestVisit.Kind, now: Double) -> Bool {
        guard visit == nil else { return false }
        visit = GuestVisit(visitor: visitor, kind: kind, invitedAt: now)
        knockT = 0
        save()
        return true
    }
    /// The invitation is taken back (only before he arrived).
    func cancelInvite() {
        guard let v = visit, !v.arrived else { return }
        visit = nil; save()
    }
    /// He is at the door: the clock of the visit starts.
    func markArrived(now: Double, calendar: Calendar = .current, sleepoverSeconds: Double? = nil, endsGame: Double? = nil) {
        guard var v = visit, !v.arrived else { return }
        v.arrivedAt = now
        v.endsAt = GuestRules.endsAt(arrival: Date(timeIntervalSince1970: now), calendar: calendar, sleepoverSeconds: sleepoverSeconds).timeIntervalSince1970
        v.endsGame = endsGame
        visit = v; save()
    }
    /// The player says goodbye early: the visit is over now.
    func endNow(now: Double) {
        guard var v = visit, v.arrived else { return }
        v.endsAt = min(v.endsAt, now); v.endsGame = nil
        visit = v; save()
    }
    /// The visitor was merged into another record (ParkBook migration): the visit follows the survivor.
    func repoint(to id: Int) {
        guard var v = visit, v.visitor != id else { return }
        v.visitor = id; visit = v; save()
    }
    /// The visit is over (he has gone).
    func finish() {
        visit = nil; card = false; arrival.cancel(); arrivalCard = .hidden; arrivalDim = false; hugWait = nil; phase = .away; stage = 0; phaseT = 0; greeted = false; friendSession = [:]; save()
    }
}
