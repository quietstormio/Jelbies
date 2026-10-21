//
//  BlobBrain.swift
//  Bob's autonomous brain. Call `tick` once per fixed sim step (before `sim.step()`); it picks what Bob does
//  (wander, look around, step in place, wave, play) and drives only existing handles of the soft body:
//    - the rigid-pose attractor (position, heading, sway, bob, lean),
//    - per-particle targets on the arm / foot particle chains (SoftBody.targets) with temporarily softened arm tets,
//    - the eye openness of the skinner,
//    - GaitDriver for the hop / roll tricks.
//  The body rest shape is never touched: every drive is released afterwards and the jelly settles back by itself.
//

import Foundation
import simd

enum BlobRequest {
    case wave
    case goTo(SIMD2<Float>)
    case eat(at: SIMD2<Float>)
    case drink(at: SIMD2<Float>)
    case come(to: SIMD2<Float>)
    /// Walk to a tray place, square up, and eat there (finger food or fork food, by `dineHooks.fork`): `bites` bites.
    case dine(place: DiningPlace, bites: Int)
    /// Walk to a tray place, square up, tip the whole body until the mouth meets his own straw, and sip: `gulps` gulps.
    case sip(place: DiningPlace, gulps: Int)
}

enum BlobActivity: Equatable {
    case idle, walking, turning, lookingAround, steppingInPlace, waving, playing, eating, drinking, coming
    case touched, recovering
}

final class BlobBrain {
    typealias Activity = BlobActivity

    // MARK: public surface

    /// Master switch: when false `tick` does nothing (the stage runs its old hop-around).
    var enabled = true
    /// The studio stage feeds its orbit camera position into `cameraPosXZ`; the game screen (fixed camera) sets this false.
    var followsStudioCamera = true
    /// Autonomous behaviour (wandering, looking, waving, playing). Requests still run when false.
    var autonomy = true
    var activity: Activity = .idle
    /// Mouth opening 0...1 for the renderer: exactly 0 except while eating / drinking.
    var mouthOpen: Float = 0
    /// Floor position resolver (point, radius) -> corrected point. Default identity; the game passes RoomLayout.resolve.
    var resolve: (SIMD3<Float>, Float) -> SIMD3<Float> = { p, _ in p }
    /// Wander area (disk) used to pick idle targets and as the default bounds.
    var wanderCenter = SIMD2<Float>(0, 0)
    var wanderRadius: Float = 2.5
    /// Where the player's camera is on the floor plane (xz): he faces it to wave.
    var cameraPosXZ = SIMD2<Float>(0, 10)
    /// Optional rectangular wander area (min, max in x, z); when set it replaces the disk.
    var wanderRect: (min: SIMD2<Float>, max: SIMD2<Float>)?
    /// The ordinary wander pick's box when set (wider than `wanderRect`, which the run / zoomies goals keep).
    var wanderRectWide: (min: SIMD2<Float>, max: SIMD2<Float>)?
    /// Longest wander leg.
    var maxWanderLeg: Float = 2.6
    /// The roaming polygon of the room camera (GameCamera.RoamFloor): goals are sampled by area over it, with zone picks and a spread score. nil = the boxes above.
    var roamProvider: (() -> GameCamera.RoamFloor?)?
    /// How often each 1 u cell of the floor was picked as a goal by this Jelly (the spread score prefers the less visited).
    var roamVisits: [Int: Int] = [:]
    /// When idle he turns to face the player and tilts back a little (`attentionPitch` rad) so his flat brows read
    /// friendly from a camera that looks down on him; relaxed while he walks.
    var facePlayerWhenIdle = false
    var attentionPitch: Float = 0
    /// Footprint radius used with `resolve`.
    var footprint: Float = 0.55
    /// The decor piece (uid) he is about to use and may therefore stand inside (the beanbag he sits in, the mat he hops on); nil = every solid piece is a wall.
    var decorIgnore: Int?
    /// He is on top of a beanbag: his floor is its top (`applyBagFloor`); false everywhere else, so no behaviour can leave him on a phantom floor.
    var bagFloorOn = false
    /// The height of the slide's step / chute under him while he rides it (`applyBagFloor`).
    var slideY: Float = 0
    /// Tests: force how a throw ends (0 plain arc, 1 bonk, 2 drop).
    /// Soccer (BlobBrain+Soccer.swift): the plan the stand-spot pick made for the kick about to start, and the tests' forced mode (0 kick, 1 dribble, 2 shoot, 3 rescue).
    var soccerPlan = SoccerIdle()
    var soccerModeForce: Int?
    /// 1 = full motion; lower for reduce-motion.
    var amplitude: Float = 1
    /// Called when a requested job (goTo / eat / drink / come / wave) has finished.
    var onFinished: ((BlobRequest) -> Void)?
    /// Test hook: seeds the random choices.
    var seed: UInt64 { get { rng } set { rng = newValue | 1 } }

    /// Touch play (BlobBrain+Touch.swift): extra lean (rad, forward pitch / roll about his facing axis) and a squash factor, added to the
    /// idle pose while a finger pets him. 0 / 0 / 1 = off (the pose is exactly the brain's own).
    var touchPitch: Float = 0
    var touchRoll: Float = 0
    var touchSquash: Float = 1
    /// "Ears on" (BlobBrain+Ears.swift): the sound-reaction pose channel (dance bounce, giggle, startle, curious tilt), eased in `tick`, added in `drivePose`.
    var ears = EarsPose()

    var walkSpeed: Float = 0.7          // world units / s (~0.6 body widths per second)
    var turnRate: Float = 1.9             // rad / s while turning with small steps (reference: 110-120 deg/s)
    /// His current floor position (xz) and heading as last driven / measured.
    var position: SIMD2<Float> { SIMD2(px, pz) }
    var heading: Float { yaw }

    var gait = GaitDriver()

    // MARK: state

    enum Script {
        case none
        case walk(target: SIMD2<Float>, then: After)
        case turn(to: Float, then: After)
        case look(index: Int, t: Float, base: Float)
        case stepInPlace(t: Float, dur: Float)
        case wave(t: Float, side: Int, then: After)
        case spin(t: Float)
        case hopPlay
        case rollPlay
        case flipPlay                  // the voice backflip (BlobBrain+Flip.swift)
        case eat(t: Float, bowl: SIMD2<Float>, dur: Float, drink: Bool)
        case dine
        case idle                      // an idle behaviour (BlobBrain+Idle.swift): sit, look, yawn, stumble
        case race                      // Jelly Circuit: one committed gait step at a time (BlobBrain+Race.swift)
    }
    enum After { case none, faceCamera, wave, face(SIMD2<Float>), eat(SIMD2<Float>, Bool), doEat(SIMD2<Float>, Bool), dineTurn(DiningPlace), dineGo }

    var script: Script = .none
    /// Jelly Circuit race state (BlobBrain+Race.swift).
    var race = RaceDrive()
    /// Idle behaviours (BlobBrain+Idle.swift): run, stumble, jumping jacks, sit, look, yawn-stretch. State, mood source and the run blend.
    var idleState = IdleState()
    /// The face (BlobBrain+Expression.swift), the mid-walk flourish roll of the current leg and the pending jump for joy (BlobBrain+Flourish.swift), the reactions (BlobBrain+React.swift).
    var expr = ExpressionState()
    var leg = LegState()
    var joyWanted = false, joyAge: Float = 0
    var hmphWanted = false, hmphAge: Float = 0
    var react = ReactState()
    var startingReaction = false
    weak var bus: ReactionBus?
    var idleMood: IdleMood = .okay
    /// Time of day (DayClock): 0...1 night / morning weights. Night makes him sleepier (naps, yawns), morning makes him stretch and wake.
    var idleNight: Float = 0
    var idleMorning: Float = 0
    /// 1 between ~23:00 and 6:00 (DayClock.deepNight): everybody goes to sleep (on his back, in a pile) unless the player is busy with him.
    var idleDeepNight: Float = 0
    /// The sleep (BlobBrain+Sleep.swift) and the lively room life (new antics, shorter waits) are on: the stage sets these; the headless suites that predate them leave them off.
    var sleepEnabled = false
    /// The app is in front and no menu / close-up is open: the room life keeps something happening (see `idleLively`, SocialTuning.lively).
    var watching = false
    /// Perks (Store/Perks.swift) that change how he behaves; the game sets them from his JellyPerks every step.
    var perkFlags = PerkFlags()
    /// The extra solo antics and the new social kinds are in the tables (the room); the headless suites that predate them leave this off.
    var anticsEnabled = false
    /// Music is playing (the stage sets it from the audio hub): he may sway to it.
    var musicPlaying = false
    /// Per-behaviour cooldowns (seconds left): the same antic does not come round again at once.
    var kindCool: [IdleKind: Float] = [:]
    var flopKicks = 0
    var sleep = SleepState()
    /// Seconds until he may again decide to go and snuggle beside a sleeper (BlobBrain+Sleep.swift).
    var snuggleCool: Float = 0
    /// Seconds he stays up after any wake (no bedtime roll outside deep night): kills the sleep / wake / sleep loop (BlobBrain+Sleep.swift).
    var awakeMin: Float = 0
    /// Seconds until the next bedtime roll while mates sleep (set on every failed or abandoned try: the walk to the pile is not retried in a loop).
    var sleepTryCool: Float = 0
    /// The player has this Jelly picked (the "Play with ...?" selection): nobody who is picked goes to bed (GameCare sets it every tick).
    var selectedNow = false
    /// Seconds until the next forced zoomies / run (the "zoomies urge": a visible burst of energy every few minutes in any ordinary mood).
    var zoomUrge: Float = IdleTuning.zoomUrgeFirst
    /// The current sit is a night nap (long hold, eyes closed). Set when the sit starts, cleared when the behaviour ends.
    var napping = false
    /// True while something else owns him (a meal on the tray, focus mode): no idle behaviour starts, a running one yields.
    var idleBlocked = false
    /// Held still only because ANOTHER Jelly's close-up is on (GameCare / the stage set it every frame, with `idleBlocked`). He is free to step aside for the
    /// Jelly who was called (`MelonController.makeRoom`): 2026-10-21 the paused Jellies stood frozen in the called one's path and he could not get through.
    var focusPaused = false
    /// Seconds (eased) he has recently stood or walked within `IdleTuning.centreRadius` of the rug centre: the roam goal score pushes him out (room coverage).
    var centreDwell: Float = 0
    /// A reserved Jelly (a meal is coming for him, GameCare / DiningGroup): he waits where he stands. Unlike `idleBlocked` (rewritten by the stage every frame)
    /// nobody else touches it. Every autonomous starter respects `held`; `pickAutonomous` only allows the wait pose (look at the tray / a neighbour, step in place, a bounce, a blink).
    var reserved = false
    /// Where the waiting Jelly looks first (the tray); nil = at the nearest neighbour or just stays.
    var waitFocus: SIMD2<Float>?
    var waitBounceT: Float = 0
    var held: Bool { idleBlocked || reserved }
    /// Jellies interacting (BlobSocial.swift): the running session and the per-brain bookkeeping.
    var social: SocialSession?
    var socialBook = SocialBook()
    var socialOthers: () -> [BlobBrain] = { [] }
    var onSocial: ((SocialEvent) -> Void)?
    /// Tests / captures: run idle behaviours although `autonomy` is off.
    var idleForced = false
    /// Voice v1: the running idle behaviour was ASKED for by the player. It runs although `autonomy` is off (focus mode) or the stage holds idle back,
    /// and clears itself when the behaviour ends (`idleEnd`).
    var commanded = false
    /// Voice v1: a trick to start on the next tick (the brain owns the skinner, so GameCare only queues it; see `startCommanded`).
    var commandedIdle: IdleKind?
    /// Voice v1: the backflip trick, queued for the next tick. `flipCompact` = focus mode (lower apex so he stays in frame).
    var commandedFlip = false
    var flipCompact = false
    /// Natural voice command "go sit on the beanbag" / "play with the ball": a decor interaction with THAT kind of piece, queued for the next tick.
    var commandedDecor: (kind: IdleKind, only: DecorKind)?
    var commandedNameHop = false
    /// Voice "goodnight": go to bed now (yawn, gather with the others, roll onto the back, sleep tucked in until morning or a tap).
    var commandedGoodnight = false
    /// A race trip is asked or running: no bedtime for anybody (GameCare sets it on every brain).
    var sleepLocked = false
    /// Character features (Features/, BlobBrain+FlapHop.swift): what grows on him, whether his wings are folded under a back item (then the flap-hop is
    /// a plain hop), the largest flap the worn items allow (deg), and the running flap-hop. The stage / GameCare set the first three.
    var feature: JellyFeature = .none
    var wingsFolded = false
    var wingFlapLimit: Float = 75
    var flapHop = FlapHopState()
    var nameHopping = false
    var flipArmA: Float = 0
    /// The flip's smoothed arm angles (rad). `commandedFlipFail` = the queued commanded flip is the funny faceplant.
    var commandedFlipFail = false
    var flipEl: Float = 0, flipSa: Float = 0, flipOut: Float = 0
    private(set) var flipFaceplants = 0
    /// One-shot extra landing impulse for the jelly wobble (JellyJiggle.tick consumes it): the faceplant's thud.
    var jellyKick: Float = 0
    /// True while the flip script owns him (the touch get-up must not treat the faceplant as being knocked over).
    var isFlipping: Bool { if case .flipPlay = script { return true }; return false }
    func noteFaceplant() { flipFaceplants += 1 }
    var flipRoot = SIMD3<Float>(0, 0, 0)
    /// Flip beats for haptics (GameCare compares them with its last seen value): take-off count, landing count.
    private(set) var flipTakeoffs = 0
    private(set) var flipLandings = 0
    var flipPhaseSeen: GaitDriver.Phase = .idle
    func noteFlipBeats(_ takeoff: Bool, _ landing: Bool) { if takeoff { flipTakeoffs += 1; AudioHub.shared.play(.jump, jelly: steerID, x: px) }; if landing { flipLandings += 1 } }
    /// Voice v1: one blink on the next tick (the listening pose).
    var blinkRequested = false
    /// Run blend 0...1 (the third gait point built from the walk: stride x1.2, step rate x1.125, 5.5 deg lean, bigger arm sweep). Exactly 0 = the locked walk.
    var runW: Float = 0
    /// Zoomies blend 0...1 on top of the run (a faster dash: cadence +20 % on top of the run; extra bob or sway pulls the planted feet off the belly, so the wobble is all in the stop and the jelly). 0 = the plain run.
    var zoomW: Float = 0
    /// Eased walk boost (BlobBrain.walkBoost for the plain roam walk, 1 while a run / zoomies / slide is on or blending out); see `walkBoostNow`.
    var walkBoostK: Float = 1.1427
    var slideKicks = 0
    /// Capture aid (`-RunMove zoomies|slide|scoot`): the scheduler always picks this move, with a short cooldown.
    var runMoveDemo: IdleKind?
    /// Touch play: he runs (the run blend) back to the focus spot after a throw; cleared on arrival (BlobBrain+Touch `hurryUpdate`).
    var hurry = false
    /// Idle arm override (render only): per side elevation / sweep (rad) blended in by `armDirW`; 0 = the walking arm untouched.
    var armDirW: Float = 0
    var armDirEl: [Float] = [0, 0]
    var armDirSa: [Float] = [0, 0]
    var armDirOut: Float = 0
    /// Body-led weight 0...1: while a body-led move (jacks, flip, any arm override) runs, the arms stay at or below the rest nub even between their flaps (ArmCap).
    var armShortW: Float = 0
    var job: BlobRequest?           // the request being served (for onFinished)
    var pending: BlobRequest?
    var restTimer: Float = 1.2
    var lastPick = -1
    var sinceWave: Float = 8        // seconds since the last wave
    var sincePlay: Float = 4

    // pose state (what the attractor is told)
    var px: Float = 0, pz: Float = 0
    var yaw: Float = 0
    var roll: Float = 0, pitch: Float = 0, squash: Float = 1, lift: Float = 0
    var pitchBase: Float = 0
    var twist: Float = 0                 // extra heading (the dining reach turns his body toward the arm; the feet stay where they are)
    var poseW: Float = 0            // 0 = free physics, 1 = fully driven
    var poseOn = false              // whether the current step wants the pose driven
    let kPose: Float = 650

