# Dance patterns (Jelly Show, Dance round)

`patterns.json` holds, per dance song (1 to 4), the prompts of three patterns: `old` (one per beat, the comparison), `calm` (rests) and `lively` (rests plus quick
doubles). A prompt is `{slot, time_s, foot}`: `slot` counts HALF beats on the song's measured grid (`time = first_beat_s + slot * period_s / 2`), `foot` is `L` (bass) or `R` (clap).
Puddle and Pond play `calm`, Lagoon and Ocean `lively`; `-DancePattern old|calm|lively` (dev builds) forces one.

Regenerate:
1. Decode the songs next to the scripts: `afconvert -f WAVE -d LEI16@44100 BobV1/Resources/.../show_dance_<n>.m4a s<n>.wav` (n = 1...4; the grids in `common.py` must equal `DanceSong.all`).
2. `python3 measure.py` writes `meas_<n>.npy` and `measure_<n>.txt` (onset strength per half-beat slot: low / mid / high band).
3. `python3 patterns.py` writes `patterns.json` (needs numpy, scipy).
4. `python3 gen_swift.py` writes `BobV1/Show/DancePatterns.swift` from the json. Never edit one without the other: `DancePatternTests` compares them (and the grid / title in `DanceSong.all`).

The notes in the json say which rests are real gaps in the music (song 2) and which are a design choice (songs 1, 3, 4).
