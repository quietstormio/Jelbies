# Jelbies 1.0 (first release)

## Feature lock

**Jelbies 1.0 is the first release. Feature lock as of 2026-10-25: no new features; fixes and polish only. New ideas go in the Post-1.0 list below.**

After the in-flight items below land, the only allowed work is bug fixes, polish, performance, accessibility and App Store prep. The lock is lifted only if the user says so explicitly. The game is offline-only and stays that way.

## What's in 1.0

### Start
- A short intro video with its own music, skippable with a tap.
- A title screen with the Cloud Jelly look, a looping logo and faceless Jelbie silhouettes drifting in the background; theme colours are chosen in Settings.
- New players start with Bob only. Adopt Pip, Moss and Lavender with Drops at the Adoption Center (second 120 Drops, third 180).

### Room life
- Care: feed, clean (de-lint, soap, rinse, shine, sparkle), pet, squish and play with jelly haptics.
- Feeding: food is tossed into the mouth at a free spot; shop foods carry perks.
- Sleep: Jelbies sleep and fidget (shifts, side rolls, dream twitches, half-wakes, drifting toward sleeping friends).
- Variety AI: less repetition with up to three Jelbies; each has a personality and they avoid acting in sync.
- Toys and furniture (many modelled in Blender) that Jelbies use, with up to three at home.
- Decor placement anywhere on the floor, in portrait and landscape.

### Characters
- Bob: baby blue, the plain locked body.
- Pip: yellow, gummy back spikes (smaller by default; hats cover them). A new signature is pending.
- Moss: green, a head daisy (sits on the hat band when a hat is worn).
- Lavender: lavender, wings with periodic flaps and short flights.

### Social
- Friends: Jelbie-to-Jelbie moves (chest bump, purr together, nuzzle, twirl, follow-the-leader, high-five).
- Friendships grow faster in the Park.
- Guests and sleepovers: invite one Park friend over for a play date or a sleepover.

### Places
- Town, Shop, Café (Jelly Cup, Baby latte), Park (up to five Jelbies, visitor Jelbies to befriend, love rises faster than petting) and the Adoption Center.

### Games
- Jelly Circuit: pick a Jelbie and race other Jelbies with two foot buttons; curved courses, hurdles with a Jump button, tiers up to Tsunami.
- Jelly Show: Look, Dance and Trick rounds, ranks from Puddle to Ocean.
- Jelly Volleyball: 2v2 beach volleyball played with body hits only (head bonk, belly-flop spike, belly dig), with trainable Speed, Power and Hops through drills.

### Progression
- Drops are earn-only; there are no purchases. Races pay most, care pays steadily.
- Ribbons and trophies per Jelbie, shown on a wall shelf and in a Trophies sheet.
- Training improves speed and skills in the games.

### Other
- Photo mode.
- Voice: say a Jelbie's name or a trick word (on device).
- Accessibility: VoiceOver labels, 44 pt targets, contrast fixes, auto-jump setting, shape cues on decor.
- Settings: sound and music, theme colour, accessibility options.
- Offline only: no accounts, no networking, no data leaves the phone.

## In flight at lock time (landing before 1.0 ships)
- Pip signature (dino tail, pending the user's pick).
- Toy play: Jelbies react on placement, come back to toys, take turns or play together.
- Jelly Volleyball and training.
- Blue title screen.
- Theme colour setting.
- Real Settings screen.
- Clean Park redesign with Park-only toys.

## Post-1.0 ideas (not building now)
- Blender versions of the Jelly Cup and latte.
- Hurdle practice in training.
- More race layouts and scenery.
- Share-a-snack social.
- The Feature Bible's idea pool (Claude Doc "Bob - Feature Bible").
- Not coming back unless the user asks: the Garden (removed 2026-10-25), Bowling, a diary, online play.

## Known issues / unverified on device
- Haptics and the perf of 3 Jelbies on device were never fully verified; a measured on-device perf check is still to do.
- Voice (listen mode, name, tricks) not verified on device.
- Show music unverified on device; stage-light banding at the top of the Show.
- Landscape of the newer screens (menu, adoption, photo) unchecked.
- Chirp voice is per slot (Pip in slot 0 sounds like Bob).
- Walk speed +10% was not done (needs deeper foot crown work; the gait is locked).
- In portrait, a front Jelbie can sit under the bottom HUD buttons.
- Pre-existing test failures (likely Xcode 27.1 simulator drift): AnticsLab seed-7 soak, BathSootSeedZero hash, JellyJiggle settle, MotionFootRender slab tets, DecorTests min gap, IdleBehaviour x3, StoreFood toss, BlobBrain soak stumble.
- No app icon yet (the AppIcon set was empty at last check).
- Nothing is pushed to a remote.

## App Store checklist
- Privacy: App Privacy "Data Not Collected" (no networking, no analytics).
- Permission strings: microphone, speech recognition, photos add-only.
- Age rating questionnaire; pricing (TBD by the user).
- ElevenLabs commercial licence check for the generated music and sound effects.
- Screenshots (portrait and landscape) and a preview video.
- Device and iOS support; Foundation Models features need a fallback on devices without Apple Intelligence (already plain-text fallbacks).
- App icon.
- TestFlight build and a pass before submission.
