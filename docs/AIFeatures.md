# AI & Apple-Only Features

**Goal:** capture the nostalgia of Nintendogs (a pet that knows its name, learns tricks, notices you) and add things only an iPhone can do. Keep the **age rating low (4+ / 9+)** while staying fun for adults.

**Design rule that keeps the rating low:** the Blob never "talks" in free text. AI is used to *understand* the player and to *choose* reactions (moods, animations, emoji thought bubbles, babble sounds), never to write open-ended sentences to the player. Everything runs **on device**: no accounts, no servers, no data leaving the phone.

---

## AI features

### 1. Voice: name and tricks (the Nintendogs mic, upgraded)
- **What it is:** the player says the Blob's name and it turns, perks up and waddles over. Tricks are taught by voice: get the Blob into a pose (e.g. it waves), say "wave", and after a few repeats it learns the word. Later, saying "wave" makes it wave.
- **Apple tech:** `SpeechAnalyzer` / `SpeechTranscriber` (iOS 26), Apple's on-device speech-to-text. No internet needed.
- **Why it's better than Nintendogs:** the DS often misheard commands. Modern on-device recognition is far more accurate, and words can be matched loosely (e.g. "Mochi" vs "Mochee").
- **Works on:** every supported iPhone. No AI model required.
- **Rating impact:** none. It only needs microphone permission.

### Voice mode: how the player talks (decided)
The mic is **never always-on**. The player opens it on purpose:
- **Gesture:** **double-tap, then hold** on the screen enters voice mode. Talk while holding, release to send. It works like a walkie-talkie.
  - Must start on **empty space, not on the Blob**. Touches on the Blob are already single tap (status), rub (pet), press-drag (grab) and flick (throw), so a double-tap-hold that starts on him would clash with petting and grabbing.
- **Visible mic button** in the HUD (press and hold to talk). Does the same thing, so new players can find voice mode, and it helps accessibility. The first time, a short tip teaches the double-tap-hold shortcut.
- **Feedback while listening:**
  - The Blob stops what it's doing, turns to face you, its eyes widen and brows lift, and it leans in.
  - A soft sound-wave bubble pulses with your voice.
  - A light haptic tick when voice mode opens and closes.
- **On release:** the speech is turned into text on the phone. It is checked first for the Blob's name and learned trick words (instant, works on every phone), then optionally sent to the on-device language model for a reaction (#3).
- **Why not always-on:**
  - Battery drain.
  - The orange mic indicator would stay on constantly.
  - It would pick up TV and conversations by mistake.
  - It's worse for kids' privacy.

  A hands-free "listening mode" could be an opt-in setting later.

### Voice v1: what is built (2026-10-16)
Code in `BobV1/Voice/`. Real recognition and haptics while recording are **not yet verified on a phone**.
- **Opening it:** double-tap then hold on empty space, or press and hold the mic button (bottom-left). A hold under 0.25 s cancels. A one-time "Hold to talk" tip sits by the mic. Ticks play on open and close. A flat edge glow in Bob's blue pulses with your voice.
- **While listening:** Bob stops, turns to face you, tips up a little more and blinks. If he is already doing a teachable move, he keeps doing it so the word can bind. The face is unchanged (no wider eyes, no brow lift).
- **Recognition:** `DictationTranscriber` (preset `.phrase`), on device, with his name and the trained words as contextual strings. Only microphone permission is asked, and only on the first hold. If recognition is unavailable, the mic shows a slash and opens the trick book instead.
- **Names:** known from the start (see "Names, nicknames, social commands and the model" below). His name makes him hop and walk about 1 unit toward you. He does **not** enter focus mode.
- **Tricks:** sit, jumping jacks, run, flip, look, come. All reuse existing moves except the flip (new, see Animations.md). The yawn is an idle behaviour only, not a trick; an old stored "yawn" lesson is dropped on load.
  - The flip is not an idle move, so it can only be taught by tapping its trick book row (he flips), then saying the word during the flip. There is no timing meter (the shot-meter bar game was removed 2026-10-17 on user request): the flip just plays, crouch, backflip, land. While the word is not yet learned, about 1 time in 3 he faceplants instead (the funny faceplant and get-up), never on the first try and never twice in a row; a faceplant still counts as doing the move for a teaching rep. Once learned, a failed reliability roll is sometimes a faceplant instead of the generic miss.
  - Teach a trick by saying any word while he is doing the move. It is learned after 3 reps, one per listen (saying it again and again in one listen counts once). The count is `VoiceTuning.repsToLearn`; the dots, name lesson and tests all read it.
  - Reliability starts at 35% and grows with use, up to 95% (come starts at 92%, see below).
  - A miss is either a wrong trick or ignoring you, 50/50.
  - Grumpy: he refuses every trick except come, with a slump and his need bubble (come is always obeyed, see below).
  - Commands are ignored while the tray is out.
  - In focus, "run" becomes a hop so he doesn't leave the spot; "come" is also a hop there (he is already close).
