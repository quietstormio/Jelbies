# Handoff

## START HERE (2026-10-25): Jelbies 1.0, feature lock

- **Feature lock:** this is the first release (1.0). No new features; fixes, polish, performance, accessibility and App Store prep only. See [RELEASE-1.0.md](RELEASE-1.0.md) for what is in the game, what is still in flight, the Post-1.0 list, known issues and the App Store checklist.
- **Integration branch:** `g-int` (worktree `.claude/worktrees/g-int`). `round-1022` is older. **Nothing is pushed.** Work branches (g-docs, g-social, etc.) merge into `g-int`.
- **Build Release and install to the phone** (UDID 00008150-000261C63ED8401C, team 5VVYA96U3R). Release, not Debug: Debug makes the jelly sim choppy.

```
cd .claude/worktrees/g-int
xcodebuild -project BobV1.xcodeproj -scheme BobV1 -configuration Release \
  -destination 'id=00008150-000261C63ED8401C' -derivedDataPath dd_sign \
  DEVELOPMENT_TEAM=5VVYA96U3R -allowProvisioningUpdates build
xcrun devicectl device install app --device 00008150-000261C63ED8401C \
  dd_sign/Build/Products/Release-iphoneos/BobV1.app
xcrun devicectl device process launch --device 00008150-000261C63ED8401C <bundle id>
```
  (Adjust the derived-data path if you use another; back signed apps up under ~/BobV1_backups.)
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
