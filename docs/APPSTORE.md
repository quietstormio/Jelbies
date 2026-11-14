# Jelmiko 1.0: App Store Connect submission pack

Prepared 2026-11-09 from branch `appstore-pack` (based on `3d340b3f`). Every fact below comes from the code or the docs in this repo. Where Apple's rules are quoted, the source is a page fetched on 2026-11-09 and linked in the section.

App facts used throughout:

| Item | Value | Where it comes from |
|---|---|---|
| Name on the Home Screen | Jelmiko | `INFOPLIST_KEY_CFBundleDisplayName` in project.pbxproj |
| Bundle ID | `io.mgsllc.BobV1` | project.pbxproj (widget: `io.mgsllc.BobV1.JelbiesWidget`) |
| Version | 1.0 (`MARKETING_VERSION`), build `CURRENT_PROJECT_VERSION` 1 | project.pbxproj |
| Devices | iPhone and iPad (`TARGETED_DEVICE_FAMILY = "1,2"`) | project.pbxproj |
| Minimum OS | iOS / iPadOS 26.2 (`IPHONEOS_DEPLOYMENT_TARGET`) | project.pbxproj |
| Company | MGS LLC | docs/PRIVACY.md |
| Support email | dione@mgsllc.io (the only address used anywhere) | `SupportText.email` in Settings/SupportPage.swift, docs/SUPPORT.md |
| Language | English only (`knownRegions = (en, Base)`) | RELEASE-1.0.md |
| Appearance | Light only (`UIUserInterfaceStyle = Light`) | BobV1-Info.plist |

---

## 1. Name and subtitle

App Store Connect limits: name 30 characters, subtitle 30 characters. Counts below were measured with a script, not by eye.

**App name (pick one)**

| # | Name | Chars |
|---|---|---|
| A (recommended) | Jelmiko | 7 |
| B | Jelmiko: Baby Jelly Pets | 24 |
| C | Jelmiko - Jelly Pet Game | 24 |

A matches the Home Screen name and the in-app logo. B and C put "jelly" and "pet" into the searchable name; use one only if "Jelmiko" alone is taken or you want the extra search weight.

**Subtitle (pick one)**

| # | Subtitle | Chars |
|---|---|---|
| A (recommended) | Cuddly baby jellies to raise | 28 |
| B | Care, play and race jellies | 27 |
| C | An offline pet game for kids | 28 |

If you choose name B or C, do not reuse its words in the subtitle (Apple indexes both fields together). With name A, subtitle A or B is fine.

---

## 2. Promotional text and description

### Promotional text (limit 170)

```
Raise up to three baby jellies. Feed them, play, dress them up, race and perform in Jelly Show. Works fully offline: no accounts, no ads, no purchases.
```

(Counted: 151 characters.)

### Description (limit 4000; this one is about 2,000)

```
Meet your Jelmiko: baby jellies from Wobble Isle who need someone to look after them.

You start with one Jelmiko, a welcome gift from the Jelly Spring, and you can bring home up to three. Bob is blue, Pip is yellow with gummy spikes, Moss is green with a little daisy, and Lavender is purple with tiny wings. Later you can adopt special Jelmiko in the Jelly Spring: Teddy, Pearl and Panda.

Look after them
Feed them snacks, fill their drinks, tidy up with a bubbly clean, and give them a gentle squish and a cuddle. Jelmiko yawn, stretch, wander, nap, make friends and notice each other, so it is lovely just to sit and watch them.

Play
Pick a toy and play together. Decorate the room, dress your Jelmiko in hats and clothes, and take photos in Photo mode.

Go out in Town
Visit the Shop, the Café, the Park and Jelly Spa. In the Park your Jelmiko meet visitors and make friends. Invite a friend over for a play date or a sleepover.

Compete and earn JellyCoins
Jelly Race: run curved courses with two foot buttons and jump the hurdles.
Jelly Show: show off your Jelmiko's look, dance and tricks.
Jelly Volleyball: a 2 v 2 beach game where Jelmiko bonk, dig and spike with their bodies.
Win ribbons and trophies, and spend JellyCoins in the Shop, the Café and Jelly Spring.

Talk to them
Hold the mic button and say your Jelmiko's name or a trick. Listening happens on your device.

Made for calm, safe play
- Works offline. There is no internet connection needed to play.
- No accounts, no ads, no in-app purchases and no tracking.
- JellyCoins are earned by playing and cannot be bought.
- Anything that leaves the game (sharing a photo, opening Settings, or emailing support) is behind a grown-up hold button.
- Voice is understood on the device and is never recorded or sent anywhere.

Also on your Home Screen and Lock Screen
A widget shows how your Jelmiko are doing, and Live Activities follow a race or a nap.

Questions? dione@mgsllc.io
```