    var debugFeet = true
    var swayScale: Float = 1
    var footStiffness: Float = 1500000       // world-target stiffness of the foot particles (1/s^2); 20000 only reached ~40 % of a lift per step
    var geom = FootGeom()
    var footSkin = FootSkin()
    var renderRest: [Float] = []
    /// The sim foot is a thin slab: its sole targets may lift / swing out at most this far (world units) so no slab tet ever inverts; the
    /// full motion is drawn by the rigid render foot (`Skinner.feetVertices`).
    var simFootCap: Float = 0.03
    // Foot beans (FootBean): grow when any foot leaves its rest spot, stay until both have been still for `beanHoldTime`, then shrink back.
    var beanG: Float = 0                 // 0 = hidden (plain embedded feet) ... 1 = beans out, embedded feet retracted
    var beanHold: Float = 0              // seconds the beans stay out after the last foot motion
    var beanHoldTime: Float = 0.7
    /// He wears shoes (GameCare.syncPerks sets it): the beans stay out for good so the rendered foot IS the bean the shell is grown from (no soft-skin foot sagging out under the sole).
    var shoesWorn = false
    var beanGrowTime: Float = 0.12
    var beanFirstIdx: [Int] = []
    var retractReady = false
    var beanScratch: [[SIMD3<Float>]] = [[], []]
    /// Planted boot (0) ... lifted ball (1) morph of each foot bean as last drawn (tests / captures).
    private(set) var beanMorphLast: [Float] = [0, 0]
    var beanStartScratch: [[SIMD3<Float>]] = [[], []]
    var footShift: [SIMD3<Float>] = [.zero, .zero]     // sim foot slab minus body-rigid foot, world (set where the sim soles are targeted)
    var beanSwaps = 0                    // number of grow starts (tests: one swap per action, never per step)
    var beanSwapCount: Int { beanSwaps }
    var beansOut: Bool { beanG > 0 }
    var beanBlend: Float { let k = smooth01(beanG); return k * k }
    var footPlump: Float = 1.6           // a lifted bean is taller than the 0.1 u slab so its rim sinks into the belly (hidden)
    var footDomeY0: Float = 0.040, footDomeY1: Float = 0.112, footDomeMin: Float = 1.0, footDomeRise: Float = 0.0
    var feet = FootGait()
    var feetInit = false             // feet.pos holds valid planted positions
    var feetDrive = true             // the feet follow world targets this tick (false while spinning)
    var nextSwing = 0                // index of the foot that swings next (0 = -x foot)
    var stepLive = false             // a step's root / heading interpolation is running
    var stepRoot0 = SIMD2<Float>(0, 0), stepRootD = SIMD2<Float>(0, 0)
    var stepYaw0: Float = 0, stepYawD: Float = 0
    var walkFinal = false            // the step in progress squares his feet and ends the walk
    var pivotSide: Int?              // pivot the pose on this foot (wave: its planted spot; gait: its nominal spot under the root)
    var pivotNominal = false
    var nubTarget: Float = 0         // nub swing wanted this tick (1 while he steps)
    var nubEnv: Float = 0            // eased envelope of the nub swing
    /// Forward (+) / back (-) pendulum phase of each nub (-1...1); the arms swing against the legs.
    private(set) var nubPhi: [Float] = [0, 0]
    var nubOverride = false          // the render override of the nub counter-swing is on
    var armWalkWant: Float = 0           // 1 = walk base pose + full sweep, 0.5 = turning in place, 0 = rest arm
    /// The arm sweep follows the stride phase of the step clock (see `stridePhase`); one gait point (the march / stride of the phone build).
    let gaitW: Float = 1
    /// Gait tuning (motion table, REF2 walk): steps/s, single-step length (world units; speed = stride * rate), swing lift arc (0.11 H).
    // 2026-10-18: the roam walk is x1.143 stride (same cadence) on top of these (BlobBrain.walkBoost, ground speed 1.144 -> ~1.30 u/s); the run is unchanged
    // 2026-10-21: a +10 % speed-up (stride 0.3355, or stride 0.320 x rate 3.93) was tried and backed out: the 2026-10-18 boost had spent the feet-attached margin
    // (FeetAttach worst overlap walk -0.021 / zoomies -0.021 / call -0.020 at the -0.020 bound) and both variants left the LANDING foot's hidden crown 0.002...0.006
    // short of fused (half-way through its ball-to-boot morph, 0.11 u ahead of a body 0.07 u behind its attractor). Needs a deeper hidden crown or a tighter follow first.
    var stepRate: Float = 3.75     // 3.5 -> 3.75 (Build B, user: a little faster: walk 1.016 -> 1.144 u/s, run 1.350 -> 1.435; the ground speed steps in whole frames of step time); was 3.2 before the 20 % speed-up
    var stride: Float = 0.305      // was 0.27 (measured ground speed 0.853 -> 1.021 u/s)
    var stepLift: Float = 0.035          // was 0.115: a shuffle, the foot stays in the bottom band under the belly (feet-lab 2026-10-17)
    var turnLift: Float = 0.06           // was 0.20
    /// Swing foot sideways swing (world units) and toe-up tilt (rad) at mid swing; waddle roll toward the stance foot (rad), bob lift
    /// (world units), forward / back rock (rad), arm-nub counter-swing (rad).
    var stepOut: Float = 0.02            // was 0.04
    var stepTilt: Float = 0.05           // was 0.25: no wedge, the sole barely shows
    var stepFwd: Float = 0.06          // was 0.30 (a foot length in front of the belly): the swing foot stays under the body. Step length x rate (ground speed) is unchanged
    var waddleRoll: Float = 0.125
    var bobLift: Float = 0.0
    var hopTipBack: Float = 0.5        // fraction of the idle tip-back kept during a hop (the hop test limits the tilt to 12 deg)
    var rockPitch: Float = 0.02
    var bobScale: Float = 1.9
    /// Wave tuning: rigid roll about the far foot (0.30 rad = 17 deg puts the centre over that foot), arm-side foot swing out / up (0.17 H).
    var waveRoll: Float = 0.45
    var waveFootOut: Float = 0.03
    var waveFootLift: Float = 0.05          // was 0.165 (the arm-side foot rose up on the belly)
    var waveFootFwd: Float = 0.06
    var waveFootTilt: Float = 0.08
    var pivotEdge: Float = 0.15          // outer-edge offset of the wave's pivot on the far foot
    /// Precomputed arm-path keyframes by path name (built in the background by `attach(renderMesh:)`).
    private(set) var armKeyframes: [String: ArmKeyframes] = [:]
    var attached = false
    var armBuilding = false
    var armCostSum = 0.0, armCostN = 0
    var armDelta: [SIMD3<Float>] = []
    var armAO: [Float] = []
    var armSide = 1
    var armActive = false
    var armPathName = ArmPath.wave.name      // the keyframe path the active arm override plays (wave, or the dining nubToMouth)
    var armS: Float = 0                      // path parameter for the non-wave paths (set by the dining timeline)
    var armT: Float = 0
    var armBlend: Float = 0
    var rng: UInt64 = 0xA24BAED4963EE407

    // touch recovery
    var calmT: Float = 0
    var recoverT: Float = 0
    var gaitRecover = false
    var stuckT: Float = 0
    var bestDist: Float = .infinity
    var scriptT: Float = 0

    init() {}
    // Avoids the runtime's isolated-deinit hop (it crashed the iOS 26.2 simulator runtime when a brain was released).
    nonisolated deinit {}

    /// A brain set up for the game screen: fixed camera, GameCamera floor bounds, faces the player when idle.
    static func forGame() -> BlobBrain {
        let b = BlobBrain()
        b.followsStudioCamera = false
        b.cameraPosXZ = SIMD2(GameCamera.eye.x, GameCamera.eye.z)
        b.resolve = { [weak b] p, r in GameCamera.constrain(p, radius: r, lowPropScale: RoomLayout.lowPropRadiusScale, ignoreDecor: b?.decorIgnore) }      // the tray is low: only his base keeps off it
        b.footprint = 0.7
        b.wanderRect = GameCamera.roamRect
        b.wanderRectWide = GameCamera.roamRectWide
        b.roamProvider = { GameCamera.roamFloor }
        b.maxWanderLeg = 5.5
        b.facePlayerWhenIdle = true
        b.attentionPitch = 0.28
        let d = UserDefaults.standard
        if d.object(forKey: "BlobPitch") != nil { b.attentionPitch = Float(d.double(forKey: "BlobPitch")) }
        if d.integer(forKey: "BlobNoWander") != 0 { b.autonomy = false }
        // capture aid: -BlobGameDemo gwalk|gturn|ghop|gcome|gwave|gstep runs a scripted loop in the game without the care menu
        if let n = d.string(forKey: "RunMove"), let k = IdleKind(rawValue: n), [.zoomies, .slide, .scoot].contains(k) { b.runMoveDemo = k; b.idleState.cooldown = 2 }
        if let name = d.string(forKey: "BlobGameDemo") { b.demo = name; b.autonomy = false; b.restTimer = 2.0 }
        return b
    }

    // MARK: demo (launch argument -BlobDemo <name>, for visual testing in the studio)

    var demo: String?
    var demoStep = 0

    static func fromLaunchArguments() -> BlobBrain? {
        guard let name = UserDefaults.standard.string(forKey: "BlobDemo") else { return nil }
        let b = BlobBrain()
        b.demo = name
        let d = UserDefaults.standard
        if d.object(forKey: "BobScale") != nil { b.bobScale = Float(d.double(forKey: "BobScale")) }       // tuning aids for captures
        if d.object(forKey: "Stride") != nil { b.stride = Float(d.double(forKey: "Stride")) }
        if d.object(forKey: "BobLift") != nil { b.bobLift = Float(d.double(forKey: "BobLift")) }
        if d.object(forKey: "RockPitch") != nil { b.rockPitch = Float(d.double(forKey: "RockPitch")) }
        if d.object(forKey: "WaddleRoll") != nil { b.waddleRoll = Float(d.double(forKey: "WaddleRoll")) }
        b.autonomy = name == "idle" || name == "play"
        b.restTimer = 1.0
        return b
    }

    func demoTick(_ sim: SoftBody) {
        guard let demo, case .none = script, pending == nil else { return }
        restTimer -= 1.0 / 60
        guard restTimer <= 0 else { return }
        demoStep += 1
        restTimer = 1.0
        switch demo {
        case "wave": pending = .wave
        case "walk": pending = .goTo(SIMD2(demoStep % 2 == 0 ? -1.3 : 1.3, 0))
        case "come": pending = .come(to: SIMD2(0, demoStep % 2 == 0 ? 0.3 : 1.5))
        case "eat": pending = .eat(at: SIMD2(0, -1.4))
        case "drink": pending = .drink(at: SIMD2(0, -1.4))
        case "wfront": pending = .goTo(SIMD2(0, demoStep % 2 == 1 ? 3.0 : -0.5))       // long walks toward / away from the studio camera
        case "wfrontL": pending = .goTo(SIMD2(0, demoStep % 2 == 1 ? -4.0 : 3.0))       // capture aid: away, then one long walk (7 u) toward the studio camera
        case "w34": pending = .goTo(SIMD2(0, demoStep % 2 == 1 ? -3.3 : 0.6))                  // short walks along z: seen at 3/4 (-MelonCamYaw 0.85) he stays in frame
        case "wside": pending = .goTo(SIMD2(demoStep % 2 == 1 ? 3.0 : -3.0, 0))      // long walks across the studio view
        case "gwalk": pending = .goTo(SIMD2(demoStep % 2 == 0 ? -1.8 : 1.8, 0.3))
        case "gcome": pending = .come(to: SIMD2(0, demoStep % 2 == 0 ? -0.8 : 1.0))
        case "gwave": pending = .wave
        case "gturn": startTurn(to: yaw + (demoStep % 2 == 0 ? 2.4 : -2.4), sim: sim)
        case "ghop": startHopPlay(sim: sim)
        case "step": currentPose(sim); script = .stepInPlace(t: 0, dur: 4); activity = .steppingInPlace
        case "gstep": currentPose(sim); script = .stepInPlace(t: 0, dur: 2.2); activity = .steppingInPlace
        case "look": currentPose(sim); script = .look(index: 0, t: 0, base: yaw); activity = .lookingAround
        case "irun": idleStart(.run, sim)
        case "istumble": if idleStart(.run, sim) { idleState.stumbleAt = 1.9 }
        case "ijacks": idleStart(.jacks, sim)
        case "izoomies": idleStart(.zoomies, sim)
        case "islide": idleStart(.slide, sim)
        case "iscoot": idleStart(.scoot, sim)
        case "isit": idleStart(.sit, sim)
        case "islump": idleStart(.slump, sim)
        case "ilook": idleStart(.look, sim)
        case "iyawn": idleStart(.yawn, sim)
        default: break
        }
    }

    /// Paths whose keyframes are precomputed on attach (the wave; eating paths later).
    nonisolated static let armPaths: [ArmPath] = [.wave, .nubToMouth]
    /// Launch argument -WaveArmScale <x> (default 1): scales the posed arm's protrusion and radii together (comparison captures).
    static var waveArmScale: Double {
        UserDefaults.standard.object(forKey: "WaveArmScale") != nil ? UserDefaults.standard.double(forKey: "WaveArmScale") : 1
    }

