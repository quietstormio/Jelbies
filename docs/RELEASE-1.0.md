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
- Town, Shop, Café (Jelly Cup, Baby latte), the Adoption Center and Jelly Volleyball.
- Park: a clean redesign (one lawn, round trees, flowering bushes, simple pond), up to five Jelbies, visitor Jelbies to befriend, love rises faster than petting, and Park-only toys (seesaw, spring bunny, sandbox).
- Groomer (Jelly Spa in Town): Quick Splash 20, Bubble Spa 40 and Royal Pamper 70 Drops per Jelbie. A shop-front cut-scene with ElevenLabs sounds, then a shiny reveal at home.

### Games
- Jelly Race: pick a Jelbie and race other Jelbies with two foot buttons; curved courses, hurdles with a Jump button, tiers up to Tsunami.
- Jelly Show: Look, Dance and Trick rounds, ranks from Puddle to Ocean.
- Jelly Volleyball: 2v2 beach volleyball with body-only hits (head bonk, belly-flop spike, belly dig). Reached from Jelly Volleyball in Town and a Compete chip. Tiers: Sandcastle, Shore, Reef and Tidal. Trainable Speed, Power, Hops and Timing through drills. Drops, ribbons and trophies.

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
- Permission strings: microphone, speech recognition (NSSpeechRecognitionUsageDescription), photos add-only. All set in the build settings (INFOPLIST_KEY_*); test a clean install on device.
- Privacy manifests: BobV1/PrivacyInfo.xcprivacy and JelbiesWidget/PrivacyInfo.xcprivacy (no tracking, no collected data; UserDefaults, SystemBootTime, FileTimestamp reasons). Both folders are synced groups, so the files ship automatically. After archiving: Generate Privacy Report and Validate App.
- Export compliance: ITSAppUsesNonExemptEncryption=false in BobV1-Info.plist.
- Appearance: UIUserInterfaceStyle=Light (Light only).
- Launch screen: declared once, in BobV1-Info.plist (UILaunchScreen, LaunchBackground).
- Build number: CURRENT_PROJECT_VERSION is 1 in every config of every target. Before each upload bump it everywhere at once, with no CI: `agvtool new-version -all <n>` (if agvtool does not pick up the synced project, sed CURRENT_PROJECT_VERSION in project.pbxproj). App Store Connect rejects a repeated build number for the same version.
- **DEV ARGS MUST BE OFF IN THE ARCHIVE: pass `JELBIES_DEV_ARGS_COND=` on every archive/Product > Archive (the Release config turns them on by default). Check the launch log for the "DEV ARGS ENABLED" line.** (`-AudioLog` is intentionally ungated: read-only diagnostic.) Details: local Release installs define the JELBIES_DEV_ARGS compilation condition (project Release setting JELBIES_DEV_ARGS_COND) so devicectl diagnostics (-AudioLog, -UpgradePoints, -SleepNow, -ClockHour, -SetRoster, -ForceSpecies, -BlobCount) keep working. The App Store archive must clear it: `xcodebuild archive ... JELBIES_DEV_ARGS_COND=` (or set JELBIES_DEV_ARGS_COND to empty in the archive build settings). Confirm the archive scheme has no launch arguments. All of those args read through `DevArgs.enabled` (Jelly/JellyRoster.swift).
- Age rating questionnaire; pricing (TBD by the user).
- ElevenLabs commercial licence check for the generated music and sound effects.
- Screenshots (portrait and landscape) and a preview video.
- iPad (ships in 1.0, TARGETED_DEVICE_FAMILY = 1,2 on the app):
  - Resizable, not full-screen: UIRequiresFullScreen is deprecated (iPadOS 26) and ignored from the iOS/iPadOS 27 SDK (TN3192), so the key is deliberately absent. Every screen must survive arbitrary window sizes and rotation; layout comes from the available size, never UIScreen.
  - All four iPad orientations are declared (INFOPLIST_KEY_UISupportedInterfaceOrientations_iPad); iPhone keeps its three.
  - Launch screen is required for submission from iOS/iPadOS 27 (TN3208): UILaunchScreen with LaunchBackground is in BobV1-Info.plist. Confirm Xcode validation accepts it.
  - Single window: the scene manifest now lives in BobV1-Info.plist (UIApplicationSupportsMultipleScenes=false; INFOPLIST_KEY_UIApplicationSceneManifest_Generation=NO, because the generated manifest forced true). Built Info.plist verified (game state is global: camera, audio, save). Check on an iPad that Assistive Access still launches its scene.
  - Haptics (no Taptic Engine) and Live Activities degrade gracefully; the widget keeps small/medium/large + accessory families.
  - Open (code, not project): a minimum window size (windowResizability(.contentMinSize) + frame(minWidth ~560, minHeight ~420)) in BobV1App.swift.
  - iPad screenshots (App Store Connect; at least one 13-inch set is REQUIRED, jpeg/png, no alpha, up to 10): 13-inch 2064x2752 or 2048x2732 portrait, 2752x2064 or 2732x2048 landscape. 11-inch (1668x2420, 1668x2388, 2420x1668) is optional and derived from the 13-inch set. Capture the real app on the iPad Pro 13-inch simulator: Jelly Race, Jelly Show, Jelly Volleyball, Jelly Spa, Jelly Spring. Strip alpha before upload.
- Device and iOS support; Foundation Models features need a fallback on devices without Apple Intelligence (already plain-text fallbacks).
- App icon.
- TestFlight build and a pass before submission.

## Launch checks added 2026-11-09 (r2-tidy)
- **Alternate app icons (checked, no mismatch).** `ThemePreset.alternateIconName` (UI/ThemeColor.swift) gives nil for Sky Blue (the primary `AppIcon`) and `"AppIcon-" + Capitalised raw value` for the other seven presets: Pink, Mint, Lavender, Yellow, Peach, Teal, Navy. The asset catalog has exactly those seven `AppIcon-*.appiconset` folders plus `AppIcon.appiconset`. project.pbxproj (both app configs) sets `ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon`, `ASSETCATALOG_COMPILER_ALTERNATE_APPICON_NAMES = "AppIcon-Pink AppIcon-Mint AppIcon-Lavender AppIcon-Yellow AppIcon-Peach AppIcon-Navy AppIcon-Teal"` and `ASSETCATALOG_COMPILER_INCLUDE_ALL_APPICON_ASSETS = YES`. Names, catalog and build settings agree; nothing changed. Still worth one on-device tap through every preset after the archive build (setAlternateIconName errors are swallowed in `AppIconSwitcher.apply`).
- **English-only 1.0.** project.pbxproj has `developmentRegion = en` and `knownRegions = (en, Base)`; there are no `*.lproj` folders. `CFBundleDevelopmentRegion` is not written in BobV1-Info.plist by hand; Xcode merges it from the project's development region (`$(DEVELOPMENT_LANGUAGE)` = en) because GENERATE_INFOPLIST_FILE is YES. Confirm it reads `en` in the built Info.plist, and set the App Store Connect primary language to English (U.S. or the chosen English variant). All player text is English only.
- **Unverified under the hand-written scene manifest (UIApplicationSupportsMultipleScenes = false).** Test on a device or iPad before submitting: (1) Assistive Access launch (does the Assistive Access scene still come up?); (2) widget deep link `jelbies://jelly/<id>` (cold start and while running, opens the right Jelbie); (3) Live Activity tap (returns to the game, no second window).
