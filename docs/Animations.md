# Blob Animations (from the reference video)

Reference: 10 s clip of the Blob (frames at 2 fps in `docs/reference/video_frames/`). Rubbery, cartoon-y limbs that stretch; soft-body jelly body squashes and sways.

| Animation | What happens in the reference |
|---|---|
| Idle / step in place | Lifts one foot forward, then the other, with a small side-to-side waddle of the body. |
| Turn around | Turns a full circle on the spot with small steps; arms stay tucked at the sides. |
| Point / stretch | Stretches one arm straight out sideways, the arm lengthening into a long tube. |
| Look around | Turns body/head a little to each side; eyes glance left and right; brows tilt a few degrees. |
| Content / sleepy eyes | Eyes close into soft arcs (happy, relaxed), brows lift slightly. |
| Walk | Side-on steps, alternating feet, body bobbing. |
| Wave | Raises one arm straight up above the head (stretches to roughly 0.6–0.7 × body height), body leans toward that side, then waves; eyes look up/sideways; ends with happy closed eyes, then back to neutral. |

Implementation notes: arms and feet need to be poseable (driven sim particles / attractor targets) while staying smooth rounded tubes blended into the body; eyes need gaze offset + openness (closed-arc) + brow rotation.

## One animation style (user: "Ensure the animation style is consistent")

Every action, current and future, follows the same rules:

- **Rubbery and bouncy.** Each action has a small anticipation (dip or squash), the move, and a springy overshoot as it settles. All actions share the same spring and easing curves; don't invent new ones per action.
- **One tempo.** Repeated beats (wave swings, steps, bites, gulps) run at about 1.5 per second.
- **The body leads.** He leans and turns first. The arms stay stubby and only move a little, and the feet take small steps.
- **Same squash everywhere.** Landings (hopping onto the chair or down from it), bites and gulps all use the same small squash pulse.
- **Same face language.** Pleased moments use the same happy squint (end of the wave, after eating, the "ahh" after drinking). The mouth shows only while eating or drinking, and blinks keep going throughout.
- **Same props behaviour.** Everything that appears or disappears (table and chair, plate, bottle, future toys) uses the same puff and springy pop. Things he holds stick to his nub.
- **Always back to rest.** Every action ends with his body back in its exact locked rest shape.

## In the game (user decisions, 2026-10-14)

The video is the motion reference, but the game keeps Bob's locked body:

- **Arms stay stubby** in every animation. The video stretches the arm into a long tube; the game never does.
- **Wave:** the short, thick arm rises from high on the side and swings between straight out and up about three times (~1.5 Hz), tip at about head-top height. The body leans away from the arm with a small bounce and a happy squint, then the arm settles back to its exact rest shape. Target pose: `reference/wave_reference_back_view.jpg`.
- **Body-led reaching:** because the arms are short, every grab is done with the whole body. He turns toward the item and leans so the stubby arm gets there; the arm itself barely moves. Items stick to the nub, cartoon style: a piece of hand food or a fork.
- **Mouth:** none normally. A mouth appears and opens/closes only while eating or drinking, then disappears completely.
- **Feeding (no bowls): a short little tray.** Tapping Feed makes a low tray pop in with a puff at a front spot, with one shared serving that's a little bigger for each extra Blob (like Nintendogs). Each Blob walks up to their place and tilts their whole body toward the tray so the stubby arm can reach. They pick up a piece, or a fork poofs into the hand (a small puff at the nub) and they stab a bite, then straighten up and eat, three bites each. When everyone's done, the tray poofs away so the room stays clear. The first version has one hand food (berries) and one fork food (cake). Feed offers two chips, Berries and Cake; one tray at a time (Feed and Drink wait until it has poofed away). Calling him over mid-meal drops it: the tray poofs and he returns to rest.
- **Drinking (separate from eating): one drink, one straw per Blob.** Tapping Drink offers two chips, Water and Soda, and pops the tray in with that bottle: a pastel plastic water bottle with a label band, or a contoured pastel soda bottle with a label band and a few bubbles. Both have an open neck (no cap) with a bendy striped straw standing out of it. The bottle is a little bigger for each extra Blob and has a straw for each Blob: one straw now, three when there are three Blobs. Each Blob walks up to their straw, turns, tips the whole body so the mouth meets the straw tip, and sips hands-free, three gulps each (the level drops with each gulp, the mouth is open only while gulping). Then a happy "ahh" with closed eyes, and the tray poofs away.
- **Hand foods vs fork foods:** each food says how it's eaten.
  - **By hand** (berries, cookies): he leans toward the plate, the piece sticks to his nub, and he straightens up and tips toward that arm to bite it.
  - **With a fork** (pasta, cake): when he reaches his place a small puff pops at his nub and the fork appears stuck to it, tines up (the same pop as the tray; there is no fork on the tray). He leans in to stab a bite, then straightens up and tips toward the fork to eat it, three bites. The fork poofs away with the tray.
  - Both styles use the same reach, the same bite rhythm and the same number of bites.
