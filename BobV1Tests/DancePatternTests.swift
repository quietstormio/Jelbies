//
//  DancePatternTests.swift
//  The Jelly Show's Dance prompts follow each song: the generated Swift data equals scripts/dance/patterns.json, every pattern is playable (order, spacing, foot runs, ends on the
//  final downbeat), the rank and dev-argument choice of pattern, the sim's times / feet, the chip count, and (decoded audio) the prompts sit on hits where the music has real gaps.
//

import XCTest
@testable import BobV1

@MainActor
final class DancePatternTests: XCTestCase {
    private struct JSONPrompt: Decodable { var slot: Int; var time_s: Double; var foot: String }
    private struct JSONPattern: Decodable { var prompts: [JSONPrompt] }
    private struct JSONGrid: Decodable { var first_beat_s: Double; var period_s: Double; var last_beat: Int }
    private struct JSONSong: Decodable { var title: String; var grid: JSONGrid; var notes: [String]; var old: JSONPattern; var calm: JSONPattern; var lively: JSONPattern
        func pattern(_ p: DancePattern) -> JSONPattern { switch p { case .old: return old; case .calm: return calm; case .lively: return lively } } }

    private func json() throws -> [Int: JSONSong] {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("scripts/dance/patterns.json")
        let raw = try JSONDecoder().decode([String: JSONSong].self, from: Data(contentsOf: url))
        return Dictionary(uniqueKeysWithValues: raw.map { (Int($0.key)!, $0.value) })
    }

    /// Nobody edits the Swift data (DancePatterns.swift) or scripts/dance/patterns.json without the other.
    func testSwiftDataEqualsTheJson() throws {
        let j = try json()
        XCTAssertEqual(Set(j.keys), Set(DanceSong.all.map(\.song)))
        XCTAssertEqual(Set(DancePatternData.words.keys), Set(j.keys))
        for s in DanceSong.all {
            let js = try XCTUnwrap(j[s.song])
            XCTAssertEqual(js.title, s.title); XCTAssertEqual(js.grid.first_beat_s, s.grid.firstBeat, accuracy: 1e-9)
            XCTAssertEqual(js.grid.period_s, s.grid.period, accuracy: 1e-9); XCTAssertEqual(js.grid.last_beat, s.lastBeat)
            for p in DancePattern.allCases {
                let want = js.pattern(p).prompts.map { DancePrompt(slot: $0.slot, foot: $0.foot == "L" ? 0 : 1) }
                XCTAssertEqual(s.prompts(p), want, "song \(s.song) \(p): Swift data differs from the json")
                XCTAssertEqual(s.promptCount(p), js.pattern(p).prompts.count)
                for (a, b) in zip(s.prompts(p), js.pattern(p).prompts) { XCTAssertEqual(s.time(ofSlot: a.slot), b.time_s, accuracy: 0.001, "song \(s.song) \(p) slot \(a.slot): time_s") }
            }
        }
    }

    func testEveryPatternIsPlayable() {
        for s in DanceSong.all {
            for p in DancePattern.allCases {
                let ps = s.prompts(p), name = "song \(s.song) \(p)"
                XCTAssertFalse(ps.isEmpty, name)
                XCTAssertEqual(zip(ps, ps.dropFirst()).filter { $0.slot >= $1.slot }.count, 0, "\(name): slots strictly increase")
                XCTAssertGreaterThanOrEqual(s.time(ofSlot: ps[0].slot), s.grid.time(ofBeat: DanceSong.firstPromptBeat) - 1e-9, "\(name): first at or after beat 4")
                XCTAssertEqual(ps.last?.slot, 2 * s.lastBeat, "\(name): last on the final downbeat")
                for (a, b) in zip(ps, ps.dropFirst()) { XCTAssertGreaterThanOrEqual(s.time(ofSlot: b.slot) - s.time(ofSlot: a.slot), 0.25 - 1e-9, "\(name): no two closer than 0.25 s") }
                var run = 1
                for (a, b) in zip(ps, ps.dropFirst()) { run = a.foot == b.foot ? run + 1 : 1; XCTAssertLessThanOrEqual(run, 3, "\(name): same foot more than 3 in a row at slot \(b.slot)") }
                if p != .lively { XCTAssertTrue(ps.allSatisfy { $0.slot % 2 == 0 }, "\(name): on the beats only") }
                else { XCTAssertTrue(ps.contains { $0.slot % 2 == 1 }, "\(name): has quick doubles") }
                if p == .old { XCTAssertEqual(ps.count, s.lastBeat - DanceSong.firstPromptBeat + 1, "old = one per beat") }
                else { XCTAssertLessThan(s.promptCount(.calm), s.promptCount(.old), "calm has rests") }
            }
        }
    }

