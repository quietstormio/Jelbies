//
//  ShowRivals.swift
//  The other people's Jelbies at the Jelly Show: three per show, each a persona (Poser / Dancer / Trickster), a pastel colour and a stat vector run
//  through the SAME formulas as the player's (ShowScoring), so they are testable headlessly and their difficulty is a table, not a guess.
//  Deterministic for one (day, rank): same-day replays meet the same rivals with the same scores. The rival inputs sit at a per-rank mean with a
//  seeded jitter of +-0.08; the persona adds +0.12 to its own round's inputs and takes 0.06 off the others. A player's FIRST show ever meets
//  rivals 0.10 softer everywhere (a likely podium). Ocean has a named headliner, Duchess Marmalade, who always gets her Glow Burst.
//

import Foundation
import simd

nonisolated enum ShowPersona: String, CaseIterable, Codable, Sendable {
    case poser, dancer, trickster
    var title: String { switch self { case .poser: return "Poser"; case .dancer: return "Dancer"; case .trickster: return "Trickster" } }
    /// A line for the lobby card.
    var blurb: String { switch self { case .poser: return "Dresses to the theme"; case .dancer: return "Never misses a beat"; case .trickster: return "Lands every trick" } }
}

/// The inputs a rival brings to each round (the player's are read from his real state).
nonisolated struct ShowRivalStats: Equatable, Codable, Sendable {
    /// Condition in the theme's main / friend stat (0...1).
    var main: Float, friend: Float
    /// Σ m / slots of the outfit (0...1).
    var outfit: Float
    /// Shine (0...1); rivals carry no dirt.
    var glow: Float
    /// Dance accuracy and skill (0...1).
    var accuracy: Float, skill: Float
    /// Trick reliability, ring timing and the chance a turn's trick matches the theme (0...1).
    var reliability: Float, timing: Float, themePick: Float
}

nonisolated struct ShowRival: Equatable, Codable, Sendable {
    var name: String
    var persona: ShowPersona
    /// sRGB 0...1 body tint.
    var tint: SIMD3<Float>
    var stats: ShowRivalStats
    var headliner = false
    /// The scores this rival makes today (fixed with the rival).
    var scores = ShowScores()
    /// Her Glow Burst fired (the results say so).
    var burst = false
    var tricks: [VoiceTrick] = []
}

