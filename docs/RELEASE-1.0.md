# Jelbies 1.0 (first release)

## Feature lock

**Jelbies 1.0 is the first release. Feature lock as of 2026-10-25: no new features; fixes and polish only. New ideas go in the Post-1.0 list below.**

The one item still in flight (Pip's signature) is the only open feature work. The Groomer was the user's explicit "one last feature" after the lock and has landed. After Pip's signature lands, the only allowed work is bug fixes, polish, performance, accessibility and App Store prep. The lock is lifted only if the user says so explicitly. The game is offline-only and stays that way.

## What's in 1.0

### Start
- A short intro video with its own music, skippable with a tap.
- The blue title screen ("E · Title screen" design): scrolling blue Jelbie pattern, sparkles, a peeking Jelbie, lip buttons and the swing logo loop. Its colour follows the theme colour setting (8 presets plus custom), which also colours the loading screen.
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
- Pip: yellow, gummy back spikes (smaller by default; hats cover them). A new signature (plush dino tail) is still in flight. Default spikes are smaller, and hats fit over the crown.
- Moss: green, a head daisy (sits on the hat band when a hat is worn).
- Lavender: lavender, wings with periodic flaps and short flights.

### Social
- Friends: six Jelbie-to-Jelbie social moves (chest bump, purr together, nuzzle, twirl, follow-the-leader, high-five).
- Friendships grow faster in the Park.
- Guests and sleepovers: invite one Park friend over for a play date or a sleepover.
- Toy play: Jelbies react when a toy is placed, take turns, and share a two-seat cushion pile.

### Places
- Town, Shop, Café (Jelly Cup, Baby latte), the Adoption Center and the Beach (Volleyball).
- Park: a clean redesign (one lawn, round trees, flowering bushes, simple pond), up to five Jelbies, visitor Jelbies to befriend, love rises faster than petting, and Park-only toys (seesaw, spring bunny, sandbox).
- Groomer (Jelly Spa in Town): Quick Splash 20, Bubble Spa 40 and Royal Pamper 70 Drops per Jelbie. A shop-front cut-scene with ElevenLabs sounds, then a shiny reveal at home.

### Games
- Jelly Circuit: pick a Jelbie and race other Jelbies with two foot buttons; curved courses, hurdles with a Jump button, tiers up to Tsunami.
- Jelly Show: Look, Dance and Trick rounds, ranks from Puddle to Ocean.
- Jelly Volleyball: 2v2 beach volleyball with body-only hits (head bonk, belly-flop spike, belly dig). Reached from the Beach in Town and a Compete chip. Tiers: Sandcastle, Shore, Reef and Tidal. Trainable Speed, Power, Hops and Timing through drills. Drops, ribbons and trophies.

### Progression
- Drops are earn-only; there are no purchases. Races pay most, care pays steadily.
- Ribbons and trophies per Jelbie, shown on a wall shelf and in a Trophies sheet.
- Training improves speed and skills in the games.

### Other
- Photo mode.
- Voice: say a Jelbie's name or a trick word (on device).
- Accessibility: VoiceOver labels, 44 pt targets, contrast fixes, auto-jump setting, shape cues on decor.
- Settings: a full Settings screen from the gear (Appearance with theme colour and live preview, Sound, Accessibility, Voice, Game, About).
- Offline only: no accounts, no networking, no data leaves the phone.

## In flight
- Pip's new signature: a plush dino tail, being redone after the user rejected the first render.

## Landed on g-int since the lock
Toy play, Jelly Volleyball with training, the blue title screen, the theme colour setting, the full Settings screen, the Park redesign with Park-only toys, the Groomer, friends/guests/sleepovers with six social moves, hat crown fit and smaller default Pip spikes.

## Audio
ElevenLabs key renewed 2026-10-25. New audio covers the groomer and volleyball (two beach tracks plus hit sounds).

## Post-1.0 ideas (not building now)
- Blender versions of the Jelly Cup and latte.
- Hurdle practice in training.
- More race layouts and scenery.
- Share-a-snack social.
- The Feature Bible's idea pool (Claude Doc "Bob - Feature Bible").
- Not coming back unless the user asks: the Garden (removed 2026-10-25), Bowling, a diary, online play.

## Known issues / unverified on device
- Haptics and the perf of 3 Jelbies on device were never fully verified; a measured on-device perf pass was skipped at the user's request (minimal testing).
- Unchecked on device: the volleyball spike direction and the toy interactions in the Park.
- Visual nits to check: high-five arm sides, the twirl speed, the groomer line-up spacing.
- Voice (listen mode, name, tricks) not verified on device.
- Show music unverified on device; stage-light banding at the top of the Show.
- Landscape of the newer screens (menu, adoption, photo) unchecked.
- Chirp voice is per slot (Pip in slot 0 sounds like Bob).
- Walk speed +10% was not done (needs deeper foot crown work; the gait is locked).
- In portrait, a front Jelbie can sit under the bottom HUD buttons.
- Pre-existing test failures (likely Xcode 27.1 simulator drift): AnticsLab seed-7 soak, BathSootSeedZero hash, JellyJiggle settle, MotionFootRender slab tets, DecorTests min gap, IdleBehaviour x3, StoreFood toss, BlobBrain soak stumble.
- App icon still missing. Six designs exist in the "Jelbies App Icons" artifact; the user is to pick.
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