- **Many foods and drinks:** there will be several of each, with different benefits. Each one is a catalogue entry (how it's eaten: by hand, with a fork, or sipped; its 3D model; its benefits). All foods and drinks are consumed at the same rate: every food takes the same number of bites and the same time, and every drink the same gulps. Adding one needs no new animation, and the first versions ship berries and water.
- **Eating is a toss (2026-10-15, replaces "tilts toward that arm to bite it"):** the stub arm never reaches his mouth. He grabs the bite, cocks the arm, flicks it (under 0.15 s), the bite arcs into his mouth and he chomps. Hand foods and fork foods both end in the toss; the fork still poofs into the hand. The fork flow is parked ("Maybe all food is hand food").
- **Straws:** one Blob = a single straw slanted sideways so you can see him drink; two or three Blobs = the centre straw up and the side straws long and horizontal. The tray is 17 % wider for two or three Blobs.
- **On his own:** when you're not interacting, he wanders, looks around, steps in place, hops, spins, rolls and waves, plus the room-life specials below.

## Motion rework (feet-first gait, measured from the references)
Numbers are measured at 24 fps from `docs/reference/blob_reference_video.mp4` (REF1: steps in place and the wave) and `docs/reference/blob_walk_reference.mp4`
(REF2: walking and turning). H = 1.3458 world units (body height). Implemented in `BlobBrain` / `BlobMotion` (`FootGait`, `FootGeom`, `WaveScript`) / `SoftBody.pivotAnchor`.
- The pose pivots on his FEET (`pivotAnchor`: the middle of both soles, or one planted foot for the wave) instead of the centroid, so tipping back / leaning never floats him.
- Every foot is a world-space target: planted feet are held where they landed (no skating, slip <= 5 % of stride), the swing foot follows a lift arc (+ sideways swing, toe-up tilt).
  Travel comes from the steps (single-step length x 3.2 steps/s); he always stops in double support (the last step is shortened and lands square).
- Walk: 3.2 steps/s, swing 0.25 s (40 % of a foot's cycle), lift ~0.12 H, waddle / bob / rock in phase with the steps, arm nubs counter-swing (render override, outward only), tip-back kept toward the camera.
- Turns: 1.9 rad/s with one step per 0.31 s. March on the spot: 2 steps/s, first lift 0.085 H.
- Wave (2.0 s): arm s(t) from the video (raise 0.33 s, then 2.02 Hz swings), lean away pivoting on the far foot, arm-side foot lifted to 0.17 H and held, eyes shut fully for 0.10 s (t = 0.33) and 0.12 s (t = 1.52), no bounce, faces the camera within 5 deg.
- Hop: crouch 0.13 s, air 0.26 s (apex 0.10 u, feet tucked), landing squash 0.80 then a 5 Hz jiggle; the only action that may have both feet off the floor.
- Tests: `Motion*Tests` (grounded, facing, slip, gait, wave shape, hop, perf).

## Focus mode and touch (2026-10-16)
- **Come here = focus mode.** He walks to the front, and the camera springs in. "Let Bob go" (top-left) is the only way out; he then wanders off and the camera eases back.
- **Select:** with two or three Blobs, double-tap one (or tap its card in the roster). An outline draws from the top centre down both sides and meets at the bottom with a spark, then glows; the action button appears. Picking another Blob restarts the draw on the new one.
- **Gestures (no tabs):**
  - one-finger slide = pet (closed eyes, lean-in, purr);
  - tap = a zone poke;
  - two-finger pinch on him = squeeze his cheeks (skin offset, no creases);
  - hold 0.25 s and drag up = pick up: he flaps his arms and kicks his legs, excited;
  - flick faster than 900 pt/s = throw. After 2 s untouched he gets up and walks back to the focus spot.
  - There is no bounce gesture (removed: "it's not doing anything").
- **Grumpy touch:** when a need is wanting he leans away, squints, does a short "hmph", and the haptic is stiff and short with no purr. Petting still helps when attention is the need. See Emotions.md.

## Room life (idle specials, 2026-10-16)
- **Schedule:** one special roughly every 15–30 s while roaming, picked by mood and never the same one twice in a row:
  - happy: run, jumping jacks, look;
  - okay: sit, look, yawn;
  - grumpy: slump.
- **Interruptions:** every special stops within 0.3 s for Come here, Feed/Drink, focus or a touch, and each one ends at rest.
- **Run:** the locked walk sped up: ×1.35 speed, ×1.2 stride, a 5° lean, ×1.3 arm sweep. A short dash across the rug, then he slows back to the walk.
- **Stumble (about 1 in 3 long runs):** a stubbed step, a lurch forward with the arms flung out, two quick catching steps, an embarrassed shake, then he walks on. One foot always stays down; a real fall is a later exception.
- **Jumping jacks:** 4–6 reps of two small hops each (arms up and feet apart, then arms down and feet together), using the hop exception. Then a satisfied little bounce. The arms stay stubs.
- **Sit and relax:** he turns slightly off camera, puts his feet forward and squashes down. Half-closed eyes, a slow breathing pulse and a sway for 6–12 s, then he gets up.
- **Slump (grumpy):** the same sit, but turned about 34° away and leaning forward, with heavier lids. Pairs with the thought bubble. There are no lowered brows yet: the skinner has no brow-lowering control.
- **Look around:** a stepped turn toward something, with a curious tilt and nod, then he turns back.
- **Yawn-stretch:** arms up, the body stretches about 15 %, eyes squeezed. The mouth opens only for the yawn, then is gone again.
- Code: `BlobBrain+Idle.swift`. Tests: `IdleBehaviourTests`.
