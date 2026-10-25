> **Feature lock (2026-10-25):** Jelbies 1.0 is the first release; no new features, fixes and polish only. See [RELEASE-1.0.md](RELEASE-1.0.md).

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
- **Body-led reaching:** because the arms are short, every grab is done with the whole body. He turns toward the item and leans so the stubby arm gets there; the arm itself barely moves. Items stick to the nub, cartoon style: a piece of food (a berry, a pizza slice).
- **Mouth:** none normally. A mouth appears and opens/closes only while eating or drinking, then disappears completely.
- **Feeding (no bowls): a short little tray.** Tapping Feed makes a low tray pop in with a puff at a front spot, with one shared serving that's a little bigger for each extra Blob (like Nintendogs). Each Blob walks up to their place and tilts their whole body toward the tray so the stubby arm can reach. A piece sticks to the nub, then he straightens up and tosses it into his mouth, three pieces each. When everyone's done, the tray poofs away so the room stays clear. Foods: berries (3 berries each) and pizza (3 little slices each: crust edge, cheese, pepperoni). Feed offers two chips, Berries and Pizza; one tray at a time (Feed and Drink wait until it has poofed away). Calling him over mid-meal drops it: the tray poofs and he returns to rest.
- **Drinking (separate from eating): one drink, one straw per Blob.** Tapping Drink offers two chips, Water and Soda, and pops the tray in with that bottle: a pastel plastic water bottle with a label band, or a contoured pastel soda bottle with a label band and a few bubbles. Both have an open neck (no cap) with a bendy striped straw standing out of it. The bottle is a little bigger for each extra Blob and has a straw for each Blob: one straw now, three when there are three Blobs. Each Blob walks up to their straw, turns, tips the whole body so the mouth meets the straw tip, and sips hands-free, three gulps each (the level drops with each gulp, the mouth is open only while gulping). Then a happy "ahh" with closed eyes, and the tray poofs away.
- **Every food is tossed, no fork (2026-10-17, user decision: "he's going to throw food in his mouth with his stubby little arms"):** he leans to the plate, the piece (berry or pizza slice) sticks to his nub, he cocks the nub and flicks, and it arcs into his mouth. The fork eat style is retired: no catalogue food uses it and the leftover fork code is dead and unreachable.
- **Many foods and drinks:** there will be several of each, with different benefits. Each one is a catalogue entry (how it's eaten: tossed from the nub, or sipped; its 3D model; its benefits). All foods and drinks are consumed at the same rate: every food takes the same number of bites and the same time, and every drink the same gulps. Adding one needs no new animation, and the first versions ship berries and water.
- **Eating is a toss (2026-10-15, replaces "tilts toward that arm to bite it"):** the stub arm never reaches his mouth. He grabs the bite, cocks the arm, flicks it (under 0.15 s), the bite arcs into his mouth and he chomps. Every food ends in the toss; forks are gone.
- **Never through the tray (2026-10-16):** with one Blob, the floor is too narrow at the tray's depth for him to walk around it. So if he's in front of the tray spot or on it when Feed/Drink is tapped, he first walks to his place (0.25 behind it). He rests 0.45 s, then the tray pops in front of him. Calling him over while the tray is out poofs the tray first, then he comes. Untaken option: shift the tray sideways (|x| ≤ ~0.6) so he can visibly walk around it. With 2–3 Blobs the same rule applies to everyone (`Dining/DiningGroup.swift`, not wired into the app yet because the game has only Bob):
  - places are handed out in left-to-right order, so their paths don't cross;
  - each Blob walks to 0.25 behind his place with no tray out;
  - once all are clear they rest 0.45 s together, the tray pops, and they step up.
  - Measured over 18 start layouts: 0 of 44 paths hit the tray (32 of 44 before).
  - Tests: `TrayNav3Tests`.
- **Re-serving is capped:** if a meal is disrupted the tray re-serves at most twice (`GameCare.maxReserves = 2`). After that it poofs and he goes back to rest. A fresh Feed/Drink tap starts the count again. Tests: `ReserveBoundTests`.
- **Straws:** one Blob = a single straw slanted sideways so you can see him drink; two or three Blobs = the centre straw up and the side straws long and horizontal. The tray is 17 % wider for two or three Blobs.
- **On his own:** when you're not interacting, he wanders, looks around, steps in place, hops, spins, rolls and waves, plus the room-life specials below.

## Motion rework (feet-first gait, measured from the references)
Numbers are measured at 24 fps from `docs/reference/blob_reference_video.mp4` (REF1: steps in place and the wave) and `docs/reference/blob_walk_reference.mp4`
(REF2: walking and turning). H = 1.3458 world units (body height). Implemented in `BlobBrain` / `BlobMotion` (`FootGait`, `FootGeom`, `WaveScript`) / `SoftBody.pivotAnchor`.
- The pose pivots on his FEET (`pivotAnchor`: the middle of both soles, or one planted foot for the wave) instead of the centroid, so tipping back / leaning never floats him.
- Every foot is a world-space target: planted feet are held where they landed (no skating, slip <= 5 % of stride), the swing foot follows a lift arc (+ sideways swing, toe-up tilt).
  Travel comes from the steps (single-step length x 3.75 steps/s); he always stops in double support (the last step is shortened and lands square).
- Walk: 3.5 steps/s (was 3.2; with the step length 0.27 -> 0.305 u that is ~20 % faster ground speed, measured 0.85 -> 1.02 u/s, 2026-10-16 user request), swing 0.24 s (40 % of a foot's cycle), lift ~0.12 H, waddle / bob / rock in phase with the steps, arm nubs counter-swing (render override, outward only), tip-back kept toward the camera.
- Turns: 1.9 rad/s with one step per 0.29 s (1/3.5; same 1.9 rad/s). March on the spot: 2 steps/s, first lift 0.085 H.
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
  - a single press-hold (or slide) = pet, never a pick up;
  - **double-tap and hold on him = pick up** (second touch-down within 0.30 s and 40 pt of a tap-up on him, then held 0.15 s or dragged; empty space is still the voice double-tap-hold). Drag to carry, flick to throw. The in-focus hint reads "Rub to pet · double-tap & hold to pick up · flick to throw". Once picked up: **Calm and happy (2026-10-16, replaces the arm-flapping "excited" pick-up, which read as freaking out):** closed happy eyes, a gentle 1 Hz sway, feet kept level and together, a small arm lift and a warm haptic swell. A dragged Bob stays within ±0.18 u of the focus spot.
  - flick faster than 900 pt/s = throw. **Bounce and quick return (2026-10-16):** he bounces 2–3 times (a typical throw can land on just one floor bounce; wall hits count too). In focus mode, invisible soft walls at the frame edges keep his whole body in the picture: a wall hit squashes him and thumps. Then he rights himself in 0.4 s and runs back to the spot. A typical throw settles in ≤ 3.2 s and a far one in ≤ 4.5 s.
  - **Love hearts:** while he's petted or held happily, bare pink hearts (no cloud, no bubble; 28–44 pt, a soft shadow and a slightly deeper pink edge) pop up beside his head every 0.6–1 s, alternating left and right, and float up ~75 pt with a gentle side sway, a slight scale pop-in and a fade-out. They stay inside the safe area, below the status bar and clear of "Let Bob go". There are no grumpy hearts.
  - **Pinch is guarded:** the cheek spring is sub-stepped and its offset is capped, so a pinch can never blow up the mesh.
  - **Pet dent:** while a finger presses him, the skin normals are softened so the dent reads as a smooth dimple, not a dark crease.
  - There is no bounce gesture (removed: "it's not doing anything").
- **Jelly (2026-10-16, "lean into the jelly aspect"):**
  - On let-go, haptic pulses follow his squash-and-wobble peaks (within ~20 ms), so the release feels like jelly settling.
  - Walking and running add a very slight render-only jiggle (`JellyJiggle.swift`, about 1.7 % H; jacks and hops about 2.8 % H). There is a footfall squash, a crown sway and a small twist. The feet and the lower 10 % of his height never move, and it snaps to exactly zero when he's still. The locked walk is unchanged underneath.
- **Grumpy touch:** when a need is wanting he leans away, squints, does a short "hmph", and the haptic is stiff and short with no purr. Petting still helps when attention is the need. See Emotions.md.

## Room life (idle specials, 2026-10-16)
- **Schedule:** one special roughly every 15–30 s while roaming, picked by mood and never the same one twice in a row:
  - happy: run, jumping jacks, zoomies, belly slide, hop-scoot, look;
  - okay: sit, look, yawn, hop-scoot;
  - grumpy: slump.
- **Interruptions:** every special stops within 0.3 s for Come here, Feed/Drink, focus or a touch, and each one ends at rest.
- **Run:** the locked walk sped up: ×1.35 speed, ×1.2 stride, a 5° lean, ×1.3 arm sweep. A short dash across the rug, then he slows back to the walk.
- **Speed and jiggle (Build B, 2026-10-17, "a little faster, jiggle a little more"):** step rate 3.5 -> 3.75 steps/s (stride unchanged, so the low feet and the tray navigation are untouched): measured walk 1.016 -> 1.144 u/s, run 1.350 -> 1.435 u/s (ground speed steps in whole sim frames of step time, so the numbers jump rather than scale; run cadence still ×1.125, run / walk now ×1.25). JellyJiggle is about 1.7× stronger on a footfall (impulse 1.4 -> 2.4, caps 0.022 -> 0.038 H, run caps ×2.2 instead of ×1.9), the crown sways more on start / stop, and a dead stop from a walk or run gives one settle wobble (a squash ripple), all still render-only and zero at rest.
- **Zoomies (`.zoomies`):** a fast dash (cadence +20 % on top of the run, about +12 % faster; more bob or sway pulls the planted feet off the belly, so the wobble is all in the stop and the jelly), then a dead stop with a big jelly wobble (squash pulses, a side-to-side rock, a quick twist, a jelly kick) that dies out in under a second. Body-led: the arms stay thumbs.
- **Belly slide (`.slide`, `GaitDriver.slide`):** a run (2.6–4.4 u) that, about 1 u before its goal, dives forward (37° pitch, crown leading, squash 0.92), slides about 0.9 u decelerating from the run's speed, peels up with a little hop, and wobbles to rest (~1.7 s). The feet stay in the body frame under him; arms are thumbs.
- **Hop-scoot (`.scoot`):** 3–5 quick little bunny hops (0.34 u each, apex 0.07 u, 0.4 s per hop) toward a spot 1.3–2 u away, thumb arms flapping a little. It uses the hop exception only.
- Frequency: the new moves share the same 15–30 s special schedule (about a third of the happy mood's picks, never twice in a row); capture aid `-RunMove zoomies|slide|scoot` makes the scheduler pick that one every ~3 s, and `-BlobDemo`/`-BlobGameDemo izoomies|islide|iscoot` run them directly. Tests: `RunMoveTests`, `FeetAttachTests`, `ArmCapTests`.
- **Stumble (about 1 in 3 long runs):** a stubbed step, a lurch forward with the arms flung out, two quick catching steps, an embarrassed shake, then he walks on. One foot always stays down; a real fall is a later exception.
- **Backflip (voice trick "flip", `BlobBrain+Flip.swift`, GaitDriver `.flip`):** on the spot, built on the hop machinery. Crouch 0.16 s (squash 0.76, arms down), then air with the hop's gravity (12.4 u/s²): apex 0.42 u roaming (0.52 s) or 0.28 u in focus (0.43 s, stays in frame). One full 360° backward pitch about his centre of mass, slow-fast-slow (40 % smoothstep, 60 % linear), done just before touch-down, arms out in the air, stretched at take-off and tucked through the turn. Landing: squash 0.74 with a quick rebound and the JellyJiggle landing wobble, then a 0.35 s "covers it" shake (tiny pitch and squash wobble), then exact rest. Total about 1.2 s, no travel (under 0.05 u), feet only leave the floor in the air. Focus-warm haptics: a light tick at take-off, a strong soft thump on landing. No player input: the shot meter (timing bar) was removed 2026-10-17 on user request; the flip plays crouch, flip, land by itself, or the faceplant variant (see AIFeatures.md for when). Tests: `FlipTests`.
- **Jumping jacks:** 4–6 reps of two small hops each (arms up and feet apart, then arms down and feet together), using the hop exception. Then a satisfied little bounce. The arms stay stubs.
- **Sit and relax:** he turns slightly off camera, puts his feet forward and squashes down. Half-closed eyes, a slow breathing pulse and a sway for 6–12 s, then he gets up.
- **Slump (grumpy):** the same sit, but turned about 34° away and leaning forward, with heavier lids. Pairs with the thought bubble. There are no lowered brows yet: the skinner has no brow-lowering control.
- **Look around:** a stepped turn toward something, with a curious tilt and nod, then he turns back.
- **Yawn-stretch:** arms up, the body stretches about 15 %, eyes squeezed. The mouth opens only for the yawn, then is gone again.
- Code: `BlobBrain+Idle.swift`. Tests: `IdleBehaviourTests`.

## 1.0 updates (2026-10-25)
- **Social moves:** chest bump, purr together, nuzzle, twirl, follow-the-leader, high-five (mostly in the Park).
- **Sleep fidgets:** shifts, side rolls, drifting toward sleeping friends, dream twitches, half-wakes, stronger breathing.
- **Volleyball body hits:** head bonk, belly-flop spike and belly dig (arms stay stubby).
- **Leg attachment:** feet follow the fitted body pose, so legs never come off in flips, cartwheels or rolls.
- **Hat crown fit:** the crown is fitted to the drawn skin each frame; the brim stays on the head in stretch and squash.
