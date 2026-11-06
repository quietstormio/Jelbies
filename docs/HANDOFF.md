# Handoff

## MANDATORY before installing any build on the phone: `scripts/regression-gate.sh` (2026-11-02)
r1055 regressed what the user had already approved (sounds, chatty idle moves, haptics). `.approved-build` holds the commit of the last build the user approved on the phone (set it
to the new commit only AFTER they approve one). The gate builds that commit and HEAD in throwaway worktrees, runs the behaviour-count suite (RoomSFXCountTests: per-kind
idle / antic / social counts, vocal chatter, contact + jump sounds, room-cue haptic sink calls; HapticSinkRegressionTests: the touch / cuddle haptics at the sink) with fixed seeds
on both, and FAILS if any pre-existing kind (count >= 12) or the vocal / contact / old-idle totals fall below 90 % of the approved build, the touch haptics reach the sink less, a
move has no haptic pattern (HapticCueTests), or EmoteFeetTests / GroupEmote*Tests / LineupTests fail. ~25 min, one throwaway sim, derived data reused in `.claude/worktrees/dd_gate_*`
(`--clean` removes it). New things are ADDITIONS on top: they get their own slot (e.g. the solo emotes' treat clock in BlobBrain+Idle `treatMaybeStart`), never a share of an old table.
Haptics: ONE engine owner, `HapticDriver` (Haptics.swift); the room's per-move cues are in `Haptics+Emotes.swift` (a table per IdleKind / SocialKind / SFX cue; a new kind without a pattern does not compile).

## Feet stay attached (2026-11-02: read before adding or changing any emote)

- **How the feet attach.** Each foot is a separate closed piece (`FootBean`, `Skinner.beanPos`) that the brain places every tick (`BlobBrain.driveLimbs` / `fillBeansRigid` / `refitBeans`). The skin then enforces two last lines (`Skinner.applyBeanJoin`): the LEASH (the piece's top, i.e. pole + neck rings 11 and 12, must lie >= 2 cm inside the fitted egg) and the TETHER (pole <= 0.55 m from the hip, a point skinned with the body). They are safety nets: if either has to move a piece, the brain placed it wrong.
- **The invariant (every emote, every character, bare and with shoes).** No frame in which the leash or tether acts; with both pieces off the floor the neck ring is >= 70 % of the standing boot's, every neck meridian has a point inside the drawn body by >= 1 cm (closed join), and the collar fillet moves no skin more than 2 cm. The brain keeps the top of every piece >= 4.5 cm inside (`BlobBrain.attachBean`), tucks both pieces into the body in the air (`airBothFeet`), and `Skinner.collarFade` removes the collar fillet while both feet are up. A teleport carries the pieces along (`Skinner.teleportJump`, `BlobBrain.noticeTeleport`).
- **Adding an emote safely.** 1) Add the case (IdleKind / Script / gait name). 2) Give it a scenario in `OnePieceInvariantTests.idleTable` (or `gaitScenario`): `testEveryMoveIsListed` and `EmoteFeetTests.testEveryEmoteKeepsItsFeet` fail until you do, and the same test then covers the new emote for all 6 characters x bare / shoes automatically. 3) Run `EmoteFeetTests` (named tests for the emotes that broke on the phone + the auto-coverage; the only exemptions are in `EmoteFeetTests.exempt`, each with its reason). 4) The runtime guard (`Skinner.leashObserver`, armed in `OnePieceInvariantTests.run`) fails ANY feet test, naming the emote, if the leash or tether moved a piece. If it fires, fix the placement (the move's foot targets), never the leash.
- **Phone check.** Launch with `-FootLog 1`; the app writes a JSON line for every frame the leash / tether acts (pole_hip, pull, script, idle kind, tilt). After the new emote: play it, then look for `pull` lines in the log. None = fine.

## Touching without overlapping: the contact profile (2026-11-02/03, g-featclip; read before adding or changing any touching emote)
The user's rule: "all touching emotes must look polished: touching, but never overlapping like a buggy game". One engine now answers "how far apart are two Jelbies' DRAWN skins": `Melon/ContactProfile.swift` (`ContactField`).
- **The profile** (per body, per skin pass, built inside `JellyParallel.skin`, parallel): the farthest skinned vertex of each of K = 128 direction bins around the body's ROOT (`JellyActor.floor`), horizontal, from the drawn skin (egg sampled every 3rd vertex, limb / ear / tail blocks every 2nd of the 24 195 vertices). Includes arms, feet, Teddy's ears + pom, Pip's tail; lying (1.27 x wider), leaning, squash, breathing come for free. Feature-only points (wings at their CURRENT fold, daisy, spikes) are filled by `FeatureSet.frame`. Cost 0.025 ms a body (parallel).
- **THE metric**: `ContactField.gap(a, b)` = the distance the two bodies could still slide toward each other along their root axis before the drawn footprints touch (exact translation gap of the two polygons). + apart, - sunk in; 0 = touching. Agrees with the mesh ground truth (every projected triangle edge, 1 mm lateral sampling) to 0.2-1.3 mm for Bob / Teddy / Pearl pairs, 3-5 mm with Pip's tail; also `gap(a, at: pa, b, at: pb)` for a hypothetical position (3 us), `ext(id, dir)` (a 0.2 us radial lookup, a few mm off near arm / tail edges: use only to decide "is a pair near"), `featureExt`, `featurePoints`, `clearance(of:ownerRoot:against:)`.
- **The wall** (`MelonStage.keepApart`): a max with the exact gap for a near pair: a root is never put where the skins overlap (the soft spring stays; the wall is a max of two continuous maps, no pop). `ContactField.enabled = false` brings back the old centre-distance rules; a rig that never skins (the lab) has no profiles and keeps them too.
- **Settle controller** (`Melon/ContactSettle.swift`): `ContactSettle.step(a, b, target: 0, anchoredA:, anchoredB:)` once per fresh profile: measures the gap, nudges the roots (`BlobBrain.contactNudge`) along the pair axis, error split between the two unless one is anchored (asleep / lying first / held), <= 1.5 cm a step, gain 0.15 on the error where it is heading (lead 3 frames: the skin trails the root; swept: 0.25 hunts +-3 cm on a lying pair, breathing included), deadband +-0.5 cm. From 0.6 ... 2.0 u starts it is in the band in about 40-60 frames (anchored: 53-65) without overshooting more than 1 cm; a lying body's own breathing keeps the raw gap within +-0.9 cm. Applied so far: the lying snuggle (`BlobBrain.snuggleTick`, lie-down phase 1 = only pushes out of overlap, phase 2 = settles to touching). Every other touching stance is to be migrated: call `ContactSettle.step` from the stance's per-step code with the partner brain.
- **Contact event** (`BlobBrain+Contact.contactTick`): the first time the gap is <= +1 cm: a jelly kick on both, ONE squish sound + ONE haptic (`roomCue(.sfx(.squish))`) per touch (the lower id announces; `BlobBrain.contactEvents` counts them); re-armed once the gap is > +3 cm; 0.35 s least between events of a pair; the settle's last mm of press never fires again. Works in a stance as in a roaming brush.
- **Wings** fold up against the owner's back (`FeatureSet.wingFoldWant`: the open wings' points vs the neighbour's skin footprint, 2 cm margin, 6 cm hysteresis, 0.16 s spring) when a neighbour's skin is within their reach; `FeatureClip` stays as the render-side safety net for anything left inside.
- **Lying pair**: `BlobBrain+LieClear.swift` walks to the spot a flat body needs, tips toward the neighbour, then the settle puts the skins in contact.
- **Tests**: `ContactProfileTests` (profile vs mesh truth, pair gap vs mesh truth, perf), `ContactSettleTests` (convergence, anchored, once-per-touch + re-arm, lying snuggle, every stance's events vs touch episodes), `FeatureClipTests` (lying pairs, wing fold, features never inside a neighbour), `ContactPolishTests` (the catalogue, `docs/CONTACT_EMOTES.md`).
- **Known**: today's stances other than the lying pair still stand where their choreography puts them (see CONTACT_EMOTES.md: hug / dance / conga stances overlap by design, boop / bump / noseBoop / highFive stop short): migrate each to `ContactSettle` (target 0), then drop its own gap constant (`closeGapFactor`, focus row gaps) in favour of the pair's measured gap. Pip's tail does not curl in yet (FeatureClip catches it).

## Play mode: toss the ball (2026-11-02, g-playtoss)

- **Flow.** Heart menu -> Play -> a toy picker on the same sliding strip as Feed (`CareMenu.pickerRow`, `ConsumableKind.toy`): only toys the player OWNS (`PlayToyRegistry.offered`); none owned -> a button to the Shop's Toys tab (`ShopTab.pending`). A toy is ONE registry entry (`Toys/PlayToy.swift`: `PlayToy` protocol; `BallToy` for the bouncy / soccer / beach ball; the bubble wand is `BubbleWandStub` until g-bubbleblow's `BubbleWand` replaces it and registers in `registerBuiltIns`). The wand is sold as store item `toy-bubbleWand` (StoreKind `.toy`, 40 JellyCoins; the key is `StoreBook.toyKey("bubbleWand")`).
- **Play mode.** `GameCare.beginPlay(ball:)` -> `PlayToss` (Play/PlayToss.swift): camera eases to `GameCamera.playPose` (`GameCamera.playBlend`, global), the Jelbies stand abreast, the ball sits in the hand at the bottom, Done (top-left) leaves. `PlayChrome` is the drag surface: the flick -> `TossAim.throwFor` (landing point on screen = release + direction x reach x speed; aim assist pulls toward the Jelbie nearest the swipe, <= 0.95).
- **Return logic (never fetch).** Header: the Jelbie it is heading for steps under it (`requestNow(.goTo)`), hops (`IdleKind.tossHeader`, started `tossHeaderLead` s before the ball arrives), the ball meets his crown -> arc back toward the hand (good 64 %, short 26 %, weak 10 %); a good one lands in the bottom band = caught. Miss: `IdleKind.tossBump` = walk round behind the ball, soccer stomp, ball rolls toward the front (each nudge stronger; <= 5 nudges, safety-net rescue at 9.5 s). With 2-3 Jelbies a header / bump may be a pass to a friend.
- **Feet.** `idle tossHeader`, `idle tossBump`, `toss: header`, `toss: bump`, `toss: rally` are in OnePieceInvariantTests (auto-covered by EmoteFeetTests, 6 characters x bare / shoes). Run only these with `TEST_RUNNER_ONEPIECE_ONLY=toss`.
- **Captures.** `-SkipIntro 1 -NewGame bob,pearl,teddy -NewGameCoins 10000 -MainMenu 0 -PlayDemo N` (1 auto-flick loop, 2 picker with toys, 3 empty picker, 4 play mode without auto-flick; `-PlayDemoBall soccer|beach`, `-PlayDemoQuality good|short|weak`, `-PlayDemoRounds n`, `-PlayDemoSpeed screens/s`). `[playtoss]` log lines show every event.

## Weather (2026-11-02)

- A storm rolls in every 2-5 hours of play (`WeatherBook`, persisted: relaunch neither rerolls nor repeats), lasts 2-4 min: build-up (sky darkens, rain, far rumbles, one Jelbie peers out of a window), peak (gentle two-pulse lightning + soft thunder every 7-15 s; the huddle), clearing (shake-off, scatter). `-Storm 1` forces one 5 s after the room is up (`-Storm 2` at the peak, `-Storm 3` at the clearing, `-StormDelay s`).
- Window: rain, gloom and flash are applied per frame at the room-cache blit (the cache build marks the glass with alpha 2) and in the window shader; the room dims / lifts through the post exposure. No cache rebuild, no extra pass (`WeatherPerfTests`).
- Jelbies: `StormReactor` (BlobBrain+Weather.swift) on the storm pose channel `BlobBrain.storm`; feet suite `StormFeetTests`. Sounds `storm_*.m4a` are real ElevenLabs sounds (2026-11-02); the sigh is a Jelbie-voice coo.
- Sound style: see docs/SOUND_STYLE.md (the Jelbie voice band, the vocal prompt template, SFX rules, loudness targets, which voice each character uses; Teddy and Pearl share Lavender's).

## Disk hygiene

Run `/cleanup` (`scripts/cleanup-safe.sh`, dry run first) before big multi-agent rounds. Every agent must build with `-derivedDataPath .claude/worktrees/dd_<name>` and delete its own simulators (`xcrun simctl delete <udid>`) when done.

## START HERE (2026-10-25): Jelbies 1.0, feature lock

- **Species signature rule (2026-10-26):** signatures belong to a colour species and never appear on another colour; see [Species.md](Species.md).
- **Feature lock:** this is the first release (1.0). No new features; fixes, polish, performance, accessibility and App Store prep only. Only Pip's new signature (plush dino tail, redone after the user rejected the first render) is still in flight. Landed on g-int: toy play, Jelly Volleyball + training, blue title screen, theme colour, full Settings, Park redesign, Groomer (the user's explicit "one last feature"), friends/guests/sleepovers, hat crown fit. See [RELEASE-1.0.md](RELEASE-1.0.md) for what is in the game, the Post-1.0 list, known issues and the App Store checklist.
- **Integration branch:** `g-int` (worktree `.claude/worktrees/g-int`). `round-1022` is older. **Nothing is pushed.** Work branches (g-docs, g-social, etc.) merge into `g-int`.
- **Build Release and install to the phone** (UDID 00008150-000261C63ED8401C, team 5VVYA96U3R). Release, not Debug: Debug makes the jelly sim choppy.

```
cd .claude/worktrees/g-int
xcodebuild -scheme BobV1 -configuration Release -destination generic/platform=iOS \
  -derivedDataPath ./dd_i -allowProvisioningUpdates DEVELOPMENT_TEAM=5VVYA96U3R build -quiet
xcrun devicectl device install app --device 00008150-000261C63ED8401C \
  dd_i/Build/Products/Release-iphoneos/BobV1.app
xcrun devicectl device process launch --device 00008150-000261C63ED8401C \
  --terminate-existing io.mgsllc.BobV1
```
  - A lone "failed with exit code 0 but produced no further output" line is harmless if the binary timestamp is fresh.
  - Useful launch args: `-Intro 1`, `-MainMenu 0`, `-BlobDrops.v1 N`.
  - Error 4016 means the phone is locked or away.
  - Back up signed apps under ~/BobV1_backups.
- **Unverified / open:** volleyball spike direction and Park toys on device; high-five arm sides; twirl speed; groomer line-up spacing; measured perf pass skipped at the user's request; app icon missing (pick from the "Jelbies App Icons" artifact). ElevenLabs key renewed 2026-10-25 (groomer and volleyball audio done).
- **Rules:** game is offline-only; the Garden is removed; one fix at a time, confirmed on the phone.

---

# Archive

---
name: project-handoff-2026-10-20
description: "State of the project after the 2026-10-21 integration: every WIP branch is merged on `integrate`, final touches (roster cap 3, -SetRoster, Jelbies rename) on `final-touches`. Read this first in the next session."
metadata:
  node_type: memory
  type: project
  originSessionId: 6a40096b-092a-48d0-8cbe-4e00ccea7702
  modified: 2026-10-21T12:00:00.000Z
---

## START HERE: state at end of 2026-10-21

**Everything is on branch `release` (pushed). That is the build for the phone.** `main` is still checkpoint 6; merge `release` into `main` when the user OKs it.

`release` = final-touches + integrate + these, in merge order:
1. **rename-app**: home-screen name "Jelbies" (INAlternativeAppNames "My Jelbies", "Bob"). The app still has NO icon (empty AppIcon set); offer to design one.
2. **lavender-wings**: wings 15% smaller, periodic flap bursts every 4–9 s (quieter in race/training, off when asleep/eating/bathing).
3. **roll-feet**: `startRoll` releases foot targets, so the feet no longer come off on a random roll. FeetAttachTests now measure the drawn foot.
4. **jelly-show**: the Jelly Show (BobV1/Show/*): Studio, Condition jars, lobby, Look/Dance/Trick rounds, results, Puddle→Ocean ranks, Drops payouts.
5. **room-movement** (9c4f443):
   - Come-here: blocking peers step aside (`clearWay`). Others no longer freeze after you interact with one.
   - Roam area is derived from the camera projection and spans almost the whole visible floor: 4% side margin, 3% bottom margin, furniture cut-outs around the sofa, plant and lamp.
   - A goal pick that avoids parking in front of a mate. Grime per roam unit retuned so dirt/minute is unchanged.

**Signed Release app:** ~/BobV1_backups/release_app/BobV1.app. Install it with:
`xcrun devicectl device install app --device 00008150-000261C63ED8401C ~/BobV1_backups/release_app/BobV1.app`
The phone's roster is already saved as Pip/Moss/Lavender, so no `-SetRoster` is needed.

### Open items / known issues
- **Walk speed +10% (user asked): NOT done.** Faster cadence pushed the FeetAttach gap past −0.020 and the run speed past its cap. Doing it needs a deeper hidden foot crown or tighter foot follow first. The gait itself is locked.
- In portrait, a Jelbie at the very front can sit under the bottom-corner HUD buttons and the go-out pill (the HUD trim was removed so they use the full floor). Pull the front margin in if the user dislikes it.
- Landscape sides are wall-limited (x ±5). Going wider needs a camera change, which has not been touched.
- Pre-existing test failures (they also fail on base commits, likely Xcode 27.1 sim drift):
  - AnticsLab seed-7 soak
  - BathSootSeedZero pixel hash
  - JellyJiggle settles-to-zero
  - MotionFootRender slab tets 0.0476 against 0.05
  - DecorTests BedAndDiningRoom min gap
  - IdleBehaviourTests ×3
  - StoreFood tossed-into-mouth
  - BlobBrain autonomy soak has a seed-sensitive stumble inversion.
- Other nits:
  - stage-light banding at the top of the Show
  - Show music unverified on device
  - chirp voice is per slot (Pip in slot 0 sounds like Bob)
- The full suite was not re-run after the final room-movement merge. Only targeted classes ran on room-movement itself.

### Next-batch candidates (user picks; no diary, no walks/outings)
- Adoption shop: buy Pip/Moss/Lavender with Drops; new players start with Bob only. See docs/Species.md.
- A third, trainable earning game.
- Camera games with a selfie preview bubble.
- App icon.
- Walk speed +10% (needs the foot work above).
- More Feature Bible items (Claude Doc "Bob — Feature Bible").

---

## Earlier state (2026-10-21 morning)

All seven work-in-progress branches are merged on **`integrate`** (1e8dea5), plus a camera fix. `main` is still checkpoint 6. Merge order was liveliness → characters → curvy courses → on-device AI → Ears → Apple extras → camera-fix-27 → soccer. A regression run on `integrate` happens in the main tree; `final-touches` (this branch, from 1e8dea5) carries the user decisions below and merges onto it.

### What is on `integrate`
| feature | what it is |
|---|---|
| Liveliness | expressions, brows, blush; mid-walk flourishes; reaction bus; roll / sigh / hmph |
| Characters | Pip (yellow, spines), Moss (green, daisy, daisy-on-hat), Lavender (lavender, wings + flap-hop); wear compat rules; 4-diner dining queue |
| Soccer | ball + mini goal replace the football: kick, dribble, pass, shoot; the net puffs |
| Curvy courses | Puddle / Ripple / Splash / Wave, course picker, follow camera |
| On-device AI | FoundationModels natural voice commands (Tier A) with the rule parser as fallback (Tier B); EventLog, thought lines (diary removed) |
| Ears | SoundAnalysis + DSP sound reactions: listener, reactor, HUD ear button |
| Apple extras | App Intents / Siri, Lock Screen + StandBy widgets, Live Activities (race / nap / pep) |
| camera-fix-27 | drawable-aspect projection, pose log, CameraAspectTests (Xcode 27.1) |

### Final touches (`final-touches`, user decisions 2026-10-21)
- **Roster cap = 3** (`JellyRoster.maxCount`, `JellyShare.maxJellies`). Bob, Pip, Moss and Lavender all stay AVAILABLE (palettes, features, sleep-mask palettes, voice names); at most three live in the room.
- **The room is a roster**, not a count: `JellyRoster.current` is an ordered list of characters by slot, saved under `BlobRoster.v1` (default Bob, Pip, Moss). Slots index everything that runs the room; `JellyProfile.character` carries the identity (keys, colour, feature, name). With the default roster slot == character, so the phone's saved data did not move.
- **`-SetRoster pip,moss,lavender`** launch argument: replaces the saved roster with exactly those, keeps each character's saved data, initialises a newcomer fresh, persists, idempotent (SetRosterTests). The coordinator launches the app once with it on the user's phone.
- **Fresh install** still starts with Bob, Pip, Moss. Adoption (Bob only to start, Drops to adopt) is documented in docs/Species.md, not built.
- **"Jellies/Jelly" → "Jelbies/Jelbie"** in user-visible creature text (decor descriptions, hat description, widget empty-state, snapshot default name, race blocker, voice/AI fallback name, accessibility label/hint). "Jelly Circuit", "Jelly Show" and the material ("jelly jars", the studio's "Light through jelly") are kept. No type or identifier was renamed; `CFBundleDisplayName` untouched.

### Needs on-device checks
- `-SetRoster pip,moss,lavender` once, then a plain relaunch: Pip in slot 0 wears yellow + spines, Lavender flaps, the widget / Siri roster shows Pip, Moss, Lavender; Bob's data is still on his keys for when he returns (`-SetRoster bob,pip,moss`).
- Performance with three Jelbies with features on (spines + daisy + wings) in Release; the sim should not go choppy.
- Haptics (squish / let-go / jelly jiggle), Ears (mic permission string, reactions), Siri phrases (the display name is "Bob", so phrases read "in Bob"), widget snapshot + portraits, Live Activities for race / nap / pep.
- Landscape: decor, food, UI, the course picker and the widgets' deep links.
- Soccer: kick / dribble / shoot by hand; the worker was stopped mid-debug before the merge.

### Known caveats
- Backpack + any neck item folds Lavender's wings (characters branch).
- The 4-diner dining queue and the race "fourth Jelbie parks off the track" code are unreachable with the cap at 3; their two tests are skipped (`XCTSkip`), not deleted.
- Slot 0 drives the Bob-only paths (meals, Clean, voice, close-up). With a non-Bob character in slot 0 those paths drive that character; it is tested in SetRosterTests but not yet seen on a phone. The stage-level roster paths (sleep-mask palette, fitting-room palette, brain feature) read `JellyRoster.current`, which `GameCare(roster:)` does not set, so they are exercised only by the default roster in tests.
- Still per SLOT, not per character: the chirp / babble voice files (`AudioHub`: `chirp_jelly<slot+1>`), so Pip in slot 0 sounds like Bob; and `BlobSelect`'s single-Jelbie fallback card is hard-coded "Bob" (reachable only with `-BlobCount 1`). Outfits (`StoreBook.worn`) ARE saved by character.
- The curvy-courses branch merged with three known failing tests listed in its commit report (puddle golden start-z, Wave camera halfWidth, seed-19 timeout).
- AI prompts still say "jelly pets" to the model (not user-visible); "Jelly Soap" (Clean chrome) was kept as a product name.
- Old stale worktrees (agent-a0bab…, a0ebcb…, a1811…, a52d4…, a5839…, a8881…, a89c1…, ab713…, ae999…) can be cleaned up only after the user OKs it.

## Next
1. Merge `final-touches` onto `integrate` after the regression run; then `integrate` → `main` as checkpoint 8.
2. Build the Jelly Show (designed: canvas https://claude.ai/artifact/SNrMLuH93KdAP6ofr1bEGg, jelly-jars Condition screen; [[project-beauty-contest]]).
3. Adoption flow (docs/Species.md) when the Show's earn rate is confirmed.

## Where things are
- Scratchpad: the /tmp scratchpad is wiped on reboot. It was copied to ~/BobV1_backups/scratchpad_2026-10-20/ (26 GB). Key items: art exports (food_art/export, wear_art/export, char_art/export + compat.json), plans (soccer_plan.md, fixC_diag.md, contest_research*.md, music_pick/picks.json), captures.
- The phone has the fix-round-B build (pre-7c). The signed app from `final-touches` is at `dd_sign/Build/Products/Release-iphoneos/BobV1.app` inside its worktree (rebuild if the worktree is gone).

## Performance
See docs/PERFORMANCE.md: no Liquid Glass over the game view, thermal-first governor, how to measure on the phone.
