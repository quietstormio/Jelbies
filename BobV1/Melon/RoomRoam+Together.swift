import Foundation
import simd

/// Step 2 of the home room round (2026-11-15; the user: "More interaction between them ... they should do more emotes"). Live only where `roomTogether` says so
/// (RoomRoam.swift): a free body in the home room. `-RoomTogether 0` gives the timing and the wander goals from before the round. No new emote kinds.
///  G1  the solo emotes (the treat slot) come sooner: the wait drawn after one is x `soloGap`;
///  G2  the emotes together (conga line, ring dance) come sooner: the cooldown after one is x `treatCool`, the wait with company before one x `treatWait`;
///  G3  a visit: one who has had no company for `visitAfter` s and stands apart from everybody picks, with chance `visitChance`, a wander goal next to a
///      housemate (the ordinary social roll does the rest when he gets there). Before, a wander goal was always pushed away from the others.
/// Each part has a dev switch (`-RoomTogetherSolo 0`, `-RoomTogetherTreat 0`, `-RoomTogetherVisit 0`); in a headless run the environment
/// `ROOMTOGETHER_OFF=solo,treat,visit` turns parts off. The numbers have environment seams for the measuring test only.
nonisolated enum RoomTogether {
    private static func devOn(_ key: String) -> Bool {
        !(DevArgs.enabled && UserDefaults.standard.object(forKey: key) != nil && UserDefaults.standard.integer(forKey: key) == 0)
    }
    private static let envOff = Set((ProcessInfo.processInfo.environment["ROOMTOGETHER_OFF"] ?? "").split(separator: ",").map { String($0) })
    private static func env(_ name: String, _ fallback: Float) -> Float { Float(ProcessInfo.processInfo.environment[name] ?? "") ?? fallback }

    nonisolated(unsafe) static var soloSooner = devOn("RoomTogetherSolo") && !envOff.contains("solo")
    nonisolated(unsafe) static var treatSooner = devOn("RoomTogetherTreat") && !envOff.contains("treat")
    nonisolated(unsafe) static var visits = devOn("RoomTogetherVisit") && !envOff.contains("visit")

    nonisolated(unsafe) static var soloGap = env("ROOMTOGETHER_SOLO_GAP", 0.55)          // x the wait drawn after a solo emote
    nonisolated(unsafe) static var treatCool = env("ROOMTOGETHER_TREAT_COOL", 0.6)          // x the cooldown after a conga line / ring dance
    nonisolated(unsafe) static var treatWait = env("ROOMTOGETHER_TREAT_WAIT", 0.7)          // x the wait with company before one
    nonisolated(unsafe) static var visitAfter = env("ROOMTOGETHER_VISIT_AFTER", 6)          // s without a social before a visit is thought of
    nonisolated(unsafe) static var visitChance = env("ROOMTOGETHER_VISIT_CHANCE", 0.5)          // per wander pick, once the rest holds
    nonisolated(unsafe) static var visitApart = env("ROOMTOGETHER_VISIT_APART", 2.3)          // x peerGap: nobody nearer than this = he stands apart
    nonisolated(unsafe) static var visitNear = env("ROOMTOGETHER_VISIT_NEAR", 1.25)          // x peerGap: the best goals are this far from the housemate ...
    nonisolated(unsafe) static var visitFar = env("ROOMTOGETHER_VISIT_FAR", 1.85)          // ... to this far
    nonisolated(unsafe) static var visitFade = env("ROOMTOGETHER_VISIT_FADE", 1.6)          // x peerGap: beyond `visitFar` the pull fades to nothing over this
    nonisolated(unsafe) static var visitPull = env("ROOMTOGETHER_VISIT_PULL", 1.0)          // x the old spread term's size

    /// What ran: 0 solo waits shortened, 1 treat cooldowns shortened, 2 treat waits shortened, 3 wander picks that were a visit, 4 candidates scored as a visit.
    nonisolated(unsafe) static var counts = [0, 0, 0, 0, 0]
    static var report: String {
        String(format: "together solo=%d treatCool=%d treatWait=%d visit=%d visitScored=%d", counts[0], counts[1], counts[2], counts[3], counts[4])
    }
}