- **Trick book** (book button next to the mic): it has a name row and one row per trick, each showing the word, 3 progress dots and reliability. Tapping a row makes him do the trick now, so it doubles as the no-voice command palette. Each row has a Forget button.
- **Saved:** UserDefaults `BlobWords.v1`. `-VoiceReset 1` clears it.
- **Capture and test aids:**
  - `-VoiceFakeMic 1` (with `-VoiceFakeText`) replaces the mic.
  - `-VoiceSay "<words>"` (with optional `-VoiceTeach <trick>` and `-VoiceDelay`) plays a voice turn.
  - `-VoiceLearned 1` pre-learns everything.
  - `-VoiceBook 1` opens the book.
- **Later:** new moves come from trick pages bought with Drops (see the Feature Bible).

#### Come here is innate (2026-10-17, replaces the come-here tutorial)
- He knows "come here" from the first launch (fresh install, after `-VoiceReset`, and old saves where come was not learned are completed on load). Reliability 92% (a miss is about 1 in 12; success still nudges it up to 95%). Also matched: "come", "come on", "here boy", "come to me", and "come here <name>". A word the player taught for come themselves is kept. "Forget" on come puts "come here" back.
- **Voice or trick-book "come" = the game's Come here:** if he obeys (reliability roll, not grumpy, no tray out) he walks to the front and focus / cuddle mode starts with the usual zoom (`GameCare.comeHere`). Already in focus, it is a happy hop. Grumpy does NOT refuse come (2026-10-17 fix): he is grumpy because he wants love, so a grumpy "come here" skips the mood check and the reliability roll, he walks over sulky (the grumpy walk is already slow and small) and the close-up petting cheers him up.
- The tutorial card is retired (not mounted; `VoiceTutorial.isDone` starts true; the code and debug flags remain, its tests are gone).

#### Names, nicknames, social commands and the model (2026-10-17, lab_voice)
Code: `Voice/VoiceNames.swift` (registry), `Voice/VoiceIntent.swift` (intents, phrase tables, model), `VoiceTraining.decideFull`, `VoiceCoordinator.process`.
- **Names are known from the start.** `JellyRoster` is keyed by Jelbie id (0 Bob, 1 Pip, 2 Moss). The old 3-rep name lesson is gone; old saves with a partial lesson are completed on load; the book's name row shows "He knows it".
  - Matching per name: the base, generated pet forms (Bobby, Bobbie, Bobo, Bobster, Bobbob / Pippy, Pipster, Pipsqueak / Mossy, Mossie, Mossmoss), curated recogniser near-misses (Bab, Bop / Pep, Pit / Moth, Mos), and a guarded phonetic key (first letter + vowel family + folded consonants). No generic edit distance on 3-4 letter names (it hits bad, bit, mass, most); a stoplist covers real words that share a key (pipe, mouse, maze ...). Negative tests list the words that must not match.
  - **Nicknames** (up to 5 per Jelbie, `JellyNicknames.v1`, cleared by `-VoiceReset 1`): typed in the trick book's name row ("Add nickname"), or taught by voice (mic button in the row, then say it in 3 listens). Matching: exact, one edit for 5+ letter nicknames, or the same phonetic key and first letter; two-word nicknames work.
