# Jelbie sound style

Written 2026-11-02 after the user said the rain sigh "is not good" and asked that sounds stay consistent for the species. The user likes the existing voice and cannot describe it, so the shipped files are the reference.

## What a Jelbie sounds like (plain English)
A Jelbie is a tiny, soft, round-sounding baby creature. Its voice is a smooth hummed note, a bit like a small flute or a soft "oo/ee" coo, with a gentle pitch slide: happy chirps glide up, sad ones droop down, babbles are a short run of two to four of these notes like a question. There is no breath, hiss, rasp or human-throat sound, no sharp squeal, and nothing loud. Snores are the same voice, an "hnn" in and a "puuu~" out, very quiet. Each character has its own pitch and softness (Moss deep and mellow, Pip bright and quick, Lavender airy), but they are clearly the same kind of creature.

The voice files were SYNTHESIZED IN CODE (numpy formant synth, `~/BobV1_sounds/2026-10-18/synth.py`, per-character timbre in `~/BobV1_sounds/2026-10-22/voices/voice_synth.py`), not ElevenLabs, so there is no original prompt. The prompt template below is derived from the measurements.

## Measured band (BobV1/Audio/Resources; f0 = voiced pitch, centroid = spectral centre of mass)
| Voice | f0 median (10-90%) | length | centroid | energy 2-5 kHz |
|---|---|---|---|---|
| jelly1 Bob | chirp 405-576 Hz (335-672), babble 437 (402-618) | chirp 0.3-0.44 s, babble 1.44 s | 600-1255 Hz | 0-29% (babble 8%) |
| jelly2 Pip | chirp 558-825 (475-1100), babble 612 (573-858) | 0.25-0.35 s, babble 1.16 s | 1040-2330 (babble 1005) | babble 8% |
| jelly3 Moss | chirp 288-405 (225-470), babble 306 (285-440) | 0.37-0.51 s, babble 1.74 s | 480-585 (babble 626) | 0-2% |
| jelly4 Lavender | chirp 510-723 (393-824), babble 538 (490-747) | 0.32-0.46 s, babble 1.51 s | 660-1225 (babble 950) | babble 15% |
| snores 1-4 | 320-650 Hz | 1.35 s | 430-890 | 0-5% |

A new Jelbie vocal fits when ALL hold:
- voiced f0 median 290-830 Hz (most sit 300-650), clean pitch track (pitch found in most frames);
- spectral centroid 450-1300 Hz;
- energy 2-5 kHz at most 15% of the total (target under 5%);
- length 0.3-0.5 s for a one-note sound, 1.0-1.8 s for a babble/group sound.
Measure with `python3 -I` + ffmpeg (see the script idea: autocorrelation f0, FFT centroid, ebur128 loudness). A human voice or breath fails this test (the old sigh: centroid 1600 Hz, 18% in 2-5 kHz, no pitch).

## Prompt template for ANY Jelbie vocal (ElevenLabs sound effects)
```
tiny cute baby creature voice, <the sound: e.g. one soft rounded "hic" coo / a soft relieved "phew" coo that sinks slightly in pitch>, soft rounded flute-like hum, warm low-mid pitch around <350-600> Hz, like a small plush toy cooing, no human voice, no breath, no air noise, no hiss, no squeal, no sharp click, clean and quiet
```
Rules learned: say "creature" and "coo/hum", never "sigh/sneeze/breath/giggle/laugh" without the creature + hum wording (the model then makes a human). Add "muffled, dark, mellow" if a candidate is too bright. Generate 2-3 candidates (0.5 s minimum duration, 0.5-1.4 s typical), measure, pick the one inside the band. "Group" sounds: do not ask for several voices (the model makes a thin high choir); ask for one soft coo.

## Non-vocal SFX (chimes, swishes, pats, boops, bubbles, thunder, rain, squeaks)
- Soft, plush, rounded, low-mid. No clown honks, no sharp squeaks, no horn tones, no clicks.
- Energy 2-5 kHz at most 15% of the total, centroid under 2.5 kHz for anything touch-related (touch wobble/squish/polish ~500-650 Hz). Chimes and bubbles may be brighter but quiet.
- For a squeak, describe a cloth or soft rubber "fwip", low-mid, no squeal.
- Only change what the user flags: the cuddle wobble/squish originals were liked and are restored; only the bath polish swipe was redone.

## Loudness targets (m4a, AAC 96 kbps mono 44.1 kHz, fades of 5 ms in / 40 ms out)
- Voice chirps/babbles about -11 to -16 LUFS integrated, peak -3 dBFS (the game plays them with a gain); short emote vocals -15 to -19 LUFS; snores -32 LUFS (peak -23 dBFS); storm sigh -24 LUFS; touch sounds -20 to -28 LUFS; peaks never above -3 dBFS.
- Clips under about 0.4 s read -70 LUFS on the meter; match those by peak (-3.5 to -6 dBFS).

## Which voice each character uses
`JellyVoiceSet.file(character:)` (AudioCatalog.swift) picks `chirp_jelly{n}_*`, `babble_jelly{n}`, `snore_jelly{n}_*` with n = min(character, 3) + 1, via the character in the slot (`JellyRoster.character(slot)`):
- Bob (0) -> jelly1; Pip (1) -> jelly2; Moss (2) -> jelly3; Lavender (3) -> jelly4.
- Teddy (4), Pearl (5) and Panda (6) all clamp to jelly4 (`min(character, 3)`), so they share Lavender's voice (Panda confirmed 2026-11-03: shared for now, no new clips). Suggestion: give Teddy (round, light brown, ears) and Pearl (white, winged) their own voice sets (jelly5/jelly6: extend `JellyVoiceSet.count`, generate chirp/babble/snore with `voice_synth.py`, e.g. Teddy lower and rounder than Bob, about 380 Hz; Pearl soft and airy near 580 Hz). Not done; ask the user.

## Where this applies
New vocal in the emotes: `emote_hic_1`, `emote_achoo_1`, `emote_woozy_1`, and `storm_relief_sigh` follow this guide (redone 2026-11-02). `cheer_small_*` (older crowd cheer, centroid 1.2-1.8 kHz) was not part of the new batch.
