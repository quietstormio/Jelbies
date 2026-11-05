# Contact emotes: catalogue, stance distances, sounds, and the BEFORE measurements

Branch `g-contactcat` (from `g-perfint` 5a3a7b1), 2026-11-02. READ-MOSTLY: no behaviour code changed. The contact engine (`ContactProfile` / `ContactSettle`, worker g-featclip) migrates the
entries below; the harness that measures them is `BobV1Tests/ContactPolishTests.swift`, the ground truth it uses is `BobV1/Melon/ContactMetric.swift`.

Goal (the user): every emote where Jelbies touch must READ as touching and never overlap ("not like a buggy game"); the touch sounds and haptics must keep firing.

## 0. Units and the numbers every entry is built from

- 1 u = 1 m. `MelonController.jellyGap = 1.4` (Melon/MelonStage.swift:393) = every brain's `peerGap` (MelonStage.swift:417; the Park's visitors get it too, same `wireRoster`).
- A standing Jelbie is about 1.4 wide side by side (measured touch distance 1.405, section 5.2; `BobForm.halfW` 0.5836 x 2 = 1.167 is the fitted egg, not the drawn skin with its arm nubs), 1.08-1.29 front to back. The harness measures the touch distance per species pair and axis (`static_spacing.tsv`).
- `skinGap(a, b)` = root distance minus touch distance (m): +0.01 = 1 cm apart, 0 = touching, negative = overlap.
- Stance classes. TOUCHING: the pair should settle to skin gap 0 +- 0.5 cm (the bodies visibly meet; sound + haptic fire once per touch). PROXIMITY: skin gap >= 0 only (they stand close, never overlap).
- Species features that matter: Pearl + Lavender = wings (sideways/back, flap), Pip = tail + spikes (back, low), Moss = daisy (head), Teddy = ears + pom (head, wide) + cream belly, Bob = none.
  Everybody has the W1d short capsule arms (stubby, hang at the sides: the arms are what reach the neighbour first in a side-by-side stance).

### 0.1 Global mechanisms that set or fight a stance distance

| Mechanism | Where | Number |
|---|---|---|
| Room peer spring `keepApart` (a continuous partial push, floors at `softFloor` of the gap) | Melon/MelonStage.swift:481-497 (`softPush 0.6`, `softFloor 0.78`) | gap 1.4 -> floor 1.092; `gap` param: close social 1.036, dining 0.7 (`groupGap`), focus row 1.0 |
| Close-social gap factor (used by `socialGap`, `fixed`/`closeFixed` spots, the Lab) | Melon/BlobSocial.swift:94 `closeGapFactor 0.74`; applied BlobSocial.swift:226-229 (`socialGap`), MelonStage.swift:450 | 0.74 x 1.4 = 1.036 (BELOW the 1.405 touch distance: the spring itself lets two plain bodies overlap by ~37 cm) |
| Group-session steering gap | BlobSocial.swift:227 | 0.6 x 1.4 = 0.84 |
| Look-ahead side-step (walkers curve round a peer) | Melon/BlobBrain+Contact.swift:60-107 (`clear = peerGap * 0.97`, scale 0.8 on a narrow floor) | 1.358 / 1.087 |
| Soft meeting squish when two bodies press while walking | Melon/BlobBrain+Contact.swift:19-26 (`ContactTuning.contactFrac 0.97`, `cooldown 1.6`), `contactTick` :124-137 | fires at root distance < 1.358 and closing; `jellyKick` 0.9..1.8 + `.squish` vol 0.25 (AudioHub.play, :135); NO haptic; only when neither is in a social |
| Feature push-out (wings, spikes, tail, ears, arms drawn inside another body get pushed to its surface, bodies untouched) | Melon/FeatureClip.swift (`margin 4 mm`) | render side only: hides feature overlap, never moves a body |
| Lying/flop placement (walk to the spot where two flat bodies just touch) | Melon/BlobBrain+LieClear.swift:17-45 (`lieTouchCentroid 1.235`, `lieTipShift 0.09`, `eggBias -0.07`) | 1.235 + 0.09 x (cos + shift) |
| Lineup (who takes which slot; walks never cross) | Melon/Lineup.swift (`commitDistance 1.0`, `period 0.25`, `hysteresis 0.4`) | assignment only, no distance |

## 1. Pair socials (`SocialKind`, sessions of two; start = `socialStart*`, drive = `drive*`)

All distances are the ROOT distance the walker is sent to (`centre gap = factor x peerGap 1.4`). `sideSpot(of:gap:)` = Melon/BlobSocial+Play.swift:24 (a spot beside the partner on the side nearer the walker,
`closeFixed` = the floor rules with the close-social spring, BlobSocial+Friends2.swift:33). Class in brackets: T touching, P proximity. "snd/hap" = what fires today (file:line).

