import Foundation
import simd

/// Step 3 of the home room round (2026-11-15; the user: "more Jelmiko sounds"). Live only where `roomVoices` says so (RoomRoam.swift): a free body in the home
/// room. `-RoomVoices 0` gives the sounds from before the round. Every voice here is ONE MORE voice through `AudioHub.roomVoice`, which keeps its own clock:
/// the chirps, the context voices and the silence filler never wait for a room voice, so their rates stay what they were (add, never displace).
///  V1  an idle move that had no voice of its own (the tail spin, the flop, the shake, the bow, the belly drum ...) gets a fitting one now and then;
///  V2  an idle move whose own voice stayed silent this time gets a second, smaller chance for the same voice;
///  V3  one who starts something together with a housemate who stands apart calls over first (hello / ooh);
///  V4  after something together ended well: a cheer, an aww or a giggle (the hub's room gap lets only one of the pair speak).
/// Never `.mmhmm` (the user, 2026-11-06). Each part has a dev switch (`-RoomVoicesIdle 0`, `-RoomVoicesRetry 0`, `-RoomVoicesHello 0`, `-RoomVoicesCheer 0`);
/// in a headless run the environment `ROOMVOICES_OFF=idle,retry,hello,cheer` turns parts off. The numbers have environment seams for the measuring test only.
nonisolated enum RoomVoices {
    private static func devOn(_ key: String) -> Bool {
        !(DevArgs.enabled && UserDefaults.standard.object(forKey: key) != nil && UserDefaults.standard.integer(forKey: key) == 0)
    }
    private static let envOff = Set((ProcessInfo.processInfo.environment["ROOMVOICES_OFF"] ?? "").split(separator: ",").map { String($0) })
    private static func env(_ name: String, _ fallback: Double) -> Double { Double(ProcessInfo.processInfo.environment[name] ?? "") ?? fallback }

    nonisolated(unsafe) static var idle = devOn("RoomVoicesIdle") && !envOff.contains("idle")
    nonisolated(unsafe) static var retry = devOn("RoomVoicesRetry") && !envOff.contains("retry")
    nonisolated(unsafe) static var hello = devOn("RoomVoicesHello") && !envOff.contains("hello")
    nonisolated(unsafe) static var cheer = devOn("RoomVoicesCheer") && !envOff.contains("cheer")

    nonisolated(unsafe) static var idleChance = env("ROOMVOICES_IDLE_CHANCE", 0.4)          // V1
    nonisolated(unsafe) static var retryChance = env("ROOMVOICES_RETRY_CHANCE", 0.3)          // V2
    nonisolated(unsafe) static var helloChance = env("ROOMVOICES_HELLO_CHANCE", 0.35)          // V3
    nonisolated(unsafe) static var helloApart = env("ROOMVOICES_HELLO_APART", 1.8)          // x peerGap: the partner stands at least this far off
    nonisolated(unsafe) static var helloEvery = env("ROOMVOICES_HELLO_EVERY", 20)          // s between two calls of one creature
    nonisolated(unsafe) static var cheerChance = env("ROOMVOICES_CHEER_CHANCE", 0.35)          // V4
    nonisolated(unsafe) static var nightMul = env("ROOMVOICES_NIGHT_MUL", 0.6)          // x every chance in the evening / at night (`idleNight` >= 0.3)
    // the hub's guards (AudioHub.roomVoice)
    nonisolated(unsafe) static var afterOwn = env("ROOMVOICES_AFTER_OWN", 2.0)          // s after his own chirp / context voice
    nonisolated(unsafe) static var ownGap = env("ROOMVOICES_OWN_GAP", 5)          // s between two room voices of one creature
    nonisolated(unsafe) static var roomGap = env("ROOMVOICES_ROOM_GAP", 0.7)          // s after anybody's voice
    nonisolated(unsafe) static var fillerLead = env("ROOMVOICES_FILLER_LEAD", 1.5)          // not when his silence filler would speak within this
    nonisolated(unsafe) static var fillerLate = env("ROOMVOICES_FILLER_LATE", 4)          // a filler overdue by more than this is not running: no wait for it

    /// Asked / played per part: [idle asked, idle played, retry asked, retry played, hello asked, hello played, cheer asked, cheer played].
    nonisolated(unsafe) static var counts = [0, 0, 0, 0, 0, 0, 0, 0]
    static var report: String {
        String(format: "voices idle=%d/%d retry=%d/%d hello=%d/%d cheer=%d/%d", counts[1], counts[0], counts[3], counts[2], counts[5], counts[4], counts[7], counts[6])
    }
    /// When each creature last called over (V3), by `steerID`, on the hub's clock.
    nonisolated(unsafe) static var lastHello: [Int: Double] = [:]

    /// V1: the voice of an idle move that has none in `JellyVoiceSet.contextVoice(forIdle:)` and no vocal of its own. A grumpy one only huffs.
    static func idleVoice(_ kind: IdleKind, grumpy: Bool) -> JellyVoice? {
        switch kind {
        case .hmph: return .pfft
        case .tail, .legSpin, .flapHop: return grumpy ? nil : (Bool.random() ? .wheee : .giggle)
        case .hopscotch, .tailThump, .bellyDrum, .signatureFlourish: return grumpy ? nil : .giggle
        case .flop, .scoot, .shake, .decorKick, .soccerKick: return grumpy ? nil : .ooh
        case .decorBoop: return grumpy ? nil : .curious
        case .politeBow: return grumpy ? nil : .hum
        default: return nil
        }
    }
    /// V1 / V2 leave these alone (the wander voice is tuned elsewhere; a yawn, a stumble and a startle already speak often; the window has its chirp at mid
    /// hold; a slump is sad; nobody speaks on the way into sleep).
    static func noIdleVoice(_ kind: IdleKind) -> Bool {
        switch kind { case .wander, .sleep, .yawn, .stumble, .startle, .window, .slump: return true; default: return false }
    }
    /// V3: no call before these (a glance, a quarrel, the quiet and the shy ones).
    static func noHello(_ kind: SocialKind) -> Bool {
        switch kind { case .look, .squabble, .sneak, .peekaboo, .whisperGiggle, .shyWave: return true; default: return false }
    }
    /// V4: what he says after it.
    static func cheerVoice(_ kind: SocialKind) -> JellyVoice {
        switch kind {
        case .nuzzle, .sitTogether, .bagSit, .cuddle, .cheekSquish, .backToBack, .cuddleLean, .swayHug, .groupHug, .spinHug: return .aww
        case .dance, .danceOff, .mirrorDance, .highFive, .chestBump, .littleRace, .tag, .leapfrog, .bellyBounce, .groupCheer, .conga, .circleDance, .congaLine, .ringDance: return .yay
        default: return Bool.random() ? .giggle : .ooh
        }
    }
    /// Evening / night: the lively voices become a hum.
    static func soft(_ v: JellyVoice) -> JellyVoice {
        switch v { case .hum, .curious, .aww, .yawn, .pfft, .nyoo: return v; default: return .hum }
    }
}

