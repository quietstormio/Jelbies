> **Feature lock (2026-10-25):** Jelbies 1.0 is the first release; no new features, fixes and polish only. See [RELEASE-1.0.md](RELEASE-1.0.md).

# Emotions (v1 built 2026-10-16: needs and moods)

Notes for when moods are added. Moods also appear in AIFeatures.md (happy, shy, curious, sleepy, excited, grumpy).

## A bad mood changes how touch lands
- When a Blob is in a bad mood, he doesn't enjoy being touched. Petting, cheek squeezes and pick-ups get an annoyed reaction until you work out what's wrong and fix it:
  - he leans away;
  - he gives a grumpy squint with angry brows (the angry-brow expression is allowed here);
  - he makes a short "hmph" puff;
  - the haptics feel stiff and short instead of the soft purr texture.
- The cause is a need you can find and fix, for example:
  - he's hungry (Feed);
  - he's thirsty (Drink);
  - he's dirty (bath, planned).
  - Later: tired or bored.
- Show hints so it is a little puzzle, not a wall: a thought bubble with an emoji, or him glancing at the thing he needs.
- Once the need is fixed, his mood recovers, and the next touch gets the normal happy response: closed eyes, lean-in, purr.
- Never mean or scary. Grumpy stays cute: low rating, fun for adults.

## Hooks that already exist
- The touch system (focus mode) has zones, the purr and a per-zone favourite-spot counter (`TouchPlay.zoneSeconds`, `favouriteZone`). A mood value can gate or flip those reactions.
- The dining flow (Feed / Drink with the tray) is the first way to fix a need.

## Built in v1 (2026-10-16)
- **Needs:** hunger, thirst and attention, each 0–1, decaying in real time (about 3 h, 2 h and 4 h to empty). A need is "wanting" below 0.3.
  - A meal restores hunger and a drink restores thirst. Petting restores attention.
  - Needs persist across launches. Offline decay is clamped so at most one need is wanting when you open the app.
  - Code: `Needs.swift`.
- **Mood:** happy (all needs ≥ 0.6), okay, or grumpy (any need wanting). Mood picks the room-life specials (see Animations.md) and gates the touch reaction above.
- **Thought bubble:** a pastel cloud over his head with the wanted item (food, a water drop or a heart). It shows for about 6 s every 20 s. Tapping it opens Feed, Drink or Come here. When the need is fixed there's a sparkle and the bubble poofs.
- **Roster:** the round button at the top-right lists every Blob with their mood and three meters. Tapping a card plays the outline highlight on that Blob, then shows the action button.
- **Not yet:** dirty/bath, tired, bored, and the angry-brow expression for grumpy.