| # | Emote | Stance set at | Root distance | Class | Features that matter | Sound / haptic today |
|---|---|---|---|---|---|---|
| 1 | boop | BlobSocial.swift:325-328 (`gap = peerGap`, `fixed(you + away*gap)`) | 1.40 | T (the bump, phase 2) | arms, ears | NO sound. kick 1.8/2.6 + `.boop` event (heart; haptic only in focus mode, MelonStage.swift:426-429) BlobSocial.swift:730-731 |
| 2 | squabble | BlobSocial.swift:325-328 (same spot as boop), shoves :765-770 | 1.40 | T (shoves) | arms | NO sound. kick 1.4/2.4 + `.shove` event (focus-mode haptic 0.22, MelonStage.swift:431) :769-770; makeUp kick 1.6 + `.makeUp` :811-812 |
| 3 | bump (belly bump) | BlobSocial+Play.swift:86-87 (`you + away*peerGap*0.92`) | 1.29 | T | belly, ears | boop sound vol 0.9 (Play.swift:235); kick 2.8 both + `.boop` :233-234; no emote haptic |
| 4 | nuzzle | BlobSocial+Play.swift:78 (`sideSpot gap peerGap*0.95`) | 1.33 | T (heads lean together) | ears, wings, daisy (heads) | NO sound; kick 1.0 + `.boop` (isA only) Play.swift:206-207 |
| 5 | sitTogether | BlobSocial+Play.swift:78 (same) | 1.33 | T (sit side by side) | arms, wings, tail | NO sound (sit settle only) |
| 6 | sneak | BlobSocial+Play.swift:93 (`behindSpot gap peerGap*0.92`) | 1.29 | T (the boop from behind) | tail/wings (behind!), ears | boop sound 0.9 Play.swift:275 + kick 1.6/3.0 + `.boop` :273-274; jump sound :282 |
| 7 | chestBump | BlobSocial+Friends.swift:86-91 (`gapK 0.78`, `you + away*peerGap*gapK`, `closeFixed`) | 1.09 | T (bellies meet at the hop top, twice) | belly, ears, arms | squish 0.9 (Friends.swift:178) + kick 3.0 + `.boop` :176-177; no emote haptic |
| 8 | highFive | BlobSocial+Friends.swift:81 (`sideSpot gap peerGap * EmoteTuning.highFiveGap`); `highFiveGap 1.05` BlobSocial+Emotes.swift:24 | 1.47 | T (cheeks bump, they lean in) | arms (old nub reach removed), ears, wings | `highfive_boop` 0.85 (Friends.swift:229) + `emoteHaptic("highFive.bump", tap)` :230 + kick 2.8 + `.boop` :227-228 |
| 9 | hum | BlobSocial+Friends.swift:86-91 (`gapK 0.82`) | 1.15 | T (heads lean in) | ears, wings, daisy | NO sound/haptic (kick 0.7 on the sway, :261); chirp + `.makeUp` :265-266 |
| 10 | cheekSquish | BlobSocial+Friends.swift:81 (`sideSpot gap peerGap*0.9`) | 1.26 | T (two presses) | ears, wings, arms | squish 0.7 (Friends.swift:293) + kick 1.5 + `.boop` (first press) :292-294; wobble 0.5 :310 (second); no haptic |
| 11 | twirl | BlobSocial+Friends.swift:86-91 (`gapK 1.1`) | 1.54 | P (each spins once, bow) | wings/tail/ears when spinning (swept radius) | chirps only (no contact sound) |
| 12 | hopAlong | BlobSocial+Friends.swift:81 (`sideSpot gap peerGap*1.0`) | 1.40 | P | wings, ears | none |
| 13 | littleRace | BlobSocial+Friends2.swift:62 (`peerGap * Friends2Tuning.raceLane`), :24 `raceLane 1.05` | 1.47 | P (two lanes) | none | zoomies sound :163 |
| 14 | tag | BlobSocial+Friends2.swift:71-74 (`gapK faceGap 0.76`), catch spot :237 (`peerGap*faceGap`) | 1.06 | T at each catch | arms, tail | boop 0.9 (Friends2.swift:221) + kick 1.2/2.6 + `.boop` :219-220 per catch (3) |
| 15 | leapfrog | BlobSocial+Friends2.swift:62 (`peerGap*0.85`) | 1.19 | P (one flat, the other hops over) | everything while one is lying flat (wider!) and the hop passes over | none (jump/chirp) |
| 16 | peekaboo | BlobSocial+Friends2.swift:85 (`you - u*peerGap*0.95`, behind from the camera) | 1.33 | P (one hides behind the other) | tail, wings (the hider's back is toward the camera) | chirps only |
| 17 | bellyBounce | BlobSocial+Friends2.swift:62 (`peerGap * sideGap 0.82`; :23) | 1.15 | T (lean in, squish, bounce apart, twice) | belly, arms, wings | squish 0.9 (Friends2.swift:370) + kick 3.0 + `.boop` :368-369; chirp |
| 18 | mirrorDance | BlobSocial+Friends2.swift:71-74 (`faceGap 0.76`) | 1.06 | P (face to face, sway + hop) | wings, ears (hop) | kick only (:537) |
| 19 | noseBoop | BlobSocial+Friends2.swift:71-74 (`gapK 0.68`) | 0.95 | T (one leans in and boops the face) | ears, daisy, wings | boop 0.8 (Friends2.swift:433) + `.boop` + `.makeUp` :430-432; booped kick 2.2. Root distance 0.95 is the CLOSEST stance in the game (touch distance 1.405) |
| 20 | backToBack | BlobSocial+Friends2.swift:62 (`sideGap 0.82`) | 1.15 | T (backs touch, sway) | TAIL, WINGS, spikes (backs touch!) | NO sound; kick 1.0 + `.boop` :460-461; chirps |
| 21 | cuddleLean | BlobSocial+Friends2.swift:62 (`sideGap 0.82`) | 1.15 | T (lean on each other) | arms, ears, wings | squish 0.5 (Friends2.swift:489) + kick 1.2 + `.boop` :487-488 |
| 22 | ringAround | BlobSocial+Friends2.swift:71-74 (`gapK 0.72`) | 1.01 | T (face to face, close, they spin together) | wings/tail/ears swing | NO sound; boop? none; chirps :535-537, kick 0.6 |
| 23 | swayHug | BlobSocial+Friends3.swift:26 (`sideSpot gap peerGap*0.80`) | 1.12 | T (side hug that sways) | arms, wings, ears | squish 0.55 (Friends3.swift:81) + kick 1.6 + `.boop` + `.makeUp` :78-80; chirps |
| 24 | whisperGiggle | BlobSocial+Friends3.swift:26 (`peerGap*0.86`) | 1.20 | T/P (one leans to the other's ear) | ears, wings | chirps + kicks only (:166-172); no contact sound |
| 25 | danceOff | BlobSocial+Friends3.swift:34-37 (`peerGap*0.95`) | 1.33 | P | wings, tail (the dance) | chirp/kick |
| 26 | shyWave | BlobSocial+Friends3.swift:41 (starts at 2.3 < d < 5.2), then `planMeeting` BlobSocial+Friends3.swift:223 (`peerGap*0.76/2` each side of the middle) | 1.06 at the end | P (meet at the end) | none | chirps |
| 27 | spinHug | BlobSocial+Emotes2.swift:13 (`SpinHugTuning.gap 0.84`) + :19 `sideSpot`; ring radius 0.74..0.80 :13 | 1.18, then a ring of diameter 1.5-1.6 | T (cheeks press, turn once round) | wings, tail (swing round), ears | `emote_spinhug` 1.0 (Emotes2.swift:70) + kick 1.8 + `.boop` :68-69; treat haptics `spinHug.press` / `.step` (:115) / `.part` |
| 28 | follow | BlobSocial.swift:231 `followGap = max(1.15, peerGap + 0.15)` | 1.55 | P | none | none |
| 29 | line | Melon/BlobSocial+Play.swift:115 (guard `d > peerGap*0.8`), follow gap as `follow` | 1.55 | P | none | none |
| 30 | chase | Melon/BlobSocial+Play.swift:327-370 (tag bump at catch, spot :347 `to + u*(peerGap*0.95)`) | 1.33 at the tag | T (a soft bump at each catch) | arms, tail | boop 0.9 (Play.swift:369) + kick 1.4/2.8 + `.boop` :367-368 |
| 31 | keepAway | BlobSocial+Play.swift:401-455 (dodges; no stance) | varies | P | none | none |
| 32 | dance (jumping jacks) | BlobSocial+Play.swift:98-101 (no spot: they dance where they stand, d < 4.5) | wherever they were (>= close gap) | P | wings, ears, arms (jacks) | none |
| 33 | greet / look / zoomies | BlobSocial.swift:338-352 (greet d < 2.6, look d < 5.5); zoomies Play.swift:107 | n/a | P | none | zoomies sound; greet kick 1.2 (BlobSocial.swift:619) |
| 34 | pass (ball) | BlobSocial+Pass.swift:26-92 (kicker behind the ball; friend watches ~3-4 away) | > 2 | P | none | boop 0.7 at each kick (Pass.swift:91) |
| 35 | bagSit (beanbag) | BlobSocial+Pass.swift:41-60 (two pieces or one + the floor beside it) | by the decor (piece radius `DecorField` spec) | T when sharing (one on, one beside) | arms, tail | `beanbagSit` on the settle (BlobBrain+Decor.swift:350, :577; Sleep.swift:759) |
| 36 | cuddle (loveseat) | BlobSocial+Toss.swift (two cushions) | by the loveseat's two seats | T (they lean toward each other, `seatMotion`) | arms, ears | beanbagSit-style settle sound; the lean has none |

The "touching" classification above is by what the emote is for (the cheeks/bellies/sides visibly meet). Rows 7-10, 14, 17, 19-23, 27 are the ones the user will scrutinise first.

## 2. Group socials (3-5 Jelbies; `socialStartGroup`, BlobSocial+Group.swift:128)

| Emote | Stance set at | Chord / spacing (root) | Class | Features that matter | Sound / haptic today |
|---|---|---|---|---|---|
| groupHug (also the guest arrival's hug, Park/GuestArrival.swift:150-155 `socialStartGroup(.groupHug, ...)`) | BlobSocial+Group.swift:142-143, `GroupTuning.touch 0.78` (Group.swift:33), ring radius `max(chord/(2 sin(pi/n)), peerGap*0.4)` :93; steering gap 0.6 x (BlobSocial.swift:227) | 1.09 neighbours (n=3: ring radius 0.63; n=5: 0.93) | T (huddle: lean in, squish together, :251) | EVERYTHING: wings x wings, tail between two, ears, daisy | squish 0.7 (Group.swift:269) + 0.45 (:275), kick 2.0+0.3n/5 (:264), `.boop`+`.makeUp` (:266-267, :279), chirps :270, :274 |
| groupCheer | BlobSocial+Group.swift:142-143, `GroupTuning.loose 1.15` | 1.61 | P | wings, ears (jumps) | kicks 1.4+0.5r, chirps (:304-311) |
| circleDance | same call, `packed = true` (`kind != .groupCheer`) | 1.09 | T (a ring of hands-on-sides dancers) | wings, tail | kicks 0.9 on the beat, chirps (Group.swift:380-409) |
| conga (old, `.conga`) | BlobSocial+Group.swift:324-390 follows the leader at `followGap` | 1.55 | P | tail (the line behind), wings | kick, chirp |
| congaLine | BlobSocial+Emotes.swift:31 `congaGap 1.15` -> `gapBehind = peerGap*1.15` (:113), trimmed path :264 | 1.61 behind the one in front, along a curve | P (a line of waddlers; each follows ~1 gap behind) | tail, wings, spikes (the one behind sees them) | `conga_tick` 0.5 on the beat (Emotes.swift:279), kick 0.55 :278, haptics `congaLine.form` / `.scatter` (:255, :290-291) pulse (0.24, 0.15); chirps on scatter :297 |
| ringDance | BlobSocial+Emotes.swift:34 `ringChord 1.25` -> chord = peerGap*1.25 (:180), r = chord/(2 sin(pi/n)) | 1.75 | P (a round dance with real steps) | wings, tail (the quarter-turn shuffle), ears | `ring_chime` 0.45 / 0.35 per hop with pitches `ringPitch` (Emotes.swift:341, :357), kick 1.1, haptics `ringDance.form` / `.scatter` (:327, :371) |

## 3. Other places where two or more Jelbies stand within touching range

| Stance | Where set | Root distance | Class | Features | Sound / haptic today |
|---|---|---|---|---|---|
| Lying side by side (lieDown, flop) | BlobBrain+LieClear.swift:17-45 (`lieTouchCentroid 1.235`, `lieTipShift 0.09`, `lieNeed` :48) | 1.235 + 0.09(cos + shift) ~ 1.32 | T (just touch) | wings (back), ears, tail; flat bodies are 1.27x wider | contactTick squish only if they press while walking (BlobBrain+Contact.swift:135); nothing at the lie-down itself |
| Sleep pile (one snuggled row; a sleeper joins another) | BlobBrain+Sleep.swift:117 `pileSpacing 1.66`, planned :221-226 (`clash < 0.93x`, `touching < 1.12x`), :619 (`want = pileSpacing + 0.04`) | 1.66 (body width 1.6, flat) | T | wings, tail, ears | squish 0.8 on the flop (Sleep.swift:498) + `impactKick`; sleepy hand-hold (arm nubs, `leanAngle 0.22`, `holdEl`) :139-141 |
| Sleep snuggle hold (hand-hold, cuddle turn) | BlobBrain+Sleep.swift:139-143 (`handSpacing >= minGap 1.5`) | 1.5+ | T (hands) | arms only | none |
| Dining group (2-3 diners round one tray) | Dining/DiningGroup.swift:27 `diningGap 0.7` (the diners' `peerGap`, :159; `groupGap` GameCare+Group.swift:26 -> `keepApart(gap:)` MelonStage.swift:450); places Dining/DiningModels.swift:109-118 (n=2: +-0.93 -> 1.86 apart, yaw +-0.32; n=3: 0 / -1.11 / +1.11, yaw 0 / 0.25 / -0.25); Lineup picks who takes which (DiningGroup.swift:116-146) | 1.11 (3-row), 1.86 (2) | P: the 3-row stands 1.11 apart < touch distance 1.405 (-29 cm side by side) | wings (back), ears | none (the meal's own sounds) |
| Focus close-up "everyone" row | GameCamera.swift:270-273 (`focusRowSpacing 1.15`, `focusRowGap 1.0` used as `keepApart` gap when `focusSpots.count > 1`, MelonStage.swift:489), FocusGroup `rowSteerGap 1.05` (GameCare+Focus.swift:24, applied :158) | 1.15 (spacing), 1.0 hard gap | P | wings, ears (the camera is front-on: wings stick out sideways) | none |
| Storm huddle | BlobBrain+Weather.swift:405 (`gap = jellyGap * StormTuning.gapFactor 1.05` :21), `clusterSlots` :428-437 (2: +-gap/2; n>=3: ring radius gap/(2 sin(pi/n))), Lineup.best picks | 1.47 neighbours | P ("pressed close" per the header, but 1.47 is above touch) | wings, ears | none |
| Guest arrival: the household bunches round the guest | Park/GuestArrival.swift:150-155 = groupHug (above); fallback walk-over :157-167 (`goTo` within 1.0) | 1.09 | T | all | groupHug's |
| Volleyball partners / opponents | Volley/VolleyModels.swift:58-61 (`bodyDiameter 1.1`, `minCentreGap = partnerGap = brainGap = 1.6`, `minGap 1.3`), separation VolleySim.swift:960-977 (`keepApart`), GameCare+Volley.swift:293 | 1.6 | P (never touching, never overlapping) | wings/ears when diving | game sounds only |
| Park friends / visitors | same `SocialKind`s through `MelonController.socialBrains` (Park/MelonController+Park.swift:12), friend sessions Park/GameCare+Park.swift:158-168 | as the socials above | as above | all species incl. visitors | as above |
| Walking past / pressing (not a social) | BlobBrain+Contact.swift (look-ahead + `contactTick`) and the `keepApart` spring | < 1.358 | soft meeting | all | `.squish` vol 0.25 + jellyKick; NO haptic |
| Bath, race (Jelly Circuit), Jelly Show, soccer | solo or other-Jelbie-free for the bodies (the race/volley have their own separation) | n/a | n/a | n/a | n/a |

## 4. Sound and haptic inventory (what must keep firing)

Contact sounds (AudioHub.play, `SFX` raw values): `squish` (chestBump Friends.swift:178, cheekSquish :293, bellyBounce Friends2.swift:370, cuddleLean :489, swayHug Friends3.swift:81, groupHug Group.swift:269/275, contactTick BlobBrain+Contact.swift:135, flop Sleep.swift:498),
`boop` (bump Play.swift:235, sneak :275, chase :369, tag Friends2.swift:221, noseBoop :433, pass Pass.swift:91), `wobble` (cheekSquish Friends.swift:310, danceOff Friends3.swift:108), `highfive_boop` (Friends.swift:229),
`emote_spinhug` (Emotes2.swift:70), `conga_tick` (Emotes.swift:279), `ring_chime` (Emotes.swift:341, :357). Emote haptics (`BlobBrain.emoteHaptic` -> `onEmoteHaptic`, rate limit 2/s, MelonStage.swift:435): `highFive.bump`, `congaLine.form/scatter`, `ringDance.form/scatter`; treat haptics `spinHug.press/step/part` (BlobBrain+Emotes2.swift:188 `treatHaptic`).
Hearts: `.boop`/`.makeUp` events -> `socialHeart` (MelonStage.swift:401-408); the ONLY haptic on `.boop` / `.shove` is the focus-mode transient (MelonStage.swift:428, :431).

Emotes that touch and fire NO contact sound of their own today: boop, squabble, hum, twirl, backToBack, ringAround, whisperGiggle (the BEFORE run, 5.3, shows boop and squabble with no contact sound at all; the others only get one from the world: a contactTick squish or the sleep flop's). The BEFORE table lists the sounds each emote really fired.

## 5. BEFORE measurements (current tree, g-perfint 5a3a7b1 + this branch's harness)

### 5.1 How it was measured

`BobV1Tests/ContactPolishTests.swift` (Release + ENABLE_TESTABILITY=YES, iOS 26.2 sim, `-parallel-testing-enabled NO`; the whole class takes ~35 min wall). Every emote is started by rig 0 with rig 1 from spots 2.9 u apart (so the walk-up really happens; `greet` from 1.7), for 5 pairs
(Bob+Teddy, Teddy+Pearl, Lavender+Pip, Pip+Teddy, Moss+Pearl) for the pair emotes, 3 trios (Pip+Lavender+Teddy, Pip+Pearl+Moss, Bob+Teddy+Pearl) for the group emotes, plus lie-down / flop pairs and a sleep pair. Every pair of every frame (every 2nd frame for the skin, every 6th for the features) is measured with
`BruteForceContactMetric.skinGap` over the drawn skin (body + arms + Teddy ears + Pip tail + foot beans, after the shipped FeatureClip). The stance is the median gap of the frames where every body stands still (< 0.12 u/s) inside the session from its phase 1 on; a touch episode starts at gap <= +1 cm and re-arms at > +3 cm.
Raw numbers per run: `results_*.tsv`, worst frames `worst_frames.tsv`, strips `strips/<emote>.png`, all in `/private/tmp/claude-501/-Users-dmarshall94-Desktop-BobV1/9cd2e159-911b-4a04-879f-e5e34721a64a/scratchpad/contactcat/` (re-created by the test with `TEST_RUNNER_CONTACT_OUT=<dir>`).

The skin gap is the support gap along the root line (arm nubs, ears and the belly count), so "overlap" includes nubs interlocking. The column "body-in-body depth" is the separate, stricter egg-based check (how deep drawn body vertices sit inside the other's fitted egg; "-" = none), so the two can be told apart.
Caveats: lieDown / flop rows start standing 1.2 apart (their worst frame is t = 0.2 s, before LieClear walks them apart: read the stance column); `leapfrog` is a pass-over by design (the hopper is above the flat one: a plan-view gap means little there); `cuddle (loveseat)` ends after 0.2 s in the Lab (the loveseat's seats are not wired in the Lab: rig incomplete, needs a decor-aware rig); `pass` / `bagSit` use a placed ball / beanbag.

### 5.2 The touch distance of a plain pair (what the stance numbers in sections 1-3 are measured against)

| pair | touch distance side by side (x), arms in (cm) | body only | touch distance front to back (z), arms in | body only |
|---|---|---|---|---|
| Bob+Teddy | 140.5 | 140.5 | 114.2 | 109.2 |
| Teddy+Pearl | 140.5 | 140.5 | 108.4 | 108.4 |
| Lavender+Pip | 140.5 | 140.5 | 128.8 | 110.5 |
| Pip+Teddy | 140.5 | 140.5 | 114.2 | 109.2 |
| Moss+Pearl | 140.5 | 140.5 | 108.4 | 108.4 |

Two standing Jelbies touch (arm nubs and belly) at a root distance of 1.405 u side by side and 1.08-1.29 u one behind the other (arms in or out makes no difference side by side: the nubs are part of the body mesh). The body is ~1.4 wide (as the code comments say), not the 1.167 of `BobForm.halfW`.
So EVERY side-by-side stance below 1.40 overlaps by construction: closeGapFactor 1.036 = -37 cm, the keepApart floor 1.092 = -31 cm, the dining 3-row 1.11 = -29 cm, the focus row 1.0 / 1.05 / 1.15 = -40 / -35 / -25 cm. Skin gap in cm (+ apart / - overlap) of two idle STANDING Jelbies put at each catalogued centre distance (the lying / sleeping rows of the BEFORE table are flat bodies and differ):

| centre distance of the stance (u) | where | x (side by side), all pairs | z (one behind the other): Teddy+Pearl, Moss+Pearl | z: Bob+Teddy, Pip+Teddy | z: Lavender+Pip |
|---|---|---|---|---|---|
| 1.09 | keepApart spring floor 0.78 x jellyGap | -31.3 | 0.8 | -4.7 | -20.1 |
| 1.04 | closeGapFactor 0.74 x jellyGap | -36.9 | -4.8 | -7.5 | -25.7 |
| 1.12 | faceGap 0.76 / spinHug 0.84 x | -28.5 | 3.6 | -2.2 | -17.1 |
| 1.11 | Dining stands (3 places) 1.11 | -29.5 | 2.6 | -3.2 | -18.1 |
| 1.00 | Focus row hard gap 1.0 (GameCamera.focusRowGap) | -40.5 | -8.4 | -9.2 | -29.0 |
| 1.05 | Focus row steer gap 1.05 (FocusGroup.rowSteerGap) | -35.5 | -3.4 | -7.2 | -23.8 |
| 1.15 | Focus row spacing 1.15 | -25.5 | 6.6 | 0.8 | -13.7 |
| 1.86 | Dining 2 places 1.86 | 45.5 | 77.6 | 71.8 | 57.4 |
| 1.09 | Group hug / circle touch chord 0.78 x 1.4 = 1.09 | -31.3 | 0.8 | -4.7 | -19.2 |
| 1.33 | sideSpot 0.95 x 1.4 = 1.33 | -7.5 | 24.6 | 18.8 | 4.7 |
| 1.40 | jellyGap 1.4 (highFive 1.05 x = 1.47) | -0.5 | 31.6 | 25.8 | 11.8 |
| 1.47 | highFive 1.47 | 6.5 | 38.6 | 32.8 | 18.9 |
| 1.66 | Sleep pile row 1.66 | 25.5 | 57.6 | 51.8 | 38.0 |
| 1.60 | Volley partnerGap 1.6 | 19.5 | 51.6 | 45.8 | 32.1 |
| 1.61 | conga follow 1.15 x 1.4 = 1.61 | 20.5 | 52.6 | 46.8 | 33.1 |
| 1.61 | Group loose circle 1.61 | 20.5 | 52.6 | 46.8 | 32.2 |
| 1.75 | ringDance chord 1.25 x 1.4 = 1.75 | 34.5 | 66.6 | 60.8 | 46.4 |

### 5.3 The BEFORE table (worst cast per emote; 5 pair casts, 3 trio casts)

| emote | class | min skin gap, worst cast (cm) | stance median range (cm) | touch episodes (<= +1 cm) | contact sounds in / outside a touch | haptic: emote / boop events | body-in-body depth (cm) | feature depth raw -> clipped (cm) | arm/ear/tail depth raw -> clipped (cm) | contact sounds fired |
|---|---|---|---|---|---|---|---|---|---|---|
| boop | touching | 54.7 (Lavender+Pip @ 2.4s, boop/ph2) | 64.4..65.5 | 0 in 5 runs | 0/0 | 0 / 10 | - | - -> - | - -> - | NONE |
| squabble | touching | -30.7 (Lavender+Pip @ 7.2s, squabble/ph2) | 78.5..81.9 | 6 in 5 runs | 0/0 | 0 / 20 | 12 | 15 -> -0 | 16 -> -0 | NONE |
| bump | touching | 36.8 (Lavender+Pip @ 2.4s, bump/ph2) | 60.1..61.2 | 0 in 5 runs | 0/10 | 0 / 20 | - | - -> - | - -> - | boop |
| nuzzle | touching | -17.1 (Bob+Teddy @ 5.2s, nuzzle/ph2) | -16.9..-16.0 | 5 in 5 runs | 5/0 | 0 / 10 | 4 | - -> - | 4 -> -0 | squish |
| sitTogether | touching | -28.9 (Pip+Teddy @ 3.5s, sitTogether/ph2 sit) | -17.0..-16.9 | 5 in 5 runs | 5/0 | 0 / 0 | 12 | 14 -> -0 | 10 -> -0 | squish |
| sneak | touching | -30.1 (Lavender+Pip @ 2.7s, sneak/ph1) | 19.3..43.2 | 8 in 5 runs | 1/9 | 0 / 10 | 10 | 21 -> -0 | 22 -> -0 | boop squish |
| chestBump | touching | -1.2 (Pip+Teddy @ 5.5s, chestBump/ph3) | 3.6..3.7 | 15 in 5 runs | 2/13 | 0 / 20 | 2 | - -> - | - -> - | squish |
| highFive | touching | 0.1 (Moss+Pearl @ 3.6s, highFive/ph2) | 25.0..28.6 | 2 in 5 runs | 0/5 | 5 / 10 | - | - -> - | - -> - | highfive_boop |
| hum | touching | 29.2 (Lavender+Pip @ 3.6s, hum/ph2) | 29.9..30.8 | 0 in 5 runs | 0/5 | 0 / 0 | - | - -> - | - -> - | squish |
| cheekSquish | touching | -29.1 (Bob+Teddy @ 4.5s, cheekSquish/ph2) | -21.5..-17.2 | 5 in 5 runs | 15/0 | 0 / 10 | 14 | 5 -> -0 | 13 -> -0 | squish |
| bellyBounce | touching | -38.8 (Bob+Teddy @ 4.2s, bellyBounce/ph2) | -18.2..-18.1 | 12 in 5 runs | 15/0 | 0 / 20 | 22 | 10 -> -0 | 21 -> -0 | squish |
| noseBoop | touching | 14.0 (Lavender+Pip @ 3.0s, noseBoop/ph2) | 26.2..27.3 | 0 in 5 runs | 0/15 | 0 / 20 | - | - -> - | - -> - | boop squish |
| backToBack | touching | -67.2 (Pip+Teddy @ 2.7s, backToBack/ph2) | -57.3..-34.8 | 7 in 5 runs | 5/0 | 0 / 10 | 35 | 48 -> -0 | 27 -> -0 | squish |
| cuddleLean | touching | -36.8 (Bob+Teddy @ 5.1s, cuddleLean/ph2) | -36.8..-36.6 | 7 in 5 runs | 10/0 | 0 / 10 | 21 | 9 -> -0 | 19 -> -0 | squish |
| ringAround | touching | -67.2 (Lavender+Pip @ 10.3s, ringAround/ph2) | -29.4..-16.7 | 53 in 5 runs | 8/17 | 0 / 0 | 30 | 38 -> -0 | 28 -> -0 | boop squish |
| swayHug | touching | -37.8 (Bob+Teddy @ 5.2s, swayHug/ph2) | -37.3..-37.1 | 5 in 5 runs | 10/0 | 0 / 10 | 22 | 9 -> -0 | 21 -> -0 | squish |
| whisperGiggle | touching | -34.5 (Lavender+Pip @ 4.3s, whisperGiggle/ph2) | -32.7..-27.6 | 5 in 5 runs | 5/0 | 0 / 0 | 18 | 12 -> -0 | 18 -> -0 | squish |
| spinHug | touching | -35.3 (Moss+Pearl @ 5.5s, spinHug/ph3) | -21.5..-21.1 | 33 in 5 runs | 5/0 | 15 / 10 | 20 | 35 -> -0 | 23 -> -0 | emote_spinhug |
| tag | touching | -19.0 (Bob+Teddy @ 8.3s, tag/ph3) | 30.9..37.7 | 34 in 5 runs | 11/9 | 0 / 30 | 8 | 13 -> -0 | 13 -> -0 | boop squish |
| chase | touching | 13.1 (Bob+Teddy @ 14.7s, chase/ph3) | 61.7..63.1 | 0 in 5 runs | 0/15 | 0 / 30 | - | - -> - | - -> - | boop |
| greet | proximity | 30.3 (Lavender+Pip @ 2.1s, greet/ph2) | 67.2..67.2 | 0 in 5 runs | 0/0 | 0 / 0 | - | - -> - | - -> - | NONE |
| look | proximity | 146.5 (Bob+Teddy @ 0.0s, look/ph0 look) | - | 0 in 5 runs | 0/0 | 0 / 0 | - | - -> - | - -> - | NONE |
| follow | proximity | 13.7 (Pip+Teddy @ 1.5s, follow/ph0) | - | 0 in 5 runs | 0/0 | 0 / 0 | - | - -> - | - -> - | NONE |
| zoomies | proximity | 17.9 (Pip+Teddy @ 3.6s, zoomies/ph0) | - | 0 in 5 runs | 0/0 | 0 / 0 | - | - -> - | - -> - | NONE |
| dance | proximity | 130.4 (Bob+Teddy @ 0.6s, dance/ph1 bounce) | 147.6..147.6 | 0 in 5 runs | 0/0 | 0 / 0 | - | - -> - | - -> - | NONE |
| keepAway | proximity | 53.7 (Lavender+Pip @ 4.2s, keepAway/ph1) | 83.9..102.3 | 0 in 5 runs | 0/0 | 0 / 0 | - | - -> - | - -> - | NONE |
| line | proximity | 13.7 (Pip+Teddy @ 1.5s, line/ph0) | - | 0 in 5 runs | 0/0 | 0 / 0 | - | - -> - | - -> - | NONE |
| twirl | proximity | -0.6 (Pip+Teddy @ 2.7s, twirl/ph2) | 37.3..44.7 | 2 in 5 runs | 0/20 | 0 / 0 | - | - -> - | - -> - | wobble |
| hopAlong | proximity | -3.1 (Bob+Teddy @ 3.1s, hopAlong/ph2) | -0.6..-0.1 | 7 in 5 runs | 0/0 | 0 / 0 | - | - -> - | - -> - | NONE |
| littleRace | proximity | -25.9 (Lavender+Pip @ 6.0s, littleRace/ph3 run) | 37.0..39.5 | 38 in 5 runs | 0/0 | 0 / 0 | - | 9 -> -0 | 6 -> -0 | NONE |
| leapfrog | proximity | -147.7 (Lavender+Pip @ 3.7s, leapfrog/ph2 flop) | -109.1..-5.2 | 20 in 5 runs | 21/4 | 0 / 0 | 52 | 52 -> -0 | 51 -> -0 | boop squish |
| peekaboo | proximity | -35.3 (Lavender+Pip @ 2.7s, peekaboo/ph0) | 7.0..24.9 | 6 in 5 runs | 0/5 | 0 / 0 | 14 | 25 -> -0 | 26 -> -0 | squish |
| mirrorDance | proximity | -3.3 (Bob+Teddy @ 9.7s, mirrorDance/ph3) | 29.6..35.5 | 12 in 5 runs | 4/1 | 0 / 0 | 1 | - -> - | - -> - | squish |
| danceOff | proximity | 8.5 (Lavender+Pip @ 6.7s, danceOff/ph2) | 42.1..42.2 | 0 in 5 runs | 0/15 | 0 / 0 | - | - -> - | - -> - | squish wobble |
| shyWave | proximity | -10.3 (Lavender+Pip @ 5.7s, shyWave/ph4) | 202.6..213.5 | 6 in 5 runs | 5/0 | 0 / 0 | 8 | - -> - | - -> - | squish |
| pass (ball) | proximity | 106.5 (Pip+Teddy @ 1.2s, pass/ph1) | 135.1..136.0 | 0 in 5 runs | 0/5 | 0 / 0 | - | - -> - | - -> - | boop |
| bagSit (beanbag) | touching | -3.8 (Pip+Teddy @ 3.1s, bagSit/ph0 decorSit) | - | 5 in 5 runs | 0/0 | 0 / 0 | - | - -> - | - -> - | NONE |
| cuddle (loveseat) | touching | 142.2 (Bob+Teddy @ 0.1s, cuddle/ph0 decorSit) | - | 0 in 5 runs | 0/0 | 0 / 0 | - | - -> - | - -> - | NONE |
| lieDown pair (LieClear) | touching | -43.6 (Pip+Teddy @ 0.2s, -/ph-1 lieDown) | -19.6..7.8 | 13 in 5 runs | 18/12 | 0 / 0 | 2 | 11 -> -0 | 2 -> -0 | squish |
| flop pair (LieClear) | touching | -54.7 (Pip+Teddy @ 0.2s, -/ph-1 flop) | -4.4..32.6 | 7 in 5 runs | 20/10 | 0 / 0 | 22 | 36 -> -0 | 16 -> -0 | boop squish |
| sleep pile | touching | -10.6 (Bob+Teddy @ 3.1s, -/ph-1 sleep) | 25.7..25.7 | 20 in 5 runs | 5/5 | 0 / 0 | - | 7 -> - | 4 -> - | squish |
| groupHug | touching | -16.5 (Pip+Lavender+Teddy @ 7.0s, groupHug/ph3) | 17.3..17.3 | 6 in 3 runs | 6/6 | 0 / 9 | 7 | - -> - | - -> - | squish |
| groupCheer | proximity | 25.8 (Pip+Pearl+Moss @ 0.7s, groupCheer/ph0) | 47.1..47.4 | 0 in 3 runs | 0/0 | 0 / 0 | - | - -> - | - -> - | NONE |
| conga | proximity | -13.9 (Pip+Pearl+Moss @ 4.4s, conga/ph3) | - | 4 in 3 runs | 0/0 | 0 / 0 | - | 14 -> -0 | 9 -> -0 | NONE |
| circleDance | touching | -80.7 (Pip+Lavender+Teddy @ 8.9s, circleDance/ph2) | -25.5..-15.5 | 25 in 3 runs | 6/0 | 0 / 0 | 52 | 40 -> 4 | 24 -> -0 | squish |
| congaLine | proximity | -62.4 (Pip+Lavender+Teddy @ 6.5s, congaLine/ph2) | - | 9 in 3 runs | 33/9 | 6 / 0 | 36 | 42 -> -0 | 38 -> -0 | conga_tick |
| ringDance | proximity | -24.2 (Pip+Lavender+Teddy @ 5.6s, ringDance/ph2) | 75.5..75.7 | 15 in 3 runs | 0/72 | 6 / 0 | - | 12 -> - | 2 -> -0 | ring_chime |


### 5.4 Reading it

- Worst skin overlaps: leapfrog -148 (pass-over), circleDance -81 (Pip tail + spikes inside Pearl / Moss in the strip), backToBack -67 (Teddy's body sinks into Pip, Pip's tail passes through Teddy), ringAround -67, congaLine -62, flop pair -55 / lieDown pair -44 (start frames), bellyBounce -39, swayHug -38, cuddleLean -37, spinHug -35, whisperGiggle -35, peekaboo -35, squabble -31, sneak -30, sitTogether -29, cheekSquish -29, ringDance -24, nuzzle -17, groupHug -16.5, conga -14.
  Every side-by-side touching stance (nuzzle, sitTogether, cheekSquish, bellyBounce, backToBack, cuddleLean, swayHug, whisperGiggle, spinHug, circleDance) settles at -17 .. -57 cm because its stance root distance (1.0-1.33) is below the 1.405 touch distance.
- Touching emotes that never touch: boop (stays +54..65 cm apart: the walker stops ~2.0 u away), bump (+37..61), hum (+30), noseBoop (+14..27), chase (+13..63), highFive (stance +25..29, closest +0.1): the bump, the sound and the heart happen with a visible gap.
- Sounds: boop and squabble fire NO contact sound at all (only the heart / shove event). Contact sounds that fire while the skins are NOT within +1 cm ("outside a touch", count over 5 casts): bump 10, chestBump 13, sneak 9, noseBoop 15, chase 15, tag 9, highFive 5, hum 5. Several fire more than once per touch (cheekSquish up to 3 in one touch: squish + squish + wobble, bellyBounce 3, cuddleLean 2, swayHug 2, leapfrog 4), so "exactly once per touch" needs a rule, not only a threshold.
- Haptics: the only contact haptics are highFive (`highFive.bump`), the spinHug treat haptics and the congaLine / ringDance pulses; every other touch has only the `.boop` / `.shove` event (a heart; a haptic only in focus mode). See the haptic column.
- Features: raw (no push-out) wing / spike / daisy / ear / arm vertices sit up to 52 cm inside the other body (leapfrog 52, backToBack 48, congaLine 42, circleDance 40, ringAround 38, spinHug 35); the shipped FeatureClip brings it to <= 0.1 cm everywhere except circleDance (4.1 cm: Pip's tail / spikes, see the strip). FeatureClip never moves a BODY: "body-in-body depth" is the column to watch (squabble 12, sitTogether 12, sneak 10, backToBack, ringAround, circleDance ...).
- The worst three strips (6 frames around the worst frame, real renderer, `strips/*.png`) were looked at: backToBack (Pip+Teddy: the two bodies visibly merge, tail through Teddy), circleDance (Pip+Pearl+Moss: Pip's spikes and tail inside Pearl), leapfrog (Lavender+Pip: the hop passes through the lying body).

### 5.5 Migration checklist for the contact engine (what the harness checks)

1. Run with `TEST_RUNNER_CONTACT_ENFORCE=1`: no overlap (min gap >= -1 cm every frame); touching stances (stance median <= +1 cm); features / limbs <= 0.5 cm inside another body; touching emotes touch (>= 1 episode), fire exactly one contact sound per touch and none while apart.
2. Compare `ContactProfile.skinGap` with `BruteForceContactMetric.skinGap` on the same `ContactSurface` (`ContactPolishTests.testMetricSanity` shows the shape of the check; surfaces are taken after the shipped FeatureClip pass, as drawn).
3. The stance distances to move are the ones in 5.2 (anything < 1.405 side by side, < ~1.1 front to back); pass-overs (leapfrog) and spins (ringAround, spinHug, circleDance, ringDance) need the per-direction profile, not one touch number.


### 5.6 AFTER measurements (g-contactmig: ContactStance table + one settle call; 5 pair casts, 3 trio casts, Release, CONTACT_ENFORCE=1)

Columns as 5.3, worst case over the casts; BEFORE numbers are the 5.3 row of the same emote. "sounds per touch" = touch episodes (skin gap <= +1 cm, re-armed past +3 cm) that got 0 / 1 / 2+ contact sounds. "emote haptics" = `highFive.bump` + the treat haptics, "boop events" = the `.boop` / `.shove` events (a heart, a haptic in focus mode): these are NOT moved by the engine, only the contact sound / emote haptic are gated on the touch.
Rows not owned by a SocialKind (lieDown / flop pair, sleep pile, bagSit, cuddle) are listed for completeness: lie / flop were started 1.2 apart by the harness itself (now 1.6, so the first frames are not a harness-made overlap); the sleep pile and bagSit are untouched by this branch; `cuddle` (loveseat) cannot run in the Lab (no seats wired).

| emote | class | worst min gap (cm) BEFORE -> AFTER | stance median range (cm) AFTER | touch episodes (all casts) | contact sounds in / outside a touch, BEFORE -> AFTER | sounds per touch AFTER (episodes with 0 / 1 / 2+) | emote haptics + boop events AFTER (BEFORE) | sound names AFTER |
|---|---|---|---|---|---|---|---|---|
| boop | touching | 54.7 -> -0.8 | -0.0..-0.0 | 5 | 0/0 -> 5 / 0 | 0 / 5 / 0 | 0 / 10 (0 / 10) | squishx5 |
| squabble | touching | -30.7 -> -24.8 | 25.8..35.5 | 20 | 0/0 -> 24 / 0 | 5 / 6 / 9 | 0 / 20 (0 / 20) | squishx24 |
| bump | touching | 36.8 -> -28.7 | -0.1..2.0 | 40 | 0/10 -> 35 / 2 | 7 / 31 / 2 | 0 / 20 (0 / 20) | boopx37 |
| nuzzle | touching | -17.1 -> -1.2 | -0.2..-0.1 | 5 | 5/0 -> 5 / 0 | 0 / 5 / 0 | 0 / 10 (0 / 10) | squishx5 |
| sitTogether | touching | -28.9 -> -3.9 | -0.3..-0.2 | 22 | 5/0 -> 24 / 0 | 0 / 21 / 1 | 0 / 0 (0 / 0) | squishx24 |
| sneak | touching | -30.1 -> -10.4 | -2.7..4.7 | 13 | 1/9 -> 8 / 6 | 5 / 8 / 0 | 0 / 10 (0 / 10) | boopx4 squishx10 |
| chestBump | touching | -1.2 -> -4.4 | 1.7..2.3 | 34 | 2/13 -> 23 / 0 | 11 / 23 / 0 | 0 / 20 (0 / 20) | squishx23 |
| highFive | touching | 0.1 -> -1.8 | -0.4..-0.2 | 26 | 0/5 -> 25 / 0 | 6 / 15 / 5 | 20 / 10 (5 / 10) | highfive_boopx20 squishx5 |
| hum | touching | 29.2 -> -1.0 | -0.1..-0.0 | 5 | 0/5 -> 5 / 0 | 0 / 5 / 0 | 0 / 0 (0 / 0) | squishx5 |
| cheekSquish | touching | -29.1 -> -1.6 | 2.1..2.5 | 10 | 15/0 -> 10 / 0 | 0 / 10 / 0 | 0 / 10 (0 / 10) | squishx10 |
| bellyBounce | touching | -38.8 -> -2.4 | -0.4..5.5 | 15 | 15/0 -> 20 / 0 | 0 / 10 / 5 | 0 / 20 (0 / 20) | squishx20 |
| noseBoop | touching | 14.0 -> -2.0 | -0.0..-0.0 | 18 | 0/15 -> 20 / 0 | 2 / 12 / 4 | 0 / 20 (0 / 20) | boopx20 |
| backToBack | touching | -67.2 -> -18.6 | -7.8..-0.4 | 11 | 5/0 -> 5 / 0 | 6 / 5 / 0 | 0 / 10 (0 / 10) | squishx5 |
| cuddleLean | touching | -36.8 -> -1.3 | -0.3..-0.0 | 5 | 10/0 -> 5 / 0 | 0 / 5 / 0 | 0 / 10 (0 / 10) | squishx5 |
| ringAround | touching | -67.2 -> -25.4 | -5.5..4.5 | 140 | 8/17 -> 117 / 33 | 43 / 85 / 12 | 0 / 0 (0 / 0) | boopx10 squishx140 |
| swayHug | touching | -37.8 -> -1.2 | -0.2..-0.1 | 5 | 10/0 -> 5 / 0 | 0 / 5 / 0 | 0 / 10 (0 / 10) | squishx5 |
| whisperGiggle | touching | -34.5 -> -1.9 | -1.0..-0.3 | 7 | 5/0 -> 10 / 0 | 0 / 4 / 3 | 0 / 0 (0 / 0) | squishx10 |
| spinHug | touching | -35.3 -> -7.0 | -0.1..-0.0 | 33 | 5/0 -> 18 / 47 | 15 / 18 / 0 | 25 / 10 (15 / 10) | emote_spinhugx5 squishx60 |
| tag | touching | -19.0 -> -25.4 | 9.6..37.9 | 35 | 11/9 -> 28 / 2 | 11 / 20 / 4 | 0 / 30 (0 / 30) | boopx10 squishx20 |
| chase | touching | 13.1 -> -16.5 | 1.0..18.4 | 26 | 0/15 -> 16 / 1 | 10 / 16 / 0 | 0 / 30 (0 / 30) | boopx9 squishx8 |
| greet | proximity | 30.3 -> 30.3 | 67.2..67.2 | 0 | 0/0 -> 0 / 0 | 0 / 0 / 0 | 0 / 0 (0 / 0) | none |
| look | proximity | 146.5 -> 146.5 | - | 0 | 0/0 -> 0 / 0 | 0 / 0 / 0 | 0 / 0 (0 / 0) | none |
| follow | proximity | 13.7 -> 13.7 | - | 0 | 0/0 -> 0 / 0 | 0 / 0 / 0 | 0 / 0 (0 / 0) | none |
| zoomies | proximity | 17.9 -> 17.9 | - | 0 | 0/0 -> 0 / 0 | 0 / 0 / 0 | 0 / 0 (0 / 0) | none |
| dance | proximity | 130.4 -> 130.4 | 147.6..147.6 | 0 | 0/0 -> 0 / 0 | 0 / 0 / 0 | 0 / 0 (0 / 0) | none |
| keepAway | proximity | 53.7 -> 53.7 | 84.0..102.3 | 0 | 0/0 -> 0 / 0 | 0 / 0 / 0 | 0 / 0 (0 / 0) | none |
| line | proximity | 13.7 -> 13.7 | - | 0 | 0/0 -> 0 / 0 | 0 / 0 / 0 | 0 / 0 (0 / 0) | none |
| twirl | proximity | -0.6 -> -1.1 | 37.3..44.7 | 2 | 0/20 -> 0 / 20 | 2 / 0 / 0 | 0 / 0 (0 / 0) | wobblex20 |
| hopAlong | proximity | -3.1 -> 1.4 | 4.0..8.6 | 0 | 0/0 -> 0 / 0 | 0 / 0 / 0 | 0 / 0 (0 / 0) | none |
| littleRace | proximity | -25.9 -> -3.6 | 49.4..56.2 | 9 | 0/0 -> 9 / 11 | 0 / 9 / 0 | 0 / 0 (0 / 0) | squishx20 |
| leapfrog | proximity | -147.7 -> -12.2 | 18.8..43.1 | 33 | 21/4 -> 17 / 26 | 19 / 11 / 3 | 0 / 0 (0 / 0) | boopx10 squishx33 |
| peekaboo | proximity | -35.3 -> -7.1 | 45.0..48.9 | 4 | 0/5 -> 2 / 3 | 2 / 2 / 0 | 0 / 0 (0 / 0) | squishx5 |
| mirrorDance | proximity | -3.3 -> 34.8 | 67.7..67.7 | 0 | 4/1 -> 0 / 0 | 0 / 0 / 0 | 0 / 0 (0 / 0) | none |
| danceOff | proximity | 8.5 -> 20.5 | 53.6..53.7 | 0 | 0/15 -> 0 / 10 | 0 / 0 / 0 | 0 / 0 (0 / 0) | wobblex10 |
| shyWave | proximity | -10.3 -> -1.1 | 202.8..213.5 | 6 | 5/0 -> 5 / 1 | 1 / 5 / 0 | 0 / 0 (0 / 0) | squishx6 |
| pass (ball) | proximity | 106.5 -> 106.5 | 135.1..136.0 | 0 | 0/5 -> 0 / 5 | 0 / 0 / 0 | 0 / 0 (0 / 0) | boopx5 |
| bagSit (beanbag) | touching | -3.8 -> -3.8 | - | 5 | 0/0 -> 1 / 4 | 4 / 1 / 0 | 0 / 0 (0 / 0) | squishx5 |
| cuddle (loveseat) | touching | 142.2 -> 142.2 | - | 0 | 0/0 -> 0 / 0 | 0 / 0 / 0 | 0 / 0 (0 / 0) | none |
| lieDown pair (LieClear) | touching | -43.6 -> -12.4 | -5.5..-1.1 | 9 | 18/12 -> 9 / 9 | 1 / 7 / 1 | 0 / 0 (0 / 0) | squishx18 |
| flop pair (LieClear) | touching | -54.7 -> -13.6 | 12.6..34.7 | 11 | 20/10 -> 6 / 24 | 5 / 6 / 0 | 0 / 0 (0 / 0) | boopx10 squishx20 |
| sleep pile | touching | -10.6 -> -10.6 | 25.7..25.7 | 20 | 5/5 -> 25 / 5 | 2 / 13 / 5 | 0 / 0 (0 / 0) | squishx30 |
| groupHug | touching | -16.5 -> -17.4 | -0.6..-0.6 | 17 | 6/6 -> 38 / 0 | 6 / 2 / 9 | 0 / 9 (0 / 9) | squishx38 |
| groupCheer | proximity | 25.8 -> 25.8 | 47.1..47.4 | 0 | 0/0 -> 0 / 0 | 0 / 0 / 0 | 0 / 0 (0 / 0) | none |
| conga | proximity | -13.9 -> -2.3 | - | 3 | 0/0 -> 3 / 1 | 0 / 3 / 0 | 0 / 0 (0 / 0) | squishx4 |
| circleDance | touching | -80.7 -> -32.4 | - | 173 | 6/0 -> 239 / 5 | 44 / 63 / 66 | 0 / 0 (0 / 0) | squishx244 |
| congaLine | proximity | -62.4 -> -7.7 | - | 9 | 33/9 -> 15 / 44 | 1 / 3 / 5 | 6 / 0 (6 / 0) | conga_tickx47 squishx12 |
| ringDance | proximity | -24.2 -> -3.9 | 77.6..79.2 | 6 | 0/72 -> 3 / 84 | 3 / 3 / 0 | 6 / 0 (6 / 0) | ring_chimex72 squishx15 |

What changed (files): `Melon/ContactStance.swift` (the table: class, per-phase target gap, anchor, features, own sound + haptic, re-touch pulses; `standGap`, `touchRadius`, the post-session `glow`), one call `contactStanceTick` in `BlobBrain.tick` (just before the idle moves take the body, so hops / bounces / flap-hops are held too), `ContactSettle` (support-gap option, urgent separation, `contactNudge` slides the root, the step in flight, the soles, the hop / flap-hop path and the sim body), `contactTick` (the emote's own sound + haptic at the first real touch, only in the table's hold step; otherwise the default squish), `contactCueFallback` (the old timer sound where NO profile exists: Lab, sound counts, UI tests), spots: `sideSpot` / `behindSpot` / `standGap` floor every close stance at the touch distance + 4 cm (1.445 m side by side), group rings use chord >= 1.445, spinHug radius from the distance, tag / chase catch spots from the profile.

Known gaps (numbers above, worst first): Pip's tail is not in the contact profile (FeatureClip owns it), so Pip casts overlap through the tail in bump (-28.7), tag, squabble (-24.8), backToBack (-18.6) and ringAround; the spins (ringAround -25, circleDance -32, spinHug) turn on a ring of walkers and still dip by up to 14-32 cm for a few frames and fire contact sounds outside a touch (spinHug 4-12 per cast); leapfrog is a pass-over by design; groupHug -16.5 at the break-apart; sneak -10 (Lavender+Pip); sleep pile / bagSit / cuddle are not wired to the engine in this branch. Several emotes now fire fewer contact sounds per touch than BEFORE (cheekSquish 3 -> 1-2, bellyBounce 3 -> 1 per bounce, cuddleLean 2 -> 1, swayHug 2 -> 1): the rule is exactly one per real touch; none was removed, a second sound needs a second touch (cheekSquish and groupHug part by 4 cm and meet again).

### 5.7 Round 2 (g-contactmig): geometry, tail as a feature, one touch gate, unwired scenes, and the skating rule

Done and measured (Bob+Teddy, Lavender+Pip, groups; Release, CONTACT_ENFORCE=1):
- Geometry from the touch distance: group ring chord (`ringChord`), ringDance chord, conga gap, spinHug radius, all pair spots (`standGap`, floor 1.445 m); tag / chase catch spots from the profile.
- Pip's tail is now in the FEATURE bins (`ContactField.tailBuf` / `mergeTail`), `features: true` on every touching stance, and the keepApart wall asks `gap(..., features: true)`. Cost of the feature path (ContactSettleTests.testFeatureGapCost): 5.7 us body-only vs 9.3 us with features per wall query. bump (Lavender+Pip) went -26.6 -> -13.5, tag stayed the worst Pip case.
- One touch gate: the harness counts `contactEvents` as the episodes; sounds per touch are now exactly 1 in every touching row (no zero-sound or double-sound episodes in the Bob+Teddy / Lavender+Pip runs); `.boop` / `.shove` events and the emote haptic (once per session) ride on the gate's touch in a profile-ful rig (drive-timer fallback only without profiles). Contact sounds outside a touch: ringAround 4, leapfrog 4 (spinHug 0, congaLine / ringDance 14 / 24 are the beat ticks, proximity).
- Sleep pile -10.6 -> -2.5 (the sleeper keeps a standing neighbour off, two sleepers settle to touch); bagSit / cuddle are in the table (separation only; bagSit never touches by design: the second Jelbie sits 0.95 m from the piece).
- Harness: stance median over the table's active (hold) phases only; leapfrog uses a 3D clearance (soles above the other's top); the feet gate `SocialFeetTests` is merged and now asserts in-session planted-sole drift <= 10 mm.
- `urgent` separation: A/B with the new geometry, OFF is worse in 53 rows (leapfrog -119, circleDance -57, squabble -29, spinHug -14, tag -18) -> kept (with translation). Under the three-channel rule (below) it only changes the size of the lean request.
- ContactSettleTests converge test: passes at 9e62e8a, regressed 60 -> 61 frames at 4fb6182a because `contactNudge` also slid feet / step / sim for no-session nudges; fixed (the extras only inside a session).

The skating rule (this commit): the settle never translates a planted body. `contactNudge` now has three channels: WALKING -> the walk's destination is re-derived from the touch distance every tick (`contactStanceWalk`), AIRBORNE (gait hop / flap-hop / both feet up) -> one rigid warp (root, step root, soles, hop path, flap-hop start, sim body, at once), PLANTED -> a lean toward / away from the partner (budget 0.08 rad ~ 4 cm at the cheeks, `leanTrim`, added after the emote's own lean), beyond it one 14 cm shuffle step on the locomotion. Lying / sleeping bodies and no-session nudges keep the old root nudge.
First measurement under that rule (SocialFeetTests, 10 ms-free engine on; planted-sole drift in session, mm; limit 10): boop, hum, groupHug, circleDance <= 10 (pass); sneak 15.6 / 42.5; chestBump 47.9; tag 62.9 / 73.8; nuzzle 91.6 / 70.7; ringAround 99.4 / 57.2; bump 245 / 312 (before the rule: boop 691, tag 780, sneak 410, bump 359, chestBump 301, noseBoop 342, hum 337, groupHug 362, ringAround 305, circleDance 519). The mid-air join in bump (-14.4 / -12.4 cm), groupHug (-10.2 / -11.0), circleDance (-10.2 / -11.0), tag (-9.9 / -7.0), chestBump (-4.8) still fails.
ContactPolishTests under the same rule (Bob+Teddy) got WORSE than round 1 where the old translation did the work: hold stances reach -0.1 .. -20 cm, boop / hum / noseBoop stop 5-12 cm short (the walk ends short and the 4 cm lean budget cannot close it, no shuffle yet because the lean request needs a fresh profile that is already in deadband), squabble -130, highFive -45, bellyBounce -32, ringAround -72, tag -82, spinHug -63: the walkers (spins, rings, tag, squabble step-apart) have no wall any more in the Lab (the stage keepApart is not wired there). This is the open problem of the round; the next step is the walk arrival (lean budget vs. arrival residual, the walker wall), not a stronger settle.

### 5.9 Measurement trust (r4-measure-r1, 2026-11-04): the columns the acceptance table is built from

`ContactPolishTests` `results_*.tsv` has these columns appended (the old ones are unchanged), one row per stance per cast:

| column | meaning |
|---|---|
| `arrival_cm` | THE ARRIVAL RESIDUAL: the drawn-skin gap (support metric, + apart / - sunk) at the first frame of the FIRST stop of the approach: the first quiet spell after somebody stepped that lasts >= 0.4 s (24 frames; `ArrivalTracker`, `Melon/ContactMetric.swift`). "Stepping" = a gait step running (`stepLive`), a gait busy, or a walk script active, for any body of the cast. `-` = the pair never stood still that long before the first touch (a bar failure: "never stood still on arrival"), or has no approach (momentary / lie / sleep rows). Bar: -1 ... +1.5 cm. |
| `arrival_at_s` | when (s from the start of the run) |
| `lastPlant_cm`, `stops` | the gap at the LAST stop before the first touch, and how many stops there were. `stops` > 1 with `arrival_cm` > 3 cm is walk-stop-walk (the stutter-step arrival). Diagnostic, not a bar column. |
| `holdMedian_cm`, `holdN`, `holdTouchN` | the hold: the frames (every 2nd) of the stance table's HOLD step (target `ContactStance.hold`), counted from the first frame the skins touch (<= +0.5 cm) to the end of the step. `holdN` = those frames, `holdTouchN` = of them at <= +0.5 cm. Under 3 frames there is NO hold (`-`, bar: "no hold"): never a median of one frame. Bar: |median| <= 0.5 cm. |
| `touchGaps_cm` | the exact gap at the frame each touch event fired. A momentary emote (`boop`: the session ends at the touch) is judged on these (bar: -1 ... +0.5 cm) instead of a hold. |
| `footMin_cm` | the least FOOTPRINT gap (what the eye sees in plan view, `BruteForceContactMetric.footprintGap` over the skinned triangles) over the frames where the strict support gap read an overlap (< -1 cm). A big difference to `minGap_cm` marks an axis artefact (staggered / hopping bodies), a small one a real overlap. Informational: the bar stays on the strict support gap. |
| `worstReach_cm`, `worstLag_cm` | at the worst overlap frame: the longest reach of a drawn body from its centroid, and the largest distance between the sim centroid and the brain root. A reach of 2-4 m is a smeared body (a body dragged by a teleporting / over-fast brain), not a pose. |
| `bar` | `pass`, or the list of what fails THE BAR as far as the harness measures it (the planted-sole drift and the mid-air join are SocialFeetTests'). |

The ground truth is the drawn skin, not a root: `BruteForceContactMetric.skinGap` reads the skinned vertices; the roots only fix the AXIS the support is read along, and the gap is independent of where on that axis a root sits (`testGapIsFromTheMeshNotTheRoots`). `ContactField.gap(features: true)` now also tests every feature vertex (tail tip, wing, spike, daisy) against the whole other footprint, so a tip INSIDE the other body always reads negative (`testFeatureTipInsideTheOtherBodyReadsNegative`; it used to fall back to the body-only gap when the lone tip had no neighbouring bin and no lateral overlap with the facing cap).

The real-app capture (`scripts/contact_capture.sh`, `ContactDemo`) logs a tick every 0.2 s and its SUMMARY line takes the hold median over the ticks inside the stance table's hold step (not "the phase with the most touching ticks"); lie-down / sleep keep the old rule. Scene rows `chase_bob_teddy` and `flop_teddy_pearl` exist (ContactDemo starts `chase` as a social kind and `flop` through the lie-down path).

### 5.9 Drive round 1 (r4-drive-r1): the strike moves peak at contact, the walk-up no longer aborts, ring / spin radii from the widest touch

Findings (traced, Release, Bob+Teddy first; numbers are minimum skin gap, cm):

- **The authored lean is geometry.** A drive lean of 0.2 rad moves the skin ~0.8 m/rad at the cheek height per body (two bodies at 0.09 rad closed 15 cm). bump / chestBump / noseBoop / highFive / bellyBounce / squabble / sneak lean in by 0.16 - 0.30 rad on a pair that already stands at the hold gap, and the stance walk then backs the pair off, the lean eases, the walk comes back (the high five swung 3 ... 70 cm for 5 s; bump -15).
  `BlobSocial+Peak.swift` `peakGuard()` (socialDrive -> peakGuard -> contactApplyLean) caps the TOWARD-partner part of the drive's lean at what the live skin gap leaves (in: up to contact, shared between both leaners, 60 %; away: wind-up opens the gap at most `openCap` 4.5 cm; relaxing to neutral is never blocked) and at 0.08 rad absolute. Only the strike kinds (`PeakTuning.strikeKinds`): the hold kinds close their last cm with the engine's own lean and the guard left them 3-4 cm short.
  `peakArmed(o)` (bump's strike starts when the pair is planted and within 5 cm skin gap, or after 3 s) so a strike never adds its lean to a walk's closing speed.
- **backToBack** (table row): side by side at 2 cm from phase 1, hold from the sit; round 0 sat 8 - 39 cm apart because the sit (planted) began before the backs were within a lean of each other. Bob+Teddy: +6.5 / hold 7.9 -> -0.6 / 0.2. A turn-step "motion warp" (root displacement = change of the support reach toward the partner) was built and measured WORSE (hold 17 cm: the support includes swinging legs / arms) and removed.
- **Walk-up abort.** `walkUpPhase` / squabble / sneak ended the session when the walk stopped farther than `peerGap + 0.4..0.5` (1.3 - 1.4 m), but the stance stands at `standGap` >= 1.445 and the walk stops up to 6 cm off that: the session aborted before the touching phase whenever the walk did not happen to overshoot (squabble "never closes", +106 cm, in round 0 and in the pair runs after another emote). `BlobBrain.walkUpFar` 2.2 m; the stance's own walk closes the rest in phase 1.
- **ringAround** (+Friends2): the gait's hop turns the body toward its CHORD, so mid-hop the pair stands side on (touch 1.4 m, not the face-to-face 0.78). The ring is now `(ringTouch + 0.06) / (2 cos 18 deg)` radius, 15 hops of 36 degrees (1.5 turns; the chord shortens the mid-air distance by 1.2 %), the pair first walks out to its ring spots; table: touching nose to nose in the greeting (phase 1), proximity while hopping (the hop turns the bodies side on, so a touching ring is not possible with this gait). `startHopTo(facing:)` lands facing the partner. The old radius used `ContactField.gap(features:)` which can return a large negative on deep overlap and flew the bodies several metres.
- **spinHug**: ring radius `half + 0.20` (was half + 0.10 at most): walking, each root swings +-12 cm round its path; measured -21 / +20 cm on the ring of half + 0.10.
- **lieDown pair**: the snuggle settles to `hold` on the support gap with the urgent push (was target 0 on the feature gap).

Not fixed (cause known): see the round report. Knobs for A/B in the harness: env `PEAK_OFF=1` (all), `PEAK_NOGUARD=1`, `PEAK_NOARM=1`, `PEAK_K`, `PEAK_GAIN`, `PEAK_OPEN`, `PEAK_ARM`, `PEAK_CAP`, `PEAK_LOG=1`.

### 5.10 Adding an interactive emote (user rule 3, 2026-11-04: ONE formula for every emote where Jelbies meet, now and later)

The formula: the meeting spot is decided once at session start; one continuous walk whose last step lands there; a hold at skin contact (skin gap 0 +- 0.5 cm, never deeper than -1 cm, never a visible gap; the
`hum Moss+Lavender` frame is the reference); tail, wings, spikes, daisy, ears and hands never inside the partner; exactly one touch sound per touch; a HAND ends ON the partner's skin (hand-tip-to-skin gap 0 +- 0.5 cm).
It is enforced by tests, not by this note. Checklist for a new `SocialKind`:

1. **Stance row**: add the kind to `ContactStance.table` (ContactStance.swift) with an explicit class (`touching` / `proximity`), `features` (wings, tail, spikes, daisy counted), the walk-up (`walk0`), `facing`, the hold/press step, the sound. No default class exists: `ContactPolishTests.testEveryInteractiveKindHasAStanceRow` FAILS while a kind has none.
2. **Hand flag**: if a hand must land (a poke, pat, clap, hand-hold) add the kind to `ContactPolishTests.handKinds`; the bar then reads `handMin_cm` / `handTouch_cm` (boop: hand 0 +- 0.5 cm at the touch, bodies at hand reach: `bodyTouch_cm` >= 0; highFive: tips meet, `handHand_cm` <= 0.5).
3. **Harness entry**: add a curated entry (name, class, props, time cap) to `curatedPairEntries` / `curatedGroupEntries`. A kind without one still runs (`autoEntries`, class from its table row) so it is measured the day it exists, but `testEveryInteractiveKindIsInTheHarness` FAILS until the curated entry is there and agrees with the table's class.
4. **Feet test**: a `testX` method in SocialFeetTests (`testEveryTouchingKindHasAFeetTest` FAILS naming the kind otherwise): planted-sole drift <= 10 mm per phase, mid-air join, sole rise.
5. **Scene row**: a row in `scripts/contact_scenes.tsv` (`testEveryTouchingKindHasASceneRow`; furniture kinds are the only exemption) so the real-app clip, sheet and `.demolog` SUMMARY (skin gap, hold median, hand tip) are judged next to the numbers.
6. **Run** (Release + testability): `ContactPolishTests` with `CONTACT_ENFORCE=1` for all five pair casts + groups (`CONTACT_ONLY=<emote>,boop,hum,swayHug,nuzzle,backToBack` as canaries), `SocialFeetTests` with `SOCIALFEET_ENGINE=1` (and 0 for the baseline), `ContactSettleTests`, `ContactProfileTests`, then `scripts/contact_capture.sh <out> <scene>`.

Results columns added in r4-measure-r2 (results_*.tsv, after `bar`): `minGapBody_cm` / `holdMedianBody_cm` (egg only: no arms, ears, feet), `snd_per_touch` (`1` = every touch exactly one sound, `-` = no touch, else the distinct counts), `handMin_cm`, `handTouch_cm`, `handHoldMedian_cm`, `handHand_cm`, `bodyTouch_cm`.
`worst_frames.tsv` is now written at the end of every `finish()` (plus `worst_frames_<cast>.tsv`). `socialfeet.tsv` has a header and one row per (stance, ContactPolishTests cast).
Hand gap definitions: lab = `BruteForceContactMetric.handGap` (the arm capsule's first vertex, the pole of the tip sphere, against the other body's drawn skin along the line tip -> its root, 3 cm lateral strip, 5 cm height band; negative = inside);
app = `ContactField.handGap` (the tip, recorded by `ContactField.build` from the arm block, against the other body's profile outline, radial). The `.demolog` tick line has `hand[i-j:cm]`, the SUMMARY `minHand` / `medHoldHand`.

### 5.10b Adding an interactive emote (the checklist; user rule 3, 2026-11-04: ONE formula for every interactive emote)

The formula: the meeting spot is decided once at session start; one continuous walk whose last step lands there; the hold is at skin contact (the hum Moss+Lavender belly press: skin gap 0 +- 0.5 cm, never deeper than -1 cm, never a visible gap); tail / wings / spikes / daisy / ears / hands never inside the partner; exactly one touch sound per touch; every lunge, bounce, turn and hop peaks AT contact, never past it (the peak is sized from the live skin gap, see `BlobSocial+Peak.swift`).

1. **Kind**: add the case to `SocialKind` (BlobSocial.swift) and the drive.
2. **Row**: add an explicit `ContactStance.table` row (ContactStance.swift). There is no default; `ContactTableTests.testEveryKindHasAnExplicitRowAndIsMeasured` fails without it.
3. **Class**: `touching` (skins meet: `.holding` for a held contact, `.pressing` for a strike) or `proximity` (they stand close, never overlap). A hand emote (boop, highFive, pat) is touching with the hand as the contact: the bodies stand at hand reach and the hand ends ON the partner's skin.
4. **Flags**: `features:` true if wings / tail / spikes / daisy can reach the partner (Pip's tail: `socialTailCurl`); `facing:` .each (face to face) or .camera (side by side); `anchor:` for the one who does not move; `sound:` / `haptic:` (one per touch, fired by `contactTick`); `walk0:` false only when the drive owns its own walk-up.
5. **Harness**: add an entry to `ContactPolishTests.pairEntries` or `groupEntries` (the same test enforces it), with its class and any prop.
6. **Capture scene**: add a row to `scripts/contact_scenes.tsv` for a real-app clip (perp + top) and WATCH the sheet.
7. **Suites**: ContactPolishTests (all five pair casts + groups, CONTACT_ENFORCE=1), SocialFeetTests ENGINE=1 for the kind, ContactSettleTests, ContactProfileTests, ContactTableTests, RoomSFXCountTests.
### 5.10c Adding an interactive emote (user rule 3, 2026-11-04) - the checklist
Every emote with a partner follows ONE formula: the meeting spot is decided once at session start; one continuous walk whose last step lands there (a stance walk arrives within 1 cm, braked final stride, the room's peer wall does not cut the final step); hold at skin contact (0 +- 0.5 cm, a few mm of press is the target, never deeper than -1 cm); tail, wings, spikes, daisy, ears and hands never inside the partner; exactly one touch sound per touch. Enforced in code:
1. **Row.** Add the kind to `ContactStance.table` (ContactStance.swift). Class: `touching` (`.holding` / `.pressing`), `proximity` (never overlap) or an explicit `.none`. Set `facing` (`.each` face to face, `.camera` side by side facing the camera), `features` (wings / tail / spikes / daisy count), `anchor`, `sound` + `volume` + `haptic` (the contact sound fires ONCE per touch from `contactTick`, never from the drive's timer except through `contactCueFallback`).
2. **Class check.** `ContactSettleTests.testEveryInteractiveKindHasAStanceRow` fails for a `SocialKind` without a row, and for a kind with a touching / proximity row that `ContactPolishTests.pairEntries` / `groupEntries` does not enumerate.
3. **Harness.** Add the entry to `pairEntries` (or `groupEntries`) in ContactPolishTests.swift with its class, and a row to `scripts/contact_scenes.tsv` for the real-app capture.
4. **Drive.** Never walk to a self-chosen spot: let phase 0 walk (`walkUpPhase`), the stance table retargets that walk to the touch spot (`Step.walks`). Strike moves (lunge, bounce, hop) must peak at skin contact: `contactApplyLean` (lean limiter) and `peakGuard` (BlobSocial+Peak.swift) cap them; size hops from the touch spot, not from a constant.
5. **Hands.** A hand emote (boop, highFive, pat, hold hands) ends with the hand ON the partner's skin (hand gap 0 +- 0.5 cm, never inside): the bodies stand at hand reach, not pressed. (Needs the drive to aim the arm; the table row carries the stand-off.)
6. **Run.** ContactPolishTests with CONTACT_ENFORCE=1 for all five pair casts (`testPairs1..5`) and `testGroups`; SocialFeetTests (drift, join); ContactSettleTests; the real-app capture (`scripts/contact_capture.sh`) and LOOK at the sheet: no stop-turn-lean arrival, no gap, no sink, the move still looks like itself.

### 5.11 Stance walk, round 2 (r4-arrivalA-r2): why the pair used to stop 9 cm short, then lean the rest
Traced with `CONTACT_TRACE_COLS=1` on nuzzle Bob+Teddy: the walk landed its last step exactly on the destination plan (`planWalkStep` D, a), but the ROOM'S PEER WALL (`MelonStage.keepApart`, called through `resolve`) cut the final step from 15.3 to 6.9 cm. The wall measures the partner at the walker's CURRENT outline, mid-turn into the pose (80 degrees off the final yaw: 10 cm wider), so the walk ended 9 cm short; `walkFinal` then ended the walk, the settle could only lean (budget 0.11 rad), the lean saturated and the pair showed a +11 cm gap for a second, then closed with the lean: "stop, turn, lean". Fixes:
- The final step of a stance walk is planned with the session partner exempt from the wall (`BlobBrain.stanceStepFree`, encoded as `-(id+1)` in `contactPartnerIDs()`, skipped in `keepApart`). The wall and the settle still guard every other step and every tick.
- The soft body keeps the walk's momentum 2 - 3 cm past the root when the root stops at once: the final stride runs at `ContactTuning.finalStepRate` (0.6) of the normal rate (measured: arrival at rate 1.0 / 0.7 / 0.5 = -1.9 / -0.1 / +2.1 cm on hum Bob+Teddy).
- The touch distance used for the destination is sampled BETWEEN steps only (double support: the outline swings +-8 cm over a stride, a sample at a fixed gait phase does not) and the destination is locked for the last 0.45 m (was 0.8 m: the lock froze a swung sample, Moss+Pearl side by side stopped 9 cm short).

### Park capture rows (r4-park-capture)

`ContactDemo` also runs in the PARK: `-StartPark 1` (simulator hook, goes to the park with the NewGame Jelbie) + `-ContactDemoPark 1` waits until the trip is `.playing`, replaces the random visitors with `-ContactDemoVisitors N` chosen pool visitors (`-ContactDemoVisitorSpecies wings,daisy,none`, in order, by signature; the pool has NO yellow/tail visitor, the tail is covered by Pip in the cast), takes the cast off autonomy and forces the kind between the Jelbie and the visitor(s) (trios: Jelbie + 2 visitors) with the same tick log and SUMMARY. The visitors' species / colour / worn item are logged (`park visitor ...`). The perp/top tracking cameras work unchanged. Rows (`scripts/contact_scenes.tsv`, `*_park_*`): ringAround_park_teddy_v, ringAround_park_pip_v, circleDance_park_pearl_vv, groupHug_park_bob_vv, bump_park_bob_v, tag_park_pearl_v, chase_park_teddy_v, highFive_park_moss_v, spinHug_park_lavender_v.
