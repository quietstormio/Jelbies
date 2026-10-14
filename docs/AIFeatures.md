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