Fact checks behind the description:
- Welcome gift, Wobble Isle, Jelly Spring: docs/Species.md lore section and `AdoptionPrice` in Start/StartFlow.swift.
- Four starters, three specials, max three at home: docs/Species.md (`JellyRoster.maxCount`).
- Care, toys, wear, decor, Photo mode: RELEASE-1.0.md "Room life", Settings > Photo mode (`actionRow("Photo mode"...)` in Settings/SettingsScreen.swift).
- Town places: `islandNodes` in Store/AroundTownIsland.swift (Jelly Show, Jelly Race, Shop, Park, Café, Jelly Spa, Home).
- Games: RELEASE-1.0.md "Games". Park friends, guests, sleepovers: RELEASE-1.0.md "Social".
- JellyCoins are earn-only: RELEASE-1.0.md "Progression", Species.md prices.
- Voice on device: `DictationTranscriber` + `SpeechAnalyzer` in Voice/SpeechInput.swift, usage strings in project.pbxproj.
- Widget and Live Activities: JelbiesWidget/, LiveActivity/LiveActivities.swift (kinds `race` and `nap`).
- No promise is made about Apple Intelligence, Siri, accessibility awards or age suitability beyond what is in the code.

Two wording notes for the owner:
1. The in-app text says "phone" in many places (for example "Everything stays on this phone"). The description says "device" because the app also ships on iPad.
2. Do not add "for ages X and up" to the description; the age rating field does that, and the app is not in the Kids Category.

### Character-count check

| Field | Limit | Count |
|---|---|---|
| Promotional text | 170 | 151 |
| Description | 4000 | 1944 |

---

## 3. Keywords

100 characters maximum, comma separated, no spaces after commas. Words already in the name and subtitle are left out because Apple indexes those anyway (written for name A and subtitle A).

```
pet,virtual,cute,care,race,volleyball,offline,kids,dress,photo,friends,creature,toys,cafe,park,spa
```

Count: 98 characters.

---

## 4. Category

- **Primary: Games.** Reason: it is a game (the plist already declares `LSApplicationCategoryType = public.app-category.simulation-games`), with three mini-games and JellyCoins.
- **Secondary: Entertainment.** Reason: it fits the "watch your pets" side of the app. (Alternative secondary: Education is not recommended, the app makes no learning claims.)
- **Games subgenres to pick if prompted:** Simulation, then Family.

Not in the Kids Category (owner decision, see memory "Launch decisions 11-08"). The grown-up hold gate is there so the app behaves well around children, but nothing in the listing should say "Kids Category" or "Made for Kids".

Side effect to know about: Apple's page says apps with Games or Entertainment as primary or secondary category get an extra Korea regional rating (GRAC) on the Korean App Store. That is automatic and the rating is based on the answers in section 5.

---

## 5. Age rating questionnaire

Source (fetched 2026-11-09): https://developer.apple.com/help/app-store-connect/reference/app-information/age-ratings-values-and-definitions

Apple's 2025 revision replaced the old 4+/9+/12+/17+ sets with 4+, 9+, 13+, 16+ and 18+, and added new questions (In-App Controls, Capabilities, Medical or Wellness, Chance-Based Activities). The page above lists these categories as of today. The question labels below follow that page; the App Store Connect form may word the options slightly differently, so read each description as you click.

Expected result: **4+**.

### In-App Controls

| Question | Answer | Code fact |
|---|---|---|
| Parental Controls | No | The grown-up hold gate (UI/ParentGate.swift) stops a child from leaving the app (Settings, Shortcuts, the share sheet, the support email). It does not monitor, limit or filter content for a child, so the safest honest answer is No. If the form's wording makes you want to say Yes, it does not change the rating. |
| Age Assurance | No | No age checks, no Declared Age Range calls, no accounts (grep of the source finds none). |

