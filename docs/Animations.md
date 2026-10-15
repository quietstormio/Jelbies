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
- **Body-led reaching:** because the arms are short, every grab is done with the whole body. He turns toward the item and leans so the stubby arm gets there; the arm itself barely moves. Items stick to the nub, cartoon style: a piece of hand food, a fork, or a drink bottle.
- **Mouth:** none normally. A mouth appears and opens/closes only while eating or drinking, then disappears completely.
- **Feeding (no bowls):** tapping Feed makes a little table, chair and plate pop in with a puff at a front spot. He walks over, hops up and stands on the chair, eats (reach, bite, chew), hops down with a happy bounce, and the set poofs away so the room stays clear (like the Nintendogs bowl). The first version has one hand food (berries) and one fork food (a cake slice).
- **Water (separate from eating):** wherever he's standing, a water bottle poofs into his hand and sticks to one nub. A bendy straw reaches his mouth, since his arm is too short to bring the bottle there. He tips back a little, gulps a few times, gives a happy "ahh" squint, and the bottle poofs away. If he's mid-meal, the drink waits until he's done.
- **Hand foods vs fork foods:** each food says how it's eaten.
  - **By hand** (berries, cookies): he leans toward the plate, the piece sticks to his nub, and he straightens up and tips toward that arm to bite it.
  - **With a fork** (pasta, cake): a fork pops into his nub along with the plate. He leans in to stab a bite, then straightens up and tips toward the fork to eat it. The fork poofs away with the table set.
  - Both styles use the same reach, the same bite rhythm and the same number of bites.
- **Many foods and drinks:** there will be several of each, with different benefits. Each one is a catalogue entry (how it's eaten: by hand, with a fork, or sipped; its 3D model; its benefits). All foods and drinks are consumed at the same rate: every food takes the same number of bites and the same time, and every drink the same gulps. Adding one needs no new animation, and the first versions ship berries and water.
- **On his own:** when you're not interacting, he wanders, looks around, steps in place, hops, spins, rolls and waves.
