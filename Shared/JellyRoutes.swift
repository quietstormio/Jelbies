//
//  JellyRoutes.swift
//  The deep links and the queued actions shared by the app, Siri (App Intents) and the widget's quick-action buttons.
//  Compiled into the app AND the widget extension, so everything is `nonisolated` (see NeedsCore.swift).
//
//  Routes (`jelbies://...`):
//    jelly/<id>   select that Jelbie (the Home Screen widget tap; JellyLink)
//    feed[/<id>]  open the game and serve the basic food (or the group serving when no id)
//    water[/<id>] open the game and serve water
//    bed          goodnight: the Jelbies go to bed (nap Live Activity, night room)
//    race/<id>    open the Track panel with that Jelbie picked (Jelly Circuit)
//    train/<id>   open training for that Jelbie
//    pet/<id>     call that Jelbie over for a cuddle (focus mode)
//
//  Queued actions (`pending.json` in the App Group): an intent that runs without the app on screen (Siri with the phone locked, a widget button)
//  appends one; the game drains the file on its next `.active` and performs each through the normal care flows, so game rules still apply
//  (food comes from the tray, a drink restores thirst only once it is sipped). Entries older than `PendingActions.maxAge` are dropped unseen.
//

import Foundation

// MARK: - Routes

nonisolated enum JellyRoute: Equatable, Hashable, Codable, Sendable {
    case jelly(Int)
    case feed(Int?)
    case water(Int?)
    case bed
    case race(Int)
    case train(Int)
    case pet(Int)

    /// The Jelbie the route is about (nil: everyone / none).
    var jellyID: Int? {
        switch self {
        case .jelly(let id), .race(let id), .train(let id), .pet(let id): return id
        case .feed(let id), .water(let id): return id
        case .bed: return nil
        }
    }

    var url: URL {
        var s = "\(JellyShare.scheme)://"
        switch self {
        case .jelly(let id): s += "jelly/\(id)"
        case .feed(let id): s += "feed" + (id.map { "/\($0)" } ?? "")
        case .water(let id): s += "water" + (id.map { "/\($0)" } ?? "")
        case .bed: s += "bed"
        case .race(let id): s += "race/\(id)"
        case .train(let id): s += "train/\(id)"
        case .pet(let id): s += "pet/\(id)"
        }
        return URL(string: s)!
    }

    /// Parses one of our links; nil for anything else (wrong scheme, unknown host, bad or out-of-range id).
    static func parse(_ url: URL) -> JellyRoute? {
        if let id = JellyLink.parse(url) { return .jelly(id) }
        guard url.scheme?.lowercased() == JellyShare.scheme, let host = url.host?.lowercased() else { return nil }
        let parts = url.pathComponents.filter { $0 != "/" }
        guard parts.count <= 1 else { return nil }
        var id: Int?
        if let p = parts.first {
            guard let n = Int(p), (0..<JellyShare.maxJellies).contains(n) else { return nil }
            id = n
        }
        switch host {
        case "feed": return .feed(id)
        case "water", "drink": return .water(id)
        case "bed", "goodnight": return parts.isEmpty ? .bed : nil
        case "race": return id.map { .race($0) }
        case "train": return id.map { .train($0) }
        case "pet": return id.map { .pet($0) }
        default: return nil
        }
    }
}

// MARK: - Queued actions

nonisolated struct PendingAction: Codable, Equatable, Sendable {
    var route: JellyRoute
    /// Seconds since 1970.
    var queuedAt: Double
    init(route: JellyRoute, queuedAt: Date) { self.route = route; self.queuedAt = queuedAt.timeIntervalSince1970 }
    var date: Date { Date(timeIntervalSince1970: queuedAt) }
}