### Capabilities

| Question | Answer | Code fact |
|---|---|---|
| Unrestricted Web Access | No | No WKWebView or SFSafariViewController anywhere in BobV1/, Shared/ or JelbiesWidget/. The only URLs opened are `UIApplication.openSettingsURLString`, `shortcuts://` and a `mailto:` link, all behind the hold gate (UI/ParentGate.swift, Settings/SupportPage.swift) or the Ears "denied" hint. |
| User-Generated Content | No | The player types Jelmiko names that stay on the device. Nothing is distributed to other people inside the app. A photo can be shared only through the system share sheet after the gate. |
| Social Media | No | No feeds, likes or sharing inside the app. |
| Messaging and Chat | No | No player-to-player communication of any kind. Friends in the Park are computer-controlled visitors. |
| Advertising | No | No ad SDK. The app never connects to anything. |

### Mature Themes

| Question | Answer | Code fact |
|---|---|---|
| Profanity or Crude Humor | None | Jelmiko speak in chirps and babble. Park visitor text is checked by Park/ParkTextSafety.swift and is written to be kid-friendly. |
| Horror/Fear Themes | None (see note) | Pets, food, toys, beach volleyball. There is a thunderstorm weather effect and a "scaredy huddle" reaction (Melon/Weather.swift, Melon/BlobBrain+Weather.swift). It is a cosy cartoon storm and the Jelmiko are comforted, so None is the honest answer. If you decide a storm counts, "Infrequent" moves the rating to 9+. |
| Alcohol, Tobacco, or Drug Use or References | None | None. The Café sells a Jelly Cup and a Baby latte (RELEASE-1.0.md), which are pretend treats for the Jelmiko, not references to a drink for people. |

### Medical or Wellness

| Question | Answer | Code fact |
|---|---|---|
| Medical or Treatment Information | None | Nothing of the kind. |
| Health or Wellness Topics | None | Feeding, cleaning and napping are pet-care play. No calorie, diet or exercise advice for the player. |

### Sexuality or Nudity

| Question | Answer | Code fact |
|---|---|---|
| Mature or Suggestive Themes | None | Jelmiko hug, nuzzle and cuddle. The nose-boop emote that read as a kiss was deleted on purpose, and face-to-face face-touch emotes are not allowed (project memory "No kiss emote, ever"). |
| Sexual Content or Nudity | None | None. |
| Graphic Sexual Content and Nudity | None | None. |

### Violence

| Question | Answer | Code fact |
|---|---|---|
| Cartoon or Fantasy Violence | None | Volleyball hits are body-only (head bonk, belly-flop spike, belly dig) on a ball. Nobody is hurt. Races and shows have no combat. |
| Realistic Violence | None | None. |
| Prolonged Graphic or Sadistic Realistic Violence | None | None. |
| Guns or Other Weapons | None | None. |

### Chance-Based Activities

| Question | Answer | Code fact |
|---|---|---|
| Gambling | None | No real money, no purchases at all. |
| Simulated Gambling | None | No betting or wagering of JellyCoins anywhere. Prizes are fixed by placing (Jelly Race, Jelly Show, Jelly Volleyball). |
| Contests | None (or Infrequent, see note) | Apple defines Contests as events where users compete with one another. Jelly Race, Jelly Show and Jelly Volleyball are against computer rivals made up per race (`LocalRivalSource` in Race/RaceModel.swift). No ranking against real people exists. Apple's own table lists "Infrequent contests" under 4+, so either answer still gives 4+. |
| Loot Boxes | None | There is no purchase of any kind, so nothing can be a purchasable loot box. Random elements are free: Park visitors can appear in a rare variant colour (`mutation` chance in Park/ParkModels.swift) and Jelly Spring shows a daily colour at a fixed price (AdoptionPrice, Start/StartFlow.swift). Neither is bought blind. This also means no Australian loot box regional rating. |

### Result

4+ globally. The Korean regional rating will be shown too because of the category (see section 4); apart from that the result follows from the answers above.