nonisolated enum ShowRivalSource {
    static let names = ["Mochi", "Biscuit", "Pebble", "Noodle", "Sprout", "Waffles", "Dumpling", "Tofu", "Pudding", "Bean", "Maple", "Fizz"]
    static let headlinerName = "Duchess Marmalade"
    /// Hues (0...1) the pastel tints are drawn from: mint, honey, lilac, peach, aqua, rose.
    static let hues: [Float] = [0.38, 0.12, 0.76, 0.06, 0.50, 0.93]
    static let jitter: Float = 0.08
    static let personaUp: Float = 0.12, personaDown: Float = 0.06
    static let firstShowEase: Float = 0.10
    static let headlinerUp: Float = 0.05

    /// The per-rank means (spec 6.4): main / friend condition, outfit fill, glow, accuracy, skill, reliability, timing, theme pick.
    static func base(_ r: ShowRank) -> ShowRivalStats {
        switch r {
        case .puddle: return ShowRivalStats(main: 0.25, friend: 0.20, outfit: 0.40, glow: 0.30, accuracy: 0.55, skill: 0.20, reliability: 0.50, timing: 0.40, themePick: 0.40)
        case .pond: return ShowRivalStats(main: 0.45, friend: 0.35, outfit: 0.55, glow: 0.50, accuracy: 0.68, skill: 0.40, reliability: 0.65, timing: 0.55, themePick: 0.60)
        case .lagoon: return ShowRivalStats(main: 0.65, friend: 0.50, outfit: 0.75, glow: 0.70, accuracy: 0.80, skill: 0.60, reliability: 0.80, timing: 0.70, themePick: 0.80)
        case .ocean: return ShowRivalStats(main: 0.85, friend: 0.70, outfit: 0.90, glow: 0.90, accuracy: 0.90, skill: 0.85, reliability: 0.92, timing: 0.85, themePick: 0.95)
        }
    }

    /// Three rivals (one of each persona) for the show of `dayKey` at `rank`. `firstShow`: the player's first show ever.
    static func rivals(dayKey: Int, rank: ShowRank, theme: ShowTheme, firstShow: Bool = false) -> [ShowRival] {
        var g = RaceRNG(seed: ShowSchedule.rivalSeed(dayKey: dayKey, rank: rank))
        var names = Self.names, hues = Self.hues
        var personas = ShowPersona.allCases
        var out: [ShowRival] = []
        for slot in 0..<3 {
            let name = names.remove(at: Int(g.next() * Float(names.count)) % names.count)
            let hue = hues.remove(at: Int(g.next() * Float(hues.count)) % hues.count)
            let persona = personas.remove(at: Int(g.next() * Float(personas.count)) % personas.count)
            var s = base(rank)
            func j() -> Float { (g.next() * 2 - 1) * jitter }
            s.main += j(); s.friend += j(); s.outfit += j(); s.glow += j(); s.accuracy += j(); s.skill += j(); s.reliability += j(); s.timing += j(); s.themePick += j()
            let up = personaUp, down = -personaDown
            s.main += persona == .poser ? up : down; s.friend += persona == .poser ? up : down; s.outfit += persona == .poser ? up : down; s.glow += persona == .poser ? up : down
            s.accuracy += persona == .dancer ? up : down; s.skill += persona == .dancer ? up : down
            s.reliability += persona == .trickster ? up : down; s.timing += persona == .trickster ? up : down; s.themePick += persona == .trickster ? up : down
            var r = ShowRival(name: name, persona: persona, tint: LocalRivalSource.hsv(hue, 0.34, 0.96), stats: s)
            if rank == .ocean, slot == 0 {               // the boss to beat
                r.name = headlinerName; r.headliner = true
                r.stats = shift(r.stats, by: headlinerUp)
            }
            if firstShow { r.stats = shift(r.stats, by: -firstShowEase) }
            r.stats = clamp(r.stats)
            r.tricks = trickPlan(for: r.persona, rng: &g)
            r.scores = scores(for: r, theme: theme, rng: &g)
            if r.headliner { r.burst = true; r.scores.trick = min(100, r.scores.trick + Float(ShowScoring.burstPoints)) }
            else if ShowScoring.burstReady(cheer: r.stats.accuracy, glow: r.stats.glow) { r.burst = true; r.scores.trick = min(100, r.scores.trick + Float(ShowScoring.burstPoints)) }
            out.append(r)
        }
        return out
    }

    static func shift(_ s: ShowRivalStats, by d: Float) -> ShowRivalStats {
        var t = s
        t.main += d; t.friend += d; t.outfit += d; t.glow += d; t.accuracy += d; t.skill += d; t.reliability += d; t.timing += d; t.themePick += d
        return t
    }
    static func clamp(_ s: ShowRivalStats) -> ShowRivalStats {
        func c(_ v: Float) -> Float { min(max(v, 0), 1) }
        return ShowRivalStats(main: c(s.main), friend: c(s.friend), outfit: c(s.outfit), glow: c(s.glow), accuracy: c(s.accuracy), skill: c(s.skill),
                              reliability: c(s.reliability), timing: c(s.timing), themePick: c(s.themePick))
    }

    /// Three different tricks a rival knows (the Trick round shows them one a turn: never a repeat).
    static func trickPlan(for persona: ShowPersona, rng g: inout RaceRNG) -> [VoiceTrick] {
        var pool = ShowTrickInfo.stageTricks
        var out: [VoiceTrick] = []
        for _ in 0..<3 where !pool.isEmpty { out.append(pool.remove(at: Int(g.next() * Float(pool.count)) % pool.count)) }
        return out
    }

    /// The rival's three round scores from her inputs: the player's formulas, with rolls for the trick successes and the theme picks.
    static func scores(for r: ShowRival, theme: ShowTheme, rng g: inout RaceRNG) -> ShowScores {
        var sc = ShowScores()
        sc.look = ShowScoring.look(outfit: r.stats.outfit, main: r.stats.main, friend: r.stats.friend, glow: r.stats.glow, dirt: 0)
        sc.dance = ShowScoring.dance(accuracy: r.stats.accuracy, skill: r.stats.skill)
        var trick = 0
        for k in 0..<ShowScoring.turns {
            let success = g.next() < r.stats.reliability
            // the theme pick: with her theme-pick chance she shows a main-stat trick, else a friend one half the time, else no match
            let roll = g.next()
            let tags: [WearTag] = roll < r.stats.themePick ? [theme.main] : (roll < r.stats.themePick + (1 - r.stats.themePick) * 0.5 ? [theme.friend] : [])
            let t = min(1, max(0, r.stats.timing + (g.next() * 2 - 1) * 0.1))
            trick += ShowScoring.turn(success: success, repeated: k >= r.tricks.count, tags: tags, theme: theme, timing: t)
        }
        sc.trick = Float(min(100, trick))
        return sc
    }

    /// The body palette a rival tint makes (the race's).
    static func palette(for r: ShowRival) -> Palette { LocalRivalSource.palette(for: r.tint, name: r.name) }
}