extension BlobBrain {
    /// One room voice of mine. True = it played (the mouth opens for a moment, like the filler's).
    @discardableResult
    func roomSay(_ v: JellyVoice, part: Int, src: String) -> Bool {
        RoomVoices.counts[2 * part] += 1
        let walking = activity == .walking || activity == .coming          // (what the stage calls walking: JellyActor.isWalking)
        guard AudioHub.shared.roomVoice(jelly: steerID, v, x: px, walking: walking, src: src) else { return false }
        RoomVoices.counts[2 * part + 1] += 1
        ambientPulse()
        return true
    }
    /// V1 / V2: at the start of every idle move, right after its own context voice had its roll (`idleBegin`). No brain random number is drawn here.
    func roomIdleVoice(_ kind: IdleKind) {
        guard RoomVoices.idle || RoomVoices.retry, !voiceMuted, !RoomVoices.noIdleVoice(kind), roomVoices else { return }
        let night = idleNight >= 0.3
        let dim = night ? RoomVoices.nightMul : 1
        if let own = JellyVoiceSet.contextVoice(forIdle: kind, mood: idleMood) {          // V2: it has a voice; did it play just now?
            guard RoomVoices.retry, idleMood != .grumpy else { return }
            guard AudioHub.shared.secondsSinceVoice(slot: steerID) > 0.05 else { return }          // (yes: nothing to add)
            guard Double.random(in: 0..<1) < RoomVoices.retryChance * dim else { return }
            roomSay(night ? RoomVoices.soft(own.voice) : own.voice, part: 1, src: "retry")
        } else {          // V1: it has none
            guard RoomVoices.idle, let v = RoomVoices.idleVoice(kind, grumpy: idleMood == .grumpy) else { return }
            guard Double.random(in: 0..<1) < RoomVoices.idleChance * dim else { return }
            roomSay(night ? RoomVoices.soft(v) : v, part: 0, src: "idle")
        }
    }
    /// V3: by the one who starts something together, the moment the session exists (`newSession`).
    func roomHelloVoice(_ kind: SocialKind, to o: BlobBrain) {
        guard RoomVoices.hello, !voiceMuted, !kind.isGroup, !RoomVoices.noHello(kind), idleMood != .grumpy, idleNight < 0.3 else { return }
        guard simd_distance(position, o.position) > peerGap * Float(RoomVoices.helloApart), roomVoices else { return }
        let now = AudioHub.clock()
        guard now - (RoomVoices.lastHello[steerID] ?? -100) >= RoomVoices.helloEvery, Double.random(in: 0..<1) < RoomVoices.helloChance else { return }
        if roomSay(Bool.random() ? .hello : .ooh, part: 2, src: "hello") { RoomVoices.lastHello[steerID] = now }
    }
    /// V4: by each of them when something together is over (`socialRelease`), under the game's own "ended happily" rule (the line above the call).
    func roomCheerVoice(_ s: SocialSession) {
        guard RoomVoices.cheer, !voiceMuted, s.end != .aborted, s.end != .stopped, s.kind != .squabble, s.kind != .look, !joyWanted, idleMood != .grumpy else { return }
        guard roomVoices else { return }
        let night = idleNight >= 0.3
        guard Double.random(in: 0..<1) < RoomVoices.cheerChance * (night ? RoomVoices.nightMul : 1) else { return }
        let v = RoomVoices.cheerVoice(s.kind)
        roomSay(night ? RoomVoices.soft(v) : v, part: 3, src: "cheer")
    }
}