    func testRankAndDevArgumentChoosePatterns() {
        XCTAssertEqual(ShowRank.allCases.map { DancePattern.forRank($0) }, [.calm, .calm, .lively, .lively])
        for r in ShowRank.allCases { XCTAssertEqual(DancePattern.resolve(rank: r, override: nil), DancePattern.forRank(r)) }
        for p in DancePattern.allCases { XCTAssertEqual(DancePattern.resolve(rank: .ocean, override: p.rawValue), p, "-DancePattern \(p.rawValue) forces it") }
        XCTAssertEqual(DancePattern.resolve(rank: .puddle, override: "nonsense"), .calm, "an unknown value is ignored")
        // the real argument (dev builds): read from the defaults
        let d = UserDefaults.standard
        d.set("old", forKey: "DancePattern"); defer { d.removeObject(forKey: "DancePattern") }
        XCTAssertTrue(DevArgs.enabled)
        XCTAssertEqual(DancePattern.resolve(rank: .lagoon), .old)
        var s = ShowSim(rank: .lagoon, theme: .bunnyPicnic, dayKey: 1, player: ShowPlayerInput(name: "Bob"), rivals: [], seed: 3)
        s.finishLook(); s.beginDance(song: DanceSong.song(2), songTime: 0)
        XCTAssertEqual(s.dance?.total, DanceSong.song(2).promptCount(.old), "-DancePattern old reaches the sim")
    }

    func testSimTimesAndFeetFollowThePattern() {
        for s in DanceSong.all {
            for p in DancePattern.allCases {
                let d = ShowDanceSim(song: s, pattern: p, timing: .kind, seed: 7, songTime: 0)
                XCTAssertEqual(d.total, s.promptCount(p))
                for (pr, w) in zip(d.prompts, s.prompts(p)) {
                    XCTAssertEqual(pr.time, s.grid.firstBeat + Double(w.slot) * s.grid.period / 2, accuracy: 1e-9)
                    XCTAssertEqual(pr.foot, w.foot, "no seeded mirroring")
                }
                XCTAssertEqual(d.hasQuickDoubles, p == .lively, "song \(s.song) \(p)")
            }
        }
        // the seed changes nothing
        let a = ShowDanceSim(song: .song(4), pattern: .calm, timing: .kind, seed: 1, songTime: 0), b = ShowDanceSim(song: .song(4), pattern: .calm, timing: .kind, seed: 2, songTime: 0)
        XCTAssertEqual(a.prompts, b.prompts)
        // a quick double is judged on its own prompts: both taps count
        var d = ShowDanceSim(song: .song(1), pattern: .lively, timing: .standard, seed: 1, songTime: 0)
        let i = d.prompts.firstIndex { $0.slot % 2 == 1 }!
        for k in 0...i { d.tap(foot: d.prompts[k].foot, at: d.prompts[k].time + ShowDanceSim.latencyOffset) }
        XCTAssertEqual(d.perfects, i + 1); XCTAssertEqual(d.misses, 0)
    }

    func testCueLeadSitsBetweenAQuickDoublesPrompts() {
        XCTAssertEqual(ShowFlow.cueLead(period: 0.5, gap: 0.5), 0.25); XCTAssertEqual(ShowFlow.cueLead(period: 0.5, gap: 0.25), 0.125, "a quick double's cue sits between the two prompts")
        XCTAssertEqual(ShowFlow.cueLead(period: 0.5, gap: .infinity), 0.25)
    }

    /// Decoded audio: onset strength at the prompt slots against the whole-beat slots the pattern leaves empty. Reported for all four songs; asserted where the rests are real gaps (song 2).
    func testPromptsSitOnHitsWhereTheMusicHasGaps() throws {
        let j = try json()
        var lines: [String] = []
        for s in DanceSong.all {
            let e = try DanceSongGridTests.envelope(s.track)
            for p in [DancePattern.calm, .lively] {
                let used = Set(s.prompts(p).map(\.slot))
                let rest = (2 * DanceSong.firstPromptBeat...2 * s.lastBeat).filter { $0 % 2 == 0 && !used.contains($0) }
                let on = s.prompts(p).map { DanceSongGridTests.peak(e, at: s.time(ofSlot: $0.slot)) }
                let off = rest.map { DanceSongGridTests.peak(e, at: s.time(ofSlot: $0)) }
                let ratio = (on.reduce(0, +) / Double(on.count)) / max(off.reduce(0, +) / Double(max(off.count, 1)), 1e-9)
                let lvOn = s.prompts(p).map { e.levelDB(from: s.time(ofSlot: $0.slot)) }.reduce(0, +) / Double(on.count)
                let lvOff = rest.map { e.levelDB(from: s.time(ofSlot: $0)) }.reduce(0, +) / Double(max(rest.count, 1))
                let line = String(format: "[patterntest] song %d %@: %d prompt slots vs %d rest beats: onset ratio %.2f, level %+.1f dB (prompts %.1f, rests %.1f dB)", s.song, p.rawValue, on.count, off.count, ratio, lvOn - lvOff, lvOn, lvOff)
                print(line); lines.append(line)
                // song 2's rests are real gaps in the music (the json's note: broadband -18 to -20 dB there, -10 to -13 elsewhere): the prompts sit on the louder hits.
                // Songs 1, 3 and 4 hit on every beat (their rests are a design choice): reported only.
                if s.song == 2 { XCTAssertGreaterThan(lvOn - lvOff, 4, line + " | " + (j[2]?.notes.first ?? "")) }
            }
        }
        XCTAssertEqual(lines.count, 8)
    }
}
