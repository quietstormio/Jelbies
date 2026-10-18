//
//  JelbiesProvider.swift
//  Reads the app's snapshot from the App Group and projects it FORWARD with the app's own away-decay math (AwayMath): one entry every
//  30 min for 12 h, so the Home Screen shows the Jellies getting hungry through the day with the app closed. Never writes anything.
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
    ])

    func placeholder(in context: Context) -> JelbiesEntry {
        JelbiesEntry(date: .now, states: Self.sample.project(at: .now), portraits: [:])
    }

    func getSnapshot(in context: Context, completion: @escaping (JelbiesEntry) -> Void) {
        let snap = load() ?? Self.sample
        completion(JelbiesEntry(date: .now, states: snap.project(at: .now), portraits: portraits(for: snap.jellies.map(\.id))))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<JelbiesEntry>) -> Void) {
        let now = Date()
        guard let snap = load() else {
            completion(Timeline(entries: [JelbiesEntry(date: now, states: [], portraits: [:])], policy: .after(now.addingTimeInterval(JellyTimeline.step))))
            return
        }
        let pics = portraits(for: snap.jellies.map(\.id))
        let dates = JellyTimeline.entryDates(from: now)
        let entries = dates.map { JelbiesEntry(date: $0, states: snap.project(at: $0), portraits: pics) }
        completion(Timeline(entries: entries, policy: .after(dates.last ?? now.addingTimeInterval(JellyTimeline.horizon))))
    }
}
