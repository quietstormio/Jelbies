//
//  JelbiesProvider.swift
//  Reads the app's snapshot from the App Group and projects it FORWARD with the app's own away-decay math (AwayMath, night hours at half
//  weight exactly as the game applies them on return): one entry every 30 min for 12 h, so the Home / Lock Screen and StandBy show the
//  Jelbies getting hungry through the day with the app closed. Also reads who is tucked in (Bedtime) and what is queued (PendingActions).
//  Never writes game state.
//

import WidgetKit
import UIKit

struct JelbiesProvider: TimelineProvider {
    /// Portraits are read once per timeline (not per entry): they only change when the app re-renders them.
    private func portraits(for ids: [Int]) -> [Int: UIImage] {
        guard let dir = JellyShare.containerURL else { return [:] }
        var out: [Int: UIImage] = [:]
        for id in ids {
            if let img = UIImage(contentsOfFile: dir.appendingPathComponent(JellyShare.portraitFile(id)).path) { out[id] = img }
        }
        return out
    }

    private func load() -> JellySnapshot? { JellySnapshot.read() }

    static let sample = JellySnapshot(savedAt: .now, jellies: [
        JellyRecord(id: 0, name: "Bob", color: "blue", levels: [0.45, 0.8, 0.7], dirt: 0.1, sparkle: 0, mood: "okay"),
        JellyRecord(id: 1, name: "Pip", color: "yellow", levels: [0.9, 0.9, 0.9], dirt: 0.1, sparkle: 0, mood: "happy"),
    ])

    /// One entry at `date`: the projected Jelbies, whether they sleep then, and what is queued.
    static func entry(_ snap: JellySnapshot, at date: Date, portraits: [Int: UIImage], tuckedIn: Date?, queued: [JellyRoute]) -> JelbiesEntry {
        JelbiesEntry(date: date, states: snap.projectNightAware(at: date), portraits: portraits,
                     sleeping: Bedtime.isSleeping(at: date, tuckedIn: tuckedIn), queued: queued)
    }

    func placeholder(in context: Context) -> JelbiesEntry {
        JelbiesEntry(date: .now, states: Self.sample.project(at: .now), portraits: [:])
    }

    func getSnapshot(in context: Context, completion: @escaping (JelbiesEntry) -> Void) {
        let snap = load() ?? Self.sample
        completion(Self.entry(snap, at: .now, portraits: portraits(for: snap.jellies.map(\.id)), tuckedIn: Bedtime.read(), queued: PendingActions.read().map(\.route)))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<JelbiesEntry>) -> Void) {
        let now = Date()
        guard let snap = load() else {
            completion(Timeline(entries: [JelbiesEntry(date: now, states: [], portraits: [:])], policy: .after(now.addingTimeInterval(JellyTimeline.step))))
            return
        }
        let pics = portraits(for: snap.jellies.map(\.id))
        let tucked = Bedtime.read(now: now)
        let queued = PendingActions.read(now: now).map(\.route)
        // the 30-min grid, plus the exact sleep edges (21:00 / 06:00 / the tuck-in's wake) so "napping" flips on time
        var dates = JellyTimeline.entryDates(from: now)
        for edge in Self.sleepEdges(from: now, tuckedIn: tucked) where edge > now && edge < dates.last! { dates.append(edge) }
        dates.sort()
        let entries = dates.map { Self.entry(snap, at: $0, portraits: pics, tuckedIn: tucked, queued: queued) }
        completion(Timeline(entries: entries, policy: .after(dates.last ?? now.addingTimeInterval(JellyTimeline.horizon))))
    }

    /// The next 21:00 and 06:00 after `now`, and the tuck-in's wake time.
    static func sleepEdges(from now: Date, tuckedIn: Date?, calendar cal: Calendar = .current) -> [Date] {
        var out: [Date] = []
        let day = cal.startOfDay(for: now)
        for h in [21, 6, 30, 45] { if let d = cal.date(byAdding: .hour, value: h, to: day) { out.append(d) } }
        if let t = tuckedIn { out.append(Bedtime.wakeDate(after: t, calendar: cal)) }
        return out
    }
}
