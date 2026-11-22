//
//  StoryFactsBuilder.swift
//  Gathers `StoryFacts` from the game's real data (MainActor: the care, the trophy books, the habit store).
//

import Foundation

@MainActor
enum StoryFactsBuilder {
    /// Facts about the Jelmiko in room slot `slot`, plus one `Housemate` per other Jelmiko at home.
    static func make(care: GameCare, slot: Int, shownParagraph: String? = nil, now: Date = Date()) -> StoryFacts? {
        guard let p = care.jelly(slot) else { return nil }
        let c = p.character
        let info = SpeciesInfo.of(JellyRoster.species(c))
        let habits = StoryHabitStore.shared.habits(c)
        var f = StoryFacts(id: c, name: care.rosterName(slot), kindName: info.name, kindAbout: info.about, shownParagraph: shownParagraph ?? info.about, mood: "")
        f.personality = p.traits?.personality.rawValue
        f.favouriteFood = p.traits?.snack

        if let inp = care.widgetInputs().first(where: { $0.id == slot }) {
            let st = JellyState(record: WidgetBridge.record(inp, look: ""), awaySeconds: 0)
            f.mood = JellyStatus.word(st, sleeping: care.asleepForAway(slot), night: SleepHours.isNight(hour: DayClock.shared.hour))
        }

        // trophies
        let shelf = care.race.trophies.shelf(character: c)
        let show = care.show.progress.trophies(character: c)
        var t = StoryFacts.Trophies()
        t.raceWins = shelf.raceWins; t.raceRibbons = shelf.raceRibbonCount; t.volleyWins = shelf.volleyTotal
        t.showCups = show.cupCount; t.rosettes = WearTag.allCases.filter { show.hasRosette($0) }.count
        t.bestRaceTier = CourseTier.allCases.last(where: { shelf.raceRibbons($0)[0] > 0 })?.title
        t.bestShowRank = ShowRank.allCases.last(where: { show.cup($0) != nil })?.title
        if let (key, date) = (shelf.won ?? [:]).max(by: { $0.value < $1.value }) {
            let parts = key.split(separator: ".").map(String.init)
            t.recentKind = parts.first
            t.recentTier = parts.count > 1 ? (CourseTier(rawValue: parts[1])?.title ?? ShowRank(rawValue: parts[1])?.title ?? VolleyTier(rawValue: parts[1])?.title) : nil
            t.recentDate = TrophyShelfItem.dateText(date)
            t.recentDaysAgo = max(0, Calendar.current.dateComponents([.day], from: date, to: now).day ?? 0)
        }
        f.trophies = t

        // events: the news the line prefers (today or yesterday, not used for its day yet)
        let day = StoryEventStore.shared.today()
        f.today = day
        f.events = StoryEventStore.shared.list(c).newestFirst()
        f.news = f.events.first { day - $0.day <= 1 && StoryBook.shared.newsAvailable($0) }
        f.relationshipLevel = JellyBond.level(c, care.bondDefaults).name

        // habits
        applyHabits(habits, to: &f)
        f.newcomer = habits.everSeconds < 1800 && t.total == 0 && p.stats.meals.isEmpty && p.stats.races == 0

        // housemates
        for o in care.jellies where o.character != c {
            let oi = SpeciesInfo.of(JellyRoster.species(o.character))
            f.housemates.append(housemate(habits, id: o.character, name: o.name, kind: oi.name, other: StoryHabitStore.shared.habits(o.character)))
        }
        markMostPlayed(&f)
        return f
    }

    nonisolated static func applyHabits(_ h: StoryHabits, to f: inout StoryFacts) {
        if let a = h.favouriteActivity, StoryPhrases.activity[a.key] != nil { f.favouriteActivity = a.key; f.favouriteActivityKind = a.kindOfPlay }
        f.favouriteSpot = h.favouriteSpot
        f.togetherShare = h.togetherShare; f.restShare = h.restShare
        f.sleepHabit = h.hasHistory && h.restShare >= 0.3 ? "naps" : nil
        f.minutesSeen = h.minutes
        f.daysTracked = h.firstDay == 0 ? 0 : max(0, h.decayDay - h.firstDay)
    }

    nonisolated static func housemate(_ h: StoryHabits, id: Int, name: String, kind: String, other: StoryHabits? = nil) -> StoryFacts.Housemate {
        var m = StoryFacts.Housemate(id: id, name: name, kindName: kind, playShare: h.playShare(with: id), togetherSeconds: h.seconds(with: id), topEmote: h.topEmote(with: id), sharedGroup: h.groupSeconds(with: id) >= 20)
        if let o = other {
            if let a = h.favouriteSpot, a == o.favouriteSpot { m.sharedSpot = a }
            m.napBuddies = h.hasHistory && o.hasHistory && h.restShare >= 0.3 && o.restShare >= 0.3
        }
        return m
    }

    nonisolated static func markMostPlayed(_ f: inout StoryFacts) {
        let best = f.housemates.max { $0.togetherSeconds < $1.togetherSeconds }
        f.mostPlayedWithID = (best?.togetherSeconds ?? 0) >= 60 ? best?.id : nil
        for i in f.housemates.indices { f.housemates[i].mostPlayedWith = f.housemates[i].id == f.mostPlayedWithID }
    }
}