- **Pipeline:** speech text -> (a) deterministic, instant, primary: names + target, learned trick words, come aliases, built-in social phrases, then teaching a new word on the running move -> (b) only if nothing matched: the on-device model maps free phrasing to an intent. Teaching always beats the model. The model can only trigger a trick that is already learned (under any word); otherwise he gives a confused look. Built-in social commands (come, stop, stopFighting, praise, scold, play, everyone) need no training.
- **Model:** Foundation Models, guided generation (`VoiceIntentOut`: target selected / named(String) / everyone, action enum, confidence). It never produces text for the player. Behind `VoiceIntentModel` (fake in tests); prewarmed when the mic opens; one fresh single-turn session per request; hard cutoff `VoiceTuning.modelBudget` (1.5 s, target ~0.8 s), confidence under 0.5 = none; unavailable / error / timeout = the deterministic result stands. Parse path and latency go to the log: `VOICELOG parse path=det|model|timeout|error|unavailable ms=N` (`-VoiceLog 1`). `-VoiceNoModel 1` turns the model off; unit tests never use the real one.
- **Targets:** "Pip, ..." names a Jelbie; "everyone / everybody / you guys / all of you" is all; otherwise the selected one (Bob). Naming selects: the roster outline highlight a tap gives (`care.rosterPick(id, quietHop: true)`, no extra hop). Come skips the highlight (the close-up is the selection). A name for a Jelbie that is not in the room = confused look. Hooks for phase B on `VoiceCoordinator`: `jellyIDs`, `onSelect(id)`, `onEveryone(ids)`, `onComeHere(ids)`, `onStopFighting(ids)`, `onRemote(reaction, ids)`.
- **Social reactions (existing moves only):** stop = ends the current move (a flip lands first); stopFighting = stop + `onStopFighting` + a sheepish look; praise = heart, happy hop, +0.08 attention; scold = the slump droop; play = heart + hop. Grumpy still refuses play and tricks.
- Not verified on device: the live model latency (the simulator has no model assets), real-mic recognition of near-miss names.

#### Feedback: he heard you and is learning (2026-10-17)
`Voice/VoiceFeedback.swift` (overlay `VoiceFeedbackView`, events from `VoiceCoordinator.emitFeedback`; no text from Bob himself).
- **Heard pill** above the mic, about 2 s: the player's own words in quotes (`voice-heard`); nothing recognised shows an ellipsis.
- **Bob's bubble** beside his head (icons only, anchored with `ThoughtBubbleView.project`, `voice-bubble`, value = event): rep = trick icon + 3 dots with the new one popping, plus a small ear-perk tilt; learned = sparkles, icon + check, toast "Learned "word" -> Trick" and a happy hop; obeyed = a check as he starts (come shows it before the focus zoom); missed roll = "?" + trick + reliability %; unknown word / nothing heard = "?" / "..." with the head tilt; grumpy = the existing refusal. Name reps show a heart + dots.
- **Trick-book row** (he demonstrates, no bubble): prompt pill "Now hold the mic and say a word for <Trick>" (`voice-prompt`) until the next word; the book's dots are live.
- Debug: `-VoiceReps sit:3` pre-fills reps. Tests: `VoiceIntegrationTests` feedback cases, UI `testVoiceHeardPillAndRepBubbleAppear`.

#### Glow timing (2026-10-17)
- The glow and level bars are drawn from `mode.isListening`, which `begin()` sets synchronously on the second tap-down (in `pointerDown`) or the mic press. No hold threshold, no waiting for the audio session or analyzer; the mic starts in parallel (40 ms later, all of session activation, engine creation and start run off the main thread). A hold under 0.25 s is a silent cancel.
- Release hides it in the same call (`VoiceMode.endHold`). Before, the state only left `.listening` after the analyzer had finalised the transcript, so the glow lingered for that whole time (the likely "gone on release" lag). The glow is four edge gradients with no blur or animation (a full-screen blur is an offscreen pass). A mic press wakes the 30 fps idle-rest governor (`gfxWake`).
- `-VoiceLog 1` logs `begin() ran synchronously in N ms` and `touch-down -> glow visible N ms, -> audio running N ms`.

### 2. Wave at him, he waves back (camera awareness)
- **What it is:** with the front camera on, the Blob notices you. Hold up a hand and it waves back (using the wave animation from the reference video). Lean in close and it gets excited, and it can follow your face with its eyes. Nintendogs + Cats on 3DS did a simple version of this, with face recognition and head-tilt copying.
- **Apple tech:** Vision framework (hand-pose and face detection). Optional: ARKit face tracking on Face ID phones for head-tilt mirroring.
- **Privacy:** camera frames are processed live on the phone and never stored or sent.
- **Works on:** every supported iPhone.
- **Rating impact:** none. It only needs camera permission.