    /// Give the brain the render mesh so the arm paths can be precomputed (off the main thread unless `synchronous`).
    /// A wave is deferred until its keyframes are ready.
    var hasRenderMesh: Bool { attached }
    var armReady: Bool { !armBuilding && !armKeyframes.isEmpty }
    func attach(renderMesh rm: RenderMesh, synchronous: Bool = false) {
        attached = true
        renderRest = rm.rest
        guard let cap = rm.armCapsule else { return }
        beanFirstIdx = [cap.beanFirst(side: -1), cap.beanFirst(side: 1)]
        armFirstIdx = [cap.first(side: -1), cap.first(side: 1)]
        let rest = rm.rest, mat = rm.mat, scale = Self.waveArmScale
        let index = rm.index
        if synchronous {
            for kf in ArmKeyframeStore.shared.keyframes(paths: Self.armPaths, rest: rest, mat: mat, capsule: cap, index: index, scale: scale) { armKeyframes[kf.name] = kf }
            return
        }
        armBuilding = true
        let paths = Self.armPaths
        // The store computes each set once per process (the second and third Jelly wait for the first, on a plain queue thread) and
        // loads it from the Caches folder on later launches.
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let result = ArmKeyframeStore.shared.keyframes(paths: paths, rest: rest, mat: mat, capsule: cap, index: index, scale: scale)
            Task { @MainActor in
                guard let self else { return }
                for kf in result { self.armKeyframes[kf.name] = kf }
                self.armBuilding = false
            }
        }
    }

    // MARK: scripted hooks (tests, demos, captures)

    /// True while the wave script runs (also during a Call, where `activity` reads .coming).
    var isWaving: Bool { if case .wave = script { return true }; return false }

    /// March on the spot for `seconds` (the "step in place" idle).
    func startStepping(seconds: Float, sim: SoftBody) {
        currentPose(sim); script = .stepInPlace(t: 0, dur: seconds); activity = .steppingInPlace
    }
    /// Turn on the spot to face world heading `yaw` with steps.
    func startTurn(to yaw: Float, sim: SoftBody) {
        currentPose(sim); script = .turn(to: yaw, then: .none); activity = .turning
    }
    /// Test hook: the hop's tuck height and how much of it the sim soles follow.
    func setHopTuck(height: Float, simCap: Float) { gait.tuckHeight = height; gait.simTuckCap = simCap }
    /// One small hop / one tipping roll now.
    func startHopPlay(sim: SoftBody, distance: Float? = nil) { currentPose(sim); startHop(sim, distance: distance) }
    func startRollPlay(sim: SoftBody) { currentPose(sim); startRoll(sim) }
    /// Spin on the spot (play).
    func startSpin(sim: SoftBody) { currentPose(sim); script = .spin(t: 0); activity = .playing }

    // MARK: requests

    func request(_ r: BlobRequest) { pending = r }

    /// Convenience: cancel whatever he is doing right now and serve `r` immediately (used by the care menu).
    func requestNow(_ r: BlobRequest) { pending = r; interruptScript = true }
    var interruptScript = false

    // MARK: rng

    func rand() -> Float {
        rng ^= rng << 13; rng ^= rng >> 7; rng ^= rng << 17
        return Float(rng >> 40) / Float(1 << 24)
    }
    func rand(_ a: Float, _ b: Float) -> Float { a + (b - a) * rand() }

    // MARK: tick

    func tick(sim: SoftBody, skinner: Skinner, dt: Float, touched touchedIn: Bool) {
        guard enabled else { return }
        defer { expressionTick(sim, skinner, dt) }          // the face layer runs on every path out of the tick (it yields to whatever owns the face)
        applyBagFloor(sim, skinner)
        sinceWave += dt; sincePlay += dt; joyAge += dt; hmphAge += dt
        centreDwellTick(dt)
        reactTick(sim, skinner, dt)
        snuggleCool = max(0, snuggleCool - dt)
        awakeMin = max(0, awakeMin - dt); sleepTryCool = max(0, sleepTryCool - dt)
        // a finger on a sleeper: a tap wakes him gently (he rolls back over and stretches, groggy); a long hold is a real pick up (below)
        var touched = touchedIn
        if idleState.kind == .sleep {
            if touched, sleep.stage >= 2, sleep.stage <= 4, sleep.touchT < SleepTuning.tapTime { sleep.touchT += dt; sleepWake(groggy: true); touched = false }
            else if !touched { sleep.touchT = 0 }
        }
        ears.ease(dt: dt)

        if touched {
            if activity != .touched { abortAll(sim, skinner) }
            activity = .touched
            calmT = 0; recoverT = 0
            // hands-off (held, thrown, tumbling): foot beans that are still out must follow the body (they are drawn from world positions, so
            // frozen they would hang in the air where he was picked up); they fold back into the embedded feet. The held dangle (driveExcited,
            // from the touch play) drives them while it runs.
            if !excitedOn && (beanG > 0 || beanHold > 0 || shoesWorn) { driveBeansRigid(sim, skinner, dt) }
            return
        }
        if activity == .touched { activity = .recovering; gaitRecover = false; calmT = 0; recoverT = 0 }
        if activity == .recovering { recover(sim, skinner, dt); return }

        if interruptScript { interruptScript = false; if case .none = script {} else { abortScript(sim, skinner) } }
        if blinkRequested { blinkRequested = false; skinner.blinkNow() }
        if let k = commandedIdle { commandedIdle = nil; startCommanded(k, sim, skinner) }
        if commandedFlip { commandedFlip = false; startCommandedFlip(sim, skinner) }
        if let d = commandedDecor { commandedDecor = nil; startCommandedDecor(d.kind, only: d.only, sim, skinner) }
        if commandedNameHop { commandedNameHop = false; startNameHop(sim, skinner) }
        if commandedGoodnight { commandedGoodnight = false; if !race.active && !sleepLocked { startGoodnight(sim, skinner) } }          // (never during a race)
        if flipTick(sim, skinner, dt) { return }
        idleGate(sim, skinner, dt)
        if idleJacksTick(sim, skinner, dt) { return }
        if flapHopTick(sim, skinner, dt) { return }
        if idleBodyMoveTick(sim, skinner, dt) { return }
        if sleepBodyTick(sim, skinner, dt) { return }
        socialTick(sim, skinner, dt)

        // gait-driven tricks (hop / roll) own the attractor while they run
        switch script {
        case .hopPlay, .rollPlay:
            // keep (most of) the idle tip-back through a hop: upright makes the brows read angry from the camera
            var hopGoal: Float = 0
            if case .hopPlay = script { hopGoal = -hopTipBack * attentionPitch * amplitude }
            pitchBase += max(-1.2 * dt, min(1.2 * dt, hopGoal - pitchBase))
            gait.basePitch = pitchBase
            gait.tick(sim, held: false, reduce: amplitude < 0.7)
            driveBeansRigid(sim, skinner, dt, tuck: gait.tuck)
            if !gait.isBusy { currentPose(sim); gait.basePitch = 0; finishScript(sim, after: false) }
            return
        default: break
        }

        if demo != nil { demoTick(sim) }
        if case .none = script {
            if let r = pending { pending = nil; start(request: r, sim) }
            else if autonomy && social == nil {
                restTimer -= dt
                if restTimer <= 0 { pickAutonomous(sim) }
            }
        }

        poseOn = false
        runScript(sim, skinner, dt)
        drivePose(sim, dt)
        driveLimbs(sim, skinner, dt)
        updateActivity()
    }

    func updateActivity() {
        switch script {
        case .none: activity = .idle
        case .walk: activity = isCome ? .coming : .walking
        case .turn: activity = isCome ? .coming : .turning
        case .look: activity = .lookingAround
        case .stepInPlace: activity = .steppingInPlace
        case .wave: activity = isCome ? .coming : .waving
        case .spin, .hopPlay, .rollPlay, .flipPlay: activity = .playing
        case .eat(_, _, _, let drink): activity = drink ? .drinking : .eating
        case .dine: activity = dine.mode == .sip ? .drinking : .eating
        case .idle: activity = idleActivity
        case .race: activity = .walking
        }
    }

    // MARK: choosing

    func currentPose(_ sim: SoftBody) {
        if poseW <= 0 {
            let p = sim.bodyPose(iterations: 8)
            px = p.centroid.x; pz = p.centroid.z; yaw = p.yaw
            roll = 0; pitch = 0; squash = 1; lift = 0
            feetInit = false; feet.reset(); stepLive = false; walkFinal = false
        }
    }

    func faceCameraYaw() -> Float {
        #if DEBUG
        // capture aid: -BlobFaceYawOffset <rad> turns him away from the camera by that angle (back 3/4 views of the wave)
        let off = Float(UserDefaults.standard.double(forKey: "BlobFaceYawOffset"))
        #else
        let off: Float = 0
        #endif
        return atan2f(cameraPosXZ.x - px, cameraPosXZ.y - pz) + off
    }

    func start(request r: BlobRequest, _ sim: SoftBody) {
        currentPose(sim)
        job = r
        scriptT = 0; stuckT = 0; bestDist = .infinity; route = []; steerStall = 0
        switch r {
        case .wave:
            script = .turn(to: faceCameraYaw(), then: .wave); activity = .turning
        case .goTo(let p):
            script = .walk(target: fixed(p), then: .none); activity = .walking
        case .eat(let b):
            script = .walk(target: fixed(bowlSpot(b)), then: .eat(b, false)); activity = .walking
        case .drink(let b):
            script = .walk(target: fixed(bowlSpot(b)), then: .eat(b, true)); activity = .walking
        case .come(let p):
            script = .walk(target: fixed(p), then: .faceCamera); activity = .coming
        case .dine(let place, let bites):
            dine = DineState(place: place, bitesLeft: bites, mode: dineHooks?.fork == true ? .fork : .finger)
            script = .walk(target: fixed(place.stand), then: .dineTurn(place)); activity = .walking
        case .sip(let place, let gulps):
            dine = DineState(place: place, bitesLeft: gulps, mode: .sip)
            script = .walk(target: fixed(place.stand), then: .dineTurn(place)); activity = .walking
        }
    }

    func fixed(_ p: SIMD2<Float>) -> SIMD2<Float> {
        let r = resolve(SIMD3(p.x, 0, p.y), footprint)
        return SIMD2(r.x, r.z)
    }

    /// Where he stands to eat: right behind the bowl (away from the camera), facing the player over it, so the bowl's
    /// back rim is just in front of his feet and his mouth is above it.
    func bowlSpot(_ bowl: SIMD2<Float>) -> SIMD2<Float> {
        return bowl + SIMD2(0, -0.66)
    }

    func pickAutonomous(_ sim: SoftBody) {
        currentPose(sim)
        if reserved && !commanded { waitPose(sim); return }
        if socialMaybeStart(sim) { return }
        if idleMaybeStart(sim) { return }
        var w: [(Int, Float)] = [(0, 8), (1, 1.0), (2, 0.6)]          // (was 5 / 2 / 1.5: more legs, fewer stands; 2026-10-21 "they need to move a lot more")
        if sinceWave > 18 { w.append((3, 2)) }
        if sincePlay > 10, !(anticsEnabled && fastOthers() >= 2) { w.append((4, 2)) }
        idleShapeWander(&w)
        w.removeAll { $0.0 == lastPick && $0.0 != 0 }
        let total = w.reduce(0) { $0 + $1.1 }
        var r = rand() * total
        var choice = w[0].0
        for (k, wt) in w { if r < wt { choice = k; break }; r -= wt }
        lastPick = choice
        scriptT = 0; stuckT = 0; bestDist = .infinity; route = []; steerStall = 0; job = nil
        switch choice {
        case 0:
            let here = SIMD2(px, pz)
            var target = here
            var fallback: SIMD2<Float>?
            var roamed = false
            if let rf = roamProvider?() {          // the whole visible floor: zone picks first (50 %, the edges and corners), else an area sample; spread from the others
                if rand() < 0.5, let g = pickRoamGoal(rf, from: here, zone: Int(rand() * Float(GameCamera.RoamFloor.zoneCount)) % GameCamera.RoamFloor.zoneCount) { target = g; roamed = true }
                else if let g = pickRoamGoal(rf, from: here, zone: nil) { target = g; roamed = true }
            }
            for _ in 0..<(roamed ? 0 : 40) {
                var cand: SIMD2<Float>
                if let r = wanderRectWide ?? wanderRect { cand = SIMD2(rand(r.min.x, r.max.x), rand(r.min.y, r.max.y)) }
                else {
                    let a = rand() * 2 * .pi, rr = wanderRadius * rand().squareRoot()
                    cand = wanderCenter + SIMD2(sinf(a), cosf(a)) * rr
                }
                let raw = cand
                let rv = resolve(SIMD3(cand.x, 0, cand.y), footprint); cand = SIMD2(rv.x, rv.z)
                let d = simd_length(cand - here)
                guard d > 0.8 && d < idleLegMax(maxWanderLeg) && peerFree(cand) && reachable(here, cand) else { continue }
                // a goal the floor rules had to drag in (off the frame / onto a prop) piles up at the edges: take real floor first, the dragged one only as a fallback
                if wanderRectWide != nil || wanderRect != nil, simd_length(cand - raw) > 0.15 { fallback = fallback ?? cand; continue }
                target = cand; fallback = nil; break
            }
            if simd_length(target - here) < 0.3, let f = fallback { target = f }
            if simd_length(target - here) < 0.3 { restTimer = 0.6; return }
            script = .walk(target: target, then: .none); activity = .walking
        case 1: script = .look(index: 0, t: 0, base: yaw)
        case 2: script = .stepInPlace(t: 0, dur: rand(1.8, 3.0)); activity = .steppingInPlace
        case 3:
            sinceWave = 0
            script = .turn(to: faceCameraYaw(), then: .wave); activity = .turning
        default:
            sincePlay = 0
            let k = rand()
            if k < 0.4 { startHop(sim) } else if k < 0.7 { script = .spin(t: 0); activity = .playing } else { startRoll(sim) }
        }
    }

    /// The wait pose of a reserved Jelly (meal coming): never a leg. Looks at the tray or a neighbour, steps in place, or a small bounce and a blink.
    func waitPose(_ sim: SoftBody) {
        scriptT = 0; stuckT = 0; bestDist = .infinity; route = []; steerStall = 0; job = nil
        let r = rand()
        var aim: Float?
        if r < 0.35 {
            if let o = socialOthers().filter({ $0 !== self }).min(by: { simd_distance($0.position, position) < simd_distance($1.position, position) }) { aim = yawTo(o.position) }
        } else if r < 0.6, let f = waitFocus { aim = yawTo(f) }
        if let aim, abs(wrapAngle(aim - yaw)) > 0.12 {
            script = .look(index: 2, t: 0, base: aim); activity = .lookingAround
        } else if rand() < 0.6 {
            script = .stepInPlace(t: 0, dur: rand(1.2, 2.2)); activity = .steppingInPlace
        } else {
            blinkRequested = true; jellyKick = max(jellyKick, 0.9)          // a little bounce and a blink, then rest again
            restTimer = rand(0.8, 1.4)
        }
    }

    /// A wander goal on the roaming polygon: `zone` (RoamFloor.sampleZone: the edges and corners, legs of at least 2.5 u) or a uniform sample by area (legs of
    /// at least 1.2 u). Of up to six valid candidates the best wins: far from the other Jellies (and from where they are heading), from the cells he picked
    /// before, a long leg, and away from the rug centre the longer he has just spent there (`centreDwell`; 2026-10-21 "they stay in the centre too much").
    func pickRoamGoal(_ rf: GameCamera.RoamFloor, from here: SIMD2<Float>, zone: Int?) -> SIMD2<Float>? {
        let maxL = idleLegMax(maxWanderLeg)
        let lo: Float = zone != nil ? 2.5 : 1.5
        guard maxL > lo else { return nil }
        let others = socialOthers().filter { $0 !== self }
        let centreBias = min(1, centreDwell / IdleTuning.centreDwellFull)
        var best: (SIMD2<Float>, Float)?
        var valid = 0
        for _ in 0..<48 {
            let raw = zone.map { rf.sampleZone($0, rand(), rand(), rand()) } ?? rf.sampleArea(rand(), rand(), rand())
            let rv = resolve(SIMD3(raw.x, 0, raw.y), footprint); let cand = SIMD2(rv.x, rv.z)
            let d = simd_length(cand - here)
            guard simd_length(cand - raw) < 0.15, d > lo, d < maxL, peerFree(cand), reachable(here, cand) else { continue }
            var nearest: Float = 5
            for o in others {
                nearest = min(nearest, simd_distance(o.position, cand))
                if case .walk(let t, _) = o.script { nearest = min(nearest, simd_distance(t, cand)) }
            }
            let central = max(0, 1 - simd_distance(cand, RoomLayout.rugCentre) / (IdleTuning.centreRadius * 1.6))
            let score = 0.6 * nearest + 1.5 / Float(1 + roamVisits[roamKey(cand), default: 0]) + 0.3 * rand() + 0.3 * min(d, 4.0) - 2.0 * centreBias * central
            if best == nil || score > best!.1 { best = (cand, score) }
            valid += 1
            if valid >= 6 { break }
        }
        if let b = best { roamVisits[roamKey(b.0), default: 0] += 1; return b.0 }
        return nil
    }

    /// Every tick: how long he has lately been near the rug centre (grows there, fades twice as slowly away from it; `pickRoamGoal` reads it).
    func centreDwellTick(_ dt: Float) {
        if simd_distance(SIMD2(px, pz), RoomLayout.rugCentre) < IdleTuning.centreRadius { centreDwell = min(IdleTuning.centreDwellFull * 2, centreDwell + dt) }
        else { centreDwell = max(0, centreDwell - dt * 0.5) }
    }
    private func roamKey(_ p: SIMD2<Float>) -> Int { (Int(floorf(p.x)) + 50) * 1000 + Int(floorf(p.y)) + 50 }

    func startHop(_ sim: SoftBody, distance: Float? = nil) {
        AudioHub.shared.play(.jump, jelly: steerID, x: px, volume: 0.8)
        // the stepping feet were held by stiff world targets: release them (and the rigid render feet) before the hop owns the body, or the
        // pinned soles drag it around (that was the hop "face-plant": the old resting spots stayed pinned while he squashed and travelled)
        sim.targets = []; beanHold = 0; feetInit = false; feet.reset(); stepLive = false
        gait.wander = false
        gait.facingYaw = yaw
        gait.home = SIMD2(px, pz)
        // hops go along the way he is facing (no turning on the spot mid-hop, he stays upright and keeps facing the same way)
        let fwd: Float = distance ?? (rand() < 0.5 ? 0.45 : 0)
        var t = SIMD2(px, pz) + SIMD2(sinf(yaw), cosf(yaw)) * (fwd > 0 ? fwd : 0.0001)
        let rv = resolve(SIMD3(t.x, 0, t.y), footprint); t = SIMD2(rv.x, rv.z)
        poseW = 0
        gait.hop(sim, to: t, reduceMotion: amplitude < 0.7)
        script = .hopPlay; activity = .playing
    }

    func startRoll(_ sim: SoftBody) {
        gait.wander = false
        gait.facingYaw = yaw
        gait.home = SIMD2(px, pz)
        let right = SIMD2<Float>(cosf(yaw), -sinf(yaw))
        let dir = rand() < 0.5 ? right : -right
        let target = SIMD2(px, pz) + dir * gait.rollTravel
        let rv = resolve(SIMD3(target.x, 0, target.y), footprint)
        if simd_length(SIMD2(rv.x, rv.z) - target) > 0.05 { startHop(sim); return }
        poseW = 0
        gait.roll(sim, toward: dir, reduceMotion: amplitude < 0.7)
        script = .rollPlay; activity = .playing
    }

    // MARK: scripts

    func finishScript(_ sim: SoftBody, after served: Bool) {
        script = .none
        restTimer = rand(IdleTuning.restAfterLeg.lowerBound, IdleTuning.restAfterLeg.upperBound) * idleLively          // (was 1.5...4.0: 2026-10-21 "they need to move a lot more")
        if let j = job { job = nil; onFinished?(j) }
        _ = served
    }

    func abortScript(_ sim: SoftBody, _ skinner: Skinner) {
        abortAll(sim, skinner)
        script = .none
        job = nil
    }

    func abortAll(_ sim: SoftBody, _ skinner: Skinner) {
        let wasLying = isLying
        if poseW > 0.2 { for i in sim.v.indices { sim.v[i] *= 0.25 } }       // dropped mid-stride: no carried-over momentum (he stays where he was stopped)
        mouthOpen = 0
        route = []
        clearSkinOverride()
        sim.targets = []
        sim.restoreStiffness()
        gait.cancel(sim)
        sim.attractor.strength = 0
        skinner.setEyeOpenness(1)
        skinner.browCounterOn = false
        dineAbort()
        socialAbort(skinner)
        idleReset(skinner)
        armActive = false; armBlend = 0; armPathName = ArmPath.wave.name
        armWalkWant = 0
        feet.reset(); feetInit = false; stepLive = false; walkFinal = false; pivotSide = nil; nubOverride = false; beanHold = 0; nubEnv = 0; nubTarget = 0; nubPhi = [0, 0]
        poseW = 0; poseOn = false
        script = .none
        job = nil
        if wasLying { activity = .recovering; gaitRecover = false; calmT = 0; recoverT = 0 }       // dropped while he lies on his back: the recover path rolls him up onto his feet
    }

    // MARK: gait helpers

    /// Seed the planted feet from the current root / heading (his feet stand square under the root).
    func ensureFeet(_ sim: SoftBody) {
        if !geom.valid { geom = FootGeom(sim: sim) }
        guard geom.valid, !feetInit else { return }
        for k in 0..<2 { feet.pos[k] = SIMD2(px, pz) + rotXZ(geom.off[k], yaw); feet.yaw[k] = yaw }
        feet.reset(); stepLive = false
        feetInit = true
    }

    /// Begin a step with the foot `nextSwing`. The root and heading advance over the step; the swing foot lands square under the new root
    /// (plus `reach` ahead of it). `inPlace` re-plants the foot where it was (marching on the spot).
    func startStep(rootD: SIMD2<Float> = .zero, dyaw: Float = 0, reach: SIMD2<Float> = .zero, peak: Float? = nil,
                           rate: Float? = nil, swingFrac: Float = 0.85, inPlace: Bool = false, outScale: Float = 1) {
        let s = nextSwing
        stepRoot0 = SIMD2(px, pz); stepRootD = rootD
        stepYaw0 = yaw; stepYawD = dyaw
        let landYaw = yaw + dyaw
        let target = inPlace ? feet.pos[s] : stepRoot0 + rootD + rotXZ(geom.off[s], landYaw) + reach
        feet.begin(side: s, to: target, toYaw: inPlace ? feet.yaw[s] : landYaw, peak: peak ?? stepLift * amplitude,
                   rate: rate ?? stepRate * runRateMul, swingFrac: swingFrac, out: stepOut * amplitude * outScale, tilt: stepTilt * amplitude, fwd: stepFwd * amplitude)
        nextSwing = 1 - s
        stepLive = true
        AudioHub.shared.footstep(jelly: steerID, x: px, running: runW > 0.5)
    }

    /// Advance the feet and the root / heading interpolation of the running step (called first thing each tick).
    func advanceGait(_ dt: Float) {
        guard feetInit else { return }
        feet.advance(dt)
        if stepLive {
            let u = feet.stepU
            px = stepRoot0.x + stepRootD.x * u; pz = stepRoot0.y + stepRootD.y * u
            yaw = wrapAngle(stepYaw0 + stepYawD * u)
            if !feet.active { stepLive = false }
        }
    }

    /// Turn on the spot toward `goal` with steps (one swing per step, up to turnRate * stepTime of heading each). Returns true while turning.
    func turnSteps(goal: Float, tol: Float) -> Bool {
        if feet.active { return true }
        let err = wrapAngle(goal - yaw)
        guard abs(err) > tol else { return false }
        let m = turnRate * amplitude.clamped(0.5, 1) * feet.stepTime
        startStep(dyaw: max(-m, min(m, err)), peak: turnLift * amplitude)
        return true
    }

    /// While a step is running: weight shift toward the stance foot (the pose pivots on the stance foot's nominal spot), bob in phase with
    /// the steps (stretch + a little lift while the foot is in the air, settling at contact), forward / back rock, arm nubs counter-swinging.
    func gaitPose(sway amp: Float, bob: Float, rock: Float = 1) {
        guard feet.active else { return }
        let sign: Float = feet.side == 1 ? 1 : -1       // +x foot swinging -> top tips toward the stance (-x) foot
        let a = amplitude
        roll = sign * amp * swayScale * a * sinf(.pi * feet.swingU)
        let w = sinf(.pi * feet.stepU)
        squash = 1 + bob * bobScale * a * w
        lift = bobLift * a * w * (bob / 0.12)
        pitch += rockPitch * a * rock * cosf(2 * .pi * feet.stepU)     // forward at contact, back at mid swing
        pitch += Self.runLean * runW                                  // the run's forward lean (0 = the locked walk)
        pivotSide = 1 - feet.side; pivotNominal = true
        nubTarget = a
    }

    // MARK: steering around obstacles (the tray, other Blobs)

    /// Other Blobs this one must not walk through (id, floor position). Empty in the game (one Blob); tests / previews wire several brains together.
    var peers: () -> [(id: Int, pos: SIMD2<Float>)] = { [] }
    /// Yield rule: a Blob steers around every peer with a HIGHER id (lower ids give way); higher ids walk straight on.
    var steerID = 0
    /// Centre distance two Blobs keep.
    var peerGap: Float = 0.9
    /// Extra clearance beyond the footprint the route keeps from the tray / walls.
    var steerMargin: Float = 0.04
    var route: [SIMD2<Float>] = []              // intermediate waypoints (around an obstacle) before the real target
    var stallRoot = SIMD2<Float>(0, 0)
    var stallYaw: Float = 0
    var steerStall: Float = 0                   // seconds the walker has made no progress (tests / diagnostics)
    var steerStallSeconds: Float { steerStall }
    var steerRoute: [SIMD2<Float>] { route }

    /// How deep (u) a floor point is inside something he must not stand in, with `margin` extra clearance (0 = free).
    func intrusion(_ p: SIMD2<Float>, margin: Float) -> Float {
        let r = resolve(SIMD3(p.x, 0, p.y), footprint + margin)
        var d = simd_length(SIMD2(r.x, r.z) - p)
        for o in peers() where o.id > steerID { d = max(d, socialGap(at: o.pos) + margin * 0.5 - simd_distance(o.pos, p)) }
        return max(d, 0)
    }

    /// The straight leg a -> b keeps its clearance (it may start inside the margin as long as it only leaves it, and end in it).
    func legClear(_ a: SIMD2<Float>, _ b: SIMD2<Float>, margin: Float) -> Bool {
        let d = b - a, L = simd_length(d)
        if L < 1e-3 { return true }
        let n = max(2, Int(L / 0.07)), a0 = intrusion(a, margin: margin)
        for i in 1...n {
            let t = Float(i) / Float(n), p = a + d * t
            if simd_length(b - p) < 0.3 { break }              // the end of the leg may sit in the margin (a stand next to the tray)
            if intrusion(p, margin: margin) > max(0.012, a0 + 0.004) { return false }
        }
        return true
    }

    /// Waypoints from `a` to `b` around whatever blocks the straight line (nil if no route within two corners).
    func planRoute(_ a: SIMD2<Float>, _ b: SIMD2<Float>, depth: Int) -> [SIMD2<Float>]? {
        let m = steerMargin
        if legClear(a, b, margin: m) { return [] }
        guard depth > 0 else { return nil }
        let d = b - a, L = simd_length(d)
        let dir = d / max(L, 1e-4), perp = SIMD2(-dir.y, dir.x)
        // first blocked point along the line
        var pb = a + d * 0.5
        let n = max(2, Int(L / 0.07)), a0 = intrusion(a, margin: m)
        for i in 1...n { let p = a + d * (Float(i) / Float(n)); if intrusion(p, margin: m) > max(0.012, a0 + 0.004) { pb = p; break } }
        var best: (len: Float, pts: [SIMD2<Float>])?
        for side in [Float(1), -1] {
            // the nearest point sideways of the block that is free (a corner just clear of the obstacle), then a few wider ones
            var off0: Float = 0.02
            while off0 < 3.0 && intrusion(pb + perp * (off0 * side), margin: m) > 0.004 { off0 += 0.02 }
            guard off0 < 3.0 else { continue }
            // (a fine set: beside the tray the floor he can use is a ~0.25 wide lane, and a coarse set can miss it from one start point while finding it from the next)
            for extra: Float in [0.015, 0.03, 0.05, 0.075, 0.1, 0.12, 0.15, 0.2, 0.25, 0.35, 0.5] {
                let c = pb + perp * ((off0 + extra) * side)
                guard intrusion(c, margin: m) < 0.01, legClear(a, c, margin: m) else { continue }
                guard let rest = planRoute(c, b, depth: depth - 1) else { continue }
                var len = simd_distance(a, c), prev = c
                for q in rest { len += simd_distance(prev, q); prev = q }
                len += simd_distance(prev, b)
                if best == nil || len < best!.len { best = (len, [c] + rest) }
            }
        }
        return best?.pts
    }

    /// Where to walk next: the target itself, or the next waypoint of a route around the obstacle in the way (kept until reached: no jitter).
    func steerTarget(to target: SIMD2<Float>) -> SIMD2<Float>? {
        let root = SIMD2(px, pz)
        if let w = route.first {
            if simd_distance(root, w) < 0.4 { route.removeFirst() }
            else if legClear(root, w, margin: steerMargin) { return w }
            else { route = [] }
        }
        if let w = route.first { return w }
        if legClear(root, target, margin: steerMargin) { return target }
        if let r = planRoute(root, target, depth: 2) { route = r; return r.first ?? target }
        // no way around: if a Blob with a higher id is what is in the way, give way for a moment (the other one walks on), then carry on regardless
        // (a Blob that stands still in the way - the game marks those with a huge id - is waited for longer: it is asked to step aside)
        let standing = peers().contains { $0.id >= Int.max / 4 }
        // Autonomous legs (a wander / run / social walk: no job, no voice command) do not wait for a Jelly that blocks them: after a beat they give the leg up
        // and pick another (`steerGiveUp`, read by the walk). A requested walk (come, the meal) keeps the long patience: the blocker is asked to step aside.
        let requested = job != nil || commanded || pending != nil
        let patience: Float = requested ? (standing ? 6 : 0.7) : (standing ? 1.0 : 0.6)
        if steerWait < patience, peerOnLeg(root, target) { return nil }
        if !requested, peerOnLeg(root, target) { steerGiveUp = true; return nil }
        return target
    }

    var steerWait: Float = 0
    /// An autonomous walk found its way blocked for good (see `steerTarget`): the walk ends and a new goal is picked.
    var steerGiveUp = false
    /// Seconds an autonomous walk has made no root progress (turning on the spot included, up to a half turn): the stuck detector.
    var walkStallT: Float = 0
    var walkStallRoot = SIMD2<Float>(0, 0)
    /// How often the leg-level give-ups fired (tests / the soak report).
    var stuckRepicks = 0
    /// A wander goal is no closer than `peerGap` to any other Blob (always true without peers: a lone Blob picks exactly as before).
    func peerFree(_ p: SIMD2<Float>) -> Bool {
        let others = peers()
        if others.isEmpty { return true }
        return !others.contains { simd_distance($0.pos, p) < peerGap }
    }
    /// A goal he can really get to: the straight leg is clear, or a route of at most two corners goes round whatever stands in it (a goal behind a
    /// standing Jelly in a narrow strip of floor is not a goal: he would wait there and give up).
    func reachable(_ a: SIMD2<Float>, _ b: SIMD2<Float>) -> Bool {
        if peers().isEmpty { return true }
        return legClear(a, b, margin: steerMargin) || planRoute(a, b, depth: 2) != nil
    }
    /// A Blob with a higher id stands within the gap of the straight leg a -> b.
    func peerOnLeg(_ a: SIMD2<Float>, _ b: SIMD2<Float>) -> Bool {
        let others = peers().filter { $0.id > steerID }
        if others.isEmpty { return false }
        let d = b - a, n = max(2, Int(simd_length(d) / 0.1))
        for i in 0...n { let p = a + d * (Float(i) / Float(n)); if others.contains(where: { simd_distance($0.pos, p) < socialGap(at: $0.pos) }) { return true } }
        return false
    }

    /// Plan the next walking step toward `target`. Returns 0 = keep going, 1 = arrived, 2 = stuck. `intermediate`: a waypoint on a route, so no final stop.
    func planWalkStep(to target: SIMD2<Float>, intermediate: Bool = false) -> Int {
        let root = SIMD2(px, pz)
        let d = target - root
        let D = simd_length(d)
        let hd = D > 1e-4 ? atan2f(d.x, d.y) : yaw
        let err = wrapAngle(hd - yaw)
        let m = turnRate * amplitude.clamped(0.5, 1) * feet.stepTime
        let u = D > 1e-4 ? d / D : SIMD2<Float>(sinf(yaw), cosf(yaw))
        let stance = 1 - nextSwing
        let s = simd_dot(feet.pos[stance] - (root + rotXZ(geom.off[stance], yaw)), u)    // how far the stance foot leads
        if D < 0.06 && abs(s) < 0.08 && !intermediate { return 1 }
        if scriptT > 14 + D / 0.25 { return 1 }
        if stuckT > 1.5 { return 2 }
        if abs(err) > 0.5 {                                // not facing the target yet: turn on the spot first
            startStep(dyaw: max(-m, min(m, err)), peak: turnLift * amplitude)
            return 0
        }
        let L = stride * runStrideMul * amplitude.clamped(0.6, 1)
        var a: Float, r: Float
        if !intermediate && (abs(D - s) < 0.06 || D < s) { a = max(0, s); r = 0; walkFinal = true }    // final step: root over the stance foot, feet land square
        else if D > s + 1.1 * L || intermediate { r = 0.5 * L; a = s + r }                        // regular step: lands half a step ahead
        else { r = min(0.6 * L, max(0.06, D / 3)); a = max(0, D - r) }            // two-step finish, the second one is final
        var rootD = u * a
        let cand = root + rootD
        let rv = resolve(SIMD3(cand.x, 0, cand.y), footprint)
        let got = SIMD2(rv.x, rv.z) - root
        if a > 0.01 { stuckT = simd_length(got) < 0.3 * a ? stuckT + feet.stepTime : max(0, stuckT - feet.stepTime) }
        rootD = got
        startStep(rootD: rootD, dyaw: max(-m, min(m, err)), reach: u * r, peak: stepLift * amplitude)
        return 0
    }

    func runScript(_ sim: SoftBody, _ skinner: Skinner, _ dt: Float) {
        scriptT += dt
        idleUpdateRun(dt)
        switch job { case .some(.dine), .some(.sip): skinner.browCounterOn = true; default: break }        // the brows are ready before he leans
        mouthOpen = 0
        roll = 0; pitch = 0; squash = 1; lift = 0; twist = 0
        armWalkWant = 0
        pivotSide = nil; pivotNominal = false; nubTarget = 0
        feetDrive = true
        advanceGait(dt)
        var goal: Float = -attentionPitch * amplitude
        switch script {
        case .walk: goal = facePlayerWhenIdle ? -1.0 * attentionPitch * amplitude : 0      // keep the tip-back toward the camera
        case .spin, .eat: goal = 0
        case .idle: if idleState.kind == .stumble { goal = 0 }       // the lurch pitches him forward from upright, not from the tip-back toward the camera
        default: break
        }
        let dp = goal - pitchBase
        pitchBase += max(-1.2 * dt, min(1.2 * dt, dp))
        switch script {
        case .hopPlay, .rollPlay, .flipPlay:
            break

        case .none:
            if facePlayerWhenIdle || socialBook.hold {
                poseOn = true; ensureFeet(sim)
                _ = turnSteps(goal: socialBook.hold ? (socialBook.faceYaw ?? yaw) : faceCameraYaw(), tol: socialBook.hold ? 0.06 : 0.12)
                gaitPose(sway: 0.6 * waddleRoll, bob: 0.03, rock: 0.5)
            }

        case .walk(let target, let then):
            poseOn = true; ensureFeet(sim)
            if simd_distance(SIMD2(px, pz), stallRoot) > 0.04 || abs(wrapAngle(yaw - stallYaw)) > 0.05 { stallRoot = SIMD2(px, pz); stallYaw = yaw; steerStall = 0 } else { steerStall += dt }
            if scriptT <= dt * 1.5 { walkStallRoot = SIMD2(px, pz); walkStallT = 0; steerWait = 0; steerGiveUp = false; flourishLegStart(target: target) }       // a new leg starts clean (and rolls its flourish)
            // stuck detector: an autonomous walk whose root has not moved 0.12 u in 3 s (a half turn on the spot takes ~1.7 s) is dropped and re-picked
            if simd_distance(SIMD2(px, pz), walkStallRoot) > 0.12 { walkStallRoot = SIMD2(px, pz); walkStallT = 0 } else { walkStallT += dt }
            if walkStallT > 3.0, job == nil, !commanded, pending == nil {
                walkStallT = 0; stuckRepicks += 1
                step(after: .none, sim, giveUp: true); restTimer = 0.25
                return
            }
            if !feet.active {
                if walkFinal { walkFinal = false; step(after: then, sim); return }
                if flourishMaybe(sim, skinner, target: target) { return }          // (between two steps: a skip, a hop, a spin, a look; the walk resumes after)
                guard let eff = steerTarget(to: target) else {
                    steerWait += dt; gaitPose(sway: waddleRoll, bob: 0.12); armWalkWant = 1
                    if steerGiveUp { steerGiveUp = false; steerWait = 0; stuckRepicks += 1; step(after: .none, sim, giveUp: true); restTimer = 0.25 }
                    return
                }
                steerWait = max(0, steerWait - dt)
                let inter = eff != target
                switch planWalkStep(to: eff, intermediate: inter) {
                case 1: if inter { route.removeFirst() } else { step(after: then, sim); return }
                case 2: step(after: .none, sim, giveUp: true); return
                default: break
                }
            }
            gaitPose(sway: waddleRoll, bob: 0.12)
            armWalkWant = 1

        case .turn(let to, let then):
            poseOn = true; ensureFeet(sim)
            // squaring up to the tray is exact: the last turn step is sized to the remaining angle, so he never settles up to 0.05 rad off (the lean's brow
            // slant and the arm reach to the tray both read that residual); every other turn keeps the loose tolerance
            var tol: Float = 0.05
            if case .dineGo = then { tol = 0.004 }
            let turning = turnSteps(goal: to, tol: tol)
            gaitPose(sway: 0.6 * waddleRoll, bob: 0.03, rock: 0.5)
            armWalkWant = turning ? 0.5 : 0
            if !turning && !feet.active { step(after: then, sim) }

        case .look(let i, let t, let base):
            poseOn = true; ensureFeet(sim)
            let seq: [Float] = [0.7, -0.7, 0.0]
            let turning = turnSteps(goal: base + seq[i], tol: 0.06)
            gaitPose(sway: 0.6 * waddleRoll, bob: 0.03, rock: 0.5)
            if !turning && !feet.active {
                let nt = t + dt
                if nt > (i == 2 ? 0.3 : 0.7) {
                    if i == 2 { finishScript(sim, after: false) } else { script = .look(index: i + 1, t: 0, base: base) }
                } else { script = .look(index: i, t: nt, base: base) }
            } else { script = .look(index: i, t: 0, base: base) }

        case .stepInPlace(let t, let dur):
            poseOn = true; ensureFeet(sim)
            if t < dur && !feet.active {
                startStep(peak: (t < 0.01 ? 0.05 : 0.04) * amplitude, rate: 2.0, swingFrac: 0.8, inPlace: true)
            }
            gaitPose(sway: 0.04, bob: 0.02, rock: 0.3)
            script = .stepInPlace(t: t + dt, dur: dur)
            if t >= dur && !feet.active { finishScript(sim, after: false) }

        case .spin(let t):
            poseOn = true
            feetDrive = false; feetInit = false; feet.reset(); stepLive = false
            let rate: Float = 5.5
            yaw = wrapAngle(yaw + rate * dt)
            let u = min(1, t / (2 * .pi / rate))
            squash = 1 - 0.05 * sinf(.pi * u) ; lift = 0
            script = .spin(t: t + dt)
            if t > 2 * .pi / rate + 0.1 { finishScript(sim, after: false) }

        case .wave(let t, let side, let then):
            poseOn = true
            if armBuilding { ensureFeet(sim); return }          // keyframes still being precomputed: stand and wait
            ensureFeet(sim)
            if armCapsuleOut || armLift != 0 { armLift = 0; armLiftV = 0; armHold = 0; return }       // swap the walking arm capsules out first (0.12 s)
            if !armActive { armSide = side; beginWave(sim, side: side) }
            script = .wave(t: t + dt, side: side, then: then)
            // lean away from the arm, pivoting on the far foot (it stays planted); the arm-side foot lifts in `driveLimbs`
            pivotSide = side > 0 ? 0 : 1
            roll = Float(side) * waveRoll * amplitude * WaveScript.lean(at: t)
            skinner.setEyeOpenness(WaveScript.eyesShut(at: t) ? 0 : 1)
            if t >= WaveScript.duration {
                skinner.setEyeOpenness(1)
                endWave(sim)
                pivotSide = nil
                step(after: then, sim)
            }

        case .dine:
            runDine(sim, skinner, dt)

        case .idle:
            runIdle(sim, skinner, dt)

        case .race:
            raceRun(sim, dt)

        case .eat(let t, let bowl, let dur, let drink):
            poseOn = true; ensureFeet(sim)
            let down = smooth01(t / 0.5) * (1 - smooth01((t - (dur - 0.5)) / 0.5))
            pitch = 0.2 * down * amplitude
            let rhythm = sinf(2 * .pi * (drink ? 2.2 : 2.8) * t)
            squash = 1 - 0.05 * down * (0.5 + 0.5 * rhythm)
            // eyes stay open, with a quick happy squint now and then
            let pulse = max(0, sinf(2 * .pi * t / 1.25 - 1.2)) > 0.93 ? Float(1) : 0
            skinner.setEyeOpenness(1 - 0.7 * down * pulse)
            // chomp (eat: 2.8 Hz, 0.25...1) or quick lapping (drink: 4 Hz, 0.2...0.6), eased in and out with the lean
            let m = 0.5 + 0.5 * sinf(2 * .pi * (drink ? 4.0 : 2.8) * t)
            mouthOpen = down * (drink ? 0.2 + 0.4 * m : 0.25 + 0.75 * m)
            script = .eat(t: t + dt, bowl: bowl, dur: dur, drink: drink)
            _ = bowl
            if t >= dur { skinner.setEyeOpenness(1); mouthOpen = 0; finishScript(sim, after: true) }
        }
    }

    func step(after: After, _ sim: SoftBody, giveUp: Bool = false) {
        scriptT = 0
        if giveUp { job = nil; script = .none; restTimer = 1; return }
        switch after {
        case .none: finishScript(sim, after: true)
        case .faceCamera:
            if isCome { script = .turn(to: faceCameraYaw(), then: .wave) }
            else { script = .turn(to: faceCameraYaw(), then: .none) }
        case .wave:
            armSide = rand() < 0.5 ? -1 : 1
            if UserDefaults.standard.object(forKey: "BlobWaveSide") != nil { armSide = UserDefaults.standard.integer(forKey: "BlobWaveSide") == 0 ? -1 : 1 }   // capture aid: -BlobWaveSide 0 = left (-1), 1 = right (+1)
            script = .wave(t: 0, side: armSide, then: .none)
        case .face(let p):
            script = .turn(to: atan2f(p.x - px, p.y - pz), then: .none)
        case .eat(let bowl, let drink):
            let face = atan2f(bowl.x - px, bowl.y - pz)
            script = .turn(to: face, then: .doEat(bowl, drink))
        case .doEat(let bowl, let drink):
            script = .eat(t: 0, bowl: bowl, dur: drink ? 3.2 : 3.0, drink: drink)
        case .dineTurn(let place):
            script = .turn(to: place.yaw, then: .dineGo)
        case .dineGo:
            dine.phase = .lean; dine.t = 0; dine.k = 0; dine.armS = 0; dine.entered = false
            script = .dine
        }
    }
    var isCome: Bool { if case .some(.come) = job { return true }; return false }
    /// The script is still the walk itself (not the turn / wave / stand that follows it).
    var isWalkScript: Bool { if case .walk = script { return true }; return false }

    // MARK: pose

    func drivePose(_ sim: SoftBody, _ dt: Float) {
        if poseOn { poseW = min(1, poseW + dt / 0.25) } else { poseW = max(0, poseW - dt / 0.3) }
        guard poseW > 0 else { if sim.attractor.strength > 0 && !gait.isBusy { sim.attractor.strength = 0 }; return }
        // pitch outermost, roll innermost: rolling no longer turns the face (pitch * roll coupling was -3.9 deg in the game)
        let q = yawQuat(yaw + twist) * simd_quatf(angle: pitch + pitchBase + touchPitch + socialBook.pitch + ears.pitch, axis: SIMD3(1, 0, 0)) * simd_quatf(angle: roll + touchRoll + socialBook.roll + expr.roll + ears.roll, axis: SIMD3(0, 0, 1))
        sim.attractor.rotation = q
        let sq = squash * touchSquash * socialBook.squash * ears.squash
        sim.attractor.squash = sq
        if geom.valid {
            // pivot on his feet: the middle of both soles (or one foot, for the wave's lean) stays on the floor at its world spot
            var m: SIMD3<Float>, w: SIMD2<Float>
            if let ps = pivotSide, feetInit {
                m = geom.contact[ps]; w = pivotNominal ? SIMD2(px, pz) + rotXZ(geom.off[ps], yaw) : feet.pos[ps]
                if !pivotNominal {
                    // the wave's lean pivots on the OUTER edge of the far foot's sole (the edge he leans onto), so a 20+ deg lean never pushes the
                    // lower sole corner into the floor and collapses the slab under it
                    let dx: Float = (ps == 0 ? -1 : 1) * pivotEdge
                    m.x += dx; w += rotXZ(SIMD2(dx, 0), yaw)
                }
            }
            else { m = geom.mid; w = SIMD2(px, pz) + rotXZ(geom.midOff, yaw) }
            var a = sim.pivotAnchor(rotation: q, squash: sq, pivot: m, world: SIMD3(w.x, sim.floorY + m.y, w.y))
            a.y += lift
            sim.attractor.anchor = a
        } else {
            sim.attractor.anchor = SIMD3(px, sim.groundedAnchorY(rotation: q, squash: sq) + lift, pz)
        }
        sim.attractor.strength = kPose * smooth01(poseW)
    }

    // MARK: limbs

    func beginWave(_ sim: SoftBody, side: Int) {
        armActive = true; armT = 0; armBlend = 0; armPathName = ArmPath.wave.name
    }

    func endWave(_ sim: SoftBody) {
        if armCostN > 0 {
            NSLog("%@", String(format: "[melon] wave arm runtime: %.1f us per sim step (evaluate + hand-off), %d steps", armCostSum / Double(armCostN) * 1e6, armCostN))
            armCostSum = 0; armCostN = 0
        }
        armActive = false
        sim.targets.removeAll()
        sim.restoreStiffness()
        clearSkinOverride()
    }

    func clearSkinOverride() {
        skinnerRef?.clearOverride()
    }
    weak var skinnerRef: Skinner?

    // MARK: foot beans

    /// Test / tool access: make sure the geometry and the retract set exist (needs the skinner for the embedding).
    func prepareBeans(_ sim: SoftBody, _ skinner: Skinner) {
        if !geom.valid { geom = FootGeom(sim: sim) }
        if !footSkin.valid && geom.valid && !renderRest.isEmpty { footSkin = FootSkin(renderRest: renderRest, skinner: skinner, footParticles: geom.particles) }
        if skinner.beanFirst.isEmpty && beanFirstIdx.count == 2 { skinner.beanFirst = beanFirstIdx }
        if !retractReady && footSkin.valid {
            // the embedded foot (slab + fillet ring) retracts onto the FOOTLESS egg, sunk 1 cm so the egg skin hides it: rest-space delta per vertex
            // weighted by its distance to the foot ellipsoid (1 on / in the foot, smooth to 0 across the fillet band)
            var vs: [Int32] = [], ds: [SIMD3<Float>] = [], ws: [Float] = [], sd: [Int8] = []
            for s in 0..<2 {
                for (i, v) in footSkin.verts[s].enumerated() {
                    // never the walking arm capsules / foot beans themselves (they sit in the render mesh too, hidden inside the belly)
                    if beanFirstIdx.count == 2, armFirstIdx.count == 2, (0..<2).contains(where: { Int(v) >= armFirstIdx[$0] && Int(v) < beanFirstIdx[$0] + FootBean.vertexCount }) { continue }
                    let f = footSkin.sdf[s][i]
                    if f >= Self.retractBand && i >= footSkin.coreCount[s] { continue }
                    let r = footSkin.rest[s][i]
                    // the embedded foot's own vertices (the slab skin) always retract fully; the belly skin around it fades with its distance to the foot
                    let w = (f <= 0 || i < footSkin.coreCount[s]) ? Float(1) : 1 - smooth01(f / Self.retractBand)
                    // along the segment from the vertex to a point deep inside the egg, to where the egg's signed distance is -retractSink
                    // (bisection: robust at the rim where the egg's sdf has a ridge, unlike Newton)
                    let q = SIMD3<Double>(Double(abs(r.x)), Double(r.y), Double(r.z))
                    let P = SIMD3<Double>(q.x * 0.35, 0.40, q.z * 0.2)
                    var t = q
                    if BobForm.bodySDF(q) > -Self.retractSink {
                        var lo = 0.0, hi = 1.0
                        for _ in 0..<28 {
                            let m = (lo + hi) / 2
                            if BobForm.bodySDF(q + (P - q) * m) > -Self.retractSink { lo = m } else { hi = m }
                        }
                        t = q + (P - q) * hi
                    }
                    let sx: Float = r.x < 0 ? -1 : 1
                    vs.append(v); ds.append(SIMD3<Float>(sx * Float(t.x) - r.x, Float(t.y) - r.y, Float(t.z) - r.z)); ws.append(w); sd.append(i < footSkin.coreCount[s] ? Int8(s) : -1)
                }
            }
            skinner.retractVertices = vs; skinner.retractRest = ds; skinner.retractWeight = ws; skinner.retractSide = sd
            retractReady = true
        }
    }
    static let retractBand: Float = 0.10
    static let retractSink: Double = 0.025

    /// Body-rigid world position of rest point `r` (the attractor's pose: the position an undisturbed embedded foot would have).
    @inline(__always) private func bodyRigid(_ sim: SoftBody, _ r: SIMD3<Float>) -> SIMD3<Float> {
        let att = sim.attractor
        let sya = att.squash, sxza = 1 / sya.squareRoot(), o = r - sim.restCentroid
        return att.anchor + simd_float3x3(att.rotation) * SIMD3(o.x * sxza, o.y * sya, o.z * sxza)
    }

    /// World point -> rest coordinates under the body-rigid pose (inverse of `bodyRigid`).
    func toRest(_ sim: SoftBody, _ p: SIMD3<Float>) -> SIMD3<Float> {
        let att = sim.attractor, sya = att.squash, sxza = 1 / sya.squareRoot()
        let o = simd_float3x3(att.rotation).transpose * (p - att.anchor)
        return sim.restCentroid + SIMD3(o.x / sxza, o.y / sya, o.z / sxza)
    }

    /// ALWAYS ATTACHED: the bean point nearest the body centre must stay inside the body (sdf < -attachDepth in the body frame). If the swing
    /// path would let the bean leave him, the whole bean is moved along the egg's inward gradient (up / in toward the belly) just enough.
    static let attachDepth: Float = 0.04
    func attachBean(_ sim: SoftBody, _ pose: BodyPose, lifted: Bool, _ v: inout [SIMD3<Float>]) {
        let c0 = sim.restCentroid
        for _ in 0..<4 {
            var best = 0, bd = Float.infinity
            for i in v.indices { let d = simd_length_squared(v[i] - pose.centroid); if d < bd { bd = d; best = i } }
            let r = c0 + pose.rotation.inverse.act(v[best] - pose.centroid)
            let q = SIMD3<Double>(Double(abs(r.x)), Double(r.y), Double(r.z))
            let f = Float(BobForm.bodySDF(q))
            if f < -Self.attachDepth { return }
            let g = BobForm.eggGradient(q)
            let l2 = Float(simd_dot(g, g)); if l2 < 1e-9 { return }
            let sx: Float = r.x < 0 ? -1 : 1
            let k = (f + Self.attachDepth + 0.002) / l2
            var dW = pose.rotation.act(SIMD3(sx * Float(g.x), Float(g.y), Float(g.z)) * (-k))
            if !lifted { dW.y = min(dW.y, 0) }        // a planted foot stays on the floor (it only slides toward the belly)
            for i in v.indices { v[i] += dW }
        }
    }

    /// Hand the bean state to the skinner: hysteresis (stay out until both feet were still for `beanHoldTime`), growth blend, retract matrix.
    func commitBeans(_ sim: SoftBody, _ skinner: Skinner, _ dt: Float, want: Bool) {
        if want {
            if beanG <= 0 && beanHold <= 0 { beanSwaps += 1 }
            beanHold = beanHoldTime
        } else if shoesWorn { beanHold = beanHoldTime } else { beanHold = max(0, beanHold - dt) }
        let target: Float = (want || beanHold > 0) ? 1 : 0
        beanG += max(-dt / beanGrowTime, min(dt / beanGrowTime, target - beanG))
        if beanG <= 0.0001 { beanG = 0; skinner.clearBeans(); return }
        // start shape: the inset bean at the body-rigid foot pose, coincident with (inside) the embedded foot
        if beanStartScratch[0].count != FootBean.vertexCount { beanStartScratch = beanScratch }
        fillBeansRigid(sim, into: &beanStartScratch, tuck: 0, scale: FootBean.startScale)
        skinner.beanPos = beanScratch
        skinner.beanStart = beanStartScratch
        skinner.beanBlend = beanBlend
        let att = sim.attractor, sya = att.squash, sxza = 1 / sya.squareRoot()
        let RS = simd_float3x3(att.rotation) * simd_float3x3(diagonal: SIMD3(sxza, sya, sxza))
        skinner.retractMatrix = RS
        skinner.retractShift = footShift
        skinnerRef = skinner
    }

    /// Bean vertices at the body-rigid foot pose (plus `tuck` up): used while the feet are not world-driven (hop, spin, idle shrink-back).
    /// 0 = planted (the boot), 1 = lifted (a rounded ball): by how far the sole is off the floor.
    static func beanMorph(clearance c: Float) -> Float { smooth01((c - 0.004) / 0.030) }

    func fillBeansRigid(_ sim: SoftBody, into dst: inout [[SIMD3<Float>]], tuck: Float, scale: Float = 1) {
        let pv = SIMD3<Float>(0, Float(FootBean.pivotLocal.y), 0)
        // The attractor is only the body's pose while the brain drives him. Thrown / launched / held far from it (a bean that lingers 0.7 s after
        // a release) it is stale: the feet would stay where he was. Then the feet follow the body's fitted pose.
        let fitted: BodyPose? = (activity == .touched || activity == .recovering || simd_length(sim.attractor.anchor - sim.centroid()) > 0.1) ? sim.bodyPose(iterations: 3) : nil
        for s in 0..<2 {
            let c = geom.contact[s]
            func place(_ i: Int, _ m: Float) -> SIMD3<Float> {
                let l = pv + (FootBean.morphed(i, m) - pv) * scale
                let r = SIMD3(c.x + l.x, c.y + l.y, c.z + l.z)
                return fitted.map { $0.centroid + $0.rotation.act(r - sim.restCentroid) } ?? bodyRigid(sim, r)
            }
            var lo = Float.infinity
            for i in 0..<FootBean.vertexCount {
                var w = place(i, 0)
                lo = min(lo, w.y + tuck)
                w.y = max(w.y + tuck, sim.floorY)
                dst[s][i] = w
            }
            // off the floor (hop, jacks, flip, held in the air): the foot rounds into the ball
            let mo = scale == 1 ? Self.beanMorph(clearance: lo - sim.floorY) : 0
            if scale == 1 { beanMorphLast[s] = mo }
            if mo > 0 {
                for i in 0..<FootBean.vertexCount { var w = place(i, mo); w.y = max(w.y + tuck, sim.floorY); dst[s][i] = w }
            }
        }
    }

    func driveBeansRigid(_ sim: SoftBody, _ skinner: Skinner, _ dt: Float, tuck: Float = 0) {
        guard beanFirstIdx.count == 2, geom.valid || { if !geom.valid { geom = FootGeom(sim: sim) }; return geom.valid }() else { return }
        prepareBeans(sim, skinner)
        guard footSkin.valid else { return }
        if beanScratch[0].count != FootBean.vertexCount { beanScratch = [[SIMD3<Float>](repeating: .zero, count: FootBean.vertexCount), [SIMD3<Float>](repeating: .zero, count: FootBean.vertexCount)] }
        footShift = [.zero, .zero]
        fillBeansRigid(sim, into: &beanScratch, tuck: tuck)
        commitBeans(sim, skinner, dt, want: tuck > 0.002)
    }

    /// Test / tool access: the embedded foot's render vertices (the beans' sole contacts come from `Skinner.beanFirst`).
    func footCoreVertices(_ s: Int, sim: SoftBody, skinner: Skinner) -> [Int32] {
        if !geom.valid { geom = FootGeom(sim: sim) }
        if !footSkin.valid && geom.valid && !renderRest.isEmpty { footSkin = FootSkin(renderRest: renderRest, skinner: skinner, footParticles: geom.particles) }
        guard footSkin.valid else { return [] }
        return Array(footSkin.verts[s].prefix(footSkin.coreCount[s]))
    }

    /// Fade of the rigid render foot over a swing: in over the first 20 % (squared, so the first frame is < 2 mm), out over the last 20 % (no pop at lift-off / touch-down).

    func driveLimbs(_ sim: SoftBody, _ skinner: Skinner, _ dt: Float) {
        var list: [ParticleTarget] = []
        let beanLive = beanG > 0 || beanHold > 0 || shoesWorn
        let footOn = feetInit && geom.valid && feetDrive && (poseW > 0 || beanLive) && debugFeet
        guard footOn || armActive || nubOverride || armWalkWant > 0 || armLift != 0 || armG > 0 else {
            if !sim.targets.isEmpty { sim.targets.removeAll() }
            if beanLive { driveBeansRigid(sim, skinner, dt) } else if skinner.beanBlend > 0 { skinner.clearBeans() }
            driveArms(sim, skinner, dt)
            return
        }
        if armActive, let kf = armKeyframes[armPathName] {
            let pose = sim.bodyPose(iterations: 3)
            armT += dt
            let tt0 = CFAbsoluteTimeGetCurrent()
            defer { armCostSum += CFAbsoluteTimeGetCurrent() - tt0; armCostN += 1 }
            kf.evaluate(side: armSide, s: armPathName == ArmPath.wave.name ? WaveScript.s(at: armT) : armS, rotation: pose.rotation, delta: &armDelta, ao: &armAO)
            skinner.overrideVertices = kf.side(armSide).vertices
            skinner.overrideDelta = armDelta
            skinner.overrideMat = armAO
            skinnerRef = skinner
        }
        if footOn {
            // Every foot follows a world target: planted feet are held where they landed (no skating). The SIM sole only follows the swing
            // path in xz and lifts / swings out by a few centimetres (the slab under a foot is only 0.1 u tall); the full swing (up, forward,
            // outward, toe up so the sole shows) is drawn by the rigid render foot below.
            let k = footStiffness * smooth01(poseW)
            let waving = armActive && { if case .wave = script { return true }; return false }()
            if !footSkin.valid && geom.valid && !renderRest.isEmpty {
                footSkin = FootSkin(renderRest: renderRest, skinner: skinner, footParticles: geom.particles)
            }
            prepareBeans(sim, skinner)
            if beanScratch[0].count != FootBean.vertexCount { beanScratch = [[SIMD3<Float>](repeating: .zero, count: FootBean.vertexCount), [SIMD3<Float>](repeating: .zero, count: FootBean.vertexCount)] }
            var want = false
            let fitted = sim.bodyPose(iterations: 3)
            for s in 0..<2 {
                var (xz, fyaw, h, out, tilt, fwd) = feet.state(s)
                var outV = SIMD2<Float>.zero
                if out != 0 || fwd != 0 { outV = rotXZ(SIMD2((s == 1 ? 1 : -1) * out, fwd), fyaw) }
                var waveLift: Float = 0
                if waving && s == (armSide > 0 ? 1 : 0) {
                    let e = WaveScript.footLift(at: armT)
                    outV += rotXZ(SIMD2(Float(armSide) * waveFootOut, waveFootFwd), yaw) * (e * amplitude)
                    h += waveFootLift * e * amplitude
                    tilt = waveFootTilt * e
                    waveLift = e
                }
                let c = geom.contact[s]
                // SIM: the sole follows the BODY's rigid pose plus a few centimetres toward the wanted spot (a bigger xz shear or any lift
                // beyond the slab height inverts the prisms); the wanted spot (planted foot pinned in the world, or the swing arc) is drawn by
                // the foot bean.
                let att = sim.attractor
                let RA = simd_float3x3(att.rotation), sya = att.squash, sxza = 1 / sya.squareRoot(), c0 = sim.restCentroid
                @inline(__always) func bodyPos(_ r: SIMD3<Float>) -> SIMD3<Float> {
                    let o = r - c0
                    return att.anchor + RA * SIMD3(o.x * sxza, o.y * sya, o.z * sxza)
                }
                let wanted = xz + outV
                let bc = bodyPos(c)
                let offFull = wanted - SIMD2(bc.x, bc.z)
                var simD = offFull; let sl = simd_length(simD)
                if sl > simFootCap { simD *= simFootCap / sl }
                let hs = min(h, simFootCap)
                footShift[s] = SIMD3(simD.x, hs, simD.y)
                for (i, p) in geom.particles[s].enumerated() {
                    let r = geom.rest[s][i]
                    let bp = bodyPos(r)
                    list.append(ParticleTarget(index: p, pos: SIMD3(bp.x + simD.x, sim.floorY + r.y + hs, bp.z + simD.y), stiffness: k))
                }
                // BEAN: a foot that is stepping, displaced from the body's own foot, lifted or waving needs the bean; both feet still at their rest
                // spots for beanHoldTime lets the beans go (one swap per action, never per step)
                if (feet.active || simd_length(offFull) > 0.012 || h > 0.006 || waveLift > 0.02) { want = true }
                let ct = cosf(tilt), st = sinf(tilt), hz = geom.heelZ[s] - c.z
                let ys: Float = 1
                let wy = sim.floorY + c.y + h
                var bv = beanScratch[s]
                let mo = Self.beanMorph(clearance: h); beanMorphLast[s] = mo           // planted = the boot, lifted = a rounded ball (user 2026-10-17), smoothly in between
                for i in 0..<FootBean.vertexCount {
                    let l = FootBean.morphed(i, mo)
                    let ly = l.y * ys, zr = l.z - hz           // tilt about the heel
                    let ty = ly * ct + zr * st, tz = -ly * st + zr * ct
                    let w = wanted + rotXZ(SIMD2(l.x, hz + tz), fyaw)
                    bv[i] = SIMD3(w.x, wy + ty, w.y)
                }
                attachBean(sim, fitted, lifted: h > 0.02, &bv)
                for i in bv.indices { bv[i].y = max(bv[i].y, sim.floorY) }       // a foot never sinks through the floor (the attach shift can only move it in / up)
                beanScratch[s] = bv
            }
            commitBeans(sim, skinner, dt, want: want)
        } else if beanLive { driveBeansRigid(sim, skinner, dt) } else if skinner.beanBlend > 0 { skinner.clearBeans() }
        driveArms(sim, skinner, dt)
        sim.targets = list
    }

    // MARK: walking arms (closed capsules)

    var armLift: Float = 0, armLiftV: Float = 0       // the LIFT axis: 0 = the rest nub, 1 = the walk pose (its own spring; the sweep S is independent)
    var armG: Float = 0, armHold: Float = 0           // swap blend (capsule out / skin nub retracted) and its 0.7 s hold
    /// The gait weight the arm sweep's phase shift follows: moves only while both arms are in a hold (ArmPath.armShiftStep) so a waddle <-> stride blend does not whip the arms (MotionArmTests).
    var armGaitW: Float = 1
    /// Body-frame capsule drawn last tick (after the cap), +x arm convention, and the tip it asked for before the cap (diagnostics / tests).
    var armLastGeom: [(a: SIMD3<Float>, b: SIMD3<Float>, r1: Float, r2: Float, f: Float)] = [(.zero, .zero, 0, 0, 1), (.zero, .zero, 0, 0, 1)]
    var armLastRawTip: [SIMD3<Float>] = [.zero, .zero]
    private var armRawTip: SIMD3<Float> = .zero
    var armLastS: [Float] = [25, 25]                   // each arm's sweep (deg) frozen at the release
    var armScratch: [[SIMD3<Float>]] = [[], []], armStartScratch: [[SIMD3<Float>]] = [[], []]
    var armFirstIdx: [Int] = []
    var armRetractReady = false
    var armCollar = ArmCollar.Set()
    var armCollarTick = 0
    var armWasOut = false
    var armAOBaked: [Float] = [], armAOEgg: [Float] = []
    private(set) var armSwapCount = 0
    var armLiftNow: Float { armLift }
    var armCapsuleOut: Bool { armG > 0 }
    var armBlendNow: Float { let k = smooth01(armG); return k * k }

    func prepareArms(_ skinner: Skinner) {
        if skinner.armFirst.isEmpty && armFirstIdx.count == 2 { skinner.armFirst = armFirstIdx }
        guard !armRetractReady, !renderRest.isEmpty, armFirstIdx.count == 2, beanFirstIdx.count == 2 else { return }
        // the rest nub's skin retracts onto the ARMLESS egg, sunk 1 cm (rest-space delta per vertex, weight fading with the distance to the rest cone)
        let F = PosedArmField(ArmGeom.rest)
        let n = renderRest.count / 3
        var vs: [Int32] = [], ds: [SIMD3<Float>] = [], ws: [Float] = [], aoB: [Float] = [], aoE: [Float] = []
        let ranges = (0..<2).map { armFirstIdx[$0]..<(beanFirstIdx[$0] + FootBean.vertexCount) }
        // the mesh surface is not exactly the analytic egg: calibrate the target level on the ring of skin just outside the nub's influence
        var ring: [Double] = []
        for v in 0..<n where !ranges[0].contains(v) && !ranges[1].contains(v) {
            let r = SIMD3(renderRest[3 * v], renderRest[3 * v + 1], renderRest[3 * v + 2])
            if abs(r.x) < 0.25 || r.y < 0.15 || r.y > 1.0 { continue }
            let q = SIMD3<Double>(Double(abs(r.x)), Double(r.y), Double(r.z))
            let d = F.cone(q)
            if d > 0.14 && d < 0.22 { ring.append(BobForm.bodySDF(q)) }
        }
        ring.sort()
        let level = (ring.isEmpty ? 0.0 : ring[ring.count / 2]) + UserDefaults.standard.double(forKey: "ArmRetractLevel")
        for v in 0..<n where !ranges[0].contains(v) && !ranges[1].contains(v) {
            let r = SIMD3(renderRest[3 * v], renderRest[3 * v + 1], renderRest[3 * v + 2])
            if abs(r.x) < 0.25 || r.y < 0.15 || r.y > 1.0 { continue }
            let q = SIMD3<Double>(Double(abs(r.x)), Double(r.y), Double(r.z))
            let d = F.cone(q)
            if d > 0.14 { continue }
            let w = d <= 0.02 ? Float(1) : 1 - smooth01(Float((d - 0.02) / 0.12))
            // nearest point of the armless egg's level surface (Newton along its own gradient): a smooth map, so the retracted skin cannot fold
            var t = q
            for _ in 0..<10 {
                let f = BobForm.bodySDF(t) - level, g = BobForm.eggGradient(t), l2 = simd_dot(g, g)
                if l2 < 1e-12 || abs(f) < 1e-7 { break }
                t -= g * (f / l2)
            }
            let sx: Float = r.x < 0 ? -1 : 1
            vs.append(Int32(v)); ds.append(SIMD3(sx * Float(t.x) - r.x, Float(t.y) - r.y, Float(t.z) - r.z)); ws.append(w)
            // the baked crease occlusion (mat channel) of the nub's skin goes with it: blend it to the armless egg's value at the target point
            let nb = BobForm.normal(q)
            aoB.append(Float(0.4 * BobForm.occlusion(q, nb)))
            let e = 1e-4
            var gr = SIMD3(BobForm.bodySDF(t + SIMD3(e, 0, 0)) - BobForm.bodySDF(t - SIMD3(e, 0, 0)),
                           BobForm.bodySDF(t + SIMD3(0, e, 0)) - BobForm.bodySDF(t - SIMD3(0, e, 0)),
                           BobForm.bodySDF(t + SIMD3(0, 0, e)) - BobForm.bodySDF(t - SIMD3(0, 0, e)))
            let gl = simd_length(gr); gr = gl > 1e-12 ? gr / gl : nb
            var occ = 0.0, wt = 1.0
            for k in 1...5 { let h = 0.05 * Double(k); occ += max(h - BobForm.bodySDF(t + gr * h), 0) / h * wt; wt *= 0.7 }
            aoE.append(Float(0.4 * min(max(occ * 1.1, 0), 1)))
        }
        armAOBaked = aoB; armAOEgg = aoE
        skinner.armRetractVertices = vs; skinner.armRetractRest = ds; skinner.armRetractWeight = ws
        let skipR = [armFirstIdx[0]..<(beanFirstIdx[0] + FootBean.vertexCount), armFirstIdx[1]..<(beanFirstIdx[1] + FootBean.vertexCount)]
        armCollar = ArmCollar.build(rest: renderRest, skip: skipR)
        skinner.armCollarVertices = armCollar.ids
        armRetractReady = true
    }

    /// Body-frame (+x convention) capsule geometry of an arm at sweep `S` (deg) and lift axis value `lift` (0 = the rest nub station line, 1 = the walk pose).
    func armGeometry(S: Float, lift: Float, capped: Bool = true) -> (a: SIMD3<Float>, b: SIMD3<Float>, r1: Float, r2: Float, f: Float) {
        armGeometry(el: ArmPath.armWalkElevation(S), sa: S * .pi / 180, lift: lift, xShift: 0, bodyLed: 0, capped: capped)
    }

    /// The idle override: the arm axis turned `w` of the way from the walk direction toward (`dirEl`, `dirSa`) (rad), the whole stub nudged `out` outward.
    func armGeometry(S: Float, lift: Float, dirEl: Float, dirSa: Float, w: Float, out: Float) -> (a: SIMD3<Float>, b: SIMD3<Float>, r1: Float, r2: Float, f: Float) {
        let el0 = ArmPath.armWalkElevation(S), sa0 = S * .pi / 180
        return armGeometry(el: el0 + (dirEl - el0) * w, sa: sa0 + (dirSa - sa0) * w, lift: lift, xShift: out * w, bodyLed: w)
    }

    func armGeometry(el: Float, sa: Float, lift: Float, xShift: Float, bodyLed: Float = 0, capped: Bool = true) -> (a: SIMD3<Float>, b: SIMD3<Float>, r1: Float, r2: Float, f: Float) {
        let W = ArmPath.armWalkRoot
        let d = SIMD3<Float>(cosf(el) * cosf(sa), sinf(el), cosf(el) * sinf(sa))
        let aw = SIMD3<Float>(Float(W.x) + xShift, Float(W.y), Float(W.z)), bw = aw + d * Float(W.length)      // the shoulder is a fixed interior point of the body (W1c): only the direction turns
        let ar = SIMD3<Float>(Float(BobForm.armTop.x), Float(BobForm.armTop.y), Float(BobForm.armTop.z))
        let br = SIMD3<Float>(Float(BobForm.armTip.x), Float(BobForm.armTip.y), Float(BobForm.armTip.z))
        let l = lift
        var aF = ar + (aw - ar) * l, bF = br + (bw - br) * l
        let r2F = Float(BobForm.armTipR) + (Float(W.r2) - Float(BobForm.armTipR)) * l
        armRawTip = bF
        // THE global arm cap (ArmCap): whatever a move asks for, the arm never stands out further than the wave's thumb
        var bC = bF
        if ArmCap.enabled && capped {
            let f = ArmCap.fuse(a: SIMD3<Double>(aF), b: SIMD3<Double>(bF))
            aF = SIMD3<Float>(f.a)
            bC = SIMD3<Float>(ArmCap.clampTip(a: f.a, b: f.b, r2: Double(r2F), limit: ArmCap.limit(bodyLed: Double(max(bodyLed, armShortW)))))
        }
        return (aF, bC, Float(BobForm.armTopR) + (Float(W.r1) - Float(BobForm.armTopR)) * l,
                r2F, Float(BobForm.armFlatten) + (1 - Float(BobForm.armFlatten)) * l)
    }

    func driveArms(_ sim: SoftBody, _ skinner: Skinner, _ dt: Float) {
        guard beanFirstIdx.count == 2, armFirstIdx.count == 2 else { return }
        // lift axis spring: a smooth lift over ~0.5 s with the sweep at full amplitude from the first step, an under-damped release (2.3 Hz, zeta 0.30)
        let tgt: Float = armWalkWant > 0 ? 1 : 0
        let om: Float = tgt > 0 ? 9.5 : 2 * .pi * 2.3, ze: Float = tgt > 0 ? 1 : 0.30
        armLiftV += (om * om * (tgt - armLift) - 2 * ze * om * armLiftV) * dt
        armLift += armLiftV * dt
        armLift = min(1.05, max(-0.4, armLift))
        if tgt == 0 && abs(armLift) < 0.004 && abs(armLiftV) < 0.08 { armLift = 0; armLiftV = 0 }
        let want = armWalkWant > 0 || armLift != 0
        if want { if armG <= 0 && armHold <= 0 { armSwapCount += 1 }; armHold = 0.7 } else { armHold = max(0, armHold - dt) }
        let gT: Float = (want || armHold > 0) ? 1 : 0
        armG += max(-dt / 0.12, min(dt / 0.12, gT - armG))
        if armG <= 0.0001 {
            armG = 0
            if armWasOut { skinner.clearArmCapsules(); skinner.clearOverride(); armWasOut = false; nubPhi = [0, 0] }
            return
        }
        guard geom.valid else { return }
        let shortGoal: Float = (idleState.kind == .jacks || idleState.kind == .zoomies || idleState.kind == .slide || idleState.kind == .scoot || isFlipping || armDirW > 0) ? 1 : 0
        armShortW += max(-dt / 0.25, min(dt / 0.15, shortGoal - armShortW))
        prepareArms(skinner)
        let ph = stridePhase
        armGaitW = ArmPath.armShiftStep(shiftW: armGaitW, target: gaitW, phase: ph, dt: dt)
        let sweep: Float = (armWalkWant >= 1 ? 1 : 0.5) * (1 + Self.runArmGain * runW)
        if armScratch[0].count != ArmCapsule.vertexCount {
            armScratch = [[SIMD3<Float>](repeating: .zero, count: ArmCapsule.vertexCount), [SIMD3<Float>](repeating: .zero, count: ArmCapsule.vertexCount)]
            armStartScratch = armScratch
        }
        let att = sim.attractor, sya = att.squash, sxza = 1 / sya.squareRoot(), c0 = sim.restCentroid
        let RS = simd_float3x3(att.rotation) * simd_float3x3(diagonal: SIMD3(sxza, sya, sxza))
        let org = att.anchor - RS * c0
        for si in 0..<2 {
            let sg: Float = si == 0 ? -1 : 1
            if armWalkWant > 0 {
                let S = ArmPath.armWalkSweepDeg(phase: ph, side: si == 0 ? -1 : 1, gaitW: armGaitW)
                armLastS[si] = ArmPath.armWalkCentreDeg + (S - ArmPath.armWalkCentreDeg) * sweep
            }
            nubPhi[si] = (armLastS[si] - ArmPath.armWalkCentreDeg) / 33
            let g = armDirW > 0 ? armGeometry(S: armLastS[si], lift: armLift, dirEl: armDirEl[si], dirSa: armDirSa[si], w: armDirW, out: armDirOut) : armGeometry(S: armLastS[si], lift: armLift)
            armLastGeom[si] = g; armLastRawTip[si] = armRawTip
            ArmCapsule.fill(a: g.a, b: g.b, r1: g.r1, r2: g.r2, flatten: g.f, sigma: sg, into: &armScratch[si])
            let r = armGeometry(S: 25, lift: 0, capped: false)
            ArmCapsule.fill(a: r.a, b: r.b, r1: r.r1, r2: r.r2, flatten: r.f, sigma: sg, inflate: -0.002, into: &armStartScratch[si])
            for i in 0..<ArmCapsule.vertexCount { armScratch[si][i] = org + RS * armScratch[si][i]; armStartScratch[si][i] = org + RS * armStartScratch[si][i] }
        }
        skinner.armPos = armScratch; skinner.armStart = armStartScratch
        skinner.armBlend = armBlendNow
        skinner.armRetractMatrix = RS
        if ArmCap.enabled && ArmCap.collar && !armCollar.ids.isEmpty {
            armCollarTick &+= 1       // one side per tick (each side refreshes at 30 Hz): the bump moves a few mm per step
            ArmCollar.fill(armCollar, geoms: armLastGeom, M: RS, side: armCollarTick & 1, into: &skinner.armCollarDelta)
        } else { skinner.armCollarDelta = [] }
        if !armWasOut {
            // crease occlusion on the capsules' vertices (the mat channel, through the same override the wave uses; positions are not moved by it)
            var verts: [Int32] = []
            for s in 0..<2 { for i in 0..<ArmCapsule.vertexCount { verts.append(Int32(armFirstIdx[s] + i)) } }
            verts += skinner.armRetractVertices
            skinner.overrideVertices = verts
            skinner.overrideDelta = [SIMD3<Float>](repeating: .zero, count: verts.count)
            skinner.overrideMat = ArmCapsule.creaseAO + ArmCapsule.creaseAO + armAOBaked
            skinnerRef = skinner
            armWasOut = true
        }
        if armWasOut {
            let bl = armBlendNow, nR = armAOBaked.count, base = 2 * ArmCapsule.vertexCount
            if skinner.overrideMat.count == base + nR {
                for k in 0..<nR { skinner.overrideMat[base + k] = armAOBaked[k] + (armAOEgg[k] - armAOBaked[k]) * skinner.armRetractWeight[k] * bl }
            }
        }
    }

    // MARK: dining (finger food, fork food, sipping)

    enum DineMode { case finger, fork, sip }

    /// Callbacks into the tray (DiningSet) for one meal; set by GameCare. Everything is in world space.
    struct DineHooks {
        var piece: (Int) -> SIMD3<Float>           // world point bite `k` reaches for: the berry it takes (finger) / the food the fork stabs (fork)
        var begin: () -> Bool                      // the next piece leaves the plate / the fork takes a forkful
        var finish: () -> Void                     // swallowed: the piece / forkful is gone
        var cancel: () -> Void                     // dropped (grabbed mid-bite): the piece goes back on the plate
        var hold: (simd_float4x4) -> Void          // world transform of the piece in hand this frame (finger foods)
        // fork foods
        var fork = false
        var forkAppear: (SIMD3<Float>) -> Void = { _ in }          // the fork poofs into his hand at this world point (tines up)
        var holdFork: (simd_float4x4) -> Void = { _ in }           // world transform of the fork in hand (grip at the origin, tines toward +z)
        var releaseFork: () -> Void = {}                           // the fork poofs away
        var launch: () -> Void = {}                                // the toss: the forkful leaves the tines
        var holdBite: (simd_float4x4) -> Void = { _ in }           // world transform of the forkful in flight
        // drinks
        var straw: () -> SIMD3<Float> = { .zero }                  // world position of the tip of his own straw
        var level: (Float) -> Void = { _ in }                      // fraction of his share drunk so far, 0...1
    }
    var dineHooks: DineHooks?
    /// How this sitting goes (GameCare sets it with the hooks, from his hunger / thirst tier): `refuse` = he shakes his head at the tray and eats nothing,
    /// `pace` = beat speed (eager when famished), `levelBase` / `levelSpan` = the part of his drink share this sitting drains (a partial drink never
    /// empties the bottle). Defaults = the whole serving at the shared rate.
    struct DinePlan: Equatable { var refuse = false; var pace: Float = 1; var levelBase: Float = 0; var levelSpan: Float = 1 }
    var dinePlan = DinePlan()
    /// True while he shakes his head at a tray (the refusal): GameCare shows the "Not hungry" label for it.
    var isRefusing: Bool { if case .dine = script { return dinePlan.refuse }; return false }

    enum DinePhase { case lean, grab, straighten, chew, happy }
    struct DineState {
        var place = DiningPlace(stand: .zero, yaw: 0, mouth: .zero)
        var bitesLeft = 0
        var total = 0
        var mode = DineMode.finger
        var phase = DinePhase.lean
        var t: Float = 0
        var entered = false                         // the current phase's first tick has run
        var k = 0                                   // bite / gulp index within this meal
        var side = 1
        var reach = ReachPose()
        var from = ReachPose()                      // the pose a lean starts from
        var cur = ReachPose()                       // the pose applied last tick
        var miss: Float = 0
        var armS: Float = 0
        var holding = false
        var forkHeld = false
        var finished = false
        var flying = false                          // the toss: the bite has left the nub / tines and is in the air (or has landed in the mouth)
        var landed = false
        var launch = SIMD3<Float>(0, 0, 0)          // where it left
        var window = false                          // inside a chomp / gulp window (mouth may be open)
        init() {}
        init(place: DiningPlace, bitesLeft: Int, mode: DineMode) { self.place = place; self.bitesLeft = bitesLeft; total = bitesLeft; self.mode = mode }
    }
    var dine = DineState()

    // timeline (the shared rate: a bite is two beats of DiningTiming.beatPeriod, a gulp one)
    nonisolated static var dineBeat: Float { DiningTiming.beatPeriod }
    private static var tLean: Float { dineBeat * 0.40 }
    private static var tGrab: Float { dineBeat * 0.15 }
    private static var tStraighten: Float { dineBeat * 0.45 }
    private static var tHappy: Float { dineBeat * 1.1 }
    private static var tSipLean: Float { dineBeat * 0.6 }

    /// World position of a point given in rest coordinates, carried by the sim body's fitted pose.
    func bodyPointWorld(_ rest: SIMD3<Float>, sim: SoftBody, pose: (centroid: SIMD3<Float>, rotation: simd_quatf)) -> SIMD3<Float> {
        let sy = sim.attractor.squash, sxz = 1 / sy.squareRoot()
        let o = rest - sim.restCentroid
        return pose.centroid + simd_float3x3(pose.rotation) * SIMD3(o.x * sxz, o.y * sy, o.z * sxz)
    }
    func nubHoldRest(s: Float) -> SIMD3<Float> {
        DineGeometry.mirrored(DineGeometry.holdPoint(path: .nubToMouth, s: Double(s)), side: dine.side)
    }

    /// Where the piece sits on the nub right now (world): the nub's hold point on the path, carried by the sim body's fitted pose.
    func nubTipWorld(sim: SoftBody) -> SIMD3<Float> {
        let p = sim.bodyPose(iterations: 3)
        return bodyPointWorld(nubHoldRest(s: dine.armS), sim: sim, pose: (p.centroid, p.rotation))
    }
    /// Where his mouth is right now (world), for the sip.
    func mouthWorld(sim: SoftBody) -> SIMD3<Float> {
        let p = sim.bodyPose(iterations: 3)
        return bodyPointWorld(DineGeometry.mouthRest, sim: sim, pose: (p.centroid, p.rotation))
    }
    /// World transform of the fork in hand: the grip on the nub, the tines along the wrist direction for the current arm parameter.
    func forkMatrixWorld(sim: SoftBody) -> simd_float4x4 {
        let p = sim.bodyPose(iterations: 3)
        return forkMatrix(sim: sim, pose: (p.centroid, p.rotation))
    }
    func forkMatrix(sim: SoftBody, pose: (centroid: SIMD3<Float>, rotation: simd_quatf)) -> simd_float4x4 {
        let nub = bodyPointWorld(nubHoldRest(s: dine.armS), sim: sim, pose: pose)
        let R = simd_float3x3(pose.rotation)
        let z = simd_normalize(R * DineGeometry.forkDir(s: dine.armS, side: dine.side, grabS: Float(ArmPath.nubGrabS)))
        let x = simd_normalize(simd_cross(R * SIMD3<Float>(0, 1, 0), z)), y = simd_cross(z, x)
        let grip = nub
        return simd_float4x4(columns: (SIMD4(x, 0), SIMD4(y, 0), SIMD4(z, 0), SIMD4(grip, 1)))
    }
    var dineBitesLeft: Int { dine.bitesLeft }
    var dineHolding: Bool { dine.holding }
    var dineForkHeld: Bool { dine.forkHeld }
    /// Test hooks: where the dine timeline is, and whether the mouth may be open right now.
    var dinePhaseName: String { "\(dine.phase)" }
    var dineMouthWindow: Bool { dine.window }
    var dineReachMiss: Float { dine.miss }
    var dineArmS: Float { dine.armS }
    var dineFlying: Bool { dine.flying }
    var dineLanded: Bool { dine.landed }
    var dineLaunchWorld: SIMD3<Float> { dine.launch }
    /// The toss timeline (seconds): the nub's flick, and the flight to the mouth (from the end of the flick).
    nonisolated static var tossFlick: Float { dineBeat * 0.18 }
    nonisolated static var tossLand: Float { dineBeat * 0.42 }
    nonisolated static let tossArc: Float = 0.15
    var dineGulpIndex: Int { dine.k }
    var dineIsGrabbing: Bool { dine.phase == .grab }
    var dineIsSipping: Bool { dine.mode == .sip }
    /// True while a keyframe arm path (wave / nubToMouth) drives the skin override; with a walking capsule out this would be a double arm.
    var armPathActive: Bool { armActive }

    func dineAbort() {
        if dine.holding { dineHooks?.cancel(); dine.holding = false }
        if dine.forkHeld { dineHooks?.releaseFork(); dine.forkHeld = false }
        dine.flying = false; dine.landed = false
        armS = 0; dine.armS = 0
    }

    func lerpPose(_ a: ReachPose, _ b: ReachPose, _ u: Float) -> ReachPose {
        ReachPose(twist: a.twist + (b.twist - a.twist) * u, pitch: a.pitch + (b.pitch - a.pitch) * u,
                  roll: a.roll + (b.roll - a.roll) * u, squash: a.squash + (b.squash - a.squash) * u)
    }

    /// Solves the body-led reach for the current bite: `hold` is a point rigid with the body (rest coordinates), `target` a world point.
    func solveDineReach(_ sim: SoftBody, holds: (Int) -> SIMD3<Float>, target: SIMD3<Float>, crouch: Float) {
        var bestMiss = Float.infinity
        let m = geom.mid, w = SIMD2(px, pz) + rotXZ(geom.midOff, yaw)
        for side in (dine.mode == .sip ? [1] : [-1, 1]) {
            let r = DineGeometry.solveReach(hold: holds(side), target: target, m: m, w: SIMD3(w.x, sim.floorY + m.y, w.y), c0: sim.restCentroid,
                                            yaw: yaw, pitchBase: pitchBase, crouch: crouch, side: side)
            if r.miss < bestMiss { bestMiss = r.miss; dine.side = side; dine.reach = r.pose }
        }
        dine.miss = bestMiss
    }

    func applyDine(_ sim: SoftBody, _ skinner: Skinner, pose: ReachPose, mouth: Float, eyes: Float, pulse: Float) {
        dine.cur = pose
        twist = pose.twist * amplitude
        self.pitch = pose.pitch * amplitude
        self.roll = pose.roll * amplitude
        self.squash = pose.squash * (1 - MotionCurve.pulseDepth * pulse)
        pivotSide = nil
        mouthOpen = mouth
        skinner.setEyeOpenness(eyes)
        updateBrowCounter(sim, skinner)
    }

    /// While he dines the brows must never read angry: the skinner turns any brow that the lean / turn makes slant down (as the game camera sees it) back
    /// up to flat. Only active during dining; the rest face is untouched.
    func updateBrowCounter(_ sim: SoftBody, _ skinner: Skinner) { skinner.browCounterOn = true }

    func runDine(_ sim: SoftBody, _ skinner: Skinner, _ dt: Float) {
        poseOn = true; ensureFeet(sim)
        // hand-off: the walking arm capsules must be swapped out (0.12 s) before anything reaches; nothing starts while one is out
        if armCapsuleOut || armLift != 0 { armLift = 0; armLiftV = 0; armHold = 0; return }
        if dinePlan.refuse { runRefuse(sim, skinner, dt); return }
        if dine.mode == .sip { runSip(sim, skinner, dt); return }
        if armBuilding || armKeyframes[ArmPath.nubToMouth.name] == nil { return }          // path still precomputing: stand and wait
        guard let h = dineHooks else { return }
        if !armActive { armActive = true; armPathName = ArmPath.nubToMouth.name; armT = 0; armBlend = 0 }
        dine.t += dt * dinePlan.pace
        let grabS = Float(ArmPath.nubGrabS)
        var pose = ReachPose()
        var armTarget: Float = 0, mouth: Float = 0, eyes: Float = 1, pulse: Float = 0
        dine.window = false
        var snap: Float?

        switch dine.phase {
        case .lean:
            if !dine.entered {                      // first tick of this lean: solve the reach (turn / pitch / roll about the planted feet)
                dine.entered = true
                dine.from = ReachPose()
                if dine.mode == .fork {
                    let target = h.piece(dine.k)
                    solveDineReach(sim, holds: { s in
                        DineGeometry.mirrored(DineGeometry.holdPoint(path: .nubToMouth, s: Double(grabS)), side: s)
                            + DineGeometry.forkDir(s: grabS, side: s, grabS: grabS) * DineGeometry.forkLength
                    }, target: target, crouch: 0.9)
                } else {
                    let berry = h.piece(dine.k) + SIMD3(0, 0.02, 0)
                    solveDineReach(sim, holds: { DineGeometry.mirrored(DineGeometry.holdPoint(path: .nubToMouth, s: Double(grabS)), side: $0) },
                                   target: berry, crouch: 0.9)
                }
                armSide = dine.side
                if dine.mode == .fork && !dine.forkHeld {            // a small puff at his nub and the fork pops into his hand, tines up
                    dine.forkHeld = true
                    let bp = sim.bodyPose(iterations: 3)
                    h.forkAppear(bodyPointWorld(nubHoldRest(s: 0), sim: sim, pose: (centroid: bp.centroid, rotation: bp.rotation)))
                }
            }
            let u = MotionCurve.spring(dine.t / Self.tLean)
            pose = lerpPose(dine.from, dine.reach, u)
            armTarget = grabS * min(1, dine.t / Self.tLean * 1.2)
            if dine.t >= Self.tLean { dine.phase = .grab; dine.t = 0; dine.entered = false }
        case .grab:
            pose = dine.reach; armTarget = grabS
            if !dine.holding, h.begin() { dine.holding = true }
            if dine.t >= Self.tGrab { dine.phase = .straighten; dine.t = 0; dine.entered = false }
        case .straighten:
            let u = MotionCurve.spring(dine.t / Self.tStraighten)
            pose = lerpPose(dine.reach, ReachPose(), u)
            armTarget = dine.t < 0.6 * Self.tStraighten ? grabS : 0.02        // the nub cocks back (still the stub, never longer) for the flick
            if dine.t >= Self.tStraighten { dine.phase = .chew; dine.t = 0; dine.entered = false }
        case .chew:
            // THE TOSS: a quick flick of the stub (the nub swings forward, never longer than its rest length) launches the bite in a small arc into his
            // mouth; the mouth opens just before it lands, then a chomp with a squash pulse and a happy wiggle, a second chomp, swallow.
            let b = Self.dineBeat, flickEnd = Self.tossFlick, landT = Self.tossLand
            if dine.t < flickEnd { snap = 0.02 + (grabS - 0.02) * smooth01(dine.t / flickEnd) } else { armTarget = 0 }
            if dine.holding && !dine.flying && dine.t >= flickEnd {
                dine.flying = true; dine.landed = false
                dine.launch = heldPointWorld(sim)
                if dine.mode == .fork { h.launch() }
            }
            if dine.flying && dine.t >= landT { dine.landed = true }
            let o1 = smooth01((dine.t - 0.30 * b) / (0.10 * b)) * (1 - smooth01((dine.t - 0.50 * b) / (0.08 * b)))
            let o2 = smooth01((dine.t - 0.64 * b) / (0.08 * b)) * (1 - smooth01((dine.t - 0.82 * b) / (0.08 * b)))
            mouth = min(1, max(o1, o2) * 0.9)
            dine.window = (dine.t > 0.28 * b && dine.t < 0.60 * b) || (dine.t > 0.62 * b && dine.t < 0.92 * b)
            pulse = max(MotionCurve.pulse((dine.t - landT) / (0.30 * b)), MotionCurve.pulse((dine.t - 0.66 * b) / (0.30 * b)))
            if dine.t > landT {                         // the happy wiggle after the first chomp
                let env = smooth01((dine.t - landT) / (0.05 * b)) * (1 - smooth01((dine.t - 0.9 * b) / (0.1 * b)))
                pose.roll = 0.06 * sinf(2 * .pi * (dine.t - landT) / (0.3 * b)) * env
            }
            if dine.holding && dine.t > 0.56 * b { dine.holding = false; dine.flying = false; dine.landed = false; h.finish(); dine.bitesLeft -= 1 }
            if dine.t >= b {
                if dine.bitesLeft > 0 { dine.k += 1; dine.phase = .lean; dine.t = 0; dine.entered = false; armTarget = 0 }
                else { dine.phase = .happy; dine.t = 0 }
            }
        case .happy:
            // happy: eyes fully closed (like the wave's closes) and one squash pulse, then he is done
            eyes = 0
            pulse = MotionCurve.pulse(dine.t / Self.tHappy)
            armTarget = 0
            if dine.t >= Self.tHappy { dine.finished = true }
        }
        // the arm follows its target with the shared spring-less slew (rates in path units per second), so s never jumps
        let rate: Float = 3.2 * dinePlan.pace
        if let snap { armS = snap } else { armS += max(-rate * dt, min(rate * dt, armTarget - armS)) }
        dine.armS = armS
        applyDine(sim, skinner, pose: pose, mouth: mouth, eyes: eyes, pulse: pulse)
        sendHeld(sim)
        if dine.finished { dineDone(sim, skinner) }
    }

    /// What he holds rides the nub (a piece at the nub's tip, or the fork by its grip); the first frames of a grab blend from the plate / the tray
    /// to the nub so a small reach miss is not a pop. Sent after the brain tick AND again after the frame's last sim step (`refreshHeld`).
    func sendHeld(_ sim: SoftBody) {
        guard let h = dineHooks, dine.holding || dine.forkHeld else { return }
        let bp = sim.bodyPose(iterations: 3)
        let bpp = (centroid: bp.centroid, rotation: bp.rotation)
        if dine.forkHeld { h.holdFork(forkMatrix(sim: sim, pose: bpp)) }
        guard dine.holding else { return }
        var p: SIMD3<Float>
        if dine.flying {
            // the toss: a small arc from where the bite left to his mouth (which moves with the body); it stays in the mouth until it is swallowed
            let u = min(1, max(0, (dine.t - Self.tossFlick) / (Self.tossLand - Self.tossFlick)))
            let target = bodyPointWorld(DineGeometry.mouthRest, sim: sim, pose: bpp)
            p = dine.launch + (target - dine.launch) * u + SIMD3(0, Self.tossArc * 4 * u * (1 - u), 0)
        } else if dine.mode == .fork { return }
        else {
            p = bodyPointWorld(nubHoldRest(s: dine.armS), sim: sim, pose: bpp)
            if dine.phase == .grab { let q = h.piece(dine.k); p = q + (p - q) * smooth01(dine.t / Self.tGrab) }
        }
        // the flying piece shrinks over the last 20% of the arc: it goes INTO his mouth instead of covering his face
        var k: Float = 1
        if dine.flying { let u = min(1, max(0, (dine.t - Self.tossFlick) / (Self.tossLand - Self.tossFlick))); k = 1 - 0.6 * smooth01((u - 0.8) / 0.2) }
        let m = simd_float4x4(columns: (SIMD4(k, 0, 0, 0), SIMD4(0, k, 0, 0), SIMD4(0, 0, k, 0), SIMD4(p.x, p.y, p.z, 1)))
        if dine.mode == .fork { h.holdBite(m) } else { h.hold(m) }
    }

    /// World point of what he holds right now: the piece at the nub's tip, or the forkful on the tines.
    func heldPointWorld(_ sim: SoftBody) -> SIMD3<Float> {
        let bp = sim.bodyPose(iterations: 3)
        let pose = (centroid: bp.centroid, rotation: bp.rotation)
        if dine.mode == .fork {
            let m = forkMatrix(sim: sim, pose: pose)
            let g = SIMD3(m.columns.3.x, m.columns.3.y, m.columns.3.z), y = SIMD3(m.columns.1.x, m.columns.1.y, m.columns.1.z), z = SIMD3(m.columns.2.x, m.columns.2.y, m.columns.2.z)
            return g + z * DineGeometry.forkLength + y * DineGeometry.forkBiteLift
        }
        return bodyPointWorld(nubHoldRest(s: dine.armS), sim: sim, pose: pose)
    }

    /// Call after the last sim step of a frame: puts what he holds back on the nub for the pose the body actually has now (the body moves a
    /// few cm per fixed step in the straighten, so the pre-step transform would trail it).
    func refreshHeld(sim: SoftBody) {
        guard case .dine = script, dine.mode != .sip else { return }
        sendHeld(sim)
    }

    /// The sip: he tips his whole body until his mouth meets the tip of his own straw (hands-free), three gulps, a closed-eyes "ahh".
    func runSip(_ sim: SoftBody, _ skinner: Skinner, _ dt: Float) {
        guard let h = dineHooks else { return }
        dine.t += dt * dinePlan.pace
        var pose = ReachPose()
        var mouth: Float = 0, eyes: Float = 1, pulse: Float = 0
        dine.window = false
        let b = Self.dineBeat
        switch dine.phase {
        case .lean, .grab:
            if !dine.entered {
                dine.entered = true
                solveDineReach(sim, holds: { _ in DineGeometry.mouthRest }, target: h.straw(), crouch: 1.0)
            }
            pose = lerpPose(ReachPose(), dine.reach, MotionCurve.spring(dine.t / Self.tSipLean))
            if dine.t >= Self.tSipLean { dine.phase = .chew; dine.t = 0; dine.k = 0 }
        case .chew:                                     // the gulps
            pose = dine.reach
            let w = smooth01((dine.t - 0.08 * b) / (0.14 * b)) * (1 - smooth01((dine.t - 0.55 * b) / (0.2 * b)))
            mouth = w * 0.55
            dine.window = dine.t > 0.04 * b && dine.t < 0.78 * b
            pulse = MotionCurve.pulse((dine.t - 0.45 * b) / (0.5 * b))
            h.level(dinePlan.levelBase + dinePlan.levelSpan * (Float(dine.k) + smooth01(dine.t / b)) / Float(max(dine.total, 1)))
            if dine.t >= b {
                dine.k += 1; dine.bitesLeft -= 1; dine.t = 0
                if dine.k >= dine.total { h.level(dinePlan.levelBase + dinePlan.levelSpan); dine.phase = .straighten }
            }
        case .straighten:
            pose = lerpPose(dine.reach, ReachPose(), MotionCurve.spring(dine.t / Self.tStraighten))
            if dine.t >= Self.tStraighten { dine.phase = .happy; dine.t = 0 }
        case .happy:
            eyes = 0
            pulse = MotionCurve.pulse(dine.t / Self.tHappy)
            if dine.t >= Self.tHappy { dine.finished = true }
        }
        applyDine(sim, skinner, pose: pose, mouth: mouth, eyes: eyes, pulse: pulse)
        if dine.finished { dineDone(sim, skinner) }
    }

    /// The refusal (Full / Quenched): he stands at the tray and shakes his head "no" (a quick yaw wobble about the planted feet, the same twist channel
    /// the reach uses; arms stay at rest, feet attached), eyes squinted, one small squash at the end. Nothing is held, nothing eaten.
    func runRefuse(_ sim: SoftBody, _ skinner: Skinner, _ dt: Float) {
        dine.t += dt
        let T = Self.refuseDuration
        var pose = ReachPose()
        let env = smooth01((dine.t - 0.25) / 0.15) * (1 - smooth01((dine.t - (T - 0.55)) / 0.35))
        pose.twist = 0.42 * sinf(2 * .pi * 2.4 * max(0, dine.t - 0.25)) * env
        let eyes = 1 - 0.55 * env
        let pulse = MotionCurve.pulse((dine.t - (T - 0.6)) / 0.45)
        applyDine(sim, skinner, pose: pose, mouth: 0, eyes: eyes, pulse: pulse)
        if dine.t >= T { dine.finished = true; dineDone(sim, skinner) }
    }
    static let refuseDuration: Float = 1.9

    func dineDone(_ sim: SoftBody, _ skinner: Skinner) {
        dinePlan = DinePlan()
        skinner.setEyeOpenness(1); mouthOpen = 0
        skinner.browCounterOn = false
        if dine.forkHeld { dineHooks?.releaseFork(); dine.forkHeld = false }
        dineEnd(sim)
        postEvent(.ateTreat)          // (a friend may look over, hopeful; nobody leaves a spot)
        wantJoy()                     // a meal finished: a jump for joy once the meal lock is off
        finishScript(sim, after: true)
    }

    func dineEnd(_ sim: SoftBody) {
        armActive = false
        sim.targets.removeAll()
        sim.restoreStiffness()
        clearSkinOverride()
        armS = 0; dine.armS = 0
        armPathName = ArmPath.wave.name
    }


    /// Phase of the STRIDE: 0 at the left foot's contact, 0.5 at the right foot's (continuous across steps), from the step clock.
    var stridePhase: Float {
        let sf = feet.swingFrac * 0.5
        let base: Float = feet.side == 0 ? 1 - sf : 0.5 - sf
        var p = base + 0.5 * feet.stepU
        p -= floorf(p)
        return p
    }

    // MARK: touch play: held-up excitement (BlobBrain+Touch.swift drives it)

    var excitedScratch: [[SIMD3<Float>]] = [[], []]
    var excitedAO: [[Float]] = [[], []]
    private(set) var excitedOn = false

    /// While he is held he is happy: his feet dangle and swing softly (both together, a hair out of step, like legs hanging from one hip) and
    /// his arms lift a little (the wave-path arm override at a low, slowly swaying amount). Render overrides only: no sim targets, the walk
    /// itself is untouched. `level` 0...1, `phase` in radians (about 1 Hz). The feet are the body-rigid beans, so they cannot be left behind
    /// or pulled apart.
    func driveExcited(sim: SoftBody, skinner: Skinner, dt: Float, level L: Float, phase ph: Float) {
        guard attached, beanFirstIdx.count == 2 else { return }
        let pose = sim.bodyPose(iterations: 3)
        sim.attractor.anchor = pose.centroid; sim.attractor.rotation = pose.rotation; sim.attractor.squash = 1
        if !geom.valid { geom = FootGeom(sim: sim) }
        guard geom.valid else { return }
        prepareBeans(sim, skinner)
        if beanScratch[0].count != FootBean.vertexCount {
            beanScratch = [[SIMD3<Float>](repeating: .zero, count: FootBean.vertexCount), [SIMD3<Float>](repeating: .zero, count: FootBean.vertexCount)]
        }
        fillBeansRigid(sim, into: &beanScratch, tuck: 0)
        for s in 0..<2 {
            let w = sinf(ph - (s == 0 ? 0 : 0.5))
            let d = pose.rotation.act(SIMD3<Float>(0, 0.012 * L * w * w, 0.05 * L * w))
            for i in 0..<FootBean.vertexCount { beanScratch[s][i] += d }
        }
        footShift = [.zero, .zero]
        commitBeans(sim, skinner, dt, want: L > 0.02)
        if let kf = armKeyframes[ArmPath.wave.name] {
            var verts: [Int32] = [], dl: [SIMD3<Float>] = [], mat: [Float] = []
            for (i, side) in [-1, 1].enumerated() {
                let s = L * (0.20 + 0.025 * sinf(ph + (i == 0 ? 0 : 0.6)))
                kf.evaluate(side: side, s: s, rotation: pose.rotation, delta: &excitedScratch[i], ao: &excitedAO[i])
                verts += kf.side(side).vertices; dl += excitedScratch[i]; mat += excitedAO[i]
            }
            skinner.overrideVertices = verts; skinner.overrideDelta = dl; skinner.overrideMat = mat
            skinnerRef = skinner
        }
        excitedOn = true
    }

    /// The excitement is over: the arms go back to their rest skin (exactly), the beans are left to the walk's own hold-and-shrink.
    func endExcited() {
        guard excitedOn else { return }
        excitedOn = false
        clearSkinOverride()
    }

    // MARK: touch recovery

    func recover(_ sim: SoftBody, _ skinner: Skinner, _ dt: Float) {
        recoverT += dt
        if gaitRecover {
            gait.tick(sim, held: false, reduce: false)
            if !gait.isBusy { settleDone(sim) }
            return
        }
        let pose = sim.bodyPose(iterations: 6)
        let calm = sim.kineticEnergy() / sim.totalMass < 0.03 && sim.minY() < 0.04
        calmT = calm ? calmT + dt : 0
        if calmT > 0.5 || recoverT > 6 {
            gait.home = SIMD2(pose.centroid.x, pose.centroid.z)
            gait.facingYaw = yaw
            if pose.tilt > 0.5 {
                gaitRecover = true
                gait.returnHome(sim)
                if !gait.isBusy { settleDone(sim) }
            } else { settleDone(sim) }
        }
    }

    func settleDone(_ sim: SoftBody) {
        let pose = sim.bodyPose(iterations: 8)
        gait.home = SIMD2(pose.centroid.x, pose.centroid.z)
        gaitRecover = false
        activity = .idle
        script = .none
        poseW = 0
        restTimer = rand(1.0, 2.0)
        currentPose(sim)
    }
}

private extension Float {
    func clamped(_ a: Float, _ b: Float) -> Float { Swift.min(b, Swift.max(a, self)) }
}

/// The behaviour-side perks of one brain (set by GameCare from the Jelly's JellyPerks).
struct PerkFlags: Equatable {
    var bouncy = false, social = false, bedtime = false
}