---

## 6. App Privacy (the nutrition label)

**Expected answer: Data Not Collected** ("No, we do not collect data from this app"). The code confirms it. Apple's help page for this form: https://developer.apple.com/help/app-store-connect/manage-app-information/manage-app-privacy

### Evidence

- **No networking in the app code.** Grep of BobV1/, Shared/ and JelbiesWidget/ for `URLSession`, `URLRequest`, `NWConnection`, `NWPathMonitor`, `WKWebView`, `SFSafariViewController`, `Firebase`, `MetricKit`, `StoreKit`, `GameKit`, `CloudKit`, `AdSupport` and `AppTrackingTransparency` finds no use. The only `https?://` strings are not network calls. (Re-run the grep before archiving; see below.)
- **No analytics, no ads, no accounts, no purchases.** Confirmed by the same grep; `ITSAppUsesNonExemptEncryption = false` in BobV1-Info.plist for the same reason.
- **Speech runs on the device.** Voice/SpeechInput.swift uses `DictationTranscriber` and `SpeechAnalyzer` (the newer on-device framework, not `SFSpeechRecognizer`), with `AssetInventory` to install the language pack. The audio is turned into text in memory; there is no recording to a file. The microphone usage string says so: "Sound is understood on your phone and is never recorded or sent anywhere."
- **Ears (the optional always-on listening) is off by default.** Audio/EarsListener.swift reduces the audio to signal measurements and then drops it.
- **Photos are add-only.** `PHPhotoLibrary.requestAuthorization(for: .addOnly)` in Photo/PhotoAlbum.swift; the usage string is "Save your Jelmiko photos to your Photos library." The app never reads the photo library. There is no camera use (no `AVCaptureSession`, no camera usage string); Photo mode takes pictures of the 3D game scene.
- **Share sheet is the user's choice.** The system share sheet only opens after the hold gate (`GatedShareButton`). What the user sends is up to them and is not collected by us.
- **Apple Intelligence text stays on device.** Park/ParkText.swift, Voice/VoiceIntent.swift and AI/TierA.swift use `FoundationModels` (Apple's on-device model, no network), guarded by `canImport` and availability checks, with filtered, pre-written fallbacks.
- **Widget and Live Activities are local.** The app and widget share data through the App Group `group.io.mgsllc.BobV1` (BobV1.entitlements). Live Activities are started with `pushType: nil` (LiveActivity/LiveActivities.swift), so there are no push tokens and nothing leaves the device.
- **Matching documents.** docs/PRIVACY.md and the in-app Privacy page (Settings/PrivacyPage.swift) both say "no data collected".

### PrivacyInfo.xcprivacy (both targets)

Both files declare: `NSPrivacyTracking = false`, no tracking domains, `NSPrivacyCollectedDataTypes` empty. Required-reason APIs declared:

| Target | API category | Reason code |
|---|---|---|
| BobV1/PrivacyInfo.xcprivacy | UserDefaults | CA92.1 (app's own data) |
| BobV1/PrivacyInfo.xcprivacy | System boot time | 35F9.1 (measure elapsed time within the app) |
| BobV1/PrivacyInfo.xcprivacy | File timestamp | C617.1 (files inside the app's own container) |
| JelbiesWidget/PrivacyInfo.xcprivacy | UserDefaults | 1C8F.1 (app group shared data) |

After archiving, use Xcode's "Generate Privacy Report" and "Validate App" to confirm there are no missing required-reason declarations. Required-reason entries are not part of the nutrition label; they are about API use.

### Things that could contradict "Data Not Collected" (checked, none is a collection by us)

1. **Speech language pack download.** The first voice use may make iOS download Apple's speech model (`AssetInventory.assetInstallationRequest` in Voice/SpeechInput.swift; the in-app notice says "Connect to Wi-Fi or mobile data, then tap the mic again"). The download is done by the system, not by the app, and no game data goes with it. docs/PRIVACY.md already says this. It does mean "never online" needs one footnote: a one-time system download for voice. If a reviewer asks, point to this.
2. **Photos add-only and share sheet.** Add-only access is not collection. Sharing is user-initiated.
3. **Apple Intelligence.** Apple's on-device model; not off-device.
4. **App Group and Live Activity.** Local sharing only.
5. **Mic permission strings are in the build.** Permission prompts are not collection, but a reviewer will see them, so the review notes explain them (section 7).
6. **Launch arguments (DEV ARGS).** `-NewGame`, `-ImportSave` and `-ClearGuest` are not behind the DEV ARGS gate (Start/StartFlow.swift comments say device Release builds can use them). They only run if someone launches the app from a computer with arguments, so they are not reachable by a player. They do not collect or send anything.
7. **Release notes wording.** The plist comment about "Live Activities (race / nap / Pep refill)" is out of date: the code defines only `race` and `nap` (Shared/JelbiesActivityAttributes.swift). Not a privacy issue, but do not mention a Pep refill activity in any listing text.

If any of these changes before submission (for example a crash reporter or analytics SDK is added), the label must be changed to match.

---

## 7. App Review notes

Paste into App Store Connect > App Review Information > Notes. Sign-in required: **No** (leave the demo account fields empty).

```
Jelmiko is a fully offline pet game for iPhone and iPad. It never connects to a server: there is no login, no account, no ads, no in-app purchases, no analytics and no tracking. Nothing needs to be set up before testing. On first launch it plays a short intro (tap to skip), then the title screen: tap New Game, name the first Jelmiko, and you are in the room. Every feature is reachable offline in a few taps.

QUICK TOUR
- Care: the bottom-right menu has Feed, Drink, Play, Decor and Bedtime. Tap a Jelmiko first to get Dress, Clean, Compete and Come here for that Jelmiko.
- Currency: JellyCoins are earned only by playing (there is nothing to buy with money). The first launch gives a small starter amount.
- Go out (the round button on the left rail) opens Town: Jelly Race, Jelly Show, Shop, Park, Café, Jelly Spa and Home. Jelly Volleyball is reached from Town and from the Compete chips. Jelly Spring (the Adoption Center) is where new Jelmiko are adopted with JellyCoins. New players start with one Jelmiko.
- Jelly Race, Jelly Show and Jelly Volleyball are played against computer-controlled rivals.
- Photo mode: gear icon (top-left) > Settings > Photo mode.
- Settings (gear icon) also has Sound, Accessibility, Voice, Privacy, Help & Support, Reset save and a theme colour with matching alternate app icons.

GROWN-UP GATE
Anything that leaves the game is behind a grown-up check: sharing a photo, opening the system Settings or Shortcuts, and the "Write to us" support email button. The check is a button that must be pressed and held for 2 seconds. With VoiceOver on, activating the button asks "Are you a grown-up?" once more. Hold the button to pass. Cancel closes it.

MICROPHONE AND SPEECH RECOGNITION
The microphone is used only while the player holds the mic button (bottom-left) to say a Jelmiko's name or a trick word, or while the optional "Ears" setting is on (off by default). Speech is turned into text on the device by Apple's on-device speech framework (DictationTranscriber / SpeechAnalyzer). Audio is not recorded to a file and is never sent anywhere. The first use may make iOS download Apple's small speech language pack once; the app itself makes no network request. If permission is denied, the app keeps working, and commands can be typed in the trick book instead. Photos permission is add-only, used only for the Save to Photos button in Photo mode. There is no camera access.

WIDGET AND LIVE ACTIVITY
The Jelmiko widget (small, medium, large, and Lock Screen accessory sizes) shows how the player's Jelmiko are doing. Tapping a Jelmiko opens the app on it (jelbies://jelly/<id>). It reads data saved on the device through an App Group; it makes no network requests. Live Activities (Jelly Race progress, and an optional bedtime nap card, on by default) are started locally by the app with no push notifications. They are started when a race begins or when the Jelmiko go to bed (the app leaves the foreground at night). If you do not see one, that is normal outside those moments.

OTHER NOTES
- The app is English only, Light appearance only.
- It is not in the Kids Category.
- Park visitor text may be written on the device by Apple Intelligence when the phone supports it (filtered for kids); other phones use pre-written text.
- Support: dione@mgsllc.io
```

Owner check before pasting: confirm each path above in the final build on a clean install (RELEASE-1.0.md lists three unverified items: Assistive Access launch, the widget deep link on cold start, and a Live Activity tap returning to the game with no second window). If one of them fails, remove its sentence from the notes.

---

## 8. Screenshot plan

Spec source (fetched 2026-11-09): https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications

### What Apple requires today

- Between 1 and 10 screenshots per device size, `.jpeg`, `.jpg` or `.png`, **no alpha channel or transparency**.
- **Required iPhone set:** "At least one screenshot for iPhone with Dynamic Island (medium display)". That group is 1179 x 2556 or 1206 x 2622 (portrait), 2556 x 1179 or 2622 x 1206 (landscape).
- **iPhone 6.9" (large display, Dynamic Island):** 1320 x 2868 (portrait) or 2868 x 1320 (landscape); also accepted 1290 x 2796 / 2796 x 1290 and 1260 x 2736 / 2736 x 1260. Apple's page says that if your UI is consistent across sizes, you only need the highest required resolution and App Store Connect scales the rest down. Because the page now names the medium Dynamic Island size as the required one, upload the 1320 x 2868 set as the master and check that App Store Connect accepts it for the required slot; if it does not, add 1206 x 2622 versions made from the same captures.
- **Required iPad set:** "At least one screenshot for iPad 13-inch display": 2064 x 2752 or 2048 x 2732 (portrait), 2752 x 2064 or 2732 x 2048 (landscape). 11-inch sizes (for example 1488 x 2266, 1668 x 2420) are optional and scaled from the 13-inch set.
- The same page mentions iPhone Duo sizes and says screenshots for it will be required for apps using the iOS 27.1 SDK or later from April 2027. This applies to a later SDK than the one in this project's plan; check it again when the project moves to that SDK.
- Strip alpha before upload. For example: `sips -s format png in.png --out out.png` does not remove alpha. Use an export that flattens onto a solid background (Preview > Export with "Alpha" unticked, or `magick in.png -background white -alpha remove -alpha off out.png`).

### Orientation

The game runs in portrait and both landscape orientations on iPhone, and in all four orientations on iPad. Use **portrait** for the iPhone set (the layout is designed for it) and show **landscape** in 2 of the iPad shots to prove the app is resizable.

### The story (same eight beats on both devices; use 6 to 8)

Capture the real app on the iPhone 17 Pro Max simulator (1320 x 2868) and the iPad Pro 13-inch (M5) simulator (2064 x 2752). Use a save with all three Jelmiko at home, a few trophies and a healthy JellyCoins balance, and no debug launch arguments (a Release or simulator build is fine for captures; the DEV ARGS rule only matters for the archive).

| # | Caption (short) | Screen to capture | In-game route |
|---|---|---|---|
| 1 | Meet your baby Jelmiko | The home room with 3 Jelmiko (Bob, Pip, Moss or Lavender), HUD visible | Continue from the title screen |
| 2 | Feed, clean and cuddle | A Jelmiko being fed (food tossed in) or the bubbly clean | Care menu > Feed or Clean |
| 3 | Dress them up | A Jelmiko in a hat/outfit, with Pip's spikes or Lavender's wings showing | Tap a Jelmiko > Dress |
| 4 | Explore Town | The Town "Where to?" map showing Jelly Show, Jelly Race, Shop, Park, Café, Jelly Spa, Home | Go out |
| 5 | Make friends in the Park | Park with a few Jelmiko and a visitor | Go out > Park |
| 6 | Race, show and volleyball | Jelly Race in progress (curved course, foot buttons) | Go out > Jelly Race |
| 7 | Win ribbons and trophies | Jelly Show stage or the trophy shelf; or Jelly Volleyball | Jelly Show / Trophies |
| 8 | Adopt new friends | Jelly Spring (the Adoption Center) picker | Go out > Jelly Spring (Adoption Center) |

Order for 6 shots: 1, 2, 4, 5, 6, 8. Then add 3 and 7 for 8.

Extras that can replace one of the above: Jelly Spa (Town > Jelly Spa), Photo mode (Settings > Photo mode), the widget on a Home Screen (a device or simulator Home Screen capture, not in-game). Avoid screens with unfinished states and do not show the Settings screen or Privacy text in an ad-style shot (they are plain).

### Per-device notes

- **iPhone (portrait, 1320 x 2868):** keep the HUD buttons clear of the bottom edge; the known issue "in portrait a front Jelmiko can sit under the bottom HUD buttons" (RELEASE-1.0.md) means you should re-pose or re-capture any shot where a Jelmiko is covered.
- **iPad (2064 x 2752 portrait plus two landscape 2752 x 2064):** the layout comes from the available size, so no special art is needed. Put the Town map and Jelly Race in landscape.
- **Landscape on the newer screens** (menu, adoption, photo) is listed as unchecked in RELEASE-1.0.md. Open each on the iPad landscape simulator before choosing it for a landscape slot.
- Captions are added as text overlays in your design tool, not in the game. Keep them to 6 words or fewer. The game captures themselves must show only real in-game screens.
- Preview video (optional): up to 3 per device size; the game's own intro (`jelbies_logo_intro_portrait.mp4`) is not suitable as a preview because it is a logo sting, not gameplay.

---

## 9. What is left for the owner

These are not in the code and were not invented here.

1. **Public Privacy Policy URL.** App Store Connect requires one. The text is ready in `docs/PRIVACY.md` (effective 2026-11-09). It must be hosted at a public address (a web page on the MGS LLC site, or GitHub Pages). The in-app Privacy page exists but is not a URL.
2. **Public Support URL.** Required too. The text is ready in `docs/SUPPORT.md`. Host it at a public address. The support email on it is dione@mgsllc.io.
3. **Marketing URL** is optional.
4. **Copyright line.** The app target sets no copyright string, and the widget's `INFOPLIST_KEY_NSHumanReadableCopyright` is empty (project.pbxproj line 663). App Store Connect has its own Copyright field: enter the line there, for example `2026 MGS LLC` (year and company wording are the owner's choice).
5. **Price.** Not set (RELEASE-1.0.md: "pricing (TBD by the user)"). The app has no in-app purchases, so the price is one fixed price or Free. Nothing in the code needs a price tier.
6. **Availability.** Choose countries and regions, plus the release option (manual, automatic, or phased). Remember Korea gets a regional rating because of the category.
7. **App icon.** Confirm the final icon is in the asset catalog (RELEASE-1.0.md earlier said "still missing"; the 2026-11-09 launch checks list `AppIcon` plus seven alternate icons as present). The App Store marketing icon is the 1024 x 1024 `AppIcon` image.
8. **Archiving with DEV ARGS off** (RELEASE-1.0.md, App Store checklist):
   - The Release configuration turns the `JELBIES_DEV_ARGS` compilation condition on by default so device diagnostics keep working (`JELBIES_DEV_ARGS_COND = JELBIES_DEV_ARGS` in project.pbxproj).
   - **The archive must clear it:** pass `JELBIES_DEV_ARGS_COND=` on every archive, for example `xcodebuild archive ... JELBIES_DEV_ARGS_COND=`, or set `JELBIES_DEV_ARGS_COND` to empty in the archive build settings.
   - Confirm the archive scheme has no launch arguments, and check the launch log does not contain the line "DEV ARGS ENABLED".
   - Bump `CURRENT_PROJECT_VERSION` (currently 1 everywhere) before each upload: `agvtool new-version -all <n>`; App Store Connect rejects a repeated build number for the same version.
   - After archiving, run Generate Privacy Report and Validate App.
9. **Export compliance.** `ITSAppUsesNonExemptEncryption = false` is set, so no question should appear.
10. **App Privacy answers** in App Store Connect: choose "Data Not Collected" (section 6) and set the Privacy Policy URL.
11. **ElevenLabs licence check.** RELEASE-1.0.md lists a commercial licence check for generated music and sound effects. Do it before submitting.
12. **TestFlight pass on a clean install** (permission prompts, the three scene-manifest items in RELEASE-1.0.md, a tap through every alternate icon).
13. **Primary language:** English (U.S. or the chosen English variant).
14. **App accessibility information** (the new Accessibility Nutrition Labels in App Store Connect) is optional but available; only tick what you have verified on a device (the code has VoiceOver labels, 44 pt targets and shape cues per RELEASE-1.0.md).