### 3. "He understands you": on-device language model reactions
- **What it is:** say anything to your Blob ("do you want a snack?", "you're so cute", "time for a bath") and it reacts as if it understood, with excitement, shyness, a hop, hiding, or a little emoji thought bubble (🍓❓). It reacts like a pet; it doesn't reply in words.
- **Apple tech:** Foundation Models framework (iOS 26), Apple's built-in on-device language model of about 3 billion parameters. *Guided generation* (`@Generable`) forces the model to fill in a fixed structure instead of free text:
  ```swift
  @Generable struct BlobReaction {
      var mood: Mood            // happy, shy, curious, sleepy, excited, grumpy
      var animation: Action     // wave, hop, spin, hide, nod, tilt, lookAway
      var thought: String       // 1–3 emoji only, validated
  }
  ```
  The Blob's personality (shy, playful…) and current needs (hungry, sleepy) go into the prompt, so a shy Blob reacts differently from a cheeky one.
- **Limits:**
  - Only on Apple Intelligence phones (iPhone 15 Pro and newer) with Apple Intelligence turned on.
  - Older phones fall back to keyword-based canned reactions, so the game is fully playable without it.
  - The context window is small (about 4K tokens), so each request is kept tiny.
- **Rating impact:** low, because the output is restricted to moods, animations and emoji. In the App Store age-rating questionnaire we disclose the AI feature and explain that it can't produce text content. Apple's built-in safety guardrails also apply.

### 4. Daily diary
- **What it is:** each day, every Blob gets one cute diary line about what really happened: *"Mochi ate two berries, napped on the rug and waved at you three times."* It's a gentle reason to check in daily (the research showed daily surprises drive Nintendogs-style retention). Adults will enjoy reading these too.
- **Apple tech:** Foundation Models, fed *only* facts from the game's own event log, via tool calling or structured input.
- **Safety:**
  - The text comes only from game events, never from what the player says.
  - Output is length-limited and filtered.
  - A template-based fallback covers non-Apple-Intelligence phones.
- **Rating impact:** low. It's generated text, but from fixed game facts with no player input. Disclose it in the questionnaire.

### 5. Sound awareness (later)
- **What it is:** the Blob reacts to claps, whistles or laughter. For example, it jumps when you clap, or the clap becomes a "come here" signal.
- **Apple tech:** the SoundAnalysis framework (built-in sound classifier). Later, a custom model could recognise player-specific sounds, run through **Core AI**, the framework announced at WWDC 2026 to replace Core ML for running your own models on the phone. Core AI appears to require iOS 27; the project currently targets iOS 26.2.
- **Rating impact:** none.

---

## Other Apple-only features (non-AI) that fit the game

| Feature | What it does in the game | Apple tech | Rating impact |
|---|---|---|---|
| **Squish haptics** | You *feel* the jelly when you press, rub or throw the Blob | Core Haptics | None |
| **Blob in your real room** | Place your Blob on your actual table or floor and watch it bounce around | ARKit / RealityKit | None |
| **Walks with real steps** | Nintendogs walks, but driven by real steps; walking 2,000 steps finds a present | HealthKit / Core Motion pedometer | None (Health permission) |
| **Lock Screen & Dynamic Island** | See "Mochi is napping 💤" or "Mochi is hungry" at a glance | Live Activities, WidgetKit | None |
| **Siri & Shortcuts** | "Hey Siri, feed Mochi" | App Intents | None |
| **Apple Watch** | Pet and feed from the wrist, get gentle nudges | watchOS companion | None |
| **Playdates** | Two friends' Blobs meet on a FaceTime call | SharePlay | Possibly higher if free chat is added; keep it emoji-only |
| **Achievements** | Badges for tricks learned, days cared for | Game Center | None |

---

## Keeping the rating low (checklist)
- No free-text output from AI to the player. Use moods, animations and emoji only.
- Diary text is generated from game events only, never from player input.
- No open chat between players. Playdates use emoji and animations only.
- Everything runs on device: no accounts, no ads or analytics SDKs that track kids.
- Disclose the AI features honestly in App Store Connect's age-rating questionnaire. It has required questions about AI assistants and chatbots.
- Apple sets the final rating from the questionnaire. This design aims for **4+ or 9+**, but it can't be guaranteed in advance.

## Suggested order
1. Body, then animations *(in progress)*.
2. Voice name and tricks (#1) and wave-back (#2): cheap, work on every phone, core nostalgia.
3. Squish haptics. Small effort, big feel.
4. Foundation Models reactions (#3) with fallback, then the daily diary (#4).
5. Real-steps walks, Live Activities, Siri, AR mode.