extension BlobBrain {
    /// G1: called right after a solo emote started and its next wait was drawn (`treatMaybeStart`).
    func roomSoloSooner() {
        guard RoomTogether.soloSooner, roomTogether else { return }
        idleState.treat *= RoomTogether.soloGap
        RoomTogether.counts[0] += 1
    }
    /// G2: called right after the cooldown of a conga line / ring dance was drawn (`socialRelease`).
    func roomTreatCoolSooner() {
        guard RoomTogether.treatSooner, roomTogether else { return }
        socialBook.treatCool *= RoomTogether.treatCool
        RoomTogether.counts[1] += 1
    }
    /// G2: called right after the next wait with company was drawn (`socialTreatWatch`).
    func roomTreatWaitSooner() {
        guard RoomTogether.treatSooner, roomTogether else { return }
        socialBook.treatLimit *= RoomTogether.treatWait
        RoomTogether.counts[2] += 1
    }

    /// A housemate worth walking over to: awake, on his own feet, in no session, calm.
    func roomVisitable(_ o: BlobBrain) -> Bool {
        o !== self && o.idleState.kind != .sleep && !o.sleepLocked && !o.held && o.social == nil && !o.socialTaken && o.autonomy && o.attached
            && o.idleDeepNight < 0.5 && o.idleMood != .grumpy
    }
    /// Where he will be when I get there: his walk target while he walks, else where he stands.
    func roomVisitSpot(_ o: BlobBrain) -> SIMD2<Float> {
        if case .walk(let t, _) = o.script { return t }
        return o.position
    }
    /// G3: is this wander pick a visit? (`pickRoamGoal`, once per call.) No random number is drawn unless everything else holds, so a body outside the home
    /// room, a lone creature and a switched-off part keep their random stream.
    func roomVisit(_ others: [BlobBrain]) -> Bool {
        guard RoomTogether.visits, !others.isEmpty, roomTogether else { return false }
        guard socialBook.enabled, anticsEnabled, social == nil, idleMood != .grumpy, idleDeepNight < 0.5, socialBook.drought >= RoomTogether.visitAfter else { return false }
        let friends = others.filter { roomVisitable($0) }
        guard !friends.isEmpty else { return false }
        let here = position, apart = peerGap * RoomTogether.visitApart
        guard friends.allSatisfy({ simd_distance(roomVisitSpot($0), here) > apart }) else { return false }          // (somebody is with him already)
        guard rand() < RoomTogether.visitChance else { return false }
        RoomTogether.counts[3] += 1
        return true
    }
    /// G3: the spread term of `pickRoamGoal` (`nearest`: how far the candidate is from everybody, the farther the better, at most 5) turned round for a visit:
    /// the full 5 for a candidate `visitNear`...`visitFar` body gaps from a housemate, fading to 0 farther off. A candidate nearer than `visitNear` to anybody
    /// keeps its old (small) value, so it still loses; the "do not stand in front of somebody" rule and every floor rule of the caller stay as they are.
    func roomVisitNearest(_ cand: SIMD2<Float>, _ others: [BlobBrain], _ nearest: Float) -> Float {
        let lo = peerGap * RoomTogether.visitNear, hi = peerGap * RoomTogether.visitFar
        guard nearest >= lo else { return nearest }
        var dv = Float.greatestFiniteMagnitude
        for o in others where roomVisitable(o) { dv = min(dv, simd_distance(roomVisitSpot(o), cand)) }
        guard dv < Float.greatestFiniteMagnitude else { return nearest }
        let fit: Float = dv <= hi ? 1 : max(0, 1 - (dv - hi) / (peerGap * RoomTogether.visitFade))
        RoomTogether.counts[4] += 1
        return 5 * RoomTogether.visitPull * fit
    }
}