nonisolated enum PendingActions {
    static let file = "pending.json"
    /// A queued action is forgotten after a day: a feed asked yesterday should not land on today's full Jelbie.
    static let maxAge: TimeInterval = 24 * 3600

    private static func url(_ directory: URL?) -> URL? { directory?.appendingPathComponent(file) }

    /// Everything queued, oldest first, without the expired ones.
    static func read(from directory: URL? = JellyShare.containerURL, now: Date = .now) -> [PendingAction] {
        guard let u = url(directory), let data = try? Data(contentsOf: u), let all = try? JSONDecoder().decode([PendingAction].self, from: data) else { return [] }
        return all.filter { now.timeIntervalSince($0.date) < maxAge && $0.date.timeIntervalSince(now) < 3600 }.sorted { $0.queuedAt < $1.queuedAt }
    }

    @discardableResult
    static func write(_ actions: [PendingAction], to directory: URL? = JellyShare.containerURL) -> Bool {
        guard let u = url(directory) else { return false }
        let e = JSONEncoder(); e.outputFormatting = [.sortedKeys]
        guard let data = try? e.encode(actions) else { return false }
        return (try? data.write(to: u, options: .atomic)) != nil
    }

    /// Appends one (a second identical queued route replaces the first, so tapping Water twice does not pour two drinks).
    @discardableResult
    static func enqueue(_ route: JellyRoute, in directory: URL? = JellyShare.containerURL, now: Date = .now) -> Bool {
        var list = read(from: directory, now: now).filter { $0.route != route }
        list.append(PendingAction(route: route, queuedAt: now))
        return write(list, to: directory)
    }

    /// Takes everything queued (the file is emptied) and returns it oldest first.
    static func drain(from directory: URL? = JellyShare.containerURL, now: Date = .now) -> [JellyRoute] {
        let list = read(from: directory, now: now)
        if let u = url(directory) { try? FileManager.default.removeItem(at: u) }
        return list.map(\.route)
    }

    /// The routes queued for a Jelbie (the widget shows a small "coming" badge for them).
    static func queued(for id: Int, from directory: URL? = JellyShare.containerURL, now: Date = .now) -> [JellyRoute] {
        read(from: directory, now: now).map(\.route).filter { $0.jellyID == id || $0.jellyID == nil }
    }
}

// MARK: - Bedtime

/// "Put my Jelbies to bed": the moment they were tucked in (nil: not tonight). Lives in the App Group so the widget and Siri see it.
nonisolated enum Bedtime {
    static let file = "bedtime.json"
    /// They wake at 06:00 (DayPhase.morning.startHour).
    static let wakeHour = 6
    /// A tuck-in older than this is over (the next day).
    static let maxAge: TimeInterval = 14 * 3600

    static func read(from directory: URL? = JellyShare.containerURL, now: Date = .now) -> Date? {
        guard let d = directory, let data = try? Data(contentsOf: d.appendingPathComponent(file)),
              let t = try? JSONDecoder().decode(Double.self, from: data) else { return nil }
        let date = Date(timeIntervalSince1970: t)
        guard now.timeIntervalSince(date) < maxAge, date <= now.addingTimeInterval(60) else { return nil }
        return date
    }
    @discardableResult
    static func write(_ date: Date?, to directory: URL? = JellyShare.containerURL) -> Bool {
        guard let d = directory else { return false }
        let u = d.appendingPathComponent(file)
        guard let date else { try? FileManager.default.removeItem(at: u); return true }
        guard let data = try? JSONEncoder().encode(date.timeIntervalSince1970) else { return false }
        return (try? data.write(to: u, options: .atomic)) != nil
    }

    /// The next 06:00 after `date` (today's if it is still ahead).
    static func wakeDate(after date: Date, calendar cal: Calendar = .current) -> Date {
        let start = cal.startOfDay(for: date)
        if let six = cal.date(byAdding: .hour, value: wakeHour, to: start), six > date { return six }
        return cal.date(byAdding: .hour, value: 24 + wakeHour, to: start) ?? date.addingTimeInterval(8 * 3600)
    }

    /// Asleep now: tucked in (and not yet 06:00), or the room's night (21:00-06:00).
    static func isSleeping(at date: Date, tuckedIn: Date?, calendar cal: Calendar = .current) -> Bool {
        if let t = tuckedIn, date >= t, date < wakeDate(after: t, calendar: cal) { return true }
        let h = cal.component(.hour, from: date)
        return h >= 21 || h < wakeHour
    }
}
